-- sheet_formula_eval: the evaluator of the Sheet app's formula language. It turns cell values
-- into numbers, text and truth values, compares them, reads blocks of cells and the blocks
-- formulas spill, and walks a formula's tree to work out its value, with LET and LAMBDA names.

local lexer = require ('sheet_formula_lex') --[[@as Sheet.FormulaLex]]
local parser = require ('sheet_formula_parse') --[[@as Sheet.FormulaParse]]

---@class Sheet.FormulaModule
local M = lexer.M
local COMPARE, FUNCS = parser.COMPARE, parser.FUNCS
local ERRORS, LAST_COL, LAST_ROW, clean =
  lexer.ERRORS, lexer.LAST_COL, lexer.LAST_ROW, lexer.clean
local finite, is_error, lower, parse_datetime =
  lexer.finite, lexer.is_error, lexer.lower, lexer.parse_datetime
local raise, raise_value = lexer.raise, lexer.raise_value

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
  if
    (v --[[@as table]]).is_union
  then
    return raise ('#VALUE!')
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

-- How deep names may name other names. A name that names itself goes round for ever, so it
-- stops here with #CYCLE!.
local NAME_DEPTH = 32

---The value of a name the workbook defines, such as `Rates` for `=Sheet1!$B$2:$B$5`, and
---whether there is one. The name's formula sees none of the names LET gives.
---@param ctx Sheet.Context
---@param name string In upper case.
---@return Sheet.Result
---@return boolean
local function defined (ctx, name)
  local find = ctx.name
  local ast = find and find (name)
  if not ast then
    return nil, false
  end
  local depth = ctx.name_depth or 0
  if depth >= NAME_DEPTH then
    return raise ('#CYCLE!'), true
  end
  ctx.name_depth = depth + 1
  local ok, result = pcall (within, ctx, nil, function ()
    return eval (ast, ctx)
  end)
  ctx.name_depth = depth
  if not ok then
    error (result, 0)
  end
  return result, true
end

---A side of a reference operator as a block of cells: a cell reference stays a block rather
---than giving its value.
---@param node Sheet.Node
---@param ctx Sheet.Context
---@return Sheet.Result
local function as_reference (node, ctx)
  if node.kind == 'ref' then
    return cell_range (node.a --[[@as Sheet.Ref]], ctx)
  end
  return eval (node, ctx)
end

---The cells two references share, for the intersection operator, or #NULL! when they share
---none.
---@param node Sheet.Node
---@param ctx Sheet.Context
---@return Sheet.Result
local function intersection (node, ctx)
  local a = as_reference (node.left --[[@as Sheet.Node]], ctx)
  local b = as_reference (node.right --[[@as Sheet.Node]], ctx)
  if
    type (a) ~= 'table'
    or type (b) ~= 'table'
    or not (a --[[@as table]]).is_range
    or not (b --[[@as table]]).is_range
  then
    return raise ('#VALUE!')
  end
  local ra, rb =
    a, --[[@as Sheet.RangeValue]]
    b --[[@as Sheet.RangeValue]]
  if string.lower (ra.sheet or '') ~= string.lower (rb.sheet or '') then
    return raise ('#NULL!')
  end
  local r1, c1 = math.max (ra.r1, rb.r1), math.max (ra.c1, rb.c1)
  local r2, c2 = math.min (ra.r2, rb.r2), math.min (ra.c2, rb.c2)
  if r1 > r2 or c1 > c2 then
    return raise ('#NULL!')
  end
  ---@type Sheet.RangeValue
  local out =
    { is_range = true, r1 = r1, c1 = c1, r2 = r2, c2 = c2, sheet = ra.sheet }
  return out
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
    -- A defined name can hold a LAMBDA, which works as a function of the workbook's own.
    local fn, found = defined (ctx, node.name or '')
    if found then
      return invoke (fn, node.args or {}, ctx)
    end
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
    v, found = defined (ctx, node.name or '')
    if found then
      return v
    end
    return raise ('#NAME?')
  end
  if kind == 'invoke' then
    local fn = eval (node.left --[[@as Sheet.Node]], ctx)
    return invoke (fn, node.args or {}, ctx)
  end
  if kind == 'intersect' then
    return intersection (node, ctx)
  end
  if kind == 'union' then
    local areas = {} ---@type Sheet.RangeValue[]
    for _, part in ipairs (node.args or {}) do
      local v = as_reference (part, ctx)
      if
        type (v) == 'table' and (v --[[@as table]]).is_union
      then
        for _, area in
          ipairs ((v --[[@as Sheet.Union]]).areas)
        do
          areas[#areas + 1] = area
        end
      elseif
        type (v) == 'table' and (v --[[@as table]]).is_range
      then
        areas[#areas + 1] = v --[[@as Sheet.RangeValue]]
      else
        return raise ('#VALUE!')
      end
    end
    ---@type Sheet.Union
    local union = { is_union = true, areas = areas }
    return union --[[@as any]]
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
  if
    ok
    and type (result) == 'table'
    and (result --[[@as table]]).is_union
  then
    return ERRORS['#VALUE!']
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

---What the other parts of the formula language share from this one.
---@class Sheet.FormulaEval
local P = {
  EMPTY = EMPTY,
  apply = apply,
  cell_range = cell_range,
  compare = compare,
  dims = dims,
  eval = eval,
  grid_at = grid_at,
  is_grid = is_grid,
  is_lambda = is_lambda,
  new_array = new_array,
  num_compare = num_compare,
  on_sheet = on_sheet,
  resolve = resolve,
  same_number = same_number,
  scalar = scalar,
  sheet_size = sheet_size,
  single = single,
  spread_at = spread_at,
  text_number = text_number,
  to_bool = to_bool,
  to_number = to_number,
  to_text = to_text,
  within = within,
}

return P
