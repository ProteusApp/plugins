-- lang.sass: Sass in the code editor, with Some Sass.
--
-- Some Sass's language server gives completion, hover help, go to definition and problems in
-- `.scss` files and in the indented `.sass` files. It knows the variables, mixins and functions
-- that other files bring in with `@use`, `@forward` and `@import`. It can serve plain `.css`
-- files too, when `sass.css` is on and lang.css is not running.
--
-- The editor calls `.scss` files `css`, the same as `.css` and `.less` files, and `.sass` files
-- `sass`. The app's lsp.client serves one language, so this plugin builds its own client from
-- the same parts. It serves both languages from one server, and tells the server which kind
-- of file each one is.
--
-- The editor keeps one provider for each language. When lang.css runs, it owns `css`, and
-- this plugin claims `.scss` files through lang.css's `css` service. lang.css is optional, so
-- it starts first when the profile runs both. When it starts later, this plugin hears the
-- service arrive and moves `.scss` files over then.
--
-- Prettier, which comes with the app, already formats `.scss` files. Nothing formats `.sass`
-- files, since Prettier does not read the indented syntax.
--
-- The parts live in lib/:
--   languages   which files the server serves, and its settings
--   attach      gives the help to the editor, through lang.css when it runs
--   documents   keeps the server's copy of each open file in step
--   client      the server behind both of the editor's languages
--   server      starts and stops the language server

local languages = require ('lib.languages') --[[@as LangSass.LanguagesModule]]
local server_module = require ('lib.server') --[[@as LangSass.ServerModule]]

-- The color of the Sass logo, for the file icons.
local SASS_PINK = '#cd6799'

---What the parts of the plugin share.
---@class LangSass.Context
---@field app Proteus.App
---@field settings Proteus.Settings
---@field editor Proteus.Editor

---@type Proteus.Plugin
return {
  name = 'Sass',
  description = 'Sass and SCSS with Some Sass: completion across @use and @import, hover help, go to definition and problems.',
  version = '1.0.0',
  requires = { proteus = '>=0.3.0', features = { 'permissions' } },
  -- Some Sass is a program it runs, on files anywhere on disk.
  permissions = { 'files', 'process' },
  depends = {
    'proteus.core.settings',
    'proteus.core.commands',
    'proteus.core.files',
    'proteus.editor.core',
    'proteus.tools.registry',
    'proteus.tools.diagnostics',
  },
  optional = { 'proteus.code.project', 'proteus.ui.notify', 'lang.css' },
  activate = function (app)
    local settings = app.use ('settings')
    local editor = app.use ('editor')

    settings.define ('sass.enabled', {
      title = 'Run the Sass language server',
      type = 'boolean',
      default = true,
      description = 'Completion, hover help, go to definition and problems in .scss and .sass files, from Some Sass.',
    })
    settings.define ('sass.css', {
      title = 'Use Some Sass for plain CSS',
      type = 'boolean',
      default = false,
      description = 'Gives .css files the same help while the CSS plugin (lang.css) is not running. With it, .css files go to it instead.',
    })
    settings.define ('sass.load_paths', {
      title = 'Load paths',
      type = 'json',
      default = {},
      description = 'Folders, from the top of the open folder, where @use and @import look for files, such as ["src/styles"]. node_modules is always one.',
    })
    settings.define ('sass.use_only', {
      title = 'Suggest only what @use brings in',
      type = 'boolean',
      default = false,
      description = 'Leaves out names from files that are not loaded with @use or @forward. Turn it on when the project does not use @import.',
    })

    ---@type LangSass.Context
    local ctx = { app = app, settings = settings, editor = editor }

    local server ---@type LangSass.Server
    local tool = app.use ('tools').register ({
      id = 'some-sass',
      name = 'Some Sass',
      description = 'Completion, hover help, go to definition and problems for Sass and SCSS.',
      program = languages.program (app.os),
      kind = 'server',
      install = 'npm install --global some-sass-language-server',
      homepage = 'https://wkillerud.github.io/some-sass/',
      settings = {
        'sass.enabled',
        'sass.css',
        'sass.load_paths',
        'sass.use_only',
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
      id = 'sass.restart',
      category = 'Sass',
      title = 'Restart the Language Server',
      icon = 'rotate-cw',
      run = function ()
        server.stop ()
        server.start (nil)
      end,
    })

    -- An icon for Sass files in every icon pack. A pack's own icon for them wins.
    local files = app.use ('files')
    for _, pattern in ipairs ({ '*.scss', '*.sass' }) do
      files.associate ({
        kind = 'icon',
        pattern = pattern,
        value = { icon = 'paintbrush', color = SASS_PINK },
      })
    end

    server.start (nil)
  end,
}
