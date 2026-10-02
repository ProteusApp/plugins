-- sheet_fn_arrays: the functions of the Sheet app's formulas that make arrays, and LET and
-- LAMBDA. SEQUENCE, UNIQUE, SORT, SORTBY and FILTER give a block of values, which spills into
-- the cells around the formula. LET names values inside a formula, and LAMBDA makes a function
-- that MAP, REDUCE, SCAN, BYROW, BYCOL and MAKEARRAY call. sheet_formula_kit loads the module.

---A key that SORT and SORTBY sort the lines of a block by.
---@class Sheet.ArraySortKey
---@field get fun(line: integer): Sheet.Value The value of a row or a column to compare.
---@field order integer 1 sorts up and -1 down.

---@param K Sheet.FormulaKit
return function (K)
  local define, raise, raise_value = K.define, K.raise, K.raise_value
  local ERRORS, MANY, EMPTY = K.ERRORS, K.MANY, K.EMPTY
  local is_error, is_lambda, is_grid = K.is_error, K.is_lambda, K.is_grid
  local dims, grid_at, new_array = K.dims, K.grid_at, K.new_array
  local eval, grid_or_value, apply, within =
    K.eval, K.grid_or_value, K.apply, K.within
  local given, int_of, number_of, bool_of =
    K.given, K.int_of, K.number_of, K.bool_of
  local to_number, to_bool, trunc = K.to_number, K.to_bool, K.trunc
  local compare, lower = K.compare, K.lower

  -- The most cells a function such as SEQUENCE or MAKEARRAY makes.
  local MAX_CELLS = 1000000

  ---A block, an array or one value as its height, its width and its values row by row.
  ---@param v Sheet.Result
  ---@param ctx Sheet.Context
  ---@return integer h
  ---@return integer w
  ---@return Sheet.Values
  local function grid_values (v, ctx)
    if is_lambda (v) then
      error (ERRORS['#CALC!'], 0)
    end
    if not is_grid (v) then
      return 1, 1, {
        v --[[@as Sheet.Value]],
      }
    end
    local h, w = dims (v)
    local g = v --[[@as Sheet.Grid]]
    if g.is_array then
      return h, w, (g --[[@as Sheet.Array]]).v
    end
    local out = {} ---@type Sheet.Values
    for i = 1, h do
      for j = 1, w do
        out[(i - 1) * w + j] = grid_at (g, i, j, ctx)
      end
    end
    return h, w, out
  end

  ---The values of an argument, as `grid_values` gives them.
  ---@param node Sheet.Node
  ---@param ctx Sheet.Context
  ---@return integer h
  ---@return integer w
  ---@return Sheet.Values
  local function values_of (node, ctx)
    return grid_values (grid_or_value (node, ctx), ctx)
  end

  ---An argument that must be a LAMBDA.
  ---@param node Sheet.Node
  ---@param ctx Sheet.Context
  ---@return Sheet.Lambda
  local function lambda_of (node, ctx)
    local fn = eval (node, ctx)
    if not is_lambda (fn) then
      return raise ('#VALUE!')
    end
    return fn --[[@as Sheet.Lambda]]
  end

  ---Calls a LAMBDA for one value of an array it builds. An error comes back as the value, and a
  ---block of more than one cell is #CALC!, since a cell of an array holds one value.
  ---@param fn Sheet.Lambda
  ---@param values table<integer, Sheet.Result>
  ---@param n integer
  ---@param ctx Sheet.Context
  ---@return Sheet.Value
  local function apply_one (fn, values, n, ctx)
    local ok, res = pcall (apply, fn, values, n, ctx)
    if not ok then
      if is_error (res) then
        return res --[[@as Sheet.Error]]
      end
      error (res, 0)
    end
    if is_lambda (res) then
      return ERRORS['#CALC!']
    end
    if is_grid (res) then
      local h, w = dims (res)
      if h ~= 1 or w ~= 1 then
        return ERRORS['#CALC!']
      end
      return grid_at (res --[[@as Sheet.Grid]], 1, 1, ctx)
    end
    return res --[[@as Sheet.Value]]
  end

  -- How values sort in SORT and SORTBY: numbers, then text, then TRUE and FALSE, then errors,
  -- with empty cells last.
  local SORT_RANK = { number = 1, string = 2, boolean = 3, table = 4 }

  ---Compares two values for SORT: -1, 0 or 1.
  ---@param a Sheet.Value
  ---@param b Sheet.Value
  ---@return integer
  local function sort_compare (a, b)
    local ra, rb = SORT_RANK[type (a)] or 5, SORT_RANK[type (b)] or 5
    if ra ~= rb then
      return ra < rb and -1 or 1
    end
    if ra == 4 or ra == 5 then
      return 0
    end
    return compare (a, b)
  end

  ---A key for a value that is the same for values UNIQUE counts as the same: text ignores case,
  ---and numbers agree to 15 digits.
  ---@param v Sheet.Value
  ---@return string
  local function value_key (v)
    local t = type (v)
    local part ---@type string
    if v == nil then
      part = 'e'
    elseif t == 'number' then
      part = 'n' .. string.format ('%.15g', v)
    elseif t == 'string' then
      part = 's' .. lower (v --[[@as string]])
    elseif t == 'boolean' then
      part = v and 'bt' or 'bf'
    else
      part = 'x' .. (v --[[@as Sheet.Error]]).code
    end
    return #part .. ':' .. part
  end

  ---Takes rows of a block, or columns with `by_col`, in a new order. Each entry of `order` is a
  ---row, or a column, of the block.
  ---@param h integer
  ---@param w integer
  ---@param v Sheet.Values
  ---@param order integer[]
  ---@param by_col boolean
  ---@return Sheet.Array
  local function pick (h, w, v, order, by_col)
    local out = {} ---@type Sheet.Values
    if by_col then
      local nw = #order
      for i = 1, h do
        for k, j in ipairs (order) do
          out[(i - 1) * nw + k] = v[(i - 1) * w + j]
        end
      end
      return new_array (h, nw, out)
    end
    for k, i in ipairs (order) do
      for j = 1, w do
        out[(k - 1) * w + j] = v[(i - 1) * w + j]
      end
    end
    return new_array (#order, w, out)
  end

  ---Puts the rows of a block, or its columns with `by_col`, in order of keys. Each key gives the
  ---value of a line to sort by and the order, 1 up or -1 down. Equal lines keep their order.
  ---@param h integer
  ---@param w integer
  ---@param v Sheet.Values
  ---@param keys Sheet.ArraySortKey[]
  ---@param by_col boolean
  ---@return Sheet.Array
  local function sorted_lines (h, w, v, keys, by_col)
    local count = by_col and w or h
    local order = {} ---@type integer[]
    for k = 1, count do
      order[k] = k
    end
    table.sort (order, function (x, y)
      for _, key in ipairs (keys) do
        local c = sort_compare (key.get (x), key.get (y))
        if c ~= 0 then
          return c * key.order < 0
        end
      end
      return x < y
    end)
    return pick (h, w, v, order, by_col)
  end

  ---A sort order argument: 1 for up, -1 for down.
  ---@param x number
  ---@return integer
  local function sort_order (x)
    if x == 1 or x == -1 then
      return math.floor (x)
    end
    return raise ('#VALUE!')
  end

  define (
    'SEQUENCE',
    'Math',
    'SEQUENCE(rows, [columns], [start], [step])',
    'Makes an array of numbers that count up from a start, row by row.',
    {
      min = 1,
      max = 4,
      run = function (args, ctx)
        local h = int_of (args[1], ctx)
        local w = given (args[2]) and int_of (args[2], ctx) or 1
        local start = given (args[3]) and number_of (args[3], ctx) or 1
        local step = given (args[4]) and number_of (args[4], ctx) or 1
        if h < 0 or w < 0 then
          return raise ('#VALUE!')
        end
        if h == 0 or w == 0 then
          return raise ('#CALC!')
        end
        if h * w > MAX_CELLS then
          return raise ('#NUM!')
        end
        local out = {} ---@type Sheet.Values
        for k = 1, h * w do
          out[k] = start + (k - 1) * step + 0.0
        end
        return new_array (h, w, out)
      end,
    }
  )

  define (
    'UNIQUE',
    'Lookup',
    'UNIQUE(array, [by_col], [exactly_once])',
    'Gives the rows of a block without repeats, or only the rows that come up once.',
    {
      min = 1,
      max = 3,
      run = function (args, ctx)
        local h, w, v = values_of (args[1], ctx)
        local by_col = given (args[2]) and bool_of (args[2], ctx)
        local once = given (args[3]) and bool_of (args[3], ctx)
        local count = by_col and w or h
        local keys = {} ---@type string[]
        local seen = {} ---@type table<string, integer>
        for k = 1, count do
          local parts = {} ---@type string[]
          local across = by_col and h or w
          for m = 1, across do
            local x = by_col and v[(m - 1) * w + k] or v[(k - 1) * w + m]
            parts[m] = value_key (x)
          end
          local key = table.concat (parts, '|')
          keys[k] = key
          seen[key] = (seen[key] or 0) + 1
        end
        local order = {} ---@type integer[]
        local taken = {} ---@type table<string, boolean>
        for k = 1, count do
          local key = keys[k]
          if not taken[key] and (not once or seen[key] == 1) then
            taken[key] = true
            order[#order + 1] = k
          end
        end
        if #order == 0 then
          return raise ('#CALC!')
        end
        return pick (h, w, v, order, by_col)
      end,
    }
  )

  define (
    'SORT',
    'Lookup',
    'SORT(array, [sort_index], [sort_order], [by_col])',
    'Sorts the rows of a block by one of its columns, or its columns by a row.',
    {
      min = 1,
      max = 4,
      run = function (args, ctx)
        local h, w, v = values_of (args[1], ctx)
        local by_col = given (args[4]) and bool_of (args[4], ctx)
        local indexes = { 1 } ---@type Sheet.Values
        if given (args[2]) then
          local _, _, list = values_of (args[2], ctx)
          indexes = list
        end
        local orders = { 1 } ---@type Sheet.Values
        if given (args[3]) then
          local _, _, list = values_of (args[3], ctx)
          orders = list
        end
        local across = by_col and h or w
        local keys = {} ---@type Sheet.ArraySortKey[]
        for k, x in ipairs (indexes) do
          local at = trunc (to_number (x))
          if at < 1 or at > across then
            return raise ('#VALUE!')
          end
          local o = orders[k] or orders[#orders] or 1
          keys[k] = {
            order = sort_order (to_number (o)),
            get = function (line)
              if by_col then
                return v[(at - 1) * w + line]
              end
              return v[(line - 1) * w + at]
            end,
          }
        end
        return sorted_lines (h, w, v, keys, by_col == true)
      end,
    }
  )

  define (
    'SORTBY',
    'Lookup',
    'SORTBY(array, by_array1, [sort_order1], [by_array2, sort_order2], ...)',
    'Sorts the rows or columns of a block by the values of other blocks.',
    {
      min = 2,
      max = MANY,
      run = function (args, ctx)
        local h, w, v = values_of (args[1], ctx)
        local keys = {} ---@type Sheet.ArraySortKey[]
        local by_col = nil ---@type boolean?
        for k = 2, #args, 2 do
          local bh, bw, bv = values_of (args[k], ctx)
          local cols ---@type boolean
          if bw == 1 and bh == h then
            cols = false
          elseif bh == 1 and bw == w then
            cols = true
          else
            return raise ('#VALUE!')
          end
          if by_col ~= nil and by_col ~= cols then
            return raise ('#VALUE!')
          end
          by_col = cols
          local o = given (args[k + 1]) and number_of (args[k + 1], ctx) or 1
          keys[#keys + 1] = {
            order = sort_order (o),
            get = function (line)
              return bv[line]
            end,
          }
        end
        return sorted_lines (h, w, v, keys, by_col == true)
      end,
    }
  )

  define (
    'FILTER',
    'Lookup',
    'FILTER(array, include, [if_empty])',
    'Gives the rows, or the columns, of a block where a test is TRUE.',
    {
      min = 2,
      max = 3,
      run = function (args, ctx)
        local h, w, v = values_of (args[1], ctx)
        local ih, iw, inc = values_of (args[2], ctx)
        local by_col ---@type boolean
        if iw == 1 and ih == h then
          by_col = false
        elseif ih == 1 and iw == w then
          by_col = true
        else
          return raise ('#VALUE!')
        end
        local order = {} ---@type integer[]
        for k = 1, by_col and w or h do
          local x = inc[k]
          if type (x) == 'table' then
            return raise_value (x)
          end
          if x ~= nil and type (x) ~= 'string' and to_bool (x) then
            order[#order + 1] = k
          end
        end
        if #order == 0 then
          if given (args[3]) then
            return grid_or_value (args[3], ctx)
          end
          return raise ('#CALC!')
        end
        return pick (h, w, v, order, by_col)
      end,
    }
  )

  define (
    'LET',
    'Logic',
    'LET(name1, value1, [name2, value2], ..., calculation)',
    'Gives names to values, then works out a calculation that uses the names.',
    {
      min = 3,
      max = MANY,
      run = function (args, ctx)
        local n = #args
        if n % 2 == 0 then
          return raise ('#VALUE!')
        end
        local names = {} ---@type table<string, Sheet.Result|Sheet.Lambda>
        return within (ctx, { names = names, parent = ctx.scope }, function ()
          for i = 1, n - 1, 2 do
            local node = args[i]
            if node.kind ~= 'name' then
              return raise ('#VALUE!')
            end
            local value = grid_or_value (args[i + 1], ctx)
            if value == nil then
              names[
                node.name --[[@as string]]
              ] =
                EMPTY
            else
              names[
                node.name --[[@as string]]
              ] =
                value
            end
          end
          return eval (args[n], ctx)
        end)
      end,
    }
  )

  define (
    'LAMBDA',
    'Logic',
    'LAMBDA([parameter1, parameter2, ...], calculation)',
    'Makes a function from a calculation, to call with values for its parameters.',
    {
      min = 1,
      max = MANY,
      run = function (args, ctx)
        local n = #args
        local params = {} ---@type string[]
        for i = 1, n - 1 do
          local node = args[i]
          if node.kind ~= 'name' then
            return raise ('#VALUE!')
          end
          params[i] = node.name --[[@as string]]
        end
        ---@type Sheet.Lambda
        local fn = {
          is_lambda = true,
          params = params,
          body = args[n],
          scope = ctx.scope,
        }
        return fn
      end,
    }
  )

  define (
    'MAP',
    'Logic',
    'MAP(array1, [array2], ..., lambda)',
    'Calls a LAMBDA for each value of one or more blocks, and gives the results in their shape.',
    {
      min = 2,
      max = MANY,
      run = function (args, ctx)
        local n = #args
        local fn = lambda_of (args[n], ctx)
        local blocks = {} ---@type Sheet.Values[]
        local h, w = 1, 1
        for i = 1, n - 1 do
          local bh, bw, bv = values_of (args[i], ctx)
          if i == 1 then
            h, w = bh, bw
          elseif bh ~= h or bw ~= w then
            return raise ('#VALUE!')
          end
          blocks[i] = bv
        end
        local out = {} ---@type Sheet.Values
        for k = 1, h * w do
          local values = {} ---@type table<integer, Sheet.Result>
          for i = 1, n - 1 do
            values[i] = blocks[i][k]
          end
          out[k] = apply_one (fn, values, n - 1, ctx)
        end
        return new_array (h, w, out)
      end,
    }
  )

  ---The start, the values and the LAMBDA of REDUCE and SCAN, whose start may be left out.
  ---@param args Sheet.Node[]
  ---@param ctx Sheet.Context
  ---@return Sheet.Result start
  ---@return integer h
  ---@return integer w
  ---@return Sheet.Values
  ---@return Sheet.Lambda
  local function fold_args (args, ctx)
    local start = nil ---@type Sheet.Result
    local first = 1
    if #args == 3 then
      if given (args[1]) then
        start = grid_or_value (args[1], ctx)
      end
      first = 2
    end
    local h, w, v = values_of (args[first], ctx)
    return start, h, w, v, lambda_of (args[first + 1], ctx)
  end

  define (
    'REDUCE',
    'Logic',
    'REDUCE([initial_value], array, lambda)',
    'Runs a total through a LAMBDA, one value of a block after another.',
    {
      min = 2,
      max = 3,
      run = function (args, ctx)
        local acc, h, w, v, fn = fold_args (args, ctx)
        for k = 1, h * w do
          acc = apply (fn, { acc, v[k] }, 2, ctx)
        end
        if acc == nil then
          return 0.0
        end
        return acc
      end,
    }
  )

  define (
    'SCAN',
    'Logic',
    'SCAN([initial_value], array, lambda)',
    'Runs a total through a LAMBDA, and gives the total after each value of a block.',
    {
      min = 2,
      max = 3,
      run = function (args, ctx)
        local acc, h, w, v, fn = fold_args (args, ctx)
        local out = {} ---@type Sheet.Values
        for k = 1, h * w do
          local next_acc = apply_one (fn, { acc, v[k] }, 2, ctx)
          out[k] = next_acc
          acc = next_acc
        end
        return new_array (h, w, out)
      end,
    }
  )

  ---BYROW and BYCOL: a LAMBDA gets each row, or each column, as an array, and gives one value.
  ---@param by_col boolean
  ---@return Sheet.Function
  local function by_line (by_col)
    return {
      min = 2,
      max = 2,
      run = function (args, ctx)
        local h, w, v = values_of (args[1], ctx)
        local fn = lambda_of (args[2], ctx)
        local out = {} ---@type Sheet.Values
        for k = 1, by_col and w or h do
          local line = pick (h, w, v, { k }, by_col)
          out[k] = apply_one (fn, { line }, 1, ctx)
        end
        if by_col then
          return new_array (1, w, out)
        end
        return new_array (h, 1, out)
      end,
    }
  end

  define (
    'BYROW',
    'Logic',
    'BYROW(array, lambda)',
    'Calls a LAMBDA with each row of a block, and gives one value for each row.',
    by_line (false)
  )

  define (
    'BYCOL',
    'Logic',
    'BYCOL(array, lambda)',
    'Calls a LAMBDA with each column of a block, and gives one value for each column.',
    by_line (true)
  )

  define (
    'MAKEARRAY',
    'Logic',
    'MAKEARRAY(rows, columns, lambda)',
    'Makes an array by calling a LAMBDA with the row and the column of each value.',
    {
      min = 3,
      max = 3,
      run = function (args, ctx)
        local h, w = int_of (args[1], ctx), int_of (args[2], ctx)
        local fn = lambda_of (args[3], ctx)
        if h < 1 or w < 1 then
          return raise ('#VALUE!')
        end
        if h * w > MAX_CELLS then
          return raise ('#NUM!')
        end
        local out = {} ---@type Sheet.Values
        for i = 1, h do
          for j = 1, w do
            out[(i - 1) * w + j] = apply_one (fn, { i + 0.0, j + 0.0 }, 2, ctx)
          end
        end
        return new_array (h, w, out)
      end,
    }
  )
end
