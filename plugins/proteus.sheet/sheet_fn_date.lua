-- sheet_fn_date: the date and time functions of the Sheet app's formulas: making dates and
-- times and taking them apart, weeks, months and workdays, the days between two dates, and
-- dates read from text. sheet_formula loads the module.

---@param K Sheet.FormulaKit
return function (K)
  local define, raise, LAST_DAY = K.define, K.raise, K.LAST_DAY
  local value_of, int_of = K.value_of, K.int_of
  local opt_int, to_number, to_text, trunc =
    K.opt_int, K.to_number, K.to_text, K.trunc
  local now, today_clock, date_arg = K.now, K.today_clock, K.date_arg
  local ymd, make_date, weekday0, date_parts =
    K.ymd, K.make_date, K.weekday0, K.date_parts
  local is_leap, days_in_month = K.is_leap, K.days_in_month
  local holidays, is_weekend = K.holidays, K.is_weekend
  local parse_datetime = K.parse_datetime

  -------------------------------------------------------------------------------------------
  -- Date
  -------------------------------------------------------------------------------------------

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
        local parts = { date_parts (date_arg (v[1], ctx)) }
        return parts[part]
      end,
    }
  end

  define (
    'YEAR',
    'Date',
    'YEAR(date)',
    'Gives the year of a date.',
    date_part (1)
  )
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
      if
        (d1 == 31 and d2 == 31) or (m1 == 2 and m2 == 2 and last1 and last2)
      then
        d1, d2 = 30, 30
      elseif d1 == 31 or (m1 == 2 and last1) then
        d1 = 30
      elseif d1 == 30 and d2 == 31 then
        d2 = 30
      end
      return ((y2 - y1) * 360 + (m2 - m1) * 30 + (d2 - d1)) / 360
    elseif basis == 1 then
      -- Actual days over the actual length of the year, as Excel works it out.
      if
        y1 == y2 or (y2 == y1 + 1 and (m1 > m2 or (m1 == m2 and d1 >= d2)))
      then
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
end
