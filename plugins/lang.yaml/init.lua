-- lang.yaml: YAML in the code editor, with yaml-language-server.
--
-- The language server gives completion, hover help and problems, from JSON schemas: the
-- `schema` associations any plugin adds through proteus.core.files, and SchemaStore's
-- catalog. Prettier, which ships with Proteus, formats YAML, so the server's own formatter
-- stays off.
--
-- The parts live in lib/:
--   globs    schema associations, turned into the globs the server reads
--   config   the settings the server asks for
--   schemas  keeps the associations and tells the server when they change
--   server   starts and stops the language server

local schemas_module = require ('lib.schemas') --[[@as LangYaml.SchemasModule]]
local server_module = require ('lib.server') --[[@as LangYaml.ServerModule]]

-- The program npm installs. On Windows npm adds a script with no extension for other shells,
-- next to the `.cmd` file. A search for the bare name finds that script first, and Windows
-- cannot run it, so the plugin asks for the `.cmd` file by its full name.
local PROGRAM = 'yaml-language-server'

---What the parts of the plugin share.
---@class LangYaml.Context
---@field app Proteus.App
---@field settings Proteus.Settings
---@field editor Proteus.Editor
---@field schemas LangYaml.Schemas

---@type Proteus.Plugin
return {
  name = 'YAML',
  description = 'YAML with yaml-language-server: completion, hover help and problems from JSON schemas. Other plugins add schemas as file associations.',
  version = '1.1.0',
  requires = { proteus = '>=0.3.0', features = { 'permissions' } },
  -- yaml-language-server is a program it runs, on files anywhere on disk.
  permissions = { 'files', 'process' },
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

    settings.define ('yaml.enabled', {
      title = 'Run the YAML language server',
      type = 'boolean',
      default = true,
      description = 'Completion, hover help and problems in YAML files, from yaml-language-server.',
    })
    settings.define ('yaml.schema_store', {
      title = "Use SchemaStore's schemas",
      type = 'boolean',
      default = true,
      description = 'Fetches schemas for common files, such as docker-compose.yml and .gitlab-ci.yml, from schemastore.org.',
    })
    settings.define ('yaml.custom_tags', {
      title = 'Custom tags',
      type = 'json',
      default = {},
      description = 'Tags the server accepts, with the kind of value each one takes, such as ["!Ref scalar", "!GetAtt sequence"] for CloudFormation.',
    })
    settings.define ('yaml.validate', {
      title = 'Show problems',
      type = 'boolean',
      default = true,
      description = 'Checks YAML files against their schemas, and shows what is wrong in the Problems panel.',
    })
    settings.define ('yaml.key_ordering', {
      title = 'Keys in alphabetical order',
      type = 'boolean',
      default = false,
      description = 'Marks keys that are not in alphabetical order as problems.',
    })
    settings.define ('yaml.version', {
      title = 'YAML version',
      type = 'select',
      options = { '1.2', '1.1' },
      default = '1.2',
      description = 'The YAML version files are read as. In 1.1, words such as yes and no are booleans.',
    })

    ---@type LangYaml.Context
    local ctx = {
      app = app,
      settings = settings,
      editor = app.use ('editor'),
      schemas = schemas_module.install (settings, app.use ('files')),
    }

    local server ---@type LangYaml.Server
    local tool = app.use ('tools').register ({
      id = 'yaml-language-server',
      name = 'YAML Language Server',
      description = 'Completion, hover help and problems for YAML.',
      program = app.os == 'windows' and (PROGRAM .. '.cmd') or PROGRAM,
      kind = 'server',
      install = 'npm install --global yaml-language-server',
      npm = { packages = { 'yaml-language-server@1.24.0' }, bin = PROGRAM },
      languages = { 'yaml' },
      homepage = 'https://github.com/redhat-developer/yaml-language-server',
      settings = {
        'yaml.enabled',
        'yaml.schema_store',
        'yaml.custom_tags',
        'yaml.validate',
        'yaml.key_ordering',
        'yaml.version',
      },
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
    server = server_module.install (ctx, tool)

    app.use ('commands').register ({
      id = 'yaml.restart',
      category = 'YAML',
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
