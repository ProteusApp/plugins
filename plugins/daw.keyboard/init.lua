-- daw.keyboard: the computer keyboard as a piano. The middle row plays the white keys from
-- A, and the row above plays the black keys, the way most music programs lay them out. Z and
-- X move down and up an octave, and C and V change how hard the notes play. Notes go to the
-- armed track, or the selected one, and recording picks them up like any other.
--
-- Keys with Ctrl, Alt or Cmd held, and keys typed into a text field, are left alone.

-- Key codes, so the layout of the keyboard does not matter, and the semitone above C each
-- one plays.
---@type table<string, integer>
local NOTES = {
  KeyA = 0,
  KeyW = 1,
  KeyS = 2,
  KeyE = 3,
  KeyD = 4,
  KeyF = 5,
  KeyT = 6,
  KeyG = 7,
  KeyY = 8,
  KeyH = 9,
  KeyU = 10,
  KeyJ = 11,
  KeyK = 12,
  KeyO = 13,
  KeyL = 14,
  KeyP = 15,
  Semicolon = 16,
}

---@type Proteus.Plugin
return {
  name = 'DAW computer keyboard',
  description = 'Play the selected track from the computer keyboard.',
  version = '1.0.0',
  requires = { proteus = '>=0.2.0', features = { 'permissions' } },
  permissions = {},
  depends = { 'daw.core', 'daw.engine', 'core.commands' },
  optional = { 'ui.statusbar', 'core.settings', 'core.keys' },
  activate = function (app)
    local daw = app.use ('daw') --[[@as Daw.Core]]
    local engine = app.use ('daw.engine') --[[@as Daw.Engine]]
    local commands = app.use ('commands')
    local status = app.try_use ('status')
    local settings = app.try_use ('settings')

    if settings then
      settings.define ('daw.computer_keyboard', {
        title = 'Play notes from the computer keyboard',
        type = 'boolean',
        default = true,
        description = 'A to K play the white keys and W to U the black ones. Z and X change the octave, C and V the velocity.',
      })
    end

    local octave = math.floor (tonumber (app.store.get ('octave', 4)) or 4)
    local velocity = tonumber (app.store.get ('velocity', 100)) or 100
    local down = {} ---@type table<string, integer>

    ---@return boolean
    local function enabled ()
      return not settings or settings.get ('daw.computer_keyboard') ~= false
    end

    local item = status
      and status.add ({
        id = 'daw.keys',
        icon = 'keyboard',
        align = 'right',
        order = 5,
        tooltip = 'Computer keyboard: Z and X change the octave, C and V the velocity. Click to switch it off or on.',
        command = 'daw.computer_keyboard',
      })

    local function show ()
      if item then
        item.show (enabled ())
        item.set (daw.time.note_name ((octave + 1) * 12) .. ' · ' .. velocity)
      end
    end

    local function release_all ()
      for _, pitch in pairs (down) do
        engine.note_off ('', pitch)
      end
      down = {}
    end

    app.dom.on_global ('keydown', function (ev)
      if not enabled () or ev.ctrl or ev.alt or ev.meta or ev.composing then
        return nil
      end
      local code = ev.code or ''
      local focus = app.dom.focus_info ()
      if focus.editable or focus.owns_keys then
        return nil
      end
      local semitone = NOTES[code]
      if semitone then
        if not down[code] and not ev['repeat'] then
          local pitch =
            math.max (0, math.min (127, (octave + 1) * 12 + semitone))
          down[code] = pitch
          engine.note_on ('', pitch, velocity / 127)
        end
        return true
      end
      if ev['repeat'] then
        return nil
      end
      if code == 'KeyZ' or code == 'KeyX' then
        release_all ()
        octave =
          math.max (-1, math.min (8, octave + (code == 'KeyX' and 1 or -1)))
        app.store.set ('octave', octave)
        show ()
        return true
      elseif code == 'KeyC' or code == 'KeyV' then
        velocity = math.max (
          1,
          math.min (127, velocity + (code == 'KeyV' and 20 or -20))
        )
        app.store.set ('velocity', velocity)
        show ()
        return true
      end
      return nil
    end)

    app.dom.on_global ('keyup', function (ev)
      local pitch = down[ev.code or '']
      if pitch then
        down[ev.code or ''] = nil
        engine.note_off ('', pitch)
      end
      return nil
    end)

    -- Letting go of the window with a key down would leave its note ringing.
    app.dom.on_global ('blur', function ()
      release_all ()
      return nil
    end)

    commands.register ({
      id = 'daw.computer_keyboard',
      category = 'DAW',
      title = 'Computer Keyboard Plays Notes',
      icon = 'keyboard',
      menu = 'Options',
      run = function ()
        if settings then
          settings.set ('daw.computer_keyboard', not enabled ())
        end
        release_all ()
        show ()
      end,
    })

    if settings then
      settings.watch ('daw.computer_keyboard', show)
    end
    show ()
    app.dispose (release_all)
  end,
}
