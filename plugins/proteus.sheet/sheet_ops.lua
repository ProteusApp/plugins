-- sheet_ops: data operations over a sheet or a workbook. Sort, filter, find and replace, the
-- fill handle's series, conditional formatting, validation, charts, Excel and CSV files, and
-- the cells that auto-fit measures. Every change goes through the sheet, so each operation is
-- one undo step. The module draws nothing and calls no host function.

local books = require ('sheet_book') --[[@as Sheet.BookModule]]
local chart = require ('sheet_chart') --[[@as Sheet.ChartModule]]
local format = require ('sheet_format') --[[@as Sheet.FormatModule]]
local formula = require ('sheet_formula') --[[@as Sheet.FormulaModule]]
local model = require ('sheet_model') --[[@as Sheet.ModelModule]]
local xlsx = require ('sheet_xlsx') --[[@as Sheet.XlsxModule]]

---One key of a sort: the column to sort rows by, or with `across`, the row to sort columns by.
---@class Sheet.SortKey
---@field col? integer
---@field row? integer
---@field desc? boolean

---@class Sheet.SortOptions
---@field header? boolean True when the first row, or column with `across`, holds headers.
---@field across? boolean Sorts columns left to right by the values in rows.

---@class Sheet.FindOptions
---@field case? boolean Match case.
---@field whole? boolean The whole cell must match.
---@field formulas? boolean Look in the text as typed, formulas included, rather than the shown values.
---@field sheet? Sheet.Sheet Look in one sheet only. Nil looks in the whole book.

---A cell that matches a search.
---@class Sheet.Match
---@field sheet Sheet.Sheet
---@field index integer The sheet's place in the book.
---@field row integer
---@field col integer

---@class Sheet.FillOptions
---@field series? boolean A single number counts up instead of repeating.

---One distinct value of a filter column, for the filter menu.
---@class Sheet.FilterValue
---@field text string The shown text. An empty cell is `''`.
---@field count integer How many rows show it.
---@field shown boolean True when the column's values keep it shown.

---What conditional formatting adds to one drawn cell.
---@class Sheet.RuleLook
---@field style? Sheet.Style The fields the matching rules set, the rule higher in the list winning.
---@field fill? string A colour scale's colour.
---@field bar? number A data bar's width, from 0 to 1.
---@field bar_color? string
---@field icon? string An icon set's icon, a character.
---@field icon_color? string

---What the grid needs to draw one cell.
---@class Sheet.Look
---@field text string
---@field color? string The text colour: a format section's, or the style's.
---@field style Sheet.Style The cell's style with the rules' styles laid over it.
---@field fill? string The background: a colour scale's, or the style's.
---@field align 'left'|'center'|'right'
---@field kind 'empty'|'number'|'text'|'bool'|'error'
---@field bar? number
---@field bar_color? string
---@field icon? string
---@field icon_color? string
---@field merge? Sheet.Rect Set on the top left cell of a merged block.
---@field covered? boolean True when a merged block covers this cell and it does not show.
---@field note? boolean
---@field list? boolean True when the cell has a dropdown list.

---A cell for auto-fit to measure.
---@class Sheet.FitCell
---@field row integer
---@field text string The shown text.
---@field style Sheet.Style

---What conditional formatting works out once per recalculation for one rule.
---@class Sheet.RulePrep
---@field rect? Sheet.Rect
---@field counts? table<string, integer>
---@field limit? number
---@field average? number
---@field min? number
---@field max? number
---@field mid? number
---@field ast? Sheet.Node

---@class Sheet.RuleCache
---@field stamp integer
---@field rules Sheet.Rule[]
---@field preps table<integer, Sheet.RulePrep>

---@class Sheet.OpsModule
local M = {}

local KEY = model.KEY

---------------------------------------------------------------------------------------------
-- Shared helpers
---------------------------------------------------------------------------------------------

---@param rect Sheet.Rect
---@param row integer
---@param col integer
---@return boolean
local function holds (rect, row, col)
  return row >= rect.r1 and row <= rect.r2 and col >= rect.c1 and col <= rect.c2
end

-- Rules, validation and charts name few distinct ranges, so this stays small.
local ranges = {} ---@type table<string, Sheet.Rect|false>

---The block a range text names, read once and kept, since drawing asks for the same ranges
---for every cell. Never change the block it returns.
---@param text any
---@return Sheet.Rect?
local function rect_of (text)
  if type (text) ~= 'string' then
    return nil
  end
  local hit = ranges[text]
  if hit == nil then
    hit = model.parse_range (text) or false
    ranges[text] = hit
  end
  return hit or nil
end

---A list with one item replaced, added or removed, as a new list.
---@param list table[]
---@param index integer
---@param item? table
---@return table[]
local function with_item (list, index, item)
  local out = {} ---@type table[]
  for i, v in ipairs (list) do
    if i == index then
      if item then
        out[#out + 1] = item
      end
    else
      out[#out + 1] = v
    end
  end
  if index > #list and item then
    out[#out + 1] = item
  end
  return out
end

---@param t table
---@return table
local function shallow (t)
  local out = {} ---@type table<any, any>
  for k, v in
    pairs (t --[[@as table<any, any>]])
  do
    out[k] = v
  end
  return out
end

---------------------------------------------------------------------------------------------
-- Sort
---------------------------------------------------------------------------------------------

---A filter with other columns, and its hidden rows worked out.
---@param sheet Sheet.Sheet
---@param rect Sheet.Rect
---@param columns table<integer, Sheet.FilterColumn>
---@return Sheet.LiveFilter
local function filter_with (sheet, rect, columns)
  ---@type Sheet.LiveFilter
  local filter = { rect = rect, columns = columns, hidden = {} }
  filter.hidden = sheet:hidden_by (filter)
  return filter
end

---Where a value sorts: numbers, then text, then TRUE and FALSE, then errors, then blanks.
---@param v Sheet.Value
---@return integer
local function rank (v)
  local t = type (v)
  if v == nil or v == '' then
    return 5
  elseif t == 'number' then
    return 1
  elseif t == 'string' then
    return 2
  elseif t == 'boolean' then
    return 3
  end
  return 4
end

---Compares two values for a sort: -1, 0 or 1. Text ignores case.
---@param a Sheet.Value
---@param b Sheet.Value
---@return integer
local function order (a, b)
  local ra, rb = rank (a), rank (b)
  if ra ~= rb then
    return ra < rb and -1 or 1
  end
  if ra == 1 then
    local x, y =
      a, --[[@as number]]
      b --[[@as number]]
    return x < y and -1 or (x > y and 1 or 0)
  elseif ra == 2 then
    local x = string.lower (a --[[@as string]])
    local y = string.lower (b --[[@as string]])
    return x < y and -1 or (x > y and 1 or 0)
  elseif ra == 3 then
    if a == b then
      return 0
    end
    return a and 1 or -1
  end
  return 0
end

---A key that makes equal values equal, text ignoring case.
---@param v Sheet.Value
---@return string?
local function value_key (v)
  local t = type (v)
  if v == nil or v == '' then
    return nil
  elseif t == 'number' then
    return 'n' .. model.number_text (v --[[@as number]])
  elseif t == 'string' then
    return 's' .. string.lower (v --[[@as string]])
  elseif t == 'boolean' then
    return v and 'bT' or 'bF'
  end
  return 'e' .. (v --[[@as Sheet.Error]]).code
end

---Sorts a block by one or more keys, as one undo step. Rows move with their styles, heights
---and notes, and formulas in them move their references by the distance moved, as a copy
---does. Blanks go last in either direction, and rows that compare equal keep their order.
---With `opts.across`, columns move instead, by the values in the rows the keys name. Returns
---false and the reason when a merged block is in the way.
---@param sheet Sheet.Sheet
---@param rect Sheet.Rect
---@param keys Sheet.SortKey[]
---@param opts? Sheet.SortOptions
---@return boolean
---@return string? problem
function M.sort (sheet, rect, keys, opts)
  local o = opts or {}
  local r = model.tidy (rect)
  local across = o.across == true
  local first = across and r.c1 or r.r1
  local last = across and r.c2 or r.r2
  if o.header then
    first = first + 1
  end
  if first >= last or #keys == 0 then
    return true, nil
  end
  local data = across and { r1 = r.r1, c1 = first, r2 = r.r2, c2 = last }
    or { r1 = first, c1 = r.c1, r2 = last, c2 = r.c2 }
  for _, m in ipairs (sheet.merges) do
    if model.overlaps (m, data) then
      return false, 'Unmerge the cells in the block before sorting it.'
    end
  end
  sheet.book:ensure ()
  ---@type { pos: integer, values: Sheet.Value[] }[]
  local items = {}
  for pos = first, last do
    local values = {} ---@type Sheet.Value[]
    for i, key in ipairs (keys) do
      if across then
        values[i] = sheet:value (key.row or r.r1, pos)
      else
        values[i] = sheet:value (pos, key.col or r.c1)
      end
    end
    items[#items + 1] = { pos = pos, values = values }
  end
  table.sort (items, function (a, b)
    for i, key in ipairs (keys) do
      local x, y = a.values[i], b.values[i]
      local c = order (x, y)
      if c ~= 0 then
        -- Blanks stay last when the order turns round.
        if key.desc and rank (x) ~= 5 and rank (y) ~= 5 then
          return c > 0
        end
        return c < 0
      end
    end
    return a.pos < b.pos
  end)
  local moved = false
  for i, item in ipairs (items) do
    if item.pos ~= first + i - 1 then
      moved = true
    end
  end
  if not moved then
    return true, nil
  end
  -- Read every source before writing, since sources and targets are the same cells.
  ---@type table<integer, { text: string, style: Sheet.Style }>
  local states = {}
  local notes = {} ---@type table<integer, string>
  local lo, hi = r.c1, r.c2
  if across then
    lo, hi = r.r1, r.r2
  end
  for pos = first, last do
    for k = lo, hi do
      local row, col = pos, k
      if across then
        row, col = k, pos
      end
      local key = row * KEY + col
      states[key] =
        { text = sheet:text (row, col), style = sheet:style_at (row, col) }
      notes[key] = sheet:note (row, col)
    end
  end
  local sizes = across and sheet.widths or sheet.heights
  local size_of = {} ---@type table<integer, number|false>
  for pos = first, last do
    size_of[pos] = sizes[pos] or false
  end
  local whole = across and (r.r1 == 1 and r.r2 >= sheet.rows)
    or (r.c1 == 1 and r.c2 >= sheet.cols)
  local line_styles = across and sheet.col_styles or sheet.row_styles
  local line_of = {} ---@type table<integer, Sheet.Style|false>
  for pos = first, last do
    line_of[pos] = line_styles[pos] or false
  end
  sheet:begin ({ select = r, label = 'Sort' })
  for i, item in ipairs (items) do
    local to, from = first + i - 1, item.pos
    if to ~= from then
      if whole then
        sheet:set_prop (
          across and 'col_styles' or 'row_styles',
          to,
          line_of[from] or nil
        )
      end
      sheet:set_prop (across and 'widths' or 'heights', to, size_of[from] or nil)
    end
  end
  for i, item in ipairs (items) do
    local to, from = first + i - 1, item.pos
    if to ~= from then
      for k = lo, hi do
        local src_row, src_col, row, col = from, k, to, k
        if across then
          src_row, src_col, row, col = k, from, k, to
        end
        local state = states[src_row * KEY + src_col]
        sheet:record (row, col, {
          text = formula.shift (state.text, row - src_row, col - src_col),
          style = sheet:own_for (row, col, state.style),
        })
        sheet:set_prop ('notes', row * KEY + col, notes[src_row * KEY + src_col])
      end
    end
  end
  -- The rows a filter hides moved with the sort, so the filter works them out again.
  local f = sheet.filter
  if f and model.overlaps (f.rect, data) then
    sheet:set_field ('filter', filter_with (sheet, f.rect, f.columns))
  end
  sheet:finish ()
  return true, nil
end

---Removes the rows of a block whose values in `opts.cols` repeat an earlier row's, text
---ignoring case, as one undo step. Empty rows stay. The rows that stay move up inside the
---block, and the rows freed at its bottom are emptied. Styles stay where they are, as in other
---spreadsheets. `opts.cols` is every column of the block when nil, and `opts.header` keeps
---the first row out. Returns how many rows went, or false and the reason when a merge is in
---the way.
---@param sheet Sheet.Sheet
---@param rect Sheet.Rect
---@param opts? { cols?: integer[], header?: boolean }
---@return integer|false removed
---@return string? problem
function M.remove_duplicates (sheet, rect, opts)
  local o = opts or {}
  local r = model.tidy (rect)
  local first = o.header and r.r1 + 1 or r.r1
  if first > r.r2 then
    return 0, nil
  end
  local data = { r1 = first, c1 = r.c1, r2 = r.r2, c2 = r.c2 }
  for _, m in ipairs (sheet.merges) do
    if model.overlaps (m, data) then
      return false, 'Unmerge the cells in the block before removing duplicates.'
    end
  end
  local cols = o.cols
  if not cols or #cols == 0 then
    cols = {}
    for c = r.c1, r.c2 do
      cols[#cols + 1] = c
    end
  end
  sheet.book:ensure ()
  local seen = {} ---@type table<string, boolean>
  local keep = {} ---@type integer[]
  for row = first, r.r2 do
    local parts = {} ---@type string[]
    local blank = true
    for i, c in ipairs (cols) do
      parts[i] = value_key (sheet:value (row, c)) or ''
      blank = blank and parts[i] == ''
    end
    local key = table.concat (parts, '\0')
    -- Empty rows are gaps, not data, so they never count as repeats.
    if blank then
      keep[#keep + 1] = row
    elseif not seen[key] then
      seen[key] = true
      keep[#keep + 1] = row
    end
  end
  local removed = r.r2 - first + 1 - #keep
  if removed == 0 then
    return 0, nil
  end
  -- Read every source before writing, since the rows that stay move onto rows being read.
  local texts = {} ---@type table<integer, string>
  local notes = {} ---@type table<integer, string>
  for row = first, r.r2 do
    for c = r.c1, r.c2 do
      texts[row * KEY + c] = sheet:text (row, c)
      notes[row * KEY + c] = sheet:note (row, c)
    end
  end
  sheet:begin ({ select = r, label = 'Remove duplicates' })
  for i = 1, r.r2 - first + 1 do
    local to, from = first + i - 1, keep[i]
    if from ~= to then
      for c = r.c1, r.c2 do
        local text, note = '', nil ---@type string, string?
        if from then
          text = formula.shift (texts[from * KEY + c], to - from, 0)
          note = notes[from * KEY + c]
        end
        sheet:record (to, c, { text = text, style = sheet:own_style (to, c) })
        sheet:set_prop ('notes', to * KEY + c, note)
      end
    end
  end
  sheet:finish ()
  return removed, nil
end

---------------------------------------------------------------------------------------------
-- Filter
---------------------------------------------------------------------------------------------

---Turns a filter on for a block, with its first row as the header, as one undo step. It
---replaces any filter the sheet had. Every row shows until a column gets a test.
---@param sheet Sheet.Sheet
---@param rect Sheet.Rect
---@return Sheet.LiveFilter
function M.set_filter (sheet, rect)
  ---@type Sheet.LiveFilter
  local filter = { rect = model.tidy (rect), columns = {}, hidden = {} }
  sheet:begin ({ select = filter.rect, label = 'Filter' })
  sheet:set_field ('filter', filter)
  sheet:finish ()
  return filter
end

---Turns a filter on for the data region around a cell, the way a spreadsheet picks the block
---when one cell is selected.
---@param sheet Sheet.Sheet
---@param row integer
---@param col integer
---@return Sheet.LiveFilter
function M.filter_around (sheet, row, col)
  return M.set_filter (sheet, sheet:region (row, col))
end

---Turns the filter off, showing every row, as one undo step.
---@param sheet Sheet.Sheet
function M.remove_filter (sheet)
  if sheet.filter then
    sheet:begin ({ label = 'Remove filter' })
    sheet:set_field ('filter', nil)
    sheet:finish ()
  end
end

---Sets the test of one filter column, or clears it when `test` is nil, and hides the rows
---that fail, as one undo step. Returns false when the sheet has no filter or the column is
---outside it.
---@param sheet Sheet.Sheet
---@param col integer
---@param test? Sheet.FilterColumn
---@return boolean
function M.filter_column (sheet, col, test)
  local f = sheet.filter
  if not f or col < f.rect.c1 or col > f.rect.c2 then
    return false
  end
  local columns = shallow (f.columns) --[[@as table<integer, Sheet.FilterColumn>]]
  if test and (test.values or test.op) then
    columns[col] = test
  else
    columns[col] = nil
  end
  sheet:begin ({ select = f.rect, label = 'Filter' })
  sheet:set_field ('filter', filter_with (sheet, f.rect, columns))
  sheet:finish ()
  return true
end

---Clears every column test, showing every row, and keeps the filter on. One undo step.
---@param sheet Sheet.Sheet
function M.clear_filter (sheet)
  local f = sheet.filter
  if f and next (f.columns) then
    sheet:begin ({ select = f.rect, label = 'Clear filter' })
    sheet:set_field ('filter', { rect = f.rect, columns = {}, hidden = {} })
    sheet:finish ()
  end
end

---Works out the hidden rows again from the values now, as one undo step when they change. A
---filter does not follow edits by itself, as in spreadsheets.
---@param sheet Sheet.Sheet
---@return boolean changed
function M.reapply_filter (sheet)
  local f = sheet.filter
  if not f then
    return false
  end
  local next_filter = filter_with (sheet, f.rect, f.columns)
  local same = true
  for row in pairs (next_filter.hidden) do
    if not f.hidden[row] then
      same = false
    end
  end
  for row in pairs (f.hidden) do
    if not next_filter.hidden[row] then
      same = false
    end
  end
  if same then
    return false
  end
  sheet:begin ({ select = f.rect, label = 'Reapply filter' })
  sheet:set_field ('filter', next_filter)
  sheet:finish ()
  return true
end

---The distinct shown values of a filter column, with how many rows show each, for the filter
---menu. Rows the other columns hide are left out, as spreadsheets do. Numbers come first in
---order, then text, then the rest, and an empty cell last as `''`.
---@param sheet Sheet.Sheet
---@param col integer
---@return Sheet.FilterValue[]
function M.filter_values (sheet, col)
  local f = sheet.filter
  if not f then
    return {}
  end
  local others = shallow (f.columns) --[[@as table<integer, Sheet.FilterColumn>]]
  others[col] = nil
  local hidden =
    sheet:hidden_by ({ rect = f.rect, columns = others, hidden = {} })
  local own = f.columns[col]
  local keep = nil ---@type table<string, boolean>?
  if own and own.values then
    keep = {}
    for _, v in ipairs (own.values) do
      keep[v] = true
    end
  end
  local counts = {} ---@type table<string, integer>
  local values = {} ---@type table<string, Sheet.Value>
  local list = {} ---@type string[]
  for row = f.rect.r1 + 1, f.rect.r2 do
    if not hidden[row] then
      local text = sheet:display (row, col)
      if not counts[text] then
        counts[text] = 0
        values[text] = sheet:value (row, col)
        list[#list + 1] = text
      end
      counts[text] = counts[text] + 1
    end
  end
  table.sort (list, function (a, b)
    local c = order (values[a], values[b])
    if c ~= 0 then
      return c < 0
    end
    return a < b
  end)
  local out = {} ---@type Sheet.FilterValue[]
  for i, text in ipairs (list) do
    out[i] = {
      text = text,
      count = counts[text],
      shown = keep == nil or keep[text] == true,
    }
  end
  return out
end

---------------------------------------------------------------------------------------------
-- Find and replace
---------------------------------------------------------------------------------------------

---Every place `query` sits in `text`, as literal text, ignoring case unless asked.
---@param text string
---@param query string
---@param case boolean
---@return integer[]
local function positions (text, query, case)
  local hay, needle = text, query
  if not case then
    hay, needle = string.lower (text), string.lower (query)
  end
  local out = {} ---@type integer[]
  if needle == '' then
    return out
  end
  local from = 1
  while true do
    local s = string.find (hay, needle, from, true)
    if not s then
      return out
    end
    out[#out + 1] = s
    from = s + #needle
  end
end

---True when a cell matches a search.
---@param sheet Sheet.Sheet
---@param cell Sheet.Cell
---@param query string
---@param opts Sheet.FindOptions
---@return boolean
local function matches (sheet, cell, query, opts)
  local hay = cell.text
  if not opts.formulas then
    hay = sheet:display (cell.row, cell.col)
  end
  if hay == '' then
    return false
  end
  if opts.whole then
    if opts.case then
      return hay == query
    end
    return string.lower (hay) == string.lower (query)
  end
  return #positions (hay, query, opts.case == true) > 0
end

---Every cell that matches a search, in order: sheet by sheet, then row by row. The search is
---literal text, ignoring case unless `opts.case`.
---@param book Sheet.Book
---@param query string
---@param opts? Sheet.FindOptions
---@return Sheet.Match[]
function M.find_all (book, query, opts)
  local o = opts or {}
  local out = {} ---@type Sheet.Match[]
  if query == '' then
    return out
  end
  book:ensure ()
  for index, sheet in ipairs (book.sheets) do
    if not o.sheet or o.sheet == sheet then
      local found = {} ---@type Sheet.Cell[]
      for _, cell in pairs (sheet.cells) do
        if cell.text ~= '' and matches (sheet, cell, query, o) then
          found[#found + 1] = cell
        end
      end
      table.sort (found, function (a, b)
        if a.row ~= b.row then
          return a.row < b.row
        end
        return a.col < b.col
      end)
      for _, cell in ipairs (found) do
        out[#out + 1] =
          { sheet = sheet, index = index, row = cell.row, col = cell.col }
      end
    end
  end
  return out
end

---The next match after a cell, or before it with `back`, going round to the start. Nil when
---nothing matches.
---@param book Sheet.Book
---@param query string
---@param from Sheet.Position
---@param opts? Sheet.FindOptions
---@param back? boolean
---@return Sheet.Match?
function M.find_next (book, query, from, opts, back)
  local list = M.find_all (book, query, opts)
  if #list == 0 then
    return nil
  end
  local index = book:index_of (from.sheet) or 1
  ---@param m Sheet.Match
  ---@return integer
  local function cmp (m)
    if m.index ~= index then
      return m.index < index and -1 or 1
    end
    if m.row ~= from.row then
      return m.row < from.row and -1 or 1
    end
    if m.col ~= from.col then
      return m.col < from.col and -1 or 1
    end
    return 0
  end
  if back then
    for i = #list, 1, -1 do
      if cmp (list[i]) < 0 then
        return list[i]
      end
    end
    return list[#list]
  end
  for _, m in ipairs (list) do
    if cmp (m) > 0 then
      return m
    end
  end
  return list[1]
end

---The text of a cell with every match of `query` replaced, and how many there were.
---@param text string
---@param query string
---@param with string
---@param opts Sheet.FindOptions
---@return string
---@return integer
local function replaced (text, query, with, opts)
  if opts.whole then
    local same = opts.case and text == query
      or (not opts.case and string.lower (text) == string.lower (query))
    if same then
      return with, 1
    end
    return text, 0
  end
  local found = positions (text, query, opts.case == true)
  if #found == 0 then
    return text, 0
  end
  local parts = {} ---@type string[]
  local pos = 1
  for _, s in ipairs (found) do
    parts[#parts + 1] = string.sub (text, pos, s - 1)
    parts[#parts + 1] = with
    pos = s + #query
  end
  parts[#parts + 1] = string.sub (text, pos)
  return table.concat (parts), #found
end

---Replaces the matches in one cell's text. Formulas change only when `opts.formulas` is set.
---@param sheet Sheet.Sheet
---@param row integer
---@param col integer
---@param query string
---@param with string
---@param opts Sheet.FindOptions
---@return boolean
local function replace_cell (sheet, row, col, query, with, opts)
  local cell = sheet:cell (row, col)
  if not cell or (cell.formula and not opts.formulas) then
    return false
  end
  local text, n = replaced (cell.text, query, with, opts)
  if n == 0 then
    return false
  end
  sheet:set (row, col, text)
  return true
end

---Replaces the matches in the cell of one match, as one undo step. The cell's text changes,
---and it reads again as if typed. A formula changes only when `opts.formulas` is set.
---Returns whether anything changed.
---@param book Sheet.Book
---@param match Sheet.Match
---@param query string
---@param with string
---@param opts? Sheet.FindOptions
---@return boolean
function M.replace (book, match, query, with, opts)
  local o = opts or {}
  book:begin ({
    sheet = match.sheet,
    select = { r1 = match.row, c1 = match.col, r2 = match.row, c2 = match.col },
    label = 'Replace',
  })
  local done = replace_cell (match.sheet, match.row, match.col, query, with, o)
  book:finish ()
  return done
end

---Replaces every match in the book, or in `opts.sheet`, as one undo step. Returns how many
---cells changed.
---@param book Sheet.Book
---@param query string
---@param with string
---@param opts? Sheet.FindOptions
---@return integer
function M.replace_all (book, query, with, opts)
  local o = shallow (opts or {}) --[[@as Sheet.FindOptions]]
  local list = M.find_all (book, query, {
    case = o.case,
    whole = o.whole,
    formulas = true,
    sheet = o.sheet,
  })
  local count = 0
  book:begin ({ sheet = o.sheet, label = 'Replace all' })
  for _, match in ipairs (list) do
    if replace_cell (match.sheet, match.row, match.col, query, with, o) then
      count = count + 1
    end
  end
  book:finish ()
  return count
end

---------------------------------------------------------------------------------------------
-- Fill series
---------------------------------------------------------------------------------------------

local DAYS = {
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
}
local MONTHS = {
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
}

---A name in a list, full or short, in any case: its place, the list, whether it is short,
---and its case as `upper`, `lower` or `title`.
---@param text string
---@return integer? index
---@return string[]? list
---@return boolean short
---@return string case
local function name_of (text)
  local lower = string.lower (text)
  local case = 'title'
  if text == string.upper (text) and text ~= lower then
    case = 'upper'
  elseif text == lower then
    case = 'lower'
  end
  for _, list in ipairs ({ DAYS, MONTHS }) do
    for i, name in ipairs (list) do
      if lower == string.lower (name) then
        return i, list, false, case
      end
      if lower == string.lower (string.sub (name, 1, 3)) then
        return i, list, true, case
      end
    end
  end
  return nil, nil, false, case
end

---@param name string
---@param short boolean
---@param case string
---@return string
local function name_text (name, short, case)
  local out = short and string.sub (name, 1, 3) or name
  if case == 'upper' then
    return string.upper (out)
  elseif case == 'lower' then
    return string.lower (out)
  end
  return out
end

---The value at position `p` of a line that fits `ys` at positions 1 to n, by least squares.
---@param ys number[]
---@param p integer
---@return number
local function trend (ys, p)
  local n = #ys
  if n == 1 then
    return ys[1] + (p - 1)
  end
  local sx, sy, sxx, sxy = 0, 0, 0, 0
  for i, y in ipairs (ys) do
    sx, sy = sx + i, sy + y
    sxx, sxy = sxx + i * i, sxy + i * y
  end
  local b = (n * sxy - sx * sy) / (n * sxx - sx * sx)
  local a = (sy - b * sx) / n
  local v = a + b * p
  return tonumber (string.format ('%.15g', v)) or v
end

---A function that gives the text at any position of a series, from the texts at positions
---1 to n, or nil when the texts are not a series and should repeat.
---@param sheet Sheet.Sheet
---@param cells { row: integer, col: integer, text: string, value: Sheet.Value }[]
---@param opts Sheet.FillOptions
---@return (fun(p: integer): string)?
local function series_of (sheet, cells, opts)
  local n = #cells
  local numbers, dates, all_numbers = {}, true, true ---@type number[], boolean, boolean
  for i, c in ipairs (cells) do
    if formula.is_formula (c.text) or type (c.value) ~= 'number' then
      all_numbers = false
      break
    end
    numbers[i] = c.value --[[@as number]]
    local kind = format.kind (sheet:number_format (c.row, c.col))
    if kind ~= 'date' and kind ~= 'datetime' then
      dates = false
    end
  end
  if all_numbers then
    if n == 1 and not dates and not opts.series then
      return nil
    end
    return function (p)
      return model.number_text (trend (numbers, p))
    end
  end
  -- Day and month names keep going.
  local index, list, short, case = name_of (cells[1].text)
  if index and list then
    local steps = { index } ---@type integer[]
    for i = 2, n do
      local j, other = name_of (cells[i].text)
      if other ~= list then
        return nil
      end
      steps[i] = j --[[@as integer]]
    end
    local size = #list
    local step = n > 1 and (steps[2] - steps[1]) % size or 1
    return function (p)
      local k = (index - 1 + (p - 1) * step) % size + 1
      return name_text (list[k], short, case)
    end
  end
  -- Text that ends in a number counts up.
  local head, digits = string.match (cells[1].text, '^(.-)(%d+)$')
  if head and not formula.is_formula (cells[1].text) then
    local counts = {} ---@type number[]
    for i, c in ipairs (cells) do
      local h, d = string.match (c.text, '^(.-)(%d+)$')
      if h ~= head then
        return nil
      end
      counts[i] = tonumber (d) or 0
    end
    local width = #digits
    return function (p)
      local v = n == 1 and counts[1] + (p - 1) or trend (counts, p)
      local whole = math.max (0, math.floor (v + 0.5))
      return head .. string.format ('%0' .. width .. 'd', whole)
    end
  end
  return nil
end

---Continues the cells of `source` across the rest of `target`, the way the fill handle does,
---in any of the four directions. Each row or column continues on its own: numbers keep their
---step, dates their step in days, one date steps a day, day and month names go on, and text
---ending in a number counts up. A single number repeats unless `opts.series`. Anything else
---repeats, with formulas moved as a copy moves them, and styles copy along. One undo step.
---Returns the filled block, or nil when `target` does not reach past `source`.
---@param sheet Sheet.Sheet
---@param source Sheet.Rect
---@param target Sheet.Rect
---@param opts? Sheet.FillOptions
---@return Sheet.Rect?
function M.fill (sheet, source, target, opts)
  local o = opts or {}
  local s, t = model.tidy (source), model.tidy (target)
  local dir ---@type 'down'|'up'|'right'|'left'|nil
  if t.r2 > s.r2 then
    dir = 'down'
  elseif t.r1 < s.r1 then
    dir = 'up'
  elseif t.c2 > s.c2 then
    dir = 'right'
  elseif t.c1 < s.c1 then
    dir = 'left'
  end
  if not dir then
    return nil
  end
  sheet.book:ensure ()
  local vertical = dir == 'down' or dir == 'up'
  local lines_from, lines_to = s.c1, s.c2
  local n = s.r2 - s.r1 + 1
  if not vertical then
    lines_from, lines_to = s.r1, s.r2
    n = s.c2 - s.c1 + 1
  end
  ---@param line integer
  ---@param p integer
  ---@return integer row
  ---@return integer col
  local function place (line, p)
    if vertical then
      return s.r1 + p - 1, line
    end
    return line, s.c1 + p - 1
  end
  local first, last = n + 1, (vertical and t.r2 - s.r1 + 1 or t.c2 - s.c1 + 1)
  if dir == 'up' then
    first, last = t.r1 - s.r1 + 1, 0
  elseif dir == 'left' then
    first, last = t.c1 - s.c1 + 1, 0
  end
  sheet:begin ({ select = t, label = 'Fill' })
  for line = lines_from, lines_to do
    local cells = {} ---@type { row: integer, col: integer, text: string, value: Sheet.Value, style: Sheet.Style }[]
    for p = 1, n do
      local row, col = place (line, p)
      cells[p] = {
        row = row,
        col = col,
        text = sheet:text (row, col),
        value = sheet:value (row, col),
        style = sheet:style_at (row, col),
      }
    end
    local series = series_of (sheet, cells, o)
    for p = first, last do
      local row, col = place (line, p)
      local k = (p - 1) % n + 1
      local src = cells[k]
      local text ---@type string
      if series then
        text = series (p)
      else
        text = formula.shift (src.text, row - src.row, col - src.col)
      end
      sheet:record (row, col, {
        text = text,
        style = sheet:own_for (row, col, src.style),
      })
    end
  end
  sheet:finish ()
  return t
end

---------------------------------------------------------------------------------------------
-- Conditional formatting
---------------------------------------------------------------------------------------------

---@type table<Sheet.Sheet, Sheet.RuleCache>
local rule_caches = setmetatable ({}, { __mode = 'k' })
---@type table<string, Sheet.Node|false>
local rule_asts = setmetatable ({}, { __mode = 'v' })

---@param text string
---@return Sheet.Node?
local function rule_ast (text)
  local ast = rule_asts[text]
  if ast == nil then
    ast = formula.parse (text) or false
    rule_asts[text] = ast
  end
  return ast or nil
end

---The numbers in a block.
---@param sheet Sheet.Sheet
---@param rect Sheet.Rect
---@return number[]
local function numbers_in (sheet, rect)
  local out = {} ---@type number[]
  for _, cell in ipairs (sheet:cells_in (rect)) do
    if type (cell.value) == 'number' then
      out[#out + 1] = cell.value --[[@as number]]
    end
  end
  return out
end

---Works out what a rule needs across its whole range.
---@param sheet Sheet.Sheet
---@param rule Sheet.Rule
---@return Sheet.RulePrep
local function prepare (sheet, rule)
  local rect = rect_of (rule.range)
  ---@type Sheet.RulePrep
  local prep = { rect = rect }
  if not rect then
    return prep
  end
  local kind = rule.type
  if kind == 'duplicate' or kind == 'unique' then
    local counts = {} ---@type table<string, integer>
    for _, cell in ipairs (sheet:cells_in (rect)) do
      local key = value_key (cell.value)
      if key then
        counts[key] = (counts[key] or 0) + 1
      end
    end
    prep.counts = counts
  elseif kind == 'top' or kind == 'bottom' then
    local list = numbers_in (sheet, rect)
    table.sort (list, function (a, b)
      if kind == 'top' then
        return a > b
      end
      return a < b
    end)
    local count = math.floor (tonumber (rule.count) or 10)
    if rule.percent then
      count = math.floor (#list * count / 100)
    end
    count = math.max (1, math.min (count, #list))
    prep.limit = list[count]
  elseif kind == 'above_average' or kind == 'below_average' then
    local list = numbers_in (sheet, rect)
    if #list > 0 then
      local sum = 0
      for _, v in ipairs (list) do
        sum = sum + v
      end
      prep.average = sum / #list
    end
  elseif kind == 'scale' or kind == 'bar' or kind == 'icons' then
    local list = numbers_in (sheet, rect)
    table.sort (list)
    if #list > 0 then
      prep.min, prep.max = list[1], list[#list]
      local mid = (#list + 1) / 2
      prep.mid = (list[math.floor (mid)] + list[math.ceil (mid)]) / 2
    end
  elseif kind == 'formula' and type (rule.formula) == 'string' then
    prep.ast = rule_ast (rule.formula)
  end
  return prep
end

---@param hex string
---@return number r
---@return number g
---@return number b
local function rgb (hex)
  local r, g, b = string.match (hex or '', '^#?(%x%x)(%x%x)(%x%x)$')
  return tonumber (r or '0', 16) or 0,
    tonumber (g or '0', 16) or 0,
    tonumber (b or '0', 16) or 0
end

---The colour a fraction of the way from one colour to another.
---@param a string
---@param b string
---@param t number
---@return string
local function blend (a, b, t)
  local r1, g1, b1 = rgb (a)
  local r2, g2, b2 = rgb (b)
  ---@param x number
  ---@param y number
  ---@return integer
  local function mix (x, y)
    return math.floor (x + (y - x) * t + 0.5)
  end
  return string.format (
    '#%02x%02x%02x',
    mix (r1, r2),
    mix (g1, g2),
    mix (b1, b2)
  )
end

---The rules' work for a sheet, done again when anything in the book changed since.
---@param sheet Sheet.Sheet
---@return Sheet.RuleCache
local function cache_of (sheet)
  sheet.book:ensure ()
  local cache = rule_caches[sheet]
  if
    not cache
    or cache.stamp ~= sheet.book.stamp
    or cache.rules ~= sheet.rules
  then
    cache = { stamp = sheet.book.stamp, rules = sheet.rules, preps = {} }
    rule_caches[sheet] = cache
  end
  return cache
end

---True when a formula rule holds for a cell. The formula is written for the top left cell of
---the range, and moves for the others as a paste would.
---@param sheet Sheet.Sheet
---@param rule Sheet.Rule
---@param prep Sheet.RulePrep
---@param row integer
---@param col integer
---@return boolean
local function formula_holds (sheet, rule, prep, row, col)
  local rect = prep.rect --[[@as Sheet.Rect]]
  local ast = prep.ast
  if row ~= rect.r1 or col ~= rect.c1 then
    ast = rule_ast (
      formula.shift (rule.formula or '', row - rect.r1, col - rect.c1)
    )
  end
  if not ast then
    return false
  end
  local ctx = sheet.book:context (sheet)
  local saved_row, saved_col = ctx.row, ctx.col
  ctx.row, ctx.col, ctx.rows, ctx.cols = row, col, sheet.rows, sheet.cols
  local v = formula.evaluate (ast, ctx)
  ctx.row, ctx.col = saved_row, saved_col
  if type (v) == 'number' then
    return v ~= 0
  end
  return v == true
end

-- The icon sets, best first: a value in the top third of its range from the lowest to the
-- highest gets the first icon, the middle third the second, and the bottom third the last,
-- as Excel's three-icon sets do.
---@type table<string, { [1]: string, [2]: string }[]>
local ICON_SETS = {
  arrows = { { '▲', '#2b9348' }, { '▶', '#9a7d0a' }, { '▼', '#e03e3e' } },
  lights = { { '●', '#2b9348' }, { '●', '#d4a017' }, { '●', '#e03e3e' } },
  flags = { { '⚑', '#2b9348' }, { '⚑', '#d4a017' }, { '⚑', '#e03e3e' } },
}
M.ICON_SETS = ICON_SETS

---What the sheet's conditional formatting rules add to one cell: a style, a colour scale's
---fill, and a data bar's width. Nil when no rule touches the cell. The rules run in order of
---priority, first in the list first: the first to set a field wins, and a rule set to stop
---ends the run where it holds. The work a rule needs across its range, such as the top 10 or
---the average, is done once per recalculation.
---@param sheet Sheet.Sheet
---@param row integer
---@param col integer
---@return Sheet.RuleLook?
function M.rule_look (sheet, row, col)
  if #sheet.rules == 0 then
    return nil
  end
  local cache = cache_of (sheet)
  local out = nil ---@type Sheet.RuleLook?
  -- The styles of the rules that hold, first rule first. The first wins on a field, as in
  -- Excel, so they are laid down from the last.
  local styles = {} ---@type Sheet.Style[]
  for i, rule in ipairs (sheet.rules) do
    local prep = cache.preps[i]
    if not prep then
      prep = prepare (sheet, rule)
      cache.preps[i] = prep
    end
    local rect = prep.rect
    if rect and holds (rect, row, col) then
      local v = sheet:value (row, col)
      local kind = rule.type
      local hit = false
      if kind == 'compare' or kind == 'text' then
        hit = model.matches (
          v,
          (sheet:display (row, col)),
          rule.op or '=',
          rule.value,
          rule.value2
        )
      elseif kind == 'blank' or kind == 'not_blank' or kind == 'error' then
        hit = model.matches (v, '', kind)
      elseif kind == 'duplicate' or kind == 'unique' then
        local key = value_key (v)
        local count = key and (prep.counts or {})[key] or 0
        hit = key ~= nil
          and (
            (kind == 'duplicate' and count > 1)
            or (kind == 'unique' and count == 1)
          )
      elseif kind == 'top' or kind == 'bottom' then
        local limit = prep.limit
        if type (v) == 'number' and limit then
          hit = (kind == 'top' and v >= limit)
            or (kind == 'bottom' and v <= limit)
        end
      elseif kind == 'above_average' or kind == 'below_average' then
        local avg = prep.average
        if type (v) == 'number' and avg then
          hit = (kind == 'above_average' and v > avg)
            or (kind == 'below_average' and v < avg)
        end
      elseif kind == 'formula' then
        hit = formula_holds (sheet, rule, prep, row, col)
      elseif kind == 'scale' and type (v) == 'number' and prep.min then
        local lo, hi =
          prep.min, --[[@as number]]
          prep.max --[[@as number]]
        local low_color = rule.min_color or '#f8696b'
        local high_color = rule.max_color or '#63be7b'
        local fill ---@type string
        if hi == lo then
          fill = rule.mid_color or high_color
        elseif rule.mid_color then
          local mid = prep.mid --[[@as number]]
          if v <= mid then
            fill = blend (
              low_color,
              rule.mid_color,
              mid == lo and 1 or (v - lo) / (mid - lo)
            )
          else
            fill = blend (rule.mid_color, high_color, (v - mid) / (hi - mid))
          end
        else
          fill = blend (low_color, high_color, (v - lo) / (hi - lo))
        end
        out = out or {}
        out.fill = out.fill or fill
        hit = true
      elseif kind == 'bar' and type (v) == 'number' and prep.min then
        local lo = math.min (0, prep.min --[[@as number]])
        local hi = math.max (0, prep.max --[[@as number]])
        out = out or {}
        if not out.bar then
          out.bar = hi == lo and 0
            or math.max (0, math.min (1, (v - lo) / (hi - lo)))
          out.bar_color = rule.color or '#638ec6'
        end
        hit = true
      elseif kind == 'icons' and type (v) == 'number' and prep.min then
        local lo, hi =
          prep.min, --[[@as number]]
          prep.max --[[@as number]]
        local share = hi == lo and 1 or (v - lo) / (hi - lo)
        local slot = share >= 0.67 and 1 or share >= 0.33 and 2 or 3
        if rule.reverse then
          slot = 4 - slot
        end
        local set = ICON_SETS[rule.icons or 'arrows'] or ICON_SETS.arrows
        out = out or {}
        if not out.icon then
          out.icon, out.icon_color = set[slot][1], set[slot][2]
        end
        hit = true
      end
      if hit and rule.style then
        styles[#styles + 1] = model.intern (rule.style)
        out = out or {}
      end
      -- Stop if true: the rules after this one do not apply where it holds.
      if hit and rule.stop then
        break
      end
    end
  end
  if out then
    local style = nil ---@type Sheet.Style?
    for k = #styles, 1, -1 do
      style = model.layer (style, styles[k])
    end
    out.style = style and model.clean (style) or nil
  end
  return out
end

---Adds a conditional formatting rule at the top of the list, where it wins over the others,
---as one undo step.
---@param sheet Sheet.Sheet
---@param rule Sheet.Rule
function M.add_rule (sheet, rule)
  sheet:begin ({ label = 'Add rule' })
  local list = { shallow (rule) } ---@type Sheet.Rule[]
  for _, other in ipairs (sheet.rules) do
    list[#list + 1] = other
  end
  sheet:set_field ('rules', list)
  sheet:finish ()
end

---Replaces the rule at an index, or removes it when `rule` is nil, as one undo step.
---@param sheet Sheet.Sheet
---@param index integer
---@param rule? Sheet.Rule
function M.set_rule (sheet, index, rule)
  if not sheet.rules[index] then
    return
  end
  sheet:begin ({ label = rule and 'Change rule' or 'Delete rule' })
  sheet:set_field (
    'rules',
    with_item (sheet.rules, index, rule and shallow (rule)) --[[@as Sheet.Rule[] ]]
  )
  sheet:finish ()
end

---The indexes of the rules whose range holds a cell.
---@param sheet Sheet.Sheet
---@param row integer
---@param col integer
---@return integer[]
function M.rules_at (sheet, row, col)
  local out = {} ---@type integer[]
  for i, rule in ipairs (sheet.rules) do
    local rect = rect_of (rule.range)
    if rect and holds (rect, row, col) then
      out[#out + 1] = i
    end
  end
  return out
end

---------------------------------------------------------------------------------------------
-- Validation
---------------------------------------------------------------------------------------------

---The validation rule of a cell, the last one whose range holds it, and its index.
---@param sheet Sheet.Sheet
---@param row integer
---@param col integer
---@return Sheet.Validation?
---@return integer?
function M.validation_at (sheet, row, col)
  for i = #sheet.validation, 1, -1 do
    local v = sheet.validation[i]
    local rect = rect_of (v.range)
    if rect and holds (rect, row, col) then
      return v, i
    end
  end
  return nil, nil
end

local OP_WORDS = {
  ['>'] = 'greater than',
  ['<'] = 'less than',
  ['>='] = 'at least',
  ['<='] = 'at most',
  ['='] = 'equal to',
  ['<>'] = 'other than',
}

---The message a refused entry shows when the rule has none.
---@param v Sheet.Validation
---@param items string[] The items of a list.
---@return string
local function default_message (v, items)
  if v.type == 'list' then
    return 'Pick one of: ' .. table.concat (items, ', ') .. '.'
  elseif v.type == 'formula' then
    return 'The value breaks the rule ' .. (v.formula or '') .. '.'
  end
  local what = v.integer and 'a whole number' or 'a number'
  if v.type == 'date' then
    what = 'a date'
  elseif v.type == 'length' then
    what = 'text with a length'
  end
  if v.op == 'between' then
    return 'Enter '
      .. what
      .. ' from '
      .. (v.value or '')
      .. ' to '
      .. (v.value2 or '')
      .. '.'
  elseif v.op == 'not_between' then
    return 'Enter '
      .. what
      .. ' outside '
      .. (v.value or '')
      .. ' to '
      .. (v.value2 or '')
      .. '.'
  elseif v.op and OP_WORDS[v.op] then
    return 'Enter '
      .. what
      .. ' '
      .. OP_WORDS[v.op]
      .. ' '
      .. (v.value or '')
      .. '.'
  end
  return 'Enter ' .. what .. '.'
end

---The values a formula gives at a cell, when the formula is written for the top left cell of
---a range and moves for the others as a paste would, and how many. With `candidate`, the cell
---itself reads as that value, so a validation formula can test what is being typed.
---@param sheet Sheet.Sheet
---@param text string
---@param rect Sheet.Rect
---@param row integer
---@param col integer
---@param candidate? Sheet.Value
---@return Sheet.Values values
---@return integer count
local function values_at (sheet, text, rect, row, col, candidate)
  local ast = rule_ast (formula.shift (text, row - rect.r1, col - rect.c1))
  if not ast then
    return { formula.error ('#ERROR!') }, 1
  end
  local base = sheet.book:context (sheet)
  local ctx = setmetatable ({
    row = row,
    col = col,
    rows = sheet.rows,
    cols = sheet.cols,
    value = function (r, c, name)
      if candidate ~= nil and name == nil and r == row and c == col then
        return candidate
      end
      return base.value (r, c, name)
    end,
  }, { __index = base }) --[[@as Sheet.Context]]
  return formula.values (ast, ctx)
end

---The items of a validation list: the ones it holds, or the shown text of the cells its
---formula names, without blanks or repeats.
---@param sheet Sheet.Sheet
---@param v Sheet.Validation
---@param row integer
---@param col integer
---@return string[]
function M.list_items (sheet, v, row, col)
  if type (v.formula) ~= 'string' then
    return v.values or {}
  end
  local rect = rect_of (v.range)
  if not rect then
    return {}
  end
  local values, count = values_at (sheet, v.formula, rect, row, col)
  local out, seen = {}, {} ---@type string[], table<string, boolean>
  for k = 1, count do
    local x = values[k]
    if x ~= nil and not formula.is_error (x) then
      local shown = formula.format_value (x)
      if shown ~= '' and not seen[shown] then
        seen[shown] = true
        out[#out + 1] = shown
      end
    end
  end
  return out
end

---Whether a text may go into a cell. Returns true when it may. Otherwise returns false, the
---message to show, and whether the rule refuses the text (strict) or only warns. An empty
---text and a formula always pass.
---@param sheet Sheet.Sheet
---@param row integer
---@param col integer
---@param text string
---@return boolean
---@return string? message
---@return boolean? strict
function M.check_input (sheet, row, col, text)
  local v = M.validation_at (sheet, row, col)
  if not v or text == '' or formula.is_formula (text) then
    return true, nil, nil
  end
  local good = false
  local items = {} ---@type string[]
  local value = format.parse_input (text, sheet.book.clock)
  if v.type == 'list' then
    items = M.list_items (sheet, v, row, col)
    local want = string.lower (text)
    for _, item in ipairs (items) do
      if string.lower (item) == want then
        good = true
      end
    end
  elseif v.type == 'length' then
    local n = utf8.len (text) or #text
    good = not v.op or model.matches (n, text, v.op, v.value, v.value2)
  elseif v.type == 'formula' then
    local rect = rect_of (v.range)
    if rect and type (v.formula) == 'string' then
      local values, count = values_at (sheet, v.formula, rect, row, col, value)
      local result = values[1]
      good = count == 1
        and (result == true or (type (result) == 'number' and result ~= 0))
    end
  elseif type (value) == 'number' then
    -- A date is a number too, typed as a date.
    good = true
    if v.integer and v.type ~= 'date' and value ~= math.floor (value) then
      good = false
    end
    if good and v.op then
      good = model.matches (value, text, v.op, v.value, v.value2)
    end
  end
  if good then
    return true, nil, nil
  end
  return false, v.message or default_message (v, items), v.strict ~= false
end

---The choices of a cell's dropdown list, or nil when the cell has none.
---@param sheet Sheet.Sheet
---@param row integer
---@param col integer
---@return string[]?
function M.dropdown (sheet, row, col)
  local v = M.validation_at (sheet, row, col)
  if v and v.type == 'list' then
    return M.list_items (sheet, v, row, col)
  end
  return nil
end

---Adds a validation rule, as one undo step.
---@param sheet Sheet.Sheet
---@param rule Sheet.Validation
function M.add_validation (sheet, rule)
  sheet:begin ({ label = 'Add validation' })
  sheet:set_field (
    'validation',
    with_item (sheet.validation, #sheet.validation + 1, shallow (rule)) --[[@as Sheet.Validation[] ]]
  )
  sheet:finish ()
end

---Replaces the validation rule at an index, or removes it when `rule` is nil. One undo step.
---@param sheet Sheet.Sheet
---@param index integer
---@param rule? Sheet.Validation
function M.set_validation (sheet, index, rule)
  if not sheet.validation[index] then
    return
  end
  sheet:begin ({ label = rule and 'Change validation' or 'Delete validation' })
  sheet:set_field (
    'validation',
    with_item (sheet.validation, index, rule and shallow (rule)) --[[@as Sheet.Validation[] ]]
  )
  sheet:finish ()
end

---------------------------------------------------------------------------------------------
-- Charts
---------------------------------------------------------------------------------------------

---The values of a chart's range, rows top to bottom, ready for `sheet_chart.data_from`. Hidden
---rows and columns are left out, as spreadsheets leave them out of charts.
---@param sheet Sheet.Sheet
---@param spec Sheet.ChartSpec
---@return Sheet.Value[][]
function M.chart_values (sheet, spec)
  local rect = rect_of (spec.range)
  local out = {} ---@type Sheet.Value[][]
  if not rect then
    return out
  end
  sheet.book:ensure ()
  for row = rect.r1, rect.r2 do
    if not sheet:row_hidden (row) then
      local line = {} ---@type Sheet.Value[]
      local n = 0
      for col = rect.c1, rect.c2 do
        if not sheet:col_hidden (col) then
          n = n + 1
          line[n] = sheet:value (row, col)
        end
      end
      out[#out + 1] = line
    end
  end
  return out
end

---A function that shows a chart's numbers the way the cells show them, in the format of the
---last number in its range, which is a value rather than a category or a header.
---@param sheet Sheet.Sheet
---@param spec Sheet.ChartSpec
---@return fun(n: number): string
function M.chart_format (sheet, spec)
  local rect = rect_of (spec.range)
  local code = nil ---@type string?
  if rect then
    sheet.book:ensure ()
    local found = false
    for row = rect.r2, rect.r1, -1 do
      for col = rect.c2, rect.c1, -1 do
        if not found and type (sheet:value (row, col)) == 'number' then
          code = sheet:number_format (row, col)
          found = true
        end
      end
    end
  end
  return function (n)
    return (format.format (n, code))
  end
end

---A chart's categories and series from its range.
---@param sheet Sheet.Sheet
---@param spec Sheet.ChartSpec
---@return Sheet.ChartData
function M.chart_data (sheet, spec)
  return chart.data_from (M.chart_values (sheet, spec), {
    series_in = spec.series_in,
    headers = spec.headers,
  })
end

---A chart as SVG at its own size, with numbers in the cells' format.
---@param sheet Sheet.Sheet
---@param spec Sheet.ChartSpec
---@return string
function M.chart_svg (sheet, spec)
  return chart.render (spec, M.chart_data (sheet, spec), {
    width = spec.w,
    height = spec.h,
    format = M.chart_format (sheet, spec),
  })
end

---@param sheet Sheet.Sheet
---@param id string
---@return Sheet.ChartSpec?
---@return integer?
function M.chart_by_id (sheet, id)
  for i, spec in ipairs (sheet.charts) do
    if spec.id == id then
      return spec, i
    end
  end
  return nil, nil
end

---Adds a chart, as one undo step. It gets a free id, and a place and size when it has none.
---Returns the chart as the sheet keeps it.
---@param sheet Sheet.Sheet
---@param spec Sheet.ChartSpec
---@return Sheet.ChartSpec
function M.add_chart (sheet, spec)
  local copy = shallow (spec) --[[@as Sheet.ChartSpec]]
  local n = #sheet.charts + 1
  while M.chart_by_id (sheet, 'c' .. n) do
    n = n + 1
  end
  if type (copy.id) ~= 'string' or M.chart_by_id (sheet, copy.id) then
    copy.id = 'c' .. n
  end
  copy.type = copy.type or 'column'
  copy.x = tonumber (copy.x) or 40
  copy.y = tonumber (copy.y) or 40
  copy.w = tonumber (copy.w) or 480
  copy.h = tonumber (copy.h) or 300
  sheet:begin ({ label = 'Add chart' })
  sheet:set_field (
    'charts',
    with_item (sheet.charts, #sheet.charts + 1, copy) --[[@as Sheet.ChartSpec[] ]]
  )
  sheet:finish ()
  return copy
end

---Moves, resizes or changes a chart: every field in `patch` replaces the chart's own, and each
---field named in `clear` goes back to automatic, as one undo step. Returns false when there is
---no such chart.
---@param sheet Sheet.Sheet
---@param id string
---@param patch table<string, any>
---@param clear? string[]
---@return boolean
function M.update_chart (sheet, id, patch, clear)
  local spec, index = M.chart_by_id (sheet, id)
  if not spec or not index then
    return false
  end
  local copy = shallow (spec) --[[@as table<string, any>]]
  for k, v in pairs (patch) do
    if k ~= 'id' then
      copy[k] = v
    end
  end
  for _, k in ipairs (clear or {}) do
    if k ~= 'id' then
      copy[k] = nil
    end
  end
  sheet:begin ({ label = 'Change chart' })
  sheet:set_field (
    'charts',
    with_item (sheet.charts, index, copy) --[[@as Sheet.ChartSpec[] ]]
  )
  sheet:finish ()
  return true
end

---Deletes a chart, as one undo step. Returns false when there is no such chart.
---@param sheet Sheet.Sheet
---@param id string
---@return boolean
function M.delete_chart (sheet, id)
  local _, index = M.chart_by_id (sheet, id)
  if not index then
    return false
  end
  sheet:begin ({ label = 'Delete chart' })
  sheet:set_field (
    'charts',
    with_item (sheet.charts, index, nil) --[[@as Sheet.ChartSpec[] ]]
  )
  sheet:finish ()
  return true
end

---------------------------------------------------------------------------------------------
-- Excel and CSV
---------------------------------------------------------------------------------------------

---A book from the files of an `.xlsx` zip, each path mapped to its text. Returns the book and
---the warnings about what was left out, or nil and a message.
---@param files table<string, string>
---@param opts? Sheet.BookOptions
---@return Sheet.Book?
---@return string[]|string
function M.read_xlsx (files, opts)
  local data, warnings = xlsx.read (files)
  if not data then
    return nil, warnings
  end
  return books.from_data (data, opts), warnings
end

---The files of an `.xlsx` zip for a book, with the value of each formula, and the warnings
---about what was left out.
---@param book Sheet.Book
---@return table<string, string>
---@return string[]
function M.write_xlsx (book)
  book:ensure ()
  return xlsx.write (books.to_data (book), function (index, row, col)
    return book:value_at (index, row, col)
  end, function (index, row, col)
    local sheet = book.sheets[index]
    local cell = sheet and sheet.cells[row * model.KEY + col]
    local area = cell and cell.spill_area
    if not area then
      return nil, nil
    end
    return area.r2 - area.r1 + 1, area.c2 - area.c1 + 1
  end)
end

---Adds a sheet holding CSV text, each cell read as if typed, and shows it. The name is `name`
---when free, or a free one made from it. One undo step. Returns the sheet.
---@param book Sheet.Book
---@param text string
---@param name? string
---@param sep? string A comma when nil, or a tab.
---@return Sheet.Sheet
function M.import_csv (book, text, name, sep)
  local free = book:free_name ('Sheet')
  if name then
    local base = string.gsub (name, "[%[%]:%*%?/\\']", '')
    base = string.sub (base, 1, 90)
    if base == '' or string.match (base, '^%s*$') then
      base = 'Sheet'
    end
    free = book:name_problem (base) and book:free_name (base, true) or base
  end
  book:begin ({ label = 'Import CSV' })
  local sheet = assert (book:add_sheet (free, #book.sheets + 1))
  local rows = model.parse_csv (text, sep)
  for r, line in ipairs (rows) do
    for c, cell in ipairs (line) do
      if cell ~= '' then
        sheet:record (r, c, sheet:typed (r, c, cell))
      end
    end
  end
  book:finish ()
  return sheet
end

---Pastes CSV text with its top left cell at a cell, each cell read as if typed. One undo
---step. Returns the block that changed.
---@param sheet Sheet.Sheet
---@param row integer
---@param col integer
---@param text string
---@param sep? string
---@return Sheet.Rect?
function M.paste_csv (sheet, row, col, text, sep)
  return sheet:paste (
    row,
    col,
    { texts = model.parse_csv (text, sep), typed = true }
  )
end

---The shown values of a sheet, or of a block, as CSV text. Numbers with no format keep 15
---digits, so nothing is lost.
---@param sheet Sheet.Sheet
---@param rect? Sheet.Rect
---@param sep? string
---@return string
function M.export_csv (sheet, rect, sep)
  local rows = sheet:grid (rect, 15)
  if #rows == 0 then
    return ''
  end
  return model.to_csv (rows, sep or ',', '\r\n') .. '\r\n'
end

---------------------------------------------------------------------------------------------
-- Drawing and auto-fit
---------------------------------------------------------------------------------------------

---The cells of a column with their shown text and style, for auto-fit to measure. Empty
---cells, hidden rows and cells inside wider merged blocks are left out.
---@param sheet Sheet.Sheet
---@param col integer
---@return Sheet.FitCell[]
function M.column_cells (sheet, col)
  sheet.book:ensure ()
  local out = {} ---@type Sheet.FitCell[]
  for _, cell in pairs (sheet.cells) do
    if
      cell.col == col
      and cell.text ~= ''
      and not sheet:row_hidden (cell.row)
    then
      local m = sheet:merge_at (cell.row, col)
      if not m or m.c1 == m.c2 then
        out[#out + 1] = {
          row = cell.row,
          text = (sheet:display (cell.row, col)),
          style = sheet:style_at (cell.row, col),
        }
      end
    end
  end
  table.sort (out, function (a, b)
    return a.row < b.row
  end)
  return out
end

---Everything the grid needs to draw one cell: the shown text and its colour, the style with
---conditional formatting laid over it, the fill, the alignment, a data bar, whether a merge
---starts or covers it, and whether it has a note or a dropdown.
---@param sheet Sheet.Sheet
---@param row integer
---@param col integer
---@return Sheet.Look
function M.look (sheet, row, col)
  local text, color = sheet:display (row, col)
  local style = sheet:style_at (row, col)
  local extra = M.rule_look (sheet, row, col)
  if extra and extra.style then
    style = model.clean (model.layer (style, extra.style))
  end
  ---@type Sheet.Look
  local look = {
    text = text,
    color = color or style.color,
    style = style,
    fill = extra and extra.fill or style.fill,
    align = sheet:align (row, col),
    kind = sheet:kind (row, col),
    bar = extra and extra.bar,
    bar_color = extra and extra.bar_color,
    icon = extra and extra.icon,
    icon_color = extra and extra.icon_color,
    note = sheet:note (row, col) ~= nil or nil,
    list = M.dropdown (sheet, row, col) ~= nil or nil,
  }
  local m = sheet:merge_at (row, col)
  if m then
    if m.r1 == row and m.c1 == col then
      look.merge = m
    else
      look.covered = true
      look.text = ''
    end
  end
  return look
end

return M
