local router_module = require ('lib.router') --[[@as LangCss.RouterModule]]

---An editor that keeps one provider for each language, as the real one does.
---@return table
local function fake_editor ()
  local editor = { providers = {}, sets = 0 }
  ---@param language string
  ---@param factory function
  ---@return fun()
  function editor.set_provider (language, factory)
    editor.providers[language] = factory
    editor.sets = editor.sets + 1
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

---A factory that marks its help with a name.
---@param name string
---@return function
local function helps (name)
  return function ()
    return { by = name }
  end
end

test ('files nobody claimed go to the plugin itself', function ()
  local editor = fake_editor ()
  local router = router_module.new (editor, 'css')
  router.own (helps ('css'))
  router.apply ()
  eq (editor.who ('a/site.css', 'css'), 'css')
  eq (editor.who ('a/theme.less', 'css'), 'css')
  eq (editor.who ('a/main.scss', 'css'), 'css')
end)

test ('a claim takes files of its kind and leaves the rest', function ()
  local editor = fake_editor ()
  local router = router_module.new (editor, 'css')
  router.own (helps ('css'))
  router.apply ()
  router.route ({ extensions = { 'scss' }, factory = helps ('sass') })
  eq (editor.who ('a/main.scss', 'css'), 'sass')
  eq (editor.who ('a/MAIN.SCSS', 'css'), 'sass')
  eq (editor.who ('a/site.css', 'css'), 'css')
  eq (router.routed ('scss'), true)
  eq (router.routed ('css'), false)
end)

test ('a claim reads extensions in any case and with a dot', function ()
  local editor = fake_editor ()
  local router = router_module.new (editor, 'css')
  router.route ({ extensions = { '.SCSS' }, factory = helps ('sass') })
  eq (router.routed ('scss'), true)
  eq (editor.who ('a/main.scss', 'css'), 'sass')
end)

test ('giving files back returns them to the plugin itself', function ()
  local editor = fake_editor ()
  local router = router_module.new (editor, 'css')
  router.own (helps ('css'))
  router.apply ()
  local give_back =
    router.route ({ extensions = { 'scss' }, factory = helps ('sass') })
  give_back ()
  eq (editor.who ('a/main.scss', 'css'), 'css')
  eq (router.routed ('scss'), false)
  -- A second call changes nothing.
  local sets = editor.sets
  give_back ()
  eq (editor.sets, sets)
end)

test (
  'the latest claim wins, and the earlier one comes back after it',
  function ()
    local editor = fake_editor ()
    local router = router_module.new (editor, 'css')
    router.route ({ extensions = { 'scss' }, factory = helps ('first') })
    local later =
      router.route ({ extensions = { 'scss' }, factory = helps ('second') })
    eq (editor.who ('a/main.scss', 'css'), 'second')
    later ()
    eq (editor.who ('a/main.scss', 'css'), 'first')
  end
)

test ('each claim sets the provider again and tells the listeners', function ()
  local editor = fake_editor ()
  local router = router_module.new (editor, 'css')
  local heard = 0
  router.on_change (function ()
    heard = heard + 1
  end)
  router.apply ()
  local give_back =
    router.route ({ extensions = { 'scss' }, factory = helps ('sass') })
  give_back ()
  eq (heard, 2)
  eq (editor.sets, 3)
end)

test ('a file in another language gets nothing', function ()
  local editor = fake_editor ()
  local router = router_module.new (editor, 'css')
  router.own (helps ('css'))
  router.apply ()
  local factory = editor.providers.css
  eq (factory ({ path = 'a/main.sass', language = 'sass' }), nil)
end)

test ('after stop, nothing sets the provider again', function ()
  local editor = fake_editor ()
  local router = router_module.new (editor, 'css')
  router.own (helps ('css'))
  router.apply ()
  local give_back =
    router.route ({ extensions = { 'scss' }, factory = helps ('sass') })
  router.stop ()
  eq (editor.providers.css, nil)
  give_back ()
  router.apply ()
  eq (editor.providers.css, nil)
end)
