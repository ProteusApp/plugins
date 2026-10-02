-- log_format: formats, which take fields out of a line so the list can show them as columns.
-- A format is a regular expression with a named group for each field, such as
-- `^(?<time>\S+) (?<level>\w+) (?<msg>.*)$`, or the fields to pick from a JSON or logfmt
-- line. A field named `level`, `lvl` or `severity` also sets the line's level. The filter
-- reads `field:value`, and the list sorts by a field.

local ll = require ('log_level') --[[@as Logs.LevelModule]]
local re = require ('log_regex') --[[@as { compile: fun(pattern: string, opts?: { fold?: boolean }): LogRegex.Program?, string? }]]

local MAX_DEPTH = 32
local MAX_WIDTH = 40 -- the widest a column gets, in characters

---@alias Logs.FormatKind 'regex'|'json'|'logfmt'

---A format the user defined.
---@class Logs.Format
---@field name string
---@field kind Logs.FormatKind
---@field pattern? string For `regex`: the expression, with a named group for each field.
---@field fields string[] The fields that show as columns, in order. A regex with none shows each named group.

---A format made ready to read lines.
---@class Logs.Parser
---@field format Logs.Format
---@field fields string[] The columns, in order.
---@field extract fun(plain: string): table<string, string>? The fields of a line, or nil when the line is not in the format.

---@class Logs.FormatModule
---@field KINDS table<Logs.FormatKind, string> What each kind is called.
---@field json_fields fun(plain: string): table<string, string>?, string[]?
---@field logfmt_fields fun(plain: string): table<string, string>?, string[]?
---@field compile fun(format: Logs.Format): Logs.Parser?, string?
---@field apply fun(line: Logs.Line, parser?: Logs.Parser)
---@field discover fun(lines: Logs.Line[], kind: Logs.FormatKind, max: integer): string[]
---@field split_names fun(text: string): string[]
---@field clean_formats fun(value: any): Logs.Format[]
---@field sort_lines fun(lines: Logs.Line[], field: string, desc: boolean): Logs.Line[]
---@field widths fun(lines: Logs.Line[], fields: string[]): integer[]
---@field text_width fun(text: string): integer

---@type table<Logs.FormatKind, string>
local KINDS = {
  regex = 'Regular expression',
  json = 'JSON fields',
  logfmt = 'logfmt fields',
}

-- Fields that say a line's level.
local LEVEL_FIELDS = { 'level', 'lvl', 'severity', 'loglevel', 'log.level' }

---------------------------------------------------------------------------------------------
-- JSON
---------------------------------------------------------------------------------------------

---@type table<string, string>
local JSON_ESCAPES = {
  n = '\n',
  t = '\t',
  r = '\r',
  b = '\b',
  f = '\f',
  ['"'] = '"',
  ['\\'] = '\\',
  ['/'] = '/',
}

---@param s string
---@param i integer
---@return integer
local function skip_space (s, i)
  return s:find ('[^ \t\r\n]', i) or #s + 1
end

---Reads a JSON string that starts at `i`. Returns its text and the position after it.
---@param s string
---@param i integer
---@return string?
---@return integer?
local function read_string (s, i)
  local out = {} ---@type string[]
  local at = i + 1
  while true do
    local c = s:find ('["\\]', at)
    if not c then
      return nil, nil
    end
    out[#out + 1] = s:sub (at, c - 1)
    if s:sub (c, c) == '"' then
      return table.concat (out), c + 1
    end
    local e = s:sub (c + 1, c + 1)
    if e == 'u' then
      local hex = s:match ('^%x%x%x%x', c + 2)
      if not hex then
        return nil, nil
      end
      out[#out + 1] = utf8.char (tonumber (hex, 16) or 63)
      at = c + 6
    elseif JSON_ESCAPES[e] then
      out[#out + 1] = JSON_ESCAPES[e]
      at = c + 2
    else
      return nil, nil
    end
  end
end

---Reads one JSON value at `i`. An object's fields go into `out` under `prefix`, a nested
---object's as `outer.inner`, and `keys` gets each name the first time. Any other value goes
---into `out[prefix]` as text: a string as it reads, an array as its JSON. With no `out`, it
---only finds where the value ends. Returns the position after the value, or nil.
---@param s string
---@param i integer
---@param depth integer
---@param prefix? string
---@param out? table<string, string>
---@param keys? string[]
---@return integer?
local function read_value (s, i, depth, prefix, out, keys)
  if depth > MAX_DEPTH then
    return nil
  end
  local c = s:sub (i, i)
  ---@param value string
  local function put (value)
    if out and prefix then
      if out[prefix] == nil and keys then
        keys[#keys + 1] = prefix
      end
      out[prefix] = value
    end
  end
  if c == '{' then
    local at = skip_space (s, i + 1)
    if s:sub (at, at) == '}' then
      return at + 1
    end
    while true do
      if s:sub (at, at) ~= '"' then
        return nil
      end
      local key, after_key = read_string (s, at)
      if not key or not after_key then
        return nil
      end
      at = skip_space (s, after_key)
      if s:sub (at, at) ~= ':' then
        return nil
      end
      at = skip_space (s, at + 1)
      local name = prefix and (prefix .. '.' .. key) or key
      local after = read_value (s, at, depth + 1, name, out, keys)
      if not after then
        return nil
      end
      at = skip_space (s, after)
      local sep = s:sub (at, at)
      if sep == '}' then
        return at + 1
      end
      if sep ~= ',' then
        return nil
      end
      at = skip_space (s, at + 1)
    end
  end
  if c == '[' then
    local at = skip_space (s, i + 1)
    if s:sub (at, at) ~= ']' then
      while true do
        local after = read_value (s, at, depth + 1)
        if not after then
          return nil
        end
        at = skip_space (s, after)
        local sep = s:sub (at, at)
        if sep == ']' then
          break
        end
        if sep ~= ',' then
          return nil
        end
        at = skip_space (s, at + 1)
      end
    end
    put (s:sub (i, at))
    return at + 1
  end
  if c == '"' then
    local text, after = read_string (s, i)
    if text then
      put (text)
    end
    return after
  end
  local word = s:match ('^%a+', i)
  if word == 'true' or word == 'false' then
    put (word)
    return i + #word
  end
  if word == 'null' then
    put ('')
    return i + 4
  end
  local number = s:match ('^%-?%d+%.?%d*[eE]?[%+%-]?%d*', i)
  if number and number ~= '' and number ~= '-' then
    put (number)
    return i + #number
  end
  return nil
end

---The fields of the JSON object a line ends with, such as the part after a time. Nested
---objects give `outer.inner`. Returns the fields and their names in order, or nil.
---@param plain string
---@return table<string, string>?
---@return string[]?
local function json_fields (plain)
  local start = plain:find ('{', 1, true)
  local tries = 0
  while start and tries < 20 do
    tries = tries + 1
    local out, keys = {}, {} ---@type table<string, string>, string[]
    local after = read_value (plain, start, 0, nil, out, keys)
    if after and not plain:find ('%S', after) then
      return out, keys
    end
    start = plain:find ('{', start + 1, true)
  end
  return nil, nil
end

---------------------------------------------------------------------------------------------
-- logfmt
---------------------------------------------------------------------------------------------

---The `key=value` fields of a logfmt line, such as `level=warn msg="disk full" took=3ms`.
---Words that are no field are passed over. Returns the fields and their names in order, or
---nil when the line has none.
---@param plain string
---@return table<string, string>?
---@return string[]?
local function logfmt_fields (plain)
  local out, keys = {}, {} ---@type table<string, string>, string[]
  local pos, len = 1, #plain
  while pos <= len do
    pos = plain:find ('%S', pos) or len + 1
    if pos > len then
      break
    end
    local key, after = plain:match ('^([%a_@][%w_%.@/%-]*)=()', pos)
    if key then
      local value ---@type string
      if plain:sub (after, after) == '"' then
        local parts = {} ---@type string[]
        local at = after + 1
        while at <= len do
          local c = plain:find ('["\\]', at)
          if not c then
            parts[#parts + 1] = plain:sub (at)
            at = len + 1
            break
          end
          parts[#parts + 1] = plain:sub (at, c - 1)
          if plain:sub (c, c) == '"' then
            at = c + 1
            break
          end
          local e = plain:sub (c + 1, c + 1)
          parts[#parts + 1] = e == 'n' and '\n' or (e == 't' and '\t' or e)
          at = c + 2
        end
        value = table.concat (parts)
        pos = at
      else
        value = plain:match ('^%S*', after)
        pos = after + #value
      end
      if out[key] == nil then
        keys[#keys + 1] = key
      end
      out[key] = value
    else
      pos = plain:find ('%s', pos) or len + 1
    end
  end
  if #keys == 0 then
    return nil, nil
  end
  return out, keys
end

---------------------------------------------------------------------------------------------
-- Formats
---------------------------------------------------------------------------------------------

---Field names from text such as `level, msg  user.id`.
---@param text string
---@return string[]
local function split_names (text)
  local out = {} ---@type string[]
  local seen = {} ---@type table<string, boolean>
  for name in text:gmatch ('[^,%s]+') do
    if not seen[name] then
      seen[name] = true
      out[#out + 1] = name
    end
  end
  return out
end

---Makes a format ready to read lines. Returns nil and what is wrong with it.
---@param format Logs.Format
---@return Logs.Parser?
---@return string?
local function compile (format)
  local fields = format.fields or {}
  if format.kind == 'regex' then
    local prog, err = re.compile (format.pattern or '')
    if not prog then
      return nil,
        'The regular expression is not valid: ' .. tostring (err) .. '.'
    end
    local names = prog.names
    if #names == 0 then
      return nil,
        'The regular expression names no group. Name one for each field, such as (?<level>\\w+).'
    end
    local known = {} ---@type table<string, boolean>
    for _, name in ipairs (names) do
      known[name] = true
    end
    for _, name in ipairs (fields) do
      if not known[name] then
        return nil, 'The regular expression has no group named ' .. name .. '.'
      end
    end
    local want = #fields > 0 and fields or names
    return {
      format = format,
      fields = want,
      extract = function (plain)
        local got = prog.match (plain)
        if not got then
          return nil
        end
        local out = {} ---@type table<string, string>
        for _, name in ipairs (names) do
          local value = got[name]
          if value then
            out[name] = value
          end
        end
        return out
      end,
    },
      nil
  end
  if format.kind ~= 'json' and format.kind ~= 'logfmt' then
    return nil,
      'A format is a regular expression, JSON fields or logfmt fields.'
  end
  if #fields == 0 then
    return nil, 'Name at least one field to show.'
  end
  local read = format.kind == 'json' and json_fields or logfmt_fields
  return {
    format = format,
    fields = fields,
    extract = function (plain)
      local out = read (plain)
      return out
    end,
  },
    nil
end

---Gives a line the fields of a format, or takes them away when there is none. A field that
---names a level sets the line's level, and the line's own words set it otherwise.
---@param line Logs.Line
---@param parser? Logs.Parser
local function apply (line, parser)
  local fields = parser and parser.extract (line.plain) or nil
  line.fields = fields
  local level = nil ---@type Logs.Level?
  if fields then
    for _, name in ipairs (LEVEL_FIELDS) do
      local value = fields[name]
      if value and value:match ('%S') then
        level = ll.level_named (value:lower ():match ('^%s*(.-)%s*$'))
        break
      end
    end
  end
  if level then
    line.level = level
    line.field_level = true
  elseif line.field_level then
    line.level = ll.detect_level (line.plain)
    line.field_level = nil
  end
end

---The JSON or logfmt field names lines hold, the most common first, up to `max`.
---@param lines Logs.Line[]
---@param kind Logs.FormatKind
---@param max integer
---@return string[]
local function discover (lines, kind, max)
  local read = kind == 'logfmt' and logfmt_fields or json_fields
  local count, first = {}, {} ---@type table<string, integer>, table<string, integer>
  local order = {} ---@type string[]
  for _, line in ipairs (lines) do
    local _, keys = read (line.plain)
    for _, key in ipairs (keys or {}) do
      if not count[key] then
        order[#order + 1] = key
        first[key] = #order
        count[key] = 0
      end
      count[key] = count[key] + 1
    end
  end
  table.sort (order, function (a, b)
    if count[a] ~= count[b] then
      return count[a] > count[b]
    end
    return first[a] < first[b]
  end)
  local out = {} ---@type string[]
  for i = 1, math.min (max, #order) do
    out[i] = order[i]
  end
  return out
end

---Saved formats, with anything malformed left out, and one format to a name.
---@param value any
---@return Logs.Format[]
local function clean_formats (value)
  local out = {} ---@type Logs.Format[]
  if type (value) ~= 'table' then
    return out
  end
  local seen = {} ---@type table<string, boolean>
  for _, v in
    ipairs (value --[[@as table<string, any>[] ]])
  do
    local name, kind =
      type (v) == 'table' and v.name, type (v) == 'table' and v.kind
    if
      type (name) == 'string'
      and name:match ('%S')
      and not seen[name]
      and KINDS[kind]
    then
      local fields = {} ---@type string[]
      if type (v.fields) == 'table' then
        for _, f in
          ipairs (v.fields --[[@as any[] ]])
        do
          if type (f) == 'string' and f ~= '' then
            fields[#fields + 1] = f
          end
        end
      end
      local pattern = type (v.pattern) == 'string' and v.pattern or nil
      if kind ~= 'regex' or pattern then
        seen[name] = true
        out[#out + 1] = {
          name = name,
          kind = kind,
          pattern = kind == 'regex' and pattern or nil,
          fields = fields,
        }
      end
    end
  end
  return out
end

---How lines sort by a field: numbers by size and the rest by text, ignoring case.
---@param value? string
---@return number|string|nil
local function sort_key (value)
  if value == nil or value == '' then
    return nil
  end
  local n = tonumber (value)
  if n then
    return n
  end
  return value:lower ()
end

---The lines sorted by a field. Lines without it go last, and lines with the same value keep
---their order.
---@param lines Logs.Line[]
---@param field string
---@param desc boolean
---@return Logs.Line[]
local function sort_lines (lines, field, desc)
  ---@type { line: Logs.Line, key: number|string|nil, i: integer }[]
  local items = {}
  for i, line in ipairs (lines) do
    items[i] = {
      line = line,
      key = sort_key (line.fields and line.fields[field] or nil),
      i = i,
    }
  end
  table.sort (items, function (a, b)
    local ka, kb = a.key, b.key
    if ka == nil or kb == nil then
      if (ka == nil) ~= (kb == nil) then
        return kb == nil
      end
      return a.i < b.i
    end
    if type (ka) ~= type (kb) then
      -- Numbers go before text.
      return (type (ka) == 'number') ~= desc
    end
    if ka ~= kb then
      if desc then
        return ka > kb
      end
      return ka < kb
    end
    return a.i < b.i
  end)
  local out = {} ---@type Logs.Line[]
  for i, item in ipairs (items) do
    out[i] = item.line
  end
  return out
end

---How many characters wide text shows, counting each UTF-8 character once.
---@param text string
---@return integer
local function text_width (text)
  local _, n = text:gsub ('[^\128-\191]', '')
  return n
end

---How wide each column shows, in characters: its widest value or its name, up to 40.
---@param lines Logs.Line[]
---@param fields string[]
---@return integer[]
local function widths (lines, fields)
  local out = {} ---@type integer[]
  for i, name in ipairs (fields) do
    out[i] = math.max (3, text_width (name) + 2)
  end
  for _, line in ipairs (lines) do
    local f = line.fields
    if f then
      for i, name in ipairs (fields) do
        local v = f[name]
        if v and #v >= out[i] then
          out[i] = math.min (MAX_WIDTH, math.max (out[i], text_width (v)))
        end
      end
    end
  end
  return out
end

---@type Logs.FormatModule
return {
  KINDS = KINDS,
  json_fields = json_fields,
  logfmt_fields = logfmt_fields,
  compile = compile,
  apply = apply,
  discover = discover,
  split_names = split_names,
  clean_formats = clean_formats,
  sort_lines = sort_lines,
  widths = widths,
  text_width = text_width,
}
