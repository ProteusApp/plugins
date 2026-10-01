-- lang.html: HTML in the code editor, with VS Code's HTML language server.
--
-- The server gives completion of tags and attributes, hover help and problems, and the
-- same for the CSS and JavaScript inside `<style>` and `<script>`. It comes from the npm
-- package vscode-langservers-extracted. Prettier ships with Proteus and formats HTML
-- already, so this plugin adds no formatter.
--
-- HTML: Open Preview shows the file in front, rendered, in a panel beside the code.
--
-- The parts live in lib/:
--   server       starts and stops the language server
--   completion   the HTML5 skeleton and the closing tag, added to the server's completion
--   preview      the preview panel
--   markup       the text work behind the other three, which the tests reach

local completion_module = require ('lib.completion') --[[@as LangHtml.CompletionModule]]
local preview_module = require ('lib.preview') --[[@as LangHtml.PreviewModule]]
local server_module = require ('lib.server') --[[@as LangHtml.ServerModule]]

-- The program npm installs. On Windows npm also puts a script with no extension, for other
-- shells, next to the `.cmd` file. A search for the bare name finds that script first, and
-- Windows cannot run it. So on Windows the plugin looks for the `.cmd` file by its full
-- name, which the app starts as it is.
local PROGRAM = 'vscode-html-language-server'

---What the parts of the plugin share.
---@class LangHtml.Context
---@field app Proteus.App
---@field settings Proteus.Settings
---@field editor Proteus.Editor

---@type Proteus.Plugin
return {
  name = 'HTML',
  description = "HTML with VS Code's language server: completion, hover help and problems, also inside style and script, and a live preview.",
  version = '1.0.0',
  requires = { proteus = '>=0.3.0', features = { 'permissions', 'webview' } },
  -- The language server is a program it runs. The `editor` service, which hands over the
  -- text of open files, needs `files`.
  permissions = { 'files', 'process' },
  depends = {
    'proteus.lib.ui',
    'proteus.ui.views',
    'proteus.ui.tabs',
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

    settings.define ('html.enabled', {
      title = 'Run the HTML language server',
      type = 'boolean',
      default = true,
      description = 'Completion, hover help and problems in HTML files, from vscode-html-language-server.',
    })
    settings.define ('html.validate', {
      title = 'Check CSS and JavaScript in HTML',
      type = 'boolean',
      default = true,
      description = 'Lists problems in the CSS and JavaScript inside style and script elements.',
    })
    settings.define ('html.preview_scripts', {
      title = 'Run scripts in the HTML preview',
      type = 'boolean',
      default = false,
      description = "Lets the page's own scripts run in the preview. Off, they are taken out before the page shows.",
    })

    ---@type LangHtml.Context
    local ctx = { app = app, settings = settings, editor = editor }

    local server ---@type LangHtml.Server
    local tool = app.use ('tools').register ({
      id = 'vscode-html-language-server',
      name = 'HTML Language Server',
      description = 'Completion, hover help and problems for HTML, and the CSS and JavaScript inside it.',
      program = app.os == 'windows' and (PROGRAM .. '.cmd') or PROGRAM,
      kind = 'server',
      install = 'npm install --global vscode-langservers-extracted',
      homepage = 'https://github.com/hrsh7th/vscode-langservers-extracted',
      settings = { 'html.enabled', 'html.validate' },
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
    completion_module.install (app.use ('files'))
    local preview = preview_module.install (ctx)

    local commands = app.use ('commands')
    commands.register ({
      id = 'html.restart',
      category = 'HTML',
      title = 'Restart the Language Server',
      icon = 'rotate-cw',
      run = function ()
        server.stop ()
        server.start (nil)
      end,
    })
    commands.register ({
      id = 'html.preview',
      category = 'HTML',
      title = 'Open Preview',
      icon = 'eye',
      run = preview.open,
    })

    server.start (nil)
  end,
}
