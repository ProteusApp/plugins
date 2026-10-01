-- server: runs Marksman's language server for Markdown files. It starts for the first Markdown
-- file that opens, on the open folder, or else on the file's own folder.

local client_module = require ('lsp.client') --[[@as Lsp.ClientModule]]
local disk = require ('disk_paths') --[[@as DiskPaths]]

---@class LangMarkdown.Server
---@field start fun(doc: Proteus.DocInfo?)
---@field stop fun()

---@class LangMarkdown.ServerModule
local M = {}

---@param ctx LangMarkdown.Context
---@param tool Proteus.ToolHandle
---@return LangMarkdown.Server
function M.install (ctx, tool)
  local app, settings, editor = ctx.app, ctx.settings, ctx.editor
  local starting = false
  local server ---@type LangMarkdown.Server

  local client = client_module.new (app, {
    name = 'Marksman',
    language = 'markdown',
    source = 'markdown',
    tool = tool,
  })

  ---@return Proteus.DocInfo?
  local function first_markdown ()
    for _, doc in ipairs (editor.docs ()) do
      if doc.language == 'markdown' then
        return doc
      end
    end
    return nil
  end

  ---The folder the server works on: the open folder, or else the file's own folder.
  ---@param doc Proteus.DocInfo
  ---@return string
  local function root_for (doc)
    local project = app.try_use ('project')
    return project and project.root () or disk.parent (client.to_disk (doc))
  end

  server = {
    start = function (doc)
      if client.running () or starting then
        return
      end
      if settings.get ('markdown.enabled') ~= true then
        tool.set_state ('stopped', 'switched off in Settings (markdown.enabled)')
        return
      end
      doc = doc or first_markdown ()
      if not doc then
        tool.set_state ('stopped', 'starts when a Markdown file opens')
        return
      end
      local root = root_for (doc)
      starting = true
      tool.locate (function (program)
        starting = false
        if not program then
          tool.set_state ('missing', 'marksman is not on the PATH')
          return
        end
        tool.set_path (program)
        client.start (program, { 'server' }, root)
      end)
    end,
    stop = function ()
      client.stop ()
    end,
  }

  app.on ('editor:opened', function (doc)
    ---@cast doc Proteus.DocInfo
    if doc.language == 'markdown' and not client.running () then
      server.start (doc)
    end
  end)

  local first = true
  settings.watch ('markdown.enabled', function ()
    if first then
      first = false
      return
    end
    server.stop ()
    server.start (nil)
  end)

  return server
end

return M
