-- log_filter: the logic behind proteus.logs, kept apart from the screen so the tests reach it.
-- It finds the level and the time of a line, filters lines by words, regular expressions,
-- levels and times, turns ANSI colour codes into HTML, finds JSON inside a line, holds lines
-- in a ring of fixed size, and merges several sources by time. It draws nothing and calls no
-- host function. Regular expressions are in log_regex.lua, and times in log_time.lua.

local lt = require ('log_time') --[[@as Logs.TimeModule]]
local re = require ('log_regex') --[[@as { compile: fun(pattern: string, opts?: { fold?: boolean }): LogRegex.Program?, string? }]]

-- The year a syslog or glog line is from, since it writes none.
local YEAR = math.floor (tonumber (os.date ('%Y')) or 1970)

---@alias Logs.Level 'error'|'warn'|'info'|'debug'|'other'

---@alias Logs.State
---| 'running' # The program runs.
---| 'stopped' # Stopped from the app.
---| 'exited' # The program ended by itself.
---| 'failed' # The program could not start.
---| 'pasted' # Text from the clipboard, which does not grow.

---What the filter box holds, taken apart. Every text is in lower case.
---@class Logs.Query
---@field terms string[] Words that must all appear.
---@field phrases string[] Phrases in quotes that must all appear.
---@field exclude string[] Words or phrases that hide a line.
---@field level? Logs.Level Keeps only lines of this level.
---@field skip table<Logs.Level, boolean> Levels `-level:` hides.
---@field regexes LogRegex.Program[] Regular expressions, from `/.../`, that must all match.
---@field exclude_regexes LogRegex.Program[] Regular expressions, from `-/.../`, that hide a line.
---@field after? Logs.When Keeps lines from this time on, from `after:`.
---@field before? Logs.When Keeps lines up to this time, from `before:`.
---@field problem? string What the filter could not read, such as a broken regular expression.

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

---A stretch of text the filter matched, as byte positions in the plain text.
---@class Logs.Range
---@field from integer
---@field to integer

---A run of text in one colour.
---@class Logs.Segment
---@field text string
---@field fg? integer An ANSI colour from 0 to 15.
---@field bold boolean

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

---@type Logs.Level[]
local LEVELS = { 'error', 'warn', 'info', 'debug', 'other' }

-- Words that name a level. A single letter counts only in brackets or as a JSON value.
---@type table<string, Logs.Level>
local WORDS = {
  error = 'error',
  err = 'error',
  fatal = 'error',
  critical = 'error',
  crit = 'error',
  panic = 'error',
  severe = 'error',
  emerg = 'error',
  emergency = 'error',
  ftl = 'error',
  warn = 'warn',
  warning = 'warn',
  wrn = 'warn',
  info = 'info',
  inf = 'info',
  information = 'info',
  notice = 'info',
  debug = 'debug',
  dbg = 'debug',
  trace = 'debug',
  trc = 'debug',
  verbose = 'debug',
  vrb = 'debug',
}

---@type table<string, Logs.Level>
local LETTERS = {
  E = 'error',
  F = 'error',
  W = 'warn',
  I = 'info',
  D = 'debug',
  T = 'debug',
  V = 'debug',
}

-- JSON and logfmt field names that hold a level.
---@type table<string, boolean>
local LEVEL_KEYS = {
  level = true,
  severity = true,
  lvl = true,
  loglevel = true,
  log_level = true,
  levelname = true,
  ['log.level'] = true,
  ['@l'] = true,
  ['@level'] = true,
}

-- Names that `level:` takes, tried in order, so `level:w` means warnings.
---@type { [1]: string, [2]: Logs.Level }[]
local LEVEL_NAMES = {
  { 'error', 'error' },
  { 'warning', 'warn' },
  { 'information', 'info' },
  { 'debug', 'debug' },
  { 'trace', 'debug' },
  { 'other', 'other' },
  { 'fatal', 'error' },
  { 'critical', 'error' },
}

-- Any control character except a tab. The escape that starts a colour code is one.
local CONTROL = '[^%C\t]'

-- Lines longer than this show cut short in the list. The detail panel shows them whole.
local MAX_ROW = 4000

local MAX_JSON_DEPTH = 64

---@type table<string, string>
local HTML = {
  ['&'] = '&amp;',
  ['<'] = '&lt;',
  ['>'] = '&gt;',
  ['"'] = '&quot;',
  ["'"] = '&#39;',
}

---------------------------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------------------------

---@param text string
---@return string
local function escape (text)
  return (text:gsub ('[&<>"\']', HTML))
end

---@param text string
---@return string
local function trim (text)
  return (text:gsub ('^%s+', ''):gsub ('%s+$', ''))
end

---A message from elsewhere as a sentence: a capital first letter and a stop at the end.
---@param text string
---@return string
local function sentence (text)
  local out = trim (text):gsub ('^%l', string.upper)
  if out ~= '' and not out:find ('[%.!?]$') then
    out = out .. '.'
  end
  return out
end

---A whole number with commas between each group of three digits.
---@param n number
---@return string
local function group (n)
  local digits = tostring (math.floor (math.abs (n)))
  local grouped = digits:reverse ():gsub ('(%d%d%d)', '%1,'):reverse () ---@type string
  if grouped:sub (1, 1) == ',' then
    grouped = grouped:sub (2)
  end
  return (n < 0 and '-' or '') .. grouped
end

---Cuts text to at most `max` bytes without splitting a UTF-8 character.
---@param text string
---@param max integer
---@return string
local function clip (text, max)
  if #text <= max then
    return text
  end
  local cut = max
  local byte = text:byte (cut + 1) or 0
  while cut > 0 and byte >= 128 and byte < 192 do
    cut = cut - 1
    byte = text:byte (cut + 1) or 0
  end
  return text:sub (1, cut)
end

---Splits text into lines. A newline at the very end does not make an empty last line.
---@param text string
---@return string[]
local function split_lines (text)
  ---@type string[]
  local out = {}
  if text == '' then
    return out
  end
  local norm = text:gsub ('\r\n', '\n'):gsub ('\r', '\n')
  for piece in (norm .. '\n'):gmatch ('([^\n]*)\n') do
    out[#out + 1] = piece
  end
  if norm:sub (-1) == '\n' then
    out[#out] = nil
  end
  return out
end

---@return table<Logs.Level, integer>
local function zero_levels ()
  return { error = 0, warn = 0, info = 0, debug = 0, other = 0 }
end

---------------------------------------------------------------------------------------------
-- ANSI colour codes
---------------------------------------------------------------------------------------------

---Applies the numbers of one colour code, such as `1;31`, to the current colour and weight.
---@param params string
---@param fg integer?
---@param bold boolean
---@return integer? fg
---@return boolean bold
local function apply_sgr (params, fg, bold)
  ---@type integer[]
  local codes = {}
  for part in (params .. ';'):gmatch ('([^;:]*)[;:]') do
    codes[#codes + 1] = math.floor (tonumber (part) or 0)
  end
  local i = 1
  while i <= #codes do
    local c = codes[i]
    if c == 0 then
      fg, bold = nil, false
    elseif c == 1 then
      bold = true
    elseif c == 22 then
      bold = false
    elseif c >= 30 and c <= 37 then
      fg = c - 30
    elseif c == 39 then
      fg = nil
    elseif c >= 90 and c <= 97 then
      fg = c - 82
    elseif c == 38 or c == 48 then
      -- 38;5;n picks one of 256 colours, and 38;2;r;g;b gives one exactly. Only the first 16
      -- of the 256 have a theme colour here. The numbers after the others are skipped, so
      -- they are not read as codes of their own.
      local mode = codes[i + 1]
      if mode == 5 then
        local n = codes[i + 2]
        if c == 38 and n and n < 16 then
          fg = n
        end
        i = i + 2
      elseif mode == 2 then
        i = i + 4
      end
    end
    i = i + 1
  end
  return fg, bold
end

---Splits text into runs of one colour. Reset, bold and the 16 foreground colours count.
---Every other escape sequence and control character is dropped.
---@param text string
---@return Logs.Segment[]
local function parse_ansi (text)
  ---@type Logs.Segment[]
  local segs = {}
  if text == '' then
    return segs
  end
  if not text:find (CONTROL) then
    segs[1] = { text = text, bold = false }
    return segs
  end
  local fg = nil ---@type integer?
  local bold = false

  ---@param piece string
  local function add (piece)
    if piece == '' then
      return
    end
    local last = segs[#segs]
    if last and last.fg == fg and last.bold == bold then
      last.text = last.text .. piece
    else
      segs[#segs + 1] = { text = piece, fg = fg, bold = bold }
    end
  end

  local pos = 1
  while pos <= #text do
    local at = text:find (CONTROL, pos)
    if not at then
      add (text:sub (pos))
      break
    end
    add (text:sub (pos, at - 1))
    if text:byte (at) == 27 then
      local params, final, after =
        text:match ('^\27%[([0-?]*)[ -/]*([@-~])()', at)
      if params then
        if final == 'm' then
          fg, bold = apply_sgr (params, fg, bold)
        end
        pos = after
      else
        -- A title or link sequence ends with a bell or with ESC \. One with no end runs to
        -- the end of the line. Anything else is ESC and one or two more characters.
        pos = text:match ('^\27%][^\7\27]*\7()', at)
          or text:match ('^\27%][^\7\27]*\27\\()', at)
          or (text:match ('^\27%]', at) and #text + 1)
          or text:match ('^\27[ -/]*[0-~]()', at)
          or at + 1
      end
    else
      pos = at + 1
    end
  end
  return segs
end

---@param text string
---@return string
local function strip_ansi (text)
  if not text:find (CONTROL) then
    return text
  end
  ---@type string[]
  local parts = {}
  for i, seg in ipairs (parse_ansi (text)) do
    parts[i] = seg.text
  end
  return table.concat (parts)
end

---------------------------------------------------------------------------------------------
-- Levels
---------------------------------------------------------------------------------------------

---The level a JSON or logfmt value names, such as `"warning"` or `"E"`.
---@param value string
---@return Logs.Level?
local function value_level (value)
  local word = trim (value):lower ()
  local level = WORDS[word]
  if level then
    return level
  end
  if #word == 1 then
    return LETTERS[word:upper ()]
  end
  return nil
end

---Reads a quoted logfmt value. Returns the value and where the text after it starts.
---@param text string
---@param quote integer Where the opening quote is.
---@return string
---@return integer
local function read_quoted (text, quote)
  local out = {} ---@type string[]
  local i = quote + 1
  while i <= #text do
    local c = text:sub (i, i)
    if c == '\\' then
      out[#out + 1] = text:sub (i + 1, i + 1)
      i = i + 2
    elseif c == '"' then
      return table.concat (out), i + 1
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat (out), i
end

---The level a logfmt pair names, such as `level=warn`. The line is read pair by pair, so text
---inside a quoted value, as in `msg="level=error in config"`, is never read as a pair.
---@param plain string
---@return Logs.Level?
local function logfmt_level (plain)
  local i, n = 1, #plain
  while i <= n do
    local c = plain:sub (i, i)
    if c:find ('%s') or c == '=' then
      i = i + 1
    elseif c == '"' then
      local _, after = read_quoted (plain, i)
      i = after
    else
      local stop = plain:find ('[%s="]', i) or n + 1
      local key = plain:sub (i, stop - 1)
      i = stop
      if plain:sub (stop, stop) == '=' then
        local value ---@type string
        if plain:sub (stop + 1, stop + 1) == '"' then
          value, i = read_quoted (plain, stop + 1)
        else
          local finish = plain:find ('%s', stop + 1) or n + 1
          value = plain:sub (stop + 1, finish - 1)
          i = finish
        end
        if LEVEL_KEYS[key:lower ()] then
          local word = value:match ("^'?(%a+)")
          local level = word and value_level (word)
          if level then
            return level
          end
        end
      end
    end
  end
  return nil
end

---A level field anywhere in the line, as JSON or as logfmt.
---@param plain string
---@return Logs.Level?
local function field_level (plain)
  if plain:find ('"%s*:') then
    local at = 1
    while true do
      local _, stop, key, value =
        plain:find ('"([%w_%.@]+)"%s*:%s*"([^"]*)"', at)
      if not stop then
        break
      end
      if LEVEL_KEYS[tostring (key):lower ()] then
        local level = value_level (tostring (value))
        if level then
          return level
        end
      end
      at = stop + 1
    end
    -- pino and bunyan write the level as a number.
    at = 1
    while true do
      local _, stop, key, number = plain:find ('"([%w_%.@]+)"%s*:%s*(%d+)', at)
      if not stop then
        break
      end
      if LEVEL_KEYS[tostring (key):lower ()] then
        local n = tonumber (number) or 0
        if n >= 50 then
          return 'error'
        elseif n >= 40 then
          return 'warn'
        elseif n >= 30 then
          return 'info'
        elseif n >= 10 then
          return 'debug'
        end
      end
      at = stop + 1
    end
  end
  if plain:find ('=', 1, true) then
    return logfmt_level (plain)
  end
  return nil
end

---The first level word near the start of a line that reads as a level rather than as part
---of a sentence. Returns the level and where it starts.
---@param head string
---@return Logs.Level?
---@return integer?
local function word_level (head)
  local first_word = nil ---@type integer?
  local at = 1
  while true do
    local s, stop = head:find ('%a+', at)
    if not s or not stop then
      break
    end
    at = stop + 1
    local word = head:sub (s, stop)
    local e = stop + 1
    if not first_word and #word >= 2 then
      first_word = s
    end
    local level = WORDS[word:lower ()]
    if level then
      local before = head:sub (s - 1, s - 1)
      local after = head:sub (e, e)
      local whole = not before:match ('[%w_]') and not after:match ('[%w_]')
      -- In a sentence a level word is in lower case and stands between spaces. As a level it
      -- is in capitals, starts the line, or sits in brackets or before a colon.
      if
        whole
        and (
          word == word:upper ()
          or s == first_word
          or before:match ('[%[<(|]')
          or after:match ('[:%]>)|]')
        )
      then
        return level, s
      end
    end
  end
  return nil, nil
end

-- glog and klog, as Kubernetes and gRPC write them, start a line with the level's letter and
-- the date: `E1001 12:00:00.000000 1 file.go:12] message`.
local GLOG = '^%s*([IWEF])%d%d%d%d %d%d:%d%d:%d%d'

---@param line string
---@return Logs.Level
local function detect_level (line)
  local plain = strip_ansi (line)
  local glog = plain:match (GLOG)
  if glog then
    return LETTERS[glog]
  end
  local field = field_level (plain)
  if field then
    return field
  end
  local head = plain:sub (1, 80)
  local level, at = word_level (head)
  local bracket = head:find ('%[[EWIDTFV]%]')
  if bracket and (not at or bracket < at) then
    return LETTERS[head:sub (bracket + 1, bracket + 1)]
  end
  return level or 'other'
end

---------------------------------------------------------------------------------------------
-- The filter
---------------------------------------------------------------------------------------------

---The level a `level:` value names, or nil for a name it does not know.
---@param name string
---@return Logs.Level?
local function level_named (name)
  local exact = WORDS[name]
  if exact then
    return exact
  end
  for _, pair in ipairs (LEVEL_NAMES) do
    if pair[1]:sub (1, #name) == name then
      return pair[2]
    end
  end
  return nil
end

-- The names `after:` and `before:` go by, and whether each keeps what comes before.
---@type table<string, boolean>
local TIME_WORDS =
  { after = false, since = false, before = true, ['until'] = true }

---Takes a filter apart. Words must all appear, `-word` hides lines, `"two words"` is one
---phrase, `/a|b/` is a regular expression, `level:error` keeps one level and
---`-level:error` hides one, and `after:` and `before:` keep a span of time.
---@param text string
---@return Logs.Query
local function parse_query (text)
  ---@type Logs.Query
  local query = {
    terms = {},
    phrases = {},
    exclude = {},
    skip = {},
    regexes = {},
    exclude_regexes = {},
  }
  local i, len = 1, #text
  while i <= len do
    local c = text:sub (i, i)
    if c:match ('%s') then
      i = i + 1
    else
      local negate = false
      if c == '-' and i < len and not text:sub (i + 1, i + 1):match ('%s') then
        negate = true
        i = i + 1
        c = text:sub (i, i)
      end
      if c == '"' then
        local close = text:find ('"', i + 1, true)
        local phrase = text:sub (i + 1, (close or len + 1) - 1):lower ()
        i = (close or len) + 1
        if phrase:match ('%S') then
          local into = negate and query.exclude or query.phrases
          into[#into + 1] = phrase
        end
      elseif c == '/' then
        -- A regular expression runs to the next / that has no \ before it, spaces and all.
        local j = i + 1
        while j <= len and text:sub (j, j) ~= '/' do
          if text:sub (j, j) == '\\' then
            j = j + 1
          end
          j = j + 1
        end
        local pattern = text:sub (i + 1, j - 1):gsub ('\\/', '/')
        i = j + 1
        if pattern ~= '' then
          local prog, err = re.compile (pattern, { fold = true })
          if prog then
            local into = negate and query.exclude_regexes or query.regexes
            into[#into + 1] = prog
          else
            query.problem = 'The regular expression /'
              .. pattern
              .. '/ is not valid: '
              .. tostring (err)
              .. '.'
          end
        end
      else
        local stop = text:find ('%s', i) or len + 1
        local word = text:sub (i, stop - 1):lower ()
        i = stop
        local name = word:match ('^level:(.*)$')
        local level = name and name ~= '' and level_named (name) or nil
        local time_word, time_value = word:match ('^(%a+):(.+)$')
        local keeps_before = time_word and TIME_WORDS[time_word]
        if level and negate then
          query.skip[level] = true
        elseif level then
          query.level = level
        elseif keeps_before ~= nil and not negate then
          -- The value was lowered with the word, and a time reads the same in lower case.
          local when = lt.parse_when (time_value --[[@as string]])
          if not when then
            query.problem = 'The time in '
              .. time_word
              .. ': is not one it reads. Write 2024-03-01T12:00, 12:00 or -15m.'
          elseif keeps_before then
            query.before = when
          else
            query.after = when
          end
        elseif negate then
          query.exclude[#query.exclude + 1] = word
        elseif name ~= '' then
          -- Any other word, but not a half-typed `level:`, which hides nothing yet.
          query.terms[#query.terms + 1] = word
        end
      end
    end
  end
  return query
end

---@param query Logs.Query
---@return boolean
local function has_words (query)
  return #query.terms > 0
    or #query.phrases > 0
    or #query.exclude > 0
    or #query.regexes > 0
    or #query.exclude_regexes > 0
end

---True when the query keeps a span of time.
---@param query Logs.Query
---@return boolean
local function has_time (query)
  return query.after ~= nil or query.before ~= nil
end

---@param query Logs.Query
---@return boolean
local function is_empty (query)
  return query.level == nil
    and next (query.skip) == nil
    and not has_words (query)
    and not has_time (query)
end

---True when lower-case text has every word, phrase and regular expression, and none that
---hides it.
---@param lower string
---@param query Logs.Query
---@return boolean
local function words_match (lower, query)
  for _, term in ipairs (query.terms) do
    if not lower:find (term, 1, true) then
      return false
    end
  end
  for _, phrase in ipairs (query.phrases) do
    if not lower:find (phrase, 1, true) then
      return false
    end
  end
  for _, prog in ipairs (query.regexes) do
    if not prog.find (lower) then
      return false
    end
  end
  for _, word in ipairs (query.exclude) do
    if lower:find (word, 1, true) then
      return false
    end
  end
  for _, prog in ipairs (query.exclude_regexes) do
    if prog.find (lower) then
      return false
    end
  end
  return true
end

---True when a line passes the filter. Pass the level when it is known, to save finding it.
---A query with a span of time needs the line itself, so see `matches_line`.
---@param line string
---@param query Logs.Query
---@param level? Logs.Level
---@return boolean
local function matches (line, query, level)
  if query.level or next (query.skip) then
    local found = level or detect_level (line)
    if (query.level and found ~= query.level) or query.skip[found] then
      return false
    end
  end
  if not has_words (query) then
    return true
  end
  return words_match (strip_ansi (line):lower (), query)
end

---True when a line passes the filter, its time included. A line with no time passes no span
---of time. `newest` is the time of the newest line, for a time such as `-15m`. The line keeps
---its text in lower case, so the next filter does not make it again.
---@param line Logs.Line
---@param query Logs.Query
---@param newest? number
---@return boolean
local function matches_line (line, query, newest)
  if query.level and line.level ~= query.level or query.skip[line.level] then
    return false
  end
  if query.after or query.before then
    local t = line.time
    if not t then
      return false
    end
    if query.after and not lt.passes (t, query.after, newest, false) then
      return false
    end
    if query.before and not lt.passes (t, query.before, newest, true) then
      return false
    end
  end
  if not has_words (query) then
    return true
  end
  local lower = line.lower
  if not lower then
    lower = line.plain:lower ()
    line.lower = lower
  end
  return words_match (lower, query)
end

---Where the filter's words and phrases appear in the plain text of a line, in order, with
---overlapping stretches joined.
---@param line string
---@param query Logs.Query
---@return Logs.Range[]
local function highlight (line, query)
  ---@type Logs.Range[]
  local found = {}
  ---@type string[]
  local needles = {}
  for _, term in ipairs (query.terms) do
    needles[#needles + 1] = term
  end
  for _, phrase in ipairs (query.phrases) do
    needles[#needles + 1] = phrase
  end
  if #needles == 0 and #query.regexes == 0 then
    return found
  end
  local lower = strip_ansi (line):lower ()
  for _, prog in ipairs (query.regexes) do
    local from = 1
    while from <= #lower do
      local s, e = prog.find (lower, from)
      if not s or not e then
        break
      end
      if e >= s then
        found[#found + 1] = { from = s, to = e }
      end
      from = math.max (e + 1, s + 1)
    end
  end
  for _, needle in ipairs (needles) do
    local from = 1
    while needle ~= '' do
      local s, e = lower:find (needle, from, true)
      if not s or not e then
        break
      end
      found[#found + 1] = { from = s, to = e }
      from = e + 1
    end
  end
  table.sort (found, function (a, b)
    return a.from < b.from
  end)
  ---@type Logs.Range[]
  local joined = {}
  for _, range in ipairs (found) do
    local prev = joined[#joined]
    if prev and range.from <= prev.to + 1 then
      if range.to > prev.to then
        prev.to = range.to
      end
    else
      joined[#joined + 1] = { from = range.from, to = range.to }
    end
  end
  return joined
end

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
