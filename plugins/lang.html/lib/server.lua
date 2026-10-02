-- server: runs VS Code's HTML language server. It starts for the first `.html` or `.htm`
-- file that opens, and hears again when a setting it reads changes.
--
-- The editor names `.vue` and `.svelte` files `html` too, and lsp.client serves every
-- document of its language. It has no way to leave some files out. So while the server
-- runs, Vue and Svelte files also get its help, as if they were plain HTML. They never
-- start it on their own.

local client_module = require ('lsp.client') --[[@as Lsp.ClientModule]]
local disk = require ('disk_paths') --[[@as DiskPaths]]
local markup = require ('lib.markup') --[[@as LangHtml.Markup]]

-- What the server reads when it starts. Prettier, which ships with Proteus, formats HTML
-- already, so the server's own formatter stays off.
local INIT_OPTIONS = {
  provideFormatter = false,
  embeddedLanguages = { css = true, javascript = true },
}

---@class LangHtml.Server
---@field start fun(doc: Proteus.DocInfo?)
---@field stop fun()

---@class LangHtml.ServerModule
local M = {}

---The settings the server asks for, by section. It asks for `html`, `css`, `javascript`
---and `js/ts`. The JavaScript part reads only its formatting settings, and the formatter is
---off, so those two get nothing. An empty table could go out as `[]`, so none is sent.
---@param section string
---@param validate boolean
---@return table?
function M.config (section, validate)
  if section == 'html' then
    return {
      suggest = { html5 = true },
      hover = { documentation = true, references = true },
      validate = { scripts = validate, styles = validate },
      -- True would hide the closing tag the server offers after `>`.
      autoClosingTags = false,
    }
  elseif section == 'css' then
    return { validate = validate }
  end
  return nil
end

---@param ctx LangHtml.Context
---@param tool Proteus.ToolHandle
---@return LangHtml.Server
function M.install (ctx, tool)
  local app, settings, editor = ctx.app, ctx.settings, ctx.editor
  local starting = false
  local server ---@type LangHtml.Server

  ---@param section string
  ---@return table?
  local function config (section)
    return M.config (section, settings.get ('html.validate') ~= false)
  end

  local client = client_module.new (app, {
    name = 'HTML',
    language = 'html',
    source = 'html',
    tool = tool,
    config = config,
  })

  ---@return Proteus.DocInfo?
  local function first_page ()
    for _, doc in ipairs (editor.docs ()) do
      if doc.language == 'html' and markup.is_page (doc.path) then
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
      if settings.get ('html.enabled') ~= true then
        tool.set_state ('stopped', 'switched off in Settings (html.enabled)')
        return
      end
      doc = doc or first_page ()
      if not doc then
        tool.set_state ('stopped', 'starts when an HTML file opens')
        return
      end
      local root = root_for (doc)
      starting = true
      tool.locate (function (program)
        starting = false
        if not program then
          tool.set_state (
            'missing',
            'vscode-html-language-server is not on the PATH'
          )
          return
        end
        tool.set_path (program)
        client.start (program, { '--stdio' }, root, INIT_OPTIONS)
      end)
    end,
    stop = function ()
      client.stop ()
    end,
  }

  app.on ('editor:opened', function (doc)
    ---@cast doc Proteus.DocInfo
    if
      doc.language == 'html'
      and markup.is_page (doc.path)
      and not client.running ()
    then
      server.start (doc)
    end
  end)

  local first = true
  settings.watch ('html.enabled', function ()
    if first then
      first = false
      return
    end
    server.stop ()
    server.start (nil)
  end)

  -- The server keeps the settings it asked for, until it hears they changed.
  local first_validate = true
  settings.watch ('html.validate', function ()
    if first_validate then
      first_validate = false
      return
    end
    if client.ready () then
      client.notify ('workspace/didChangeConfiguration', {
        settings = { html = config ('html'), css = config ('css') },
      })
    end
  end)

  return server
end

return M
