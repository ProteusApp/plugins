-- Tests for sheet_ops: sort, filter, find and replace, fill series, conditional formatting,
-- validation, charts, Excel and CSV, auto-fit and the drawing helper. Each change is one undo
-- step, and the tests undo them.

local B = require ('sheet_book') --[[@as Sheet.BookModule]]
local f = require ('sheet_formula') --[[@as Sheet.FormulaModule]]
local m = require ('sheet_model') --[[@as Sheet.ModelModule]]
local ops = require ('sheet_ops') --[[@as Sheet.OpsModule]]

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
---@return string
local function text (s, addr)
  local row, col = at (addr)
  return s:text (row, col)
end

---@param s Sheet.Sheet
---@param addr string
---@return string
local function shown (s, addr)
  local row, col = at (addr)
  return (s:display (row, col))
end

---The texts of a column from row `r1` to `r2`.
---@param s Sheet.Sheet
---@param col string
---@param r1 integer
---@param r2 integer
---@return string[]
local function column (s, col, r1, r2)
  local out = {} ---@type string[]
  local c = m.col_number (col) --[[@as integer]]
  for row = r1, r2 do
    out[#out + 1] = s:text (row, c)
  end
  return out
end

---------------------------------------------------------------------------------------------
-- Sort
---------------------------------------------------------------------------------------------

test (
  'sort puts numbers, text, booleans, errors and blanks in that order',
  function ()
    local s = sheet_of ({
      A1 = 'Key',
      A2 = 'pear',
      A3 = '10',
      A4 = 'TRUE',
      A6 = '=1/0',
      A7 = '2',
      A8 = 'Apple',
    })
    ok (ops.sort (s, r ('A1:A8'), { { col = 1 } }, { header = true }))
    eq (
      column (s, 'A', 1, 8),
      { 'Key', '2', '10', 'Apple', 'pear', 'TRUE', '=1/0', '' }
    )
    ok (
      ops.sort (s, r ('A1:A8'), { { col = 1, desc = true } }, { header = true })
    )
    eq (
      column (s, 'A', 1, 8),
      { 'Key', '=1/0', 'TRUE', 'pear', 'Apple', '10', '2', '' }
    )
    s:undo ()
    eq (column (s, 'A', 2, 3), { '2', '10' })
  end
)

test ('sort by two keys keeps equal rows in their order', function ()
  local s = sheet_of ({
    A1 = 'b',
    B1 = '2',
    C1 = '1',
    A2 = 'a',
    B2 = '2',
    C2 = '2',
    A3 = 'b',
    B3 = '1',
    C3 = '3',
    A4 = 'a',
    B4 = '1',
    C4 = '4',
    A5 = 'A',
    B5 = '1',
    C5 = '5',
  })
  ops.sort (s, r ('A1:C5'), { { col = 1 }, { col = 2, desc = true } })
  eq (column (s, 'C', 1, 5), { '2', '4', '5', '1', '3' })
end)

test (
  'sorted rows take their styles, heights, notes and moved formulas',
  function ()
    local s = sheet_of ({
      A1 = '3',
      B1 = '=A1*2',
      A2 = '1',
      B2 = '=A2*2',
      A3 = '2',
      B3 = '=$A$1',
    })
    s:set_style (r ('A1'), { bold = true })
    s:set_height (1, 40)
    s:set_note (1, 2, 'Was first.')
    local steps = #s.book.done
    ok (ops.sort (s, r ('A1:B3'), { { col = 1 } }))
    eq (#s.book.done, steps + 1)
    eq (column (s, 'A', 1, 3), { '1', '2', '3' })
    eq (column (s, 'B', 1, 3), { '=A1*2', '=$A$1', '=A3*2' })
    ok (s:is_bold (3, 1) and not s:is_bold (1, 1))
    eq ({ s:height (1), s:height (3) }, { 24, 40 })
    eq (s:note (3, 2), 'Was first.')
    eq (shown (s, 'B3'), '6')
    -- A block already in order makes no step.
    ok (ops.sort (s, r ('A1:B3'), { { col = 1 } }))
    eq (#s.book.done, steps + 1)
    s:undo ()
    eq (column (s, 'A', 1, 3), { '3', '1', '2' })
    eq (s:height (1), 40)
  end
)

test (
  'remove duplicates keeps the first of each and moves the rest up',
  function ()
    local s = sheet_of ({
      A1 = 'Name',
      B1 = 'City',
      A2 = 'Ann',
      B2 = 'Oslo',
      A3 = 'ann',
      B3 = 'OSLO',
      A4 = 'Bob',
      B4 = 'Rome',
      A5 = 'Ann',
      B5 = 'Rome',
      C5 = '=B5',
    })
    eq (
      { ops.remove_duplicates (s, r ('A1:C5'), { header = true }) },
      { 1, nil }
    )
    eq (column (s, 'A', 1, 5), { 'Name', 'Ann', 'Bob', 'Ann', '' })
    eq (column (s, 'C', 1, 5), { '', '', '', '=B4', '' })
    s:undo ()
    eq (column (s, 'A', 1, 5), { 'Name', 'Ann', 'ann', 'Bob', 'Ann' })
    -- Only the Name column counts as the key.
    local removed = ops.remove_duplicates (s, r ('A2:B5'), { cols = { 1 } })
    eq (removed, 2)
    eq (column (s, 'A', 2, 5), { 'Ann', 'Bob', '', '' })
    eq (column (s, 'B', 2, 5), { 'Oslo', 'Rome', '', '' })
    eq ({ ops.remove_duplicates (s, r ('A2:B5'), { cols = { 1 } }) }, { 0, nil })
  end
)

test ('sort across columns by a row, and merges are refused', function ()
  local s =
    sheet_of ({ A1 = 'c', B1 = 'a', C1 = 'b', A2 = '3', B2 = '1', C2 = '2' })
  s:set_width (1, 150)
  ok (ops.sort (s, r ('A1:C2'), { { row = 1 } }, { across = true }))
  eq ({ text (s, 'A1'), text (s, 'B1'), text (s, 'C1') }, { 'a', 'b', 'c' })
  eq ({ text (s, 'A2'), text (s, 'C2') }, { '1', '3' })
  eq (s:width (3), 150)
  s:merge (r ('A5:B5'))
  eq ({ ops.sort (s, r ('A4:B6'), { { col = 1 } }) }, {
    false,
    'Unmerge the cells in the block before sorting it.',
  })
end)

---------------------------------------------------------------------------------------------
-- Filter
---------------------------------------------------------------------------------------------

---@return Sheet.Sheet
local function table_sheet ()
  return sheet_of ({
    A1 = 'Item',
    B1 = 'Cost',
    C1 = 'Status',
    A2 = 'Rent',
    B2 = '1200',
    C2 = 'OK',
    A3 = 'Food',
    B3 = '450',
    C3 = 'Over',
    A4 = 'Power',
    B4 = '160',
    C4 = 'OK',
    A5 = 'Fun',
    B5 = '212',
    C5 = 'Over',
    A6 = 'Misc',
    C6 = 'OK',
  })
end

test ('a filter hides rows by value and by condition', function ()
  local s = table_sheet ()
  local filter = ops.filter_around (s, 3, 2)
  eq (filter.rect, r ('A1:C6'))
  ok (not s:row_hidden (2))
  ok (ops.filter_column (s, 3, { values = { 'Over' } }))
  eq (s.filter and s.filter.hidden, { [2] = true, [4] = true, [6] = true })
  ok (s:row_hidden (2) and s:filtered (2) and not s.hidden_rows[2])
  ok (ops.filter_column (s, 2, { op = '>', value = '300' }))
  eq (s.filter and s.filter.hidden, {
    [2] = true,
    [4] = true,
    [5] = true,
    [6] = true,
  })
  -- The menu lists what the other columns leave, and marks what this one keeps.
  eq (ops.filter_values (s, 3), {
    { text = 'OK', count = 1, shown = false },
    { text = 'Over', count = 1, shown = true },
  })
  eq (ops.filter_values (s, 2), {
    { text = '212', count = 1, shown = true },
    { text = '450', count = 1, shown = true },
  })
  eq (ops.filter_values (s, 1), {
    { text = 'Food', count = 1, shown = true },
  })
  ok (not ops.filter_column (s, 9, { values = {} }))
  -- A user-hidden row stays hidden when the filter goes.
  s:set_hidden ('row', 3, 3, true)
  ops.clear_filter (s)
  ok (s:row_hidden (3) and not s:row_hidden (2))
  s:undo ()
  s:undo ()
  ok (s:row_hidden (2))
  s:undo ()
  s:undo ()
  eq (s.filter and s.filter.hidden, {})
  ops.remove_filter (s)
  eq (s.filter, nil)
  s:undo ()
  ok (s.filter ~= nil)
end)

test ('a filter keeps its rows until it is applied again', function ()
  local s = table_sheet ()
  ops.set_filter (s, r ('A1:C6'))
  ops.filter_column (s, 3, { values = { 'OK' } })
  eq (s.filter and s.filter.hidden, { [3] = true, [5] = true })
  s:set (2, 3, 'Over')
  ok (not s:row_hidden (2))
  ok (ops.reapply_filter (s))
  ok (s:row_hidden (2))
  ok (not ops.reapply_filter (s))
  eq (ops.filter_values (s, 3), {
    { text = 'OK', count = 2, shown = true },
    { text = 'Over', count = 3, shown = false },
  })
end)

test ('sorting a filtered block keeps the right rows hidden', function ()
  local s = table_sheet ()
  ops.set_filter (s, r ('A1:C6'))
  ops.filter_column (s, 3, { values = { 'Over' } })
  ok (ops.sort (s, r ('A1:C6'), { { col = 2 } }, { header = true }))
  -- Costs go 160, 212, 450, 1200, blank. Only Fun and Food say Over.
  eq (column (s, 'A', 2, 6), { 'Power', 'Fun', 'Food', 'Rent', 'Misc' })
  eq (s.filter and s.filter.hidden, { [2] = true, [5] = true, [6] = true })
  s:undo ()
  eq (s.filter and s.filter.hidden, { [2] = true, [4] = true, [6] = true })
end)

---------------------------------------------------------------------------------------------
-- Find and replace
---------------------------------------------------------------------------------------------

---@return Sheet.Book
local function find_book ()
  local book = B.new ({ clock = clock, name = 'One' })
  local one = book.sheets[1]
  one:put (1, 1, { text = 'Apple pie' })
  one:put (2, 2, { text = 'apple' })
  one:put (3, 1, { text = '=UPPER("apple")' })
  one:put (4, 1, { text = '1200' })
  one:set_format (r ('A4'), '$#,##0')
  local two = assert (book:add_sheet ('Two'))
  two:put (1, 1, { text = 'Pineapple' })
  book.done = {}
  book.active = 1
  return book
end

---@param list Sheet.Match[]
---@return string[]
local function places (list)
  local out = {} ---@type string[]
  for i, match in ipairs (list) do
    out[i] = match.sheet.name .. '!' .. m.address (match.row, match.col)
  end
  return out
end

test ('find looks in shown values or in formulas, in reading order', function ()
  local book = find_book ()
  eq (
    places (ops.find_all (book, 'apple')),
    { 'One!A1', 'One!B2', 'One!A3', 'Two!A1' }
  )
  eq (places (ops.find_all (book, 'apple', { formulas = true })), {
    'One!A1',
    'One!B2',
    'One!A3',
    'Two!A1',
  })
  eq (places (ops.find_all (book, 'APPLE', { case = true })), { 'One!A3' })
  eq (places (ops.find_all (book, 'apple', { whole = true })), {
    'One!B2',
    'One!A3',
  })
  eq (
    places (ops.find_all (book, 'apple', { whole = true, case = true })),
    { 'One!B2' }
  )
  eq (places (ops.find_all (book, '$1,200')), { 'One!A4' })
  eq (places (ops.find_all (book, '$1,200', { formulas = true })), {})
  eq (
    places (ops.find_all (book, 'p', { sheet = book.sheets[2] })),
    { 'Two!A1' }
  )
  -- The search is literal, not a Lua pattern.
  book.sheets[1]:put (5, 1, { text = 'a.b%c' })
  eq (places (ops.find_all (book, '.b%')), { 'One!A5' })
  eq (ops.find_all (book, ''), {})
end)

test ('find next and previous go round', function ()
  local book = find_book ()
  local one = book.sheets[1]
  local hit =
    assert (ops.find_next (book, 'apple', { sheet = one, row = 1, col = 1 }))
  eq (places ({ hit }), { 'One!B2' })
  hit =
    assert (ops.find_next (book, 'apple', { sheet = one, row = 3, col = 1 }))
  eq (places ({ hit }), { 'Two!A1' })
  hit = assert (
    ops.find_next (book, 'apple', { sheet = book.sheets[2], row = 1, col = 1 })
  )
  eq (places ({ hit }), { 'One!A1' })
  hit = assert (
    ops.find_next (book, 'apple', { sheet = one, row = 1, col = 1 }, nil, true)
  )
  eq (places ({ hit }), { 'Two!A1' })
  eq (ops.find_next (book, 'kiwi', { sheet = one, row = 1, col = 1 }), nil)
end)

test ('replace one or all, as one step', function ()
  local book = find_book ()
  local one = book.sheets[1]
  local hit = ops.find_all (book, 'apple')[1]
  ok (ops.replace (book, hit, 'apple', 'Cherry'))
  eq (text (one, 'A1'), 'Cherry pie')
  eq (#book.done, 1)
  book:undo ()
  -- Formulas change only when asked.
  eq (ops.replace_all (book, 'apple', 'pear'), 3)
  eq (text (one, 'A3'), '=UPPER("apple")')
  eq (text (book.sheets[2], 'A1'), 'Pinepear')
  eq (#book.done, 1)
  book:undo ()
  eq (text (one, 'B2'), 'apple')
  eq (
    ops.replace_all (book, 'apple', 'pear', { formulas = true, case = true }),
    3
  )
  eq (text (one, 'A3'), '=UPPER("pear")')
  eq (text (one, 'A1'), 'Apple pie')
  book:undo ()
  eq (ops.replace_all (book, 'apple', 'kiwi', { whole = true }), 1)
  eq (text (one, 'B2'), 'kiwi')
  -- A replaced text reads again as if typed.
  eq (ops.replace_all (book, 'kiwi', '15%'), 1)
  eq (shown (one, 'B2'), '15%')
end)

---------------------------------------------------------------------------------------------
-- Fill series
---------------------------------------------------------------------------------------------

test ('numbers keep their step, and one number repeats', function ()
  local s = sheet_of ({ A1 = '1', A2 = '3', B1 = '5', C1 = '0.1', C2 = '0.2' })
  eq (ops.fill (s, r ('A1:C2'), r ('A1:C5')), r ('A1:C5'))
  eq (column (s, 'A', 3, 5), { '5', '7', '9' })
  eq (column (s, 'B', 1, 5), { '5', '', '5', '', '5' })
  eq (column (s, 'C', 3, 5), { '0.3', '0.4', '0.5' })
  s:undo ()
  eq (text (s, 'A3'), '')
  -- A series asked for counts up from one number.
  ops.fill (s, r ('B1'), r ('B1:B3'), { series = true })
  eq (column (s, 'B', 1, 3), { '5', '6', '7' })
  -- Up and left run the series backward.
  ops.fill (s, r ('A1:A2'), r ('A1:A2'))
  eq (ops.fill (s, r ('A1:A2'), r ('A1:A2')), nil)
  local t = sheet_of ({ C5 = '10', C6 = '20', E1 = '4', F1 = '6' })
  ops.fill (t, r ('C5:C6'), r ('C2:C6'))
  eq (column (t, 'C', 2, 4), { '-20', '-10', '0' })
  ops.fill (t, r ('E1:F1'), r ('B1:F1'))
  eq ({ text (t, 'B1'), text (t, 'C1'), text (t, 'D1') }, { '-2', '0', '2' })
end)

test ('dates, day names, month names and numbered text continue', function ()
  local s = sheet_of ({
    B1 = 'Mon',
    C1 = 'monday',
    D1 = 'JAN',
    E1 = 'Item 1',
    F1 = 'Q1',
    G1 = 'Box 08',
    H1 = 'Sat',
    I1 = 'Mar',
    I2 = 'Jun',
  })
  s:set (1, 1, '9/29/2026')
  ops.fill (s, r ('A1:I1'), r ('A1:I4'))
  eq (column (s, 'B', 2, 4), { 'Tue', 'Wed', 'Thu' })
  eq (column (s, 'C', 2, 3), { 'tuesday', 'wednesday' })
  eq (column (s, 'D', 2, 3), { 'FEB', 'MAR' })
  eq (column (s, 'E', 2, 3), { 'Item 2', 'Item 3' })
  eq (column (s, 'F', 2, 3), { 'Q2', 'Q3' })
  eq (column (s, 'G', 2, 3), { 'Box 09', 'Box 10' })
  eq (column (s, 'H', 2, 3), { 'Sun', 'Mon' })
  eq ({ shown (s, 'A2'), shown (s, 'A4') }, { '9/30/2026', '10/2/2026' })
  -- Two dates keep their step in days, and two months theirs.
  local t = sheet_of ({ A1 = 'Mar', A2 = 'Jun' })
  t:set (1, 2, '9/1/2026')
  t:set (2, 2, '9/8/2026')
  ops.fill (t, r ('A1:B2'), r ('A1:B4'))
  eq (column (t, 'A', 3, 4), { 'Sep', 'Dec' })
  eq ({ shown (t, 'B3'), shown (t, 'B4') }, { '9/15/2026', '9/22/2026' })
end)

test (
  'fill repeats anything else, moving formulas and copying styles',
  function ()
    local s = sheet_of ({ A1 = '=B1*2', A2 = 'x', B1 = '1', B2 = '2' })
    s:set_style (r ('A1'), { bold = true })
    ops.fill (s, r ('A1:A2'), r ('A1:A6'))
    eq (column (s, 'A', 3, 6), { '=B3*2', 'x', '=B5*2', 'x' })
    ok (s:is_bold (3, 1) and s:is_bold (5, 1) and not s:is_bold (4, 1))
    ops.fill (s, r ('A1:A1'), r ('A1:C1'))
    eq (text (s, 'C1'), '=D1*2')
    eq (#s.book.done, 3)
  end
)

---------------------------------------------------------------------------------------------
-- Conditional formatting
---------------------------------------------------------------------------------------------

test ('rules add styles to the cells they match', function ()
  local s = sheet_of ({
    A1 = '5',
    A2 = '-3',
    A3 = '0',
    A4 = 'apple pie',
    A5 = '=1/0',
    B1 = 'x',
    B2 = 'y',
    B3 = 'x',
  })
  ops.add_rule (s, {
    range = 'A1:A5',
    type = 'compare',
    op = '>',
    value = '0',
    style = { color = '#c62828' },
  })
  ops.add_rule (s, {
    range = 'A1:A5',
    type = 'text',
    op = 'contains',
    value = 'PIE',
    style = { bold = true },
  })
  ops.add_rule (
    s,
    { range = 'A1:A6', type = 'blank', style = { fill = '#eeeeee' } }
  )
  ops.add_rule (
    s,
    { range = 'A1:A6', type = 'error', style = { italic = true } }
  )
  ops.add_rule (
    s,
    { range = 'B1:B3', type = 'duplicate', style = { fill = '#ffcccc' } }
  )
  ops.add_rule (
    s,
    { range = 'B1:B3', type = 'unique', style = { fill = '#ccffcc' } }
  )
  eq (ops.rule_look (s, 1, 1), { style = { color = '#c62828' } })
  eq (ops.rule_look (s, 2, 1), nil)
  eq (ops.rule_look (s, 4, 1), { style = { bold = true } })
  eq (ops.rule_look (s, 6, 1), { style = { fill = '#eeeeee' } })
  eq (ops.rule_look (s, 5, 1), { style = { italic = true } })
  eq (ops.rule_look (s, 1, 2), { style = { fill = '#ffcccc' } })
  eq (ops.rule_look (s, 2, 2), { style = { fill = '#ccffcc' } })
  -- A new rule goes on top of the list.
  eq (ops.rules_at (s, 2, 1), { 3, 4, 5, 6 })
  eq (s.rules[1].type, 'unique')
  -- The rule higher in the list wins on the same field, as in Excel.
  ops.add_rule (s, {
    range = 'A1',
    type = 'not_blank',
    style = { color = '#000000' },
  })
  eq (ops.rule_look (s, 1, 1), { style = { color = '#000000' } })
  ops.set_rule (s, 1, nil)
  eq (#s.rules, 6)
  eq (ops.rule_look (s, 1, 1), { style = { color = '#c62828' } })
  s:undo ()
  eq (#s.rules, 7)
end)

test ('stop if true keeps the rules below from applying', function ()
  local s = sheet_of ({ A1 = '5', A2 = '-5' })
  s:set_field ('rules', {
    {
      range = 'A1:A2',
      type = 'compare',
      op = '>',
      value = '0',
      style = { bold = true },
      stop = true,
    },
    { range = 'A1:A2', type = 'not_blank', style = { italic = true } },
    { range = 'A1:A2', type = 'bar' },
  })
  eq (ops.rule_look (s, 1, 1), { style = { bold = true } })
  eq (
    ops.rule_look (s, 2, 1),
    { style = { italic = true }, bar = 0, bar_color = '#638ec6' }
  )
end)

test ('a file from before version 3 turns its rules round', function ()
  local file = table.concat ({
    '{ "version": 2, "sheets": [ { "name": "Old", "cells": { "A1": "5" }, "rules": [',
    '{ "range": "A1", "type": "not_blank", "style": { "color": "#111111" } },',
    '{ "range": "A1", "type": "not_blank", "style": { "color": "#222222" } }',
    '] } ] }',
  })
  local book = assert (B.decode (file))
  local s = book.sheets[1]
  -- In version 2 the later rule won, so it comes first now, and still wins.
  eq (s.rules[1].style, { color = '#222222' })
  eq (ops.rule_look (s, 1, 1), { style = { color = '#222222' } })
  local again = assert (B.decode (B.encode (book)))
  eq (again.sheets[1].rules[1].style, { color = '#222222' })
end)

test ('top, bottom and average rules look at the whole range', function ()
  local s = sheet_of ({ A1 = '10', A2 = '40', A3 = '20', A4 = '30', A5 = 'x' })
  s:set_field ('rules', {
    { range = 'A1:A5', type = 'top', count = 2, style = { bold = true } },
    {
      range = 'A1:A5',
      type = 'bottom',
      count = 25,
      percent = true,
      style = { italic = true },
    },
    { range = 'A1:A5', type = 'above_average', style = { color = '#ff0000' } },
  })
  eq (ops.rule_look (s, 2, 1), { style = { bold = true, color = '#ff0000' } })
  eq (ops.rule_look (s, 4, 1), { style = { bold = true, color = '#ff0000' } })
  eq (ops.rule_look (s, 1, 1), { style = { italic = true } })
  eq (ops.rule_look (s, 3, 1), nil)
  -- A change in the range moves the top two.
  s:set (3, 1, '100')
  eq (ops.rule_look (s, 3, 1), { style = { bold = true, color = '#ff0000' } })
  eq (ops.rule_look (s, 4, 1), nil)
end)

test ('a formula rule moves for each cell of its range', function ()
  local s = sheet_of ({
    B5 = '50',
    B6 = '150',
    B7 = '200',
    C5 = 'a',
    C6 = 'b',
    C7 = 'c',
  })
  s:set_field ('rules', {
    {
      range = 'C5:C7',
      type = 'formula',
      formula = '=$B5>100',
      style = { bold = true },
    },
  })
  eq (ops.rule_look (s, 5, 3), nil)
  eq (ops.rule_look (s, 6, 3), { style = { bold = true } })
  eq (ops.rule_look (s, 7, 3), { style = { bold = true } })
end)

test ('colour scales and data bars', function ()
  local s =
    sheet_of ({ A1 = '0', A2 = '50', A3 = '100', B1 = '-10', B2 = '10' })
  s:set_field ('rules', {
    {
      range = 'A1:A3',
      type = 'scale',
      min_color = '#000000',
      max_color = '#ffffff',
    },
    { range = 'B1:B2', type = 'bar', color = '#0000ff' },
  })
  eq (ops.rule_look (s, 1, 1), { fill = '#000000' })
  eq (ops.rule_look (s, 2, 1), { fill = '#808080' })
  eq (ops.rule_look (s, 3, 1), { fill = '#ffffff' })
  eq (ops.rule_look (s, 1, 2), { bar = 0, bar_color = '#0000ff' })
  eq (ops.rule_look (s, 2, 2), { bar = 1, bar_color = '#0000ff' })
  s:set_field ('rules', {
    {
      range = 'A1:A3',
      type = 'scale',
      min_color = '#000000',
      mid_color = '#ff0000',
      max_color = '#ffffff',
    },
  })
  eq (ops.rule_look (s, 2, 1), { fill = '#ff0000' })
  eq (ops.rule_look (s, 3, 1), { fill = '#ffffff' })
end)

---------------------------------------------------------------------------------------------
-- Validation
---------------------------------------------------------------------------------------------

test ('validation checks text before it goes in', function ()
  local s = sheet_of ()
  ops.add_validation (
    s,
    { range = 'A1:A5', type = 'list', values = { 'OK', 'Over' } }
  )
  ops.add_validation (s, {
    range = 'B1:B5',
    type = 'number',
    op = 'between',
    value = '1',
    value2 = '10',
    integer = true,
  })
  ops.add_validation (s, {
    range = 'C1',
    type = 'number',
    op = '>',
    value = '0',
    message = 'Costs are positive.',
    strict = false,
  })
  eq ({ ops.check_input (s, 1, 1, 'ok') }, { true })
  eq ({ ops.check_input (s, 1, 1, 'Maybe') }, {
    false,
    'Pick one of: OK, Over.',
    true,
  })
  eq ({ ops.check_input (s, 1, 1, '') }, { true })
  eq ({ ops.check_input (s, 1, 1, '=A2') }, { true })
  eq (ops.dropdown (s, 2, 1), { 'OK', 'Over' })
  eq (ops.dropdown (s, 2, 2), nil)
  eq ({ ops.check_input (s, 2, 2, '5') }, { true })
  eq ({ ops.check_input (s, 2, 2, '5.5') }, {
    false,
    'Enter a whole number from 1 to 10.',
    true,
  })
  eq ({ ops.check_input (s, 2, 2, 'eleven') }, {
    false,
    'Enter a whole number from 1 to 10.',
    true,
  })
  eq (
    { ops.check_input (s, 1, 3, '-4') },
    { false, 'Costs are positive.', false }
  )
  eq ({ ops.check_input (s, 9, 9, 'anything') }, { true })
  local v, i = ops.validation_at (s, 1, 3)
  eq ({ v and v.message, i }, { 'Costs are positive.', 3 })
  ops.set_validation (s, 1, nil)
  eq (ops.dropdown (s, 2, 1), nil)
  s:undo ()
  eq (ops.dropdown (s, 2, 1), { 'OK', 'Over' })
end)

test (
  'validation takes a list from cells, dates, text lengths and formulas',
  function ()
    local book = B.new ({ clock = clock })
    local s = book.sheets[1]
    local lists = assert (book:add_sheet ('Lists'))
    for i, item in ipairs ({ 'Red', 'Green', '', 'Red', 'Blue' }) do
      lists:put (i, 1, { text = item })
    end
    s:put (1, 5, { text = '10' })
    ops.add_validation (
      s,
      { range = 'A1:A9', type = 'list', formula = '=Lists!$A$1:$A$5' }
    )
    ops.add_validation (s, {
      range = 'B1:B9',
      type = 'date',
      op = 'between',
      value = '1/1/2026',
      value2 = '12/31/2026',
    })
    ops.add_validation (
      s,
      { range = 'C1:C9', type = 'length', op = '<=', value = '5' }
    )
    -- The formula is written for C... D1, and each cell reads its own row.
    ops.add_validation (s, {
      range = 'D1:D9',
      type = 'formula',
      formula = '=AND(ISNUMBER(D1), D1<=$E$1)',
    })
    eq (ops.dropdown (s, 1, 1), { 'Red', 'Green', 'Blue' })
    eq ({ ops.check_input (s, 3, 1, 'green') }, { true })
    eq ({ ops.check_input (s, 3, 1, 'Pink') }, {
      false,
      'Pick one of: Red, Green, Blue.',
      true,
    })
    -- The list follows its cells.
    lists:set (3, 1, 'Pink')
    eq ({ ops.check_input (s, 3, 1, 'Pink') }, { true })
    eq ({ ops.check_input (s, 1, 2, '3/15/2026') }, { true })
    eq ({ ops.check_input (s, 1, 2, '3/15/2027') }, {
      false,
      'Enter a date from 1/1/2026 to 12/31/2026.',
      true,
    })
    eq ({ ops.check_input (s, 1, 2, 'soon') }, {
      false,
      'Enter a date from 1/1/2026 to 12/31/2026.',
      true,
    })
    eq ({ ops.check_input (s, 1, 3, 'short') }, { true })
    eq ({ ops.check_input (s, 1, 3, 'é1234') }, { true })
    eq ({ ops.check_input (s, 1, 3, 'longer') }, {
      false,
      'Enter text with a length at most 5.',
      true,
    })
    eq ({ ops.check_input (s, 4, 4, '7') }, { true })
    eq ({ ops.check_input (s, 4, 4, '12') }, {
      false,
      'The value breaks the rule =AND(ISNUMBER(D1), D1<=$E$1).',
      true,
    })
    eq ({ ops.check_input (s, 4, 4, 'x') }, {
      false,
      'The value breaks the rule =AND(ISNUMBER(D1), D1<=$E$1).',
      true,
    })
    -- Renaming the sheet of a list keeps the list.
    ok (book:rename_sheet (2, 'Colours'))
    eq (s.validation[1].formula, '=Colours!$A$1:$A$5')
    eq (ops.dropdown (s, 1, 1), { 'Red', 'Green', 'Pink', 'Blue' })
    -- Inserting a row above the list's cells moves its reference.
    lists:insert_rows (1, 1)
    eq (s.validation[1].formula, '=Colours!$A$2:$A$6')
  end
)

---------------------------------------------------------------------------------------------
-- Charts
---------------------------------------------------------------------------------------------

test ('a chart reads its range and changes as one step each', function ()
  local s = sheet_of ({
    A1 = 'Item',
    B1 = 'Cost',
    A2 = 'Rent',
    B2 = '1200',
    A3 = 'Food',
    B3 = '450',
    A4 = 'Fun',
    B4 = '212',
  })
  s:set_format (r ('B2:B4'), '$#,##0')
  local wanted = { type = 'bar', range = 'A1:B4' } ---@type any
  local spec = ops.add_chart (s, wanted)
  eq ({ spec.id, spec.x, spec.w }, { 'c1', 40, 480 })
  eq (ops.chart_values (s, spec), {
    { 'Item', 'Cost' },
    { 'Rent', 1200 },
    { 'Food', 450 },
    { 'Fun', 212 },
  })
  s:set_hidden ('row', 3, 3, true)
  local data = ops.chart_data (s, spec)
  eq (data.categories, { 'Rent', 'Fun' })
  eq (data.series, { { name = 'Cost', values = { 1200, 212 } } })
  eq (ops.chart_format (s, spec) (1500), '$1,500')
  ok (string.find (ops.chart_svg (s, spec), '<svg', 1, true))
  ok (ops.update_chart (s, 'c1', { x = 300, title = 'Costs', id = 'nope' }))
  eq (
    { s.charts[1].x, s.charts[1].title, s.charts[1].id },
    { 300, 'Costs', 'c1' }
  )
  ok (ops.update_chart (s, 'c1', { series_in = 'rows' }))
  ok (ops.update_chart (s, 'c1', { legend = 'top' }, { 'series_in', 'id' }))
  eq (
    { s.charts[1].series_in, s.charts[1].legend, s.charts[1].id },
    { nil, 'top', 'c1' }
  )
  s:undo ()
  s:undo ()
  local again = { id = 'c1', range = 'A1:B2' } ---@type any
  eq (ops.add_chart (s, again).id, 'c2')
  ok (ops.delete_chart (s, 'c1'))
  ok (not ops.delete_chart (s, 'c1'))
  ok (not ops.update_chart (s, 'zz', {}))
  eq (#s.charts, 1)
  s:undo ()
  s:undo ()
  s:undo ()
  eq (s.charts[1].x, 40)
end)

---------------------------------------------------------------------------------------------
-- Excel and CSV
---------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------
-- Moving cells
---------------------------------------------------------------------------------------------

---Cuts a block and pastes it with its top left cell at `to`.
---@param from_sheet Sheet.Sheet
---@param block string
---@param to_sheet Sheet.Sheet
---@param to string
local function move (from_sheet, block, to_sheet, to)
  local clip = from_sheet:copy (r (block))
  clip.cut = true
  local row, col = at (to)
  to_sheet:paste (row, col, clip)
end

test ('a cut and paste points other formulas where the cells went', function ()
  local s = sheet_of ({
    A1 = '5',
    A2 = '7',
    B1 = '=A1*2',
    B2 = '=SUM(A1:A2)',
    B3 = '=SUM(A1:A3)',
    B4 = '=$A$1+1',
    B5 = '=E1',
    B6 = '=A1:A2',
  })
  move (s, 'A1:A2', s, 'E1')
  -- A reference inside the block moves, $ or not. A range that sticks out stays.
  eq (text (s, 'B1'), '=E1*2')
  eq (text (s, 'B2'), '=SUM(E1:E2)')
  eq (text (s, 'B3'), '=SUM(A1:A3)')
  eq (text (s, 'B4'), '=$E$1+1')
  -- A reference to a cell the block lands on is gone.
  eq (text (s, 'B5'), '=#REF!')
  eq (shown (s, 'B1'), '10')
  eq (shown (s, 'B2'), '12')
  -- The whole move is one undo step.
  s:undo ()
  eq (
    { text (s, 'A1'), text (s, 'E1'), text (s, 'B1'), text (s, 'B5') },
    { '5', '', '=A1*2', '=E1' }
  )
end)

test (
  'a drag that moves cells inside their own block keeps references right',
  function ()
    local s = sheet_of ({ A1 = '1', A2 = '=A1+1', A3 = '=A2+1', C1 = '=A3' })
    move (s, 'A1:A3', s, 'A2')
    eq ({ text (s, 'A1'), text (s, 'A2'), text (s, 'A3'), text (s, 'A4') }, {
      '',
      '1',
      '=A2+1',
      '=A3+1',
    })
    eq (text (s, 'C1'), '=A4')
    eq (shown (s, 'C1'), '3')
  end
)

test ('a cut to another sheet follows the cells across the book', function ()
  local book = B.new ({ clock = clock, name = 'Data' })
  local data = book.sheets[1]
  local other = assert (book:add_sheet ('Q1 sales'))
  data:put (1, 1, { text = '4' })
  data:put (1, 2, { text = '=A1+C1' })
  data:put (1, 3, { text = '10' })
  other:put (1, 1, { text = '=Data!A1*3' })
  other:put (2, 1, { text = '=C5' })
  move (data, 'A1:B1', other, 'B5')
  eq (data:text (1, 1), '')
  -- A reference on another sheet to the moved cell now names where it went.
  eq (other:text (1, 1), '=B5*3')
  eq (other:text (2, 1), '=#REF!')
  -- The moved formula reads A1 where it went, and C1 on the sheet it came from.
  eq (other:text (5, 3), '=B5+Data!C1')
  eq (other:value (5, 3), 14)
  data:put (2, 1, { text = "='Q1 sales'!B5" })
  move (other, 'B5', data, 'D4')
  eq (data:text (2, 1), '=D4')
  eq (other:text (1, 1), '=Data!D4*3')
end)

test (
  'rules, validation, charts and the filter inside a moved block go with it',
  function ()
    local s = sheet_of ({
      A1 = 'Item',
      B1 = 'Cost',
      A2 = 'Rent',
      B2 = '1200',
      A3 = 'Food',
      B3 = '450',
    })
    s:set_field ('rules', {
      {
        range = 'B2:B3',
        type = 'formula',
        formula = '=B2>500',
        style = { bold = true },
      },
      { range = 'B2:D3', type = 'compare', op = '>', value = '0' },
    })
    s:set_field (
      'validation',
      { { range = 'B2:B3', type = 'number', op = '>', value = '0' } }
    )
    s:set_field ('charts', { { id = 'c1', type = 'bar', range = 'A1:B3' } })
    ops.set_filter (s, r ('A1:B3'))
    ops.filter_column (s, 2, { op = '>', value = '500' })
    eq (s.filter and s.filter.hidden, { [3] = true })
    move (s, 'A1:B3', s, 'D11')
    eq (s.rules[1].range, 'E12:E13')
    eq (s.rules[1].formula, '=E12>500')
    -- A rule that only partly lies in the block stays.
    eq (s.rules[2].range, 'B2:D3')
    eq (s.validation[1].range, 'E12:E13')
    eq (s.charts[1].range, 'D11:E13')
    local filter = assert (s.filter, 'a filter')
    eq (filter.rect, r ('D11:E13'))
    eq (filter.columns[5], { op = '>', value = '500' })
    eq (filter.hidden, { [13] = true })
    eq (ops.rule_look (s, 12, 5), { style = { bold = true } })
    s:undo ()
    eq ({ s.rules[1].range, s.charts[1].range }, { 'B2:B3', 'A1:B3' })
    eq ((assert (s.filter, 'a filter')).rect, r ('A1:B3'))
    -- Moved to another sheet, the rules and the validation go along, and the chart stays.
    local other = assert (s.book:add_sheet ('Other'))
    move (s, 'A1:B3', other, 'A1')
    eq ({ #s.rules, #s.validation, #s.charts }, { 1, 0, 1 })
    eq (other.rules[1].range, 'B2:B3')
    eq (other.validation[1].range, 'B2:B3')
    eq (s.filter, nil)
    eq ((assert (other.filter, 'a filter')).rect, r ('A1:B3'))
  end
)

test ('an Excel file round trip keeps cells, formats and values', function ()
  local book = B.example ({ clock = clock })
  local files, warnings = ops.write_xlsx (book)
  ok (files['xl/workbook.xml'])
  ok (
    string.find (
      files['xl/worksheets/sheet1.xml'],
      '<f>SUM(B5:B10)</f><v>2155</v>',
      1,
      true
    )
  )
  ok (#warnings > 0)
  local back, notes = ops.read_xlsx (files, { clock = clock })
  ok (back, tostring (notes))
  local sheet = (back --[[@as Sheet.Book]]).sheets[1]
  eq (sheet:text (11, 2), '=SUM(B5:B10)')
  eq ((sheet:display (11, 2)), '$2,155.00')
  eq ((sheet:display (17, 3)), '$3,200.00')
  eq ({ ops.read_xlsx ({}) }, { nil, 'This file is not an Excel workbook.' })
end)

test (
  'CSV comes in as a new sheet or at a cell, and goes out as shown',
  function ()
    local book = B.new ({ clock = clock, name = 'Data' })
    local sheet =
      ops.import_csv (book, 'Item,Cost\nRent,"$1,200"\nFood,10%\n', 'Data')
    eq (sheet.name, 'Data (2)')
    eq (book.active, 2)
    eq ((sheet:display (2, 2)), '$1,200')
    eq ((sheet:display (3, 2)), '10%')
    eq (ops.import_csv (book, 'a', 'x/y').name, 'xy')
    book:undo ()
    book:undo ()
    eq (book:names (), { 'Data' })
    local s = book.sheets[1]
    eq (ops.paste_csv (s, 2, 2, 'a,b\n1,2'), r ('B2:C3'))
    eq (s:value (3, 3), 2)
    s:put (5, 1, { text = '=1/3' })
    eq (
      ops.export_csv (s),
      ',,\r\n,a,b\r\n,1,2\r\n,,\r\n0.333333333333333,,\r\n'
    )
    eq (ops.export_csv (s, r ('B2:C2'), ';'), 'a;b\r\n')
  end
)

---------------------------------------------------------------------------------------------
-- Auto-fit and drawing
---------------------------------------------------------------------------------------------

test ('column_cells gives auto-fit the shown text and style', function ()
  local s = sheet_of ({
    A1 = '1200',
    A2 = 'Long text here',
    A3 = 'hidden',
    A4 = 'merged',
  })
  s:set_format (r ('A1'), '$#,##0.00')
  s:set_style (r ('A2'), { bold = true, size = 16 })
  s:set_hidden ('row', 3, 3, true)
  s:merge (r ('A4:B4'))
  eq (ops.column_cells (s, 1), {
    { row = 1, text = '$1,200.00', style = { format = '$#,##0.00' } },
    { row = 2, text = 'Long text here', style = { bold = true, size = 16 } },
  })
end)

test ('look gathers what the grid draws', function ()
  local s = sheet_of ({ A1 = '-5', B1 = 'Title', A2 = '50', A3 = '100' })
  s:set_format (r ('A1'), '0;[Red]-0')
  s:set_style (r ('A2'), { fill = '#eeeeee', bold = true })
  s:merge (r ('B1:C1'))
  s:set_note (2, 1, 'Hi')
  s:set_field ('rules', {
    {
      range = 'A2:A3',
      type = 'compare',
      op = '>',
      value = '60',
      style = { italic = true },
    },
    { range = 'A1:A3', type = 'bar' },
  })
  ops.add_validation (s, { range = 'D1', type = 'list', values = { 'a' } })
  local a1 = ops.look (s, 1, 1)
  eq ({ a1.text, a1.align, a1.kind }, { '-5', 'right', 'number' })
  ok (a1.color and a1.bar == 0)
  local a2 = ops.look (s, 2, 1)
  eq (a2.style, { fill = '#eeeeee', bold = true })
  eq ({ a2.fill, a2.note }, { '#eeeeee', true })
  local a3 = ops.look (s, 3, 1)
  eq (a3.style, { italic = true })
  eq (a3.bar, 1)
  eq (ops.look (s, 1, 2).merge, r ('B1:C1'))
  local c1 = ops.look (s, 1, 3)
  eq ({ c1.covered, c1.text }, { true, '' })
  eq (ops.look (s, 1, 4).list, true)
end)
