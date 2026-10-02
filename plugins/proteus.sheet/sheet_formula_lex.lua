-- sheet_formula_lex: the ground of the Sheet app's formula language. It holds the error
-- values, cell addresses, text that knows Latin-1 letters, numbers and dates read from text and
-- written as text, and the tokenizer that splits formula text into tokens.
--
-- It makes the module table sheet_formula returns. The parser, the evaluator, the function kit
-- and the formula editing helpers each add their functions to it.

local calendar = require ('sheet_calendar') --[[@as Sheet.CalendarModule]]
local format = require ('sheet_format') --[[@as Sheet.FormatModule]]

---@class Sheet.FormulaModule
---@field ERROR_CODES string[]
---@field functions string[] Every function name, sorted.
---@field catalog Sheet.CatalogEntry[] Every function, sorted by name.
local M = {}

local MANY = 255
local MAX_DEPTH = 64
-- The last row and column a sheet has, 1048576 and XFD, as in Excel.
local LAST_ROW = 1048576
local LAST_COL = 16384
M.LAST_ROW = LAST_ROW
M.LAST_COL = LAST_COL
-- Serial day numbers count from 1899-12-30, as spreadsheets do, so 1970-01-01 is 25569.
local EPOCH = 25569
-- The last day spreadsheets allow, 9999-12-31.
local LAST_DAY = 2958465

-- Lua 5.4 takes a base in math.log and two arguments in math.atan. selene reads the Lua 5.1
-- library, which has neither, so the calls go through these names.
local log = math.log --[[@as fun(x: number, base?: number): number]]
local atan = math.atan --[[@as fun(y: number, x?: number): number]]

M.ERROR_CODES = {
  '#DIV/0!',
  '#VALUE!',
  '#REF!',
  '#NAME?',
  '#N/A',
  '#NUM!',
  '#CYCLE!',
  '#ERROR!',
  '#NULL!',
  '#SPILL!',
  '#CALC!',
}

---@type table<string, Sheet.Error>
local ERRORS = {}
for _, code in ipairs (M.ERROR_CODES) do
  ERRORS[code] = { code = code }
end

---@param code string
---@return Sheet.Error
function M.error (code)
  return ERRORS[code] or ERRORS['#VALUE!']
end

---@param v any
---@return boolean
function M.is_error (v)
  return type (v) == 'table' and v.code ~= nil and ERRORS[v.code] == v
end
local is_error = M.is_error

---@param code string
---@return any
local function raise (code)
  error (ERRORS[code], 0)
end

---@param err any
---@return any
local function raise_value (err)
  error (err, 0)
end

---@param n number
---@return number
local function finite (n)
  if n ~= n or n == math.huge or n == -math.huge then
    return raise ('#NUM!')
  end
  return n
end

---Cuts a number toward zero.
---@param n number
---@return integer
local function trunc (n)
  if n >= 0 then
    return math.floor (n)
  end
  return math.ceil (n)
end

---Drops float noise, so 3.0000000000000004 becomes 3 before a floor or a ceiling.
---@param n number
---@return number
local function clean (n)
  return tonumber (string.format ('%.15g', n)) or n
end

---@param text string
---@return boolean
function M.is_formula (text)
  return type (text) == 'string'
    and #text > 1
    and string.sub (text, 1, 1) == '='
end

---------------------------------------------------------------------------------------------
-- Addresses
---------------------------------------------------------------------------------------------

---Turns a column number into letters: 1 is A, 27 is AA.
---@param n integer
---@return string
function M.col_name (n)
  local s = ''
  while n > 0 do
    local rem = (n - 1) % 26
    s = string.char (65 + rem) .. s
    n = math.floor ((n - 1) / 26)
  end
  return s
end

---Turns column letters into a number, or nil when they are not letters.
---@param letters string
---@return integer?
function M.col_number (letters)
  if not string.match (letters, '^%a+$') then
    return nil
  end
  local up = string.upper (letters)
  local n = 0
  for i = 1, #up do
    n = n * 26 + (string.byte (up, i) - 64)
  end
  return n
end

---@param row integer
---@param col integer
---@return string
function M.address (row, col)
  return M.col_name (col) .. string.format ('%d', row)
end

---Reads an address such as `B12` or `$B$12`. Returns the row and the column.
---@param text string
---@return integer? row
---@return integer? col
function M.parse_address (text)
  local letters, digits =
    string.match (text, '^%s*%$?(%a%a?%a?)%$?(%d%d?%d?%d?%d?%d?%d?)%s*$')
  if not letters then
    return nil, nil
  end
  local row = math.tointeger (tonumber (digits))
  if not row or row < 1 then
    return nil, nil
  end
  return row, M.col_number (letters)
end

-- A sheet name may go without quotes when it looks like this and not like a cell.
local PLAIN_SHEET = '^[%a_\128-\255][%w_%.\128-\255]*$'

---Writes a sheet name the way a reference does: `Sales`, or `'Q1 sales'` when the name needs
---quotes. A quote inside the name is written twice.
---@param name string
---@return string
function M.quote_sheet (name)
  local up = string.upper (name)
  if
    string.match (name, PLAIN_SHEET)
    and not string.match (name, '^%a%a?%a?%d+$')
    and not string.match (up, '^R%d*C%d*$')
    and not string.match (up, '^[RC]%d*$')
    and up ~= 'TRUE'
    and up ~= 'FALSE'
  then
    return name
  end
  return "'" .. (string.gsub (name, "'", "''")) .. "'"
end

---------------------------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------------------------

-- Latin-1 letters such as é take two bytes in UTF-8, the first of them 195. Upper and lower
-- case differ by 32 in the second byte, except for × and ÷, which have no case.
local TO_UPPER = {} ---@type table<string, string>
local TO_LOWER = {} ---@type table<string, string>
for b = 160, 190 do
  if b ~= 183 then
    TO_UPPER[string.char (b)] = '\195' .. string.char (b - 32)
    TO_LOWER[string.char (b - 32)] = '\195' .. string.char (b)
  end
end

---@param s string
---@return string
local function upper (s)
  local out = string.upper (s)
  if string.find (out, '\195', 1, true) then
    out = string.gsub (out, '\195([\160-\190])', TO_UPPER)
  end
  return out
end

---@param s string
---@return string
local function lower (s)
  local out = string.lower (s)
  if string.find (out, '\195', 1, true) then
    out = string.gsub (out, '\195([\128-\158])', TO_LOWER)
  end
  return out
end

---@param s string
---@return string[]
local function chars (s)
  local out = {} ---@type string[]
  for ch in string.gmatch (s, utf8.charpattern) do
    out[#out + 1] = ch
  end
  return out
end

---The number of characters in text, not bytes.
---@param s string
---@return integer
local function length (s)
  return utf8.len (s) or #chars (s)
end

---The byte where character `n` starts, or one past the end.
---@param s string
---@param n integer
---@return integer
local function byte_of (s, n)
  if n <= 1 then
    return 1
  end
  return utf8.offset (s, n) or (#s + 1)
end

---Turns a pattern with `*` and `?` into a Lua pattern. `~*`, `~?` and `~~` stand for the
---character itself. `anchored` makes the pattern match the whole text.
---@param text string
---@param anchored boolean
---@return string
local function wildcard (text, anchored)
  local out = {} ---@type string[]
  if anchored then
    out[1] = '^'
  end
  local i = 1
  while i <= #text do
    local ch = string.sub (text, i, i)
    local after = string.sub (text, i + 1, i + 1)
    if ch == '~' and (after == '*' or after == '?' or after == '~') then
      out[#out + 1] = '%' .. after
      i = i + 2
    else
      if ch == '*' then
        out[#out + 1] = '.*'
      elseif ch == '?' then
        out[#out + 1] = utf8.charpattern
      elseif string.match (ch, '%W') then
        out[#out + 1] = '%' .. ch
      else
        out[#out + 1] = ch
      end
      i = i + 1
    end
  end
  if anchored then
    out[#out + 1] = '$'
  end
  return table.concat (out)
end

---------------------------------------------------------------------------------------------
-- Numbers, dates and text
---------------------------------------------------------------------------------------------

---Reads text as a number the way a cell does: `12`, `-3.5`, `1,200`, `1e3` or `15%`.
---Returns nil for anything else.
---@param text string
---@return number?
function M.parse_number (text)
  local s = string.match (text, '^%s*(.-)%s*$')
  local scale = 1
  if string.sub (s, -1) == '%' then
    scale = 0.01
    s = string.sub (s, 1, -2)
  end
  local sign, body = string.match (s, '^([+-]?)(.*)$')
  local mantissa, exponent = string.match (body, '^([%d%.,]+)([eE][+-]?%d+)$')
  if not mantissa then
    mantissa, exponent = body, ''
  end
  if string.find (mantissa, ',', 1, true) then
    if exponent ~= '' then
      return nil
    end
    local whole = string.match (mantissa, '^([%d,]+)%.?%d*$')
    if not whole then
      return nil
    end
    -- Commas must group digits in threes, as in 1,234,567.
    while string.match (whole, ',%d%d%d$') do
      whole = string.sub (whole, 1, -5)
    end
    if not string.match (whole, '^%d%d?%d?$') then
      return nil
    end
    mantissa = (string.gsub (mantissa, ',', ''))
  end
  if
    not string.match (mantissa, '^%d+%.?%d*$')
    and not string.match (mantissa, '^%.%d+$')
  then
    return nil
  end
  local n = tonumber (sign .. mantissa .. exponent)
  if not n then
    return nil
  end
  return (n + 0.0) * scale
end

---Shows a number with up to `digits` significant digits, 10 when nil, so float noise such as
---0.30000000000000004 shows as 0.3.
---@param n number
---@param digits? integer
---@return string
function M.format_number (n, digits)
  if n ~= n or n == math.huge or n == -math.huge then
    return '#NUM!'
  end
  if n == 0 then
    return '0'
  end
  local s = string.format ('%.' .. (digits or 10) .. 'g', n)
  return (string.gsub (s, 'e', 'E'))
end

---Shows any value as text.
---@param v Sheet.Value
---@param digits? integer
---@return string
function M.format_value (v, digits)
  if v == nil then
    return ''
  end
  local t = type (v)
  if t == 'number' then
    return M.format_number (v --[[@as number]], digits)
  end
  if t == 'string' then
    return v --[[@as string]]
  end
  if t == 'boolean' then
    return v and 'TRUE' or 'FALSE'
  end
  return (v --[[@as Sheet.Error]]).code
end

---A date and time as a serial number of days, the way spreadsheets store dates. The calendar
---is sheet_calendar's, so every part of the app counts days the same way.
---@param y integer
---@param m integer
---@param d integer
---@param h? integer
---@param mi? integer
---@param s? integer
---@return number
function M.serial (y, m, d, h, mi, s)
  return calendar.serial (y, m, d, h, mi, s)
end

---The parts of a serial date: year, month, day, hour, minute and second.
---@param serial number
---@return integer y
---@return integer m
---@return integer d
---@return integer h
---@return integer mi
---@return integer s
function M.date_parts (serial)
  local y, m, d, h, mi, s = calendar.date_parts (serial)
  return y, m, d, h, mi, s
end

---The year, month and day of a serial date, ignoring the time.
---@param serial number
---@return integer y
---@return integer m
---@return integer d
local function ymd (serial)
  local y, m, d = calendar.date_parts (math.floor (serial))
  return y, m, d
end

local is_leap = calendar.is_leap
local days_in_month = calendar.days_in_month

---A serial date from a year, month and day that may run over, as DATE works: month 13 is
---January of the next year, and day 0 is the last day of the month before.
---@param y integer
---@param m integer
---@param d integer
---@return integer
local function make_date (y, m, d)
  return math.floor (calendar.serial (y, m, d))
end

---The day of the week of a serial date, 0 for Sunday to 6 for Saturday.
---@param serial number
---@return integer
local function weekday0 (serial)
  return (math.floor (serial) - EPOCH + 4) % 7
end

---The local date and time now, as a serial number.
---@return number
function M.clock ()
  local t = os.date ('*t') --[[@as osdate]]
  return M.serial (t.year, t.month, t.day, t.hour, t.min, t.sec)
end

---Shows a serial date as `2026-09-29`, or `2026-09-29 14:30` with the time.
---@param serial number
---@param with_time? boolean
---@return string
function M.format_date (serial, with_time)
  local y, m, d, h, mi = M.date_parts (serial)
  local text = string.format ('%04d-%02d-%02d', y, m, d)
  if with_time then
    text = text .. string.format (' %02d:%02d', h, mi)
  end
  return text
end

---Reads a date, a time, or a date and a time from text, as a serial number. Typing into a cell
---reads text the same way.
---@param text string
---@param clock? fun(): number Gives the year of a date written without one.
---@return number?
local function parse_datetime (text, clock)
  return (calendar.read (text, clock))
end

---Rounds a number to `digits` decimals. `mode` is 'near' (half away from zero), 'up' (away
---from zero) or 'down' (toward zero). The %.15g step drops float noise first, so 2.675 rounds
---to 2.68 as it does on paper.
---@param x number
---@param digits integer
---@param mode 'near'|'up'|'down'
---@return number
local function round_to (x, digits, mode)
  if digits > 15 then
    return x
  end
  if digits < -15 then
    digits = -15
  end
  local sign = x < 0 and -1 or 1
  local scale = 10 ^ math.abs (digits)
  local ax = math.abs (x)
  local scaled = digits >= 0 and ax * scale or ax / scale
  scaled = tonumber (string.format ('%.15g', scaled)) or scaled
  local r ---@type number
  if mode == 'near' then
    r = math.floor (scaled + 0.5)
  elseif mode == 'up' then
    r = math.ceil (scaled)
  else
    r = math.floor (scaled)
  end
  if digits >= 0 then
    return sign * (r / scale)
  end
  return sign * (r * scale)
end

---Formats a number the way the TEXT function does, through sheet_format, so a cell's number
---format and TEXT show a value the same way.
---@param n number
---@param fmt string
---@return string
function M.format (n, fmt)
  return (format.format (n, fmt))
end

---------------------------------------------------------------------------------------------
-- Tokenizer
---------------------------------------------------------------------------------------------

---@param digits string
---@return integer?
local function to_row (digits)
  if #digits > 7 then
    return nil
  end
  local row = math.tointeger (tonumber (digits))
  if not row or row < 1 then
    return nil
  end
  return row
end

---Reads one end of a reference at `i`: a cell such as `$B$2`, a column such as `B`, or a row
---such as `2`. Returns the reference, the index after it, and which of the three it is.
---@param src string
---@param i integer
---@return Sheet.Ref?
---@return integer
---@return 'cell'|'col'|'row'|nil
local function ref_part (src, i)
  local d1, letters, d2, digits = string.match (src, '^(%$?)(%a*)(%$?)(%d*)', i)
  if not d1 then
    return nil, i, nil
  end
  local next_i = i + #d1 + #letters + #d2 + #digits
  if letters ~= '' and #letters <= 3 then
    local col = M.col_number (letters) --[[@as integer]]
    if digits ~= '' then
      local row = to_row (digits)
      if not row then
        return nil, i, nil
      end
      return { row = row, col = col, row_abs = d2 == '$', col_abs = d1 == '$' },
        next_i,
        'cell'
    end
    if d2 == '' then
      return { col = col, col_abs = d1 == '$', row_abs = false }, next_i, 'col'
    end
  end
  if letters == '' and d2 == '' and digits ~= '' then
    local row = to_row (digits)
    if row then
      return { row = row, row_abs = d1 == '$', col_abs = false }, next_i, 'row'
    end
  end
  return nil, i, nil
end

---@param ch string
---@return boolean
local function joins_word (ch)
  return string.match (ch, '[%w_%.%(%$]') ~= nil
end

---Reads a reference, a range, a number or a name at `i`.
---@param src string
---@param i integer
---@return Sheet.Token?
local function read_word (src, i)
  local a, j, shape = ref_part (src, i)
  if a and string.sub (src, j, j) == ':' then
    local b, k, shape_b = ref_part (src, j + 1)
    if b and shape_b == shape and not joins_word (string.sub (src, k, k)) then
      return {
        kind = 'range',
        text = string.sub (src, i, k - 1),
        from = i,
        to = k - 1,
        a = a,
        b = b,
      }
    end
  end
  if a and shape == 'cell' and not joins_word (string.sub (src, j, j)) then
    -- A1# is the block the formula in A1 spills.
    local spill = string.sub (src, j, j) == '#'
    local stop = spill and j or j - 1
    return {
      kind = 'ref',
      text = string.sub (src, i, stop),
      from = i,
      to = stop,
      a = a,
      spill = spill or nil,
    }
  end
  local num = string.match (src, '^%d*%.?%d*', i) or ''
  if num ~= '' and num ~= '.' then
    local exp = string.match (src, '^[eE][+-]?%d+', i + #num) or '' ---@type string
    local text = num .. exp ---@type string
    if string.match (string.sub (src, i + #text, i + #text), '[%a_]') then
      return nil
    end
    return {
      kind = 'number',
      text = text,
      from = i,
      to = i + #text - 1,
      value = (tonumber (text) or 0) + 0.0,
    }
  end
  local name = string.match (src, '^[%a_][%w_%.]*', i)
  if name then
    return { kind = 'name', text = name, from = i, to = i + #name - 1 }
  end
  return nil
end

---Reads a sheet name and its "!" at `i`, in quotes or not. Returns the name without quotes and
---the index after the "!", or nil when no sheet name starts there.
---@param src string
---@param i integer
---@return string?
---@return integer
local function sheet_prefix (src, i)
  if string.sub (src, i, i) ~= "'" then
    local name = string.match (src, '^([%a_\128-\255][%w_%.\128-\255]*)!', i)
    if name then
      return name, i + #name + 1
    end
    return nil, i
  end
  local parts = {} ---@type string[]
  local j = i + 1
  while true do
    local q = string.find (src, "'", j, true)
    if not q then
      return nil, i
    end
    parts[#parts + 1] = string.sub (src, j, q - 1)
    if string.sub (src, q + 1, q + 1) == "'" then
      parts[#parts + 1] = "'"
      j = q + 2
    else
      local name = table.concat (parts)
      if name == '' or string.sub (src, q + 1, q + 1) ~= '!' then
        return nil, i
      end
      return name, q + 2
    end
  end
end

---Splits formula text into tokens from byte `start`. In strict mode it returns nil and a
---message at the first thing it cannot read. In lenient mode, for text still being typed, it
---skips what it cannot read and ends an open quote at the end of the text.
---@param src string
---@param start integer
---@param lenient boolean
---@return Sheet.Token[]?
---@return string?
local function lex (src, start, lenient)
  local tokens = {} ---@type Sheet.Token[]
  local i = start
  local n = #src
  local braces = 0
  while i <= n do
    local ch = string.sub (src, i, i)
    local sheet, after = nil, i ---@type string?, integer
    if ch == "'" or string.find (ch, '^[%a_\128-\255]') then
      sheet, after = sheet_prefix (src, i)
    end
    if sheet then
      local token = read_word (src, after)
      if token and (token.kind == 'ref' or token.kind == 'range') then
        local a = token.a --[[@as Sheet.Ref]]
        a.sheet = sheet
        if token.b then
          token.b.sheet = sheet
        end
        token.sheet = sheet
        token.sheet_text = string.sub (src, i, after - 1)
        token.text = string.sub (src, i, token.to)
        token.from = i
        tokens[#tokens + 1] = token
        i = token.to + 1
      elseif lenient then
        i = after
      else
        return nil,
          'A cell reference must follow the sheet name at ' .. i .. '.'
      end
    elseif string.match (ch, '%s') then
      i = i + 1
    elseif ch == '"' then
      local parts = {} ---@type string[]
      local j = i + 1
      while true do
        local q = string.find (src, '"', j, true)
        if not q then
          if not lenient then
            return nil, 'A text in quotes has no closing quote.'
          end
          parts[#parts + 1] = string.sub (src, j)
          q = n
        elseif string.sub (src, q + 1, q + 1) == '"' then
          parts[#parts + 1] = string.sub (src, j, q - 1)
          parts[#parts + 1] = '"'
          j = q + 2
          q = nil
        else
          parts[#parts + 1] = string.sub (src, j, q - 1)
        end
        if q then
          tokens[#tokens + 1] = {
            kind = 'string',
            text = string.sub (src, i, q),
            from = i,
            to = q,
            value = table.concat (parts),
          }
          i = q + 1
          break
        end
      end
    elseif ch == "'" then
      if not lenient then
        return nil, 'A sheet name in quotes must end with a quote and "!".'
      end
      break
    elseif ch == '#' then
      local found = nil ---@type string?
      for _, code in ipairs (M.ERROR_CODES) do
        if string.upper (string.sub (src, i, i + #code - 1)) == code then
          found = code
          break
        end
      end
      if found then
        tokens[#tokens + 1] = {
          kind = 'error',
          text = string.sub (src, i, i + #found - 1),
          from = i,
          to = i + #found - 1,
          value = found,
        }
        i = i + #found
      elseif lenient then
        i = i + 1
      else
        return nil, 'An unknown error name starts at ' .. i .. '.'
      end
    elseif string.match (ch, '[%w%$_%.]') then
      local token = read_word (src, i)
      if token then
        tokens[#tokens + 1] = token
        i = token.to + 1
      elseif lenient then
        i = i + #(string.match (src, '^[%w%$_%.]+', i) or ch)
      else
        return nil, 'Unexpected text at ' .. i .. '.'
      end
    else
      local two = string.sub (src, i, i + 1)
      if two == '<>' or two == '<=' or two == '>=' then
        tokens[#tokens + 1] = { kind = 'op', text = two, from = i, to = i + 1 }
        i = i + 2
      else
        ---@type Sheet.TokenKind?
        local kind = nil
        if string.match (ch, '[=<>&%+%-%*/%^%%]') then
          kind = 'op'
        elseif ch == '(' then
          kind = 'open'
        elseif ch == ')' then
          kind = 'close'
        elseif ch == ',' then
          kind = 'comma'
        elseif ch == '{' then
          kind = 'lbrace'
          braces = braces + 1
        elseif ch == '}' then
          kind = 'rbrace'
          braces = braces - 1
        elseif ch == ';' and braces > 0 then
          -- A semicolon only means something inside an array constant, where it ends a row.
          kind = 'semicolon'
        end
        if kind then
          tokens[#tokens + 1] = { kind = kind, text = ch, from = i, to = i }
        elseif not lenient then
          return nil, 'Unexpected "' .. ch .. '".'
        end
        i = i + 1
      end
    end
  end
  return tokens
end

---Splits formula text into tokens, starting at byte `start`. Returns nil and a message when
---the text has a character that cannot start a token, or a quote with no end.
---@param src string
---@param start? integer
---@return Sheet.Token[]?
---@return string?
function M.tokenize (src, start)
  return lex (src, start or 1, false)
end

---What the other parts of the formula language share from this one.
---@class Sheet.FormulaLex
local P = {
  M = M,
  ERRORS = ERRORS,
  LAST_COL = LAST_COL,
  LAST_DAY = LAST_DAY,
  LAST_ROW = LAST_ROW,
  MANY = MANY,
  MAX_DEPTH = MAX_DEPTH,
  atan = atan,
  byte_of = byte_of,
  chars = chars,
  clean = clean,
  days_in_month = days_in_month,
  finite = finite,
  is_error = is_error,
  is_leap = is_leap,
  length = length,
  lex = lex,
  log = log,
  lower = lower,
  make_date = make_date,
  parse_datetime = parse_datetime,
  raise = raise,
  raise_value = raise_value,
  round_to = round_to,
  sheet_prefix = sheet_prefix,
  trunc = trunc,
  upper = upper,
  weekday0 = weekday0,
  wildcard = wildcard,
  ymd = ymd,
}

return P
