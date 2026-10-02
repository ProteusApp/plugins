-- sheet_fn_finance: the money functions of the Sheet app's formulas. Loans and annuities
-- (PMT, FV, PV, NPER, RATE), NPV and IRR come first, then more money and date functions: cash
-- flows on dates (XNPV, XIRR), MIRR, depreciation (SLN, SYD, DB, DDB), interest rates (EFFECT,
-- NOMINAL), sums of payments (CUMIPMT, CUMPRINC), working days with any weekend
-- (NETWORKDAYS.INTL, WORKDAY.INTL) and the 360-day year of DAYS360. sheet_formula_kit loads it.

---@param K Sheet.FormulaKit
return function (K)
  local define, raise = K.define, K.raise
  local is_error, raise_value = K.is_error, K.raise_value
  local given, value_of, number_of, int_of =
    K.given, K.value_of, K.number_of, K.int_of
  local numbers, each, to_number, opt = K.numbers, K.each, K.to_number, K.opt
  local trunc, MANY, log = K.trunc, K.MANY, K.log
  local date_arg, ymd, weekday0, holidays =
    K.date_arg, K.ymd, K.weekday0, K.holidays
  local days_in_month, make_date = K.days_in_month, K.make_date

  -- The last day spreadsheets allow, 9999-12-31.
  local LAST_DAY = 2958465

  -------------------------------------------------------------------------------------------
  -- Financial
  -------------------------------------------------------------------------------------------

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

  -------------------------------------------------------------------------------------------
  -- Cash flows on dates
  -------------------------------------------------------------------------------------------

  ---The cash flows and their dates for XNPV and XIRR, as two lists of the same length.
  ---@param vnode Sheet.Node
  ---@param dnode Sheet.Node
  ---@param ctx Sheet.Context
  ---@return number[] flows
  ---@return number[] days
  local function dated_flows (vnode, dnode, ctx)
    local flows = {} ---@type number[]
    each (vnode, ctx, function (v)
      if is_error (v) then
        raise_value (v)
      end
      if type (v) ~= 'number' then
        raise ('#VALUE!')
      end
      flows[#flows + 1] = v --[[@as number]]
    end)
    local days = {} ---@type number[]
    each (dnode, ctx, function (v)
      if is_error (v) then
        raise_value (v)
      end
      days[#days + 1] = math.floor (date_arg (v, ctx))
    end)
    if #flows ~= #days or #flows < 2 then
      error (K.ERRORS['#NUM!'], 0)
    end
    for _, d in ipairs (days) do
      if d < days[1] then
        error (K.ERRORS['#NUM!'], 0)
      end
    end
    return flows, days
  end

  ---What dated cash flows are worth on the first date, at a yearly rate.
  ---@param rate number
  ---@param flows number[]
  ---@param days number[]
  ---@return number
  local function xnpv (rate, flows, days)
    local total = 0.0
    for i, x in ipairs (flows) do
      total = total + x / (1 + rate) ^ ((days[i] - days[1]) / 365)
    end
    return total
  end

  define (
    'XNPV',
    'Financial',
    'XNPV(rate, values, dates)',
    'Gives what cash flows on given dates are worth on the first date.',
    {
      min = 3,
      max = 3,
      run = function (args, ctx)
        local rate = number_of (args[1], ctx)
        if rate <= -1 then
          return raise ('#NUM!')
        end
        local flows, days = dated_flows (args[2], args[3], ctx)
        return xnpv (rate, flows, days)
      end,
    }
  )

  define (
    'XIRR',
    'Financial',
    'XIRR(values, dates, [guess])',
    'Gives the yearly rate at which cash flows on given dates are worth nothing.',
    {
      min = 2,
      max = 3,
      run = function (args, ctx)
        local flows, days = dated_flows (args[1], args[2], ctx)
        local up, down = false, false
        for _, x in ipairs (flows) do
          up = up or x > 0
          down = down or x < 0
        end
        if not up or not down then
          return raise ('#NUM!')
        end
        local guess = given (args[3]) and number_of (args[3], ctx) or 0.1
        local rate = solve (function (r)
          return xnpv (r, flows, days)
        end, guess)
        if not rate then
          return raise ('#NUM!')
        end
        return rate
      end,
    }
  )

  define (
    'MIRR',
    'Financial',
    'MIRR(values, finance_rate, reinvest_rate)',
    'Gives the rate of return of cash flows, with money borrowed and reinvested at given rates.',
    {
      min = 3,
      max = 3,
      run = function (args, ctx)
        local flows = numbers (args, ctx, 1, 1)
        local finance = number_of (args[2], ctx)
        local reinvest = number_of (args[3], ctx)
        local n = #flows
        local pv_out, fv_in = 0.0, 0.0
        for i, x in ipairs (flows) do
          if x < 0 then
            pv_out = pv_out + x / (1 + finance) ^ (i - 1)
          else
            fv_in = fv_in + x * (1 + reinvest) ^ (n - i)
          end
        end
        if pv_out == 0 or fv_in == 0 or n < 2 then
          return raise ('#DIV/0!')
        end
        return (-fv_in / pv_out) ^ (1 / (n - 1)) - 1
      end,
    }
  )

  -------------------------------------------------------------------------------------------
  -- Depreciation
  -------------------------------------------------------------------------------------------

  define (
    'SLN',
    'Financial',
    'SLN(cost, salvage, life)',
    'Gives the straight-line depreciation of an asset for one period.',
    {
      min = 3,
      max = 3,
      map = function (v)
        local cost, salvage, life =
          to_number (v[1]), to_number (v[2]), to_number (v[3])
        if life == 0 then
          return raise ('#DIV/0!')
        end
        return (cost - salvage) / life
      end,
    }
  )

  define (
    'SYD',
    'Financial',
    'SYD(cost, salvage, life, per)',
    "Gives the sum-of-years' digits depreciation of an asset for a period.",
    {
      min = 4,
      max = 4,
      map = function (v)
        local cost, salvage = to_number (v[1]), to_number (v[2])
        local life, per = to_number (v[3]), to_number (v[4])
        if life <= 0 or per <= 0 or per > life then
          return raise ('#NUM!')
        end
        return (cost - salvage) * (life - per + 1) * 2 / (life * (life + 1))
      end,
    }
  )

  define (
    'DDB',
    'Financial',
    'DDB(cost, salvage, life, period, [factor])',
    'Gives the double-declining balance depreciation of an asset for a period.',
    {
      min = 4,
      max = 5,
      map = function (v, n)
        local cost, salvage = to_number (v[1]), to_number (v[2])
        local life, period = to_number (v[3]), to_number (v[4])
        local factor = opt (v, n, 5, 2)
        if
          cost < 0
          or salvage < 0
          or life <= 0
          or period <= 0
          or period > life
          or factor <= 0
        then
          return raise ('#NUM!')
        end
        local rate = math.min (factor / life, 1)
        local prior ---@type number
        if period == math.floor (period) then
          local book = cost
          for _ = 1, period - 1 do
            book = book - math.max (0, math.min (book * rate, book - salvage))
          end
          prior = cost - book
        else
          -- A part period takes what the periods before it wrote off, by the formula.
          prior =
            math.min (cost * (1 - (1 - rate) ^ (period - 1)), cost - salvage)
        end
        return math.max (
          0,
          math.min ((cost - prior) * rate, cost - salvage - prior)
        )
      end,
    }
  )

  define (
    'DB',
    'Financial',
    'DB(cost, salvage, life, period, [month])',
    'Gives the fixed-declining balance depreciation of an asset for a period.',
    {
      min = 4,
      max = 5,
      map = function (v, n)
        local cost, salvage = to_number (v[1]), to_number (v[2])
        local life, period = trunc (to_number (v[3])), trunc (to_number (v[4]))
        local month = trunc (opt (v, n, 5, 12))
        local last = month < 12 and life + 1 or life
        if
          cost < 0
          or salvage < 0
          or life <= 0
          or period < 1
          or period > last
          or month < 1
          or month > 12
        then
          return raise ('#NUM!')
        end
        if cost == 0 then
          return 0
        end
        -- Excel rounds the rate to three decimals.
        local rate = math.floor (
          (1 - (salvage / cost) ^ (1 / life)) * 1000 + 0.5
        ) / 1000
        local total = cost * rate * month / 12
        if period == 1 then
          return total
        end
        local dep = 0.0
        for p = 2, period do
          if p == life + 1 then
            dep = (cost - total) * rate * (12 - month) / 12
          else
            dep = (cost - total) * rate
          end
          total = total + dep
        end
        return dep
      end,
    }
  )

  -------------------------------------------------------------------------------------------
  -- Rates and sums of payments
  -------------------------------------------------------------------------------------------

  define (
    'EFFECT',
    'Financial',
    'EFFECT(nominal_rate, npery)',
    'Gives the yearly rate a nominal rate comes to, compounded some times a year.',
    {
      min = 2,
      max = 2,
      map = function (v)
        local rate, n = to_number (v[1]), trunc (to_number (v[2]))
        if rate <= 0 or n < 1 then
          return raise ('#NUM!')
        end
        return (1 + rate / n) ^ n - 1
      end,
    }
  )

  define (
    'NOMINAL',
    'Financial',
    'NOMINAL(effect_rate, npery)',
    'Gives the nominal yearly rate for a yearly rate compounded some times a year.',
    {
      min = 2,
      max = 2,
      map = function (v)
        local rate, n = to_number (v[1]), trunc (to_number (v[2]))
        if rate <= 0 or n < 1 then
          return raise ('#NUM!')
        end
        return n * ((1 + rate) ^ (1 / n) - 1)
      end,
    }
  )

  ---CUMIPMT and CUMPRINC: the interest, or the principal, paid from one period to another.
  ---@param principal boolean
  ---@return Sheet.Function
  local function cumulative (principal)
    return {
      min = 6,
      max = 6,
      map = function (v)
        local rate, nper, pv =
          to_number (v[1]), to_number (v[2]), to_number (v[3])
        local first, last = trunc (to_number (v[4])), trunc (to_number (v[5]))
        local kind = trunc (to_number (v[6]))
        if
          rate <= 0
          or nper <= 0
          or pv <= 0
          or first < 1
          or last < first
          or last > nper
          or (kind ~= 0 and kind ~= 1)
        then
          return raise ('#NUM!')
        end
        local payment = pmt (rate, nper, pv, 0, kind)
        local total = 0.0
        for per = first, last do
          local interest = ipmt (rate, per, nper, pv, 0, kind)
          total = total + (principal and payment - interest or interest)
        end
        return total
      end,
    }
  end
  define (
    'CUMIPMT',
    'Financial',
    'CUMIPMT(rate, nper, pv, start_period, end_period, type)',
    'Gives the interest paid on a loan from one period to another.',
    cumulative (false)
  )
  define (
    'CUMPRINC',
    'Financial',
    'CUMPRINC(rate, nper, pv, start_period, end_period, type)',
    'Gives the principal paid on a loan from one period to another.',
    cumulative (true)
  )

  -------------------------------------------------------------------------------------------
  -- Dates
  -------------------------------------------------------------------------------------------

  ---The days of the week that are the weekend, by `weekday0`, from a weekend argument: a
  ---number from 1 to 7 for two days or from 11 to 17 for one, or text of seven 0s and 1s
  ---from Monday, where 1 is a weekend day.
  ---@param node Sheet.Node?
  ---@param ctx Sheet.Context
  ---@return table<integer, boolean>
  local function weekend_of (node, ctx)
    local out = {} ---@type table<integer, boolean>
    if not given (node) then
      out[0], out[6] = true, true
      return out
    end
    local v = value_of (node --[[@as Sheet.Node]], ctx)
    if type (v) == 'string' then
      if
        not string.match (v, '^[01][01][01][01][01][01][01]$')
        or v == '1111111'
      then
        return raise ('#VALUE!')
      end
      for i = 1, 7 do
        if string.sub (v, i, i) == '1' then
          out[i % 7] = true
        end
      end
      return out
    end
    local code = trunc (to_number (v))
    if code >= 1 and code <= 7 then
      out[(code + 5) % 7], out[(code + 6) % 7] = true, true
    elseif code >= 11 and code <= 17 then
      out[code - 11] = true
    else
      return raise ('#NUM!')
    end
    return out
  end

  define (
    'NETWORKDAYS.INTL',
    'Date',
    'NETWORKDAYS.INTL(start_date, end_date, [weekend], [holidays])',
    'Counts the working days from one date to another, with the weekend days given, less any holidays.',
    {
      min = 2,
      max = 4,
      run = function (args, ctx)
        local x = math.floor (date_arg (value_of (args[1], ctx), ctx))
        local y = math.floor (date_arg (value_of (args[2], ctx), ctx))
        local weekend = weekend_of (args[3], ctx)
        local off = holidays (args[4], ctx)
        local sign = x > y and -1 or 1
        local a, b = math.min (x, y), math.max (x, y)
        local days = b - a + 1
        local per_week = 0
        for w = 0, 6 do
          if not weekend[w] then
            per_week = per_week + 1
          end
        end
        local count = math.floor (days / 7) * per_week
        for k = 0, days % 7 - 1 do
          if not weekend[weekday0 (a + k)] then
            count = count + 1
          end
        end
        for day in pairs (off) do
          if day >= a and day <= b and not weekend[weekday0 (day)] then
            count = count - 1
          end
        end
        return sign * count
      end,
    }
  )

  define (
    'WORKDAY.INTL',
    'Date',
    'WORKDAY.INTL(start_date, days, [weekend], [holidays])',
    'Gives the date a number of working days before or after a date, with the weekend days given.',
    {
      min = 2,
      max = 4,
      run = function (args, ctx)
        local day = math.floor (date_arg (value_of (args[1], ctx), ctx))
        local left = int_of (args[2], ctx)
        local weekend = weekend_of (args[3], ctx)
        local off = holidays (args[4], ctx)
        if math.abs (left) > LAST_DAY then
          return raise ('#NUM!')
        end
        local step = left < 0 and -1 or 1
        left = math.abs (left)
        while left > 0 do
          day = day + step
          if day < 0 or day > LAST_DAY then
            return raise ('#NUM!')
          end
          if not weekend[weekday0 (day)] and not off[day] then
            left = left - 1
          end
        end
        return day
      end,
    }
  )

  define (
    'DAYS360',
    'Date',
    'DAYS360(start_date, end_date, [method])',
    'Counts the days between two dates in a year of twelve 30-day months.',
    {
      min = 2,
      max = 3,
      run = function (args, ctx)
        local a = math.floor (date_arg (value_of (args[1], ctx), ctx))
        local b = math.floor (date_arg (value_of (args[2], ctx), ctx))
        local europe = given (args[3]) and K.bool_of (args[3], ctx)
        local y1, m1, d1 = ymd (a)
        local y2, m2, d2 = ymd (b)
        if europe then
          d1 = math.min (d1, 30)
          d2 = math.min (d2, 30)
        else
          -- The US rule: the last day of the starting month counts as the 30th, and a 31st
          -- at the end counts as the 1st of the next month unless the start is the 30th.
          if d1 == days_in_month (y1, m1) then
            d1 = 30
          end
          if d2 == 31 then
            if d1 < 30 then
              local next_day = make_date (y2, m2 + 1, 1)
              y2, m2, d2 = ymd (next_day)
            else
              d2 = 30
            end
          end
        end
        return (y2 - y1) * 360 + (m2 - m1) * 30 + (d2 - d1)
      end,
    }
  )
end
