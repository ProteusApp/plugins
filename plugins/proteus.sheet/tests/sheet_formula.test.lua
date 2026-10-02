-- Tests for sheet_formula: sheet references, arrays, the full set of functions, and the
-- helpers the formula bar uses while a formula is typed. Where a number comes from a
-- spreadsheet's help page rather than from arithmetic, a comment says so.

local f = require ('sheet_formula') --[[@as Sheet.FormulaModule]]

-- A fixed clock and dice, so TODAY, NOW and RAND give the same answer every run.
local NOW = f.serial (2026, 9, 29, 14, 30, 0)

---@alias Cells table<string, Sheet.Value>

---A workbook for the tests. `cells` is the formula's own sheet, Sheet1, and `others` holds
---more sheets by name. A sheet named in a formula is 50 rows by 10 columns. A cell holding text
---that starts with "=" is worked out when something reads it.
---@param cells? Cells
---@param others? table<string, Cells>
---@param here? integer[] The row and column of the formula, for ROW() and COLUMN().
---@return Sheet.Context
local function book (cells, others, here)
  local own = cells or {}
  local by_name = { sheet1 = own } ---@type table<string, Cells>
  for name, sheet in pairs (others or {}) do
    by_name[string.lower (name)] = sheet
  end
  ---@type Sheet.Context
  local ctx
  ctx = {
    rows = 100,
    cols = 26,
    row = here and here[1],
    col = here and here[2],
    clock = function ()
      return NOW
    end,
    random = function ()
      return 0.25
    end,
    size = function (name)
      if by_name[string.lower (name)] then
        return 50, 10
      end
      return nil, nil
    end,
    value = function (row, col, sheet)
      local source = own
      if sheet then
        source = by_name[string.lower (sheet)] or {}
      end
      local v = source[f.address (row, col)]
      if type (v) == 'string' and f.is_formula (v) then
        local ast = f.parse (v)
        if not ast then
          return f.error ('#ERROR!')
        end
        return f.evaluate (ast, ctx)
      end
      return v
    end,
  }
  return ctx
end

---Works out one formula beside the given cells.
---@param formula string
---@param cells? Cells
---@param others? table<string, Cells>
---@return Sheet.Value
local function value (formula, cells, others)
  local ast = assert (f.parse (formula), formula)
  return f.evaluate (ast, book (cells, others))
end

---Works out one formula and shows its value as text, numbers with up to 10 digits.
---@param formula string
---@param cells? Cells
---@param others? table<string, Cells>
---@return string
local function calc (formula, cells, others)
  return f.format_value (value (formula, cells, others))
end

---Fails unless a formula gives a number within `tol` of `want`.
---@param formula string
---@param want number
---@param tol number
---@param cells? Cells
local function near (formula, want, tol, cells)
  local v = value (formula, cells)
  ok (
    type (v) == 'number' and math.abs (v - want) <= tol,
    formula .. ' gave ' .. f.format_value (v) .. ', not ' .. want
  )
end

---A date as `calc` shows its serial number.
---@param y integer
---@param m integer
---@param d integer
---@return string
local function day (y, m, d)
  return f.format_value (f.serial (y, m, d))
end

---------------------------------------------------------------------------------------------
-- Sheet references
---------------------------------------------------------------------------------------------

local OTHERS = {
  Data = { A1 = 1, A2 = 2, A3 = 3, B1 = 'x', A50 = 100, A51 = 1000 },
  ['Q1 sales'] = { A1 = 10, A2 = 20, B1 = 5 },
  ["Bob's"] = { A1 = 7 },
}

test ('the tokenizer reads sheet names with and without quotes', function ()
  local text = "='Q1 sales'!A1:B9+Data!A:A-'Bob''s'!$C$3"
  local tokens = assert (f.tokenize (text, 2))
  eq (#tokens, 5)
  eq (tokens[1].kind, 'range')
  eq (tokens[1].sheet, 'Q1 sales')
  eq (tokens[1].sheet_text, "'Q1 sales'!")
  eq (tokens[1].text, "'Q1 sales'!A1:B9")
  eq ({ tokens[1].from, tokens[1].to }, { 2, 17 })
  eq (tokens[1].a, {
    row = 1,
    col = 1,
    row_abs = false,
    col_abs = false,
    sheet = 'Q1 sales',
  })
  eq (tokens[3].sheet, 'Data')
  eq ({ tokens[3].from, tokens[3].to }, { 19, 26 })
  eq (tokens[3].b, { col = 1, col_abs = false, row_abs = false, sheet = 'Data' })
  eq (tokens[5].kind, 'ref')
  eq (tokens[5].sheet, "Bob's")
  eq (tokens[5].a, {
    row = 3,
    col = 3,
    row_abs = true,
    col_abs = true,
    sheet = "Bob's",
  })
  -- A plain reference has no sheet.
  eq (assert (f.tokenize ('A1'))[1].a, {
    row = 1,
    col = 1,
    row_abs = false,
    col_abs = false,
  })
end)

test ('sheet names that do not read refuse to parse', function ()
  for _, bad in ipairs ({
    "='Q1 sales!A1",
    "='Q1 sales'A1",
    '=Data!',
    '=Data!SUM(1)',
    "=''!A1",
    '=Data!1.5',
  }) do
    ok (f.parse (bad) == nil, bad .. ' should not parse')
  end
end)

test ('refs() names the sheet of each block', function ()
  local ast =
    assert (f.parse ("=SUM('Q1 sales'!A1:B9, Data!C:C, Data!3:4) + D4"))
  eq (f.refs (ast), {
    { r1 = 1, c1 = 1, r2 = 9, c2 = 2, sheet = 'Q1 sales' },
    { c1 = 3, c2 = 3, sheet = 'Data' },
    { r1 = 3, r2 = 4, sheet = 'Data' },
    { r1 = 4, c1 = 4, r2 = 4, c2 = 4 },
  })
end)

test ('references to other sheets read their values', function ()
  local mine = { B1 = 4 }
  eq (calc ('=Data!A1+Data!A2', mine, OTHERS), '3')
  eq (calc ("='Q1 sales'!A1*2", mine, OTHERS), '20')
  eq (calc ("=SUM('Q1 sales'!A1:B2)", mine, OTHERS), '35')
  eq (calc ("='Bob''s'!A1", mine, OTHERS), '7')
  eq (calc ('=data!a1+DATA!A3', mine, OTHERS), '4')
  eq (calc ('=Data!$A$3', mine, OTHERS), '3')
  eq (calc ('=Sheet1!B1+B1', mine, OTHERS), '8')
  eq (calc ('=COUNTA(Data!A:B)', mine, OTHERS), '5')
  -- A whole column of another sheet stops at that sheet's last row, 50 here.
  eq (calc ('=SUM(Data!A:A)', mine, OTHERS), '106')
  eq (calc ('=SUM(Data!1:2)', mine, OTHERS), '3')
  eq (calc ('=Data!Z99', mine, OTHERS), '0')
end)

test ('a sheet the workbook does not know is #REF!', function ()
  eq (calc ('=Nope!A1', {}, OTHERS), '#REF!')
  eq (calc ('=SUM(Nope!A1:B2)', {}, OTHERS), '#REF!')
  eq (calc ('=IFERROR(Nope!A1, "gone")', {}, OTHERS), 'gone')
  -- A context with no size knows no sheet names at all.
  local ctx = book ({}, OTHERS)
  ctx.size = nil
  eq (f.evaluate (assert (f.parse ('=Data!A1')), ctx), f.error ('#REF!'))
  eq (f.evaluate (assert (f.parse ('=A1+1')), ctx), 1)
end)

test ('quote_sheet adds quotes only when a name needs them', function ()
  eq (f.quote_sheet ('Sales'), 'Sales')
  eq (f.quote_sheet ('Sheet.2'), 'Sheet.2')
  eq (f.quote_sheet ('Données'), 'Données')
  eq (f.quote_sheet ('Q1 sales'), "'Q1 sales'")
  eq (f.quote_sheet ("Bob's"), "'Bob''s'")
  eq (f.quote_sheet ('my-sheet'), "'my-sheet'")
  eq (f.quote_sheet ('2024'), "'2024'")
  -- Names that look like a cell or a value need quotes too.
  eq (f.quote_sheet ('A1'), "'A1'")
  eq (f.quote_sheet ('R1C1'), "'R1C1'")
  eq (f.quote_sheet ('true'), "'true'")
end)

test ('shift moves references to other sheets too', function ()
  eq (
    f.shift ("='Q1 sales'!A1+Data!$B$2+C3", 1, 1),
    "='Q1 sales'!B2+Data!$B$2+D4"
  )
  eq (f.shift ('=SUM(Data!A1:A3)', 0, 1), '=SUM(Data!B1:B3)')
  eq (f.shift ('=SUM(Data!A:A)', 3, 2), '=SUM(Data!C:C)')
  eq (f.shift ('=Data!A1', -1, 0), '=#REF!')
end)

test ('move follows a block of cells that moved', function ()
  local block = { r1 = 1, c1 = 1, r2 = 2, c2 = 2 } ---@type Sheet.Rect
  local here = { from = 'Sheet1', to = 'Sheet1', own = 'Sheet1' }
  eq (
    f.move ('=A1+$B$2+SUM(A1:B2)+SUM(A1:C3)+A:A', block, 2, 3, here),
    '=D3+$E$4+SUM(D3:E4)+SUM(A1:C3)+A:A'
  )
  -- A reference to a cell the block lands on and did not hold is gone.
  eq (f.move ('=C3+B2', block, 1, 1, here), '=#REF!+C3')
  local away = { from = 'Sheet1', to = 'Q1 sales', own = 'Sheet1' }
  eq (f.move ('=A1+C1', block, 0, 0, away), "='Q1 sales'!A1+C1")
  -- A formula that moves with the block names the sheet it came from when it reads it.
  away.lands = 'Q1 sales'
  eq (f.move ('=A1+C1', block, 0, 0, away), '=A1+Sheet1!C1')
end)

test ('a reference past the last row or column is #REF!', function ()
  eq (calc ('=XFE1'), '#REF!')
  eq (calc ('=A1048577'), '#REF!')
  eq (calc ('=SUM(A1:A1048577)'), '#REF!')
  eq (calc ('=SUM(XFE1, 1)'), '#REF!')
  eq (calc ('=XFD1048576'), '0')
  eq (calc ('=ROWS(OFFSET(A1, 1048575, 0))'), '1')
  eq (calc ('=ROWS(OFFSET(A1, 1048576, 0))'), '#REF!')
  eq (f.shift ('=A1048576', 1, 0), '=#REF!')
  eq (f.shift ('=XFD1', 0, 1), '=#REF!')
end)

test ('adjust with no options changes only references with no sheet', function ()
  eq (f.adjust ('=A5+Data!A5', 'row', 3, 1), '=A6+Data!A5')
  eq (f.adjust ('=A3+Data!A3', 'row', 3, -1), '=#REF!+Data!A3')
end)

test (
  'adjust with options changes references on the sheet that changed',
  function ()
    local on_data = { sheet = 'Data', own = 'Sheet1' }
    eq (f.adjust ('=A5+Data!A5', 'row', 3, 1, on_data), '=A5+Data!A6')
    eq (
      f.adjust (
        '=A5+Data!A5+Sheet1!A5',
        'row',
        3,
        1,
        { sheet = 'Sheet1', own = 'Sheet1' }
      ),
      '=A6+Data!A5+Sheet1!A6'
    )
    eq (
      f.adjust ('=data!A5', 'row', 3, 1, { sheet = 'DATA', own = 'Sheet1' }),
      '=data!A6'
    )
    eq (
      f.adjust ("='Q1 sales'!A3+A3", 'row', 3, -1, {
        sheet = 'Q1 SALES',
        own = 'Sheet1',
      }),
      '=#REF!+A3'
    )
    eq (
      f.adjust ('=SUM(Data!A2:A10)', 'row', 4, -2, on_data),
      '=SUM(Data!A2:A8)'
    )
    -- With no `own`, a reference with no sheet cannot be on the sheet that changed.
    eq (f.adjust ('=Data!C1+C1', 'col', 2, 1, { sheet = 'Data' }), '=Data!D1+C1')
    -- With no `sheet`, the change was on the formula's own sheet.
    eq (f.adjust ('=C1+Data!C1', 'col', 2, 1, { own = 'Sheet1' }), '=D1+Data!C1')
    eq (f.adjust ('=Sheet1!C1', 'col', 2, 1, { own = 'sheet1' }), '=Sheet1!D1')
  end
)

test ('rename_sheet follows a renamed sheet', function ()
  eq (
    f.rename_sheet ("=Data!A1+data!B2+'Q1 sales'!C3+A1", 'DATA', 'Q2 data'),
    "='Q2 data'!A1+'Q2 data'!B2+'Q1 sales'!C3+A1"
  )
  eq (f.rename_sheet ("='Q1 sales'!A1:B2", 'q1 sales', 'Sales'), '=Sales!A1:B2')
  eq (f.rename_sheet ('=Data!A1', 'Data', "Bob's"), "='Bob''s'!A1")
  -- Text in quotes is not a reference, so it stays.
  eq (f.rename_sheet ('="Data!A1"&Data!A1', 'Data', 'X'), '="Data!A1"&X!A1')
  eq (f.rename_sheet ('=Other!A1', 'Data', 'X'), '=Other!A1')
  eq (f.rename_sheet ('plain', 'Data', 'X'), 'plain')
end)

test ('drop_sheet turns references to a deleted sheet into #REF!', function ()
  local text = f.drop_sheet ('=SUM(Data!A1:A3)+Data!B1+A1', 'data')
  eq (text, '=SUM(#REF!)+#REF!+A1')
  eq (calc (text), '#REF!')
  eq (f.drop_sheet ('=A1+Other!A1', 'Data'), '=A1+Other!A1')
end)

test ('normalize keeps the case of sheet names', function ()
  eq (f.normalize ("=sum('Q1 sales'!a1:b2"), "=SUM('Q1 sales'!A1:B2)")
  eq (f.normalize ('=data!a1+b2'), '=data!A1+B2')
  eq (f.normalize ('=sum({1,2;3,4}'), '=SUM({1,2;3,4})')
end)

test ('can_point allows a reference after a sheet name', function ()
  ---@param text string
  ---@return boolean
  local function at_end (text)
    return f.can_point (text, #text + 1)
  end
  ok (at_end ('=Data!'))
  ok (at_end ("='Q1 sales'!"))
  ok (at_end ('=SUM(Data!A1,'))
  ok (not at_end ("='Q1 ("))
  ok (not at_end ("='Q1, "))
  ok (not at_end ('=#REF!'))
  ok (not at_end ('=1+#ref!'))
  ok (not at_end ('="a,'))
end)

---------------------------------------------------------------------------------------------
-- Arrays
---------------------------------------------------------------------------------------------

test ('array constants parse by rows and columns', function ()
  local ast = assert (f.parse ('={1,2;3,4}'))
  eq (ast.kind, 'array')
  eq (ast.array, { is_array = true, h = 2, w = 2, v = { 1, 2, 3, 4 } })
  eq (
    assert (f.parse ('={1,"a";TRUE,#N/A}')).array,
    { is_array = true, h = 2, w = 2, v = { 1, 'a', true, f.error ('#N/A') } }
  )
  eq (assert (f.parse ('={-1,+2.5}')).array.v, { -1, 2.5 })
  eq (assert (f.parse ('={1;2;3}')).array, {
    is_array = true,
    h = 3,
    w = 1,
    v = { 1, 2, 3 },
  })
  eq (
    select (2, f.parse ('={1,2;3}')),
    'Every row of an array needs the same number of values.'
  )
  for _, bad in ipairs ({ '={}', '={A1}', '={1,2', '={{1}}', '={1+2}', '=1}' }) do
    ok (f.parse (bad) == nil, bad .. ' should not parse')
  end
  -- A semicolon means something only inside braces.
  ok (f.tokenize ('1;2') == nil)
  ok (f.tokenize ('{1;2}') ~= nil)
end)

test ('array constants work as function arguments', function ()
  eq (calc ('=SUM({1,2;3,4})'), '10')
  eq (calc ('={1,2;3,4}'), '1')
  eq (calc ('=INDEX({1,2;3,4}, 2, 1)'), '3')
  eq (calc ('=ROWS({1,2;3,4})&COLUMNS({1,2,3})'), '23')
  -- Text and TRUE in an array are skipped, as in a range.
  eq (calc ('=SUM({1,"2",TRUE})'), '1')
  eq (calc ('=COUNTA({1,"",TRUE})'), '3')
  eq (calc ('=MATCH(3, {1,2,3}, 0)'), '3')
end)

local GRID = {
  A1 = 3,
  A2 = 6,
  A3 = 9,
  A4 = 'x',
  B1 = 10,
  B2 = 20,
  B3 = 30,
  B4 = 40,
  B5 = 50,
}

test ('operators work cell by cell over blocks', function ()
  -- The example from the design: add B where A is over 5.
  eq (calc ('=SUMPRODUCT((A1:A3>5)*(B1:B3))', GRID), '50')
  eq (calc ('=SUM(A1:A3*2)', GRID), '36')
  eq (calc ('=SUM((A1:A3>5)*1)', GRID), '2')
  -- TRUE and FALSE in an array are skipped by SUM, so it takes a sum of 0 here.
  eq (calc ('=SUM(A1:A3>5)', GRID), '0')
  eq (calc ('=MAX(A1:A3*B1:B3)', GRID), '270')
  eq (calc ('=MIN(A1:A3-B1:B3)', GRID), '-21')
  eq (calc ('=AVERAGE(A1:A3*{1;2;3})', GRID), '14')
  -- "x"*1 is #VALUE!, and COUNT skips errors.
  eq (calc ('=COUNT(A1:A4*1)', GRID), '3')
  eq (calc ('=AND(A1:A3>2)', GRID), 'TRUE')
  eq (calc ('=AND(A1:A3>3)', GRID), 'FALSE')
  eq (calc ('=OR(A1:A3>8)', GRID), 'TRUE')
  eq (calc ('=CONCAT(A1:A3&"-")', GRID), '3-6-9-')
  eq (calc ('=TEXTJOIN(",", TRUE, A1:A5&"")', GRID), '3,6,9,x')
  eq (calc ('=SUM(-A1:A3)', GRID), '-18')
  eq (calc ('=SUM(A1:A3%)', GRID), '0.18')
end)

test ('a single value or a single row or column repeats to fit', function ()
  eq (calc ('=SUM({1,2,3}+{10;20})'), '102')
  eq (calc ('=INDEX({1,2,3}+{10;20}, 2, 3)'), '23')
  eq (calc ('=SUM(A1:A3*{1,10})', GRID), '198')
  -- Past the edge of the shorter block the cells are #N/A, as in spreadsheets.
  eq (calc ('=SUM({1,2}*{1,2,3})'), '#N/A')
  eq (calc ('=SUMPRODUCT(A1:A3*B1:B4)', GRID), '#N/A')
  eq (calc ('=INDEX({1,2}*{1,2,3}, 1, 2)'), '4')
end)

test ('a block as the result shows its top left value', function ()
  eq (calc ('=A1:A3*10', GRID), '30')
  eq (calc ('=-A1:A3', GRID), '-3')
  eq (calc ('={1,2,3}+{10;20}'), '11')
  eq (calc ('=B1:B3', GRID), '10')
  eq (calc ('=A4:A5', GRID), 'x')
  eq (calc ('=A6:A9', GRID), '0')
end)

test ('SUMPRODUCT', function ()
  eq (calc ('=SUMPRODUCT(A1:A3, B1:B3)', GRID), '420')
  -- Text counts as 0 in SUMPRODUCT's own arguments.
  eq (calc ('=SUMPRODUCT(A1:A4, B1:B4)', GRID), '420')
  -- "x" > 5 is TRUE, since text sorts after numbers.
  eq (calc ('=SUMPRODUCT((A1:A4>5)*B1:B4)', GRID), '90')
  eq (calc ('=SUMPRODUCT(--(A1:A5>5))', GRID), '3')
  eq (calc ('=SUMPRODUCT(A1:A3, B1:B4)', GRID), '#VALUE!')
  eq (calc ('=SUMPRODUCT(5)'), '5')
  eq (calc ('=SUMPRODUCT({1,2}, {3,4})'), '11')
  eq (calc ('=SUMPRODUCT(A1:A2, {1;#DIV/0!})', GRID), '#DIV/0!')
end)

test ('functions of single values work on each cell of a block', function ()
  eq (calc ('=SUM(ROUND(A1:A3/4, 0))', GRID), '5')
  eq (calc ('=ROUND(A1:A3/4, 0)', GRID), '1')
  eq (calc ('=SUMPRODUCT(LEN({"a","bb","ccc"}))'), '6')
  eq (calc ('=SUM(ABS({-1,2,-3}))'), '6')
  eq (calc ('=SUMPRODUCT(--ISNUMBER(A1:A5))', GRID), '3')
  eq (calc ('=SUMPRODUCT(ISBLANK(A1:A5)*1)', GRID), '1')
  eq (calc ('=CONCAT(UPPER({"a","b"}))'), 'AB')
  -- An error stays in its own cell.
  eq (calc ('=INDEX(SQRT({4,-1}), 1, 1)'), '2')
  eq (calc ('=INDEX(SQRT({4,-1}), 1, 2)'), '#NUM!')
end)

test ('IF and IFERROR work on each cell of a block', function ()
  eq (calc ('=IF(A1:A3>5, "big", "small")', GRID), 'small')
  eq (calc ('=SUM(IF(A1:A3>5, A1:A3, 0))', GRID), '15')
  -- The missing FALSE branch gives FALSE, which SUM skips.
  eq (calc ('=SUM(IF(A1:A3>5, B1:B3))', GRID), '50')
  eq (calc ('=CONCAT(IF({1,0,1}, "y", "n"))'), 'yny')
  eq (calc ('=SUM(IFERROR(1/(A1:A3-6), 0))', GRID), '0')
  eq (calc ('=SUM(IFERROR(A1:A4*1, 100))', GRID), '118')
  eq (calc ('=SUM(IFNA({1,2}*{1,2,3}, 10))'), '15')
end)

---------------------------------------------------------------------------------------------
-- INDIRECT and OFFSET
---------------------------------------------------------------------------------------------

local REFS = { A1 = 1, A2 = 2, A3 = 3, B1 = 10, B2 = 20, B3 = 30, C1 = 'B2' }

test ('INDIRECT reads a reference from text', function ()
  eq (calc ('=INDIRECT("A2")', REFS), '2')
  eq (calc ('=INDIRECT(C1)', REFS), '20')
  eq (calc ('=INDIRECT("a"&3)', REFS), '3')
  eq (calc ('=SUM(INDIRECT("A1:B3"))', REFS), '66')
  eq (calc ('=SUM(INDIRECT("A:A"))', REFS), '6')
  eq (calc ('=INDIRECT("Data!A3")', REFS, OTHERS), '3')
  eq (calc ('=SUM(INDIRECT("\'Q1 sales\'!A1:A2"))', REFS, OTHERS), '30')
  eq (calc ('=INDIRECT("R2C2", FALSE)', REFS), '20')
  eq (calc ('=SUM(INDIRECT("R1C1:R3C1", FALSE))', REFS), '6')
  eq (calc ('=INDIRECT("Data!R3C1", FALSE)', REFS, OTHERS), '3')
  eq (calc ('=INDIRECT("nope")', REFS), '#REF!')
  eq (calc ('=INDIRECT("A1+1")', REFS), '#REF!')
  eq (calc ('=INDIRECT("Nope!A1")', REFS, OTHERS), '#REF!')
  eq (calc ('=INDIRECT("R0C1", FALSE)', REFS), '#REF!')
end)

test ('OFFSET moves and sizes a reference', function ()
  eq (calc ('=OFFSET(A1, 1, 1)', REFS), '20')
  eq (calc ('=SUM(OFFSET(A1, 0, 0, 3, 1))', REFS), '6')
  eq (calc ('=SUM(OFFSET(A1:B1, 1, 0))', REFS), '22')
  eq (calc ('=SUM(OFFSET(A1, 1, 0, 2, 2))', REFS), '55')
  eq (calc ('=ROWS(OFFSET(A1, 0, 0, 4, 2))', REFS), '4')
  eq (calc ('=OFFSET(INDIRECT("B1"), 2, 0)', REFS), '30')
  eq (calc ('=OFFSET(Data!A1, 2, 0)', REFS, OTHERS), '3')
  eq (calc ('=ROW(INDIRECT("C7"))+COLUMN(OFFSET(A1, 0, 3))', REFS), '11')
  eq (calc ('=OFFSET(A1, -1, 0)', REFS), '#REF!')
  eq (calc ('=OFFSET(A1, 0, 0, 0, 1)', REFS), '#REF!')
  eq (calc ('=OFFSET(5, 1, 1)', REFS), '#VALUE!')
  eq (calc ('=COUNTIF(OFFSET(A1, 0, 0, 3), ">1")', REFS), '2')
end)

---------------------------------------------------------------------------------------------
-- Criteria
---------------------------------------------------------------------------------------------

local CRIT = {
  A1 = 'apple',
  A2 = 'Banana',
  A3 = 'apricot',
  A4 = 5,
  A5 = 12,
  A6 = '5',
  A7 = '*star',
  A8 = 'abc',
  A9 = true,
  A11 = '',
  B1 = 1,
  B2 = 2,
  B3 = 3,
  B4 = 4,
  B5 = 5,
  B6 = 6,
  B7 = 7,
  B8 = 8,
  B9 = 9,
  B10 = 10,
  B11 = 11,
}

test ('criteria compare, match text and use wildcards', function ()
  eq (calc ('=COUNTIF(A1:A11, ">5")', CRIT), '1')
  eq (calc ('=COUNTIF(A1:A11, 5)', CRIT), '2')
  eq (calc ('=COUNTIF(A1:A11, "5")', CRIT), '2')
  eq (calc ('=COUNTIF(A1:A11, "<>apple")', CRIT), '10')
  eq (calc ('=COUNTIF(A1:A11, "=abc")', CRIT), '1')
  eq (calc ('=COUNTIF(A1:A11, "ABC")', CRIT), '1')
  eq (calc ('=COUNTIF(A1:A11, "")', CRIT), '2')
  eq (calc ('=COUNTIF(A1:A11, "<>")', CRIT), '9')
  eq (calc ('=COUNTIF(A1:A11, "a*")', CRIT), '3')
  eq (calc ('=COUNTIF(A1:A11, "?pple")', CRIT), '1')
  eq (calc ('=COUNTIF(A1:A11, "a?c")', CRIT), '1')
  eq (calc ('=COUNTIF(A1:A11, "<>a*")', CRIT), '8')
  -- A tilde makes the next * or ? stand for itself.
  eq (calc ('=COUNTIF(A1:A11, "~*star")', CRIT), '1')
  eq (calc ('=COUNTIF(A1:A11, "~*")', CRIT), '0')
  eq (calc ('=COUNTIF(A1:A11, TRUE)', CRIT), '1')
  eq (calc ('=COUNTIF(A1:A11, ">=b")', CRIT), '1')
  eq (calc ('=COUNTIF({"é","É","e"}, "é")'), '2')
  eq (calc ('=COUNTIF({"né","nb"}, "n?")'), '2')
end)

test ('numbers compare at 15 significant digits', function ()
  -- Excel gives TRUE for each of these, though the floats differ in their last bits.
  eq (calc ('=0.1+0.2=0.3'), 'TRUE')
  eq (calc ('=0.1+0.2<>0.3'), 'FALSE')
  eq (calc ('=0.1+0.2>0.3'), 'FALSE')
  eq (calc ('=0.1+0.2<=0.3'), 'TRUE')
  eq (calc ('=1.1*3=3.3'), 'TRUE')
  eq (calc ('=1+1E-15=1'), 'TRUE')
  eq (calc ('=1+1E-13=1'), 'FALSE')
  eq (calc ('=1E-20=0'), 'FALSE')
  local cells = { A1 = '=0.1+0.2', A2 = 0.3, A3 = 3.3, A4 = 1 }
  eq (calc ('=COUNTIF(A1:A2, 0.3)', cells), '2')
  eq (calc ('=COUNTIF(A1:A2, "=0.3")', cells), '2')
  eq (calc ('=COUNTIF(A1:A2, "<0.3")', cells), '0')
  eq (calc ('=COUNTIF(A1:A2, ">=0.3")', cells), '2')
  eq (calc ('=SUMIF(A1:A2, 0.3)', cells), '0.6')
  eq (calc ('=MATCH(1.1*3, A1:A4, 0)', cells), '3')
  eq (calc ('=XMATCH(0.3, A1:A4)', cells), '1')
  eq (calc ('=VLOOKUP(0.1+0.2, A2:A3, 1, FALSE)', cells), '0.3')
  eq (calc ('=SWITCH(0.1+0.2, 0.3, "same", "other")'), 'same')
  eq (calc ('=RANK(0.3, A1:A4)', cells), '3')
  eq (calc ('=MODE(0.1+0.2, 0.3, 5)'), '0.3')
  eq (f.compare_numbers (0.1 + 0.2, 0.3), 0)
  eq (f.compare_numbers (1, 2), -1)
  eq (f.compare_numbers (-1, -2), 1)
end)

test ('SUMIF, SUMIFS, COUNTIFS, AVERAGEIFS, MINIFS and MAXIFS', function ()
  eq (calc ('=SUMIF(A1:A11, "a*", B1:B11)', CRIT), '12')
  eq (calc ('=SUMIF(B1:B11, ">5")', CRIT), '51')
  eq (calc ('=SUMIF(A1:A11, "<>apple", B1:B11)', CRIT), '65')
  -- A sum range of another size starts at its top left cell.
  eq (calc ('=SUMIF(A1:A3, "a*", B5)', CRIT), '12')
  eq (calc ('=SUMIFS(B1:B11, A1:A11, "a*", B1:B11, "<5")', CRIT), '4')
  eq (calc ('=SUMIFS(B1:B11, A1:A10, "a*")', CRIT), '#VALUE!')
  eq (calc ('=COUNTIFS(A1:A11, "a*", B1:B11, ">2")', CRIT), '2')
  eq (calc ('=COUNTIFS(A1:A11, "a*", B1:B11)', CRIT), '#VALUE!')
  eq (calc ('=AVERAGEIF(A1:A11, "a*", B1:B11)', CRIT), '4')
  eq (calc ('=AVERAGEIFS(B1:B11, A1:A11, "a*")', CRIT), '4')
  eq (calc ('=AVERAGEIFS(B1:B11, A1:A11, "kiwi")', CRIT), '#DIV/0!')
  eq (calc ('=MINIFS(B1:B11, A1:A11, "a*")', CRIT), '1')
  eq (calc ('=MAXIFS(B1:B11, A1:A11, "a*", B1:B11, "<8")', CRIT), '3')
  eq (calc ('=MINIFS(B1:B11, A1:A11, "kiwi")', CRIT), '0')
  eq (calc ('=MAXIFS(B1:B3, A1:A3, "a*")', { A1 = 'a', B1 = '=1/0' }), '#DIV/0!')
  eq (calc ('=SUMIFS(B1:B2, A1:A2, "x")', { A1 = 'x', B1 = '=1/0' }), '#DIV/0!')
end)

test ('lookups use wildcards in exact mode', function ()
  eq (calc ('=MATCH("b*", A1:A11, 0)', CRIT), '2')
  eq (calc ('=MATCH("~*star", A1:A11, 0)', CRIT), '7')
  eq (calc ('=VLOOKUP("ap*", A1:B11, 2, FALSE)', CRIT), '1')
  eq (calc ('=HLOOKUP("b?nana", {"x","Banana";1,2}, 2, FALSE)'), '2')
  -- XLOOKUP and XMATCH take wildcards only in match mode 2, as spreadsheets do.
  eq (calc ('=XLOOKUP("ap*", A1:A11, B1:B11)', CRIT), '#N/A')
  eq (calc ('=XLOOKUP("ap*", A1:A11, B1:B11, "none", 2)', CRIT), '1')
  eq (calc ('=XMATCH("?bc", A1:A11, 2)', CRIT), '8')
end)

---------------------------------------------------------------------------------------------
-- Lookup
---------------------------------------------------------------------------------------------

-- A grade table sorted by score, and the same scores across a row in E1:I2.
local GRADES = {
  A1 = 10,
  B1 = 'F',
  A2 = 20,
  B2 = 'D',
  A3 = 30,
  B3 = 'C',
  A4 = 40,
  B4 = 'B',
  A5 = 50,
  B5 = 'A',
  C1 = 50,
  C2 = 40,
  C3 = 30,
  C4 = 20,
  C5 = 10,
  E1 = 10,
  F1 = 20,
  G1 = 30,
  H1 = 40,
  I1 = 50,
  E2 = 'F',
  F2 = 'D',
  G2 = 'C',
  H2 = 'B',
  I2 = 'A',
}

test ('VLOOKUP and HLOOKUP find the nearest match in sorted data', function ()
  eq (calc ('=VLOOKUP(35, A1:B5, 2)', GRADES), 'C')
  eq (calc ('=VLOOKUP(35, A1:B5, 2, TRUE)', GRADES), 'C')
  eq (calc ('=VLOOKUP(50, A1:B5, 2)', GRADES), 'A')
  eq (calc ('=VLOOKUP(99, A1:B5, 2)', GRADES), 'A')
  eq (calc ('=VLOOKUP(5, A1:B5, 2)', GRADES), '#N/A')
  eq (calc ('=VLOOKUP(35, A1:B5, 2, FALSE)', GRADES), '#N/A')
  eq (calc ('=VLOOKUP(30, A1:B5, 2, 0)', GRADES), 'C')
  eq (calc ('=VLOOKUP("m", {"a",1;"k",2;"t",3}, 2)'), '2')
  -- An empty lookup value finds nothing, even among empty cells.
  eq (calc ('=VLOOKUP(Z9, A1:B9, 2)', GRADES), '#N/A')
  eq (calc ('=MATCH(Z9, A1:A9)', GRADES), '#N/A')
  eq (calc ('=HLOOKUP(35, E1:I2, 2)', GRADES), 'C')
  eq (calc ('=HLOOKUP(20, E1:I2, 2, FALSE)', GRADES), 'D')
  eq (calc ('=HLOOKUP(20, E1:I2, 3)', GRADES), '#REF!')
  eq (calc ('=HLOOKUP(20, E1:I2, 0)', GRADES), '#VALUE!')
end)

test ('MATCH with types 1, 0 and -1', function ()
  eq (calc ('=MATCH(35, A1:A5)', GRADES), '3')
  eq (calc ('=MATCH(35, A1:A5, 1)', GRADES), '3')
  eq (calc ('=MATCH(5, A1:A5, 1)', GRADES), '#N/A')
  eq (calc ('=MATCH(30, A1:A5, 0)', GRADES), '3')
  eq (calc ('=MATCH(35, C1:C5, -1)', GRADES), '2')
  eq (calc ('=MATCH(10, C1:C5, -1)', GRADES), '5')
  eq (calc ('=MATCH(55, C1:C5, -1)', GRADES), '#N/A')
  -- In sorted data with repeats, the nearest match is the last of the equal values.
  eq (calc ('=MATCH(2, {1,2,2,3})'), '3')
  eq (calc ('=MATCH(20, E1:I1, 0)', GRADES), '2')
end)

test ('LOOKUP in vector and array form', function ()
  eq (calc ('=LOOKUP(35, A1:A5, B1:B5)', GRADES), 'C')
  eq (calc ('=LOOKUP(35, A1:A5, E2:I2)', GRADES), 'C')
  eq (calc ('=LOOKUP(35, A1:B5)', GRADES), 'C')
  eq (calc ('=LOOKUP(35, E1:I2)', GRADES), 'C')
  eq (calc ('=LOOKUP(5, A1:A5, B1:B5)', GRADES), '#N/A')
end)

test ('XLOOKUP', function ()
  eq (calc ('=XLOOKUP(30, A1:A5, B1:B5)', GRADES), 'C')
  eq (calc ('=XLOOKUP(35, A1:A5, B1:B5)', GRADES), '#N/A')
  eq (calc ('=XLOOKUP(35, A1:A5, B1:B5, "none")', GRADES), 'none')
  eq (calc ('=XLOOKUP(35, A1:A5, B1:B5, , -1)', GRADES), 'C')
  eq (calc ('=XLOOKUP(35, A1:A5, B1:B5, , 1)', GRADES), 'B')
  -- The next larger or smaller value needs no sorted data.
  eq (calc ('=XLOOKUP(35, {40,10,30,50}, {"a","b","c","d"}, , 1)'), 'a')
  eq (calc ('=XLOOKUP(35, {40,10,30,50}, {"a","b","c","d"}, , -1)'), 'c')
  -- Search mode -1 finds the last match.
  eq (calc ('=XLOOKUP(2, {1,2,2,3}, {"a","b","c","d"})'), 'b')
  eq (calc ('=XLOOKUP(2, {1,2,2,3}, {"a","b","c","d"}, , 0, -1)'), 'c')
  -- A wider return range gives the whole row or column.
  eq (calc ('=INDEX(XLOOKUP(30, A1:A5, A1:B5), 1, 2)', GRADES), 'C')
  eq (calc ('=INDEX(XLOOKUP(30, E1:I1, E1:I2), 2, 1)', GRADES), 'C')
  eq (calc ('=SUM(XLOOKUP(30, E1:I1, E1:I2))', GRADES), '30')
  eq (calc ('=XLOOKUP(30, A1:A5, B1:B4)', GRADES), '#VALUE!')
  eq (calc ('=XLOOKUP(30, A1:B5, B1:B5)', GRADES), '#VALUE!')
  eq (calc ('=XLOOKUP(30, A1:A5, B1:B5, , 3)', GRADES), '#VALUE!')
end)

test ('XMATCH', function ()
  eq (calc ('=XMATCH(30, A1:A5)', GRADES), '3')
  eq (calc ('=XMATCH(35, A1:A5, 1)', GRADES), '4')
  eq (calc ('=XMATCH(35, A1:A5, -1)', GRADES), '3')
  eq (calc ('=XMATCH(35, A1:A5)', GRADES), '#N/A')
  eq (calc ('=XMATCH(2, {1,2,2,3}, 0, -1)'), '3')
  eq (calc ('=XMATCH(30, A1:B5)', GRADES), '#VALUE!')
end)

test ('INDEX gives cells, rows and columns', function ()
  eq (calc ('=INDEX(A1:B5, 3, 2)', GRADES), 'C')
  eq (calc ('=SUM(INDEX(A1:B5, 0, 1))', GRADES), '150')
  eq (calc ('=INDEX(A1:B5, 2, 0)', GRADES), '20')
  eq (calc ('=COUNTA(INDEX(A1:B5, 2, 0))', GRADES), '2')
  eq (calc ('=INDEX(A1:A5, 2)', GRADES), '20')
  eq (calc ('=INDEX(E1:I1, 2)', GRADES), '20')
  eq (calc ('=INDEX(A1:B5, 6, 1)', GRADES), '#REF!')
  eq (calc ('=INDEX(A1:B5, -1, 1)', GRADES), '#REF!')
  eq (calc ('=INDEX({1,2;3,4}, 2, 2)'), '4')
  eq (calc ('=SUM(INDEX({1,2;3,4}, 0, 2))'), '6')
  eq (calc ('=ROW(INDEX(A1:B5, 4, 1))', GRADES), '4')
end)

test ('ROW, COLUMN, ROWS and COLUMNS', function ()
  eq (calc ('=ROW(C7)'), '7')
  eq (calc ('=ROW(A2:A9)'), '2')
  eq (calc ('=COLUMN(D1)'), '4')
  eq (calc ('=COLUMN(C:E)'), '3')
  eq (calc ('=ROW({1,2})'), '#VALUE!')
  -- With no argument they need to know which cell the formula is in.
  eq (calc ('=ROW()'), '#VALUE!')
  local ast = assert (f.parse ('=ROW()*100+COLUMN()'))
  eq (f.evaluate (ast, book ({}, nil, { 12, 3 })), 1203)
  eq (calc ('=ROWS(A1:B5)'), '5')
  eq (calc ('=COLUMNS(A1:B5)'), '2')
  eq (calc ('=ROWS(5)'), '1')
  eq (calc ('=COLUMNS(A:C)'), '3')
end)

test ('ADDRESS', function ()
  eq (calc ('=ADDRESS(2, 3)'), '$C$2')
  -- Excel's help page for ADDRESS gives C$2 and R2C[3] for these two.
  eq (calc ('=ADDRESS(2, 3, 2)'), 'C$2')
  eq (calc ('=ADDRESS(2, 3, 2, FALSE)'), 'R2C[3]')
  eq (calc ('=ADDRESS(2, 3, 3)'), '$C2')
  eq (calc ('=ADDRESS(2, 3, 4)'), 'C2')
  eq (calc ('=ADDRESS(2, 3, 1, FALSE)'), 'R2C3')
  eq (calc ('=ADDRESS(2, 3, 4, FALSE)'), 'R[2]C[3]')
  eq (calc ('=ADDRESS(1, 27, 1, TRUE, "Q1 sales")'), "'Q1 sales'!$AA$1")
  eq (calc ('=ADDRESS(1, 1, 4, TRUE, "Data")'), 'Data!A1')
  eq (calc ('=ADDRESS(0, 1)'), '#VALUE!')
  eq (calc ('=ADDRESS(1, 1, 5)'), '#VALUE!')
  eq (calc ('=INDIRECT(ADDRESS(2, 2))', REFS), '20')
end)

---------------------------------------------------------------------------------------------
-- Math
---------------------------------------------------------------------------------------------

test ('SUMSQ and PRODUCT', function ()
  eq (calc ('=SUMSQ(3, 4)'), '25')
  eq (calc ('=SUMSQ(A1:A3)', GRID), '126')
  -- Excel's help page for PRODUCT gives 2250 for 5, 15 and 30.
  eq (calc ('=PRODUCT(5, 15, 30)'), '2250')
  eq (calc ('=PRODUCT(A1:A4)', GRID), '162')
  eq (calc ('=PRODUCT(A9)'), '0')
  eq (calc ('=PRODUCT("x")'), '#VALUE!')
end)

test ('MROUND and TRUNC', function ()
  -- Values from Excel's help pages for MROUND and TRUNC.
  eq (calc ('=MROUND(10, 3)'), '9')
  eq (calc ('=MROUND(-10, -3)'), '-9')
  eq (calc ('=MROUND(1.3, 0.2)'), '1.4')
  eq (calc ('=MROUND(5, -2)'), '#NUM!')
  eq (calc ('=MROUND(5, 0)'), '0')
  eq (calc ('=TRUNC(8.9)'), '8')
  eq (calc ('=TRUNC(-8.9)'), '-8')
  eq (calc ('=TRUNC(0.45)'), '0')
  eq (calc ('=TRUNC(3.14159, 2)'), '3.14')
  eq (calc ('=TRUNC(1234, -2)'), '1200')
end)

test ('CEILING and FLOOR, plain and .MATH', function ()
  -- Values from Excel's help pages for these four functions.
  eq (calc ('=CEILING(2.5, 1)'), '3')
  eq (calc ('=CEILING(-2.5, -2)'), '-4')
  eq (calc ('=CEILING(-2.5, 2)'), '-2')
  eq (calc ('=CEILING(1.5, 0.1)'), '1.5')
  eq (calc ('=CEILING(0.234, 0.01)'), '0.24')
  eq (calc ('=CEILING(2.5, -2)'), '#NUM!')
  eq (calc ('=CEILING(4.3)'), '5')
  eq (calc ('=CEILING.MATH(24.3, 5)'), '25')
  eq (calc ('=CEILING.MATH(6.7)'), '7')
  eq (calc ('=CEILING.MATH(-8.1, 2)'), '-8')
  eq (calc ('=CEILING.MATH(-5.5, 2, -1)'), '-6')
  eq (calc ('=FLOOR(3.7, 2)'), '2')
  eq (calc ('=FLOOR(-2.5, -2)'), '-2')
  eq (calc ('=FLOOR(2.5, -2)'), '#NUM!')
  eq (calc ('=FLOOR(1.58, 0.1)'), '1.5')
  eq (calc ('=FLOOR(0.234, 0.01)'), '0.23')
  eq (calc ('=FLOOR(5, 0)'), '#DIV/0!')
  eq (calc ('=FLOOR.MATH(24.3, 5)'), '20')
  eq (calc ('=FLOOR.MATH(6.7)'), '6')
  eq (calc ('=FLOOR.MATH(-8.1, 2)'), '-10')
  eq (calc ('=FLOOR.MATH(-5.5, 2, -1)'), '-4')
end)

test ('EVEN, ODD, QUOTIENT and SIGN', function ()
  -- Values from Excel's help pages for these four functions.
  eq (calc ('=EVEN(1.5)'), '2')
  eq (calc ('=EVEN(3)'), '4')
  eq (calc ('=EVEN(2)'), '2')
  eq (calc ('=EVEN(-1)'), '-2')
  eq (calc ('=EVEN(0)'), '0')
  eq (calc ('=ODD(1.5)'), '3')
  eq (calc ('=ODD(3)'), '3')
  eq (calc ('=ODD(2)'), '3')
  eq (calc ('=ODD(-1)'), '-1')
  eq (calc ('=ODD(-2)'), '-3')
  eq (calc ('=ODD(0)'), '1')
  eq (calc ('=QUOTIENT(5, 2)'), '2')
  eq (calc ('=QUOTIENT(4.5, 3.1)'), '1')
  eq (calc ('=QUOTIENT(-10, 3)'), '-3')
  eq (calc ('=QUOTIENT(1, 0)'), '#DIV/0!')
  eq (calc ('=SIGN(10)'), '1')
  eq (calc ('=SIGN(4-4)'), '0')
  eq (calc ('=SIGN(-0.00001)'), '-1')
end)

test ('EXP, LN, LOG and LOG10', function ()
  eq (calc ('=EXP(1)'), '2.718281828')
  eq (calc ('=EXP(0)'), '1')
  eq (calc ('=EXP(1000)'), '#NUM!')
  -- Excel's help pages give 4.4543473 for LN(86) and 1.9344985 for LOG10(86).
  eq (calc ('=LN(86)'), '4.454347296')
  eq (calc ('=LN(0)'), '#NUM!')
  eq (calc ('=LOG10(86)'), '1.934498451')
  eq (calc ('=LOG10(1E5)'), '5')
  eq (calc ('=LOG10(-1)'), '#NUM!')
  eq (calc ('=LOG(10)'), '1')
  eq (calc ('=LOG(8, 2)'), '3')
  eq (calc ('=LOG(1000)'), '3')
  near ('=LOG(86, 2.7182818)', 4.4543473, 1e-7)
  eq (calc ('=LOG(5, 1)'), '#DIV/0!')
  eq (calc ('=LOG(-1)'), '#NUM!')
end)

test ('RANDBETWEEN reads the dice it is given', function ()
  eq (calc ('=RANDBETWEEN(1, 100)'), '26')
  eq (calc ('=RANDBETWEEN(-5, -5)'), '-5')
  eq (calc ('=RANDBETWEEN(5, 1)'), '#NUM!')
end)

test ('GCD, LCM, FACT, COMBIN and PERMUT', function ()
  -- Values from Excel's help pages for these five functions.
  eq (calc ('=GCD(5, 2)'), '1')
  eq (calc ('=GCD(24, 36)'), '12')
  eq (calc ('=GCD(7, 1)'), '1')
  eq (calc ('=GCD(5, 0)'), '5')
  eq (calc ('=GCD(A1:A3)', GRID), '3')
  eq (calc ('=GCD(-1, 5)'), '#NUM!')
  eq (calc ('=LCM(5, 2)'), '10')
  eq (calc ('=LCM(24, 36)'), '72')
  eq (calc ('=LCM(3, 0)'), '0')
  eq (calc ('=FACT(5)'), '120')
  eq (calc ('=FACT(1.9)'), '1')
  eq (calc ('=FACT(0)'), '1')
  eq (calc ('=FACT(-1)'), '#NUM!')
  eq (calc ('=FACT(171)'), '#NUM!')
  eq (calc ('=COMBIN(8, 2)'), '28')
  eq (calc ('=COMBIN(10, 0)'), '1')
  eq (calc ('=COMBIN(5, 6)'), '#NUM!')
  eq (calc ('=PERMUT(100, 3)'), '970200')
  eq (calc ('=PERMUT(3, 2)'), '6')
  eq (calc ('=PERMUT(3, -1)'), '#NUM!')
end)

test ('angles and trigonometry', function ()
  eq (calc ('=DEGREES(PI())'), '180')
  -- Excel's help page for RADIANS gives 4.712389 for 270 degrees.
  eq (calc ('=RADIANS(270)'), '4.71238898')
  eq (calc ('=SIN(PI()/2)'), '1')
  eq (calc ('=COS(0)'), '1')
  eq (calc ('=TAN(PI()/4)'), '1')
  -- Excel's help pages give -0.523598776, 2.094395102, 0.785398163 and -2.35619449.
  eq (calc ('=ASIN(-0.5)'), '-0.5235987756')
  eq (calc ('=ACOS(-0.5)'), '2.094395102')
  eq (calc ('=ATAN(1)'), '0.7853981634')
  eq (calc ('=ATAN2(1, 1)'), '0.7853981634')
  eq (calc ('=ATAN2(-1, -1)'), '-2.35619449')
  eq (calc ('=ASIN(2)'), '#NUM!')
  eq (calc ('=ACOS(-1.5)'), '#NUM!')
  eq (calc ('=ATAN2(0, 0)'), '#DIV/0!')
end)

---------------------------------------------------------------------------------------------
-- Statistics
---------------------------------------------------------------------------------------------

test ('AVERAGEA counts text as 0 and TRUE as 1', function ()
  -- Excel's help page for AVERAGEA gives 5.6 for 10, 7, 9, 2 and "Not available".
  local cells = { A1 = 10, A2 = 7, A3 = 9, A4 = 2, A5 = 'Not available' }
  eq (calc ('=AVERAGEA(A1:A5)', cells), '5.6')
  eq (calc ('=AVERAGEA(A1:A4, TRUE)', cells), '5.8')
  eq (calc ('=AVERAGEA(A1:A9)', cells), '5.6')
  eq (calc ('=AVERAGEA(A7:A9)', cells), '#DIV/0!')
  eq (calc ('=AVERAGEA("x")', cells), '#VALUE!')
end)

test ('MEDIAN and MODE', function ()
  -- Values from Excel's help pages for MEDIAN and MODE.SNGL.
  eq (calc ('=MEDIAN(1, 2, 3, 4, 5)'), '3')
  eq (calc ('=MEDIAN(1, 2, 3, 4, 5, 6)'), '3.5')
  eq (calc ('=MEDIAN(A9)'), '#NUM!')
  eq (calc ('=MODE(5.6, 4, 4, 3, 2, 4)'), '4')
  eq (calc ('=MODE.SNGL({5.6,4,4,3,2,4})'), '4')
  eq (calc ('=MODE(1, 2, 3)'), '#N/A')
  -- A tie goes to the value that comes first.
  eq (calc ('=MODE(1, 2, 2, 1)'), '1')
end)

test ('LARGE and SMALL', function ()
  -- Values from Excel's help pages for LARGE and SMALL.
  eq (calc ('=LARGE({3,5,3,5,4;4,2,4,6,7}, 3)'), '5')
  eq (calc ('=LARGE({3,5,3,5,4;4,2,4,6,7}, 7)'), '4')
  eq (calc ('=SMALL({3,4,5,2,3,4,6,4,7}, 4)'), '4')
  eq (calc ('=SMALL({1,4,8,3,7,12,54,8,23}, 2)'), '3')
  eq (calc ('=LARGE({1,2}, 0)'), '#NUM!')
  eq (calc ('=SMALL({1,2}, 3)'), '#NUM!')
  eq (calc ('=LARGE(A1:A4, 1)', GRID), '9')
end)

test ('RANK, RANK.EQ and RANK.AVG', function ()
  -- Values from Excel's help pages for RANK and RANK.AVG.
  eq (calc ('=RANK(3.5, {7,3.5,3.5,1,2}, 1)'), '3')
  eq (calc ('=RANK(7, {7,3.5,3.5,1,2}, 1)'), '5')
  eq (calc ('=RANK(7, {7,3.5,3.5,1,2})'), '1')
  eq (calc ('=RANK.AVG(94, {89,88,92,101,94,97,95})'), '4')
  eq (calc ('=RANK.EQ(3.5, {7,3.5,3.5,1,2})'), '2')
  eq (calc ('=RANK.AVG(3.5, {7,3.5,3.5,1,2})'), '2.5')
  eq (calc ('=RANK(9, {1,2})'), '#N/A')
end)

test ('PERCENTILE and QUARTILE', function ()
  -- Values from Excel's help pages for PERCENTILE.INC and QUARTILE.
  eq (calc ('=PERCENTILE({1,3,2,4}, 0.3)'), '1.9')
  eq (calc ('=PERCENTILE.INC({1,2,3,4}, 1)'), '4')
  eq (calc ('=PERCENTILE({1,2,3,4}, 0)'), '1')
  eq (calc ('=PERCENTILE({1,2,3,4}, 1.5)'), '#NUM!')
  eq (calc ('=QUARTILE({1,2,4,7,8,9,10,12}, 1)'), '3.5')
  eq (calc ('=QUARTILE.INC({1,2,4,7,8,9,10,12}, 2)'), '7.5')
  eq (calc ('=QUARTILE({1,2}, 5)'), '#NUM!')
end)

test ('STDEV and VAR, of a sample and of a population', function ()
  -- Excel's help pages use these ten breaking strengths, and give 27.46391572, 26.05455814,
  -- 754.2666667 and 678.84.
  local data = '{1345,1301,1368,1322,1310,1370,1318,1350,1303,1299}'
  eq (calc ('=STDEV(' .. data .. ')'), '27.46391572')
  eq (calc ('=STDEV.S(' .. data .. ')'), '27.46391572')
  eq (calc ('=STDEVP(' .. data .. ')'), '26.05455814')
  eq (calc ('=STDEV.P(' .. data .. ')'), '26.05455814')
  eq (calc ('=VAR(' .. data .. ')'), '754.2666667')
  eq (calc ('=VAR.S(' .. data .. ')'), '754.2666667')
  eq (calc ('=VARP(' .. data .. ')'), '678.84')
  eq (calc ('=VAR.P(' .. data .. ')'), '678.84')
  eq (calc ('=STDEV(1)'), '#DIV/0!')
  eq (calc ('=VARP(1)'), '0')
  eq (calc ('=STDEV.P(A9)'), '#DIV/0!')
end)

test ('CORREL, SLOPE, INTERCEPT and FORECAST', function ()
  -- Values from Excel's help pages: 0.997054486, 0.305556, 0.0483871 and 10.607253.
  near ('=CORREL({3,2,4,5,6}, {9,7,12,15,17})', 0.997054486, 1e-9)
  near ('=SLOPE({2,3,9,1,8,7,5}, {6,5,11,7,5,4,4})', 0.305556, 1e-6)
  near ('=INTERCEPT({2,3,9,1,8}, {6,5,11,7,5})', 0.0483871, 1e-7)
  near ('=FORECAST(30, {6,7,9,15,21}, {20,28,31,38,40})', 10.607253, 1e-6)
  near ('=FORECAST.LINEAR(30, {6,7,9,15,21}, {20,28,31,38,40})', 10.607253, 1e-6)
  -- Pairs with text on either side are left out.
  eq (calc ('=SLOPE({2,4,"x",8}, {1,2,3,4})'), '2')
  eq (calc ('=CORREL({1,2}, {1,2,3})'), '#N/A')
  eq (calc ('=CORREL({1,1}, {1,2})'), '#DIV/0!')
  eq (calc ('=SLOPE({1,2}, {3,3})'), '#DIV/0!')
end)

---------------------------------------------------------------------------------------------
-- Logic
---------------------------------------------------------------------------------------------

test ('IFS and IFNA', function ()
  local cells = { A1 = 85 }
  eq (calc ('=IFS(A1>89, "A", A1>79, "B", TRUE, "F")', cells), 'B')
  eq (calc ('=IFS(A1>89, "A")', cells), '#N/A')
  eq (calc ('=IFS(FALSE, 1, TRUE)', cells), '#VALUE!')
  eq (calc ('=IFS(TRUE, A1:A2)', cells), '85')
  eq (calc ('=IFNA(#N/A, "x")'), 'x')
  eq (calc ('=IFNA(1/0, "x")'), '#DIV/0!')
  eq (calc ('=IFNA(5, "x")'), '5')
  eq (calc ('=IFNA(VLOOKUP(99, {1,2}, 2, FALSE), "none")'), 'none')
end)

test ('XOR, SWITCH and CHOOSE', function ()
  -- Excel's help page for XOR gives FALSE for both of its examples.
  eq (calc ('=XOR(3>0, 2<9)'), 'FALSE')
  eq (calc ('=XOR(3>12, 4>6)'), 'FALSE')
  eq (calc ('=XOR(TRUE, FALSE)'), 'TRUE')
  eq (calc ('=XOR(1>0, 2>0, 3>0)'), 'TRUE')
  eq (calc ('=XOR({TRUE,TRUE,FALSE})'), 'FALSE')
  eq (calc ('=SWITCH(2, 1, "a", 2, "b")'), 'b')
  eq (calc ('=SWITCH(3, 1, "a", 2, "b")'), '#N/A')
  eq (calc ('=SWITCH(3, 1, "a", 2, "b", "other")'), 'other')
  eq (calc ('=SWITCH("B", "b", 1)'), '1')
  eq (calc ('=CHOOSE(2, "a", "b", "c")'), 'b')
  eq (calc ('=CHOOSE(2.9, "a", "b", "c")'), 'b')
  eq (calc ('=CHOOSE(4, "a", "b")'), '#VALUE!')
  eq (calc ('=CHOOSE(0, 1)'), '#VALUE!')
  eq (calc ('=SUM(CHOOSE(2, A1:A2, B1:B2))', GRID), '30')
  -- Only the chosen value is worked out.
  eq (calc ('=CHOOSE(1, 5, 1/0)'), '5')
end)

---------------------------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------------------------

test ('TEXTJOIN', function ()
  eq (calc ('=TEXTJOIN(", ", TRUE, "a", "", "b")'), 'a, b')
  eq (calc ('=TEXTJOIN(", ", FALSE, "a", "", "b")'), 'a, , b')
  eq (calc ('=TEXTJOIN("-", TRUE, A1:A5)', GRID), '3-6-9-x')
  eq (calc ('=TEXTJOIN("-", FALSE, A3:A5)', GRID), '9-x-')
  eq (calc ('=TEXTJOIN("", TRUE, {"a","b";"c","d"})'), 'abcd')
  eq (calc ('=TEXTJOIN(",", TRUE, 1/0)'), '#DIV/0!')
end)

test ('text functions count characters, not bytes', function ()
  eq (calc ('=LEN("café")'), '4')
  eq (calc ('=LEFT("café", 4)'), 'café')
  eq (calc ('=LEFT("café", 3)'), 'caf')
  eq (calc ('=RIGHT("café", 2)'), 'fé')
  eq (calc ('=MID("naïve", 3, 2)'), 'ïv')
  eq (calc ('=MID("naïve", 3, 99)'), 'ïve')
  eq (calc ('=FIND("é", "café")'), '4')
  eq (calc ('=REPLACE("café", 4, 1, "e")'), 'cafe')
  eq (calc ('=UPPER("café")'), 'CAFÉ')
  eq (calc ('=LOWER("ÉCOLE × 2")'), 'école × 2')
end)

test ('PROPER and CLEAN', function ()
  -- Values from Excel's help pages for PROPER and CLEAN.
  eq (calc ('=PROPER("this is a TITLE")'), 'This Is A Title')
  eq (calc ('=PROPER("2-way street")'), '2-Way Street')
  eq (calc ('=PROPER("76BudGet")'), '76Budget')
  eq (calc ('=PROPER("élan VITAL")'), 'Élan Vital')
  eq (calc ('=CLEAN(CHAR(9)&"Monthly report"&CHAR(10))'), 'Monthly report')
end)

test ('REPLACE', function ()
  -- Values from Excel's help page for REPLACE.
  eq (calc ('=REPLACE("abcdefghijk", 6, 5, "*")'), 'abcde*k')
  eq (calc ('=REPLACE("2009", 3, 2, "10")'), '2010')
  eq (calc ('=REPLACE("123456", 1, 3, "@")'), '@456')
  eq (calc ('=REPLACE("abc", 9, 1, "x")'), 'abcx')
  eq (calc ('=REPLACE("abc", 0, 1, "x")'), '#VALUE!')
  eq (calc ('=REPLACE("abc", 1, -1, "x")'), '#VALUE!')
end)

test ('SEARCH ignores case and takes wildcards', function ()
  -- Excel's help page for SEARCH gives 7 and 8 for the first two.
  eq (calc ('=SEARCH("e", "Statements", 6)'), '7')
  eq (calc ('=SEARCH("margin", "Profit Margin")'), '8')
  eq (calc ('=SEARCH("p?o", "Profit")'), '1')
  eq (calc ('=SEARCH("f*t", "Profit")'), '4')
  eq (calc ('=SEARCH("~*", "a*b")'), '2')
  eq (calc ('=SEARCH("É", "café")'), '4')
  eq (calc ('=SEARCH("", "abc", 2)'), '2')
  eq (calc ('=SEARCH("x", "abc")'), '#VALUE!')
  eq (calc ('=SEARCH("a", "abc", 5)'), '#VALUE!')
end)

test ('REPT and EXACT', function ()
  -- Values from Excel's help pages for REPT and EXACT.
  eq (calc ('=REPT("*-", 3)'), '*-*-*-')
  eq (calc ('=REPT("a", 0)'), '')
  eq (calc ('=REPT("a", -1)'), '#VALUE!')
  eq (calc ('=REPT("ab", 20000)'), '#VALUE!')
  eq (calc ('=EXACT("word", "word")'), 'TRUE')
  eq (calc ('=EXACT("Word", "word")'), 'FALSE')
  eq (calc ('=EXACT(1, "1")'), 'TRUE')
end)

test ('VALUE reads money, dates and times too', function ()
  -- Excel's help page for VALUE gives 1000 and 0.2 for these two.
  eq (calc ('=VALUE("$1,000")'), '1000')
  eq (calc ('=VALUE("16:48:00")-VALUE("12:00:00")'), '0.2')
  eq (calc ('=VALUE("2026-09-29")'), '46294')
  eq (calc ('=VALUE("-$5")'), '-5')
  eq (calc ('="2026-09-29"+1'), '46295')
  eq (calc ('=VALUE("$")'), '#VALUE!')
  -- Brackets mean a negative number, as in accounting.
  eq (calc ('=VALUE("(5)")'), '-5')
  eq (calc ('=VALUE(" ( $1,200.50 ) ")'), '-1200.5')
  eq (calc ('="(5)"+1'), '-4')
  eq (calc ('=VALUE("(-5)")'), '#VALUE!')
  eq (calc ('=VALUE("()")'), '#VALUE!')
end)

test ('CHAR, CODE, UNICHAR and UNICODE', function ()
  -- Values from Excel's help pages for these four functions.
  eq (calc ('=CHAR(65)'), 'A')
  eq (calc ('=CHAR(33)'), '!')
  eq (calc ('=CHAR(233)'), 'é')
  eq (calc ('=CHAR(0)'), '#VALUE!')
  eq (calc ('=CHAR(256)'), '#VALUE!')
  eq (calc ('=CODE("A")'), '65')
  eq (calc ('=CODE("!")'), '33')
  eq (calc ('=CODE("é")'), '233')
  eq (calc ('=CODE("")'), '#VALUE!')
  eq (calc ('=UNICHAR(66)'), 'B')
  eq (calc ('=UNICHAR(32)'), ' ')
  eq (calc ('=UNICHAR(8364)'), '€')
  eq (calc ('=UNICHAR(0)'), '#VALUE!')
  eq (calc ('=UNICHAR(55296)'), '#VALUE!')
  eq (calc ('=UNICODE("B")'), '66')
  eq (calc ('=UNICODE(" ")'), '32')
  eq (calc ('=UNICODE("€uro")'), '8364')
end)

test ('T and N', function ()
  -- Values from Excel's help pages for T and N.
  eq (calc ('=T("Rainfall")'), 'Rainfall')
  eq (calc ('=T(19)'), '')
  eq (calc ('=T(TRUE)'), '')
  eq (calc ('=T(A1)', GRID), '')
  eq (calc ('=T(A4)', GRID), 'x')
  eq (calc ('=N(7)'), '7')
  eq (calc ('=N("Even")'), '0')
  eq (calc ('=N(TRUE)'), '1')
  eq (calc ('=N(A9)'), '0')
  eq (calc ('=N(1/0)'), '#DIV/0!')
end)

test ('FIXED and DOLLAR', function ()
  -- Values from Excel's help pages for FIXED and DOLLAR.
  eq (calc ('=FIXED(1234.567, 1)'), '1,234.6')
  eq (calc ('=FIXED(1234.567, -1)'), '1,230')
  eq (calc ('=FIXED(-1234.567, -1, TRUE)'), '-1230')
  eq (calc ('=FIXED(44.332)'), '44.33')
  eq (calc ('=FIXED(0.5, 0)'), '1')
  eq (calc ('=FIXED(-0.001)'), '0.00')
  eq (calc ('=DOLLAR(1234.567, 2)'), '$1,234.57')
  eq (calc ('=DOLLAR(1234.567, -2)'), '$1,200')
  eq (calc ('=DOLLAR(-1234.567, -2)'), '($1,200)')
  eq (calc ('=DOLLAR(-0.123, 4)'), '($0.1230)')
  eq (calc ('=DOLLAR(99.888)'), '$99.89')
end)

test ('TEXTBEFORE and TEXTAFTER', function ()
  eq (calc ('=TEXTBEFORE("a-b-c", "-")'), 'a')
  eq (calc ('=TEXTBEFORE("a-b-c", "-", 2)'), 'a-b')
  eq (calc ('=TEXTBEFORE("a-b-c", "-", -1)'), 'a-b')
  eq (calc ('=TEXTBEFORE("a-b-c", "x")'), '#N/A')
  eq (calc ('=TEXTBEFORE("a-b-c", "x", 1, 0, 0, "none")'), 'none')
  eq (calc ('=TEXTBEFORE("aXb", "x")'), '#N/A')
  eq (calc ('=TEXTBEFORE("aXb", "x", 1, 1)'), 'a')
  eq (calc ('=TEXTBEFORE("a-b", "-", 3)'), '#N/A')
  eq (calc ('=TEXTBEFORE("a-b", "-", 2, 0, 1)'), 'a-b')
  eq (calc ('=TEXTBEFORE("a-b", "-", 0)'), '#VALUE!')
  eq (calc ('=TEXTBEFORE("abc", "")'), '')
  eq (calc ('=TEXTAFTER("a-b-c", "-")'), 'b-c')
  eq (calc ('=TEXTAFTER("a-b-c", "-", 2)'), 'c')
  eq (calc ('=TEXTAFTER("a-b-c", "-", -1)'), 'c')
  eq (calc ('=TEXTAFTER("a--b", "--")'), 'b')
  eq (calc ('=TEXTAFTER("a-b", "-", 2, 0, 1)'), '')
  eq (calc ('=TEXTAFTER("a-b", "-", -2, 0, 1)'), 'a-b')
  eq (calc ('=TEXTAFTER("abc", "")'), 'abc')
  eq (calc ('=TEXTAFTER("café au lait", " AU ", 1, 1)'), 'lait')
end)

---------------------------------------------------------------------------------------------
-- Dates
---------------------------------------------------------------------------------------------

test ('DATE and TIME', function ()
  eq (calc ('=DATE(2026, 9, 29)'), '46294')
  eq (calc ('=DATE(2026, 13, 1)'), day (2027, 1, 1))
  eq (calc ('=DATE(2026, 1, 0)'), day (2025, 12, 31))
  eq (calc ('=DATE(2026, 2, 30)'), day (2026, 3, 2))
  eq (calc ('=DATE(2026, -1, 1)'), day (2025, 11, 1))
  -- Excel's help page for DATE reads year 108 as 2008.
  eq (calc ('=DATE(108, 1, 2)'), day (2008, 1, 2))
  eq (calc ('=DATE(-1, 1, 1)'), '#NUM!')
  eq (calc ('=DATE(10000, 1, 1)'), '#NUM!')
  eq (calc ('=TIME(12, 0, 0)'), '0.5')
  -- Excel's help page for TIME gives 0.7001157 and 0.520833 for these two.
  near ('=TIME(16, 48, 10)', 0.7001157, 1e-7)
  near ('=TIME(0, 750, 0)', 0.520833, 1e-6)
  eq (calc ('=TIME(27, 0, 0)'), '0.125')
  eq (calc ('=TIME(-1, 0, 0)'), '#NUM!')
end)

test ('YEAR, MONTH, DAY, HOUR, MINUTE and SECOND', function ()
  eq (calc ('=YEAR(DATE(2026, 9, 29))'), '2026')
  eq (calc ('=MONTH(DATE(2026, 9, 29))'), '9')
  eq (calc ('=DAY(DATE(2026, 9, 29))'), '29')
  eq (calc ('=YEAR("2026-09-29")'), '2026')
  -- Values from Excel's help pages for MONTH, HOUR, MINUTE and SECOND.
  eq (calc ('=MONTH("15-Apr-2011")'), '4')
  eq (calc ('=DAY("15-Apr-2011")'), '15')
  eq (calc ('=HOUR(0.75)'), '18')
  eq (calc ('=HOUR("3:30:30 PM")'), '15')
  eq (calc ('=MINUTE("12:45:00")'), '45')
  eq (calc ('=SECOND("4:48:18 PM")'), '18')
  eq (calc ('=HOUR(NOW())&":"&MINUTE(NOW())'), '14:30')
  eq (calc ('=YEAR(-1)'), '#NUM!')
  eq (calc ('=YEAR("nope")'), '#VALUE!')
  -- An empty cell is day 0, which Excel's calendar shows as 1900-01-00.
  eq (calc ('=MONTH(A9)'), '1')
end)

test ('WEEKDAY, WEEKNUM and ISOWEEKNUM', function ()
  -- 2008-02-14 was a Thursday. Excel's help page for WEEKDAY gives 5, 4 and 3.
  eq (calc ('=WEEKDAY(DATE(2008, 2, 14))'), '5')
  eq (calc ('=WEEKDAY(DATE(2008, 2, 14), 2)'), '4')
  eq (calc ('=WEEKDAY(DATE(2008, 2, 14), 3)'), '3')
  eq (calc ('=WEEKDAY(DATE(2008, 2, 14), 11)'), '4')
  eq (calc ('=WEEKDAY(DATE(2008, 2, 14), 16)'), '6')
  eq (calc ('=WEEKDAY(DATE(2008, 2, 14), 4)'), '#NUM!')
  -- Excel's help pages give 10 and 11 for WEEKNUM, and 10 for ISOWEEKNUM, of 2012-03-09.
  eq (calc ('=WEEKNUM(DATE(2012, 3, 9))'), '10')
  eq (calc ('=WEEKNUM(DATE(2012, 3, 9), 2)'), '11')
  eq (calc ('=ISOWEEKNUM(DATE(2012, 3, 9))'), '10')
  eq (calc ('=WEEKNUM(DATE(2026, 9, 29))'), '40')
  eq (calc ('=WEEKNUM(DATE(2026, 9, 29), 21)'), '40')
  -- 2021-01-01 was a Friday, so it falls in the last ISO week of 2020.
  eq (calc ('=ISOWEEKNUM(DATE(2021, 1, 1))'), '53')
  eq (calc ('=WEEKNUM(DATE(2026, 1, 1), 3)'), '#NUM!')
end)

test ('EDATE, EOMONTH and DAYS', function ()
  -- Values from Excel's help pages for EDATE, EOMONTH and DAYS.
  eq (calc ('=EDATE(DATE(2011, 1, 15), 1)'), day (2011, 2, 15))
  eq (calc ('=EDATE(DATE(2011, 1, 15), -1)'), day (2010, 12, 15))
  eq (calc ('=EDATE(DATE(2011, 1, 15), 2)'), day (2011, 3, 15))
  eq (calc ('=EDATE(DATE(2026, 1, 31), 1)'), day (2026, 2, 28))
  eq (calc ('=EDATE("2024-02-29", 12)'), day (2025, 2, 28))
  eq (calc ('=EOMONTH(DATE(2011, 1, 1), 1)'), day (2011, 2, 28))
  eq (calc ('=EOMONTH(DATE(2011, 1, 1), -3)'), day (2010, 10, 31))
  eq (calc ('=EOMONTH(DATE(2024, 1, 15), 1)'), day (2024, 2, 29))
  eq (calc ('=EOMONTH(1, -1)'), '#NUM!')
  eq (calc ('=DAYS("15-MAR-2021", "1-FEB-2021")'), '42')
  eq (calc ('=DAYS(DATE(2021, 12, 31), DATE(2021, 1, 1))'), '364')
  eq (calc ('=DAYS(1, 2)'), '-1')
end)

test ('DATEDIF counts in years, months and days', function ()
  -- Values from Excel's help page for DATEDIF.
  eq (calc ('=DATEDIF("2001-01-01", "2003-01-01", "Y")'), '2')
  eq (calc ('=DATEDIF("2001-06-01", "2002-08-15", "D")'), '440')
  eq (calc ('=DATEDIF("2001-06-01", "2002-08-15", "YD")'), '75')
  eq (calc ('=DATEDIF("2001-06-01", "2002-08-15", "MD")'), '14')
  eq (calc ('=DATEDIF("2001-06-01", "2002-08-15", "m")'), '14')
  eq (calc ('=DATEDIF("2001-06-01", "2002-08-15", "YM")'), '2')
  eq (calc ('=DATEDIF("2001-06-15", "2002-08-01", "M")'), '13')
  eq (calc ('=DATEDIF("2026-01-15", "2026-03-10", "MD")'), '23')
  eq (calc ('=DATEDIF("2025-12-15", "2026-01-10", "YD")'), '26')
  eq (calc ('=DATEDIF("2003-01-01", "2001-01-01", "Y")'), '#NUM!')
  eq (calc ('=DATEDIF("2001-01-01", "2003-01-01", "W")'), '#NUM!')
end)

test ('NETWORKDAYS and WORKDAY skip weekends and holidays', function ()
  -- Values from Excel's help pages for NETWORKDAYS and WORKDAY.
  local cells = {
    H1 = f.serial (2012, 11, 22),
    H2 = f.serial (2012, 12, 4),
    H3 = f.serial (2013, 1, 21),
    J1 = f.serial (2008, 11, 26),
    J2 = f.serial (2008, 12, 4),
    J3 = f.serial (2009, 1, 21),
  }
  eq (calc ('=NETWORKDAYS(DATE(2012, 10, 1), DATE(2013, 3, 1))', cells), '110')
  eq (
    calc ('=NETWORKDAYS(DATE(2012, 10, 1), DATE(2013, 3, 1), H1)', cells),
    '109'
  )
  eq (
    calc ('=NETWORKDAYS(DATE(2012, 10, 1), DATE(2013, 3, 1), H1:H3)', cells),
    '107'
  )
  eq (calc ('=NETWORKDAYS(DATE(2013, 3, 1), DATE(2012, 10, 1))', cells), '-110')
  eq (calc ('=NETWORKDAYS("2026-10-03", "2026-10-04")', cells), '0')
  eq (calc ('=WORKDAY(DATE(2008, 10, 1), 151)', cells), day (2009, 4, 30))
  eq (calc ('=WORKDAY(DATE(2008, 10, 1), 151, J1:J3)', cells), day (2009, 5, 5))
  -- 2026-10-02 is a Friday.
  eq (calc ('=WORKDAY(DATE(2026, 10, 2), 1)', cells), day (2026, 10, 5))
  eq (calc ('=WORKDAY(DATE(2026, 10, 5), -1)', cells), day (2026, 10, 2))
  eq (calc ('=WORKDAY(DATE(2026, 10, 3), 0)', cells), day (2026, 10, 3))
  eq (
    calc ('=WORKDAY(DATE(2026, 10, 2), 1, {"2026-10-05"})', cells),
    day (2026, 10, 6)
  )
end)

test ('DATEVALUE and TIMEVALUE read dates and times from text', function ()
  -- Excel's help page for DATEVALUE gives 40777, 40685 and 40597 for the first three.
  eq (calc ('=DATEVALUE("8/22/2011")'), '40777')
  eq (calc ('=DATEVALUE("22-MAY-2011")'), '40685')
  eq (calc ('=DATEVALUE("2011/02/23")'), '40597')
  -- A date with no year takes this year from the clock.
  eq (calc ('=DATEVALUE("5-JUL")'), day (2026, 7, 5))
  eq (calc ('=DATEVALUE("2026-09-29 14:30")'), '46294')
  eq (calc ('=DATEVALUE("Sep 29, 2026")'), '46294')
  eq (calc ('=DATEVALUE("September 29 2026")'), '46294')
  eq (calc ('=DATEVALUE("29 September 2026")'), '46294')
  eq (calc ('=DATEVALUE("9/29/26")'), '46294')
  eq (calc ('=DATEVALUE("2/30/2026")'), '#VALUE!')
  eq (calc ('=DATEVALUE("nope")'), '#VALUE!')
  eq (calc ('=DATEVALUE(46294)'), '#VALUE!')
  -- Excel's help page for TIMEVALUE gives 0.1 and 0.2743 for these two.
  eq (calc ('=TIMEVALUE("2:24 AM")'), '0.1')
  near ('=TIMEVALUE("22-Aug-2011 6:35 AM")', 0.274305556, 1e-9)
  near ('=TIMEVALUE("14:30")', 14.5 / 24, 1e-12)
  eq (calc ('=TIMEVALUE("12:00 am")'), '0')
  eq (calc ('=TIMEVALUE("x")'), '#VALUE!')
  eq (calc ('=TIMEVALUE("13:00 pm")'), '#VALUE!')
end)

test ('YEARFRAC', function ()
  -- Excel's help page for YEARFRAC gives 0.58055556, 0.57650273 and 0.57808219.
  near ('=YEARFRAC(DATE(2012, 1, 1), DATE(2012, 7, 30))', 0.58055556, 1e-8)
  near ('=YEARFRAC(DATE(2012, 1, 1), DATE(2012, 7, 30), 1)', 0.57650273, 1e-8)
  near ('=YEARFRAC(DATE(2012, 1, 1), DATE(2012, 7, 30), 3)', 0.57808219, 1e-8)
  near ('=YEARFRAC(DATE(2012, 1, 1), DATE(2012, 7, 30), 2)', 211 / 360, 1e-12)
  -- Over several years, basis 1 divides by the mean length of the years: 1461 / 4 here.
  near ('=YEARFRAC(DATE(2010, 6, 1), DATE(2013, 6, 1), 1)', 1096 / 365.25, 1e-12)
  near ('=YEARFRAC(DATE(2012, 7, 30), DATE(2012, 1, 1))', 0.58055556, 1e-8)
  near ('=YEARFRAC(DATE(2026, 1, 31), DATE(2026, 3, 31), 4)', 60 / 360, 1e-12)
  eq (calc ('=YEARFRAC(1, 2, 5)'), '#NUM!')
end)

---------------------------------------------------------------------------------------------
-- Info
---------------------------------------------------------------------------------------------

test ('the IS functions', function ()
  local cells = { A1 = '=1/0', A2 = '', A3 = 4 }
  eq (calc ('=ISBLANK(A9)', cells), 'TRUE')
  eq (calc ('=ISBLANK(A2)', cells), 'FALSE')
  eq (calc ('=ISBLANK(A1)', cells), 'FALSE')
  eq (calc ('=ISNUMBER(A3)', cells), 'TRUE')
  eq (calc ('=ISNUMBER("4")', cells), 'FALSE')
  eq (calc ('=ISTEXT("a")', cells), 'TRUE')
  eq (calc ('=ISTEXT(A9)', cells), 'FALSE')
  eq (calc ('=ISLOGICAL(TRUE)', cells), 'TRUE')
  eq (calc ('=ISLOGICAL("TRUE")', cells), 'FALSE')
  eq (calc ('=ISERROR(A1)', cells), 'TRUE')
  eq (calc ('=ISERROR(#N/A)', cells), 'TRUE')
  eq (calc ('=ISERROR(A3)', cells), 'FALSE')
  eq (calc ('=ISERR(#N/A)', cells), 'FALSE')
  eq (calc ('=ISERR(1/0)', cells), 'TRUE')
  eq (calc ('=ISNA(NA())', cells), 'TRUE')
  eq (calc ('=ISNA(1/0)', cells), 'FALSE')
  -- Values from Excel's help pages for ISEVEN and ISODD.
  eq (calc ('=ISEVEN(-1)'), 'FALSE')
  eq (calc ('=ISEVEN(2.5)'), 'TRUE')
  eq (calc ('=ISEVEN(5)'), 'FALSE')
  eq (calc ('=ISEVEN(0)'), 'TRUE')
  eq (calc ('=ISODD(-1)'), 'TRUE')
  eq (calc ('=ISODD(2.5)'), 'FALSE')
  eq (calc ('=ISODD(5)'), 'TRUE')
  eq (calc ('=ISEVEN("x")'), '#VALUE!')
  eq (calc ('=ISREF(A1)', cells), 'TRUE')
  eq (calc ('=ISREF(A1:B2)', cells), 'TRUE')
  eq (calc ('=ISREF(OFFSET(A1, 1, 1))', cells), 'TRUE')
  eq (calc ('=ISREF(INDIRECT("A3"))', cells), 'TRUE')
  eq (calc ('=ISREF(1)', cells), 'FALSE')
  eq (calc ('=ISREF("A1")', cells), 'FALSE')
  eq (calc ('=ISREF(ABS(1))', cells), 'FALSE')
end)

test ('NA, TYPE and ERROR.TYPE', function ()
  eq (calc ('=NA()'), '#N/A')
  eq (calc ('=TYPE(2)'), '1')
  eq (calc ('=TYPE("x")'), '2')
  eq (calc ('=TYPE(TRUE)'), '4')
  eq (calc ('=TYPE(1/0)'), '16')
  eq (calc ('=TYPE({1,2})'), '64')
  eq (calc ('=TYPE(A9)'), '1')
  eq (calc ('=TYPE(A1:A3)', GRID), '64')
  eq (calc ('=TYPE(A4:A4)', GRID), '2')
  eq (calc ('=ERROR.TYPE(#NULL!)'), '1')
  eq (calc ('=ERROR.TYPE(1/0)'), '2')
  eq (calc ('=ERROR.TYPE("a"+1)'), '3')
  eq (calc ('=ERROR.TYPE(#REF!)'), '4')
  eq (calc ('=ERROR.TYPE(NOPE())'), '5')
  eq (calc ('=ERROR.TYPE(SQRT(-1))'), '6')
  eq (calc ('=ERROR.TYPE(#N/A)'), '7')
  eq (calc ('=ERROR.TYPE(1)'), '#N/A')
end)

---------------------------------------------------------------------------------------------
-- Financial
---------------------------------------------------------------------------------------------

test ('PMT, IPMT and PPMT', function ()
  -- Values from Excel's help pages for these three functions.
  eq (calc ('=ROUND(PMT(0.08/12, 10, 10000), 2)'), '-1037.03')
  eq (calc ('=ROUND(PMT(0.06/12, 18*12, 0, 50000), 2)'), '-129.08')
  eq (calc ('=PMT(0, 10, 1000)'), '-100')
  eq (calc ('=PMT(0.1, 0, 1000)'), '#NUM!')
  eq (calc ('=ROUND(IPMT(0.1/12, 1, 3*12, 8000), 2)'), '-66.67')
  eq (calc ('=ROUND(IPMT(0.1, 3, 3, 8000), 2)'), '-292.45')
  eq (calc ('=IPMT(0.1, 4, 3, 8000)'), '#NUM!')
  eq (calc ('=ROUND(PPMT(0.1/12, 1, 2*12, 2000), 2)'), '-75.62')
  eq (calc ('=ROUND(PPMT(0.08, 10, 10, 200000), 2)'), '-27598.05')
  -- The interest and the principal add up to the payment.
  near (
    '=IPMT(0.05, 2, 10, 1000, 0, 1)+PPMT(0.05, 2, 10, 1000, 0, 1)',
    -123.3376,
    1e-4
  )
end)

test ('FV, PV and NPV', function ()
  -- Values from Excel's help pages for these three functions.
  eq (calc ('=ROUND(FV(0.06/12, 10, -200, -500, 1), 2)'), '2581.4')
  eq (calc ('=ROUND(FV(0.12/12, 12, -1000), 2)'), '12682.5')
  eq (calc ('=ROUND(FV(0.11/12, 35, -2000, , 1), 2)'), '82846.25')
  eq (calc ('=FV(0, 10, -100)'), '1000')
  eq (calc ('=ROUND(PV(0.08/12, 12*20, 500), 2)'), '-59777.15')
  eq (calc ('=PV(0, 10, 100)'), '-1000')
  eq (calc ('=ROUND(NPV(0.1, -10000, 3000, 4200, 6800), 2)'), '1188.44')
  eq (
    calc ('=ROUND(NPV(0.08, 8000, 9200, 10000, 12000, 14500)-40000, 2)'),
    '1922.06'
  )
  eq (calc ('=NPV(-1, 1)'), '#DIV/0!')
  eq (calc ('=NPV(0, A1:A4)', GRID), '18')
end)

test ('NPER, RATE and IRR', function ()
  -- Values from Excel's help pages: 59.6738657, 60.0821229 and -9.57859404 for NPER, 9.24% a
  -- year for RATE, and -2.1%, 8.7% and -44.4% for IRR.
  near ('=NPER(0.12/12, -100, -1000, 10000, 1)', 59.6738657, 1e-7)
  near ('=NPER(0.12/12, -100, -1000, 10000)', 60.0821229, 1e-7)
  near ('=NPER(0.12/12, -100, -1000)', -9.57859404, 1e-8)
  eq (calc ('=NPER(0, -100, 1000)'), '10')
  eq (calc ('=NPER(0.1, 0, 1000)'), '#NUM!')
  eq (calc ('=ROUND(RATE(4*12, -200, 8000)*12, 4)'), '0.0924')
  near ('=RATE(10, 0, -100, 200)', 2 ^ 0.1 - 1, 1e-9)
  eq (calc ('=ROUND(IRR({-70000,12000,15000,18000,21000}), 3)'), '-0.021')
  eq (calc ('=ROUND(IRR({-70000,12000,15000,18000,21000,26000}), 3)'), '0.087')
  eq (calc ('=ROUND(IRR({-70000,12000,15000}, -0.1), 3)'), '-0.444')
  eq (calc ('=IRR({1,2})'), '#NUM!')
  -- Plain Newton steps past -1 from the default guess on these. Excel finds -63% and -19%.
  near ('=IRR({-100,10,10})', -0.629844, 1e-6)
  near ('=IRR({-100,10,10,10,10,10})', -0.194018520, 1e-8)
  near ('=RATE(2, 10, -100)', -0.629844, 1e-6)
  near ('=RATE(12, -100, 400)', 0.2289330710, 1e-9)
  eq (calc ('=RATE(10, 0, -100, -200)'), '#NUM!')
  eq (calc ('=IRR({-100,10,10}, -1)'), '#NUM!')
end)

---------------------------------------------------------------------------------------------
-- Arrays, LET and LAMBDA
---------------------------------------------------------------------------------------------

---Works out a formula that gives a block, and shows its values row by row: commas between
---the values of a row and semicolons between rows, as an array constant writes them.
---@param formula string
---@param cells? Cells
---@return string
local function rows_of (formula, cells)
  local body = string.sub (formula, 2)
  local h = value ('=ROWS(' .. body .. ')', cells)
  local w = value ('=COLUMNS(' .. body .. ')', cells)
  if type (h) ~= 'number' or type (w) ~= 'number' then
    return f.format_value (value (formula, cells))
  end
  local out = {} ---@type string[]
  for i = 1, h do
    local line = {} ---@type string[]
    for j = 1, w do
      line[j] = calc (string.format ('=INDEX(%s, %d, %d)', body, i, j), cells)
    end
    out[i] = table.concat (line, ',')
  end
  return table.concat (out, ';')
end

local PEOPLE = {
  A1 = 'Ann',
  B1 = 'Sales',
  C1 = 300,
  A2 = 'bob',
  B2 = 'Ops',
  C2 = 100,
  A3 = 'Cy',
  B3 = 'Sales',
  C3 = 200,
  A4 = 'ann',
  B4 = 'Ops',
  C4 = 100,
}

test ('SEQUENCE counts up row by row', function ()
  eq (rows_of ('=SEQUENCE(3)'), '1;2;3')
  eq (rows_of ('=SEQUENCE(2, 3)'), '1,2,3;4,5,6')
  eq (rows_of ('=SEQUENCE(2, 2, 10, -5)'), '10,5;0,-5')
  eq (calc ('=SUM(SEQUENCE(100))'), '5050')
  eq (calc ('=SEQUENCE(0)'), '#CALC!')
  eq (calc ('=SEQUENCE(-1)'), '#VALUE!')
end)

test ('UNIQUE drops repeats, ignoring case', function ()
  eq (rows_of ('=UNIQUE(B1:B4)', PEOPLE), 'Sales;Ops')
  eq (rows_of ('=UNIQUE(A1:A4)', PEOPLE), 'Ann;bob;Cy')
  eq (rows_of ('=UNIQUE(B1:C4)', PEOPLE), 'Sales,300;Ops,100;Sales,200')
  eq (rows_of ('=UNIQUE(C1:C4, FALSE, TRUE)', PEOPLE), '300;200')
  eq (rows_of ('=UNIQUE({1,2,1,3}, TRUE)'), '1,2,3')
  eq (rows_of ('=UNIQUE(A1:A3)', { A1 = 0.3, A2 = 1, A3 = '=0.1+0.2' }), '0.3;1')
  eq (calc ('=UNIQUE({1;1}, FALSE, TRUE)'), '#CALC!')
end)

test (
  'SORT and SORTBY put rows in order and keep equal rows as they were',
  function ()
    eq (rows_of ('=SORT(C1:C4)', PEOPLE), '100;100;200;300')
    eq (
      rows_of ('=SORT(A1:C4, 3, -1)', PEOPLE),
      'Ann,Sales,300;Cy,Sales,200;bob,Ops,100;ann,Ops,100'
    )
    eq (
      rows_of ('=SORT(A1:B4, {2,1}, {1,-1})', PEOPLE),
      'bob,Ops;ann,Ops;Cy,Sales;Ann,Sales'
    )
    eq (rows_of ('=SORT({3,1,2}, 1, 1, TRUE)'), '1,2,3')
    eq (rows_of ('=SORT({"b";2;TRUE;"a";1})'), '1;2;a;b;TRUE')
    eq (
      rows_of ('=SORTBY(A1:A4, C1:C4, 1, B1:B4, -1)', PEOPLE),
      'bob;ann;Cy;Ann'
    )
    eq (rows_of ('=SORTBY({"x","y","z"}, {3,1,2})'), 'y,z,x')
    eq (calc ('=SORT(A1:C4, 4)', PEOPLE), '#VALUE!')
    eq (calc ('=SORT(A1:C4, 1, 0)', PEOPLE), '#VALUE!')
    eq (calc ('=SORTBY(A1:A4, C1:C3)', PEOPLE), '#VALUE!')
  end
)

test ('FILTER keeps the rows where a test is TRUE', function ()
  eq (rows_of ('=FILTER(A1:A4, B1:B4="Sales")', PEOPLE), 'Ann;Cy')
  eq (
    rows_of ('=FILTER(A1:C4, (B1:B4="Ops")*(C1:C4>50))', PEOPLE),
    'bob,Ops,100;ann,Ops,100'
  )
  eq (rows_of ('=FILTER({1,2,3}, {TRUE,FALSE,TRUE})'), '1,3')
  eq (calc ('=FILTER(A1:A4, C1:C4>1000)', PEOPLE), '#CALC!')
  eq (calc ('=FILTER(A1:A4, C1:C4>1000, "none")', PEOPLE), 'none')
  eq (calc ('=FILTER(A1:A4, C1:C3>1)', PEOPLE), '#VALUE!')
  eq (calc ('=SUM(FILTER(C1:C4, B1:B4="Sales"))', PEOPLE), '500')
end)

test ('LET names values inside a formula', function ()
  eq (calc ('=LET(x, 2, y, x*10, x+y)'), '22')
  eq (calc ('=LET(total, SUM(C1:C4), total/4)', PEOPLE), '175')
  -- A name can hold a block of cells, and functions that need a reference take it.
  eq (calc ('=LET(r, C1:C4, ROWS(r) & "/" & MAX(r))', PEOPLE), '4/300')
  eq (calc ('=LET(x, 1, LET(x, 2, x) + x)'), '3')
  eq (calc ('=LET(x, 1)'), '#VALUE!')
  eq (calc ('=LET(A1, 1, 2)'), '#VALUE!')
  eq (calc ('=x+1'), '#NAME?')
  eq (calc ('=LET(x, 1/0, 5)'), '#DIV/0!')
end)

test ('LAMBDA makes a function that LET, MAP and their kin call', function ()
  eq (calc ('=LAMBDA(a, b, a*b)(6, 7)'), '42')
  eq (calc ('=LET(double, LAMBDA(n, n*2), double(21))'), '42')
  eq (calc ('=LET(k, 3, add, LAMBDA(n, n+k), add(1))'), '4')
  eq (calc ('=LAMBDA(x, x)'), '#CALC!')
  eq (calc ('=LAMBDA(x, x)(1, 2)'), '#VALUE!')
  eq (calc ('=LET(x, 5, x(1))'), '#VALUE!')
  eq (rows_of ('=MAP({1,2;3,4}, LAMBDA(x, x*x))'), '1,4;9,16')
  eq (rows_of ('=MAP({1,2}, {10,20}, LAMBDA(a, b, a+b))'), '11,22')
  eq (rows_of ('=MAP({1,0}, LAMBDA(x, 1/x))'), '1,#DIV/0!')
  eq (calc ('=REDUCE(0, C1:C4, LAMBDA(acc, x, acc+x))', PEOPLE), '700')
  eq (calc ('=REDUCE(, {1,2,3}, LAMBDA(acc, x, acc+x))'), '6')
  eq (rows_of ('=SCAN(0, {1,2,3}, LAMBDA(acc, x, acc+x))'), '1,3,6')
  eq (rows_of ('=BYROW({1,2;3,4}, LAMBDA(row, SUM(row)))'), '3;7')
  eq (rows_of ('=BYCOL({1,2;3,4}, LAMBDA(col, MAX(col)))'), '3,4')
  eq (rows_of ('=MAKEARRAY(2, 3, LAMBDA(r, c, r*10+c))'), '11,12,13;21,22,23')
  eq (calc ('=MAP({1}, 5)'), '#VALUE!')
end)

---------------------------------------------------------------------------------------------
-- Every function
---------------------------------------------------------------------------------------------

local EVERY = {
  'ABS',
  'ACOS',
  'ADDRESS',
  'AND',
  'ASIN',
  'ATAN',
  'ATAN2',
  'AVERAGE',
  'AVERAGEA',
  'AVERAGEIF',
  'AVERAGEIFS',
  'BYCOL',
  'BYROW',
  'CEILING',
  'CEILING.MATH',
  'CHAR',
  'CHOOSE',
  'CLEAN',
  'CODE',
  'COLUMN',
  'COLUMNS',
  'COMBIN',
  'CONCAT',
  'CONCATENATE',
  'CORREL',
  'COS',
  'COUNT',
  'COUNTA',
  'COUNTBLANK',
  'COUNTIF',
  'COUNTIFS',
  'DATE',
  'DATEDIF',
  'DATEVALUE',
  'DAY',
  'DAYS',
  'DEGREES',
  'DOLLAR',
  'EDATE',
  'EOMONTH',
  'ERROR.TYPE',
  'EVEN',
  'EXACT',
  'EXP',
  'FACT',
  'FALSE',
  'FILTER',
  'FIND',
  'FIXED',
  'FLOOR',
  'FLOOR.MATH',
  'FORECAST',
  'FORECAST.LINEAR',
  'FV',
  'GCD',
  'HLOOKUP',
  'HOUR',
  'IF',
  'IFERROR',
  'IFNA',
  'IFS',
  'INDEX',
  'INDIRECT',
  'INT',
  'INTERCEPT',
  'IPMT',
  'IRR',
  'ISBLANK',
  'ISERR',
  'ISERROR',
  'ISEVEN',
  'ISLOGICAL',
  'ISNA',
  'ISNUMBER',
  'ISODD',
  'ISOWEEKNUM',
  'ISREF',
  'ISTEXT',
  'LAMBDA',
  'LARGE',
  'LCM',
  'LEFT',
  'LEN',
  'LET',
  'LN',
  'LOG',
  'LOG10',
  'LOOKUP',
  'LOWER',
  'MAKEARRAY',
  'MAP',
  'MATCH',
  'MAX',
  'MAXIFS',
  'MEDIAN',
  'MID',
  'MIN',
  'MINIFS',
  'MINUTE',
  'MOD',
  'MODE',
  'MODE.SNGL',
  'MONTH',
  'MROUND',
  'N',
  'NA',
  'NETWORKDAYS',
  'NOT',
  'NOW',
  'NPER',
  'NPV',
  'ODD',
  'OFFSET',
  'OR',
  'PERCENTILE',
  'PERCENTILE.INC',
  'PERMUT',
  'PI',
  'PMT',
  'POWER',
  'PPMT',
  'PRODUCT',
  'PROPER',
  'PV',
  'QUARTILE',
  'QUARTILE.INC',
  'QUOTIENT',
  'RADIANS',
  'RAND',
  'RANDBETWEEN',
  'RANK',
  'RANK.AVG',
  'RANK.EQ',
  'RATE',
  'REDUCE',
  'REPLACE',
  'REPT',
  'RIGHT',
  'ROUND',
  'ROUNDDOWN',
  'ROUNDUP',
  'ROW',
  'ROWS',
  'SCAN',
  'SEARCH',
  'SECOND',
  'SEQUENCE',
  'SIGN',
  'SIN',
  'SLOPE',
  'SMALL',
  'SORT',
  'SORTBY',
  'SQRT',
  'STDEV',
  'STDEV.P',
  'STDEV.S',
  'STDEVP',
  'SUBSTITUTE',
  'SUM',
  'SUMIF',
  'SUMIFS',
  'SUMPRODUCT',
  'SUMSQ',
  'SWITCH',
  'T',
  'TAN',
  'TEXT',
  'TEXTAFTER',
  'TEXTBEFORE',
  'TEXTJOIN',
  'TIME',
  'TIMEVALUE',
  'TODAY',
  'TRIM',
  'TRUE',
  'TRUNC',
  'TYPE',
  'UNICHAR',
  'UNICODE',
  'UNIQUE',
  'UPPER',
  'VALUE',
  'VAR',
  'VAR.P',
  'VAR.S',
  'VARP',
  'VLOOKUP',
  'WEEKDAY',
  'WEEKNUM',
  'WORKDAY',
  'XLOOKUP',
  'XMATCH',
  'XOR',
  'YEAR',
  'YEARFRAC',
}

test ('the function list is complete, and every function has a test', function ()
  eq (f.functions, EVERY)
  -- A function counts as tested when a formula in this file or sheet.test.lua calls it.
  local called = {} ---@type table<string, boolean>
  for _, path in ipairs ({
    'plugins/proteus.sheet/tests/sheet_formula.test.lua',
    'plugins/proteus.sheet/tests/sheet.test.lua',
  }) do
    for name in string.gmatch (read (path), '([%a][%w%.]*)%(') do
      called[string.upper (name)] = true
    end
  end
  for _, name in ipairs (f.functions) do
    ok (called[name], name .. ' has no test')
  end
end)

test ('the catalog has one entry for each function', function ()
  local categories = {
    Math = true,
    Statistics = true,
    Logic = true,
    Text = true,
    Lookup = true,
    Date = true,
    Info = true,
    Financial = true,
  }
  local names = {} ---@type string[]
  for i, entry in ipairs (f.catalog) do
    names[i] = entry.name
    ok (categories[entry.category], entry.name .. ' has an odd category')
    ok (
      string.sub (entry.syntax, 1, #entry.name + 1) == entry.name .. '(',
      entry.name .. ' has an odd syntax'
    )
    ok (string.sub (entry.syntax, -1) == ')', entry.name .. ' syntax ends oddly')
    ok (
      string.match (entry.summary, '^%u.*%.$') ~= nil,
      entry.name .. ' needs a one-sentence summary'
    )
  end
  eq (names, EVERY)
  for _, entry in ipairs (f.catalog) do
    if entry.name == 'SUMIF' then
      eq (entry, {
        name = 'SUMIF',
        category = 'Math',
        syntax = 'SUMIF(range, criterion, [sum_range])',
        summary = 'Adds the numbers in a range that meet a condition.',
      })
    end
  end
end)

---------------------------------------------------------------------------------------------
-- Helpers for typing formulas
---------------------------------------------------------------------------------------------

test ('complete finds the function name being typed', function ()
  eq (f.complete ('=SU', 4), { from = 2, to = 3, prefix = 'SU' })
  -- At the start of a name nothing is typed yet, in the middle the whole name is replaced,
  -- and at the end the name is complete.
  eq (f.complete ('=SUM(A1)', 2), nil)
  eq (f.complete ('=SUM(A1)', 3), { from = 2, to = 4, prefix = 'S' })
  eq (f.complete ('=SUM(A1)', 5), { from = 2, to = 4, prefix = 'SUM' })
  eq (f.complete ('=1+ave', 7), { from = 4, to = 6, prefix = 'ave' })
  eq (f.complete ('=ROUND(pi', 10), { from = 8, to = 9, prefix = 'pi' })
  eq (f.complete ('=CEILING.M', 11), { from = 2, to = 10, prefix = 'CEILING.M' })
  eq (f.complete ('="a"&SU', 8), { from = 6, to = 7, prefix = 'SU' })
  -- Nothing counts inside text, inside a sheet name, or in a sheet name before "!".
  eq (f.complete ('="SU', 4), nil)
  eq (f.complete ('="a SU"', 6), nil)
  eq (f.complete ("='Sum", 5), nil)
  eq (f.complete ('=Summary!A1', 4), nil)
  eq (f.complete ('=Data!SU', 9), nil)
  eq (f.complete ('=A1:SU', 7), nil)
  eq (f.complete ('=$SU', 5), nil)
  eq (f.complete ('=12AB', 6), nil)
  -- A name no function starts with, a cell, and text that is not a formula.
  eq (f.complete ('=ZZZ', 5), nil)
  eq (f.complete ('=A1', 4), nil)
  eq (f.complete ('SU', 3), nil)
  eq (f.complete ('=', 2), nil)
end)

test ('call_at finds the function and the argument around the caret', function ()
  eq (f.call_at ('=SUM(', 6), { name = 'SUM', arg = 1 })
  eq (f.call_at ('=SUMIF(A1:A9, ">5", ', 21), { name = 'SUMIF', arg = 3 })
  eq (f.call_at ('=if(A1, "a,b', 13), { name = 'IF', arg = 2 })
  eq (f.call_at ('=ROUND(SUM(A1, ', 16), { name = 'SUM', arg = 2 })
  eq (f.call_at ('=ROUND(SUM(A1), ', 17), { name = 'ROUND', arg = 2 })
  eq (f.call_at ('=SUM((1+', 9), { name = 'SUM', arg = 1 })
  eq (f.call_at ('=SUM({1,2,', 11), { name = 'SUM', arg = 1 })
  eq (f.call_at ('=SUM({1,2},', 12), { name = 'SUM', arg = 2 })
  eq (f.call_at ("=SUM('a,(b'!A1, ", 17), { name = 'SUM', arg = 2 })
  -- The caret at the start, the middle and the end of the name PI, then inside its brackets.
  local text = '=ROUND(PI(), 2)'
  eq (f.call_at (text, 8), { name = 'ROUND', arg = 1 })
  eq (f.call_at (text, 9), { name = 'ROUND', arg = 1 })
  eq (f.call_at (text, 10), { name = 'ROUND', arg = 1 })
  eq (f.call_at (text, 11), { name = 'PI', arg = 1 })
  eq (f.call_at (text, 14), { name = 'ROUND', arg = 2 })
  eq (f.call_at ('=1+2', 5), nil)
  eq (f.call_at ('=SUM(1)', 8), nil)
  eq (f.call_at ('=SUM(1)', 3), nil)
  eq (f.call_at ('SUM(', 5), nil)
end)

test ('ref_spans lists every reference with its bytes', function ()
  eq (f.ref_spans ('=A1+SUM(B2:C3, Data!D4)'), {
    { from = 2, to = 3, area = { r1 = 1, c1 = 1, r2 = 1, c2 = 1 } },
    { from = 9, to = 13, area = { r1 = 2, c1 = 2, r2 = 3, c2 = 3 } },
    {
      from = 16,
      to = 22,
      area = { r1 = 4, c1 = 4, r2 = 4, c2 = 4, sheet = 'Data' },
    },
  })
  eq (f.ref_spans ('=SUM($A:$A)'), {
    { from = 6, to = 10, area = { c1 = 1, c2 = 1 } },
  })
  -- Text still being typed, and references inside quotes.
  eq (f.ref_spans ('=SUM(A1, "x'), {
    { from = 6, to = 7, area = { r1 = 1, c1 = 1, r2 = 1, c2 = 1 } },
  })
  eq (#f.ref_spans ('=A1+'), 1)
  eq (#f.ref_spans ('=A1:'), 1)
  eq (#f.ref_spans ('=A1 ; B2'), 2)
  eq (f.ref_spans ('="A1"&B2')[1].from, 7)
  eq (#f.ref_spans ('="A1"&B2'), 1)
  eq (f.ref_spans ('A1+B2'), {})
end)

test ('toggle_anchor cycles the $ signs of a reference', function ()
  eq ({ f.toggle_anchor ('=A1', 4) }, { '=$A$1', 6 })
  eq ({ f.toggle_anchor ('=$A$1', 6) }, { '=A$1', 5 })
  eq ({ f.toggle_anchor ('=A$1', 5) }, { '=$A1', 5 })
  eq ({ f.toggle_anchor ('=$A1', 5) }, { '=A1', 4 })
  -- The caret at the start, the middle and right after a reference.
  eq ({ f.toggle_anchor ('=A1+B2', 2) }, { '=$A$1+B2', 6 })
  eq ({ f.toggle_anchor ('=A1+B2', 3) }, { '=$A$1+B2', 6 })
  eq ({ f.toggle_anchor ('=A1+B2', 4) }, { '=$A$1+B2', 6 })
  eq ({ f.toggle_anchor ('=A1+B2', 7) }, { '=A1+$B$2', 9 })
  -- Both ends of a range change together.
  eq ({ f.toggle_anchor ('=SUM(A1:B2)', 8) }, { '=SUM($A$1:$B$2)', 15 })
  eq ({ f.toggle_anchor ('=SUM(A:A)', 7) }, { '=SUM($A:$A)', 11 })
  eq ({ f.toggle_anchor ('=SUM($3:$3)', 7) }, { '=SUM(3:3)', 9 })
  eq ({ f.toggle_anchor ("='Q1 sales'!B3", 14) }, { "='Q1 sales'!$B$3", 17 })
  eq ({ f.toggle_anchor ('=A1+', 4) }, { '=$A$1+', 6 })
  -- No reference there: nothing changes.
  eq ({ f.toggle_anchor ('=SUM(1)', 5) }, { '=SUM(1)', 5 })
  eq ({ f.toggle_anchor ('="A1"', 3) }, { '="A1"', 3 })
  eq ({ f.toggle_anchor ('A1', 2) }, { 'A1', 2 })
end)

test ('volatile finds formulas to work out after every change', function ()
  for _, text in ipairs ({
    '=RAND()',
    '=A1+NOW()',
    '=TODAY()',
    '=RANDBETWEEN(1, 6)',
    '=SUM(INDIRECT("A1:A3"))',
    '=IF(A1, OFFSET(A1, 1, 1), 0)',
  }) do
    ok (f.volatile (assert (f.parse (text))), text)
  end
  ok (not f.volatile (assert (f.parse ('=SUM(A1:A3)*2'))))
end)

test ('result_format says how a result should show', function ()
  ---@param text string
  ---@return string?
  local function kind (text)
    return f.result_format (assert (f.parse (text)))
  end
  eq (kind ('=DATE(2026, 9, 29)'), 'date')
  eq (kind ('=TODAY()'), 'date')
  eq (kind ('=EDATE(A1, 1)'), 'date')
  eq (kind ('=EOMONTH(A1, 0)'), 'date')
  eq (kind ('=WORKDAY(A1, 5)'), 'date')
  eq (kind ('=DATEVALUE("2026-09-29")'), 'date')
  eq (kind ('=NOW()'), 'datetime')
  eq (kind ('=TIME(9, 0, 0)'), 'time')
  eq (kind ('=TIMEVALUE("9:00")'), 'time')
  eq (kind ('=DATE(2026, 1, 1)+30'), 'date')
  eq (kind ('=1+TODAY()'), 'date')
  eq (kind ('=TODAY()+1+1-1'), 'date')
  eq (kind ('=DATE(2026, 1, 1)+TIME(9, 0, 0)'), 'datetime')
  eq (kind ('=TODAY()-DATE(2026, 1, 1)'), nil)
  eq (kind ('=YEAR(TODAY())'), nil)
  eq (kind ('=SUM(A1)'), nil)
  eq (kind ('=TODAY()*2'), nil)
  eq (f.date_kind (assert (f.parse ('=DATE(2026, 1, 1)'))), 'date')
  eq (f.date_kind (assert (f.parse ('=TIME(1, 0, 0)'))), nil)
  -- A long chain is walked with a loop, not recursion.
  local long = '=TODAY()' .. string.rep ('+1', 5000)
  eq (kind (long), 'date')
end)

---------------------------------------------------------------------------------------------
-- Long formulas and speed
---------------------------------------------------------------------------------------------

test ('long chains of references are read without recursion', function ()
  local parts = {} ---@type string[]
  for i = 1, 3000 do
    parts[i] = 'A' .. i
  end
  local ast = assert (f.parse ('=' .. table.concat (parts, '+')))
  eq (#f.refs (ast), 3000)
  ok (not f.volatile (ast))
  eq (f.evaluate (ast, book ({ A1 = 1, A3000 = 2 })), 3)
end)

test (
  'a few thousand formulas with lookups and arrays work out quickly',
  function ()
    local cells = {} ---@type Cells
    for row = 1, 200 do
      cells['A' .. row] = row
      cells['B' .. row] = 'item ' .. row
    end
    local formulas = {} ---@type Sheet.Node[]
    for row = 1, 3000 do
      local r = row % 200 + 1
      formulas[row] = assert (
        f.parse (
          '=IF(A'
            .. r
            .. '>100, VLOOKUP(A'
            .. r
            .. ', $A$1:$B$200, 2, FALSE), ROUND(A'
            .. r
            .. '*1.1, 2))&COUNTIF($A$1:$A$200, ">"&A'
            .. r
            .. ')'
        )
      )
    end
    local ctx = book (cells)
    local started = os.clock ()
    for row = 1, 3000 do
      f.evaluate (formulas[row], ctx)
    end
    eq (f.evaluate (formulas[150], ctx), 'item 151' .. '49')
    eq (
      f.evaluate (assert (f.parse ('=SUMPRODUCT((A1:A200>100)*A1:A200)')), ctx),
      15050
    )
    ok (os.clock () - started < 10, 'working out took too long')
  end
)
