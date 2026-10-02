-- sheet_fn_more: more math, text and information functions for the Sheet app's formulas:
-- hyperbolic and reciprocal trigonometry, numbers in other bases, Roman numerals, CONVERT
-- between units, TEXTSPLIT and NUMBERVALUE, and the functions that tell about cells and sheets,
-- such as FORMULATEXT, SHEET and CELL. sheet_formula loads the module.

---A unit CONVERT knows: what it measures, its size in the base unit, and whether it takes a
---metric prefix such as `k` or a binary one such as `Ki`.
---@class Sheet.Unit
---@field kind string
---@field size number
---@field prefix? 'metric'|'binary'
---@field power? integer 2 for an area and 3 for a volume, so a prefix counts that many times.

---@param K Sheet.FormulaKit
return function (K)
  local define, raise = K.define, K.raise
  local given, value_of, text_of, int_of =
    K.given, K.value_of, K.text_of, K.int_of
  local to_number, to_text = K.to_number, K.to_text
  local trunc, lower = K.trunc, K.lower
  local new_array, reference = K.new_array, K.reference
  local format_value = K.format_value

  local exp, log = math.exp, math.log

  -------------------------------------------------------------------------------------------
  -- Trigonometry
  -------------------------------------------------------------------------------------------

  ---A function of one number, as `math1` in sheet_formula makes them.
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

  ---@param x number
  ---@return number
  local function sinh (x)
    return (exp (x) - exp (-x)) / 2
  end

  ---@param x number
  ---@return number
  local function cosh (x)
    return (exp (x) + exp (-x)) / 2
  end

  ---@param x number
  ---@return number
  local function tanh (x)
    if x > 20 then
      return 1
    elseif x < -20 then
      return -1
    end
    local a, b = exp (x), exp (-x)
    return (a - b) / (a + b)
  end

  ---1 / x, or #DIV/0! for 0.
  ---@param x number
  ---@return number
  local function reciprocal (x)
    if x == 0 then
      return raise ('#DIV/0!')
    end
    return 1 / x
  end

  define (
    'SINH',
    'Math',
    'SINH(number)',
    'Gives the hyperbolic sine of a number.',
    math1 (sinh)
  )
  define (
    'COSH',
    'Math',
    'COSH(number)',
    'Gives the hyperbolic cosine of a number.',
    math1 (cosh)
  )
  define (
    'TANH',
    'Math',
    'TANH(number)',
    'Gives the hyperbolic tangent of a number.',
    math1 (tanh)
  )
  define (
    'ASINH',
    'Math',
    'ASINH(number)',
    'Gives the number whose hyperbolic sine is the given one.',
    math1 (function (x)
      if x < 0 then
        return -log (-x + math.sqrt (x * x + 1))
      end
      return log (x + math.sqrt (x * x + 1))
    end)
  )
  define (
    'ACOSH',
    'Math',
    'ACOSH(number)',
    'Gives the number from 0 up whose hyperbolic cosine is the given one.',
    math1 (function (x)
      if x < 1 then
        return raise ('#NUM!')
      end
      return log (x + math.sqrt (x * x - 1))
    end)
  )
  define (
    'ATANH',
    'Math',
    'ATANH(number)',
    'Gives the number whose hyperbolic tangent is the given one, from -1 to 1.',
    math1 (function (x)
      if x <= -1 or x >= 1 then
        return raise ('#NUM!')
      end
      return log ((1 + x) / (1 - x)) / 2
    end)
  )
  define (
    'COT',
    'Math',
    'COT(number)',
    'Gives the cotangent of an angle in radians.',
    math1 (function (x)
      return reciprocal (math.tan (x))
    end)
  )
  define (
    'COTH',
    'Math',
    'COTH(number)',
    'Gives the hyperbolic cotangent of a number.',
    math1 (function (x)
      return reciprocal (tanh (x))
    end)
  )
  define (
    'CSC',
    'Math',
    'CSC(number)',
    'Gives the cosecant of an angle in radians.',
    math1 (function (x)
      return reciprocal (math.sin (x))
    end)
  )
  define (
    'CSCH',
    'Math',
    'CSCH(number)',
    'Gives the hyperbolic cosecant of a number.',
    math1 (function (x)
      return reciprocal (sinh (x))
    end)
  )
  define (
    'SEC',
    'Math',
    'SEC(number)',
    'Gives the secant of an angle in radians.',
    math1 (function (x)
      return reciprocal (math.cos (x))
    end)
  )
  define (
    'SECH',
    'Math',
    'SECH(number)',
    'Gives the hyperbolic secant of a number.',
    math1 (function (x)
      return 1 / cosh (x)
    end)
  )
  define (
    'ACOT',
    'Math',
    'ACOT(number)',
    'Gives the angle in radians, from 0 to pi, whose cotangent is the given number.',
    math1 (function (x)
      return math.pi / 2 - math.atan (x)
    end)
  )

  -------------------------------------------------------------------------------------------
  -- Bases
  -------------------------------------------------------------------------------------------

  local DIGITS = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'

  ---Writes a whole number from 0 in a base from 2 to 36.
  ---@param n number
  ---@param radix integer
  ---@return string
  local function in_base (n, radix)
    if n == 0 then
      return '0'
    end
    local out = {} ---@type string[]
    while n > 0 do
      local d = math.floor (n % radix)
      table.insert (out, 1, string.sub (DIGITS, d + 1, d + 1))
      n = math.floor (n / radix)
    end
    return table.concat (out)
  end

  ---Reads digits in a base, or nil when a digit does not belong to it.
  ---@param text string
  ---@param radix integer
  ---@return number?
  local function from_base (text, radix)
    local n = 0.0
    local up = string.upper (text)
    for i = 1, #up do
      local d = string.find (DIGITS, string.sub (up, i, i), 1, true)
      if not d or d > radix then
        return nil
      end
      n = n * radix + (d - 1)
    end
    return n
  end

  define (
    'BASE',
    'Math',
    'BASE(number, radix, [min_length])',
    'Writes a number in another base, such as 2 for binary or 16 for hexadecimal.',
    {
      min = 2,
      max = 3,
      map = function (v, n)
        local x, radix = trunc (to_number (v[1])), trunc (to_number (v[2]))
        local width = n >= 3 and trunc (to_number (v[3])) or 0
        if
          x < 0
          or x >= 2 ^ 53
          or radix < 2
          or radix > 36
          or width < 0
          or width > 255
        then
          return raise ('#NUM!')
        end
        local s = in_base (x, radix)
        if #s < width then
          s = string.rep ('0', width - #s) .. s
        end
        return s
      end,
    }
  )

  define (
    'DECIMAL',
    'Math',
    'DECIMAL(text, radix)',
    'Reads a number written in another base.',
    {
      min = 2,
      max = 2,
      map = function (v)
        local text = to_text (v[1])
        local radix = trunc (to_number (v[2]))
        if radix < 2 or radix > 36 or #text > 255 then
          return raise ('#NUM!')
        end
        local n = from_base (text, radix)
        if not n then
          return raise ('#NUM!')
        end
        return n
      end,
    }
  )

  ---Writes a number from DEC2BIN and its kin, padded to `places` when given.
  ---@param x number
  ---@param radix integer
  ---@param places? number
  ---@return string
  local function to_base_text (x, radix, places)
    local full = radix ^ 10
    if x < -full / 2 or x >= full / 2 then
      return raise ('#NUM!')
    end
    if x < 0 then
      return in_base (full + x, radix)
    end
    local s = in_base (x, radix)
    if places then
      local width = trunc (places)
      if width < #s or width > 10 then
        return raise ('#NUM!')
      end
      s = string.rep ('0', width - #s) .. s
    end
    return s
  end

  ---Reads a number in BIN2DEC and its kin: up to ten digits, the tenth one's top bit for the
  ---sign.
  ---@param v Sheet.Value
  ---@param radix integer
  ---@return number
  local function from_base_text (v, radix)
    local text = type (v) == 'number' and format_value (v) or to_text (v)
    if #text > 10 then
      return raise ('#NUM!')
    end
    if text == '' then
      return 0
    end
    local n = from_base (text, radix)
    if not n then
      return raise ('#NUM!')
    end
    local full = radix ^ 10
    if #text == 10 and n >= full / 2 then
      n = n - full
    end
    return n
  end

  for from_name, from_radix in pairs ({ DEC = 10, BIN = 2, OCT = 8, HEX = 16 }) do
    for to_name, to_radix in pairs ({ DEC = 10, BIN = 2, OCT = 8, HEX = 16 }) do
      if from_name ~= to_name then
        local name = from_name .. '2' .. to_name
        local words = {
          DEC = 'decimal',
          BIN = 'binary',
          OCT = 'octal',
          HEX = 'hexadecimal',
        }
        local to_dec = to_name == 'DEC'
        define (
          name,
          'Math',
          name .. (to_dec and '(number)' or '(number, [places])'),
          'Turns a '
            .. words[from_name]
            .. ' number into '
            .. words[to_name]
            .. '.',
          {
            min = 1,
            max = to_dec and 1 or 2,
            map = function (v, n)
              local x ---@type number
              if from_radix == 10 then
                x = trunc (to_number (v[1]))
              else
                x = from_base_text (v[1], from_radix)
              end
              if to_dec then
                return x
              end
              local places = n >= 2 and to_number (v[2]) or nil
              return to_base_text (x, to_radix, places)
            end,
          }
        )
      end
    end
  end

  -------------------------------------------------------------------------------------------
  -- Roman numerals
  -------------------------------------------------------------------------------------------

  local ROMAN_CHARS = { 'M', 'D', 'C', 'L', 'X', 'V', 'I' }
  local ROMAN_VALUES = { 1000, 500, 100, 50, 10, 5, 1 }

  ---Writes a number from 0 to 3999 in Roman numerals. Form 0 is the classic one, and forms 1
  ---to 4 are ever more concise, letting a bigger numeral come after a smaller one, as in
  ---Excel: 499 is CDXCIX, LDVLIV, XDIX, VDIV and ID.
  ---@param value integer
  ---@param mode integer
  ---@return string
  local function roman (value, mode)
    local out = {} ---@type string[]
    local n = value
    for i = 0, 3 do
      local index = 2 * i + 1
      local digit = math.floor (n / ROMAN_VALUES[index])
      if digit % 5 == 4 then
        local index2 = digit == 4 and index - 1 or index - 2
        local steps = 0
        while steps < mode and index < 7 do
          steps = steps + 1
          if ROMAN_VALUES[index2] - ROMAN_VALUES[index + 1] <= n then
            index = index + 1
          else
            steps = mode
          end
        end
        out[#out + 1] = ROMAN_CHARS[index] .. ROMAN_CHARS[index2]
        n = n + ROMAN_VALUES[index] - ROMAN_VALUES[index2]
      else
        if digit > 4 then
          out[#out + 1] = ROMAN_CHARS[index - 1]
        end
        out[#out + 1] = string.rep (ROMAN_CHARS[index], digit % 5)
        n = n % ROMAN_VALUES[index]
      end
    end
    return table.concat (out)
  end

  define (
    'ROMAN',
    'Math',
    'ROMAN(number, [form])',
    'Writes a number from 0 to 3999 in Roman numerals, from classic (0) to concise (4).',
    {
      min = 1,
      max = 2,
      map = function (v, n)
        local x = trunc (to_number (v[1]))
        local mode = 0
        if n >= 2 then
          if type (v[2]) == 'boolean' then
            mode = v[2] and 0 or 4
          elseif v[2] ~= nil then
            mode = trunc (to_number (v[2]))
          end
        end
        if x < 0 or x > 3999 or mode < 0 or mode > 4 then
          return raise ('#VALUE!')
        end
        return roman (x, mode)
      end,
    }
  )

  ---@type table<string, integer>
  local ROMAN_OF = { I = 1, V = 5, X = 10, L = 50, C = 100, D = 500, M = 1000 }

  define (
    'ARABIC',
    'Math',
    'ARABIC(text)',
    'Reads a number written in Roman numerals.',
    {
      min = 1,
      max = 1,
      map = function (v)
        local text =
          string.upper (string.match (to_text (v[1]), '^%s*(.-)%s*$'))
        local sign = 1
        if string.sub (text, 1, 1) == '-' then
          sign, text = -1, string.sub (text, 2)
        end
        if #text > 255 then
          return raise ('#VALUE!')
        end
        local total = 0
        for i = 1, #text do
          local here = ROMAN_OF[string.sub (text, i, i)]
          if not here then
            return raise ('#VALUE!')
          end
          local after = ROMAN_OF[string.sub (text, i + 1, i + 1)]
          if after and after > here then
            total = total - here
          else
            total = total + here
          end
        end
        return sign * total + 0.0
      end,
    }
  )

  -------------------------------------------------------------------------------------------
  -- CONVERT
  -------------------------------------------------------------------------------------------

  ---@type table<string, Sheet.Unit>
  local UNITS = {}

  ---@param kind string
  ---@param names string Every name the unit goes by, with spaces between.
  ---@param size number
  ---@param prefix? 'metric'|'binary'
  ---@param power? integer
  local function unit (kind, names, size, prefix, power)
    for name in string.gmatch (names, '%S+') do
      UNITS[name] = { kind = kind, size = size, prefix = prefix, power = power }
    end
  end

  -- Mass, in grams.
  unit ('mass', 'g', 1, 'metric')
  unit ('mass', 'sg', 14593.902937206)
  unit ('mass', 'lbm', 453.59237)
  unit ('mass', 'u', 1.66053906660e-24, 'metric')
  unit ('mass', 'ozm', 28.349523125)
  unit ('mass', 'grain', 0.06479891)
  unit ('mass', 'cwt shweight', 45359.237)
  unit ('mass', 'uk_cwt lcwt hweight', 50802.34544)
  unit ('mass', 'stone', 6350.29318)
  unit ('mass', 'ton', 907184.74)
  unit ('mass', 'uk_ton LTON brton', 1016046.9088)
  -- Distance, in metres.
  unit ('distance', 'm', 1, 'metric')
  unit ('distance', 'mi', 1609.344)
  unit ('distance', 'Nmi', 1852)
  unit ('distance', 'in', 0.0254)
  unit ('distance', 'ft', 0.3048)
  unit ('distance', 'yd', 0.9144)
  unit ('distance', 'ang', 1e-10, 'metric')
  unit ('distance', 'ell', 1.143)
  unit ('distance', 'ly', 9460730472580800, 'metric')
  unit ('distance', 'parsec pc', 3.08567758149137e16, 'metric')
  unit ('distance', 'Picapt Pica', 0.0254 / 72)
  unit ('distance', 'pica', 0.0254 / 6)
  unit ('distance', 'survey_mi', 1609.3472186944)
  -- Time, in seconds.
  unit ('time', 'yr', 31557600)
  unit ('time', 'day d', 86400)
  unit ('time', 'hr', 3600)
  unit ('time', 'mn min', 60)
  unit ('time', 'sec s', 1, 'metric')
  -- Pressure, in pascals.
  unit ('pressure', 'Pa p', 1, 'metric')
  unit ('pressure', 'atm at', 101325, 'metric')
  unit ('pressure', 'mmHg', 133.322, 'metric')
  unit ('pressure', 'psi', 6894.75729316836)
  unit ('pressure', 'Torr', 101325 / 760)
  -- Force, in newtons.
  unit ('force', 'N', 1, 'metric')
  unit ('force', 'dyn dy', 1e-5, 'metric')
  unit ('force', 'lbf', 4.4482216152605)
  unit ('force', 'pond', 0.00980665, 'metric')
  -- Energy, in joules.
  unit ('energy', 'J', 1, 'metric')
  unit ('energy', 'e', 1e-7, 'metric')
  unit ('energy', 'c', 4.184, 'metric')
  unit ('energy', 'cal', 4.1868, 'metric')
  unit ('energy', 'eV ev', 1.602176634e-19, 'metric')
  unit ('energy', 'HPh hh', 2684519.53769617)
  unit ('energy', 'Wh wh', 3600, 'metric')
  unit ('energy', 'flb', 1.3558179483314)
  unit ('energy', 'BTU btu', 1055.05585262)
  -- Power, in watts.
  unit ('power', 'HP h', 745.69987158227)
  unit ('power', 'PS', 735.49875)
  unit ('power', 'W w', 1, 'metric')
  -- Magnetism, in teslas.
  unit ('magnetism', 'T', 1, 'metric')
  unit ('magnetism', 'ga', 1e-4, 'metric')
  -- Volume, in cubic metres.
  unit ('volume', 'tsp', 4.92892159375e-6)
  unit ('volume', 'tspm', 5e-6)
  unit ('volume', 'tbs', 1.478676478125e-5)
  unit ('volume', 'oz', 2.95735295625e-5)
  unit ('volume', 'cup', 2.365882365e-4)
  unit ('volume', 'pt us_pt', 4.73176473e-4)
  unit ('volume', 'uk_pt', 5.6826125e-4)
  unit ('volume', 'qt', 9.46352946e-4)
  unit ('volume', 'uk_qt', 1.1365225e-3)
  unit ('volume', 'gal', 3.785411784e-3)
  unit ('volume', 'uk_gal', 4.54609e-3)
  unit ('volume', 'l L lt', 1e-3, 'metric')
  unit ('volume', 'm3', 1, 'metric', 3)
  unit ('volume', 'ang3', 1e-30, 'metric', 3)
  unit ('volume', 'ft3', 0.028316846592)
  unit ('volume', 'in3', 1.6387064e-5)
  unit ('volume', 'yd3', 0.764554857984)
  unit ('volume', 'mi3', 4168181825.44058)
  unit ('volume', 'barrel', 0.158987294928)
  unit ('volume', 'bushel', 0.03523907016688)
  unit ('volume', 'GRT regton', 2.8316846592)
  unit ('volume', 'MTON', 1.13267386368)
  -- Area, in square metres.
  unit ('area', 'm2', 1, 'metric', 2)
  unit ('area', 'ang2', 1e-20, 'metric', 2)
  unit ('area', 'ar', 100, 'metric')
  unit ('area', 'ha', 10000)
  unit ('area', 'ft2', 0.09290304)
  unit ('area', 'in2', 6.4516e-4)
  unit ('area', 'yd2', 0.83612736)
  unit ('area', 'mi2', 2589988.110336)
  unit ('area', 'Nmi2', 3429904)
  unit ('area', 'uk_acre', 4046.8564224)
  unit ('area', 'us_acre', 4046.87260987425)
  unit ('area', 'Morgen', 2500)
  -- Information, in bits.
  unit ('information', 'bit', 1, 'binary')
  unit ('information', 'byte', 8, 'binary')
  -- Speed, in metres a second.
  unit ('speed', 'm/s m/sec', 1, 'metric')
  unit ('speed', 'm/h m/hr', 1 / 3600, 'metric')
  unit ('speed', 'mph', 0.44704)
  unit ('speed', 'kn', 1852 / 3600)
  unit ('speed', 'admkn', 1853.184 / 3600)
  -- Temperature, which converts by an offset as well as a scale, in kelvin.
  unit ('temperature', 'C cel', 1)
  unit ('temperature', 'F fah', 5 / 9)
  unit ('temperature', 'K kel', 1, 'metric')
  unit ('temperature', 'Rank', 5 / 9)
  unit ('temperature', 'Reau', 1.25)

  -- How far each temperature's zero is from absolute zero, in its own degrees.
  local ZERO = {
    C = 273.15,
    cel = 273.15,
    F = 459.67,
    fah = 459.67,
    K = 0,
    kel = 0,
    Rank = 0,
    Reau = 218.52,
  }

  local METRIC = {
    Y = 1e24,
    Z = 1e21,
    E = 1e18,
    P = 1e15,
    T = 1e12,
    G = 1e9,
    M = 1e6,
    k = 1e3,
    h = 1e2,
    da = 1e1,
    e = 1e1,
    d = 1e-1,
    c = 1e-2,
    m = 1e-3,
    u = 1e-6,
    n = 1e-9,
    p = 1e-12,
    f = 1e-15,
    a = 1e-18,
    z = 1e-21,
    y = 1e-24,
  }
  local BINARY = {
    ki = 2 ^ 10,
    Mi = 2 ^ 20,
    Gi = 2 ^ 30,
    Ti = 2 ^ 40,
    Pi = 2 ^ 50,
    Ei = 2 ^ 60,
    Zi = 2 ^ 70,
    Yi = 2 ^ 80,
  }

  ---A unit by its name, with a prefix when it takes one: its kind, its size and its name
  ---without the prefix. Names match case exactly, as in Excel.
  ---@param name string
  ---@return Sheet.Unit?
  ---@return number scale
  ---@return string base
  local function find_unit (name)
    local u = UNITS[name]
    if u then
      return u, 1, name
    end
    for _, len in ipairs ({ 2, 1 }) do
      local head, rest = string.sub (name, 1, len), string.sub (name, len + 1)
      local found = UNITS[rest]
      if found and found.prefix then
        local scale = found.prefix == 'binary'
            and (BINARY[head] or METRIC[head])
          or METRIC[head]
        if scale then
          return found, scale ^ (found.power or 1), rest
        end
      end
    end
    return nil, 1, name
  end

  define (
    'CONVERT',
    'Math',
    'CONVERT(number, from_unit, to_unit)',
    'Turns a measure from one unit into another, such as "mi" into "km" or "F" into "C".',
    {
      min = 3,
      max = 3,
      map = function (v)
        local x = to_number (v[1])
        local from, from_scale, from_name = find_unit (to_text (v[2]))
        local to, to_scale, to_name = find_unit (to_text (v[3]))
        if not from or not to or from.kind ~= to.kind then
          return raise ('#N/A')
        end
        if from.kind == 'temperature' then
          local kelvin = (x * from_scale + ZERO[from_name]) * from.size
          return kelvin / to.size / to_scale - ZERO[to_name]
        end
        return x * from.size * from_scale / (to.size * to_scale)
      end,
    }
  )

  -------------------------------------------------------------------------------------------
  -- Text
  -------------------------------------------------------------------------------------------

  ---The delimiters of TEXTSPLIT: one text, or an array of them.
  ---@param node Sheet.Node?
  ---@param ctx Sheet.Context
  ---@param fold boolean True to ignore case.
  ---@return string[]
  local function delimiters (node, ctx, fold)
    local out = {} ---@type string[]
    if not given (node) then
      return out
    end
    K.each (node --[[@as Sheet.Node]], ctx, function (v)
      local s = to_text (v)
      if s ~= '' then
        out[#out + 1] = fold and lower (s) or s
      end
    end)
    return out
  end

  ---Splits text at any of the delimiters. With none, the text stays whole.
  ---@param text string
  ---@param delims string[]
  ---@param fold boolean
  ---@return string[]
  local function split (text, delims, fold)
    if #delims == 0 then
      return { text }
    end
    local hay = fold and lower (text) or text
    local out = {} ---@type string[]
    local start, i = 1, 1
    while i <= #text do
      local hit = nil ---@type string?
      for _, d in ipairs (delims) do
        if string.sub (hay, i, i + #d - 1) == d and (not hit or #d > #hit) then
          hit = d
        end
      end
      if hit then
        out[#out + 1] = string.sub (text, start, i - 1)
        i = i + #hit
        start = i
      else
        i = i + 1
      end
    end
    out[#out + 1] = string.sub (text, start)
    return out
  end

  define (
    'TEXTSPLIT',
    'Text',
    'TEXTSPLIT(text, col_delimiter, [row_delimiter], [ignore_empty], [match_mode], [pad_with])',
    'Splits text into columns, and into rows, at the delimiters given.',
    {
      min = 2,
      max = 6,
      run = function (args, ctx)
        local text = text_of (args[1], ctx)
        local fold = given (args[5]) and int_of (args[5], ctx) == 1
        local cols = delimiters (args[2], ctx, fold)
        local rows = delimiters (args[3], ctx, fold)
        if #cols == 0 and #rows == 0 then
          return raise ('#VALUE!')
        end
        local skip = given (args[4]) and K.bool_of (args[4], ctx)
        local pad = K.ERRORS['#N/A'] ---@type Sheet.Value
        if given (args[6]) then
          pad = value_of (args[6], ctx)
        end
        local lines = {} ---@type string[][]
        local w = 0
        for _, line in ipairs (split (text, rows, fold)) do
          if not (skip and line == '') then
            local parts = {} ---@type string[]
            for _, part in ipairs (split (line, cols, fold)) do
              if not (skip and part == '') then
                parts[#parts + 1] = part
              end
            end
            lines[#lines + 1] = parts
            w = math.max (w, #parts)
          end
        end
        if #lines == 0 or w == 0 then
          return raise ('#CALC!')
        end
        local out = {} ---@type Sheet.Values
        for i, parts in ipairs (lines) do
          for j = 1, w do
            local part = parts[j]
            if part == nil then
              out[(i - 1) * w + j] = pad
            else
              out[(i - 1) * w + j] = part
            end
          end
        end
        return new_array (#lines, w, out)
      end,
    }
  )

  define (
    'NUMBERVALUE',
    'Text',
    'NUMBERVALUE(text, [decimal_separator], [group_separator])',
    'Reads text as a number, with the decimal and group separators given.',
    {
      min = 1,
      max = 3,
      map = function (v, n)
        if type (v[1]) == 'number' then
          return v[1]
        end
        local text = to_text (v[1])
        local point = n >= 2 and to_text (v[2]) or '.'
        local group = n >= 3 and to_text (v[3]) or ','
        point, group = string.sub (point, 1, 1), string.sub (group, 1, 1)
        if point == '' or point == group then
          return raise ('#VALUE!')
        end
        local s = string.gsub (text, '%s', '')
        if s == '' then
          return 0
        end
        local scale = 1
        while string.sub (s, -1) == '%' do
          scale = scale / 100
          s = string.sub (s, 1, -2)
        end
        local at = string.find (s, point, 1, true)
        local whole = at and string.sub (s, 1, at - 1) or s
        local frac = at and string.sub (s, at + 1) or ''
        if group ~= '' then
          local kept = {} ---@type string[]
          for i = 1, #whole do
            local ch = string.sub (whole, i, i)
            if ch ~= group then
              kept[#kept + 1] = ch
            end
          end
          whole = table.concat (kept)
          if string.find (frac, group, 1, true) then
            return raise ('#VALUE!')
          end
        end
        local x = K.parse_number (whole .. (at and '.' .. frac or ''))
        if not x or string.find (whole, ',', 1, true) then
          return raise ('#VALUE!')
        end
        return x * scale
      end,
    }
  )

  -------------------------------------------------------------------------------------------
  -- Cells and sheets
  -------------------------------------------------------------------------------------------

  ---The cell a reference argument starts at, or the formula's own cell with none.
  ---@param node Sheet.Node?
  ---@param ctx Sheet.Context
  ---@return integer row
  ---@return integer col
  ---@return string? sheet
  local function cell_of (node, ctx)
    if not given (node) then
      return ctx.row or 1, ctx.col or 1, nil
    end
    local range = reference (node --[[@as Sheet.Node]], ctx)
    if not range then
      error (K.ERRORS['#VALUE!'], 0)
    end
    return range.r1, range.c1, range.sheet
  end

  define (
    'FORMULATEXT',
    'Info',
    'FORMULATEXT(reference)',
    'Gives the formula in a cell as text.',
    {
      min = 1,
      max = 1,
      run = function (args, ctx)
        local row, col, sheet = cell_of (args[1], ctx)
        local text = ctx.formula_text and ctx.formula_text (row, col, sheet)
        if not text then
          return raise ('#N/A')
        end
        return text
      end,
    }
  )

  define (
    'ISFORMULA',
    'Info',
    'ISFORMULA(reference)',
    'Gives TRUE when a cell holds a formula.',
    {
      min = 1,
      max = 1,
      run = function (args, ctx)
        local row, col, sheet = cell_of (args[1], ctx)
        return ctx.formula_text ~= nil
          and ctx.formula_text (row, col, sheet) ~= nil
      end,
    }
  )

  define (
    'SHEET',
    'Info',
    'SHEET([value])',
    'Gives the number of a sheet in the workbook, counting from 1.',
    {
      min = 0,
      max = 1,
      run = function (args, ctx)
        local index = ctx.sheet_index
        if not index then
          return 1
        end
        local found = nil ---@type integer?
        if not given (args[1]) then
          found = index (nil)
        else
          local range = reference (args[1], ctx)
          if range then
            found = index (range.sheet)
          else
            found = index (to_text (value_of (args[1], ctx)))
          end
        end
        if not found then
          return raise ('#N/A')
        end
        return found + 0.0
      end,
    }
  )

  define (
    'SHEETS',
    'Info',
    'SHEETS([reference])',
    'Counts the sheets in the workbook, or in a reference.',
    {
      min = 0,
      max = 1,
      run = function (args, ctx)
        if given (args[1]) then
          if not reference (args[1], ctx) then
            return raise ('#VALUE!')
          end
          return 1
        end
        return (ctx.sheet_count and ctx.sheet_count () or 1) + 0.0
      end,
    }
  )

  define (
    'CELL',
    'Info',
    'CELL(info_type, [reference])',
    'Tells about a cell: its "address", "row", "col", "contents" or "type".',
    {
      min = 1,
      max = 2,
      run = function (args, ctx)
        local info = lower (text_of (args[1], ctx))
        local row, col, sheet = cell_of (args[2], ctx)
        if info == 'address' then
          local head = sheet and (K.quote_sheet (sheet) .. '!') or ''
          return head
            .. '$'
            .. K.col_name (col)
            .. '$'
            .. string.format ('%d', row)
        elseif info == 'row' then
          return row + 0.0
        elseif info == 'col' then
          return col + 0.0
        end
        local v = ctx.value (row, col, sheet)
        if info == 'contents' then
          if v == nil then
            return 0
          end
          return v
        elseif info == 'type' then
          if v == nil then
            return 'b'
          end
          return type (v) == 'string' and 'l' or 'v'
        end
        return raise ('#VALUE!')
      end,
    }
  )

  define (
    'HYPERLINK',
    'Info',
    'HYPERLINK(link_location, [friendly_name])',
    'Shows a link: its friendly name, or the address when there is none.',
    {
      min = 1,
      max = 2,
      map = function (v, n)
        if n >= 2 and v[2] ~= nil then
          return v[2]
        end
        return to_text (v[1])
      end,
    }
  )
end
