-- server: runs yaml-language-server for YAML files. It starts for the first YAML file that
-- opens, and hears again whenever a schema association or one of its settings changes.

local client_module = require ('lsp.client') --[[@as Lsp.ClientModule]]
local config = require ('lib.config') --[[@as LangYaml.ConfigModule]]
local disk = require ('disk_paths') --[[@as DiskPaths]]

---@class LangYaml.Server
---@field start fun(doc: Proteus.DocInfo?)
---@field stop fun()

---@class LangYaml.ServerModule
local M = {}

---@param ctx LangYaml.Context
---@param tool Proteus.ToolHandle
---@return LangYaml.Server
function M.install (ctx, tool)
  local app, settings, editor = ctx.app, ctx.settings, ctx.editor
  local starting = false
  local server ---@type LangYaml.Server

  local client = client_module.new (app, {
    name = 'YAML',
    language = 'yaml',
    source = 'yaml',
    tool = tool,
    config = function (section)
      return config.section (section, ctx.schemas.options ())
    end,
  })

  -- The server asks for every section again when it hears this.
  ctx.schemas.on_change (function ()
    if client.ready () then
      client.notify ('workspace/didChangeConfiguration', {
        settings = { yaml = config.yaml (ctx.schemas.options ()) },
      })
    end
  end)

  ---@return Proteus.DocInfo?
  local function first_yaml_doc ()
    for _, doc in ipairs (editor.docs ()) do
      if doc.language == 'yaml' then
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
      if settings.get ('yaml.enabled') ~= true then
        tool.set_state ('stopped', 'switched off in Settings (yaml.enabled)')
        return
      end
      doc = doc or first_yaml_doc ()
      local root = doc and root_for (doc)
      if not root then
        tool.set_state ('stopped', 'starts when a YAML file opens')
        return
      end
      starting = true
      tool.locate (function (program)
        starting = false
        if not program then
          tool.set_state ('missing', 'yaml-language-server is not on the PATH')
          return
        end
        tool.set_path (program)
        client.start (program, { '--stdio' }, root)
      end)
    end,
    stop = function ()
      client.stop ()
    end,
  }

  app.on ('editor:opened', function (doc)
    ---@cast doc Proteus.DocInfo
    if doc.language == 'yaml' and not client.running () then
      server.start (doc)
    end
  end)

  local first = true
  settings.watch ('yaml.enabled', function ()
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
