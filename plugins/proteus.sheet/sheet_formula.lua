-- sheet_formula: the formula language of the Sheet app. A tokenizer and a parser turn the
-- text after "=" into a tree, and an evaluator walks the tree. Formula text never runs as Lua.
--
-- The same tokens drive the rewrites of formula text: moving the references of a copied
-- formula, fixing references after a row or a column is inserted or deleted, and following a
-- sheet that is renamed or deleted. The helpers at the end serve the formula bar while a
-- formula is typed: completion, the argument being typed, reference colours and F4.

local calendar = require ('sheet_calendar') --[[@as Sheet.CalendarModule]]
local format = require ('sheet_format') --[[@as Sheet.FormatModule]]

---A spreadsheet error, such as `#DIV/0!`. Each code has one shared table, so two errors with
---the same code are equal.
---@class Sheet.Error
---@field code string

---A cell value. Nil is an empty cell.
---@alias Sheet.Value number|string|boolean|Sheet.Error|nil

---A list of values that may have holes, such as the arguments of a function.
---@alias Sheet.Values table<integer, Sheet.Value>

---One end of a reference. A whole column has no row, and a whole row has no column.
---@class Sheet.Ref
---@field row? integer
---@field col? integer
---@field row_abs boolean True when the row has a `$`.
---@field col_abs boolean True when the column has a `$`.
---@field sheet? string The sheet it names, without quotes. Nil means the formula's own sheet.

---@alias Sheet.TokenKind 'number'|'string'|'error'|'ref'|'range'|'name'|'op'|'open'|'close'|'comma'|'lbrace'|'rbrace'|'semicolon'

---@class Sheet.Token
---@field kind Sheet.TokenKind
---@field text string The source text.
---@field from integer The first byte.
---@field to integer The last byte.
---@field value? number|string
---@field a? Sheet.Ref A reference, or the first end of a range.
---@field b? Sheet.Ref The second end of a range.
---@field sheet? string The sheet a reference names, without quotes.
---@field sheet_text? string The sheet part of a reference as written, with its quotes and "!".
---@field spill? boolean True for a reference to the block a formula spills, such as `A1#`.

---@alias Sheet.NodeKind 'number'|'string'|'bool'|'error'|'ref'|'range'|'spill'|'name'|'call'|'invoke'|'unary'|'binary'|'percent'|'empty'|'array'

---A node of the formula tree.
---@class Sheet.Node
---@field kind Sheet.NodeKind
---@field value? number|string|boolean
---@field op? string
---@field left? Sheet.Node The operand of a unary or percent node, the left side, or the function an invoke node calls.
---@field right? Sheet.Node
---@field name? string A function or a name, in upper case.
---@field args? Sheet.Node[]
---@field a? Sheet.Ref
---@field b? Sheet.Ref
---@field array? Sheet.Array The values of an array constant such as `{1,2;3,4}`.

---A block of cells a formula reads. Whole columns leave the rows out, and whole rows leave the
---columns out.
---@class Sheet.Area
---@field r1? integer
---@field c1? integer
---@field r2? integer
---@field c2? integer
---@field sheet? string The sheet it names. Nil means the formula's own sheet.

---A block of cells with every side known, top left to bottom right.
---@class Sheet.Rect
---@field r1 integer
---@field c1 integer
---@field r2 integer
---@field c2 integer

---A block of cells as a value, while a function reads it.
---@class Sheet.RangeValue: Sheet.Rect
---@field is_range true
---@field sheet? string

---A block of values worked out by a formula, such as `{1,2;3,4}` or `A1:A3*2`. The values run
---row by row, and an empty cell leaves a hole.
---@class Sheet.Array
---@field is_array true
---@field h integer
---@field w integer
---@field v Sheet.Values

---@alias Sheet.Grid Sheet.RangeValue|Sheet.Array

---A function a formula makes with LAMBDA. It keeps the names around it when it was made.
---@class Sheet.Lambda
---@field is_lambda true
---@field params string[] The names of its arguments, in upper case.
---@field body Sheet.Node
---@field scope? Sheet.Scope

---Names that LET and LAMBDA give values, inside the part of a formula they cover.
---@class Sheet.Scope
---@field names table<string, Sheet.Result|Sheet.Lambda>
---@field parent? Sheet.Scope

---@alias Sheet.Result Sheet.Value|Sheet.RangeValue|Sheet.Array|Sheet.Lambda

---What the evaluator needs from a workbook.
---@class Sheet.Context
---@field value fun(row: integer, col: integer, sheet?: string): Sheet.Value
---@field rows integer The last row a whole column reaches.
---@field cols integer The last column a whole row reaches.
---@field size? fun(sheet: string): integer?, integer? The rows and columns of a named sheet, or nil when there is no such sheet.
---@field clock? fun(): number The date and time now, as a serial number of days.
---@field random? fun(): number
---@field row? integer The row of the cell being worked out, for ROW() with no argument.
---@field col? integer The column of the cell being worked out, for COLUMN() with no argument.
---@field spill? fun(row: integer, col: integer, sheet?: string): integer?, integer? The height and width of the block a formula's cell spills, or nil when it spills none.
---@field scope? Sheet.Scope The names LET and LAMBDA give, while their part of a formula is worked out.
---@field hidden? fun(row: integer, sheet?: string): 'filter'|'user'|nil Why a row is hidden: by the filter or by the user.
---@field subtotal? fun(row: integer, col: integer, sheet?: string): boolean True when a cell holds a SUBTOTAL or an AGGREGATE, which those leave out.
---@field formula_text? fun(row: integer, col: integer, sheet?: string): string? The formula a cell holds, with its "=", or nil.
---@field sheet_index? fun(sheet?: string): integer? Where a sheet sits in the book, the formula's own when nil.
---@field sheet_count? fun(): integer

---A function the formulas can call. `run` gets the argument trees and works them out as it
---needs to. `map` gets the argument values instead, and runs once for each value when an
---argument is a block of cells. With `catch`, `map` also gets errors as values.
---@class Sheet.Function
---@field min integer
---@field max integer
---@field run? fun(args: Sheet.Node[], ctx: Sheet.Context): Sheet.Result
---@field map? fun(v: Sheet.Values, n: integer, ctx: Sheet.Context): Sheet.Value
---@field catch? boolean

---@alias Sheet.Category 'Math'|'Statistics'|'Logic'|'Text'|'Lookup'|'Date'|'Info'|'Financial'

---@class Sheet.CatalogEntry
---@field name string
---@field category Sheet.Category
---@field syntax string Such as `SUMIF(range, criterion, [sum_range])`.
---@field summary string One plain sentence.

---A function name being typed, from `complete`.
---@class Sheet.Completion
---@field from integer The first byte of the name.
---@field to integer The last byte of the name, which may run on past the caret.
---@field prefix string The part of the name before the caret, as typed.

---The function whose arguments hold the caret, from `call_at`.
---@class Sheet.CallInfo
---@field name string In upper case.
---@field arg integer Counts from 1.

---A reference in formula text, from `ref_spans`.
---@class Sheet.RefSpan
---@field from integer
---@field to integer
---@field area Sheet.Area

---@class Sheet.MoveOptions
---@field from string The sheet the block moves from.
---@field to string The sheet the block moves to.
---@field own string The sheet the formula lives on.
---@field lands? string The sheet the formula lives on after the move, when it moves too.

---@class Sheet.AdjustOptions
---@field sheet? string The sheet where the rows or columns changed.
---@field own? string The sheet the formula lives on.

---An open bracket while formula text is scanned.
---@class Sheet.Frame
---@field name? string The function the bracket belongs to, or nil for a plain bracket.
---@field arg integer
---@field brace boolean True for the `{` of an array constant.

---@class Sheet.Parser
---@field tokens Sheet.Token[]
---@field i integer
---@field depth integer

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

---------------------------------------------------------------------------------------------
-- Parser
---------------------------------------------------------------------------------------------

---@param message string
---@return any
local function fail (message)
  local problem = { syntax = message }
  error (problem, 0)
end

---@param p Sheet.Parser
---@param kind Sheet.TokenKind
---@param text? string
---@return boolean
local function looking_at (p, kind, text)
  local t = p.tokens[p.i]
  return t ~= nil and t.kind == kind and (text == nil or t.text == text)
end

---@type fun(p: Sheet.Parser): Sheet.Node
local expression

-- The functions formulas can call, by name. The parser checks how many arguments a call
-- gives, and the evaluator runs them.
---@type table<string, Sheet.Function>
local FUNCS = {}

---How many arguments a function takes, in words.
---@param spec Sheet.Function
---@return string
local function arity (spec)
  if spec.min == spec.max then
    return spec.min == 1 and '1 argument' or spec.min .. ' arguments'
  end
  if spec.max >= MANY then
    return 'at least '
      .. spec.min
      .. (spec.min == 1 and ' argument' or ' arguments')
  end
  return spec.min .. ' to ' .. spec.max .. ' arguments'
end

---A call with as many arguments as its function takes. A wrong count fails as it is typed,
---rather than giving #VALUE! when the formula is worked out. A name no function has stays,
---for LET and LAMBDA names, and gives #NAME? later.
---@param node Sheet.Node
---@return Sheet.Node
local function checked (node)
  local name = node.name or ''
  local spec = FUNCS[name]
  local n = #(node.args or {})
  if spec and (n < spec.min or n > spec.max) then
    return fail (name .. ' takes ' .. arity (spec) .. ', not ' .. n .. '.')
  end
  return node
end

---@param p Sheet.Parser
---@param name string
---@return Sheet.Node
local function call_args (p, name)
  local args = {} ---@type Sheet.Node[]
  if looking_at (p, 'close') then
    p.i = p.i + 1
    return checked ({ kind = 'call', name = name, args = args })
  end
  while true do
    if looking_at (p, 'comma') or looking_at (p, 'close') then
      args[#args + 1] = { kind = 'empty' }
    else
      args[#args + 1] = expression (p)
    end
    if looking_at (p, 'comma') then
      p.i = p.i + 1
    elseif looking_at (p, 'close') then
      p.i = p.i + 1
      break
    else
      return fail ('A ")" is missing after the arguments of ' .. name .. '.')
    end
  end
  return checked ({ kind = 'call', name = name, args = args })
end

---Reads one value of an array constant: a number with an optional sign, text, TRUE, FALSE or
---an error.
---@param p Sheet.Parser
---@return Sheet.Value
local function constant (p)
  local t = p.tokens[p.i]
  if not t then
    return fail ('A "}" is missing.')
  end
  p.i = p.i + 1
  local sign = 1
  if t.kind == 'op' and (t.text == '-' or t.text == '+') then
    sign = t.text == '-' and -1 or 1
    t = p.tokens[p.i]
    if not t or t.kind ~= 'number' then
      return fail ('An array holds only numbers, text, TRUE, FALSE and errors.')
    end
    p.i = p.i + 1
  end
  if t.kind == 'number' then
    return sign * t.value --[[@as number]]
  end
  if sign == 1 then
    if t.kind == 'string' then
      return t.value
    end
    if t.kind == 'error' then
      return ERRORS[t.value]
    end
    if t.kind == 'name' then
      local up = string.upper (t.text)
      if up == 'TRUE' or up == 'FALSE' then
        return up == 'TRUE'
      end
    end
  end
  return fail ('An array holds only numbers, text, TRUE, FALSE and errors.')
end

---Reads an array constant after its "{". A comma separates the values in a row, and a
---semicolon ends a row.
---@param p Sheet.Parser
---@return Sheet.Node
local function array_constant (p)
  -- A constant is never nil, so the length of the list counts the values.
  local values = {} ---@type Sheet.Value[]
  local h = 1 ---@type integer
  -- The width is 0 until the first row ends.
  local w = 0 ---@type integer
  local first = 1 ---@type integer
  while true do
    values[#values + 1] = constant (p)
    local t = p.tokens[p.i]
    if not t then
      return fail ('A "}" is missing.')
    end
    p.i = p.i + 1
    if t.kind == 'semicolon' or t.kind == 'rbrace' then
      local len = #values - first + 1
      if w > 0 and len ~= w then
        return fail ('Every row of an array needs the same number of values.')
      end
      w = len
      if t.kind == 'rbrace' then
        break
      end
      first = #values + 1
      h = h + 1
    elseif t.kind ~= 'comma' then
      return fail ('Unexpected "' .. t.text .. '".')
    end
  end
  return {
    kind = 'array',
    array = { is_array = true, h = h, w = w, v = values },
  }
end

---@param p Sheet.Parser
---@return Sheet.Node
local function primary (p)
  local t = p.tokens[p.i]
  if not t then
    return fail ('The formula ends too soon.')
  end
  p.i = p.i + 1
  local kind = t.kind
  if kind == 'number' or kind == 'string' or kind == 'error' then
    return {
      kind = kind --[[@as Sheet.NodeKind]],
      value = t.value,
    }
  end
  if kind == 'ref' then
    return { kind = t.spill and 'spill' or 'ref', a = t.a }
  end
  if kind == 'range' then
    return { kind = 'range', a = t.a, b = t.b }
  end
  if kind == 'name' then
    local name = string.upper (t.text)
    if looking_at (p, 'open') then
      p.i = p.i + 1
      return call_args (p, name)
    end
    if name == 'TRUE' or name == 'FALSE' then
      return { kind = 'bool', value = name == 'TRUE' }
    end
    return { kind = 'name', name = name }
  end
  if kind == 'open' then
    local inner = expression (p)
    if not looking_at (p, 'close') then
      return fail ('A ")" is missing.')
    end
    p.i = p.i + 1
    return inner
  end
  if kind == 'lbrace' then
    return array_constant (p)
  end
  return fail ('Unexpected "' .. t.text .. '".')
end

---@param p Sheet.Parser
---@return Sheet.Node
local function postfix (p)
  local node = primary (p)
  -- A function call right after a call, as in LAMBDA(x, x*2)(5), calls what it gave.
  while node.kind == 'call' or node.kind == 'invoke' do
    if not looking_at (p, 'open') then
      break
    end
    p.i = p.i + 1
    local args = call_args (p, node.name or 'the function').args
    node = { kind = 'invoke', left = node, args = args }
  end
  while looking_at (p, 'op', '%') do
    p.i = p.i + 1
    node = { kind = 'percent', left = node }
  end
  return node
end

---@param p Sheet.Parser
---@return Sheet.Node
local function unary (p)
  if looking_at (p, 'op', '-') or looking_at (p, 'op', '+') then
    local op = p.tokens[p.i].text
    p.i = p.i + 1
    p.depth = p.depth + 1
    if p.depth > MAX_DEPTH then
      return fail ('The formula nests too deeply.')
    end
    local operand = unary (p)
    p.depth = p.depth - 1
    return { kind = 'unary', op = op, left = operand }
  end
  return postfix (p)
end

---Builds a left-to-right chain of binary operators.
---@param ops table<string, boolean>
---@param next_level fun(p: Sheet.Parser): Sheet.Node
---@return fun(p: Sheet.Parser): Sheet.Node
local function chain (ops, next_level)
  ---@param p Sheet.Parser
  ---@return Sheet.Node
  return function (p)
    local node = next_level (p)
    while true do
      local t = p.tokens[p.i]
      if not (t and t.kind == 'op' and ops[t.text]) then
        return node
      end
      p.i = p.i + 1
      node =
        { kind = 'binary', op = t.text, left = node, right = next_level (p) }
    end
  end
end

-- Lowest first: comparison, &, + and -, * and /, ^. Unary signs and % bind tighter than ^,
-- so -2^2 is 4 and 2^3^2 is 64, as in spreadsheets.
local power = chain ({ ['^'] = true }, unary)
local product = chain ({ ['*'] = true, ['/'] = true }, power)
local sum = chain ({ ['+'] = true, ['-'] = true }, product)
local join = chain ({ ['&'] = true }, sum)
local COMPARE = {
  ['='] = true,
  ['<>'] = true,
  ['<'] = true,
  ['>'] = true,
  ['<='] = true,
  ['>='] = true,
}
local comparison = chain (COMPARE, join)

---@param p Sheet.Parser
---@return Sheet.Node
expression = function (p)
  p.depth = p.depth + 1
  if p.depth > MAX_DEPTH then
    return fail ('The formula nests too deeply.')
  end
  local node = comparison (p)
  p.depth = p.depth - 1
  return node
end

---Parses a formula, with or without its leading "=". Returns the tree, or nil and a message.
---@param src string
---@return Sheet.Node?
---@return string?
function M.parse (src)
  local start = string.sub (src, 1, 1) == '=' and 2 or 1
  local tokens, problem = M.tokenize (src, start)
  if not tokens then
    return nil, problem
  end
  if #tokens == 0 then
    return nil, 'The formula is empty.'
  end
  local p = { tokens = tokens, i = 1, depth = 0 } ---@type Sheet.Parser
  local ok, result = pcall (expression, p)
  if not ok then
    local err = result --[[@as any]]
    if type (err) == 'table' and err.syntax then
      return nil, err.syntax
    end
    error (err, 0)
  end
  if p.i <= #tokens then
    return nil, 'Unexpected "' .. tokens[p.i].text .. '".'
  end
  return result
end

---------------------------------------------------------------------------------------------
-- Values
---------------------------------------------------------------------------------------------

---Reads text as a number in arithmetic: `12`, `1,200`, `15%`, `$5`, or a date or time such as
---`2026-09-29` or `14:30`.
---@param s string
---@return number?
local function text_number (s)
  local n = M.parse_number (s)
  if n then
    return n
  end
  local bare, count = string.gsub (s, '^(%s*[+-]?)%$', '%1')
  if count > 0 then
    return M.parse_number (bare)
  end
  -- An accounting negative such as (5) or ($1,200.50), with no sign of its own inside.
  local inner = string.match (s, '^%s*%(%s*%$?%s*([^%s%+%-()][^()]-)%s*%)%s*$')
  if inner then
    local m = M.parse_number (inner)
    return m and -m
  end
  return parse_datetime (s)
end

---A value as a number, or nil when it has none. Errors give nil too.
---@param v Sheet.Value
---@return number?
local function as_number (v)
  local t = type (v)
  if t == 'number' then
    return v --[[@as number]]
  end
  if v == nil then
    return 0.0
  end
  if t == 'boolean' then
    return v and 1.0 or 0.0
  end
  if t == 'string' then
    return text_number (v --[[@as string]])
  end
  return nil
end

---@param v Sheet.Value
---@return number
local function to_number (v)
  local n = as_number (v)
  if n then
    return n
  end
  if is_error (v) then
    return raise_value (v)
  end
  return raise ('#VALUE!')
end

---@param v Sheet.Value
---@return string
local function to_text (v)
  if is_error (v) then
    return raise_value (v)
  end
  return M.format_value (v)
end

---@param v Sheet.Value
---@return boolean
local function to_bool (v)
  local t = type (v)
  if t == 'boolean' then
    return v --[[@as boolean]]
  end
  if v == nil then
    return false
  end
  if t == 'number' then
    return v ~= 0
  end
  if t == 'string' then
    local up = string.upper (v --[[@as string]])
    if up == 'TRUE' then
      return true
    end
    if up == 'FALSE' then
      return false
    end
    return raise ('#VALUE!')
  end
  return raise_value (v)
end

local RANK = { number = 1, string = 2, boolean = 3 }

---Compares two numbers at 15 significant digits, as spreadsheets do, so 0.1+0.2 equals 0.3.
---Numbers far apart skip the rounding.
---@param x number
---@param y number
---@return integer
local function num_compare (x, y)
  if x == y then
    return 0
  end
  local d = x - y
  if math.abs (d) <= 2e-14 * math.max (math.abs (x), math.abs (y)) then
    local cx, cy = clean (x), clean (y)
    if cx == cy then
      return 0
    end
    return cx < cy and -1 or 1
  end
  return d < 0 and -1 or 1
end

M.compare_numbers = num_compare

---True when two numbers agree to 15 significant digits.
---@param x number
---@param y number
---@return boolean
local function same_number (x, y)
  return num_compare (x, y) == 0
end

---Compares two values the spreadsheet way: numbers before text before TRUE and FALSE, text
---without regard to case, and an empty cell as 0, "" or FALSE to suit the other side.
---@param a Sheet.Value
---@param b Sheet.Value
---@return integer
local function compare (a, b)
  if a == nil and b == nil then
    return 0
  end
  if a == nil then
    local tb = type (b)
    a = tb == 'string' and '' or tb == 'number' and 0 or false
  elseif b == nil then
    local ta = type (a)
    b = ta == 'string' and '' or ta == 'number' and 0 or false
  end
  local ra, rb = RANK[type (a)], RANK[type (b)]
  if ra ~= rb then
    return ra < rb and -1 or 1
  end
  local x, y = a, b ---@type any, any
  if ra == 1 then
    return num_compare (x, y)
  elseif ra == 2 then
    x, y = lower (x), lower (y)
  elseif ra == 3 then
    x, y = x and 1 or 0, y and 1 or 0
  end
  if x < y then
    return -1
  end
  if x > y then
    return 1
  end
  return 0
end

---Works out one operator on two values that hold no blocks. Returns an error as a value
---rather than raising it, so a block can keep one error per cell.
---@param op string
---@param a Sheet.Value
---@param b Sheet.Value
---@return Sheet.Value
local function operate (op, a, b)
  if type (a) == 'table' then
    return a
  end
  if type (b) == 'table' then
    return b
  end
  if op == '&' then
    return M.format_value (a) .. M.format_value (b)
  end
  if COMPARE[op] then
    local c = compare (a, b)
    if op == '=' then
      return c == 0
    elseif op == '<>' then
      return c ~= 0
    elseif op == '<' then
      return c < 0
    elseif op == '>' then
      return c > 0
    elseif op == '<=' then
      return c <= 0
    end
    return c >= 0
  end
  local x, y = as_number (a), as_number (b)
  if not x or not y then
    return ERRORS['#VALUE!']
  end
  local r ---@type number
  if op == '+' then
    r = x + y
  elseif op == '-' then
    r = x - y
  elseif op == '*' then
    r = x * y
  elseif op == '/' then
    if y == 0 then
      return ERRORS['#DIV/0!']
    end
    r = x / y
  else
    if x == 0 and y < 0 then
      return ERRORS['#DIV/0!']
    end
    r = x ^ y
  end
  if r ~= r or r == math.huge or r == -math.huge then
    return ERRORS['#NUM!']
  end
  return r
end

---A sign or a percent on one value, with errors returned as values.
---@param kind Sheet.NodeKind
---@param op string?
---@param v Sheet.Value
---@return Sheet.Value
local function operate1 (kind, op, v)
  if type (v) == 'table' then
    return v
  end
  if kind == 'unary' and op == '+' then
    return v
  end
  local n = as_number (v)
  if not n then
    return ERRORS['#VALUE!']
  end
  if kind == 'percent' then
    return n / 100
  end
  return -n
end

---@param h integer
---@param w integer
---@param v Sheet.Values
---@return Sheet.Array
local function new_array (h, w, v)
  return { is_array = true, h = h, w = w, v = v }
end

---The height and width of a block. A single value is one by one.
---@param v Sheet.Result
---@return integer h
---@return integer w
local function dims (v)
  if type (v) == 'table' then
    local t = v --[[@as table]]
    if t.is_range then
      return t.r2 - t.r1 + 1, t.c2 - t.c1 + 1
    end
    if t.is_array then
      return t.h, t.w
    end
  end
  return 1, 1
end

---True for a block of cells or an array. Errors are tables too, and are not blocks.
---@param v Sheet.Result
---@return boolean
local function is_grid (v)
  if type (v) ~= 'table' then
    return false
  end
  local t = v --[[@as table]]
  return t.is_range == true or t.is_array == true
end

---The value at row `i` and column `j` of a block, counting from 1.
---@param g Sheet.Grid
---@param i integer
---@param j integer
---@param ctx Sheet.Context
---@return Sheet.Value
local function grid_at (g, i, j, ctx)
  if g.is_range then
    local r = g --[[@as Sheet.RangeValue]]
    return ctx.value (r.r1 + i - 1, r.c1 + j - 1, r.sheet)
  end
  local a = g --[[@as Sheet.Array]]
  return a.v[(i - 1) * a.w + j]
end

---The value of a block at row `i` and column `j` when blocks of different sizes meet. A block
---one row high repeats down, one column wide repeats across, and a cell past the edge of a
---bigger block is #N/A.
---@param g Sheet.Grid
---@param gh integer
---@param gw integer
---@param i integer
---@param j integer
---@param ctx Sheet.Context
---@return Sheet.Value
local function spread_at (g, gh, gw, i, j, ctx)
  if gh == 1 then
    i = 1
  elseif i > gh then
    return ERRORS['#N/A']
  end
  if gw == 1 then
    j = 1
  elseif j > gw then
    return ERRORS['#N/A']
  end
  return grid_at (g, i, j, ctx)
end

---The size of a named sheet. A sheet the workbook does not know is #REF!.
---@param sheet string
---@param ctx Sheet.Context
---@return integer rows
---@return integer cols
local function sheet_size (sheet, ctx)
  local size = ctx.size
  if not size then
    error (ERRORS['#REF!'], 0)
  end
  local rows, cols = size (sheet)
  if not rows or not cols then
    error (ERRORS['#REF!'], 0)
  end
  return rows, cols
end

---Raises #REF! for a reference past the last row or column of a sheet.
---@param row integer?
---@param col integer?
local function on_sheet (row, col)
  if (row and row > LAST_ROW) or (col and col > LAST_COL) then
    raise ('#REF!')
  end
end

---The value of a cell, raising its error when it holds one.
---@param a Sheet.Ref
---@param ctx Sheet.Context
---@return Sheet.Value
local function cell_value (a, ctx)
  on_sheet (a.row, a.col)
  local sheet = a.sheet
  if sheet then
    sheet_size (sheet, ctx)
  end
  local v = ctx.value (a.row --[[@as integer]], a.col --[[@as integer]], sheet)
  if type (v) == 'table' then
    return raise_value (v)
  end
  return v
end

---@param a Sheet.Ref
---@param b Sheet.Ref
---@param ctx Sheet.Context
---@return Sheet.RangeValue
local function resolve (a, b, ctx)
  on_sheet (a.row, a.col)
  on_sheet (b.row, b.col)
  local sheet = a.sheet
  local rows, cols = ctx.rows, ctx.cols
  if sheet then
    rows, cols = sheet_size (sheet, ctx)
  end
  local ra, rb = a.row or 1, b.row or rows
  local ca, cb = a.col or 1, b.col or cols
  return {
    is_range = true,
    r1 = math.min (ra, rb),
    c1 = math.min (ca, cb),
    r2 = math.max (ra, rb),
    c2 = math.max (ca, cb),
    sheet = sheet,
  }
end

---The block a formula's cell spills, for a reference such as `A1#`. A cell that spills
---nothing is #REF!.
---@param a Sheet.Ref
---@param ctx Sheet.Context
---@return Sheet.RangeValue
local function spill_range (a, ctx)
  on_sheet (a.row, a.col)
  if a.sheet then
    sheet_size (a.sheet, ctx)
  end
  local row = a.row --[[@as integer]]
  local col = a.col --[[@as integer]]
  local h, w = nil, nil ---@type integer?, integer?
  if ctx.spill then
    h, w = ctx.spill (row, col, a.sheet)
  end
  if not h or not w then
    return raise ('#REF!')
  end
  return {
    is_range = true,
    r1 = row,
    c1 = col,
    r2 = row + h - 1,
    c2 = col + w - 1,
    sheet = a.sheet,
  }
end

---A reference to one cell as a block.
---@param a Sheet.Ref
---@param ctx Sheet.Context
---@return Sheet.RangeValue
local function cell_range (a, ctx)
  on_sheet (a.row, a.col)
  if a.sheet then
    sheet_size (a.sheet, ctx)
  end
  local row, col =
    a.row, --[[@as integer]]
    a.col --[[@as integer]]
  return {
    is_range = true,
    r1 = row,
    c1 = col,
    r2 = row,
    c2 = col,
    sheet = a.sheet,
  }
end

---The one value of a block with one cell, raising it when it is an error. A bigger block
---comes back as it is.
---@param v Sheet.Result
---@param ctx Sheet.Context
---@return Sheet.Result
local function single (v, ctx)
  if
    (v --[[@as table]]).is_lambda
  then
    return raise ('#CALC!')
  end
  local h, w = dims (v)
  if h ~= 1 or w ~= 1 then
    return v
  end
  local x = grid_at (v --[[@as Sheet.Grid]], 1, 1, ctx)
  if type (x) == 'table' then
    return raise_value (x)
  end
  return x
end

---One value from a result, for an argument that takes one value. A block with more than one
---cell is #VALUE!.
---@param v Sheet.Result
---@param ctx Sheet.Context
---@return Sheet.Value
local function scalar (v, ctx)
  if type (v) ~= 'table' then
    return v --[[@as Sheet.Value]]
  end
  local x = single (v, ctx)
  if type (x) == 'table' then
    return raise ('#VALUE!')
  end
  return x --[[@as Sheet.Value]]
end

---------------------------------------------------------------------------------------------
-- Evaluator
---------------------------------------------------------------------------------------------

---@type fun(node: Sheet.Node, ctx: Sheet.Context): Sheet.Result
local eval

---Works out an operator cell by cell over blocks, as in `A1:A9>5` or `{1,2}*B1:C1`.
---@param op string
---@param a Sheet.Result
---@param b Sheet.Result
---@param ctx Sheet.Context
---@return Sheet.Array
local function elementwise (op, a, b, ctx)
  local ah, aw = dims (a)
  local bh, bw = dims (b)
  local h, w = math.max (ah, bh), math.max (aw, bw)
  local ga, gb = is_grid (a), is_grid (b)
  local out = {} ---@type Sheet.Values
  local k = 0
  for i = 1, h do
    for j = 1, w do
      k = k + 1
      local x, y = a, b ---@type Sheet.Result, Sheet.Result
      if ga then
        x = spread_at (a --[[@as Sheet.Grid]], ah, aw, i, j, ctx)
      end
      if gb then
        y = spread_at (b --[[@as Sheet.Grid]], bh, bw, i, j, ctx)
      end
      out[k] = operate (op, x --[[@as Sheet.Value]], y --[[@as Sheet.Value]])
    end
  end
  return new_array (h, w, out)
end

---@param node Sheet.Node
---@param ctx Sheet.Context
---@return Sheet.Result
local function binary (node, ctx)
  local op = node.op --[[@as string]]
  local a = eval (node.left --[[@as Sheet.Node]], ctx)
  if type (a) == 'table' then
    a = single (a, ctx)
  end
  local b = eval (node.right --[[@as Sheet.Node]], ctx)
  if type (b) == 'table' then
    b = single (b, ctx)
  end
  if type (a) == 'table' or type (b) == 'table' then
    return elementwise (op, a, b, ctx)
  end
  local v = operate (op, a --[[@as Sheet.Value]], b --[[@as Sheet.Value]])
  if type (v) == 'table' then
    return raise_value (v)
  end
  return v
end

---Runs a `map` function once for each cell of the blocks among its arguments, as in
---`ROUND(A1:A9, 0)`. Blocks of different sizes meet as they do for operators.
---@param spec Sheet.Function
---@param vals table<integer, Sheet.Result>
---@param n integer
---@param ctx Sheet.Context
---@return Sheet.Array
local function lifted (spec, vals, n, ctx)
  local map = spec.map --[[@as fun(v: Sheet.Values, n: integer, ctx: Sheet.Context): Sheet.Value]]
  local catch = spec.catch
  local hs, ws = {}, {} ---@type integer[], integer[]
  local h, w = 1, 1
  for i = 1, n do
    local gh, gw = 0, 0
    if is_grid (vals[i]) then
      gh, gw = dims (vals[i])
      h, w = math.max (h, gh), math.max (w, gw)
    end
    hs[i], ws[i] = gh, gw
  end
  local out = {} ---@type Sheet.Values
  local cur = {} ---@type Sheet.Values
  local k = 0
  for r = 1, h do
    for c = 1, w do
      k = k + 1
      local bad = nil ---@type Sheet.Value
      for i = 1, n do
        local v = vals[i]
        if hs[i] > 0 then
          v = spread_at (v --[[@as Sheet.Grid]], hs[i], ws[i], r, c, ctx)
        end
        if not catch and bad == nil and is_error (v) then
          bad = v --[[@as Sheet.Value]]
        end
        cur[i] = v --[[@as Sheet.Value]]
      end
      if bad ~= nil then
        out[k] = bad
      else
        local ok, res = pcall (map, cur, n, ctx)
        if not ok then
          if not is_error (res) then
            error (res, 0)
          end
          out[k] = res --[[@as Sheet.Value]]
        elseif
          type (res) == 'number'
          and (res ~= res or res == math.huge or res == -math.huge)
        then
          out[k] = ERRORS['#NUM!']
        else
          out[k] = res
        end
      end
    end
  end
  return new_array (h, w, out)
end

---Works out the arguments of a `map` function and runs it.
---@param spec Sheet.Function
---@param args Sheet.Node[]
---@param n integer
---@param ctx Sheet.Context
---@return Sheet.Result
local function call_map (spec, args, n, ctx)
  local vals = {} ---@type table<integer, Sheet.Result>
  local lift = false
  local catch = spec.catch
  for i = 1, n do
    local v ---@type Sheet.Result
    if catch then
      local ok, r = pcall (eval, args[i], ctx)
      if not ok and not is_error (r) then
        error (r, 0)
      end
      v = r
    else
      v = eval (args[i], ctx)
    end
    if is_grid (v) then
      local h, w = dims (v)
      if h == 1 and w == 1 then
        v = grid_at (v --[[@as Sheet.Grid]], 1, 1, ctx)
        if not catch and type (v) == 'table' then
          raise_value (v)
        end
      else
        lift = true
      end
    end
    vals[i] = v
  end
  if lift then
    return lifted (spec, vals, n, ctx)
  end
  local map = spec.map --[[@as fun(v: Sheet.Values, n: integer, ctx: Sheet.Context): Sheet.Value]]
  return map (vals --[[@as Sheet.Values]], n, ctx)
end

-- What a name holds when LET gives it an empty value, since a table cannot hold nil.
local EMPTY = {}

---True for a function that LAMBDA made.
---@param v any
---@return boolean
local function is_lambda (v)
  return type (v) == 'table' and v.is_lambda == true
end

---The value LET or LAMBDA gave a name, and whether one did.
---@param ctx Sheet.Context
---@param name string
---@return Sheet.Result|Sheet.Lambda
---@return boolean
local function lookup (ctx, name)
  local scope = ctx.scope
  while scope do
    local v = scope.names[name]
    if v ~= nil then
      if v == EMPTY then
        return nil, true
      end
      return v, true
    end
    scope = scope.parent
  end
  return nil, false
end

---Works out a node with other names in scope, and puts the old ones back after, even when
---it raises an error.
---@param ctx Sheet.Context
---@param scope Sheet.Scope?
---@param fn fun(): Sheet.Result
---@return Sheet.Result
local function within (ctx, scope, fn)
  local saved = ctx.scope
  ctx.scope = scope
  local ok, result = pcall (fn)
  ctx.scope = saved
  if not ok then
    error (result, 0)
  end
  return result
end

---Calls a LAMBDA with values for its arguments. `n` is how many values there are, since an
---empty one leaves a hole.
---@param fn Sheet.Lambda
---@param values table<integer, Sheet.Result>
---@param n integer
---@param ctx Sheet.Context
---@return Sheet.Result
local function apply (fn, values, n, ctx)
  if n ~= #fn.params then
    return raise ('#VALUE!')
  end
  local names = {} ---@type table<string, Sheet.Result|Sheet.Lambda>
  for i, name in ipairs (fn.params) do
    local v = values[i]
    if v == nil then
      names[name] = EMPTY
    else
      names[name] = v
    end
  end
  return within (ctx, { names = names, parent = fn.scope }, function ()
    return eval (fn.body, ctx)
  end)
end

---Calls what a formula gave as a function, with the arguments in the formula. Anything but a
---LAMBDA is #VALUE!.
---@param fn any
---@param args Sheet.Node[]
---@param ctx Sheet.Context
---@return Sheet.Result
local function invoke (fn, args, ctx)
  if not is_lambda (fn) then
    return raise ('#VALUE!')
  end
  local values = {} ---@type table<integer, Sheet.Result>
  for i, arg in ipairs (args) do
    if arg.kind ~= 'empty' then
      local kind = arg.kind
      if kind == 'ref' then
        values[i] = cell_range (arg.a --[[@as Sheet.Ref]], ctx)
      elseif kind == 'range' then
        values[i] =
          resolve (arg.a --[[@as Sheet.Ref]], arg.b --[[@as Sheet.Ref]], ctx)
      else
        values[i] = eval (arg, ctx)
      end
    end
  end
  return apply (fn --[[@as Sheet.Lambda]], values, #args, ctx)
end

---@param node Sheet.Node
---@param ctx Sheet.Context
---@return Sheet.Result
local function call (node, ctx)
  if ctx.scope then
    local fn, found = lookup (ctx, node.name or '')
    if found then
      return invoke (fn, node.args or {}, ctx)
    end
  end
  local spec = FUNCS[node.name or '']
  if not spec then
    return raise ('#NAME?')
  end
  local args = node.args or {}
  local n = #args
  if n < spec.min or n > spec.max then
    return raise ('#VALUE!')
  end
  local v ---@type Sheet.Result
  if spec.map then
    v = call_map (spec, args, n, ctx)
  else
    local run = spec.run --[[@as fun(args: Sheet.Node[], ctx: Sheet.Context): Sheet.Result]]
    v = run (args, ctx)
  end
  local t = type (v)
  if t == 'number' then
    return finite (v + 0.0)
  end
  if t == 'table' and is_error (v) then
    return raise_value (v)
  end
  return v
end

---@param node Sheet.Node
---@param ctx Sheet.Context
---@return Sheet.Result
eval = function (node, ctx)
  local kind = node.kind
  if kind == 'number' or kind == 'string' or kind == 'bool' then
    return node.value
  end
  if kind == 'ref' then
    return cell_value (node.a --[[@as Sheet.Ref]], ctx)
  end
  if kind == 'range' then
    return resolve (node.a --[[@as Sheet.Ref]], node.b --[[@as Sheet.Ref]], ctx)
  end
  if kind == 'spill' then
    return spill_range (node.a --[[@as Sheet.Ref]], ctx)
  end
  if kind == 'binary' then
    return binary (node, ctx)
  end
  if kind == 'call' then
    return call (node, ctx)
  end
  if kind == 'empty' then
    return nil
  end
  if kind == 'array' then
    return node.array
  end
  if kind == 'error' then
    return raise (node.value --[[@as string]])
  end
  if kind == 'name' then
    local v, found = lookup (ctx, node.name or '')
    if found then
      return v
    end
    return raise ('#NAME?')
  end
  if kind == 'invoke' then
    local fn = eval (node.left --[[@as Sheet.Node]], ctx)
    return invoke (fn, node.args or {}, ctx)
  end
  local v = eval (node.left --[[@as Sheet.Node]], ctx)
  if type (v) == 'table' then
    v = single (v, ctx)
  end
  if type (v) == 'table' then
    local h, w = dims (v)
    local out = {} ---@type Sheet.Values
    local k = 0
    for i = 1, h do
      for j = 1, w do
        k = k + 1
        out[k] =
          operate1 (kind, node.op, grid_at (v --[[@as Sheet.Grid]], i, j, ctx))
      end
    end
    return new_array (h, w, out)
  end
  local r = operate1 (kind, node.op, v --[[@as Sheet.Value]])
  if type (r) == 'table' then
    return raise_value (r)
  end
  return r
end

---The values of a block as an array, with an empty cell as 0, the way a block spills.
---@param g Sheet.Grid
---@param ctx Sheet.Context
---@return Sheet.Array
local function spilled (g, ctx)
  local h, w = dims (g)
  local out = {} ---@type Sheet.Values
  for i = 1, h do
    for j = 1, w do
      local v = grid_at (g, i, j, ctx)
      if v == nil then
        v = 0.0
      end
      out[(i - 1) * w + j] = v
    end
  end
  return new_array (h, w, out)
end

---Works out a formula and gives every value it makes, row by row, with an empty cell as nil,
---and how many there are. A list of items read from cells uses it. An error comes back as
---the one value.
---@param ast Sheet.Node
---@param ctx Sheet.Context
---@return Sheet.Values
---@return integer count
function M.values (ast, ctx)
  local ok, result = pcall (eval, ast, ctx)
  if not ok then
    return { is_error (result) and result or ERRORS['#VALUE!'] }, 1
  end
  if not is_grid (result) then
    return {
      result --[[@as Sheet.Value]],
    }, 1
  end
  local h, w = dims (result)
  local out = {} ---@type Sheet.Values
  local done, problem = pcall (function ()
    for i = 1, h do
      for j = 1, w do
        out[(i - 1) * w + j] = grid_at (result --[[@as Sheet.Grid]], i, j, ctx)
      end
    end
  end)
  if not done then
    return { is_error (problem) and problem or ERRORS['#VALUE!'] }, 1
  end
  return out, h * w
end

---Works out the value of a parsed formula. An empty result shows as 0, as in spreadsheets. A
---result that is a block of cells gives its top left value. With `spill`, a block of more than
---one cell comes back too, as an array, for the cells around the formula to show.
---@param ast Sheet.Node
---@param ctx Sheet.Context
---@param spill? boolean
---@return Sheet.Value
---@return Sheet.Array?
function M.evaluate (ast, ctx, spill)
  local ok, result = pcall (eval, ast, ctx)
  if ok and is_lambda (result) then
    return ERRORS['#CALC!']
  end
  if ok and spill and is_grid (result) then
    local h, w = dims (result)
    if h > 1 or w > 1 then
      local done, block = pcall (spilled, result --[[@as Sheet.Grid]], ctx)
      if done then
        return block.v[1], block
      end
      ok, result = false, block
    end
  end
  if ok and is_grid (result) then
    ok, result = pcall (grid_at, result --[[@as Sheet.Grid]], 1, 1, ctx)
  end
  if ok then
    if result == nil then
      return 0.0
    end
    return result --[[@as Sheet.Value]]
  end
  if is_error (result) then
    return result --[[@as Sheet.Error]]
  end
  return ERRORS['#VALUE!']
end

---------------------------------------------------------------------------------------------
-- Function helpers
---------------------------------------------------------------------------------------------

---@param node Sheet.Node
---@param ctx Sheet.Context
---@return Sheet.Value
local function value_of (node, ctx)
  return scalar (eval (node, ctx), ctx)
end

---@param node Sheet.Node
---@param ctx Sheet.Context
---@return number
local function number_of (node, ctx)
  return to_number (value_of (node, ctx))
end

---@param node Sheet.Node
---@param ctx Sheet.Context
---@return string
local function text_of (node, ctx)
  return to_text (value_of (node, ctx))
end

---@param node Sheet.Node
---@param ctx Sheet.Context
---@return boolean
local function bool_of (node, ctx)
  return to_bool (value_of (node, ctx))
end

---A whole number from an argument, cut toward zero.
---@param node Sheet.Node
---@param ctx Sheet.Context
---@return integer
local function int_of (node, ctx)
  return trunc (number_of (node, ctx))
end

---True when an argument is there and not left empty, as the last one in `ROUND(1.5, )`.
---@param node Sheet.Node?
---@return boolean
local function given (node)
  return node ~= nil and node.kind ~= 'empty'
end

---The block of cells an argument names, or nil when it is not a reference. A function such
---as INDIRECT or OFFSET can name one too.
---@param node Sheet.Node
---@param ctx Sheet.Context
---@return Sheet.RangeValue?
local function reference (node, ctx)
  local kind = node.kind
  if kind == 'ref' then
    return cell_range (node.a --[[@as Sheet.Ref]], ctx)
  end
  if kind == 'range' then
    return resolve (node.a --[[@as Sheet.Ref]], node.b --[[@as Sheet.Ref]], ctx)
  end
  if
    kind == 'call'
    or kind == 'name'
    or kind == 'invoke'
    or kind == 'spill'
  then
    local v = eval (node, ctx)
    if
      type (v) == 'table' and (v --[[@as table]]).is_range
    then
      return v --[[@as Sheet.RangeValue]]
    end
  end
  return nil
end

---@param node Sheet.Node
---@param ctx Sheet.Context
---@return Sheet.RangeValue
local function need_reference (node, ctx)
  return reference (node, ctx) or raise ('#VALUE!')
end

---An argument as a block of cells or an array, or its one value. A reference to one cell
---stays a block, so an error in the cell does not raise.
---@param node Sheet.Node
---@param ctx Sheet.Context
---@return Sheet.Result
local function grid_or_value (node, ctx)
  local kind = node.kind
  if kind == 'ref' then
    return cell_range (node.a --[[@as Sheet.Ref]], ctx)
  end
  if kind == 'range' then
    return resolve (node.a --[[@as Sheet.Ref]], node.b --[[@as Sheet.Ref]], ctx)
  end
  return eval (node, ctx)
end

---An argument that must be a block of cells or an array.
---@param node Sheet.Node
---@param ctx Sheet.Context
---@return Sheet.Grid
local function need_grid (node, ctx)
  local v = grid_or_value (node, ctx)
  if not is_grid (v) then
    return raise ('#VALUE!')
  end
  return v --[[@as Sheet.Grid]]
end

---Calls `fn` with every value an argument holds. A reference, a block or an array gives each
---value and true. Anything else gives its one value and false. An empty argument gives nothing.
---@param node Sheet.Node
---@param ctx Sheet.Context
---@param fn fun(v: Sheet.Value, in_ref: boolean)
local function each (node, ctx, fn)
  local kind = node.kind
  if kind == 'empty' then
    return
  end
  if kind == 'ref' then
    local a = node.a --[[@as Sheet.Ref]]
    on_sheet (a.row, a.col)
    if a.sheet then
      sheet_size (a.sheet, ctx)
    end
    fn (
      ctx.value (a.row --[[@as integer]], a.col --[[@as integer]], a.sheet),
      true
    )
    return
  end
  local v = grid_or_value (node, ctx)
  if type (v) ~= 'table' then
    fn (v --[[@as Sheet.Value]], false)
    return
  end
  local t = v --[[@as table]]
  if t.is_range then
    local sheet = t.sheet --[[@as string?]]
    local value = ctx.value
    for r = t.r1, t.r2 do
      for c = t.c1, t.c2 do
        fn (value (r, c, sheet), true)
      end
    end
  else
    local list = t.v --[[@as Sheet.Values]]
    for k = 1, t.h * t.w do
      fn (list[k], true)
    end
  end
end

---The numbers in the arguments of SUM and its kin, from `first` to `last`. Cells skip text and
---TRUE or FALSE, while an argument typed in the formula counts as a number or fails.
---@param args Sheet.Node[]
---@param ctx Sheet.Context
---@param first? integer
---@param last? integer
---@return number[]
local function numbers (args, ctx, first, last)
  local out = {} ---@type number[]
  ---@param v Sheet.Value
  ---@param in_ref boolean
  local function add (v, in_ref)
    if in_ref then
      if type (v) == 'number' then
        out[#out + 1] = v
      elseif type (v) == 'table' then
        raise_value (v)
      end
    else
      out[#out + 1] = to_number (v)
    end
  end
  for k = first or 1, last or #args do
    each (args[k], ctx, add)
  end
  return out
end

---The TRUE and FALSE values in the arguments of AND, OR and XOR.
---@param args Sheet.Node[]
---@param ctx Sheet.Context
---@return boolean[]
local function logicals (args, ctx)
  local out = {} ---@type boolean[]
  ---@param v Sheet.Value
  ---@param in_ref boolean
  local function add (v, in_ref)
    if in_ref then
      if type (v) == 'boolean' then
        out[#out + 1] = v
      elseif type (v) == 'number' then
        out[#out + 1] = v ~= 0
      elseif type (v) == 'table' then
        raise_value (v)
      end
    else
      out[#out + 1] = to_bool (v)
    end
  end
  for _, node in ipairs (args) do
    each (node, ctx, add)
  end
  if #out == 0 then
    return raise ('#VALUE!')
  end
  return out
end

---@param a any
---@param b any
---@param op string
---@return boolean
local function ordered (a, b, op)
  if type (a) == 'number' and type (b) == 'number' then
    local c = num_compare (a, b)
    if op == '<' then
      return c < 0
    elseif op == '>' then
      return c > 0
    elseif op == '<=' then
      return c <= 0
    end
    return c >= 0
  end
  if op == '<' then
    return a < b
  elseif op == '>' then
    return a > b
  elseif op == '<=' then
    return a <= b
  end
  return a >= b
end

---True when a cell holds the number `num`, as a number or as text that reads as one.
---@param v Sheet.Value
---@param num number
---@return boolean
local function holds_number (v, num)
  if type (v) == 'number' then
    return same_number (v, num)
  end
  if type (v) == 'string' then
    local n = M.parse_number (v)
    return n ~= nil and same_number (n, num)
  end
  return false
end

---Builds the test for SUMIF, COUNTIF and their kin: `5`, `">5"`, `"<>x"`, `"=abc"`, `""` for an
---empty cell, and `*` and `?` as wildcards in text, with `~` before one to mean the character.
---@param crit Sheet.Value
---@return fun(v: Sheet.Value): boolean
local function matcher (crit)
  if type (crit) == 'number' then
    return function (v)
      return holds_number (v, crit)
    end
  end
  if type (crit) == 'boolean' then
    return function (v)
      return v == crit
    end
  end
  local s = to_text (crit)
  local op, rest = string.match (s, '^([<>=][>=]?)(.*)$')
  if not op or not COMPARE[op] then
    op, rest = '=', s
  end
  local num = M.parse_number (rest)
  if op == '=' or op == '<>' then
    local up = string.upper (rest)
    ---@type fun(v: Sheet.Value): boolean
    local want
    if rest == '' then
      want = function (v)
        return v == nil or v == ''
      end
    elseif num then
      want = function (v)
        return holds_number (v, num)
      end
    elseif up == 'TRUE' or up == 'FALSE' then
      local flag = up == 'TRUE'
      want = function (v)
        return v == flag
      end
    else
      local pattern = wildcard (lower (rest), true)
      want = function (v)
        return type (v) == 'string' and string.find (lower (v), pattern) ~= nil
      end
    end
    if op == '<>' then
      return function (v)
        return not want (v)
      end
    end
    return want
  end
  if num then
    return function (v)
      return type (v) == 'number' and ordered (v, num, op)
    end
  end
  local low = lower (rest)
  return function (v)
    return type (v) == 'string' and ordered (lower (v), low, op)
  end
end

---The exact test for lookups. Text ignores case, and with `wild` it allows `*`, `?` and `~`.
---@param want Sheet.Value
---@param wild boolean
---@return fun(v: Sheet.Value): boolean
local function equals (want, wild)
  if want == nil then
    return function ()
      return false
    end
  end
  if type (want) == 'string' then
    local low = lower (want)
    if wild and string.find (want, '[%*%?~]') then
      local pattern = wildcard (low, true)
      return function (v)
        return type (v) == 'string' and string.find (lower (v), pattern) ~= nil
      end
    end
    return function (v)
      return type (v) == 'string' and lower (v) == low
    end
  end
  if type (want) == 'number' then
    return function (v)
      return type (v) == 'number' and same_number (v, want)
    end
  end
  return function (v)
    return v == want
  end
end

---Calls `fn` with the value in the target beside each cell that meets every condition. The
---conditions are pairs of a range and a criterion in `args[first..last]`. Every range must have
---the shape of the first. The target is `target` or, when it is not given, the first range.
---`resize` lets a target of another size start at its top left cell, as SUMIF allows.
---@param args Sheet.Node[]
---@param first integer
---@param last integer
---@param target Sheet.Node?
---@param resize boolean
---@param ctx Sheet.Context
---@param fn fun(v: Sheet.Value)
local function each_match (args, first, last, target, resize, ctx, fn)
  if last < first or (last - first) % 2 == 0 then
    error (ERRORS['#VALUE!'], 0)
  end
  local grids = {} ---@type Sheet.Grid[]
  local tests = {} ---@type (fun(v: Sheet.Value): boolean)[]
  local h, w = 0, 0
  for k = first, last, 2 do
    local g = need_grid (args[k], ctx)
    local gh, gw = dims (g)
    if k == first then
      h, w = gh, gw
    elseif gh ~= h or gw ~= w then
      error (ERRORS['#VALUE!'], 0)
    end
    grids[#grids + 1] = g
    tests[#tests + 1] = matcher (value_of (args[k + 1], ctx))
  end
  local out = grids[1]
  if given (target) then
    out = need_grid (target --[[@as Sheet.Node]], ctx)
    local th, tw = dims (out)
    if th ~= h or tw ~= w then
      if not resize or not out.is_range then
        error (ERRORS['#VALUE!'], 0)
      end
      local r = out --[[@as Sheet.RangeValue]]
      out = {
        is_range = true,
        r1 = r.r1,
        c1 = r.c1,
        r2 = r.r1 + h - 1,
        c2 = r.c1 + w - 1,
        sheet = r.sheet,
      }
    end
  end
  local count = #tests
  for i = 1, h do
    for j = 1, w do
      local pass = true
      for t = 1, count do
        if not tests[t] (grid_at (grids[t], i, j, ctx)) then
          pass = false
          break
        end
      end
      if pass then
        fn (grid_at (out, i, j, ctx))
      end
    end
  end
end

---@param ctx Sheet.Context
---@return number
local function now (ctx)
  if ctx.clock then
    return ctx.clock ()
  end
  return M.clock ()
end

---@param ctx Sheet.Context
---@return number
local function random (ctx)
  if ctx.random then
    return ctx.random ()
  end
  return math.random ()
end

---An optional number argument of a `map` function: `d` when it is left out.
---@param v Sheet.Values
---@param n integer
---@param i integer
---@param d number
---@return number
local function opt (v, n, i, d)
  if i > n then
    return d
  end
  return to_number (v[i])
end

---@param v Sheet.Values
---@param n integer
---@param i integer
---@param d integer
---@return integer
local function opt_int (v, n, i, d)
  if i > n then
    return d
  end
  return trunc (to_number (v[i]))
end

---@param v Sheet.Values
---@param n integer
---@param i integer
---@param d boolean
---@return boolean
local function opt_bool (v, n, i, d)
  if i > n then
    return d
  end
  return to_bool (v[i])
end

---A clock for reading dates written without a year, from the workbook's clock.
---@param ctx Sheet.Context
---@return fun(): number
local function today_clock (ctx)
  return function ()
    return now (ctx)
  end
end

---A date argument as a serial number. Text such as `2026-09-29` counts, and a date before
---1899-12-30 is #NUM!.
---@param v Sheet.Value
---@param ctx? Sheet.Context
---@return number
local function date_arg (v, ctx)
  local n ---@type number?
  if type (v) == 'string' then
    n = M.parse_number (v)
      or parse_datetime (v, ctx and today_clock (ctx) or nil)
    if not n then
      return raise ('#VALUE!')
    end
  else
    n = to_number (v)
  end
  if n < 0 or n > LAST_DAY + 1 then
    return raise ('#NUM!')
  end
  return n
end

local CATALOG = {} ---@type Sheet.CatalogEntry[]

---Adds a function and its catalog entry.
---@param name string
---@param category Sheet.Category
---@param syntax string
---@param summary string
---@param spec Sheet.Function
local function define (name, category, syntax, summary, spec)
  FUNCS[name] = spec
  CATALOG[#CATALOG + 1] = {
    name = name,
    category = category,
    syntax = syntax,
    summary = summary,
  }
end

---A function of one number.
---@param fn fun(x: number): number
---@return Sheet.Function
local function math1 (fn)
  return {
    min = 1,
    max = 1,
    map = function (v)
      return fn (to_number (v[1]))
    end,
  }
end

---A function of one text.
---@param fn fun(s: string): Sheet.Value
---@return Sheet.Function
local function text1 (fn)
  return {
    min = 1,
    max = 1,
    map = function (v)
      return fn (to_text (v[1]))
    end,
  }
end

---A test of one value that sees errors too, such as ISERROR.
---@param fn fun(v: Sheet.Value): boolean
---@return Sheet.Function
local function test1 (fn)
  return {
    min = 1,
    max = 1,
    catch = true,
    map = function (v)
      return fn (v[1])
    end,
  }
end

---@param list number[]
---@return number
local function total_of (list)
  local total = 0.0
  for _, x in ipairs (list) do
    total = total + x
  end
  return total
end

---The variance of a list, of a sample or of the whole population.
---@param list number[]
---@param sample boolean
---@return number
local function variance (list, sample)
  local n = #list
  if n < (sample and 2 or 1) then
    return raise ('#DIV/0!')
  end
  local mean = total_of (list) / n
  local squares = 0.0
  for _, x in ipairs (list) do
    squares = squares + (x - mean) ^ 2
  end
  return squares / (sample and n - 1 or n)
end

---The value at fraction `k` of a sorted list, between two values when it falls between them.
---@param list number[]
---@param k number
---@return number
local function percentile (list, k)
  local n = #list
  if n == 0 or k < 0 or k > 1 then
    return raise ('#NUM!')
  end
  table.sort (list)
  local pos = k * (n - 1) + 1
  local low = math.floor (pos)
  local frac = pos - low
  if low >= n then
    return list[n]
  end
  return list[low] + frac * (list[low + 1] - list[low])
end

---Pairs of numbers from two blocks of the same size, for SLOPE and its kin. A pair where either
---side is not a number is left out.
---@param ynode Sheet.Node
---@param xnode Sheet.Node
---@param ctx Sheet.Context
---@return number[] ys
---@return number[] xs
local function paired (ynode, xnode, ctx)
  local yv, xv = grid_or_value (ynode, ctx), grid_or_value (xnode, ctx)
  local yh, yw = dims (yv)
  local xh, xw = dims (xv)
  if yh * yw ~= xh * xw then
    error (ERRORS['#N/A'], 0)
  end
  local ys, xs = {}, {} ---@type number[], number[]
  for k = 1, yh * yw do
    local y, x = yv, xv ---@type Sheet.Result, Sheet.Result
    if is_grid (yv) then
      y = grid_at (
        yv --[[@as Sheet.Grid]],
        math.floor ((k - 1) / yw) + 1,
        (k - 1) % yw + 1,
        ctx
      )
    end
    if is_grid (xv) then
      x = grid_at (
        xv --[[@as Sheet.Grid]],
        math.floor ((k - 1) / xw) + 1,
        (k - 1) % xw + 1,
        ctx
      )
    end
    if is_error (y) then
      error (y, 0)
    end
    if is_error (x) then
      error (x, 0)
    end
    if type (y) == 'number' and type (x) == 'number' then
      ys[#ys + 1] = y
      xs[#xs + 1] = x
    end
  end
  return ys, xs
end

---The slope and the intercept of the straight line that best fits the pairs.
---@param ys number[]
---@param xs number[]
---@return number slope
---@return number intercept
local function fit (ys, xs)
  local n = #xs
  if n == 0 then
    error (ERRORS['#DIV/0!'], 0)
  end
  local mx, my = total_of (xs) / n, total_of (ys) / n
  local sxy, sxx = 0.0, 0.0
  for i = 1, n do
    sxy = sxy + (xs[i] - mx) * (ys[i] - my)
    sxx = sxx + (xs[i] - mx) ^ 2
  end
  if sxx == 0 then
    error (ERRORS['#DIV/0!'], 0)
  end
  local slope = sxy / sxx ---@type number
  return slope, my - slope * mx
end

---------------------------------------------------------------------------------------------
-- Math
---------------------------------------------------------------------------------------------

define (
  'SUM',
  'Math',
  'SUM(number1, [number2], ...)',
  'Adds numbers and the numbers in ranges.',
  {
    min = 1,
    max = MANY,
    run = function (args, ctx)
      return total_of (numbers (args, ctx))
    end,
  }
)

define (
  'SUMIF',
  'Math',
  'SUMIF(range, criterion, [sum_range])',
  'Adds the numbers in a range that meet a condition.',
  {
    min = 2,
    max = 3,
    run = function (args, ctx)
      local total = 0.0
      each_match (args, 1, 2, args[3], true, ctx, function (v)
        if type (v) == 'number' then
          total = total + v
        elseif type (v) == 'table' then
          raise_value (v)
        end
      end)
      return total
    end,
  }
)

define (
  'SUMIFS',
  'Math',
  'SUMIFS(sum_range, criteria_range1, criterion1, [criteria_range2, criterion2], ...)',
  'Adds the numbers in a range whose rows meet every condition.',
  {
    min = 3,
    max = MANY,
    run = function (args, ctx)
      local total = 0.0
      each_match (args, 2, #args, args[1], false, ctx, function (v)
        if type (v) == 'number' then
          total = total + v
        elseif type (v) == 'table' then
          raise_value (v)
        end
      end)
      return total
    end,
  }
)

define (
  'SUMPRODUCT',
  'Math',
  'SUMPRODUCT(array1, [array2], ...)',
  'Multiplies matching values in arrays of the same size and adds the products.',
  {
    min = 1,
    max = MANY,
    run = function (args, ctx)
      local grids = {} ---@type Sheet.Result[]
      local h, w = 0, 0
      for i, node in ipairs (args) do
        local g = grid_or_value (node, ctx)
        local gh, gw = dims (g)
        if i == 1 then
          h, w = gh, gw
        elseif gh ~= h or gw ~= w then
          return raise ('#VALUE!')
        end
        grids[i] = g
      end
      local total = 0.0
      for r = 1, h do
        for c = 1, w do
          local p = 1.0
          for _, g in ipairs (grids) do
            local v = g ---@type Sheet.Result
            if is_grid (g) then
              v = grid_at (g --[[@as Sheet.Grid]], r, c, ctx)
            end
            if type (v) == 'number' then
              p = p * v
            elseif is_error (v) then
              return raise_value (v)
            else
              -- Text, TRUE, FALSE and empty cells count as 0, as in spreadsheets.
              p = 0
            end
          end
          total = total + p
        end
      end
      return total
    end,
  }
)

define (
  'SUMSQ',
  'Math',
  'SUMSQ(number1, [number2], ...)',
  'Adds the squares of numbers.',
  {
    min = 1,
    max = MANY,
    run = function (args, ctx)
      local total = 0.0
      for _, x in ipairs (numbers (args, ctx)) do
        total = total + x * x
      end
      return total
    end,
  }
)

define (
  'PRODUCT',
  'Math',
  'PRODUCT(number1, [number2], ...)',
  'Multiplies numbers together.',
  {
    min = 1,
    max = MANY,
    run = function (args, ctx)
      local list = numbers (args, ctx)
      if #list == 0 then
        return 0
      end
      local p = 1.0
      for _, x in ipairs (list) do
        p = p * x
      end
      return p
    end,
  }
)

define (
  'ABS',
  'Math',
  'ABS(number)',
  'Gives a number without its sign.',
  math1 (math.abs)
)

---@param mode 'near'|'up'|'down'
---@return Sheet.Function
local function rounding (mode)
  return {
    min = 1,
    max = 2,
    map = function (v, n)
      return round_to (to_number (v[1]), opt_int (v, n, 2, 0), mode)
    end,
  }
end

define (
  'ROUND',
  'Math',
  'ROUND(number, [digits])',
  'Rounds a number to a number of decimal places, halves away from zero.',
  rounding ('near')
)
define (
  'ROUNDUP',
  'Math',
  'ROUNDUP(number, [digits])',
  'Rounds a number away from zero to a number of decimal places.',
  rounding ('up')
)
define (
  'ROUNDDOWN',
  'Math',
  'ROUNDDOWN(number, [digits])',
  'Rounds a number toward zero to a number of decimal places.',
  rounding ('down')
)
define (
  'TRUNC',
  'Math',
  'TRUNC(number, [digits])',
  'Cuts off the decimal places of a number past a point.',
  rounding ('down')
)

define (
  'MROUND',
  'Math',
  'MROUND(number, multiple)',
  'Rounds a number to the nearest multiple of another.',
  {
    min = 2,
    max = 2,
    map = function (v)
      local x, m = to_number (v[1]), to_number (v[2])
      if m == 0 or x == 0 then
        return 0
      end
      if (x > 0) ~= (m > 0) then
        return raise ('#NUM!')
      end
      return round_to (x / m, 0, 'near') * m
    end,
  }
)

define (
  'INT',
  'Math',
  'INT(number)',
  'Rounds a number down to a whole number.',
  math1 (function (x)
    return math.floor (x)
  end)
)

define (
  'CEILING',
  'Math',
  'CEILING(number, [significance])',
  'Rounds a number up to a multiple of the significance.',
  {
    min = 1,
    max = 2,
    map = function (v, n)
      local x, s = to_number (v[1]), opt (v, n, 2, 1)
      if s == 0 or x == 0 then
        return 0
      end
      if x > 0 and s < 0 then
        return raise ('#NUM!')
      end
      return math.ceil (clean (x / s)) * s
    end,
  }
)

define (
  'CEILING.MATH',
  'Math',
  'CEILING.MATH(number, [significance], [mode])',
  'Rounds a number up to a multiple, with negative numbers away from zero when the mode is set.',
  {
    min = 1,
    max = 3,
    map = function (v, n)
      local x, s = to_number (v[1]), math.abs (opt (v, n, 2, 1))
      if s == 0 or x == 0 then
        return 0
      end
      if x < 0 and opt (v, n, 3, 0) ~= 0 then
        return -math.ceil (clean (-x / s)) * s
      end
      return math.ceil (clean (x / s)) * s
    end,
  }
)

define (
  'FLOOR',
  'Math',
  'FLOOR(number, [significance])',
  'Rounds a number down to a multiple of the significance.',
  {
    min = 1,
    max = 2,
    map = function (v, n)
      local x, s = to_number (v[1]), opt (v, n, 2, 1)
      if x == 0 then
        return 0
      end
      if s == 0 then
        return raise ('#DIV/0!')
      end
      if x > 0 and s < 0 then
        return raise ('#NUM!')
      end
      return math.floor (clean (x / s)) * s
    end,
  }
)

define (
  'FLOOR.MATH',
  'Math',
  'FLOOR.MATH(number, [significance], [mode])',
  'Rounds a number down to a multiple, with negative numbers toward zero when the mode is set.',
  {
    min = 1,
    max = 3,
    map = function (v, n)
      local x, s = to_number (v[1]), math.abs (opt (v, n, 2, 1))
      if s == 0 or x == 0 then
        return 0
      end
      if x < 0 and opt (v, n, 3, 0) ~= 0 then
        return -math.floor (clean (-x / s)) * s
      end
      return math.floor (clean (x / s)) * s
    end,
  }
)

define (
  'EVEN',
  'Math',
  'EVEN(number)',
  'Rounds a number away from zero to the next even whole number.',
  math1 (function (x)
    local a = math.ceil (clean (math.abs (x)))
    if a % 2 == 1 then
      a = a + 1
    end
    return x < 0 and -a or a
  end)
)

define (
  'ODD',
  'Math',
  'ODD(number)',
  'Rounds a number away from zero to the next odd whole number.',
  math1 (function (x)
    local a = math.ceil (clean (math.abs (x)))
    if a % 2 == 0 then
      a = a + 1
    end
    return x < 0 and -a or a
  end)
)

define (
  'MOD',
  'Math',
  'MOD(number, divisor)',
  'Gives the remainder after a division, with the sign of the divisor.',
  {
    min = 2,
    max = 2,
    map = function (v)
      local a, b = to_number (v[1]), to_number (v[2])
      if b == 0 then
        return raise ('#DIV/0!')
      end
      return a - b * math.floor (a / b)
    end,
  }
)

define (
  'QUOTIENT',
  'Math',
  'QUOTIENT(numerator, denominator)',
  'Divides and keeps the whole part of the result.',
  {
    min = 2,
    max = 2,
    map = function (v)
      local a, b = to_number (v[1]), to_number (v[2])
      if b == 0 then
        return raise ('#DIV/0!')
      end
      return trunc (a / b)
    end,
  }
)

define ('POWER', 'Math', 'POWER(number, power)', 'Raises a number to a power.', {
  min = 2,
  max = 2,
  map = function (v)
    local x, y = to_number (v[1]), to_number (v[2])
    if x == 0 and y < 0 then
      return raise ('#DIV/0!')
    end
    return x ^ y
  end,
})

define (
  'SQRT',
  'Math',
  'SQRT(number)',
  'Gives the square root of a number.',
  math1 (function (x)
    if x < 0 then
      return raise ('#NUM!')
    end
    return math.sqrt (x)
  end)
)

define ('EXP', 'Math', 'EXP(number)', 'Raises e to a power.', math1 (math.exp))

define (
  'LN',
  'Math',
  'LN(number)',
  'Gives the natural logarithm of a number.',
  math1 (function (x)
    if x <= 0 then
      return raise ('#NUM!')
    end
    return log (x)
  end)
)

define (
  'LOG',
  'Math',
  'LOG(number, [base])',
  'Gives the logarithm of a number, in base 10 unless another base is given.',
  {
    min = 1,
    max = 2,
    map = function (v, n)
      local x, base = to_number (v[1]), opt (v, n, 2, 10)
      if x <= 0 or base <= 0 then
        return raise ('#NUM!')
      end
      if base == 1 then
        return raise ('#DIV/0!')
      end
      return log (x, base)
    end,
  }
)

define (
  'LOG10',
  'Math',
  'LOG10(number)',
  'Gives the logarithm of a number in base 10.',
  math1 (function (x)
    if x <= 0 then
      return raise ('#NUM!')
    end
    return log (x, 10)
  end)
)

define ('PI', 'Math', 'PI()', 'Gives the number pi, 3.14159265358979.', {
  min = 0,
  max = 0,
  map = function ()
    return math.pi
  end,
})

define ('RAND', 'Math', 'RAND()', 'Gives a random number from 0 up to 1.', {
  min = 0,
  max = 0,
  map = function (_, _, ctx)
    return random (ctx)
  end,
})

define (
  'RANDBETWEEN',
  'Math',
  'RANDBETWEEN(low, high)',
  'Gives a random whole number between two numbers.',
  {
    min = 2,
    max = 2,
    map = function (v, _, ctx)
      local lo = math.ceil (to_number (v[1]))
      local hi = math.floor (to_number (v[2]))
      if lo > hi then
        return raise ('#NUM!')
      end
      return lo + math.floor (random (ctx) * (hi - lo + 1))
    end,
  }
)

define (
  'SIGN',
  'Math',
  'SIGN(number)',
  'Gives 1 for a positive number, -1 for a negative one and 0 for zero.',
  math1 (function (x)
    if x > 0 then
      return 1
    end
    if x < 0 then
      return -1
    end
    return 0
  end)
)

---The whole numbers for GCD and LCM. A negative number is #NUM!.
---@param args Sheet.Node[]
---@param ctx Sheet.Context
---@return integer[]
local function whole_numbers (args, ctx)
  local out = {} ---@type integer[]
  for i, x in ipairs (numbers (args, ctx)) do
    if x < 0 or x >= 2 ^ 53 then
      return raise ('#NUM!')
    end
    out[i] = math.floor (x)
  end
  return out
end

---@param a integer
---@param b integer
---@return integer
local function gcd (a, b)
  while b ~= 0 do
    local rest = a % b ---@type integer
    a = b
    b = rest
  end
  return a
end

define (
  'GCD',
  'Math',
  'GCD(number1, [number2], ...)',
  'Gives the greatest whole number that divides every number.',
  {
    min = 1,
    max = MANY,
    run = function (args, ctx)
      local g = 0
      for _, x in ipairs (whole_numbers (args, ctx)) do
        g = gcd (g, x)
      end
      return g
    end,
  }
)

define (
  'LCM',
  'Math',
  'LCM(number1, [number2], ...)',
  'Gives the smallest whole number that every number divides.',
  {
    min = 1,
    max = MANY,
    run = function (args, ctx)
      local l = 1
      for _, x in ipairs (whole_numbers (args, ctx)) do
        if x == 0 then
          return 0
        end
        l = l / gcd (l, x) * x
      end
      return l
    end,
  }
)

define (
  'FACT',
  'Math',
  'FACT(number)',
  'Gives the factorial of a number, 1 times 2 times 3 and so on up to it.',
  math1 (function (x)
    if x < 0 then
      return raise ('#NUM!')
    end
    local p = 1.0
    for i = 2, math.floor (x) do
      p = p * i
      if p == math.huge then
        return raise ('#NUM!')
      end
    end
    return p
  end)
)

---Checks the arguments of COMBIN and PERMUT and cuts them to whole numbers.
---@param v Sheet.Values
---@return integer n
---@return integer k
local function choose_args (v)
  local n, k = trunc (to_number (v[1])), trunc (to_number (v[2]))
  if n < 0 or k < 0 or k > n then
    error (ERRORS['#NUM!'], 0)
  end
  return n, k
end

define (
  'COMBIN',
  'Math',
  'COMBIN(number, chosen)',
  'Gives the number of ways to choose some items from a set, in any order.',
  {
    min = 2,
    max = 2,
    map = function (v)
      local n, k = choose_args (v)
      k = math.min (k, n - k)
      local r = 1.0
      for i = 1, k do
        r = r * (n - k + i) / i
      end
      return math.floor (r + 0.5)
    end,
  }
)

define (
  'PERMUT',
  'Math',
  'PERMUT(number, chosen)',
  'Gives the number of ways to choose some items from a set, in order.',
  {
    min = 2,
    max = 2,
    map = function (v)
      local n, k = choose_args (v)
      local r = 1.0
      for i = n - k + 1, n do
        r = r * i
      end
      return r
    end,
  }
)

define (
  'DEGREES',
  'Math',
  'DEGREES(angle)',
  'Turns radians into degrees.',
  math1 (function (x)
    return x * 180 / math.pi
  end)
)

define (
  'RADIANS',
  'Math',
  'RADIANS(angle)',
  'Turns degrees into radians.',
  math1 (function (x)
    return x * math.pi / 180
  end)
)

define (
  'SIN',
  'Math',
  'SIN(angle)',
  'Gives the sine of an angle in radians.',
  math1 (math.sin)
)
define (
  'COS',
  'Math',
  'COS(angle)',
  'Gives the cosine of an angle in radians.',
  math1 (math.cos)
)
define (
  'TAN',
  'Math',
  'TAN(angle)',
  'Gives the tangent of an angle in radians.',
  math1 (math.tan)
)

define (
  'ASIN',
  'Math',
  'ASIN(number)',
  'Gives the angle in radians whose sine is a number.',
  math1 (function (x)
    if x < -1 or x > 1 then
      return raise ('#NUM!')
    end
    return math.asin (x)
  end)
)

define (
  'ACOS',
  'Math',
  'ACOS(number)',
  'Gives the angle in radians whose cosine is a number.',
  math1 (function (x)
    if x < -1 or x > 1 then
      return raise ('#NUM!')
    end
    return math.acos (x)
  end)
)

define (
  'ATAN',
  'Math',
  'ATAN(number)',
  'Gives the angle in radians whose tangent is a number.',
  math1 (function (x)
    return atan (x)
  end)
)

define (
  'ATAN2',
  'Math',
  'ATAN2(x, y)',
  'Gives the angle in radians from the x axis to the point x, y.',
  {
    min = 2,
    max = 2,
    map = function (v)
      local x, y = to_number (v[1]), to_number (v[2])
      if x == 0 and y == 0 then
        return raise ('#DIV/0!')
      end
      return atan (y, x)
    end,
  }
)

---------------------------------------------------------------------------------------------
-- Statistics
---------------------------------------------------------------------------------------------

define (
  'AVERAGE',
  'Statistics',
  'AVERAGE(number1, [number2], ...)',
  'Gives the mean of numbers.',
  {
    min = 1,
    max = MANY,
    run = function (args, ctx)
      local list = numbers (args, ctx)
      if #list == 0 then
        return raise ('#DIV/0!')
      end
      return total_of (list) / #list
    end,
  }
)

define (
  'AVERAGEA',
  'Statistics',
  'AVERAGEA(value1, [value2], ...)',
  'Gives the mean of values, with text as 0 and TRUE as 1.',
  {
    min = 1,
    max = MANY,
    run = function (args, ctx)
      local total, count = 0.0, 0
      ---@param v Sheet.Value
      ---@param in_ref boolean
      local function add (v, in_ref)
        if not in_ref then
          total = total + to_number (v)
          count = count + 1
        elseif type (v) == 'table' then
          raise_value (v)
        elseif v ~= nil then
          -- In a range, text counts as 0 and TRUE as 1.
          if type (v) == 'number' then
            total = total + v
          elseif v == true then
            total = total + 1
          end
          count = count + 1
        end
      end
      for _, node in ipairs (args) do
        each (node, ctx, add)
      end
      if count == 0 then
        return raise ('#DIV/0!')
      end
      return total / count
    end,
  }
)

define (
  'AVERAGEIF',
  'Statistics',
  'AVERAGEIF(range, criterion, [average_range])',
  'Gives the mean of the numbers in a range that meet a condition.',
  {
    min = 2,
    max = 3,
    run = function (args, ctx)
      local total, count = 0.0, 0
      each_match (args, 1, 2, args[3], true, ctx, function (v)
        if type (v) == 'number' then
          total = total + v
          count = count + 1
        elseif type (v) == 'table' then
          raise_value (v)
        end
      end)
      if count == 0 then
        return raise ('#DIV/0!')
      end
      return total / count
    end,
  }
)

define (
  'AVERAGEIFS',
  'Statistics',
  'AVERAGEIFS(average_range, criteria_range1, criterion1, [criteria_range2, criterion2], ...)',
  'Gives the mean of the numbers in a range whose rows meet every condition.',
  {
    min = 3,
    max = MANY,
    run = function (args, ctx)
      local total, count = 0.0, 0
      each_match (args, 2, #args, args[1], false, ctx, function (v)
        if type (v) == 'number' then
          total = total + v
          count = count + 1
        elseif type (v) == 'table' then
          raise_value (v)
        end
      end)
      if count == 0 then
        return raise ('#DIV/0!')
      end
      return total / count
    end,
  }
)

define (
  'MEDIAN',
  'Statistics',
  'MEDIAN(number1, [number2], ...)',
  'Gives the middle value of numbers.',
  {
    min = 1,
    max = MANY,
    run = function (args, ctx)
      local list = numbers (args, ctx)
      return percentile (list, 0.5)
    end,
  }
)

---@type Sheet.Function
local MODE = {
  min = 1,
  max = MANY,
  run = function (args, ctx)
    local list = numbers (args, ctx)
    local counts = {} ---@type table<number, integer>
    local best, most = nil, 1 ---@type number?, integer
    -- Values that agree to 15 digits count as one, so 0.1+0.2 and 0.3 are the same value.
    for _, x in ipairs (list) do
      local key = clean (x)
      counts[key] = (counts[key] or 0) + 1
    end
    -- The first value in the data wins a tie, as in spreadsheets.
    for _, x in ipairs (list) do
      if counts[clean (x)] > most then
        best, most = x, counts[clean (x)]
      end
    end
    if not best then
      return raise ('#N/A')
    end
    return best
  end,
}
define (
  'MODE',
  'Statistics',
  'MODE(number1, [number2], ...)',
  'Gives the value that comes up most often.',
  MODE
)
define (
  'MODE.SNGL',
  'Statistics',
  'MODE.SNGL(number1, [number2], ...)',
  'Gives the value that comes up most often.',
  MODE
)

define (
  'MIN',
  'Statistics',
  'MIN(number1, [number2], ...)',
  'Gives the smallest number.',
  {
    min = 1,
    max = MANY,
    run = function (args, ctx)
      local low = nil ---@type number?
      for _, x in ipairs (numbers (args, ctx)) do
        if not low or x < low then
          low = x
        end
      end
      return low or 0
    end,
  }
)

define (
  'MAX',
  'Statistics',
  'MAX(number1, [number2], ...)',
  'Gives the largest number.',
  {
    min = 1,
    max = MANY,
    run = function (args, ctx)
      local high = nil ---@type number?
      for _, x in ipairs (numbers (args, ctx)) do
        if not high or x > high then
          high = x
        end
      end
      return high or 0
    end,
  }
)

---MINIFS and MAXIFS.
---@param want_max boolean
---@return Sheet.Function
local function extreme_ifs (want_max)
  return {
    min = 3,
    max = MANY,
    run = function (args, ctx)
      local best = nil ---@type number?
      each_match (args, 2, #args, args[1], false, ctx, function (v)
        if type (v) == 'number' then
          if
            not best
            or (want_max and v > best)
            or (not want_max and v < best)
          then
            best = v
          end
        elseif type (v) == 'table' then
          raise_value (v)
        end
      end)
      return best or 0
    end,
  }
end

define (
  'MINIFS',
  'Statistics',
  'MINIFS(min_range, criteria_range1, criterion1, [criteria_range2, criterion2], ...)',
  'Gives the smallest number in a range whose rows meet every condition.',
  extreme_ifs (false)
)
define (
  'MAXIFS',
  'Statistics',
  'MAXIFS(max_range, criteria_range1, criterion1, [criteria_range2, criterion2], ...)',
  'Gives the largest number in a range whose rows meet every condition.',
  extreme_ifs (true)
)

---COUNT and COUNTA. They skip or count errors, as spreadsheets do, and never pass one on.
---@param any_value boolean True for COUNTA.
---@return Sheet.Function
local function counter (any_value)
  return {
    min = 1,
    max = MANY,
    run = function (args, ctx)
      local count = 0
      ---@param v Sheet.Value
      ---@param in_ref boolean
      local function add (v, in_ref)
        if any_value then
          if v ~= nil or not in_ref then
            count = count + 1
          end
        elseif
          type (v) == 'number'
          or (
            not in_ref
            and (
              type (v) == 'boolean'
              or (
                type (v) == 'string' and text_number (v --[[@as string]])
              )
            )
          )
        then
          -- Typed into the formula, TRUE and text that reads as a number count too.
          count = count + 1
        end
      end
      for i = 1, #args do
        local ok, err = pcall (each, args[i], ctx, add)
        if not ok then
          if not is_error (err) then
            error (err, 0)
          end
          if any_value then
            count = count + 1
          end
        end
      end
      return count
    end,
  }
end

define (
  'COUNT',
  'Statistics',
  'COUNT(value1, [value2], ...)',
  'Counts the numbers among values and ranges.',
  counter (false)
)
define (
  'COUNTA',
  'Statistics',
  'COUNTA(value1, [value2], ...)',
  'Counts the values and the cells that are not empty.',
  counter (true)
)

define (
  'COUNTBLANK',
  'Statistics',
  'COUNTBLANK(range)',
  'Counts the empty cells in a range.',
  {
    min = 1,
    max = 1,
    run = function (args, ctx)
      local count = 0
      each (args[1], ctx, function (v, in_ref)
        if not in_ref then
          raise ('#VALUE!')
        end
        if v == nil or v == '' then
          count = count + 1
        end
      end)
      return count
    end,
  }
)

define (
  'COUNTIF',
  'Statistics',
  'COUNTIF(range, criterion)',
  'Counts the cells in a range that meet a condition.',
  {
    min = 2,
    max = 2,
    run = function (args, ctx)
      local count = 0
      each_match (args, 1, 2, nil, false, ctx, function ()
        count = count + 1
      end)
      return count
    end,
  }
)

define (
  'COUNTIFS',
  'Statistics',
  'COUNTIFS(criteria_range1, criterion1, [criteria_range2, criterion2], ...)',
  'Counts the rows whose cells meet every condition.',
  {
    min = 2,
    max = MANY,
    run = function (args, ctx)
      local count = 0
      each_match (args, 1, #args, nil, false, ctx, function ()
        count = count + 1
      end)
      return count
    end,
  }
)

---LARGE and SMALL.
---@param from_top boolean
---@return Sheet.Function
local function kth (from_top)
  return {
    min = 2,
    max = 2,
    run = function (args, ctx)
      local list = numbers (args, ctx, 1, 1)
      local k = math.ceil (number_of (args[2], ctx))
      if k < 1 or k > #list then
        return raise ('#NUM!')
      end
      table.sort (list)
      if from_top then
        return list[#list - k + 1]
      end
      return list[k]
    end,
  }
end

define (
  'LARGE',
  'Statistics',
  'LARGE(data, k)',
  'Gives the k-th largest number.',
  kth (true)
)
define (
  'SMALL',
  'Statistics',
  'SMALL(data, k)',
  'Gives the k-th smallest number.',
  kth (false)
)

---RANK, RANK.EQ and RANK.AVG.
---@param average boolean
---@return Sheet.Function
local function ranking (average)
  return {
    min = 2,
    max = 3,
    run = function (args, ctx)
      local x = number_of (args[1], ctx)
      local list = numbers (args, ctx, 2, 2)
      local ascending = given (args[3]) and number_of (args[3], ctx) ~= 0
      local before, same = 0, 0
      for _, y in ipairs (list) do
        local c = num_compare (y, x)
        if c == 0 then
          same = same + 1
        elseif (ascending and c < 0) or (not ascending and c > 0) then
          before = before + 1
        end
      end
      if same == 0 then
        return raise ('#N/A')
      end
      if average then
        return before + (same + 1) / 2
      end
      return before + 1
    end,
  }
end

define (
  'RANK',
  'Statistics',
  'RANK(number, data, [ascending])',
  'Gives the place of a number in a list, the largest first unless ascending is set.',
  ranking (false)
)
define (
  'RANK.EQ',
  'Statistics',
  'RANK.EQ(number, data, [ascending])',
  'Gives the place of a number in a list, the largest first unless ascending is set.',
  ranking (false)
)
define (
  'RANK.AVG',
  'Statistics',
  'RANK.AVG(number, data, [ascending])',
  'Gives the place of a number in a list, with tied numbers sharing the mean of their places.',
  ranking (true)
)

---@type Sheet.Function
local PERCENTILE = {
  min = 2,
  max = 2,
  run = function (args, ctx)
    return percentile (numbers (args, ctx, 1, 1), number_of (args[2], ctx))
  end,
}
define (
  'PERCENTILE',
  'Statistics',
  'PERCENTILE(data, k)',
  'Gives the value below which a fraction k of the numbers fall.',
  PERCENTILE
)
define (
  'PERCENTILE.INC',
  'Statistics',
  'PERCENTILE.INC(data, k)',
  'Gives the value below which a fraction k of the numbers fall.',
  PERCENTILE
)

---@type Sheet.Function
local QUARTILE = {
  min = 2,
  max = 2,
  run = function (args, ctx)
    local q = int_of (args[2], ctx)
    if q < 0 or q > 4 then
      return raise ('#NUM!')
    end
    return percentile (numbers (args, ctx, 1, 1), q / 4)
  end,
}
define (
  'QUARTILE',
  'Statistics',
  'QUARTILE(data, quart)',
  'Gives a quartile of numbers: 0 is the smallest, 2 the median and 4 the largest.',
  QUARTILE
)
define (
  'QUARTILE.INC',
  'Statistics',
  'QUARTILE.INC(data, quart)',
  'Gives a quartile of numbers: 0 is the smallest, 2 the median and 4 the largest.',
  QUARTILE
)

---Variance and standard deviation, of a sample or of the whole population.
---@param sample boolean
---@param root boolean True for the standard deviation.
---@return Sheet.Function
local function spread (sample, root)
  return {
    min = 1,
    max = MANY,
    run = function (args, ctx)
      local v = variance (numbers (args, ctx), sample)
      return root and math.sqrt (v) or v
    end,
  }
end

define (
  'STDEV',
  'Statistics',
  'STDEV(number1, [number2], ...)',
  'Gives the standard deviation of a sample.',
  spread (true, true)
)
define (
  'STDEV.S',
  'Statistics',
  'STDEV.S(number1, [number2], ...)',
  'Gives the standard deviation of a sample.',
  spread (true, true)
)
define (
  'STDEVP',
  'Statistics',
  'STDEVP(number1, [number2], ...)',
  'Gives the standard deviation of a whole population.',
  spread (false, true)
)
define (
  'STDEV.P',
  'Statistics',
  'STDEV.P(number1, [number2], ...)',
  'Gives the standard deviation of a whole population.',
  spread (false, true)
)
define (
  'VAR',
  'Statistics',
  'VAR(number1, [number2], ...)',
  'Gives the variance of a sample.',
  spread (true, false)
)
define (
  'VAR.S',
  'Statistics',
  'VAR.S(number1, [number2], ...)',
  'Gives the variance of a sample.',
  spread (true, false)
)
define (
  'VARP',
  'Statistics',
  'VARP(number1, [number2], ...)',
  'Gives the variance of a whole population.',
  spread (false, false)
)
define (
  'VAR.P',
  'Statistics',
  'VAR.P(number1, [number2], ...)',
  'Gives the variance of a whole population.',
  spread (false, false)
)

define (
  'CORREL',
  'Statistics',
  'CORREL(data1, data2)',
  'Gives how closely two sets of numbers move together, from -1 to 1.',
  {
    min = 2,
    max = 2,
    run = function (args, ctx)
      local ys, xs = paired (args[1], args[2], ctx)
      local n = #xs
      if n == 0 then
        return raise ('#DIV/0!')
      end
      local mx, my = total_of (xs) / n, total_of (ys) / n
      local sxy, sxx, syy = 0.0, 0.0, 0.0
      for i = 1, n do
        sxy = sxy + (xs[i] - mx) * (ys[i] - my)
        sxx = sxx + (xs[i] - mx) ^ 2
        syy = syy + (ys[i] - my) ^ 2
      end
      if sxx == 0 or syy == 0 then
        return raise ('#DIV/0!')
      end
      return sxy / math.sqrt (sxx * syy)
    end,
  }
)

define (
  'SLOPE',
  'Statistics',
  'SLOPE(known_ys, known_xs)',
  'Gives the slope of the straight line that best fits pairs of numbers.',
  {
    min = 2,
    max = 2,
    run = function (args, ctx)
      local slope = fit (paired (args[1], args[2], ctx))
      return slope
    end,
  }
)

define (
  'INTERCEPT',
  'Statistics',
  'INTERCEPT(known_ys, known_xs)',
  'Gives where the straight line that best fits pairs of numbers crosses the y axis.',
  {
    min = 2,
    max = 2,
    run = function (args, ctx)
      local _, intercept = fit (paired (args[1], args[2], ctx))
      return intercept
    end,
  }
)

---@type Sheet.Function
local FORECAST = {
  min = 3,
  max = 3,
  run = function (args, ctx)
    local x = number_of (args[1], ctx)
    local slope, intercept = fit (paired (args[2], args[3], ctx))
    return intercept + slope * x
  end,
}
define (
  'FORECAST',
  'Statistics',
  'FORECAST(x, known_ys, known_xs)',
  'Predicts a y value for x from the straight line that best fits pairs of numbers.',
  FORECAST
)
define (
  'FORECAST.LINEAR',
  'Statistics',
  'FORECAST.LINEAR(x, known_ys, known_xs)',
  'Predicts a y value for x from the straight line that best fits pairs of numbers.',
  FORECAST
)

---------------------------------------------------------------------------------------------
-- Logic
---------------------------------------------------------------------------------------------

---An argument's result, left out as FALSE when it is not there.
---@param node Sheet.Node?
---@param ctx Sheet.Context
---@return Sheet.Result
local function branch (node, ctx)
  if not node then
    return false
  end
  return eval (node, ctx)
end

define (
  'IF',
  'Logic',
  'IF(condition, value_if_true, [value_if_false])',
  'Gives one value when a condition is true and another when it is false.',
  {
    min = 2,
    max = 3,
    run = function (args, ctx)
      local c = eval (args[1], ctx)
      if type (c) == 'table' then
        c = single (c, ctx)
      end
      if type (c) ~= 'table' then
        if
          to_bool (c --[[@as Sheet.Value]])
        then
          return branch (args[2], ctx)
        end
        return branch (args[3], ctx)
      end
      -- A condition over a block picks a value for each of its cells.
      local yes, no = branch (args[2], ctx), branch (args[3], ctx)
      local ch, cw = dims (c)
      local yh, yw = dims (yes)
      local nh, nw = dims (no)
      local h = math.max (ch, yh, nh)
      local w = math.max (cw, yw, nw)
      local out = {} ---@type Sheet.Values
      local k = 0
      for i = 1, h do
        for j = 1, w do
          k = k + 1
          local cv = spread_at (c --[[@as Sheet.Grid]], ch, cw, i, j, ctx)
          local ok, flag = pcall (to_bool, cv)
          if not ok then
            out[k] = is_error (flag) and flag or ERRORS['#VALUE!']
          else
            local pick = flag and yes or no
            local ph, pw = dims (pick)
            if is_grid (pick) then
              out[k] = spread_at (pick --[[@as Sheet.Grid]], ph, pw, i, j, ctx)
            else
              out[k] = pick --[[@as Sheet.Value]]
            end
          end
        end
      end
      return new_array (h, w, out)
    end,
  }
)

define (
  'IFS',
  'Logic',
  'IFS(condition1, value1, [condition2, value2], ...)',
  'Gives the value beside the first condition that is true.',
  {
    min = 2,
    max = MANY,
    run = function (args, ctx)
      if #args % 2 == 1 then
        return raise ('#VALUE!')
      end
      for i = 1, #args, 2 do
        if bool_of (args[i], ctx) then
          return eval (args[i + 1], ctx)
        end
      end
      return raise ('#N/A')
    end,
  }
)

---IFERROR and IFNA. Over a block, each cell with a matching error takes the fallback.
---@param code? string Only this error is caught, or any when nil.
---@return Sheet.Function
local function on_error (code)
  ---@param v any
  ---@return boolean
  local function caught (v)
    return is_error (v) and (code == nil or v.code == code)
  end
  return {
    min = 2,
    max = 2,
    run = function (args, ctx)
      local ok, v = pcall (eval, args[1], ctx)
      if not ok then
        if caught (v) then
          return eval (args[2], ctx)
        end
        return raise_value (v)
      end
      if not is_grid (v) then
        return v
      end
      local h, w = dims (v)
      if h == 1 and w == 1 then
        local x = grid_at (v --[[@as Sheet.Grid]], 1, 1, ctx)
        if caught (x) then
          return eval (args[2], ctx)
        end
        return x
      end
      local fallback = nil ---@type Sheet.Value
      local out = {} ---@type Sheet.Values
      local k = 0
      for i = 1, h do
        for j = 1, w do
          k = k + 1
          local x = grid_at (v --[[@as Sheet.Grid]], i, j, ctx)
          if caught (x) then
            if fallback == nil then
              fallback = value_of (args[2], ctx)
            end
            x = fallback
          end
          out[k] = x
        end
      end
      return new_array (h, w, out)
    end,
  }
end

define (
  'IFERROR',
  'Logic',
  'IFERROR(value, value_if_error)',
  'Gives a value, or a fallback when the value is an error.',
  on_error (nil)
)
define (
  'IFNA',
  'Logic',
  'IFNA(value, value_if_na)',
  'Gives a value, or a fallback when the value is #N/A.',
  on_error ('#N/A')
)

define (
  'AND',
  'Logic',
  'AND(logical1, [logical2], ...)',
  'Gives TRUE when every value is true.',
  {
    min = 1,
    max = MANY,
    run = function (args, ctx)
      for _, b in ipairs (logicals (args, ctx)) do
        if not b then
          return false
        end
      end
      return true
    end,
  }
)

define (
  'OR',
  'Logic',
  'OR(logical1, [logical2], ...)',
  'Gives TRUE when any value is true.',
  {
    min = 1,
    max = MANY,
    run = function (args, ctx)
      for _, b in ipairs (logicals (args, ctx)) do
        if b then
          return true
        end
      end
      return false
    end,
  }
)

define (
  'XOR',
  'Logic',
  'XOR(logical1, [logical2], ...)',
  'Gives TRUE when an odd number of values are true.',
  {
    min = 1,
    max = MANY,
    run = function (args, ctx)
      local count = 0
      for _, b in ipairs (logicals (args, ctx)) do
        if b then
          count = count + 1
        end
      end
      return count % 2 == 1
    end,
  }
)

define (
  'NOT',
  'Logic',
  'NOT(logical)',
  'Turns TRUE into FALSE and FALSE into TRUE.',
  {
    min = 1,
    max = 1,
    map = function (v)
      return not to_bool (v[1])
    end,
  }
)

define (
  'SWITCH',
  'Logic',
  'SWITCH(value, case1, result1, [case2, result2], ..., [default])',
  'Gives the result beside the first case that equals a value.',
  {
    min = 3,
    max = MANY,
    run = function (args, ctx)
      local x = value_of (args[1], ctx)
      local n = #args
      for i = 2, n - 1, 2 do
        if compare (x, value_of (args[i], ctx)) == 0 then
          return eval (args[i + 1], ctx)
        end
      end
      if n % 2 == 0 then
        return eval (args[n], ctx)
      end
      return raise ('#N/A')
    end,
  }
)

define ('TRUE', 'Logic', 'TRUE()', 'Gives TRUE.', {
  min = 0,
  max = 0,
  map = function ()
    return true
  end,
})

define ('FALSE', 'Logic', 'FALSE()', 'Gives FALSE.', {
  min = 0,
  max = 0,
  map = function ()
    return false
  end,
})

define (
  'CHOOSE',
  'Logic',
  'CHOOSE(index, value1, [value2], ...)',
  'Gives the value at a position in a list of values.',
  {
    min = 2,
    max = MANY,
    run = function (args, ctx)
      local i = int_of (args[1], ctx)
      if i < 1 or i >= #args then
        return raise ('#VALUE!')
      end
      return eval (args[i + 1], ctx)
    end,
  }
)

---------------------------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------------------------

---@type Sheet.Function
local CONCAT = {
  min = 1,
  max = MANY,
  run = function (args, ctx)
    local parts = {} ---@type string[]
    ---@param v Sheet.Value
    local function add (v)
      parts[#parts + 1] = to_text (v)
    end
    for _, node in ipairs (args) do
      each (node, ctx, add)
    end
    return table.concat (parts)
  end,
}
define (
  'CONCAT',
  'Text',
  'CONCAT(text1, [text2], ...)',
  'Joins text and the text in ranges into one.',
  CONCAT
)
define (
  'CONCATENATE',
  'Text',
  'CONCATENATE(text1, [text2], ...)',
  'Joins pieces of text into one.',
  CONCAT
)

define (
  'TEXTJOIN',
  'Text',
  'TEXTJOIN(delimiter, ignore_empty, text1, [text2], ...)',
  'Joins text with a delimiter between the pieces, leaving out empty ones when asked.',
  {
    min = 3,
    max = MANY,
    run = function (args, ctx)
      local delim = text_of (args[1], ctx)
      local skip = bool_of (args[2], ctx)
      local parts = {} ---@type string[]
      ---@param v Sheet.Value
      local function add (v)
        local s = to_text (v)
        if s ~= '' or not skip then
          parts[#parts + 1] = s
        end
      end
      for i = 3, #args do
        each (args[i], ctx, add)
      end
      return table.concat (parts, delim)
    end,
  }
)

define (
  'LEN',
  'Text',
  'LEN(text)',
  'Counts the characters in text.',
  text1 (length)
)

define (
  'LEFT',
  'Text',
  'LEFT(text, [count])',
  'Gives the first characters of text.',
  {
    min = 1,
    max = 2,
    map = function (v, n)
      local s = to_text (v[1])
      local count = opt_int (v, n, 2, 1)
      if count < 0 then
        return raise ('#VALUE!')
      end
      return string.sub (s, 1, byte_of (s, count + 1) - 1)
    end,
  }
)

define (
  'RIGHT',
  'Text',
  'RIGHT(text, [count])',
  'Gives the last characters of text.',
  {
    min = 1,
    max = 2,
    map = function (v, n)
      local s = to_text (v[1])
      local count = opt_int (v, n, 2, 1)
      if count < 0 then
        return raise ('#VALUE!')
      end
      local len = length (s)
      if count >= len then
        return s
      end
      return string.sub (s, byte_of (s, len - count + 1))
    end,
  }
)

define (
  'MID',
  'Text',
  'MID(text, start, count)',
  'Gives the characters of text from a start position.',
  {
    min = 3,
    max = 3,
    map = function (v)
      local s = to_text (v[1])
      local start, count = trunc (to_number (v[2])), trunc (to_number (v[3]))
      if start < 1 or count < 0 then
        return raise ('#VALUE!')
      end
      local a = byte_of (s, start)
      return string.sub (s, a, byte_of (s, start + count) - 1)
    end,
  }
)

define (
  'UPPER',
  'Text',
  'UPPER(text)',
  'Turns text into capital letters.',
  text1 (upper)
)
define (
  'LOWER',
  'Text',
  'LOWER(text)',
  'Turns text into small letters.',
  text1 (lower)
)

---True for a character that has a case or belongs to a word, for PROPER.
---@param ch string
---@return boolean
local function is_letter (ch)
  if #ch == 1 then
    return string.match (ch, '%a') ~= nil
  end
  local b1, b2 = string.byte (ch, 1, 2)
  if b1 == 194 or b1 == 226 then
    -- Symbols and punctuation such as ©, « and the typographic quotes and dashes.
    return false
  end
  return not (b1 == 195 and (b2 == 151 or b2 == 183))
end

define (
  'PROPER',
  'Text',
  'PROPER(text)',
  'Gives each word a capital first letter and small letters after it.',
  text1 (function (s)
    local out = {} ---@type string[]
    local inside = false
    for ch in string.gmatch (s, utf8.charpattern) do
      local letter = is_letter (ch)
      if letter then
        out[#out + 1] = inside and lower (ch) or upper (ch)
      else
        out[#out + 1] = ch
      end
      inside = letter
    end
    return table.concat (out)
  end)
)

define (
  'TRIM',
  'Text',
  'TRIM(text)',
  'Takes spaces off both ends of text and leaves one space between words.',
  text1 (function (s)
    local out = string.gsub (s, '^ +', '')
    out = string.gsub (out, ' +$', '')
    out = string.gsub (out, '  +', ' ')
    return out
  end)
)

define (
  'CLEAN',
  'Text',
  'CLEAN(text)',
  'Takes the control characters out of text.',
  text1 (function (s)
    return (string.gsub (s, '[\0-\31]', ''))
  end)
)

define (
  'SUBSTITUTE',
  'Text',
  'SUBSTITUTE(text, old_text, new_text, [instance])',
  'Replaces old text with new text, every time or only at one instance.',
  {
    min = 3,
    max = 4,
    map = function (v, n)
      local s = to_text (v[1])
      local old, new = to_text (v[2]), to_text (v[3])
      local which = n >= 4 and trunc (to_number (v[4])) or nil
      if which and which < 1 then
        return raise ('#VALUE!')
      end
      if old == '' then
        return s
      end
      local out = {} ---@type string[]
      local i, count = 1, 0
      while true do
        local a, b = string.find (s, old, i, true)
        if not a then
          break
        end
        count = count + 1
        if not which or count == which then
          out[#out + 1] = string.sub (s, i, a - 1) .. new
        else
          out[#out + 1] = string.sub (s, i, b)
        end
        i = b + 1
        if which and count == which then
          break
        end
      end
      out[#out + 1] = string.sub (s, i)
      return table.concat (out)
    end,
  }
)

define (
  'REPLACE',
  'Text',
  'REPLACE(text, start, count, new_text)',
  'Replaces a number of characters of text from a start position.',
  {
    min = 4,
    max = 4,
    map = function (v)
      local s = to_text (v[1])
      local start, count = trunc (to_number (v[2])), trunc (to_number (v[3]))
      if start < 1 or count < 0 then
        return raise ('#VALUE!')
      end
      local new = to_text (v[4])
      return string.sub (s, 1, byte_of (s, start) - 1)
        .. new
        .. string.sub (s, byte_of (s, start + count))
    end,
  }
)

---FIND and SEARCH. Returns the character position where `needle` starts in `hay`.
---@param v Sheet.Values
---@param n integer
---@param search boolean True for SEARCH: no case, and wildcards.
---@return integer
local function find_text (v, n, search)
  local needle, hay = to_text (v[1]), to_text (v[2])
  local start = opt_int (v, n, 3, 1)
  if start < 1 or start > length (hay) + 1 then
    return raise ('#VALUE!')
  end
  if needle == '' then
    return start
  end
  local byte = byte_of (hay, start)
  local pos ---@type integer?
  if search then
    pos = string.find (lower (hay), wildcard (lower (needle), false), byte)
  else
    pos = string.find (hay, needle, byte, true)
  end
  if not pos then
    return raise ('#VALUE!')
  end
  return length (string.sub (hay, 1, pos - 1)) + 1
end

define (
  'FIND',
  'Text',
  'FIND(find_text, within_text, [start])',
  'Gives the position of text inside other text, minding case.',
  {
    min = 2,
    max = 3,
    map = function (v, n)
      return find_text (v, n, false)
    end,
  }
)

define (
  'SEARCH',
  'Text',
  'SEARCH(find_text, within_text, [start])',
  'Gives the position of text inside other text, ignoring case and allowing wildcards.',
  {
    min = 2,
    max = 3,
    map = function (v, n)
      return find_text (v, n, true)
    end,
  }
)

define ('REPT', 'Text', 'REPT(text, times)', 'Repeats text a number of times.', {
  min = 2,
  max = 2,
  map = function (v)
    local s = to_text (v[1])
    local times = trunc (to_number (v[2]))
    if times < 0 or #s * times > 32767 then
      return raise ('#VALUE!')
    end
    return string.rep (s, times)
  end,
})

define (
  'EXACT',
  'Text',
  'EXACT(text1, text2)',
  'Gives TRUE when two pieces of text are the same, minding case.',
  {
    min = 2,
    max = 2,
    map = function (v)
      return to_text (v[1]) == to_text (v[2])
    end,
  }
)

define (
  'TEXT',
  'Text',
  'TEXT(value, format)',
  'Formats a number as text, such as "0.00" or "yyyy-mm-dd".',
  {
    min = 2,
    max = 2,
    map = function (v)
      local x = v[1]
      local fmt = to_text (v[2])
      local n = 0.0
      if type (x) == 'number' then
        n = x
      elseif type (x) == 'string' then
        local parsed = M.parse_number (x)
        if not parsed then
          return x
        end
        n = parsed
      elseif type (x) == 'boolean' then
        return x and 'TRUE' or 'FALSE'
      end
      return M.format (n, fmt)
    end,
  }
)

define (
  'VALUE',
  'Text',
  'VALUE(text)',
  'Turns text that shows a number, a date or a time into a number.',
  {
    min = 1,
    max = 1,
    map = function (v)
      local x = v[1]
      if type (x) == 'number' then
        return x
      end
      if x == nil then
        return 0
      end
      if type (x) == 'string' then
        local n = text_number (x)
        if n then
          return n
        end
      end
      return raise ('#VALUE!')
    end,
  }
)

define (
  'CHAR',
  'Text',
  'CHAR(number)',
  'Gives the character with a code from 1 to 255.',
  {
    min = 1,
    max = 1,
    map = function (v)
      local code = trunc (to_number (v[1]))
      if code < 1 or code > 255 then
        return raise ('#VALUE!')
      end
      return utf8.char (code)
    end,
  }
)

---The code of the first character of text.
---@param s string
---@return integer
local function first_code (s)
  if s == '' then
    return raise ('#VALUE!')
  end
  local ok, code = pcall (utf8.codepoint, s, 1)
  if ok then
    return code
  end
  return string.byte (s, 1)
end

define (
  'CODE',
  'Text',
  'CODE(text)',
  'Gives the code of the first character of text.',
  text1 (first_code)
)

define (
  'UNICHAR',
  'Text',
  'UNICHAR(number)',
  'Gives the character with a Unicode number.',
  {
    min = 1,
    max = 1,
    map = function (v)
      local code = trunc (to_number (v[1]))
      if code < 1 or code > 1114111 or (code >= 55296 and code <= 57343) then
        return raise ('#VALUE!')
      end
      return utf8.char (code)
    end,
  }
)

define (
  'UNICODE',
  'Text',
  'UNICODE(text)',
  'Gives the Unicode number of the first character of text.',
  text1 (first_code)
)

define (
  'T',
  'Text',
  'T(value)',
  'Gives a value when it is text, and empty text otherwise.',
  {
    min = 1,
    max = 1,
    map = function (v)
      if type (v[1]) == 'string' then
        return v[1]
      end
      return ''
    end,
  }
)

define (
  'N',
  'Text',
  'N(value)',
  'Gives a value when it is a number, 1 or 0 for TRUE or FALSE, and 0 otherwise.',
  {
    min = 1,
    max = 1,
    map = function (v)
      local x = v[1]
      if type (x) == 'number' then
        return x
      end
      if type (x) == 'boolean' then
        return x and 1 or 0
      end
      return 0
    end,
  }
)

---A number rounded to `digits` decimals and written with a format code.
---@param x number
---@param digits integer
---@param head string The format before the decimals, such as `#,##0`.
---@return string
---@return number rounded
local function fixed_text (x, digits, head)
  if digits > 127 then
    error (ERRORS['#VALUE!'], 0)
  end
  local r = round_to (x, digits, 'near')
  local code = head
  if digits > 0 then
    code = code .. '.' .. string.rep ('0', digits)
  end
  return M.format (math.abs (r), code), r
end

define (
  'FIXED',
  'Text',
  'FIXED(number, [decimals], [no_commas])',
  'Rounds a number and writes it as text, with commas unless asked not to.',
  {
    min = 1,
    max = 3,
    map = function (v, n)
      local plain = opt_bool (v, n, 3, false)
      local text, r = fixed_text (
        to_number (v[1]),
        opt_int (v, n, 2, 2),
        plain and '0' or '#,##0'
      )
      return (r < 0 and '-' or '') .. text
    end,
  }
)

define (
  'DOLLAR',
  'Text',
  'DOLLAR(number, [decimals])',
  'Rounds a number and writes it as money, such as $1,234.57.',
  {
    min = 1,
    max = 2,
    map = function (v, n)
      local text, r =
        fixed_text (to_number (v[1]), opt_int (v, n, 2, 2), '$#,##0')
      -- A negative amount goes in brackets, as the US money format writes it.
      if r < 0 then
        return '(' .. text .. ')'
      end
      return text
    end,
  }
)

---TEXTBEFORE and TEXTAFTER.
---@param after boolean
---@return Sheet.Function
local function text_around (after)
  return {
    min = 2,
    max = 6,
    map = function (v, n)
      local s, delim = to_text (v[1]), to_text (v[2])
      local instance = opt_int (v, n, 3, 1)
      local no_case = opt (v, n, 4, 0) ~= 0
      local match_end = opt (v, n, 5, 0) ~= 0
      if instance == 0 then
        return raise ('#VALUE!')
      end
      local starts = {} ---@type integer[]
      if delim ~= '' then
        local hay = no_case and lower (s) or s
        local needle = no_case and lower (delim) or delim
        local i = 1
        while true do
          local a, b = string.find (hay, needle, i, true)
          if not a then
            break
          end
          starts[#starts + 1] = a
          i = b + 1
        end
      end
      local k = instance > 0 and instance or #starts + instance + 1
      local cut ---@type integer?
      if delim == '' then
        cut = instance > 0 and 1 or #s + 1
      elseif k >= 1 and k <= #starts then
        cut = starts[k]
      elseif match_end and instance > 0 and k == #starts + 1 then
        cut = #s + 1
      elseif match_end and instance < 0 and k == 0 then
        -- The start of the text counts as a delimiter with no width.
        if after then
          return s
        end
        return ''
      end
      if not cut then
        if n >= 6 then
          return v[6]
        end
        return raise ('#N/A')
      end
      if after then
        local width = cut <= #s and #delim or 0
        return string.sub (s, cut + width)
      end
      return string.sub (s, 1, cut - 1)
    end,
  }
end

define (
  'TEXTBEFORE',
  'Text',
  'TEXTBEFORE(text, delimiter, [instance], [match_mode], [match_end], [if_not_found])',
  'Gives the text before a delimiter.',
  text_around (false)
)
define (
  'TEXTAFTER',
  'Text',
  'TEXTAFTER(text, delimiter, [instance], [match_mode], [match_end], [if_not_found])',
  'Gives the text after a delimiter.',
  text_around (true)
)

---------------------------------------------------------------------------------------------
-- Lookup
---------------------------------------------------------------------------------------------

---Finds a value in sorted data without an exact match. `dir` 1 finds the last value up to
---`want` in ascending data, and -1 the last value from `want` up in descending data. Only
---values of the same type as `want` count, and the search stops at the first value on the far
---side. Returns the position or nil.
---@param get fun(k: integer): Sheet.Value
---@param count integer
---@param want Sheet.Value
---@param dir integer
---@return integer?
local function find_sorted (get, count, want, dir)
  if want == nil then
    return nil
  end
  local kind = type (want)
  local best = nil ---@type integer?
  for k = 1, count do
    local v = get (k)
    if type (v) == kind then
      local c = compare (v, want)
      if c == 0 or (dir > 0 and c < 0) or (dir < 0 and c > 0) then
        best = k
      else
        break
      end
    end
  end
  return best
end

---Finds a value by exact match, first to last.
---@param get fun(k: integer): Sheet.Value
---@param count integer
---@param want Sheet.Value
---@param wild boolean
---@return integer?
local function find_exact (get, count, want, wild)
  local same = equals (want, wild)
  for k = 1, count do
    if same (get (k)) then
      return k
    end
  end
  return nil
end

---Finds a value for XLOOKUP and XMATCH. Mode 0 is an exact match, 2 an exact match with
---wildcards, -1 the exact value or the next smaller one, and 1 the exact value or the next
---larger one. The data need no order.
---@param get fun(k: integer): Sheet.Value
---@param count integer
---@param want Sheet.Value
---@param mode integer
---@param reverse boolean True to search from the last value back.
---@return integer?
local function find_near (get, count, want, mode, reverse)
  local same = equals (want, mode == 2)
  local from, to, step = 1, count, 1
  if reverse then
    from, to, step = count, 1, -1
  end
  local best, best_v = nil, nil ---@type integer?, Sheet.Value
  for k = from, to, step do
    local v = get (k)
    if same (v) then
      return k
    end
    if (mode == 1 or mode == -1) and v ~= nil and type (v) == type (want) then
      local c = compare (v, want)
      if c * mode > 0 and (best == nil or compare (v, best_v) * mode < 0) then
        best, best_v = k, v
      end
    end
  end
  return best
end

---A getter for the values along a one-row or one-column block.
---@param g Sheet.Grid
---@param ctx Sheet.Context
---@return fun(k: integer): Sheet.Value
---@return integer count
local function along (g, ctx)
  local h, w = dims (g)
  if h == 1 then
    return function (k)
      return grid_at (g, 1, k, ctx)
    end, w
  end
  return function (k)
    return grid_at (g, k, 1, ctx)
  end, h
end

---Part of a block: rows `r1` to `r2` and columns `c1` to `c2`, counting from 1.
---@param g Sheet.Grid
---@param r1 integer
---@param c1 integer
---@param r2 integer
---@param c2 integer
---@param ctx Sheet.Context
---@return Sheet.Grid
local function sub_grid (g, r1, c1, r2, c2, ctx)
  if g.is_range then
    local r = g --[[@as Sheet.RangeValue]]
    return {
      is_range = true,
      r1 = r.r1 + r1 - 1,
      c1 = r.c1 + c1 - 1,
      r2 = r.r1 + r2 - 1,
      c2 = r.c1 + c2 - 1,
      sheet = r.sheet,
    }
  end
  local out = {} ---@type Sheet.Values
  local k = 0
  for i = r1, r2 do
    for j = c1, c2 do
      k = k + 1
      out[k] = grid_at (g, i, j, ctx)
    end
  end
  return new_array (r2 - r1 + 1, c2 - c1 + 1, out)
end

---VLOOKUP and HLOOKUP.
---@param across boolean True for HLOOKUP, which looks along the first row.
---@return Sheet.Function
local function table_lookup (across)
  return {
    min = 3,
    max = 4,
    run = function (args, ctx)
      local want = value_of (args[1], ctx)
      local g = need_grid (args[2], ctx)
      local index = int_of (args[3], ctx)
      local approx = true
      if args[4] then
        approx = bool_of (args[4], ctx)
      end
      local h, w = dims (g)
      local count, size = h, w
      if across then
        count, size = w, h
      end
      if index < 1 then
        return raise ('#VALUE!')
      end
      if index > size then
        return raise ('#REF!')
      end
      ---@param k integer
      ---@return Sheet.Value
      local function get (k)
        if across then
          return grid_at (g, 1, k, ctx)
        end
        return grid_at (g, k, 1, ctx)
      end
      local k ---@type integer?
      if approx then
        k = find_sorted (get, count, want, 1)
      else
        k = find_exact (get, count, want, true)
      end
      if not k then
        return raise ('#N/A')
      end
      if across then
        return grid_at (g, index, k, ctx)
      end
      return grid_at (g, k, index, ctx)
    end,
  }
end

define (
  'VLOOKUP',
  'Lookup',
  'VLOOKUP(value, table, column, [approximate])',
  'Finds a value in the first column of a table and gives the value in another column of its row.',
  table_lookup (false)
)
define (
  'HLOOKUP',
  'Lookup',
  'HLOOKUP(value, table, row, [approximate])',
  'Finds a value in the first row of a table and gives the value in another row of its column.',
  table_lookup (true)
)

---Reads the match mode and search mode of XLOOKUP and XMATCH.
---@param args Sheet.Node[]
---@param at integer Where the match mode sits.
---@param ctx Sheet.Context
---@return integer mode
---@return boolean reverse
local function x_modes (args, at, ctx)
  local mode, dir = 0, 1
  if given (args[at]) then
    mode = int_of (args[at], ctx)
  end
  if given (args[at + 1]) then
    dir = int_of (args[at + 1], ctx)
  end
  if
    mode < -1
    or mode > 2
    or (dir ~= 1 and dir ~= -1 and dir ~= 2 and dir ~= -2)
  then
    error (ERRORS['#VALUE!'], 0)
  end
  return mode, dir < 0
end

define (
  'XLOOKUP',
  'Lookup',
  'XLOOKUP(value, lookup_range, return_range, [if_not_found], [match_mode], [search_mode])',
  'Finds a value in one range and gives what sits at the same place in another.',
  {
    min = 3,
    max = 6,
    run = function (args, ctx)
      local want = value_of (args[1], ctx)
      local look = need_grid (args[2], ctx)
      local back = need_grid (args[3], ctx)
      local lh, lw = dims (look)
      local bh, bw = dims (back)
      if lh ~= 1 and lw ~= 1 then
        return raise ('#VALUE!')
      end
      local across = lh == 1 and lw > 1
      if (across and bw ~= lw) or (not across and bh ~= lh) then
        return raise ('#VALUE!')
      end
      local mode, reverse = x_modes (args, 5, ctx)
      local get, count = along (look, ctx)
      local k = find_near (get, count, want, mode, reverse)
      if not k then
        if given (args[4]) then
          return eval (args[4], ctx)
        end
        return raise ('#N/A')
      end
      if across then
        return sub_grid (back, 1, k, bh, k, ctx)
      end
      return sub_grid (back, k, 1, k, bw, ctx)
    end,
  }
)

define (
  'LOOKUP',
  'Lookup',
  'LOOKUP(value, lookup_range, [result_range])',
  'Finds the largest value up to a value in sorted data and gives what sits at the same place.',
  {
    min = 2,
    max = 3,
    run = function (args, ctx)
      local want = value_of (args[1], ctx)
      local g = need_grid (args[2], ctx)
      local h, w = dims (g)
      local get, count = along (g, ctx)
      local result ---@type fun(k: integer): Sheet.Value
      if given (args[3]) then
        result = along (need_grid (args[3] --[[@as Sheet.Node]], ctx), ctx)
      elseif w > h then
        -- A wide block is searched along its first row, and gives from its last row.
        count = w
        get = function (k)
          return grid_at (g, 1, k, ctx)
        end
        result = function (k)
          return grid_at (g, h, k, ctx)
        end
      else
        count = h
        get = function (k)
          return grid_at (g, k, 1, ctx)
        end
        result = function (k)
          return grid_at (g, k, w, ctx)
        end
      end
      local k = find_sorted (get, count, want, 1)
      if not k then
        return raise ('#N/A')
      end
      return result (k)
    end,
  }
)

define (
  'MATCH',
  'Lookup',
  'MATCH(value, range, [match_type])',
  'Gives the position of a value in a row or column: 0 for an exact match, 1 or -1 for sorted data.',
  {
    min = 2,
    max = 3,
    run = function (args, ctx)
      local want = value_of (args[1], ctx)
      local g = need_grid (args[2], ctx)
      local h, w = dims (g)
      if h ~= 1 and w ~= 1 then
        return raise ('#N/A')
      end
      local kind = 1
      if args[3] then
        kind = int_of (args[3], ctx)
      end
      local get, count = along (g, ctx)
      local k ---@type integer?
      if kind == 0 then
        k = find_exact (get, count, want, true)
      else
        k = find_sorted (get, count, want, kind > 0 and 1 or -1)
      end
      if not k then
        return raise ('#N/A')
      end
      return k
    end,
  }
)

define (
  'XMATCH',
  'Lookup',
  'XMATCH(value, range, [match_mode], [search_mode])',
  'Gives the position of a value in a row or column, in any order.',
  {
    min = 2,
    max = 4,
    run = function (args, ctx)
      local want = value_of (args[1], ctx)
      local g = need_grid (args[2], ctx)
      local h, w = dims (g)
      if h ~= 1 and w ~= 1 then
        return raise ('#VALUE!')
      end
      local mode, reverse = x_modes (args, 3, ctx)
      local get, count = along (g, ctx)
      local k = find_near (get, count, want, mode, reverse)
      if not k then
        return raise ('#N/A')
      end
      return k
    end,
  }
)

define (
  'INDEX',
  'Lookup',
  'INDEX(range, row, [column])',
  'Gives the cell at a row and column of a range, or a whole row or column for 0.',
  {
    min = 2,
    max = 3,
    run = function (args, ctx)
      local g = need_grid (args[1], ctx)
      local h, w = dims (g)
      local row = int_of (args[2], ctx)
      local col ---@type integer
      if args[3] then
        col = int_of (args[3], ctx)
      elseif w == 1 then
        col = 1
      elseif h == 1 then
        row, col = 1, row
      else
        col = 0
      end
      if row < 0 or row > h or col < 0 or col > w then
        return raise ('#REF!')
      end
      local r1, r2, c1, c2 = row, row, col, col
      if row == 0 then
        r1, r2 = 1, h
      end
      if col == 0 then
        c1, c2 = 1, w
      end
      return sub_grid (g, r1, c1, r2, c2, ctx)
    end,
  }
)

---ROW and COLUMN.
---@param want_row boolean
---@return Sheet.Function
local function position (want_row)
  return {
    min = 0,
    max = 1,
    ---@param args Sheet.Node[]
    ---@param ctx Sheet.Context
    ---@return Sheet.Result
    run = function (args, ctx)
      if not given (args[1]) then
        local here = ctx.col ---@type integer?
        if want_row then
          here = ctx.row
        end
        return here or raise ('#VALUE!')
      end
      local rng = need_reference (args[1], ctx)
      return want_row and rng.r1 or rng.c1
    end,
  }
end

define (
  'ROW',
  'Lookup',
  'ROW([reference])',
  'Gives the row number of a reference, or of the cell the formula is in.',
  position (true)
)
define (
  'COLUMN',
  'Lookup',
  'COLUMN([reference])',
  'Gives the column number of a reference, or of the cell the formula is in.',
  position (false)
)

define (
  'ROWS',
  'Lookup',
  'ROWS(range)',
  'Counts the rows of a range or an array.',
  {
    min = 1,
    max = 1,
    run = function (args, ctx)
      local h = dims (grid_or_value (args[1], ctx))
      return h
    end,
  }
)

define (
  'COLUMNS',
  'Lookup',
  'COLUMNS(range)',
  'Counts the columns of a range or an array.',
  {
    min = 1,
    max = 1,
    run = function (args, ctx)
      local _, w = dims (grid_or_value (args[1], ctx))
      return w
    end,
  }
)

---Reads a reference written as text, such as `B3`, `Data!A1:C9` or, when `a1` is false,
---`R3C2`. Returns nil when the text is not a reference.
---@param text string
---@param a1 boolean
---@param ctx Sheet.Context
---@return Sheet.RangeValue?
local function read_reference (text, a1, ctx)
  local s = string.match (text, '^%s*(.-)%s*$')
  if a1 then
    local tokens = M.tokenize (s)
    if not tokens or #tokens ~= 1 then
      return nil
    end
    local t = tokens[1]
    if t.kind == 'ref' then
      return cell_range (t.a --[[@as Sheet.Ref]], ctx)
    end
    if t.kind == 'range' then
      return resolve (t.a --[[@as Sheet.Ref]], t.b --[[@as Sheet.Ref]], ctx)
    end
    return nil
  end
  local sheet, after = sheet_prefix (s, 1)
  local body = string.upper (string.sub (s, after))
  local r1, c1, r2, c2 = string.match (body, '^R(%d+)C(%d+):R(%d+)C(%d+)$')
  if not r1 then
    r1, c1 = string.match (body, '^R(%d+)C(%d+)$')
    r2, c2 = r1, c1
  end
  if not r1 then
    return nil
  end
  ---@type Sheet.Ref, Sheet.Ref
  local a, b =
    {
      row = math.tointeger (tonumber (r1)),
      col = math.tointeger (tonumber (c1)),
      row_abs = true,
      col_abs = true,
      sheet = sheet,
    }, {
      row = math.tointeger (tonumber (r2)),
      col = math.tointeger (tonumber (c2)),
      row_abs = true,
      col_abs = true,
      sheet = sheet,
    }
  if
    (a.row or 0) < 1
    or (a.col or 0) < 1
    or (b.row or 0) < 1
    or (b.col or 0) < 1
  then
    return nil
  end
  return resolve (a, b, ctx)
end

define (
  'INDIRECT',
  'Lookup',
  'INDIRECT(reference_text, [a1_style])',
  'Gives the cells a reference written as text names, such as "B3" or "Data!A1:C9".',
  {
    min = 1,
    max = 2,
    run = function (args, ctx)
      local text = text_of (args[1], ctx)
      local a1 = true
      if args[2] then
        a1 = bool_of (args[2], ctx)
      end
      return read_reference (text, a1, ctx) or raise ('#REF!')
    end,
  }
)

define (
  'OFFSET',
  'Lookup',
  'OFFSET(reference, rows, columns, [height], [width])',
  'Gives the cells a number of rows and columns away from a reference, in a block of a given size.',
  {
    min = 3,
    max = 5,
    run = function (args, ctx)
      local base = need_reference (args[1], ctx)
      local dr, dc = int_of (args[2], ctx), int_of (args[3], ctx)
      local h, w = dims (base)
      if given (args[4]) then
        h = int_of (args[4], ctx)
      end
      if given (args[5]) then
        w = int_of (args[5], ctx)
      end
      local r1, c1 = base.r1 + dr, base.c1 + dc
      if h < 1 or w < 1 or r1 < 1 or c1 < 1 then
        return raise ('#REF!')
      end
      on_sheet (r1 + h - 1, c1 + w - 1)
      return {
        is_range = true,
        r1 = r1,
        c1 = c1,
        r2 = r1 + h - 1,
        c2 = c1 + w - 1,
        sheet = base.sheet,
      }
    end,
  }
)

define (
  'ADDRESS',
  'Lookup',
  'ADDRESS(row, column, [absolute], [a1_style], [sheet])',
  'Writes the address of a cell as text, such as $C$2.',
  {
    min = 2,
    max = 5,
    map = function (v, n)
      local row, col = trunc (to_number (v[1])), trunc (to_number (v[2]))
      local kind = opt_int (v, n, 3, 1)
      if row < 1 or col < 1 or kind < 1 or kind > 4 then
        return raise ('#VALUE!')
      end
      local row_abs = kind == 1 or kind == 2
      local col_abs = kind == 1 or kind == 3
      local out ---@type string
      if opt_bool (v, n, 4, true) then
        out = (col_abs and '$' or '')
          .. M.col_name (col)
          .. (row_abs and '$' or '')
          .. string.format ('%d', row)
      else
        out = (row_abs and 'R%d' or 'R[%d]'):format (row)
          .. (col_abs and 'C%d' or 'C[%d]'):format (col)
      end
      if n >= 5 and v[5] ~= nil then
        local sheet = to_text (v[5])
        if sheet ~= '' then
          out = M.quote_sheet (sheet) .. '!' .. out
        end
      end
      return out
    end,
  }
)

---------------------------------------------------------------------------------------------
-- Date
---------------------------------------------------------------------------------------------

define ('TODAY', 'Date', 'TODAY()', 'Gives the date today.', {
  min = 0,
  max = 0,
  map = function (_, _, ctx)
    return math.floor (now (ctx))
  end,
})

define ('NOW', 'Date', 'NOW()', 'Gives the date and time now.', {
  min = 0,
  max = 0,
  map = function (_, _, ctx)
    return now (ctx)
  end,
})

define (
  'DATE',
  'Date',
  'DATE(year, month, day)',
  'Makes a date from a year, a month and a day. A month or a day past its end runs on.',
  {
    min = 3,
    max = 3,
    map = function (v)
      local y = trunc (to_number (v[1]))
      local m, d = trunc (to_number (v[2])), trunc (to_number (v[3]))
      if y < 0 or y > 9999 then
        return raise ('#NUM!')
      end
      -- Years before 1900 count from 1900, as spreadsheets read them.
      if y < 1900 then
        y = y + 1900
      end
      local serial = make_date (y, m, d)
      if serial < 0 or serial > LAST_DAY then
        return raise ('#NUM!')
      end
      return serial
    end,
  }
)

define (
  'TIME',
  'Date',
  'TIME(hour, minute, second)',
  'Makes a time of day from hours, minutes and seconds.',
  {
    min = 3,
    max = 3,
    map = function (v)
      local total = trunc (to_number (v[1])) * 3600
        + trunc (to_number (v[2])) * 60
        + trunc (to_number (v[3]))
      if total < 0 then
        return raise ('#NUM!')
      end
      return (total % 86400) / 86400
    end,
  }
)

---YEAR, MONTH, DAY, HOUR, MINUTE and SECOND.
---@param part integer Which of the six parts of `date_parts`.
---@return Sheet.Function
local function date_part (part)
  return {
    min = 1,
    max = 1,
    map = function (v, _, ctx)
      local parts = { M.date_parts (date_arg (v[1], ctx)) }
      return parts[part]
    end,
  }
end

define ('YEAR', 'Date', 'YEAR(date)', 'Gives the year of a date.', date_part (1))
define (
  'MONTH',
  'Date',
  'MONTH(date)',
  'Gives the month of a date, from 1 to 12.',
  date_part (2)
)
define (
  'DAY',
  'Date',
  'DAY(date)',
  'Gives the day of the month of a date.',
  date_part (3)
)
define (
  'HOUR',
  'Date',
  'HOUR(time)',
  'Gives the hour of a time, from 0 to 23.',
  date_part (4)
)
define (
  'MINUTE',
  'Date',
  'MINUTE(time)',
  'Gives the minute of a time.',
  date_part (5)
)
define (
  'SECOND',
  'Date',
  'SECOND(time)',
  'Gives the second of a time.',
  date_part (6)
)

---The weekday a week starts on for WEEKDAY and WEEKNUM types 1, 2 and 11 to 17, from 0 for
---Sunday. Other types give nil.
---@param kind integer
---@return integer?
local function week_start (kind)
  if kind == 1 then
    return 0
  end
  if kind == 2 then
    return 1
  end
  if kind >= 11 and kind <= 17 then
    return (kind - 10) % 7
  end
  return nil
end

define (
  'WEEKDAY',
  'Date',
  'WEEKDAY(date, [type])',
  'Gives the day of the week: type 1 counts from Sunday as 1, type 2 from Monday as 1, type 3 from Monday as 0.',
  {
    min = 1,
    max = 2,
    map = function (v, n, ctx)
      local day = weekday0 (date_arg (v[1], ctx))
      local kind = opt_int (v, n, 2, 1)
      if kind == 3 then
        return (day + 6) % 7
      end
      local start = week_start (kind)
      if not start then
        return raise ('#NUM!')
      end
      return (day - start) % 7 + 1
    end,
  }
)

---The ISO week number of a date: weeks start on Monday, and week 1 holds the first Thursday.
---@param serial number
---@return integer
local function iso_week (serial)
  local day = math.floor (serial)
  local thursday = day - (weekday0 (day) + 6) % 7 + 3
  local y = ymd (thursday)
  return math.floor ((thursday - make_date (y, 1, 1)) / 7) + 1
end

define (
  'WEEKNUM',
  'Date',
  'WEEKNUM(date, [type])',
  'Gives the week of the year, with weeks from Sunday for type 1, from Monday for type 2, and ISO weeks for type 21.',
  {
    min = 1,
    max = 2,
    map = function (v, n, ctx)
      local day = math.floor (date_arg (v[1], ctx))
      local kind = opt_int (v, n, 2, 1)
      if kind == 21 then
        return iso_week (day)
      end
      local start = week_start (kind)
      if not start then
        return raise ('#NUM!')
      end
      local jan1 = make_date ((ymd (day)), 1, 1)
      local lead = (weekday0 (jan1) - start) % 7
      return math.floor ((day - jan1 + lead) / 7) + 1
    end,
  }
)

define (
  'ISOWEEKNUM',
  'Date',
  'ISOWEEKNUM(date)',
  'Gives the ISO week of the year, with weeks from Monday.',
  {
    min = 1,
    max = 1,
    map = function (v, _, ctx)
      return iso_week (date_arg (v[1], ctx))
    end,
  }
)

---EDATE and EOMONTH.
---@param month_end boolean
---@return Sheet.Function
local function add_months (month_end)
  return {
    min = 2,
    max = 2,
    map = function (v, _, ctx)
      local y, m, d = ymd (date_arg (v[1], ctx))
      local months = y * 12 + (m - 1) + trunc (to_number (v[2]))
      local yy = math.floor (months / 12)
      local mm = months - yy * 12 + 1
      local last = days_in_month (yy, mm)
      local serial =
        make_date (yy, mm, month_end and last or math.min (d, last))
      -- Serial 1 is 1900-01-01, the first day the calendar has.
      if serial < 1 or serial > LAST_DAY then
        return raise ('#NUM!')
      end
      return serial
    end,
  }
end

define (
  'EDATE',
  'Date',
  'EDATE(start_date, months)',
  'Gives the date a number of months before or after a date.',
  add_months (false)
)
define (
  'EOMONTH',
  'Date',
  'EOMONTH(start_date, months)',
  'Gives the last day of the month a number of months before or after a date.',
  add_months (true)
)

define (
  'DAYS',
  'Date',
  'DAYS(end_date, start_date)',
  'Counts the days between two dates.',
  {
    min = 2,
    max = 2,
    map = function (v, _, ctx)
      return math.floor (date_arg (v[1], ctx))
        - math.floor (date_arg (v[2], ctx))
    end,
  }
)

define (
  'DATEDIF',
  'Date',
  'DATEDIF(start_date, end_date, unit)',
  'Counts the whole years "Y", months "M" or days "D" between two dates, or the rest after years "YM", "YD" or months "MD".',
  {
    min = 3,
    max = 3,
    map = function (v, _, ctx)
      local a = math.floor (date_arg (v[1], ctx))
      local b = math.floor (date_arg (v[2], ctx))
      local unit = string.upper (to_text (v[3]))
      if a > b then
        return raise ('#NUM!')
      end
      local y1, m1, d1 = ymd (a)
      local y2, m2, d2 = ymd (b)
      local months = (y2 - y1) * 12 + m2 - m1
      if d2 < d1 then
        months = months - 1
      end
      if unit == 'D' then
        return b - a
      elseif unit == 'M' then
        return months
      elseif unit == 'Y' then
        return math.floor (months / 12)
      elseif unit == 'YM' then
        return months % 12
      elseif unit == 'MD' then
        if d2 >= d1 then
          return d2 - d1
        end
        -- The start day in the month before the end, run on as DATE does.
        return b - make_date (y2, m2 - 1, d1)
      elseif unit == 'YD' then
        local start = make_date (y2, m1, d1)
        if start > b then
          start = make_date (y2 - 1, m1, d1)
        end
        return b - start
      end
      return raise ('#NUM!')
    end,
  }
)

---The holidays for NETWORKDAYS and WORKDAY, as a set of serial days.
---@param node Sheet.Node?
---@param ctx Sheet.Context
---@return table<integer, boolean>
local function holidays (node, ctx)
  local out = {} ---@type table<integer, boolean>
  if given (node) then
    each (node --[[@as Sheet.Node]], ctx, function (v)
      if v ~= nil then
        out[math.floor (date_arg (v, ctx))] = true
      end
    end)
  end
  return out
end

---@param day integer
---@return boolean
local function is_weekend (day)
  local w = weekday0 (day)
  return w == 0 or w == 6
end

define (
  'NETWORKDAYS',
  'Date',
  'NETWORKDAYS(start_date, end_date, [holidays])',
  'Counts the weekdays from one date to another, both included, less any holidays.',
  {
    min = 2,
    max = 3,
    run = function (args, ctx)
      local x = math.floor (date_arg (value_of (args[1], ctx), ctx))
      local y = math.floor (date_arg (value_of (args[2], ctx), ctx))
      local sign = x > y and -1 or 1
      local a, b = math.min (x, y), math.max (x, y)
      local days = b - a + 1
      local count = math.floor (days / 7) * 5
      for k = 0, days % 7 - 1 do
        if not is_weekend (a + k) then
          count = count + 1
        end
      end
      for day in pairs (holidays (args[3], ctx)) do
        if day >= a and day <= b and not is_weekend (day) then
          count = count - 1
        end
      end
      return sign * count
    end,
  }
)

define (
  'WORKDAY',
  'Date',
  'WORKDAY(start_date, days, [holidays])',
  'Gives the date a number of weekdays before or after a date, skipping holidays.',
  {
    min = 2,
    max = 3,
    run = function (args, ctx)
      local day = math.floor (date_arg (value_of (args[1], ctx), ctx))
      local left = int_of (args[2], ctx)
      if math.abs (left) > LAST_DAY then
        return raise ('#NUM!')
      end
      local off = holidays (args[3], ctx)
      local step = left < 0 and -1 or 1
      left = math.abs (left)
      while left > 0 do
        day = day + step
        if day < 0 or day > LAST_DAY then
          return raise ('#NUM!')
        end
        if not is_weekend (day) and not off[day] then
          left = left - 1
        end
      end
      return day
    end,
  }
)

define (
  'DATEVALUE',
  'Date',
  'DATEVALUE(date_text)',
  'Turns text that shows a date into a date.',
  {
    min = 1,
    max = 1,
    map = function (v, _, ctx)
      local s = v[1]
      if type (s) ~= 'string' then
        return raise ('#VALUE!')
      end
      local n = parse_datetime (s, today_clock (ctx))
      if not n or n < 1 then
        return raise ('#VALUE!')
      end
      return math.floor (n)
    end,
  }
)

define (
  'TIMEVALUE',
  'Date',
  'TIMEVALUE(time_text)',
  'Turns text that shows a time into a fraction of a day.',
  {
    min = 1,
    max = 1,
    map = function (v, _, ctx)
      local s = v[1]
      if type (s) ~= 'string' then
        return raise ('#VALUE!')
      end
      local n = parse_datetime (s, today_clock (ctx))
      if not n then
        return raise ('#VALUE!')
      end
      return n - math.floor (n)
    end,
  }
)

---The share of a year between two dates, with the 30/360 US day count or the actual days.
---@param a integer
---@param b integer
---@param basis integer
---@return number
local function year_fraction (a, b, basis)
  local y1, m1, d1 = ymd (a)
  local y2, m2, d2 = ymd (b)
  if basis == 0 then
    local last1 = d1 == days_in_month (y1, m1)
    local last2 = d2 == days_in_month (y2, m2)
    -- The US rules: the 31st counts as the 30th, and so does the last day of February.
    if (d1 == 31 and d2 == 31) or (m1 == 2 and m2 == 2 and last1 and last2) then
      d1, d2 = 30, 30
    elseif d1 == 31 or (m1 == 2 and last1) then
      d1 = 30
    elseif d1 == 30 and d2 == 31 then
      d2 = 30
    end
    return ((y2 - y1) * 360 + (m2 - m1) * 30 + (d2 - d1)) / 360
  elseif basis == 1 then
    -- Actual days over the actual length of the year, as Excel works it out.
    if y1 == y2 or (y2 == y1 + 1 and (m1 > m2 or (m1 == m2 and d1 >= d2))) then
      local year_len = 365
      local feb29 = false
      if y1 == y2 then
        feb29 = is_leap (y1)
      else
        feb29 = (is_leap (y1) and a < make_date (y1, 3, 1))
          or (is_leap (y2) and b >= make_date (y2, 3, 1))
          or (m2 == 2 and d2 == 29)
      end
      if feb29 then
        year_len = 366
      end
      return (b - a) / year_len
    end
    local years = y2 - y1 + 1
    local days = make_date (y2 + 1, 1, 1) - make_date (y1, 1, 1)
    return (b - a) / (days / years)
  elseif basis == 2 then
    return (b - a) / 360
  elseif basis == 3 then
    return (b - a) / 365
  end
  if d1 == 31 then
    d1 = 30
  end
  if d2 == 31 then
    d2 = 30
  end
  return ((y2 - y1) * 360 + (m2 - m1) * 30 + (d2 - d1)) / 360
end

define (
  'YEARFRAC',
  'Date',
  'YEARFRAC(start_date, end_date, [basis])',
  'Gives the share of a year between two dates, counting days as 30/360 for basis 0 or as they are for basis 1.',
  {
    min = 2,
    max = 3,
    map = function (v, n, ctx)
      local a = math.floor (date_arg (v[1], ctx))
      local b = math.floor (date_arg (v[2], ctx))
      local basis = opt_int (v, n, 3, 0)
      if basis < 0 or basis > 4 then
        return raise ('#NUM!')
      end
      return year_fraction (math.min (a, b), math.max (a, b), basis)
    end,
  }
)

---------------------------------------------------------------------------------------------
-- Info
---------------------------------------------------------------------------------------------

define (
  'ISBLANK',
  'Info',
  'ISBLANK(value)',
  'Gives TRUE for an empty cell.',
  test1 (function (v)
    return v == nil
  end)
)
define (
  'ISNUMBER',
  'Info',
  'ISNUMBER(value)',
  'Gives TRUE for a number.',
  test1 (function (v)
    return type (v) == 'number'
  end)
)
define (
  'ISTEXT',
  'Info',
  'ISTEXT(value)',
  'Gives TRUE for text.',
  test1 (function (v)
    return type (v) == 'string'
  end)
)
define (
  'ISLOGICAL',
  'Info',
  'ISLOGICAL(value)',
  'Gives TRUE for TRUE or FALSE.',
  test1 (function (v)
    return type (v) == 'boolean'
  end)
)
define (
  'ISERROR',
  'Info',
  'ISERROR(value)',
  'Gives TRUE for any error.',
  test1 (is_error)
)
define (
  'ISERR',
  'Info',
  'ISERR(value)',
  'Gives TRUE for any error except #N/A.',
  test1 (function (v)
    return is_error (v) and v ~= ERRORS['#N/A']
  end)
)
define (
  'ISNA',
  'Info',
  'ISNA(value)',
  'Gives TRUE for #N/A.',
  test1 (function (v)
    return v == ERRORS['#N/A']
  end)
)

---ISEVEN and ISODD.
---@param odd boolean
---@return Sheet.Function
local function parity (odd)
  return {
    min = 1,
    max = 1,
    map = function (v)
      return (trunc (to_number (v[1])) % 2 == 1) == odd
    end,
  }
end

define (
  'ISEVEN',
  'Info',
  'ISEVEN(number)',
  'Gives TRUE for an even number.',
  parity (false)
)
define (
  'ISODD',
  'Info',
  'ISODD(number)',
  'Gives TRUE for an odd number.',
  parity (true)
)

define (
  'ISREF',
  'Info',
  'ISREF(value)',
  'Gives TRUE for a reference to cells.',
  {
    min = 1,
    max = 1,
    run = function (args, ctx)
      local node = args[1]
      if node.kind == 'ref' or node.kind == 'range' then
        return true
      end
      if node.kind ~= 'call' then
        return false
      end
      local ok, v = pcall (eval, node, ctx)
      return ok and type (v) == 'table' and (v --[[@as table]]).is_range == true
    end,
  }
)

define (
  'NA',
  'Info',
  'NA()',
  'Gives the error #N/A, for a value that is missing.',
  {
    min = 0,
    max = 0,
    map = function ()
      return ERRORS['#N/A']
    end,
  }
)

define (
  'TYPE',
  'Info',
  'TYPE(value)',
  'Gives the type of a value: 1 number, 2 text, 4 TRUE or FALSE, 16 error, 64 array.',
  {
    min = 1,
    max = 1,
    run = function (args, ctx)
      local ok, v = pcall (eval, args[1], ctx)
      if not ok then
        if is_error (v) then
          return 16
        end
        return raise_value (v)
      end
      if is_grid (v) then
        local h, w = dims (v)
        if h * w > 1 then
          return 64
        end
        v = grid_at (v --[[@as Sheet.Grid]], 1, 1, ctx)
      end
      local t = type (v)
      if t == 'string' then
        return 2
      elseif t == 'boolean' then
        return 4
      elseif t == 'table' then
        return 16
      end
      return 1
    end,
  }
)

-- #CYCLE! and #ERROR! are this app's own, so they take numbers after the standard seven.
local ERROR_NUMBER = {
  ['#NULL!'] = 1,
  ['#DIV/0!'] = 2,
  ['#VALUE!'] = 3,
  ['#REF!'] = 4,
  ['#NAME?'] = 5,
  ['#NUM!'] = 6,
  ['#N/A'] = 7,
  ['#ERROR!'] = 8,
  ['#CYCLE!'] = 9,
  -- Excel gives #SPILL! the 9 this app gives #CYCLE!, so it takes the next free number.
  ['#SPILL!'] = 10,
  ['#CALC!'] = 14,
}

define (
  'ERROR.TYPE',
  'Info',
  'ERROR.TYPE(value)',
  'Gives the number of an error: 1 #NULL!, 2 #DIV/0!, 3 #VALUE!, 4 #REF!, 5 #NAME?, 6 #NUM!, 7 #N/A.',
  {
    min = 1,
    max = 1,
    catch = true,
    map = function (v)
      local x = v[1]
      if not is_error (x) then
        return raise ('#N/A')
      end
      return ERROR_NUMBER[
        (x --[[@as Sheet.Error]]).code
      ]
    end,
  }
)

---------------------------------------------------------------------------------------------
-- Financial
---------------------------------------------------------------------------------------------

---Payments at the start of each period when the type argument is not 0.
---@param v Sheet.Values
---@param n integer
---@param i integer
---@return integer
local function pay_type (v, n, i)
  return opt (v, n, i, 0) ~= 0 and 1 or 0
end

---@param rate number
---@param nper number
---@param pv number
---@param fv number
---@param kind integer
---@return number
local function pmt (rate, nper, pv, fv, kind)
  if nper == 0 then
    return raise ('#NUM!')
  end
  if rate == 0 then
    return -(pv + fv) / nper
  end
  local f = (1 + rate) ^ nper
  return -(rate * (fv + pv * f)) / ((1 + rate * kind) * (f - 1))
end

---@param rate number
---@param nper number
---@param payment number
---@param pv number
---@param kind integer
---@return number
local function fv (rate, nper, payment, pv, kind)
  if rate == 0 then
    return -(pv + payment * nper)
  end
  local f = (1 + rate) ^ nper
  return -(pv * f + payment * (1 + rate * kind) * (f - 1) / rate)
end

---The interest part of the payment in period `per`.
---@param rate number
---@param per number
---@param nper number
---@param pv number
---@param future number
---@param kind integer
---@return number
local function ipmt (rate, per, nper, pv, future, kind)
  if per < 1 or per > nper then
    return raise ('#NUM!')
  end
  local payment = pmt (rate, nper, pv, future, kind)
  local interest ---@type number
  if per == 1 then
    interest = kind == 1 and 0 or -pv
  elseif kind == 1 then
    interest = fv (rate, per - 2, payment, pv, 1) - payment
  else
    interest = fv (rate, per - 1, payment, pv, 0)
  end
  return interest * rate
end

define (
  'PMT',
  'Financial',
  'PMT(rate, periods, present_value, [future_value], [type])',
  'Gives the payment each period for a loan or an investment at a fixed rate.',
  {
    min = 3,
    max = 5,
    map = function (v, n)
      return pmt (
        to_number (v[1]),
        to_number (v[2]),
        to_number (v[3]),
        opt (v, n, 4, 0),
        pay_type (v, n, 5)
      )
    end,
  }
)

define (
  'IPMT',
  'Financial',
  'IPMT(rate, period, periods, present_value, [future_value], [type])',
  'Gives the interest part of the payment in one period.',
  {
    min = 4,
    max = 6,
    map = function (v, n)
      return ipmt (
        to_number (v[1]),
        to_number (v[2]),
        to_number (v[3]),
        to_number (v[4]),
        opt (v, n, 5, 0),
        pay_type (v, n, 6)
      )
    end,
  }
)

define (
  'PPMT',
  'Financial',
  'PPMT(rate, period, periods, present_value, [future_value], [type])',
  'Gives the part of the payment in one period that pays back the loan.',
  {
    min = 4,
    max = 6,
    map = function (v, n)
      local rate, per, nper =
        to_number (v[1]), to_number (v[2]), to_number (v[3])
      local pv, future, kind =
        to_number (v[4]), opt (v, n, 5, 0), pay_type (v, n, 6)
      return pmt (rate, nper, pv, future, kind)
        - ipmt (rate, per, nper, pv, future, kind)
    end,
  }
)

define (
  'FV',
  'Financial',
  'FV(rate, periods, payment, [present_value], [type])',
  'Gives the future value of an investment with fixed payments and a fixed rate.',
  {
    min = 3,
    max = 5,
    map = function (v, n)
      return fv (
        to_number (v[1]),
        to_number (v[2]),
        to_number (v[3]),
        opt (v, n, 4, 0),
        pay_type (v, n, 5)
      )
    end,
  }
)

define (
  'PV',
  'Financial',
  'PV(rate, periods, payment, [future_value], [type])',
  'Gives what a series of fixed future payments is worth now.',
  {
    min = 3,
    max = 5,
    map = function (v, n)
      local rate, nper, payment =
        to_number (v[1]), to_number (v[2]), to_number (v[3])
      local future, kind = opt (v, n, 4, 0), pay_type (v, n, 5)
      if rate == 0 then
        return -(future + payment * nper)
      end
      local f = (1 + rate) ^ nper
      return -(future + payment * (1 + rate * kind) * (f - 1) / rate) / f
    end,
  }
)

define (
  'NPV',
  'Financial',
  'NPV(rate, value1, [value2], ...)',
  'Gives what future cash flows at the end of each period are worth now.',
  {
    min = 2,
    max = MANY,
    run = function (args, ctx)
      local rate = number_of (args[1], ctx)
      if rate == -1 then
        return raise ('#DIV/0!')
      end
      local total = 0.0
      for i, x in ipairs (numbers (args, ctx, 2)) do
        total = total + x / (1 + rate) ^ i
      end
      return total
    end,
  }
)

define (
  'NPER',
  'Financial',
  'NPER(rate, payment, present_value, [future_value], [type])',
  'Gives how many periods it takes to pay off a loan or reach a savings goal.',
  {
    min = 3,
    max = 5,
    map = function (v, n)
      local rate, payment, pv =
        to_number (v[1]), to_number (v[2]), to_number (v[3])
      local future, kind = opt (v, n, 4, 0), pay_type (v, n, 5)
      if rate == 0 then
        if payment == 0 then
          return raise ('#NUM!')
        end
        return -(pv + future) / payment
      end
      local top = payment * (1 + rate * kind) - future * rate
      local bottom = pv * rate + payment * (1 + rate * kind)
      if bottom == 0 or top / bottom <= 0 or rate <= -1 then
        return raise ('#NUM!')
      end
      return log (top / bottom) / log (1 + rate)
    end,
  }
)

---True for a number that is neither infinite nor NaN.
---@param y number
---@return boolean
local function is_finite (y)
  return y == y and y ~= math.huge and y ~= -math.huge
end

---Finds a zero of `f` above -1 by bisection, in the first bracket from a scan of rates that
---holds a change of sign, looking out from `guess`. Returns nil when there is none.
---@param f fun(x: number): number
---@param guess number
---@return number?
local function bisect (f, guess)
  local points = {} ---@type number[]
  local x = -0.999
  while x < 1000 do
    points[#points + 1] = x
    x = x < 1 and x + 0.01 or x * 1.1
  end
  -- Try the brackets nearest the guess first.
  local pairs_by_distance = {} ---@type integer[]
  for i = 1, #points - 1 do
    pairs_by_distance[i] = i
  end
  table.sort (pairs_by_distance, function (i, j)
    return math.abs (points[i] - guess) < math.abs (points[j] - guess)
  end)
  for _, i in ipairs (pairs_by_distance) do
    local lo, hi = points[i], points[i + 1]
    local flo, fhi = f (lo), f (hi)
    if is_finite (flo) and is_finite (fhi) and (flo < 0) ~= (fhi < 0) then
      for _ = 1, 200 do
        local mid = (lo + hi) / 2
        local fm = f (mid)
        if fm == 0 or hi - lo < 1e-15 * math.max (1, math.abs (mid)) then
          return mid
        end
        if (fm < 0) == (flo < 0) then
          lo, flo = mid, fm
        else
          hi = mid
        end
      end
      return (lo + hi) / 2
    end
  end
  return nil
end

---Finds where `f` is zero near `guess`, above -1, as RATE and IRR need. Newton's method runs
---first, with its step halved whenever it would land at or below -1 or make things worse.
---When it does not settle, a scan for a change of sign and bisection take over. Returns nil
---when there is no zero.
---@param f fun(x: number): number
---@param guess number
---@return number?
local function solve (f, guess)
  if guess <= -1 then
    return nil
  end
  local x = guess
  local y = f (x)
  for _ = 1, 100 do
    if not is_finite (y) then
      break
    end
    if y == 0 then
      return x
    end
    local h = 1e-7 * math.max (1, math.abs (x))
    local slope = (f (x + h) - y) / h ---@type number
    if slope == 0 or not is_finite (slope) then
      break
    end
    local step = y / slope
    local next_x, next_y = x - step, 0.0
    local tries = 0
    while true do
      if next_x > -1 then
        next_y = f (next_x)
        if is_finite (next_y) and math.abs (next_y) <= math.abs (y) * 2 then
          break
        end
      end
      tries = tries + 1
      if tries > 60 then
        break
      end
      step = step / 2
      next_x = x - step
    end
    if tries > 60 then
      break
    end
    -- A step cut short by the halving is no sign of having settled.
    if
      tries == 0
      and math.abs (next_x - x) < 1e-12 * math.max (1, math.abs (x))
    then
      return next_x
    end
    x, y = next_x, next_y
  end
  return bisect (f, guess)
end

define (
  'RATE',
  'Financial',
  'RATE(periods, payment, present_value, [future_value], [type], [guess])',
  'Gives the interest rate per period of a loan or an investment.',
  {
    min = 3,
    max = 6,
    map = function (v, n)
      local nper, payment, pv =
        to_number (v[1]), to_number (v[2]), to_number (v[3])
      local future, kind = opt (v, n, 4, 0), pay_type (v, n, 5)
      local rate = solve (function (r)
        if math.abs (r) < 1e-12 then
          return pv + payment * nper + future
        end
        local f = (1 + r) ^ nper
        return pv * f + payment * (1 + r * kind) * (f - 1) / r + future
      end, opt (v, n, 6, 0.1))
      if not rate then
        return raise ('#NUM!')
      end
      return rate
    end,
  }
)

define (
  'IRR',
  'Financial',
  'IRR(values, [guess])',
  'Gives the rate at which a series of cash flows is worth nothing now.',
  {
    min = 1,
    max = 2,
    run = function (args, ctx)
      local flows = numbers (args, ctx, 1, 1)
      local up, down = false, false
      for _, x in ipairs (flows) do
        up = up or x > 0
        down = down or x < 0
      end
      if not up or not down then
        return raise ('#NUM!')
      end
      local guess = given (args[2]) and number_of (args[2], ctx) or 0.1
      local rate = solve (function (r)
        local total = 0.0
        for i, x in ipairs (flows) do
          total = total + x / (1 + r) ^ (i - 1)
        end
        return total
      end, guess)
      if not rate then
        return raise ('#NUM!')
      end
      return rate
    end,
  }
)

---------------------------------------------------------------------------------------------
-- More functions
---------------------------------------------------------------------------------------------

---What the modules with more functions get from the formula language: its helpers, and
---`define` to add a function and its catalog entry. Each module returns a function that takes
---the kit, so the functions join the catalog before it is sorted.
---@class Sheet.FormulaKit
---@field define fun(name: string, category: Sheet.Category, syntax: string, summary: string, spec: Sheet.Function)
---@field ERRORS table<string, Sheet.Error>
---@field MANY integer
---@field EMPTY table What a name holds when LET gives it an empty value.
---@field raise fun(code: string): any
---@field raise_value fun(err: any): any
---@field is_error fun(v: any): boolean
---@field is_lambda fun(v: any): boolean
---@field is_grid fun(v: Sheet.Result): boolean
---@field dims fun(v: Sheet.Result): integer, integer
---@field grid_at fun(g: Sheet.Grid, i: integer, j: integer, ctx: Sheet.Context): Sheet.Value
---@field new_array fun(h: integer, w: integer, v: Sheet.Values): Sheet.Array
---@field eval fun(node: Sheet.Node, ctx: Sheet.Context): Sheet.Result
---@field grid_or_value fun(node: Sheet.Node, ctx: Sheet.Context): Sheet.Result
---@field need_grid fun(node: Sheet.Node, ctx: Sheet.Context): Sheet.Grid
---@field need_reference fun(node: Sheet.Node, ctx: Sheet.Context): Sheet.RangeValue
---@field each fun(node: Sheet.Node, ctx: Sheet.Context, fn: fun(v: Sheet.Value, in_ref: boolean))
---@field numbers fun(args: Sheet.Node[], ctx: Sheet.Context, first?: integer, last?: integer): number[]
---@field paired fun(ynode: Sheet.Node, xnode: Sheet.Node, ctx: Sheet.Context): number[], number[]
---@field apply fun(fn: Sheet.Lambda, values: table<integer, Sheet.Result>, n: integer, ctx: Sheet.Context): Sheet.Result
---@field within fun(ctx: Sheet.Context, scope: Sheet.Scope?, fn: fun(): Sheet.Result): Sheet.Result
---@field given fun(node: Sheet.Node?): boolean
---@field value_of fun(node: Sheet.Node, ctx: Sheet.Context): Sheet.Value
---@field number_of fun(node: Sheet.Node, ctx: Sheet.Context): number
---@field int_of fun(node: Sheet.Node, ctx: Sheet.Context): integer
---@field bool_of fun(node: Sheet.Node, ctx: Sheet.Context): boolean
---@field text_of fun(node: Sheet.Node, ctx: Sheet.Context): string
---@field to_number fun(v: Sheet.Value): number
---@field to_bool fun(v: Sheet.Value): boolean
---@field to_text fun(v: Sheet.Value): string
---@field opt fun(v: Sheet.Values, n: integer, i: integer, d: number): number
---@field opt_int fun(v: Sheet.Values, n: integer, i: integer, d: integer): integer
---@field opt_bool fun(v: Sheet.Values, n: integer, i: integer, d: boolean): boolean
---@field trunc fun(n: number): integer
---@field finite fun(n: number): number
---@field compare fun(a: Sheet.Value, b: Sheet.Value): integer
---@field lower fun(s: string): string
---@field upper fun(s: string): string
---@field total_of fun(list: number[]): number
---@field variance fun(list: number[], sample: boolean): number
---@field fit fun(ys: number[], xs: number[]): number, number
---@field solve fun(f: (fun(x: number): number), guess: number): number?
---@field date_arg fun(v: Sheet.Value, ctx?: Sheet.Context): number
---@field ymd fun(serial: number): integer, integer, integer
---@field make_date fun(y: integer, m: integer, d: integer): integer
---@field weekday0 fun(serial: number): integer
---@field holidays fun(node: Sheet.Node?, ctx: Sheet.Context): table<integer, boolean>
---@field days_in_month fun(y: integer, m: integer): integer
---@field round_to fun(x: number, digits: integer, mode: 'near'|'up'|'down'): number
---@field parse_number fun(text: string): number?
---@field col_name fun(n: integer): string
---@field address fun(row: integer, col: integer): string
---@field quote_sheet fun(name: string): string
---@field percentile fun(list: number[], k: number): number
---@field clean fun(n: number): number
---@field reference fun(node: Sheet.Node, ctx: Sheet.Context): Sheet.RangeValue?
---@field pmt fun(rate: number, nper: number, pv: number, fv: number, kind: integer): number
---@field fv fun(rate: number, nper: number, payment: number, pv: number, kind: integer): number
---@field ipmt fun(rate: number, per: number, nper: number, pv: number, future: number, kind: integer): number
---@field is_weekend fun(day: integer): boolean
---@field chars fun(s: string): string[]
---@field length fun(s: string): integer
---@field wildcard fun(text: string, anchored: boolean): string
---@field format_value fun(v: Sheet.Value, digits?: integer): string
---@field parse_address fun(text: string): integer?, integer?
---@field col_number fun(letters: string): integer?
---@field LAST_ROW integer
---@field LAST_COL integer

---@type Sheet.FormulaKit
local kit = {
  define = define,
  ERRORS = ERRORS,
  MANY = MANY,
  EMPTY = EMPTY,
  raise = raise,
  raise_value = raise_value,
  is_error = is_error,
  is_lambda = is_lambda,
  is_grid = is_grid,
  dims = dims,
  grid_at = grid_at,
  new_array = new_array,
  eval = eval,
  grid_or_value = grid_or_value,
  need_grid = need_grid,
  need_reference = need_reference,
  each = each,
  numbers = numbers,
  paired = paired,
  apply = apply,
  within = within,
  given = given,
  value_of = value_of,
  number_of = number_of,
  int_of = int_of,
  bool_of = bool_of,
  text_of = text_of,
  to_number = to_number,
  to_bool = to_bool,
  to_text = to_text,
  opt = opt,
  opt_int = opt_int,
  opt_bool = opt_bool,
  trunc = trunc,
  finite = finite,
  compare = compare,
  lower = lower,
  upper = upper,
  total_of = total_of,
  variance = variance,
  fit = fit,
  solve = solve,
  date_arg = date_arg,
  ymd = ymd,
  make_date = make_date,
  weekday0 = weekday0,
  holidays = holidays,
  days_in_month = days_in_month,
  round_to = round_to,
  parse_number = M.parse_number,
  col_name = M.col_name,
  address = M.address,
  quote_sheet = M.quote_sheet,
  percentile = percentile,
  clean = clean,
  reference = reference,
  pmt = pmt,
  fv = fv,
  ipmt = ipmt,
  is_weekend = is_weekend,
  chars = chars,
  length = length,
  wildcard = wildcard,
  format_value = M.format_value,
  parse_address = M.parse_address,
  col_number = M.col_number,
  LAST_ROW = LAST_ROW,
  LAST_COL = LAST_COL,
}
for _, name in ipairs ({
  'sheet_fn_arrays',
  'sheet_fn_stats',
  'sheet_fn_finance',
  'sheet_fn_more',
}) do
  local add = require (name) --[[@as fun(kit: Sheet.FormulaKit)]]
  add (kit)
end

table.sort (CATALOG, function (a, b)
  return a.name < b.name
end)
M.catalog = CATALOG

M.functions = {}
for _, entry in ipairs (CATALOG) do
  M.functions[#M.functions + 1] = entry.name
end

---------------------------------------------------------------------------------------------
-- Reading formulas
---------------------------------------------------------------------------------------------

---@param a Sheet.Ref
---@param b? Sheet.Ref
---@return Sheet.Area
local function area_of (a, b)
  if not b then
    return { r1 = a.row, c1 = a.col, r2 = a.row, c2 = a.col, sheet = a.sheet }
  end
  ---@type Sheet.Area
  local area =
    { r1 = a.row, c1 = a.col, r2 = b.row, c2 = b.col, sheet = a.sheet }
  if a.row and b.row then
    area.r1, area.r2 = math.min (a.row, b.row), math.max (a.row, b.row)
  end
  if a.col and b.col then
    area.c1, area.c2 = math.min (a.col, b.col), math.max (a.col, b.col)
  end
  return area
end

---Calls `fn` with every node of a tree, parents before children and left before right. It
---walks with a list rather than recursion, so a long chain such as A1+A2+...+A9999 is safe.
---@param ast Sheet.Node
---@param fn fun(node: Sheet.Node)
local function walk (ast, fn)
  local stack = { ast } ---@type Sheet.Node[]
  while #stack > 0 do
    local node = stack[#stack]
    stack[#stack] = nil
    fn (node)
    local args = node.args
    if args then
      for i = #args, 1, -1 do
        stack[#stack + 1] = args[i]
      end
    end
    if node.right then
      stack[#stack + 1] = node.right
    end
    if node.left then
      stack[#stack + 1] = node.left
    end
  end
end

---Every block of cells a formula reads, with the sheet each one names. Cells that INDIRECT
---and OFFSET reach are not known until the formula is worked out.
---@param ast Sheet.Node
---@return Sheet.Area[]
function M.refs (ast)
  local out = {} ---@type Sheet.Area[]
  walk (ast, function (node)
    -- A1# reads the formula in A1, which is worked out again whenever its block changes.
    if node.kind == 'ref' or node.kind == 'spill' then
      out[#out + 1] = area_of (node.a --[[@as Sheet.Ref]])
    elseif node.kind == 'range' then
      out[#out + 1] = area_of (node.a --[[@as Sheet.Ref]], node.b)
    end
  end)
  return out
end

local VOLATILE = {
  RAND = true,
  RANDBETWEEN = true,
  NOW = true,
  TODAY = true,
  INDIRECT = true,
  OFFSET = true,
}

---True when a formula must be worked out again after every change: it calls RAND,
---RANDBETWEEN, NOW, TODAY, INDIRECT or OFFSET.
---@param ast Sheet.Node
---@return boolean
function M.volatile (ast)
  local found = false
  walk (ast, function (node)
    if node.kind == 'call' and VOLATILE[node.name or ''] then
      found = true
    end
  end)
  return found
end

---True when a formula reads which rows are hidden: it calls SUBTOTAL or AGGREGATE.
---@param ast Sheet.Node
---@return boolean
function M.reads_hidden (ast)
  local found = false
  walk (ast, function (node)
    if
      node.kind == 'call'
      and (node.name == 'SUBTOTAL' or node.name == 'AGGREGATE')
    then
      found = true
    end
  end)
  return found
end

---@type table<string, 'date'|'time'|'datetime'>
local FORMAT_OF = {
  DATE = 'date',
  TODAY = 'date',
  EDATE = 'date',
  EOMONTH = 'date',
  WORKDAY = 'date',
  DATEVALUE = 'date',
  NOW = 'datetime',
  TIME = 'time',
  TIMEVALUE = 'time',
}

---How the result of a formula should show, from its outermost function: `=DATE(2026,9,29)`
---shows as a date. A date plus or minus days stays a date, a date plus a time is a date and
---time, and a date minus a date is a count of days.
---@param ast Sheet.Node
---@return 'date'|'time'|'datetime'|'percent'|nil
function M.result_format (ast)
  -- Walk down the left side of a chain such as TODAY()+1-2, then fold back up.
  local steps = {} ---@type Sheet.Node[]
  local node = ast
  while node.kind == 'binary' and (node.op == '+' or node.op == '-') do
    steps[#steps + 1] = node
    node = node.left --[[@as Sheet.Node]]
  end
  local kind = nil ---@type 'date'|'time'|'datetime'|nil
  if node.kind == 'call' then
    kind = FORMAT_OF[node.name or '']
  end
  for i = #steps, 1, -1 do
    local step = steps[i]
    local right = M.result_format (step.right --[[@as Sheet.Node]]) --[[@as 'date'|'time'|'datetime'|nil]]
    if step.op == '+' then
      if
        (kind == 'date' and right == 'time')
        or (kind == 'time' and right == 'date')
      then
        kind = 'datetime'
      else
        kind = kind or right
      end
    elseif right then
      kind = nil
    end
  end
  return kind
end

---Says when a formula shows a date or a date and time, as `result_format` does. A time alone
---gives nil here.
---@param ast Sheet.Node
---@return 'date'|'datetime'|nil
function M.date_kind (ast)
  local kind = M.result_format (ast)
  if kind == 'date' then
    return 'date'
  end
  if kind == 'datetime' then
    return 'datetime'
  end
  return nil
end

---------------------------------------------------------------------------------------------
-- Rewriting formulas
---------------------------------------------------------------------------------------------

---@param ref Sheet.Ref
---@return string
local function ref_text (ref)
  local out = ''
  if ref.col then
    out = (ref.col_abs and '$' or '') .. M.col_name (ref.col)
  end
  if ref.row then
    out = out .. (ref.row_abs and '$' or '') .. string.format ('%d', ref.row)
  end
  return out
end

---@param ref Sheet.Ref
---@return Sheet.Ref
local function copy_ref (ref)
  return {
    row = ref.row,
    col = ref.col,
    row_abs = ref.row_abs,
    col_abs = ref.col_abs,
    sheet = ref.sheet,
  }
end

---The text of a reference or a range token from its ends, with its sheet as written.
---@param t Sheet.Token
---@param a Sheet.Ref
---@param b? Sheet.Ref
---@return string
local function token_text (t, a, b)
  local out = (t.sheet_text or '') .. ref_text (a)
  if b then
    out = out .. ':' .. ref_text (b)
  end
  if t.spill then
    out = out .. '#'
  end
  return out
end

---@param ref Sheet.Ref
---@param axis 'row'|'col'
---@return integer?
local function coord (ref, axis)
  if axis == 'row' then
    return ref.row
  end
  return ref.col
end

---@param ref Sheet.Ref
---@param axis 'row'|'col'
---@param v integer
local function set_coord (ref, axis, v)
  if axis == 'row' then
    ref.row = v
  else
    ref.col = v
  end
end

---Rebuilds formula text, letting `fn` replace the text of each reference or range. When `fn`
---returns nil the original text stays. Text that is not a formula, or does not tokenize,
---comes back unchanged.
---@param text string
---@param fn fun(t: Sheet.Token): string?
---@return string
local function rewrite (text, fn)
  if not M.is_formula (text) then
    return text
  end
  local tokens = M.tokenize (text, 2)
  if not tokens then
    return text
  end
  local parts = {} ---@type string[]
  local pos = 1
  for _, t in ipairs (tokens) do
    if t.kind == 'ref' or t.kind == 'range' then
      local new = fn (t)
      if new and new ~= t.text then
        parts[#parts + 1] = string.sub (text, pos, t.from - 1)
        parts[#parts + 1] = new
        pos = t.to + 1
      end
    end
  end
  if pos == 1 then
    return text
  end
  parts[#parts + 1] = string.sub (text, pos)
  return table.concat (parts)
end

---@param ref Sheet.Ref
---@param drow integer
---@param dcol integer
---@return Sheet.Ref?
local function moved (ref, drow, dcol)
  local out = copy_ref (ref)
  if out.row and not out.row_abs then
    out.row = out.row + drow
  end
  if out.col and not out.col_abs then
    out.col = out.col + dcol
  end
  if
    (out.row and (out.row < 1 or out.row > LAST_ROW))
    or (out.col and (out.col < 1 or out.col > LAST_COL))
  then
    return nil
  end
  return out
end

---Moves the relative references in a formula by a number of rows and columns, as a copy and
---paste does. References with `$` stay. A reference pushed off the sheet turns into #REF!.
---References to other sheets move too.
---@param text string
---@param drow integer
---@param dcol integer
---@return string
function M.shift (text, drow, dcol)
  if drow == 0 and dcol == 0 then
    return text
  end
  return rewrite (text, function (t)
    local a = moved (t.a --[[@as Sheet.Ref]], drow, dcol)
    if t.kind == 'ref' then
      return a and token_text (t, a) or '#REF!'
    end
    local b = moved (t.b --[[@as Sheet.Ref]], drow, dcol)
    if not a or not b then
      return '#REF!'
    end
    return token_text (t, a, b)
  end)
end

---Folds a sheet name for comparing, since sheet names ignore case.
---@param name string
---@return string
local function sheet_key (name)
  return lower (name)
end

---True when a reference sits on the sheet where rows or columns changed.
---@param sheet string?
---@param opts Sheet.AdjustOptions?
---@return boolean
local function affected (sheet, opts)
  if not opts then
    return sheet == nil
  end
  local mine = sheet or opts.own
  local where = opts.sheet or opts.own
  if opts.sheet == nil and sheet == nil then
    return true
  end
  return mine ~= nil and where ~= nil and sheet_key (mine) == sheet_key (where)
end

---True when a reference names one cell, or both ends of a range, inside a block.
---@param t Sheet.Token
---@param rect Sheet.Rect
---@return boolean all
---@return boolean some True when at least one cell of the reference is in the block.
local function inside (t, rect)
  local a = t.a --[[@as Sheet.Ref]]
  local b = t.kind == 'range' and t.b or a --[[@as Sheet.Ref]]
  local r1 = math.min (a.row or 1, b.row or 1)
  local r2 = math.max (a.row or math.huge, b.row or math.huge)
  local c1 = math.min (a.col or 1, b.col or 1)
  local c2 = math.max (a.col or math.huge, b.col or math.huge)
  local all = r1 >= rect.r1
    and r2 <= rect.r2
    and c1 >= rect.c1
    and c2 <= rect.c2
  local some = r1 <= rect.r2
    and r2 >= rect.r1
    and c1 <= rect.c2
    and c2 >= rect.c1
  return all, some
end

---Fixes the references in a formula after a block of cells moves, as a cut and paste or a
---drag does. A reference that lies wholly inside the block moves with it, `$` or not, and
---follows it to another sheet. A reference to cells the block lands on, and that the block
---did not hold, turns into #REF!, since the cells it named are gone. Every other reference
---stays where it points.
---
---`opts.from` and `opts.to` name the sheets the block moves from and to, `opts.own` the sheet
---the formula lives on, and `opts.lands` the sheet it lives on after the move, when the
---formula moves with the block. A reference gets a sheet name when it needs one to keep
---pointing at the same sheet.
---@param text string
---@param src Sheet.Rect The block before the move.
---@param drow integer
---@param dcol integer
---@param opts Sheet.MoveOptions
---@return string
function M.move (text, src, drow, dcol, opts)
  local from, to = sheet_key (opts.from), sheet_key (opts.to)
  local lands = opts.lands or opts.own
  local dst = {
    r1 = src.r1 + drow,
    c1 = src.c1 + dcol,
    r2 = src.r2 + drow,
    c2 = src.c2 + dcol,
  }
  return rewrite (text, function (t)
    local named = t.sheet or opts.own
    local key = sheet_key (named)
    local a = t.a --[[@as Sheet.Ref]]
    local b = t.b
    local where = named
    if key == from and inside (t, src) then
      a = copy_ref (a)
      a.row, a.col = (a.row or 0) + drow, (a.col or 0) + dcol
      if b then
        b = copy_ref (b)
        b.row, b.col = (b.row or 0) + drow, (b.col or 0) + dcol
      end
      where = opts.to
    elseif key == to and inside (t, dst) then
      local _, held = inside (t, src)
      if key ~= from or not held then
        return '#REF!'
      end
    end
    local head ---@type string
    if t.sheet and sheet_key (t.sheet) == sheet_key (where) then
      head = t.sheet_text or ''
    elseif sheet_key (where) == sheet_key (lands) then
      head = ''
    else
      head = M.quote_sheet (where) .. '!'
    end
    local out = head .. ref_text (a)
    if t.kind == 'range' and b then
      out = out .. ':' .. ref_text (b)
    end
    if t.spill then
      out = out .. '#'
    end
    return out
  end)
end

---Fixes the references in a formula after rows or columns change. `count` rows or columns
---were inserted before `at` when it is positive. When it is negative, `-count` of them were
---deleted starting at `at`. Every reference moves, `$` or not. A reference to a deleted cell
---turns into #REF!, and a range that loses some of its rows or columns shrinks.
---
---`opts.sheet` names the sheet that changed, and `opts.own` the sheet the formula lives on.
---A reference changes when the sheet it names, or `own` when it names none, is the one that
---changed. With no `opts`, only references that name no sheet change.
---@param text string
---@param axis 'row'|'col'
---@param at integer
---@param count integer
---@param opts? Sheet.AdjustOptions
---@return string
function M.adjust (text, axis, at, count, opts)
  if count == 0 then
    return text
  end
  local n = -count
  local last = at + n - 1
  return rewrite (text, function (t)
    if not affected (t.sheet, opts) then
      return nil
    end
    local a = copy_ref (t.a --[[@as Sheet.Ref]])
    if t.kind == 'ref' then
      local v = coord (a, axis) or 0
      if count > 0 then
        if v >= at then
          set_coord (a, axis, v + count)
        end
      elseif v >= at and v <= last then
        return '#REF!'
      elseif v > last then
        set_coord (a, axis, v - n)
      end
      return token_text (t, a)
    end
    local b = copy_ref (t.b --[[@as Sheet.Ref]])
    local x, y = coord (a, axis), coord (b, axis)
    if x == nil or y == nil then
      -- A whole column does not change when rows do, and a whole row does not when columns do.
      return nil
    end
    local lo, hi = math.min (x, y), math.max (x, y)
    if count > 0 then
      if lo >= at then
        lo = lo + count
      end
      if hi >= at then
        hi = hi + count
      end
    else
      if lo >= at and hi <= last then
        return '#REF!'
      end
      if lo > last then
        lo = lo - n
      elseif lo >= at then
        lo = at
      end
      if hi > last then
        hi = hi - n
      elseif hi >= at then
        hi = at - 1
      end
    end
    set_coord (a, axis, lo)
    set_coord (b, axis, hi)
    return token_text (t, a, b)
  end)
end

---Points the references to sheet `old` at sheet `new`, after a rename. Sheet names ignore case,
---and `new` gets quotes when it needs them.
---@param text string
---@param old string
---@param new string
---@return string
function M.rename_sheet (text, old, new)
  local key = sheet_key (old)
  local prefix = M.quote_sheet (new) .. '!'
  return rewrite (text, function (t)
    if t.sheet and sheet_key (t.sheet) == key then
      return prefix .. string.sub (t.text, #(t.sheet_text or '') + 1)
    end
    return nil
  end)
end

---Turns the references to sheet `name` into #REF!, after the sheet is deleted.
---@param text string
---@param name string
---@return string
function M.drop_sheet (text, name)
  local key = sheet_key (name)
  return rewrite (text, function (t)
    if t.sheet and sheet_key (t.sheet) == key then
      return '#REF!'
    end
    return nil
  end)
end

---Tidies a formula as it is entered: references and function names go to upper case, a
---missing closing quote is added, and so are missing closing parentheses. Sheet names keep
---their case.
---@param text string
---@return string
function M.normalize (text)
  if not M.is_formula (text) then
    return text
  end
  local src = text
  local tokens = M.tokenize (src, 2)
  if not tokens then
    src = text .. '"'
    tokens = M.tokenize (src, 2)
    if not tokens then
      return text
    end
  end
  local depth = 0
  local parts = {} ---@type string[]
  local pos = 1
  for _, t in ipairs (tokens) do
    if t.kind == 'open' then
      depth = depth + 1
    elseif t.kind == 'close' then
      depth = depth - 1
    end
    local kind = t.kind
    if
      kind == 'ref'
      or kind == 'range'
      or kind == 'error'
      or kind == 'name'
    then
      local head = t.sheet_text or ''
      local up = head .. string.upper (string.sub (t.text, #head + 1))
      if up ~= t.text then
        parts[#parts + 1] = string.sub (src, pos, t.from - 1)
        parts[#parts + 1] = up
        pos = t.to + 1
      end
    end
  end
  parts[#parts + 1] = string.sub (src, pos)
  local out = table.concat (parts)
  if depth > 0 then
    out = out .. string.rep (')', depth)
  end
  return out
end

---------------------------------------------------------------------------------------------
-- Typing formulas
---------------------------------------------------------------------------------------------

---The function name right before byte `i`, the "(" of a call, or nil when a plain bracket
---opens there.
---@param text string
---@param i integer
---@return string?
local function name_before (text, i)
  local head = string.sub (text, 1, i - 1)
  local s, name = string.match (head, '()([%a_][%w_%.]*)%s*$')
  if not name then
    return nil
  end
  local prev = string.sub (head, s - 1, s - 1)
  if prev ~= '' and string.find (prev, '[%w_%.%$!:\'"#]') then
    return nil
  end
  return string.upper (name)
end

---Walks formula text up to the byte before `stop`. Returns the quote `stop` sits inside, `"`
---for text or `'` for a sheet name, and the brackets open around it, innermost last.
---@param text string
---@param stop integer
---@return string?
---@return Sheet.Frame[]
local function scan (text, stop)
  local frames = {} ---@type Sheet.Frame[]
  local quote = nil ---@type string?
  local i = 2
  while i < stop do
    local ch = string.sub (text, i, i)
    if quote then
      if ch == quote then
        if i + 1 < stop and string.sub (text, i + 1, i + 1) == quote then
          i = i + 1
        else
          quote = nil
        end
      end
    elseif ch == '"' or ch == "'" then
      quote = ch
    elseif ch == '(' then
      frames[#frames + 1] =
        { name = name_before (text, i), arg = 1, brace = false }
    elseif ch == '{' then
      frames[#frames + 1] = { arg = 1, brace = true }
    elseif ch == ')' or ch == '}' then
      local brace = ch == '}'
      for k = #frames, 1, -1 do
        local found = frames[k].brace == brace
        frames[k] = nil
        if found then
          break
        end
      end
    elseif ch == ',' then
      local top = frames[#frames]
      if top then
        top.arg = top.arg + 1
      end
    end
    i = i + 1
  end
  return quote, frames
end

---True when some function name starts with `prefix`, ignoring case.
---@param prefix string
---@return boolean
local function names_start (prefix)
  local up = string.upper (prefix)
  for _, name in ipairs (M.functions) do
    if string.sub (name, 1, #up) == up then
      return true
    end
  end
  return false
end

---The function name being typed when the caret sits before byte `pos`: `from` and `to` span
---the whole name, and `prefix` is the part before the caret. Returns nil inside text in
---quotes, inside a sheet name, after a "!" or ":", and when no function starts that way.
---@param text string
---@param pos integer
---@return Sheet.Completion?
function M.complete (text, pos)
  if string.sub (text, 1, 1) ~= '=' or pos < 2 or pos > #text + 1 then
    return nil
  end
  if scan (text, pos) then
    return nil
  end
  local head = string.sub (text, 1, pos - 1)
  local from, prefix = string.match (head, '()([%a_][%w_%.]*)$')
  if not from then
    return nil
  end
  local prev = string.sub (text, from - 1, from - 1)
  if string.find (prev, '[%w_%.%$!:\'"#]') then
    return nil
  end
  local rest = string.match (text, '^[%w_%.]*', pos)
  local to = pos - 1 + #rest
  if string.sub (text, to + 1, to + 1) == '!' or not names_start (prefix) then
    return nil
  end
  return { from = from, to = to, prefix = prefix }
end

---The innermost function whose arguments hold the caret before byte `pos`, and which of its
---arguments the caret is in. Plain brackets and array constants are passed over. Returns nil
---outside every function.
---@param text string
---@param pos integer
---@return Sheet.CallInfo?
function M.call_at (text, pos)
  if string.sub (text, 1, 1) ~= '=' then
    return nil
  end
  local _, frames = scan (text, math.min (pos, #text + 1))
  for k = #frames, 1, -1 do
    local frame = frames[k]
    if not frame.brace and frame.name then
      ---@type Sheet.CallInfo
      local info = { name = frame.name, arg = frame.arg }
      return info
    end
  end
  return nil
end

---Every reference in formula text, in order, with the bytes it spans, for colouring. Text
---still being typed works too.
---@param text string
---@return Sheet.RefSpan[]
function M.ref_spans (text)
  local out = {} ---@type Sheet.RefSpan[]
  if string.sub (text, 1, 1) ~= '=' then
    return out
  end
  for _, t in ipairs (lex (text, 2, true) or {}) do
    if t.kind == 'ref' or t.kind == 'range' then
      out[#out + 1] = {
        from = t.from,
        to = t.to,
        area = area_of (t.a --[[@as Sheet.Ref]], t.b),
      }
    end
  end
  return out
end

-- The anchors F4 moves to from each one, column first: A1, $A$1, A$1, $A1, then A1 again.
local NEXT_ANCHOR = {
  ['--'] = '$$',
  ['$$'] = '-$',
  ['-$'] = '$-',
  ['$-'] = '--',
}

---Sets the anchors a reference has room for. A whole column has no row, and a whole row no
---column.
---@param ref Sheet.Ref
---@param col_abs boolean
---@param row_abs boolean
local function set_anchor (ref, col_abs, row_abs)
  if ref.col then
    ref.col_abs = col_abs
  end
  if ref.row then
    ref.row_abs = row_abs
  end
end

---F4: cycles the `$` anchors of the reference at or right before the caret, `pos`, through
---A1, $A$1, A$1 and $A1. Both ends of a range change together. Returns the new text and the
---caret after the reference, or the text and `pos` unchanged when no reference is there.
---@param text string
---@param pos integer
---@return string
---@return integer
function M.toggle_anchor (text, pos)
  if string.sub (text, 1, 1) ~= '=' then
    return text, pos
  end
  local hit = nil ---@type Sheet.Token?
  for _, t in ipairs (lex (text, 2, true) or {}) do
    if t.kind == 'ref' or t.kind == 'range' then
      if t.from <= pos and pos <= t.to then
        hit = t
        break
      end
      if t.to + 1 == pos then
        hit = t
      end
    end
  end
  if not hit then
    return text, pos
  end
  local a = copy_ref (hit.a --[[@as Sheet.Ref]])
  local b = hit.b and copy_ref (hit.b) or nil
  local col_abs, row_abs = a.col_abs, a.row_abs
  if a.col and a.row then
    local key = (col_abs and '$' or '-') .. (row_abs and '$' or '-')
    local next_key = NEXT_ANCHOR[key]
    col_abs = string.sub (next_key, 1, 1) == '$'
    row_abs = string.sub (next_key, 2, 2) == '$'
  elseif a.col then
    col_abs = not col_abs
  else
    row_abs = not row_abs
  end
  set_anchor (a, col_abs, row_abs)
  if b then
    set_anchor (b, col_abs, row_abs)
  end
  local new = token_text (hit, a, b)
  local out = string.sub (text, 1, hit.from - 1)
    .. new
    .. string.sub (text, hit.to + 1)
  return out, hit.from + #new
end

---True when the caret in formula text sits where a reference can go, such as right after
---"=", "(", ",", an operator or a sheet name's "!", and not inside quotes. Clicking a cell or
---pressing an arrow key then puts the cell's address there. `pos` is the byte the caret sits
---before.
---@param text string
---@param pos integer
---@return boolean
function M.can_point (text, pos)
  if string.sub (text, 1, 1) ~= '=' then
    return false
  end
  if scan (text, pos) then
    return false
  end
  local head = string.sub (text, 1, pos - 1)
  local before = string.match (head, '(%S)%s*$')
  if not before or not string.find ('=(,+-*/^&<>:!', before, 1, true) then
    return false
  end
  if before == '!' then
    -- An error such as #REF! ends in "!" too, and no reference goes after it.
    local tail = string.upper (string.match (head, '(%S+)%s*$') or '')
    for _, code in ipairs (M.ERROR_CODES) do
      if string.sub (tail, -#code) == code then
        return false
      end
    end
  end
  local after = string.match (string.sub (text, pos), '^%s*(%S)')
  return after == nil or string.find (')+-*/^&<>=,', after, 1, true) ~= nil
end

return M
