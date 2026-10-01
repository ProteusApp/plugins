-- lang.docker: Dockerfiles and Compose files in the code editor.
--
-- docker-langserver gives Dockerfiles completion for instructions, flags and variables, hover
-- help, go to definition for build stages and variables, and problems. Format Document asks
-- it to format the file. Hadolint checks each Dockerfile for best practice as it opens and
-- each time it is saved. Compose files get their JSON schema as file associations, which a
-- YAML plugin such as lang.yaml reads.
--
-- The editor calls files named `Dockerfile` or `Containerfile` `dockerfile`, so those are the
-- files it serves.
--
-- The parts live in lib/:
--   server      starts and stops the language server, and asks it to format
--   provider    completion, hover help and go to definition from the server
--   completion  where each completion item starts, and the text it inserts
--   config      the settings the server asks for
--   edits       applies the server's formatting edits
--   program     finds node and the server's script
--   launch      where the server's script may be
--   lint        runs Hadolint
--   hadolint    turns Hadolint's output into problems
--   release     the Hadolint download for each platform
--   compose     the Compose schema's file associations

local compose = require ('lib.compose') --[[@as LangDocker.ComposeModule]]
local lint_module = require ('lib.lint') --[[@as LangDocker.LintModule]]
local paths_module = require ('lsp.paths') --[[@as Lsp.PathsModule]]
local release = require ('lib.release') --[[@as Proteus.ToolRelease]]
local server_module = require ('lib.server') --[[@as LangDocker.ServerModule]]

---What the parts of the plugin share.
---@class LangDocker.Context
---@field app Proteus.App
---@field settings Proteus.Settings
---@field editor Proteus.Editor
---@field paths Lsp.Paths Turns the editor's paths into full paths, and back.
---@field notify fun(text: string) A warning, when ui.notify runs.

---@type Proteus.Plugin
return {
  name = 'Docker',
  description = 'Dockerfiles with docker-langserver and Hadolint: completion, hover help, problems and formatting. Compose files get their schema for a YAML plugin.',
  version = '1.0.0',
  requires = { proteus = '>=0.3.0', features = { 'permissions' } },
  -- docker-langserver and Hadolint are programs it runs, and downloads in Hadolint's case, on
  -- files anywhere on disk.
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
    local editor = app.use ('editor')

    settings.define ('docker.enabled', {
      title = 'Run the Dockerfile language server',
      type = 'boolean',
      default = true,
      description = 'Completion, hover help and problems in Dockerfiles, from docker-langserver.',
    })
    settings.define ('docker.hadolint', {
      title = 'Check Dockerfiles with Hadolint',
      type = 'boolean',
      default = true,
      description = 'Runs Hadolint on each Dockerfile as it opens and when it is saved, and shows its best-practice findings in the Problems panel.',
    })
    settings.define ('docker.format', {
      title = 'Format Dockerfiles',
      type = 'boolean',
      default = true,
      description = 'Format Document asks docker-langserver to format Dockerfiles, and so does each save while editor.format_on_save is on.',
    })

    ---@type LangDocker.Context
    local ctx = {
      app = app,
      settings = settings,
      editor = editor,
      paths = paths_module.new (app, editor),
      notify = function (text)
        local n = app.try_use ('notify')
        if n then
          n.warn (text)
        end
      end,
    }

    local tools = app.use ('tools')

    local server ---@type LangDocker.Server
    local server_tool = tools.register ({
      id = 'docker-langserver',
      name = 'Dockerfile',
      description = 'Completion, hover help, problems and formatting for Dockerfiles.',
      program = 'docker-langserver',
      kind = 'server',
      install = 'npm install --global dockerfile-language-server-nodejs',
      homepage = 'https://github.com/rcjsuen/dockerfile-language-server-nodejs',
      settings = { 'docker.enabled', 'docker.format' },
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
    server = server_module.install (ctx, server_tool)

    local lint ---@type LangDocker.Lint
    local hadolint_tool = tools.register ({
      id = 'hadolint',
      name = 'Hadolint',
      description = 'Best-practice checks for Dockerfiles.',
      program = 'hadolint',
      kind = 'command',
      install = 'brew install hadolint',
      homepage = 'https://github.com/hadolint/hadolint',
      settings = { 'docker.hadolint' },
      release = release,
      check = function ()
        lint.check ()
      end,
    })
    lint = lint_module.install (ctx, hadolint_tool)

    editor.add_formatter ('dockerfile', function (doc, text, done)
      if settings.get ('docker.format') ~= true then
        done (nil)
        return
      end
      server.format (doc, text, done)
    end)

    local files = app.use ('files')
    for _, association in ipairs (compose.associations ()) do
      files.associate (association)
    end

    app.use ('commands').register ({
      id = 'docker.restart',
      category = 'Docker',
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
