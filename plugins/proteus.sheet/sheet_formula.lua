-- sheet_formula: the formula language of the Sheet app. A tokenizer and a parser turn the
-- text after "=" into a tree, and an evaluator walks the tree. Formula text never runs as Lua.
--
-- The same tokens drive the rewrites of formula text: moving the references of a copied
-- formula, fixing references after a row or a column is inserted or deleted, and following a
-- sheet that is renamed or deleted. The helpers at the end serve the formula bar while a
-- formula is typed: completion, the argument being typed, reference colours and F4.

local lexer = require ('sheet_formula_lex') --[[@as Sheet.FormulaLex]]

---A spreadsheet error, such as `#DIV/0!`. Each code has one shared table, so two errors with
---the same code are equal.
---@class Sheet.Error
---@field code string

---A cell value. Nil is an empty cell.
---@alias Sheet.Value number|string|boolean|Sheet.Error|nil

---A list of values that may have holes, such as the arguments of a function.
---@alias Sheet.Values table<integer, Sheet.Value>

---One end of a reference. A whole column has no row, and a whole row has no column.
---@class Sheet.Ref
---@field row? integer
---@field col? integer
---@field row_abs boolean True when the row has a `$`.
---@field col_abs boolean True when the column has a `$`.
---@field sheet? string The sheet it names, without quotes. Nil means the formula's own sheet.

---@alias Sheet.TokenKind 'number'|'string'|'error'|'ref'|'range'|'name'|'op'|'open'|'close'|'comma'|'lbrace'|'rbrace'|'semicolon'

---@class Sheet.Token
---@field kind Sheet.TokenKind
---@field text string The source text.
---@field from integer The first byte.
---@field to integer The last byte.
---@field value? number|string
---@field a? Sheet.Ref A reference, or the first end of a range.
---@field b? Sheet.Ref The second end of a range.
---@field sheet? string The sheet a reference names, without quotes.
---@field sheet_text? string The sheet part of a reference as written, with its quotes and "!".
---@field spill? boolean True for a reference to the block a formula spills, such as `A1#`.

---@alias Sheet.NodeKind 'number'|'string'|'bool'|'error'|'ref'|'range'|'spill'|'name'|'call'|'invoke'|'unary'|'binary'|'percent'|'empty'|'array'|'intersect'|'union'

---A node of the formula tree.
---@class Sheet.Node
---@field kind Sheet.NodeKind
---@field value? number|string|boolean
---@field op? string
---@field left? Sheet.Node The operand of a unary or percent node, the left side, or the function an invoke node calls.
---@field right? Sheet.Node
---@field name? string A function or a name, in upper case.
---@field args? Sheet.Node[]
---@field a? Sheet.Ref
---@field b? Sheet.Ref
---@field array? Sheet.Array The values of an array constant such as `{1,2;3,4}`.

---A block of cells a formula reads. Whole columns leave the rows out, and whole rows leave the
---columns out.
---@class Sheet.Area
---@field r1? integer
---@field c1? integer
---@field r2? integer
---@field c2? integer
---@field sheet? string The sheet it names. Nil means the formula's own sheet.

---A block of cells with every side known, top left to bottom right.
---@class Sheet.Rect
---@field r1 integer
---@field c1 integer
---@field r2 integer
---@field c2 integer

---A block of cells as a value, while a function reads it.
---@class Sheet.RangeValue: Sheet.Rect
---@field is_range true
---@field sheet? string

---A block of values worked out by a formula, such as `{1,2;3,4}` or `A1:A3*2`. The values run
---row by row, and an empty cell leaves a hole.
---@class Sheet.Array
---@field is_array true
---@field h integer
---@field w integer
---@field v Sheet.Values

---@alias Sheet.Grid Sheet.RangeValue|Sheet.Array

---Several blocks of cells as one reference, from the union operator, as in `(A1:A3,C1:C3)`.
---Functions that read every value, such as SUM, read each block.
---@class Sheet.Union
---@field is_union true
---@field areas Sheet.RangeValue[]

---A function a formula makes with LAMBDA. It keeps the names around it when it was made.
---@class Sheet.Lambda
---@field is_lambda true
---@field params string[] The names of its arguments, in upper case.
---@field body Sheet.Node
---@field scope? Sheet.Scope

---Names that LET and LAMBDA give values, inside the part of a formula they cover.
---@class Sheet.Scope
---@field names table<string, Sheet.Result|Sheet.Lambda>
---@field parent? Sheet.Scope

---@alias Sheet.Result Sheet.Value|Sheet.RangeValue|Sheet.Array|Sheet.Lambda

---What the evaluator needs from a workbook.
---@class Sheet.Context
---@field value fun(row: integer, col: integer, sheet?: string): Sheet.Value
---@field rows integer The last row a whole column reaches.
---@field cols integer The last column a whole row reaches.
---@field size? fun(sheet: string): integer?, integer? The rows and columns of a named sheet, or nil when there is no such sheet.
---@field clock? fun(): number The date and time now, as a serial number of days.
---@field random? fun(): number
---@field row? integer The row of the cell being worked out, for ROW() with no argument.
---@field col? integer The column of the cell being worked out, for COLUMN() with no argument.
---@field spill? fun(row: integer, col: integer, sheet?: string): integer?, integer? The height and width of the block a formula's cell spills, or nil when it spills none.
---@field scope? Sheet.Scope The names LET and LAMBDA give, while their part of a formula is worked out.
---@field hidden? fun(row: integer, sheet?: string): 'filter'|'user'|nil Why a row is hidden: by the filter or by the user.
---@field subtotal? fun(row: integer, col: integer, sheet?: string): boolean True when a cell holds a SUBTOTAL or an AGGREGATE, which those leave out.
---@field formula_text? fun(row: integer, col: integer, sheet?: string): string? The formula a cell holds, with its "=", or nil.
---@field sheet_index? fun(sheet?: string): integer? Where a sheet sits in the book, the formula's own when nil.
---@field sheet_count? fun(): integer
---@field name? fun(name: string): Sheet.Node? The parsed formula a defined name stands for, by its name in upper case.
---@field name_depth? integer How deep names that name other names go, while one is worked out.

---A function the formulas can call. `run` gets the argument trees and works them out as it
---needs to. `map` gets the argument values instead, and runs once for each value when an
---argument is a block of cells. With `catch`, `map` also gets errors as values.
---@class Sheet.Function
---@field min integer
---@field max integer
---@field run? fun(args: Sheet.Node[], ctx: Sheet.Context): Sheet.Result
---@field map? fun(v: Sheet.Values, n: integer, ctx: Sheet.Context): Sheet.Value
---@field catch? boolean

---@alias Sheet.Category 'Math'|'Statistics'|'Logic'|'Text'|'Lookup'|'Date'|'Info'|'Financial'

---@class Sheet.CatalogEntry
---@field name string
---@field category Sheet.Category
---@field syntax string Such as `SUMIF(range, criterion, [sum_range])`.
---@field summary string One plain sentence.

---A function name being typed, from `complete`.
---@class Sheet.Completion
---@field from integer The first byte of the name.
---@field to integer The last byte of the name, which may run on past the caret.
---@field prefix string The part of the name before the caret, as typed.

---The function whose arguments hold the caret, from `call_at`.
---@class Sheet.CallInfo
---@field name string In upper case.
---@field arg integer Counts from 1.

---A reference in formula text, from `ref_spans`.
---@class Sheet.RefSpan
---@field from integer
---@field to integer
---@field area Sheet.Area

---@class Sheet.MoveOptions
---@field from string The sheet the block moves from.
---@field to string The sheet the block moves to.
---@field own string The sheet the formula lives on.
---@field lands? string The sheet the formula lives on after the move, when it moves too.

---@class Sheet.AdjustOptions
---@field sheet? string The sheet where the rows or columns changed.
---@field own? string The sheet the formula lives on.

---An open bracket while formula text is scanned.
---@class Sheet.Frame
---@field name? string The function the bracket belongs to, or nil for a plain bracket.
---@field arg integer
---@field brace boolean True for the `{` of an array constant.

---@class Sheet.Parser
---@field tokens Sheet.Token[]
---@field i integer
---@field depth integer

---@class Sheet.FormulaModule
local M = lexer.M
local ERRORS, LAST_COL, LAST_DAY, LAST_ROW =
  lexer.ERRORS, lexer.LAST_COL, lexer.LAST_DAY, lexer.LAST_ROW
local MANY, MAX_DEPTH, atan, byte_of =
  lexer.MANY, lexer.MAX_DEPTH, lexer.atan, lexer.byte_of
local chars, clean, days_in_month, finite =
  lexer.chars, lexer.clean, lexer.days_in_month, lexer.finite
local is_error, is_leap, length, lex =
  lexer.is_error, lexer.is_leap, lexer.length, lexer.lex
local log, lower, make_date, parse_datetime =
  lexer.log, lexer.lower, lexer.make_date, lexer.parse_datetime
local raise, raise_value, round_to, sheet_prefix =
  lexer.raise, lexer.raise_value, lexer.round_to, lexer.sheet_prefix
local trunc, upper, weekday0, wildcard =
  lexer.trunc, lexer.upper, lexer.weekday0, lexer.wildcard
local ymd = lexer.ymd

---------------------------------------------------------------------------------------------
-- Parser
---------------------------------------------------------------------------------------------

---@param message string
---@return any
local function fail (message)
  local problem = { syntax = message }
  error (problem, 0)
end

---@param p Sheet.Parser
---@param kind Sheet.TokenKind
---@param text? string
---@return boolean
local function looking_at (p, kind, text)
  local t = p.tokens[p.i]
  return t ~= nil and t.kind == kind and (text == nil or t.text == text)
end

---@type fun(p: Sheet.Parser): Sheet.Node
local expression

-- The functions formulas can call, by name. The parser checks how many arguments a call
-- gives, and the evaluator runs them.
---@type table<string, Sheet.Function>
local FUNCS = {}

---How many arguments a function takes, in words.
---@param spec Sheet.Function
---@return string
local function arity (spec)
  if spec.min == spec.max then
    return spec.min == 1 and '1 argument' or spec.min .. ' arguments'
  end
  if spec.max >= MANY then
    return 'at least '
      .. spec.min
      .. (spec.min == 1 and ' argument' or ' arguments')
  end
  return spec.min .. ' to ' .. spec.max .. ' arguments'
end

---A call with as many arguments as its function takes. A wrong count fails as it is typed,
---rather than giving #VALUE! when the formula is worked out. A name no function has stays,
---for LET and LAMBDA names, and gives #NAME? later.
---@param node Sheet.Node
---@return Sheet.Node
local function checked (node)
  local name = node.name or ''
  local spec = FUNCS[name]
  local n = #(node.args or {})
  if spec and (n < spec.min or n > spec.max) then
    return fail (name .. ' takes ' .. arity (spec) .. ', not ' .. n .. '.')
  end
  return node
end

---@param p Sheet.Parser
---@param name string
---@return Sheet.Node
local function call_args (p, name)
  local args = {} ---@type Sheet.Node[]
  if looking_at (p, 'close') then
    p.i = p.i + 1
    return checked ({ kind = 'call', name = name, args = args })
  end
  while true do
    if looking_at (p, 'comma') or looking_at (p, 'close') then
      args[#args + 1] = { kind = 'empty' }
    else
      args[#args + 1] = expression (p)
    end
    if looking_at (p, 'comma') then
      p.i = p.i + 1
    elseif looking_at (p, 'close') then
      p.i = p.i + 1
      break
    else
      return fail ('A ")" is missing after the arguments of ' .. name .. '.')
    end
  end
  return checked ({ kind = 'call', name = name, args = args })
end

---Reads one value of an array constant: a number with an optional sign, text, TRUE, FALSE or
---an error.
---@param p Sheet.Parser
---@return Sheet.Value
local function constant (p)
  local t = p.tokens[p.i]
  if not t then
    return fail ('A "}" is missing.')
  end
  p.i = p.i + 1
  local sign = 1
  if t.kind == 'op' and (t.text == '-' or t.text == '+') then
    sign = t.text == '-' and -1 or 1
    t = p.tokens[p.i]
    if not t or t.kind ~= 'number' then
      return fail ('An array holds only numbers, text, TRUE, FALSE and errors.')
    end
    p.i = p.i + 1
  end
  if t.kind == 'number' then
    return sign * t.value --[[@as number]]
  end
  if sign == 1 then
    if t.kind == 'string' then
      return t.value
    end
    if t.kind == 'error' then
      return ERRORS[t.value]
    end
    if t.kind == 'name' then
      local up = string.upper (t.text)
      if up == 'TRUE' or up == 'FALSE' then
        return up == 'TRUE'
      end
    end
  end
  return fail ('An array holds only numbers, text, TRUE, FALSE and errors.')
end

---Reads an array constant after its "{". A comma separates the values in a row, and a
---semicolon ends a row.
---@param p Sheet.Parser
---@return Sheet.Node
local function array_constant (p)
  -- A constant is never nil, so the length of the list counts the values.
  local values = {} ---@type Sheet.Value[]
  local h = 1 ---@type integer
  -- The width is 0 until the first row ends.
  local w = 0 ---@type integer
  local first = 1 ---@type integer
  while true do
    values[#values + 1] = constant (p)
    local t = p.tokens[p.i]
    if not t then
      return fail ('A "}" is missing.')
    end
    p.i = p.i + 1
    if t.kind == 'semicolon' or t.kind == 'rbrace' then
      local len = #values - first + 1
      if w > 0 and len ~= w then
        return fail ('Every row of an array needs the same number of values.')
      end
      w = len
      if t.kind == 'rbrace' then
        break
      end
      first = #values + 1
      h = h + 1
    elseif t.kind ~= 'comma' then
      return fail ('Unexpected "' .. t.text .. '".')
    end
  end
  return {
    kind = 'array',
    array = { is_array = true, h = h, w = w, v = values },
  }
end

---@param p Sheet.Parser
---@return Sheet.Node
local function primary (p)
  local t = p.tokens[p.i]
  if not t then
    return fail ('The formula ends too soon.')
  end
  p.i = p.i + 1
  local kind = t.kind
  if kind == 'number' or kind == 'string' or kind == 'error' then
    return {
      kind = kind --[[@as Sheet.NodeKind]],
      value = t.value,
    }
  end
  if kind == 'ref' then
    return { kind = t.spill and 'spill' or 'ref', a = t.a }
  end
  if kind == 'range' then
    return { kind = 'range', a = t.a, b = t.b }
  end
  if kind == 'name' then
    local name = string.upper (t.text)
    if looking_at (p, 'open') then
      p.i = p.i + 1
      return call_args (p, name)
    end
    if name == 'TRUE' or name == 'FALSE' then
      return { kind = 'bool', value = name == 'TRUE' }
    end
    return { kind = 'name', name = name }
  end
  if kind == 'open' then
    local inner = expression (p)
    -- A comma inside brackets joins references into one, as in (A1:A3,C1:C3).
    if looking_at (p, 'comma') then
      local parts = { inner } ---@type Sheet.Node[]
      while looking_at (p, 'comma') do
        p.i = p.i + 1
        parts[#parts + 1] = expression (p)
      end
      inner = { kind = 'union', args = parts }
    end
    if not looking_at (p, 'close') then
      return fail ('A ")" is missing.')
    end
    p.i = p.i + 1
    return inner
  end
  if kind == 'lbrace' then
    return array_constant (p)
  end
  return fail ('Unexpected "' .. t.text .. '".')
end

-- The tokens that can start the right side of the intersection operator, a space.
local REFERENCE_KINDS = { ref = true, range = true, name = true }

---True when the next token starts a reference with only spaces before it, which makes the
---space the intersection operator, as in `A1:C3 B2:D4`.
---@param p Sheet.Parser
---@return boolean
local function space_follows (p)
  local before, t = p.tokens[p.i - 1], p.tokens[p.i]
  return t ~= nil
    and before ~= nil
    and REFERENCE_KINDS[t.kind] == true
    and t.from > before.to + 1
    and (
      before.kind == 'ref'
      or before.kind == 'range'
      or before.kind == 'name'
      or before.kind == 'close'
    )
end

---@param p Sheet.Parser
---@return Sheet.Node
local function postfix (p)
  local node = primary (p)
  while space_follows (p) do
    node = { kind = 'intersect', left = node, right = primary (p) }
  end
  -- A function call right after a call, as in LAMBDA(x, x*2)(5), calls what it gave.
  while node.kind == 'call' or node.kind == 'invoke' do
    if not looking_at (p, 'open') then
      break
    end
    p.i = p.i + 1
    local args = call_args (p, node.name or 'the function').args
    node = { kind = 'invoke', left = node, args = args }
  end
  while looking_at (p, 'op', '%') do
    p.i = p.i + 1
    node = { kind = 'percent', left = node }
  end
  return node
end

---@param p Sheet.Parser
---@return Sheet.Node
local function unary (p)
  if looking_at (p, 'op', '-') or looking_at (p, 'op', '+') then
    local op = p.tokens[p.i].text
    p.i = p.i + 1
    p.depth = p.depth + 1
    if p.depth > MAX_DEPTH then
      return fail ('The formula nests too deeply.')
    end
    local operand = unary (p)
    p.depth = p.depth - 1
    return { kind = 'unary', op = op, left = operand }
  end
  return postfix (p)
end

---Builds a left-to-right chain of binary operators.
---@param ops table<string, boolean>
---@param next_level fun(p: Sheet.Parser): Sheet.Node
---@return fun(p: Sheet.Parser): Sheet.Node
local function chain (ops, next_level)
  ---@param p Sheet.Parser
  ---@return Sheet.Node
  return function (p)
    local node = next_level (p)
    while true do
      local t = p.tokens[p.i]
      if not (t and t.kind == 'op' and ops[t.text]) then
        return node
      end
      p.i = p.i + 1
      node =
        { kind = 'binary', op = t.text, left = node, right = next_level (p) }
    end
  end
end

-- Lowest first: comparison, &, + and -, * and /, ^. Unary signs and % bind tighter than ^,
-- so -2^2 is 4 and 2^3^2 is 64, as in spreadsheets.
local power = chain ({ ['^'] = true }, unary)
local product = chain ({ ['*'] = true, ['/'] = true }, power)
local sum = chain ({ ['+'] = true, ['-'] = true }, product)
local join = chain ({ ['&'] = true }, sum)
local COMPARE = {
  ['='] = true,
  ['<>'] = true,
  ['<'] = true,
  ['>'] = true,
  ['<='] = true,
  ['>='] = true,
}
local comparison = chain (COMPARE, join)

---@param p Sheet.Parser
---@return Sheet.Node
expression = function (p)
  p.depth = p.depth + 1
  if p.depth > MAX_DEPTH then
    return fail ('The formula nests too deeply.')
  end
  local node = comparison (p)
  p.depth = p.depth - 1
  return node
end

---Parses a formula, with or without its leading "=". Returns the tree, or nil and a message.
---@param src string
---@return Sheet.Node?
---@return string?
function M.parse (src)
  local start = string.sub (src, 1, 1) == '=' and 2 or 1
  local tokens, problem = M.tokenize (src, start)
  if not tokens then
    return nil, problem
  end
  if #tokens == 0 then
    return nil, 'The formula is empty.'
  end
  local p = { tokens = tokens, i = 1, depth = 0 } ---@type Sheet.Parser
  local ok, result = pcall (expression, p)
  if not ok then
    local err = result --[[@as any]]
    if type (err) == 'table' and err.syntax then
      return nil, err.syntax
    end
    error (err, 0)
  end
  if p.i <= #tokens then
    return nil, 'Unexpected "' .. tokens[p.i].text .. '".'
  end
  return result
end

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

---What the modules with more functions get from the formula language: its helpers, and
---`define` to add a function and its catalog entry. Each module returns a function that takes
---the kit, so the functions join the catalog before it is sorted.
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

---------------------------------------------------------------------------------------------
-- Reading formulas
---------------------------------------------------------------------------------------------

---@param a Sheet.Ref
---@param b? Sheet.Ref
---@return Sheet.Area
local function area_of (a, b)
  if not b then
    return { r1 = a.row, c1 = a.col, r2 = a.row, c2 = a.col, sheet = a.sheet }
  end
  ---@type Sheet.Area
  local area =
    { r1 = a.row, c1 = a.col, r2 = b.row, c2 = b.col, sheet = a.sheet }
  if a.row and b.row then
    area.r1, area.r2 = math.min (a.row, b.row), math.max (a.row, b.row)
  end
  if a.col and b.col then
    area.c1, area.c2 = math.min (a.col, b.col), math.max (a.col, b.col)
  end
  return area
end

---Calls `fn` with every node of a tree, parents before children and left before right. It
---walks with a list rather than recursion, so a long chain such as A1+A2+...+A9999 is safe.
---@param ast Sheet.Node
---@param fn fun(node: Sheet.Node)
local function walk (ast, fn)
  local stack = { ast } ---@type Sheet.Node[]
  while #stack > 0 do
    local node = stack[#stack]
    stack[#stack] = nil
    fn (node)
    local args = node.args
    if args then
      for i = #args, 1, -1 do
        stack[#stack + 1] = args[i]
      end
    end
    if node.right then
      stack[#stack + 1] = node.right
    end
    if node.left then
      stack[#stack + 1] = node.left
    end
  end
end

---Every block of cells a formula reads, with the sheet each one names. Cells that INDIRECT
---and OFFSET reach are not known until the formula is worked out.
---@param ast Sheet.Node
---@return Sheet.Area[]
function M.refs (ast)
  local out = {} ---@type Sheet.Area[]
  walk (ast, function (node)
    -- A1# reads the formula in A1, which is worked out again whenever its block changes.
    if node.kind == 'ref' or node.kind == 'spill' then
      out[#out + 1] = area_of (node.a --[[@as Sheet.Ref]])
    elseif node.kind == 'range' then
      out[#out + 1] = area_of (node.a --[[@as Sheet.Ref]], node.b)
    end
  end)
  return out
end

local VOLATILE = {
  RAND = true,
  RANDBETWEEN = true,
  NOW = true,
  TODAY = true,
  INDIRECT = true,
  OFFSET = true,
}

---True when a formula must be worked out again after every change: it calls RAND,
---RANDBETWEEN, NOW, TODAY, INDIRECT or OFFSET.
---@param ast Sheet.Node
---@return boolean
function M.volatile (ast)
  local found = false
  walk (ast, function (node)
    if node.kind == 'call' and VOLATILE[node.name or ''] then
      found = true
    end
  end)
  return found
end

---The names a formula uses that are not functions, in upper case, each once: the names a
---workbook may define, and the names LET and LAMBDA give.
---@param ast Sheet.Node
---@return string[]
function M.names (ast)
  local out, seen = {}, {} ---@type string[], table<string, boolean>
  walk (ast, function (node)
    local name = node.name
    if
      name
      and (node.kind == 'name' or (node.kind == 'call' and not FUNCS[name]))
      and not seen[name]
    then
      seen[name] = true
      out[#out + 1] = name
    end
  end)
  return out
end

---Why text cannot be a defined name, or nil when it can. A name starts with a letter, an
---underscore or a backslash, then has letters, digits, underscores and points. It cannot
---look like a cell, such as `A1` or `R1C1`, be TRUE or FALSE, or be a function's name.
---@param name string
---@return string?
function M.name_problem (name)
  if name == '' then
    return 'Type a name.'
  end
  if #name > 255 then
    return 'A name can have at most 255 characters.'
  end
  if not string.match (name, '^[%a_\\][%w_%.\\]*$') then
    return 'A name starts with a letter or _, and holds only letters, digits, _ and points.'
  end
  local up = string.upper (name)
  if
    string.match (up, '^%a%a?%a?%d+$')
    or string.match (up, '^R%d*C%d*$')
    or up == 'R'
    or up == 'C'
  then
    return 'A name cannot look like a cell, such as A1 or R1C1.'
  end
  if up == 'TRUE' or up == 'FALSE' then
    return 'A name cannot be TRUE or FALSE.'
  end
  if FUNCS[up] then
    return up .. ' is a function.'
  end
  return nil
end

---True when a formula reads which rows are hidden: it calls SUBTOTAL or AGGREGATE.
---@param ast Sheet.Node
---@return boolean
function M.reads_hidden (ast)
  local found = false
  walk (ast, function (node)
    if
      node.kind == 'call'
      and (node.name == 'SUBTOTAL' or node.name == 'AGGREGATE')
    then
      found = true
    end
  end)
  return found
end

---@type table<string, 'date'|'time'|'datetime'>
local FORMAT_OF = {
  DATE = 'date',
  TODAY = 'date',
  EDATE = 'date',
  EOMONTH = 'date',
  WORKDAY = 'date',
  DATEVALUE = 'date',
  NOW = 'datetime',
  TIME = 'time',
  TIMEVALUE = 'time',
}

---How the result of a formula should show, from its outermost function: `=DATE(2026,9,29)`
---shows as a date. A date plus or minus days stays a date, a date plus a time is a date and
---time, and a date minus a date is a count of days.
---@param ast Sheet.Node
---@return 'date'|'time'|'datetime'|'percent'|nil
function M.result_format (ast)
  -- Walk down the left side of a chain such as TODAY()+1-2, then fold back up.
  local steps = {} ---@type Sheet.Node[]
  local node = ast
  while node.kind == 'binary' and (node.op == '+' or node.op == '-') do
    steps[#steps + 1] = node
    node = node.left --[[@as Sheet.Node]]
  end
  local kind = nil ---@type 'date'|'time'|'datetime'|nil
  if node.kind == 'call' then
    kind = FORMAT_OF[node.name or '']
  end
  for i = #steps, 1, -1 do
    local step = steps[i]
    local right = M.result_format (step.right --[[@as Sheet.Node]]) --[[@as 'date'|'time'|'datetime'|nil]]
    if step.op == '+' then
      if
        (kind == 'date' and right == 'time')
        or (kind == 'time' and right == 'date')
      then
        kind = 'datetime'
      else
        kind = kind or right
      end
    elseif right then
      kind = nil
    end
  end
  return kind
end

---Says when a formula shows a date or a date and time, as `result_format` does. A time alone
---gives nil here.
---@param ast Sheet.Node
---@return 'date'|'datetime'|nil
function M.date_kind (ast)
  local kind = M.result_format (ast)
  if kind == 'date' then
    return 'date'
  end
  if kind == 'datetime' then
    return 'datetime'
  end
  return nil
end

---------------------------------------------------------------------------------------------
-- Rewriting formulas
---------------------------------------------------------------------------------------------

---@param ref Sheet.Ref
---@return string
local function ref_text (ref)
  local out = ''
  if ref.col then
    out = (ref.col_abs and '$' or '') .. M.col_name (ref.col)
  end
  if ref.row then
    out = out .. (ref.row_abs and '$' or '') .. string.format ('%d', ref.row)
  end
  return out
end

---@param ref Sheet.Ref
---@return Sheet.Ref
local function copy_ref (ref)
  return {
    row = ref.row,
    col = ref.col,
    row_abs = ref.row_abs,
    col_abs = ref.col_abs,
    sheet = ref.sheet,
  }
end

---The text of a reference or a range token from its ends, with its sheet as written.
---@param t Sheet.Token
---@param a Sheet.Ref
---@param b? Sheet.Ref
---@return string
local function token_text (t, a, b)
  local out = (t.sheet_text or '') .. ref_text (a)
  if b then
    out = out .. ':' .. ref_text (b)
  end
  if t.spill then
    out = out .. '#'
  end
  return out
end

-- The helpers of the rewrites stay inside a block, since a chunk can hold only 200 locals.
do
  ---@param ref Sheet.Ref
  ---@param axis 'row'|'col'
  ---@return integer?
  local function coord (ref, axis)
    if axis == 'row' then
      return ref.row
    end
    return ref.col
  end

  ---@param ref Sheet.Ref
  ---@param axis 'row'|'col'
  ---@param v integer
  local function set_coord (ref, axis, v)
    if axis == 'row' then
      ref.row = v
    else
      ref.col = v
    end
  end

  ---Rebuilds formula text, letting `fn` replace the text of each reference or range. When `fn`
  ---returns nil the original text stays. Text that is not a formula, or does not tokenize,
  ---comes back unchanged.
  ---@param text string
  ---@param fn fun(t: Sheet.Token): string?
  ---@return string
  local function rewrite (text, fn)
    if not M.is_formula (text) then
      return text
    end
    local tokens = M.tokenize (text, 2)
    if not tokens then
      return text
    end
    local parts = {} ---@type string[]
    local pos = 1
    for _, t in ipairs (tokens) do
      if t.kind == 'ref' or t.kind == 'range' then
        local new = fn (t)
        if new and new ~= t.text then
          parts[#parts + 1] = string.sub (text, pos, t.from - 1)
          parts[#parts + 1] = new
          pos = t.to + 1
        end
      end
    end
    if pos == 1 then
      return text
    end
    parts[#parts + 1] = string.sub (text, pos)
    return table.concat (parts)
  end

  ---@param ref Sheet.Ref
  ---@param drow integer
  ---@param dcol integer
  ---@return Sheet.Ref?
  local function moved (ref, drow, dcol)
    local out = copy_ref (ref)
    if out.row and not out.row_abs then
      out.row = out.row + drow
    end
    if out.col and not out.col_abs then
      out.col = out.col + dcol
    end
    if
      (out.row and (out.row < 1 or out.row > LAST_ROW))
      or (out.col and (out.col < 1 or out.col > LAST_COL))
    then
      return nil
    end
    return out
  end

  ---Moves the relative references in a formula by a number of rows and columns, as a copy and
  ---paste does. References with `$` stay. A reference pushed off the sheet turns into #REF!.
  ---References to other sheets move too.
  ---@param text string
  ---@param drow integer
  ---@param dcol integer
  ---@return string
  function M.shift (text, drow, dcol)
    if drow == 0 and dcol == 0 then
      return text
    end
    return rewrite (text, function (t)
      local a = moved (t.a --[[@as Sheet.Ref]], drow, dcol)
      if t.kind == 'ref' then
        return a and token_text (t, a) or '#REF!'
      end
      local b = moved (t.b --[[@as Sheet.Ref]], drow, dcol)
      if not a or not b then
        return '#REF!'
      end
      return token_text (t, a, b)
    end)
  end

  ---Folds a sheet name for comparing, since sheet names ignore case.
  ---@param name string
  ---@return string
  local function sheet_key (name)
    return lower (name)
  end

  ---True when a reference sits on the sheet where rows or columns changed.
  ---@param sheet string?
  ---@param opts Sheet.AdjustOptions?
  ---@return boolean
  local function affected (sheet, opts)
    if not opts then
      return sheet == nil
    end
    local mine = sheet or opts.own
    local where = opts.sheet or opts.own
    if opts.sheet == nil and sheet == nil then
      return true
    end
    return mine ~= nil
      and where ~= nil
      and sheet_key (mine) == sheet_key (where)
  end

  ---True when a reference names one cell, or both ends of a range, inside a block.
  ---@param t Sheet.Token
  ---@param rect Sheet.Rect
  ---@return boolean all
  ---@return boolean some True when at least one cell of the reference is in the block.
  local function inside (t, rect)
    local a = t.a --[[@as Sheet.Ref]]
    local b = t.kind == 'range' and t.b or a --[[@as Sheet.Ref]]
    local r1 = math.min (a.row or 1, b.row or 1)
    local r2 = math.max (a.row or math.huge, b.row or math.huge)
    local c1 = math.min (a.col or 1, b.col or 1)
    local c2 = math.max (a.col or math.huge, b.col or math.huge)
    local all = r1 >= rect.r1
      and r2 <= rect.r2
      and c1 >= rect.c1
      and c2 <= rect.c2
    local some = r1 <= rect.r2
      and r2 >= rect.r1
      and c1 <= rect.c2
      and c2 >= rect.c1
    return all, some
  end

  ---Fixes the references in a formula after a block of cells moves, as a cut and paste or a
  ---drag does. A reference that lies wholly inside the block moves with it, `$` or not, and
  ---follows it to another sheet. A reference to cells the block lands on, and that the block
  ---did not hold, turns into #REF!, since the cells it named are gone. Every other reference
  ---stays where it points.
  ---
  ---`opts.from` and `opts.to` name the sheets the block moves from and to, `opts.own` the sheet
  ---the formula lives on, and `opts.lands` the sheet it lives on after the move, when the
  ---formula moves with the block. A reference gets a sheet name when it needs one to keep
  ---pointing at the same sheet.
  ---@param text string
  ---@param src Sheet.Rect The block before the move.
  ---@param drow integer
  ---@param dcol integer
  ---@param opts Sheet.MoveOptions
  ---@return string
  function M.move (text, src, drow, dcol, opts)
    local from, to = sheet_key (opts.from), sheet_key (opts.to)
    local lands = opts.lands or opts.own
    local dst = {
      r1 = src.r1 + drow,
      c1 = src.c1 + dcol,
      r2 = src.r2 + drow,
      c2 = src.c2 + dcol,
    }
    return rewrite (text, function (t)
      local named = t.sheet or opts.own
      local key = sheet_key (named)
      local a = t.a --[[@as Sheet.Ref]]
      local b = t.b
      local where = named
      if key == from and inside (t, src) then
        a = copy_ref (a)
        a.row, a.col = (a.row or 0) + drow, (a.col or 0) + dcol
        if b then
          b = copy_ref (b)
          b.row, b.col = (b.row or 0) + drow, (b.col or 0) + dcol
        end
        where = opts.to
      elseif key == to and inside (t, dst) then
        local _, held = inside (t, src)
        if key ~= from or not held then
          return '#REF!'
        end
      end
      local head ---@type string
      if t.sheet and sheet_key (t.sheet) == sheet_key (where) then
        head = t.sheet_text or ''
      elseif sheet_key (where) == sheet_key (lands) then
        head = ''
      else
        head = M.quote_sheet (where) .. '!'
      end
      local out = head .. ref_text (a)
      if t.kind == 'range' and b then
        out = out .. ':' .. ref_text (b)
      end
      if t.spill then
        out = out .. '#'
      end
      return out
    end)
  end

  ---Fixes the references in a formula after rows or columns change. `count` rows or columns
  ---were inserted before `at` when it is positive. When it is negative, `-count` of them were
  ---deleted starting at `at`. Every reference moves, `$` or not. A reference to a deleted cell
  ---turns into #REF!, and a range that loses some of its rows or columns shrinks.
  ---
  ---`opts.sheet` names the sheet that changed, and `opts.own` the sheet the formula lives on.
  ---A reference changes when the sheet it names, or `own` when it names none, is the one that
  ---changed. With no `opts`, only references that name no sheet change.
  ---@param text string
  ---@param axis 'row'|'col'
  ---@param at integer
  ---@param count integer
  ---@param opts? Sheet.AdjustOptions
  ---@return string
  function M.adjust (text, axis, at, count, opts)
    if count == 0 then
      return text
    end
    local n = -count
    local last = at + n - 1
    return rewrite (text, function (t)
      if not affected (t.sheet, opts) then
        return nil
      end
      local a = copy_ref (t.a --[[@as Sheet.Ref]])
      if t.kind == 'ref' then
        local v = coord (a, axis) or 0
        if count > 0 then
          if v >= at then
            set_coord (a, axis, v + count)
          end
        elseif v >= at and v <= last then
          return '#REF!'
        elseif v > last then
          set_coord (a, axis, v - n)
        end
        return token_text (t, a)
      end
      local b = copy_ref (t.b --[[@as Sheet.Ref]])
      local x, y = coord (a, axis), coord (b, axis)
      if x == nil or y == nil then
        -- A whole column does not change when rows do, and a whole row does not when columns do.
        return nil
      end
      local lo, hi = math.min (x, y), math.max (x, y)
      if count > 0 then
        if lo >= at then
          lo = lo + count
        end
        if hi >= at then
          hi = hi + count
        end
      else
        if lo >= at and hi <= last then
          return '#REF!'
        end
        if lo > last then
          lo = lo - n
        elseif lo >= at then
          lo = at
        end
        if hi > last then
          hi = hi - n
        elseif hi >= at then
          hi = at - 1
        end
      end
      set_coord (a, axis, lo)
      set_coord (b, axis, hi)
      return token_text (t, a, b)
    end)
  end

  ---Points the references to sheet `old` at sheet `new`, after a rename. Sheet names ignore case,
  ---and `new` gets quotes when it needs them.
  ---@param text string
  ---@param old string
  ---@param new string
  ---@return string
  function M.rename_sheet (text, old, new)
    local key = sheet_key (old)
    local prefix = M.quote_sheet (new) .. '!'
    return rewrite (text, function (t)
      if t.sheet and sheet_key (t.sheet) == key then
        return prefix .. string.sub (t.text, #(t.sheet_text or '') + 1)
      end
      return nil
    end)
  end

  ---Turns the references to sheet `name` into #REF!, after the sheet is deleted.
  ---@param text string
  ---@param name string
  ---@return string
  function M.drop_sheet (text, name)
    local key = sheet_key (name)
    return rewrite (text, function (t)
      if t.sheet and sheet_key (t.sheet) == key then
        return '#REF!'
      end
      return nil
    end)
  end

  ---Tidies a formula as it is entered: references and function names go to upper case, a
  ---missing closing quote is added, and so are missing closing parentheses. Sheet names keep
  ---their case.
  ---@param text string
  ---@return string
  function M.normalize (text)
    if not M.is_formula (text) then
      return text
    end
    local src = text
    local tokens = M.tokenize (src, 2)
    if not tokens then
      src = text .. '"'
      tokens = M.tokenize (src, 2)
      if not tokens then
        return text
      end
    end
    local depth = 0
    local parts = {} ---@type string[]
    local pos = 1
    for _, t in ipairs (tokens) do
      if t.kind == 'open' then
        depth = depth + 1
      elseif t.kind == 'close' then
        depth = depth - 1
      end
      local kind = t.kind
      if
        kind == 'ref'
        or kind == 'range'
        or kind == 'error'
        or kind == 'name'
      then
        local head = t.sheet_text or ''
        local up = head .. string.upper (string.sub (t.text, #head + 1))
        if up ~= t.text then
          parts[#parts + 1] = string.sub (src, pos, t.from - 1)
          parts[#parts + 1] = up
          pos = t.to + 1
        end
      end
    end
    parts[#parts + 1] = string.sub (src, pos)
    local out = table.concat (parts)
    if depth > 0 then
      out = out .. string.rep (')', depth)
    end
    return out
  end
end

---------------------------------------------------------------------------------------------
-- Typing formulas
---------------------------------------------------------------------------------------------

-- The helpers of this part stay inside a block, since a chunk can hold only 200 locals.
do
  ---The function name right before byte `i`, the "(" of a call, or nil when a plain bracket
  ---opens there.
  ---@param text string
  ---@param i integer
  ---@return string?
  local function name_before (text, i)
    local head = string.sub (text, 1, i - 1)
    local s, name = string.match (head, '()([%a_][%w_%.]*)%s*$')
    if not name then
      return nil
    end
    local prev = string.sub (head, s - 1, s - 1)
    if prev ~= '' and string.find (prev, '[%w_%.%$!:\'"#]') then
      return nil
    end
    return string.upper (name)
  end

  ---Walks formula text up to the byte before `stop`. Returns the quote `stop` sits inside, `"`
  ---for text or `'` for a sheet name, and the brackets open around it, innermost last.
  ---@param text string
  ---@param stop integer
  ---@return string?
  ---@return Sheet.Frame[]
  local function scan (text, stop)
    local frames = {} ---@type Sheet.Frame[]
    local quote = nil ---@type string?
    local i = 2
    while i < stop do
      local ch = string.sub (text, i, i)
      if quote then
        if ch == quote then
          if i + 1 < stop and string.sub (text, i + 1, i + 1) == quote then
            i = i + 1
          else
            quote = nil
          end
        end
      elseif ch == '"' or ch == "'" then
        quote = ch
      elseif ch == '(' then
        frames[#frames + 1] =
          { name = name_before (text, i), arg = 1, brace = false }
      elseif ch == '{' then
        frames[#frames + 1] = { arg = 1, brace = true }
      elseif ch == ')' or ch == '}' then
        local brace = ch == '}'
        for k = #frames, 1, -1 do
          local found = frames[k].brace == brace
          frames[k] = nil
          if found then
            break
          end
        end
      elseif ch == ',' then
        local top = frames[#frames]
        if top then
          top.arg = top.arg + 1
        end
      end
      i = i + 1
    end
    return quote, frames
  end

  ---True when some function name starts with `prefix`, ignoring case.
  ---@param prefix string
  ---@return boolean
  local function names_start (prefix)
    local up = string.upper (prefix)
    for _, name in ipairs (M.functions) do
      if string.sub (name, 1, #up) == up then
        return true
      end
    end
    return false
  end

  ---The function name being typed when the caret sits before byte `pos`: `from` and `to` span
  ---the whole name, and `prefix` is the part before the caret. Returns nil inside text in
  ---quotes, inside a sheet name, after a "!" or ":", and when no function starts that way.
  ---@param text string
  ---@param pos integer
  ---@return Sheet.Completion?
  function M.complete (text, pos)
    if string.sub (text, 1, 1) ~= '=' or pos < 2 or pos > #text + 1 then
      return nil
    end
    if scan (text, pos) then
      return nil
    end
    local head = string.sub (text, 1, pos - 1)
    local from, prefix = string.match (head, '()([%a_][%w_%.]*)$')
    if not from then
      return nil
    end
    local prev = string.sub (text, from - 1, from - 1)
    if string.find (prev, '[%w_%.%$!:\'"#]') then
      return nil
    end
    local rest = string.match (text, '^[%w_%.]*', pos)
    local to = pos - 1 + #rest
    if string.sub (text, to + 1, to + 1) == '!' or not names_start (prefix) then
      return nil
    end
    return { from = from, to = to, prefix = prefix }
  end

  ---The innermost function whose arguments hold the caret before byte `pos`, and which of its
  ---arguments the caret is in. Plain brackets and array constants are passed over. Returns nil
  ---outside every function.
  ---@param text string
  ---@param pos integer
  ---@return Sheet.CallInfo?
  function M.call_at (text, pos)
    if string.sub (text, 1, 1) ~= '=' then
      return nil
    end
    local _, frames = scan (text, math.min (pos, #text + 1))
    for k = #frames, 1, -1 do
      local frame = frames[k]
      if not frame.brace and frame.name then
        ---@type Sheet.CallInfo
        local info = { name = frame.name, arg = frame.arg }
        return info
      end
    end
    return nil
  end

  ---Every reference in formula text, in order, with the bytes it spans, for colouring. Text
  ---still being typed works too.
  ---@param text string
  ---@return Sheet.RefSpan[]
  function M.ref_spans (text)
    local out = {} ---@type Sheet.RefSpan[]
    if string.sub (text, 1, 1) ~= '=' then
      return out
    end
    for _, t in ipairs (lex (text, 2, true) or {}) do
      if t.kind == 'ref' or t.kind == 'range' then
        out[#out + 1] = {
          from = t.from,
          to = t.to,
          area = area_of (t.a --[[@as Sheet.Ref]], t.b),
        }
      end
    end
    return out
  end

  -- The anchors F4 moves to from each one, column first: A1, $A$1, A$1, $A1, then A1 again.
  local NEXT_ANCHOR = {
    ['--'] = '$$',
    ['$$'] = '-$',
    ['-$'] = '$-',
    ['$-'] = '--',
  }

  ---Sets the anchors a reference has room for. A whole column has no row, and a whole row no
  ---column.
  ---@param ref Sheet.Ref
  ---@param col_abs boolean
  ---@param row_abs boolean
  local function set_anchor (ref, col_abs, row_abs)
    if ref.col then
      ref.col_abs = col_abs
    end
    if ref.row then
      ref.row_abs = row_abs
    end
  end

  ---F4: cycles the `$` anchors of the reference at or right before the caret, `pos`, through
  ---A1, $A$1, A$1 and $A1. Both ends of a range change together. Returns the new text and the
  ---caret after the reference, or the text and `pos` unchanged when no reference is there.
  ---@param text string
  ---@param pos integer
  ---@return string
  ---@return integer
  function M.toggle_anchor (text, pos)
    if string.sub (text, 1, 1) ~= '=' then
      return text, pos
    end
    local hit = nil ---@type Sheet.Token?
    for _, t in ipairs (lex (text, 2, true) or {}) do
      if t.kind == 'ref' or t.kind == 'range' then
        if t.from <= pos and pos <= t.to then
          hit = t
          break
        end
        if t.to + 1 == pos then
          hit = t
        end
      end
    end
    if not hit then
      return text, pos
    end
    local a = copy_ref (hit.a --[[@as Sheet.Ref]])
    local b = hit.b and copy_ref (hit.b) or nil
    local col_abs, row_abs = a.col_abs, a.row_abs
    if a.col and a.row then
      local key = (col_abs and '$' or '-') .. (row_abs and '$' or '-')
      local next_key = NEXT_ANCHOR[key]
      col_abs = string.sub (next_key, 1, 1) == '$'
      row_abs = string.sub (next_key, 2, 2) == '$'
    elseif a.col then
      col_abs = not col_abs
    else
      row_abs = not row_abs
    end
    set_anchor (a, col_abs, row_abs)
    if b then
      set_anchor (b, col_abs, row_abs)
    end
    local new = token_text (hit, a, b)
    local out = string.sub (text, 1, hit.from - 1)
      .. new
      .. string.sub (text, hit.to + 1)
    return out, hit.from + #new
  end

  ---True when the caret in formula text sits where a reference can go, such as right after
  ---"=", "(", ",", an operator or a sheet name's "!", and not inside quotes. Clicking a cell or
  ---pressing an arrow key then puts the cell's address there. `pos` is the byte the caret sits
  ---before.
  ---@param text string
  ---@param pos integer
  ---@return boolean
  function M.can_point (text, pos)
    if string.sub (text, 1, 1) ~= '=' then
      return false
    end
    if scan (text, pos) then
      return false
    end
    local head = string.sub (text, 1, pos - 1)
    local before = string.match (head, '(%S)%s*$')
    if not before or not string.find ('=(,+-*/^&<>:!', before, 1, true) then
      return false
    end
    if before == '!' then
      -- An error such as #REF! ends in "!" too, and no reference goes after it.
      local tail = string.upper (string.match (head, '(%S+)%s*$') or '')
      for _, code in ipairs (M.ERROR_CODES) do
        if string.sub (tail, -#code) == code then
          return false
        end
      end
    end
    local after = string.match (string.sub (text, pos), '^%s*(%S)')
    return after == nil or string.find (')+-*/^&<>=,', after, 1, true) ~= nil
  end

end

return M
