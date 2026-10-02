-- sheet_formula_kit: what the functions of the Sheet app's formulas are made with. The helpers
-- read arguments, match criteria such as ">5" or "a*", and work out sums, spreads and fits.
-- `define` adds a function and its catalog entry. The kit hands both to each function module,
-- one per category, and the catalog is sorted once they have all joined it.

local evaluator = require ('sheet_formula_eval') --[[@as Sheet.FormulaEval]]
local lexer = require ('sheet_formula_lex') --[[@as Sheet.FormulaLex]]
local parser = require ('sheet_formula_parse') --[[@as Sheet.FormulaParse]]

---@class Sheet.FormulaModule
local M = lexer.M
local COMPARE, FUNCS = parser.COMPARE, parser.FUNCS
local EMPTY, apply, cell_range, compare =
  evaluator.EMPTY, evaluator.apply, evaluator.cell_range, evaluator.compare
local dims, eval, grid_at, is_grid =
  evaluator.dims, evaluator.eval, evaluator.grid_at, evaluator.is_grid
local is_lambda, new_array, num_compare, on_sheet =
  evaluator.is_lambda,
  evaluator.new_array,
  evaluator.num_compare,
  evaluator.on_sheet
local resolve, same_number, scalar, sheet_size =
  evaluator.resolve,
  evaluator.same_number,
  evaluator.scalar,
  evaluator.sheet_size
local single, spread_at, text_number, to_bool =
  evaluator.single,
  evaluator.spread_at,
  evaluator.text_number,
  evaluator.to_bool
local to_number, to_text, within =
  evaluator.to_number, evaluator.to_text, evaluator.within
local ERRORS, LAST_COL, LAST_DAY, LAST_ROW =
  lexer.ERRORS, lexer.LAST_COL, lexer.LAST_DAY, lexer.LAST_ROW
local MANY, atan, byte_of, chars =
  lexer.MANY, lexer.atan, lexer.byte_of, lexer.chars
local clean, days_in_month, finite, is_error =
  lexer.clean, lexer.days_in_month, lexer.finite, lexer.is_error
local is_leap, length, log, lower =
  lexer.is_leap, lexer.length, lexer.log, lexer.lower
local make_date, parse_datetime, raise, raise_value =
  lexer.make_date, lexer.parse_datetime, lexer.raise, lexer.raise_value
local round_to, sheet_prefix, trunc, upper =
  lexer.round_to, lexer.sheet_prefix, lexer.trunc, lexer.upper
local weekday0, wildcard, ymd = lexer.weekday0, lexer.wildcard, lexer.ymd

---------------------------------------------------------------------------------------------
-- Function helpers
---------------------------------------------------------------------------------------------

---@param node Sheet.Node
---@param ctx Sheet.Context
---@return Sheet.Value
local function value_of (node, ctx)
  return scalar (eval (node, ctx), ctx)
end

---@param node Sheet.Node
---@param ctx Sheet.Context
---@return number
local function number_of (node, ctx)
  return to_number (value_of (node, ctx))
end

---@param node Sheet.Node
---@param ctx Sheet.Context
---@return string
local function text_of (node, ctx)
  return to_text (value_of (node, ctx))
end

---@param node Sheet.Node
---@param ctx Sheet.Context
---@return boolean
local function bool_of (node, ctx)
  return to_bool (value_of (node, ctx))
end

---A whole number from an argument, cut toward zero.
---@param node Sheet.Node
---@param ctx Sheet.Context
---@return integer
local function int_of (node, ctx)
  return trunc (number_of (node, ctx))
end

---True when an argument is there and not left empty, as the last one in `ROUND(1.5, )`.
---@param node Sheet.Node?
---@return boolean
local function given (node)
  return node ~= nil and node.kind ~= 'empty'
end

---The block of cells an argument names, or nil when it is not a reference. A function such
---as INDIRECT or OFFSET can name one too.
---@param node Sheet.Node
---@param ctx Sheet.Context
---@return Sheet.RangeValue?
local function reference (node, ctx)
  local kind = node.kind
  if kind == 'ref' then
    return cell_range (node.a --[[@as Sheet.Ref]], ctx)
  end
  if kind == 'range' then
    return resolve (node.a --[[@as Sheet.Ref]], node.b --[[@as Sheet.Ref]], ctx)
  end
  if
    kind == 'call'
    or kind == 'name'
    or kind == 'invoke'
    or kind == 'spill'
    or kind == 'intersect'
  then
    local v = eval (node, ctx)
    if
      type (v) == 'table' and (v --[[@as table]]).is_range
    then
      return v --[[@as Sheet.RangeValue]]
    end
  end
  return nil
end

---@param node Sheet.Node
---@param ctx Sheet.Context
---@return Sheet.RangeValue
local function need_reference (node, ctx)
  return reference (node, ctx) or raise ('#VALUE!')
end

---An argument as a block of cells or an array, or its one value. A reference to one cell
---stays a block, so an error in the cell does not raise.
---@param node Sheet.Node
---@param ctx Sheet.Context
---@return Sheet.Result
local function grid_or_value (node, ctx)
  local kind = node.kind
  if kind == 'ref' then
    return cell_range (node.a --[[@as Sheet.Ref]], ctx)
  end
  if kind == 'range' then
    return resolve (node.a --[[@as Sheet.Ref]], node.b --[[@as Sheet.Ref]], ctx)
  end
  return eval (node, ctx)
end

---An argument that must be a block of cells or an array.
---@param node Sheet.Node
---@param ctx Sheet.Context
---@return Sheet.Grid
local function need_grid (node, ctx)
  local v = grid_or_value (node, ctx)
  if not is_grid (v) then
    return raise ('#VALUE!')
  end
  return v --[[@as Sheet.Grid]]
end

---Calls `fn` with every value an argument holds. A reference, a block or an array gives each
---value and true. Anything else gives its one value and false. An empty argument gives nothing.
---@param node Sheet.Node
---@param ctx Sheet.Context
---@param fn fun(v: Sheet.Value, in_ref: boolean)
local function each (node, ctx, fn)
  local kind = node.kind
  if kind == 'empty' then
    return
  end
  if kind == 'ref' then
    local a = node.a --[[@as Sheet.Ref]]
    on_sheet (a.row, a.col)
    if a.sheet then
      sheet_size (a.sheet, ctx)
    end
    fn (
      ctx.value (a.row --[[@as integer]], a.col --[[@as integer]], a.sheet),
      true
    )
    return
  end
  local v = grid_or_value (node, ctx)
  if type (v) ~= 'table' then
    fn (v --[[@as Sheet.Value]], false)
    return
  end
  local t = v --[[@as table]]
  if t.is_union then
    local value = ctx.value
    for _, area in
      ipairs ((t --[[@as Sheet.Union]]).areas)
    do
      for r = area.r1, area.r2 do
        for c = area.c1, area.c2 do
          fn (value (r, c, area.sheet), true)
        end
      end
    end
  elseif t.is_range then
    local sheet = t.sheet --[[@as string?]]
    local value = ctx.value
    for r = t.r1, t.r2 do
      for c = t.c1, t.c2 do
        fn (value (r, c, sheet), true)
      end
    end
  else
    local list = t.v --[[@as Sheet.Values]]
    for k = 1, t.h * t.w do
      fn (list[k], true)
    end
  end
end

---The numbers in the arguments of SUM and its kin, from `first` to `last`. Cells skip text and
---TRUE or FALSE, while an argument typed in the formula counts as a number or fails.
---@param args Sheet.Node[]
---@param ctx Sheet.Context
---@param first? integer
---@param last? integer
---@return number[]
local function numbers (args, ctx, first, last)
  local out = {} ---@type number[]
  ---@param v Sheet.Value
  ---@param in_ref boolean
  local function add (v, in_ref)
    if in_ref then
      if type (v) == 'number' then
        out[#out + 1] = v
      elseif type (v) == 'table' then
        raise_value (v)
      end
    else
      out[#out + 1] = to_number (v)
    end
  end
  for k = first or 1, last or #args do
    each (args[k], ctx, add)
  end
  return out
end

---The TRUE and FALSE values in the arguments of AND, OR and XOR.
---@param args Sheet.Node[]
---@param ctx Sheet.Context
---@return boolean[]
local function logicals (args, ctx)
  local out = {} ---@type boolean[]
  ---@param v Sheet.Value
  ---@param in_ref boolean
  local function add (v, in_ref)
    if in_ref then
      if type (v) == 'boolean' then
        out[#out + 1] = v
      elseif type (v) == 'number' then
        out[#out + 1] = v ~= 0
      elseif type (v) == 'table' then
        raise_value (v)
      end
    else
      out[#out + 1] = to_bool (v)
    end
  end
  for _, node in ipairs (args) do
    each (node, ctx, add)
  end
  if #out == 0 then
    return raise ('#VALUE!')
  end
  return out
end

---@param a any
---@param b any
---@param op string
---@return boolean
local function ordered (a, b, op)
  if type (a) == 'number' and type (b) == 'number' then
    local c = num_compare (a, b)
    if op == '<' then
      return c < 0
    elseif op == '>' then
      return c > 0
    elseif op == '<=' then
      return c <= 0
    end
    return c >= 0
  end
  if op == '<' then
    return a < b
  elseif op == '>' then
    return a > b
  elseif op == '<=' then
    return a <= b
  end
  return a >= b
end

---True when a cell holds the number `num`, as a number or as text that reads as one.
---@param v Sheet.Value
---@param num number
---@return boolean
local function holds_number (v, num)
  if type (v) == 'number' then
    return same_number (v, num)
  end
  if type (v) == 'string' then
    local n = M.parse_number (v)
    return n ~= nil and same_number (n, num)
  end
  return false
end

---Builds the test for SUMIF, COUNTIF and their kin: `5`, `">5"`, `"<>x"`, `"=abc"`, `""` for an
---empty cell, and `*` and `?` as wildcards in text, with `~` before one to mean the character.
---@param crit Sheet.Value
---@return fun(v: Sheet.Value): boolean
local function matcher (crit)
  if type (crit) == 'number' then
    return function (v)
      return holds_number (v, crit)
    end
  end
  if type (crit) == 'boolean' then
    return function (v)
      return v == crit
    end
  end
  local s = to_text (crit)
  local op, rest = string.match (s, '^([<>=][>=]?)(.*)$')
  if not op or not COMPARE[op] then
    op, rest = '=', s
  end
  local num = M.parse_number (rest)
  if op == '=' or op == '<>' then
    local up = string.upper (rest)
    ---@type fun(v: Sheet.Value): boolean
    local want
    if rest == '' then
      want = function (v)
        return v == nil or v == ''
      end
    elseif num then
      want = function (v)
        return holds_number (v, num)
      end
    elseif up == 'TRUE' or up == 'FALSE' then
      local flag = up == 'TRUE'
      want = function (v)
        return v == flag
      end
    else
      local pattern = wildcard (lower (rest), true)
      want = function (v)
        return type (v) == 'string' and string.find (lower (v), pattern) ~= nil
      end
    end
    if op == '<>' then
      return function (v)
        return not want (v)
      end
    end
    return want
  end
  if num then
    return function (v)
      return type (v) == 'number' and ordered (v, num, op)
    end
  end
  local low = lower (rest)
  return function (v)
    return type (v) == 'string' and ordered (lower (v), low, op)
  end
end

---The exact test for lookups. Text ignores case, and with `wild` it allows `*`, `?` and `~`.
---@param want Sheet.Value
---@param wild boolean
---@return fun(v: Sheet.Value): boolean
local function equals (want, wild)
  if want == nil then
    return function ()
      return false
    end
  end
  if type (want) == 'string' then
    local low = lower (want)
    if wild and string.find (want, '[%*%?~]') then
      local pattern = wildcard (low, true)
      return function (v)
        return type (v) == 'string' and string.find (lower (v), pattern) ~= nil
      end
    end
    return function (v)
      return type (v) == 'string' and lower (v) == low
    end
  end
  if type (want) == 'number' then
    return function (v)
      return type (v) == 'number' and same_number (v, want)
    end
  end
  return function (v)
    return v == want
  end
end

---Calls `fn` with the value in the target beside each cell that meets every condition. The
---conditions are pairs of a range and a criterion in `args[first..last]`. Every range must have
---the shape of the first. The target is `target` or, when it is not given, the first range.
---`resize` lets a target of another size start at its top left cell, as SUMIF allows.
---@param args Sheet.Node[]
---@param first integer
---@param last integer
---@param target Sheet.Node?
---@param resize boolean
---@param ctx Sheet.Context
---@param fn fun(v: Sheet.Value)
local function each_match (args, first, last, target, resize, ctx, fn)
  if last < first or (last - first) % 2 == 0 then
    error (ERRORS['#VALUE!'], 0)
  end
  local grids = {} ---@type Sheet.Grid[]
  local tests = {} ---@type (fun(v: Sheet.Value): boolean)[]
  local h, w = 0, 0
  for k = first, last, 2 do
    local g = need_grid (args[k], ctx)
    local gh, gw = dims (g)
    if k == first then
      h, w = gh, gw
    elseif gh ~= h or gw ~= w then
      error (ERRORS['#VALUE!'], 0)
    end
    grids[#grids + 1] = g
    tests[#tests + 1] = matcher (value_of (args[k + 1], ctx))
  end
  local out = grids[1]
  if given (target) then
    out = need_grid (target --[[@as Sheet.Node]], ctx)
    local th, tw = dims (out)
    if th ~= h or tw ~= w then
      if not resize or not out.is_range then
        error (ERRORS['#VALUE!'], 0)
      end
      local r = out --[[@as Sheet.RangeValue]]
      out = {
        is_range = true,
        r1 = r.r1,
        c1 = r.c1,
        r2 = r.r1 + h - 1,
        c2 = r.c1 + w - 1,
        sheet = r.sheet,
      }
    end
  end
  local count = #tests
  for i = 1, h do
    for j = 1, w do
      local pass = true
      for t = 1, count do
        if not tests[t] (grid_at (grids[t], i, j, ctx)) then
          pass = false
          break
        end
      end
      if pass then
        fn (grid_at (out, i, j, ctx))
      end
    end
  end
end

---@param ctx Sheet.Context
---@return number
local function now (ctx)
  if ctx.clock then
    return ctx.clock ()
  end
  return M.clock ()
end

---@param ctx Sheet.Context
---@return number
local function random (ctx)
  if ctx.random then
    return ctx.random ()
  end
  return math.random ()
end

---An optional number argument of a `map` function: `d` when it is left out.
---@param v Sheet.Values
---@param n integer
---@param i integer
---@param d number
---@return number
local function opt (v, n, i, d)
  if i > n then
    return d
  end
  return to_number (v[i])
end

---@param v Sheet.Values
---@param n integer
---@param i integer
---@param d integer
---@return integer
local function opt_int (v, n, i, d)
  if i > n then
    return d
  end
  return trunc (to_number (v[i]))
end

---@param v Sheet.Values
---@param n integer
---@param i integer
---@param d boolean
---@return boolean
local function opt_bool (v, n, i, d)
  if i > n then
    return d
  end
  return to_bool (v[i])
end

---A clock for reading dates written without a year, from the workbook's clock.
---@param ctx Sheet.Context
---@return fun(): number
local function today_clock (ctx)
  return function ()
    return now (ctx)
  end
end

---A date argument as a serial number. Text such as `2026-09-29` counts, and a date before
---1899-12-30 is #NUM!.
---@param v Sheet.Value
---@param ctx? Sheet.Context
---@return number
local function date_arg (v, ctx)
  local n ---@type number?
  if type (v) == 'string' then
    n = M.parse_number (v)
      or parse_datetime (v, ctx and today_clock (ctx) or nil)
    if not n then
      return raise ('#VALUE!')
    end
  else
    n = to_number (v)
  end
  if n < 0 or n > LAST_DAY + 1 then
    return raise ('#NUM!')
  end
  return n
end

---The holidays for NETWORKDAYS and WORKDAY, as a set of serial days.
---@param node Sheet.Node?
---@param ctx Sheet.Context
---@return table<integer, boolean>
local function holidays (node, ctx)
  local out = {} ---@type table<integer, boolean>
  if given (node) then
    each (node --[[@as Sheet.Node]], ctx, function (v)
      if v ~= nil then
        out[math.floor (date_arg (v, ctx))] = true
      end
    end)
  end
  return out
end

---@param day integer
---@return boolean
local function is_weekend (day)
  local w = weekday0 (day)
  return w == 0 or w == 6
end

local CATALOG = {} ---@type Sheet.CatalogEntry[]

---Adds a function and its catalog entry.
---@param name string
---@param category Sheet.Category
---@param syntax string
---@param summary string
---@param spec Sheet.Function
local function define (name, category, syntax, summary, spec)
  FUNCS[name] = spec
  CATALOG[#CATALOG + 1] = {
    name = name,
    category = category,
    syntax = syntax,
    summary = summary,
  }
end

---A function of one number.
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

---A function of one text.
---@param fn fun(s: string): Sheet.Value
---@return Sheet.Function
local function text1 (fn)
  return {
    min = 1,
    max = 1,
    map = function (v)
      return fn (to_text (v[1]))
    end,
  }
end

---A test of one value that sees errors too, such as ISERROR.
---@param fn fun(v: Sheet.Value): boolean
---@return Sheet.Function
local function test1 (fn)
  return {
    min = 1,
    max = 1,
    catch = true,
    map = function (v)
      return fn (v[1])
    end,
  }
end

---@param list number[]
---@return number
local function total_of (list)
  local total = 0.0
  for _, x in ipairs (list) do
    total = total + x
  end
  return total
end

---The variance of a list, of a sample or of the whole population.
---@param list number[]
---@param sample boolean
---@return number
local function variance (list, sample)
  local n = #list
  if n < (sample and 2 or 1) then
    return raise ('#DIV/0!')
  end
  local mean = total_of (list) / n
  local squares = 0.0
  for _, x in ipairs (list) do
    squares = squares + (x - mean) ^ 2
  end
  return squares / (sample and n - 1 or n)
end

---The value at fraction `k` of a sorted list, between two values when it falls between them.
---@param list number[]
---@param k number
---@return number
local function percentile (list, k)
  local n = #list
  if n == 0 or k < 0 or k > 1 then
    return raise ('#NUM!')
  end
  table.sort (list)
  local pos = k * (n - 1) + 1
  local low = math.floor (pos)
  local frac = pos - low
  if low >= n then
    return list[n]
  end
  return list[low] + frac * (list[low + 1] - list[low])
end

---Pairs of numbers from two blocks of the same size, for SLOPE and its kin. A pair where either
---side is not a number is left out.
---@param ynode Sheet.Node
---@param xnode Sheet.Node
---@param ctx Sheet.Context
---@return number[] ys
---@return number[] xs
local function paired (ynode, xnode, ctx)
  local yv, xv = grid_or_value (ynode, ctx), grid_or_value (xnode, ctx)
  local yh, yw = dims (yv)
  local xh, xw = dims (xv)
  if yh * yw ~= xh * xw then
    error (ERRORS['#N/A'], 0)
  end
  local ys, xs = {}, {} ---@type number[], number[]
  for k = 1, yh * yw do
    local y, x = yv, xv ---@type Sheet.Result, Sheet.Result
    if is_grid (yv) then
      y = grid_at (
        yv --[[@as Sheet.Grid]],
        math.floor ((k - 1) / yw) + 1,
        (k - 1) % yw + 1,
        ctx
      )
    end
    if is_grid (xv) then
      x = grid_at (
        xv --[[@as Sheet.Grid]],
        math.floor ((k - 1) / xw) + 1,
        (k - 1) % xw + 1,
        ctx
      )
    end
    if is_error (y) then
      error (y, 0)
    end
    if is_error (x) then
      error (x, 0)
    end
    if type (y) == 'number' and type (x) == 'number' then
      ys[#ys + 1] = y
      xs[#xs + 1] = x
    end
  end
  return ys, xs
end

---The slope and the intercept of the straight line that best fits the pairs.
---@param ys number[]
---@param xs number[]
---@return number slope
---@return number intercept
local function fit (ys, xs)
  local n = #xs
  if n == 0 then
    error (ERRORS['#DIV/0!'], 0)
  end
  local mx, my = total_of (xs) / n, total_of (ys) / n
  local sxy, sxx = 0.0, 0.0
  for i = 1, n do
    sxy = sxy + (xs[i] - mx) * (ys[i] - my)
    sxx = sxx + (xs[i] - mx) ^ 2
  end
  if sxx == 0 then
    error (ERRORS['#DIV/0!'], 0)
  end
  local slope = sxy / sxx ---@type number
  return slope, my - slope * mx
end

---------------------------------------------------------------------------------------------
-- More functions
---------------------------------------------------------------------------------------------

---What the function modules get from the formula language: its helpers, and `define` to add
---a function and its catalog entry. Each module returns a function that takes the kit, so the
---functions join the catalog before it is sorted.
---@class Sheet.FormulaKit
---@field define fun(name: string, category: Sheet.Category, syntax: string, summary: string, spec: Sheet.Function)
---@field ERRORS table<string, Sheet.Error>
---@field MANY integer
---@field EMPTY table What a name holds when LET gives it an empty value.
---@field raise fun(code: string): any
---@field raise_value fun(err: any): any
---@field is_error fun(v: any): boolean
---@field is_lambda fun(v: any): boolean
---@field is_grid fun(v: Sheet.Result): boolean
---@field dims fun(v: Sheet.Result): integer, integer
---@field grid_at fun(g: Sheet.Grid, i: integer, j: integer, ctx: Sheet.Context): Sheet.Value
---@field new_array fun(h: integer, w: integer, v: Sheet.Values): Sheet.Array
---@field eval fun(node: Sheet.Node, ctx: Sheet.Context): Sheet.Result
---@field grid_or_value fun(node: Sheet.Node, ctx: Sheet.Context): Sheet.Result
---@field need_grid fun(node: Sheet.Node, ctx: Sheet.Context): Sheet.Grid
---@field need_reference fun(node: Sheet.Node, ctx: Sheet.Context): Sheet.RangeValue
---@field each fun(node: Sheet.Node, ctx: Sheet.Context, fn: fun(v: Sheet.Value, in_ref: boolean))
---@field numbers fun(args: Sheet.Node[], ctx: Sheet.Context, first?: integer, last?: integer): number[]
---@field paired fun(ynode: Sheet.Node, xnode: Sheet.Node, ctx: Sheet.Context): number[], number[]
---@field apply fun(fn: Sheet.Lambda, values: table<integer, Sheet.Result>, n: integer, ctx: Sheet.Context): Sheet.Result
---@field within fun(ctx: Sheet.Context, scope: Sheet.Scope?, fn: fun(): Sheet.Result): Sheet.Result
---@field given fun(node: Sheet.Node?): boolean
---@field value_of fun(node: Sheet.Node, ctx: Sheet.Context): Sheet.Value
---@field number_of fun(node: Sheet.Node, ctx: Sheet.Context): number
---@field int_of fun(node: Sheet.Node, ctx: Sheet.Context): integer
---@field bool_of fun(node: Sheet.Node, ctx: Sheet.Context): boolean
---@field text_of fun(node: Sheet.Node, ctx: Sheet.Context): string
---@field to_number fun(v: Sheet.Value): number
---@field to_bool fun(v: Sheet.Value): boolean
---@field to_text fun(v: Sheet.Value): string
---@field opt fun(v: Sheet.Values, n: integer, i: integer, d: number): number
---@field opt_int fun(v: Sheet.Values, n: integer, i: integer, d: integer): integer
---@field opt_bool fun(v: Sheet.Values, n: integer, i: integer, d: boolean): boolean
---@field trunc fun(n: number): integer
---@field finite fun(n: number): number
---@field compare fun(a: Sheet.Value, b: Sheet.Value): integer
---@field lower fun(s: string): string
---@field upper fun(s: string): string
---@field total_of fun(list: number[]): number
---@field variance fun(list: number[], sample: boolean): number
---@field fit fun(ys: number[], xs: number[]): number, number
---@field date_arg fun(v: Sheet.Value, ctx?: Sheet.Context): number
---@field ymd fun(serial: number): integer, integer, integer
---@field make_date fun(y: integer, m: integer, d: integer): integer
---@field weekday0 fun(serial: number): integer
---@field holidays fun(node: Sheet.Node?, ctx: Sheet.Context): table<integer, boolean>
---@field days_in_month fun(y: integer, m: integer): integer
---@field round_to fun(x: number, digits: integer, mode: 'near'|'up'|'down'): number
---@field parse_number fun(text: string): number?
---@field col_name fun(n: integer): string
---@field address fun(row: integer, col: integer): string
---@field quote_sheet fun(name: string): string
---@field percentile fun(list: number[], k: number): number
---@field clean fun(n: number): number
---@field reference fun(node: Sheet.Node, ctx: Sheet.Context): Sheet.RangeValue?
---@field is_weekend fun(day: integer): boolean
---@field chars fun(s: string): string[]
---@field length fun(s: string): integer
---@field wildcard fun(text: string, anchored: boolean): string
---@field format_value fun(v: Sheet.Value, digits?: integer): string
---@field parse_address fun(text: string): integer?, integer?
---@field col_number fun(letters: string): integer?
---@field LAST_ROW integer
---@field LAST_COL integer
---@field log fun(x: number, base?: number): number
---@field atan fun(y: number, x?: number): number
---@field math1 fun(fn: fun(x: number): number): Sheet.Function
---@field each_match fun(args: Sheet.Node[], first: integer, last: integer, target: Sheet.Node?, resize: boolean, ctx: Sheet.Context, fn: fun(v: Sheet.Value))
---@field random fun(ctx: Sheet.Context): number
---@field num_compare fun(x: number, y: number): integer
---@field text_number fun(s: string): number?
---@field test1 fun(fn: fun(v: Sheet.Value): boolean): Sheet.Function
---@field logicals fun(args: Sheet.Node[], ctx: Sheet.Context): boolean[]
---@field single fun(v: Sheet.Result, ctx: Sheet.Context): Sheet.Result
---@field spread_at fun(g: Sheet.Grid, gh: integer, gw: integer, i: integer, j: integer, ctx: Sheet.Context): Sheet.Value
---@field text1 fun(fn: fun(s: string): Sheet.Value): Sheet.Function
---@field byte_of fun(s: string, n: integer): integer
---@field format fun(n: number, fmt: string): string
---@field equals fun(want: Sheet.Value, wild: boolean): fun(v: Sheet.Value): boolean
---@field resolve fun(a: Sheet.Ref, b: Sheet.Ref, ctx: Sheet.Context): Sheet.RangeValue
---@field cell_range fun(a: Sheet.Ref, ctx: Sheet.Context): Sheet.RangeValue
---@field on_sheet fun(row: integer?, col: integer?)
---@field tokenize fun(src: string, start?: integer): Sheet.Token[]?, string?
---@field sheet_prefix fun(src: string, i: integer): string?, integer
---@field LAST_DAY integer
---@field now fun(ctx: Sheet.Context): number
---@field today_clock fun(ctx: Sheet.Context): fun(): number
---@field date_parts fun(serial: number): integer, integer, integer, integer, integer, integer
---@field is_leap fun(y: integer): boolean
---@field parse_datetime fun(text: string, clock?: fun(): number): number?

---@type Sheet.FormulaKit
local kit = {
  define = define,
  ERRORS = ERRORS,
  MANY = MANY,
  EMPTY = EMPTY,
  raise = raise,
  raise_value = raise_value,
  is_error = is_error,
  is_lambda = is_lambda,
  is_grid = is_grid,
  dims = dims,
  grid_at = grid_at,
  new_array = new_array,
  eval = eval,
  grid_or_value = grid_or_value,
  need_grid = need_grid,
  need_reference = need_reference,
  each = each,
  numbers = numbers,
  paired = paired,
  apply = apply,
  within = within,
  given = given,
  value_of = value_of,
  number_of = number_of,
  int_of = int_of,
  bool_of = bool_of,
  text_of = text_of,
  to_number = to_number,
  to_bool = to_bool,
  to_text = to_text,
  opt = opt,
  opt_int = opt_int,
  opt_bool = opt_bool,
  trunc = trunc,
  finite = finite,
  compare = compare,
  lower = lower,
  upper = upper,
  total_of = total_of,
  variance = variance,
  fit = fit,
  date_arg = date_arg,
  ymd = ymd,
  make_date = make_date,
  weekday0 = weekday0,
  holidays = holidays,
  days_in_month = days_in_month,
  round_to = round_to,
  parse_number = M.parse_number,
  col_name = M.col_name,
  address = M.address,
  quote_sheet = M.quote_sheet,
  percentile = percentile,
  clean = clean,
  reference = reference,
  is_weekend = is_weekend,
  chars = chars,
  length = length,
  wildcard = wildcard,
  format_value = M.format_value,
  parse_address = M.parse_address,
  col_number = M.col_number,
  LAST_ROW = LAST_ROW,
  LAST_COL = LAST_COL,
  log = log,
  atan = atan,
  math1 = math1,
  each_match = each_match,
  random = random,
  num_compare = num_compare,
  text_number = text_number,
  test1 = test1,
  logicals = logicals,
  single = single,
  spread_at = spread_at,
  text1 = text1,
  byte_of = byte_of,
  format = M.format,
  equals = equals,
  resolve = resolve,
  cell_range = cell_range,
  on_sheet = on_sheet,
  tokenize = M.tokenize,
  sheet_prefix = sheet_prefix,
  LAST_DAY = LAST_DAY,
  now = now,
  today_clock = today_clock,
  date_parts = M.date_parts,
  is_leap = is_leap,
  parse_datetime = parse_datetime,
}
for _, name in ipairs ({
  'sheet_fn_math',
  'sheet_fn_stats',
  'sheet_fn_logic_info',
  'sheet_fn_text',
  'sheet_fn_regex',
  'sheet_fn_lookup',
  'sheet_fn_date',
  'sheet_fn_finance',
  'sheet_fn_arrays',
  'sheet_fn_more',
}) do
  local add = require (name) --[[@as fun(kit: Sheet.FormulaKit)]]
  add (kit)
end

table.sort (CATALOG, function (a, b)
  return a.name < b.name
end)
M.catalog = CATALOG

M.functions = {}
for _, entry in ipairs (CATALOG) do
  M.functions[#M.functions + 1] = entry.name
end

return kit
