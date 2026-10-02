-- Tests for sheet_book: sheets in a workbook, formulas across sheets, recalculation that
-- reaches only what an edit changes, one undo history for the book, and the file.

local B = require ('sheet_book') --[[@as Sheet.BookModule]]
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

---A book with a sheet for each entry of `sheets`, in the order of `names`.
---@param names string[]
---@param sheets table<string, table<string, string>>
---@return Sheet.Book
local function book_of (names, sheets)
  local book = B.new ({ clock = clock, name = names[1] })
  for i = 2, #names do
    assert (book:add_sheet (names[i]))
  end
  for i, name in ipairs (names) do
    local sheet = book.sheets[i]
    for addr, text in pairs (sheets[name] or {}) do
      local row, col = at (addr)
      sheet:put (row, col, { text = text })
    end
  end
  book.done, book.undone = {}, {}
  book.active = 1
  return book
end

---@param sheet Sheet.Sheet
---@param addr string
---@return string
local function shown (sheet, addr)
  local row, col = at (addr)
  return (sheet:display (row, col))
end

---@param sheet Sheet.Sheet
---@param addr string
---@return string
local function text (sheet, addr)
  local row, col = at (addr)
  return sheet:text (row, col)
end

---@param sheet Sheet.Sheet
---@param addr string
---@param value string
local function set (sheet, addr, value)
  local row, col = at (addr)
  sheet:set (row, col, value)
end

---------------------------------------------------------------------------------------------
-- Sheets
---------------------------------------------------------------------------------------------

test ('a new book has one sheet, and new sheets take free names', function ()
  local book = B.new ()
  eq (book:names (), { 'Sheet1' })
  eq (book.active, 1)
  local s2 = assert (book:add_sheet ())
  eq (s2.name, 'Sheet2')
  eq (book.active, 2)
  ok (book:active_sheet () == s2)
  local first = assert (book:add_sheet ('First', 1))
  eq (book:names (), { 'First', 'Sheet1', 'Sheet2' })
  ok (book:active_sheet () == first)
  ok (book:find ('first') == first)
  ok (book:sheet ('SHEET2') == s2)
  eq (book:sheet (2).name, 'Sheet1')
  eq (book:index_of (s2), 3)
  -- Each add is one step, and undo takes the sheet away and shows the one before.
  local info = assert (book:undo ())
  eq (book:names (), { 'Sheet1', 'Sheet2' })
  eq (info.sheet, 2)
  eq (book.active, 2)
  book:redo ()
  eq (book:names (), { 'First', 'Sheet1', 'Sheet2' })
  book:set_active (3)
  eq (book.active, 3)
  book:set_active (9)
  eq (book.active, 3)
end)

test ('sheet names follow the rules', function ()
  local book = B.new ()
  eq (book:name_problem (''), 'A sheet needs a name.')
  eq (book:name_problem ('   '), 'A sheet needs a name.')
  eq (
    book:name_problem (string.rep ('x', 101)),
    'A sheet name can have at most 100 characters.'
  )
  ok (book:name_problem (string.rep ('x', 100)) == nil)
  for _, bad in ipairs ({ 'a[b', 'a]b', 'a:b', 'a*b', 'a?b', 'a/b', 'a\\b' }) do
    ok (book:name_problem (bad), bad .. ' should be refused')
  end
  ok (book:name_problem ("'quoted") ~= nil)
  ok (book:name_problem ("quoted'") ~= nil)
  ok (book:name_problem ("it's fine") == nil)
  eq (book:name_problem ('sheet1'), 'Another sheet is called Sheet1.')
  -- A sheet may keep its own name in another case.
  ok (book:name_problem ('SHEET1', book.sheets[1]) == nil)
  eq ({ book:add_sheet ('SHEET1') }, { nil, 'Another sheet is called Sheet1.' })
  eq ({ book:rename_sheet (1, 'a:b') }, {
    false,
    'A sheet name cannot hold any of these: [ ] : * ? / \\',
  })
  eq ({ book:rename_sheet (1, 'SHEET1') }, { true })
  eq (book.sheets[1].name, 'SHEET1')
  eq (book:free_name ('Sheet'), 'Sheet2')
  eq (book:free_name ('Budget', true), 'Budget (2)')
  eq (book:free_name ('Budget (2)', true), 'Budget (2)')
end)
test ('a workbook name must make a file name on every system', function ()
  eq (B.file_name_problem (''), 'Type a name.')
  ok (B.file_name_problem ('a/b') ~= nil)
  ok (B.file_name_problem ('.hidden') ~= nil)
  ok (B.file_name_problem ('tab\there') ~= nil)
  for _, bad in ipairs ({ 'CON', 'nul', 'Aux.backup', 'com1', 'LPT9', 'prn ' }) do
    ok (B.file_name_problem (bad), bad .. ' should be refused')
  end
  for _, good in ipairs ({ 'Console', 'null', 'com10', 'Budget 2026', 'CON 1' }) do
    eq (B.file_name_problem (good), nil, good)
  end
  eq (B.safe_file_name ('NUL'), 'NUL 1')
  eq (B.safe_file_name ('a:b?'), 'a-b-')
  eq (B.safe_file_name ('  '), 'Imported')
  eq (B.safe_file_name ('Budget'), 'Budget')
end)

test ('formulas read other sheets by name, ignoring case', function ()
  local book = book_of ({ 'Main', 'Data', 'Q1 sales' }, {
    Data = { A1 = '5', A2 = '7', B1 = '=A1*10' },
    ['Q1 sales'] = { B2 = '100', B3 = '200' },
    Main = {
      A1 = '=Data!A1*2',
      A2 = '=data!B1+1',
      A3 = "=SUM('Q1 sales'!B2:B3)",
      A4 = '=SUM(Data!A:A)',
      A5 = '=Nowhere!A1',
      A6 = '=ROWS(Data!A:A)',
      A7 = "='q1 SALES'!B2",
    },
  })
  local main = book.sheets[1]
  eq (shown (main, 'A1'), '10')
  eq (shown (main, 'A2'), '51')
  eq (shown (main, 'A3'), '300')
  eq (shown (main, 'A4'), '12')
  eq (shown (main, 'A5'), '#REF!')
  eq (shown (main, 'A6'), '100')
  eq (shown (main, 'A7'), '100')
  -- A reference to a sheet that does not exist is #REF!, not a loop, in a book of one sheet.
  local alone = B.new ()
  alone.sheets[1]:put (1, 1, { text = '=Data!A1' })
  eq (shown (alone.sheets[1], 'A1'), '#REF!')
end)

test ('an edit on one sheet reaches formulas on others', function ()
  local book = book_of ({ 'Main', 'Data' }, {
    Data = { A1 = '5', B1 = '=A1*10' },
    Main = { A1 = '=Data!B1+1', A2 = '=A1*2', A3 = '1' },
  })
  local main, data = book.sheets[1], book.sheets[2]
  eq (shown (main, 'A2'), '102')
  set (data, 'A1', '6')
  eq (shown (main, 'A2'), '122')
  eq (book.last.full, false)
  eq (book.last.evaluated, 3)
  -- An edit that no formula reads works nothing out.
  set (main, 'A3', '2')
  book:ensure ()
  eq (book.last.evaluated, 0)
end)

test ('a sheet added later makes its references work', function ()
  local book = book_of ({ 'Main' }, { Main = { A1 = '=Later!A1+1' } })
  local main = book.sheets[1]
  eq (shown (main, 'A1'), '#REF!')
  local later = assert (book:add_sheet ('Later'))
  later:set (1, 1, '41')
  eq (shown (main, 'A1'), '42')
end)

test ('loops across sheets show #CYCLE!', function ()
  local book = book_of ({ 'One', 'Two' }, {
    One = { A1 = '=Two!A1+1', B1 = '=A1*2' },
    Two = { A1 = '=One!A1+1' },
  })
  local one, two = book.sheets[1], book.sheets[2]
  eq (shown (one, 'A1'), '#CYCLE!')
  eq (shown (one, 'B1'), '#CYCLE!')
  eq (shown (two, 'A1'), '#CYCLE!')
  set (two, 'A1', '5')
  eq (shown (one, 'B1'), '12')
end)

test ('renaming a sheet rewrites the formulas that name it', function ()
  local book = book_of ({ 'Main', 'Data' }, {
    Data = { A1 = '5', A2 = '=Data!A1+1' },
    Main = { A1 = '=Data!A1*2', A2 = '=SUM(data!A1:A2)', A3 = '="Data!A1"' },
  })
  local main, data = book.sheets[1], book.sheets[2]
  book.sheets[1]:set_field ('rules', {
    { range = 'A1:A2', type = 'formula', formula = '=Data!A1>1', style = {} },
  })
  eq ({ book:rename_sheet (2, 'Q1 sales') }, { true })
  eq (data.name, 'Q1 sales')
  eq (text (main, 'A1'), "='Q1 sales'!A1*2")
  eq (text (main, 'A2'), "=SUM('Q1 sales'!A1:A2)")
  eq (text (main, 'A3'), '="Data!A1"')
  eq (text (data, 'A2'), "='Q1 sales'!A1+1")
  eq (main.rules[1].formula, "='Q1 sales'!A1>1")
  eq (shown (main, 'A1'), '10')
  eq (shown (main, 'A2'), '11')
  -- One step undoes the name and every formula.
  local info = assert (book:undo ())
  eq (info.label, 'Rename sheet')
  eq (data.name, 'Data')
  eq (text (main, 'A1'), '=Data!A1*2')
  eq (main.rules[1].formula, '=Data!A1>1')
  eq (shown (main, 'A1'), '10')
  book:redo ()
  eq (text (main, 'A1'), "='Q1 sales'!A1*2")
  ok (book:find ('q1 sales') == data)
  ok (book:find ('Data') == nil)
end)

test ('deleting a sheet turns references to it into #REF!', function ()
  local book = book_of ({ 'Main', 'Data', 'Other' }, {
    Data = { A1 = '5' },
    Main = { A1 = '=Data!A1*2', A2 = '=Other!A1' },
    Other = { A1 = '3' },
  })
  local main, data = book.sheets[1], book.sheets[2]
  book.active = 2
  eq ({ book:delete_sheet (2) }, { true })
  eq (book:names (), { 'Main', 'Other' })
  eq (book.active, 2)
  eq (text (main, 'A1'), '=#REF!*2')
  eq (shown (main, 'A1'), '#REF!')
  eq (shown (main, 'A2'), '3')
  -- Undo puts the same sheet back, in its place, with the formulas as they were.
  local info = assert (book:undo ())
  eq (book:names (), { 'Main', 'Data', 'Other' })
  ok (book.sheets[2] == data)
  eq (text (main, 'A1'), '=Data!A1*2')
  eq (shown (main, 'A1'), '10')
  eq ({ info.sheet, book.active }, { 2, 2 })
  book:redo ()
  eq (book.active, 2)
  eq (book:active_sheet ().name, 'Other')
  book:undo ()
  -- The last sheet stays.
  local one = B.new ()
  eq (
    { one:delete_sheet (1) },
    { false, 'A workbook keeps at least one sheet.' }
  )
  eq ({ one:delete_sheet (5) }, { false, 'There is no such sheet.' })
end)

test ('duplicating a sheet copies everything under a free name', function ()
  local book = book_of ({ 'Budget' }, {
    Budget = { A1 = 'Rent', B1 = '1200', B2 = '=B1*2', C1 = '=Budget!B1' },
  })
  local budget = book.sheets[1]
  budget:set_style ({ r1 = 1, c1 = 1, r2 = 1, c2 = 1 }, { bold = true })
  budget:set_note (1, 2, 'Up in March.')
  budget:set_width (1, 170)
  budget:merge ({ r1 = 5, c1 = 1, r2 = 5, c2 = 3 })
  budget:set_freeze (1, 0)
  local copy = assert (book:duplicate_sheet (1))
  eq (copy.name, 'Budget (2)')
  eq (book:names (), { 'Budget', 'Budget (2)' })
  eq (book.active, 2)
  eq (shown (copy, 'B2'), '2400')
  ok (copy:is_bold (1, 1))
  eq (copy:note (1, 2), 'Up in March.')
  eq (copy:width (1), 170)
  eq (copy.merges, { { r1 = 5, c1 = 1, r2 = 5, c2 = 3 } })
  eq (copy.freeze_rows, 1)
  -- A reference that names the first sheet still reads it.
  eq (text (copy, 'C1'), '=Budget!B1')
  -- The copy changes on its own.
  set (copy, 'B1', '5')
  eq (shown (copy, 'B2'), '10')
  eq (shown (budget, 'B2'), '2400')
  eq (book:duplicate_sheet (1).name, 'Budget (3)')
  book:undo ()
  book:undo ()
  book:undo ()
  eq (book:names (), { 'Budget' })
end)

test ('moving a sheet keeps the same sheet active', function ()
  local book = book_of ({ 'A', 'B', 'C' }, {})
  book.active = 1
  ok (book:move_sheet (1, 3))
  eq (book:names (), { 'B', 'C', 'A' })
  eq (book.active, 3)
  ok (not book:move_sheet (2, 2))
  ok (not book:move_sheet (9, 1))
  local info = assert (book:undo ())
  eq (book:names (), { 'A', 'B', 'C' })
  eq (info.sheet, 1)
  book.active = 2
  book:move_sheet (3, 1)
  eq (book:names (), { 'C', 'A', 'B' })
  eq (book.active, 3)
  book:undo ()
  eq (book.active, 2)
end)

---------------------------------------------------------------------------------------------
-- Recalculation
---------------------------------------------------------------------------------------------

test ('an edit works out only the formulas that depend on it', function ()
  local book = book_of ({ 'S' }, {
    S = {
      A1 = '1',
      A2 = '2',
      A3 = '3',
      B1 = '=A1*2',
      B2 = '=B1+A2',
      B3 = '=B2+A3',
      C1 = '=SUM(A:A)',
      D1 = '=A3*10',
      E1 = '7',
      E2 = '=E1',
    },
  })
  local s = book.sheets[1]
  book:ensure ()
  eq (book.last, { full = true, evaluated = 6, dirty = 6 })
  set (s, 'A1', '10')
  book:ensure ()
  -- B1, B2, B3 and the SUM, and not D1 or E2.
  eq (book.last, { full = false, evaluated = 4, dirty = 4 })
  eq (shown (s, 'B3'), '25')
  eq (shown (s, 'C1'), '15')
  set (s, 'A3', '4')
  book:ensure ()
  eq (book.last.evaluated, 3)
  -- A new formula is worked out, and so are the formulas that read its cell.
  set (s, 'A2', '=A1+1')
  book:ensure ()
  eq (book.last.evaluated, 4)
  eq (shown (s, 'B2'), '31')
  -- A cell that stops being a formula takes the formulas that read it along.
  set (s, 'A2', '5')
  eq (shown (s, 'B3'), '29')
  -- Nothing changed, nothing to do.
  local before = book.last
  book:ensure ()
  eq (book.last, before)
end)

test ('volatile formulas are worked out after every edit', function ()
  local ticks = 0
  local book = B.new ({
    clock = function ()
      ticks = ticks + 1
      return NOW + ticks
    end,
  })
  local s = book.sheets[1]
  s:put (1, 1, { text = '=NOW()' })
  s:put (1, 2, { text = '=A1+1' })
  s:put (1, 3, { text = '5' })
  s:put (1, 4, { text = '=C1*2' })
  local first = s:value (1, 1)
  s:set (1, 3, '6')
  book:ensure ()
  -- NOW, the cell that reads it, and D1.
  eq (book.last.evaluated, 3)
  ok (s:value (1, 1) ~= first)
  local second = s:value (1, 1)
  book:refresh ()
  book:ensure ()
  eq (book.last.evaluated, 2)
  ok (s:value (1, 1) ~= second)
end)

test ('INDIRECT and OFFSET read cells worked out on demand', function ()
  local book = book_of ({ 'S', 'Data' }, {
    S = {
      A1 = '=INDIRECT("B" & 1)',
      B1 = '=C1*2',
      C1 = '4',
      D1 = '=OFFSET(A1, 0, 4)',
      E1 = '=INDIRECT("Data!A1")+1',
      F1 = '=INDIRECT("F1")',
      G1 = '=INDIRECT("G2")',
      G2 = '=G1+1',
    },
    Data = { A1 = '=10*2' },
  })
  local s = book.sheets[1]
  eq (shown (s, 'A1'), '8')
  eq (shown (s, 'D1'), '21')
  eq (shown (s, 'E1'), '21')
  eq (shown (s, 'F1'), '#CYCLE!')
  eq (shown (s, 'G1'), '#CYCLE!')
  set (s, 'C1', '5')
  eq (shown (s, 'A1'), '10')
  set (book.sheets[2], 'A1', '1')
  eq (shown (s, 'D1'), '2')
end)

test (
  'a long chain of INDIRECT gives #CYCLE! rather than overflowing',
  function ()
    local book = B.new ({ rows = 400 })
    local s = book.sheets[1]
    s:put (400, 1, { text = '1' })
    for row = 1, 399 do
      s:put (row, 1, { text = '=INDIRECT("A' .. (row + 1) .. '")+1' })
    end
    book:ensure ()
    for row = 1, 400 do
      local v = s:value (row, 1)
      ok (type (v) == 'number' or v == f.error ('#CYCLE!'), 'row ' .. row)
    end
    eq (s:value (400, 1), 1)
    eq (s:value (399, 1), 2)
  end
)

test ('20,000 formulas: one edit touches only what it must', function ()
  local rows = 10000
  local book = B.new ({ rows = rows, name = 'Data' })
  local data = book.sheets[1]
  for row = 1, rows do
    data:put (row, 1, { text = tostring (row) })
    -- A chain down column B and a block of independent formulas in column C.
    data:put (row, 2, {
      text = row == 1 and '=A1' or ('=B' .. (row - 1) .. '+A' .. row),
    })
    data:put (row, 3, { text = '=A' .. row .. '*2' })
  end
  local summary = assert (book:add_sheet ('Summary'))
  summary:put (1, 1, { text = '=SUM(Data!C1:C10000)' })
  summary:put (2, 1, { text = '=Data!B10000' })
  local started = os.clock ()
  book:ensure ()
  local full = os.clock () - started
  eq (book.last.evaluated, 20002)
  eq (summary:value (2, 1), rows * (rows + 1) / 2)

  -- The last input reaches its chain link, its block cell and both totals.
  started = os.clock ()
  data:set (rows, 1, '0')
  book:ensure ()
  local last = os.clock () - started
  eq (book.last, { full = false, evaluated = 4, dirty = 4 })
  eq (summary:value (1, 1), rows * (rows + 1) - 2 * rows)

  -- The first input reaches the whole chain.
  started = os.clock ()
  data:set (1, 1, '2')
  book:ensure ()
  local first = os.clock () - started
  eq (book.last.evaluated, rows + 3)

  -- An input nobody reads works nothing out.
  data:set (1, 26, '5')
  book:ensure ()
  eq (book.last.evaluated, 0)

  print (
    string.format (
      '    20,002 formulas: full %.3f s, edit at the end %.4f s (4 formulas), edit at the top %.3f s (%d formulas)',
      full,
      last,
      first,
      rows + 3
    )
  )
  ok (full < 30, 'the full recalculation took too long')
end)

---------------------------------------------------------------------------------------------
-- Undo
---------------------------------------------------------------------------------------------

test (
  'one history for the book, and undo shows the sheet it happened on',
  function ()
    local book = book_of ({ 'One', 'Two' }, {})
    local one, two = book.sheets[1], book.sheets[2]
    set (one, 'A1', 'first')
    set (two, 'B3', 'second')
    book.active = 1
    ok (book:can_undo ())
    local info = assert (book:undo ())
    eq (info, { sheet = 2, rect = { r1 = 3, c1 = 2, r2 = 3, c2 = 2 } })
    eq (book.active, 2)
    eq (text (two, 'B3'), '')
    info = assert (book:undo ())
    eq (info.sheet, 1)
    eq (text (one, 'A1'), '')
    ok (not book:can_undo ())
    eq (book:undo (), nil)
    info = assert (book:redo ())
    eq (info.sheet, 1)
    eq (text (one, 'A1'), 'first')
    ok (book:can_redo ())
  end
)

test ('begin and finish make one step across sheets', function ()
  local book = book_of ({ 'One', 'Two' }, {})
  local one, two = book.sheets[1], book.sheets[2]
  book:begin ({ label = 'Both' })
  set (one, 'A1', '1')
  book:begin ()
  set (two, 'A1', '2')
  book:finish ()
  set (one, 'A1', '3')
  book:finish ()
  eq (#book.done, 1)
  eq (book:undo_label (), 'Both')
  -- Undo is refused while a batch is open.
  book:begin ()
  eq (book:undo (), nil)
  book:finish ()
  book:undo ()
  eq ({ text (one, 'A1'), text (two, 'A1') }, { '', '' })
  eq (book:redo_label (), 'Both')
  book:redo ()
  eq ({ text (one, 'A1'), text (two, 'A1') }, { '3', '2' })
  -- An empty batch leaves no step.
  book:begin ()
  book:finish ()
  eq (#book.done, 1)
end)

test ('the history keeps the last 200 steps', function ()
  local book = B.new ()
  local s = book.sheets[1]
  for i = 1, 205 do
    s:set (1, 1, tostring (i))
  end
  eq (#book.done, B.HISTORY)
  for _ = 1, 200 do
    book:undo ()
  end
  eq (s:text (1, 1), '5')
  ok (not book:can_undo ())
end)

test ('a new edit clears redo', function ()
  local book = B.new ()
  local s = book.sheets[1]
  s:set (1, 1, 'a')
  book:undo ()
  ok (book:can_redo ())
  s:set (1, 1, 'b')
  ok (not book:can_redo ())
end)

---------------------------------------------------------------------------------------------
-- The file
---------------------------------------------------------------------------------------------

---A book with one of everything the file holds.
---@return Sheet.Book
local function full_book ()
  local book = book_of ({ 'Budget', 'Data' }, {
    Budget = {
      A1 = 'Monthly budget',
      A4 = 'Item',
      B4 = 'Cost',
      A5 = 'Rent',
      B5 = '1200',
      A6 = 'Food',
      B6 = '450',
      B7 = '=SUM(B5:B6)',
      C7 = '=Data!A1',
    },
    Data = { A1 = '3', B2 = 'Say "hi"\n\ttab\\' },
  })
  local s = book.sheets[1]
  s:set_style ({ r1 = 1, c1 = 1, r2 = 1, c2 = 1 }, { bold = true, size = 16 })
  s:set_style ({ r1 = 1, c1 = 2, r2 = s.rows, c2 = 2 }, { format = '$#,##0.00' })
  s:set_style ({ r1 = 4, c1 = 1, r2 = 4, c2 = s.cols }, { fill = '#e8eefc' })
  s:set_width (1, 170)
  s:set_height (4, 32)
  s:set_hidden ('row', 9, 9, true)
  s:set_hidden ('col', 5, 5, true)
  s:set_freeze (4, 1)
  s:merge ({ r1 = 1, c1 = 1, r2 = 1, c2 = 3 })
  s:set_note (5, 2, 'Rent went up in March.')
  s:set_field ('filter', {
    rect = { r1 = 4, c1 = 1, r2 = 6, c2 = 2 },
    columns = { [1] = { values = { 'Rent' } } },
    hidden = {},
  })
  s:set_field ('rules', {
    {
      range = 'B5:B6',
      type = 'compare',
      op = '>',
      value = '1000',
      style = { color = '#c62828' },
    },
  })
  s:set_field (
    'validation',
    { { range = 'A5:A6', type = 'list', values = { 'Rent', 'Food' } } }
  )
  s:set_field ('charts', {
    {
      id = 'c1',
      type = 'column',
      range = 'A4:B6',
      title = 'Costs',
      x = 700,
      y = 90,
      w = 480,
      h = 300,
    },
  })
  book.active = 2
  return book
end

test ('decode (encode (book)) gives the same book back', function ()
  local book = full_book ()
  local text_1 = B.encode (book)
  local back = assert (B.decode (text_1, { clock = clock }))
  eq (B.to_data (back), B.to_data (book))
  eq (B.encode (back), text_1)
  eq (back.active, 2)
  local s = back.sheets[1]
  eq (shown (s, 'B7'), '$1,650.00')
  eq (shown (s, 'C7'), '3')
  ok (s:is_bold (1, 1))
  eq (s:width (1), 170)
  eq (s:height (4), 32)
  ok (s:row_hidden (9) and s:col_hidden (5))
  eq ({ s:freeze () }, { 4, 1 })
  eq (s:merge_at (1, 2), { r1 = 1, c1 = 1, r2 = 1, c2 = 3 })
  eq (s:note (5, 2), 'Rent went up in March.')
  -- The filter's hidden rows are worked out on load.
  ok (s:row_hidden (6) and not s:row_hidden (5))
  eq (text (back.sheets[2], 'B2'), 'Say "hi"\n\ttab\\')
  eq (#back.done, 0)
end)

test ('encode writes one cell per line, in reading order', function ()
  local text_1 = B.encode (full_book ())
  ok (string.find (text_1, '"version": 2', 1, true))
  ok (
    string.find (
      text_1,
      '        "A1": "Monthly budget",\n        "A4": "Item",\n        "B4": "Cost",',
      1,
      true
    )
  )
  ok (string.find (text_1, '"A1": { "bold": true, "size": 16 }', 1, true))
  ok (string.find (text_1, '"freeze": { "rows": 4, "cols": 1 }', 1, true))
  ok (string.find (text_1, '"merges": ["A1:C1"]', 1, true))
  ok (string.find (text_1, '"hidden_rows": [9]', 1, true))
  ok (string.find (text_1, '"hidden_cols": ["E"]', 1, true))
  ok (
    string.find (
      text_1,
      '"filter": { "range": "A4:B6", "columns": { "A": { "values": ["Rent"] } } }',
      1,
      true
    )
  )
  ok (
    string.find (
      text_1,
      '{ "range": "B5:B6", "type": "compare", "op": ">", "value": "1000", "style": { "color": "#c62828" } }',
      1,
      true
    )
  )
  ok (
    string.find (
      text_1,
      '{ "id": "c1", "type": "column", "range": "A4:B6", "title": "Costs", "x": 700, "y": 90, "w": 480, "h": 300 }',
      1,
      true
    )
  )
  -- A small change makes a small difference.
  local book = full_book ()
  local a = B.encode (book)
  book.sheets[1]:set (5, 2, '1300')
  local b = B.encode (book)
  local changed = 0
  local lines_a = {} ---@type string[]
  for line in string.gmatch (a, '[^\n]+') do
    lines_a[#lines_a + 1] = line
  end
  local i = 0
  for line in string.gmatch (b, '[^\n]+') do
    i = i + 1
    if line ~= lines_a[i] then
      changed = changed + 1
    end
  end
  eq (changed, 1)
end)

test ('the file reader takes what it can', function ()
  eq ({ B.decode ('{ "version": 2, "sheets": [ }') }, {
    nil,
    'The file is not valid JSON. A value is not valid JSON at byte 29.',
  })
  eq ({ B.decode ('[1, 2]x') }, {
    nil,
    'The file is not valid JSON. There is more text after the data at byte 7.',
  })
  eq ({ B.decode ('"text"') }, { nil, 'The file holds no workbook.' })
  -- Empty maps and lists, missing fields and bad values all load.
  local book = assert (B.decode (table.concat ({
    '{ "version": 2, "active": 7, "sheets": [',
    '  { "name": "One", "cells": {}, "styles": [], "merges": {}, "rules": {} },',
    '  { "name": "one", "rows": "many", "cells": { "A1": 5, "B1": true, "C1": null } },',
    '  { "cells": { "A1": "=One!A1" }, "charts": [ { "range": "A1:B2" }, { "id": 3 } ] },',
    '  "not a sheet"',
    '] }',
  }, '\n')))
  eq (book:names (), { 'One', 'one (2)', 'Sheet3' })
  eq (book.active, 3)
  eq (text (book.sheets[2], 'A1'), '5')
  eq (text (book.sheets[2], 'B1'), 'TRUE')
  eq (book.sheets[2].rows, 100)
  eq (book.sheets[3].charts, {
    {
      id = 'c1',
      type = 'column',
      range = 'A1:B2',
      x = 0,
      y = 0,
      w = 480,
      h = 300,
    },
  })
  eq (shown (book.sheets[3], 'A1'), '0')
  -- JSON escapes, surrogate pairs and numbers.
  eq (
    B.parse_json (
      '{"a": "\\u00e9\\ud83d\\ude00\\n", "b": [1, -2.5e2, true, false]}'
    ),
    { a = 'é😀\n', b = { 1, -250, true, false } }
  )
  eq ({ B.parse_json (string.rep ('[', 200)) }, {
    nil,
    'The data nests too deeply at byte 102.',
  })
  -- No data at all is an empty book.
  eq (B.from_data (nil):names (), { 'Sheet1' })
end)

test ('the example workbook reads its income sheet', function ()
  local book = B.example ({ clock = clock })
  eq (book:names (), { 'Budget', 'Income' })
  local budget, income = book.sheets[1], book.sheets[2]
  eq (text (budget, 'C17'), '=Income!D11')
  eq (shown (budget, 'C17'), '$3,200.00')
  eq (shown (income, 'A4'), 'April 2026')
  eq (shown (income, 'D4'), '$3,120.00')
  -- A change on the income sheet reaches the budget.
  income:set (4, 2, '3600')
  eq (shown (budget, 'C17'), '$3,300.00')
  eq (budget.freeze_rows, 4)
  eq (#budget.charts, 1)
  eq (#budget.rules, 1)
  eq (budget:note (5, 2), 'Rent went up in March.')
  eq (#book.done, 1)
end)
