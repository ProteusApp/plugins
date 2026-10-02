local x = require ('sheet_xlsx') --[[@as Sheet.XlsxModule]]

-- The parts of a workbook openpyxl made, trimmed to what the tests read. It has two sheets,
-- the second one active, with text, numbers, a date, booleans, formulas, a shared formula,
-- styles, a merge, widths, a height, a hidden row and column, and a frozen pane.
local ROOT_RELS = [[<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>]]

local WORKBOOK =
  [[<workbook xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><workbookPr /><bookViews><workbookView activeTab="1" /></bookViews><sheets><sheet name="Budget" sheetId="1" state="visible" r:id="rId1" /><sheet name="Q1 sales" sheetId="2" state="visible" r:id="rId2" /></sheets><definedNames /><calcPr calcId="124519" fullCalcOnLoad="1" /></workbook>]]

local WORKBOOK_RELS =
  [[<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="/xl/worksheets/sheet1.xml" Id="rId1" /><Relationship Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="/xl/worksheets/sheet2.xml" Id="rId2" /><Relationship Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml" Id="rId3" /></Relationships>]]

local STYLES = [[<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><numFmts count="3"><numFmt numFmtId="164" formatCode="$#,##0.00" /><numFmt numFmtId="165" formatCode="yyyy-mm-dd" /><numFmt numFmtId="166" formatCode="0.0%" /></numFmts><fonts count="5"><font><name val="Calibri" /><family val="2" /><color theme="1" /><sz val="11" /><scheme val="minor" /></font><font><b val="1" />]]
  .. [[<color rgb="FF1F4E79" /><sz val="16" /></font><font><b val="1" /><i val="1" /></font><font><strike val="1" /><u val="single" /></font><font><color rgb="FFC62828" /></font></fonts><fills count="3"><fill><patternFill /></fill><fill><patternFill patternType="gray125" /></fill><fill><patternFill patternType="solid"><fgColor rgb="FFE8EEFC" /></patternFill></fill></fills><borders count="3"><border>]]
  .. [[<left /><right /><top /><bottom /><diagonal /></border><border><bottom style="medium"><color rgb="FF333333" /></bottom></border><border><left style="thin" /><right style="dashed" /><top style="dotted" /><bottom style="double" /></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" /></cellStyleXfs><cellXfs count="9">]]
  .. [[<xf numFmtId="0" fontId="0" fillId="0" borderId="0" pivotButton="0" quotePrefix="0" xfId="0" /><xf numFmtId="0" fontId="1" fillId="0" borderId="0" pivotButton="0" quotePrefix="0" xfId="0" /><xf numFmtId="0" fontId="2" fillId="2" borderId="1" pivotButton="0" quotePrefix="0" xfId="0" /><xf numFmtId="164" fontId="0" fillId="0" borderId="0" pivotButton="0" quotePrefix="0" xfId="0" />]]
  .. [[<xf numFmtId="165" fontId="0" fillId="0" borderId="0" pivotButton="0" quotePrefix="0" xfId="0" /><xf numFmtId="166" fontId="0" fillId="0" borderId="0" pivotButton="0" quotePrefix="0" xfId="0" /><xf numFmtId="0" fontId="3" fillId="0" borderId="0" applyAlignment="1" pivotButton="0" quotePrefix="0" xfId="0"><alignment horizontal="center" vertical="top" wrapText="1" /></xf>]]
  .. [[<xf numFmtId="0" fontId="0" fillId="0" borderId="2" pivotButton="0" quotePrefix="0" xfId="0" /><xf numFmtId="0" fontId="4" fillId="0" borderId="0" pivotButton="0" quotePrefix="0" xfId="0" /></cellXfs></styleSheet>]]

local SHEET1 = [[<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><dimension ref="A1:D10" /><sheetViews><sheetView workbookViewId="0"><pane xSplit="1" ySplit="2" topLeftCell="B3" activePane="bottomRight" state="frozen" /><selection pane="bottomRight" activeCell="A1" sqref="A1" /></sheetView></sheetViews><sheetFormatPr baseColWidth="8" defaultRowHeight="15" /><cols>]]
  .. [[<col width="24" customWidth="1" min="1" max="1" /><col width="12.5" customWidth="1" min="2" max="2" /><col hidden="1" width="13" customWidth="1" min="6" max="6" /></cols><sheetData><row r="1" ht="24" customHeight="1"><c r="A1" s="1" t="inlineStr"><is><t>Monthly budget</t></is></c></row><row r="2"><c r="A2" s="2" t="inlineStr"><is><t>Item</t></is></c><c r="B2" s="2" t="inlineStr"><is><t>Planned</t>]]
  .. [[</is></c></row><row r="3"><c r="A3" t="inlineStr"><is><t>Rent</t></is></c><c r="B3" s="3" t="n"><v>1200</v></c><c r="C3" s="3" t="n"><v>1250</v></c><c r="D3"><f>C3-B3</f><v /></c></row><row r="4"><c r="B4" s="3" t="n"><v>400.5</v></c></row><row r="6"><c r="B6"><f>SUM(B3:B5)</f><v /></c></row><row r="7"><c r="B7" s="4" t="n"><v>46294</v></c></row><row r="8"><c r="B8" t="b"><v>1</v></c>]]
  .. [[<c r="C8" t="b"><v>0</v></c></row><row r="9"><c r="B9" s="5" t="n"><v>0.125</v></c></row><row r="10"><c r="A10" s="6" t="inlineStr"><is><t>Note &amp; &lt;tag&gt;</t></is></c><c r="B10" s="7" t="inlineStr"><is><t>thin box</t></is></c><c r="C10" s="8" t="inlineStr"><is><t>red</t></is></c></row><row r="12" hidden="1"></row></sheetData><mergeCells count="1"><mergeCell ref="A1:D1" /></mergeCells>]]
  .. [[</worksheet>]]

local SHEET2 =
  [[<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>x</t></is></c><c r="C1" t="inlineStr"><is><t>from budget</t></is></c></row><row r="2"><c r="A2" t="n"><v>1</v></c><c r="B2"><f t="shared" ref="B2:B5" si="0">A2*2</f><v>2</v></c><c r="C2"><f>Budget!B6</f><v /></c></row><row r="3"><c r="A3" t="n"><v>2</v></c><c r="B3"><f t="shared" si="0"/><v>4</v></c></row><row r="4"><c r="A4" t="n"><v>3</v></c><c r="B4"><f t="shared" si="0"/><v>6</v></c></row><row r="5"><c r="A5" t="n"><v>4</v></c><c r="B5"><f t="shared" si="0"/><v>8</v></c></row></sheetData></worksheet>]]

---@return table<string, string>
local function fixture ()
  return {
    ['_rels/.rels'] = ROOT_RELS,
    ['xl/workbook.xml'] = WORKBOOK,
    ['xl/_rels/workbook.xml.rels'] = WORKBOOK_RELS,
    ['xl/styles.xml'] = STYLES,
    ['xl/worksheets/sheet1.xml'] = SHEET1,
    ['xl/worksheets/sheet2.xml'] = SHEET2,
  }
end

---A workbook with one sheet, built from the parts a test cares about.
---@param sheet string The sheetData and anything after it.
---@param extra? table<string, string> More files.
---@return table<string, string>
local function one_sheet (sheet, extra)
  local files = {
    ['xl/workbook.xml'] = '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Data" sheetId="1" r:id="rId1"/></sheets></workbook>',
    ['xl/_rels/workbook.xml.rels'] = '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>',
    ['xl/worksheets/sheet1.xml'] = '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      .. sheet
      .. '</worksheet>',
  }
  for k, v in pairs (extra or {}) do
    files[k] = v
  end
  return files
end

---@param files table<string, string>
---@return Sheet.BookData
---@return string[]
local function read_ok (files)
  local book, warnings = x.read (files)
  assert (book, tostring (warnings))
  return book, warnings --[[@as string[] ]]
end

---------------------------------------------------------------------------------------------
-- The XML reader
---------------------------------------------------------------------------------------------

test ('the XML reader keeps elements, attributes, text and prefixes', function ()
  local root = assert (x.parse_xml ([==[<?xml version="1.0"?>
<!-- a comment -->
<x:root xmlns:x="urn:a" a="1" b='two &amp; &quot;three&quot;'>
  <x:item id="&#65;&#x42;"/>
  <x:text xml:space="preserve">  a &lt; b &#x263A; </x:text>
  <data><![CDATA[<not> & a tag]]></data>
</x:root>]==]))
  eq (root.name, 'x:root')
  eq (root.attrs, { ['xmlns:x'] = 'urn:a', a = '1', b = 'two & "three"' })
  eq (#root.children, 3)
  eq (root.children[1].name, 'x:item')
  eq (root.children[1].attrs.id, 'AB')
  eq (root.children[1].children, {})
  eq (root.children[2].text, '  a < b \226\152\186 ')
  eq (root.children[3].text, '<not> & a tag')
end)

test (
  'the XML reader keeps unknown entities and line breaks as written',
  function ()
    local root = assert (x.parse_xml ('<a v="x\ny">1\r\n2 &nbsp; &#xD800;</a>'))
    eq (root.text, '1\n2 &nbsp; &#xD800;')
    eq (root.attrs.v, 'x y')
  end
)

test ('the XML reader refuses a document that is not well formed', function ()
  local cases = {
    '<a><b></a>',
    '<a>',
    '<a b="1></a>',
    '<a></a><b></b>',
    'no tags',
    '<a><!-- open</a>',
  }
  for _, src in ipairs (cases) do
    local root, err = x.parse_xml (src)
    eq (root, nil, src)
    ok (type (err) == 'string' and #err > 0, src)
  end
end)

test ('the XML reader handles deep nesting without recursion', function ()
  local depth = 20000
  local src = string.rep ('<a>', depth) .. 'deep' .. string.rep ('</a>', depth)
  local node = assert (x.parse_xml (src))
  for _ = 2, depth do
    node = node.children[1]
  end
  eq (node.text, 'deep')
end)

---------------------------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------------------------

test ('reading finds the sheets in order and the active one', function ()
  local book, warnings = read_ok (fixture ())
  eq (book.version, 2)
  eq (book.active, 2)
  eq (#book.sheets, 2)
  eq (book.sheets[1].name, 'Budget')
  eq (book.sheets[2].name, 'Q1 sales')
  eq (warnings, {})
end)

test ('reading brings over values and formulas', function ()
  local book = read_ok (fixture ())
  local cells = book.sheets[1].cells or {}
  eq (cells.A1, 'Monthly budget')
  eq (cells.B3, '1200')
  eq (cells.B4, '400.5')
  eq (cells.D3, '=C3-B3')
  eq (cells.B6, '=SUM(B3:B5)')
  eq (cells.B7, '46294')
  eq (cells.B8, 'TRUE')
  eq (cells.C8, 'FALSE')
  eq (cells.B9, '0.125')
  eq (cells.A10, 'Note & <tag>')
end)

test ('reading expands a shared formula into each of its cells', function ()
  local book = read_ok (fixture ())
  local cells = book.sheets[2].cells or {}
  eq (cells.B2, '=A2*2')
  eq (cells.B3, '=A3*2')
  eq (cells.B4, '=A4*2')
  eq (cells.B5, '=A5*2')
  eq (cells.C2, '=Budget!B6')
end)

test ('reading brings over cell styles', function ()
  local styles = read_ok (fixture ()).sheets[1].styles or {}
  eq (styles.A1, { bold = true, size = 21, color = '#1f4e79' })
  eq (styles.A2, {
    bold = true,
    italic = true,
    fill = '#e8eefc',
    border_bottom = 'medium',
    border_color = '#333333',
  })
  eq (styles.B3, { format = '$#,##0.00' })
  eq (styles.B7, { format = 'yyyy-mm-dd' })
  eq (styles.B9, { format = '0.0%' })
  eq (styles.A10, {
    underline = true,
    strike = true,
    align = 'center',
    valign = 'top',
    wrap = true,
  })
  eq (styles.B10, {
    border_left = 'thin',
    border_right = 'dashed',
    border_top = 'dotted',
    border_bottom = 'double',
  })
  eq (styles.C10, { color = '#c62828' })
  eq (styles.A3, nil)
  eq (styles.D3, nil)
end)

test ('reading brings over the shape of a sheet', function ()
  local sheet = read_ok (fixture ()).sheets[1]
  eq (sheet.rows, 100)
  eq (sheet.cols, 26)
  eq (sheet.widths, { A = 168, B = 88, F = 91 })
  eq (sheet.heights, { ['1'] = 32 })
  eq (sheet.hidden_rows, { 12 })
  eq (sheet.hidden_cols, { 'F' })
  eq (sheet.merges, { 'A1:D1' })
  eq (sheet.freeze, { rows = 2, cols = 1 })
  eq (read_ok (fixture ()).sheets[2].freeze, nil)
end)

test ('reading sizes a sheet to what it uses', function ()
  local book = read_ok (
    one_sheet (
      '<sheetData><row r="250"><c r="AD250"><v>1</v></c></row></sheetData>'
    )
  )
  eq (book.sheets[1].rows, 250)
  eq (book.sheets[1].cols, 30)
end)

test (
  'reading leaves out rows past the end, and far rows with no cells',
  function ()
    local book, warnings = read_ok (
      one_sheet (
        '<sheetData><row r="3" ht="30" customHeight="1"><c r="A3"><v>1</v></c></row>'
          .. '<row r="900" hidden="1"/><row r="1048576" hidden="1" ht="30" customHeight="1"/>'
          .. '<row r="1048577"><c r="A1048577"><v>2</v></c></row>'
          .. '<row r="5"><c r="XFE5"><v>3</v></c><c r="B5"><v>4</v></c></row></sheetData>'
          .. '<mergeCells><mergeCell ref="A1048576:B1048577"/></mergeCells>'
      )
    )
    local sheet = book.sheets[1]
    -- A hidden row near the cells stays, and one at the bottom of the sheet does not stretch it.
    eq (sheet.rows, 900)
    eq (sheet.hidden_rows, { 900 })
    eq (sheet.heights, { ['3'] = 40 })
    eq (sheet.cells, { A3 = '1', B5 = '4' })
    eq (sheet.merges, nil)
    eq (
      warnings,
      { 'Cells in Data past row 1048576 or column XFD were left out.' }
    )
  end
)

test (
  'reading keeps the last value of a formula that reads another workbook',
  function ()
    local book, warnings = read_ok (
      one_sheet (
        '<sheetData><row r="1"><c r="A1"><f>[1]Sheet1!A1*2</f><v>42</v></c>'
          .. '<c r="B1"><f>\'[2]My data\'!B2</f><v>7</v></c>'
          .. '<c r="C1"><f>"[1]"&amp;A1</f><v>x</v></c></row></sheetData>'
      )
    )
    eq (book.sheets[1].cells, { A1 = '42', B1 = '7', C1 = '="[1]"&A1' })
    eq (warnings, {
      'Formulas in Data that read other workbooks were left out. Their last values are kept.',
    })
  end
)

test (
  'reading an array formula leaves out the last values of its block',
  function ()
    local book = read_ok (
      one_sheet (
        '<sheetData><row r="1"><c r="A1" cm="1"><f t="array" ref="A1:B2">_xlfn._xlws.SORT(D1:E2)</f><v>1</v></c>'
          .. '<c r="B1"><v>2</v></c><c r="C1"><f>_xlfn.LET(_xlpm.x,2,_xlpm.x*3)</f><v>6</v></c></row>'
          .. '<row r="2"><c r="A2"><v>3</v></c><c r="B2"><v>4</v></c>'
          .. '<c r="C2"><f>SUM(_xlfn.ANCHORARRAY(A1))</f><v>10</v></c></row></sheetData>'
      )
    )
    eq (book.sheets[1].cells, {
      A1 = '=SORT(D1:E2)',
      C1 = '=LET(x,2,x*3)',
      C2 = '=SUM(A1#)',
    })
  end
)

test ('reading drops a NUL character', function ()
  local book = read_ok (
    one_sheet (
      '<sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>a&#0;b_x0000_c</t></is></c></row></sheetData>'
    )
  )
  eq (book.sheets[1].cells, { A1 = 'abc' })
end)

test ('reading shows numbers with the digits Excel shows', function ()
  local files = one_sheet (
    '<sheetData><row r="1"><c r="A1"><v>0.30000000000000004</v></c><c r="B1"><v>-1.5E-3</v></c><c r="C1"><v>123456789012</v></c><c r="D1" t="d"><v>2026-09-29T12:00:00</v></c></row></sheetData>'
  )
  local cells = read_ok (files).sheets[1].cells or {}
  eq (cells, { A1 = '0.3', B1 = '-0.0015', C1 = '123456789012', D1 = '46294.5' })
end)

test ('reading joins rich text and decodes escaped characters', function ()
  local files = one_sheet (
    '<sheetData><row r="1"><c r="A1" t="s"><v>0</v></c><c r="A2" t="s"><v>1</v></c><c r="A3" t="s"><v>2</v></c></row></sheetData>',
    {
      ['xl/sharedStrings.xml'] = [[<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="3" uniqueCount="3">
  <si><r><rPr><b/></rPr><t>Bold</t></r><r><t xml:space="preserve"> and plain</t></r></si>
  <si><t>line_x000D_
two _x005F_x0041_</t></si>
  <si><t>東京</t><rPh sb="0" eb="2"><t>トウキョウ</t></rPh></si>
</sst>]],
    }
  )
  local book, warnings = read_ok (files)
  local cells = book.sheets[1].cells or {}
  eq (cells.A1, 'Bold and plain')
  eq (cells.A2, 'line\r\ntwo _x0041_')
  eq (cells.A3, '東京')
  eq (warnings, { 'Mixed text formatting inside cells in Data was left out.' })
end)

test ('reading keeps text that would read as something else as text', function ()
  local files = one_sheet (
    '<sheetData><row r="1">'
      .. '<c r="A1" t="inlineStr"><is><t>00123</t></is></c>'
      .. '<c r="B1" t="inlineStr"><is><t>=not a formula</t></is></c>'
      .. '<c r="C1" t="inlineStr"><is><t>TRUE</t></is></c>'
      .. '<c r="D1" t="inlineStr"><is><t>plain words</t></is></c>'
      .. '<c r="E1" t="inlineStr"><is><t>\'quoted</t></is></c>'
      .. '<c r="F1" t="e"><v>#N/A</v></c>'
      .. '</row></sheetData>'
  )
  local cells = read_ok (files).sheets[1].cells or {}
  eq (cells.A1, "'00123")
  eq (cells.B1, "'=not a formula")
  eq (cells.C1, "'TRUE")
  eq (cells.D1, 'plain words')
  eq (cells.E1, "''quoted")
  eq (cells.F1, '#N/A')
end)

test ('reading drops the prefixes Excel gives newer functions', function ()
  local files = one_sheet (
    '<sheetData><row r="1">'
      .. '<c r="A1"><f>_xlfn.XLOOKUP(B1,C1:C9,D1:D9)</f></c>'
      .. '<c r="A2"><f>_xlfn._xlws.SORT(B1:B9)&amp;"_xlfn.kept"</f></c>'
      .. '</row></sheetData>'
  )
  local cells = read_ok (files).sheets[1].cells or {}
  eq (cells.A1, '=XLOOKUP(B1,C1:C9,D1:D9)')
  eq (cells.A2, '=SORT(B1:B9)&"_xlfn.kept"')
end)

test (
  'reading maps theme, indexed and tinted colours and built-in formats',
  function ()
    local styles =
      [[<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<fonts><font><sz val="11"/><color theme="1"/><name val="Calibri"/></font>
<font><sz val="11"/><color rgb="FF000000"/></font>
<font><sz val="11"/><color indexed="10"/></font>
<font><sz val="9"/><color theme="4"/></font></fonts>
<fills><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>
<fill><patternFill patternType="solid"><fgColor theme="4" tint="0.79998168889431442"/><bgColor indexed="64"/></patternFill></fill>
<fill><patternFill patternType="solid"><fgColor theme="9" tint="-0.249977111117893"/></patternFill></fill></fills>
<borders><border/></borders>
<cellXfs><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>
<xf numFmtId="14" fontId="1" fillId="0" borderId="0"/>
<xf numFmtId="9" fontId="2" fillId="2" borderId="0"/>
<xf numFmtId="44" fontId="3" fillId="3" borderId="0"/>
<xf numFmtId="30" fontId="0" fillId="0" borderId="0"/></cellXfs></styleSheet>]]
    local files = one_sheet (
      '<sheetData><row r="1"><c r="A1" s="1"><v>1</v></c><c r="B1" s="2"><v>1</v></c><c r="C1" s="3"><v>1</v></c><c r="D1" s="4"><v>1</v></c></row></sheetData>',
      { ['xl/styles.xml'] = styles }
    )
    local got = read_ok (files).sheets[1].styles or {}
    eq (got.A1, { format = 'm/d/yyyy' })
    eq (got.B1, { color = '#ff0000', fill = '#dae3f3', format = '0%' })
    eq (got.C1, {
      size = 12,
      color = '#4472c4',
      fill = '#548235',
      format = '_("$"* #,##0.00_);_("$"* \\(#,##0.00\\);_("$"* "-"??_);_(@_)',
    })
    eq (got.D1, nil)
  end
)

test ('reading uses the theme colours the file carries', function ()
  local theme =
    [[<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><a:themeElements><a:clrScheme name="Office"><a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1><a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1><a:dk2><a:srgbClr val="0E2841"/></a:dk2><a:lt2><a:srgbClr val="E8E8E8"/></a:lt2><a:accent1><a:srgbClr val="156082"/></a:accent1></a:clrScheme></a:themeElements></a:theme>]]
  local styles =
    [[<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts><font><sz val="11"/></font><font><sz val="11"/><color theme="4"/></font><font><sz val="11"/><color theme="5"/></font></fonts><cellXfs><xf fontId="0"/><xf fontId="1"/><xf fontId="2"/></cellXfs></styleSheet>]]
  local files = one_sheet (
    '<sheetData><row r="1"><c r="A1" s="1"><v>1</v></c><c r="B1" s="2"><v>1</v></c></row></sheetData>',
    { ['xl/styles.xml'] = styles, ['xl/theme/theme1.xml'] = theme }
  )
  local got = read_ok (files).sheets[1].styles or {}
  eq (got.A1, { color = '#156082' })
  eq (got.B1, { color = '#ed7d31' })
end)

test ('reading lays cell styles over row and column styles', function ()
  local styles =
    [[<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><numFmts><numFmt numFmtId="164" formatCode="$#,##0.00"/></numFmts><fonts><font><sz val="11"/></font><font><b/><sz val="11"/></font></fonts><cellXfs><xf fontId="0" numFmtId="0"/><xf fontId="0" numFmtId="164"/><xf fontId="1" numFmtId="164"/><xf fontId="1" numFmtId="0"/></cellXfs></styleSheet>]]
  local files = one_sheet (
    '<cols><col min="2" max="2" width="9.140625" style="1"/></cols>'
      .. '<sheetData><row r="3" s="3" customFormat="1">'
      .. '<c r="A3" s="3"><v>1</v></c><c r="B3" s="2"><v>2</v></c><c r="C3"><v>3</v></c>'
      .. '</row><row r="4"><c r="B4" s="1"><v>4</v></c><c r="B5" s="0"><v>5</v></c></row></sheetData>',
    { ['xl/styles.xml'] = styles }
  )
  local sheet = read_ok (files).sheets[1]
  eq (sheet.col_styles, { B = { format = '$#,##0.00' } })
  eq (sheet.row_styles, { ['3'] = { bold = true } })
  eq (sheet.widths, nil)
  eq (sheet.styles, { C3 = { bold = false }, B5 = { format = 'General' } })
end)

test ('reading moves dates in a 1904 workbook', function ()
  local files = one_sheet (
    '<sheetData><row r="1"><c r="A1" s="1"><v>44832</v></c><c r="B1"><v>44832</v></c></row></sheetData>',
    {
      ['xl/styles.xml'] = '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><cellXfs><xf numFmtId="0"/><xf numFmtId="14"/></cellXfs></styleSheet>',
    }
  )
  files['xl/workbook.xml'] = string.gsub (
    files['xl/workbook.xml'],
    '<sheets>',
    '<workbookPr date1904="1"/><sheets>'
  )
  local cells = read_ok (files).sheets[1].cells or {}
  eq (cells.A1, '46294')
  eq (cells.B1, '44832')
end)

test ('reading warns about each kind of thing it leaves out', function ()
  local files = one_sheet (
    '<sheetData/><autoFilter ref="A1:C9"/><conditionalFormatting sqref="A1"><cfRule type="expression" priority="1"/></conditionalFormatting><dataValidations count="1"><dataValidation sqref="B1"/></dataValidations><drawing r:id="rId1" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"/>',
    {
      ['xl/worksheets/_rels/sheet1.xml.rels'] = '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/comments" Target="../comments1.xml"/></Relationships>',
      ['xl/drawings/drawing1.xml'] = '<xdr:wsDr xmlns:xdr="urn:x"><xdr:twoCellAnchor><xdr:graphicFrame/></xdr:twoCellAnchor></xdr:wsDr>',
      ['xl/drawings/_rels/drawing1.xml.rels'] = '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart" Target="../charts/chart1.xml"/></Relationships>',
    }
  )
  files['xl/workbook.xml'] =
    [[<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Data" sheetId="1" r:id="rId1"/><sheet name="Secret" sheetId="2" state="hidden" r:id="rId2"/><sheet name="Chart1" sheetId="3" r:id="rId3"/></sheets><definedNames><definedName name="_xlnm._FilterDatabase" localSheetId="0" hidden="1">Data!$A$1:$C$9</definedName><definedName name="Rates">Data!$B$1</definedName></definedNames></workbook>]]
  files['xl/_rels/workbook.xml.rels'] =
    [[<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/chartsheet" Target="chartsheets/sheet1.xml"/></Relationships>]]
  files['xl/worksheets/sheet2.xml'] =
    '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData/></worksheet>'
  local book, warnings = read_ok (files)
  eq (#book.sheets, 2)
  eq (warnings, {
    'Charts in Data were left out.',
    'Comments in Data were left out.',
    'Conditional formats in Data were left out.',
    'Data validation in Data was left out.',
    'The filter in Data was left out.',
    'The hidden sheet Secret shows here.',
    'The chart sheet Chart1 was left out.',
    'Named ranges were left out.',
  })
end)

test (
  'reading takes the parts Excel adds and fills in missing addresses',
  function ()
    local files = one_sheet (
      '<sheetData><row r="1" spans="1:3" x14ac:dyDescent="0.25"><c r="A1" s="0" t="s"><v>0</v></c><c t="s"><v>1</v></c><c><v>3</v></c></row><row><c><v>4</v></c></row></sheetData>',
      {
        ['xl/sharedStrings.xml'] = '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="2" uniqueCount="2"><si><t>first</t></si><si><t>second</t></si></sst>',
      }
    )
    files['xl/workbook.xml'] = table.concat ({
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n',
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006" mc:Ignorable="x15 xr xr6 xr10 xr2" xmlns:x15="http://schemas.microsoft.com/office/spreadsheetml/2010/11/main" xmlns:xr="http://schemas.microsoft.com/office/spreadsheetml/2014/revision">',
      '<fileVersion appName="xl" lastEdited="7" lowestEdited="7" rupBuild="27425"/><workbookPr defaultThemeVersion="202300"/><mc:AlternateContent xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"><mc:Choice Requires="x15">',
      '<x15ac:absPath url="C:/Users/" xmlns:x15ac="http://schemas.microsoft.com/office/spreadsheetml/2010/11/ac"/></mc:Choice></mc:AlternateContent><xr:revisionPtr revIDLastSave="0" documentId="8_{0}" xr6:coauthVersionLast="47" xmlns:xr6="http://schemas.microsoft.com/office/spreadsheetml/2016/revision6"/>',
      '<bookViews><workbookView xWindow="-110" yWindow="-110" windowWidth="25820" windowHeight="15500" xr2:uid="{0}" xmlns:xr2="http://schemas.microsoft.com/office/spreadsheetml/2015/revision2"/></bookViews><sheets><sheet name="Data" sheetId="1" r:id="rId1"/></sheets><calcPr calcId="191029"/></workbook>',
    })
    local cells = read_ok (files).sheets[1].cells or {}
    eq (cells, { A1 = 'first', B1 = 'second', C1 = '3', A2 = '4' })
  end
)

test ('reading refuses what is not a workbook', function ()
  local book, err = x.read ({ ['readme.txt'] = 'hello' })
  eq (book, nil)
  eq (err, 'This file is not an Excel workbook.')
  local files = fixture ()
  files['xl/workbook.xml'] = '<workbook><sheets></workbook>'
  book, err = x.read (files)
  eq (book, nil)
  ok (string.find (tostring (err), 'damaged', 1, true), tostring (err))
  files = fixture ()
  files['xl/workbook.xml'] =
    '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheets/></workbook>'
  book, err = x.read (files)
  eq (book, nil)
  eq (err, 'The workbook has no sheets that can be opened.')
end)

---------------------------------------------------------------------------------------------
-- Writing
---------------------------------------------------------------------------------------------

---@return Sheet.BookData
local function sample_book ()
  return {
    version = 2,
    active = 2,
    sheets = {
      {
        name = 'Budget',
        rows = 100,
        cols = 28,
        widths = { A = 170, C = 60 },
        heights = { ['4'] = 32 },
        hidden_rows = { 7, 9 },
        hidden_cols = { 'C', 'AB' },
        freeze = { rows = 4, cols = 1 },
        cells = {
          A1 = 'Monthly budget & <plan>',
          A4 = 'Item',
          B4 = 'Amount',
          A5 = 'Rent',
          B5 = '1200',
          A6 = 'Food',
          B6 = '-412.25',
          B7 = '0.125',
          B8 = '=SUM(B5:B6)',
          C8 = '=IF(B8>0,"over","under")',
          D8 = '=XLOOKUP(A5,A5:A6,B5:B6)',
          A9 = 'TRUE',
          A10 = "'00123",
          A11 = '46294',
          B11 = "=Q1!A1&'Q1 sales'!A2",
        },
        styles = {
          A1 = { bold = true, size = 21, color = '#1f4e79' },
          B5 = { format = '$#,##0.00', fill = '#e8eefc' },
          B7 = { format = '0.0%', italic = true },
          A11 = { format = 'yyyy-mm-dd', align = 'center', valign = 'middle' },
          C8 = {
            border_top = 'thin',
            border_bottom = 'double',
            border_color = '#333333',
            wrap = true,
          },
          D9 = { underline = true, strike = true },
        },
        col_styles = { B = { format = '#,##0.00' } },
        row_styles = { ['4'] = { bold = true, fill = '#dddddd' } },
        merges = { 'A1:D1', 'A12:B13' },
      },
      {
        name = 'Q1',
        rows = 100,
        cols = 26,
        cells = { A1 = 'x', A2 = '2' },
      },
      {
        name = 'Q1 sales',
        rows = 120,
        cols = 30,
        cells = { A2 = 'y', AD120 = 'far' },
      },
    },
  }
end

test ('writing makes every part an Excel file needs', function ()
  local files, warnings = x.write (sample_book ())
  local names = {} ---@type string[]
  for path in pairs (files) do
    names[#names + 1] = path
  end
  table.sort (names)
  eq (names, {
    '[Content_Types].xml',
    '_rels/.rels',
    'docProps/app.xml',
    'docProps/core.xml',
    'xl/_rels/workbook.xml.rels',
    'xl/sharedStrings.xml',
    'xl/styles.xml',
    'xl/workbook.xml',
    'xl/worksheets/sheet1.xml',
    'xl/worksheets/sheet2.xml',
    'xl/worksheets/sheet3.xml',
  })
  for path, text in pairs (files) do
    local root, err = x.parse_xml (text)
    ok (root, path .. ': ' .. tostring (err))
  end
  eq (warnings, {})
  ok (
    string.find (
      files['[Content_Types].xml'],
      '/xl/worksheets/sheet3.xml',
      1,
      true
    )
  )
end)

test ('writing puts formulas without the = and adds Excel prefixes', function ()
  local files = x.write (sample_book ())
  local sheet = files['xl/worksheets/sheet1.xml']
  ok (string.find (sheet, '<c r="B8" s="%d+"><f>SUM%(B5:B6%)</f></c>'), sheet)
  ok (string.find (sheet, '<f>IF(B8&gt;0,"over","under")</f>', 1, true))
  ok (string.find (sheet, '<f>_xlfn.XLOOKUP(A5,A5:A6,B5:B6)</f>', 1, true))
  ok (string.find (sheet, "<f>Q1!A1&amp;'Q1 sales'!A2</f>", 1, true))
end)

test ('writing stores the value of each formula when it is given', function ()
  local book = sample_book ()
  ---@param sheet integer
  ---@param row integer
  ---@param col integer
  ---@return Sheet.Value
  local function values (sheet, row, col)
    if sheet == 1 and row == 8 and col == 2 then
      return 787.75
    elseif sheet == 1 and row == 8 and col == 3 then
      return 'over'
    elseif sheet == 1 and row == 8 and col == 4 then
      return { code = '#N/A' }
    end
    return nil
  end
  local sheet = x.write (book, values)['xl/worksheets/sheet1.xml']
  ok (string.find (sheet, '<f>SUM(B5:B6)</f><v>787.75</v>', 1, true), sheet)
  ok (
    string.find (
      sheet,
      't="str"><f>IF(B8&gt;0,"over","under")</f><v>over</v>',
      1,
      true
    )
  )
  ok (
    string.find (
      sheet,
      't="e"><f>_xlfn.XLOOKUP(A5,A5:A6,B5:B6)</f><v>#N/A</v>',
      1,
      true
    )
  )
end)

test (
  'a formula that spills writes as an array formula over its block',
  function ()
    local book = {
      version = 2,
      sheets = {
        {
          name = 'Data',
          cells = {
            A1 = '=SEQUENCE(3)',
            C1 = '=SUM(A1#)',
            D1 = '=LET(x, 2, f, LAMBDA(n, n*x), f(5))',
          },
        },
      },
    }
    ---@param _ integer
    ---@param row integer
    ---@param col integer
    ---@return Sheet.Value
    local function values (_, row, col)
      if col == 1 then
        return row + 0.0
      end
      return col == 3 and 6 or 10
    end
    ---@param _ integer
    ---@param row integer
    ---@param col integer
    ---@return integer?
    ---@return integer?
    local function spills (_, row, col)
      if row == 1 and col == 1 then
        return 3, 1
      end
      return nil, nil
    end
    local files = x.write (book, values, spills)
    local sheet = files['xl/worksheets/sheet1.xml']
    ok (
      string.find (
        sheet,
        '<c r="A1" cm="1"><f t="array" ref="A1:A3">_xlfn.SEQUENCE(3)</f><v>1</v></c>',
        1,
        true
      ),
      sheet
    )
    ok (string.find (sheet, '<c r="A3"><v>3</v></c>', 1, true), sheet)
    ok (string.find (sheet, '<f>SUM(_xlfn.ANCHORARRAY(A1))</f>', 1, true), sheet)
    ok (
      string.find (
        sheet,
        '<f>_xlfn.LET(_xlpm.x, 2, _xlpm.f, _xlfn.LAMBDA(_xlpm.n, _xlpm.n*_xlpm.x), _xlpm.f(5))</f>',
        1,
        true
      ),
      sheet
    )
    ok (files['xl/metadata.xml'], 'the metadata part is written')
    ok (string.find (files['[Content_Types].xml'], '/xl/metadata.xml', 1, true))
    ok (
      string.find (files['xl/_rels/workbook.xml.rels'], 'sheetMetadata', 1, true)
    )
    -- Reading it back gives the formulas, and leaves the block's values for the formula to spill.
    local back = read_ok (files)
    eq (back.sheets[1].cells, book.sheets[1].cells)
    -- A book with no spills has no metadata part.
    eq (x.write (book, values)['xl/metadata.xml'], nil)
  end
)

test ('writing types each value and escapes text', function ()
  local files = x.write (sample_book ())
  local sheet = files['xl/worksheets/sheet1.xml']
  local strings = files['xl/sharedStrings.xml']
  ok (string.find (sheet, '<c r="B6"%s?[^>]*><v>%-412%.25</v></c>'), sheet)
  ok (string.find (sheet, '<c r="A9" t="b"><v>1</v></c>', 1, true))
  ok (string.find (strings, '<t>Monthly budget &amp; &lt;plan&gt;</t>', 1, true))
  ok (string.find (strings, '<t>00123</t>', 1, true))
  local _, uses = string.gsub (sheet, 't="s"', '')
  ok (string.find (strings, 'count="' .. (uses + 3) .. '"', 1, true), strings)
end)

test ('writing fixes sheet names Excel refuses and warns', function ()
  local book = {
    version = 2,
    sheets = {
      { name = 'Plan: 2026/27 [draft]', cells = { A1 = '1' } },
      { name = 'A very long sheet name that goes past the limit' },
      { name = 'plan_ 2026_27 _draft_' },
      { name = 'History' },
      { name = 'Budget & more' },
    },
  }
  local files, warnings = x.write (book)
  local wb = files['xl/workbook.xml']
  ok (string.find (wb, 'name="Plan_ 2026_27 _draft_ (2)"', 1, true), wb)
  ok (string.find (wb, 'name="A very long sheet name that goe"', 1, true), wb)
  ok (string.find (wb, 'name="plan_ 2026_27 _draft_"', 1, true), wb)
  ok (string.find (wb, 'name="History (2)"', 1, true), wb)
  ok (string.find (wb, 'name="Budget &amp; more"', 1, true), wb)
  eq (warnings, {
    "Excel does not allow the sheet name 'Plan: 2026/27 [draft]', so the file calls it 'Plan_ 2026_27 _draft_ (2)'.",
    "Excel does not allow the sheet name 'A very long sheet name that goes past the limit', so the file calls it 'A very long sheet name that goe'.",
    "Excel does not allow the sheet name 'History', so the file calls it 'History (2)'.",
  })
end)

test ('writing points formulas at a sheet whose name had to change', function ()
  local book = {
    version = 2,
    sheets = {
      { name = 'Q1: sales', cells = { A1 = '5' } },
      { name = 'Sums', cells = { A1 = "='Q1: sales'!A1*2", A2 = '=Sums!A1' } },
    },
  }
  local files = x.write (book)
  local sheet = files['xl/worksheets/sheet2.xml']
  ok (string.find (sheet, "<f>'Q1_ sales'!A1*2</f>", 1, true), sheet)
  ok (string.find (sheet, '<f>Sums!A1</f>', 1, true), sheet)
  eq (book.sheets[2].cells, { A1 = "='Q1: sales'!A1*2", A2 = '=Sums!A1' })
end)

test ('writing gives a date formula a date format', function ()
  local files = x.write ({
    version = 2,
    sheets = {
      {
        name = 'S',
        cells = { A1 = '=DATE(2026,9,29)', A2 = '=TODAY()+7', A3 = '=1+1' },
        styles = { A2 = { format = 'yyyy-mm-dd' } },
      },
    },
  })
  local styles = read_ok (files).sheets[1].styles or {}
  eq (styles.A1, { format = 'm/d/yyyy' })
  eq (styles.A2, { format = 'yyyy-mm-dd' })
  eq (styles.A3, nil)
end)

test ('writing leaves out merges that overlap', function ()
  local files, warnings = x.write ({
    version = 2,
    sheets = {
      { name = 'S', merges = { 'A1:C2', 'B2:D4', 'E1:E9', '$F$1:G1' } },
    },
  })
  eq (read_ok (files).sheets[1].merges, { 'A1:C2', 'E1:E9', 'F1:G1' })
  eq (warnings, { 'Merged cells in S that overlap others were left out.' })
end)

test ('writing warns once for each kind of thing it leaves out', function ()
  local book = sample_book ()
  book.sheets[1].rules = {
    {
      range = 'B5:B6',
      type = 'compare',
      op = '>',
      value = '0',
      style = { color = '#c62828' },
    },
  }
  book.sheets[2].rules = {
    { range = 'A1', type = 'blank', style = { fill = '#eeeeee' } },
  }
  book.sheets[2].notes = { A1 = 'Check this.' }
  book.sheets[3].validation =
    { { range = 'A2', type = 'list', values = { 'y', 'n' } } }
  book.sheets[3].charts = {
    {
      id = 'c1',
      type = 'column',
      range = 'A1:B5',
      x = 0,
      y = 0,
      w = 400,
      h = 300,
    },
  }
  book.sheets[1].notes = {}
  local _, warnings = x.write (book)
  eq (warnings, {
    'Conditional formats were left out of the Excel file.',
    'Validation rules were left out of the Excel file.',
    'Notes were left out of the Excel file.',
    'Charts were left out of the Excel file.',
  })
end)

test ('writing an empty book still makes a sheet', function ()
  local files = x.write ({ version = 2, sheets = {} })
  ok (string.find (files['xl/workbook.xml'], '<sheet name="Sheet1"', 1, true))
  local book = read_ok (files)
  eq (book.sheets[1].name, 'Sheet1')
  eq (book.sheets[1].cells, {})
end)

test ('writing escapes control characters in text', function ()
  local files = x.write ({
    version = 2,
    sheets = { { name = 'S', cells = { A1 = 'a\rb\1c _x0041_ d' } } },
  })
  ok (
    string.find (
      files['xl/sharedStrings.xml'],
      'a_x000D_b_x0001_c _x005F_x0041_ d',
      1,
      true
    ),
    files['xl/sharedStrings.xml']
  )
  eq ((read_ok (files).sheets[1].cells or {}).A1, 'a\rb\1c _x0041_ d')
end)

---------------------------------------------------------------------------------------------
-- Round trips
---------------------------------------------------------------------------------------------

test ('a book written and read back is the same book', function ()
  local book = sample_book ()
  local back, warnings = read_ok ((x.write (book)))
  eq (warnings, {})
  eq (back, book)
end)

test ('a book read from Excel, written and read again is unchanged', function ()
  local first = read_ok (fixture ())
  local second = read_ok ((x.write (first)))
  eq (second, first)
end)
