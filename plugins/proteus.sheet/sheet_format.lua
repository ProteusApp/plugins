-- sheet_format: number formats for the Sheet app. It shows a value through an Excel format
-- code such as `$#,##0.00`, `0.0%` or `yyyy-mm-dd`, and it works out what typed text means,
-- so `15%` stores 0.15 with a percent format. It draws nothing and calls no host function.
--
-- Dates and times are serial numbers of days since 1899-12-30, as in sheet_formula. The
-- calendar, and reading dates and times from text, live in sheet_calendar, which the formulas
-- share.

local calendar = require ('sheet_calendar') --[[@as Sheet.CalendarModule]]

---@alias Sheet.FormatKind 'general'|'number'|'currency'|'accounting'|'percent'|'scientific'|'fraction'|'date'|'time'|'datetime'|'duration'|'text'

---@alias Sheet.Align 'left'|'center'|'right'

---A choice in the format menu.
---@class Sheet.FormatPreset
---@field id string
---@field label string
---@field code string

---@alias Sheet.FormatTokenKind 'lit'|'digit'|'point'|'comma'|'percent'|'exp'|'slash'|'text'|'general'|'date'|'ampm'|'fill'|'skip'|'attr'

---One piece of a format code.
---@class Sheet.FormatToken
---@field kind Sheet.FormatTokenKind
---@field text string What a literal shows, a placeholder such as `#`, or a date code such as `yyyy`.
---@field src string The code text the token came from, so a code can be rebuilt.
---@field part? string What the token does in its section, such as 'int', 'frac', 'group' or 'minute'.
---@field elapsed? boolean True for `[h]`, `[m]` and `[s]`.
---@field digits? integer How many decimals of a second a sub-second token shows.
---@field currency? boolean True for the symbol of `[$€-407]`.

---A condition such as `[>=100]`.
---@class Sheet.FormatCondition
---@field op string
---@field limit number

---One section of a format code, between semicolons.
---@class Sheet.FormatSection
---@field tokens Sheet.FormatToken[]
---@field role 'number'|'date'|'text'|'general'
---@field layout 'plain'|'sci'|'frac'
---@field color? string
---@field cond? Sheet.FormatCondition
---@field ints integer[] Token indexes of the integer placeholders, left to right.
---@field fracs integer[] Token indexes of the decimal placeholders.
---@field exps integer[] Token indexes of the exponent placeholders.
---@field nums integer[] Token indexes of the numerator placeholders.
---@field dens integer[] Token indexes of the denominator placeholders.
---@field den? integer A fixed denominator, such as the 8 in `# ?/8`.
---@field point? integer The token index of the decimal point.
---@field exp? integer The token index of `E+` or `E-`.
---@field frac_from integer The first token of a fraction, from the numerator.
---@field frac_to integer The last token of a fraction, to the denominator.
---@field grouping boolean
---@field scale integer How many times to divide by 1000.
---@field percent integer How many times to multiply by 100.
---@field precision integer How many decimals of a second a date section shows.
---@field calendar boolean True when a date section shows a year, a month or a day.
---@field clock boolean True when a date section shows a time of day.
---@field elapsed boolean True when a date section shows elapsed time, such as `[h]`.
---@field twelve boolean True when a date section shows AM and PM.

---A format code read into sections.
---@class Sheet.FormatCode
---@field sections Sheet.FormatSection[] Every section, in the order written.
---@field numbers Sheet.FormatSection[] The sections for numbers, at most three.
---@field text? Sheet.FormatSection The section for text.

---@class Sheet.FormatModule
---@field presets Sheet.FormatPreset[]
local M = {}

local MONTHS = calendar.MONTHS
local WEEKDAYS = {
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
}

-- Each colour has about 4:1 contrast on white and on the dark theme, so it reads on both.
-- Black and White become greys for the same reason.
---@type table<string, string>
local COLORS = {
  black = '#6e6e6e',
  white = '#8c8c8c',
  red = '#e03e3e',
  green = '#2b9348',
  blue = '#3d7fe0',
  yellow = '#9a7d0a',
  magenta = '#c940c9',
  cyan = '#0e8fa0',
}
-- `[Color1]` to `[Color8]`, in the order of Excel's palette.
local PALETTE = {
  'black',
  'white',
  'red',
  'green',
  'blue',
  'yellow',
  'magenta',
  'cyan',
}

---@type table<string, Sheet.FormatTokenKind>
local SYMBOLS = {
  ['.'] = 'point',
  [','] = 'comma',
  ['%'] = 'percent',
  ['@'] = 'text',
  ['/'] = 'slash',
}
local DATE_LETTERS =
  { y = true, m = true, d = true, h = true, s = true, e = true }
---@type table<string, string>
local OPPOSITE = {
  ['<'] = '>=',
  ['<='] = '>',
  ['>'] = '<=',
  ['>='] = '<',
  ['='] = '<>',
  ['<>'] = '=',
}
local CURRENCY = {
  '$',
  '€',
  '£',
  '¥',
  '￥',
  '₹',
  '₩',
  '₽',
  '¢',
  '₺',
  '₫',
  '₪',
  '₱',
  '฿',
}

---------------------------------------------------------------------------------------------
-- Calendar
---------------------------------------------------------------------------------------------

local calendar_date = calendar.day_date

---A date and time as a serial number. Months past 12 or days past the end of a month roll
---over, as they do in the DATE function.
---@param y integer
---@param m integer
---@param d integer
---@param h? number
---@param mi? number
---@param s? number
---@return number
function M.serial (y, m, d, h, mi, s)
  return calendar.serial (y, m, d, h, mi, s)
end

---The parts of a serial date: year, month, day, hour, minute, second, and the weekday from
---1 for Sunday. The time rounds to the nearest second.
---@param serial number
---@return integer y
---@return integer m
---@return integer d
---@return integer h
---@return integer mi
---@return integer s
---@return integer weekday
function M.date_parts (serial)
  return calendar.date_parts (serial)
end

-- The range of serials a date format shows: 0001-01-01 up to 9999-12-31.
local FIRST_DATE = M.serial (1, 1, 1)
local LAST_DATE = M.serial (10000, 1, 1)

---The local date and time now, as a serial number.
---@return number
local function now ()
  local t = os.date ('*t') --[[@as osdate]]
  return M.serial (t.year, t.month, t.day, t.hour, t.min, t.sec)
end

---------------------------------------------------------------------------------------------
-- Digits
---------------------------------------------------------------------------------------------

---Shows a number with up to 10 significant digits, as a General cell does, so float noise
---such as 0.30000000000000004 shows as 0.3.
---@param n number
---@return string
local function general_text (n)
  if n ~= n or n == math.huge or n == -math.huge then
    return '#NUM!'
  end
  if n == 0 then
    return '0'
  end
  return (string.gsub (string.format ('%.10g', n), 'e', 'E'))
end

---The first 15 significant digits of a positive number, and the power of ten of the first.
---Spreadsheets keep 15 digits, so this is where float noise stops.
---@param v number
---@return string digits
---@return integer exponent
local function significant (v)
  local lead, rest, exponent =
    string.match (string.format ('%.14e', v), '^(%d)%.(%d+)e([-+]%d+)$')
  return lead .. rest, tonumber (exponent) --[[@as integer]]
end

---Adds one to a string of digits.
---@param digits string
---@return string
local function increment (digits)
  local head, nines = string.match (digits, '^(.-)(9*)$')
  if head == '' then
    return '1' .. string.rep ('0', #nines)
  end
  local last = string.char (string.byte (head, -1) + 1)
  return string.sub (head, 1, -2) .. last .. string.rep ('0', #nines)
end

---Rounds a string of digits to `keep` digits, half away from zero. The second result is
---true when the rounding carried into a new digit, as 999 does to 1000.
---@param digits string
---@param keep integer
---@return string
---@return boolean
local function round_digits (digits, keep)
  if keep >= #digits then
    return digits .. string.rep ('0', keep - #digits), false
  end
  local out = string.sub (digits, 1, keep)
  if string.sub (digits, keep + 1, keep + 1) >= '5' then
    out = increment (out)
  end
  return out, #out > keep
end

---Splits a number that is not negative into the digits before and after the point, rounded
---half away from zero to `decimals` places. The whole part is '' when it is zero.
---@param v number
---@param decimals integer
---@return string whole
---@return string fraction Exactly `decimals` digits.
local function decimal_digits (v, decimals)
  if v == 0 then
    return '', string.rep ('0', decimals)
  end
  local digits, exponent = significant (v)
  local keep = exponent + 1 + decimals
  local scaled ---@type string
  if keep < 0 then
    scaled = '0'
  elseif keep == 0 then
    scaled = string.sub (digits, 1, 1) >= '5' and '1' or '0'
  else
    scaled = round_digits (digits, keep)
  end
  if #scaled <= decimals then
    scaled = string.rep ('0', decimals - #scaled + 1) .. scaled
  end
  local whole = string.sub (scaled, 1, #scaled - decimals)
  local fraction = string.sub (scaled, #scaled - decimals + 1)
  return (string.gsub (whole, '^0+', '')), fraction
end

---@param n number A whole number, not negative.
---@return string
local function whole_digits (n)
  local whole = decimal_digits (n, 0)
  return whole
end

---Counts the characters of UTF-8 text.
---@param text string
---@return integer
local function width (text)
  local _, count = string.gsub (text, '[^\128-\191]', '')
  return count
end

---The UTF-8 character that starts at byte `i`, or '' past the end.
---@param text string
---@param i integer
---@return string
local function char_at (text, i)
  local b = string.byte (text, i)
  if not b then
    return ''
  end
  local len = b >= 0xF0 and 4 or b >= 0xE0 and 3 or b >= 0xC0 and 2 or 1
  return string.sub (text, i, i + len - 1)
end

---@param text string
---@return string
local function trim (text)
  return (string.match (text, '^%s*(.-)%s*$'))
end

---------------------------------------------------------------------------------------------
-- Reading a format code
---------------------------------------------------------------------------------------------

---@param kind Sheet.FormatTokenKind
---@param text string
---@param src string
---@return Sheet.FormatToken
local function token (kind, text, src)
  return { kind = kind, text = text, src = src }
end

---@return Sheet.FormatSection
local function new_section ()
  return {
    tokens = {},
    role = 'number',
    layout = 'plain',
    ints = {},
    fracs = {},
    exps = {},
    nums = {},
    dens = {},
    frac_from = 0,
    frac_to = -1,
    grouping = false,
    scale = 0,
    percent = 0,
    precision = 0,
    calendar = false,
    clock = false,
    elapsed = false,
    twelve = false,
  }
end

---@param text string
---@return boolean
local function is_decimal (text)
  return string.match (text, '^[+-]?%d+%.?%d*$') ~= nil
    or string.match (text, '^[+-]?%.%d+$') ~= nil
end

---Reads the text inside square brackets: a colour, a condition, elapsed time, or a currency
---and locale. Anything else, such as `[DBNum1]`, is kept but shows nothing. Returns false
---for a condition that does not read.
---@param section Sheet.FormatSection
---@param inner string
---@param src string
---@return boolean
local function read_bracket (section, inner, src)
  local tokens = section.tokens
  local lower = string.lower (inner)
  local color = COLORS[lower]
  local index = string.match (lower, '^color%s*(%d+)$')
  if index then
    color = COLORS[PALETTE[tonumber (index)] or '']
  end
  if color or index then
    section.color = section.color or color
    tokens[#tokens + 1] = token ('attr', '', src)
    return true
  end
  local op, limit = string.match (inner, '^%s*([<>=]+)%s*(.-)%s*$')
  if op then
    if not OPPOSITE[op] or not is_decimal (limit) then
      return false
    end
    section.cond = {
      op = op,
      limit = tonumber (limit) --[[@as number]],
    }
    tokens[#tokens + 1] = token ('attr', '', src)
    return true
  end
  if
    string.match (lower, '^h+$')
    or string.match (lower, '^m+$')
    or string.match (lower, '^s+$')
  then
    local t = token ('date', lower, src)
    t.elapsed = true
    tokens[#tokens + 1] = t
    return true
  end
  local symbol = string.match (inner, '^%$([^%-]*)')
  if symbol and symbol ~= '' then
    local t = token ('lit', symbol, src)
    t.currency = true
    tokens[#tokens + 1] = t
    return true
  end
  tokens[#tokens + 1] = token ('attr', '', src)
  return true
end

---Reads a letter, which may start `General`, `AM/PM`, `A/P` or a run of date letters such
---as `yyyy`. Any other letter shows as itself. Returns the index after it.
---@param tokens Sheet.FormatToken[]
---@param code string
---@param i integer
---@return integer
local function read_letter (tokens, code, i)
  local c = string.sub (code, i, i)
  local lower = string.lower (c)
  local ahead = string.upper (string.sub (code, i, i + 4))
  if string.lower (string.sub (code, i, i + 6)) == 'general' then
    tokens[#tokens + 1] = token ('general', '', string.sub (code, i, i + 6))
    return i + 7
  end
  if ahead == 'AM/PM' then
    tokens[#tokens + 1] = token ('ampm', 'AM/PM', string.sub (code, i, i + 4))
    return i + 5
  end
  if string.sub (ahead, 1, 3) == 'A/P' then
    tokens[#tokens + 1] = token ('ampm', 'A/P', string.sub (code, i, i + 2))
    return i + 3
  end
  if DATE_LETTERS[lower] then
    local j = i
    while j <= #code and string.lower (string.sub (code, j, j)) == lower do
      j = j + 1
    end
    tokens[#tokens + 1] =
      token ('date', string.rep (lower, j - i), string.sub (code, i, j - 1))
    return j
  end
  tokens[#tokens + 1] = token ('lit', c, c)
  return i + 1
end

---Splits a code into sections of tokens. Returns nil when the code is malformed: a quote or
---a bracket left open, a `\`, `_` or `*` at the very end, a condition that does not read, or
---more than four sections.
---@param code string
---@return Sheet.FormatSection[]?
local function tokenize (code)
  local section = new_section ()
  local sections = { section } ---@type Sheet.FormatSection[]
  local i, n = 1, #code
  while i <= n do
    local c = string.sub (code, i, i)
    local tokens = section.tokens
    if c == ';' then
      section = new_section ()
      sections[#sections + 1] = section
      i = i + 1
    elseif c == '"' then
      local close = string.find (code, '"', i + 1, true)
      if not close then
        return nil
      end
      tokens[#tokens + 1] = token (
        'lit',
        string.sub (code, i + 1, close - 1),
        string.sub (code, i, close)
      )
      i = close + 1
    elseif c == '\\' or c == '_' or c == '*' then
      local ch = char_at (code, i + 1)
      if ch == '' then
        return nil
      end
      if c == '\\' then
        tokens[#tokens + 1] = token ('lit', ch, c .. ch)
      elseif c == '_' then
        tokens[#tokens + 1] = token ('skip', ' ', c .. ch)
      else
        tokens[#tokens + 1] = token ('fill', '', c .. ch)
      end
      i = i + 1 + #ch
    elseif c == '[' then
      local close = string.find (code, ']', i + 1, true)
      if not close then
        return nil
      end
      local inner = string.sub (code, i + 1, close - 1)
      if not read_bracket (section, inner, string.sub (code, i, close)) then
        return nil
      end
      i = close + 1
    elseif c == '0' or c == '#' or c == '?' then
      tokens[#tokens + 1] = token ('digit', c, c)
      i = i + 1
    elseif SYMBOLS[c] then
      tokens[#tokens + 1] = token (SYMBOLS[c], c, c)
      i = i + 1
    elseif
      (c == 'E' or c == 'e')
      and string.find ('+-', string.sub (code, i + 1, i + 1), 1, true)
      and i < n
    then
      tokens[#tokens + 1] = token (
        'exp',
        string.sub (code, i + 1, i + 1),
        string.sub (code, i, i + 1)
      )
      i = i + 2
    elseif string.match (c, '%a') then
      i = read_letter (tokens, code, i)
    else
      local ch = char_at (code, i)
      tokens[#tokens + 1] = token ('lit', ch, ch)
      i = i + #ch
    end
  end
  if #sections > 4 then
    return nil
  end
  return sections
end

---@param section Sheet.FormatSection
---@param kind Sheet.FormatTokenKind
---@return boolean
local function has (section, kind)
  for _, t in ipairs (section.tokens) do
    if t.kind == kind then
      return true
    end
  end
  return false
end

---@param t Sheet.FormatToken?
---@return boolean
local function is_space (t)
  return t ~= nil and t.kind == 'lit' and t.text == ' '
end

---A digit written without quotes, such as the 8 in `?/8`.
---@param t Sheet.FormatToken?
---@return boolean
local function is_numeral (t)
  return t ~= nil and t.kind == 'lit' and string.match (t.src, '^%d$') ~= nil
end

---Works out the date and time parts of a section: which `m` means minutes, the decimals of
---a second, and whether it shows a date, a time or elapsed time.
---@param section Sheet.FormatSection
local function analyse_date (section)
  local tokens = section.tokens
  for k, t in ipairs (tokens) do
    if t.kind == 'point' and t.part == nil then
      local count = 0
      while
        tokens[k + count + 1]
        and tokens[k + count + 1].kind == 'digit'
        and tokens[k + count + 1].text == '0'
      do
        count = count + 1
        tokens[k + count].part = 'used'
      end
      if count > 0 then
        t.part = 'subsec'
        t.digits = math.min (count, 3)
        section.precision = math.max (section.precision, t.digits)
      end
    end
  end
  -- An m or mm means minutes right after an hour or right before a second.
  local before ---@type Sheet.FormatToken?
  for k, t in ipairs (tokens) do
    if t.kind == 'date' then
      if t.text == 'm' or t.text == 'mm' then
        local after ---@type Sheet.FormatToken?
        for j = k + 1, #tokens do
          if tokens[j].kind == 'date' then
            after = tokens[j]
            break
          end
        end
        if
          (before and string.sub (before.text, 1, 1) == 'h')
          or (after and string.sub (after.text, 1, 1) == 's')
          or t.elapsed
        then
          t.part = 'minute'
        end
      end
      before = t
    end
  end
  for _, t in ipairs (tokens) do
    if t.kind == 'ampm' then
      section.twelve = true
      section.clock = true
    elseif t.kind == 'date' then
      local letter = string.sub (t.text, 1, 1)
      if t.elapsed then
        section.elapsed = true
      elseif letter == 'h' or letter == 's' or t.part == 'minute' then
        section.clock = true
      else
        section.calendar = true
      end
    end
  end
end

---Marks the commas of a number: a comma between integer placeholders groups thousands, and
---a comma right after the placeholders divides by 1000.
---@param section Sheet.FormatSection
---@param last integer The last token of the number.
local function analyse_commas (section, last)
  local tokens = section.tokens
  for k = 1, last do
    local t = tokens[k]
    if t.kind == 'comma' then
      local prev, after = tokens[k - 1], tokens[k + 1]
      if
        prev
        and prev.part == 'int'
        and after
        and after.kind == 'digit'
        and after.part == 'int'
      then
        t.part = 'group'
        section.grouping = true
      elseif
        prev
        and (prev.part == 'int' or prev.part == 'frac' or prev.part == 'scale')
      then
        t.part = 'scale'
        section.scale = section.scale + 1
      end
    end
  end
end

---Finds a fraction such as `# ??/??` or `?/8`. Returns false when the section has none.
---@param section Sheet.FormatSection
---@return boolean
local function analyse_fraction (section)
  local tokens = section.tokens
  for k, t in ipairs (tokens) do
    if t.kind == 'slash' then
      local j = k - 1
      while is_space (tokens[j]) do
        j = j - 1
      end
      local d = k + 1
      while is_space (tokens[d]) do
        d = d + 1
      end
      local top, bottom = tokens[j], tokens[d]
      if
        top
        and top.kind == 'digit'
        and bottom
        and (bottom.kind == 'digit' or is_numeral (bottom))
      then
        local num_end = j
        while tokens[j - 1] and tokens[j - 1].kind == 'digit' do
          j = j - 1
        end
        for q = j, num_end do
          tokens[q].part = 'num'
          section.nums[#section.nums + 1] = q
        end
        local den_end = d
        if is_numeral (bottom) then
          local text = ''
          while
            tokens[den_end]
            and (
              is_numeral (tokens[den_end])
              or (
                tokens[den_end].kind == 'digit'
                and tokens[den_end].text == '0'
              )
            )
          do
            tokens[den_end].part = 'fixed'
            text = text .. tokens[den_end].text
            den_end = den_end + 1
          end
          local value = tonumber (text) or 1
          section.den = math.floor (math.max (1, math.min (value, 1e9)))
        else
          while tokens[den_end] and tokens[den_end].kind == 'digit' do
            tokens[den_end].part = 'den'
            section.dens[#section.dens + 1] = den_end
            den_end = den_end + 1
          end
        end
        section.frac_from = j
        section.frac_to = den_end - 1
        for q = 1, j - 1 do
          local before = tokens[q]
          if before.kind == 'digit' then
            before.part = 'int'
            section.ints[#section.ints + 1] = q
          elseif before.kind == 'percent' then
            section.percent = section.percent + 1
          end
        end
        analyse_commas (section, j - 1)
        section.layout = 'frac'
        return true
      end
    end
  end
  return false
end

---Works out the placeholders of a number section: its integer and decimal digits, and its
---exponent or its fraction.
---@param section Sheet.FormatSection
local function analyse_number (section)
  local tokens = section.tokens
  for k, t in ipairs (tokens) do
    if t.kind == 'exp' then
      section.exp = k
      section.layout = 'sci'
      break
    end
  end
  if not section.exp and analyse_fraction (section) then
    return
  end
  local last = section.exp and section.exp - 1 or #tokens
  for k = 1, last do
    local t = tokens[k]
    if t.kind == 'digit' then
      if section.point then
        t.part = 'frac'
        section.fracs[#section.fracs + 1] = k
      else
        t.part = 'int'
        section.ints[#section.ints + 1] = k
      end
    elseif t.kind == 'point' and not section.point then
      section.point = k
    elseif t.kind == 'percent' then
      section.percent = section.percent + 1
    end
  end
  analyse_commas (section, last)
  if section.exp then
    local k = section.exp + 1
    while tokens[k] and tokens[k].kind == 'digit' do
      tokens[k].part = 'exp'
      section.exps[#section.exps + 1] = k
      k = k + 1
    end
  end
end

---Reads a format code. Returns nil for General and for a code that does not read, which
---shows as General too.
---@param code string
---@return Sheet.FormatCode?
local function parse_code (code)
  if string.lower (trim (code)) == 'general' then
    return nil
  end
  local sections = tokenize (code)
  if not sections then
    return nil
  end
  local count = #sections
  local numbers = {} ---@type Sheet.FormatSection[]
  local text ---@type Sheet.FormatSection?
  -- The fourth section is for text, and so is a last section that holds `@`.
  if count == 4 or has (sections[count], 'text') then
    text = sections[count]
    text.role = 'text'
    count = count - 1
  end
  for k = 1, count do
    local section = sections[k]
    numbers[k] = section
    local timed = has (section, 'date') or has (section, 'ampm')
    if timed then
      section.role = 'date'
      analyse_date (section)
    elseif has (section, 'general') then
      section.role = 'general'
    else
      analyse_number (section)
    end
  end
  return { sections = sections, numbers = numbers, text = text }
end

-- Reading a code takes longer than showing a value, and a sheet shows the same few codes
-- over and over, so each code is read once and kept.
local cache = {} ---@type table<string, Sheet.FormatCode|false>
local cached = 0

---@param code? string
---@return Sheet.FormatCode?
local function compile (code)
  if code == nil or code == '' then
    return nil
  end
  local hit = cache[code]
  if hit ~= nil then
    return hit or nil
  end
  local ok, parsed = pcall (parse_code, code)
  local result = ok and parsed or nil
  if cached >= 1000 then
    cache = {}
    cached = 0
  end
  cache[code] = result or false
  cached = cached + 1
  return result
end

---------------------------------------------------------------------------------------------
-- Showing a value
---------------------------------------------------------------------------------------------

---What a token shows when nothing more is known.
---@param t Sheet.FormatToken
---@return string
local function shown (t)
  local kind = t.kind
  if kind == 'lit' then
    return t.text
  elseif kind == 'skip' then
    return ' '
  elseif kind == 'fill' or kind == 'attr' then
    return ''
  elseif kind == 'comma' then
    return (t.part == 'group' or t.part == 'scale') and '' or ','
  elseif
    kind == 'digit'
    or kind == 'point'
    or kind == 'percent'
    or kind == 'slash'
    or kind == 'text'
  then
    return t.text
  end
  return t.src
end

---@param tokens Sheet.FormatToken[]
---@param emit table<integer, string>
---@return string
local function collect (tokens, emit)
  local out = {} ---@type string[]
  for k, t in ipairs (tokens) do
    out[k] = emit[k] or shown (t)
  end
  return table.concat (out)
end

---What an empty placeholder shows: `0` shows a zero, `?` a space and `#` nothing.
---@param placeholder string
---@return string
local function filler (placeholder)
  if placeholder == '0' then
    return '0'
  elseif placeholder == '?' then
    return ' '
  end
  return ''
end

---Places whole-number digits into placeholders from the right. The leftmost placeholder
---takes any digits left over, so a number too wide for its format keeps all its digits.
---@param tokens Sheet.FormatToken[]
---@param idx integer[]
---@param digits string
---@param grouping boolean
---@param emit table<integer, string>
local function fill_whole (tokens, idx, digits, grouping, emit)
  local n, len = #idx, #digits
  for j = 1, n do
    local p = n - j
    local out = {} ---@type string[]
    if p < len then
      local top = j == 1 and len - 1 or p
      for q = top, p, -1 do
        out[#out + 1] = string.sub (digits, len - q, len - q)
        if grouping and q > 0 and q % 3 == 0 then
          out[#out + 1] = ','
        end
      end
    else
      local pad = filler (tokens[idx[j]].text)
      out[1] = pad
      if grouping and p > 0 and p % 3 == 0 and pad ~= '' then
        out[2] = pad == ' ' and ' ' or ','
      end
    end
    emit[idx[j]] = table.concat (out)
  end
end

---Places decimal digits into placeholders from the left. A trailing zero shows only where
---the placeholder is a `0`.
---@param tokens Sheet.FormatToken[]
---@param idx integer[]
---@param digits string
---@param emit table<integer, string>
local function fill_decimals (tokens, idx, digits, emit)
  local last = 0
  for k = #digits, 1, -1 do
    if string.sub (digits, k, k) ~= '0' then
      last = k
      break
    end
  end
  for k, at in ipairs (idx) do
    emit[at] = k <= last and string.sub (digits, k, k)
      or filler (tokens[at].text)
  end
end

---Places a denominator into placeholders from the left, so the slashes of a column line up.
---@param tokens Sheet.FormatToken[]
---@param idx integer[]
---@param digits string
---@param emit table<integer, string>
local function fill_denominator (tokens, idx, digits, emit)
  local n = #idx
  for j, at in ipairs (idx) do
    if j > #digits then
      emit[at] = filler (tokens[at].text)
    elseif j == n then
      emit[at] = string.sub (digits, j)
    else
      emit[at] = string.sub (digits, j, j)
    end
  end
end

---Shows a number with plain placeholders, such as `#,##0.00`.
---@param section Sheet.FormatSection
---@param v number Not negative.
---@return string
---@return boolean nonzero False when the number shows as zero.
local function render_plain (section, v)
  local tokens = section.tokens
  local scaled = v * 100 ^ section.percent / 1000 ^ section.scale
  local whole, fraction = decimal_digits (scaled, #section.fracs)
  local emit = {} ---@type table<integer, string>
  fill_whole (tokens, section.ints, whole, section.grouping, emit)
  fill_decimals (tokens, section.fracs, fraction, emit)
  -- With no integer placeholders, as in `.00`, the whole part sits before the point.
  local point = section.point
  if #section.ints == 0 and point and whole ~= '' then
    emit[point] = whole .. '.'
  end
  -- A section with no placeholders, such as `"none"`, shows no minus sign, as in Excel.
  local nonzero = whole ~= '' or string.find (fraction, '[1-9]') ~= nil
  if #section.ints == 0 and #section.fracs == 0 then
    nonzero = false
  end
  return collect (tokens, emit), nonzero
end

---Shows a number in scientific notation, such as `0.00E+00`. With two or more integer
---placeholders, as in `##0.0E+0`, the exponent is a multiple of their count.
---@param section Sheet.FormatSection
---@param v number Not negative.
---@return string
---@return boolean nonzero
local function render_sci (section, v)
  local tokens = section.tokens
  local scaled = v * 100 ^ section.percent
  local ni, nf = #section.ints, #section.fracs
  local whole, fraction, power = '', string.rep ('0', nf), 0
  if scaled > 0 then
    local digits, exponent = significant (scaled)
    for _ = 1, 2 do
      local count = 1
      power = exponent
      if ni >= 2 then
        power = exponent - exponent % ni
        count = exponent - power + 1
      end
      local rounded, carried = round_digits (digits, count + nf)
      if not carried then
        whole = string.sub (rounded, 1, count)
        fraction = string.sub (rounded, count + 1)
        break
      end
      -- 9.99 in 0.0E+0 rounds up to 10.0, so it starts again from 1E+1.
      exponent = exponent + 1
      digits = '1'
    end
  end
  local emit = {} ---@type table<integer, string>
  fill_whole (tokens, section.ints, whole, false, emit)
  fill_decimals (tokens, section.fracs, fraction, emit)
  local point = section.point
  if ni == 0 and point and whole ~= '' then
    emit[point] = whole .. '.'
  end
  local exp = section.exp --[[@as integer]]
  local sign = power < 0 and '-' or (tokens[exp].text == '+' and '+' or '')
  emit[exp] = 'E' .. sign
  local power_digits = power == 0 and ''
    or string.format ('%d', math.abs (power))
  fill_whole (tokens, section.exps, power_digits, false, emit)
  return collect (tokens, emit), scaled ~= 0
end

---The fraction nearest to `x` among the steps of its continued fraction whose denominator
---is at most `most`. Excel stops at these steps too, so 0.3 in `?/?` shows 2/7 but 1.3 in
---`# ?/?` shows 1 1/3, because the float 0.3 sits a hair below 3/10 and 1.3 a hair above.
---@param x number Not negative.
---@param most number
---@return number numerator
---@return number denominator
local function approximate (x, most)
  local p2 = 0 ---@type number
  local p1 = 1 ---@type number
  local q2 = 1 ---@type number
  local q1 = 0 ---@type number
  local p = 0 ---@type number
  local q = 0 ---@type number
  local b = x
  for _ = 1, 64 do
    if q1 >= most then
      break
    end
    local a = math.floor (b)
    p = a * p1 + p2
    q = a * q1 + q2
    if b - a < 0.00000005 then
      break
    end
    b = 1 / (b - a)
    p2 = p1
    p1 = p --[[@as number]]
    q2 = q1
    q1 = q --[[@as number]]
  end
  if q > most and q1 > most then
    return p2, q2
  elseif q > most then
    return p1, q1
  end
  return p, q
end

---Shows a number as a fraction, such as `# ?/?` or `# ?/8`. Without a whole part, as in
---`?/?`, the fraction may be more than one.
---@param section Sheet.FormatSection
---@param v number Not negative.
---@return string
---@return boolean nonzero
local function render_fraction (section, v)
  local tokens = section.tokens
  local scaled = v * 100 ^ section.percent
  scaled = tonumber (string.format ('%.15g', scaled)) or scaled
  local has_whole = #section.ints > 0
  local whole, part = 0, scaled
  if has_whole then
    whole = math.floor (scaled)
    part = scaled - whole
  end
  local num, den ---@type number, number
  if section.den then
    den = section.den --[[@as integer]]
    num = math.floor (part * den + 0.5)
  else
    num, den = approximate (part, 10 ^ #section.dens - 1)
  end
  if has_whole and num >= den then
    whole = whole + 1
    num = num - den
  end
  local emit = {} ---@type table<integer, string>
  local whole_text = whole_digits (whole)
  if whole == 0 and num == 0 then
    whole_text = '0'
  end
  fill_whole (tokens, section.ints, whole_text, section.grouping, emit)
  if has_whole and num == 0 then
    -- A whole number keeps the width of the fraction as spaces, so columns line up.
    for k = section.frac_from, section.frac_to do
      local t = tokens[k]
      emit[k] = string.rep (' ', t.kind == 'digit' and 1 or width (shown (t)))
    end
  else
    local num_text = whole_digits (num)
    fill_whole (
      tokens,
      section.nums,
      num_text == '' and '0' or num_text,
      false,
      emit
    )
    if not section.den then
      fill_denominator (tokens, section.dens, whole_digits (den), emit)
    end
  end
  return collect (tokens, emit), whole ~= 0 or num ~= 0
end

---@param n integer
---@param len integer
---@return string
local function pad (n, len)
  return string.format (len >= 2 and '%02d' or '%d', n)
end

---Shows a serial number with date and time codes. The time rounds to the decimals of a
---second the section shows before it splits into parts, so 59.9 seconds in `ss` shows as
---the next minute rather than as 60.
---@param section Sheet.FormatSection
---@param v number Not negative, unless the section shows a date before 1900.
---@return string
---@return boolean nonzero
local function render_date (section, v)
  local precision = section.precision
  local per_second = math.floor (10 ^ precision + 0.5)
  local units = math.floor (v * 86400 * per_second + 0.5)
  local total = math.floor (units / per_second)
  local fraction = units - total * per_second
  local day = math.floor (total / 86400)
  local secs = total - day * 86400
  local y, m, d = calendar_date (day)
  local h = math.floor (secs / 3600)
  local mi = math.floor (secs / 60) % 60
  local s = secs % 60
  local weekday = (day - 1) % 7 + 1
  local out = {} ---@type string[]
  for k, t in ipairs (section.tokens) do
    local piece ---@type string
    local letter, len = string.sub (t.text, 1, 1), #t.text
    if t.kind == 'date' and t.elapsed then
      local amount = total
      if letter == 'h' then
        amount = math.floor (total / 3600)
      elseif letter == 'm' then
        amount = math.floor (total / 60)
      end
      piece = pad (amount, len)
    elseif t.kind == 'date' then
      if letter == 'y' then
        piece = len <= 2 and string.format ('%02d', y % 100)
          or string.format ('%d', y)
      elseif letter == 'e' then
        piece = string.format ('%d', y)
      elseif letter == 'd' then
        local name = WEEKDAYS[weekday]
        piece = len >= 4 and name
          or len == 3 and string.sub (name, 1, 3)
          or pad (d, len)
      elseif letter == 'h' then
        piece = pad (section.twelve and (h + 11) % 12 + 1 or h, len)
      elseif letter == 's' then
        piece = pad (s, len)
      elseif t.part == 'minute' then
        piece = pad (mi, len)
      else
        local name = MONTHS[m]
        if len == 5 then
          piece = string.sub (name, 1, 1)
        elseif len >= 4 then
          piece = name
        elseif len == 3 then
          piece = string.sub (name, 1, 3)
        else
          piece = pad (m, len)
        end
      end
    elseif t.kind == 'ampm' then
      if t.text == 'AM/PM' then
        piece = h < 12 and 'AM' or 'PM'
      else
        piece = h < 12 and string.sub (t.src, 1, 1) or string.sub (t.src, 3, 3)
      end
    elseif t.part == 'subsec' then
      local digits = string.format ('%0' .. precision .. 'd', fraction)
      piece = '.' .. string.sub (digits, 1, t.digits)
    elseif t.part == 'used' then
      piece = ''
    else
      piece = shown (t)
    end
    out[k] = piece
  end
  return table.concat (out), units ~= 0
end

---Shows a section that holds `General`, such as `[Blue]General`. General shows its own
---minus sign.
---@param section Sheet.FormatSection
---@param n number
---@return string
local function render_general (section, n)
  local out = {} ---@type string[]
  for k, t in ipairs (section.tokens) do
    out[k] = t.kind == 'general' and general_text (n) or shown (t)
  end
  return table.concat (out)
end

---Shows text through the text section, where `@` stands for the text.
---@param section Sheet.FormatSection
---@param text string
---@return string
local function render_text (section, text)
  local out = {} ---@type string[]
  for k, t in ipairs (section.tokens) do
    if t.kind == 'text' or t.kind == 'general' then
      out[k] = text
    else
      out[k] = shown (t)
    end
  end
  return table.concat (out)
end

---@param cond Sheet.FormatCondition
---@param n number
---@return boolean
local function meets (cond, n)
  local op, limit = cond.op, cond.limit
  if op == '<' then
    return n < limit
  elseif op == '<=' then
    return n <= limit
  elseif op == '>' then
    return n > limit
  elseif op == '>=' then
    return n >= limit
  elseif op == '=' then
    return n == limit
  end
  return n ~= limit
end

---True when a condition lets only negative numbers in. Such a section shows no minus sign,
---because its own text shows the sign, as `(0.00)` does.
---@param op string
---@param limit number
---@return boolean
local function negative_only (op, limit)
  if op == '<' then
    return limit <= 0
  elseif op == '<=' or op == '=' then
    return limit < 0
  end
  return false
end

---Picks the section for a number. The second result is true when the section shows the
---sign itself, so the number shows without its minus sign.
---@param parsed Sheet.FormatCode
---@param n number
---@return Sheet.FormatSection?
---@return boolean
local function choose (parsed, n)
  local first, second, third =
    parsed.numbers[1], parsed.numbers[2], parsed.numbers[3]
  if not first then
    return nil, false
  end
  local c1 = first.cond
  local c2 = second and second.cond
  if c1 or c2 then
    if c1 and meets (c1, n) then
      return first, negative_only (c1.op, c1.limit)
    end
    if second and c2 and meets (c2, n) then
      return second, negative_only (c2.op, c2.limit)
    end
    if c1 and c2 then
      return third or first, false
    end
    if c1 and second then
      return second, negative_only (OPPOSITE[c1.op], c1.limit)
    end
    return first, false
  end
  if n < 0 and second then
    return second, true
  end
  if n == 0 and third then
    return third, false
  end
  return first, false
end

---@param section Sheet.FormatSection
---@param n number
---@param own_sign boolean True when the section shows the sign itself.
---@return string
local function render_number (section, n, own_sign)
  if section.role == 'general' then
    return render_general (section, n)
  end
  if section.role == 'date' then
    local v, sign = n, ''
    if n < 0 and (own_sign or not section.calendar) then
      v = -n
      sign = own_sign and '' or '-'
    end
    if
      (section.calendar and (v < FIRST_DATE or v >= LAST_DATE))
      or math.abs (v) >= 1e8
    then
      return general_text (n)
    end
    local text, nonzero = render_date (section, v)
    return (nonzero and sign or '') .. text
  end
  local v = math.abs (n)
  local text, nonzero ---@type string, boolean
  if section.layout == 'sci' then
    text, nonzero = render_sci (section, v)
  elseif section.layout == 'frac' then
    text, nonzero = render_fraction (section, v)
  else
    text, nonzero = render_plain (section, v)
  end
  -- A number that rounds to zero shows no minus sign, so -0.001 in 0.00 is 0.00.
  if n < 0 and nonzero and not own_sign then
    text = '-' .. text
  end
  return text
end

---@param value Sheet.Value
---@param code? string
---@return string
---@return string?
local function format_value (value, code)
  if value == nil then
    return '', nil
  end
  local t = type (value)
  if t == 'boolean' then
    return value and 'TRUE' or 'FALSE', nil
  end
  if t == 'table' then
    return (value --[[@as Sheet.Error]]).code, nil
  end
  local parsed = compile (code)
  if t == 'string' then
    local text = value --[[@as string]]
    if text == '' or not parsed or not parsed.text then
      return text, nil
    end
    return render_text (parsed.text, text), parsed.text.color
  end
  -- A float, so that negating the smallest integer cannot wrap around.
  local n = value --[[@as number]] + 0.0
  if n ~= n or n == math.huge or n == -math.huge then
    return '#NUM!', nil
  end
  if not parsed then
    return general_text (n), nil
  end
  local section, own_sign = choose (parsed, n)
  if not section then
    return general_text (n), nil
  end
  return render_number (section, n, own_sign), section.color
end

---The text a cell shows for a value, and a CSS colour when the format picks one, as
---`[Red]` does. A nil or `General` code shows numbers with up to 10 significant digits.
---A code that does not read shows as General.
---@param value Sheet.Value
---@param code? string
---@return string
---@return string?
function M.format (value, code)
  local ok, text, color = pcall (format_value, value, code)
  if not ok then
    return format_value (value, nil)
  end
  return text, color
end

---------------------------------------------------------------------------------------------
-- Reading typed text
---------------------------------------------------------------------------------------------

---@param n number
---@param negative boolean
---@return number
local function finish (n, negative)
  local v = n + 0.0
  if negative then
    v = -v
  end
  if v == 0 then
    return 0.0
  end
  return v
end

---@param text string
---@return boolean
local function is_plain (text)
  return string.match (text, '^%d+%.?%d*$') ~= nil
    or string.match (text, '^%.%d+$') ~= nil
end

---True when the commas of a number group its digits in threes, as in 1,234,567.
---@param text string
---@return boolean
local function is_grouped (text)
  local whole = string.match (text, '^([%d,]+)%.?%d*$')
  if not whole then
    return false
  end
  while string.match (whole, ',%d%d%d$') do
    whole = string.sub (whole, 1, -5)
  end
  return string.match (whole, '^%d%d?%d?$') ~= nil
end

---Reads a number as typed: `1,234.5`, `(12)`, `$5.50`, `-$5`, `15%` or `1.5E3`. Returns the
---number and the format the typing implies.
---@param text string
---@return number?
---@return string?
local function read_number (text)
  local body = text
  local negative = false
  local inner = string.match (body, '^%((.*)%)$')
  if inner then
    negative = true
    body = trim (inner)
  end
  local sign = string.match (body, '^[+-]')
  if sign then
    if inner then
      return nil, nil
    end
    negative = sign == '-'
    body = string.sub (body, 2)
  end
  local currency = string.sub (body, 1, 1) == '$'
  if currency then
    body = string.match (body, '^%$%s*(.*)$')
    local after = string.match (body, '^[+-]')
    if after then
      if sign or inner then
        return nil, nil
      end
      negative = after == '-'
      body = string.sub (body, 2)
    end
  end
  local percent = string.sub (body, -1) == '%'
  if percent then
    if currency then
      return nil, nil
    end
    body = string.sub (body, 1, -2)
  end
  local mantissa, exponent = string.match (body, '^([%d%.]+)[eE]([+-]?%d+)$')
  if mantissa then
    local n = tonumber (mantissa .. 'e' .. exponent)
    if currency or percent or not is_plain (mantissa) or not n then
      return nil, nil
    end
    return finish (n, negative), '0.00E+00'
  end
  local grouped = string.find (body, ',', 1, true) ~= nil
  if grouped and not is_grouped (body) then
    return nil, nil
  end
  local plain = string.gsub (body, ',', '')
  if not is_plain (plain) then
    return nil, nil
  end
  -- Shifting the point in the text keeps 12.5% exact, where multiplying by 0.01 would not.
  local n = tonumber (percent and plain .. 'e-2' or plain)
  if not n then
    return nil, nil
  end
  local decimals = #(string.match (plain, '%.(%d*)$') or '')
  local code ---@type string?
  if currency then
    code = decimals > 0 and '$#,##0.00' or '$#,##0'
  elseif percent then
    code = (grouped and '#,##0' or '0')
      .. (decimals > 0 and '.' .. string.rep ('0', decimals) or '')
      .. '%'
  elseif grouped then
    code = decimals > 0 and '#,##0.00' or '#,##0'
  end
  return finish (n, negative), code
end

---Reads a whole number and a fraction, such as `1 1/2`.
---@param text string
---@return number?
---@return string?
local function read_fraction (text)
  local sign, whole, top, bottom =
    string.match (text, '^([+-]?)(%d+)%s+(%d+)/(%d+)$')
  if not whole then
    return nil, nil
  end
  local num, den = tonumber (top), tonumber (bottom)
  if not num or not den or den == 0 or num >= den then
    return nil, nil
  end
  local code = #bottom == 1 and '# ?/?'
    or #bottom == 2 and '# ??/??'
    or '# ???/???'
  return finish (tonumber (whole) + num / den, sign == '-'), code
end

---What typing `text` into a cell stores, as spreadsheets guess it. Returns the value, and a
---format code when the typing implies one: `$1,200` stores 1200 with `$#,##0`, `15%` stores
---0.15 with `0%`, and `9/29/2026` stores a serial date with `m/d/yyyy`. A leading `'` keeps
---the rest as text. `clock` gives the date now as a serial, for dates typed without a year.
---@param text string
---@param clock? fun(): number
---@return Sheet.Value
---@return string?
function M.parse_input (text, clock)
  if text == '' then
    return nil, nil
  end
  if string.sub (text, 1, 1) == "'" then
    return string.sub (text, 2), nil
  end
  local s = trim (text)
  if s == '' then
    return text, nil
  end
  local upper = string.upper (s)
  if upper == 'TRUE' then
    return true, nil
  elseif upper == 'FALSE' then
    return false, nil
  end
  local n, code = read_number (s)
  if n then
    return n, code
  end
  n, code = read_fraction (s)
  if n then
    return n, code
  end
  n, code = calendar.read (s, clock or now)
  if n then
    return n, code
  end
  return text, nil
end

---------------------------------------------------------------------------------------------
-- The format menu
---------------------------------------------------------------------------------------------

M.presets = {
  { id = 'general', label = 'Automatic', code = 'General' },
  { id = 'text', label = 'Plain text', code = '@' },
  { id = 'number', label = 'Number', code = '#,##0.00' },
  { id = 'percent', label = 'Percent', code = '0.00%' },
  { id = 'scientific', label = 'Scientific', code = '0.00E+00' },
  {
    id = 'accounting',
    label = 'Accounting',
    code = '_($* #,##0.00_);_($* (#,##0.00);_($* "-"??_);_(@_)',
  },
  { id = 'financial', label = 'Financial', code = '#,##0.00;(#,##0.00)' },
  { id = 'currency', label = 'Currency', code = '$#,##0.00' },
  { id = 'currency_rounded', label = 'Currency rounded', code = '$#,##0' },
  { id = 'date', label = 'Date', code = 'm/d/yyyy' },
  { id = 'long_date', label = 'Long date', code = 'dddd, mmmm d, yyyy' },
  { id = 'time', label = 'Time', code = 'h:mm:ss AM/PM' },
  { id = 'datetime', label = 'Date time', code = 'm/d/yyyy h:mm:ss' },
  { id = 'duration', label = 'Duration', code = '[h]:mm:ss' },
}

---@param section Sheet.FormatSection
---@return boolean
local function shows_currency (section)
  for _, t in ipairs (section.tokens) do
    if t.currency then
      return true
    end
    if t.kind == 'lit' then
      for _, symbol in ipairs (CURRENCY) do
        if string.find (t.text, symbol, 1, true) then
          return true
        end
      end
    end
  end
  return false
end

---@param parsed? Sheet.FormatCode
---@return Sheet.FormatKind
local function kind_of (parsed)
  if not parsed then
    return 'general'
  end
  local first = parsed.numbers[1]
  if not first then
    return 'text'
  end
  if first.role == 'general' then
    return 'general'
  end
  if first.role == 'date' then
    if first.elapsed then
      return 'duration'
    elseif first.calendar and (first.clock or first.precision > 0) then
      return 'datetime'
    elseif first.calendar then
      return 'date'
    end
    return 'time'
  end
  if first.layout == 'sci' then
    return 'scientific'
  elseif first.layout == 'frac' then
    return 'fraction'
  elseif first.percent > 0 then
    return 'percent'
  elseif has (first, 'fill') and has (first, 'skip') then
    return 'accounting'
  elseif shows_currency (first) then
    return 'currency'
  end
  return 'number'
end

---What a code shows: 'general', 'number', 'currency', 'accounting', 'percent', 'scientific',
---'fraction', 'date', 'time', 'datetime', 'duration' or 'text'. The first section decides.
---@param code? string
---@return Sheet.FormatKind
function M.kind (code)
  return kind_of (compile (code))
end

---Adds or removes decimal places in one section. The zero section of Accounting, `"-"??`,
---holds one `?` for each decimal place, so it gains or loses a `?`.
---@param section Sheet.FormatSection
---@param index integer
---@param delta integer
---@return string
local function adjust_section (section, index, delta)
  local tokens = section.tokens
  local srcs = {} ---@type string[]
  for k, t in ipairs (tokens) do
    srcs[k] = t.src
  end
  local ints, fracs = section.ints, section.fracs
  if section.role ~= 'number' or section.layout == 'frac' then
    return table.concat (srcs)
  end
  local marks = #ints > 0 and not section.point and index == 3
  for _, at in ipairs (ints) do
    if tokens[at].text ~= '?' then
      marks = false
    end
  end
  if marks then
    if delta > 0 then
      srcs[ints[#ints]] = srcs[ints[#ints]] .. string.rep ('?', delta)
    else
      for k = #ints, math.max (1, #ints + delta + 1), -1 do
        srcs[ints[k]] = ''
      end
    end
  elseif delta > 0 then
    local zeros = string.rep ('0', delta)
    if #fracs > 0 then
      srcs[fracs[#fracs]] = srcs[fracs[#fracs]] .. zeros
    elseif section.point then
      srcs[section.point] = srcs[section.point] .. zeros
    elseif #ints > 0 then
      srcs[ints[#ints]] = srcs[ints[#ints]] .. '.' .. zeros
    end
  else
    local drop = math.min (-delta, #fracs)
    for k = #fracs, #fracs - drop + 1, -1 do
      srcs[fracs[k]] = ''
    end
    if drop == #fracs and section.point then
      srcs[section.point] = ''
    end
  end
  return table.concat (srcs)
end

---The code with `delta` more decimal places, or fewer when `delta` is negative, in every
---number section. From General it starts from the decimals `value` shows. It never goes
---below zero decimals. Dates, times, fractions and text keep their code.
---@param code? string
---@param delta integer
---@param value? Sheet.Value
---@return string
function M.adjust_decimals (code, delta, value)
  local parsed = compile (code)
  if not parsed then
    local text = type (value) == 'number'
        and general_text (value --[[@as number]])
      or '0'
    local digits, exponent = string.match (text, '^%-?([%d%.]+)(E?)')
    local decimals = #(string.match (digits or '', '%.(%d+)') or '')
    local places = math.max (0, decimals + delta)
    local out = places > 0 and '0.' .. string.rep ('0', places) or '0'
    return exponent == 'E' and out .. 'E+00' or out
  end
  local parts = {} ---@type string[]
  for k, section in ipairs (parsed.sections) do
    parts[k] = adjust_section (section, k, delta)
  end
  return table.concat (parts, ';')
end

---Where a value sits in its cell when the cell sets no alignment: numbers and dates on the
---right, text on the left, and TRUE, FALSE and errors in the centre. Under the `@` format
---everything sits on the left.
---@param value Sheet.Value
---@param code? string
---@return Sheet.Align
function M.align (value, code)
  if M.kind (code) == 'text' then
    return 'left'
  end
  local t = type (value)
  if t == 'number' then
    return 'right'
  elseif t == 'boolean' or t == 'table' then
    return 'center'
  end
  return 'left'
end

return M
