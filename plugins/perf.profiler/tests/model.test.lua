local model = require ('perf_model') --[[@as Profiler.ModelModule]]

---A kernel reading at `now` milliseconds, with each plugin's self time and calls so far.
---@param now number
---@param plugins table<string, { self: number, calls: integer, kinds?: table<string, Proteus.PerfKind>, errors?: integer, start?: number }>
---@param extra? { busy?: number, events?: table<string, Proteus.PerfEvent>, since?: number, lua_kb?: number }
---@return Proteus.PerfStats
local function reading (now, plugins, extra)
  local out = {} ---@type table<string, Proteus.PerfPlugin>
  local busy = 0
  for id, p in pairs (plugins) do
    busy = busy + p.self
    out[id] = {
      calls = p.calls,
      self = p.self,
      total = p.self,
      max = 0,
      errors = p.errors or 0,
      start = p.start,
      kinds = p.kinds
        or {
          timer = { calls = p.calls, self = p.self, total = p.self, max = 0 },
        },
    }
  end
  extra = extra or {}
  return {
    since = extra.since or 0,
    now = now,
    busy = extra.busy or busy,
    plugins = out,
    events = extra.events or {},
    lua_kb = extra.lua_kb or 1024,
  }
end

---@param seq integer
---@param at number
---@param ms number
---@param parts Proteus.PerfPart[]
---@return Proteus.PerfTask
local function task (seq, at, ms, parts)
  return {
    seq = seq,
    at = at,
    ms = ms,
    owner = parts[1].owner,
    what = parts[1].what,
    parts = parts,
  }
end

test (
  'a window is the difference between the newest reading and an older one',
  function ()
    local state = model.new ()
    model.add (state, reading (1000, { a = { self = 100, calls = 10 } }))
    model.add (
      state,
      reading (
        6000,
        { a = { self = 150, calls = 20 }, b = { self = 5, calls = 1 } }
      )
    )
    model.add (
      state,
      reading (
        11000,
        { a = { self = 400, calls = 30 }, b = { self = 105, calls = 3 } }
      )
    )
    local win = assert (model.window (state, 10))
    eq (win.wall, 10000)
    eq (win.busy, 405)
    eq (win.rows[1].id, 'a')
    eq (win.rows[1].self, 300)
    eq (win.rows[1].calls, 20)
    eq (win.rows[1].share, 0.03)
    eq (win.rows[2].self, 105)
    local short = assert (model.window (state, 5))
    eq (short.wall, 5000)
    eq (short.rows[1].self, 250)
  end
)

test ('a window longer than the readings starts from the oldest one', function ()
  local state = model.new ()
  model.add (state, reading (1000, { a = { self = 10, calls = 1 } }))
  model.add (state, reading (2000, { a = { self = 30, calls = 2 } }))
  local win = assert (model.window (state, 60))
  eq (win.wall, 1000)
  eq (win.rows[1].self, 20)
  local all = assert (model.window (state, nil))
  eq (all.wall, 2000)
  eq (all.rows[1].self, 30)
end)

test ('a reset in the kernel starts the readings over', function ()
  local state = model.new ()
  model.add (state, reading (1000, { a = { self = 10, calls = 1 } }))
  model.add (
    state,
    reading (2000, { a = { self = 2, calls = 1 } }, { since = 1500 })
  )
  eq (#state.samples, 1)
  local win = assert (model.window (state, nil))
  eq (win.wall, 500)
end)

test ('a stall is split into plugin code and the browser', function ()
  local state = model.new ()
  model.add (state, reading (0, {}), {
    task (1, 1180, 120, {
      { owner = 'git', what = "handler for 'fs:changed'", ms = 100 },
      { owner = 'tree', what = 'click handler', ms = 20 },
    }),
  }, {
    seconds = {},
    gaps = { { seq = 1, at = 1000, ms = 300 } },
    long_tasks = {},
    long_task_support = true,
  })
  local stalls = model.stalls (state, 0)
  eq (#stalls, 1)
  local s = stalls[1]
  eq (s.at, 1000)
  eq (s.ms, 300)
  eq (s.lua, 120)
  eq (s.browser, 180)
  eq (s.parts[1].owner, 'git')
  eq (
    s.cause,
    'Mostly the browser laying out and painting the page. git ran for 100 ms of it, in its handler for fs:changed'
  )
end)

test ('a slow plugin task is a stall even with no frames watched', function ()
  local state = model.new ()
  model.add (state, reading (0, {}), {
    task (
      1,
      5000,
      400,
      { { owner = 'search', what = 'input handler', ms = 400 } }
    ),
    task (
      2,
      6000,
      10,
      { { owner = 'search', what = 'input handler', ms = 10 } }
    ),
  })
  local stalls = model.stalls (state, 0)
  eq (#stalls, 1)
  eq (stalls[1].cause, 'search, in its input handler')
  eq (stalls[1].browser, 0)
end)

test ('overlapping stalls join into one', function ()
  local state = model.new ()
  model.add (state, reading (0, {}), {}, {
    seconds = {},
    gaps = { { seq = 1, at = 1000, ms = 100 } },
    long_tasks = { { seq = 2, at = 1050, ms = 200 } },
    long_task_support = true,
  })
  local stalls = model.stalls (state, 0)
  eq (#stalls, 1)
  eq (stalls[1].ms, 250)
  ok (stalls[1].cause:find ('outside plugin code', 1, true))
end)

test ('the busiest plugins keep their timeline color', function ()
  local state = model.new ()
  model.add (
    state,
    reading (0, { a = { self = 0, calls = 0 }, b = { self = 0, calls = 0 } })
  )
  model.add (
    state,
    reading (
      1000,
      { a = { self = 50, calls = 1 }, b = { self = 10, calls = 1 } }
    )
  )
  local bars = model.timeline (state)
  eq (#bars, 1)
  eq (state.slots, { a = 1, b = 2 })
  -- b overtakes a, and both keep their colors.
  model.add (
    state,
    reading (
      2000,
      { a = { self = 60, calls = 2 }, b = { self = 200, calls = 2 } }
    )
  )
  model.timeline (state)
  eq (state.slots, { a = 1, b = 2 })
  eq (model.legend (state), { 'a', 'b' })
end)

test ('plugins past the colored ones share the gray part of a bar', function ()
  local state = model.new ()
  local before, after = {}, {}
  for i = 1, model.SLOTS + 2 do
    before['p' .. i] = { self = 0, calls = 0 }
    after['p' .. i] = { self = 100 - i, calls = 1 }
  end
  model.add (state, reading (0, before))
  model.add (state, reading (1000, after))
  local bar = model.timeline (state)[1]
  eq (#bar.parts, model.SLOTS + 1)
  local rest = bar.parts[#bar.parts]
  eq (rest.slot, 0)
  eq (rest.ms, (100 - 6) + (100 - 7))
end)

test ('describe says what a kind of callback is', function ()
  eq (model.describe ("handler for 'fs:changed'"), 'its handler for fs:changed')
  eq (model.describe ('click handler'), 'its click handler')
  eq (model.describe ('timer'), 'its timer')
  eq (model.describe ("command 'file.save'"), 'the command file.save')
  eq (
    model.describe ("command 'file.save' check"),
    'checking whether the command file.save can run'
  )
  eq (model.describe ('start'), 'starting up')
  eq (model.describe ('code on_change'), 'code on_change')
end)

test ('escape makes text safe to put in HTML', function ()
  eq (
    model.escape ([[<a href="x">'&'</a>]]),
    '&lt;a href=&quot;x&quot;&gt;&#39;&amp;&#39;&lt;/a&gt;'
  )
  eq (model.escape (12), '12')
end)

test ('numbers read the way people say them', function ()
  eq (model.ms (0.42), '0.4 ms')
  eq (model.ms (12.4), '12 ms')
  eq (model.ms (1234), '1.2 s')
  eq (model.ms (0), '0 ms')
  eq (model.percent (0.004), '<1%')
  eq (model.percent (0.256), '26%')
  eq (model.count (12400), '12,400')
  eq (model.count (999), '999')
  eq (model.count (-1234), '-1,234')
  eq (model.clock (3723000), '01:02:03')
  eq (model.clock (0, -5), '19:00:00')
end)

test ('findings name the busiest plugin and why, worst first', function ()
  local state = model.new ()
  model.add (state, reading (0, { git = { self = 0, calls = 0 } }))
  model.add (
    state,
    reading (10000, {
      git = {
        self = 4000,
        calls = 800,
        errors = 2,
        kinds = {
          ["handler for 'fs:changed'"] = {
            calls = 800,
            self = 4000,
            total = 4000,
            max = 9,
          },
        },
      },
    }, { events = { ['fs:changed'] = { sent = 800, ms = 4000 } } })
  )
  local win = assert (model.window (state, 10))
  local found = model.findings (win, {}, {
    total = 30000,
    plugins = { tree = { nodes = 25000, widgets = 0 } },
  }, 58)
  local texts = {} ---@type string[]
  for _, f in ipairs (found) do
    texts[#texts + 1] = f.level .. ': ' .. f.text
  end
  eq (texts, {
    'high: git used 40% of the time, mostly in its handler for fs:changed: 800 calls at 5.0 ms each.',
    'high: tree has 25,000 elements on the page. A large page is slow to lay out and repaint.',
    'medium: Plugin code kept the window busy 40% of the time. Clicks and keys wait while it runs.',
    'medium: git raised 2 errors. The Console shows them.',
    'medium: The event fs:changed was sent 80 times a second, and its listeners took 4.0 s.',
  })
end)

test ('findings say so when nothing stands out', function ()
  local state = model.new ()
  model.add (state, reading (0, { a = { self = 0, calls = 0 } }))
  model.add (state, reading (10000, { a = { self = 20, calls = 4 } }))
  local found = model.findings (assert (model.window (state, 10)), {}, nil, 60)
  eq (#found, 1)
  eq (found[1].level, 'info')
  ok (found[1].text:find ('Nothing stands out', 1, true))
end)

test ('the report lists findings, plugins and stalls', function ()
  local state = model.new ()
  model.add (state, reading (0, { a = { self = 0, calls = 0 } }))
  model.add (state, reading (10000, { a = { self = 20, calls = 4 } }))
  local win = assert (model.window (state, 10))
  local text = model.report (win, {
    {
      at = 5000,
      ms = 120,
      lua = 120,
      browser = 0,
      parts = {},
      cause = 'a, in its timer',
    },
  }, model.findings (win, {}, nil, 60))
  ok (text:find ('| a | <1% | 20 ms | 4 | 0 |  | timer |', 1, true), text)
  ok (text:find ('- 00:00:05, 120 ms: a, in its timer', 1, true), text)
end)

test ('a stall finds the tasks inside it among many', function ()
  local state = model.new ()
  local tasks = {} ---@type Proteus.PerfTask[]
  for i = 1, 200 do
    tasks[#tasks + 1] =
      task (i, i * 100, 5, { { owner = 'noise', what = 'timer', ms = 5 } })
  end
  -- Starts before the stall and ends inside it.
  tasks[#tasks + 1] =
    task (201, 20100, 40, { { owner = 'early', what = 'timer', ms = 40 } })
  -- Starts inside the stall and ends after it.
  tasks[#tasks + 1] =
    task (202, 20400, 300, { { owner = 'late', what = 'timer', ms = 300 } })
  model.add (state, reading (0, {}), tasks, {
    seconds = {},
    gaps = { { seq = 1, at = 20080, ms = 200 } },
    long_tasks = {},
    long_task_support = true,
  })
  local stalls = model.stalls (state, 0)
  eq (#stalls, 1)
  local owners = {} ---@type table<string, number>
  for _, part in ipairs (stalls[1].parts) do
    owners[part.owner] = math.floor (part.ms + 0.5)
  end
  -- The late task is a stall of its own, so the two join, from 20080 to 20400. The early task
  -- began at 20060, so 25 ms of it fall inside, with the 5 ms of slack.
  eq (stalls[1].ms, 320)
  eq (owners, { early = 25, late = 300 })
end)
