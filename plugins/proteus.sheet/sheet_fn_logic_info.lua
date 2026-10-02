-- sheet_fn_logic_info: the logic and information functions of the Sheet app's formulas: IF
-- and its kin, AND, OR and SWITCH, and the tests of what a value is, such as ISBLANK, TYPE
-- and ERROR.TYPE. sheet_formula loads the module.

---@param K Sheet.FormulaKit
return function (K)
  local define, test1, raise, raise_value =
    K.define, K.test1, K.raise, K.raise_value
  local ERRORS, MANY = K.ERRORS, K.MANY
  local is_error, is_grid = K.is_error, K.is_grid
  local dims, grid_at, spread_at, new_array, single =
    K.dims, K.grid_at, K.spread_at, K.new_array, K.single
  local eval, value_of, bool_of, int_of =
    K.eval, K.value_of, K.bool_of, K.int_of
  local logicals, compare = K.logicals, K.compare
  local to_bool, to_number, trunc = K.to_bool, K.to_number, K.trunc

  -------------------------------------------------------------------------------------------
  -- Logic
  -------------------------------------------------------------------------------------------

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
                out[k] =
                  spread_at (pick --[[@as Sheet.Grid]], ph, pw, i, j, ctx)
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

  -------------------------------------------------------------------------------------------
  -- Info
  -------------------------------------------------------------------------------------------

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
        return ok
          and type (v) == 'table'
          and (v --[[@as table]]).is_range == true
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
end
