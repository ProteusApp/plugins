-- lang.typescript: TypeScript in the code editor, with typescript-language-server.
--
-- The server gives completion with documentation, hover help, go to definition (F12 or
-- Ctrl+click) and problems. Organize Imports sorts the file's imports and drops unused ones.
-- tsconfig.json gets its JSON schema as a file association. When the project has its own
-- TypeScript in node_modules, the server uses that version.
--
-- The one server also serves other languages. lang.javascript and lang.react ask for theirs
-- through the `typescript` service, so every kind of file shares what the server knows:
--
--   local remove = app.use ('typescript').serve ({
--     language = 'jsx', language_id = 'javascriptreact',
--   })
--
-- The parts live in lib/:
--   server    the server, shared by every language that asks for it
--   program   finds node and the server's script, and the project's TypeScript
--   launch    where the server's script may be
--   edits     applies the edits the server sends back

local server_module = require ('lib.server') --[[@as LangTypescript.ServerModule]]

-- The JSON schema for TypeScript's own settings files, from schemastore.org.
local TSCONFIG = 'https://www.schemastore.org/tsconfig.json'

---What the parts of the plugin share.
---@class LangTypescript.Context
---@field app Proteus.App
---@field settings Proteus.Settings
---@field editor Proteus.Editor
---@field notify fun(level: 'info'|'warn'|'error', text: string) A pop-up, when ui.notify runs.

---What other plugins get from `app.use ('typescript')`.
---@class LangTypescript.Service
---@field serve fun(spec: LangTypescript.ServeSpec): fun() Serves one more editor language. Gives a function that stops serving it.

---@type Proteus.Plugin
return {
  name = 'TypeScript',
  description = 'TypeScript with typescript-language-server: completion, hover help, go to definition, problems and Organize Imports, on one server that JavaScript and React files share.',
  version = '1.1.0',
  requires = { proteus = '>=0.3.0', features = { 'permissions' } },
  -- The language server is a program it runs, on files anywhere on disk.
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
    settings.define ('typescript.enabled', {
      title = 'Run the TypeScript language server',
      type = 'boolean',
      default = true,
      description = 'Completion, hover help, go to definition and problems in TypeScript and JavaScript files.',
    })
    settings.define ('typescript.project_typescript', {
      title = "Use the project's TypeScript",
      type = 'boolean',
      default = true,
      description = "Checks the code with the TypeScript in the open folder's node_modules when it has one. Off, the TypeScript installed beside the language server checks it.",
    })

    ---@type LangTypescript.Context
    local ctx = {
      app = app,
      settings = settings,
      editor = app.use ('editor'),
      notify = function (level, text)
        local n = app.try_use ('notify')
        if n then
          n[level] (text)
        end
      end,
    }

    local server ---@type LangTypescript.Server
    local tool = app.use ('tools').register ({
      id = 'typescript-language-server',
      name = 'TypeScript',
      description = 'Completion, hover help, go to definition and problems for TypeScript and JavaScript.',
      program = 'typescript-language-server',
      kind = 'server',
      install = 'npm install --global typescript-language-server typescript@6',
      npm = {
        packages = {
          'typescript-language-server@6.0.1',
          'typescript@6.0.3',
        },
        bin = 'typescript-language-server',
      },
      languages = {},
      homepage = 'https://github.com/typescript-language-server/typescript-language-server',
      settings = { 'typescript.enabled', 'typescript.project_typescript' },
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

    -- Each plugin that uses the service gets its own table, so the languages it asked for
    -- go back when it stops. Adding a language runs nothing new, since this plugin already
    -- runs the server, so the service needs no permission.
    app.provide_scoped ('typescript', function (consumer)
      ---@type LangTypescript.Service
      return {
        serve = function (spec)
          local remove = server.serve ({
            language = tostring (spec.language),
            language_id = tostring (spec.language_id or spec.language),
          })
          consumer.dispose (remove)
          return remove
        end,
      }
    end)

    local files = app.use ('files')
    for _, pattern in ipairs ({ 'tsconfig.json', 'tsconfig.*.json' }) do
      files.associate ({ kind = 'schema', pattern = pattern, value = TSCONFIG })
    end

    local commands = app.use ('commands')
    commands.register ({
      id = 'typescript.restart',
      category = 'TypeScript',
      title = 'Restart the Language Server',
      icon = 'rotate-cw',
      run = function ()
        server.stop ()
        server.start (nil)
      end,
    })
    commands.register ({
      id = 'typescript.organize_imports',
      category = 'TypeScript',
      title = 'Organize Imports',
      icon = 'list-ordered',
      key = 'shift+alt+o',
      when = function ()
        local doc = ctx.editor.current ()
        return doc ~= nil and server.serves (doc.language)
      end,
      run = function ()
        server.organize_imports ()
      end,
    })

    server.serve ({ language = 'typescript', language_id = 'typescript' })
  end,
}
