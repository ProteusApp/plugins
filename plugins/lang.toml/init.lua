-- lang.toml: TOML in the code editor, with Taplo.
--
-- Taplo's language server gives completion, hover help and problems, from JSON schemas: the
-- `schema` associations any plugin adds through core.files, and SchemaStore's catalog.
-- Format Document runs `taplo fmt`. When Taplo is not on the PATH, the Tools panel offers
-- its official release, checked against a pinned checksum.
--
-- The parts live in lib/:
--   schemas   schema associations, turned into Taplo's settings
--   server    starts and stops the language server
--   format    the formatter
--   release   the Taplo download for each platform

local disk = require ('disk_paths') --[[@as DiskPaths]]
local format_module = require ('lib.format') --[[@as LangToml.FormatModule]]
local release = require ('lib.release') --[[@as Proteus.ToolRelease]]
local schemas_module = require ('lib.schemas') --[[@as LangToml.SchemasModule]]
local server_module = require ('lib.server') --[[@as LangToml.ServerModule]]

---What the parts of the plugin share.
---@class LangToml.Context
---@field app Proteus.App
---@field settings Proteus.Settings
---@field editor Proteus.Editor
---@field schemas LangToml.Schemas
---@field to_disk fun(doc: Proteus.DocInfo): string A document's full path.
---@field notify fun(text: string) A warning, when ui.notify runs.

---@type Proteus.Plugin
return {
  name = 'TOML',
  description = 'TOML with Taplo: completion, hover help and problems from JSON schemas, and formatting. Other plugins add schemas as file associations.',
  version = '1.0.1',
  requires = { proteus = '>=0.2.0', features = { 'permissions' } },
  -- Taplo is a program it runs and downloads, on files anywhere on disk.
  permissions = { 'files', 'process' },
  depends = {
    'core.settings',
    'core.commands',
    'core.files',
    'editor.core',
    'tools.registry',
    'tools.diagnostics',
  },
  optional = { 'code.project', 'ui.notify' },
  activate = function (app)
    local settings = app.use ('settings')
    local editor = app.use ('editor')

    settings.define ('toml.enabled', {
      title = 'Run the TOML language server',
      type = 'boolean',
      default = true,
      description = 'Completion, hover help and problems in TOML files, from Taplo.',
    })
    settings.define ('toml.schema_catalog', {
      title = "Use SchemaStore's schemas",
      type = 'boolean',
      default = true,
      description = 'Fetches schemas for common files, such as Cargo.toml and pyproject.toml, from schemastore.org.',
    })
    settings.define ('toml.format', {
      title = 'Format TOML with Taplo',
      type = 'boolean',
      default = true,
      description = 'Runs taplo fmt on TOML files when they are formatted or saved.',
    })

    local workspace = disk.normalize (app.kernel.launch.workspace or '')

    ---@type LangToml.Context
    local ctx = {
      app = app,
      settings = settings,
      editor = editor,
      schemas = schemas_module.install (settings, app.use ('files')),
      to_disk = function (doc)
        return doc.external and disk.normalize (doc.path)
          or disk.join (workspace, doc.path)
      end,
      notify = function (text)
        local n = app.try_use ('notify')
        if n then
          n.warn (text)
        end
      end,
    }

    local server ---@type LangToml.Server
    local tool = app.use ('tools').register ({
      id = 'taplo',
      name = 'Taplo',
      description = 'Completion, hover help, problems and formatting for TOML.',
      program = 'taplo',
      kind = 'server',
      install = 'cargo install taplo-cli --locked',
      homepage = 'https://taplo.tamasfe.dev',
      settings = { 'toml.enabled', 'toml.schema_catalog', 'toml.format' },
      release = release,
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
    format_module.install (ctx, tool)

    app.use ('commands').register ({
      id = 'toml.restart',
      category = 'TOML',
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
