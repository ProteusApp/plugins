-- lang.json: JSON in the code editor, with vscode-json-language-server.
--
-- The server gives completion, hover help and problems from JSON schemas: the `schema`
-- associations any plugin adds through core.files, and SchemaStore's catalog. It also makes
-- the `completion` associations show, such as npm package names in package.json, since the
-- editor asks those only while a server runs for the file. Prettier formats JSON, so the
-- server does not.
--
-- The parts live in lib/:
--   schemas     schema associations and the catalog, turned into the server's settings
--   server      starts and stops the language server
--   provider    completion and hover help from the server
--   completion  turns the server's completion items into plain text
--   language    which files may hold comments
--   program     finds node and the server's script
--   launch      where the server's script may be

local schemas_module = require ('lib.schemas') --[[@as LangJson.SchemasModule]]
local server_module = require ('lib.server') --[[@as LangJson.ServerModule]]

---What the parts of the plugin share.
---@class LangJson.Context
---@field app Proteus.App
---@field settings Proteus.Settings
---@field editor Proteus.Editor
---@field schemas LangJson.Schemas
---@field notify fun(text: string) A warning, when ui.notify runs.

---@type Proteus.Plugin
return {
  name = 'JSON',
  description = 'JSON with vscode-json-language-server: completion, hover help and problems from JSON schemas. Other plugins add schemas as file associations.',
  version = '1.0.0',
  requires = { proteus = '>=0.3.0', features = { 'permissions' } },
  -- The language server is a program it runs, on files anywhere on disk. SchemaStore's
  -- catalog comes from schemastore.org.
  permissions = { 'files', 'process', 'net' },
  depends = {
    'proteus.core.settings',
    'proteus.core.commands',
    'proteus.core.files',
    'proteus.editor.core',
    'proteus.tools.registry',
    'proteus.tools.diagnostics',
  },
  optional = { 'proteus.code.project', 'proteus.ui.notify' },
  activate = function (app)
    local settings = app.use ('settings')

    settings.define ('json.enabled', {
      title = 'Run the JSON language server',
      type = 'boolean',
      default = true,
      description = 'Completion, hover help and problems in JSON files, from vscode-json-language-server.',
    })
    settings.define ('json.schema_catalog', {
      title = "Use SchemaStore's schemas",
      type = 'boolean',
      default = true,
      description = 'Fetches the list of schemas for common files, such as package.json and tsconfig.json, from schemastore.org.',
    })
    settings.define ('json.validate', {
      title = 'Check JSON files',
      type = 'boolean',
      default = true,
      description = 'Shows syntax errors, and values that break the schema, in the Problems panel.',
    })

    local server ---@type LangJson.Server
    local tool = app.use ('tools').register ({
      id = 'vscode-json-language-server',
      name = 'JSON',
      description = 'Completion, hover help and problems for JSON, from JSON schemas.',
      program = 'vscode-json-language-server',
      kind = 'server',
      install = 'npm install --global vscode-langservers-extracted',
      homepage = 'https://github.com/hrsh7th/vscode-langservers-extracted',
      settings = { 'json.enabled', 'json.schema_catalog', 'json.validate' },
      start = function ()
        server.start (nil)
      end,
      stop = function ()
        server.stop ()
      end,
      check = function ()
        server.stop ()
        server.start (nil)
      end,
    })

    ---@type LangJson.Context
    local ctx = {
      app = app,
      settings = settings,
      editor = app.use ('editor'),
      schemas = schemas_module.install (
        app,
        settings,
        app.use ('files'),
        tool.log
      ),
      notify = function (text)
        local n = app.try_use ('notify')
        if n then
          n.warn (text)
        end
      end,
    }
    server = server_module.install (ctx, tool)

    app.use ('commands').register ({
      id = 'json.restart',
      category = 'JSON',
      title = 'Restart the Language Server',
      icon = 'rotate-cw',
      run = function ()
        server.stop ()
        server.start (nil)
      end,
    })

    server.start (nil)
  end,
}
