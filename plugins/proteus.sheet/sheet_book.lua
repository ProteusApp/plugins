-- sheet_book: the workbook of the Sheet app. A book holds its sheets in order and knows the
-- active one. It keeps one undo history for every sheet, works out the formulas of the whole
-- book in the order of their references, and reads and writes the `.sheet.json` file. The
-- cells of each sheet live in sheet_model. The module draws nothing and calls no host function.
--
-- After an edit, only the formulas that read the edited cells, directly or through others,
-- are worked out again, together with the volatile ones such as NOW and INDIRECT. Each sheet
-- keeps an index from its cells to the formulas that read them, so finding those formulas
-- does not mean looking at every formula in the book.

local formula = require ('sheet_formula') --[[@as Sheet.FormulaModule]]
local model = require ('sheet_model') --[[@as Sheet.ModelModule]]

---A cell style. Every field is optional, and a missing field means the default. An own style
---may hold a reset value that cancels a row or column field: `false` for the flags, `'none'`
---for colours and borders, `'General'` for the format, `'general'` for `align`, `'bottom'` for
---`valign` and 13 for `size`.
---@class Sheet.Style
---@field bold? boolean
---@field italic? boolean
---@field underline? boolean
---@field strike? boolean
---@field size? number Font size in pixels. The default is 13.
---@field color? string Text colour, `#rrggbb`.
---@field fill? string Background colour, `#rrggbb`.
---@field align? 'left'|'center'|'right'|'general' Missing means numbers right, text left, others centre.
---@field valign? 'top'|'middle'|'bottom' The default is bottom.
---@field wrap? boolean
---@field format? string A number format code. Missing means General.
---@field border_top? string `thin`, `medium`, `thick`, `dashed`, `dotted` or `double`.
---@field border_right? string
---@field border_bottom? string
---@field border_left? string
---@field border_color? string One colour for every side. The default is a dark grey.

---A conditional formatting rule. The list runs in order of priority, as in Excel: where two
---rules set the same field, the one higher in the list wins, and a rule with `stop` keeps the
---rules below it from applying where it holds. `value` and `value2` are text as typed.
---@class Sheet.Rule
---@field range string Such as `D5:D10`.
---@field type string `compare`, `text`, `blank`, `not_blank`, `error`, `duplicate`, `unique`, `top`, `bottom`, `above_average`, `below_average`, `formula`, `scale` or `bar`.
---@field op? string
---@field value? string
---@field value2? string
---@field count? number
---@field percent? boolean
---@field formula? string Written for the top left cell of the range.
---@field style? Sheet.Style
---@field min_color? string
---@field mid_color? string
---@field max_color? string
---@field color? string The colour of a data bar.
---@field stop? boolean Stop if true: where the rule holds, the rules below it do not apply.

---A validation rule: a list of allowed text, or a test on numbers.
---@class Sheet.Validation
---@field range string
---@field type 'list'|'number'
---@field values? string[]
---@field op? string
---@field value? string
---@field value2? string
---@field integer? boolean
---@field message? string
---@field strict? boolean False warns instead of refusing.

---What one column of a filter keeps shown: the rows whose shown text is in `values`, and the
---rows that pass the test in `op`. A column with both keeps rows that pass both.
---@class Sheet.FilterColumn
---@field values? string[] The shown texts that stay shown. An empty cell is `''`.
---@field op? string A compare or text op of the rules, or `blank` or `not_blank`.
---@field value? string
---@field value2? string

---@class Sheet.Filter
---@field range string
---@field columns? table<string, Sheet.FilterColumn> Column letters to their filters.

---@class Sheet.Freeze
---@field rows? integer
---@field cols? integer

---One sheet of a workbook file.
---@class Sheet.SheetData
---@field name string
---@field rows? integer
---@field cols? integer
---@field widths? table<string, number> Column letters to pixels.
---@field heights? table<string, number> Row numbers, as text, to pixels.
---@field hidden_rows? integer[]
---@field hidden_cols? string[]
---@field freeze? Sheet.Freeze
---@field cells? table<string, string> Addresses to the text as typed.
---@field styles? table<string, Sheet.Style>
---@field col_styles? table<string, Sheet.Style>
---@field row_styles? table<string, Sheet.Style>
---@field merges? string[]
---@field notes? table<string, string>
---@field filter? Sheet.Filter
---@field rules? Sheet.Rule[]
---@field validation? Sheet.Validation[]
---@field charts? Sheet.ChartSpec[]

---A workbook file, version 3. Version 3 lists conditional formatting rules first rule
---first, as Excel does, where version 2 listed them the other way round.
---@class Sheet.BookData
---@field version integer
---@field active? integer The sheet shown first, counting from 1.
---@field sheets Sheet.SheetData[]

---@class Sheet.BookOptions
---@field clock? fun(): number The date and time now, as a serial number.
---@field random? fun(): number
---@field rows? integer The size of the first sheet of a new book.
---@field cols? integer
---@field name? string The name of the first sheet of a new book.

---A cell on a sheet.
---@class Sheet.Position
---@field sheet Sheet.Sheet
---@field row integer
---@field col integer

---A block a formula reads, with its sheet found. A whole column or row runs to `math.huge`.
---@class Sheet.WatchArea
---@field sheet Sheet.Sheet
---@field r1 integer
---@field c1 integer
---@field r2 number
---@field c2 number
---@field cell Sheet.Cell The formula that reads it.

---Each sheet's index from its cells to the formulas that read them.
---@class Sheet.Watch
---@field points table<integer, table<Sheet.Cell, boolean>> Small blocks, cell by cell.
---@field big table<Sheet.WatchArea, boolean> Blocks of more than 64 cells.
---@field by_col table<integer, table<Sheet.Cell, boolean>> The formulas of each column.
---@field spills table<integer, Sheet.Cell> The formula whose block shows in each cell around it.
---@field blocked table<Sheet.Cell, Sheet.Rect> Formulas whose block cannot spill, and the cells it needs.

---One change inside an undo step. `cell` changes a cell's text and style. `prop` changes one
---entry of a sheet's map, or a whole field when `key` is nil. `state` swaps everything a sheet
---holds, around an insert or a delete. `sheets` changes the list of sheets.
---@class Sheet.Change
---@field kind 'cell'|'prop'|'state'|'sheets'
---@field sheet? Sheet.Sheet
---@field row? integer
---@field col? integer
---@field field? string
---@field key? any
---@field before any
---@field after any
---@field active_before? integer
---@field active_after? integer

---One undo step.
---@class Sheet.Step
---@field changes Sheet.Change[]
---@field sheet? Sheet.Sheet The sheet it happened on.
---@field select? Sheet.Rect The block to select after undo or redo.
---@field label? string Such as `Paste`, for the Undo menu item.

---What undo or redo did, so the UI can show it.
---@class Sheet.StepInfo
---@field sheet integer The sheet to show, which is now the active one.
---@field rect? Sheet.Rect The block to select, or nil when the step changed no cells.
---@field label? string

---@class Sheet.BatchOptions
---@field sheet? Sheet.Sheet
---@field select? Sheet.Rect
---@field label? string

---What the last recalculation did.
---@class Sheet.RecalcStats
---@field full boolean True when every formula was worked out.
---@field evaluated integer How many formulas were worked out.
---@field dirty integer How many formulas were due.

---@class Sheet.Book
---@field __index Sheet.Book
---@field sheets Sheet.Sheet[]
---@field active integer
---@field clock fun(): number
---@field random fun(): number
---@field done Sheet.Step[]
---@field undone Sheet.Step[]
---@field depth integer How many batches are open.
---@field batch? Sheet.Step The step being built.
---@field batch_cells? table<Sheet.Sheet, table<integer, Sheet.Change>>
---@field batch_props? table<Sheet.Sheet, table<string, Sheet.Change>>
---@field full boolean True when every formula needs working out again.
---@field stale boolean True when the volatile formulas need working out again.
---@field edited Sheet.Position[] Cells whose text changed since the last recalculation.
---@field spill_moved Sheet.Position[] Cells a block spilled into, or left, since the formulas that read them were worked out.
---@field volatile table<Sheet.Cell, boolean>
---@field row_readers table<Sheet.Cell, boolean> Formulas that read which rows are hidden, such as SUBTOTAL.
---@field rows_stale boolean True when hidden rows changed since those formulas were worked out.
---@field by_name table<string, Sheet.Sheet> Sheets by lower-case name.
---@field name_cache table<string, Sheet.Sheet|false> Sheets by name as a formula writes it.
---@field live table<Sheet.Sheet, boolean> The sheets in the book now.
---@field nesting integer How deep the formulas worked out on demand go.
---@field evaluated integer
---@field stamp integer Counts every change and recalculation, so caches know when to refresh.
---@field last Sheet.RecalcStats
---@field edits integer Counts the steps done, undone and redone, so the UI can tell when to save.
local Book = {}
Book.__index = Book

---@class Sheet.BookModule
---@field HISTORY integer
local M = {}

local HISTORY = 200
M.HISTORY = HISTORY
-- A block with at most this many cells goes into the index cell by cell.
local SMALL = 64
-- How deep formulas worked out on demand may nest before they give #CYCLE!. Each level holds
-- a pcall on the C stack, which runs out a few hundred calls deep.
local DEPTH = 32
local HUGE = math.huge
local KEY = model.KEY
local CYCLE = formula.error ('#CYCLE!')
local SPILL = formula.error ('#SPILL!')
local TOO_DEEP = formula.error ('#CALC!')
-- How many times in a row a recalculation goes round again for blocks that spilled further.
local SPILL_ROUNDS = 8
local BROKEN = formula.error ('#ERROR!')
local MAX_NAME = 100

---@type table<Sheet.Node, Sheet.Area[]>
local refs_of = setmetatable ({}, { __mode = 'k' })
---@type table<Sheet.Node, boolean>
local volatile_of = setmetatable ({}, { __mode = 'k' })

---@param ast Sheet.Node
---@return Sheet.Area[]
local function refs (ast)
  local list = refs_of[ast]
  if not list then
    list = formula.refs (ast)
    refs_of[ast] = list
  end
  return list
end

---@param ast Sheet.Node
---@return boolean
local function is_volatile (ast)
  local v = volatile_of[ast]
  if v == nil then
    v = formula.volatile (ast)
    volatile_of[ast] = v
  end
  return v
end

---@param a Sheet.WatchArea
---@return boolean
local function small (a)
  return a.r2 ~= HUGE
    and a.c2 ~= HUGE
    and (a.r2 - a.r1 + 1) * (a.c2 - a.c1 + 1) <= SMALL
end

---@param list any[]
---@return any[]
local function copy_list (list)
  local out = {} ---@type any[]
  for i, v in ipairs (list) do
    out[i] = v
  end
  return out
end

---------------------------------------------------------------------------------------------
-- Making a book
---------------------------------------------------------------------------------------------

---@param opts? Sheet.BookOptions
---@return Sheet.Book
local function blank_book (opts)
  local self = setmetatable ({}, Book) --[[@as Sheet.Book]]
  self.sheets = {}
  self.active = 1
  self.clock = opts and opts.clock or formula.clock
  self.random = opts and opts.random or math.random
  self.done = {}
  self.undone = {}
  self.depth = 0
  self.full = true
  self.stale = false
  self.edited = {}
  self.spill_moved = {}
  self.volatile = {}
  self.row_readers = {}
  self.rows_stale = false
  self.by_name = {}
  self.name_cache = {}
  self.live = {}
  self.nesting = 0
  self.evaluated = 0
  self.stamp = 0
  self.last = { full = true, evaluated = 0, dirty = 0 }
  self.edits = 0
  return self
end

---Makes a book with one empty sheet, named `Sheet1` unless `opts.name` says otherwise.
---@param opts? Sheet.BookOptions
---@return Sheet.Book
function M.new (opts)
  local book = blank_book (opts)
  local sheet = model.blank (
    book,
    opts and opts.name or 'Sheet1',
    opts and opts.rows,
    opts and opts.cols
  )
  book.sheets = { sheet }
  book:names_changed ()
  return book
end

---------------------------------------------------------------------------------------------
-- Sheets
---------------------------------------------------------------------------------------------

---Finds the maps of sheet names again, after a sheet is added, renamed, moved or deleted.
function Book:names_changed ()
  self.by_name = {}
  self.name_cache = {}
  self.live = {}
  for _, sheet in ipairs (self.sheets) do
    self.by_name[string.lower (sheet.name)] = sheet
    self.live[sheet] = true
  end
  self.full = true
  self.stamp = self.stamp + 1
end

---The sheet with this name, ignoring case, or nil.
---@param name string
---@return Sheet.Sheet?
function Book:find (name)
  local hit = self.name_cache[name]
  if hit == nil then
    hit = self.by_name[string.lower (name)] or false
    self.name_cache[name] = hit
  end
  return hit or nil
end

---Where a sheet sits in the book, counting from 1, or nil when it is not in the book.
---@param sheet Sheet.Sheet
---@return integer?
function Book:index_of (sheet)
  for i, s in ipairs (self.sheets) do
    if s == sheet then
      return i
    end
  end
  return nil
end

---The sheet at an index, or the sheet with a name.
---@param which integer|string
---@return Sheet.Sheet?
function Book:sheet (which)
  if type (which) == 'number' then
    return self.sheets[which]
  end
  return self:find (which --[[@as string]])
end

---@return Sheet.Sheet
function Book:active_sheet ()
  return self.sheets[self.active] or self.sheets[1]
end

---Shows another sheet. This is not an undo step.
---@param index integer
function Book:set_active (index)
  if self.sheets[index] then
    self.active = index
  end
end

---The names of the sheets, in order.
---@return string[]
function Book:names ()
  local out = {} ---@type string[]
  for i, sheet in ipairs (self.sheets) do
    out[i] = sheet.name
  end
  return out
end

---Why a text cannot be a sheet name at all, or nil when it can.
---@param name any
---@return string?
local function name_shape (name)
  if type (name) ~= 'string' or string.match (name, '^%s*$') then
    return 'A sheet needs a name.'
  end
  if #name > MAX_NAME then
    return 'A sheet name can have at most 100 characters.'
  end
  if string.find (name, '[%[%]:%*%?/\\]') then
    return 'A sheet name cannot hold any of these: [ ] : * ? / \\'
  end
  if string.sub (name, 1, 1) == "'" or string.sub (name, -1) == "'" then
    return "A sheet name cannot start or end with '."
  end
  return nil
end

---Why a name cannot name a sheet, or nil when it can. `except` is the sheet being renamed,
---which may keep its own name in another case.
---@param name string
---@param except? Sheet.Sheet
---@return string?
function Book:name_problem (name, except)
  local shape = name_shape (name)
  if shape then
    return shape
  end
  local other = self.by_name[string.lower (name)]
  if other and other ~= except then
    return 'Another sheet is called ' .. other.name .. '.'
  end
  return nil
end

---A name no sheet has yet. `Sheet` gives `Sheet1`, `Sheet2` and so on. With `copy`, a base
---such as `Budget` gives `Budget (2)`, `Budget (3)` and so on.
---@param base string
---@param copy? boolean
---@return string
function Book:free_name (base, copy)
  local stem = string.gsub (base, ' %(%d+%)$', '')
  stem = string.sub (stem, 1, MAX_NAME - 6)
  local i = copy and 2 or 1
  while true do
    local name = copy and (stem .. ' (' .. i .. ')') or (stem .. i)
    if not self.by_name[string.lower (name)] then
      return name
    end
    i = i + 1
  end
end

---Replaces the list of sheets without recording it.
---@param list Sheet.Sheet[]
---@param active integer
function Book:put_sheets (list, active)
  self.sheets = copy_list (list)
  for _, sheet in ipairs (self.sheets) do
    sheet.book = self
  end
  self.active = math.max (1, math.min (active, #self.sheets))
  self:names_changed ()
end

---Records a new list of sheets as part of the open step, and puts it in place.
---@param list Sheet.Sheet[]
---@param active integer
function Book:change_sheets (list, active)
  self:log ({
    kind = 'sheets',
    before = copy_list (self.sheets),
    after = copy_list (list),
    active_before = self.active,
    active_after = active,
  })
  self:put_sheets (list, active)
end

---Adds an empty sheet, after the active one unless `at` says where, and shows it. The name is
---the next free `SheetN` when `name` is nil. One undo step.
---@param name? string
---@param at? integer
---@return Sheet.Sheet?
---@return string? problem
function Book:add_sheet (name, at)
  local n = name or self:free_name ('Sheet')
  local problem = self:name_problem (n)
  if problem then
    return nil, problem
  end
  local sheet = model.blank (self, n)
  local list = copy_list (self.sheets)
  local where = math.max (1, math.min (at or (self.active + 1), #list + 1))
  table.insert (list, where, sheet)
  self:begin ({ sheet = sheet, label = 'Add sheet' })
  self:change_sheets (list, where)
  self:finish ()
  return sheet, nil
end

---Rewrites every formula that names a sheet, and every formula rule, through `fn`, as part
---of the open step. `except` is a sheet to leave alone.
---@param fn fun(text: string, own: Sheet.Sheet): string
---@param except? Sheet.Sheet
function Book:rewrite_formulas (fn, except)
  for _, sheet in ipairs (self.sheets) do
    if sheet ~= except then
      self:rewrite_sheet (sheet, fn)
    end
  end
end

---Rewrites the formulas of one sheet, as `rewrite_formulas` does.
---@param sheet Sheet.Sheet
---@param fn fun(text: string, own: Sheet.Sheet): string
function Book:rewrite_sheet (sheet, fn)
  local list = {} ---@type Sheet.Cell[]
  for _, cell in pairs (sheet.cells) do
    if cell.formula and string.find (cell.text, '!', 1, true) then
      list[#list + 1] = cell
    end
  end
  for _, cell in ipairs (list) do
    local text = fn (cell.text, sheet)
    if text ~= cell.text then
      sheet:record (cell.row, cell.col, { text = text, style = cell.style })
    end
  end
  local rules = {} ---@type Sheet.Rule[]
  local changed = false
  for i, rule in ipairs (sheet.rules) do
    rules[i] = rule
    if type (rule.formula) == 'string' then
      local text = fn (rule.formula, sheet)
      if text ~= rule.formula then
        local copy = {} ---@type table<string, any>
        for k, v in
          pairs (rule --[[@as table<string, any>]])
        do
          copy[k] = v
        end
        copy.formula = text
        rules[i] = copy --[[@as Sheet.Rule]]
        changed = true
      end
    end
  end
  if changed then
    sheet:set_field ('rules', rules)
  end
end

---Renames a sheet, and points every formula that names it at the new name. One undo step.
---Returns false and the reason when the name cannot be used.
---@param index integer
---@param name string
---@return boolean
---@return string? problem
function Book:rename_sheet (index, name)
  local sheet = self.sheets[index]
  if not sheet then
    return false, 'There is no such sheet.'
  end
  local problem = self:name_problem (name, sheet)
  if problem then
    return false, problem
  end
  if name == sheet.name then
    return true, nil
  end
  local old = sheet.name
  self:begin ({ sheet = sheet, label = 'Rename sheet' })
  self:rewrite_formulas (function (text)
    return formula.rename_sheet (text, old, name)
  end)
  sheet:set_prop ('name', nil, name)
  self:finish ()
  return true, nil
end

---Deletes a sheet. Every reference to it turns into #REF!. A book keeps at least one sheet.
---One undo step.
---@param index integer
---@return boolean
---@return string? problem
function Book:delete_sheet (index)
  local sheet = self.sheets[index]
  if not sheet then
    return false, 'There is no such sheet.'
  end
  if #self.sheets == 1 then
    return false, 'A workbook keeps at least one sheet.'
  end
  local list = copy_list (self.sheets)
  table.remove (list, index)
  local active = self.active
  if active > index or active > #list then
    active = active - 1
  end
  -- The step names the deleted sheet, so undo shows it again when it comes back.
  self:begin ({ sheet = sheet, label = 'Delete sheet' })
  self:change_sheets (list, math.max (1, active))
  self:rewrite_formulas (function (text)
    return formula.drop_sheet (text, sheet.name)
  end)
  self:finish ()
  return true, nil
end

---Copies a sheet with everything it holds, under a free name such as `Budget (2)`, right after
---it, and shows the copy. One undo step.
---@param index integer
---@return Sheet.Sheet?
function Book:duplicate_sheet (index)
  local sheet = self.sheets[index]
  if not sheet then
    return nil
  end
  local copy = sheet:clone (self:free_name (sheet.name, true))
  local list = copy_list (self.sheets)
  table.insert (list, index + 1, copy)
  self:begin ({ sheet = copy, label = 'Duplicate sheet' })
  self:change_sheets (list, index + 1)
  self:finish ()
  return copy
end

---Moves a sheet to another place in the order. The same sheet stays active. One undo step.
---@param from integer
---@param to integer
---@return boolean
function Book:move_sheet (from, to)
  local sheet = self.sheets[from]
  if not sheet then
    return false
  end
  local list = copy_list (self.sheets)
  table.remove (list, from)
  local where = math.max (1, math.min (to, #list + 1))
  if where == from then
    return false
  end
  table.insert (list, where, sheet)
  local shown = self:active_sheet ()
  local active = 1
  for i, s in ipairs (list) do
    if s == shown then
      active = i
    end
  end
  self:begin ({ sheet = shown, label = 'Move sheet' })
  self:change_sheets (list, active)
  self:finish ()
  return true
end

---------------------------------------------------------------------------------------------
-- Recalculation
---------------------------------------------------------------------------------------------

---Splits formula cells into groups that depend on each other in a loop, with each group
---after every group it reads. This is Tarjan's method, written without recursion so a long
---chain of formulas cannot overflow the stack.
---@param nodes Sheet.Cell[]
---@return Sheet.Cell[][]
local function groups_of (nodes)
  local index = {} ---@type table<Sheet.Cell, integer>
  local low = {} ---@type table<Sheet.Cell, integer>
  local on_stack = {} ---@type table<Sheet.Cell, boolean>
  local stack = {} ---@type Sheet.Cell[]
  local out = {} ---@type Sheet.Cell[][]
  local counter = 0
  ---@param v Sheet.Cell
  local function visit (v)
    index[v], low[v] = counter, counter
    counter = counter + 1
    stack[#stack + 1] = v
    on_stack[v] = true
  end
  for _, start in ipairs (nodes) do
    if not index[start] then
      visit (start)
      local work = { { cell = start, next = 1 } }
      while #work > 0 do
        local frame = work[#work]
        local v = frame.cell
        local deps = v.deps or {}
        if frame.next <= #deps then
          local w = deps[frame.next]
          frame.next = frame.next + 1
          if not index[w] then
            visit (w)
            work[#work + 1] = { cell = w, next = 1 }
          elseif on_stack[w] then
            low[v] = math.min (low[v], index[w])
          end
        else
          work[#work] = nil
          local parent = work[#work]
          if parent then
            low[parent.cell] = math.min (low[parent.cell], low[v])
          end
          if low[v] == index[v] then
            local group = {} ---@type Sheet.Cell[]
            while true do
              local w = table.remove (stack) --[[@as Sheet.Cell]]
              on_stack[w] = nil
              group[#group + 1] = w
              if w == v then
                break
              end
            end
            out[#out + 1] = group
          end
        end
      end
    end
  end
  return out
end

---Adds a formula cell to the indexes of the sheets it reads.
---@param sheet Sheet.Sheet
---@param cell Sheet.Cell
function Book:watch (sheet, cell)
  cell.home = sheet
  local areas = {} ---@type Sheet.WatchArea[]
  cell.areas = areas
  local mine = sheet.watch.by_col[cell.col]
  if not mine then
    mine = {}
    sheet.watch.by_col[cell.col] = mine
  end
  mine[cell] = true
  local ast = cell.ast
  if not ast then
    return
  end
  for _, area in ipairs (refs (ast)) do
    local target = sheet ---@type Sheet.Sheet?
    if area.sheet then
      target = self:find (area.sheet)
    end
    if target then
      ---@type Sheet.WatchArea
      local a = {
        sheet = target,
        r1 = area.r1 or 1,
        c1 = area.c1 or 1,
        r2 = area.r2 or HUGE,
        c2 = area.c2 or HUGE,
        cell = cell,
      }
      areas[#areas + 1] = a
      local points = target.watch.points
      if small (a) then
        for r = a.r1, a.r2 --[[@as integer]] do
          for c = a.c1, a.c2 --[[@as integer]] do
            local key = r * KEY + c
            local set = points[key]
            if not set then
              set = {}
              points[key] = set
            end
            set[cell] = true
          end
        end
      else
        target.watch.big[a] = true
      end
    end
  end
  if is_volatile (ast) then
    cell.volatile = true
    self.volatile[cell] = true
  end
  if formula.reads_hidden (ast) then
    self.row_readers[cell] = true
  end
end

---Takes a formula cell out of the indexes.
---@param sheet Sheet.Sheet
---@param cell Sheet.Cell
function Book:unwatch (sheet, cell)
  local mine = sheet.watch.by_col[cell.col]
  if mine then
    mine[cell] = nil
  end
  self.volatile[cell] = nil
  self.row_readers[cell] = nil
  for _, a in ipairs (cell.areas or {}) do
    local w = a.sheet.watch
    if small (a) then
      for r = a.r1, a.r2 --[[@as integer]] do
        for c = a.c1, a.c2 --[[@as integer]] do
          local key = r * KEY + c
          local set = w.points[key]
          if set then
            set[cell] = nil
            if next (set) == nil then
              w.points[key] = nil
            end
          end
        end
      end
    else
      w.big[a] = nil
    end
  end
  cell.areas = nil
end

---Calls `fn` with every formula cell that reads a cell.
---@param sheet Sheet.Sheet
---@param row integer
---@param col integer
---@param fn fun(cell: Sheet.Cell)
function Book:readers (sheet, row, col, fn)
  local w = sheet.watch
  local set = w.points[row * KEY + col]
  if set then
    for cell in pairs (set) do
      fn (cell)
    end
  end
  for a in pairs (w.big) do
    if row >= a.r1 and row <= a.r2 and col >= a.c1 and col <= a.c2 then
      fn (a.cell)
    end
  end
end

---Tells the book that a cell's text changed, so the formulas that read it are worked out
---again. `old` and `new` are the cell before and after, either one nil for an empty cell.
---@param sheet Sheet.Sheet
---@param row integer
---@param col integer
---@param old? Sheet.Cell
---@param new? Sheet.Cell
function Book:cell_changed (sheet, row, col, old, new)
  self.stamp = self.stamp + 1
  if self.full then
    return
  end
  if old and old.formula then
    self:unwatch (sheet, old)
    self:place (sheet, old, nil)
  end
  if new and new.formula then
    self:watch (sheet, new)
  end
  local list = self.edited
  list[#list + 1] = { sheet = sheet, row = row, col = col }
end

---Counts a change that needs no recalculation, such as a style, so caches refresh.
function Book:touch ()
  self.stamp = self.stamp + 1
end

---The context formulas on a sheet are worked out in. A cell that waits to be worked out is
---worked out when a formula reads it, which is how INDIRECT and OFFSET reach cells no
---reference names.
---@param sheet Sheet.Sheet
---@return Sheet.Context
function Book:context (sheet)
  local ctx = sheet.ctx
  if ctx then
    return ctx
  end
  local book = self
  ---@type Sheet.Context
  ctx = {
    rows = sheet.rows,
    cols = sheet.cols,
    clock = self.clock,
    random = self.random,
    value = function (row, col, name)
      local target = sheet
      if name then
        local found = book:find (name)
        if not found then
          return nil
        end
        target = found
      end
      local key = row * KEY + col
      local cell = target.cells[key]
      if not cell or cell.text == '' then
        local anchor = target.watch.spills[key]
        if not anchor then
          return nil
        end
        if anchor.pending then
          book:on_demand (anchor)
        end
        return (target:spilled (row, col))
      end
      if cell.pending then
        return book:on_demand (cell)
      end
      return cell.value
    end,
    size = function (name)
      local found = book:find (name)
      if not found then
        return nil, nil
      end
      return found.rows, found.cols
    end,
    hidden = function (row, name)
      local target = sheet ---@type Sheet.Sheet?
      if name then
        target = book:find (name)
      end
      if not target then
        return nil
      end
      if target:filtered (row) then
        return 'filter'
      end
      return target.hidden_rows[row] and 'user' or nil
    end,
    subtotal = function (row, col, name)
      local target = sheet ---@type Sheet.Sheet?
      if name then
        target = book:find (name)
      end
      local cell = target and target.cells[row * KEY + col]
      if not cell or not cell.formula then
        return false
      end
      local up = string.upper (cell.text)
      return string.find (up, 'SUBTOTAL(', 1, true) ~= nil
        or string.find (up, 'AGGREGATE(', 1, true) ~= nil
    end,
    formula_text = function (row, col, name)
      local target = sheet ---@type Sheet.Sheet?
      if name then
        target = book:find (name)
      end
      local cell = target and target.cells[row * KEY + col]
      if cell and cell.formula then
        return cell.text
      end
      return nil
    end,
    sheet_index = function (name)
      local target = sheet ---@type Sheet.Sheet?
      if name then
        target = book:find (name)
      end
      return target and book:index_of (target)
    end,
    sheet_count = function ()
      return #book.sheets
    end,
    spill = function (row, col, name)
      local target = sheet
      if name then
        local found = book:find (name)
        if not found then
          return nil, nil
        end
        target = found
      end
      local cell = target.cells[row * KEY + col]
      if not cell or not cell.formula then
        return nil, nil
      end
      if cell.pending then
        book:on_demand (cell)
      end
      local area = cell.spill_area
      if not area then
        return nil, nil
      end
      return area.r2 - area.r1 + 1, area.c2 - area.c1 + 1
    end,
  }
  sheet.ctx = ctx
  return ctx
end

---Works out one formula cell.
---@param cell Sheet.Cell
function Book:compute (cell)
  local sheet = cell.home --[[@as Sheet.Sheet]]
  local ctx = self:context (sheet)
  local row, col = ctx.row, ctx.col
  ctx.row, ctx.col = cell.row, cell.col
  ctx.rows, ctx.cols = sheet.rows, sheet.cols
  cell.busy = true
  local ast = cell.ast
  if ast then
    local value, block = formula.evaluate (ast, ctx, true)
    cell.value = value
    self:place (sheet, cell, block)
  else
    cell.value = BROKEN
  end
  cell.busy = nil
  cell.pending = nil
  ctx.row, ctx.col = row, col
  self.evaluated = self.evaluated + 1
end

---True when a block cannot spill into the cells it needs: one of them holds text, or another
---formula's block, or sits in merged cells.
---@param sheet Sheet.Sheet
---@param cell Sheet.Cell
---@param area Sheet.Rect
---@return boolean
local function spill_blocked (sheet, cell, area)
  if area.r2 > formula.LAST_ROW or area.c2 > formula.LAST_COL then
    return true
  end
  local spills = sheet.watch.spills
  for r = area.r1, area.r2 do
    for c = area.c1, area.c2 do
      if r ~= cell.row or c ~= cell.col then
        local key = r * KEY + c
        local other = sheet.cells[key]
        if other and other.text ~= '' then
          return true
        end
        local owner = spills[key]
        if owner and owner ~= cell then
          return true
        end
      end
    end
  end
  for _, m in ipairs (sheet.merges) do
    if model.overlaps (m, area) then
      return true
    end
  end
  return false
end

---Puts the block a formula gave into the cells around it, or takes it away when `block` is
---nil. A block with no room shows #SPILL! in the formula's cell. The cells the block newly
---covers go on `spill_moved`, so the formulas that read them are worked out again.
---@param sheet Sheet.Sheet
---@param cell Sheet.Cell
---@param block Sheet.Array?
function Book:place (sheet, cell, block)
  local w = sheet.watch
  local old = cell.spill_area
  if old then
    for r = old.r1, old.r2 do
      for c = old.c1, old.c2 do
        local key = r * KEY + c
        if w.spills[key] == cell then
          w.spills[key] = nil
        end
      end
    end
  end
  w.blocked[cell] = nil
  cell.spill, cell.spill_area = nil, nil
  local area = nil ---@type Sheet.Rect?
  if block then
    area = {
      r1 = cell.row,
      c1 = cell.col,
      r2 = cell.row + block.h - 1,
      c2 = cell.col + block.w - 1,
    }
    if spill_blocked (sheet, cell, area) then
      cell.value = SPILL
      w.blocked[cell] = area
      area = nil
    else
      for r = area.r1, area.r2 do
        for c = area.c1, area.c2 do
          if r ~= cell.row or c ~= cell.col then
            w.spills[r * KEY + c] = cell
          end
        end
      end
      cell.spill, cell.spill_area = block, area
      sheet:grow (area.r2, area.c2)
    end
  end
  -- The formulas that read the cells the block left are already due when the formula is.
  -- Those that read the cells it newly covers are not.
  local moved = self.spill_moved
  if area then
    for r = area.r1, area.r2 do
      for c = area.c1, area.c2 do
        local before = old
          and r >= old.r1
          and r <= old.r2
          and c >= old.c1
          and c <= old.c2
        if not before then
          moved[#moved + 1] = { sheet = sheet, row = r, col = c }
        end
      end
    end
  end
  if old and not area then
    for r = old.r1, old.r2 do
      for c = old.c1, old.c2 do
        moved[#moved + 1] = { sheet = sheet, row = r, col = c }
      end
    end
  end
end

---Works out a cell that a formula reads before its turn came. A cell already being worked
---out is a loop, #CYCLE!. A chain too deep to follow, such as INDIRECT reading INDIRECT
---more than 32 times over, is #CALC!, since it need not be a loop.
---@param cell Sheet.Cell
---@return Sheet.Value
function Book:on_demand (cell)
  if cell.busy then
    return CYCLE
  end
  if self.nesting >= DEPTH then
    return TOO_DEEP
  end
  self.nesting = self.nesting + 1
  self:compute (cell)
  self.nesting = self.nesting - 1
  return cell.value
end

---The formula cells, among `dirty`, that a formula reads.
---@param cell Sheet.Cell
---@param dirty table<Sheet.Cell, boolean>
---@return Sheet.Cell[]
local function deps_of (cell, dirty)
  local deps = {} ---@type Sheet.Cell[]
  local loops = false
  for _, a in ipairs (cell.areas or {}) do
    if small (a) then
      local cells = a.sheet.cells
      for r = a.r1, a.r2 --[[@as integer]] do
        for c = a.c1, a.c2 --[[@as integer]] do
          local d = cells[r * KEY + c]
          if d and dirty[d] then
            deps[#deps + 1] = d
            loops = loops or d == cell
          end
        end
      end
    else
      for col, set in pairs (a.sheet.watch.by_col) do
        if col >= a.c1 and col <= a.c2 then
          for d in pairs (set) do
            if dirty[d] and d.row >= a.r1 and d.row <= a.r2 then
              deps[#deps + 1] = d
              loops = loops or d == cell
            end
          end
        end
      end
    end
  end
  cell.loops = loops
  return deps
end

---Works out the formula cells in `list`, each after the cells it reads. Cells that read
---themselves, directly or through others, show #CYCLE!.
---@param list Sheet.Cell[]
---@param dirty table<Sheet.Cell, boolean>
---@param full boolean
function Book:run (list, dirty, full)
  self.evaluated = 0
  self.nesting = 0
  for _, cell in ipairs (list) do
    cell.pending = true
  end
  for _, cell in ipairs (list) do
    cell.deps = deps_of (cell, dirty)
  end
  local groups = groups_of (list)
  -- Loops get #CYCLE! first, so a formula that reaches one on demand sees it.
  for _, group in ipairs (groups) do
    if #group > 1 or group[1].loops then
      for _, cell in ipairs (group) do
        cell.value = CYCLE
        cell.pending = nil
      end
    end
  end
  for _, group in ipairs (groups) do
    local cell = group[1]
    if cell.pending then
      self:compute (cell)
    end
  end
  for _, cell in ipairs (list) do
    cell.deps = nil
  end
  self.last = { full = full, evaluated = self.evaluated, dirty = #list }
  self.stamp = self.stamp + 1
end

---Works out every formula in the book again, and builds the indexes from scratch.
function Book:recalc ()
  self.full = false
  self.stale = false
  self.edited = {}
  self.spill_moved = {}
  self.volatile = {}
  self.row_readers = {}
  self.rows_stale = false
  for _, sheet in ipairs (self.sheets) do
    sheet.watch = model.new_watch ()
  end
  local list = {} ---@type Sheet.Cell[]
  local dirty = {} ---@type table<Sheet.Cell, boolean>
  for _, sheet in ipairs (self.sheets) do
    for _, cell in pairs (sheet.cells) do
      if cell.formula then
        cell.spill, cell.spill_area = nil, nil
        self:watch (sheet, cell)
        list[#list + 1] = cell
        dirty[cell] = true
      end
    end
  end
  self:run (list, dirty, true)
  self:settle ()
end

---Works out again the formulas that read cells a block spilled into or left, until the blocks
---stop moving. A block that keeps moving stops after a few rounds.
function Book:settle ()
  local rounds = 0
  while #self.spill_moved > 0 and rounds < SPILL_ROUNDS do
    rounds = rounds + 1
    local last = self.last
    self:update ()
    self.last = {
      full = last.full,
      evaluated = last.evaluated + self.last.evaluated,
      dirty = last.dirty + self.last.dirty,
    }
  end
  self.spill_moved = {}
end

---Works out the formulas that read the cells edited since the last time, directly or
---through others, and the volatile formulas.
function Book:update ()
  local dirty = {} ---@type table<Sheet.Cell, boolean>
  local list = {} ---@type Sheet.Cell[]
  local queue = {} ---@type Sheet.Position[]
  ---@param cell Sheet.Cell
  local function mark (cell)
    if not dirty[cell] then
      dirty[cell] = true
      list[#list + 1] = cell
      local home = cell.home --[[@as Sheet.Sheet]]
      queue[#queue + 1] = { sheet = home, row = cell.row, col = cell.col }
      -- What reads the block a formula spilled is due along with it.
      local area = cell.spill_area
      if area then
        for r = area.r1, area.r2 do
          for c = area.c1, area.c2 do
            if r ~= cell.row or c ~= cell.col then
              queue[#queue + 1] = { sheet = home, row = r, col = c }
            end
          end
        end
      end
    end
  end
  local edited = self.edited
  local moved = self.spill_moved
  self.edited = {}
  self.spill_moved = {}
  self.stale = false
  for _, pos in ipairs (edited) do
    if self.live[pos.sheet] then
      local key = pos.row * KEY + pos.col
      local cell = pos.sheet.cells[key]
      if cell and cell.formula then
        mark (cell)
      else
        queue[#queue + 1] = pos
      end
      -- Typing into a block's cells stops it spilling, and clearing a cell may give a block
      -- that had no room the room it needs.
      local w = pos.sheet.watch
      local anchor = w.spills[key]
      if anchor and anchor ~= cell then
        mark (anchor)
      end
      for other, area in pairs (w.blocked) do
        if
          pos.row >= area.r1
          and pos.row <= area.r2
          and pos.col >= area.c1
          and pos.col <= area.c2
        then
          mark (other)
        end
      end
    end
  end
  for _, pos in ipairs (moved) do
    if self.live[pos.sheet] then
      queue[#queue + 1] = pos
    end
  end
  for cell in pairs (self.volatile) do
    mark (cell)
  end
  if self.rows_stale then
    self.rows_stale = false
    for cell in pairs (self.row_readers) do
      mark (cell)
    end
  end
  local i = 1
  while i <= #queue do
    local pos = queue[i]
    i = i + 1
    self:readers (pos.sheet, pos.row, pos.col, mark)
  end
  self:run (list, dirty, false)
end

---Brings every value up to date: all of them after a load or a change of shape, and only
---what an edit reaches otherwise. Reading a value calls this, so it rarely needs a call.
function Book:ensure ()
  if self.full then
    self:recalc ()
  elseif
    #self.edited > 0
    or #self.spill_moved > 0
    or self.stale
    or self.rows_stale
  then
    self:update ()
    self:settle ()
  end
end

---Asks for the volatile formulas, such as NOW and RAND, to be worked out again.
function Book:refresh ()
  self.stale = true
end

---Tells the book that rows were hidden or shown, by the user or by a filter, so SUBTOTAL and
---AGGREGATE are worked out again.
function Book:rows_changed ()
  self.rows_stale = true
end

---The value of a cell on the sheet at `index`, as the Excel writer asks for it.
---@param index integer
---@param row integer
---@param col integer
---@return Sheet.Value
function Book:value_at (index, row, col)
  local sheet = self.sheets[index]
  if not sheet then
    return nil
  end
  return sheet:value (row, col)
end

---------------------------------------------------------------------------------------------
-- Undo
---------------------------------------------------------------------------------------------

---Starts a batch. Every change until the matching `finish` becomes one undo step. Batches can
---nest, and only the outermost one counts. The first batch or change to name a sheet, a block
---to select or a label gives them to the step.
---@param opts? Sheet.BatchOptions
function Book:begin (opts)
  if self.depth == 0 then
    self.batch = { changes = {} }
    self.batch_cells = {}
    self.batch_props = {}
  end
  local batch = self.batch --[[@as Sheet.Step]]
  if opts then
    batch.sheet = batch.sheet or opts.sheet
    batch.select = batch.select or opts.select
    batch.label = batch.label or opts.label
  end
  self.depth = self.depth + 1
end

---Ends a batch, and keeps it as one undo step when it changed anything.
function Book:finish ()
  if self.depth == 0 then
    return
  end
  self.depth = self.depth - 1
  if self.depth > 0 then
    return
  end
  local step = self.batch
  self.batch, self.batch_cells, self.batch_props = nil, nil, nil
  if step and #step.changes > 0 then
    self.done[#self.done + 1] = step
    if #self.done > HISTORY then
      table.remove (self.done, 1)
    end
    self.undone = {}
    self.edits = self.edits + 1
  end
end

---Adds a change to the open step. A change of shape ends the merging of later cell changes
---into earlier ones, since a cell after it may be another cell.
---@param change Sheet.Change
function Book:log (change)
  self:begin ({ sheet = change.sheet })
  local batch = self.batch --[[@as Sheet.Step]]
  batch.changes[#batch.changes + 1] = change
  if change.kind == 'state' or change.kind == 'sheets' then
    self.batch_cells, self.batch_props = {}, {}
  end
  self:finish ()
end

---Records a cell change in the open step. A second change to the same cell in one step
---merges with the first.
---@param sheet Sheet.Sheet
---@param row integer
---@param col integer
---@param before Sheet.CellState
---@param after Sheet.CellState
function Book:log_cell (sheet, row, col, before, after)
  self:begin ({ sheet = sheet })
  local cells = self.batch_cells --[[@as table<Sheet.Sheet, table<integer, Sheet.Change>>]]
  local map = cells[sheet]
  if not map then
    map = {}
    cells[sheet] = map
  end
  local key = row * KEY + col
  local change = map[key]
  if change then
    change.after = after
  else
    change = {
      kind = 'cell',
      sheet = sheet,
      row = row,
      col = col,
      before = before,
      after = after,
    }
    map[key] = change
    local batch = self.batch --[[@as Sheet.Step]]
    batch.changes[#batch.changes + 1] = change
  end
  self:finish ()
end

---Records a change to a sheet's field, or to one entry of a map field, in the open step.
---@param sheet Sheet.Sheet
---@param field string
---@param key any
---@param before any
---@param after any
function Book:log_prop (sheet, field, key, before, after)
  self:begin ({ sheet = sheet })
  local props = self.batch_props --[[@as table<Sheet.Sheet, table<string, Sheet.Change>>]]
  local map = props[sheet]
  if not map then
    map = {}
    props[sheet] = map
  end
  local id = field .. '\0' .. tostring (key)
  local change = map[id]
  if change then
    change.after = after
  else
    change = {
      kind = 'prop',
      sheet = sheet,
      field = field,
      key = key,
      before = before,
      after = after,
    }
    map[id] = change
    local batch = self.batch --[[@as Sheet.Step]]
    batch.changes[#batch.changes + 1] = change
  end
  self:finish ()
end

---Plays one change backward or forward.
---@param change Sheet.Change
---@param back boolean
function Book:apply (change, back)
  local value = change.after
  if back then
    value = change.before
  end
  local kind = change.kind
  local sheet = change.sheet
  if kind == 'cell' and sheet then
    sheet:put (change.row --[[@as integer]], change.col --[[@as integer]], value)
  elseif kind == 'prop' and sheet then
    sheet:put_prop (change.field --[[@as string]], change.key, value)
  elseif kind == 'state' and sheet then
    sheet:put_state (value)
  elseif kind == 'sheets' then
    local active = change.active_after
    if back then
      active = change.active_before
    end
    self:put_sheets (value, active or 1)
  end
end

---Plays a whole step backward or forward, and says what the UI should show.
---@param step Sheet.Step
---@param back boolean
---@return Sheet.StepInfo
function Book:play (step, back)
  local changes = step.changes
  local from, to, dir = 1, #changes, 1
  if back then
    from, to, dir = #changes, 1, -1
  end
  for i = from, to, dir do
    self:apply (changes[i], back)
  end
  local index = step.sheet and self:index_of (step.sheet)
  if index then
    self.active = index
  else
    index = self.active
  end
  local shown = self.sheets[index]
  local rect = step.select ---@type Sheet.Rect?
  if not rect then
    for _, change in ipairs (changes) do
      if change.kind == 'cell' and change.sheet == shown then
        local r = change.row --[[@as integer]]
        local c = change.col --[[@as integer]]
        if rect then
          rect = {
            r1 = r < rect.r1 and r or rect.r1,
            c1 = c < rect.c1 and c or rect.c1,
            r2 = r > rect.r2 and r or rect.r2,
            c2 = c > rect.c2 and c or rect.c2,
          }
        else
          rect = { r1 = r, c1 = c, r2 = r, c2 = c }
        end
      end
    end
  end
  return { sheet = index, rect = rect, label = step.label }
end

---@return boolean
function Book:can_undo ()
  return #self.done > 0
end

---@return boolean
function Book:can_redo ()
  return #self.undone > 0
end

---The label of the step undo would take back, such as `Paste`, or nil.
---@return string?
function Book:undo_label ()
  local step = self.done[#self.done]
  return step and step.label
end

---@return string?
function Book:redo_label ()
  local step = self.undone[#self.undone]
  return step and step.label
end

---Takes back the last step. Makes its sheet active and returns what to show, or nil when
---there is nothing to undo.
---@return Sheet.StepInfo?
function Book:undo ()
  if self.depth > 0 then
    return nil
  end
  local step = table.remove (self.done)
  if not step then
    return nil
  end
  self.undone[#self.undone + 1] = step
  self.edits = self.edits + 1
  return self:play (step, true)
end

---Does the last undone step again. Makes its sheet active and returns what to show, or nil.
---@return Sheet.StepInfo?
function Book:redo ()
  if self.depth > 0 then
    return nil
  end
  local step = table.remove (self.undone)
  if not step then
    return nil
  end
  self.done[#self.done + 1] = step
  self.edits = self.edits + 1
  return self:play (step, false)
end

---------------------------------------------------------------------------------------------
-- The file
---------------------------------------------------------------------------------------------

---The book as plain data, the shape of a version 3 `.sheet.json` file.
---@param book Sheet.Book
---@return Sheet.BookData
function M.to_data (book)
  local sheets = {} ---@type Sheet.SheetData[]
  for i, sheet in ipairs (book.sheets) do
    sheets[i] = sheet:to_data ()
  end
  return { version = 3, active = book.active, sheets = sheets }
end

---A sheet's file data with its rules first rule first. Files before version 3 list them the
---other way round, last rule winning, so their rules turn round.
---@param item table
---@param data any
---@return table
local function rules_first (item, data)
  local version = type (data) == 'table' and tonumber (data.version) or nil
  if (version and version >= 3) or type (item.rules) ~= 'table' then
    return item
  end
  local copy = {} ---@type table<string, any>
  for k, v in pairs (item) do
    copy[k] = v
  end
  local turned = {} ---@type any[]
  local rules = item.rules --[[@as any[] ]]
  for i = #rules, 1, -1 do
    turned[#turned + 1] = rules[i]
  end
  copy.rules = turned
  return copy
end

---Makes a book from decoded file data. Version 1 files load as one sheet named `Sheet1`.
---Missing fields, maps and lists saved as `{}`, and values of the wrong type all load. The
---values are worked out before it returns.
---@param data any
---@param opts? Sheet.BookOptions
---@return Sheet.Book
function M.from_data (data, opts)
  local book = blank_book (opts)
  local list = {} ---@type any[]
  if type (data) == 'table' and type (data.sheets) == 'table' then
    for _, item in
      ipairs (data.sheets --[[@as any[] ]])
    do
      if type (item) == 'table' then
        list[#list + 1] = item
      end
    end
  elseif type (data) == 'table' then
    list[1] = data
  end
  local taken = {} ---@type table<string, boolean>
  for i, item in ipairs (list) do
    local name = 'Sheet' .. i
    if not name_shape (item.name) then
      name = item.name --[[@as string]]
    end
    local base = name ---@type string
    local n = 2
    while taken[string.lower (name)] do
      name = base .. ' (' .. n .. ')'
      n = n + 1
    end
    taken[string.lower (name)] = true
    local sheet =
      model.blank (book, name, opts and opts.rows, opts and opts.cols)
    book.sheets[#book.sheets + 1] = sheet
    sheet:load (rules_first (item, data))
  end
  if #book.sheets == 0 then
    book.sheets[1] =
      model.blank (book, 'Sheet1', opts and opts.rows, opts and opts.cols)
  end
  book:names_changed ()
  local active = type (data) == 'table' and tonumber (data.active) or 1
  book.active = math.max (1, math.min (math.floor (active or 1), #book.sheets))
  book:recalc ()
  for _, sheet in ipairs (book.sheets) do
    sheet:refilter ()
  end
  book.done, book.undone = {}, {}
  return book
end

local JSON_ESCAPES = {
  ['"'] = '\\"',
  ['\\'] = '\\\\',
  ['\n'] = '\\n',
  ['\r'] = '\\r',
  ['\t'] = '\\t',
}

---@param s string
---@return string
local function json_string (s)
  local body = string.gsub (s, '[%c"\\]', function (ch)
    return JSON_ESCAPES[ch] or string.format ('\\u%04x', string.byte (ch))
  end)
  return '"' .. body .. '"'
end

---A number as JSON, as short as it can be and still read back the same.
---@param n number
---@return string
local function json_number (n)
  if n ~= n or n == HUGE or n == -HUGE then
    return '0'
  end
  if n == math.floor (n) and math.abs (n) < 2 ^ 53 then
    return string.format ('%d', n)
  end
  for digits = 15, 16 do
    local s = string.format ('%.' .. digits .. 'g', n)
    if tonumber (s) == n then
      return s
    end
  end
  return string.format ('%.17g', n)
end

local STYLE_KEYS = model.STYLE_FIELDS
local RULE_KEYS = {
  'range',
  'type',
  'op',
  'value',
  'value2',
  'count',
  'percent',
  'formula',
  'style',
  'min_color',
  'mid_color',
  'max_color',
  'color',
  'stop',
}
local VALIDATION_KEYS = {
  'range',
  'type',
  'values',
  'op',
  'value',
  'value2',
  'integer',
  'message',
  'strict',
}
local CHART_KEYS = {
  'id',
  'type',
  'stacked',
  'range',
  'series_in',
  'headers',
  'title',
  'legend',
  'x_title',
  'y_title',
  'colors',
  'x',
  'y',
  'w',
  'h',
}
local FILTER_COLUMN_KEYS = { 'values', 'op', 'value', 'value2' }

---@type table<string, string[]>
local KEYS_OF = { style = STYLE_KEYS }

---A value as JSON on one line. Objects write the keys in `keys` in that order and skip the
---rest, so the file keeps a fixed shape.
---@param v any
---@param keys? string[]
---@return string
local function json_inline (v, keys)
  local t = type (v)
  if t == 'string' then
    return json_string (v)
  elseif t == 'number' then
    return json_number (v)
  elseif t == 'boolean' then
    return v and 'true' or 'false'
  elseif t ~= 'table' then
    return 'null'
  end
  if keys then
    local parts = {} ---@type string[]
    for _, k in ipairs (keys) do
      local item = v[k] ---@type any
      if item ~= nil then
        parts[#parts + 1] = json_string (k)
          .. ': '
          .. json_inline (item, KEYS_OF[k])
      end
    end
    if #parts == 0 then
      return '{}'
    end
    return '{ ' .. table.concat (parts, ', ') .. ' }'
  end
  local parts = {} ---@type string[]
  for _, item in
    ipairs (v --[[@as any[] ]])
  do
    parts[#parts + 1] = json_inline (item)
  end
  return '[' .. table.concat (parts, ', ') .. ']'
end

---Sorts map keys: cell addresses in reading order, column letters left to right, and row
---numbers from the top.
---@param map table<string, any>
---@return string[]
local function sorted_keys (map)
  local keys = {} ---@type string[]
  local order = {} ---@type table<string, integer>
  for k in pairs (map) do
    keys[#keys + 1] = k
    local row, col = formula.parse_address (k)
    if row and col then
      order[k] = row * KEY + col
    else
      order[k] = formula.col_number (k) or math.tointeger (tonumber (k)) or 0
    end
  end
  table.sort (keys, function (a, b)
    if order[a] ~= order[b] then
      return order[a] < order[b]
    end
    return a < b
  end)
  return keys
end

---Writes a map field with one entry per line.
---@param out string[]
---@param name string
---@param map table<string, any>
---@param keys? string[] The key order of each entry, when entries are objects.
local function write_map (out, name, map, keys)
  local list = sorted_keys (map)
  if #list == 0 then
    out[#out + 1] = '      ' .. json_string (name) .. ': {}'
    return
  end
  local lines = {} ---@type string[]
  for i, k in ipairs (list) do
    lines[i] = '        '
      .. json_string (k)
      .. ': '
      .. json_inline (map[k], keys)
  end
  out[#out + 1] = '      '
    .. json_string (name)
    .. ': {\n'
    .. table.concat (lines, ',\n')
    .. '\n      }'
end

---Writes a list of objects with one object per line.
---@param out string[]
---@param name string
---@param list table[]
---@param keys string[]
local function write_list (out, name, list, keys)
  local lines = {} ---@type string[]
  for i, item in ipairs (list) do
    lines[i] = '        ' .. json_inline (item, keys)
  end
  out[#out + 1] = '      '
    .. json_string (name)
    .. ': [\n'
    .. table.concat (lines, ',\n')
    .. '\n      ]'
end

---@param data Sheet.SheetData
---@return string
local function sheet_json (data)
  local out = {} ---@type string[]
  out[#out + 1] = '      "name": ' .. json_string (data.name)
  out[#out + 1] = '      "rows": ' .. json_number (data.rows or 0)
  out[#out + 1] = '      "cols": ' .. json_number (data.cols or 0)
  if data.widths then
    write_map (out, 'widths', data.widths)
  end
  if data.heights then
    write_map (out, 'heights', data.heights)
  end
  if data.hidden_rows then
    out[#out + 1] = '      "hidden_rows": ' .. json_inline (data.hidden_rows)
  end
  if data.hidden_cols then
    out[#out + 1] = '      "hidden_cols": ' .. json_inline (data.hidden_cols)
  end
  if data.freeze then
    out[#out + 1] = '      "freeze": '
      .. json_inline (data.freeze, { 'rows', 'cols' })
  end
  write_map (out, 'cells', data.cells or {})
  if data.styles then
    write_map (out, 'styles', data.styles, STYLE_KEYS)
  end
  if data.col_styles then
    write_map (out, 'col_styles', data.col_styles, STYLE_KEYS)
  end
  if data.row_styles then
    write_map (out, 'row_styles', data.row_styles, STYLE_KEYS)
  end
  if data.merges then
    out[#out + 1] = '      "merges": ' .. json_inline (data.merges)
  end
  if data.notes then
    write_map (out, 'notes', data.notes)
  end
  local filter = data.filter
  if filter then
    local columns = {} ---@type string[]
    for _, k in ipairs (sorted_keys (filter.columns or {})) do
      columns[#columns + 1] = json_string (k)
        .. ': '
        .. json_inline ((filter.columns or {})[k], FILTER_COLUMN_KEYS)
    end
    local text = '{ "range": ' .. json_string (filter.range)
    if #columns > 0 then
      text = text .. ', "columns": { ' .. table.concat (columns, ', ') .. ' }'
    end
    out[#out + 1] = '      "filter": ' .. text .. ' }'
  end
  if data.rules then
    write_list (out, 'rules', data.rules, RULE_KEYS)
  end
  if data.validation then
    write_list (out, 'validation', data.validation, VALIDATION_KEYS)
  end
  if data.charts then
    write_list (out, 'charts', data.charts, CHART_KEYS)
  end
  return '    {\n' .. table.concat (out, ',\n') .. '\n    }'
end

-- Names Windows keeps for devices, whatever follows them after a dot.
local DEVICES = { con = true, prn = true, aux = true, nul = true }
for i = 0, 9 do
  DEVICES['com' .. i] = true
  DEVICES['lpt' .. i] = true
end
for _, digit in ipairs ({ '\194\185', '\194\178', '\194\179' }) do
  DEVICES['com' .. digit] = true
  DEVICES['lpt' .. digit] = true
end

---Why a workbook name cannot be a file name, or nil when it can. A name cannot start with a
---dot, hold `\ / : * ? " < > |` or a control character, or be a name Windows keeps for a
---device, such as `CON` or `NUL`.
---@param name string
---@return string?
function M.file_name_problem (name)
  if name == '' then
    return 'Type a name.'
  end
  if
    string.find (name, '[\\/:%*%?"<>|%c]') or string.sub (name, 1, 1) == '.'
  then
    return 'A name cannot start with a dot or hold \\ / : * ? " < > |'
  end
  local stem = string.match (string.lower (name), '^([^%.]*)') or ''
  stem = string.match (stem, '^(.-)[%s]*$')
  if DEVICES[stem] then
    return 'Windows keeps the name ' .. string.upper (stem) .. ' for a device.'
  end
  return nil
end

---A workbook name made safe for a file, from any text.
---@param text string
---@return string
function M.safe_file_name (text)
  local base = string.gsub (text, '[\\/:%*%?"<>|%c]', '-')
  base = string.match (base, '^%s*(.-)%s*$')
  if base == '' or string.sub (base, 1, 1) == '.' then
    return 'Imported'
  end
  if M.file_name_problem (base) then
    return base .. ' 1'
  end
  return base
end

---Writes a book as the text of its `.sheet.json` file: fixed key order, one cell per line in
---reading order, so a small change makes a small difference between saves.
---@param book Sheet.Book
---@return string
function M.encode (book)
  local data = M.to_data (book)
  local sheets = {} ---@type string[]
  for i, sheet in ipairs (data.sheets) do
    sheets[i] = sheet_json (sheet)
  end
  return table.concat ({
    '{',
    '  "version": 3,',
    '  "active": ' .. json_number (data.active or 1) .. ',',
    '  "sheets": [',
    table.concat (sheets, ',\n'),
    '  ]',
    '}',
    '',
  }, '\n')
end

---------------------------------------------------------------------------------------------
-- Reading JSON
---------------------------------------------------------------------------------------------

local JSON_DEPTH = 100
local UNESCAPE = {
  ['"'] = '"',
  ['\\'] = '\\',
  ['/'] = '/',
  b = '\b',
  f = '\f',
  n = '\n',
  r = '\r',
  t = '\t',
}

-- Marks the errors the reader raises, apart from any other error.
local JSON_FAIL = 'json: '

---@class Sheet.JsonReader
---@field text string
---@field pos integer

---@param r Sheet.JsonReader
---@param message string
local function json_fail (r, message)
  error (JSON_FAIL .. message .. ' at byte ' .. r.pos .. '.', 0)
end

---@param r Sheet.JsonReader
local function json_space (r)
  local _, e = string.find (r.text, '^[ \t\r\n]*', r.pos)
  r.pos = (e or r.pos - 1) + 1
end

---@param r Sheet.JsonReader
---@return string
local function json_read_string (r)
  local text = r.text
  local parts = {} ---@type string[]
  local pos = r.pos + 1
  while true do
    local s, e = string.find (text, '["\\]', pos)
    if not s then
      r.pos = #text
      json_fail (r, 'A text has no closing quote')
    end
    ---@cast s integer
    ---@cast e integer
    parts[#parts + 1] = string.sub (text, pos, s - 1)
    if string.sub (text, s, s) == '"' then
      r.pos = e + 1
      return table.concat (parts)
    end
    local ch = string.sub (text, s + 1, s + 1)
    if ch == 'u' then
      local hex = string.match (text, '^%x%x%x%x', s + 2)
      if not hex then
        r.pos = s
        json_fail (r, 'A \\u escape needs four hex digits')
      end
      local code = tonumber (hex, 16) --[[@as integer]]
      pos = s + 6
      if code >= 0xD800 and code <= 0xDBFF then
        local low = string.match (text, '^\\u(%x%x%x%x)', pos)
        local lc = low and tonumber (low, 16)
        if lc and lc >= 0xDC00 and lc <= 0xDFFF then
          code = 0x10000 + (code - 0xD800) * 0x400 + (lc - 0xDC00)
          pos = pos + 6
        end
      end
      parts[#parts + 1] = utf8.char (code)
    else
      local out = UNESCAPE[ch]
      if not out then
        r.pos = s
        json_fail (r, 'An escape in a text is not valid')
      end
      parts[#parts + 1] = out
      pos = s + 2
    end
  end
end

---@param r Sheet.JsonReader
---@param depth integer
---@return any
local function json_value (r, depth)
  if depth > JSON_DEPTH then
    json_fail (r, 'The data nests too deeply')
  end
  json_space (r)
  local text = r.text
  local ch = string.sub (text, r.pos, r.pos)
  if ch == '{' then
    local out = {} ---@type table<string, any>
    r.pos = r.pos + 1
    json_space (r)
    if string.sub (text, r.pos, r.pos) == '}' then
      r.pos = r.pos + 1
      return out
    end
    while true do
      json_space (r)
      if string.sub (text, r.pos, r.pos) ~= '"' then
        json_fail (r, 'A key must be a text in quotes')
      end
      local key = json_read_string (r)
      json_space (r)
      if string.sub (text, r.pos, r.pos) ~= ':' then
        json_fail (r, 'A ":" is missing after a key')
      end
      r.pos = r.pos + 1
      out[key] = json_value (r, depth + 1)
      json_space (r)
      local sep = string.sub (text, r.pos, r.pos)
      r.pos = r.pos + 1
      if sep == '}' then
        return out
      elseif sep ~= ',' then
        r.pos = r.pos - 1
        json_fail (r, 'A "," or "}" is missing')
      end
    end
  elseif ch == '[' then
    local out = {} ---@type any[]
    r.pos = r.pos + 1
    json_space (r)
    if string.sub (text, r.pos, r.pos) == ']' then
      r.pos = r.pos + 1
      return out
    end
    while true do
      out[#out + 1] = json_value (r, depth + 1)
      json_space (r)
      local sep = string.sub (text, r.pos, r.pos)
      r.pos = r.pos + 1
      if sep == ']' then
        return out
      elseif sep ~= ',' then
        r.pos = r.pos - 1
        json_fail (r, 'A "," or "]" is missing')
      end
    end
  elseif ch == '"' then
    return json_read_string (r)
  end
  for word, value in pairs ({ ['true'] = true, ['false'] = false }) do
    if string.sub (text, r.pos, r.pos + #word - 1) == word then
      r.pos = r.pos + #word
      return value
    end
  end
  if string.sub (text, r.pos, r.pos + 3) == 'null' then
    r.pos = r.pos + 4
    return nil
  end
  local num = string.match (text, '^-?%d+%.?%d*[eE]?[+-]?%d*', r.pos)
  local n = num and tonumber (num)
  if not n then
    json_fail (r, 'A value is not valid JSON')
  end
  r.pos = r.pos + #num
  return n
end

---Reads JSON text into Lua values. Returns nil and a message when the text is not JSON.
---@param text string
---@return any
---@return string? problem
function M.parse_json (text)
  if type (text) ~= 'string' then
    return nil, 'There is no text to read.'
  end
  ---@type Sheet.JsonReader
  local r = { text = text, pos = 1 }
  local ok, result = pcall (json_value, r, 0)
  if not ok then
    local text_error = tostring (result)
    if string.sub (text_error, 1, #JSON_FAIL) == JSON_FAIL then
      return nil, string.sub (text_error, #JSON_FAIL + 1)
    end
    return nil, text_error
  end
  json_space (r)
  if r.pos <= #text then
    return nil, 'There is more text after the data at byte ' .. r.pos .. '.'
  end
  return result, nil
end

---Reads the text of a `.sheet.json` file into a book. Returns nil and a message when the text
---is not JSON.
---@param text string
---@param opts? Sheet.BookOptions
---@return Sheet.Book?
---@return string? problem
function M.decode (text, opts)
  local data, problem = M.parse_json (text)
  if problem then
    return nil, 'The file is not valid JSON. ' .. problem
  end
  if type (data) ~= 'table' then
    return nil, 'The file holds no workbook.'
  end
  return M.from_data (data, opts), nil
end

---------------------------------------------------------------------------------------------
-- The example
---------------------------------------------------------------------------------------------

local MONEY = '$#,##0.00'
local TITLE = { bold = true, size = 20 }
local HEADER = {
  bold = true,
  fill = '#e8eefc',
  border_bottom = 'medium',
  border_color = '#3b5bdb',
}
local TOTAL = { bold = true, border_top = 'thin' }

---The rows of the budget sheet, by row number. Columns D to F of rows 5 to 11 are added below,
---since each row has the same formulas.
---@type table<integer, string[]>
local BUDGET = {
  [1] = { 'Monthly budget' },
  [2] = { 'Change a number in column B or C, and every total follows.' },
  [4] = { 'Item', 'Planned', 'Actual', 'Difference', 'Share', 'Status' },
  [5] = { 'Rent', '1200', '1200' },
  [6] = { 'Groceries', '450', '482.35' },
  [7] = { 'Utilities', '160', '141.2' },
  [8] = { 'Transport', '120', '96.5' },
  [9] = { 'Phone and internet', '75', '75' },
  [10] = { 'Eating out', '150', '212.4' },
  [11] = { 'Total', '=SUM(B5:B10)', '=SUM(C5:C10)' },
  [13] = { 'Average spent', '', '=ROUND(AVERAGE(C5:C10), 2)' },
  [14] = {
    'Biggest item',
    '',
    '=INDEX(A5:A10, MATCH(MAX(C5:C10), C5:C10, 0))',
  },
  [15] = { 'Items over plan', '', '=COUNTIF(F5:F10, "Over")' },
  [17] = { 'Income', '', '=Income!D11' },
  [18] = { 'Savings goal', '', '=C17*10%' },
  [19] = { 'Left over', '', '=C17-C11' },
  [20] = {
    '=IF(C19>=C18, "On track: "&TEXT(C19/C17, "0%")&" of income is left over.", "Short of the savings goal by "&TEXT(C18-C19, "$#,##0.00")&".")',
  },
}

---The income sheet: six months, each a date shown as its month.
---@type table<integer, string[]>
local INCOME = {
  [1] = { 'Monthly income' },
  [3] = { 'Month', 'Salary', 'Other', 'Total' },
  [4] = { '46113', '3000', '120' },
  [5] = { '46143', '3000', '0' },
  [6] = { '46174', '3000', '85' },
  [7] = { '46204', '3150', '200' },
  [8] = { '46235', '3150', '280' },
  [9] = { '46266', '3150', '65' },
  [11] = { 'Average', '', '', '=AVERAGE(D4:D9)' },
}

---@param rows table<integer, string[]>
---@return table<string, string>
local function cells_of (rows)
  local out = {} ---@type table<string, string>
  for row, line in pairs (rows) do
    for col, text in ipairs (line) do
      if text ~= '' then
        out[formula.address (row, col)] = text
      end
    end
  end
  return out
end

---The workbook written on first start: a monthly budget that shows off formulas, formats, a
---chart, a conditional rule and a note, and an income sheet the budget reads.
---@param opts? Sheet.BookOptions
---@return Sheet.Book
function M.example (opts)
  local budget = cells_of (BUDGET)
  for row = 5, 11 do
    local r = string.format ('%d', row)
    budget['D' .. r] = '=C' .. r .. '-B' .. r
    budget['E' .. r] = '=C' .. r .. '/C$11'
    budget['F' .. r] = row == 11
        and '=IF(C11>B11, "Over budget", "Within budget")'
      or ('=IF(C' .. r .. '>B' .. r .. ', "Over", "OK")')
  end
  local styles = { A1 = TITLE } ---@type table<string, Sheet.Style>
  for col = 1, 6 do
    styles[formula.address (4, col)] = HEADER
    styles[formula.address (11, col)] = TOTAL
  end
  for row = 5, 11 do
    styles['E' .. row] = row == 11
        and { bold = true, border_top = 'thin', format = '0.0%' }
      or { format = '0.0%' }
  end
  for _, addr in ipairs ({ 'C13', 'C17', 'C18', 'C19' }) do
    styles[addr] = { format = MONEY }
  end
  -- A count in the money column cancels the column's format.
  styles.C15 = { format = 'General' }
  styles.A20 = { italic = true }
  local income = cells_of (INCOME)
  local income_styles = { A1 = TITLE, D11 = { bold = true, format = MONEY } } ---@type table<string, Sheet.Style>
  for col = 1, 4 do
    income_styles[formula.address (3, col)] = HEADER
  end
  for row = 4, 9 do
    income['D' .. row] = '=B' .. row .. '+C' .. row
    income_styles['A' .. row] = { format = 'mmmm yyyy', align = 'left' }
  end
  ---@type Sheet.BookData
  local data = {
    version = 3,
    active = 1,
    sheets = {
      {
        name = 'Budget',
        widths = { A = 170, B = 110, C = 110, D = 110, F = 120 },
        freeze = { rows = 4 },
        cells = budget,
        styles = styles,
        col_styles = {
          B = { format = MONEY },
          C = { format = MONEY },
          D = { format = MONEY },
        },
        notes = { B5 = 'Rent went up in March.' },
        rules = {
          {
            range = 'D5:D10',
            type = 'compare',
            op = '>',
            value = '0',
            style = { color = '#c62828', bold = true },
          },
        },
        charts = {
          {
            id = 'c1',
            type = 'column',
            range = 'A4:C10',
            title = 'Planned and actual',
            legend = 'bottom',
            x = 720,
            y = 100,
            w = 480,
            h = 300,
          },
        },
      },
      {
        name = 'Income',
        widths = { A = 140, B = 110, C = 110, D = 110 },
        freeze = { rows = 3 },
        cells = income,
        styles = income_styles,
        col_styles = {
          B = { format = MONEY },
          C = { format = MONEY },
          D = { format = MONEY },
        },
      },
    },
  }
  return M.from_data (data, opts)
end

return M
