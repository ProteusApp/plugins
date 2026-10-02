-- sheet_formula_parse: the parser of the Sheet app's formula language. It turns the tokens of
-- formula text into a tree, checks how many arguments each call gives, and holds the table of
-- the functions formulas can call, which the function modules fill.

local lexer = require ('sheet_formula_lex') --[[@as Sheet.FormulaLex]]

---@class Sheet.FormulaModule
local M = lexer.M
local ERRORS, MANY, MAX_DEPTH = lexer.ERRORS, lexer.MANY, lexer.MAX_DEPTH

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

---What the other parts of the formula language share from this one.
---@class Sheet.FormulaParse
local P = {
  COMPARE = COMPARE,
  FUNCS = FUNCS,
}

return P
