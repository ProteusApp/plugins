-- Tests for sheet_model: typing, number formats, styles over cells, rows and columns, borders,
-- sizes, merges, notes, frozen panes, inserting and deleting, and paste special. Each change
-- is one undo step, and each test undoes it.

local f = require ('sheet_formula') --[[@as Sheet.FormulaModule]]
local m = require ('sheet_model') --[[@as Sheet.ModelModule]]

local NOW = f.serial (2026, 9, 29, 14, 30, 0)

---@return number
local function clock ()
  return NOW
end

---@param addr string
---@return integer row
---@return integer col
local function at (addr)
  local row, col = m.parse_address (addr)
  assert (row and col, addr)
  return row, --[[@as integer]]
    col --[[@as integer]]
end

---@param rect string
---@return Sheet.Rect
local function r (rect)
  local out = m.parse_range (rect)
  assert (out, rect)
  return out --[[@as Sheet.Rect]]
end

---@param cells? table<string, string>
---@return Sheet.Sheet
local function sheet_of (cells)
  local s = m.new ({ clock = clock })
  for addr, text in pairs (cells or {}) do
    local row, col = at (addr)
    s:put (row, col, { text = text })
  end
  return s
end

---@param s Sheet.Sheet
---@param addr string
---@param text string
local function set (s, addr, text)
  local row, col = at (addr)
  s:set (row, col, text)
end

---@param s Sheet.Sheet
---@param addr string
---@return string
local function shown (s, addr)
  local row, col = at (addr)
  return (s:display (row, col))
end

---@param s Sheet.Sheet
---@param addr string
---@return string
local function text (s, addr)
  local row, col = at (addr)
  return s:text (row, col)
end

---@param s Sheet.Sheet
---@param addr string
---@return Sheet.Style
local function style (s, addr)
  local row, col = at (addr)
  return s:style_at (row, col)
end

---@param s Sheet.Sheet
---@param addr string
---@return Sheet.Style?
local function own (s, addr)
  local row, col = at (addr)
  return m.copy_style (s:own_style (row, col))
end

---------------------------------------------------------------------------------------------
-- Typing and formats
---------------------------------------------------------------------------------------------

test (
  'typing a number with a format stores the number and the format',
  function ()
    local s = sheet_of ()
    set (s, 'A1', '$1,200')
    eq (text (s, 'A1'), '1200')
    eq (s:value (1, 1), 1200)
    eq (own (s, 'A1'), { format = '$#,##0' })
    eq (shown (s, 'A1'), '$1,200')
    set (s, 'A2', '15%')
    eq (text (s, 'A2'), '0.15')
    eq (shown (s, 'A2'), '15%')
    eq (s:edit_text (2, 1), '15%')
    set (s, 'A3', '9/29/2026')
    eq (s:value (3, 1), 46294)
    eq (shown (s, 'A3'), '9/29/2026')
    eq (s:edit_text (3, 1), '9/29/2026')
    set (s, 'A4', '2:30 PM')
    eq (s:edit_text (4, 1), '2:30:00 PM')
    set (s, 'A5', "'007")
    eq (s:value (5, 1), '007')
    eq (own (s, 'A5'), nil)
    set (s, 'A6', '1200')
    eq (own (s, 'A6'), nil)
    eq (s:edit_text (6, 1), '1200')
    eq (s:edit_text (9, 9), '')
    -- A cell with a format keeps it.
    s:set_format (r ('B1'), '0.00')
    set (s, 'B1', '15%')
    eq (shown (s, 'B1'), '0.15')
    -- So does a cell whose column has one.
    s:set_format (r ('C1:C100'), '0.0%')
    eq (s.col_styles[3], { format = '0.0%' })
    set (s, 'C5', '5%')
    eq (own (s, 'C5'), nil)
    eq (shown (s, 'C5'), '5.0%')
    -- Each typing is one step, format and all.
    s:undo ()
    eq (text (s, 'C5'), '')
    s:undo ()
    eq (s.col_styles[3], nil)
    eq (shown (s, 'B1'), '0.15')
    s:undo ()
    eq ({ text (s, 'B1'), own (s, 'B1') }, { '', { format = '0.00' } })
    s:undo ()
    eq (own (s, 'B1'), nil)
    s:undo ()
    eq ({ text (s, 'A6'), own (s, 'A5') }, { '', nil })
  end
)

test ('a formula shows its result in an automatic format', function ()
  local s = sheet_of ({
    A1 = '=DATE(2026, 9, 29)',
    A2 = '=TIME(14, 30, 0)',
    A3 = '=A1+7',
    B2 = '1200',
    B3 = '=B2*2',
    B4 = '=SUM(B2:B3)',
    B5 = '=COUNT(B2:B3)',
    C1 = '=Other!A1',
  })
  s:set_format (r ('B2'), '$#,##0.00')
  eq (shown (s, 'A1'), '2026-09-29')
  eq (shown (s, 'A2'), '2:30 PM')
  -- A formula that reads a date formula shows a date too.
  eq (shown (s, 'A3'), '2026-10-06')
  eq (shown (s, 'B3'), '$2,400.00')
  eq (shown (s, 'B4'), '$3,600.00')
  eq (s:number_format (4, 2), '$#,##0.00')
  -- A format of its own wins.
  s:set_format (r ('B4'), '0')
  eq (shown (s, 'B4'), '3600')
  -- Text and errors show as they are.
  eq (shown (s, 'C1'), '#REF!')
  -- With digits, as CSV asks, a number with no format shows its digits.
  s:put (6, 1, { text = '=1/3' })
  eq (s:display (6, 1, 15), '0.333333333333333')
  eq (s:display (2, 2, 15), '$1,200.00')
end)

test ('a format section can colour a value', function ()
  local s = sheet_of ({ A1 = '-5', A2 = '5' })
  s:set_format (r ('A1:A2'), '0;[Red]-0')
  local shown_text, color = s:display (1, 1)
  eq (shown_text, '-5')
  ok (type (color) == 'string' and string.sub (color, 1, 1) == '#')
  eq ({ s:display (2, 1) }, { '5' })
end)

test ('alignment follows the style, or the value', function ()
  local s = sheet_of ({ A1 = '5', A2 = 'x', A3 = 'TRUE' })
  eq ({ s:align (1, 1), s:align (2, 1), s:align (3, 1) }, {
    'right',
    'left',
    'center',
  })
  s:set_style (r ('A1'), { align = 'center' })
  eq (s:align (1, 1), 'center')
  s:set_format (r ('A2'), '@')
  eq (s:align (2, 1), 'left')
end)

---------------------------------------------------------------------------------------------
-- Styles
---------------------------------------------------------------------------------------------

test ('set_style patches a block, and false takes a field away', function ()
  local s = sheet_of ({ A1 = 'x' })
  s:set_style (r ('A1:B2'), { bold = true, fill = '#ffeeaa', size = 16 })
  eq (style (s, 'B2'), { bold = true, fill = '#ffeeaa', size = 16 })
  ok (s:is_bold (1, 1))
  eq (#s.book.done, 1)
  s:set_style (r ('A1'), { fill = false, size = 13 })
  eq (style (s, 'A1'), { bold = true })
  -- Bad values are dropped.
  local bad = { align = 'sideways', size = -2 } ---@type any
  s:set_style (r ('C1'), bad)
  eq (s:own_style (1, 3), nil)
  s:undo ()
  eq (style (s, 'A1'), { bold = true, fill = '#ffeeaa', size = 16 })
  s:undo ()
  eq (style (s, 'B2'), {})
  eq (s:cell (2, 2), nil)
end)

test (
  'whole columns and rows take the style, and cells keep what differs',
  function ()
    local s = sheet_of ({ B3 = 'x', B4 = 'y' })
    local rows = s.rows
    s:set_style (r ('B3'), { italic = true, fill = '#ff0000' })
    s:set_style ({ r1 = 1, c1 = 2, r2 = rows, c2 = 2 }, { fill = '#00ff00' })
    eq (s.col_styles[2], { fill = '#00ff00' })
    eq (own (s, 'B3'), { italic = true })
    eq (style (s, 'B3'), { italic = true, fill = '#00ff00' })
    eq (style (s, 'B50'), { fill = '#00ff00' })
    -- A row style lies over the column's.
    s:set_style ({ r1 = 4, c1 = 1, r2 = 4, c2 = s.cols }, { fill = '#0000ff' })
    eq (s.row_styles[4], { fill = '#0000ff' })
    eq (style (s, 'B4').fill, '#0000ff')
    -- A column style set later wins where it crosses the row, through the cell.
    s:set_style ({ r1 = 1, c1 = 2, r2 = rows, c2 = 2 }, { fill = '#123456' })
    eq (style (s, 'B4').fill, '#123456')
    eq (style (s, 'A4').fill, '#0000ff')
    eq (style (s, 'B3').fill, '#123456')
    -- A row that turns bold off over a bold column holds a reset.
    s:set_style ({ r1 = 1, c1 = 2, r2 = rows, c2 = 2 }, { bold = true })
    s:set_style ({ r1 = 5, c1 = 1, r2 = 5, c2 = s.cols }, { bold = false })
    eq (s.row_styles[5], { bold = false })
    ok (not s:is_bold (5, 2))
    ok (s:is_bold (6, 2))
    -- A cell turns bold off over its column the same way.
    s:set_style (r ('B6'), { bold = false })
    eq (own (s, 'B6'), { bold = false })
    eq (style (s, 'B6'), { fill = '#123456' })
    -- Clearing the column's format clears it where rows cross too.
    s:clear_format ({ r1 = 1, c1 = 2, r2 = rows, c2 = 2 })
    eq (s.col_styles[2], nil)
    eq (style (s, 'B3'), {})
    eq (style (s, 'B4'), {})
    eq (style (s, 'A4').fill, '#0000ff')
    -- Every call was one step.
    for _ = 1, 6 do
      s:undo ()
    end
    eq (style (s, 'B3'), { italic = true, fill = '#00ff00' })
    s:undo ()
    eq (style (s, 'B3'), { italic = true, fill = '#ff0000' })
  end
)

test ('a style over the whole sheet goes on every column', function ()
  local s = sheet_of ({ A1 = 'x' })
  s:set_style ({ r1 = 2, c1 = 1, r2 = 2, c2 = s.cols }, { italic = false })
  s:set_style ({ r1 = 1, c1 = 1, r2 = s.rows, c2 = s.cols }, { italic = true })
  eq (s.col_styles[26], { italic = true })
  eq (s.row_styles[2], nil)
  ok (style (s, 'Z99').italic and style (s, 'C2').italic)
end)

test ('toggles switch a flag on, or off when every cell has it', function ()
  local s = sheet_of ({ A1 = 'x', A2 = 'y' })
  s:toggle_style (r ('A1:A2'), 'italic')
  ok (style (s, 'A2').italic)
  s:toggle_style (r ('A1:A3'), 'italic')
  ok (style (s, 'A3').italic)
  s:toggle_style (r ('A1:A3'), 'italic')
  ok (not style (s, 'A1').italic)
  -- A whole column checks the column styles.
  local col = { r1 = 1, c1 = 4, r2 = s.rows, c2 = 4 }
  s:toggle_bold (col)
  eq (s.col_styles[4], { bold = true })
  ok (s:all_have (col, 'bold'))
  s:toggle_bold (col)
  eq (s.col_styles[4], nil)
  local big = { r1 = 1, c1 = 1, r2 = s.rows, c2 = s.cols }
  ok (not s:all_have (big, 'bold'))
  s:toggle_bold (big)
  ok (s:all_have (big, 'bold'))
end)

test ('number formats and decimals over a block', function ()
  local s = sheet_of ({ A1 = '3.14159', A2 = '2' })
  s:set_format (r ('A1:A2'), '0.00')
  eq ({ shown (s, 'A1'), shown (s, 'A2') }, { '3.14', '2.00' })
  s:adjust_decimals (r ('A1:A2'), 1)
  eq (style (s, 'A1').format, '0.000')
  eq (shown (s, 'A2'), '2.000')
  s:adjust_decimals (r ('A1:A2'), -3)
  eq (shown (s, 'A1'), '3')
  s:set_format (r ('A1'), nil)
  eq (shown (s, 'A1'), '3.14159')
  -- From General, the decimals start from what the value shows.
  s:adjust_decimals (r ('A1'), -1)
  eq (style (s, 'A1').format, '0.0000')
end)

test ('border presets draw the right sides', function ()
  local s = sheet_of ()
  local block = r ('B2:D4')
  s:set_borders (block, 'outer', 'medium', '#333333')
  eq (style (s, 'B2'), {
    border_top = 'medium',
    border_left = 'medium',
    border_color = '#333333',
  })
  eq (style (s, 'C2'), { border_top = 'medium', border_color = '#333333' })
  eq (style (s, 'D4'), {
    border_bottom = 'medium',
    border_right = 'medium',
    border_color = '#333333',
  })
  eq (style (s, 'C3'), {})
  s:set_borders (block, 'none')
  eq (style (s, 'B2'), {})
  s:set_borders (block, 'inner')
  eq (style (s, 'B2'), { border_bottom = 'thin', border_right = 'thin' })
  eq (style (s, 'D3'), { border_bottom = 'thin' })
  eq (style (s, 'D4'), {})
  s:set_borders (block, 'none')
  s:set_borders (block, 'all')
  eq (style (s, 'C3'), {
    border_top = 'thin',
    border_bottom = 'thin',
    border_left = 'thin',
    border_right = 'thin',
  })
  s:set_borders (block, 'none')
  for _, case in ipairs ({
    { 'top', 'C2', 'border_top' },
    { 'bottom', 'C4', 'border_bottom' },
    { 'left', 'B3', 'border_left' },
    { 'right', 'D3', 'border_right' },
    { 'horizontal', 'C3', 'border_bottom' },
    { 'vertical', 'C3', 'border_right' },
  }) do
    s:set_borders (block, case[1] --[[@as Sheet.BorderPreset]])
    eq (
      (style (s, case[2]) --[[@as table<string, any>]])[case[3]],
      'thin',
      case[1]
    )
    s:undo ()
    eq (style (s, case[2]), {}, case[1] .. ' undo')
  end
end)

test ('borders over whole columns go on the column styles', function ()
  local s = sheet_of ()
  local rows = s.rows
  s:set_borders ({ r1 = 1, c1 = 2, r2 = rows, c2 = 3 }, 'outer')
  eq (s.col_styles[2], { border_left = 'thin' })
  eq (s.col_styles[3], { border_right = 'thin' })
  eq (style (s, 'B1'), { border_top = 'thin', border_left = 'thin' })
  eq (style (s, 'C50'), { border_right = 'thin' })
  eq (style (s, 'B' .. rows), { border_bottom = 'thin', border_left = 'thin' })
  eq (#s.book.done, 1)
  s:set_borders ({ r1 = 1, c1 = 2, r2 = rows, c2 = 3 }, 'inner')
  eq (style (s, 'B50').border_bottom, 'thin')
  eq (style (s, 'B' .. rows).border_bottom, nil)
  s:undo ()
  s:undo ()
  eq ({ s.col_styles[2], s.col_styles[3] }, {})
  eq (style (s, 'B1'), {})
end)

---------------------------------------------------------------------------------------------
-- Structure
---------------------------------------------------------------------------------------------

test (
  'sizes, hidden rows and columns, and frozen panes are undo steps',
  function ()
    local s = sheet_of ()
    s:set_widths (2, 4, 150)
    eq ({ s:width (1), s:width (2), s:width (4) }, { 100, 150, 150 })
    s:set_height (3, 40)
    s:set_heights (5, 6, 5)
    eq ({ s:height (1), s:height (3), s:height (5) }, { 24, 40, 12 })
    s:set_hidden ('row', 7, 8, true)
    s:set_hidden ('col', 3, 3, true)
    ok (s:row_hidden (7) and s:row_hidden (8) and not s:row_hidden (9))
    ok (s:col_hidden (3) and not s:filtered (7))
    s:set_freeze (2, 1)
    eq ({ s:freeze () }, { 2, 1 })
    eq (#s.book.done, 6)
    s:undo ()
    eq ({ s:freeze () }, { 0, 0 })
    s:undo ()
    ok (not s:col_hidden (3))
    s:undo ()
    ok (not s:row_hidden (7))
    s:undo ()
    s:undo ()
    eq (s:height (3), 24)
    s:undo ()
    eq (s:width (2), 100)
    eq (s.widths, {})
  end
)

test ('notes are set, changed and removed', function ()
  local s = sheet_of ()
  s:set_note (2, 3, 'Check this.')
  eq (s:note (2, 3), 'Check this.')
  s:set_note (2, 3, 'Checked.')
  s:set_note (2, 3, '')
  eq (s:note (2, 3), nil)
  s:undo ()
  eq (s:note (2, 3), 'Checked.')
  s:undo ()
  s:undo ()
  eq (s:note (2, 3), nil)
  s:set_note (1, 1, 'a')
  s:clear (r ('A1:B2'), 'notes')
  eq (s:note (1, 1), nil)
end)

test (
  'merging keeps the top left text and refuses to cut another merge',
  function ()
    local s = sheet_of ({ A1 = 'Title', B1 = 'gone', C2 = 'gone too' })
    eq ({ s:merge (r ('A1:C2')) }, { true })
    eq (text (s, 'A1'), 'Title')
    eq ({ text (s, 'B1'), text (s, 'C2') }, { '', '' })
    eq (s:merge_at (2, 3), { r1 = 1, c1 = 1, r2 = 2, c2 = 3 })
    eq (s:merge_at (3, 1), nil)
    eq ({ s:merge (r ('B2:D3')) }, {
      false,
      'The block cuts across the merged cells A1:C2. Unmerge them first.',
    })
    eq ({ s:merge (r ('E5')) }, { false, 'Pick more than one cell to merge.' })
    -- A bigger block takes the merge inside it.
    ok (s:merge (r ('A1:D4')))
    eq (s.merges, { { r1 = 1, c1 = 1, r2 = 4, c2 = 4 } })
    ok (s:unmerge (r ('B2')))
    eq (s.merges, {})
    ok (not s:unmerge (r ('B2')))
    -- Merge across makes one block per row.
    ok (s:merge (r ('A6:C7'), true))
    eq (s.merges, {
      { r1 = 6, c1 = 1, r2 = 6, c2 = 3 },
      { r1 = 7, c1 = 1, r2 = 7, c2 = 3 },
    })
    s:undo ()
    s:undo ()
    s:undo ()
    s:undo ()
    eq (s.merges, {})
    eq ({ text (s, 'B1'), text (s, 'C2') }, { 'gone', 'gone too' })
  end
)

test ('the data region around a cell', function ()
  local s = sheet_of ({ B2 = 'a', C2 = 'b', B3 = '1', D4 = 'x', F9 = 'far' })
  eq (s:region (2, 2), { r1 = 2, c1 = 2, r2 = 4, c2 = 4 })
  eq (s:region (9, 6), { r1 = 9, c1 = 6, r2 = 9, c2 = 6 })
  eq (s:region (20, 20), { r1 = 20, c1 = 20, r2 = 20, c2 = 20 })
  -- A cell that only touches the block at a corner joins it.
  s:set (5, 5, 'corner')
  eq (s:region (2, 2), { r1 = 2, c1 = 2, r2 = 5, c2 = 5 })
end)

test ('the region of a tall block is found quickly', function ()
  local list = {} ---@type { [1]: integer, [2]: integer, [3]: string }[]
  for row = 1, 5000 do
    for c = 1, 5 do
      list[#list + 1] = { row, c, tostring (row * c) }
    end
  end
  local s = sheet_of ()
  s:set_many (list)
  local started = os.clock ()
  eq (s:region (2, 1), { r1 = 1, c1 = 1, r2 = 5000, c2 = 5 })
  ok (os.clock () - started < 0.2, 'region took too long')
end)

test ('growing a sheet draws the new rows', function ()
  local s = sheet_of ()
  eq (#s:layout ().tops, 101)
  s:grow (200, 26)
  eq (#s:layout ().tops, 201)
end)

---A sheet with something at every kind of address, for insert and delete.
---@return Sheet.Sheet
local function busy_sheet ()
  local s = sheet_of ({
    A4 = 'Item',
    B4 = 'Cost',
    A5 = 'Rent',
    B5 = '100',
    A6 = 'Food',
    B6 = '50',
    B11 = '=SUM(B5:B10)',
    C11 = '=B5+B6',
  })
  local other = assert (s.book:add_sheet ('Other'))
  other:put (1, 1, { text = '=Sheet1!B6*2' })
  other:put (1, 2, { text = '=B6' })
  s.book:set_active (1)
  s:set_style (r ('B5'), { bold = true })
  s:set_style ({ r1 = 6, c1 = 1, r2 = 6, c2 = s.cols }, { italic = true })
  s:set_style ({ r1 = 1, c1 = 3, r2 = s.rows, c2 = 3 }, { fill = '#eeeeee' })
  s:set_height (6, 40)
  s:set_width (3, 150)
  s:set_hidden ('row', 7, 7, true)
  s:set_hidden ('col', 5, 5, true)
  s:merge (r ('A8:B9'))
  s:set_note (6, 2, 'Weekly shop.')
  s:set_freeze (4, 1)
  s:set_field ('filter', {
    rect = r ('A4:B10'),
    columns = { [1] = { values = { 'Rent', 'Food' } } },
    hidden = { [10] = true },
  })
  s:set_field ('rules', {
    {
      range = 'B5:B10',
      type = 'formula',
      formula = '=$B5>60',
      style = { color = '#c62828' },
    },
  })
  s:set_field (
    'validation',
    { { range = 'B5:B10', type = 'number', op = '>=', value = '0' } }
  )
  s:set_field ('charts', {
    {
      id = 'c1',
      type = 'column',
      range = 'A4:B6',
      x = 0,
      y = 0,
      w = 100,
      h = 100,
    },
  })
  s.book.done = {}
  return s
end

test ('inserting rows moves everything with an address', function ()
  local s = busy_sheet ()
  local other = s.book.sheets[2]
  s:insert_rows (5, 2)
  eq (s.rows, 102)
  eq ({ text (s, 'A7'), text (s, 'B8'), text (s, 'B13') }, {
    'Rent',
    '50',
    '=SUM(B7:B12)',
  })
  eq (text (s, 'C13'), '=B7+B8')
  eq (shown (s, 'B13'), '150')
  ok (s:is_bold (7, 2) and not s:is_bold (5, 2))
  eq (s.row_styles[8], { italic = true })
  eq (s.col_styles[3], { fill = '#eeeeee' })
  eq (s:height (8), 40)
  ok (s:row_hidden (9) and not s:row_hidden (7))
  eq (s.merges, { { r1 = 10, c1 = 1, r2 = 11, c2 = 2 } })
  eq (s:note (8, 2), 'Weekly shop.')
  eq (s.freeze_rows, 4)
  eq (s.filter and s.filter.rect, r ('A4:B12'))
  ok (s:filtered (12))
  eq (s.rules[1].range, 'B7:B12')
  eq (s.rules[1].formula, '=$B7>60')
  eq (s.validation[1].range, 'B7:B12')
  eq (s.charts[1].range, 'A4:B8')
  -- Formulas on other sheets that name this one follow.
  eq (other:text (1, 1), '=Sheet1!B8*2')
  eq (other:text (1, 2), '=B6')
  eq (other:display (1, 1), '100')
  -- Rows inserted inside the frozen rows freeze with them.
  s:insert_rows (2, 1)
  eq (s.freeze_rows, 5)
  -- One step each, and undo puts everything back.
  local info = assert (s.book:undo ())
  eq (info.label, 'Insert rows')
  s.book:undo ()
  eq (s.rows, 100)
  eq (text (s, 'B11'), '=SUM(B5:B10)')
  eq (s.merges, { { r1 = 8, c1 = 1, r2 = 9, c2 = 2 } })
  eq (other:text (1, 1), '=Sheet1!B6*2')
  eq (s:height (6), 40)
  eq (s.charts[1].range, 'A4:B6')
  eq (shown (s, 'B11'), '150')
  s.book:redo ()
  eq (text (s, 'B13'), '=SUM(B7:B12)')
end)

test ('deleting rows shrinks what they cut and drops what they hold', function ()
  local s = busy_sheet ()
  local other = s.book.sheets[2]
  s:delete_rows (6, 3)
  eq (s.rows, 97)
  eq ({ text (s, 'A5'), text (s, 'A6') }, { 'Rent', '' })
  eq (text (s, 'B8'), '=SUM(B5:B7)')
  eq (text (s, 'C8'), '=B5+#REF!')
  eq (other:text (1, 1), '=#REF!*2')
  eq (s.row_styles, {})
  eq (s:height (6), 24)
  eq (s.hidden_rows, {})
  -- The merge A8:B9 loses row 8 and is one row now, which is still a merge of two cells.
  eq (s.merges, { { r1 = 6, c1 = 1, r2 = 6, c2 = 2 } })
  eq (s:note (6, 2), nil)
  eq (s.filter and s.filter.rect, r ('A4:B7'))
  eq (s.rules[1].range, 'B5:B7')
  eq (s.charts[1].range, 'A4:B5')
  -- A range whose cells are all deleted goes.
  s:delete_rows (4, 4)
  eq (#s.charts, 0)
  eq (s.filter, nil)
  eq (s.freeze_rows, 3)
  s.book:undo ()
  s.book:undo ()
  eq (text (s, 'C11'), '=B5+B6')
  eq (other:text (1, 1), '=Sheet1!B6*2')
  eq (s.row_styles[6], { italic = true })
end)

test ('inserting and deleting columns moves styles, widths and more', function ()
  local s = busy_sheet ()
  s:insert_cols (2, 1)
  eq (text (s, 'C5'), '100')
  eq (text (s, 'C11'), '=SUM(C5:C10)')
  eq (s.col_styles[4], { fill = '#eeeeee' })
  eq (s:width (4), 150)
  ok (s:col_hidden (6))
  eq (s.merges, { { r1 = 8, c1 = 1, r2 = 9, c2 = 3 } })
  eq (s.freeze_cols, 1)
  eq (s.filter and s.filter.rect, r ('A4:C10'))
  eq (s.rules[1].formula, '=$C5>60')
  s:delete_cols (1, 1)
  eq (s.freeze_cols, 0)
  eq (s.filter and s.filter.columns, {})
  s.book:undo ()
  s.book:undo ()
  eq (s:width (3), 150)
  eq (s.filter and s.filter.columns, { [1] = { values = { 'Rent', 'Food' } } })
end)

---------------------------------------------------------------------------------------------
-- Paste and paste special
---------------------------------------------------------------------------------------------

test ('a paste carries the full style of each cell', function ()
  local s = sheet_of ({ A1 = '5', A2 = '=A1*2' })
  s:set_style ({ r1 = 1, c1 = 1, r2 = s.rows, c2 = 1 }, { fill = '#eeeeee' })
  s:set_style (r ('A1'), { bold = true })
  s:set_note (1, 1, 'Source.')
  local clip = s:copy (r ('A1:A2'))
  eq (clip.styles[1][1], { bold = true, fill = '#eeeeee' })
  eq (clip.literals, { { '5' }, { '10' } })
  -- Pasted into another column, the cells hold the style they showed.
  s:paste (1, 3, clip)
  eq (style (s, 'C1'), { bold = true, fill = '#eeeeee' })
  eq (style (s, 'C2'), { fill = '#eeeeee' })
  eq (text (s, 'C2'), '=C1*2')
  eq (s:note (1, 3), 'Source.')
  -- Pasted into a column with its own fill, the fill resets where the source had none.
  s:set_style ({ r1 = 1, c1 = 5, r2 = s.rows, c2 = 5 }, { fill = '#ff0000' })
  local plain = s:copy (r ('B1:B1'))
  s:paste (1, 5, plain)
  eq (style (s, 'E1'), {})
  eq (own (s, 'E1'), { fill = 'none' })
end)

test ('paste values, formulas or formats alone', function ()
  local s = sheet_of ({ A1 = '5', A2 = '=A1*2', A3 = 'TRUE' })
  s:set_style (r ('A1:A2'), { bold = true })
  s:put (5, 2, { text = 'old', style = m.intern ({ italic = true }) })
  local clip = s:copy (r ('A1:A3'))
  local steps = #s.book.done
  -- Values: the results as plain values, and the target keeps its styles.
  s:paste (5, 2, clip, nil, { only = 'values' })
  eq ({ text (s, 'B5'), text (s, 'B6'), text (s, 'B7') }, { '5', '10', 'TRUE' })
  eq (style (s, 'B5'), { italic = true })
  eq (#s.book.done, steps + 1)
  s:undo ()
  eq (text (s, 'B5'), 'old')
  -- Formulas: the text moves as a copy does, and no style comes along.
  s:paste (5, 2, clip, nil, { only = 'formulas' })
  eq (text (s, 'B6'), '=B5*2')
  eq (style (s, 'B5'), { italic = true })
  s:undo ()
  -- Formats: the styles come, and the text stays.
  s:paste (5, 2, clip, nil, { only = 'formats' })
  eq (text (s, 'B5'), 'old')
  eq (style (s, 'B5'), { bold = true })
  s:undo ()
  eq (style (s, 'B5'), { italic = true })
end)

test (
  'transpose turns rows into columns and moves references to match',
  function ()
    local s = sheet_of ({ A1 = '1', B1 = '2', C1 = '=A1+B1', A2 = 'x' })
    s:merge (r ('A2:B2'))
    local clip = s:copy (r ('A1:C2'))
    local area = s:paste (5, 5, clip, nil, { transpose = true })
    eq (area, r ('E5:F7'))
    eq (
      { text (s, 'E5'), text (s, 'E6'), text (s, 'E7') },
      { '1', '2', '=C7+D7' }
    )
    eq (text (s, 'F5'), 'x')
    -- The merge across row 2 runs down a column now.
    eq (s:merge_at (6, 6), { r1 = 5, c1 = 6, r2 = 6, c2 = 6 })
    s:undo ()
    eq (s:merge_at (6, 6), nil)
    -- Values and transpose together.
    s:paste (5, 5, clip, nil, { only = 'values', transpose = true })
    eq (text (s, 'E7'), '3')
    eq (s:merge_at (5, 6), nil)
  end
)

test ('a clip repeats to fill a block of whole clips', function ()
  local s = sheet_of ({ A1 = '1', A2 = '=A1+1' })
  local clip = s:copy (r ('A1:A2'))
  local area = s:paste (1, 3, clip, r ('C1:D4'))
  eq (area, r ('C1:D4'))
  eq ({ text (s, 'C3'), text (s, 'D4') }, { '1', '=D3+1' })
  -- A block that is not whole clips pastes the clip once.
  eq (s:paste (1, 6, clip, r ('F1:F3')), r ('F1:F2'))
end)

test ('cut moves cells, styles and notes, even to another sheet', function ()
  local s = sheet_of ({ A1 = '5', B1 = '=A1*2' })
  s:set_style (r ('B1'), { bold = true })
  s:set_note (1, 2, 'Moves.')
  local other = assert (s.book:add_sheet ('Other'))
  local clip = s:copy (r ('B1'))
  clip.cut = true
  other:paste (3, 3, clip)
  eq (text (s, 'B1'), '')
  eq (s:own_style (1, 2), nil)
  eq (s:note (1, 2), nil)
  eq (other:text (3, 3), '=A1*2')
  ok (other:is_bold (3, 3))
  eq (other:note (3, 3), 'Moves.')
  local info = assert (s.book:undo ())
  eq (info.sheet, 2)
  eq (text (s, 'B1'), '=A1*2')
  eq (s:note (1, 2), 'Moves.')
end)

test ('text from outside pastes as if typed', function ()
  local s = sheet_of ()
  s:paste_text (1, 1, '$5\t10%\n9/29/2026\tplain')
  eq (shown (s, 'A1'), '$5')
  eq (shown (s, 'B1'), '10%')
  eq (shown (s, 'A2'), '9/29/2026')
  eq (text (s, 'B2'), 'plain')
end)

test ('fill down copies styles with the text', function ()
  local s = sheet_of ({ A1 = '1', B1 = '=A1*2' })
  s:set_style (r ('B1'), { fill = '#eeeeee', format = '0.00' })
  s:fill_down (r ('A1:B3'))
  eq (style (s, 'B3'), { fill = '#eeeeee', format = '0.00' })
  eq (shown (s, 'B3'), '2.00')
end)

test ('clear keeps styles unless asked', function ()
  local s = sheet_of ({ A1 = 'x' })
  s:set_style (r ('A1'), { bold = true })
  s:clear (r ('A1'))
  eq ({ text (s, 'A1'), s:is_bold (1, 1) }, { '', true })
  s:put (1, 1, { text = 'y', style = s:own_style (1, 1) })
  s:clear (r ('A1'), 'formats')
  eq ({ text (s, 'A1'), s:is_bold (1, 1) }, { 'y', false })
  s:set_style (r ('A1'), { bold = true })
  s:clear (r ('A1'), 'all')
  eq (s:cell (1, 1), nil)
end)

---------------------------------------------------------------------------------------------
-- Conditions
---------------------------------------------------------------------------------------------

test ('matches tests values the way filters and rules do', function ()
  local mt = m.matches
  ok (mt (5, '5', '>', '3'))
  ok (not mt (5, '5', '>', '5'))
  ok (mt (5, '5', '>=', '5'))
  ok (mt (5, '5', '<', '10'))
  ok (mt (5, '5', '=', '5'))
  ok (mt ('Rent', 'Rent', '=', 'rent'))
  ok (mt ('b', 'b', '>', 'A'))
  ok (not mt (5, '5', '=', 'five'))
  ok (mt (5, '5', '<>', 'five'))
  ok (not mt (5, '5', '>', 'five'))
  ok (mt (5, '5', 'between', '1', '10'))
  ok (mt (5, '5', 'between', '10', '1'))
  ok (not mt (11, '11', 'between', '1', '10'))
  ok (mt (11, '11', 'not_between', '1', '10'))
  ok (mt ('Groceries', 'Groceries', 'contains', 'ROC'))
  ok (mt ('Groceries', 'Groceries', 'not_contains', 'x'))
  ok (mt ('Groceries', 'Groceries', 'starts', 'gro'))
  ok (mt ('Groceries', 'Groceries', 'ends', 'IES'))
  ok (mt ('Groceries', 'Groceries', 'equals', 'groceries'))
  ok (mt (1200, '$1,200.00', 'contains', '1,2'))
  ok (mt (nil, '', 'blank'))
  ok (mt ('', '', 'blank'))
  ok (mt (0, '0', 'not_blank'))
  ok (not mt (nil, '', '>', '0'))
  ok (mt (nil, '', '<>', '0'))
  ok (mt (f.error ('#N/A'), '#N/A', 'error'))
end)

---------------------------------------------------------------------------------------------
-- Helpers for the grid
---------------------------------------------------------------------------------------------

test (
  'the layout places rows and columns, and hidden ones take no room',
  function ()
    local s = sheet_of ()
    local layout = s:layout ()
    eq ({ layout.tops[1], layout.tops[2], layout.tops[101] }, { 0, 24, 2400 })
    eq (layout.lefts[27], 2600)
    ok (s:layout () == layout)
    s:set_height (2, 40)
    s:set_hidden ('row', 3, 3, true)
    s:set_width (1, 50)
    layout = s:layout ()
    eq ({ layout.tops[3], layout.tops[4], layout.tops[5] }, { 64, 64, 88 })
    eq (layout.lefts[2], 50)
    eq (
      { s:row_at (0), s:row_at (23), s:row_at (24), s:row_at (63) },
      { 1, 1, 2, 2 }
    )
    -- A hidden row is never the one found.
    eq ({ s:row_at (64), s:row_at (70) }, { 4, 4 })
    eq ({ s:row_at (-5), s:row_at (99999) }, { 1, 100 })
    eq ({ s:col_at (49), s:col_at (50), s:col_at (149) }, { 1, 2, 2 })
    s:set_hidden ('row', 99, 100, true)
    eq (s:row_at (99999), 98)
  end
)

test ('a selection grows to take whole merges', function ()
  local s = sheet_of ()
  s:merge (r ('B2:C3'))
  s:merge (r ('C4:D4'))
  eq (s:expand_to_merges (r ('A1:B2')), r ('A1:C3'))
  eq (s:expand_to_merges (r ('C3:C4')), r ('B2:D4'))
  eq (s:expand_to_merges (r ('F6')), r ('F6'))
end)

test ('moving by one skips hidden rows and merged cells', function ()
  local s = sheet_of ()
  s:set_hidden ('row', 3, 4, true)
  s:set_hidden ('col', 2, 2, true)
  s:merge (r ('D6:E7'))
  eq ({ s:next_visible (2, 1, 1, 0) }, { 5, 1 })
  eq ({ s:next_visible (5, 1, -1, 0) }, { 2, 1 })
  eq ({ s:next_visible (1, 1, 0, 1) }, { 1, 3 })
  eq ({ s:next_visible (6, 3, 0, 1) }, { 6, 4 })
  eq ({ s:next_visible (6, 4, 0, 1) }, { 6, 6 })
  eq ({ s:next_visible (7, 5, 1, 0) }, { 8, 5 })
  eq ({ s:next_visible (1, 1, -1, 0) }, { 1, 1 })
end)

test ('parse_ref reads the name box, with or without a sheet', function ()
  eq ({ m.parse_ref ('b2') }, { r ('B2') })
  eq ({ m.parse_ref (' B9:A2 ') }, { r ('A2:B9') })
  eq ({ m.parse_ref ('Data!A1') }, { r ('A1'), 'Data' })
  eq ({ m.parse_ref ("'Q1 sales'!A1:B9") }, { r ('A1:B9'), 'Q1 sales' })
  eq ({ m.parse_ref ('A:A') }, {})
  eq ({ m.parse_ref ('A1+B2') }, {})
  eq ({ m.parse_ref ('hello') }, {})
end)

test ('the book counts edits, undos and redos for saving', function ()
  local s = sheet_of ()
  local book = s.book
  eq (book.edits, 0)
  s:set (1, 1, 'x')
  s:set (1, 1, 'x')
  eq (book.edits, 1)
  book:undo ()
  book:redo ()
  eq (book.edits, 3)
  book:set_active (1)
  eq (book.edits, 3)
end)
