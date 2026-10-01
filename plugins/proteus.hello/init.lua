-- proteus.hello: the whole "blank" app. One plugin, drawing straight onto the window.
-- There is no shell, no menu bar and no theme here. A copy of this plugin is a good start for a new app.

-- lang=css
local CSS = [[
.hello { height: 100%; display: grid; place-items: center; background: #0f1115; color: #e8e8ea;
  font: 15px/1.6 system-ui, sans-serif; }
.hello-card { max-width: 520px; padding: 36px; border-radius: 16px; background: #171a21; border: 1px solid #262a33; }
.hello h1 { margin: 0 0 8px; font-size: 26px; }
.hello p { color: #a3a9b5; margin: 0 0 16px; }
.hello code { font-family: Consolas, monospace; background: #0f1115; padding: 1px 6px; border-radius: 4px; color: #b9a7ff; }
.hello .count { font-size: 42px; font-weight: 700; color: #b9a7ff; }
.hello button { font: inherit; padding: 8px 16px; border-radius: 8px; border: 1px solid #333846; background: #222733;
  color: inherit; cursor: pointer; margin-right: 8px; }
.hello button:hover { background: #2b3140; }
.hello .hint { margin-top: 22px; font-size: 12px; color: #6d7482; }
]]

---@type Proteus.Plugin
return {
  name = 'Hello',
  description = 'A one-plugin app: a counter and a way back to the Plugin Editor.',
  version = '1.0.0',
  requires = { proteus = '>=0.3.0', features = { 'permissions' } },
  -- It keeps the count in app.store, and needs nothing more.
  permissions = {},
  depends = { 'proteus.lib.ui' },
  -- It draws the whole window, so it cannot share the window with the layout plugin.
  conflicts = { 'proteus.ui.shell' },
  activate = function (app)
    local ui = app.use ('ui')
    ui.css (CSS)

    local count = app.store.get ('count', 0)
    local number = ui.div ({ class = 'count', tostring (count) })

    ui.mount (ui.div ({
      class = 'hello',
      ui.div ({
        class = 'hello-card',
        ui.h1 ({ 'Hello from one plugin' }),
        ui.p ({
          'This whole window is ',
          ui.code ({ 'plugins/community/proteus.hello/init.lua' }),
          '. The blank profile runs this plugin and the UI library it needs, and nothing else.',
        }),
        number,
        ui.p ({
          'The count is saved with ',
          ui.code ({ 'app.store' }),
          ', so it survives a restart.',
        }),
        ui.button ({
          'Add one',
          onclick = function ()
            count = count + 1
            app.store.set ('count', count)
            number:text (count)
          end,
        }),
        ui.button ({
          'Open the Plugin Editor',
          onclick = function ()
            app.kernel.switch_profile ('editor')
          end,
        }),
        ui.div ({
          class = 'hint',
          'Ctrl+Alt+Shift+H opens the Plugin Editor in safe mode from any profile.',
        }),
      }),
    }))
  end,
}
