-- Runs daw.engine against a stand-in app, session and page, and checks how devices' saved
-- states reach the engine and come back for a save.

---The daw service, from daw.core's own modules.
---@return Daw.Core
local function core ()
  local mods = {} ---@type table<string, any>
  ---@param name string
  ---@return any
  local function req (name)
    if mods[name] == nil then
      local path = 'plugins/daw.core/' .. name .. '.lua'
      -- daw.core's modules need the whole library, with their own require.
      -- selene: allow(global_usage)
      local env = setmetatable ({ require = req }, { __index = _G })
      mods[name] = assert (load (read (path), '@' .. path, 't', env)) ()
    end
    return mods[name]
  end
  return {
    song = req ('daw_song'),
    device = req ('daw_device'),
    resolve = req ('daw_resolve'),
  } --[[@as Daw.Core]]
end

---@class EngineRun
---@field daw Daw.Core
---@field posted table[] What the page was sent.
---@field say fun(m: table) A message from the page.
---@field change fun(song: Daw.Song, kind: string)
---@field tick fun() Runs the timers due now.
---@field capture fun(done: fun(states: table<string, string>?))?

---A synth on one track and a Web Audio Module effect, each with a state.
---@param daw Daw.Core
---@return Daw.Song
local function song_with_states (daw)
  local s = daw.song.add_track (daw.song.new ('T'), {
    instrument = {
      id = 'd1',
      device = 'test.synth',
      params = {},
      bypass = false,
      state = 'AAEC',
    },
    effects = {
      { id = 'd2', device = 'test.module', params = {}, bypass = false },
    },
  })
  return daw.song.set_states (s, { d2 = '{"preset":"Warm"}' })
end

---@return EngineRun
local function start ()
  local path = 'plugins/daw.engine/init.lua'
  local plugin = assert (load (read (path), '@' .. path)) () --[[@as Proteus.Plugin]]
  local daw = core ()
  local song = song_with_states (daw)
  local due = {} ---@type fun()[]
  local handlers = {} ---@type table<string, fun(...)>
  ---@type EngineRun
  local run = {
    daw = daw,
    posted = {},
    say = function () end,
    change = function () end,
    tick = function ()
      local now = due
      due = {}
      for _, fn in ipairs (now) do
        fn ()
      end
    end,
  }
  ---@type table<string, Daw.DeviceSpec>
  local specs = {
    ['test.synth'] = {
      id = 'test.synth',
      name = 'Synth',
      role = 'instrument',
      params = {},
      patch = {},
      native = { plugin = 'clap:test' },
    } --[[@as Daw.DeviceSpec]],
    ['test.module'] = {
      id = 'test.module',
      name = 'Module',
      role = 'effect',
      params = {},
      patch = {},
      owner = 'test.pack',
      wam = { path = 'wam/x.js' },
    } --[[@as Daw.DeviceSpec]],
  }
  ---An element that does nothing, but a web view keeps what it is sent.
  ---@return table
  local function el ()
    local e = {}
    function e:widget (method, msg)
      if method == 'post' then
        run.posted[#run.posted + 1] = msg
      end
    end
    function e:append () end
    function e:style () end
    function e:remove () end
    return e
  end
  local session = {
    song = function ()
      return song
    end,
    selected_track = function ()
      return nil
    end,
    capture = function (fn)
      run.capture = fn
    end,
  }
  local ui = {
    css = function () end,
    webview = function (opts)
      run.say = opts.on_message
      return el ()
    end,
    div = function ()
      return el ()
    end,
    mount = function () end,
  }
  local app = {
    use = function (name)
      if name == 'ui' then
        return ui
      elseif name == 'daw' then
        return daw
      elseif name == 'daw.devices' then
        return {
          get = function (id)
            return specs[id]
          end,
          list = function ()
            return { specs['test.synth'], specs['test.module'] }
          end,
        }
      elseif name == 'daw.session' then
        return session
      end
      return { register = function () end }
    end,
    try_use = function ()
      return nil
    end,
    provide = function () end,
    store = {
      get = function (_, default)
        return default
      end,
      set = function () end,
    },
    json = {
      encode = function (value)
        return value
      end,
    },
    timer = {
      after = function (_, fn)
        due[#due + 1] = fn
        return function () end
      end,
    },
    on = function (event, fn)
      handlers[event] = fn
    end,
    emit = function () end,
    dispose = function () end,
    warn = function () end,
  }
  plugin.activate (app --[[@as Proteus.App]])
  run.change = function (next_song, kind)
    song = next_song
    handlers['daw:changed'] (song, { kind = kind })
    run.tick ()
  end
  return run
end

---The posts since `from`, each as its type, and its device for set_state.
---@param run EngineRun
---@param from integer
---@return string[]
local function kinds (run, from)
  local out = {} ---@type string[]
  for i = from, #run.posted do
    local m = run.posted[i]
    if m.type == 'set_state' then
      out[#out + 1] = 'set_state ' .. m.device .. ' ' .. tostring (m.state)
    elseif m.type == 'load' then
      out[#out + 1] = 'load ' .. #m.song.tracks
    elseif m.type ~= 'live' and m.type ~= 'metronome' then
      out[#out + 1] = m.type
    end
  end
  table.sort (out)
  return out
end

test ('a ready engine gets each state before the song loads', function ()
  local run = start ()
  run.say ({ type = 'ready' })
  eq (kinds (run, 1), {
    'load 1',
    'set_state d1 AAEC',
    'set_state d2 {"preset":"Warm"}',
  })
  local last = run.posted[#run.posted]
  eq (last.type, 'load', 'the states go first')
end)

test ('an edit sends only the states the engine does not hold', function ()
  local run = start ()
  run.say ({ type = 'ready' })
  local from = #run.posted + 1
  local s = song_with_states (run.daw)
  -- An undo may bring back an older state: the engine keeps the one it plays.
  run.change (run.daw.song.set_states (s, { d1 = 'OLD' }), 'undo')
  eq (kinds (run, from), { 'load 1' })
  -- A device that leaves and comes back is sent again.
  from = #run.posted + 1
  run.change (run.daw.song.remove_device (s, 'd2'), 'edit')
  run.change (s, 'undo')
  eq (kinds (run, from), {
    'load 1',
    'load 1',
    'set_state d2 {"preset":"Warm"}',
  })
end)

test ('opening a song drops every device first', function ()
  local run = start ()
  run.say ({ type = 'ready' })
  local from = #run.posted + 1
  run.change (song_with_states (run.daw), 'open')
  local first = from
  while run.posted[first].type ~= 'load' do
    first = first + 1
  end
  eq (#run.posted[first].song.tracks, 0, 'an empty song first')
  eq (kinds (run, first + 1), {
    'load 1',
    'set_state d1 AAEC',
    'set_state d2 {"preset":"Warm"}',
  })
end)

test ('a save asks the engine, and takes text answers only', function ()
  local run = start ()
  run.say ({ type = 'ready' })
  local got = nil ---@type table<string, string>?
  assert (run.capture, 'the engine gives the session its capture') (
    function (states)
      got = states
    end
  )
  local ask = run.posted[#run.posted]
  eq (ask.type, 'get_states')
  run.say ({ type = 'states', id = 'other', states = { d1 = 'no' } })
  eq (got, nil, 'an answer to another question is not this one')
  run.say ({ type = 'states', id = ask.id, states = { d1 = 'BBBB', d2 = 5 } })
  eq (got, { d1 = 'BBBB' })
  -- Once the song keeps them, the engine is not sent them again.
  local from = #run.posted + 1
  run.change (
    run.daw.song.set_states (song_with_states (run.daw), { d1 = 'BBBB' }),
    'state'
  )
  eq (kinds (run, from), {})
end)
