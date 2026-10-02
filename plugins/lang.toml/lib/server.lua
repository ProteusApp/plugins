-- server: runs Taplo's language server for TOML files. It starts for the first TOML file that
-- opens, and hears again whenever a plugin adds a schema.

local client_module = require ('lsp.client') --[[@as Lsp.ClientModule]]
local disk = require ('disk_paths') --[[@as DiskPaths]]

-- Taplo asks for its settings under this name, which comes from its VS Code extension.
local SECTION = 'evenBetterToml'

---@class LangToml.Server
---@field start fun(doc: Proteus.DocInfo?)
---@field stop fun()

---@class LangToml.ServerModule
local M = {}

---@param ctx LangToml.Context
---@param tool Proteus.ToolHandle
---@return LangToml.Server
function M.install (ctx, tool)
  local app, settings, editor = ctx.app, ctx.settings, ctx.editor
  local starting = false
  local server ---@type LangToml.Server

  local client = client_module.new (app, {
    name = 'Taplo',
    language = 'toml',
    source = 'toml',
    tool = tool,
    config = function (section)
      return section == SECTION and ctx.schemas.config () or nil
    end,
  })

  ctx.schemas.on_change (function ()
    if client.ready () then
      client.notify ('workspace/didChangeConfiguration', {
        settings = { [SECTION] = ctx.schemas.config () },
      })
    end
  end)

  ---@return Proteus.DocInfo?
  local function first_toml_doc ()
    for _, doc in ipairs (editor.docs ()) do
      if doc.language == 'toml' then
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
      if settings.get ('toml.enabled') ~= true then
        tool.set_state ('stopped', 'switched off in Settings (toml.enabled)')
        return
      end
      doc = doc or first_toml_doc ()
      local root = doc and root_for (doc)
      if not root then
        tool.set_state ('stopped', 'starts when a TOML file opens')
        return
      end
      starting = true
      ctx.schemas.need ()
      tool.locate (function (program)
        starting = false
        if not program then
          tool.set_state ('missing', 'taplo is not on the PATH')
          return
        end
        tool.set_path (program)
        client.start (
          program,
          { 'lsp', 'stdio' },
          root,
          { configurationSection = SECTION }
        )
      end)
    end,
    stop = function ()
      client.stop ()
    end,
  }

  app.on ('editor:opened', function (doc)
    ---@cast doc Proteus.DocInfo
    if doc.language == 'toml' and not client.running () then
      server.start (doc)
    end
  end)

  local first = true
  settings.watch ('toml.enabled', function ()
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
