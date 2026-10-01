-- Runs daw.engine on the native engine against a stand-in app, and plays it the messages the
-- app's engine says when it crashes and starts again.

---An object whose every method does nothing and returns another such object.
---@return table
local function anything ()
  return setmetatable ({}, {
    __index = function ()
      return function ()
        return anything ()
      end
    end,
  })
end

---@class EngineRun
---@field sent table[] Messages to the native engine.
---@field opened integer How many native engines it opened.
---@field say fun(m: table) Plays the newest engine a message.
---@field warned string[]
---@field events table[]
---@field commands table<string, fun()>

---@return EngineRun
local function start ()
  local path = 'plugins/daw.engine/init.lua'
  local plugin = assert (load (read (path), '@' .. path)) () --[[@as Proteus.Plugin]]
  ---@type EngineRun
  local run = {
    sent = {},
    opened = 0,
    say = function (_) end,
    warned = {},
    events = {},
    commands = {},
  }
  local song = { tracks = {} }
  local services = {
    ui = anything (),
    daw = {
      resolve = {
        song = function ()
          return { tempo = 120, tracks = {} }, {}
        end,
      },
    },
    ['daw.devices'] = {
      list = function ()
        return {}
      end,
    },
    ['daw.session'] = {
      song = function ()
        return song
      end,
      selected_track = function ()
        return 't1'
      end,
    },
    commands = {
      register = function (spec)
        run.commands[spec.id] = spec.run
      end,
    },
    settings = {
      define = function () end,
      get = function (key)
        return key == 'daw.engine' and 'native' or nil
      end,
    },
    notify = {
      warn = function (text)
        run.warned[#run.warned + 1] = text
      end,
    },
  }
  local app = {
    use = function (name)
      return assert (services[name], name)
    end,
    try_use = function (name)
      return services[name]
    end,
    on = function () end,
    emit = function (...)
      run.events[#run.events + 1] = { ... }
    end,
    provide = function () end,
    dispose = function () end,
    store = {
      get = function (_, default)
        return default
      end,
      set = function () end,
    },
    timer = {
      after = function (_, fn)
        fn ()
      end,
    },
    json = {
      encode = function ()
        return '{}'
      end,
    },
    audio = {
      open = function (on_message)
        run.opened = run.opened + 1
        run.say = on_message
        return {
          send = function (m)
            run.sent[#run.sent + 1] = m
          end,
          send_file = function () end,
          close = function () end,
        }
      end,
    },
  }
  plugin.activate (app --[[@as Proteus.App]])
  return run
end

---The types of the messages sent from `from` on.
---@param run EngineRun
---@param from integer
---@return string[]
local function types (run, from)
  local out = {} ---@type string[]
  for i = from, #run.sent do
    out[#out + 1] = run.sent[i].type
  end
  return out
end

local CRASHED = {
  type = 'crashed',
  reason = 'it crashed with signal 11 (a memory fault)',
  signal = 11,
  attempt = 1,
  wait = 0.5,
}

test ('the song goes to the native engine when it is ready', function ()
  local run = start ()
  eq (run.opened, 1)
  run.say ({ type = 'ready' })
  eq (types (run, 1), { 'metronome', 'live', 'load' })
end)

test (
  'a crashed engine gets the song again when it starts, and the user hears once why',
  function ()
    local run = start ()
    run.say ({ type = 'ready' })
    run.say ({ type = 'transport', playing = true, beat = 2 })
    local from = #run.sent + 1
    run.say (CRASHED)
    eq (run.warned, {
      'The native sound engine stopped: it crashed with signal 11 (a memory fault). It starts again and loads the song.',
    })
    eq (run.events[#run.events], { 'daw:transport', false, 2 }, 'it stopped')
    run.say ({ type = 'restarted', attempt = 1 })
    run.say ({ type = 'ready' })
    eq (types (run, from), { 'metronome', 'live', 'load' })
    eq (run.opened, 1, 'the app starts it again, not the DAW')
    local again = {} ---@type table<string, any>
    for k, v in pairs (CRASHED) do
      again[k] = v
    end
    again.attempt = 2
    run.say (again)
    eq (#run.warned, 1, 'crashes in a row warn once')
  end
)

test (
  'an engine that keeps crashing stops, and Restart the Sound Engine starts a new one',
  function ()
    local run = start ()
    run.say ({
      type = 'exit',
      crashed = true,
      reason = 'it ended with code 3',
      error = 'it ended with code 3. It crashed 4 times in 60 seconds, so it stays stopped',
    })
    eq (run.warned, {
      'The native sound engine stopped: it ended with code 3. It crashed 4 times in 60 seconds, so it stays stopped. Restart the Sound Engine starts it again.',
    })
    run.commands['daw.reload_engine'] ()
    eq (run.opened, 2)
    run.say ({ type = 'ready' })
    eq (run.sent[#run.sent].type, 'load')
  end
)
