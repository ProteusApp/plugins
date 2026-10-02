-- sheet_calendar: dates and times for the Sheet app. It counts days, and it reads dates and
-- times from text. Typing into a cell and the formulas that read text, such as DATEVALUE,
-- both read through it, so the two accept the same dates. It draws nothing and calls no host
-- function.
--
-- Dates and times are serial numbers of days since 1899-12-30, as spreadsheets store them.
-- The calendar follows Excel, which counts a 29 February 1900: serial 60 is that day, and
-- serial 61 is 1 March 1900.

---@class Sheet.CalendarModule
---@field MONTHS string[] The month names, from January.
local M = {}

-- Serial day numbers count from 1899-12-30, so 1970-01-01 is 25569.
local EPOCH = 25569
M.EPOCH = EPOCH

M.MONTHS = {
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
}

local MONTH_DAYS = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

---------------------------------------------------------------------------------------------
-- Counting days
---------------------------------------------------------------------------------------------

---True for a leap year of the ordinary calendar, where 1900 is not one.
---@param y integer
---@return boolean
function M.is_leap (y)
  return y % 4 == 0 and (y % 100 ~= 0 or y % 400 == 0)
end

---The days in a month of the ordinary calendar.
---@param y integer
---@param m integer
---@return integer
function M.days_in_month (y, m)
  if m == 2 then
    return M.is_leap (y) and 29 or 28
  end
  return MONTH_DAYS[m]
end

---Days since 1970-01-01 for a date in the ordinary calendar.
---@param y integer
---@param m integer
---@param d integer
---@return integer
local function days_from_civil (y, m, d)
  local year = m <= 2 and y - 1 or y
  local era = math.floor (year / 400)
  local yoe = year - era * 400
  local mp = (m + 9) % 12
  local doy = math.floor ((153 * mp + 2) / 5) + d - 1
  local doe = yoe * 365 + math.floor (yoe / 4) - math.floor (yoe / 100) + doy
  return era * 146097 + doe - 719468
end

---The date in the ordinary calendar for a count of days since 1970-01-01.
---@param z integer
---@return integer y
---@return integer m
---@return integer d
local function civil_from_days (z)
  local shifted = z + 719468
  local era = math.floor (shifted / 146097)
  local doe = shifted - era * 146097
  local yoe = math.floor (
    (
      doe
      - math.floor (doe / 1460)
      + math.floor (doe / 36524)
      - math.floor (doe / 146096)
    ) / 365
  )
  local doy = doe - (365 * yoe + math.floor (yoe / 4) - math.floor (yoe / 100))
  local mp = math.floor ((5 * doy + 2) / 153)
  local d = doy - math.floor ((153 * mp + 2) / 5) + 1
  local m = mp < 10 and mp + 3 or mp - 9
  local y = yoe + era * 400
  if m <= 2 then
    y = y + 1
  end
  return y, m, d
end

---The date of a serial day. Day 0 shows as 1900-01-00 and day 60 as 1900-02-29, as in Excel,
---so the days before 1 March 1900 sit one day after their true date.
---@param day integer
---@return integer y
---@return integer m
---@return integer d
function M.day_date (day)
  if day == 60 then
    return 1900, 2, 29
  end
  if day == 0 then
    return 1900, 1, 0
  end
  if day < 60 then
    return civil_from_days (day + 1 - EPOCH)
  end
  return civil_from_days (day - EPOCH)
end

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
  local year = y + math.floor ((m - 1) / 12)
  local month = (m - 1) % 12 + 1
  local first = days_from_civil (year, month, 1) + EPOCH
  if first < 61 then
    first = first - 1
  end
  local seconds = (h or 0) * 3600 + (mi or 0) * 60 + (s or 0)
  return first + d - 1 + seconds / 86400
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
  local total = math.floor (serial * 86400 + 0.5)
  local day = math.floor (total / 86400)
  local secs = total - day * 86400
  local y, m, d = M.day_date (day)
  return y,
    m,
    d,
    math.floor (secs / 3600),
    math.floor (secs / 60) % 60,
    secs % 60,
    (day - 1) % 7 + 1
end

---------------------------------------------------------------------------------------------
-- Reading dates and times
---------------------------------------------------------------------------------------------

---@type table<string, integer>
local MONTH_NUMBERS = { sept = 9 }
for k, name in ipairs (M.MONTHS) do
  MONTH_NUMBERS[string.lower (name)] = k
  MONTH_NUMBERS[string.lower (string.sub (name, 1, 3))] = k
end

---@param text string
---@return string
local function trim (text)
  return string.match (text, '^%s*(.-)%s*$')
end

---The year of a clock, for a date typed without one. With no clock there is no such year.
---@param clock? fun(): number
---@return integer?
local function this_year (clock)
  if not clock then
    return nil
  end
  local y = M.date_parts (clock ())
  return y
end

---A year as written. Two digits mean 1930 to 2029, as in Excel. Other lengths are refused.
---@param text string
---@return integer?
local function year_of (text)
  local n = math.tointeger (tonumber (text))
  if not n then
    return nil
  end
  if #text == 4 then
    return n
  elseif #text == 2 then
    return n < 30 and 2000 + n or 1900 + n
  end
  return nil
end

---@param text string
---@return string
local function year_code (text)
  return #text == 4 and 'yyyy' or 'yy'
end

---@param text string
---@return string
local function day_code (text)
  return string.sub (text, 1, 1) == '0' and #text == 2 and 'dd' or 'd'
end

---The codes for a written month and day. Both pad to two digits when either was written with
---a leading zero, or when both were written with two digits.
---@param month string
---@param day string
---@return string
---@return string
local function pair_codes (month, day)
  local padded = (#month == 2 and #day == 2)
    or string.sub (month, 1, 1) == '0' and #month == 2
    or string.sub (day, 1, 1) == '0' and #day == 2
  if padded then
    return #month == 2 and 'mm' or 'm', #day == 2 and 'dd' or 'd'
  end
  return 'm', 'd'
end

---A month name or its first three letters, and the code that shows it the same way.
---@param word string
---@return integer?
---@return string
local function month_of (word)
  local lower = string.lower (word)
  local month = MONTH_NUMBERS[lower]
  if not month then
    return nil, ''
  end
  return month, (#lower > 3 and lower ~= 'sept') and 'mmmm' or 'mmm'
end

---The separator a format code shows for the one written between the parts of a date.
---@param sep string
---@return string
local function sep_code (sep)
  return string.find (sep, '-', 1, true) and '-' or ' '
end

---A serial date when the parts make a real day from 1900 to 9999. 29 February 1900 counts,
---as in Excel.
---@param y integer?
---@param m integer?
---@param d integer?
---@param code string
---@return number?
---@return string?
local function make_date (y, m, d, code)
  if not y or not m or not d or y < 1900 or y > 9999 or m < 1 or m > 12 then
    return nil, nil
  end
  local last = M.days_in_month (y, m)
  if y == 1900 and m == 2 then
    last = 29
  end
  if d < 1 or d > last then
    return nil, nil
  end
  return M.serial (y, m, d), code
end

---Reads a date, in the US order of month then day, or year first: `2026-09-29`,
---`2026/9/29`, `2026.09.29`, `9/29/2026`, `9/29/26`, `9/2026`, `9/29`, `29-Sep-2026`,
---`29 Sep 2026`, `29-Sep`, `Sep 29, 2026`, `Sep. 29`, `Sep 2026`. A date with no day is the
---first of the month, and a date with no year takes the year of `clock`, or is refused when
---there is no clock. Returns the serial and the format code the text was written in.
---@param text string
---@param clock? fun(): number
---@return number?
---@return string?
function M.read_date (text, clock)
  local int = math.tointeger
  do
    -- 2026-09-29, 2026/9/29 and 2026.09.29
    local y, sep, m, d =
      string.match (text, '^(%d%d%d%d)([-/%.])(%d%d?)%2(%d%d?)$')
    if y then
      local mc, dc = pair_codes (m, d)
      -- A point in a format code is a decimal point, so a dotted date shows with dashes.
      local shown = sep == '.' and '-' or sep
      return make_date (
        int (tonumber (y)),
        int (tonumber (m)),
        int (tonumber (d)),
        'yyyy' .. shown .. mc .. shown .. dc
      )
    end
  end
  do
    -- 9/29/2026 and 9/29/26
    local m, sep, d, y = string.match (text, '^(%d%d?)([-/])(%d%d?)%2(%d+)$')
    if m then
      local mc, dc = pair_codes (m, d)
      return make_date (
        year_of (y),
        int (tonumber (m)),
        int (tonumber (d)),
        mc .. sep .. dc .. sep .. year_code (y)
      )
    end
  end
  do
    -- 9/2026 is the first of the month.
    local m, sep, y = string.match (text, '^(%d%d?)([-/])(%d%d%d%d)$')
    if m then
      local mc = pair_codes (m, '1')
      return make_date (
        int (tonumber (y)),
        int (tonumber (m)),
        1,
        mc .. sep .. 'yyyy'
      )
    end
  end
  do
    -- 9/29 is this year.
    local m, sep, d = string.match (text, '^(%d%d?)([-/])(%d%d?)$')
    if m then
      local mc, dc = pair_codes (m, d)
      return make_date (
        this_year (clock),
        int (tonumber (m)),
        int (tonumber (d)),
        mc .. sep .. dc
      )
    end
  end
  do
    -- 29-Sep-2026, 29 Sep 2026 and 29 Sept. 2026
    local d, sep, name, y =
      string.match (text, '^(%d%d?)([%- ]+)(%a+)%.?[%-, ]+(%d+)$')
    if d then
      local m, mc = month_of (name)
      local s = sep_code (sep)
      return make_date (
        year_of (y),
        m,
        int (tonumber (d)),
        day_code (d) .. s .. mc .. s .. year_code (y)
      )
    end
  end
  do
    -- 29-Sep is this year.
    local d, sep, name = string.match (text, '^(%d%d?)([%- ]+)(%a+)%.?$')
    if d then
      local m, mc = month_of (name)
      return make_date (
        this_year (clock),
        m,
        int (tonumber (d)),
        day_code (d) .. sep_code (sep) .. mc
      )
    end
  end
  do
    -- Sep 29, 2026, September 29 2026 and Sep. 29 2026
    local name, d, sep, y =
      string.match (text, '^(%a+)%.?[%- ]+(%d%d?)([, ]+)(%d+)$')
    if name then
      local m, mc = month_of (name)
      local comma = string.find (sep, ',', 1, true) and ', ' or ' '
      return make_date (
        year_of (y),
        m,
        int (tonumber (d)),
        mc .. ' ' .. day_code (d) .. comma .. year_code (y)
      )
    end
  end
  do
    -- Sep 29 is this year.
    local name, d = string.match (text, '^(%a+)%.?[%- ]+(%d%d?)$')
    if name then
      local m, mc = month_of (name)
      return make_date (
        this_year (clock),
        m,
        int (tonumber (d)),
        mc .. ' ' .. day_code (d)
      )
    end
  end
  do
    -- Sep 2026 and Sep-2026 are the first of the month.
    local name, sep, y = string.match (text, '^(%a+)%.?([%- ]+)(%d%d%d%d)$')
    if name then
      local m, mc = month_of (name)
      return make_date (int (tonumber (y)), m, 1, mc .. sep_code (sep) .. 'yyyy')
    end
  end
  return nil, nil
end

---@param h integer
---@param mi integer
---@param s number
---@return number
local function day_fraction (h, mi, s)
  return (h * 3600 + mi * 60 + s) / 86400
end

---Reads a time: `14:30`, `14:30:15`, `14:30:15.5`, `2:30 PM`, `2 pm`, `9 a.m.`, minutes and
---seconds such as `30:15.5`, or a count of hours past 24 such as `36:00`, which is a duration.
---Returns the fraction of a day and the format code the text was written in.
---@param text string
---@return number?
---@return string?
function M.read_time (text)
  local body, marker = string.match (text, '^([%d:%.]+)%s*([aApP])%.?[mM]?%.?$')
  local hs, ms, ss, fs ---@type string?, string?, string?, string?
  local minutes_only = false
  if body then
    hs = string.match (body, '^(%d%d?)$')
    if not hs then
      hs, ms = string.match (body, '^(%d%d?):(%d%d?)$')
    end
    if not hs then
      hs, ms, ss = string.match (body, '^(%d%d?):(%d%d?):(%d%d?)$')
    end
    if not hs then
      hs, ms, ss, fs = string.match (body, '^(%d%d?):(%d%d?):(%d%d?)%.(%d+)$')
    end
  else
    -- 30:15.5 is minutes and seconds.
    ms, ss, fs = string.match (text, '^(%d+):(%d%d?)%.(%d+)$')
    if ms then
      hs = '0'
      minutes_only = true
    else
      hs, ms, ss, fs = string.match (text, '^(%d+):(%d%d?):(%d%d?)%.(%d+)$')
    end
    if not hs then
      hs, ms, ss = string.match (text, '^(%d+):(%d%d?):(%d%d?)$')
    end
    if not hs then
      hs, ms = string.match (text, '^(%d+):(%d%d?)$')
    end
  end
  if not hs or #hs > 5 then
    return nil, nil
  end
  local h = tonumber (hs) --[[@as integer]]
  local mi = tonumber (ms or '0') --[[@as integer]]
  local s = tonumber (ss or '0') --[[@as number]]
  if mi > 59 or s > 59 then
    return nil, nil
  end
  local lead = string.sub (hs, 1, 1) == '0' and #hs == 2 and 'hh' or 'h'
  local decimals = fs and '.' .. string.rep ('0', math.min (#fs, 3)) or ''
  if fs then
    s = s + tonumber ('0.' .. fs)
  end
  if marker then
    if h > 12 then
      return nil, nil
    end
    local hour = h % 12 + (string.lower (marker) == 'p' and 12 or 0)
    local code = lead
      .. (ms and ':mm' or '')
      .. (ss and ':ss' .. decimals or '')
      .. ' AM/PM'
    return day_fraction (hour, mi, s), code
  end
  local code = (h >= 24 and '[h]' or lead) .. ':mm'
  if minutes_only then
    code = 'mm:ss'
  elseif ss then
    code = code .. ':ss'
  end
  return day_fraction (h, mi, s), code .. decimals
end

---Reads a date, a time, or a date and a time of day such as `2026-09-29 14:30`,
---`2026-09-29T14:30` or `Sep 29, 2026, 2:30 PM`. Returns the serial and the format code the
---text was written in. `clock` gives the year of a date written without one.
---@param text string
---@param clock? fun(): number
---@return number?
---@return string?
function M.read (text, clock)
  local s = trim (text)
  if s == '' then
    return nil, nil
  end
  local day, code = M.read_date (s, clock)
  if day then
    return day, code
  end
  local time, time_code = M.read_time (s)
  if time then
    return time, time_code
  end
  local splits = {} ---@type { [1]: string, [2]: string }[]
  local iso, clock_text =
    string.match (s, '^(%d%d%d%d%-%d%d?%-%d%d?)[Tt](%d.*)$')
  if iso then
    splits[1] = { iso, clock_text }
  end
  local from = 1
  while true do
    local at = string.find (s, ' ', from, true)
    if not at then
      break
    end
    local head = trim (string.sub (s, 1, at - 1))
    -- Sep 29, 2026, 2:30 PM puts a comma before the time.
    head = string.match (head, '^(.-),?$')
    splits[#splits + 1] = { head, trim (string.sub (s, at + 1)) }
    from = at + 1
  end
  for _, split in ipairs (splits) do
    local date, date_code = M.read_date (split[1], clock)
    if date then
      local part, part_code = M.read_time (split[2])
      if part and part < 1 then
        return date + part, date_code .. ' ' .. part_code
      end
    end
  end
  return nil, nil
end

return M
