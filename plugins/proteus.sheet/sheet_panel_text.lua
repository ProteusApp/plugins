-- sheet_panel_text: the words and small choices behind the Sheet app's toolbar and panels.
--
-- It describes rules in a line of text, guesses the block a quick sum adds up, picks the
-- block a sort or a chart works on, and holds the lists the pop-ups offer. It draws nothing
-- and calls no host function, so the tests reach all of it.

local format = require ('sheet_format') --[[@as Sheet.FormatModule]]
local model = require ('sheet_model') --[[@as Sheet.ModelModule]]

---A condition a rule or a filter can test, as the forms list them.
---@class Sheet.Condition
---@field id string
---@field label string
---@field type string The rule type it makes.
---@field op? string
---@field percent? boolean
---@field input 'none'|'one'|'two'|'count'|'formula' The boxes the form shows for it.
---@field filter? boolean True when the filter menu offers it too.

---A choice in the number format menu, with a sample of what it shows.
---@class Sheet.FormatChoice
---@field id string
---@field label string
---@field code string
---@field example string

---A formula a quick sum types or puts in cells.
---@class Sheet.SumPlan
---@field text? string Text to type into the active cell.
---@field cells? { [1]: integer, [2]: integer, [3]: string }[] Cells to fill, as row, column and text.
---@field rect? Sheet.Rect The block the new formulas fill.
---@field busy? boolean True when a cell the formulas would fill holds text already.

---@class Sheet.PanelTextModule
local M = {}

M.SIZES = { 9, 10, 11, 12, 13, 14, 16, 18, 20, 22, 24, 28, 32, 36 }
M.DEFAULT_SIZE = 13
M.MIN_SIZE = 6
M.MAX_SIZE = 96

-- Five rows of ten: greys, strong colours, then three shades of each from light to dark.
M.COLORS = {
  '#000000',
  '#434343',
  '#666666',
  '#999999',
  '#b7b7b7',
  '#cccccc',
  '#d9d9d9',
  '#efefef',
  '#f3f3f3',
  '#ffffff',
  '#980000',
  '#ff0000',
  '#ff9900',
  '#ffff00',
  '#00ff00',
  '#00ffff',
  '#4a86e8',
  '#0000ff',
  '#9900ff',
  '#ff00ff',
  '#f4cccc',
  '#fce5cd',
  '#fff2cc',
  '#d9ead3',
  '#d0e0e3',
  '#c9daf8',
  '#cfe2f3',
  '#d9d2e9',
  '#ead1dc',
  '#e6b8af',
  '#ea9999',
  '#f9cb9c',
  '#ffe599',
  '#b6d7a8',
  '#a2c4c9',
  '#a4c2f4',
  '#9fc5e8',
  '#b4a7d6',
  '#d5a6bd',
  '#dd7e6b',
  '#cc0000',
  '#e69138',
  '#f1c232',
  '#6aa84f',
  '#45818e',
  '#3c78d8',
  '#3d85c6',
  '#674ea7',
  '#a64d79',
  '#85200c',
}
M.PALETTE_COLUMNS = 10

M.BORDER_COLORS = {
  '#000000',
  '#666666',
  '#b7b7b7',
  '#cc0000',
  '#e69138',
  '#f1c232',
  '#6aa84f',
  '#3c78d8',
  '#674ea7',
  '#a64d79',
}

---@type { id: Sheet.BorderPreset, label: string }[]
M.BORDERS = {
  { id = 'all', label = 'All borders' },
  { id = 'inner', label = 'Inner borders' },
  { id = 'horizontal', label = 'Horizontal borders' },
  { id = 'vertical', label = 'Vertical borders' },
  { id = 'outer', label = 'Outer borders' },
  { id = 'left', label = 'Left border' },
  { id = 'top', label = 'Top border' },
  { id = 'right', label = 'Right border' },
  { id = 'bottom', label = 'Bottom border' },
  { id = 'none', label = 'Clear borders' },
}

---@type { id: string, label: string }[]
M.LINES = {
  { id = 'thin', label = 'Thin' },
  { id = 'medium', label = 'Medium' },
  { id = 'thick', label = 'Thick' },
  { id = 'dashed', label = 'Dashed' },
  { id = 'dotted', label = 'Dotted' },
  { id = 'double', label = 'Double' },
}

M.SUM_FUNCTIONS = { 'SUM', 'AVERAGE', 'COUNT', 'MAX', 'MIN' }

---@type Sheet.Condition[]
M.CONDITIONS = {
  {
    id = 'blank',
    label = 'Is empty',
    type = 'blank',
    input = 'none',
    filter = true,
  },
  {
    id = 'not_blank',
    label = 'Is not empty',
    type = 'not_blank',
    input = 'none',
    filter = true,
  },
  {
    id = 'contains',
    label = 'Text contains',
    type = 'text',
    op = 'contains',
    input = 'one',
    filter = true,
  },
  {
    id = 'not_contains',
    label = 'Text does not contain',
    type = 'text',
    op = 'not_contains',
    input = 'one',
    filter = true,
  },
  {
    id = 'starts',
    label = 'Text starts with',
    type = 'text',
    op = 'starts',
    input = 'one',
    filter = true,
  },
  {
    id = 'ends',
    label = 'Text ends with',
    type = 'text',
    op = 'ends',
    input = 'one',
    filter = true,
  },
  {
    id = 'equals',
    label = 'Text is exactly',
    type = 'text',
    op = 'equals',
    input = 'one',
    filter = true,
  },
  {
    id = '>',
    label = 'Greater than',
    type = 'compare',
    op = '>',
    input = 'one',
    filter = true,
  },
  {
    id = '>=',
    label = 'Greater than or equal to',
    type = 'compare',
    op = '>=',
    input = 'one',
    filter = true,
  },
  {
    id = '<',
    label = 'Less than',
    type = 'compare',
    op = '<',
    input = 'one',
    filter = true,
  },
  {
    id = '<=',
    label = 'Less than or equal to',
    type = 'compare',
    op = '<=',
    input = 'one',
    filter = true,
  },
  {
    id = '=',
    label = 'Is equal to',
    type = 'compare',
    op = '=',
    input = 'one',
    filter = true,
  },
  {
    id = '<>',
    label = 'Is not equal to',
    type = 'compare',
    op = '<>',
    input = 'one',
    filter = true,
  },
  {
    id = 'between',
    label = 'Is between',
    type = 'compare',
    op = 'between',
    input = 'two',
    filter = true,
  },
  {
    id = 'not_between',
    label = 'Is not between',
    type = 'compare',
    op = 'not_between',
    input = 'two',
    filter = true,
  },
  { id = 'error', label = 'Is an error', type = 'error', input = 'none' },
  {
    id = 'duplicate',
    label = 'Is a duplicate',
    type = 'duplicate',
    input = 'none',
  },
  { id = 'unique', label = 'Is unique', type = 'unique', input = 'none' },
  { id = 'top', label = 'Is in the top', type = 'top', input = 'count' },
  {
    id = 'top_percent',
    label = 'Is in the top percent',
    type = 'top',
    percent = true,
    input = 'count',
  },
  {
    id = 'bottom',
    label = 'Is in the bottom',
    type = 'bottom',
    input = 'count',
  },
  {
    id = 'bottom_percent',
    label = 'Is in the bottom percent',
    type = 'bottom',
    percent = true,
    input = 'count',
  },
  {
    id = 'above_average',
    label = 'Is above average',
    type = 'above_average',
    input = 'none',
  },
  {
    id = 'below_average',
    label = 'Is below average',
    type = 'below_average',
    input = 'none',
  },
  {
    id = 'formula',
    label = 'Custom formula is',
    type = 'formula',
    input = 'formula',
  },
  { id = 'scale', label = 'Colour scale', type = 'scale', input = 'none' },
  { id = 'bar', label = 'Data bar', type = 'bar', input = 'none' },
}

---@type table<string, Sheet.Condition>
local CONDITION = {}
for _, c in ipairs (M.CONDITIONS) do
  CONDITION[c.id] = c
end

-- The colours a new colour scale starts from: red for low, yellow, green for high.
M.SCALE_MIN = '#f8696b'
M.SCALE_MID = '#ffeb84'
M.SCALE_MAX = '#63be7b'
M.BAR_COLOR = '#638ec6'
-- The style a new rule starts with: dark red text on a light red fill.
M.RULE_COLOR = '#9c0006'
M.RULE_FILL = '#ffc7ce'

---The condition a form lists for its id.
---@param id string
---@return Sheet.Condition?
function M.condition (id)
  return CONDITION[id]
end

---The id of the form condition that matches a rule.
---@param rule Sheet.Rule
---@return string
function M.condition_of (rule)
  if rule.type == 'compare' or rule.type == 'text' then
    return rule.op or '>'
  end
  if rule.type == 'top' or rule.type == 'bottom' then
    return rule.type .. (rule.percent and '_percent' or '')
  end
  return rule.type
end

---The fields of a rule for a form condition and the values typed for it. The style and the
---colours are not part of it.
---@param id string
---@param a? string The first value, the count, or the formula.
---@param b? string The second value of a between test.
---@return table<string, any>
function M.rule_fields (id, a, b)
  local c = CONDITION[id] or CONDITION['>']
  local out = { type = c.type } ---@type table<string, any>
  if c.op then
    out.op = c.op
  end
  if c.input == 'one' then
    out.value = a or ''
  elseif c.input == 'two' then
    out.value = a or ''
    out.value2 = b or ''
  elseif c.input == 'count' then
    out.count = tonumber (a) or 10
    out.percent = c.percent or nil
  elseif c.input == 'formula' then
    local text = a or ''
    if text ~= '' and string.sub (text, 1, 1) ~= '=' then
      text = '=' .. text
    end
    out.formula = text
  end
  return out
end

---@param text? string
---@return string
local function quoted (text)
  return '"' .. (text or '') .. '"'
end

---A rule's condition as one short line.
---@param rule Sheet.Rule
---@return string
local function describe (rule)
  local id = M.condition_of (rule)
  local c = CONDITION[id]
  if not c then
    return 'Unknown rule'
  end
  if c.input == 'one' then
    local value = rule.type == 'text' and quoted (rule.value)
      or (rule.value or '')
    return c.label .. ' ' .. value
  elseif c.input == 'two' then
    return c.label
      .. ' '
      .. (rule.value or '')
      .. ' and '
      .. (rule.value2 or '')
  elseif c.input == 'count' then
    local n = rule.count or 10
    local word = rule.type == 'top' and 'Top ' or 'Bottom '
    return word .. n .. (rule.percent and '%' or '')
  elseif c.input == 'formula' then
    return 'Formula ' .. (rule.formula or '')
  end
  return c.label
end

---A rule as one short line, such as `Greater than 100` or `Text contains "late"`, with
---`, then stop` for a rule that keeps the rules below it from applying.
---@param rule Sheet.Rule
---@return string
function M.describe_rule (rule)
  local line = describe (rule)
  if rule.stop then
    return line .. ', then stop'
  end
  return line
end

local VALIDATION_OPS = {
  ['>'] = 'greater than',
  ['>='] = 'at least',
  ['<'] = 'less than',
  ['<='] = 'at most',
  ['='] = 'equal to',
  ['<>'] = 'not equal to',
  between = 'between',
  not_between = 'not between',
}

---The compare ops a number validation offers, in menu order.
---@type { id: string, label: string }[]
M.VALIDATION_OPS = {
  { id = 'between', label = 'Between' },
  { id = 'not_between', label = 'Not between' },
  { id = '>', label = 'Greater than' },
  { id = '>=', label = 'At least' },
  { id = '<', label = 'Less than' },
  { id = '<=', label = 'At most' },
  { id = '=', label = 'Equal to' },
  { id = '<>', label = 'Not equal to' },
}

---A validation rule as one short line, such as `List: OK, Over` or `Number between 1 and 9`.
---@param v Sheet.Validation
---@return string
function M.describe_validation (v)
  if v.type == 'list' then
    return 'List: ' .. table.concat (v.values or {}, ', ')
  end
  local what = v.integer and 'Whole number' or 'Number'
  local op = v.op and VALIDATION_OPS[v.op]
  if not op then
    return 'Any ' .. string.lower (what)
  end
  if v.op == 'between' or v.op == 'not_between' then
    return what
      .. ' '
      .. op
      .. ' '
      .. (v.value or '')
      .. ' and '
      .. (v.value2 or '')
  end
  return what .. ' ' .. op .. ' ' .. (v.value or '')
end

---Splits the text of a list box into its values: one per line, or split by commas when it
---is all on one line. Blank values and repeats are left out.
---@param text string
---@return string[]
function M.list_values (text)
  local sep = string.find (text, '\n', 1, true) and '\n' or ','
  local out, seen = {}, {} ---@type string[], table<string, boolean>
  for part in string.gmatch (text .. sep, '(.-)' .. sep) do
    local item = string.match (part, '^%s*(.-)%s*$')
    if item ~= '' and not seen[item] then
      seen[item] = true
      out[#out + 1] = item
    end
  end
  return out
end

---The number format choices, each with a sample of how it shows a value.
---@return Sheet.FormatChoice[]
function M.format_choices ()
  local out = {} ---@type Sheet.FormatChoice[]
  for _, p in ipairs (format.presets) do
    local kind = format.kind (p.code)
    local sample = 1000.12 ---@type Sheet.Value
    if kind == 'percent' then
      sample = 0.1012
    elseif kind == 'date' or kind == 'datetime' or kind == 'time' then
      -- 2026-09-29 at 14:24.
      sample = 46294.6
    elseif kind == 'duration' then
      sample = 1.0441
    elseif p.id == 'financial' then
      sample = -1000.12
    end
    local text = format.format (sample, p.code)
    out[#out + 1] = {
      id = p.id,
      label = p.label,
      code = p.code,
      example = (string.gsub (text, '^%s+', '')),
    }
  end
  return out
end

---A colour typed by hand as `#rrggbb`, or nil when it is not one. It takes `#abc` and a
---missing `#` too.
---@param text string
---@return string?
function M.parse_color (text)
  local hex = string.match (text or '', '^%s*#?(%x+)%s*$')
  if not hex then
    return nil
  end
  if #hex == 3 then
    hex = string.gsub (hex, '(%x)', '%1%1')
  end
  if #hex ~= 6 then
    return nil
  end
  return '#' .. string.lower (hex)
end

---True when a `#rrggbb` colour is dark enough that white text reads best on it.
---@param color string
---@return boolean
function M.is_dark (color)
  local hex = M.parse_color (color)
  if not hex then
    return false
  end
  local r = tonumber (string.sub (hex, 2, 3), 16) / 255
  local g = tonumber (string.sub (hex, 4, 5), 16) / 255
  local b = tonumber (string.sub (hex, 6, 7), 16) / 255
  return 0.299 * r + 0.587 * g + 0.114 * b < 0.55
end

---A font size typed in the size box, or nil when it is not a size the app draws.
---@param text string
---@return number?
function M.parse_size (text)
  local n = tonumber (string.match (text or '', '^%s*(.-)%s*$'))
  if not n or n < M.MIN_SIZE or n > M.MAX_SIZE then
    return nil
  end
  return math.floor (n * 2 + 0.5) / 2
end

---The count the find bar shows, such as `3 of 12`.
---@param index? integer The match the selection is on, if any.
---@param count integer
---@return string
function M.match_label (index, count)
  if count == 0 then
    return 'No matches'
  end
  if not index then
    return count == 1 and '1 match' or count .. ' matches'
  end
  return index .. ' of ' .. count
end

---@param sheet Sheet.Sheet
---@param row integer
---@param col integer
---@return boolean
local function is_number (sheet, row, col)
  return sheet:kind (row, col) == 'number'
end

---@param sheet Sheet.Sheet
---@param row integer
---@param col integer
---@return boolean
local function is_empty (sheet, row, col)
  return sheet:text (row, col) == ''
end

---The block of numbers a quick sum in a cell adds up: the run of numbers right above it, or
---the run to its left when there is none above. Nil when neither side has a number.
---@param sheet Sheet.Sheet
---@param row integer
---@param col integer
---@return Sheet.Rect?
function M.sum_range (sheet, row, col)
  if row > 1 and is_number (sheet, row - 1, col) then
    local top = row - 1
    while top > 1 and is_number (sheet, top - 1, col) do
      top = top - 1
    end
    return { r1 = top, c1 = col, r2 = row - 1, c2 = col }
  end
  if col > 1 and is_number (sheet, row, col - 1) then
    local left = col - 1
    while left > 1 and is_number (sheet, row, left - 1) do
      left = left - 1
    end
    return { r1 = row, c1 = left, r2 = row, c2 = col - 1 }
  end
  return nil
end

---True when a block of cells holds at least one number.
---@param sheet Sheet.Sheet
---@param rect Sheet.Rect
---@return boolean
local function has_number (sheet, rect)
  for r = rect.r1, rect.r2 do
    for c = rect.c1, rect.c2 do
      if is_number (sheet, r, c) then
        return true
      end
    end
  end
  return false
end

---What a quick sum does, as spreadsheets do it. With one cell selected it types a formula
---into it over the numbers above or to the left. With a block selected it puts one formula
---under each column, or right of a single row: in the block's last row or column when that
---is empty, otherwise just past it.
---@param sheet Sheet.Sheet
---@param rect Sheet.Rect The selection.
---@param row integer The active cell.
---@param col integer
---@param fn string Such as `SUM`.
---@return Sheet.SumPlan
function M.sum_plan (sheet, rect, row, col, fn)
  if rect.r1 == rect.r2 and rect.c1 == rect.c2 then
    local range = M.sum_range (sheet, row, col)
    if range then
      return { text = '=' .. fn .. '(' .. model.range_name (range) .. ')' }
    end
    return { text = '=' .. fn .. '(' }
  end
  local cells = {} ---@type { [1]: integer, [2]: integer, [3]: string }[]
  if rect.r1 == rect.r2 then
    local last = rect.c2
    local src = { r1 = rect.r1, c1 = rect.c1, r2 = rect.r1, c2 = rect.c2 }
    if is_empty (sheet, rect.r1, rect.c2) then
      src.c2 = rect.c2 - 1
    else
      last = rect.c2 + 1
    end
    if has_number (sheet, src) then
      cells[1] =
        { rect.r1, last, '=' .. fn .. '(' .. model.range_name (src) .. ')' }
    end
    return {
      cells = cells,
      rect = { r1 = rect.r1, c1 = last, r2 = rect.r1, c2 = last },
      busy = not is_empty (sheet, rect.r1, last) or nil,
    }
  end
  local empty_last = true
  for c = rect.c1, rect.c2 do
    if not is_empty (sheet, rect.r2, c) then
      empty_last = false
    end
  end
  local target = empty_last and rect.r2 or rect.r2 + 1
  local bottom = empty_last and rect.r2 - 1 or rect.r2
  local busy = nil ---@type boolean?
  for c = rect.c1, rect.c2 do
    local src = { r1 = rect.r1, c1 = c, r2 = bottom, c2 = c }
    if has_number (sheet, src) then
      cells[#cells + 1] =
        { target, c, '=' .. fn .. '(' .. model.range_name (src) .. ')' }
      if not is_empty (sheet, target, c) then
        busy = true
      end
    end
  end
  return {
    cells = cells,
    rect = { r1 = target, c1 = rect.c1, r2 = target, c2 = rect.c2 },
    busy = busy,
  }
end

---The block a quick sort by one column moves, and whether its first row is a header. A cell
---inside a filter sorts the filter's rows under its header. A selection of several rows sorts
---itself. Otherwise the whole sheet sorts, below its frozen rows. Nil when there is nothing
---to sort.
---@param sheet Sheet.Sheet
---@param rect Sheet.Rect
---@param row integer
---@param col integer
---@return Sheet.Rect?
---@return boolean header
function M.sort_block (sheet, rect, row, col)
  local f = sheet.filter
  if f then
    local fr = f.rect
    if row >= fr.r1 and row <= fr.r2 and col >= fr.c1 and col <= fr.c2 then
      return fr, true
    end
  end
  if rect.r2 > rect.r1 then
    return rect, false
  end
  local last_row, last_col = sheet:used ()
  local first = sheet:freeze () + 1
  if last_row <= first then
    return nil, false
  end
  return {
    r1 = first,
    c1 = 1,
    r2 = last_row,
    c2 = math.max (last_col, col),
  },
    false
end

---The block a new chart reads: the selection, or the filled block around a single cell.
---Nil when that block is one empty cell.
---@param sheet Sheet.Sheet
---@param rect Sheet.Rect
---@param row integer
---@param col integer
---@return Sheet.Rect?
function M.chart_block (sheet, rect, row, col)
  if rect.r1 ~= rect.r2 or rect.c1 ~= rect.c2 then
    return rect
  end
  local region = sheet:region (row, col)
  if
    region.r1 == region.r2
    and region.c1 == region.c2
    and is_empty (sheet, row, col)
  then
    return nil
  end
  return region
end

---Whether a block's first row looks like a header: every filled cell in it holds text, and a
---column under it holds a number, or the block is a filter's.
---@param sheet Sheet.Sheet
---@param rect Sheet.Rect
---@return boolean
function M.guess_header (sheet, rect)
  local f = sheet.filter
  if
    f
    and f.rect.r1 == rect.r1
    and f.rect.c1 == rect.c1
    and f.rect.c2 == rect.c2
  then
    return true
  end
  if rect.r2 <= rect.r1 then
    return false
  end
  local filled = false
  for c = rect.c1, rect.c2 do
    local kind = sheet:kind (rect.r1, c)
    if kind ~= 'empty' and kind ~= 'text' then
      return false
    end
    filled = filled or kind == 'text'
  end
  if not filled then
    return false
  end
  for c = rect.c1, rect.c2 do
    for r = rect.r1 + 1, math.min (rect.r2, rect.r1 + 20) do
      if is_number (sheet, r, c) then
        return true
      end
    end
  end
  return false
end

---How a sort or filter names a column: `Column B`, with the header's text when there is one.
---@param sheet Sheet.Sheet
---@param header_row? integer
---@param col integer
---@return string
function M.column_label (sheet, header_row, col)
  local name = 'Column ' .. model.col_name (col)
  if header_row then
    local text = (sheet:display (header_row, col))
    if text ~= '' then
      return name .. ': ' .. text
    end
  end
  return name
end

return M
