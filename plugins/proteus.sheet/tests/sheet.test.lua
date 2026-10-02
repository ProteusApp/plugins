local f = require ('sheet_formula') --[[@as Sheet.FormulaModule]]
local m = require ('sheet_model') --[[@as Sheet.ModelModule]]

-- A fixed clock and dice, so TODAY, NOW and RAND give the same answer every run.
local NOW = f.serial (2026, 9, 29, 14, 30, 0)

---@return number
local function clock ()
  return NOW
end

---@return number
local function dice ()
  return 0.25
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

---@param cells? table<string, string>
---@return Sheet.Sheet
local function sheet_of (cells)
  local s = m.new ({ clock = clock, random = dice })
  for addr, text in pairs (cells or {}) do
    local row, col = at (addr)
    s:put (row, col, { text = text, bold = false })
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
  return s:display (row, col)
end

---@param s Sheet.Sheet
---@param addr string
---@return string
local function text (s, addr)
  local row, col = at (addr)
  return s:text (row, col)
end

---Works out one formula in cell Z99, beside the given cells, and returns what it shows.
---@param formula string
---@param cells? table<string, string>
---@return string
local function calc (formula, cells)
  local s = sheet_of (cells)
  s:put (99, 26, { text = formula, bold = false })
  return s:display (99, 26)
end

---@param rect string
---@return Sheet.Rect
local function r (rect)
  local out = m.parse_range (rect)
  assert (out, rect)
  return out --[[@as Sheet.Rect]]
end

---------------------------------------------------------------------------------------------
-- Addresses
---------------------------------------------------------------------------------------------

test ('column letters and numbers', function ()
  eq (f.col_name (1), 'A')
  eq (f.col_name (26), 'Z')
  eq (f.col_name (27), 'AA')
  eq (f.col_name (52), 'AZ')
  eq (f.col_name (53), 'BA')
  eq (f.col_name (702), 'ZZ')
  eq (f.col_name (703), 'AAA')
  eq (f.col_number ('a'), 1)
  eq (f.col_number ('AA'), 27)
  eq (f.col_number ('zz'), 702)
  eq (f.col_number ('A1'), nil)
  for n = 1, 2000 do
    eq (f.col_number (f.col_name (n)), n)
  end
end)

test ('addresses', function ()
  eq ({ m.parse_address ('B12') }, { 12, 2 })
  eq ({ m.parse_address ('$c$3') }, { 3, 3 })
  eq ({ m.parse_address (' AA10 ') }, { 10, 27 })
  eq ({ m.parse_address ('A0') }, {})
  eq ({ m.parse_address ('12') }, {})
  eq ({ m.parse_address ('ABCD1') }, {})
  eq (m.address (12, 2), 'B12')
  eq (m.parse_range ('b2:a1'), { r1 = 1, c1 = 1, r2 = 2, c2 = 2 })
  eq (m.parse_range ('C3'), { r1 = 3, c1 = 3, r2 = 3, c2 = 3 })
  eq (m.parse_range ('C3:'), nil)
  eq (m.range_name ({ r1 = 3, c1 = 4, r2 = 1, c2 = 2 }), 'B1:D3')
  eq (m.range_name ({ r1 = 3, c1 = 4, r2 = 3, c2 = 4 }), 'D3')
end)

---------------------------------------------------------------------------------------------
-- Tokens and the parser
---------------------------------------------------------------------------------------------

test ('the tokenizer names each piece and where it sits', function ()
  local tokens = assert (f.tokenize ('=SUM($A$1:b2, "x""y") >= 1.5e2%', 2))
  local kinds, texts = {}, {} ---@type string[], string[]
  for i, t in ipairs (tokens) do
    kinds[i], texts[i] = t.kind, t.text
  end
  eq (kinds, {
    'name',
    'open',
    'range',
    'comma',
    'string',
    'close',
    'op',
    'number',
    'op',
  })
  eq (texts, { 'SUM', '(', '$A$1:b2', ',', '"x""y"', ')', '>=', '1.5e2', '%' })
  eq (tokens[3].from, 6)
  eq (tokens[3].to, 12)
  eq (tokens[5].value, 'x"y')
  eq (tokens[8].value, 150)
  eq (tokens[3].a, { row = 1, col = 1, row_abs = true, col_abs = true })
  eq (tokens[3].b, { row = 2, col = 2, row_abs = false, col_abs = false })
end)

test ('the tokenizer reads every reference form', function ()
  local tokens =
    assert (f.tokenize ('A1 $A1 A$1 A:C $B:$B 3:5 $2:$2 #ref! LOG10('))
  local kinds = {} ---@type string[]
  for i, t in ipairs (tokens) do
    kinds[i] = t.kind
  end
  eq (kinds, {
    'ref',
    'ref',
    'ref',
    'range',
    'range',
    'range',
    'range',
    'error',
    'name',
    'open',
  })
  -- Without a bracket after it, LOG10 is a cell in column LOG.
  eq (assert (f.tokenize ('LOG10'))[1].kind, 'ref')
  eq (tokens[2].a, { row = 1, col = 1, row_abs = false, col_abs = true })
  eq (tokens[3].a, { row = 1, col = 1, row_abs = true, col_abs = false })
  eq (tokens[4].a, { col = 1, col_abs = false, row_abs = false })
  eq (tokens[6].b, { row = 5, row_abs = false, col_abs = false })
  eq (tokens[8].value, '#REF!')
end)

test ('the tokenizer refuses what it cannot read', function ()
  eq (
    { f.tokenize ('"open') },
    { nil, 'A text in quotes has no closing quote.' }
  )
  ok (f.tokenize ('1 ; 2') == nil)
  ok (f.tokenize ('#WHAT') == nil)
  ok (f.tokenize ('12abc') == nil)
  ok (f.tokenize ('$') == nil)
end)

test ('parse errors show #ERROR!', function ()
  for _, bad in ipairs ({
    '=1+',
    '=(1',
    '=SUM(1',
    '=1 2',
    '=*2',
    '=)',
    '="open',
    '=1;2',
    '=A1:',
  }) do
    local ast = f.parse (bad)
    ok (ast == nil, bad .. ' should not parse')
    eq (calc (bad), '#ERROR!', bad)
  end
  local _, problem = f.parse ('=SUM(1')
  eq (problem, 'A ")" is missing after the arguments of SUM.')
  local deep = '=' .. string.rep ('(', 100) .. '1' .. string.rep (')', 100)
  eq (select (2, f.parse (deep)), 'The formula nests too deeply.')
  eq (calc ('=' .. string.rep ('-', 100) .. '1'), '#ERROR!')
end)

test ('a formula is text that starts with = and has more after it', function ()
  ok (f.is_formula ('=1'))
  ok (not f.is_formula ('='))
  ok (not f.is_formula ('1=1'))
  eq (calc ('='), '=')
end)

---------------------------------------------------------------------------------------------
-- Operators
---------------------------------------------------------------------------------------------

test ('operator precedence, lowest first', function ()
  eq (calc ('=1+2*3'), '7')
  eq (calc ('=(1+2)*3'), '9')
  eq (calc ('=10-2-3'), '5')
  eq (calc ('=12/2/3'), '2')
  eq (calc ('=2^3^2'), '64')
  eq (calc ('=-2^2'), '4')
  eq (calc ('=2^-1'), '0.5')
  eq (calc ('=2*-3'), '-6')
  eq (calc ('=--3'), '3')
  eq (calc ('=+5'), '5')
  eq (calc ('=50%'), '0.5')
  eq (calc ('=-50%'), '-0.5')
  eq (calc ('=200*10%'), '20')
  eq (calc ('=2^3%'), '1.021012126')
  eq (calc ('=1+2&3'), '33')
  eq (calc ('="a"&1+1'), 'a2')
  eq (calc ('=1+2=3'), 'TRUE')
  eq (calc ('=2*3>5'), 'TRUE')
  eq (calc ('="x"&"y"="XY"'), 'TRUE')
  eq (calc ('=1<2=TRUE'), 'TRUE')
  eq (calc ('=1 + 2 * 3 ^ 2'), '19')
end)

test ('comparisons', function ()
  eq (calc ('=1=1'), 'TRUE')
  eq (calc ('=1<>1'), 'FALSE')
  eq (calc ('=1<2'), 'TRUE')
  eq (calc ('=2>1'), 'TRUE')
  eq (calc ('=2<=2'), 'TRUE')
  eq (calc ('=2>=3'), 'FALSE')
  eq (calc ('="abc"="ABC"'), 'TRUE')
  eq (calc ('="a"<"B"'), 'TRUE')
  eq (calc ('=9<"1"'), 'TRUE')
  eq (calc ('="z"<TRUE'), 'TRUE')
  eq (calc ('=FALSE<TRUE'), 'TRUE')
  eq (calc ('=A1=0'), 'TRUE')
  eq (calc ('=A1=""'), 'TRUE')
  eq (calc ('=A1=FALSE'), 'TRUE')
  eq (calc ('=A1=B1'), 'TRUE')
  eq (calc ('=A1<1'), 'TRUE')
end)

test ('float noise does not show', function ()
  eq (calc ('=0.1+0.2'), '0.3')
  eq (calc ('=1/3'), '0.3333333333')
  eq (calc ('=2/3'), '0.6666666667')
  eq (calc ('=1.1*1.1'), '1.21')
  eq (calc ('=10^20'), '1E+20')
  eq (calc ('=1/10^7'), '1E-07')
  eq (calc ('=-0'), '0')
  eq (calc ('=123456789*10'), '1234567890')
  eq (f.format_number (0.1 + 0.2), '0.3')
  eq (f.format_number (1234.5), '1234.5')
  eq (f.format_number (1 / 3, 15), '0.333333333333333')
  eq (f.format_number (0 / 0), '#NUM!')
end)

---------------------------------------------------------------------------------------------
-- Values and types
---------------------------------------------------------------------------------------------

test ('reading typed text as numbers', function ()
  eq (f.parse_number ('12'), 12)
  eq (f.parse_number (' -3.5 '), -3.5)
  eq (f.parse_number ('+.5'), 0.5)
  eq (f.parse_number ('1,200'), 1200)
  eq (f.parse_number ('1,234,567.25'), 1234567.25)
  eq (f.parse_number ('1e3'), 1000)
  eq (f.parse_number ('15%'), 0.15)
  eq (f.parse_number ('7.'), 7)
  eq (f.parse_number ('1,2'), nil)
  eq (f.parse_number ('12,34'), nil)
  eq (f.parse_number ('abc'), nil)
  eq (f.parse_number (''), nil)
  eq (f.parse_number ('%'), nil)
  eq (f.parse_number ('0x10'), nil)
  eq (f.parse_number ('inf'), nil)
  eq (f.parse_number ('1 2'), nil)
  eq (math.type (f.parse_number ('12')), 'float')
end)

test ('cell text becomes a number, text, TRUE or FALSE', function ()
  local s = sheet_of ({
    A1 = '1200',
    A2 = 'Rent',
    A3 = 'true',
    A4 = "'007",
    A5 = '  ',
    A6 = '12%',
  })
  eq (s:value (1, 1), 1200)
  eq (s:value (2, 1), 'Rent')
  eq (s:value (3, 1), true)
  eq (s:value (4, 1), '007')
  eq (s:value (5, 1), '  ')
  eq (s:value (6, 1), 0.12)
  eq (s:value (7, 1), nil)
  eq (s:kind (1, 1), 'number')
  eq (s:kind (2, 1), 'text')
  eq (s:kind (3, 1), 'bool')
  eq (s:kind (7, 1), 'empty')
  eq (shown (s, 'A3'), 'TRUE')
  eq (shown (s, 'A4'), '007')
end)

test ('mixed types follow spreadsheet rules', function ()
  local cells = { A1 = '5', A2 = 'text', A3 = '7', B1 = '=""' }
  -- An empty cell is 0 in arithmetic and "" in text.
  eq (calc ('=C1+1', cells), '1')
  eq (calc ('=C1&"x"', cells), 'x')
  eq (calc ('=C1', cells), '0')
  -- Text that looks like a number counts in arithmetic.
  eq (calc ('="3"+4', cells), '7')
  eq (calc ('="1,000"*2', cells), '2000')
  eq (calc ('="12%"*100', cells), '12')
  eq (calc ('=TRUE+1', cells), '2')
  eq (calc ('="a"+1', cells), '#VALUE!')
  eq (calc ('=A2*2', cells), '#VALUE!')
  eq (calc ('=B1+1', cells), '#VALUE!')
  -- SUM and AVERAGE skip text in ranges, but not text typed as an argument.
  eq (calc ('=SUM(A1:A3)', cells), '12')
  eq (calc ('=AVERAGE(A1:A3)', cells), '6')
  eq (calc ('=SUM(A2)', cells), '0')
  eq (calc ('=SUM("4", 1)', cells), '5')
  eq (calc ('=SUM("four")', cells), '#VALUE!')
  eq (calc ('=SUM(TRUE, 1)', cells), '2')
  eq (calc ('=A1&A3', cells), '57')
  eq (calc ('=1&TRUE', cells), '1TRUE')
end)

---------------------------------------------------------------------------------------------
-- References
---------------------------------------------------------------------------------------------

test ('references in every form', function ()
  local cells = {
    A1 = '1',
    A2 = '2',
    A3 = '3',
    B1 = '10',
    B2 = '20',
    C5 = '100',
  }
  eq (calc ('=a1+$A$2+A$3+$B1', cells), '16')
  eq (calc ('=SUM(A1:B2)', cells), '33')
  eq (calc ('=SUM(B2:A1)', cells), '33')
  eq (calc ('=SUM(a:a)', cells), '6')
  eq (calc ('=SUM(A:B)', cells), '36')
  eq (calc ('=SUM($A:$A)', cells), '6')
  eq (calc ('=SUM(1:1)', cells), '11')
  eq (calc ('=SUM(1:2)', cells), '33')
  eq (calc ('=SUM($5:$5)', cells), '100')
  eq (calc ('=A1:A1*2', cells), '2')
  -- A block as the result shows its top left value, since nothing spills.
  eq (calc ('=A1:A3', cells), '1')
  eq (calc ('=A1:A3+1', cells), '2')
  eq (calc ('=ZZ9000', cells), '0')
end)

test ('refs() lists every block a formula reads', function ()
  local ast = assert (f.parse ('=SUM(A1:B2, D:D, 3:4) + $C$9'))
  eq (f.refs (ast), {
    { r1 = 1, c1 = 1, r2 = 2, c2 = 2 },
    { c1 = 4, c2 = 4 },
    { r1 = 3, r2 = 4 },
    { r1 = 9, c1 = 3, r2 = 9, c2 = 3 },
  })
end)

---------------------------------------------------------------------------------------------
-- Errors
---------------------------------------------------------------------------------------------

test ('every error by name', function ()
  eq (calc ('=1/0'), '#DIV/0!')
  eq (calc ('=MOD(1, 0)'), '#DIV/0!')
  eq (calc ('=0^-1'), '#DIV/0!')
  eq (calc ('="a"*2'), '#VALUE!')
  eq (calc ('=#REF!'), '#REF!')
  eq (calc ('=#ref!+1'), '#REF!')
  eq (calc ('=NOPE(1)'), '#NAME?')
  eq (calc ('=nothing'), '#NAME?')
  eq (calc ('=VLOOKUP("x", A1:B2, 2)'), '#N/A')
  eq (calc ('=SQRT(-1)'), '#NUM!')
  eq (calc ('=(-8)^(1/3)'), '#NUM!')
  eq (calc ('=10^400'), '#NUM!')
  eq (calc ('=1+'), '#ERROR!')
  -- A wrong count of arguments fails as it is typed, as a syntax error does.
  eq (calc ('=SUM()'), '#ERROR!')
  eq (calc ('=ABS(1, 2)'), '#ERROR!')
  eq (calc ('=#N/A'), '#N/A')
  eq (calc ('=#NULL!'), '#NULL!')
  local s = sheet_of ({ A1 = '=A1' })
  eq (shown (s, 'A1'), '#CYCLE!')
  ok (f.is_error (s:value (1, 1)))
  ok (not f.is_error ('#REF!'))
  eq (s:kind (1, 1), 'error')
end)

test ('an error in an argument passes through', function ()
  local cells = { A1 = '=1/0', A2 = '5', A3 = '=NOPE()' }
  eq (calc ('=A1+1', cells), '#DIV/0!')
  eq (calc ('=A1&"x"', cells), '#DIV/0!')
  eq (calc ('=-A1', cells), '#DIV/0!')
  eq (calc ('=A1%', cells), '#DIV/0!')
  eq (calc ('=A1=1', cells), '#DIV/0!')
  eq (calc ('=SUM(A1:A2)', cells), '#DIV/0!')
  eq (calc ('=AVERAGE(A2, A1)', cells), '#DIV/0!')
  eq (calc ('=MAX(A1:A3)', cells), '#DIV/0!')
  eq (calc ('=ROUND(A3, 1)', cells), '#NAME?')
  eq (calc ('=IF(A1, 1, 2)', cells), '#DIV/0!')
  eq (calc ('=UPPER(A3)', cells), '#NAME?')
  eq (calc ('=CONCAT(A2:A3)', cells), '#NAME?')
  eq (calc ('=AND(A1:A2)', cells), '#DIV/0!')
  eq (calc ('=SUMIF(A2:A2, 5, A1:A1)', cells), '#DIV/0!')
  eq (calc ('=A3+A1', cells), '#NAME?')
  -- The first error from the left wins.
  eq (calc ('=A1+A3', cells), '#DIV/0!')
  -- IFERROR catches it, and COUNT and COUNTA skip or count it.
  eq (calc ('=IFERROR(A1, "none")', cells), 'none')
  eq (calc ('=IFERROR(A2, "none")', cells), '5')
  eq (calc ('=IFERROR(1/0, A1)', cells), '#DIV/0!')
  eq (calc ('=COUNT(A1:A3, 1/0)', cells), '1')
  eq (calc ('=COUNTA(A1:A3, 1/0)', cells), '4')
  -- IF only works out the branch it takes.
  eq (calc ('=IF(TRUE, 1, A1)', cells), '1')
end)

---------------------------------------------------------------------------------------------
-- Cycles
---------------------------------------------------------------------------------------------

test ('cycles show #CYCLE!, and cells that read them do too', function ()
  local s = sheet_of ({
    A1 = '=B1+1',
    B1 = '=C1+1',
    C1 = '=A1+1',
    D1 = '=A1*2',
    E1 = '=IFERROR(A1, 0)',
    F1 = '=SUM(F2:F9)',
    F5 = '=F1',
    G1 = '=SUM(G:G)',
    H1 = '5',
    H2 = '=H1*2',
  })
  eq (shown (s, 'A1'), '#CYCLE!')
  eq (shown (s, 'B1'), '#CYCLE!')
  eq (shown (s, 'C1'), '#CYCLE!')
  eq (shown (s, 'D1'), '#CYCLE!')
  eq (shown (s, 'E1'), '0')
  eq (shown (s, 'F1'), '#CYCLE!')
  eq (shown (s, 'F5'), '#CYCLE!')
  eq (shown (s, 'G1'), '#CYCLE!')
  eq (shown (s, 'H2'), '10')
  -- Breaking the loop brings the values back.
  set (s, 'C1', '1')
  eq (shown (s, 'B1'), '2')
  eq (shown (s, 'A1'), '3')
  eq (shown (s, 'D1'), '6')
end)

test (
  'a long chain of formulas works out in order without recursion',
  function ()
    local s = m.new ({ rows = 3000 })
    s:put (1, 1, { text = '1', bold = false })
    for row = 2, 3000 do
      s:put (row, 1, { text = '=A' .. (row - 1) .. '+1', bold = false })
    end
    s:put (1, 2, { text = '=SUM(A:A)', bold = false })
    eq (s:display (3000, 1), '3000')
    eq (s:display (1, 2), '4501500')
    s:put (1, 1, { text = '10', bold = false })
    eq (s:display (3000, 1), '3009')
  end
)

test ('recalculation after a change reaches every dependent cell', function ()
  local s = sheet_of ({
    A1 = '2',
    A2 = '=A1*10',
    A3 = '=A2+A1',
    B1 = '=SUM(A1:A3)',
  })
  eq (shown (s, 'B1'), '44')
  set (s, 'A1', '3')
  eq (shown (s, 'A2'), '30')
  eq (shown (s, 'A3'), '33')
  eq (shown (s, 'B1'), '66')
  set (s, 'A1', '')
  eq (shown (s, 'B1'), '0')
end)

---------------------------------------------------------------------------------------------
-- Functions
---------------------------------------------------------------------------------------------

local NUMS = { A1 = '4', A2 = '8', A3 = 'x', A4 = '15', A5 = 'TRUE' }

test ('SUM, AVERAGE, MIN and MAX', function ()
  eq (calc ('=SUM(A1:A5)', NUMS), '27')
  eq (calc ('=SUM(A1, A2, 3)', NUMS), '15')
  eq (calc ('=SUM(A1:A2, A4)', NUMS), '27')
  eq (calc ('=sum(B1:B9)', NUMS), '0')
  eq (calc ('=AVERAGE(A1:A5)', NUMS), '9')
  eq (calc ('=AVERAGE(B1:B9)', NUMS), '#DIV/0!')
  eq (calc ('=MIN(A1:A5)', NUMS), '4')
  eq (calc ('=MIN(A1:A5, -2)', NUMS), '-2')
  eq (calc ('=MAX(A1:A5)', NUMS), '15')
  eq (calc ('=MAX(B1:B9)', NUMS), '0')
end)

test ('COUNT, COUNTA and COUNTBLANK', function ()
  local cells = { A1 = '4', A2 = 'x', A4 = 'TRUE', A5 = '=""', A6 = '=1/0' }
  eq (calc ('=COUNT(A1:A6)', cells), '1')
  eq (calc ('=COUNT(1, "2", "x", TRUE)', cells), '3')
  eq (calc ('=COUNTA(A1:A6)', cells), '5')
  eq (calc ('=COUNTA(1, "")', cells), '2')
  eq (calc ('=COUNTBLANK(A1:A6)', cells), '2')
  eq (calc ('=COUNTBLANK(A1:A10)', cells), '6')
  eq (calc ('=COUNTBLANK(1)', cells), '#VALUE!')
end)

test ('IF and IFERROR', function ()
  eq (calc ('=IF(1>2, "yes", "no")'), 'no')
  eq (calc ('=IF(1<2, "yes", "no")'), 'yes')
  eq (calc ('=IF(1>2, "yes")'), 'FALSE')
  eq (calc ('=IF(A1, 1, 2)'), '2')
  eq (calc ('=IF("true", 1, 2)'), '1')
  eq (calc ('=IF("maybe", 1, 2)'), '#VALUE!')
  eq (calc ('=IF(TRUE, , 2)'), '0')
  eq (calc ('=IF(3, "n", "z")'), 'n')
  eq (calc ('=IFERROR(1/0, "oops")'), 'oops')
  eq (calc ('=IFERROR(4, "oops")'), '4')
  eq (calc ('=IFERROR(NOPE(), 7)'), '7')
end)

test ('AND, OR, NOT, TRUE and FALSE', function ()
  local cells = { A1 = 'TRUE', A2 = '1', A3 = 'text' }
  eq (calc ('=AND(TRUE, 1)'), 'TRUE')
  eq (calc ('=AND(TRUE, 0)'), 'FALSE')
  eq (calc ('=AND(A1:A3)', cells), 'TRUE')
  eq (calc ('=AND(A3)', cells), '#VALUE!')
  eq (calc ('=AND("yes")'), '#VALUE!')
  eq (calc ('=OR(FALSE, 0)'), 'FALSE')
  eq (calc ('=OR(FALSE, 2)'), 'TRUE')
  eq (calc ('=OR(1>2, "TRUE")'), 'TRUE')
  eq (calc ('=NOT(TRUE)'), 'FALSE')
  eq (calc ('=NOT(0)'), 'TRUE')
  eq (calc ('=TRUE()'), 'TRUE')
  eq (calc ('=FALSE()'), 'FALSE')
  eq (calc ('=true'), 'TRUE')
end)

test ('ROUND, ROUNDUP, ROUNDDOWN and INT', function ()
  eq (calc ('=ROUND(2.5, 0)'), '3')
  eq (calc ('=ROUND(-2.5, 0)'), '-3')
  eq (calc ('=ROUND(2.675, 2)'), '2.68')
  eq (calc ('=ROUND(1234.5678, 2)'), '1234.57')
  eq (calc ('=ROUND(1234.5678, -2)'), '1200')
  eq (calc ('=ROUND(1234.5678)'), '1235')
  eq (calc ('=ROUND(0.1+0.2, 20)'), '0.3')
  eq (calc ('=ROUNDUP(3.2, 0)'), '4')
  eq (calc ('=ROUNDUP(-3.2, 0)'), '-4')
  eq (calc ('=ROUNDUP(0.1+0.2, 1)'), '0.3')
  eq (calc ('=ROUNDUP(1234, -2)'), '1300')
  eq (calc ('=ROUNDDOWN(3.7, 0)'), '3')
  eq (calc ('=ROUNDDOWN(-3.7, 0)'), '-3')
  eq (calc ('=ROUNDDOWN(3.14159, 3)'), '3.141')
  eq (calc ('=INT(3.7)'), '3')
  eq (calc ('=INT(-3.2)'), '-4')
  eq (calc ('=INT(1E18)*10'), '1E+19')
end)

test ('ABS, SQRT, POWER, MOD and PI', function ()
  eq (calc ('=ABS(-4.5)'), '4.5')
  eq (calc ('=SQRT(16)'), '4')
  eq (calc ('=SQRT(-4)'), '#NUM!')
  eq (calc ('=POWER(2, 10)'), '1024')
  eq (calc ('=POWER(0, -1)'), '#DIV/0!')
  eq (calc ('=MOD(10, 3)'), '1')
  eq (calc ('=MOD(-1, 3)'), '2')
  eq (calc ('=MOD(1, -3)'), '-2')
  eq (calc ('=MOD(5.5, 1)'), '0.5')
  eq (calc ('=MOD(1, 0)'), '#DIV/0!')
  eq (calc ('=PI()'), '3.141592654')
  eq (calc ('=RAND()'), '0.25')
end)

test ('CONCAT, CONCATENATE, LEN, UPPER, LOWER and TRIM', function ()
  local cells = { A1 = 'a', A2 = '2', B1 = 'b' }
  eq (calc ('=CONCAT("x", 1, TRUE)'), 'x1TRUE')
  eq (calc ('=CONCAT(A1:B2)', cells), 'ab2')
  eq (calc ('=CONCATENATE(A1, "-", B1)', cells), 'a-b')
  eq (calc ('=LEN("hello")'), '5')
  eq (calc ('=LEN("héllo")'), '5')
  eq (calc ('=LEN(A9)'), '0')
  eq (calc ('=LEN(12.5)'), '4')
  eq (calc ('=UPPER("MiXeD")'), 'MIXED')
  eq (calc ('=LOWER("MiXeD")'), 'mixed')
  eq (calc ('=TRIM("  a   b  c ")'), 'a b c')
end)

test ('LEFT, RIGHT, MID, FIND and SUBSTITUTE', function ()
  eq (calc ('=LEFT("spreadsheet", 6)'), 'spread')
  eq (calc ('=LEFT("abc")'), 'a')
  eq (calc ('=LEFT("abc", 10)'), 'abc')
  eq (calc ('=LEFT("abc", 0)'), '')
  eq (calc ('=LEFT("abc", -1)'), '#VALUE!')
  eq (calc ('=LEFT("héllo", 2)'), 'hé')
  eq (calc ('=RIGHT("spreadsheet", 5)'), 'sheet')
  eq (calc ('=RIGHT("abc")'), 'c')
  eq (calc ('=RIGHT("abc", 9)'), 'abc')
  eq (calc ('=MID("spreadsheet", 3, 4)'), 'read')
  eq (calc ('=MID("abc", 5, 2)'), '')
  eq (calc ('=MID("abc", 0, 2)'), '#VALUE!')
  eq (calc ('=FIND("s", "spreadsheets")'), '1')
  eq (calc ('=FIND("s", "spreadsheets", 2)'), '7')
  eq (calc ('=FIND("S", "spreadsheets")'), '#VALUE!')
  eq (calc ('=FIND("l", "héllo")'), '3')
  eq (calc ('=FIND("", "abc")'), '1')
  eq (calc ('=FIND("a", "abc", 9)'), '#VALUE!')
  eq (calc ('=SUBSTITUTE("a-b-c", "-", "+")'), 'a+b+c')
  eq (calc ('=SUBSTITUTE("a-b-c", "-", "+", 2)'), 'a-b+c')
  eq (calc ('=SUBSTITUTE("a-b-c", "-", "+", 5)'), 'a-b-c')
  eq (calc ('=SUBSTITUTE("abc", "", "x")'), 'abc')
  eq (calc ('=SUBSTITUTE("a.b", ".", "%")'), 'a%b')
  eq (calc ('=SUBSTITUTE("abc", "b", "x", 0)'), '#VALUE!')
end)

test ('TEXT formats numbers and dates', function ()
  eq (calc ('=TEXT(1234.567, "0")'), '1235')
  eq (calc ('=TEXT(1234.567, "0.00")'), '1234.57')
  eq (calc ('=TEXT(1234.567, "#,##0")'), '1,235')
  eq (calc ('=TEXT(1234567.891, "#,##0.00")'), '1,234,567.89')
  eq (calc ('=TEXT(0.256, "0%")'), '26%')
  eq (calc ('=TEXT(0.256, "0.0%")'), '25.6%')
  eq (calc ('=TEXT(-1234.5, "#,##0.00")'), '-1,234.50')
  eq (calc ('=TEXT(5, "000")'), '005')
  eq (calc ('=TEXT(0.5, "#.00")'), '.50')
  eq (calc ('=TEXT(3.1, "0.##")'), '3.1')
  eq (calc ('=TEXT(42, "$#,##0")'), '$42')
  eq (calc ('=TEXT(-42, "$0")'), '-$42')
  eq (calc ('=TEXT(7, "0 ""items""")'), '7 items')
  eq (calc ('=TEXT("abc", "0.00")'), 'abc')
  eq (calc ('=TEXT("12", "0.00")'), '12.00')
  eq (calc ('=TEXT(TRUE, "0")'), 'TRUE')
  eq (calc ('=TEXT(A1, "0.0")'), '0.0')
  eq (calc ('=TEXT(-0.001, "0.00")'), '0.00')
  local day = f.serial (2026, 3, 7, 9, 5, 30)
  eq (f.format (day, 'yyyy-mm-dd'), '2026-03-07')
  eq (f.format (day, 'dd/mm/yy'), '07/03/26')
  eq (f.format (day, 'd mmm yyyy'), '7 Mar 2026')
  eq (f.format (day, 'dddd, mmmm d'), 'Saturday, March 7')
  eq (f.format (day, 'hh:mm:ss'), '09:05:30')
  eq (f.format (day, 'h:mm'), '9:05')
  eq (f.format (day, 'mm:ss'), '05:30')
  eq (f.format (day, 'yyyy-mm-dd "at" hh:mm'), '2026-03-07 at 09:05')
end)

test ('VALUE', function ()
  eq (calc ('=VALUE("12.5")'), '12.5')
  eq (calc ('=VALUE("1,000")+1'), '1001')
  eq (calc ('=VALUE("50%")'), '0.5')
  eq (calc ('=VALUE(7)'), '7')
  eq (calc ('=VALUE("seven")'), '#VALUE!')
  eq (calc ('=VALUE(TRUE)'), '#VALUE!')
end)

local SALES = {
  A1 = 'apple',
  B1 = '10',
  A2 = 'Banana',
  B2 = '20',
  A3 = 'apricot',
  B3 = '30',
  A4 = 'apple',
  B4 = 'n/a',
  A5 = '',
  B5 = '50',
  A6 = '7',
  B6 = '60',
  A7 = '12',
  B7 = '70',
}

test ('SUMIF, COUNTIF and AVERAGEIF', function ()
  eq (calc ('=SUMIF(A1:A7, "apple", B1:B7)', SALES), '10')
  eq (calc ('=COUNTIF(A1:A7, "apple")', SALES), '2')
  eq (calc ('=COUNTIF(A1:A7, "APPLE")', SALES), '2')
  eq (calc ('=COUNTIF(A1:A7, "ap*")', SALES), '3')
  eq (calc ('=COUNTIF(A1:A7, "b?nana")', SALES), '1')
  eq (calc ('=COUNTIF(A1:A7, "<>apple")', SALES), '5')
  eq (calc ('=COUNTIF(A1:A7, "")', SALES), '1')
  eq (calc ('=COUNTIF(A1:A7, "<>")', SALES), '6')
  eq (calc ('=COUNTIF(A1:A7, ">8")', SALES), '1')
  eq (calc ('=COUNTIF(A1:A7, "<=7")', SALES), '1')
  eq (calc ('=COUNTIF(A1:A7, 7)', SALES), '1')
  eq (calc ('=COUNTIF(A1:A7, "=12")', SALES), '1')
  eq (calc ('=COUNTIF(A1:A7, ">b")', SALES), '1')
  eq (calc ('=COUNTIF(B1:B7, ">=30")', SALES), '4')
  eq (calc ('=SUMIF(B1:B7, ">25")', SALES), '210')
  eq (calc ('=SUMIF(A1:A7, "a*", B1:B7)', SALES), '40')
  eq (calc ('=AVERAGEIF(A1:A7, "a*", B1:B7)', SALES), '20')
  eq (calc ('=AVERAGEIF(A1:A7, "kiwi", B1:B7)', SALES), '#DIV/0!')
  eq (calc ('=AVERAGEIF(B1:B7, "<40")', SALES), '20')
  eq (calc ('=COUNTIF(A1:A7, "~*")', { A1 = '*', A2 = 'x' }), '1')
  eq (calc ('=COUNTIF(A1:A2, TRUE)', { A1 = 'TRUE', A2 = 'x' }), '1')
  eq (calc ('=COUNTIF(A1:A2, "true")', { A1 = 'TRUE', A2 = 'x' }), '1')
  eq (calc ('=SUMIF(5, 5)'), '#VALUE!')
end)

test ('VLOOKUP, INDEX and MATCH', function ()
  -- SALES is not sorted, so these ask for an exact match. With no fourth argument, VLOOKUP
  -- looks for the nearest match in sorted data, as spreadsheets do.
  eq (calc ('=VLOOKUP("banana", A1:B7, 2, FALSE)', SALES), '20')
  eq (calc ('=VLOOKUP("apple", A1:B7, 2, FALSE)', SALES), '10')
  eq (calc ('=VLOOKUP(7, A1:B7, 2, FALSE)', SALES), '60')
  eq (calc ('=VLOOKUP("apr*", A1:B7, 2, FALSE)', SALES), '30')
  eq (calc ('=VLOOKUP("kiwi", A1:B7, 2, FALSE)', SALES), '#N/A')
  eq (calc ('=VLOOKUP("apple", A1:B7, 3)', SALES), '#REF!')
  eq (calc ('=VLOOKUP("apple", A1:B7, 0)', SALES), '#VALUE!')
  eq (calc ('=VLOOKUP("apple", "x", 1)', SALES), '#VALUE!')
  eq (calc ('=VLOOKUP("Banana", A:B, 2, FALSE)', SALES), '20')
  eq (calc ('=MATCH("apricot", A1:A7, 0)', SALES), '3')
  eq (calc ('=MATCH(12, A1:A7, 0)', SALES), '7')
  eq (calc ('=MATCH(20, A2:B2, 0)', SALES), '2')
  eq (calc ('=MATCH("kiwi", A1:A7, 0)', SALES), '#N/A')
  eq (calc ('=MATCH("apple", A1:B7, 0)', SALES), '#N/A')
  eq (calc ('=INDEX(A1:B7, 2, 2)', SALES), '20')
  eq (calc ('=INDEX(B1:B7, 3)', SALES), '30')
  eq (calc ('=INDEX(A2:B2, 2)', SALES), '20')
  eq (calc ('=INDEX(A1:B7, 8, 1)', SALES), '#REF!')
  -- One number on a block of rows and columns gives the whole row, shown by its first cell.
  eq (calc ('=INDEX(A1:B7, 2)', SALES), 'Banana')
  eq (calc ('=INDEX(A1:A7, MATCH("apricot", A1:A7, 0))', SALES), 'apricot')
  eq (calc ('=INDEX(B1:B7, MATCH(MAX(B1:B7), B1:B7, 0))', SALES), '70')
  eq (calc ('=INDEX(A1:A9, 9)', SALES), '0')
end)

test ('TODAY and NOW read the clock they are given', function ()
  eq (calc ('=TODAY()'), '2026-09-29')
  eq (calc ('=NOW()'), '2026-09-29 14:30')
  eq (calc ('=TODAY()+7'), '2026-10-06')
  eq (calc ('=TODAY()-1'), '2026-09-28')
  eq (calc ('=TODAY()-TODAY()'), '0')
  eq (calc ('=TEXT(TODAY(), "dd mmm yyyy")'), '29 Sep 2026')
  eq (calc ('=TEXT(NOW(), "hh:mm")'), '14:30')
  eq (calc ('=TODAY()*1'), '46294')
  eq ({ f.date_parts (NOW) }, { 2026, 9, 29, 14, 30, 0 })
  eq ({ f.date_parts (f.serial (1970, 1, 1)) }, { 1970, 1, 1, 0, 0, 0 })
  eq (f.serial (1970, 1, 1), 25569)
  eq (f.serial (2000, 2, 29), 36585)
  eq ({ f.date_parts (36585) }, { 2000, 2, 29, 0, 0, 0 })
  eq (
    f.format_date (f.serial (1999, 12, 31, 23, 59, 59), true),
    '1999-12-31 23:59'
  )
end)

-- Every function past these first 45 has its tests in sheet_formula.test.lua, which checks
-- that the two files between them cover the whole list.
test (
  'function names are not case sensitive, and the first functions are here',
  function ()
    eq (calc ('=Sum(1, 2)'), '3')
    eq (calc ('=concatenate("a", "b")'), 'ab')
    local tested = {
      'ABS',
      'AND',
      'AVERAGE',
      'AVERAGEIF',
      'CONCAT',
      'CONCATENATE',
      'COUNT',
      'COUNTA',
      'COUNTBLANK',
      'COUNTIF',
      'FALSE',
      'FIND',
      'IF',
      'IFERROR',
      'INDEX',
      'INT',
      'LEFT',
      'LEN',
      'LOWER',
      'MATCH',
      'MAX',
      'MID',
      'MIN',
      'MOD',
      'NOT',
      'NOW',
      'OR',
      'PI',
      'POWER',
      'RAND',
      'RIGHT',
      'ROUND',
      'ROUNDDOWN',
      'ROUNDUP',
      'SQRT',
      'SUBSTITUTE',
      'SUM',
      'SUMIF',
      'TEXT',
      'TODAY',
      'TRIM',
      'TRUE',
      'UPPER',
      'VALUE',
      'VLOOKUP',
    }
    local known = {} ---@type table<string, boolean>
    for _, name in ipairs (f.functions) do
      known[name] = true
    end
    for _, name in ipairs (tested) do
      ok (known[name], name .. ' is missing')
    end
  end
)

---------------------------------------------------------------------------------------------
-- Moving references
---------------------------------------------------------------------------------------------

test ('shift moves relative references and leaves $ alone', function ()
  eq (f.shift ('=A1+B2', 1, 0), '=A2+B3')
  eq (f.shift ('=A1+B2', 0, 2), '=C1+D2')
  eq (f.shift ('=$A$1+A$1+$A1+A1', 2, 2), '=$A$1+C$1+$A3+C3')
  eq (f.shift ('=SUM(A1:B3)*$C$1', 3, 1), '=SUM(B4:C6)*$C$1')
  eq (f.shift ('=SUM($A1:A$2)', 1, 1), '=SUM($A2:B$2)')
  eq (f.shift ('=SUM(A:A)', 5, 1), '=SUM(B:B)')
  eq (f.shift ('=SUM($A:A)', 5, 1), '=SUM($A:B)')
  eq (f.shift ('=SUM(2:2)', 3, 4), '=SUM(5:5)')
  eq (f.shift ('=SUM($2:2)', 3, 4), '=SUM($2:5)')
  eq (f.shift ('=A1', -1, 0), '=#REF!')
  eq (f.shift ('=B2+SUM(A1:B2)', 0, -1), '=A2+SUM(#REF!)')
  eq (f.shift ('=$A$1', -5, -5), '=$A$1')
  eq (f.shift ('="A1"&A1', 1, 0), '="A1"&A2')
  eq (f.shift ('=sum( a1 , b1 )', 1, 0), '=sum( A2 , B2 )')
  eq (f.shift ('=A1', 0, 0), '=A1')
  eq (f.shift ('A1', 1, 1), 'A1')
  eq (f.shift ('="open', 1, 1), '="open')
  eq (f.shift ('=Z1', 0, 1), '=AA1')
end)

test ('adjust fixes references after rows are inserted', function ()
  eq (f.adjust ('=A1+A5', 'row', 3, 2), '=A1+A7')
  eq (f.adjust ('=$A$5', 'row', 5, 1), '=$A$6')
  eq (f.adjust ('=SUM(A2:A4)', 'row', 2, 1), '=SUM(A3:A5)')
  eq (f.adjust ('=SUM(A2:A4)', 'row', 3, 2), '=SUM(A2:A6)')
  eq (f.adjust ('=SUM(A2:A4)', 'row', 5, 1), '=SUM(A2:A4)')
  eq (f.adjust ('=SUM(A:A)', 'row', 1, 3), '=SUM(A:A)')
  eq (f.adjust ('=SUM(2:4)', 'row', 3, 1), '=SUM(2:5)')
  eq (f.adjust ('=SUM(A1:A3)&"A3"', 'row', 1, 1), '=SUM(A2:A4)&"A3"')
end)

test ('adjust fixes references after rows are deleted', function ()
  eq (f.adjust ('=A1+A5', 'row', 3, -1), '=A1+A4')
  eq (f.adjust ('=A3', 'row', 3, -1), '=#REF!')
  eq (f.adjust ('=A3+A4', 'row', 2, -3), '=#REF!+#REF!')
  eq (f.adjust ('=$A$9', 'row', 1, -2), '=$A$7')
  eq (f.adjust ('=SUM(A2:A10)', 'row', 4, -2), '=SUM(A2:A8)')
  eq (f.adjust ('=SUM(A2:A10)', 'row', 1, -3), '=SUM(A1:A7)')
  eq (f.adjust ('=SUM(A2:A10)', 'row', 9, -4), '=SUM(A2:A8)')
  eq (f.adjust ('=SUM(A2:A4)', 'row', 2, -3), '=SUM(#REF!)')
  eq (f.adjust ('=SUM(A2:A4)', 'row', 1, -5), '=SUM(#REF!)')
  eq (f.adjust ('=SUM(A:A)', 'row', 1, -5), '=SUM(A:A)')
  eq (f.adjust ('=SUM(3:6)', 'row', 4, -1), '=SUM(3:5)')
end)

test ('adjust fixes references after columns change', function ()
  eq (f.adjust ('=A1+C1', 'col', 2, 1), '=A1+D1')
  eq (f.adjust ('=$C$1', 'col', 1, 2), '=$E$1')
  eq (f.adjust ('=SUM(A1:C1)', 'col', 2, 1), '=SUM(A1:D1)')
  eq (f.adjust ('=SUM(B:D)', 'col', 1, 1), '=SUM(C:E)')
  eq (f.adjust ('=SUM(1:1)', 'col', 1, 1), '=SUM(1:1)')
  eq (f.adjust ('=B1', 'col', 2, -1), '=#REF!')
  eq (f.adjust ('=C1+Z1', 'col', 2, -1), '=B1+Y1')
  eq (f.adjust ('=SUM(A1:D1)', 'col', 2, -2), '=SUM(A1:B1)')
  eq (f.adjust ('=SUM(B:C)', 'col', 2, -2), '=SUM(#REF!)')
  eq (f.adjust ('plain text', 'col', 1, 1), 'plain text')
end)

test ('normalize tidies a formula as it is entered', function ()
  eq (f.normalize ('=sum(a1:b2'), '=SUM(A1:B2)')
  eq (f.normalize ('=if(a1>0,"yes","no"'), '=IF(A1>0,"yes","no")')
  eq (f.normalize ('=concat("abc'), '=CONCAT("abc")')
  eq (f.normalize ('=round(pi(), 2)'), '=ROUND(PI(), 2)')
  eq (f.normalize ('="a1"&a1'), '="a1"&A1')
  eq (f.normalize ('=#n/a'), '=#N/A')
  eq (f.normalize ('=1;2'), '=1;2')
  eq (f.normalize ('hello'), 'hello')
end)

test ('date_kind finds formulas that show a date', function ()
  eq (f.date_kind (assert (f.parse ('=TODAY()'))), 'date')
  eq (f.date_kind (assert (f.parse ('=NOW()+1'))), 'datetime')
  eq (f.date_kind (assert (f.parse ('=7+TODAY()'))), 'date')
  eq (f.date_kind (assert (f.parse ('=TODAY()-A1'))), 'date')
  eq (f.date_kind (assert (f.parse ('=TODAY()-TODAY()'))), nil)
  eq (f.date_kind (assert (f.parse ('=A1'))), nil)
end)

---------------------------------------------------------------------------------------------
-- The sheet model
---------------------------------------------------------------------------------------------

test ('a new sheet has 100 rows and 26 columns', function ()
  local s = m.new ()
  eq ({ s.rows, s.cols }, { 100, 26 })
  eq (s:text (1, 1), '')
  eq (s:value (1, 1), nil)
  eq (s:display (1, 1), '')
  eq ({ s:used () }, { 0, 0 })
  eq (s:width (1), 100)
  s:set_width (1, 140.4)
  eq (s:width (1), 140)
  s:set_width (2, 5)
  eq (s:width (2), 24)
  s:set_width (1, 100)
  eq (s.widths, { [2] = 24 })
end)

test ('setting a cell past the edge grows the sheet', function ()
  local s = m.new ()
  s:set (150, 30, 'far')
  eq ({ s.rows, s.cols }, { 150, 30 })
  eq ({ s:used () }, { 150, 30 })
  s:grow (160, 5)
  eq ({ s.rows, s.cols }, { 160, 30 })
end)

test ('undo and redo, one step per action', function ()
  local s = sheet_of ()
  set (s, 'A1', '1')
  set (s, 'A2', '=A1*2')
  eq (shown (s, 'A2'), '2')
  set (s, 'A1', '5')
  eq (shown (s, 'A2'), '10')
  local done, area = s:undo ()
  ok (done)
  eq (area, { r1 = 1, c1 = 1, r2 = 1, c2 = 1 })
  eq (shown (s, 'A2'), '2')
  s:undo ()
  eq (text (s, 'A2'), '')
  ok (s:can_redo ())
  s:redo ()
  eq (shown (s, 'A2'), '2')
  s:redo ()
  eq (shown (s, 'A2'), '10')
  ok (not s:can_redo ())
  eq ({ s:redo () }, { false })
  -- A new change clears the redo list.
  s:undo ()
  set (s, 'B1', 'x')
  ok (not s:can_redo ())
  -- Setting the same text records nothing.
  local count = #s.book.done
  set (s, 'B1', 'x')
  eq (#s.book.done, count)
end)

test ('a batch is one undo step, and batches nest', function ()
  local s = sheet_of ()
  s:begin ()
  set (s, 'A1', '1')
  s:begin ()
  set (s, 'A2', '2')
  set (s, 'A1', '3')
  s:finish ()
  s:finish ()
  eq (#s.book.done, 1)
  s:undo ()
  eq ({ text (s, 'A1'), text (s, 'A2') }, { '', '' })
  s:redo ()
  eq ({ text (s, 'A1'), text (s, 'A2') }, { '3', '2' })
  s:set_many ({ { 5, 1, 'a' }, { 5, 2, 'b' } })
  eq (#s.book.done, 2)
  s:begin ()
  s:finish ()
  eq (#s.book.done, 2)
end)

test ('bold is kept beside the text, and Ctrl+B toggles it', function ()
  local s = sheet_of ({ A1 = 'x', A2 = 'y' })
  s:toggle_bold (r ('A1:A2'))
  ok (s:is_bold (1, 1) and s:is_bold (2, 1))
  s:toggle_bold (r ('A1:A3'))
  ok (s:is_bold (3, 1))
  s:toggle_bold (r ('A1:A3'))
  ok (not s:is_bold (1, 1) and not s:is_bold (3, 1))
  s:undo ()
  ok (s:is_bold (1, 1))
  set (s, 'A1', 'changed')
  ok (s:is_bold (1, 1))
  s:clear (r ('A1:A1'))
  eq (text (s, 'A1'), '')
  ok (s:is_bold (1, 1))
end)

test ('clear empties a block as one step', function ()
  local s = sheet_of ({ A1 = '1', B2 = '2', C3 = '3' })
  s:clear (r ('A1:B2'))
  eq ({ text (s, 'A1'), text (s, 'B2'), text (s, 'C3') }, { '', '', '3' })
  s:undo ()
  eq ({ text (s, 'A1'), text (s, 'B2') }, { '1', '2' })
  s:clear (r ('A1:Z5000'))
  eq ({ s:used () }, { 0, 0 })
end)

test ('copy and paste move relative references by the offset', function ()
  local s = sheet_of ({
    A1 = '1',
    A2 = '2',
    B1 = '=A1*$A$2',
    B2 = '=SUM($A$1:A2)',
  })
  s:toggle_bold (r ('B1:B1'))
  local clip = s:copy (r ('B1:B2'))
  eq (clip.texts, { { '=A1*$A$2' }, { '=SUM($A$1:A2)' } })
  eq (clip.tsv, '2\n3')
  eq (clip.bold, { { true }, { false } })
  local area = s:paste (3, 4, clip)
  eq (area, { r1 = 3, c1 = 4, r2 = 4, c2 = 4 })
  eq (text (s, 'D3'), '=C3*$A$2')
  eq (text (s, 'D4'), '=SUM($A$1:C4)')
  ok (s:is_bold (3, 4))
  -- One step for the whole paste.
  s:undo ()
  eq ({ text (s, 'D3'), text (s, 'D4') }, { '', '' })
  -- A reference pushed off the sheet turns into #REF!.
  s:paste (1, 1, s:copy (r ('B2:B2')))
  eq (text (s, 'A1'), '=SUM(#REF!)')
end)

test ('a one-cell clip fills the whole selection', function ()
  local s = sheet_of ({ B1 = '=C1+1' })
  local clip = s:copy (r ('B1:B1'))
  s:paste (2, 2, clip, r ('B2:C3'))
  eq (text (s, 'B2'), '=C2+1')
  eq (text (s, 'C3'), '=D3+1')
end)

test ('cut and paste moves cells without moving their references', function ()
  local s = sheet_of ({ A1 = '5', B1 = '=A1*2' })
  s:toggle_bold (r ('B1:B1'))
  local clip = s:copy (r ('B1:B1'))
  clip.cut = true
  s:paste (3, 3, clip)
  eq (text (s, 'B1'), '')
  ok (not s:is_bold (1, 2))
  eq (text (s, 'C3'), '=A1*2')
  ok (s:is_bold (3, 3))
  eq (shown (s, 'C3'), '10')
  s:undo ()
  eq ({ text (s, 'B1'), text (s, 'C3') }, { '=A1*2', '' })
  -- A cut pasted over its own cells keeps what lands there, and a reference into the moved
  -- block follows it.
  local again = s:copy (r ('A1:B1'))
  again.cut = true
  s:paste (1, 2, again)
  eq ({ text (s, 'A1'), text (s, 'B1'), text (s, 'C1') }, { '', '5', '=B1*2' })
end)

test ('pasting text from outside', function ()
  local s = sheet_of ()
  local area = s:paste_text (2, 2, 'a\tb\r\n1\t=B2&C2\r\n')
  eq (area, { r1 = 2, c1 = 2, r2 = 3, c2 = 3 })
  eq (
    { text (s, 'B2'), text (s, 'C2'), text (s, 'B3'), text (s, 'C3') },
    { 'a', 'b', '1', '=B2&C2' }
  )
  eq (shown (s, 'C3'), 'ab')
  s:paste_text (10, 1, 'x,y,z\n1,2,3')
  eq ({ text (s, 'A10'), text (s, 'C11') }, { 'x', '3' })
  s:paste_text (20, 1, 'Hello, world')
  eq ({ text (s, 'A20'), text (s, 'B20') }, { 'Hello, world', '' })
  s:paste_text (21, 1, 'one\ntwo')
  eq ({ text (s, 'A21'), text (s, 'A22') }, { 'one', 'two' })
  s:paste_text (30, 1, '7')
  eq (s:value (30, 1), 7)
end)

test ('parse_clipboard tells tabs, commas and lines apart', function ()
  eq (m.parse_clipboard ('a\tb\nc\td\n'), { { 'a', 'b' }, { 'c', 'd' } })
  eq (m.parse_clipboard ('1,2,3'), { { '1', '2', '3' } })
  eq (m.parse_clipboard ('a,b\nc,d'), { { 'a', 'b' }, { 'c', 'd' } })
  eq (m.parse_clipboard ('a, b'), { { 'a, b' } })
  eq (m.parse_clipboard ('a,b\nc'), { { 'a,b' }, { 'c' } })
  eq (m.parse_clipboard ('"x, y",z'), { { 'x, y', 'z' } })
  eq (m.parse_clipboard ('plain'), { { 'plain' } })
  eq (m.parse_clipboard (''), { { '' } })
  eq (m.parse_clipboard ('"two\nlines"\tb'), { { 'two\nlines', 'b' } })
end)

test ('same_clip knows its own text on the clipboard', function ()
  local s = sheet_of ({ A1 = '1', A2 = '=A1+1' })
  local clip = s:copy (r ('A1:A2'))
  ok (m.same_clip (clip, '1\n2'))
  ok (m.same_clip (clip, '1\r\n2\r\n'))
  ok (not m.same_clip (clip, '1\n3'))
  ok (not m.same_clip ({ texts = {} }, ''))
end)

test ('fill down and fill right', function ()
  local s = sheet_of ({ A1 = '1', B1 = '=A1*2', C1 = '=$A$1+A1' })
  s:toggle_bold (r ('B1:B1'))
  ok (s:fill_down (r ('A1:C4')))
  eq (text (s, 'B4'), '=A4*2')
  eq (text (s, 'C3'), '=$A$1+A3')
  eq (text (s, 'A4'), '1')
  ok (s:is_bold (4, 2))
  eq (#s.book.done, 2)
  s:undo ()
  eq (text (s, 'B4'), '')
  -- One row copies the row above it.
  ok (s:fill_down (r ('B2:B2')))
  eq (text (s, 'B2'), '=A2*2')
  ok (not s:fill_down (r ('A1:C1')))
  ok (s:fill_right (r ('B1:D1')))
  eq (text (s, 'D1'), '=C1*2')
  ok (s:fill_right (r ('E1:E1')))
  eq (text (s, 'E1'), '=D1*2')
  ok (not s:fill_right (r ('A5:A6')))
end)

test ('inserting and deleting rows moves cells and fixes formulas', function ()
  local s = sheet_of ({
    A1 = '1',
    A2 = '2',
    A3 = '3',
    A4 = '=SUM(A1:A3)',
    B1 = '=A3*10',
  })
  s:insert_rows (2, 2)
  eq (s.rows, 102)
  eq ({ text (s, 'A2'), text (s, 'A4'), text (s, 'A5') }, { '', '2', '3' })
  eq (text (s, 'A6'), '=SUM(A1:A5)')
  eq (text (s, 'B1'), '=A5*10')
  eq (shown (s, 'A6'), '6')
  s:delete_rows (4, 1)
  eq (text (s, 'A5'), '=SUM(A1:A4)')
  eq (shown (s, 'A5'), '4')
  eq (text (s, 'B1'), '=A4*10')
  s:delete_rows (4, 1)
  eq (text (s, 'B1'), '=#REF!*10')
  eq (shown (s, 'B1'), '#REF!')
  eq (text (s, 'A4'), '=SUM(A1:A3)')
  -- Each change is one undo step, and undo brings the old formulas back.
  s:undo ()
  eq (text (s, 'B1'), '=A4*10')
  s:undo ()
  s:undo ()
  eq (text (s, 'A4'), '=SUM(A1:A3)')
  eq (text (s, 'B1'), '=A3*10')
  eq (s.rows, 100)
  s:redo ()
  eq (text (s, 'A6'), '=SUM(A1:A5)')
end)

test (
  'inserting and deleting columns moves cells, widths and formulas',
  function ()
    local s =
      sheet_of ({ A1 = '1', B1 = '2', C1 = '=A1+B1', D1 = '=SUM(A1:C1)' })
    s:set_width (2, 150)
    s:set_width (4, 60)
    s:insert_cols (2, 1)
    eq (s.cols, 27)
    eq ({ text (s, 'B1'), text (s, 'C1') }, { '', '2' })
    eq (text (s, 'D1'), '=A1+C1')
    eq (text (s, 'E1'), '=SUM(A1:D1)')
    eq ({ s:width (2), s:width (3), s:width (5) }, { 100, 150, 60 })
    s:delete_cols (1, 2)
    eq (text (s, 'B1'), '=#REF!+A1')
    eq (text (s, 'C1'), '=SUM(A1:B1)')
    eq ({ s:width (1), s:width (3) }, { 150, 60 })
    s:undo ()
    eq (s:width (3), 150)
    s:undo ()
    eq (text (s, 'C1'), '=A1+B1')
    eq (s:width (2), 150)
  end
)

test ('Ctrl and an arrow jump to the edge of the data', function ()
  local s = sheet_of ({ A1 = 'x', A2 = 'x', A3 = 'x', A7 = 'x', A8 = 'x' })
  eq ({ s:jump (1, 1, 1, 0) }, { 3, 1 })
  eq ({ s:jump (3, 1, 1, 0) }, { 7, 1 })
  eq ({ s:jump (7, 1, 1, 0) }, { 8, 1 })
  eq ({ s:jump (8, 1, 1, 0) }, { 100, 1 })
  eq ({ s:jump (100, 1, 1, 0) }, { 100, 1 })
  eq ({ s:jump (100, 1, -1, 0) }, { 8, 1 })
  eq ({ s:jump (5, 1, -1, 0) }, { 3, 1 })
  eq ({ s:jump (1, 1, 0, 1) }, { 1, 26 })
  eq ({ s:jump (1, 5, 0, -1) }, { 1, 1 })
  eq ({ s:jump (1, 1, -1, 0) }, { 1, 1 })
end)

test ('stats add up the numbers in a block', function ()
  local s = sheet_of ({ A1 = '2', A2 = '4', A3 = 'x', A4 = '=A1*3' })
  eq (s:stats (r ('A1:A5')), { sum = 12, count = 3, average = 4 })
  eq (s:stats (r ('B1:B5')), { sum = 0, count = 0 })
  eq (s:stats ({ r1 = 1, c1 = 1, r2 = 100000, c2 = 26 }).count, 3)
end)

test ('displayed values', function ()
  local s = sheet_of ({
    A1 = '=1/3',
    A2 = '=NOW()',
    A3 = '=TODAY()',
    A4 = '=1/0',
    A5 = '1234567.891',
  })
  eq (shown (s, 'A1'), '0.3333333333')
  eq (s:display (1, 1, 15), '0.333333333333333')
  eq (shown (s, 'A2'), '2026-09-29 14:30')
  eq (shown (s, 'A3'), '2026-09-29')
  eq (shown (s, 'A4'), '#DIV/0!')
  eq (shown (s, 'A5'), '1234567.891')
  eq (s:grid (r ('A4:A5')), { { '#DIV/0!' }, { '1234567.891' } })
  eq (#s:grid (), 5)
end)

---------------------------------------------------------------------------------------------
-- CSV
---------------------------------------------------------------------------------------------

test ('CSV reading handles quotes, commas and line breaks', function ()
  eq (m.parse_csv ('a,b,c\n1,2,3\n'), { { 'a', 'b', 'c' }, { '1', '2', '3' } })
  eq (m.parse_csv ('a,b\r\n1,2'), { { 'a', 'b' }, { '1', '2' } })
  eq (m.parse_csv ('"x, y","say ""hi"""'), { { 'x, y', 'say "hi"' } })
  eq (
    m.parse_csv ('"two\nlines",b\r\nc,d'),
    { { 'two\nlines', 'b' }, { 'c', 'd' } }
  )
  eq (m.parse_csv ('"crlf\r\ninside",1'), { { 'crlf\r\ninside', '1' } })
  eq (m.parse_csv ('a,,c,'), { { 'a', '', 'c', '' } })
  eq (m.parse_csv (',\n,'), { { '', '' }, { '', '' } })
  eq (m.parse_csv ('a\n\nb'), { { 'a' }, { '' }, { 'b' } })
  eq (m.parse_csv ('"abc"def,g'), { { 'abcdef', 'g' } })
  eq (m.parse_csv ('"never closed'), { { 'never closed' } })
  eq (m.parse_csv (''), {})
  eq (m.parse_csv ('a\tb\n"c\td"\te', '\t'), { { 'a', 'b' }, { 'c\td', 'e' } })
  eq (m.parse_csv ('a;b', ';'), { { 'a', 'b' } })
end)

test ('CSV writing quotes what needs it, and reads back the same', function ()
  local rows = {
    { 'plain', 'with, comma', 'say "hi"' },
    { 'two\nlines', '', 'end' },
  }
  local out = m.to_csv (rows)
  eq (out, 'plain,"with, comma","say ""hi"""\r\n"two\nlines",,end')
  eq (m.parse_csv (out), rows)
  eq (m.to_csv ({ { 'a\tb', 'c' } }, '\t', '\n'), '"a\tb"\tc')
  eq (m.parse_csv (m.to_csv (rows, '\t', '\n'), '\t'), rows)
  eq (m.to_csv ({}), '')
end)

test ('from_grid makes a sheet from rows of text', function ()
  local s = m.from_grid ({
    { 'Item', 'Cost' },
    { 'Tea', '4' },
    { 'Total', '=SUM(B2)' },
  })
  eq (shown (s, 'B3'), '4')
  eq (#s.book.done, 0)
  eq ({ s.rows, s.cols }, { 100, 26 })
end)

---------------------------------------------------------------------------------------------
-- The file format
---------------------------------------------------------------------------------------------

test ('to_data and from_data round trip', function ()
  local s = sheet_of ({ A1 = 'Rent', B1 = '1200', B4 = '=SUM(B1:B3)' })
  s:toggle_bold (r ('A1:A1'))
  s:set_width (1, 140)
  s:grow (120, 30)
  local data = m.to_data (s)
  eq (data, {
    version = 3,
    active = 1,
    sheets = {
      {
        name = 'Sheet1',
        rows = 120,
        cols = 30,
        widths = { A = 140 },
        cells = { A1 = 'Rent', B1 = '1200', B4 = '=SUM(B1:B3)' },
        styles = { A1 = { bold = true } },
      },
    },
  })
  local back = m.from_data (data, { clock = clock })
  eq (m.to_data (back), data)
  eq (shown (back, 'B4'), '1200')
  eq (#back.book.done, 0)
  -- A version 1 file loads as one sheet named Sheet1.
  local old = m.from_data ({
    version = 1,
    rows = 10,
    cols = 4,
    cells = { A1 = 'x' },
    styles = { A1 = { bold = true } },
  })
  eq ({ old.name, old.rows, text (old, 'A1') }, { 'Sheet1', 10, 'x' })
  ok (old:is_bold (1, 1))
end)

test ('from_data tolerates missing and odd fields', function ()
  local empty = m.from_data (nil)
  eq ({ empty.rows, empty.cols }, { 100, 26 })
  local s = m.from_data ({
    cells = {
      A1 = 5,
      A2 = true,
      A3 = '',
      B2 = 'x',
      ['not an address'] = 'y',
      [3] = 'z',
    },
    styles = { B2 = { bold = true }, C9 = { bold = true }, D1 = 'bold' },
    widths = { 150, [3] = 80, ['4'] = 60, E = 'wide', F = -3 },
    rows = 'many',
  })
  eq ({ text (s, 'A1'), text (s, 'A2'), text (s, 'A3') }, { '5', 'TRUE', '' })
  ok (s:is_bold (2, 2))
  ok (s:is_bold (9, 3))
  eq (text (s, 'C9'), '')
  eq (
    { s:width (1), s:width (3), s:width (4), s:width (5), s:width (6) },
    { 150, 80, 60, 100, 100 }
  )
  eq (s.rows, 100)
  local listy =
    m.from_data ({ cells = {}, styles = {}, widths = {}, rows = 3, cols = 2 })
  eq ({ listy.rows, listy.cols }, { 3, 2 })
  local grown = m.from_data ({ cells = { Z9 = 'far' }, rows = 3, cols = 2 })
  eq ({ grown.rows, grown.cols }, { 9, 26 })
end)

test ('encode writes stable, readable JSON', function ()
  local s = m.new ({ rows = 10, cols = 4 })
  s:put (2, 1, { text = 'Say "hi"\n\tnow\\', bold = true })
  s:put (1, 2, { text = '=A2', bold = false })
  s:put (3, 3, { text = '', bold = true })
  s:set_width (2, 130)
  eq (
    m.encode (s),
    table.concat ({
      '{',
      '  "version": 3,',
      '  "active": 1,',
      '  "sheets": [',
      '    {',
      '      "name": "Sheet1",',
      '      "rows": 10,',
      '      "cols": 4,',
      '      "widths": {',
      '        "B": 130',
      '      },',
      '      "cells": {',
      '        "B1": "=A2",',
      '        "A2": "Say \\"hi\\"\\n\\tnow\\\\"',
      '      },',
      '      "styles": {',
      '        "A2": { "bold": true },',
      '        "C3": { "bold": true }',
      '      }',
      '    }',
      '  ]',
      '}',
      '',
    }, '\n')
  )
  eq (
    m.encode (m.new ()),
    '{\n  "version": 3,\n  "active": 1,\n  "sheets": [\n    {\n      "name": "Sheet1",\n      "rows": 100,\n      "cols": 26,\n      "cells": {}\n    }\n  ]\n}\n'
  )
  s:put (4, 1, { text = 'bell\7', bold = false })
  ok (m.encode (s):find ('"bell\\u0007"', 1, true))
end)

test ('a few thousand formulas recalculate quickly', function ()
  local s = m.new ({ rows = 2000 })
  for row = 1, 2000 do
    s:put (row, 1, { text = tostring (row), bold = false })
    s:put (row, 2, { text = '=A' .. row .. '*2', bold = false })
    local running = row == 1 and '=B1' or ('=C' .. (row - 1) .. '+B' .. row)
    s:put (row, 3, { text = running, bold = false })
  end
  s:put (1, 4, { text = '=SUM(B:B)-C2000', bold = false })
  local started = os.clock ()
  eq (s:display (2000, 3), '4002000')
  eq (s:display (1, 4), '0')
  s:set (1, 1, '11')
  eq (s:display (2000, 3), '4002020')
  ok (os.clock () - started < 20, 'recalculation took too long')
end)

test ('can_point knows where a reference can go', function ()
  ---@param formula string
  ---@return boolean
  local function at_end (formula)
    return f.can_point (formula, #formula + 1)
  end
  ok (at_end ('='))
  ok (at_end ('=A1+'))
  ok (at_end ('=SUM('))
  ok (at_end ('=SUM(A1:'))
  ok (at_end ('=IF(A1>0, '))
  ok (at_end ('=1*('))
  ok (not at_end ('=A1'))
  ok (not at_end ('=SUM(A1)'))
  ok (not at_end ('=5%'))
  ok (not at_end ('="a+'))
  ok (at_end ('="a"&'))
  ok (not at_end ('A1+'))
  ok (not at_end (''))
  ok (f.can_point ('=SUM()', 6))
  ok (f.can_point ('=(+1)', 3))
  ok (not f.can_point ('=(A1)', 3))
end)

test (
  'SUBTOTAL and AGGREGATE leave out hidden rows and other subtotals',
  function ()
    local s = sheet_of ({
      A1 = 'Item',
      B1 = 'Cost',
      A2 = 'Rent',
      B2 = '100',
      A3 = 'Food',
      B3 = '20',
      A4 = 'Rent',
      B4 = '300',
      B5 = '=SUBTOTAL(9, B2:B4)',
      B6 = '=SUBTOTAL(9, B2:B5)',
      C1 = '=SUBTOTAL(109, B2:B4)',
      C2 = '=SUBTOTAL(1, B2:B4)',
      C3 = '=SUBTOTAL(2, B2:B4)',
      C4 = '=SUBTOTAL(3, A2:A4)',
      C5 = '=SUBTOTAL(4, B2:B4)',
      C6 = '=SUBTOTAL(5, B2:B4)',
      C7 = '=SUBTOTAL(6, B2:B3)',
      C8 = '=SUBTOTAL(10, B2:B4)',
      D1 = '=AGGREGATE(9, 5, B2:B4)',
      D2 = '=AGGREGATE(9, 4, B2:B6)',
      D3 = '=AGGREGATE(9, 0, B2:B6)',
      D4 = '=AGGREGATE(4, 6, E1:E3)',
      D5 = '=AGGREGATE(14, 6, E1:E3, 2)',
      D6 = '=AGGREGATE(12, 0, B2:B4)',
      D7 = '=AGGREGATE(9, 4, E1:E3)',
      D8 = '=SUBTOTAL(12, B2:B4)',
      D9 = '=SUBTOTAL(9, 5)',
      E1 = '7',
      E2 = '=1/0',
      E3 = '3',
    })
    eq (
      { shown (s, 'B5'), shown (s, 'B6'), shown (s, 'C1') },
      { '420', '420', '420' }
    )
    eq (
      { shown (s, 'C2'), shown (s, 'C3'), shown (s, 'C4'), shown (s, 'C5') },
      { '140', '3', '3', '300' }
    )
    eq (
      { shown (s, 'C6'), shown (s, 'C7'), shown (s, 'C8') },
      { '20', '2000', '20800' }
    )
    eq (
      { shown (s, 'D1'), shown (s, 'D2'), shown (s, 'D3') },
      { '420', '1260', '420' }
    )
    eq (
      { shown (s, 'D4'), shown (s, 'D5'), shown (s, 'D6') },
      { '7', '3', '100' }
    )
    eq ({ shown (s, 'D7'), shown (s, 'D8'), shown (s, 'D9') }, {
      '#DIV/0!',
      '#VALUE!',
      '#VALUE!',
    })
    -- A row the user hides counts for 9 and not for 109, and the subtotals follow at once.
    s:set_hidden ('row', 3, 3, true)
    eq (
      { shown (s, 'B5'), shown (s, 'C1'), shown (s, 'D1') },
      { '420', '400', '400' }
    )
    s:set_hidden ('row', 3, 3, false)
    -- A row the filter hides counts for neither.
    local ops = require ('sheet_ops') --[[@as Sheet.OpsModule]]
    ops.set_filter (s, m.parse_range ('A1:B4') --[[@as Sheet.Rect]])
    ops.filter_column (s, 1, { values = { 'Rent' } })
    eq (
      { shown (s, 'B5'), shown (s, 'C1'), shown (s, 'C4') },
      { '400', '400', '2' }
    )
    eq (shown (s, 'D1'), '400')
    ops.remove_filter (s)
    eq (shown (s, 'B5'), '420')
  end
)

test ('the information functions tell about cells and sheets', function ()
  local s = sheet_of ({
    A1 = '=1+2',
    A2 = 'text',
    B1 = '=FORMULATEXT(A1)',
    B2 = '=FORMULATEXT(A2)',
    B3 = '=ISFORMULA(A1)',
    B4 = '=ISFORMULA(A2)',
    C1 = '=SHEET()',
    C2 = '=SHEETS()',
    C3 = '=SHEET("Other")',
    C4 = '=SHEET(Other!A1)',
    C5 = '=SHEETS(A1:B2)',
    C6 = '=SHEET("Nope")',
    D1 = '=CELL("address", B7)',
    D2 = '=CELL("row", B7)',
    D3 = '=CELL("col", B7)',
    D4 = '=CELL("contents", A1)',
    D5 = '=CELL("type", A2)',
    D6 = '=CELL("type", Z9)',
    D7 = '=CELL("address", Other!C3)',
    D8 = '=CELL("nope", A1)',
    E1 = '=HYPERLINK("https://example.com", "Example")',
    E2 = '=HYPERLINK("https://example.com")',
  })
  assert (s.book:add_sheet ('Other'))
  eq ({ shown (s, 'B1'), shown (s, 'B2'), shown (s, 'B3'), shown (s, 'B4') }, {
    '=1+2',
    '#N/A',
    'TRUE',
    'FALSE',
  })
  eq ({ shown (s, 'C1'), shown (s, 'C2'), shown (s, 'C3'), shown (s, 'C4') }, {
    '1',
    '2',
    '2',
    '2',
  })
  eq ({ shown (s, 'C5'), shown (s, 'C6') }, { '1', '#N/A' })
  eq (
    { shown (s, 'D1'), shown (s, 'D2'), shown (s, 'D3') },
    { '$B$7', '7', '2' }
  )
  eq ({ shown (s, 'D4'), shown (s, 'D5'), shown (s, 'D6') }, { '3', 'l', 'b' })
  eq ({ shown (s, 'D7'), shown (s, 'D8') }, { 'Other!$C$3', '#VALUE!' })
  eq ({ shown (s, 'E1'), shown (s, 'E2') }, { 'Example', 'https://example.com' })
end)

test ('the example budget works out with no errors', function ()
  local s = m.example ({ clock = clock })
  local rows, cols = s:used ()
  eq ({ rows, cols }, { 20, 6 })
  for row = 1, rows do
    for col = 1, cols do
      ok (
        s:kind (row, col) ~= 'error',
        m.address (row, col) .. ' shows an error'
      )
    end
  end
  eq (shown (s, 'B11'), '$2,155.00')
  eq (shown (s, 'C11'), '$2,207.45')
  eq (shown (s, 'D6'), '$32.35')
  eq (shown (s, 'D11'), '$52.45')
  eq (shown (s, 'E5'), '54.4%')
  eq (shown (s, 'E11'), '100.0%')
  eq (shown (s, 'F5'), 'OK')
  eq (shown (s, 'F6'), 'Over')
  eq (shown (s, 'F11'), 'Over budget')
  eq (shown (s, 'C13'), '$367.91')
  eq (shown (s, 'C14'), 'Rent')
  eq (shown (s, 'C15'), '2')
  eq (shown (s, 'C17'), '$3,200.00')
  eq (shown (s, 'C18'), '$320.00')
  eq (shown (s, 'C19'), '$992.55')
  eq (shown (s, 'A20'), 'On track: 31% of income is left over.')
  ok (s:is_bold (4, 6) and s:is_bold (11, 1) and not s:is_bold (5, 1))
  eq (s:width (1), 170)
end)
