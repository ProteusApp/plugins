-- lang.shell: shell scripts in the code editor, with bash-language-server, ShellCheck and
-- shfmt.
--
-- The language server gives completion of commands, variables and functions, hover help, go
-- to definition and problems. It runs ShellCheck for the problems, with the ShellCheck this
-- plugin finds. Format Document runs shfmt. ShellCheck and shfmt each have a row in the Tools
-- panel, which offers their official release when they are not on the PATH.
--
-- The parts live in lib/:
--   server      starts and stops the language server
--   provider    completion, hover help and go to definition from the server
--   completion  fits the server's completion items to the word before the cursor
--   dialect     tells zsh scripts apart, since ShellCheck does not read zsh
--   helper      ShellCheck's and shfmt's rows in the Tools panel
--   format      the formatter
--   config      the server's settings and shfmt's arguments
--   release     the ShellCheck and shfmt downloads for each platform
--   program     finds node and the server's script
--   launch      where the server's script may be

local format_module = require ('lib.format') --[[@as LangShell.FormatModule]]
local helper_module = require ('lib.helper') --[[@as LangShell.HelperModule]]
local paths_module = require ('lsp.paths') --[[@as Lsp.PathsModule]]
local releases = require ('lib.release') --[[@as LangShell.Releases]]
local server_module = require ('lib.server') --[[@as LangShell.ServerModule]]

---What the parts of the plugin share.
---@class LangShell.Context
---@field app Proteus.App
---@field settings Proteus.Settings
---@field editor Proteus.Editor
---@field to_disk fun(doc: Proteus.DocInfo): string A document's full path.
---@field from_disk fun(path: string): string The editor's path for a full path.
---@field notify fun(text: string) A warning, when ui.notify runs.
---@field shellcheck LangShell.Helper
---@field shfmt LangShell.Helper

---@type Proteus.Plugin
return {
  name = 'Shell',
  description = 'Shell scripts with bash-language-server, ShellCheck and shfmt: completion, hover help, go to definition, problems and formatting.',
  version = '1.1.0',
  requires = { proteus = '>=0.3.0', features = { 'permissions' } },
  -- The language server, ShellCheck and shfmt are programs it runs and downloads, on files
  -- anywhere on disk.
  permissions = { 'files', 'process' },
  depends = {
    'proteus.core.settings',
    'proteus.core.commands',
    'proteus.editor.core',
    'proteus.tools.registry',
    'proteus.tools.diagnostics',
  },
  optional = {
    'proteus.core.files',
    'proteus.code.project',
    'proteus.ui.notify',
  },
  activate = function (app)
    local settings = app.use ('settings')
    local editor = app.use ('editor')

    settings.define ('shell.enabled', {
      title = 'Run the shell language server',
      type = 'boolean',
      default = true,
      description = 'Completion, hover help, go to definition and problems in shell scripts, from bash-language-server.',
    })
    settings.define ('shell.shellcheck', {
      title = 'Check shell scripts with ShellCheck',
      type = 'boolean',
      default = true,
      description = "Shows ShellCheck's problems in the Problems panel. ShellCheck does not read zsh, so zsh scripts get none.",
    })
    settings.define ('shell.format', {
      title = 'Format shell scripts with shfmt',
      type = 'boolean',
      default = true,
      description = 'Runs shfmt on shell scripts when they are formatted or saved.',
    })
    settings.define ('shell.indent', {
      title = 'Shell indent',
      type = 'number',
      default = -1,
      description = "How shfmt indents. -1 follows the project's .editorconfig, and uses tabs without one. 0 uses tabs, and a larger number uses that many spaces.",
    })

    local paths = paths_module.new (app, editor)
    local notify = function (text)
      local n = app.try_use ('notify')
      if n then
        n.warn (text)
      end
    end

    local shellcheck = helper_module.new (app, settings, {
      setting = 'shell.shellcheck',
      spec = {
        id = 'shellcheck',
        name = 'ShellCheck',
        description = 'Finds bugs and risky habits in shell scripts.',
        program = 'shellcheck',
        install = 'scoop install shellcheck, brew install shellcheck or apt install shellcheck',
        homepage = 'https://www.shellcheck.net',
        settings = { 'shell.shellcheck' },
        release = releases.shellcheck,
      },
    })
    local shfmt = helper_module.new (app, settings, {
      setting = 'shell.format',
      spec = {
        id = 'shfmt',
        name = 'shfmt',
        description = 'Formats shell scripts the same way every time.',
        program = 'shfmt',
        install = 'scoop install shfmt, brew install shfmt or go install mvdan.cc/sh/v3/cmd/shfmt@latest',
        homepage = 'https://github.com/mvdan/sh',
        settings = { 'shell.format', 'shell.indent' },
        release = releases.shfmt,
      },
    })

    local server ---@type LangShell.Server
    local tool = app.use ('tools').register ({
      id = 'bash-language-server',
      name = 'Bash Language Server',
      description = 'Completion, hover help, go to definition and problems for shell scripts.',
      program = 'bash-language-server',
      kind = 'server',
      install = 'npm install --global bash-language-server',
      npm = {
        packages = { 'bash-language-server@5.8.1' },
        bin = 'bash-language-server',
      },
      languages = { 'shell' },
      homepage = 'https://github.com/bash-lsp/bash-language-server',
      settings = { 'shell.enabled', 'shell.shellcheck' },
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

    ---@type LangShell.Context
    local ctx = {
      app = app,
      settings = settings,
      editor = editor,
      to_disk = paths.to_disk,
      from_disk = paths.from_disk,
      notify = notify,
      shellcheck = shellcheck,
      shfmt = shfmt,
    }
    server = server_module.install (ctx, tool)
    format_module.install (ctx)

    ---Looks for ShellCheck and shfmt once a shell script is open.
    local function wake ()
      shellcheck.wake ()
      shfmt.wake ()
    end

    app.on ('editor:opened', function (doc)
      ---@cast doc Proteus.DocInfo
      if doc.language == 'shell' then
        wake ()
      end
    end)
    for _, doc in ipairs (editor.docs ()) do
      if doc.language == 'shell' then
        wake ()
        break
      end
    end

    app.use ('commands').register ({
      id = 'shell.restart',
      category = 'Shell',
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
