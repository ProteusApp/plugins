-- sheet_model: one sheet of a workbook. It keeps each cell's text and style, the row and column
-- styles, sizes, hidden rows and columns, merged blocks, notes, frozen panes, and the filter,
-- rules, validation and charts as data. The workbook in sheet_book owns the undo history and
-- works the values out, so every change here goes through the sheet's book. The module draws
-- nothing and calls no host function.
--
-- A style is a shared table that never changes once made. Changing a cell's style swaps its
-- table for another, so equal styles can be compared with `==`.

local format = require ('sheet_format') --[[@as Sheet.FormatModule]]
local formula = require ('sheet_formula') --[[@as Sheet.FormulaModule]]
local style_mod = require ('sheet_model_style') --[[@as Sheet.ModelStyleModule]]

---A cell with text or a style of its own. Empty cells have no entry at all.
---@class Sheet.Cell
---@field row integer
---@field col integer
---@field text string What the user typed, or the number it stands for.
---@field style? Sheet.Style The cell's own style, laid over its row and column styles.
---@field bold? boolean The cell's own bold, kept for callers that know only bold.
---@field formula boolean True when the text starts with "=".
---@field value Sheet.Value The typed value, or the result of the formula after a recalculation.
---@field ast? Sheet.Node The parsed formula, or nil when it does not parse.
---@field home? Sheet.Sheet The sheet of a formula cell, set when the book watches it.
---@field areas? Sheet.WatchArea[] The blocks a formula reads, with their sheets found.
---@field volatile? boolean
---@field pending? boolean True while the value waits to be worked out.
---@field busy? boolean True while the value is being worked out.
---@field deps? Sheet.Cell[]
---@field loops? boolean True when the formula reads its own cell.
---@field spill? Sheet.Array The block of values a formula gives, which the cells around it show.
---@field spill_area? Sheet.Rect The cells the block covers, the formula's own cell first.

---The text and style of one cell, as undo keeps them.
---@class Sheet.CellState
---@field text string
---@field style? Sheet.Style
---@field bold? boolean When set and `style` is nil, only the cell's bold changes.

---Style fields to change over a block. A field set to `false` goes back to the default.
---@class Sheet.StylePatch
---@field bold? boolean
---@field italic? boolean
---@field underline? boolean
---@field strike? boolean
---@field size? number|false
---@field color? string|false
---@field fill? string|false
---@field align? 'left'|'center'|'right'|'general'|false
---@field valign? 'top'|'middle'|'bottom'|false
---@field wrap? boolean
---@field format? string|false
---@field border_top? string|false
---@field border_right? string|false
---@field border_bottom? string|false
---@field border_left? string|false
---@field border_color? string|false

---@alias Sheet.BorderPreset 'all'|'outer'|'inner'|'top'|'bottom'|'left'|'right'|'horizontal'|'vertical'|'none'

---A filter as the sheet keeps it: the block with its header row first, each column's test,
---and the rows the tests hide.
---@class Sheet.LiveFilter
---@field rect Sheet.Rect
---@field columns table<integer, Sheet.FilterColumn>
---@field hidden table<integer, boolean>

---What the rows or columns an insert or a delete moves past hold besides cells: the lists a
---sheet keeps and its size. Undo keeps them before and after.
---@class Sheet.SheetShape
---@field merges Sheet.Rect[]
---@field filter? Sheet.LiveFilter
---@field rules Sheet.Rule[]
---@field validation Sheet.Validation[]
---@field charts Sheet.ChartSpec[]
---@field rows integer
---@field cols integer
---@field freeze_rows integer
---@field freeze_cols integer

---What deleted rows or columns held, by their places before the delete, so undo puts it back.
---@class Sheet.Band
---@field cells table<integer, Sheet.CellState>
---@field notes table<integer, string>
---@field links table<integer, string>
---@field styles table<integer, Sheet.Style> Row or column styles.
---@field sizes table<integer, number> Heights or widths.
---@field hidden table<integer, boolean>

---An insert or a delete, as undo keeps it: the move itself, the formulas on the sheet whose
---text it changed, and what the deleted rows or columns held. It holds only what the move
---changes, never a copy of the whole sheet.
---@class Sheet.Shift
---@field axis 'row'|'col'
---@field at integer
---@field count integer Positive inserts before `at`, negative deletes from `at` on.
---@field texts table<integer, string> Formula texts after the move, by their new places.
---@field old_texts table<integer, string> The same formulas' texts before, by their old places.
---@field band? Sheet.Band

---Cells taken by a copy or a cut.
---@class Sheet.Clip
---@field texts string[][] Rows of cell text.
---@field bold? boolean[][]
---@field styles? Sheet.Style[][] The full style of each cell, for pasting formats.
---@field patches? Sheet.StylePatch[][] Changes to each cell's style, for HTML from another program.
---@field literals? string[][] Each value as text that types back to it, for pasting values.
---@field merges? Sheet.Rect[] Merged blocks, counting rows and columns from 1 in the clip.
---@field notes? table<integer, string> Notes by `i * KEY + j` in the clip.
---@field links? table<integer, string> Links by `i * KEY + j` in the clip.
---@field row? integer The top row they came from, so pasted formulas can move.
---@field col? integer
---@field sheet? Sheet.Sheet The sheet they came from.
---@field cut? boolean A cut moves the cells, so pasting empties the source.
---@field typed? boolean True for text from outside, which pastes as if typed.
---@field tsv? string The values as tab-separated text, as the system clipboard gets them.

---How a paste works. `only` pastes one part: the values as plain values, the formulas and
---text without styles, or the styles without text. `transpose` turns rows into columns.
---@class Sheet.PasteOptions
---@field only? 'values'|'formulas'|'formats'
---@field transpose? boolean

---Where rows and columns sit in pixels. A hidden row or column takes no room.
---@class Sheet.Layout
---@field tops number[] `tops[r]` is the top of row r, from 0. `tops[rows + 1]` is the total height.
---@field lefts number[] `lefts[c]` is the left edge of column c, from 0. `lefts[cols + 1]` is the total width.
---@field stamp integer

---@class Sheet.Stats
---@field sum number
---@field count integer How many numbers.
---@field average? number

---@class Sheet.Options: Sheet.BookOptions

---@class Sheet.Sheet
---@field __index Sheet.Sheet
---@field book Sheet.Book
---@field name string
---@field rows integer
---@field cols integer
---@field cells table<integer, Sheet.Cell>
---@field row_styles table<integer, Sheet.Style>
---@field col_styles table<integer, Sheet.Style>
---@field widths table<integer, number> Column widths that differ from the default.
---@field heights table<integer, number> Row heights that differ from the default.
---@field hidden_rows table<integer, boolean> Rows the user hid.
---@field hidden_cols table<integer, boolean>
---@field notes table<integer, string> Notes by `row * KEY + col`.
---@field links table<integer, string> Links by `row * KEY + col`: a web or mail address, or a place in the book after `#`, such as `#Sheet2!A1`.
---@field merges Sheet.Rect[]
---@field freeze_rows integer
---@field freeze_cols integer
---@field filter? Sheet.LiveFilter
---@field rules Sheet.Rule[]
---@field validation Sheet.Validation[]
---@field charts Sheet.ChartSpec[]
---@field watch Sheet.Watch
---@field ctx? Sheet.Context
---@field merge_index? table<integer, Sheet.Rect>
---@field merge_list? Sheet.Rect[] The list the merge index was built from.
---@field layout_cache? Sheet.Layout
---@field touched table<integer, boolean>|true Cells written since the grid last asked, by key, or true when anything may have changed.
---@field tall? Sheet.TallRows The rows grown for their text, kept by the grid's drawing.
local Sheet = {}
Sheet.__index = Sheet

---@class Sheet.ModelModule
---@field KEY integer
---@field DEFAULT_WIDTH integer
---@field DEFAULT_HEIGHT integer
---@field DEFAULT_ROWS integer
---@field DEFAULT_COLS integer
---@field STYLE_FIELDS string[]
---@field RESET table<string, any>
---@field col_name fun(n: integer): string
---@field col_number fun(letters: string): integer?
---@field address fun(row: integer, col: integer): string
---@field parse_address fun(text: string): integer?, integer?
local M = {}

-- Row * KEY + column names one cell. No sheet has this many columns.
local KEY = 32768
local DEFAULT_ROWS = 100
local DEFAULT_COLS = 26
local MIN_WIDTH = 24
local MAX_WIDTH = 1200
local MIN_HEIGHT = 12
local MAX_HEIGHT = 600
-- A block bigger than this walks the cells that exist rather than every address in it.
local WALK = 4096

M.KEY = KEY
M.DEFAULT_WIDTH = 100
M.DEFAULT_HEIGHT = 24
M.DEFAULT_ROWS = DEFAULT_ROWS
M.DEFAULT_COLS = DEFAULT_COLS
M.col_name = formula.col_name
M.col_number = formula.col_number
M.address = formula.address
M.parse_address = formula.parse_address

---sheet_book requires this module, so this one finds it only when a function runs.
---@return Sheet.BookModule
local function books ()
  local mod = require ('sheet_book') --[[@as Sheet.BookModule]]
  return mod
end

---@return Sheet.Watch
function M.new_watch ()
  return {
    points = {},
    cols = {},
    rows = {},
    big = {},
    by_col = {},
    spills = {},
    blocked = {},
  }
end

---------------------------------------------------------------------------------------------
-- Blocks
---------------------------------------------------------------------------------------------

---A block with its corners in order.
---@param rect Sheet.Rect
---@return Sheet.Rect
local function tidy (rect)
  return {
    r1 = math.min (rect.r1, rect.r2),
    c1 = math.min (rect.c1, rect.c2),
    r2 = math.max (rect.r1, rect.r2),
    c2 = math.max (rect.c1, rect.c2),
  }
end
M.tidy = tidy

---True when two blocks share a cell.
---@param a Sheet.Rect
---@param b Sheet.Rect
---@return boolean
function M.overlaps (a, b)
  return a.r1 <= b.r2 and b.r1 <= a.r2 and a.c1 <= b.c2 and b.c1 <= a.c2
end

---True when block `a` holds all of block `b`.
---@param a Sheet.Rect
---@param b Sheet.Rect
---@return boolean
function M.contains (a, b)
  return a.r1 <= b.r1 and a.r2 >= b.r2 and a.c1 <= b.c1 and a.c2 >= b.c2
end

---Where a row or column goes after `count` are inserted before `at`, or deleted from `at` on
---when `count` is negative. Nil when it was deleted.
---@param pos integer
---@param at integer
---@param count integer
---@return integer?
local function moved_to (pos, at, count)
  if count > 0 then
    return pos >= at and pos + count or pos
  end
  if pos < at then
    return pos
  end
  if pos <= at - count - 1 then
    return nil
  end
  return pos + count
end

---A block after rows or columns change, as references change: it moves, grows around an
---insert inside it, shrinks when part of it is deleted, and is nil when all of it is.
---@param rect Sheet.Rect
---@param axis 'row'|'col'
---@param at integer
---@param count integer
---@return Sheet.Rect?
function M.adjust_rect (rect, axis, at, count)
  local lo, hi = rect.c1, rect.c2
  if axis == 'row' then
    lo, hi = rect.r1, rect.r2
  end
  if count > 0 then
    if lo >= at then
      lo = lo + count
    end
    if hi >= at then
      hi = hi + count
    end
  else
    local n = -count
    local last = at + n - 1
    if lo >= at and hi <= last then
      return nil
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
  if axis == 'row' then
    return { r1 = lo, c1 = rect.c1, r2 = hi, c2 = rect.c2 }
  end
  return { r1 = rect.r1, c1 = lo, r2 = rect.r2, c2 = hi }
end

---Reads `B2` or `B2:D9` into a block.
---@param text string
---@return Sheet.Rect?
function M.parse_range (text)
  if type (text) ~= 'string' then
    return nil
  end
  local a, b = string.match (text, '^%s*([%$%w]+)%s*:%s*([%$%w]+)%s*$')
  if a then
    local r1, c1 = M.parse_address (a)
    local r2, c2 = M.parse_address (b)
    if r1 and c1 and r2 and c2 then
      return tidy ({ r1 = r1, c1 = c1, r2 = r2, c2 = c2 })
    end
    return nil
  end
  local row, col = M.parse_address (text)
  if row and col then
    return { r1 = row, c1 = col, r2 = row, c2 = col }
  end
  return nil
end

---Reads a reference such as `B2`, `B2:D9`, `Data!A1` or `'Q1 sales'!A1:B9`, as the name box
---takes one. Returns the block and the sheet name as written, which is nil for no sheet.
---@param text string
---@return Sheet.Rect?
---@return string? sheet
function M.parse_ref (text)
  if type (text) ~= 'string' then
    return nil, nil
  end
  local src = string.match (text, '^%s*(.-)%s*$')
  local spans = formula.ref_spans ('=' .. src)
  local span = spans[1]
  if #spans ~= 1 or span.from ~= 2 or span.to ~= #src + 1 then
    return nil, nil
  end
  local a = span.area
  if not a.r1 or not a.c1 or not a.r2 or not a.c2 then
    return nil, nil
  end
  return tidy ({ r1 = a.r1, c1 = a.c1, r2 = a.r2, c2 = a.c2 }), a.sheet
end

---Shows a block as `B2`, or `B2:D9`.
---@param rect Sheet.Rect
---@return string
function M.range_name (rect)
  local r = tidy (rect)
  local first = M.address (r.r1, r.c1)
  if r.r1 == r.r2 and r.c1 == r.c2 then
    return first
  end
  return first .. ':' .. M.address (r.r2, r.c2)
end

---A range text after rows or columns change, or nil when its cells were all deleted. Text that
---is not a range stays as it is.
---@param text string
---@param axis 'row'|'col'
---@param at integer
---@param count integer
---@return string?
local function adjust_range (text, axis, at, count)
  local rect = M.parse_range (text)
  if not rect then
    return text
  end
  local out = M.adjust_rect (rect, axis, at, count)
  return out and M.range_name (out)
end

---------------------------------------------------------------------------------------------
-- Styles
---------------------------------------------------------------------------------------------

-- sheet_model_style makes, layers and patches styles, and the module offers its functions.
M.STYLE_FIELDS = style_mod.STYLE_FIELDS
M.RESET = style_mod.RESET
M.is_default = style_mod.is_default
M.intern = style_mod.intern
M.copy_style = style_mod.copy_style
M.layer = style_mod.layer
M.EMPTY = style_mod.EMPTY
M.clean = style_mod.clean
M.cell_patch = style_mod.cell_patch

local SIDES, is_default, intern, layer =
  style_mod.SIDES, style_mod.is_default, style_mod.intern, style_mod.layer
local clean, cell_patch, fields_of =
  style_mod.clean, style_mod.cell_patch, style_mod.fields_of
local patched, strip, full_patch, patch_fields =
  style_mod.patched,
  style_mod.strip,
  style_mod.full_patch,
  style_mod.patch_fields

---The own style a cell needs to show the style `full`, given its row and column styles. Copy,
---fill and sort use it, so a cell shows the style it had where it came from.
---@param row integer
---@param col integer
---@param full Sheet.Style
---@return Sheet.Style?
function Sheet:own_for (row, col, full)
  return cell_patch (nil, full_patch (full), self:inherited (row, col))
end

---------------------------------------------------------------------------------------------
-- Cells
---------------------------------------------------------------------------------------------

---@type table<string, Sheet.Node|false>
local parsed = setmetatable ({}, { __mode = 'v' })

---@param text string
---@return Sheet.Node?
local function parse (text)
  local ast = parsed[text]
  if ast == nil then
    ast = formula.parse (text) or false
    parsed[text] = ast
  end
  return ast or nil
end

---A number as cell text, as short as it can be and still read back the same.
---@param n number
---@return string
function M.number_text (n)
  if n ~= n or n == math.huge or n == -math.huge then
    return '#NUM!'
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

---The value of text typed into a cell. A leading ' keeps the rest as text.
---@param text string
---@param clock fun(): number
---@return Sheet.Value
local function literal (text, clock)
  if text == '' then
    return nil
  end
  -- Plain numbers skip the parser, since most cells hold them.
  if string.match (text, '^%-?%d+%.?%d*$') then
    return (tonumber (text) or 0) + 0.0
  end
  return (format.parse_input (text, clock))
end

---@param row integer
---@param col integer
---@param text string
---@param style? Sheet.Style
---@param clock fun(): number
---@return Sheet.Cell
local function make_cell (row, col, text, style, clock)
  ---@type Sheet.Cell
  local cell = {
    row = row,
    col = col,
    text = text,
    style = style,
    bold = style and style.bold == true or nil,
    formula = false,
  }
  if formula.is_formula (text) then
    cell.formula = true
    cell.ast = parse (text)
  else
    cell.value = literal (text, clock)
  end
  return cell
end

---Makes an empty sheet in a book, without adding it to the book's list. sheet_book calls this.
---@param book Sheet.Book
---@param name string
---@param rows? integer
---@param cols? integer
---@return Sheet.Sheet
function M.blank (book, name, rows, cols)
  local self = setmetatable ({}, Sheet) --[[@as Sheet.Sheet]]
  self.book = book
  self.name = name
  self.rows = math.max (1, math.floor (rows or DEFAULT_ROWS))
  self.cols = math.max (1, math.floor (cols or DEFAULT_COLS))
  self.cells = {}
  self.row_styles = {}
  self.col_styles = {}
  self.widths = {}
  self.heights = {}
  self.hidden_rows = {}
  self.hidden_cols = {}
  self.notes = {}
  self.links = {}
  self.merges = {}
  self.freeze_rows = 0
  self.freeze_cols = 0
  self.rules = {}
  self.validation = {}
  self.charts = {}
  self.watch = M.new_watch ()
  self.touched = true
  return self
end

---Makes an empty sheet, alone in a new book.
---@param opts? Sheet.Options
---@return Sheet.Sheet
function M.new (opts)
  return books ().new (opts):active_sheet ()
end

---------------------------------------------------------------------------------------------
-- Reading cells
---------------------------------------------------------------------------------------------

---@param row integer
---@param col integer
---@return Sheet.Cell?
function Sheet:cell (row, col)
  return self.cells[row * KEY + col]
end

---The text typed into a cell, or "" for an empty one.
---@param row integer
---@param col integer
---@return string
function Sheet:text (row, col)
  local cell = self.cells[row * KEY + col]
  return cell and cell.text or ''
end

---@param row integer
---@param col integer
---@return Sheet.Value
function Sheet:value (row, col)
  self.book:ensure ()
  local cell = self.cells[row * KEY + col]
  if cell and cell.text ~= '' then
    return cell.value
  end
  return (self:spilled (row, col))
end

---The value a formula's block shows in an empty cell, and the formula's cell, or nil when no
---block spills there.
---@param row integer
---@param col integer
---@return Sheet.Value
---@return Sheet.Cell?
function Sheet:spilled (row, col)
  local anchor = self.watch.spills[row * KEY + col]
  if not anchor then
    return nil, nil
  end
  local block, area = anchor.spill, anchor.spill_area
  if not block or not area then
    return nil, nil
  end
  return block.v[(row - area.r1) * block.w + (col - area.c1) + 1], anchor
end

---The style a cell shows: its own style over its row's over its column's, without reset
---values. Never change the table it returns.
---@param row integer
---@param col integer
---@return Sheet.Style
function Sheet:style_at (row, col)
  local cell = self.cells[row * KEY + col]
  return clean (
    layer (
      layer (self.col_styles[col], self.row_styles[row]),
      cell and cell.style
    )
  )
end

---The style a cell gets from its row and column alone.
---@param row integer
---@param col integer
---@return Sheet.Style
function Sheet:inherited (row, col)
  return clean (layer (self.col_styles[col], self.row_styles[row]))
end

---The cell's own style, as stored, or nil.
---@param row integer
---@param col integer
---@return Sheet.Style?
function Sheet:own_style (row, col)
  local cell = self.cells[row * KEY + col]
  return cell and cell.style
end

---@param row integer
---@return Sheet.Style?
function Sheet:row_style (row)
  return self.row_styles[row]
end

---@param col integer
---@return Sheet.Style?
function Sheet:col_style (col)
  return self.col_styles[col]
end

---@param row integer
---@param col integer
---@return boolean
function Sheet:is_bold (row, col)
  return self:style_at (row, col).bold == true
end

-- The formats a formula's result shows with when it makes a date or a time.
local RESULT_CODES = {
  date = 'yyyy-mm-dd',
  datetime = 'yyyy-mm-dd hh:mm',
  time = 'h:mm AM/PM',
}

---@type table<Sheet.Node, string|false>
local result_codes = setmetatable ({}, { __mode = 'k' })
---@type table<Sheet.Node, Sheet.Area|false>
local first_areas = setmetatable ({}, { __mode = 'k' })

---@param ast Sheet.Node
---@return string?
local function result_code (ast)
  local hit = result_codes[ast]
  if hit == nil then
    local kind = formula.result_format (ast)
    hit = kind and RESULT_CODES[kind] or false
    result_codes[ast] = hit
  end
  return hit or nil
end

---@param ast Sheet.Node
---@return Sheet.Area?
local function first_area (ast)
  local hit = first_areas[ast]
  if hit == nil then
    hit = formula.refs (ast)[1] or false
    first_areas[ast] = hit
  end
  return hit or nil
end

---The format a formula cell shows its number with when the cell sets none: a date or time for
---a formula that makes one, and otherwise the format of the first cell it reads, as
---`=SUM(B2:B9)` shows money when B2 does.
---@param cell Sheet.Cell
---@return string?
function Sheet:auto_format (cell)
  local ast = cell.ast
  if not ast then
    return nil
  end
  local code = result_code (ast)
  if code then
    return code
  end
  local area = first_area (ast)
  if not area then
    return nil
  end
  local target = self ---@type Sheet.Sheet?
  if area.sheet then
    target = self.book:find (area.sheet)
  end
  if not target then
    return nil
  end
  local row, col = area.r1 or 1, area.c1 or 1
  local own = target:style_at (row, col).format
  if own then
    return own
  end
  local other = target.cells[row * KEY + col]
  if other and other.ast then
    return result_code (other.ast)
  end
  return nil
end

---The number format a cell shows with: its style's, or the automatic one of a formula.
---@param row integer
---@param col integer
---@return string?
function Sheet:number_format (row, col)
  local own = self:style_at (row, col).format
  if own then
    return own
  end
  local cell = self.cells[row * KEY + col]
  if cell and cell.formula then
    return self:auto_format (cell)
  end
  return nil
end

---What a cell shows, and the colour a format section such as `[Red]` picks. With `digits`, a
---cell with no format shows numbers with up to that many significant digits.
---@param row integer
---@param col integer
---@param digits? integer
---@return string
---@return string?
function Sheet:display (row, col, digits)
  self.book:ensure ()
  local cell = self.cells[row * KEY + col]
  if not cell or cell.text == '' then
    local v, anchor = self:spilled (row, col)
    if anchor then
      -- A spilled number shows with the cell's format, or the formula's automatic one.
      local own = self:style_at (row, col).format
      if not own and type (v) == 'number' then
        own = self:auto_format (anchor)
      end
      if digits and not own then
        return formula.format_value (v, digits), nil
      end
      return format.format (v, own)
    end
  end
  if not cell then
    return '', nil
  end
  local v = cell.value
  local code = self:style_at (row, col).format
  if not code and cell.formula and type (v) == 'number' then
    code = self:auto_format (cell)
  end
  if digits and not code then
    return formula.format_value (v, digits), nil
  end
  return format.format (v, code)
end

---How a cell's value lines up and looks.
---@param row integer
---@param col integer
---@return 'empty'|'number'|'text'|'bool'|'error'
function Sheet:kind (row, col)
  local v = self:value (row, col)
  if v == nil then
    return 'empty'
  end
  local t = type (v)
  if t == 'number' then
    return 'number'
  end
  if t == 'string' then
    return v == '' and 'empty' or 'text'
  end
  if t == 'boolean' then
    return 'bool'
  end
  return 'error'
end

---Where a cell's text sits across the cell: its style's alignment, or numbers and dates on
---the right, text on the left, and TRUE, FALSE and errors in the centre.
---@param row integer
---@param col integer
---@return 'left'|'center'|'right'
function Sheet:align (row, col)
  local align = self:style_at (row, col).align
  if align == 'left' or align == 'center' or align == 'right' then
    return align --[[@as 'left'|'center'|'right']]
  end
  return format.align (self:value (row, col), self:number_format (row, col))
end

---The text to put in the editor for a cell. Dates, times and percents show the way they are
---typed, so the text reads back to the same value.
---@param row integer
---@param col integer
---@return string
function Sheet:edit_text (row, col)
  local cell = self.cells[row * KEY + col]
  if not cell then
    return ''
  end
  local v = self:value (row, col)
  if cell.formula or type (v) ~= 'number' then
    return cell.text
  end
  local kind = format.kind (self:style_at (row, col).format)
  if kind == 'date' then
    return (format.format (v, 'm/d/yyyy'))
  elseif kind == 'datetime' then
    return (format.format (v, 'm/d/yyyy h:mm:ss'))
  elseif kind == 'time' or kind == 'duration' then
    return (format.format (v, 'h:mm:ss AM/PM'))
  elseif kind == 'percent' then
    return M.number_text (tonumber (string.format ('%.15g', v * 100)) or 0)
      .. '%'
  end
  return cell.text
end

---The last row and column that hold text, or 0 and 0 for an empty sheet.
---@return integer rows
---@return integer cols
function Sheet:used ()
  local rows, cols = 0, 0
  for _, cell in pairs (self.cells) do
    if cell.text ~= '' then
      rows = math.max (rows, cell.row)
      cols = math.max (cols, cell.col)
    end
  end
  return rows, cols
end

---The cells with text or a style inside a block, in no set order. A big block walks the
---cells that exist rather than every address in it.
---@param rect Sheet.Rect
---@return Sheet.Cell[]
function Sheet:cells_in (rect)
  local out = {} ---@type Sheet.Cell[]
  local area = (rect.r2 - rect.r1 + 1) * (rect.c2 - rect.c1 + 1)
  if area <= WALK then
    for r = rect.r1, rect.r2 do
      for c = rect.c1, rect.c2 do
        local cell = self.cells[r * KEY + c]
        if cell then
          out[#out + 1] = cell
        end
      end
    end
    return out
  end
  for _, cell in pairs (self.cells) do
    if
      cell.row >= rect.r1
      and cell.row <= rect.r2
      and cell.col >= rect.c1
      and cell.col <= rect.c2
    then
      out[#out + 1] = cell
    end
  end
  return out
end

---Sum, count and average of the numbers in a block.
---@param rect Sheet.Rect
---@return Sheet.Stats
function Sheet:stats (rect)
  self.book:ensure ()
  local sum, count = 0.0, 0
  for _, cell in ipairs (self:cells_in (rect)) do
    local v = cell.value
    if type (v) == 'number' then
      sum = sum + v
      count = count + 1
    end
  end
  return { sum = sum, count = count, average = count > 0 and sum / count or nil }
end

---Where Ctrl and an arrow key lands: the last filled cell before a gap, the next filled cell
---after one, or the edge of the sheet.
---@param row integer
---@param col integer
---@param dr integer
---@param dc integer
---@return integer row
---@return integer col
function Sheet:jump (row, col, dr, dc)
  local rows, cols, cells = self.rows, self.cols, self.cells
  ---@param r integer
  ---@param c integer
  ---@return boolean
  local function inside (r, c)
    return r >= 1 and r <= rows and c >= 1 and c <= cols
  end
  ---@param r integer
  ---@param c integer
  ---@return boolean
  local function filled (r, c)
    local cell = cells[r * KEY + c]
    return cell ~= nil and cell.text ~= ''
  end
  local r, c = row + dr, col + dc
  if not inside (r, c) then
    return row, col
  end
  if filled (row, col) and filled (r, c) then
    while inside (r + dr, c + dc) and filled (r + dr, c + dc) do
      r, c = r + dr, c + dc
    end
    return r, c
  end
  while not filled (r, c) and inside (r + dr, c + dc) do
    r, c = r + dr, c + dc
  end
  return r, c
end

---The block of filled cells around a cell, as far as filled cells touch each other, sideways
---or corner to corner. An empty cell with no filled neighbour is a block of itself.
---@param row integer
---@param col integer
---@return Sheet.Rect
function Sheet:region (row, col)
  local cells = self.cells
  ---@param r integer
  ---@param c integer
  ---@return boolean
  local function filled (r, c)
    local cell = cells[r * KEY + c]
    return cell ~= nil and cell.text ~= ''
  end
  local rows, cols = self.rows, self.cols
  ---@param r integer
  ---@param a integer
  ---@param b integer
  ---@return boolean
  local function row_has (r, a, b)
    for c = math.max (1, a), math.min (cols, b) do
      if filled (r, c) then
        return true
      end
    end
    return false
  end
  ---@param c integer
  ---@param a integer
  ---@param b integer
  ---@return boolean
  local function col_has (c, a, b)
    for r = math.max (1, a), math.min (rows, b) do
      if filled (r, c) then
        return true
      end
    end
    return false
  end
  -- Each side grows as far as it can before the next side looks, so a tall block scans each
  -- new row once rather than rescanning its whole height for every row it gains.
  local r1, c1, r2, c2 = row, col, row, col
  local grew = true
  while grew do
    grew = false
    while r1 > 1 and row_has (r1 - 1, c1 - 1, c2 + 1) do
      r1, grew = r1 - 1, true
    end
    while r2 < rows and row_has (r2 + 1, c1 - 1, c2 + 1) do
      r2, grew = r2 + 1, true
    end
    while c1 > 1 and col_has (c1 - 1, r1 - 1, r2 + 1) do
      c1, grew = c1 - 1, true
    end
    while c2 < cols and col_has (c2 + 1, r1 - 1, r2 + 1) do
      c2, grew = c2 + 1, true
    end
  end
  return { r1 = r1, c1 = c1, r2 = r2, c2 = c2 }
end

---The values of a block as rows of text, for a CSV file. The block is every used cell when
---`rect` is nil.
---@param rect? Sheet.Rect
---@param digits? integer
---@return string[][]
function Sheet:grid (rect, digits)
  local r = rect
  if not r then
    local rows, cols = self:used ()
    r = { r1 = 1, c1 = 1, r2 = rows, c2 = cols }
  end
  local out = {} ---@type string[][]
  for row = r.r1, r.r2 do
    local line = {} ---@type string[]
    for col = r.c1, r.c2 do
      line[#line + 1] = self:display (row, col, digits)
    end
    out[#out + 1] = line
  end
  return out
end

---------------------------------------------------------------------------------------------
-- Sizes, hidden rows and columns, merges, notes and frozen panes
---------------------------------------------------------------------------------------------

---@param col integer
---@return number
function Sheet:width (col)
  return self.widths[col] or M.DEFAULT_WIDTH
end

---@param row integer
---@return number
function Sheet:height (row)
  return self.heights[row] or M.DEFAULT_HEIGHT
end

---True when a row is hidden, by the user or by the filter.
---@param row integer
---@return boolean
function Sheet:row_hidden (row)
  if self.hidden_rows[row] then
    return true
  end
  local filter = self.filter
  return filter ~= nil and filter.hidden[row] == true
end

---True when the filter hides a row.
---@param row integer
---@return boolean
function Sheet:filtered (row)
  local filter = self.filter
  return filter ~= nil and filter.hidden[row] == true
end

---@param col integer
---@return boolean
function Sheet:col_hidden (col)
  return self.hidden_cols[col] == true
end

---The merged block a cell belongs to, or nil.
---@param row integer
---@param col integer
---@return Sheet.Rect?
function Sheet:merge_at (row, col)
  local list = self.merges
  if #list == 0 then
    return nil
  end
  if self.merge_list ~= list then
    local index = {} ---@type table<integer, Sheet.Rect>
    for _, m in ipairs (list) do
      for r = m.r1, m.r2 do
        for c = m.c1, m.c2 do
          index[r * KEY + c] = m
        end
      end
    end
    self.merge_index, self.merge_list = index, list
  end
  return (self.merge_index --[[@as table<integer, Sheet.Rect>]])[row * KEY + col]
end

---The note on a cell, or nil.
---@param row integer
---@param col integer
---@return string?
function Sheet:note (row, col)
  return self.notes[row * KEY + col]
end

---The link on a cell, or nil.
---@param row integer
---@param col integer
---@return string?
function Sheet:link (row, col)
  return self.links[row * KEY + col]
end

---@return integer rows
---@return integer cols
function Sheet:freeze ()
  return self.freeze_rows, self.freeze_cols
end

---Where every row and column sits in pixels, counting hidden ones as no room. The table is
---worked out again only after something in the book changes. Never change it.
---@return Sheet.Layout
function Sheet:layout ()
  local cache = self.layout_cache
  local stamp = self.book.stamp
  if cache and cache.stamp == stamp then
    return cache
  end
  local tops, lefts = { 0 }, { 0 } ---@type number[], number[]
  for row = 1, self.rows do
    local h = self:row_hidden (row) and 0 or self:height (row)
    tops[row + 1] = tops[row] + h
  end
  for col = 1, self.cols do
    local w = self:col_hidden (col) and 0 or self:width (col)
    lefts[col + 1] = lefts[col] + w
  end
  cache = { tops = tops, lefts = lefts, stamp = stamp }
  self.layout_cache = cache
  return cache
end

---The index whose span in `edges` holds `pos`, by halving, skipping spans of no size.
---@param edges number[]
---@param pos number
---@return integer
local function span_at (edges, pos)
  local n = #edges - 1
  local lo, hi = 1, n
  if pos < 0 then
    hi = 1
  elseif pos >= edges[n + 1] then
    lo = n
  end
  while lo < hi do
    local mid = math.floor ((lo + hi + 1) / 2)
    if edges[mid] <= pos then
      lo = mid
    else
      hi = mid - 1
    end
  end
  -- A span of no size is hidden, so step to the next one that shows, or back to the last.
  local found = lo
  while found < n and edges[found + 1] == edges[found] do
    found = found + 1
  end
  while found > 1 and edges[found + 1] == edges[found] do
    found = found - 1
  end
  return found
end

---The row at a height in pixels from the top of the sheet.
---@param y number
---@return integer
function Sheet:row_at (y)
  return span_at (self:layout ().tops, y)
end

---The column at a distance in pixels from the left of the sheet.
---@param x number
---@return integer
function Sheet:col_at (x)
  return span_at (self:layout ().lefts, x)
end

---The block grown until no merged block crosses its edge, so a selection takes whole merges.
---@param rect Sheet.Rect
---@return Sheet.Rect
function Sheet:expand_to_merges (rect)
  local r = tidy (rect)
  local grew = #self.merges > 0
  while grew do
    grew = false
    for _, m in ipairs (self.merges) do
      if M.overlaps (m, r) and not M.contains (r, m) then
        r = {
          r1 = math.min (r.r1, m.r1),
          c1 = math.min (r.c1, m.c1),
          r2 = math.max (r.r2, m.r2),
          c2 = math.max (r.c2, m.c2),
        }
        grew = true
      end
    end
  end
  return r
end

---The next cell in a direction that shows: hidden rows and columns are skipped, and so are
---the cells a merged block covers. Stays put at the edge of the sheet.
---@param row integer
---@param col integer
---@param dr integer
---@param dc integer
---@return integer row
---@return integer col
function Sheet:next_visible (row, col, dr, dc)
  local here = self:merge_at (row, col)
  local r, c = row, col ---@type integer, integer
  if here then
    -- Leave a merged block from its far edge.
    if dr > 0 then
      r = here.r2
    elseif dr < 0 then
      r = here.r1
    end
    if dc > 0 then
      c = here.c2
    elseif dc < 0 then
      c = here.c1
    end
  end
  while true do
    local nr, nc = r + dr, c + dc ---@type integer, integer
    if nr < 1 or nr > self.rows or nc < 1 or nc > self.cols then
      return row, col
    end
    r, c = nr, nc
    if not self:row_hidden (r) and not self:col_hidden (c) then
      local m = self:merge_at (r, c)
      if m then
        return m.r1, m.c1
      end
      return r, c
    end
  end
end

---Makes the sheet at least this big. This is not an undo step.
---@param rows integer
---@param cols integer
function Sheet:grow (rows, cols)
  if rows > self.rows or cols > self.cols then
    self.rows = math.max (self.rows, rows)
    self.cols = math.max (self.cols, cols)
    self.layout_cache = nil
  end
end

---------------------------------------------------------------------------------------------
-- Writing without undo
---------------------------------------------------------------------------------------------

---The text and style of a cell, as undo keeps them.
---@param row integer
---@param col integer
---@return Sheet.CellState
function Sheet:state (row, col)
  local cell = self.cells[row * KEY + col]
  if not cell then
    return { text = '' }
  end
  return { text = cell.text, style = cell.style }
end

---A style with bold switched on or off, for callers that know only bold.
---@param style? Sheet.Style
---@param on boolean
---@return Sheet.Style?
local function with_bold (style, on)
  local t = fields_of (style)
  t.bold = on or nil
  return intern (t)
end

---Writes a cell without recording it for undo. A state with `bold` and no `style` keeps the
---cell's other style fields.
---@param row integer
---@param col integer
---@param st Sheet.CellState
function Sheet:put (row, col, st)
  local key = row * KEY + col
  local old = self.cells[key]
  local style = st.style
  if st.bold ~= nil and st.style == nil then
    style = with_bold (old and old.style, st.bold)
  end
  local text = st.text or ''
  if text == '' and not style then
    if old then
      self.cells[key] = nil
      if old.text ~= '' then
        self.book:cell_changed (self, row, col, old, nil)
      end
    end
  elseif old and old.text == text then
    old.style = style
    old.bold = style and style.bold == true or nil
  else
    local cell = make_cell (row, col, text, style, self.book.clock)
    self.cells[key] = cell
    self.book:cell_changed (self, row, col, old, cell)
  end
  local touched = self.touched
  if touched ~= true then
    touched[key] = true
  end
  self:grow (row, col)
  self.book:touch ()
end

---The cells written since the last call, by key, or true when anything may have changed,
---such as after an insert, a load or a new column width. The grid grows rows for their text
---by this, so an edit looks at the cells it wrote rather than at the whole sheet.
---@return table<integer, boolean>|true
function Sheet:take_touched ()
  local touched = self.touched
  self.touched = {}
  return touched
end

---Sets a field, or one entry of a map field when `key` is given, without recording it.
---@param field string
---@param key any
---@param value any
function Sheet:put_prop (field, key, value)
  local t = self --[[@as table<string, any>]]
  if key == nil then
    t[field] = value
  else
    local map = t[field] --[[@as table<any, any>]]
    map[key] = value
  end
  if field ~= 'notes' and field ~= 'links' and field ~= 'name' then
    -- Sizes, row and column styles and the lists may change how tall any row needs to be.
    self.touched = true
  end
  if field == 'name' then
    self.book:names_changed ()
  elseif field == 'rows' or field == 'cols' then
    self.book.full = true
  elseif field == 'hidden_rows' or field == 'filter' then
    self.book:rows_changed ()
  end
  self.book:touch ()
end

---The lists and the size of the sheet, by reference. An insert or a delete builds new lists
---rather than changing these, so the shape stays as it was for undo.
---@return Sheet.SheetShape
function Sheet:shape ()
  return {
    merges = self.merges,
    filter = self.filter,
    rules = self.rules,
    validation = self.validation,
    charts = self.charts,
    rows = self.rows,
    cols = self.cols,
    freeze_rows = self.freeze_rows,
    freeze_cols = self.freeze_cols,
  }
end

---Puts back the lists and the size a shape holds, without recording it.
---@param st Sheet.SheetShape
function Sheet:put_shape (st)
  self.merges = st.merges
  self.filter = st.filter
  self.rules = st.rules
  self.validation = st.validation
  self.charts = st.charts
  self.rows = st.rows
  self.cols = st.cols
  self.freeze_rows = st.freeze_rows
  self.freeze_cols = st.freeze_cols
  self.touched = true
  self.book.full = true
  self.book:touch ()
end

---Moves every cell, note, style, size and hidden mark past `at` by `count` rows or columns,
---without recording it, and returns what the deleted ones held. A cell keeps its text and
---its parsed formula, so nothing is read again. Formula texts change apart, in `put_texts`.
---@param axis 'row'|'col'
---@param at integer
---@param count integer
---@return Sheet.Band?
function Sheet:move_band (axis, at, count)
  local is_row = axis == 'row'
  ---@type Sheet.Band?
  local band = count < 0
      and {
        cells = {},
        notes = {},
        links = {},
        styles = {},
        sizes = {},
        hidden = {},
      }
    or nil
  local cells = {} ---@type table<integer, Sheet.Cell>
  for key, cell in pairs (self.cells) do
    local pos = is_row and cell.row or cell.col
    local np = moved_to (pos, at, count)
    if np then
      if is_row then
        cell.row = np
      else
        cell.col = np
      end
      cells[cell.row * KEY + cell.col] = cell
    elseif band then
      band.cells[key] = { text = cell.text, style = cell.style }
    end
  end
  self.cells = cells
  ---Moves a map by cell, keeping what the deleted cells held in `lost`.
  ---@param map table<integer, string>
  ---@param lost? table<integer, string>
  ---@return table<integer, string>
  local function move_keys (map, lost)
    local out = {} ---@type table<integer, string>
    for key, text in pairs (map) do
      local row = math.floor (key / KEY)
      local col = key - row * KEY
      local np = moved_to (is_row and row or col, at, count)
      if np then
        if is_row then
          out[np * KEY + col] = text
        else
          out[row * KEY + np] = text
        end
      elseif lost then
        lost[key] = text
      end
    end
    return out
  end
  self.notes = move_keys (self.notes, band and band.notes)
  self.links = move_keys (self.links, band and band.links)
  ---@generic T
  ---@param map table<integer, T>
  ---@param lost? table<integer, T>
  ---@return table<integer, T>
  local function shift_map (map, lost)
    local out = {} ---@type table<integer, any>
    for k, v in pairs (map) do
      local nk = moved_to (k, at, count)
      if nk then
        out[nk] = v
      elseif lost then
        lost[k] = v
      end
    end
    return out
  end
  if is_row then
    self.row_styles = shift_map (self.row_styles, band and band.styles)
    self.heights = shift_map (self.heights, band and band.sizes)
    self.hidden_rows = shift_map (self.hidden_rows, band and band.hidden)
  else
    self.col_styles = shift_map (self.col_styles, band and band.styles)
    self.widths = shift_map (self.widths, band and band.sizes)
    self.hidden_cols = shift_map (self.hidden_cols, band and band.hidden)
  end
  self.touched = true
  self.book.full = true
  self.book:touch ()
  return band
end

---Puts back what deleted rows or columns held, after undo inserted them again.
---@param axis 'row'|'col'
---@param band Sheet.Band
function Sheet:put_band (axis, band)
  local clock = self.book.clock
  for key, st in pairs (band.cells) do
    local row = math.floor (key / KEY)
    local col = key - row * KEY
    self.cells[key] = make_cell (row, col, st.text, st.style, clock)
  end
  for key, text in pairs (band.notes) do
    self.notes[key] = text
  end
  for key, text in pairs (band.links or {}) do
    self.links[key] = text
  end
  local styles = axis == 'row' and self.row_styles or self.col_styles
  local sizes = axis == 'row' and self.heights or self.widths
  local hidden = axis == 'row' and self.hidden_rows or self.hidden_cols
  for k, v in pairs (band.styles) do
    styles[k] = v
  end
  for k, v in pairs (band.sizes) do
    sizes[k] = v
  end
  for k, v in pairs (band.hidden) do
    hidden[k] = v
  end
  self.book.full = true
  self.book:touch ()
end

---Gives formula cells new texts, by place, without recording it.
---@param texts table<integer, string>
function Sheet:put_texts (texts)
  local clock = self.book.clock
  for key, text in pairs (texts) do
    local cell = self.cells[key]
    if cell then
      self.cells[key] = make_cell (cell.row, cell.col, text, cell.style, clock)
    end
  end
  self.book.full = true
end

---Plays an insert or a delete forward, or backward with `back`, without recording it.
---@param shift Sheet.Shift
---@param back boolean
function Sheet:play_shift (shift, back)
  if back then
    self:move_band (shift.axis, shift.at, -shift.count)
    if shift.band then
      self:put_band (shift.axis, shift.band)
    end
    self:put_texts (shift.old_texts)
  else
    shift.band = self:move_band (shift.axis, shift.at, shift.count)
    self:put_texts (shift.texts)
  end
end

---------------------------------------------------------------------------------------------
-- Writing with undo
---------------------------------------------------------------------------------------------

---Writes a cell and records the change in the book's open step.
---@param row integer
---@param col integer
---@param after Sheet.CellState
function Sheet:record (row, col, after)
  local before = self:state (row, col)
  local style = after.style
  if after.bold ~= nil and after.style == nil then
    style = with_bold (before.style, after.bold)
  end
  local text = after.text or ''
  if before.text == text and before.style == style then
    return
  end
  ---@type Sheet.CellState
  local state = { text = text, style = style }
  self.book:log_cell (self, row, col, before, state)
  self:put (row, col, state)
end

---Sets a field, or one entry of a map field when `key` is given, and records the change.
---Lists such as `rules` are replaced whole, never changed in place.
---@param field string
---@param key any
---@param value any
function Sheet:set_prop (field, key, value)
  local t = self --[[@as table<string, any>]]
  local before ---@type any
  if key == nil then
    before = t[field]
  else
    local map = t[field] --[[@as table<any, any>]]
    before = map[key]
  end
  if before == value then
    return
  end
  self.book:log_prop (self, field, key, before, value)
  self:put_prop (field, key, value)
end

---Replaces a whole field, such as `rules`, `validation`, `charts`, `filter` or `merges`, as
---one undo step.
---@param field string
---@param value any
function Sheet:set_field (field, value)
  self.book:begin ({ sheet = self })
  self:set_prop (field, nil, value)
  self.book:finish ()
end

---Starts a batch on the sheet's book. Every change until `finish` is one undo step.
---@param opts? Sheet.BatchOptions
function Sheet:begin (opts)
  local o = opts or {}
  self.book:begin ({
    sheet = o.sheet or self,
    select = o.select,
    label = o.label,
  })
end

function Sheet:finish ()
  self.book:finish ()
end

---@return boolean
function Sheet:can_undo ()
  return self.book:can_undo ()
end

---@return boolean
function Sheet:can_redo ()
  return self.book:can_redo ()
end

---Takes back the book's last step. Returns whether there was one, and the block to select.
---@return boolean
---@return Sheet.Rect?
function Sheet:undo ()
  local info = self.book:undo ()
  if not info then
    return false, nil
  end
  return true, info.rect
end

---Does the book's last undone step again. Returns whether there was one, and the block.
---@return boolean
---@return Sheet.Rect?
function Sheet:redo ()
  local info = self.book:redo ()
  if not info then
    return false, nil
  end
  return true, info.rect
end

---Works out every value in the book again.
function Sheet:recalc ()
  self.book:recalc ()
end

---Brings the book's values up to date.
function Sheet:ensure ()
  self.book:ensure ()
end

---------------------------------------------------------------------------------------------
-- Typing
---------------------------------------------------------------------------------------------

---What typing a text into a cell stores. A number, date or time whose typing implies a
---format, such as `$1,200` or `9/29/2026`, stores the number, and the cell takes the format
---unless it has a number format already.
---@param row integer
---@param col integer
---@param text string
---@return Sheet.CellState
function Sheet:typed (row, col, text)
  local cell = self.cells[row * KEY + col]
  local style = cell and cell.style
  if text == '' or formula.is_formula (text) then
    return { text = text, style = style }
  end
  local value, code = format.parse_input (text, self.book.clock)
  if type (value) == 'number' and code then
    text = M.number_text (value --[[@as number]])
    if not self:style_at (row, col).format then
      style = cell_patch (style, { format = code }, self:inherited (row, col))
    end
  end
  return { text = text, style = style }
end

---Sets the text of a cell as if typed, as one undo step unless a batch is open.
---@param row integer
---@param col integer
---@param text string
function Sheet:set (row, col, text)
  self:record (row, col, self:typed (row, col, text or ''))
end

---Sets several cells as one undo step. Each entry is a row, a column and the text.
---@param list { [1]: integer, [2]: integer, [3]: string }[]
function Sheet:set_many (list)
  self:begin ()
  for _, entry in ipairs (list) do
    self:set (entry[1], entry[2], entry[3])
  end
  self:finish ()
end

---Clears a block as one undo step. `what` is `contents` (the default), which keeps styles and
---notes as spreadsheets do on Delete, or `formats`, `notes` or `all`.
---@param rect Sheet.Rect
---@param what? 'contents'|'formats'|'notes'|'links'|'all'
function Sheet:clear (rect, what)
  local r = tidy (rect)
  local w = what or 'contents'
  self:begin ({ select = r, label = 'Clear' })
  if w == 'contents' or w == 'all' then
    for _, cell in ipairs (self:cells_in (r)) do
      if cell.text ~= '' then
        self:record (cell.row, cell.col, { text = '', style = cell.style })
      end
    end
  end
  if w == 'formats' or w == 'all' then
    self:clear_format (r)
  end
  for _, field in ipairs ({ 'notes', 'links' }) do
    if w == field or w == 'all' then
      local keys = {} ---@type integer[]
      for key in
        pairs ((self --[[@as table<string, table<integer, string>>]])[field])
      do
        local row = math.floor (key / KEY)
        local col = key - row * KEY
        if row >= r.r1 and row <= r.r2 and col >= r.c1 and col <= r.c2 then
          keys[#keys + 1] = key
        end
      end
      for _, key in ipairs (keys) do
        self:set_prop (field, key, nil)
      end
    end
  end
  self:finish ()
end

---------------------------------------------------------------------------------------------
-- Styles over a block
---------------------------------------------------------------------------------------------

---A block cut to the sheet's size.
---@param self Sheet.Sheet
---@param rect Sheet.Rect
---@return Sheet.Rect
local function inside (self, rect)
  local r = tidy (rect)
  return {
    r1 = math.max (1, r.r1),
    c1 = math.max (1, r.c1),
    r2 = math.min (self.rows, r.r2),
    c2 = math.min (self.cols, r.c2),
  }
end

---Patches the own style of every cell in a block, each with the patch `patch_of` gives it.
---@param rect Sheet.Rect
---@param patch_of fun(row: integer, col: integer): Sheet.StylePatch?
function Sheet:patch_cells (rect, patch_of)
  for row = rect.r1, rect.r2 do
    for col = rect.c1, rect.c2 do
      local patch = patch_of (row, col)
      if patch then
        local cell = self.cells[row * KEY + col]
        local style =
          cell_patch (cell and cell.style, patch, self:inherited (row, col))
        self:record (
          row,
          col,
          { text = cell and cell.text or '', style = style }
        )
      end
    end
  end
end

---Takes some fields out of the own style of every cell in a block.
---@param rect Sheet.Rect
---@param fields string[]
function Sheet:strip_cells (rect, fields)
  for _, cell in ipairs (self:cells_in (rect)) do
    if cell.style then
      local style = strip (cell.style, fields)
      if style ~= cell.style then
        self:record (cell.row, cell.col, { text = cell.text, style = style })
      end
    end
  end
end

---Sets style fields over a block as one undo step. A field set to `false` goes back to the
---default. When the block is whole columns or whole rows, the patch goes on the column or row
---styles, and the cells inside keep only the fields that differ.
---@param rect Sheet.Rect
---@param patch Sheet.StylePatch
function Sheet:set_style (rect, patch)
  local r = inside (self, rect)
  if r.r1 > r.r2 or r.c1 > r.c2 then
    return
  end
  local fields = patch_fields (patch)
  if #fields == 0 then
    return
  end
  local p = {} ---@type table<string, any>
  for _, k in ipairs (fields) do
    p[k] = (patch --[[@as table<string, any>]])[k]
  end
  local clean_patch = p --[[@as Sheet.StylePatch]]
  local whole_cols = r.r1 == 1 and r.r2 >= self.rows
  local whole_rows = r.c1 == 1 and r.c2 >= self.cols
  self:begin ({ select = r, label = 'Format' })
  if whole_cols then
    for c = r.c1, r.c2 do
      self:set_prop ('col_styles', c, patched (self.col_styles[c], clean_patch))
    end
    local styled = {} ---@type integer[]
    for row in pairs (self.row_styles) do
      styled[#styled + 1] = row
    end
    table.sort (styled)
    if whole_rows then
      -- The patch covers every cell, so row styles lose the fields too.
      for _, row in ipairs (styled) do
        self:set_prop ('row_styles', row, strip (self.row_styles[row], fields))
      end
    end
    self:strip_cells (r, fields)
    -- A row style that sets a patched field would still win over the column, so the cells
    -- where it crosses the columns take the patch themselves.
    for _, row in ipairs (styled) do
      local rs = self.row_styles[row] --[[@as table<string, any>?]]
      local crosses = false
      for _, k in ipairs (fields) do
        if rs and rs[k] ~= nil then
          crosses = true
        end
      end
      if crosses then
        self:patch_cells (
          { r1 = row, c1 = r.c1, r2 = row, c2 = r.c2 },
          function ()
            return clean_patch
          end
        )
      end
    end
  elseif whole_rows then
    local below = {} ---@type table<string, boolean>
    for _, cs in pairs (self.col_styles) do
      local t = cs --[[@as table<string, any>]]
      for _, k in ipairs (fields) do
        if not is_default (k, t[k]) then
          below[k] = true
        end
      end
    end
    for row = r.r1, r.r2 do
      self:set_prop (
        'row_styles',
        row,
        patched (self.row_styles[row], clean_patch, below)
      )
    end
    self:strip_cells (r, fields)
  else
    self:patch_cells (r, function ()
      return clean_patch
    end)
  end
  self:finish ()
end

---Removes every style from a block, as one undo step.
---@param rect Sheet.Rect
function Sheet:clear_format (rect)
  local patch = {} ---@type table<string, any>
  for _, k in ipairs (M.STYLE_FIELDS) do
    patch[k] = false
  end
  self:set_style (rect, patch --[[@as Sheet.StylePatch]])
end

---Sets the number format of a block, or General when `code` is nil.
---@param rect Sheet.Rect
---@param code? string
function Sheet:set_format (rect, code)
  self:set_style (rect, { format = code or false })
end

---Shows one more decimal place in a block, or one fewer when `delta` is negative, starting
---from the format and value of its top left cell.
---@param rect Sheet.Rect
---@param delta integer
function Sheet:adjust_decimals (rect, delta)
  local r = tidy (rect)
  local code = self:number_format (r.r1, r.c1)
  self:set_format (
    r,
    format.adjust_decimals (code, delta, self:value (r.r1, r.c1))
  )
end

---Whether every cell in a block shows a flag such as bold. A big block checks the cells that
---exist and the row and column styles.
---@param rect Sheet.Rect
---@param field string
---@return boolean
function Sheet:all_have (rect, field)
  local r = inside (self, rect)
  local area = (r.r2 - r.r1 + 1) * (r.c2 - r.c1 + 1)
  if area <= WALK then
    for row = r.r1, r.r2 do
      for col = r.c1, r.c2 do
        if
          not (self:style_at (row, col) --[[@as table<string, any>]])[field]
        then
          return false
        end
      end
    end
    return true
  end
  local cells = self:cells_in (r)
  for _, cell in ipairs (cells) do
    if
      not (self:style_at (cell.row, cell.col) --[[@as table<string, any>]])[field]
    then
      return false
    end
  end
  if #cells == area then
    return true
  end
  local cols_have, rows_have = true, true
  for c = r.c1, r.c2 do
    if
      not (clean (self.col_styles[c]) --[[@as table<string, any>]])[field]
    then
      cols_have = false
    end
  end
  for row = r.r1, r.r2 do
    if
      not (clean (self.row_styles[row]) --[[@as table<string, any>]])[field]
    then
      rows_have = false
      break
    end
  end
  return cols_have or rows_have
end

---Switches a flag such as bold, italic, underline, strike or wrap on for a block, or off when
---every cell in it has it already. One undo step.
---@param rect Sheet.Rect
---@param field 'bold'|'italic'|'underline'|'strike'|'wrap'
function Sheet:toggle_style (rect, field)
  local on = not self:all_have (rect, field)
  local patch = {} ---@type table<string, any>
  patch[field] = on
  self:set_style (rect, patch --[[@as Sheet.StylePatch]])
end

---Makes a block bold, or plain again when every cell in it is bold already.
---@param rect Sheet.Rect
function Sheet:toggle_bold (rect)
  self:toggle_style (rect, 'bold')
end

---@param row integer
---@param col integer
---@param on boolean
function Sheet:set_bold (row, col, on)
  self:set_style ({ r1 = row, c1 = col, r2 = row, c2 = col }, { bold = on })
end

---The border sides a preset gives one cell of a block.
---@param preset Sheet.BorderPreset
---@param r Sheet.Rect
---@param row integer
---@param col integer
---@param line string
---@param color? string
---@return Sheet.StylePatch
local function border_patch (preset, r, row, col, line, color)
  local p = {} ---@type table<string, any>
  if preset == 'none' then
    for _, side in ipairs (SIDES) do
      p[side] = false
    end
    p.border_color = false
    return p --[[@as Sheet.StylePatch]]
  end
  local top, bottom, left, right = false, false, false, false
  if preset == 'all' then
    top, bottom, left, right = true, true, true, true
  elseif preset == 'outer' then
    top, bottom = row == r.r1, row == r.r2
    left, right = col == r.c1, col == r.c2
  elseif preset == 'inner' then
    bottom, right = row < r.r2, col < r.c2
  elseif preset == 'horizontal' then
    bottom = row < r.r2
  elseif preset == 'vertical' then
    right = col < r.c2
  elseif preset == 'top' then
    top = row == r.r1
  elseif preset == 'bottom' then
    bottom = row == r.r2
  elseif preset == 'left' then
    left = col == r.c1
  elseif preset == 'right' then
    right = col == r.c2
  end
  local any = false
  for side, on in pairs ({
    border_top = top,
    border_bottom = bottom,
    border_left = left,
    border_right = right,
  }) do
    if on then
      p[side] = line
      any = true
    end
  end
  if any and color then
    p.border_color = color
  end
  return p --[[@as Sheet.StylePatch]]
end

---The fields where two patches differ, as a patch that turns `base` into `want`.
---@param base Sheet.StylePatch
---@param want Sheet.StylePatch
---@return Sheet.StylePatch?
local function patch_diff (base, want)
  local out = {} ---@type table<string, any>
  local any = false
  local b = base --[[@as table<string, any>]]
  local w = want --[[@as table<string, any>]]
  for _, k in ipairs (M.STYLE_FIELDS) do
    local x, y = b[k], w[k]
    if x ~= y then
      if y == nil then
        out[k] = false
      else
        out[k] = y
      end
      any = true
    end
  end
  if not any then
    return nil
  end
  return out --[[@as Sheet.StylePatch]]
end

---Draws borders over a block by preset: `all`, `outer`, `inner`, `top`, `bottom`, `left`,
---`right`, `horizontal` and `vertical` for the inner lines, or `none`. `line` is the line
---style, thin when nil. One undo step.
---@param rect Sheet.Rect
---@param preset Sheet.BorderPreset
---@param line? string
---@param color? string
function Sheet:set_borders (rect, preset, line, color)
  local r = inside (self, rect)
  if r.r1 > r.r2 or r.c1 > r.c2 then
    return
  end
  local style = line or 'thin'
  self:begin ({ select = r, label = 'Borders' })
  local whole_cols = r.r1 == 1 and r.r2 >= self.rows
  local whole_rows = r.c1 == 1 and r.c2 >= self.cols
  if whole_cols or whole_rows then
    -- The rows in the middle of whole columns all get the same sides, so those go on the
    -- column styles, and the first and last rows take what differs. Whole rows go the same
    -- way across.
    if whole_cols then
      local mid = math.min (r.r1 + 1, r.r2)
      for col = r.c1, r.c2 do
        local common = border_patch (preset, r, mid, col, style, color)
        self:set_style ({ r1 = 1, c1 = col, r2 = self.rows, c2 = col }, common)
        for _, row in ipairs ({ r.r1, r.r2 }) do
          local diff = patch_diff (
            common,
            border_patch (preset, r, row, col, style, color)
          )
          if diff then
            self:set_style ({ r1 = row, c1 = col, r2 = row, c2 = col }, diff)
          end
        end
      end
    else
      local mid = math.min (r.c1 + 1, r.c2)
      for row = r.r1, r.r2 do
        local common = border_patch (preset, r, row, mid, style, color)
        self:set_style ({ r1 = row, c1 = 1, r2 = row, c2 = self.cols }, common)
        for _, col in ipairs ({ r.c1, r.c2 }) do
          local diff = patch_diff (
            common,
            border_patch (preset, r, row, col, style, color)
          )
          if diff then
            self:set_style ({ r1 = row, c1 = col, r2 = row, c2 = col }, diff)
          end
        end
      end
    end
  else
    self:patch_cells (r, function (row, col)
      local p = border_patch (preset, r, row, col, style, color)
      if
        next (p --[[@as table]]) == nil
      then
        return nil
      end
      return p
    end)
  end
  self:finish ()
end

---------------------------------------------------------------------------------------------
-- Structure
---------------------------------------------------------------------------------------------

---Sets a column width, as one undo step.
---@param col integer
---@param width number
function Sheet:set_width (col, width)
  self:set_widths (col, col, width)
end

---Sets the width of several columns, as one undo step.
---@param c1 integer
---@param c2 integer
---@param width number
function Sheet:set_widths (c1, c2, width)
  local w = math.floor (math.max (MIN_WIDTH, math.min (MAX_WIDTH, width)) + 0.5)
  self:begin ({ label = 'Column width' })
  for col = math.min (c1, c2), math.max (c1, c2) do
    self:set_prop ('widths', col, w ~= M.DEFAULT_WIDTH and w or nil)
  end
  self:finish ()
end

---Sets a row height, as one undo step.
---@param row integer
---@param height number
function Sheet:set_height (row, height)
  self:set_heights (row, row, height)
end

---Sets the height of several rows, as one undo step.
---@param r1 integer
---@param r2 integer
---@param height number
function Sheet:set_heights (r1, r2, height)
  local h =
    math.floor (math.max (MIN_HEIGHT, math.min (MAX_HEIGHT, height)) + 0.5)
  self:begin ({ label = 'Row height' })
  for row = math.min (r1, r2), math.max (r1, r2) do
    self:set_prop ('heights', row, h ~= M.DEFAULT_HEIGHT and h or nil)
  end
  self:finish ()
end

---Hides or shows rows or columns, as one undo step.
---@param axis 'row'|'col'
---@param from integer
---@param to integer
---@param hidden boolean
function Sheet:set_hidden (axis, from, to, hidden)
  local field = axis == 'row' and 'hidden_rows' or 'hidden_cols'
  self:begin ({ label = hidden and 'Hide' or 'Show' })
  for i = math.min (from, to), math.max (from, to) do
    self:set_prop (field, i, hidden or nil)
  end
  self:finish ()
end

---Freezes the top rows and the left columns, as one undo step. Zero freezes none.
---@param rows integer
---@param cols integer
function Sheet:set_freeze (rows, cols)
  self:begin ({ label = 'Freeze' })
  self:set_prop ('freeze_rows', nil, math.max (0, math.floor (rows or 0)))
  self:set_prop ('freeze_cols', nil, math.max (0, math.floor (cols or 0)))
  self:finish ()
end

---Sets the note on a cell, or removes it when `text` is nil or empty. One undo step.
---@param row integer
---@param col integer
---@param text? string
function Sheet:set_note (row, col, text)
  local value = text
  if value == '' then
    value = nil
  end
  self:begin ({
    select = { r1 = row, c1 = col, r2 = row, c2 = col },
    label = 'Note',
  })
  self:set_prop ('notes', row * KEY + col, value)
  self:finish ()
end

---Sets the link on a cell, or takes it away with nil or `''`, as one undo step.
---@param row integer
---@param col integer
---@param target? string
function Sheet:set_link (row, col, target)
  local value = target
  if value == '' then
    value = nil
  end
  self:begin ({
    select = { r1 = row, c1 = col, r2 = row, c2 = col },
    label = 'Link',
  })
  self:set_prop ('links', row * KEY + col, value)
  self:finish ()
end

---Merges a block, or each row of it on its own with `across`. The block shows its top left
---cell, so the text of the other cells goes. Merges inside the block join it. A block that
---cuts across another merge's edge is refused, with the reason. One undo step.
---@param rect Sheet.Rect
---@param across? boolean
---@return boolean
---@return string? problem
function Sheet:merge (rect, across)
  local r = inside (self, rect)
  local blocks = {} ---@type Sheet.Rect[]
  if across then
    if r.c1 < r.c2 then
      for row = r.r1, r.r2 do
        blocks[#blocks + 1] = { r1 = row, c1 = r.c1, r2 = row, c2 = r.c2 }
      end
    end
  elseif r.r1 < r.r2 or r.c1 < r.c2 then
    blocks[1] = r
  end
  if #blocks == 0 then
    return false, 'Pick more than one cell to merge.'
  end
  for _, m in ipairs (self.merges) do
    for _, b in ipairs (blocks) do
      if M.overlaps (m, b) and not M.contains (b, m) then
        return false,
          'The block cuts across the merged cells '
            .. M.range_name (m)
            .. '. Unmerge them first.'
      end
    end
  end
  local list = {} ---@type Sheet.Rect[]
  for _, m in ipairs (self.merges) do
    local absorbed = false
    for _, b in ipairs (blocks) do
      if M.contains (b, m) then
        absorbed = true
      end
    end
    if not absorbed then
      list[#list + 1] = m
    end
  end
  self:begin ({ select = r, label = 'Merge' })
  for _, b in ipairs (blocks) do
    list[#list + 1] = b
    for _, cell in ipairs (self:cells_in (b)) do
      if (cell.row ~= b.r1 or cell.col ~= b.c1) and cell.text ~= '' then
        self:record (cell.row, cell.col, { text = '', style = cell.style })
      end
    end
  end
  self:set_prop ('merges', nil, list)
  self:finish ()
  return true, nil
end

---Unmerges every merged block that shares a cell with a block. One undo step.
---@param rect Sheet.Rect
---@return boolean changed
function Sheet:unmerge (rect)
  local r = tidy (rect)
  local list = {} ---@type Sheet.Rect[]
  for _, m in ipairs (self.merges) do
    if not M.overlaps (m, r) then
      list[#list + 1] = m
    end
  end
  if #list == #self.merges then
    return false
  end
  self:begin ({ select = r, label = 'Unmerge' })
  self:set_prop ('merges', nil, list)
  self:finish ()
  return true
end

---A rule, validation or chart with its range moved after rows or columns change, or nil when
---its cells were all deleted. The table is a new one when anything changed.
---@param item table
---@param axis 'row'|'col'
---@param at integer
---@param count integer
---@param name string The sheet's name, for a formula rule.
---@return table?
local function adjust_item (item, axis, at, count, name)
  local range = adjust_range (item.range, axis, at, count)
  if not range then
    return nil
  end
  local text = item.formula ---@type any
  if type (text) == 'string' then
    text = formula.adjust (text, axis, at, count, { sheet = name, own = name })
  end
  if range == item.range and text == item.formula then
    return item
  end
  local copy = {} ---@type table<string, any>
  for k, v in
    pairs (item --[[@as table<string, any>]])
  do
    copy[k] = v
  end
  copy.range = range
  copy.formula = text
  return copy
end

---Inserts rows or columns before `at` when `count` is positive, or deletes `-count` of them
---from `at` on. Everything with an address moves: cells, styles, sizes, hidden rows and
---columns, merges, notes, the filter, rules, validation, charts and frozen panes. Formulas
---across the book follow. One undo step.
---@param axis 'row'|'col'
---@param at integer
---@param count integer
function Sheet:reshape (axis, at, count)
  if count == 0 or at < 1 then
    return
  end
  local size = axis == 'row' and self.rows or self.cols
  if count < 0 then
    if at > size then
      return
    end
    count = -math.min (-count, size - at + 1)
  end
  local name = self.name
  local opts = { sheet = name, own = name }
  local is_row = axis == 'row'
  ---@param pos integer
  ---@return integer?
  local function move (pos)
    return moved_to (pos, at, count)
  end
  ---@generic T
  ---@param map table<integer, T>
  ---@return table<integer, T>
  local function shift_map (map)
    local out = {} ---@type table<integer, any>
    for k, v in pairs (map) do
      local nk = move (k)
      if nk then
        out[nk] = v
      end
    end
    return out
  end
  local before = self:shape ()
  local after = self:shape ()

  -- The formulas on this sheet whose text the move changes. The rest keep their text.
  local texts, old_texts = {}, {} ---@type table<integer, string>, table<integer, string>
  for key, cell in pairs (self.cells) do
    if cell.formula then
      local row, col = cell.row, cell.col
      local nr, nc = row, col ---@type integer?, integer?
      if is_row then
        nr = move (row)
      else
        nc = move (col)
      end
      if nr and nc then
        local text = formula.adjust (cell.text, axis, at, count, opts)
        if text ~= cell.text then
          texts[nr * KEY + nc] = text
          old_texts[key] = cell.text
        end
      end
    end
  end

  if is_row then
    after.rows = math.max (1, self.rows + count)
  else
    after.cols = math.max (1, self.cols + count)
  end

  local merges = {} ---@type Sheet.Rect[]
  for _, m in ipairs (self.merges) do
    local out = M.adjust_rect (m, axis, at, count)
    if out and (out.r1 < out.r2 or out.c1 < out.c2) then
      merges[#merges + 1] = out
    end
  end
  after.merges = merges

  local filter = self.filter
  if filter then
    local rect = M.adjust_rect (filter.rect, axis, at, count)
    if rect then
      local columns = filter.columns
      local hidden = filter.hidden
      if is_row then
        hidden = shift_map (hidden)
      else
        columns = shift_map (columns)
      end
      after.filter = { rect = rect, columns = columns, hidden = hidden }
    else
      after.filter = nil
    end
  end

  ---@param list table[]
  ---@return table[]
  local function adjust_list (list)
    local out = {} ---@type table[]
    for _, item in ipairs (list) do
      local moved = adjust_item (item, axis, at, count, name)
      if moved then
        out[#out + 1] = moved
      end
    end
    return out
  end
  after.rules = adjust_list (self.rules) --[[@as Sheet.Rule[] ]]
  after.validation = adjust_list (self.validation) --[[@as Sheet.Validation[] ]]
  after.charts = adjust_list (self.charts) --[[@as Sheet.ChartSpec[] ]]

  ---@param frozen integer
  ---@return integer
  local function freeze (frozen)
    if at > frozen then
      return frozen
    end
    if count > 0 then
      return frozen + count
    end
    local last = at - count - 1
    return frozen - (math.min (last, frozen) - at + 1)
  end
  if is_row then
    after.freeze_rows = freeze (self.freeze_rows)
  else
    after.freeze_cols = freeze (self.freeze_cols)
  end

  local word = is_row and 'rows' or 'columns'
  self:begin ({ label = (count > 0 and 'Insert ' or 'Delete ') .. word })
  ---@type Sheet.Shift
  local shift = {
    axis = axis,
    at = at,
    count = count,
    texts = texts,
    old_texts = old_texts,
  }
  self.book:log ({
    kind = 'shift',
    sheet = self,
    shift = shift,
    before = before,
    after = after,
  })
  self:play_shift (shift, false)
  self:put_shape (after)
  self.book:rewrite_formulas (function (text, own)
    return formula.adjust (
      text,
      axis,
      at,
      count,
      { sheet = name, own = own.name }
    )
  end, self)
  -- A defined name belongs to no sheet, so only its references that name this one move.
  self.book:rewrite_names (function (text)
    return formula.adjust (text, axis, at, count, { sheet = name })
  end)
  self:finish ()
end

---@param at integer
---@param count? integer
function Sheet:insert_rows (at, count)
  self:reshape ('row', at, count or 1)
end

---@param at integer
---@param count? integer
function Sheet:delete_rows (at, count)
  self:reshape ('row', at, -(count or 1))
end

---@param at integer
---@param count? integer
function Sheet:insert_cols (at, count)
  self:reshape ('col', at, count or 1)
end

---@param at integer
---@param count? integer
function Sheet:delete_cols (at, count)
  self:reshape ('col', at, -(count or 1))
end

---------------------------------------------------------------------------------------------
-- Conditions and the filter
---------------------------------------------------------------------------------------------

---@param s string
---@return string
local function lower (s)
  return string.lower (s)
end

---What a condition's text operand means, as a typed value.
---@param text? string
---@return Sheet.Value
local function operand (text)
  if text == nil or text == '' then
    return nil
  end
  return (format.parse_input (text))
end

---Compares two values: -1, 0 or 1, or nil when they cannot be compared. Text ignores case.
---@param a Sheet.Value
---@param b Sheet.Value
---@return integer?
local function compare (a, b)
  local ta, tb = type (a), type (b)
  if ta == 'number' and tb == 'number' then
    return formula.compare_numbers (a --[[@as number]], b --[[@as number]])
  end
  if ta == 'string' and tb == 'string' then
    local x, y = lower (a --[[@as string]]), lower (b --[[@as string]])
    return x < y and -1 or (x > y and 1 or 0)
  end
  if ta == 'boolean' and tb == 'boolean' then
    return a == b and 0 or (a and 1 or -1)
  end
  return nil
end

---Whether a cell passes a test of a filter, a rule or a validation. `op` is a compare op,
---`>`, `<`, `>=`, `<=`, `=`, `<>`, `between` or `not_between`, which compares numbers as
---numbers and text ignoring case, or a text op, `contains`, `not_contains`, `starts`, `ends` or
---`equals`, which reads the shown text ignoring case, or `blank`, `not_blank` or `error`.
---`a` and `b` are text as typed.
---@param v Sheet.Value The cell's value.
---@param shown string The cell's shown text.
---@param op string
---@param a? string
---@param b? string
---@return boolean
function M.matches (v, shown, op, a, b)
  local blank = v == nil or v == ''
  if op == 'blank' then
    return blank
  elseif op == 'not_blank' then
    return not blank
  elseif op == 'error' then
    return formula.is_error (v)
  end
  local text, want = lower (shown or ''), lower (a or '')
  if op == 'contains' then
    return string.find (text, want, 1, true) ~= nil
  elseif op == 'not_contains' then
    return string.find (text, want, 1, true) == nil
  elseif op == 'starts' then
    return string.sub (text, 1, #want) == want
  elseif op == 'ends' then
    return want == '' or string.sub (text, -#want) == want
  elseif op == 'equals' then
    return text == want
  end
  local x = operand (a)
  if op == 'between' or op == 'not_between' then
    local y = operand (b)
    local lo, hi = compare (v, x), compare (v, y)
    if blank or not lo or not hi then
      return op == 'not_between'
    end
    local low, high = x, y
    if compare (x, y) == 1 then
      low, high = y, x
    end
    local inside_range = (compare (v, low) or -1) >= 0
      and (compare (v, high) or 1) <= 0
    if op == 'between' then
      return inside_range
    end
    return not inside_range
  end
  if blank then
    return op == '<>' and x ~= nil
  end
  local c = compare (v, x)
  if op == '=' then
    return c == 0
  elseif op == '<>' then
    return c ~= 0
  elseif c == nil then
    return false
  elseif op == '>' then
    return c > 0
  elseif op == '<' then
    return c < 0
  elseif op == '>=' then
    return c >= 0
  elseif op == '<=' then
    return c <= 0
  end
  return false
end

---Whether a cell passes one column test of a filter.
---@param row integer
---@param col integer
---@param test Sheet.FilterColumn
---@param set? table<string, boolean> The test's values as a set.
---@return boolean
function Sheet:passes (row, col, test, set)
  local shown = self:display (row, col)
  if set and not set[shown] then
    return false
  end
  if test.op then
    return M.matches (
      self:value (row, col),
      shown,
      test.op,
      test.value,
      test.value2
    )
  end
  return true
end

---The rows below the header of a filter that its tests hide.
---@param filter Sheet.LiveFilter
---@return table<integer, boolean>
function Sheet:hidden_by (filter)
  self.book:ensure ()
  local hidden = {} ---@type table<integer, boolean>
  local tests = {} ---@type { col: integer, test: Sheet.FilterColumn, set?: table<string, boolean> }[]
  for col, test in pairs (filter.columns) do
    local set = nil ---@type table<string, boolean>?
    if test.values then
      set = {}
      for _, v in ipairs (test.values) do
        set[v] = true
      end
    end
    tests[#tests + 1] = { col = col, test = test, set = set }
  end
  if #tests == 0 then
    return hidden
  end
  for row = filter.rect.r1 + 1, filter.rect.r2 do
    for _, t in ipairs (tests) do
      if not self:passes (row, t.col, t.test, t.set) then
        hidden[row] = true
        break
      end
    end
  end
  return hidden
end

---Works out the rows the filter hides again, without an undo step. Loading calls this.
function Sheet:refilter ()
  local f = self.filter
  if f then
    f.hidden = self:hidden_by (f)
    self.book:rows_changed ()
  end
end

---------------------------------------------------------------------------------------------
-- The file, through the book
---------------------------------------------------------------------------------------------

---The sheet's whole book as plain data, the shape of a `.sheet.json` file.
---@param sheet Sheet.Sheet
---@return Sheet.BookData
function M.to_data (sheet)
  return books ().to_data (sheet.book)
end

---Makes a book from decoded file data, version 1 or 2, and returns its active sheet.
---@param data any
---@param opts? Sheet.Options
---@return Sheet.Sheet
function M.from_data (data, opts)
  return books ().from_data (data, opts):active_sheet ()
end

---Writes the sheet's whole book as the text of its `.sheet.json` file.
---@param sheet Sheet.Sheet
---@return string
function M.encode (sheet)
  return books ().encode (sheet.book)
end

---The example workbook written on first start. Returns its budget sheet.
---@param opts? Sheet.Options
---@return Sheet.Sheet
function M.example (opts)
  return books ().example (opts):active_sheet ()
end

---------------------------------------------------------------------------------------------
-- Parts
---------------------------------------------------------------------------------------------

---What the parts of the model get from this module. Each part returns a function that takes
---the kit and adds its methods to every sheet and its functions to the module.
---@class Sheet.ModelKit
local kit = {
  Sheet = Sheet,
  M = M,
  KEY = KEY,
  tidy = tidy,
  with_bold = with_bold,
  cell_patch = cell_patch,
  full_patch = full_patch,
  intern = intern,
  make_cell = make_cell,
  MIN_WIDTH = MIN_WIDTH,
  MAX_WIDTH = MAX_WIDTH,
  MIN_HEIGHT = MIN_HEIGHT,
  MAX_HEIGHT = MAX_HEIGHT,
}
for _, name in ipairs ({ 'sheet_model_clip', 'sheet_model_data' }) do
  local add = require (name) --[[@as fun(kit: Sheet.ModelKit)]]
  add (kit)
end

return M
