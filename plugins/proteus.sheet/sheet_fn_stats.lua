-- sheet_fn_stats: the statistics of the Sheet app's formulas. Averages, counts, ranks,
-- percentiles, spreads and straight-line fits come first. SUBTOTAL and AGGREGATE leave
-- out hidden rows, errors and other subtotals. The distributions (normal, t, chi-squared,
-- binomial and Poisson) rest on the gamma and beta functions, worked out to about 15 digits.
-- The rest are the summaries and fits spreadsheets have: GEOMEAN, SKEW, LINEST, FREQUENCY and
-- their kin. sheet_formula loads the module.

---A line, plane or curve fitted to data by least squares, for LINEST, TREND and GROWTH.
---@class Sheet.Fit
---@field coef number[] The intercept first, then one factor for each x.
---@field n integer How many points.
---@field k integer How many x.
---@field const boolean False when the intercept is held at 0.
---@field inverse number[][] The inverse of XᵀX, for the standard errors.
---@field ss_reg number
---@field ss_resid number

---@param K Sheet.FormulaKit
return function (K)
  local define, raise, raise_value = K.define, K.raise, K.raise_value
  local ERRORS, MANY = K.ERRORS, K.MANY
  local is_error, is_grid = K.is_error, K.is_grid
  local dims, grid_at, new_array = K.dims, K.grid_at, K.new_array
  local grid_or_value, reference = K.grid_or_value, K.reference
  local given, int_of, number_of, bool_of =
    K.given, K.int_of, K.number_of, K.bool_of
  local numbers, paired, each = K.numbers, K.paired, K.each
  local to_number = K.to_number
  local trunc, total_of, variance, percentile =
    K.trunc, K.total_of, K.variance, K.percentile
  local clean = K.clean
  local each_match, line_fit = K.each_match, K.fit
  local num_compare, text_number = K.num_compare, K.text_number

  local exp, log, sqrt, abs = math.exp, math.log, math.sqrt, math.abs
  local PI = math.pi
  -- The smallest number the continued fractions divide by.
  local TINY = 1e-300
  local EPS = 1e-16

  -------------------------------------------------------------------------------------------
  -- Statistics
  -------------------------------------------------------------------------------------------

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
        local slope = line_fit (paired (args[1], args[2], ctx))
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
        local _, intercept = line_fit (paired (args[1], args[2], ctx))
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
      local slope, intercept = line_fit (paired (args[2], args[3], ctx))
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

  -------------------------------------------------------------------------------------------
  -- Special functions
  -------------------------------------------------------------------------------------------

  -- Lanczos's coefficients for g = 7, good to about 15 digits.
  local LANCZOS = {
    0.99999999999980993,
    676.5203681218851,
    -1259.1392167224028,
    771.32342877765313,
    -176.61502916214059,
    12.507343278686905,
    -0.13857109526572012,
    9.9843695780195716e-6,
    1.5056327351493116e-7,
  }

  ---The natural log of the gamma function, for x above 0.
  ---@param x number
  ---@return number
  local function log_gamma (x)
    if x < 0.5 then
      return log (PI / abs (math.sin (PI * x))) - log_gamma (1 - x)
    end
    local z = x - 1
    local a = LANCZOS[1]
    local t = z + 7.5
    for i = 1, 8 do
      a = a + LANCZOS[i + 1] / (z + i)
    end
    return 0.5 * log (2 * PI) + (z + 0.5) * log (t) - t + log (a)
  end

  ---The regularized incomplete gamma functions P(a, x) and Q(a, x) = 1 - P(a, x), each
  ---worked out on its own so a small tail keeps its digits.
  ---@param a number
  ---@param x number
  ---@return number p
  ---@return number q
  local function gamma_pq (a, x)
    if x <= 0 then
      return 0, 1
    end
    local front = exp (-x + a * log (x) - log_gamma (a))
    if x < a + 1 then
      local ap, term = a, 1 / a
      local sum = term
      for _ = 1, 10000 do
        ap = ap + 1
        term = term * x / ap
        sum = sum + term
        if abs (term) < abs (sum) * EPS then
          break
        end
      end
      local p = sum * front
      return p, 1 - p
    end
    local b = x + 1 - a
    local c, d = 1 / TINY, 1 / b
    local h = d
    for i = 1, 10000 do
      local an = -i * (i - a)
      b = b + 2
      d = an * d + b
      if abs (d) < TINY then
        d = TINY
      end
      c = b + an / c
      if abs (c) < TINY then
        c = TINY
      end
      d = 1 / d
      local del = d * c
      h = h * del
      if abs (del - 1) < EPS then
        break
      end
    end
    local q = front * h
    return 1 - q, q
  end

  ---The continued fraction of the incomplete beta function, by Lentz's method.
  ---@param a number
  ---@param b number
  ---@param x number
  ---@return number
  local function beta_cf (a, b, x)
    local qab, qap, qam = a + b, a + 1, a - 1
    local c, d = 1, 1 - qab * x / qap
    if abs (d) < TINY then
      d = TINY
    end
    d = 1 / d
    local h = d
    for m = 1, 10000 do
      local m2 = 2 * m
      local aa = m * (b - m) * x / ((qam + m2) * (a + m2))
      d = 1 + aa * d
      if abs (d) < TINY then
        d = TINY
      end
      c = 1 + aa / c
      if abs (c) < TINY then
        c = TINY
      end
      d = 1 / d
      h = h * d * c
      aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2))
      d = 1 + aa * d
      if abs (d) < TINY then
        d = TINY
      end
      c = 1 + aa / c
      if abs (c) < TINY then
        c = TINY
      end
      d = 1 / d
      local del = d * c
      h = h * del
      if abs (del - 1) < EPS then
        break
      end
    end
    return h
  end

  ---The regularized incomplete beta function I_x(a, b).
  ---@param a number
  ---@param b number
  ---@param x number
  ---@return number
  local function beta_i (a, b, x)
    if x <= 0 then
      return 0
    end
    if x >= 1 then
      return 1
    end
    local front = exp (
      log_gamma (a + b)
        - log_gamma (a)
        - log_gamma (b)
        + a * log (x)
        + b * log (1 - x)
    )
    if x < (a + 1) / (a + b + 2) then
      return front * beta_cf (a, b, x) / a
    end
    return 1 - front * beta_cf (b, a, 1 - x) / b
  end

  ---The standard normal distribution up to z.
  ---@param z number
  ---@return number
  local function norm_cdf (z)
    local _, q = gamma_pq (0.5, z * z / 2)
    if z < 0 then
      return q / 2
    end
    return 1 - q / 2
  end

  ---@param z number
  ---@return number
  local function norm_pdf (z)
    return exp (-z * z / 2) / sqrt (2 * PI)
  end

  -- Acklam's rational approximation of the inverse normal, which a Halley step then makes
  -- good to the last digits.
  local A = {
    -3.969683028665376e+01,
    2.209460984245205e+02,
    -2.759285104469687e+02,
    1.383577518672690e+02,
    -3.066479806614716e+01,
    2.506628277459239e+00,
  }
  local B = {
    -5.447609879822406e+01,
    1.615858368580409e+02,
    -1.556989798598866e+02,
    6.680131188771972e+01,
    -1.328068155288572e+01,
  }
  local C = {
    -7.784894002430293e-03,
    -3.223964580411365e-01,
    -2.400758277161838e+00,
    -2.549732539343734e+00,
    4.374664141464968e+00,
    2.938163982698783e+00,
  }
  local D = {
    7.784695709041462e-03,
    3.224671290700398e-01,
    2.445134137142996e+00,
    3.754408661907416e+00,
  }

  ---The z for which the standard normal distribution reaches p.
  ---@param p number
  ---@return number
  local function norm_inv (p)
    if p <= 0 or p >= 1 then
      return raise ('#NUM!')
    end
    local x ---@type number
    if p < 0.02425 then
      local q = sqrt (-2 * log (p))
      x = (((((C[1] * q + C[2]) * q + C[3]) * q + C[4]) * q + C[5]) * q + C[6])
        / ((((D[1] * q + D[2]) * q + D[3]) * q + D[4]) * q + 1)
    elseif p > 1 - 0.02425 then
      local q = sqrt (-2 * log (1 - p))
      x = -(
          ((((C[1] * q + C[2]) * q + C[3]) * q + C[4]) * q + C[5]) * q + C[6]
        )
        / ((((D[1] * q + D[2]) * q + D[3]) * q + D[4]) * q + 1)
    else
      local q = p - 0.5
      local r = q * q
      x = (((((A[1] * r + A[2]) * r + A[3]) * r + A[4]) * r + A[5]) * r + A[6])
        * q
        / (((((B[1] * r + B[2]) * r + B[3]) * r + B[4]) * r + B[5]) * r + 1)
    end
    for _ = 1, 2 do
      local e = norm_cdf (x) - p
      local u = e * sqrt (2 * PI) * exp (x * x / 2)
      x = x - u / (1 + x * u / 2)
    end
    return x
  end

  ---Student's t distribution up to t, with df degrees of freedom.
  ---@param t number
  ---@param df number
  ---@return number
  local function t_cdf (t, df)
    local tail = beta_i (df / 2, 0.5, df / (df + t * t)) / 2
    if t > 0 then
      return 1 - tail
    end
    return tail
  end

  ---@param t number
  ---@param df number
  ---@return number
  local function t_pdf (t, df)
    return exp (
      log_gamma ((df + 1) / 2)
        - log_gamma (df / 2)
        - 0.5 * log (df * PI)
        - (df + 1) / 2 * log (1 + t * t / df)
    )
  end

  ---The x at which a rising function reaches p, by bisection. The search starts at
  ---[lo, hi] and widens to the right until it holds p.
  ---@param f fun(x: number): number
  ---@param p number
  ---@param lo number
  ---@param hi number
  ---@return number
  local function invert (f, p, lo, hi)
    local tries = 0
    while f (hi) < p do
      lo, hi = hi, hi * 2
      tries = tries + 1
      if tries > 200 then
        return raise ('#NUM!')
      end
    end
    for _ = 1, 300 do
      local mid = (lo + hi) / 2
      if mid == lo or mid == hi then
        break
      end
      if f (mid) < p then
        lo = mid
      else
        hi = mid
      end
    end
    return (lo + hi) / 2
  end

  ---The t at which Student's t distribution reaches p.
  ---@param p number
  ---@param df number
  ---@return number
  local function t_inv (p, df)
    if p <= 0 or p >= 1 or df < 1 then
      return raise ('#NUM!')
    end
    if p == 0.5 then
      return 0
    end
    if p < 0.5 then
      return -invert (function (x)
        return 1 - t_cdf (-x, df)
      end, 1 - p, 0, 1)
    end
    return invert (function (x)
      return t_cdf (x, df)
    end, p, 0, 1)
  end

  ---@param x number
  ---@param df number
  ---@return number
  local function chisq_pdf (x, df)
    if x <= 0 then
      return 0
    end
    local k = df / 2
    return exp ((k - 1) * log (x) - x / 2 - k * log (2) - log_gamma (k))
  end

  ---A degrees of freedom argument: a whole number from 1.
  ---@param x number
  ---@return integer
  local function degrees (x)
    local df = trunc (x)
    if df < 1 or df > 1e10 then
      return raise ('#NUM!')
    end
    return df
  end

  ---A probability argument, from 0 to 1.
  ---@param p number
  ---@return number
  local function probability (p)
    if p < 0 or p > 1 then
      return raise ('#NUM!')
    end
    return p
  end

  -------------------------------------------------------------------------------------------
  -- SUBTOTAL and AGGREGATE
  -------------------------------------------------------------------------------------------

  ---The values that SUBTOTAL or AGGREGATE reads from its arguments, from `first` to `last`.
  ---References leave out the rows hidden by a filter, the rows the user hid when `user` is
  ---set, other subtotals when `nested` is set, and errors when `errors` is set. A value that
  ---is not a reference is #VALUE! for SUBTOTAL, which reads references only.
  ---@param args Sheet.Node[]
  ---@param first integer
  ---@param last integer
  ---@param ctx Sheet.Context
  ---@param opts { user: boolean, nested: boolean, errors: boolean, refs_only: boolean, filtered: boolean }
  ---@return Sheet.Value[] values Every value that counts, numbers and text alike.
  local function gather (args, first, last, ctx, opts)
    local out = {} ---@type Sheet.Value[]
    local hidden, subtotal = ctx.hidden, ctx.subtotal
    for k = first, last do
      local node = args[k]
      local range = reference (node, ctx)
      if range then
        local sheet = range.sheet
        for r = range.r1, range.r2 do
          local why = hidden and hidden (r, sheet)
          local skip_row = (why == 'filter' and opts.filtered)
            or (why == 'user' and opts.user)
          if not skip_row then
            for c = range.c1, range.c2 do
              if not (opts.nested and subtotal and subtotal (r, c, sheet)) then
                local v = ctx.value (r, c, sheet)
                if is_error (v) then
                  if not opts.errors then
                    raise_value (v)
                  end
                elseif v ~= nil then
                  out[#out + 1] = v
                end
              end
            end
          end
        end
      elseif opts.refs_only then
        return raise ('#VALUE!')
      else
        each (node, ctx, function (v)
          if is_error (v) then
            if not opts.errors then
              raise_value (v)
            end
          elseif v ~= nil then
            out[#out + 1] = v
          end
        end)
      end
    end
    return out
  end

  ---@param values Sheet.Value[]
  ---@return number[]
  local function only_numbers (values)
    local out = {} ---@type number[]
    for _, v in ipairs (values) do
      if type (v) == 'number' then
        out[#out + 1] = v
      end
    end
    return out
  end

  ---The most common number, the first one to come up when several tie.
  ---@param list number[]
  ---@return number
  local function mode_of (list)
    local counts = {} ---@type table<number, integer>
    for _, x in ipairs (list) do
      local key = clean (x)
      counts[key] = (counts[key] or 0) + 1
    end
    local best, most = nil, 1 ---@type number?, integer
    for _, x in ipairs (list) do
      if counts[clean (x)] > most then
        best, most = x, counts[clean (x)]
      end
    end
    if not best then
      return raise ('#N/A')
    end
    return best
  end

  ---The k-th largest or smallest number.
  ---@param list number[]
  ---@param k integer
  ---@param top boolean
  ---@return number
  local function kth_of (list, k, top)
    if k < 1 or k > #list then
      return raise ('#NUM!')
    end
    table.sort (list)
    if top then
      return list[#list - k + 1]
    end
    return list[k]
  end

  ---The value at fraction k of a sorted list, counting ranks from 1 to n + 1, as
  ---PERCENTILE.EXC does. A k too near 0 or 1 for the data is #NUM!.
  ---@param list number[]
  ---@param k number
  ---@return number
  local function percentile_exc (list, k)
    local n = #list
    local rank = k * (n + 1)
    if n == 0 or k <= 0 or k >= 1 or rank < 1 or rank > n then
      return raise ('#NUM!')
    end
    table.sort (list)
    local low = math.floor (rank)
    if low >= n then
      return list[n]
    end
    return list[low] + (rank - low) * (list[low + 1] - list[low])
  end

  ---The summaries SUBTOTAL and AGGREGATE work out from their numbers, by function number.
  ---@type table<integer, fun(values: Sheet.Value[]): number>
  local SUMMARY = {
    function (values)
      local list = only_numbers (values)
      if #list == 0 then
        return raise ('#DIV/0!')
      end
      return total_of (list) / #list
    end,
    function (values)
      return #only_numbers (values) + 0.0
    end,
    function (values)
      local n = 0
      for _, v in ipairs (values) do
        if v ~= '' then
          n = n + 1
        end
      end
      return n + 0.0
    end,
    function (values)
      local list = only_numbers (values)
      local best = list[1] or 0.0
      for _, x in ipairs (list) do
        best = math.max (best, x)
      end
      return best
    end,
    function (values)
      local list = only_numbers (values)
      local best = list[1] or 0.0
      for _, x in ipairs (list) do
        best = math.min (best, x)
      end
      return best
    end,
    function (values)
      local list = only_numbers (values)
      local product = #list > 0 and 1.0 or 0.0
      for _, x in ipairs (list) do
        product = product * x
      end
      return product
    end,
    function (values)
      return sqrt (variance (only_numbers (values), true))
    end,
    function (values)
      return sqrt (variance (only_numbers (values), false))
    end,
    function (values)
      return total_of (only_numbers (values))
    end,
    function (values)
      return variance (only_numbers (values), true)
    end,
    function (values)
      return variance (only_numbers (values), false)
    end,
    function (values)
      return percentile (only_numbers (values), 0.5)
    end,
    function (values)
      return mode_of (only_numbers (values))
    end,
  }

  define (
    'SUBTOTAL',
    'Math',
    'SUBTOTAL(function_num, ref1, [ref2], ...)',
    'Sums, counts or averages the cells of references, leaving out filtered rows and other subtotals.',
    {
      min = 2,
      max = MANY,
      run = function (args, ctx)
        local code = int_of (args[1], ctx)
        local fn = code > 100 and code - 100 or code
        if fn < 1 or fn > 11 then
          return raise ('#VALUE!')
        end
        local values = gather (args, 2, #args, ctx, {
          user = code > 100,
          nested = true,
          errors = false,
          refs_only = true,
          filtered = true,
        })
        return SUMMARY[fn] (values)
      end,
    }
  )

  define (
    'AGGREGATE',
    'Math',
    'AGGREGATE(function_num, options, ref1, [ref2_or_k], ...)',
    'Works out one of 19 summaries of references, leaving out hidden rows, errors or subtotals as the options say.',
    {
      min = 3,
      max = MANY,
      run = function (args, ctx)
        local fn = int_of (args[1], ctx)
        local option = int_of (args[2], ctx)
        if fn < 1 or fn > 19 or option < 0 or option > 7 then
          return raise ('#VALUE!')
        end
        local opts = {
          nested = option <= 3,
          user = option == 1 or option == 3 or option == 5 or option == 7,
          errors = option == 2 or option == 3 or option == 6 or option == 7,
          refs_only = false,
          filtered = option == 1 or option == 3 or option == 5 or option == 7,
        }
        if fn <= 13 then
          return SUMMARY[fn] (gather (args, 3, #args, ctx, opts))
        end
        if #args ~= 4 then
          return raise ('#VALUE!')
        end
        local list = only_numbers (gather (args, 3, 3, ctx, opts))
        local k = number_of (args[4], ctx)
        if fn == 14 or fn == 15 then
          return kth_of (list, trunc (k), fn == 14)
        elseif fn == 16 then
          return percentile (list, k)
        elseif fn == 17 then
          local q = trunc (k)
          if q < 0 or q > 4 then
            return raise ('#NUM!')
          end
          return percentile (list, q / 4)
        elseif fn == 18 then
          return percentile_exc (list, k)
        end
        local q = trunc (k)
        if q < 1 or q > 3 then
          return raise ('#NUM!')
        end
        return percentile_exc (list, q / 4)
      end,
    }
  )

  -------------------------------------------------------------------------------------------
  -- Distributions
  -------------------------------------------------------------------------------------------

  ---NORM.DIST and NORMDIST.
  ---@type Sheet.Function
  local NORM_DIST = {
    min = 4,
    max = 4,
    map = function (v)
      local x, mean, sd = to_number (v[1]), to_number (v[2]), to_number (v[3])
      if sd <= 0 then
        return raise ('#NUM!')
      end
      local z = (x - mean) / sd
      if K.to_bool (v[4]) then
        return norm_cdf (z)
      end
      return norm_pdf (z) / sd
    end,
  }
  define (
    'NORM.DIST',
    'Statistics',
    'NORM.DIST(x, mean, standard_dev, cumulative)',
    'Gives the normal distribution at x, cumulative or as a density.',
    NORM_DIST
  )
  define (
    'NORMDIST',
    'Statistics',
    'NORMDIST(x, mean, standard_dev, cumulative)',
    'Gives the normal distribution at x, as NORM.DIST does.',
    NORM_DIST
  )

  ---NORM.INV and NORMINV.
  ---@type Sheet.Function
  local NORM_INV = {
    min = 3,
    max = 3,
    map = function (v)
      local p, mean, sd = to_number (v[1]), to_number (v[2]), to_number (v[3])
      if sd <= 0 then
        return raise ('#NUM!')
      end
      return mean + sd * norm_inv (p)
    end,
  }
  define (
    'NORM.INV',
    'Statistics',
    'NORM.INV(probability, mean, standard_dev)',
    'Gives the x at which the normal distribution reaches a probability.',
    NORM_INV
  )
  define (
    'NORMINV',
    'Statistics',
    'NORMINV(probability, mean, standard_dev)',
    'Gives the x at which the normal distribution reaches a probability, as NORM.INV does.',
    NORM_INV
  )

  define (
    'NORM.S.DIST',
    'Statistics',
    'NORM.S.DIST(z, cumulative)',
    'Gives the standard normal distribution at z, cumulative or as a density.',
    {
      min = 2,
      max = 2,
      map = function (v)
        local z = to_number (v[1])
        if K.to_bool (v[2]) then
          return norm_cdf (z)
        end
        return norm_pdf (z)
      end,
    }
  )
  define (
    'NORMSDIST',
    'Statistics',
    'NORMSDIST(z)',
    'Gives the standard normal distribution up to z.',
    {
      min = 1,
      max = 1,
      map = function (v)
        return norm_cdf (to_number (v[1]))
      end,
    }
  )

  ---NORM.S.INV and NORMSINV.
  ---@type Sheet.Function
  local NORM_S_INV = {
    min = 1,
    max = 1,
    map = function (v)
      return norm_inv (to_number (v[1]))
    end,
  }
  define (
    'NORM.S.INV',
    'Statistics',
    'NORM.S.INV(probability)',
    'Gives the z at which the standard normal distribution reaches a probability.',
    NORM_S_INV
  )
  define (
    'NORMSINV',
    'Statistics',
    'NORMSINV(probability)',
    'Gives the z at which the standard normal distribution reaches a probability, as NORM.S.INV does.',
    NORM_S_INV
  )

  define (
    'T.DIST',
    'Statistics',
    'T.DIST(x, deg_freedom, cumulative)',
    "Gives Student's t distribution at x, cumulative or as a density.",
    {
      min = 3,
      max = 3,
      map = function (v)
        local t, df = to_number (v[1]), degrees (to_number (v[2]))
        if K.to_bool (v[3]) then
          return t_cdf (t, df)
        end
        return t_pdf (t, df)
      end,
    }
  )
  define (
    'T.DIST.2T',
    'Statistics',
    'T.DIST.2T(x, deg_freedom)',
    "Gives the two-tailed Student's t distribution beyond x.",
    {
      min = 2,
      max = 2,
      map = function (v)
        local t, df = to_number (v[1]), degrees (to_number (v[2]))
        if t < 0 then
          return raise ('#NUM!')
        end
        return beta_i (df / 2, 0.5, df / (df + t * t))
      end,
    }
  )
  define (
    'T.DIST.RT',
    'Statistics',
    'T.DIST.RT(x, deg_freedom)',
    "Gives the right tail of Student's t distribution beyond x.",
    {
      min = 2,
      max = 2,
      map = function (v)
        local t, df = to_number (v[1]), degrees (to_number (v[2]))
        return t_cdf (-t, df)
      end,
    }
  )
  define (
    'T.INV',
    'Statistics',
    'T.INV(probability, deg_freedom)',
    "Gives the t at which Student's t distribution reaches a probability.",
    {
      min = 2,
      max = 2,
      map = function (v)
        return t_inv (to_number (v[1]), degrees (to_number (v[2])))
      end,
    }
  )
  define (
    'T.INV.2T',
    'Statistics',
    'T.INV.2T(probability, deg_freedom)',
    "Gives the t beyond which both tails of Student's t distribution hold a probability.",
    {
      min = 2,
      max = 2,
      map = function (v)
        local p = to_number (v[1])
        if p <= 0 or p > 1 then
          return raise ('#NUM!')
        end
        return abs (t_inv (p / 2, degrees (to_number (v[2]))))
      end,
    }
  )

  ---T.TEST and TTEST: the chance that two samples come from means this far apart.
  ---@type Sheet.Function
  local T_TEST = {
    min = 4,
    max = 4,
    run = function (args, ctx)
      local tails, kind = int_of (args[3], ctx), int_of (args[4], ctx)
      if (tails ~= 1 and tails ~= 2) or kind < 1 or kind > 3 then
        return raise ('#NUM!')
      end
      local t, df ---@type number, number
      if kind == 1 then
        local ys, xs = paired (args[1], args[2], ctx)
        local n = #xs
        if n < 2 then
          return raise ('#DIV/0!')
        end
        local diffs = {} ---@type number[]
        for i = 1, n do
          diffs[i] = ys[i] - xs[i]
        end
        local sd = sqrt (variance (diffs, true))
        if sd == 0 then
          return raise ('#DIV/0!')
        end
        t = (total_of (diffs) / n) / (sd / sqrt (n))
        df = n - 1
      else
        local a = numbers (args, ctx, 1, 1)
        local b = numbers (args, ctx, 2, 2)
        local na, nb = #a, #b
        if na < 2 or nb < 2 then
          return raise ('#DIV/0!')
        end
        local ma, mb = total_of (a) / na, total_of (b) / nb
        local va, vb = variance (a, true), variance (b, true)
        if kind == 2 then
          df = na + nb - 2
          local pooled = ((na - 1) * va + (nb - 1) * vb) / df
          t = (ma - mb) / sqrt (pooled * (1 / na + 1 / nb))
        else
          local sa, sb = va / na, vb / nb
          t = (ma - mb) / sqrt (sa + sb)
          df = (sa + sb) ^ 2 / (sa * sa / (na - 1) + sb * sb / (nb - 1))
        end
      end
      if t ~= t then
        return raise ('#DIV/0!')
      end
      return tails * t_cdf (-abs (t), df)
    end,
  }
  define (
    'T.TEST',
    'Statistics',
    'T.TEST(array1, array2, tails, type)',
    "Gives the probability of Student's t-test that two samples share a mean.",
    T_TEST
  )
  define (
    'TTEST',
    'Statistics',
    'TTEST(array1, array2, tails, type)',
    "Gives the probability of Student's t-test that two samples share a mean, as T.TEST does.",
    T_TEST
  )

  ---The chance of `x` successes, or up to `x` when `cumulative`, in `n` tries.
  ---@param x integer
  ---@param n integer
  ---@param p number
  ---@return number
  local function binom_pmf (x, n, p)
    if p == 0 then
      return x == 0 and 1 or 0
    end
    if p == 1 then
      return x == n and 1 or 0
    end
    return exp (
      log_gamma (n + 1)
        - log_gamma (x + 1)
        - log_gamma (n - x + 1)
        + x * log (p)
        + (n - x) * log (1 - p)
    )
  end

  ---BINOM.DIST and BINOMDIST.
  ---@type Sheet.Function
  local BINOM = {
    min = 4,
    max = 4,
    map = function (v)
      local x, n = trunc (to_number (v[1])), trunc (to_number (v[2]))
      local p = probability (to_number (v[3]))
      if x < 0 or x > n then
        return raise ('#NUM!')
      end
      if not K.to_bool (v[4]) then
        return binom_pmf (x, n, p)
      end
      if p == 0 or p == 1 then
        return (p == 0 or x == n) and 1 or 0
      end
      -- The binomial tail is an incomplete beta function.
      if x == n then
        return 1
      end
      return 1 - beta_i (x + 1, n - x, p)
    end,
  }
  define (
    'BINOM.DIST',
    'Statistics',
    'BINOM.DIST(number_s, trials, probability_s, cumulative)',
    'Gives the binomial distribution: the chance of a number of successes in a number of tries.',
    BINOM
  )
  define (
    'BINOMDIST',
    'Statistics',
    'BINOMDIST(number_s, trials, probability_s, cumulative)',
    'Gives the binomial distribution, as BINOM.DIST does.',
    BINOM
  )

  ---POISSON.DIST and POISSON.
  ---@type Sheet.Function
  local POISSON = {
    min = 3,
    max = 3,
    map = function (v)
      local x, mean = trunc (to_number (v[1])), to_number (v[2])
      if x < 0 or mean < 0 then
        return raise ('#NUM!')
      end
      if K.to_bool (v[3]) then
        if mean == 0 then
          return 1
        end
        local _, q = gamma_pq (x + 1, mean)
        return q
      end
      if mean == 0 then
        return x == 0 and 1 or 0
      end
      return exp (x * log (mean) - mean - log_gamma (x + 1))
    end,
  }
  define (
    'POISSON.DIST',
    'Statistics',
    'POISSON.DIST(x, mean, cumulative)',
    'Gives the Poisson distribution: the chance of a number of events at a mean rate.',
    POISSON
  )
  define (
    'POISSON',
    'Statistics',
    'POISSON(x, mean, cumulative)',
    'Gives the Poisson distribution, as POISSON.DIST does.',
    POISSON
  )

  define (
    'CHISQ.DIST',
    'Statistics',
    'CHISQ.DIST(x, deg_freedom, cumulative)',
    'Gives the chi-squared distribution at x, cumulative or as a density.',
    {
      min = 3,
      max = 3,
      map = function (v)
        local x, df = to_number (v[1]), degrees (to_number (v[2]))
        if x < 0 then
          return raise ('#NUM!')
        end
        if K.to_bool (v[3]) then
          local p = gamma_pq (df / 2, x / 2)
          return p
        end
        return chisq_pdf (x, df)
      end,
    }
  )

  ---CHISQ.DIST.RT and CHIDIST.
  ---@type Sheet.Function
  local CHISQ_RT = {
    min = 2,
    max = 2,
    map = function (v)
      local x, df = to_number (v[1]), degrees (to_number (v[2]))
      if x < 0 then
        return raise ('#NUM!')
      end
      local _, q = gamma_pq (df / 2, x / 2)
      return q
    end,
  }
  define (
    'CHISQ.DIST.RT',
    'Statistics',
    'CHISQ.DIST.RT(x, deg_freedom)',
    'Gives the right tail of the chi-squared distribution beyond x.',
    CHISQ_RT
  )
  define (
    'CHIDIST',
    'Statistics',
    'CHIDIST(x, deg_freedom)',
    'Gives the right tail of the chi-squared distribution, as CHISQ.DIST.RT does.',
    CHISQ_RT
  )

  define (
    'CHISQ.INV',
    'Statistics',
    'CHISQ.INV(probability, deg_freedom)',
    'Gives the x at which the chi-squared distribution reaches a probability.',
    {
      min = 2,
      max = 2,
      map = function (v)
        local p, df = probability (to_number (v[1])), degrees (to_number (v[2]))
        if p == 0 then
          return 0
        end
        if p == 1 then
          return raise ('#NUM!')
        end
        return invert (function (x)
          local lower = gamma_pq (df / 2, x / 2)
          return lower
        end, p, 0, df + 1)
      end,
    }
  )

  ---CHISQ.INV.RT and CHIINV.
  ---@type Sheet.Function
  local CHISQ_INV_RT = {
    min = 2,
    max = 2,
    map = function (v)
      local p, df = probability (to_number (v[1])), degrees (to_number (v[2]))
      if p == 0 then
        return raise ('#NUM!')
      end
      if p == 1 then
        return 0
      end
      return invert (function (x)
        local _, q = gamma_pq (df / 2, x / 2)
        return -q
      end, -p, 0, df + 1)
    end,
  }
  define (
    'CHISQ.INV.RT',
    'Statistics',
    'CHISQ.INV.RT(probability, deg_freedom)',
    'Gives the x beyond which the right tail of the chi-squared distribution holds a probability.',
    CHISQ_INV_RT
  )
  define (
    'CHIINV',
    'Statistics',
    'CHIINV(probability, deg_freedom)',
    'Gives the x beyond which the right tail of the chi-squared distribution holds a probability, as CHISQ.INV.RT does.',
    CHISQ_INV_RT
  )

  ---CHISQ.TEST and CHITEST: the chance of counts this far from the expected ones.
  ---@type Sheet.Function
  local CHISQ_TEST = {
    min = 2,
    max = 2,
    run = function (args, ctx)
      local actual = grid_or_value (args[1], ctx)
      local expected = grid_or_value (args[2], ctx)
      local h, w = dims (actual)
      local eh, ew = dims (expected)
      if
        h ~= eh
        or w ~= ew
        or not is_grid (actual)
        or not is_grid (expected)
      then
        return raise ('#N/A')
      end
      local stat = 0.0
      for i = 1, h do
        for j = 1, w do
          local a = grid_at (actual --[[@as Sheet.Grid]], i, j, ctx)
          local e = grid_at (expected --[[@as Sheet.Grid]], i, j, ctx)
          if is_error (a) then
            raise_value (a)
          end
          if is_error (e) then
            raise_value (e)
          end
          if type (a) == 'number' and type (e) == 'number' then
            if e == 0 then
              return raise ('#DIV/0!')
            end
            stat = stat + (a - e) ^ 2 / e
          end
        end
      end
      local df = (h > 1 and w > 1) and (h - 1) * (w - 1) or h * w - 1
      if df < 1 then
        return raise ('#N/A')
      end
      local _, q = gamma_pq (df / 2, stat / 2)
      return q
    end,
  }
  define (
    'CHISQ.TEST',
    'Statistics',
    'CHISQ.TEST(actual_range, expected_range)',
    'Gives the chance that counts differ from the expected counts by chance alone.',
    CHISQ_TEST
  )
  define (
    'CHITEST',
    'Statistics',
    'CHITEST(actual_range, expected_range)',
    'Gives the chance that counts differ from the expected counts by chance alone, as CHISQ.TEST does.',
    CHISQ_TEST
  )

  -------------------------------------------------------------------------------------------
  -- Summaries
  -------------------------------------------------------------------------------------------

  ---The covariance of paired numbers, of a sample or of a population.
  ---@param sample boolean
  ---@return Sheet.Function
  local function covariance (sample)
    return {
      min = 2,
      max = 2,
      run = function (args, ctx)
        local ys, xs = paired (args[1], args[2], ctx)
        local n = #xs
        if n < (sample and 2 or 1) then
          return raise ('#DIV/0!')
        end
        local mx, my = total_of (xs) / n, total_of (ys) / n
        local s = 0.0
        for i = 1, n do
          s = s + (xs[i] - mx) * (ys[i] - my)
        end
        return s / (sample and n - 1 or n)
      end,
    }
  end
  define (
    'COVARIANCE.P',
    'Statistics',
    'COVARIANCE.P(array1, array2)',
    'Gives the covariance of paired numbers, over the whole population.',
    covariance (false)
  )
  define (
    'COVARIANCE.S',
    'Statistics',
    'COVARIANCE.S(array1, array2)',
    'Gives the covariance of paired numbers, of a sample.',
    covariance (true)
  )
  define (
    'COVAR',
    'Statistics',
    'COVAR(array1, array2)',
    'Gives the covariance of paired numbers, as COVARIANCE.P does.',
    covariance (false)
  )

  define (
    'RSQ',
    'Statistics',
    'RSQ(known_ys, known_xs)',
    'Gives the square of the correlation of paired numbers.',
    {
      min = 2,
      max = 2,
      run = function (args, ctx)
        local ys, xs = paired (args[1], args[2], ctx)
        local n = #xs
        if n < 2 then
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
        return sxy * sxy / (sxx * syy)
      end,
    }
  )

  ---Positive numbers, for GEOMEAN and HARMEAN.
  ---@param args Sheet.Node[]
  ---@param ctx Sheet.Context
  ---@return number[]
  local function positives (args, ctx)
    local list = numbers (args, ctx)
    if #list == 0 then
      return raise ('#NUM!')
    end
    for _, x in ipairs (list) do
      if x <= 0 then
        return raise ('#NUM!')
      end
    end
    return list
  end

  define (
    'GEOMEAN',
    'Statistics',
    'GEOMEAN(number1, [number2], ...)',
    'Gives the geometric mean of positive numbers.',
    {
      min = 1,
      max = MANY,
      run = function (args, ctx)
        local list = positives (args, ctx)
        local s = 0.0
        for _, x in ipairs (list) do
          s = s + log (x)
        end
        return exp (s / #list)
      end,
    }
  )
  define (
    'HARMEAN',
    'Statistics',
    'HARMEAN(number1, [number2], ...)',
    'Gives the harmonic mean of positive numbers.',
    {
      min = 1,
      max = MANY,
      run = function (args, ctx)
        local list = positives (args, ctx)
        local s = 0.0
        for _, x in ipairs (list) do
          s = s + 1 / x
        end
        return #list / s
      end,
    }
  )

  ---The mean and the sum of the powers of the deviations from it.
  ---@param list number[]
  ---@param power integer
  ---@return number mean
  ---@return number sum
  local function moments (list, power)
    local n = #list
    local mean = total_of (list) / n
    local s = 0.0
    for _, x in ipairs (list) do
      s = s + (x - mean) ^ power
    end
    return mean, s
  end

  define (
    'SKEW',
    'Statistics',
    'SKEW(number1, [number2], ...)',
    'Gives how lopsided numbers are around their mean, for a sample.',
    {
      min = 1,
      max = MANY,
      run = function (args, ctx)
        local list = numbers (args, ctx)
        local n = #list
        if n < 3 then
          return raise ('#DIV/0!')
        end
        local sd = sqrt (variance (list, true))
        if sd == 0 then
          return raise ('#DIV/0!')
        end
        local _, s3 = moments (list, 3)
        return n / ((n - 1) * (n - 2)) * s3 / sd ^ 3
      end,
    }
  )
  define (
    'SKEW.P',
    'Statistics',
    'SKEW.P(number1, [number2], ...)',
    'Gives how lopsided numbers are around their mean, for a whole population.',
    {
      min = 1,
      max = MANY,
      run = function (args, ctx)
        local list = numbers (args, ctx)
        local n = #list
        if n < 1 then
          return raise ('#DIV/0!')
        end
        local sd = sqrt (variance (list, false))
        if sd == 0 then
          return raise ('#DIV/0!')
        end
        local _, s3 = moments (list, 3)
        return s3 / n / sd ^ 3
      end,
    }
  )
  define (
    'KURT',
    'Statistics',
    'KURT(number1, [number2], ...)',
    'Gives how heavy the tails of numbers are, next to a normal distribution.',
    {
      min = 1,
      max = MANY,
      run = function (args, ctx)
        local list = numbers (args, ctx)
        local n = #list
        if n < 4 then
          return raise ('#DIV/0!')
        end
        local var = variance (list, true)
        if var == 0 then
          return raise ('#DIV/0!')
        end
        local _, s4 = moments (list, 4)
        return n * (n + 1) / ((n - 1) * (n - 2) * (n - 3)) * s4 / (var * var)
          - 3 * (n - 1) ^ 2 / ((n - 2) * (n - 3))
      end,
    }
  )
  define (
    'AVEDEV',
    'Statistics',
    'AVEDEV(number1, [number2], ...)',
    'Gives the average distance of numbers from their mean.',
    {
      min = 1,
      max = MANY,
      run = function (args, ctx)
        local list = numbers (args, ctx)
        local n = #list
        if n == 0 then
          return raise ('#NUM!')
        end
        local mean = total_of (list) / n
        local s = 0.0
        for _, x in ipairs (list) do
          s = s + abs (x - mean)
        end
        return s / n
      end,
    }
  )
  define (
    'DEVSQ',
    'Statistics',
    'DEVSQ(number1, [number2], ...)',
    'Gives the sum of the squares of the distances of numbers from their mean.',
    {
      min = 1,
      max = MANY,
      run = function (args, ctx)
        local list = numbers (args, ctx)
        if #list == 0 then
          return raise ('#NUM!')
        end
        local _, s2 = moments (list, 2)
        return s2
      end,
    }
  )

  define (
    'PERCENTILE.EXC',
    'Statistics',
    'PERCENTILE.EXC(data, k)',
    'Gives the value below which a fraction k of the numbers fall, with k strictly between 0 and 1.',
    {
      min = 2,
      max = 2,
      run = function (args, ctx)
        return percentile_exc (
          numbers (args, ctx, 1, 1),
          number_of (args[2], ctx)
        )
      end,
    }
  )
  define (
    'QUARTILE.EXC',
    'Statistics',
    'QUARTILE.EXC(data, quart)',
    'Gives the first, second or third quartile of numbers, as PERCENTILE.EXC counts them.',
    {
      min = 2,
      max = 2,
      run = function (args, ctx)
        local q = int_of (args[2], ctx)
        if q < 1 or q > 3 then
          return raise ('#NUM!')
        end
        return percentile_exc (numbers (args, ctx, 1, 1), q / 4)
      end,
    }
  )

  ---Cuts a fraction down to a number of significant digits, without rounding up.
  ---@param x number
  ---@param digits integer
  ---@return number
  local function cut_digits (x, digits)
    local scale = 10 ^ digits
    return math.floor (clean (x * scale)) / scale
  end

  ---PERCENTRANK, PERCENTRANK.INC and PERCENTRANK.EXC: where x falls in the data, as a
  ---fraction, between two values when it falls between them.
  ---@param exclusive boolean
  ---@return Sheet.Function
  local function percent_rank (exclusive)
    return {
      min = 2,
      max = 3,
      run = function (args, ctx)
        local list = numbers (args, ctx, 1, 1)
        local x = number_of (args[2], ctx)
        local digits = given (args[3]) and int_of (args[3], ctx) or 3
        if digits < 1 then
          return raise ('#NUM!')
        end
        local n = #list
        if n == 0 then
          return raise ('#NUM!')
        end
        table.sort (list)
        if x < list[1] or x > list[n] then
          return raise ('#N/A')
        end
        ---@param rank number Counting from 1.
        ---@return number
        local function share (rank)
          if exclusive then
            return rank / (n + 1)
          end
          if n == 1 then
            return 1
          end
          return (rank - 1) / (n - 1)
        end
        for i = 1, n do
          if list[i] == x then
            return cut_digits (share (i), digits)
          end
          if list[i] > x then
            local lo, hi = list[i - 1], list[i]
            local rank = i - 1 + (x - lo) / (hi - lo)
            return cut_digits (share (rank), digits)
          end
        end
        return cut_digits (share (n), digits)
      end,
    }
  end
  define (
    'PERCENTRANK',
    'Statistics',
    'PERCENTRANK(data, x, [significance])',
    'Gives where a value falls in numbers, as a fraction from 0 to 1.',
    percent_rank (false)
  )
  define (
    'PERCENTRANK.INC',
    'Statistics',
    'PERCENTRANK.INC(data, x, [significance])',
    'Gives where a value falls in numbers, as a fraction from 0 to 1.',
    percent_rank (false)
  )
  define (
    'PERCENTRANK.EXC',
    'Statistics',
    'PERCENTRANK.EXC(data, x, [significance])',
    'Gives where a value falls in numbers, as a fraction strictly between 0 and 1.',
    percent_rank (true)
  )

  define (
    'FREQUENCY',
    'Statistics',
    'FREQUENCY(data, bins)',
    'Counts the numbers that fall in each bin, and those above the last, as a column.',
    {
      min = 2,
      max = 2,
      run = function (args, ctx)
        local data = numbers (args, ctx, 1, 1)
        local bins = numbers (args, ctx, 2, 2)
        local order = {} ---@type integer[]
        for i = 1, #bins do
          order[i] = i
        end
        table.sort (order, function (a, b)
          if bins[a] ~= bins[b] then
            return bins[a] < bins[b]
          end
          return a < b
        end)
        local counts = {} ---@type Sheet.Values
        for i = 1, #bins + 1 do
          counts[i] = 0.0
        end
        for _, x in ipairs (data) do
          local slot = #bins + 1
          for _, i in ipairs (order) do
            if x <= bins[i] then
              slot = i
              break
            end
          end
          counts[slot] = counts[slot] + 1
        end
        return new_array (#bins + 1, 1, counts)
      end,
    }
  )

  -------------------------------------------------------------------------------------------
  -- Fits: LINEST, TREND and GROWTH
  -------------------------------------------------------------------------------------------

  ---The inverse of a square matrix, by Gauss-Jordan elimination, or nil when it has none.
  ---@param m number[][]
  ---@return number[][]?
  local function inverse (m)
    local n = #m
    local a = {} ---@type number[][]
    for i = 1, n do
      a[i] = {}
      for j = 1, n do
        a[i][j] = m[i][j]
      end
      for j = 1, n do
        a[i][n + j] = i == j and 1 or 0
      end
    end
    for col = 1, n do
      local pivot = col
      for r = col + 1, n do
        if abs (a[r][col]) > abs (a[pivot][col]) then
          pivot = r
        end
      end
      if abs (a[pivot][col]) < 1e-12 then
        return nil
      end
      a[col], a[pivot] = a[pivot], a[col]
      local p = a[col][col]
      for j = 1, 2 * n do
        a[col][j] = a[col][j] / p
      end
      for r = 1, n do
        if r ~= col then
          local f = a[r][col]
          if f ~= 0 then
            for j = 1, 2 * n do
              a[r][j] = a[r][j] - f * a[col][j]
            end
          end
        end
      end
    end
    local out = {} ---@type number[][]
    for i = 1, n do
      out[i] = {}
      for j = 1, n do
        out[i][j] = a[i][n + j]
      end
    end
    return out
  end

  ---The known values of a fit: the ys, and for each y its xs. A column of ys takes a column
  ---of xs for each variable, and a row of ys a row for each. With no xs, x counts 1, 2, 3.
  ---@param ynode Sheet.Node
  ---@param xnode Sheet.Node?
  ---@param ctx Sheet.Context
  ---@param log_y boolean True for GROWTH, which fits the logs of the ys.
  ---@return number[] ys
  ---@return number[][] xs
  ---@return boolean by_row True when the ys run along a row.
  local function known (ynode, xnode, ctx, log_y)
    local yv = grid_or_value (ynode, ctx)
    local yh, yw = dims (yv)
    local n = yh * yw
    local by_row = yh == 1 and yw > 1
    local ys = {} ---@type number[]
    for k = 1, n do
      local y = yv --[[@as Sheet.Value]]
      if is_grid (yv) then
        if by_row then
          y = grid_at (yv --[[@as Sheet.Grid]], 1, k, ctx)
        else
          y = grid_at (
            yv --[[@as Sheet.Grid]],
            math.floor ((k - 1) / yw) + 1,
            (k - 1) % yw + 1,
            ctx
          )
        end
      end
      if type (y) ~= 'number' then
        error (ERRORS['#VALUE!'], 0)
      end
      if log_y then
        if y <= 0 then
          error (ERRORS['#NUM!'], 0)
        end
        y = log (y)
      end
      ys[k] = y
    end
    local xs = {} ---@type number[][]
    if not given (xnode) then
      for k = 1, n do
        xs[k] = { k + 0.0 }
      end
      return ys, xs, by_row
    end
    local xv = grid_or_value (xnode --[[@as Sheet.Node]], ctx)
    local xh, xw = dims (xv)
    local vars ---@type integer
    if xh * xw == n then
      vars = 1
    elseif not by_row and xh == n then
      vars = xw
    elseif by_row and xw == n then
      vars = xh
    else
      error (ERRORS['#REF!'], 0)
    end
    for k = 1, n do
      local row = {} ---@type number[]
      for j = 1, vars do
        local x ---@type Sheet.Value
        if not is_grid (xv) then
          x = xv --[[@as Sheet.Value]]
        elseif vars == 1 then
          x = grid_at (
            xv --[[@as Sheet.Grid]],
            math.floor ((k - 1) / xw) + 1,
            (k - 1) % xw + 1,
            ctx
          )
        elseif by_row then
          x = grid_at (xv --[[@as Sheet.Grid]], j, k, ctx)
        else
          x = grid_at (xv --[[@as Sheet.Grid]], k, j, ctx)
        end
        if type (x) ~= 'number' then
          error (ERRORS['#VALUE!'], 0)
        end
        row[j] = x
      end
      xs[k] = row
    end
    return ys, xs, by_row
  end

  ---Fits y = b + m1*x1 + m2*x2 + ... by least squares. Without `const`, b is 0.
  ---@param ys number[]
  ---@param xs number[][]
  ---@param const boolean
  ---@return Sheet.Fit
  local function regress (ys, xs, const)
    local n = #ys
    local k = #xs[1]
    local p = k + 1
    -- The normal equations, with the intercept as the first unknown.
    local xtx = {} ---@type number[][]
    local xty = {} ---@type number[]
    for i = 1, p do
      xtx[i] = {}
      for j = 1, p do
        xtx[i][j] = 0
      end
      xty[i] = 0
    end
    for r = 1, n do
      local row = { const and 1 or 0 } ---@type number[]
      for j = 1, k do
        row[j + 1] = xs[r][j]
      end
      for i = 1, p do
        xty[i] = xty[i] + row[i] * ys[r]
        for j = 1, p do
          xtx[i][j] = xtx[i][j] + row[i] * row[j]
        end
      end
    end
    if not const then
      -- Holding b at 0 keeps its equation out of the way.
      xtx[1][1] = 1
    end
    local inv = inverse (xtx)
    if not inv then
      return raise ('#NUM!')
    end
    local coef = {} ---@type number[]
    for i = 1, p do
      local s = 0.0
      for j = 1, p do
        s = s + inv[i][j] * xty[j]
      end
      coef[i] = s
    end
    if not const then
      coef[1] = 0
    end
    local mean = total_of (ys) / n
    local ss_resid, ss_total = 0.0, 0.0
    for r = 1, n do
      local fit = coef[1]
      for j = 1, k do
        fit = fit + coef[j + 1] * xs[r][j]
      end
      ss_resid = ss_resid + (ys[r] - fit) ^ 2
      ss_total = ss_total + (const and (ys[r] - mean) ^ 2 or ys[r] ^ 2)
    end
    return {
      coef = coef,
      n = n,
      k = k,
      const = const,
      inverse = inv,
      ss_reg = ss_total - ss_resid,
      ss_resid = ss_resid,
    }
  end

  ---The fitted value for one set of xs.
  ---@param fit Sheet.Fit
  ---@param x number[]
  ---@return number
  local function predict (fit, x)
    local y = fit.coef[1]
    for j = 1, fit.k do
      y = y + fit.coef[j + 1] * x[j]
    end
    return y
  end

  define (
    'LINEST',
    'Statistics',
    'LINEST(known_ys, [known_xs], [const], [stats])',
    'Fits a straight line, or a plane, to data, and gives its slopes and intercept as a row.',
    {
      min = 1,
      max = 4,
      run = function (args, ctx)
        local ys, xs = known (args[1], args[2], ctx, false)
        local const = not given (args[3]) or bool_of (args[3], ctx)
        local stats = given (args[4]) and bool_of (args[4], ctx)
        local fit = regress (ys, xs, const)
        local k = fit.k
        local w = k + 1
        local out = {} ---@type Sheet.Values
        -- Excel lists the slopes from the last x to the first, then the intercept.
        for j = 1, k do
          out[j] = fit.coef[k - j + 2]
        end
        out[w] = fit.coef[1]
        if not stats then
          return new_array (1, w, out)
        end
        local df = fit.n - k - (const and 1 or 0)
        local se_y = df > 0 and sqrt (fit.ss_resid / df) or nil
        local na = ERRORS['#N/A']
        for j = 1, k do
          local d = fit.inverse[k - j + 2][k - j + 2]
          out[w + j] = se_y and sqrt (d) * se_y or na
        end
        out[2 * w] = const and se_y and sqrt (fit.inverse[1][1]) * se_y or na
        local r2 = (fit.ss_reg + fit.ss_resid) > 0
            and fit.ss_reg / (fit.ss_reg + fit.ss_resid)
          or na
        out[2 * w + 1] = r2
        out[2 * w + 2] = se_y or na
        if df <= 0 then
          out[3 * w + 1] = na
        elseif fit.ss_resid == 0 then
          out[3 * w + 1] = ERRORS['#NUM!']
        else
          out[3 * w + 1] = (fit.ss_reg / k) / (fit.ss_resid / df)
        end
        out[3 * w + 2] = df + 0.0
        out[4 * w + 1] = fit.ss_reg
        out[4 * w + 2] = fit.ss_resid
        for i = 3, 5 do
          for j = 3, w do
            out[(i - 1) * w + j] = na
          end
        end
        return new_array (5, w, out)
      end,
    }
  )

  ---TREND and GROWTH: the fitted values for new xs, or for the known xs.
  ---@param grow boolean True for GROWTH, which fits an exponential curve.
  ---@return Sheet.Function
  local function along_fit (grow)
    return {
      min = 1,
      max = 4,
      run = function (args, ctx)
        local ys, xs, by_row = known (args[1], args[2], ctx, grow)
        local const = not given (args[4]) or bool_of (args[4], ctx)
        local fit = regress (ys, xs, const)
        ---@param y number
        ---@return number
        local function shown (y)
          return grow and exp (y) or y
        end
        if not given (args[3]) then
          local out = {} ---@type Sheet.Values
          for r = 1, fit.n do
            out[r] = shown (predict (fit, xs[r]))
          end
          if by_row then
            return new_array (1, fit.n, out)
          end
          return new_array (fit.n, 1, out)
        end
        local nv = grid_or_value (args[3], ctx)
        local nh, nw = dims (nv)
        local out = {} ---@type Sheet.Values
        if fit.k == 1 then
          for i = 1, nh do
            for j = 1, nw do
              local x = is_grid (nv)
                  and grid_at (nv --[[@as Sheet.Grid]], i, j, ctx)
                or nv
              if type (x) ~= 'number' then
                return raise ('#VALUE!')
              end
              out[(i - 1) * nw + j] = shown (predict (fit, { x }))
            end
          end
          return new_array (nh, nw, out)
        end
        -- Several xs: each new point is a row, or a column for ys along a row.
        local count = by_row and nw or nh
        for p = 1, count do
          local x = {} ---@type number[]
          for j = 1, fit.k do
            local v = by_row and grid_at (nv --[[@as Sheet.Grid]], j, p, ctx)
              or grid_at (nv --[[@as Sheet.Grid]], p, j, ctx)
            if type (v) ~= 'number' then
              return raise ('#VALUE!')
            end
            x[j] = v
          end
          out[p] = shown (predict (fit, x))
        end
        if by_row then
          return new_array (1, count, out)
        end
        return new_array (count, 1, out)
      end,
    }
  end
  define (
    'TREND',
    'Statistics',
    'TREND(known_ys, [known_xs], [new_xs], [const])',
    'Gives the values a straight line fitted to data takes at new xs.',
    along_fit (false)
  )
  define (
    'GROWTH',
    'Statistics',
    'GROWTH(known_ys, [known_xs], [new_xs], [const])',
    'Gives the values an exponential curve fitted to data takes at new xs.',
    along_fit (true)
  )
end
