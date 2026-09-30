-- sample.plugin: Showcases minimal API and tests the Plugin Manager flow.
--
---@type Proteus.Plugin
return {
  name = 'Sample Plugin',
  description = 'A sample plugin.',
  version = '0.1.0',
  depends = { 'lib.ui', 'core.commands' },
  optional = { 'ui.notify', 'ui.toolbar', 'ui.menubar' },

  activate = function (app)
    local commands = app.use ('commands')

    commands.register ({
      id = 'sample.plugin.hello',
      title = 'Say Hello',
      category = 'Sample.plugin',
      icon = 'smile', -- any Lucide icon name: https://lucide.dev/icons
      toolbar = true, -- adds a toolbar button
      menu = 'Plugins', -- adds an entry to the Plugins menu
      run = function ()
        local notify = app.try_use ('notify')
        if notify then
          notify.success ('Hello from sample.plugin!')
        end
      end,
    })
  end,
}
