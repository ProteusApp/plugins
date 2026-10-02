-- perf.profiler's numbers. The plugin reads app.kernel.perf once a second, and this module
-- turns those readings into what the panel shows: each plugin's share of a stretch of time,
-- a timeline, the stalls with their causes, and findings in plain words. It draws nothing,
-- so the tests reach all of it.
--
-- The kernel counts from the moment the app starts. A window over the last 10 seconds is the
-- difference between the newest reading and the one 10 seconds older.

---@class Profiler.Sample
---@field at number When it was read, in milliseconds since 1970.
---@field stats Proteus.PerfStats
---@field by? table<string, number> Each plugin's self time since the reading before, worked out once when it arrives. Nil for the first.
---@field busy? number Plugin code since the reading before.

---@class Profiler.State
---@field since? number The kernel's `since` the samples count from. A reset changes it.
---@field samples Profiler.Sample[] Oldest first, one a second.
---@field tasks Proteus.PerfTask[] Slow tasks, oldest first.
---@field gaps Proteus.PerfMoment[] Times the page drew nothing for 50 ms or more.
---@field long_tasks Proteus.PerfMoment[] Long tasks the browser reported.
---@field seconds Proteus.PerfSecond[] Frames drawn in each of the last 60 seconds.
---@field long_task_support boolean
---@field task_seq integer The last task read.
---@field frame_seq integer The last stall or long task read.
---@field slots table<string, integer> The chart color each plugin has, so it keeps it.

---@class Profiler.KindRow
---@field what string
---@field calls integer
---@field self number
---@field total number

---@class Profiler.Row
---@field id string
---@field calls integer
---@field self number Milliseconds of its own code.
---@field total number
---@field errors integer
---@field share number Its self time as a share of the window, from 0 to 1.
---@field longest? number Its longest share of one slow task in the window.
---@field load? number
---@field start? number
---@field kinds Profiler.KindRow[] Longest self time first.

---@class Profiler.EventRow
---@field name string
---@field sent integer
---@field ms number
---@field rate number Times a second.

---@class Profiler.Window
---@field seconds? number The length asked for, or nil for everything since counting started.
---@field from number
---@field to number
---@field wall number Milliseconds covered.
---@field busy number Milliseconds of plugin code.
---@field rows Profiler.Row[] Longest self time first.
---@field events Profiler.EventRow[] Longest listener time first.
---@field lua_kb number
---@field lua_growth_kb number
---@field js_kb? number

---@class Profiler.BarPart
---@field id string A plugin id, or `''` for the rest.
---@field ms number
---@field slot integer Its color, from 1, or 0 for the rest.

---@class Profiler.Bar
---@field at number The end of the second.
---@field ms number
---@field parts Profiler.BarPart[]
---@field stall boolean True when a stall touched this second.

---@class Profiler.Stall
---@field at number When it started, in milliseconds since 1970.
---@field ms number
---@field lua number Milliseconds of plugin code inside it.
---@field browser number The rest: the browser's own work.
---@field parts Proteus.PerfPart[] Each plugin's share, longest first.
---@field cause string

---@class Profiler.Finding
---@field level 'high'|'medium'|'info'
---@field plugin? string
---@field text string

---@class Profiler.ModelModule
local M = {}

M.KEEP_SAMPLES = 61
M.KEEP_TASKS = 500
M.KEEP_MOMENTS = 300
-- A pause this long is one the user feels.
M.STALL_MS = 50
-- How many plugins get a color of their own on the timeline. The rest share a gray.
M.SLOTS = 5
-- How far apart the kernel's clock and the browser's frame clock may read.
local SLACK_MS = 5

---@return Profiler.State
function M.new ()
  return {
    samples = {},
    tasks = {},
    gaps = {},
    long_tasks = {},
    seconds = {},
    long_task_support = false,
    task_seq = 0,
    frame_seq = 0,
    slots = {},
  }
end

---@param list any[]
---@param keep integer
local function trim (list, keep)
  local extra = #list - keep
  if extra <= 0 then
    return
  end
  local n = #list
  for i = 1, n - extra do
    list[i] = list[i + extra]
  end
  for i = n - extra + 1, n do
    list[i] = nil
  end
end

---Adds a reading. When the kernel started counting again, everything read before goes.
---@param state Profiler.State
---@param stats Proteus.PerfStats
---@param tasks? Proteus.PerfTask[] New slow tasks.
---@param frames? Proteus.PerfFrames New stalls and long tasks, and the frame counts.
function M.add (state, stats, tasks, frames)
  if stats.since ~= state.since then
    state.since = stats.since
    state.samples, state.tasks, state.gaps, state.long_tasks = {}, {}, {}, {}
  end
  local prev = state.samples[#state.samples]
  local sample = { at = stats.now, stats = stats } ---@type Profiler.Sample
  if prev then
    local by = {} ---@type table<string, number>
    for id, p in pairs (stats.plugins) do
      local old = prev.stats.plugins[id]
      local ms = p.self - (old and old.self or 0)
      if ms > 0 then
        by[id] = ms
      end
    end
    sample.by, sample.busy = by, stats.busy - prev.stats.busy
  end
  state.samples[#state.samples + 1] = sample
  trim (state.samples, M.KEEP_SAMPLES)
  for _, t in ipairs (tasks or {}) do
    state.tasks[#state.tasks + 1] = t
    state.task_seq = math.max (state.task_seq, t.seq)
  end
  trim (state.tasks, M.KEEP_TASKS)
  if frames then
    for _, g in ipairs (frames.gaps or {}) do
      state.gaps[#state.gaps + 1] = g
      state.frame_seq = math.max (state.frame_seq, g.seq)
    end
    for _, t in ipairs (frames.long_tasks or {}) do
      state.long_tasks[#state.long_tasks + 1] = t
      state.frame_seq = math.max (state.frame_seq, t.seq)
    end
    trim (state.gaps, M.KEEP_MOMENTS)
    trim (state.long_tasks, M.KEEP_MOMENTS)
    state.seconds = frames.seconds or state.seconds
    state.long_task_support = frames.long_task_support == true
  end
end

---@param n number?
---@return number
local function num (n)
  return n or 0
end

---The reading a window starts from: the newest one at least `seconds` older than the last,
---or the oldest kept when none is that old. Nil means from when counting started.
---@param state Profiler.State
---@param seconds? number
---@return Profiler.Sample?
local function base_of (state, seconds)
  if not seconds then
    return nil
  end
  local last = state.samples[#state.samples]
  local want = last.at - seconds * 1000
  local base = state.samples[1]
  for _, s in ipairs (state.samples) do
    if s.at <= want then
      base = s
    end
  end
  return base
end

---Everything that happened in the last `seconds`, or since counting started when nil.
---@param state Profiler.State
---@param seconds? number
---@return Profiler.Window?
function M.window (state, seconds)
  local last = state.samples[#state.samples]
  if not last then
    return nil
  end
  local base = base_of (state, seconds)
  local now = last.stats
  local before = base and base.stats or nil
  local from = before and before.now or now.since
  local wall = math.max (0, now.now - from)

  -- The longest share of one slow task each plugin had in the window.
  local longest = {} ---@type table<string, number>
  for _, t in ipairs (state.tasks) do
    if t.at > from then
      for _, part in ipairs (t.parts) do
        if part.ms > (longest[part.owner] or 0) then
          longest[part.owner] = part.ms
        end
      end
    end
  end

  local rows = {} ---@type Profiler.Row[]
  for id, p in pairs (now.plugins) do
    local old = before and before.plugins[id] or nil
    local calls = p.calls - num (old and old.calls)
    local errors = p.errors - num (old and old.errors)
    if calls > 0 or errors > 0 or (not seconds and (p.load or p.start)) then
      local kinds = {} ---@type Profiler.KindRow[]
      for what, k in pairs (p.kinds) do
        local was = old and old.kinds[what] or nil
        local kcalls = k.calls - num (was and was.calls)
        if kcalls > 0 then
          kinds[#kinds + 1] = {
            what = what,
            calls = kcalls,
            self = k.self - num (was and was.self),
            total = k.total - num (was and was.total),
          }
        end
      end
      table.sort (kinds, function (a, b)
        if a.self ~= b.self then
          return a.self > b.self
        end
        return a.what < b.what
      end)
      local self_ms = p.self - num (old and old.self)
      rows[#rows + 1] = {
        id = id,
        calls = calls,
        self = self_ms,
        total = p.total - num (old and old.total),
        errors = errors,
        share = wall > 0 and self_ms / wall or 0,
        longest = longest[id],
        load = p.load,
        start = p.start,
        kinds = kinds,
      }
    end
  end
  table.sort (rows, function (a, b)
    if a.self ~= b.self then
      return a.self > b.self
    end
    return a.id < b.id
  end)

  local events = {} ---@type Profiler.EventRow[]
  for name, ev in pairs (now.events) do
    local old = before and before.events[name] or nil
    local sent = ev.sent - num (old and old.sent)
    if sent > 0 then
      events[#events + 1] = {
        name = name,
        sent = sent,
        ms = ev.ms - num (old and old.ms),
        rate = wall > 0 and sent / (wall / 1000) or 0,
      }
    end
  end
  table.sort (events, function (a, b)
    if a.ms ~= b.ms then
      return a.ms > b.ms
    end
    return a.sent > b.sent
  end)

  return {
    seconds = seconds,
    from = from,
    to = now.now,
    wall = wall,
    busy = now.busy - num (before and before.busy),
    rows = rows,
    events = events,
    lua_kb = now.lua_kb,
    lua_growth_kb = before and (now.lua_kb - before.lua_kb) or 0,
    js_kb = now.js_kb,
  }
end

---Gives the busiest plugins a color each. A plugin keeps its color while it stays among the
---busiest, so the chart does not repaint it when the order changes.
---@param state Profiler.State
---@param busiest string[] Busiest first.
local function assign_slots (state, busiest)
  local top = {} ---@type table<string, true>
  for i = 1, math.min (M.SLOTS, #busiest) do
    top[busiest[i]] = true
  end
  local used = {} ---@type table<integer, true>
  for id, slot in pairs (state.slots) do
    if top[id] then
      used[slot] = true
    else
      state.slots[id] = nil
    end
  end
  for i = 1, math.min (M.SLOTS, #busiest) do
    local id = busiest[i]
    if not state.slots[id] then
      for slot = 1, M.SLOTS do
        if not used[slot] then
          used[slot] = true
          state.slots[id] = slot
          break
        end
      end
    end
  end
end

---One bar for each second between readings: the time of plugin code in it, by plugin.
---@param state Profiler.State
---@param stalls? Profiler.Stall[] Every stall kept, when the caller has them already.
---@return Profiler.Bar[]
function M.timeline (state, stalls)
  local bars = {} ---@type Profiler.Bar[]
  local sums = {} ---@type table<string, number>
  local per = {} ---@type table<string, number>[]
  for _, sample in ipairs (state.samples) do
    local by = sample.by
    if by then
      for id, ms in pairs (by) do
        sums[id] = (sums[id] or 0) + ms
      end
      per[#per + 1] = by
      bars[#bars + 1] =
        { at = sample.at, ms = sample.busy or 0, parts = {}, stall = false }
    end
  end
  local busiest = {} ---@type string[]
  for id in pairs (sums) do
    busiest[#busiest + 1] = id
  end
  table.sort (busiest, function (x, y)
    if sums[x] ~= sums[y] then
      return sums[x] > sums[y]
    end
    return x < y
  end)
  assign_slots (state, busiest)
  for i, bar in ipairs (bars) do
    local rest = 0
    local parts = {} ---@type Profiler.BarPart[]
    for id, ms in pairs (per[i]) do
      local slot = state.slots[id]
      if slot then
        parts[#parts + 1] = { id = id, ms = ms, slot = slot }
      else
        rest = rest + ms
      end
    end
    table.sort (parts, function (x, y)
      return x.slot < y.slot
    end)
    if rest > 0 then
      parts[#parts + 1] = { id = '', ms = rest, slot = 0 }
    end
    bar.parts = parts
  end
  for _, stall in ipairs (stalls or M.stalls (state, 0)) do
    for _, bar in ipairs (bars) do
      if stall.at < bar.at and stall.at + stall.ms > bar.at - 1000 then
        bar.stall = true
      end
    end
  end
  return bars
end

---The plugin in front of a chart color: slot 1 to SLOTS.
---@param state Profiler.State
---@return table<integer, string>
function M.legend (state)
  local out = {} ---@type table<integer, string>
  for id, slot in pairs (state.slots) do
    out[slot] = id
  end
  return out
end

---What a kind of callback is, in words, such as `its handler for fs:changed`.
---@param what string
---@return string
function M.describe (what)
  local event = what:match ("^handler for '(.*)'$")
  if event then
    return 'its handler for ' .. event
  end
  local checked = what:match ("^command '(.*)' check$")
  if checked then
    return 'checking whether the command ' .. checked .. ' can run'
  end
  local command = what:match ("^command '(.*)'$")
  if command then
    return 'the command ' .. command
  end
  if what == 'timer' then
    return 'its timer'
  elseif what == 'call' then
    return 'code it ran with app.try'
  elseif what == 'start' then
    return 'starting up'
  elseif what == 'load' then
    return 'loading its code'
  elseif what == 'cleanup' then
    return 'cleaning up'
  elseif what == 'deactivate' then
    return 'stopping'
  elseif what:match ('^%a+ handler$') then
    return 'its ' .. what
  end
  return what
end

---@type table<string, string>
local ENTITIES = {
  ['&'] = '&amp;',
  ['<'] = '&lt;',
  ['>'] = '&gt;',
  ['"'] = '&quot;',
  ["'"] = '&#39;',
}

---Text made safe to put in HTML, in Lua. The panel escapes hundreds of strings a second, and
---`ui.escape` crosses into JavaScript for each one.
---@param text any
---@return string
function M.escape (text)
  return (tostring (text):gsub ('[&<>"\']', ENTITIES))
end

---@param ms number
---@return string
function M.ms (ms)
  if ms >= 10000 then
    return string.format ('%.0f s', ms / 1000)
  elseif ms >= 1000 then
    return string.format ('%.1f s', ms / 1000)
  elseif ms >= 10 then
    return string.format ('%.0f ms', ms)
  elseif ms >= 0.05 then
    return string.format ('%.1f ms', ms)
  end
  return '0 ms'
end

---@param share number From 0 to 1.
---@return string
function M.percent (share)
  local p = share * 100
  if p > 0 and p < 1 then
    return '<1%'
  end
  return string.format ('%.0f%%', p)
end

---A whole number with commas, such as `12,400`.
---@param n number
---@return string
function M.count (n)
  local s = string.format ('%d', math.floor (n + 0.5))
  local out = s:reverse ():gsub ('(%d%d%d)', '%1,'):reverse ()
  return (out:gsub ('^,', ''):gsub ('^%-,', '-'))
end

---The time of day of a moment, such as `14:03:22`, in the time zone `offset` hours from UTC.
---@param at number Milliseconds since 1970.
---@param offset? number Hours.
---@return string
function M.clock (at, offset)
  local secs = math.floor (at / 1000 + (offset or 0) * 3600) % 86400
  return string.format (
    '%02d:%02d:%02d',
    math.floor (secs / 3600),
    math.floor ((secs % 3600) / 60),
    secs % 60
  )
end

---Folds the parts of the tasks inside a stall into one list per plugin and kind.
---@param into table<string, Proteus.PerfPart>
---@param task Proteus.PerfTask
---@param share number How much of the task fell inside the stall, from 0 to 1.
local function add_parts (into, task, share)
  for _, part in ipairs (task.parts) do
    local key = part.owner .. '\0' .. part.what
    local p = into[key]
    if not p then
      p = { owner = part.owner, what = part.what, ms = 0 }
      into[key] = p
    end
    p.ms = p.ms + part.ms * share
  end
end

---The times the window froze since `from`, oldest first. A stall is a gap between frames, a
---long task the browser reported, or a plugin task that ran 50 ms or more, with the ones that
---overlap joined. Each says how much of it was plugin code, whose, and what was left over for
---the browser's own work, such as laying out the page.
---@param state Profiler.State
---@param from number Milliseconds since 1970.
---@return Profiler.Stall[]
function M.stalls (state, from)
  ---@type { a: number, b: number }[]
  local spans = {}
  for _, list in ipairs ({ state.gaps, state.long_tasks }) do
    for _, m in ipairs (list) do
      if m.ms >= M.STALL_MS and m.at + m.ms > from then
        spans[#spans + 1] = { a = m.at, b = m.at + m.ms }
      end
    end
  end
  for _, t in ipairs (state.tasks) do
    if t.ms >= M.STALL_MS and t.at > from then
      spans[#spans + 1] = { a = t.at - t.ms, b = t.at }
    end
  end
  table.sort (spans, function (x, y)
    return x.a < y.a
  end)
  local joined = {} ---@type { a: number, b: number }[]
  for _, s in ipairs (spans) do
    local prev = joined[#joined]
    if prev and s.a <= prev.b + SLACK_MS then
      prev.b = math.max (prev.b, s.b)
    else
      joined[#joined + 1] = { a = s.a, b = s.b }
    end
  end

  -- Tasks arrive in the order they ended, so the ones inside a stall sit together: from the
  -- first that ended after it began, to the last that began before it ended.
  local tasks = state.tasks
  local longest = 0
  for _, t in ipairs (tasks) do
    longest = math.max (longest, t.ms)
  end
  local out = {} ---@type Profiler.Stall[]
  for _, s in ipairs (joined) do
    local ms = s.b - s.a
    local lua = 0
    local by = {} ---@type table<string, Proteus.PerfPart>
    local lo, hi = 1, #tasks + 1
    while lo < hi do
      local mid = math.floor ((lo + hi) / 2)
      if tasks[mid].at > s.a - SLACK_MS then
        hi = mid
      else
        lo = mid + 1
      end
    end
    for i = lo, #tasks do
      local t = tasks[i]
      if t.at > s.b + SLACK_MS + longest then
        break
      end
      local inside = math.min (t.at, s.b + SLACK_MS)
        - math.max (t.at - t.ms, s.a - SLACK_MS)
      if inside > 0 and t.ms > 0 then
        local share = math.min (1, inside / t.ms)
        lua = lua + t.ms * share
        add_parts (by, t, share)
      end
    end
    lua = math.min (lua, ms)
    local parts = {} ---@type Proteus.PerfPart[]
    for _, p in pairs (by) do
      parts[#parts + 1] = p
    end
    table.sort (parts, function (x, y)
      return x.ms > y.ms
    end)
    local top = parts[1]
    local cause
    if top and lua >= ms / 2 then
      cause = top.owner .. ', in ' .. M.describe (top.what)
    elseif top then
      cause = 'Mostly the browser laying out and painting the page. '
        .. top.owner
        .. ' ran for '
        .. M.ms (top.ms)
        .. ' of it, in '
        .. M.describe (top.what)
    else
      cause =
        'The browser, outside plugin code: laying out or painting the page, collecting garbage, or a widget such as the code editor'
    end
    out[#out + 1] = {
      at = s.a,
      ms = ms,
      lua = lua,
      browser = ms - lua,
      parts = parts,
      cause = cause,
    }
  end
  return out
end

---The frame rate over the last `seconds`, and the longest time between two frames.
---@param state Profiler.State
---@param seconds? number
---@return number? fps Nil when frames were not watched.
---@return number worst
function M.fps (state, seconds)
  local list = state.seconds
  local n = #list
  -- The newest second is still filling.
  local last = n - 1
  local first = math.max (1, last - (seconds or 60) + 1)
  local frames, count, worst = 0, 0, 0
  for i = first, last do
    frames = frames + list[i].frames
    count = count + 1
    worst = math.max (worst, list[i].worst)
  end
  if count == 0 then
    return nil, 0
  end
  return frames / count, worst
end

local LEVELS = { high = 1, medium = 2, info = 3 }

---What stands out, worst first, in words.
---@param win Profiler.Window
---@param stalls Profiler.Stall[] The stalls in the window.
---@param dom? Proteus.PerfDom
---@param fps? number
---@param self_id? string This plugin, left out of the blame.
---@param offset? number Hours from UTC, for times of day.
---@return Profiler.Finding[]
function M.findings (win, stalls, dom, fps, self_id, offset)
  local out = {} ---@type Profiler.Finding[]
  ---@param level 'high'|'medium'|'info'
  ---@param text string
  ---@param plugin? string
  local function add (level, text, plugin)
    out[#out + 1] = { level = level, text = text, plugin = plugin }
  end
  local secs = win.wall / 1000

  if #stalls > 0 then
    local worst = stalls[1]
    for _, s in ipairs (stalls) do
      if s.ms > worst.ms then
        worst = s
      end
    end
    add (
      worst.ms >= 200 and 'high' or 'medium',
      string.format (
        'The window froze %s. The longest, %s at %s, was %s.',
        #stalls == 1 and 'once' or (M.count (#stalls) .. ' times'),
        M.ms (worst.ms),
        M.clock (worst.at, offset),
        worst.cause:sub (1, 1):lower () .. worst.cause:sub (2)
      ),
      worst.parts[1] and worst.lua >= worst.ms / 2 and worst.parts[1].owner
        or nil
    )
  end

  if fps and fps < 50 then
    add (
      fps < 30 and 'high' or 'medium',
      string.format (
        'The page drew %.0f frames a second, where 60 is smooth.',
        fps
      )
    )
  end

  local busy = win.wall > 0 and win.busy / win.wall or 0
  if busy >= 0.2 then
    add (
      busy >= 0.5 and 'high' or 'medium',
      'Plugin code kept the window busy '
        .. M.percent (busy)
        .. ' of the time. Clicks and keys wait while it runs.'
    )
  end

  local named = 0
  for _, row in ipairs (win.rows) do
    if row.id ~= self_id and row.share >= 0.05 and named < 3 then
      named = named + 1
      local top = row.kinds[1]
      local text = row.id .. ' used ' .. M.percent (row.share) .. ' of the time'
      if top then
        text = text
          .. ', mostly in '
          .. M.describe (top.what)
          .. ': '
          .. M.count (top.calls)
          .. (top.calls == 1 and ' call' or ' calls')
          .. ' at '
          .. M.ms (top.self / top.calls)
          .. ' each'
      end
      add (row.share >= 0.25 and 'high' or 'medium', text .. '.', row.id)
    end
  end

  for _, row in ipairs (win.rows) do
    for _, k in ipairs (row.kinds) do
      local rate = secs > 0 and k.calls / secs or 0
      if k.what == 'timer' and rate >= 20 and row.id ~= self_id then
        add (
          'medium',
          string.format (
            '%s runs a timer %.0f times a second. Each run is work even when nothing changed.',
            row.id,
            rate
          ),
          row.id
        )
      end
    end
    if row.errors > 0 then
      add (
        'medium',
        row.id
          .. ' raised '
          .. M.count (row.errors)
          .. (row.errors == 1 and ' error' or ' errors')
          .. '. The Console shows them.',
        row.id
      )
    end
  end

  for _, ev in ipairs (win.events) do
    if ev.rate >= 50 then
      add (
        'medium',
        string.format (
          'The event %s was sent %.0f times a second, and its listeners took %s.',
          ev.name,
          ev.rate,
          M.ms (ev.ms)
        )
      )
    end
  end

  if dom then
    for id, d in pairs (dom.plugins) do
      if d.nodes >= 5000 then
        add (
          d.nodes >= 20000 and 'high' or 'medium',
          id
            .. ' has '
            .. M.count (d.nodes)
            .. ' elements on the page. A large page is slow to lay out and repaint.',
          id
        )
      end
    end
  end

  if secs >= 30 and win.lua_growth_kb >= 20 * 1024 then
    add (
      'medium',
      'Lua memory grew '
        .. M.count (win.lua_growth_kb / 1024)
        .. ' MB in '
        .. M.ms (win.wall)
        .. '. Something keeps data it no longer needs.'
    )
  end

  if not win.seconds then
    for _, row in ipairs (win.rows) do
      local start = num (row.load) + num (row.start)
      if start >= 100 then
        add (
          start >= 500 and 'high' or 'info',
          row.id .. ' took ' .. M.ms (start) .. ' to start.',
          row.id
        )
      end
    end
  end

  -- table.sort is not stable, so the order they were found in breaks ties.
  local order = {} ---@type table<Profiler.Finding, integer>
  for i, f in ipairs (out) do
    order[f] = i
  end
  table.sort (out, function (x, y)
    if x.level ~= y.level then
      return LEVELS[x.level] < LEVELS[y.level]
    end
    return order[x] < order[y]
  end)
  if #out == 0 then
    add (
      'info',
      'Nothing stands out. Plugin code ran for '
        .. M.ms (win.busy)
        .. ' in '
        .. M.ms (win.wall)
        .. ', and the window did not freeze.'
    )
  end
  return out
end

---The window's numbers as Markdown, to paste into an issue or a chat.
---@param win Profiler.Window
---@param stalls Profiler.Stall[]
---@param findings Profiler.Finding[]
---@param dom? Proteus.PerfDom
---@param offset? number Hours from UTC.
---@return string
function M.report (win, stalls, findings, dom, offset)
  local lines = {} ---@type string[]
  ---@param s string
  local function put (s)
    lines[#lines + 1] = s
  end
  put ('# Proteus profile')
  put ('')
  put (
    string.format (
      '%s to %s: plugin code ran %s of %s (%s). Lua memory %s MB.',
      M.clock (win.from, offset),
      M.clock (win.to, offset),
      M.ms (win.busy),
      M.ms (win.wall),
      M.percent (win.wall > 0 and win.busy / win.wall or 0),
      M.count (win.lua_kb / 1024)
    )
  )
  put ('')
  put ('## Findings')
  put ('')
  for _, f in ipairs (findings) do
    put ('- **' .. f.level .. '**: ' .. f.text)
  end
  put ('')
  put ('## Plugins')
  put ('')
  put ('| Plugin | Share | Self | Calls | Errors | Elements | Busiest in |')
  put ('|---|---:|---:|---:|---:|---:|---|')
  for _, row in ipairs (win.rows) do
    local d = dom and dom.plugins[row.id] or nil
    put (
      string.format (
        '| %s | %s | %s | %s | %s | %s | %s |',
        row.id,
        M.percent (row.share),
        M.ms (row.self),
        M.count (row.calls),
        M.count (row.errors),
        d and M.count (d.nodes) or '',
        row.kinds[1] and row.kinds[1].what or ''
      )
    )
  end
  if #stalls > 0 then
    put ('')
    put ('## Stalls')
    put ('')
    for _, s in ipairs (stalls) do
      put (
        string.format (
          '- %s, %s: %s',
          M.clock (s.at, offset),
          M.ms (s.ms),
          s.cause
        )
      )
    end
  end
  return table.concat (lines, '\n') .. '\n'
end

return M
