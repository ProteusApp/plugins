-- log_filter: the logic behind proteus.logs, kept apart from the screen so the tests reach it.
-- It finds the level and the time of a line, filters lines by words, regular expressions,
-- levels and times, turns ANSI colour codes into HTML, finds JSON inside a line, holds lines
-- in a ring of fixed size, and merges several sources by time. It draws nothing and calls no
-- host function. Regular expressions are in log_regex.lua, and times in log_time.lua.

local ansi = require ('log_ansi') --[[@as Logs.AnsiModule]]
local ll = require ('log_level') --[[@as Logs.LevelModule]]
local lq = require ('log_query') --[[@as Logs.QueryModule]]
local lt = require ('log_time') --[[@as Logs.TimeModule]]
local tx = require ('log_text') --[[@as Logs.TextModule]]

local escape, trim, sentence, group, clip, split_lines =
  tx.escape, tx.trim, tx.sentence, tx.group, tx.clip, tx.split_lines
local parse_ansi, strip_ansi = ansi.parse_ansi, ansi.strip_ansi
local LEVELS, detect_level, zero_levels =
  ll.LEVELS, ll.detect_level, ll.zero_levels
local parse_query, is_empty, has_time, matches, matches_line, highlight =
  lq.parse_query,
  lq.is_empty,
  lq.has_time,
  lq.matches,
  lq.matches_line,
  lq.highlight

-- The year a syslog or glog line is from, since it writes none.
local YEAR = math.floor (tonumber (os.date ('%Y')) or 1970)

---@alias Logs.State
---| 'running' # The program runs.
---| 'stopped' # Stopped from the app.
---| 'exited' # The program ended by itself.
---| 'failed' # The program could not start.
---| 'pasted' # Text from the clipboard, which does not grow.

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

---Where lines come from: a file to follow, a command to run, or pasted text.
---@class Logs.SourceSpec
---@field kind 'file'|'command'|'paste'
---@field path? string The full path of a file.
---@field command? string The command line of a command.
---@field cwd? string The folder a command runs in.
---@field name? string The name of pasted text.
---@field whole? boolean For a file, read from its first line rather than its last thousand.

---A fixed number of lines. Once it is full, each new line pushes out the oldest.
---@class Logs.Ring
---@field __index Logs.Ring
---@field capacity integer
---@field slots table<integer, Logs.Line>
---@field head integer The slot of the oldest line.
---@field size integer
local Ring = {}
Ring.__index = Ring

---@class Logs.FilterModule
---@field LEVELS Logs.Level[] Every level, worst first.
---@field parse_query fun(text: string): Logs.Query
---@field is_empty fun(query: Logs.Query): boolean True when the query hides nothing.
---@field detect_level fun(line: string): Logs.Level
---@field matches fun(line: string, query: Logs.Query, level?: Logs.Level): boolean
---@field highlight fun(line: string, query: Logs.Query): Logs.Range[]
---@field strip_ansi fun(text: string): string
---@field parse_ansi fun(text: string): Logs.Segment[]
---@field escape fun(text: string): string
---@field render_line fun(line: string, query: Logs.Query): string
---@field row_html fun(line: Logs.Line, query: Logs.Query, tag?: { name: string, n: integer }): string
---@field clip fun(text: string, max: integer): string
---@field find_json fun(line: string): string?
---@field pretty_json fun(text: string): string?
---@field make_line fun(n: integer, text: string, err?: boolean, prev_time?: number): Logs.Line
---@field matches_line fun(line: Logs.Line, query: Logs.Query, newest?: number): boolean
---@field ring fun(capacity: integer): Logs.Ring
---@field find_line fun(ring: Logs.Ring, n: integer): Logs.Line?
---@field index_of fun(sorted: integer[], n: integer): integer?
---@field zero_levels fun(): table<Logs.Level, integer>
---@field classify fun(line: Logs.Line, query: Logs.Query, hidden: table<string, boolean>, newest?: number): boolean, boolean
---@field scan fun(ring: Logs.Ring, query: Logs.Query, hidden: table<string, boolean>, limit: integer, newest?: number): Logs.Scan
---@field merge fun(lists: Logs.Line[][]): Logs.Line[]
---@field newest fun(ring: Logs.Ring): number?
---@field has_time fun(query: Logs.Query): boolean
---@field split_lines fun(text: string): string[]
---@field trim fun(text: string): string
---@field sentence fun(text: string): string
---@field group fun(n: number): string
---@field follow_command fun(path: string, os_name: string, whole?: boolean): string, string[]
---@field shell_command fun(line: string, os_name: string): string, string[]
---@field source_name fun(spec: Logs.SourceSpec): string
---@field source_title fun(spec: Logs.SourceSpec): string
---@field state_label fun(state: Logs.State, code?: integer): string
---@field spec_key fun(spec: Logs.SourceSpec): string
---@field remember fun(list: Logs.SourceSpec[], spec: Logs.SourceSpec, max: integer): Logs.SourceSpec[]
---@field clean_specs fun(value: any): Logs.SourceSpec[]
---@field clean_levels fun(value: any): Logs.Level[]

-- Lines longer than this show cut short in the list. The detail panel shows them whole.
local MAX_ROW = 4000

local MAX_JSON_DEPTH = 64

---The HTML for the text of one line: escaped, coloured from its ANSI codes, and with each
---filter match in `<mark>`. A match that crosses a colour change is marked in each part.
---@param line string
---@param query Logs.Query
---@return string
local function render_line (line, query)
  local ranges = highlight (line, query)
  ---@type string[]
  local out = {}
  -- Where the current run starts in the plain text.
  local pos = 1 ---@type integer
  local r = 1
  for _, seg in ipairs (parse_ansi (line)) do
    ---@type string[]
    local classes = {}
    if seg.fg then
      classes[#classes + 1] = 'logs-c' .. seg.fg
    end
    if seg.bold then
      classes[#classes + 1] = 'logs-b'
    end
    if #classes > 0 then
      out[#out + 1] = '<span class="' .. table.concat (classes, ' ') .. '">'
    end
    local last = pos + #seg.text - 1 ---@type integer
    local at = pos ---@type integer
    while at <= last do
      while ranges[r] and ranges[r].to < at do
        r = r + 1
      end
      local range = ranges[r]
      if range and range.from <= at then
        local stop = math.min (range.to, last)
        out[#out + 1] = '<mark>'
          .. escape (seg.text:sub (at - pos + 1, stop - pos + 1))
          .. '</mark>'
        at = stop + 1
      else
        local stop = range and math.min (range.from - 1, last) or last
        out[#out + 1] = escape (seg.text:sub (at - pos + 1, stop - pos + 1))
        at = stop + 1
      end
    end
    if #classes > 0 then
      out[#out + 1] = '</span>'
    end
    pos = last + 1
  end
  return table.concat (out)
end

---The HTML for one row of the list. The row carries the line's id in `data-item`, or its
---number when it has no id. In the merged view, `tag` names the source the line came from,
---and `n` picks its colour.
---@param line Logs.Line
---@param query Logs.Query
---@param tag? { name: string, n: integer }
---@return string
local function row_html (line, query, tag)
  local text = line.text
  local more = ''
  if #text > MAX_ROW then
    text = clip (text, MAX_ROW)
    more = '<span class="logs-more">…</span>'
  end
  return table.concat ({
    '<div class="logs-row logs-lv-',
    line.level,
    line.err and ' logs-stderr' or '',
    '" data-item="',
    line.id or line.n,
    '"><span class="logs-n">',
    line.n,
    '</span>',
    tag
        and ('<span class="logs-tag logs-tag-' .. (tag.n % 6) .. '">' .. escape (
          tag.name
        ) .. '</span>')
      or '',
    '<span class="logs-t">',
    render_line (text, query),
    more,
    '</span></div>',
  })
end

---------------------------------------------------------------------------------------------
-- JSON
---------------------------------------------------------------------------------------------

---@param s string
---@param i integer
---@return integer
local function skip_space (s, i)
  return s:find ('[^ \t\r\n]', i) or #s + 1
end

---Reads a JSON string that starts at `i`. Returns the position after it.
---@param s string
---@param i integer
---@return integer?
local function read_string (s, i)
  local at = i + 1
  while true do
    local c = s:find ('["\\%c]', at)
    if not c then
      return nil
    end
    local ch = s:sub (c, c)
    if ch == '"' then
      return c + 1
    end
    if ch ~= '\\' then
      return nil
    end
    local nx = s:sub (c + 1, c + 1)
    if nx == 'u' then
      if not s:match ('^%x%x%x%x', c + 2) then
        return nil
      end
      at = c + 6
    elseif nx ~= '' and ('"\\/bfnrt'):find (nx, 1, true) then
      at = c + 2
    else
      return nil
    end
  end
end

---Reads a JSON number that starts at `i`. Returns the position after it.
---@param s string
---@param i integer
---@return integer?
local function read_number (s, i)
  local at = s:match ('^%-?0()', i) or s:match ('^%-?[1-9]%d*()', i)
  if not at then
    return nil
  end
  at = s:match ('^%.%d+()', at) or at
  at = s:match ('^[eE][%+%-]?%d+()', at) or at
  return at
end

---Reads one JSON value that starts at `i`, and adds its tokens to `out` when given.
---Returns the position after it, or nil when the text there is not JSON.
---@param s string
---@param i integer
---@param out string[]?
---@param depth integer
---@return integer?
local function read_value (s, i, out, depth)
  if depth > MAX_JSON_DEPTH then
    return nil
  end
  local c = s:sub (i, i)
  if c == '{' or c == '[' then
    local close = c == '{' and '}' or ']'
    if out then
      out[#out + 1] = c
    end
    local at = skip_space (s, i + 1)
    if s:sub (at, at) == close then
      if out then
        out[#out + 1] = close
      end
      return at + 1
    end
    while true do
      if c == '{' then
        if s:sub (at, at) ~= '"' then
          return nil
        end
        local key_end = read_string (s, at)
        if not key_end then
          return nil
        end
        if out then
          out[#out + 1] = s:sub (at, key_end - 1)
        end
        at = skip_space (s, key_end)
        if s:sub (at, at) ~= ':' then
          return nil
        end
        if out then
          out[#out + 1] = ':'
        end
        at = skip_space (s, at + 1)
      end
      local value_end = read_value (s, at, out, depth + 1)
      if not value_end then
        return nil
      end
      at = skip_space (s, value_end)
      local sep = s:sub (at, at)
      if sep == close then
        if out then
          out[#out + 1] = close
        end
        return at + 1
      end
      if sep ~= ',' then
        return nil
      end
      if out then
        out[#out + 1] = ','
      end
      at = skip_space (s, at + 1)
    end
  end
  local after = nil ---@type integer?
  local word = s:match ('^%a+', i)
  if c == '"' then
    after = read_string (s, i)
  elseif word == 'true' or word == 'false' or word == 'null' then
    after = i + #word
  else
    after = read_number (s, i)
  end
  if after and out then
    out[#out + 1] = s:sub (i, after - 1)
  end
  return after
end

---The JSON object or array a line ends with, such as the part after a time, or nil.
---@param line string
---@return string?
local function find_json (line)
  local plain = strip_ansi (line)
  local start = plain:find ('[{%[]')
  local tries = 0
  while start and tries < 50 do
    tries = tries + 1
    local after = read_value (plain, start, nil, 0)
    if after and after - start > 2 and not plain:find ('%S', after) then
      return plain:sub (start, after - 1)
    end
    start = plain:find ('[{%[]', start + 1)
  end
  return nil
end

---JSON laid out with two spaces per level. Keys keep their order. Returns nil for text that
---is not JSON.
---@param text string
---@return string?
local function pretty_json (text)
  ---@type string[]
  local tokens = {}
  local after = read_value (text, skip_space (text, 1), tokens, 0)
  if not after or text:find ('%S', after) then
    return nil
  end
  ---@type string[]
  local out = {}
  local depth = 0
  local i = 1
  while i <= #tokens do
    local t = tokens[i]
    if t == '{' or t == '[' then
      local close = t == '{' and '}' or ']'
      if tokens[i + 1] == close then
        out[#out + 1] = t .. close
        i = i + 1
      else
        depth = depth + 1
        out[#out + 1] = t .. '\n' .. string.rep ('  ', depth)
      end
    elseif t == '}' or t == ']' then
      depth = depth - 1
      out[#out + 1] = '\n' .. string.rep ('  ', depth) .. t
    elseif t == ',' then
      out[#out + 1] = ',\n' .. string.rep ('  ', depth)
    elseif t == ':' then
      out[#out + 1] = ': '
    else
      out[#out + 1] = t
    end
    i = i + 1
  end
  return table.concat (out)
end

---------------------------------------------------------------------------------------------
-- Lines and the ring
---------------------------------------------------------------------------------------------

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

---------------------------------------------------------------------------------------------
-- Sources
---------------------------------------------------------------------------------------------

---The program and arguments that follow a file: the last thousand lines, or with `whole`
---every line from the first, then each new one.
---@param path string
---@param os_name string
---@param whole? boolean
---@return string program
---@return string[] args
local function follow_command (path, os_name, whole)
  if os_name == 'windows' then
    -- PowerShell ends a quoted string at any of its four single quotes, so each is doubled.
    -- It also writes in the console code page unless told to use UTF-8.
    local quoted = path:gsub ("'", "''"):gsub ('\226\128[\152-\155]', '%0%0')
    return 'powershell',
      {
        '-NoProfile',
        '-Command',
        '[Console]::OutputEncoding = [Text.Encoding]::UTF8; '
          .. "Get-Content -LiteralPath '"
          .. quoted
          .. "'"
          .. (whole and '' or ' -Tail 1000')
          .. ' -Wait -Encoding UTF8',
      }
  end
  return 'tail', { '-n', whole and '+1' or '1000', '-F', path }
end

---The program and arguments that run a command line through the shell.
---@param line string
---@param os_name string
---@return string program
---@return string[] args
local function shell_command (line, os_name)
  if os_name == 'windows' then
    return 'cmd', { '/c', line }
  end
  return 'sh', { '-c', line }
end

---@param spec Logs.SourceSpec
---@return string
local function source_name (spec)
  if spec.kind == 'file' then
    local path = spec.path or ''
    return path:match ('[^/\\]+$') or path
  end
  if spec.kind == 'command' then
    local line = trim (spec.command or '')
    if #line > 60 then
      return clip (line, 57) .. '…'
    end
    return line
  end
  return spec.name or 'Pasted text'
end

---A longer description of a source, for a tooltip.
---@param spec Logs.SourceSpec
---@return string
local function source_title (spec)
  if spec.kind == 'file' then
    return (spec.path or '') .. (spec.whole and '\nthe whole file' or '')
  end
  if spec.kind == 'command' then
    local cwd = spec.cwd
    return (spec.command or '') .. (cwd and ('\nin ' .. cwd) or '')
  end
  return spec.name or 'Pasted text'
end

---@param state Logs.State
---@param code? integer
---@return string
local function state_label (state, code)
  if state == 'running' then
    return 'Running'
  elseif state == 'stopped' then
    return 'Stopped'
  elseif state == 'exited' then
    return code and ('Exited with code ' .. code) or 'Exited'
  elseif state == 'failed' then
    return 'Failed to start'
  end
  return 'Pasted'
end

---Two specs with the same key are the same source.
---@param spec Logs.SourceSpec
---@return string
local function spec_key (spec)
  return table.concat ({
    spec.kind,
    spec.path or spec.command or spec.name or '',
    spec.cwd or '',
    spec.whole and 'whole' or '',
  }, '\n')
end

---A copy of a spec with only the fields that are saved.
---@param spec Logs.SourceSpec
---@return Logs.SourceSpec
local function copy_spec (spec)
  return {
    kind = spec.kind,
    path = spec.path,
    command = spec.command,
    cwd = spec.cwd,
    whole = spec.whole,
  }
end

---A new list of recent sources with `spec` first and no repeats.
---@param list Logs.SourceSpec[]
---@param spec Logs.SourceSpec
---@param max integer
---@return Logs.SourceSpec[]
local function remember (list, spec, max)
  local key = spec_key (spec)
  ---@type Logs.SourceSpec[]
  local out = { copy_spec (spec) }
  for _, other in ipairs (list) do
    if #out >= max then
      break
    end
    if spec_key (other) ~= key then
      out[#out + 1] = other
    end
  end
  return out
end

---Saved specs, with anything malformed left out.
---@param value any
---@return Logs.SourceSpec[]
local function clean_specs (value)
  ---@type Logs.SourceSpec[]
  local out = {}
  if type (value) ~= 'table' then
    return out
  end
  for _, v in
    ipairs (value --[[@as table<string, any>[] ]])
  do
    if type (v) == 'table' then
      local path, command, cwd = v.path, v.command, v.cwd
      if v.kind == 'file' and type (path) == 'string' and path ~= '' then
        out[#out + 1] =
          { kind = 'file', path = path, whole = v.whole == true or nil }
      elseif
        v.kind == 'command'
        and type (command) == 'string'
        and command:match ('%S')
      then
        out[#out + 1] = {
          kind = 'command',
          command = command,
          cwd = type (cwd) == 'string' and cwd ~= '' and cwd or nil,
        }
      end
    end
  end
  return out
end

---Saved level names, with anything unknown left out.
---@param value any
---@return Logs.Level[]
local function clean_levels (value)
  ---@type Logs.Level[]
  local out = {}
  if type (value) ~= 'table' then
    return out
  end
  for _, v in
    ipairs (value --[[@as any[] ]])
  do
    for _, level in ipairs (LEVELS) do
      if v == level then
        out[#out + 1] = level
      end
    end
  end
  return out
end

---@type Logs.FilterModule
local M = {
  LEVELS = LEVELS,
  parse_query = parse_query,
  is_empty = is_empty,
  detect_level = detect_level,
  matches = matches,
  highlight = highlight,
  strip_ansi = strip_ansi,
  parse_ansi = parse_ansi,
  escape = escape,
  render_line = render_line,
  row_html = row_html,
  clip = clip,
  find_json = find_json,
  pretty_json = pretty_json,
  make_line = make_line,
  matches_line = matches_line,
  ring = ring,
  find_line = find_line,
  index_of = index_of,
  zero_levels = zero_levels,
  classify = classify,
  scan = scan,
  merge = merge,
  newest = newest,
  has_time = has_time,
  split_lines = split_lines,
  trim = trim,
  sentence = sentence,
  group = group,
  follow_command = follow_command,
  shell_command = shell_command,
  source_name = source_name,
  source_title = source_title,
  state_label = state_label,
  spec_key = spec_key,
  remember = remember,
  clean_specs = clean_specs,
  clean_levels = clean_levels,
}

return M
