-- lang.css: CSS and Less in the code editor, with vscode-css-language-server.
--
-- The server gives completion of properties and values, hover help that says which browsers
-- support a property, problems from its checks, and go to definition for variables and
-- `@import`. Prettier, which comes with the app, already formats CSS, Less and SCSS, so the
-- server does not.
--
-- The editor calls `.css`, `.scss` and `.less` files all `css`, and keeps one provider for
-- each language. So this plugin sets the one for `css` and hands each file on by its
-- extension. Another plugin claims files through the `css` service, as lang.sass does for
-- `.scss` files. The rest go to this plugin's server, `.scss` files too when nothing claimed
-- them.
--
-- The parts live in lib/:
--   router      shares the `css` language between plugins, by extension
--   languages   which files the server reads, and its settings
--   server      starts and stops the language server
--   documents   keeps the server's copy of each open file in step
--   provider    completion, hover help and go to definition from the server
--   completion  turns the server's completion items into plain text
--   program     finds node and the server's script
--   launch      where the server's script may be

local languages = require ('lib.languages') --[[@as LangCss.LanguagesModule]]
local router_module = require ('lib.router') --[[@as LangCss.RouterModule]]
local server_module = require ('lib.server') --[[@as LangCss.ServerModule]]

---What the parts of the plugin share.
---@class LangCss.Context
---@field app Proteus.App
---@field settings Proteus.Settings
---@field editor Proteus.Editor
---@field router LangCss.Router
---@field notify fun(text: string) A warning, when ui.notify runs.

---What another plugin passes to `css.route`.
---@class LangCss.RouteSpec
---@field extensions string[] Such as `{ 'scss' }`.
---@field factory Proteus.ProviderFactory The help for each of those files, or nil for none.

---The `css` service. Each plugin that uses it gets its own, and its claims go back when it
---stops.
---@class LangCss.Service
---@field route fun(spec: LangCss.RouteSpec): fun() Claims files by extension. Returns a function that gives them back.

-- Stops the router before the plugin's cleanup, so nothing sets the provider again while the
-- plugin stops.
local stop_router = nil ---@type fun()?

---@type Proteus.Plugin
return {
  name = 'CSS',
  description = 'CSS and Less with vscode-css-language-server: completion, hover help with browser support, problems and go to definition.',
  version = '1.1.0',
  requires = { proteus = '>=0.3.0', features = { 'permissions' } },
  -- The language server is a program it runs, on files anywhere on disk.
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

    settings.define ('css.enabled', {
      title = 'Run the CSS language server',
      type = 'boolean',
      default = true,
      description = 'Completion, hover help, go to definition and problems in .css and .less files, from vscode-css-language-server.',
    })
    settings.define ('css.validate', {
      title = 'Check CSS files',
      type = 'boolean',
      default = true,
      description = 'Shows syntax errors and the lint rules below in the Problems panel.',
    })
    local tool_settings = { 'css.enabled', 'css.validate' }
    for _, spec in ipairs (languages.LINT_RULES) do
      local key = 'css.lint.' .. spec.key
      settings.define (key, {
        title = 'Lint: ' .. spec.title,
        type = 'select',
        options = languages.LEVELS,
        default = spec.default,
        description = spec.description,
      })
      tool_settings[#tool_settings + 1] = key
    end

    local router = router_module.new (editor, languages.LANGUAGE)
    stop_router = router.stop

    local server ---@type LangCss.Server
    local tool = app.use ('tools').register ({
      id = 'vscode-css-language-server',
      name = 'CSS',
      description = 'Completion, hover help, go to definition and problems for CSS and Less.',
      program = 'vscode-css-language-server',
      kind = 'server',
      install = 'npm install --global vscode-langservers-extracted',
      npm = {
        packages = { 'vscode-langservers-extracted@4.10.0' },
        bin = 'vscode-css-language-server',
      },
      languages = { 'css' },
      homepage = 'https://github.com/hrsh7th/vscode-langservers-extracted',
      settings = tool_settings,
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

    ---@type LangCss.Context
    local ctx = {
      app = app,
      settings = settings,
      editor = editor,
      router = router,
      notify = function (text)
        local n = app.try_use ('notify')
        if n then
          n.warn (text)
        end
      end,
    }
    server = server_module.install (ctx, tool)

    app.use ('commands').register ({
      id = 'css.restart',
      category = 'CSS',
      title = 'Restart the Language Server',
      icon = 'rotate-cw',
      run = function ()
        server.stop ()
        server.start (nil)
      end,
    })

    -- This plugin owns the `css` language from now on, even while its own server is off, so
    -- the files other plugins claim keep their help.
    router.apply ()
    server.start (nil)

    -- Last, since a plugin that waits for the service claims its files the moment it comes.
    -- The router hands a claiming plugin each file's text and full path, which the editor
    -- keeps for plugins with `files`, so the service asks for it too.
    app.provide_scoped ('css', function (consumer)
      ---@type LangCss.Service
      return {
        route = function (spec)
          local extensions = {} ---@type string[]
          for _, ext in
            ipairs (type (spec.extensions) == 'table' and spec.extensions or {})
          do
            extensions[#extensions + 1] = tostring (ext)
          end
          local factory = spec.factory
          if type (factory) ~= 'function' then
            error ('css.route needs a factory function', 2)
          end
          local remove = router.route ({
            extensions = extensions,
            factory = factory,
          })
          local cancel = consumer.dispose (remove)
          return function ()
            remove ()
            cancel ()
          end
        end,
      }
    end, { needs = 'files' })
  end,
  deactivate = function ()
    if stop_router then
      stop_router ()
      stop_router = nil
    end
  end,
}
