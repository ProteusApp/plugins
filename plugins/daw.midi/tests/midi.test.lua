-- Runs daw.midi against a stand-in app and engine, and plays it messages as the app's MIDI
-- input would deliver them.

---@return { calls: string[], send: fun(m: table), commands: table<string, fun()> }
local function start ()
  local path = 'plugins/daw.midi/init.lua'
  local plugin = assert (load (read (path), '@' .. path)) () --[[@as Proteus.Plugin]]
  local calls = {} ---@type string[]
  local handler = nil ---@type fun(m: table)?
  local commands = {} ---@type table<string, fun()>
  local engine = {
    note_on = function (track, note, velocity)
      calls[#calls + 1] = string.format ('on %s %d %.2f', track, note, velocity)
    end,
    note_off = function (track, note)
      calls[#calls + 1] = string.format ('off %s %d', track, note)
    end,
    all_notes_off = function ()
      calls[#calls + 1] = 'all off'
    end,
  }
  local app = {
    use = function (name)
      if name == 'daw.engine' then
        return engine
      end
      return {
        register = function (spec)
          commands[spec.id] = spec.run
        end,
      }
    end,
    try_use = function ()
      return nil
    end,
    midi = {
      listen = function (fn)
        handler = fn
        return { close = function () end }
      end,
      inputs = function (cb)
        cb ({})
      end,
    },
  }
  plugin.activate (app --[[@as Proteus.App]])
  return {
    calls = calls,
    send = function (m)
      assert (handler, 'it listens') (m)
    end,
    commands = commands,
  }
end

test ('a key plays and stops a note on the live track', function ()
  local s = start ()
  s.send ({ type = 'note_on', channel = 1, note = 60, velocity = 127 })
  s.send ({ type = 'note_off', channel = 1, note = 60, velocity = 0 })
  eq (s.calls, { 'on  60 1.00', 'off  60' })
end)

test ('the sustain pedal holds notes until it lifts', function ()
  local s = start ()
  s.send ({ type = 'controller', channel = 1, controller = 64, value = 127 })
  s.send ({ type = 'note_on', channel = 1, note = 62, velocity = 64 })
  s.send ({ type = 'note_off', channel = 1, note = 62, velocity = 0 })
  eq (#s.calls, 1, 'the note keeps sounding')
  s.send ({ type = 'controller', channel = 1, controller = 64, value = 0 })
  eq (s.calls[2], 'off  62')
end)

test (
  'a key played again under the pedal is not stopped when the pedal lifts',
  function ()
    local s = start ()
    s.send ({ type = 'controller', channel = 1, controller = 64, value = 127 })
    s.send ({ type = 'note_on', channel = 1, note = 64, velocity = 100 })
    s.send ({ type = 'note_off', channel = 1, note = 64, velocity = 0 })
    s.send ({ type = 'note_on', channel = 1, note = 64, velocity = 100 })
    s.send ({ type = 'controller', channel = 1, controller = 64, value = 0 })
    eq (#s.calls, 2, 'two note ons, and no note off')
  end
)

test ('all notes off stops everything', function ()
  local s = start ()
  s.send ({ type = 'controller', channel = 1, controller = 123, value = 0 })
  eq (s.calls, { 'all off' })
end)

test ('other messages play nothing', function ()
  local s = start ()
  s.send ({ type = 'pitch_bend', channel = 1, value = 100 })
  s.send ({ type = 'program', channel = 1, value = 3 })
  eq (s.calls, {})
  ok (s.commands['daw.midi_reconnect'] ~= nil, 'it has a reconnect command')
end)
