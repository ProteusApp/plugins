-- sample.plugin: Showcases minimal API and tests the Plugin Manager flow.
--
--- @type Proteus.Plugin
return {
  name = 'Sample Plugin',
  description = 'A sample plugin.',
  version = '1.0.3',
  depends = { 'lib.ui', 'core.commands' },
  optional = { 'ui.notify', 'ui.toolbar', 'ui.menubar' },

  activate = function (app)
    local commands = app.use ('commands')

    commands.register ({
      id = 'sample.plugin.hello',
      title = 'Says Hello',
      category = 'samples',
      icon = 'smile',
      toolbar = true,
      menu = 'Sample Plugin',
      run = function ()
        local notify = app.try_use ('notify')
        if notify then
          notify.success ('Hello from sample.plugin!')
        end
      end,
    })
  end,
}
