-- sheet_fn_math: the math functions of the Sheet app's formulas: sums and products with their
-- conditional kin, rounding, whole numbers, logarithms and trigonometry. sheet_formula_kit
-- loads the module.

---@param K Sheet.FormulaKit
return function (K)
  local define, math1, raise, raise_value =
    K.define, K.math1, K.raise, K.raise_value
  local ERRORS, MANY = K.ERRORS, K.MANY
  local is_error, is_grid = K.is_error, K.is_grid
  local dims, grid_at, grid_or_value = K.dims, K.grid_at, K.grid_or_value
  local numbers, each_match = K.numbers, K.each_match
  local opt, opt_int, random = K.opt, K.opt_int, K.random
  local to_number, total_of = K.to_number, K.total_of
  local trunc, clean, round_to = K.trunc, K.clean, K.round_to
  local log, atan = K.log, K.atan

  -------------------------------------------------------------------------------------------
  -- Math
  -------------------------------------------------------------------------------------------

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

  define (
    'POWER',
    'Math',
    'POWER(number, power)',
    'Raises a number to a power.',
    {
      min = 2,
      max = 2,
      map = function (v)
        local x, y = to_number (v[1]), to_number (v[2])
        if x == 0 and y < 0 then
          return raise ('#DIV/0!')
        end
        return x ^ y
      end,
    }
  )

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
end
