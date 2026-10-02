-- log_ring: the lines of a source. It makes a line from the text that arrived, with its level
-- and time, holds lines in a ring of fixed size that lets the oldest go, goes over a ring with
-- the filter, and merges the lines of several sources in order of time.

local ansi = require ('log_ansi') --[[@as Logs.AnsiModule]]
local ll = require ('log_level') --[[@as Logs.LevelModule]]
local lq = require ('log_query') --[[@as Logs.QueryModule]]
local lt = require ('log_time') --[[@as Logs.TimeModule]]

local strip_ansi = ansi.strip_ansi
local detect_level, zero_levels = ll.detect_level, ll.zero_levels
local matches_line = lq.matches_line

-- The year a syslog or glog line is from, since it writes none.
local YEAR = math.floor (tonumber (os.date ('%Y')) or 1970)

---One line of a source.
---@class Logs.Line
---@field n integer The line number, counted from the start of the source.
---@field text string The text as it arrived, colour codes and all.
---@field plain string The text without colour codes.
---@field level Logs.Level
---@field err boolean True for a line the program wrote to stderr.
---@field time? number When it was written, in milliseconds since 1970. A line that says no time, such as a stack trace's, takes the time of the line before it.
---@field stamped boolean True when the line says its own time.
---@field lower? string The plain text in lower case, made the first time the filter needs it.
---@field src? integer The id of the source it came from.
---@field id? integer A number no other line in the app has, for the merged view.

---What one pass over a source found.
---@class Logs.Scan
---@field shown Logs.Line[] The last lines that pass the filter and the level chips, oldest first.
---@field all Logs.Line[] Every line that passes the filter and the level chips, oldest first.
---@field matched integer How many lines pass the filter and the level chips.
---@field levels table<Logs.Level, integer> How many lines of each level pass the filter.

---A fixed number of lines. Once it is full, each new line pushes out the oldest.
---@class Logs.Ring
---@field __index Logs.Ring
---@field capacity integer
---@field slots table<integer, Logs.Line>
---@field head integer The slot of the oldest line.
---@field size integer
local Ring = {}
Ring.__index = Ring

---@class Logs.RingModule
---@field make_line fun(n: integer, text: string, err?: boolean, prev_time?: number): Logs.Line
---@field ring fun(capacity: integer): Logs.Ring
---@field find_line fun(ring: Logs.Ring, n: integer): Logs.Line?
---@field index_of fun(sorted: integer[], n: integer): integer?
---@field classify fun(line: Logs.Line, query: Logs.Query, hidden: table<string, boolean>, newest?: number): boolean, boolean
---@field scan fun(ring: Logs.Ring, query: Logs.Query, hidden: table<string, boolean>, limit: integer, newest?: number): Logs.Scan
---@field newest fun(ring: Logs.Ring): number?
---@field merge fun(lists: Logs.Line[][]): Logs.Line[]

---A line as the source keeps it. `prev_time` is the time of the line before, which a line
---that says no time of its own takes, such as a line of a stack trace.
---@param n integer
---@param text string
---@param err? boolean
---@param prev_time? number
---@return Logs.Line
local function make_line (n, text, err, prev_time)
  local plain = strip_ansi (text)
  local time = lt.line_time (plain, YEAR)
  return {
    n = n,
    text = text,
    plain = plain,
    level = detect_level (plain),
    err = err == true,
    time = time or prev_time,
    stamped = time ~= nil,
  }
end

---Adds a line. Returns the oldest line when the ring was full and let it go.
---@param line Logs.Line
---@return Logs.Line? dropped
function Ring:push (line)
  if self.size < self.capacity then
    self.size = self.size + 1
    self.slots[(self.head + self.size - 2) % self.capacity + 1] = line
    return nil
  end
  local dropped = self.slots[self.head]
  self.slots[self.head] = line
  self.head = self.head % self.capacity + 1
  return dropped
end

---@return integer
function Ring:count ()
  return self.size
end

---The line at a position, where 1 is the oldest.
---@param i integer
---@return Logs.Line?
function Ring:get (i)
  if i < 1 or i > self.size then
    return nil
  end
  return self.slots[(self.head + i - 2) % self.capacity + 1]
end

function Ring:clear ()
  self.slots = {}
  self.head = 1
  self.size = 0
end

---@param capacity integer
---@return Logs.Ring
local function ring (capacity)
  return setmetatable (
    { capacity = capacity, slots = {}, head = 1, size = 0 },
    Ring
  )
end

---Finds a line in the ring by its line number. Line numbers only go up, so this halves the
---range each step.
---@param lines Logs.Ring
---@param n integer
---@return Logs.Line?
local function find_line (lines, n)
  local lo, hi = 1, lines:count ()
  while lo <= hi do
    local mid = math.floor ((lo + hi) / 2)
    local line = lines:get (mid)
    if not line then
      return nil
    end
    if line.n == n then
      return line
    end
    if line.n < n then
      lo = mid + 1
    else
      hi = mid - 1
    end
  end
  return nil
end

---The position of `n` in a list sorted from small to large, or nil.
---@param sorted integer[]
---@param n integer
---@return integer?
local function index_of (sorted, n)
  local lo, hi = 1, #sorted
  while lo <= hi do
    local mid = math.floor ((lo + hi) / 2)
    local value = sorted[mid]
    if value == n then
      return mid
    end
    if value < n then
      lo = mid + 1
    else
      hi = mid - 1
    end
  end
  return nil
end

---Whether a line passes the filter, and whether it also passes the level chips. `newest` is
---the time of the newest line, for a time such as `after:-15m`.
---@param line Logs.Line
---@param query Logs.Query
---@param hidden table<string, boolean>
---@param newest? number
---@return boolean counted
---@return boolean visible
local function classify (line, query, hidden, newest)
  if not matches_line (line, query, newest) then
    return false, false
  end
  return true, not hidden[line.level]
end

---Goes over every line of a source once. Counts what passes, keeps every line that passes
---both the filter and the level chips, and the last `limit` of them on their own.
---@param lines Logs.Ring
---@param query Logs.Query
---@param hidden table<string, boolean>
---@param limit integer
---@param newest? number
---@return Logs.Scan
local function scan (lines, query, hidden, limit, newest)
  local levels = zero_levels ()
  ---@type Logs.Line[]
  local all = {}
  for i = 1, lines:count () do
    local line = lines:get (i)
    if line then
      local counted, visible = classify (line, query, hidden, newest)
      if counted then
        levels[line.level] = levels[line.level] + 1
      end
      if visible then
        all[#all + 1] = line
      end
    end
  end
  ---@type Logs.Line[]
  local shown = {}
  for i = math.max (1, #all - limit + 1), #all do
    shown[#shown + 1] = all[i]
  end
  return { shown = shown, all = all, matched = #all, levels = levels }
end

---The time of the newest line that has one.
---@param lines Logs.Ring
---@return number?
local function newest (lines)
  for i = lines:count (), 1, -1 do
    local line = lines:get (i)
    if line and line.time then
      return line.time
    end
  end
  return nil
end

---True when line `a` goes before line `b` in the merged view: the earlier time first, and
---lines with the same time, or with none, in the order they arrived.
---@param a Logs.Line
---@param b Logs.Line
---@return boolean
local function earlier (a, b)
  if a.time and b.time and a.time ~= b.time then
    return a.time < b.time
  end
  return (a.id or a.n) < (b.id or b.n)
end

---Merges lists that are each in order into one, by time. Each list keeps its own order.
---@param lists Logs.Line[][]
---@return Logs.Line[]
local function merge (lists)
  ---@type Logs.Line[]
  local out = {}
  local at = {} ---@type integer[]
  for i = 1, #lists do
    at[i] = 1
  end
  while true do
    local best = nil ---@type integer?
    for i, list in ipairs (lists) do
      local line = list[at[i]]
      if line and (not best or earlier (line, lists[best][at[best]])) then
        best = i
      end
    end
    if not best then
      return out
    end
    out[#out + 1] = lists[best][at[best]]
    at[best] = at[best] + 1
  end
end

---@type Logs.RingModule
local M = {
  make_line = make_line,
  ring = ring,
  find_line = find_line,
  index_of = index_of,
  classify = classify,
  scan = scan,
  newest = newest,
  merge = merge,
}

return M
