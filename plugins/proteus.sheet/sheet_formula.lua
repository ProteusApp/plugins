-- sheet_formula: the formula language of the Sheet app. A tokenizer and a parser turn the
-- text after "=" into a tree, and an evaluator walks the tree. Formula text never runs as Lua.
--
-- The same tokens drive the rewrites of formula text: moving the references of a copied
-- formula, fixing references after a row or a column is inserted or deleted, and following a
-- sheet that is renamed or deleted. The helpers at the end serve the formula bar while a
-- formula is typed: completion, the argument being typed, reference colours and F4.

local lexer = require ('sheet_formula_lex') --[[@as Sheet.FormulaLex]]
local parser = require ('sheet_formula_parse') --[[@as Sheet.FormulaParse]]
-- The function kit fills the table of functions and adds the catalog to the module.
require ('sheet_formula_kit')

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
local FUNCS = parser.FUNCS
local LAST_COL, LAST_ROW, lex, lower =
  lexer.LAST_COL, lexer.LAST_ROW, lexer.lex, lexer.lower

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
