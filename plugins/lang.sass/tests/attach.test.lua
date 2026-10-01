local attach_module = require ('lib.attach') --[[@as LangSass.AttachModule]]

-- lang.css's router, which owns the editor's `css` language when lang.css runs. The tests
-- below run this plugin against the real one.
local router_module = load (
  read ('plugins/lang.css/lib/router.lua'),
  '@plugins/lang.css/lib/router.lua'
) ()

---An editor that keeps one provider for each language, as the real one does.
---@return table
local function fake_editor ()
  local editor = { providers = {} }
  ---@param language string
  ---@param factory function
  ---@return fun()
  function editor.set_provider (language, factory)
    editor.providers[language] = factory
    return function ()
      if editor.providers[language] == factory then
        editor.providers[language] = nil
      end
    end
  end
  ---Which plugin helps with a file, or nil.
  ---@param path string
  ---@param language string
  ---@return string?
  function editor.who (path, language)
    local factory = editor.providers[language]
    local provider = factory and factory ({ path = path, language = language })
    return provider and provider.by or nil
  end
  return editor
end

---A factory that helps with files of these extensions, and marks its help with a name.
---@param name string
---@param extensions string[]
---@return function
local function helps (name, extensions)
  return function (doc)
    for _, ext in ipairs (extensions) do
      if doc.path:sub (-#ext - 1) == '.' .. ext then
        return { by = name }
      end
    end
    return nil
  end
end

---This plugin's attach, with Some Sass's help for `.scss` and `.sass` files.
---@param editor table
---@param services table<string, any> The running services, by name.
---@return LangSass.Attach
local function sass_plugin (editor, services)
  return attach_module.new ({
    editor = editor,
    languages = { 'css', 'sass' },
    providers = {
      css = helps ('sass', { 'scss' }),
      sass = helps ('sass', { 'sass' }),
    },
    css = function ()
      return attach_module.find_css (function (name)
        return services[name]
      end)
    end,
  })
end

---lang.css as it starts: it sets the provider for `css`, then shares its service.
---@param editor table
---@param services table<string, any>
---@return table router
local function start_css_plugin (editor, services)
  local router = router_module.new (editor, 'css')
  router.own (helps ('css', { 'css', 'less', 'scss' }))
  router.apply ()
  services.css = { route = router.route }
  return router
end

---Fails unless every file gets help from the plugin that should give it.
---@param editor table
local function both_serve (editor)
  eq (editor.who ('a/main.scss', 'css'), 'sass')
  eq (editor.who ('a/_mixins.sass', 'sass'), 'sass')
  eq (editor.who ('a/site.css', 'css'), 'css')
  eq (editor.who ('a/theme.less', 'css'), 'css')
end

test ('alone, the plugin sets both providers itself', function ()
  local editor = fake_editor ()
  local sass = sass_plugin (editor, {})
  sass.attach ()
  eq (editor.who ('a/main.scss', 'css'), 'sass')
  eq (editor.who ('a/_mixins.sass', 'sass'), 'sass')
  eq (editor.who ('a/site.css', 'css'), nil)
  sass.detach ()
  eq (editor.providers.css, nil)
  eq (editor.providers.sass, nil)
end)

test ('find_css takes only a service with route', function ()
  local services = { css = { route = 42 } }
  local function try_use (name)
    return services[name]
  end
  eq (attach_module.find_css (try_use), nil)
  services.css = 'css'
  eq (attach_module.find_css (try_use), nil)
  services.css = { route = function () end }
  eq (attach_module.find_css (try_use), services.css)
end)

test ('lang.css first: both plugins serve their files', function ()
  local editor = fake_editor ()
  local services = {}
  start_css_plugin (editor, services)
  local sass = sass_plugin (editor, services)
  sass.attach ()
  both_serve (editor)
end)

test ('this plugin first: both serve once it hears lang.css arrive', function ()
  local editor = fake_editor ()
  local services = {}
  local sass = sass_plugin (editor, services)
  sass.attach ()
  start_css_plugin (editor, services)
  -- What lib/server.lua does on `kernel:service` for `css`.
  sass.attach ()
  both_serve (editor)
end)

test ('scss goes back to lang.css when Some Sass stops', function ()
  local editor = fake_editor ()
  local services = {}
  start_css_plugin (editor, services)
  local sass = sass_plugin (editor, services)
  sass.attach ()
  sass.detach ()
  eq (editor.who ('a/main.scss', 'css'), 'css')
  eq (editor.who ('a/_mixins.sass', 'sass'), nil)
  eq (editor.who ('a/site.css', 'css'), 'css')
end)

test ('attaching twice leaves one claim', function ()
  local editor = fake_editor ()
  local services = {}
  local router = start_css_plugin (editor, services)
  local sass = sass_plugin (editor, services)
  sass.attach ()
  sass.attach ()
  sass.detach ()
  eq (router.routed ('scss'), false)
end)
