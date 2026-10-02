-- log_query: the log viewer's filter. It takes the text of the filter box apart into words,
-- phrases, regular expressions, levels, fields and a span of time, tells whether a line
-- passes, and finds where the words and expressions appear in a line so the list can mark
-- them.

local ansi = require ('log_ansi') --[[@as Logs.AnsiModule]]
local ll = require ('log_level') --[[@as Logs.LevelModule]]
local lt = require ('log_time') --[[@as Logs.TimeModule]]
local re = require ('log_regex') --[[@as { compile: fun(pattern: string, opts?: { fold?: boolean }): LogRegex.Program?, string? }]]

local strip_ansi = ansi.strip_ansi
local detect_level, level_named = ll.detect_level, ll.level_named

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
---@field marked? boolean Keeps only bookmarked lines, from `is:marked`.
---@field unmarked? boolean Hides bookmarked lines, from `-is:marked`.
---@field fields Logs.FieldTest[] Tests of a line's fields, from `field:value`.
---@field problem? string What the filter could not read, such as a broken regular expression.

---A test of one field of a line, such as `status:>=500` or `-user:bot`.
---@class Logs.FieldTest
---@field name string The field, as the format names it.
---@field op ':'|'='|'>'|'<'|'>='|'<=' `:` finds the value in the field, `=` wants it whole, and the rest compare.
---@field value string In lower case.
---@field number? number The value as a number, for a comparison.
---@field negate boolean True for `-field:value`, which hides the lines that pass.

---A stretch of text the filter matched, as byte positions in the plain text.
---@class Logs.Range
---@field from integer
---@field to integer

---@class Logs.QueryModule
---@field parse_query fun(text: string, fields?: table<string, string>): Logs.Query
---@field is_empty fun(query: Logs.Query): boolean True when the query hides nothing.
---@field has_time fun(query: Logs.Query): boolean
---@field matches fun(line: string, query: Logs.Query, level?: Logs.Level): boolean
---@field matches_line fun(line: Logs.Line, query: Logs.Query, newest?: number): boolean
---@field highlight fun(line: string, query: Logs.Query): Logs.Range[]

-- The names `after:` and `before:` go by, and whether each keeps what comes before.
---@type table<string, boolean>
local TIME_WORDS =
  { after = false, since = false, before = true, ['until'] = true }

---Takes a filter apart. Words must all appear, `-word` hides lines, `"two words"` is one
---phrase, `/a|b/` is a regular expression, `level:error` keeps one level and
---`-level:error` hides one, `after:` and `before:` keep a span of time, and `is:marked`
---keeps the bookmarked lines. `fields` maps the lower-case name of each field the formats
---show to its name, and `name:value` tests that field.
---@param text string
---@param fields? table<string, string>
---@return Logs.Query
local function parse_query (text, fields)
  local known = fields or {}
  ---@type Logs.Query
  local query = {
    terms = {},
    phrases = {},
    exclude = {},
    skip = {},
    regexes = {},
    exclude_regexes = {},
    fields = {},
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
        -- A field's value may be in quotes, spaces and all: msg:"disk full".
        local quote_at = text:match ('^[^%s:"]+:[=<>]*()"', i)
        if quote_at and quote_at < stop then
          local close = text:find ('"', quote_at + 1, true)
          stop = (close or len) + 1
        end
        local word = text:sub (i, stop - 1):lower ()
        i = stop
        local field_name, field_rest = word:match ('^([^:]+):(.*)$')
        local field = field_name and known[field_name] or nil
        local name = word:match ('^level:(.*)$')
        local level = name and name ~= '' and level_named (name) or nil
        local time_word, time_value = word:match ('^(%a+):(.+)$')
        local keeps_before = time_word and TIME_WORDS[time_word]
        if field and field_name ~= 'level' then
          local op, value = field_rest:match ('^([=<>]*)(.*)$')
          value = value:gsub ('^"(.*)"?$', '%1'):gsub ('"$', '')
          if op == '' then
            op = ':'
          end
          local number = tonumber (value)
          local compares = op ~= ':' and op ~= '='
          if
            value ~= ''
            and (
              op == ':'
              or op == '='
              or op == '>'
              or op == '<'
              or op == '>='
              or op == '<='
            )
          then
            query.fields[#query.fields + 1] = {
              name = field,
              op = op --[[@as ':'|'='|'>'|'<'|'>='|'<=']],
              value = value,
              number = compares and number or nil,
              negate = negate,
            }
          elseif value ~= '' then
            query.problem = 'The test in '
              .. field_name
              .. ': is not one it reads. Write '
              .. field_name
              .. ':value, '
              .. field_name
              .. ':=value or '
              .. field_name
              .. ':>10.'
          end
        elseif word == 'is:marked' or word == 'is:bookmarked' then
          if negate then
            query.unmarked = true
          else
            query.marked = true
          end
        elseif level and negate then
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
  return #query.fields > 0
    or #query.terms > 0
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
    and not query.marked
    and not query.unmarked
    and next (query.skip) == nil
    and not has_words (query)
    and not has_time (query)
end

---True when a field passes a test.
---@param value? string
---@param test Logs.FieldTest
---@return boolean
local function field_passes (value, test)
  if value == nil then
    return false
  end
  local op = test.op
  if op == ':' then
    return value:lower ():find (test.value, 1, true) ~= nil
  elseif op == '=' then
    return value:lower () == test.value
  end
  local a, b = tonumber (value), test.number ---@type number|string?, number|string?
  if not a or not b then
    a, b = value:lower (), test.value
  end
  if op == '>' then
    return a > b
  elseif op == '<' then
    return a < b
  elseif op == '>=' then
    return a >= b
  end
  return a <= b
end

---True when a line's fields pass every test.
---@param line Logs.Line
---@param query Logs.Query
---@return boolean
local function fields_match (line, query)
  local fields = line.fields
  for _, test in ipairs (query.fields) do
    local value = fields and fields[test.name] or nil
    if field_passes (value, test) == test.negate then
      return false
    end
  end
  return true
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
  if (query.marked and not line.marked) or (query.unmarked and line.marked) then
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
  if #query.fields > 0 and not fields_match (line, query) then
    return false
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

---@type Logs.QueryModule
local M = {
  parse_query = parse_query,
  is_empty = is_empty,
  has_time = has_time,
  matches = matches,
  matches_line = matches_line,
  highlight = highlight,
}

return M
