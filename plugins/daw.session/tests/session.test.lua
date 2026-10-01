-- Runs daw.session against a stand-in app, and checks that a save first asks for what the
-- devices saved, and writes it with the song.

---The daw service, from daw.core's own modules.
---@return Daw.Core
local function core ()
  local mods = {} ---@type table<string, any>
  ---@param name string
  ---@return any
  local function req (name)
    if mods[name] == nil then
      local path = 'plugins/daw.core/' .. name .. '.lua'
      local env = setmetatable ({ require = req }, { __index = _G })
      mods[name] = assert (load (read (path), '@' .. path, 't', env)) ()
    end
    return mods[name]
  end
  return {
    song = req ('daw_song'),
    file = req ('daw_file'),
    history = req ('daw_history'),
    demo = req ('daw_demo'),
  } --[[@as Daw.Core]]
end

---@class SessionRun
---@field session Daw.Session
---@field daw Daw.Core
---@field written table<string, Daw.Song>
---@field changes string[]
---@field timers { ms: number, fn: fun(), cancelled: boolean }[]

---@return SessionRun
local function start ()
  local path = 'plugins/daw.session/init.lua'
  local plugin = assert (load (read (path), '@' .. path)) () --[[@as Proteus.Plugin]]
  local daw = core ()
  ---@type SessionRun
  local run = {
    session = nil --[[@as Daw.Session]],
    daw = daw,
    written = {},
    changes = {},
    timers = {},
  }
  local store = {} ---@type table<string, any>
  local app = {
    use = function (name)
      if name == 'daw' then
        return daw
      end
      return { register = function () end }
    end,
    try_use = function ()
      return nil
    end,
    provide = function (_, service)
      run.session = service
    end,
    store = {
      get = function (k, default)
        if store[k] == nil then
          return default
        end
        return store[k]
      end,
      set = function (k, v)
        store[k] = v
      end,
    },
    fs = {
      mkdir = function () end,
      write_json = function (target, value)
        run.written[target] = value
      end,
      read_json = function ()
        return nil
      end,
      exists = function (target)
        return run.written[target] ~= nil
      end,
      list = function ()
        return {}
      end,
    },
    timer = {
      after = function (ms, fn)
        local t = { ms = ms, fn = fn, cancelled = false }
        run.timers[#run.timers + 1] = t
        return function ()
          t.cancelled = true
        end
      end,
    },
    emit = function (event, _, change)
      if event == 'daw:changed' then
        run.changes[#run.changes + 1] = change.kind
      end
    end,
    dom = {
      focus_info = function ()
        return { editable = false }
      end,
    },
    util = {
      now = function ()
        return 0
      end,
    },
    dispose = function () end,
    warn = function () end,
  }
  plugin.activate (app --[[@as Proteus.App]])
  return run
end

---Runs the timers that wait `ms`, as if that long passed.
---@param run SessionRun
---@param ms number
local function pass (run, ms)
  for _, t in ipairs (run.timers) do
    if t.ms == ms and not t.cancelled then
      t.cancelled = true
      t.fn ()
    end
  end
end

---The demo song with one device that saved a state, opened as the session's song.
---@param run SessionRun
---@return string device id
local function with_device (run)
  local s = run.session.song ()
  local id = s.tracks[1].instrument.id
  run.session.apply (run.daw.song.set_param (s, id, 'cutoff', 500))
  return id
end

test ('a save writes what the engine says each device saved', function ()
  local run = start ()
  local asked = nil ---@type fun(states: table<string, string>?)?
  run.session.capture (function (done)
    asked = done
  end)
  local id = with_device (run)
  local saved = nil ---@type string?
  run.session.save (function (target)
    saved = target
  end)
  ok (asked, 'the save asks the engine')
  eq (saved, nil, 'and waits for its answer')
  assert (asked) ({ [id] = 'AAEC', nowhere = 'x' })
  eq (saved, 'songs/Demo.song.json')
  local file = run.written['songs/Demo.song.json']
  eq (file.format, 2)
  eq (run.daw.song.states (file), { [id] = 'AAEC' })
  eq (
    run.daw.song.states (run.session.song ()),
    { [id] = 'AAEC' },
    'the open song keeps it'
  )
  eq (run.changes[#run.changes], 'state')
  ok (not run.session.dirty ())
  ok (not run.session.can_redo ())
  run.session.undo ()
  eq (
    run.daw.song.states (run.session.song ()),
    {},
    'keeping states was no undo step'
  )
end)

test (
  'a save the engine does not answer keeps the states the song had',
  function ()
    local run = start ()
    run.session.capture (function () end)
    with_device (run)
    local saved = nil ---@type string?
    run.session.save (function (target)
      saved = target
    end)
    eq (saved, nil)
    pass (run, 3000)
    eq (saved, 'songs/Demo.song.json')
    eq (run.daw.song.states (run.written['songs/Demo.song.json']), {})
  end
)

test ('an edit while the engine answers leaves the song unsaved', function ()
  local run = start ()
  local asked = nil ---@type fun(states: table<string, string>?)?
  run.session.capture (function (done)
    asked = done
  end)
  local id = with_device (run)
  run.session.save ()
  run.session.apply (
    run.daw.song.set_param (run.session.song (), id, 'cutoff', 700)
  )
  assert (asked) ({ [id] = 'AAEC' })
  ok (run.session.dirty (), 'the file has the song from before the edit')
  eq (run.daw.song.states (run.session.song ()), { [id] = 'AAEC' })
end)

test ('opening another song saves the one that goes with its states', function ()
  local run = start ()
  local asked = nil ---@type fun(states: table<string, string>?)?
  run.session.capture (function (done)
    asked = done
  end)
  local id = with_device (run)
  run.session.new ()
  assert (asked) ({ [id] = 'AAEC' })
  eq (
    run.daw.song.states (run.written['songs/Demo.song.json']),
    { [id] = 'AAEC' }
  )
  eq (
    run.daw.song.states (run.session.song ()),
    {},
    'the new song gets none of them'
  )
end)
