-- proteus.template: one of each part most plugins need, as a start for a plugin of your own.
-- It keeps a list of greetings:
--
--   a command      `template.greet` says a greeting, from the palette, a menu or a key
--   a setting      `template.greeting` is the word each greeting starts with
--   a panel        a view in the right dock, built with the ui library, lists the greetings
--   a service      `template` lets another plugin say one, and its type is in types/
--   a folder       each greeting is written to template/greetings.md in the workspace
--
-- lib/greetings.lua holds the logic, tests/ checks it, and handbook/ is its page in the
-- Handbook. In the Plugin Editor, New Plugin can start a plugin from a copy of this one, with
-- every name changed to yours.

local greetings = require ('lib.greetings') --[[@as Template.GreetingsModule]]

-- The file each greeting is written to, in the folder this plugin claims in `folders`.
local FILE = 'template/greetings.md'

-- lang=css
local CSS = [[
.template-panel {
  display: flex;
  flex-direction: column;
  gap: 8px;
  padding: 10px;
}
.template-row {
  display: flex;
  gap: 6px;
}
.template-row .ui-input {
  flex: 1;
  min-width: 0;
}
.template-item {
  padding: 4px 6px;
  border-radius: 4px;
  background: var(--bg-alt);
}
]]

---@type Proteus.Plugin
return {
  name = 'Plugin Template',
  description = 'A start for a plugin of your own: a command, a setting, a panel, a service, a folder, tests and a Handbook page.',
  version = '1.0.0',
  requires = { proteus = '>=0.3.0', features = { 'permissions' } },
  -- Nothing beyond drawing, keeping its own data and writing in its own folder.
  permissions = {},
  folders = { 'template' },
  depends = {
    'proteus.lib.ui',
    'proteus.ui.views',
    'proteus.core.commands',
    'proteus.core.settings',
  },
  optional = { 'proteus.ui.notify' },

  activate = function (app)
    local ui = app.use ('ui')
    local views = app.use ('views')
    local commands = app.use ('commands')
    local settings = app.use ('settings')
    local notify = app.try_use ('notify')
    ui.css (CSS)

    settings.define ('template.greeting', {
      title = 'Greeting',
      type = 'string',
      default = 'Hello',
      description = 'The word each greeting starts with.',
    })

    -- app.store keeps the list across restarts.
    local said = app.store.get ('said', {}) ---@type string[]
    local list = ui.div ({ style = { display = 'contents' } })

    local function draw ()
      list:clear ()
      if #said == 0 then
        list:append (ui.div ({
          class = 'ui-muted',
          'No greetings yet. Type a name and press Enter.',
        }))
      end
      for _, text in ipairs (said) do
        list:append (ui.div ({ class = 'template-item', text }))
      end
    end

    ---Says a greeting: keeps it, writes the file, draws the panel and shows it.
    ---@param name? string
    ---@return string text
    local function greet (name)
      local text =
        greetings.make (tostring (settings.get ('template.greeting')), name)
      said = greetings.add (said, text)
      app.store.set ('said', said)
      app.fs.write (FILE, greetings.markdown (said))
      draw ()
      if notify then
        notify.info (text)
      end
      return text
    end

    local input = ui.input ({ placeholder = 'A name' })
    local function greet_input ()
      greet (input:value ())
      input:value ('')
    end
    input:on ('keydown', function (ev)
      if ev.key == 'Enter' then
        greet_input ()
        return 'stop'
      end
      return nil
    end)

    views.add ('right', {
      id = 'template',
      title = 'Greetings',
      icon = 'hand',
      content = ui.div ({
        class = 'template-panel',
        ui.div ({
          class = 'template-row',
          input,
          ui.button ({ 'Greet', onclick = greet_input }),
        }),
        list,
        ui.button ({
          'Clear',
          onclick = function ()
            said = {}
            app.store.set ('said', said)
            app.fs.write (FILE, greetings.markdown (said))
            draw ()
          end,
        }),
      }),
    })
    draw ()

    commands.register ({
      id = 'template.greet',
      title = 'Say a Greeting',
      category = 'Greetings',
      icon = 'hand',
      menu = 'Plugins',
      run = function ()
        greet (nil)
      end,
    })

    -- What other plugins get from app.use ('template'). Its type is in types/.
    ---@type Template.Service
    local service = {
      greet = function (name)
        return greet (name)
      end,
      list = function ()
        local copy = {} ---@type string[]
        for i, text in ipairs (said) do
          copy[i] = text
        end
        return copy
      end,
    }
    app.provide ('template', service)
  end,
}
