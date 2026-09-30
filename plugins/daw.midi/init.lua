-- daw.midi: plays the DAW from MIDI keyboards. The notes go to the armed track, or else the
-- selected one, the same as the computer keyboard's, so recording takes them too. The sustain
-- pedal holds notes until it lifts.
--
-- It asks for the `midi` permission, which only hears what a keyboard plays: the app passes
-- notes and controllers, never SysEx, and sends nothing back to the device.

---@type Proteus.Plugin
return {
  name = 'DAW MIDI keyboards',
  description = 'Play and record the DAW from a MIDI keyboard, with the sustain pedal.',
  version = '1.0.0',
  requires = { proteus = '>=0.2.0', features = { 'permissions', 'midi' } },
  permissions = { 'midi' },
  depends = { 'daw.core', 'daw.engine', 'core.commands' },
  optional = { 'ui.notify' },
  activate = function (app)
    local engine = app.use ('daw.engine') --[[@as Daw.Engine]]
    local commands = app.use ('commands')
    local notify = app.try_use ('notify')

    local pedal = false
    local held = {} ---@type table<integer, boolean>
    local listener = nil ---@type Proteus.MidiListener?

    local function release_held ()
      for note in pairs (held) do
        engine.note_off ('', note)
      end
      held = {}
    end

    ---@param m Proteus.MidiMessage
    local function on_message (m)
      local note = m.note
      if m.type == 'note_on' and note then
        held[note] = nil
        engine.note_on ('', note, (m.velocity or 100) / 127)
      elseif m.type == 'note_off' and note then
        if pedal then
          held[note] = true
        else
          engine.note_off ('', note)
        end
      elseif m.type == 'controller' then
        if m.controller == 64 then
          pedal = (m.value or 0) >= 64
          if not pedal then
            release_held ()
          end
        elseif m.controller == 120 or m.controller == 123 then
          -- All sound off, and all notes off.
          held = {}
          engine.all_notes_off ()
        end
      end
    end

    local function listen ()
      if listener then
        listener.close ()
      end
      listener = app.midi.listen (on_message)
    end
    listen ()

    commands.register ({
      id = 'daw.midi_reconnect',
      category = 'DAW',
      title = 'Reconnect MIDI Keyboards',
      icon = 'cable',
      menu = 'Options',
      run = function ()
        listen ()
        app.midi.inputs (function (names)
          if not notify then
            return
          end
          local list = names or {}
          if #list == 0 then
            notify.warn ('No MIDI keyboard is connected.')
          else
            notify.info ('Listening to ' .. table.concat (list, ', ') .. '.')
          end
        end)
      end,
    })
  end,
}
