-- Tests for the Sheet app's grid arithmetic and drawing: where rows and columns sit, what a
-- point lands on, scrolling, the fill handle and dragged blocks, cell classes, the formula
-- helpers' HTML, and the table the grid draws.

local B = require ('sheet_book') --[[@as Sheet.BookModule]]
local calc = require ('sheet_grid_calc') --[[@as Sheet.GridCalcModule]]
local draw = require ('sheet_grid_draw') --[[@as Sheet.GridDrawModule]]
local m = require ('sheet_model') --[[@as Sheet.ModelModule]]

local W, H = calc.HEAD_W, calc.HEAD_H

---Five rows of 24 pixels and four columns of 100, with the given frozen panes.
---@param fr? integer
---@param fc? integer
---@return Sheet.GridGeo
local function geo_of (fr, fc)
  return calc.geometry (
    { 0, 24, 48, 72, 96, 120 },
    { 0, 100, 200, 300, 400 },
    fr or 0,
    fc or 0
  )
end

---@param cells? table<string, string>
---@return Sheet.Sheet
local function sheet_of (cells)
  local book = B.new ()
  local s = book:active_sheet ()
  for addr, text in pairs (cells or {}) do
    local row, col = m.parse_address (addr)
    s:set (row --[[@as integer]], col --[[@as integer]], text)
  end
  return s
end

---@param s Sheet.Sheet
---@return Sheet.GridGeo
local function geo_for (s)
  local lay = s:layout ()
  local fr, fc = s:freeze ()
  return calc.geometry (lay.tops, lay.lefts, fr, fc)
end

---@param s Sheet.Sheet
---@param first? integer
---@param last? integer
---@return string html
---@return Sheet.GridStyles styles
local function table_of (s, first, last)
  local styles = draw.new_styles ()
  local html = draw.table_html (s, geo_for (s), {
    first = first or 1,
    last = last or s.rows,
    styles = styles,
  })
  return html, styles
end

---@param text string
---@param pattern string
---@return integer
local function count (text, pattern)
  local n = 0
  for _ in string.gmatch (text, pattern) do
    n = n + 1
  end
  return n
end

-- Where things sit --------------------------------------------------------------------------

test (
  'index_at finds the span holding a position and steps past hidden ones',
  function ()
    local edges = { 0, 10, 20, 20, 30 }
    eq (calc.index_at (edges, 0), 1)
    eq (calc.index_at (edges, 9.5), 1)
    eq (calc.index_at (edges, 10), 2)
    eq (calc.index_at (edges, 20), 4)
    eq (calc.index_at (edges, -5), 1)
    eq (calc.index_at (edges, 99), 4)
  end
)

test (
  'hit tells headers from cells and adds the scroll only past the frozen panes',
  function ()
    local geo = geo_of (2, 1)
    eq (calc.hit (geo, 10, 10, 0, 0).zone, 'corner')
    local col = calc.hit (geo, W + 150, 10, 0, 0)
    eq ({ col.zone, col.col }, { 'col', 2 })
    local row = calc.hit (geo, 10, H + 30, 0, 0)
    eq ({ row.zone, row.row }, { 'row', 2 })
    -- A frozen cell ignores the scroll.
    local frozen = calc.hit (geo, W + 50, H + 30, 500, 500)
    eq ({ frozen.row, frozen.col }, { 2, 1 })
    -- A scrolling cell adds it.
    local scrolled = calc.hit (geo, W + 150, H + 50, 100, 24)
    eq ({ scrolled.row, scrolled.col }, { 4, 3 })
    eq ({ scrolled.past_x, scrolled.past_y }, { 0, 0 })
    local past = calc.hit (geo, W + 1000, H + 1000, 0, 0)
    eq ({ past.row, past.col, past.past_x, past.past_y }, { 5, 4, 1, 1 })
  end
)

test (
  'canvas_box places a block by the running sums, headers included',
  function ()
    local b = calc.canvas_box (geo_of (), { r1 = 2, c1 = 2, r2 = 3, c2 = 4 })
    eq (b, { x = W + 100, y = H + 24, w = 300, h = 48 })
  end
)

test (
  'view_box cuts a block to what shows, and scrolled rows slide under frozen ones',
  function ()
    local geo = geo_of (1, 0)
    eq (
      calc.view_box (geo, { r1 = 1, c1 = 1, r2 = 1, c2 = 1 }, 0, 50, 500, 500),
      {
        x = W,
        y = H,
        w = 100,
        h = 24,
      }
    )
    -- Row 2 scrolled up by 30 pixels hides under the frozen row 1.
    eq (
      calc.view_box (geo, { r1 = 2, c1 = 1, r2 = 2, c2 = 1 }, 0, 30, 500, 500),
      nil
    )
    local part =
      calc.view_box (geo, { r1 = 2, c1 = 1, r2 = 3, c2 = 1 }, 0, 30, 500, 500)
    eq (part, { x = W, y = H + 24, w = 100, h = 18 })
    -- A block that starts frozen shows down to the freeze line at least.
    local both =
      calc.view_box (geo, { r1 = 1, c1 = 1, r2 = 2, c2 = 1 }, 0, 60, 500, 500)
    eq (both, { x = W, y = H, w = 100, h = 24 })
    eq (
      calc.view_box (geo, { r1 = 5, c1 = 4, r2 = 5, c2 = 4 }, 0, 0, W + 250, 500),
      nil
    )
  end
)

test (
  'reveal scrolls a block into view and leaves frozen ones alone',
  function ()
    local geo = geo_of (1, 1)
    local sx, sy = calc.reveal (
      geo,
      { r1 = 5, c1 = 4, r2 = 5, c2 = 4 },
      0,
      0,
      W + 250,
      H + 60
    )
    eq ({ sx, sy }, { 150, 60 })
    sx, sy = calc.reveal (
      geo,
      { r1 = 2, c1 = 2, r2 = 2, c2 = 2 },
      150,
      72,
      W + 250,
      H + 60
    )
    eq ({ sx, sy }, { 0, 0 })
    sx, sy = calc.reveal (
      geo,
      { r1 = 1, c1 = 1, r2 = 1, c2 = 1 },
      99,
      99,
      W + 250,
      H + 60
    )
    eq ({ sx, sy }, { 99, 99 })
  end
)

test ('draw_rows keeps a margin around the rows in view', function ()
  local tops = { 0 }
  for r = 1, 1000 do
    tops[r + 1] = r * 24
  end
  local geo = calc.geometry (tops, { 0, 100 }, 2, 0)
  eq ({ calc.draw_rows (geo, 0, H + 240, 5, 100) }, { 3, 16 })
  eq ({ calc.draw_rows (geo, 2400, H + 240, 5, 100) }, { 98, 116 })
  eq ({ calc.draw_rows (geo, 0, 500, 5, 5000) }, { 3, 1000 })
  ok (calc.needs_rows (geo, 2400, H + 240, 3, 15, 2))
  ok (not calc.needs_rows (geo, 2400, H + 240, 98, 116, 2))
end)

test ('draw_cols keeps a margin around the columns in view', function ()
  local lefts = { 0 }
  for c = 1, 200 do
    lefts[c + 1] = c * 100
  end
  local geo = calc.geometry ({ 0, 24 }, lefts, 0, 1)
  -- Scrolled to column 51, with 8 columns in view, and the frozen column A.
  local first, last = calc.draw_cols (geo, 5000, W + 100 + 800, 4)
  eq ({ first, last }, { 48, 64 })
  ok (not calc.needs_cols (geo, 5000, W + 900, first, last, 2))
  ok (calc.needs_cols (geo, 5300, W + 900, first, last, 2))
  ok (calc.needs_cols (geo, 4700, W + 900, first, last, 2))
  -- The first scrolling column is never before the frozen ones.
  eq ({ calc.draw_cols (geo, 0, W + 900, 4) }, { 2, 14 })
end)

test ('map_pos keeps a position in its row after rows grow', function ()
  local model_tops = { 0, 24, 48, 72 }
  local grown = { 0, 30, 54, 78 }
  eq (calc.map_pos (model_tops, grown, 10), 10)
  eq (calc.map_pos (model_tops, grown, 30), 36)
  eq (calc.map_pos (model_tops, model_tops, 30), 30)
end)

-- Dragging --------------------------------------------------------------------------------

test (
  'fill_target stretches the source the way the pointer went furthest',
  function ()
    local src = { r1 = 2, c1 = 2, r2 = 3, c2 = 3 }
    eq (calc.fill_target (src, 3, 3), nil)
    eq (calc.fill_target (src, 8, 4), { r1 = 2, c1 = 2, r2 = 8, c2 = 3 })
    eq (calc.fill_target (src, 1, 3), { r1 = 1, c1 = 2, r2 = 3, c2 = 3 })
    eq (calc.fill_target (src, 4, 9), { r1 = 2, c1 = 2, r2 = 3, c2 = 9 })
    eq (calc.fill_target (src, 2, 1), { r1 = 2, c1 = 1, r2 = 3, c2 = 3 })
  end
)

test ('move_target keeps a dragged block inside the sheet', function ()
  local src = { r1 = 2, c1 = 2, r2 = 3, c2 = 3 }
  eq (
    calc.move_target (src, 2, 2, 5, 6, 100, 26),
    { r1 = 5, c1 = 6, r2 = 6, c2 = 7 }
  )
  eq (
    calc.move_target (src, 3, 3, 1, 1, 100, 26),
    { r1 = 1, c1 = 1, r2 = 2, c2 = 2 }
  )
  eq (
    calc.move_target (src, 2, 2, 100, 26, 100, 26),
    { r1 = 99, c1 = 25, r2 = 100, c2 = 26 }
  )
end)

test ('fill_down_to follows the column beside the block', function ()
  local filled =
    { ['2,1'] = true, ['3,1'] = true, ['4,1'] = true, ['5,1'] = true }
  local function has (r, c)
    return filled[r .. ',' .. c] == true
  end
  eq (calc.fill_down_to ({ r1 = 2, c1 = 2, r2 = 2, c2 = 2 }, 100, 26, has), 5)
  eq (calc.fill_down_to ({ r1 = 2, c1 = 4, r2 = 2, c2 = 4 }, 100, 26, has), nil)
end)

test (
  'drop_index and moved_index move a sheet tab by the gap it lands in',
  function ()
    local middles = { 50, 150, 250 }
    eq (calc.drop_index (middles, 10), 1)
    eq (calc.drop_index (middles, 200), 3)
    eq (calc.drop_index (middles, 900), 4)
    eq (calc.moved_index (1, 3), 2)
    eq (calc.moved_index (3, 1), 1)
    eq (calc.moved_index (2, 2), 2)
  end
)

test (
  'unhide_span reaches the hidden rows beside a selection with none',
  function ()
    local hidden = { [3] = true, [4] = true }
    local function h (i)
      return hidden[i] == true
    end
    eq ({ calc.unhide_span (2, 2, 10, h) }, { 2, 4 })
    eq ({ calc.unhide_span (5, 5, 10, h) }, { 3, 5 })
    eq ({ calc.unhide_span (2, 5, 10, h) }, { 2, 5 })
  end
)

test ('the status numbers of a selection', function ()
  eq (calc.size_label ({ r1 = 2, c1 = 1, r2 = 4, c2 = 2 }), '3R x 2C')
  eq (
    calc.stats ({ 4, 1, 7 }),
    { sum = 12, count = 3, average = 4, min = 1, max = 7 }
  )
  eq (calc.stats ({}), { sum = 0, count = 0 })
end)

-- Colours and classes -----------------------------------------------------------------------

test (
  'text_on picks dark text on a light fill and light text on a dark one',
  function ()
    eq (calc.text_on ('#fde68a'), '#1f2328')
    eq (calc.text_on ('#1e3a8a'), '#f5f6f8')
    eq (calc.text_on ('#fff'), '#1f2328')
    eq (calc.text_on ('red'), nil)
  end
)

test ('cell_css turns a look into declarations', function ()
  local cell, inner = calc.cell_css ({
    style = {
      bold = true,
      underline = true,
      strike = true,
      size = 16,
      wrap = true,
      valign = 'middle',
    },
    fill = '#1e3a8a',
    align = 'right',
    bottom = calc.border_css ('medium', '#ff0000'),
  })
  eq (
    cell,
    'font-weight:700;text-decoration:underline line-through;font-size:16px;color:#f5f6f8;'
      .. 'background-color:#1e3a8a;text-align:right;vertical-align:middle;'
      .. 'border-bottom:2px solid #ff0000'
  )
  eq (inner, 'white-space:pre-wrap;overflow-wrap:anywhere')
  local plain = calc.cell_css ({ style = {}, align = 'center', error = true })
  eq (plain, 'color:var(--danger);text-align:center')
  eq (calc.border_css ('thin'), '1px solid var(--fg)')
  eq (calc.border_css ('wavy'), nil)
end)

test (
  'class_for gives equal looks one class and writes each rule once',
  function ()
    local styles = draw.new_styles ()
    local bold = m.intern ({ bold = true }) --[[@as Sheet.Style]]
    local a = draw.class_for (styles, { style = bold, align = 'left' })
    local b = draw.class_for (styles, { style = bold, align = 'left' })
    local c = draw.class_for (styles, { style = bold, align = 'right' })
    eq (a, b)
    ok (a ~= c)
    eq (#styles.rules, 2)
    ok (
      string.find (
        draw.styles_css (styles),
        'td.' .. a .. '{font-weight:700}',
        1,
        true
      )
    )
  end
)

-- The formula helpers ---------------------------------------------------------------------

test ('split_syntax and current_arg find the argument being typed', function ()
  local name, args = calc.split_syntax ('SUMIF(range, criterion, [sum_range])')
  eq (name, 'SUMIF')
  eq (args, { 'range', 'criterion', '[sum_range]' })
  local _, many = calc.split_syntax ('SUM(number1, [number2], ...)')
  eq (calc.current_arg (many, 1), 1)
  eq (calc.current_arg (many, 2), 2)
  eq (calc.current_arg (many, 7), 2)
  local _, none = calc.split_syntax ('NOW()')
  eq (none, {})
  eq (calc.current_arg (none, 1), nil)
end)

test ('hint_html puts the current argument in bold', function ()
  local html = calc.hint_html ({
    name = 'IF',
    category = 'Logic',
    syntax = 'IF(test, [then], [else])',
    summary = 'Picks one of two values.',
  }, 2)
  eq (
    html,
    '<div class="sheet-grid-hs">IF(test, <b>[then]</b>, [else])</div>'
      .. '<div class="sheet-grid-hd">Picks one of two values.</div>'
  )
end)

test ('matching offers the shorter names first', function ()
  ---@type Sheet.CatalogEntry[]
  local catalog = {
    { name = 'SUBSTITUTE', category = 'Text', syntax = '', summary = '' },
    { name = 'SUM', category = 'Math', syntax = '', summary = '' },
    { name = 'SUMIF', category = 'Math', syntax = '', summary = '' },
    { name = 'AVERAGE', category = 'Statistics', syntax = '', summary = '' },
  }
  local names = {} ---@type string[]
  for _, fn in ipairs (calc.matching (catalog, 'su', 2)) do
    names[#names + 1] = fn.name
  end
  eq (names, { 'SUM', 'SUMIF' })
end)

test (
  'mirror_html colours each reference, the same cells in the same colour',
  function ()
    local text = '=A1+B2:C3*A1<"x"\n'
    ---@type Sheet.GridSpan[]
    local spans = {
      { from = 2, to = 3, area = { r1 = 1, c1 = 1, r2 = 1, c2 = 1 } },
      { from = 5, to = 9, area = { r1 = 2, c1 = 2, r2 = 3, c2 = 3 } },
      { from = 11, to = 12, area = { r1 = 1, c1 = 1, r2 = 1, c2 = 1 } },
    }
    local colors = calc.span_colors (spans)
    eq (colors, { 1, 2, 1 })
    eq (
      calc.mirror_html (text, spans, colors),
      '=<span class="sheet-grid-rc1">A1</span>+<span class="sheet-grid-rc2">B2:C3</span>*'
        .. '<span class="sheet-grid-rc1">A1</span>&lt;&quot;x&quot;\n '
    )
  end
)

test (
  'area_rect runs whole columns and rows to the edge of the sheet',
  function ()
    eq (
      calc.area_rect ({ c1 = 2, c2 = 3 }, 100, 26),
      { r1 = 1, c1 = 2, r2 = 100, c2 = 3 }
    )
    eq (
      calc.area_rect ({ r1 = 4, r2 = 5 }, 100, 26),
      { r1 = 4, c1 = 1, r2 = 5, c2 = 26 }
    )
    eq (
      calc.area_rect ({ r1 = 3, c1 = 2, r2 = 3, c2 = 2 }, 100, 26),
      { r1 = 3, c1 = 2, r2 = 3, c2 = 2 }
    )
    eq (calc.area_rect ({}, 100, 26), nil)
  end
)

-- Drawing the table -------------------------------------------------------------------------

test (
  'the table draws one cell per visible column and pads the rows it leaves out',
  function ()
    local s = sheet_of ({ A1 = 'x', B2 = '5' })
    local html = table_of (s, 1, 10)
    eq (count (html, '<tr[ >]'), 1 + 10 + 1)
    ok (
      string.find (
        html,
        'sheet-grid-pad" style="height:' .. (90 * 24) .. 'px',
        1,
        true
      )
    )
    ok (string.find (html, '<div>5</div>', 1, true))
    eq (count (html, '<col '), 27)
  end
)

test ('the cells a formula spills into draw its values', function ()
  local s = sheet_of ({ A1 = '=SEQUENCE(3, 1, 41)' })
  local html = table_of (s, 1, 4)
  for _, n in ipairs ({ '>41<', '>42<', '>43<' }) do
    ok (string.find (html, n, 1, true), n .. ' is drawn')
  end
end)

test ('text does not run over the cells a formula spills into', function ()
  local s = sheet_of ({ A2 = 'a long label that runs on', B1 = '=SEQUENCE(2)' })
  local html = table_of (s, 1, 3)
  eq (count (html, 'sheet%-grid%-o'), 0)
  s:set (1, 2, '')
  eq (count (table_of (s, 1, 3), 'sheet%-grid%-o'), 1)
end)

test ('an icon set draws its icon before the text', function ()
  local s = sheet_of ({ A1 = '1', A2 = '9' })
  s:set_field (
    'rules',
    { { range = 'A1:A2', type = 'icons', icons = 'arrows' } }
  )
  local html = table_of (s, 1, 2)
  ok (
    string.find (
      html,
      '<span class="sheet-grid-ic" style="color:#2b9348">▲</span>9',
      1,
      true
    ),
    html
  )
end)

test ('hidden rows and columns draw nothing', function ()
  local s = sheet_of ({ A1 = 'a', A2 = 'b', B1 = 'c' })
  s:set_hidden ('row', 2, 2, true)
  s:set_hidden ('col', 2, 2, true)
  local html = table_of (s, 1, 3)
  ok (not string.find (html, 'data-item="row:2"', 1, true))
  ok (not string.find (html, 'data-item="col:2"', 1, true))
  ok (not string.find (html, '>b<', 1, true))
  ok (string.find (html, 'sheet-grid-hid', 1, true))
end)

test (
  'a merged block draws once with its spans, and frozen panes split it',
  function ()
    local s = sheet_of ({ A1 = 'Title' })
    s:merge ({ r1 = 1, c1 = 1, r2 = 3, c2 = 2 })
    local html = table_of (s, 1, 5)
    ok (string.find (html, 'rowspan="3" colspan="2"', 1, true))
    eq (count (html, 'Title'), 1)
    s:set_freeze (2, 0)
    html = table_of (s, 1, 5)
    ok (string.find (html, 'rowspan="2" colspan="2"', 1, true))
    eq (count (html, 'colspan="2"'), 2)
    eq (count (html, 'Title'), 1)
  end
)

test (
  'frozen rows and columns carry the classes that make them stick',
  function ()
    local s = sheet_of ({ A1 = 'x' })
    s:set_freeze (1, 1)
    local html = table_of (s, 1, 3)
    ok (
      string.find (
        html,
        'class="sheet-grid-fr sheet-grid-fr1 sheet-grid-frl"',
        1,
        true
      )
    )
    ok (
      string.find (html, 'sheet-grid-fc sheet-grid-fc1 sheet-grid-fcl', 1, true)
    )
    local css = draw.frame_css (geo_for (s))
    ok (string.find (css, 'tr.sheet-grid-fr1>*{top:' .. H .. 'px}', 1, true))
    ok (string.find (css, '.sheet-grid-fc1{left:' .. W .. 'px}', 1, true))
  end
)

test ('long text spills into the empty cells beside it', function ()
  local s = sheet_of ({ A1 = 'A long heading', A2 = 'short', B2 = 'x' })
  local html = table_of (s, 1, 2)
  ok (string.find (html, 'sheet-grid-o', 1, true))
  ok (string.find (html, '<div style="width:', 1, true))
  -- A2 has a neighbour, so it does not spill.
  ok (string.find (html, '<td class="sheet%-grid%-s%d+"><div>short</div>'))
end)

test ('a border on the cell below draws as the line under this one', function ()
  local s = sheet_of ({ A2 = 'x' })
  s:set_borders ({ r1 = 2, c1 = 1, r2 = 2, c2 = 1 }, 'top', 'thick', '#ff0000')
  local _, styles = table_of (s, 1, 3)
  ok (
    string.find (
      draw.styles_css (styles),
      'border-bottom:3px solid #ff0000',
      1,
      true
    )
  )
end)

test ('notes, lists and filter headers get their markers', function ()
  local s = sheet_of ({ A1 = 'Head', A2 = 'x' })
  s:set_note (2, 1, 'A note')
  local ops = require ('sheet_ops') --[[@as Sheet.OpsModule]]
  ops.add_validation (s, { range = 'B2', type = 'list', values = { 'a', 'b' } })
  ops.set_filter (s, { r1 = 1, c1 = 1, r2 = 2, c2 = 1 })
  local html = table_of (s, 1, 3)
  ok (string.find (html, 'sheet-grid-nt', 1, true))
  ok (string.find (html, 'sheet-grid-dd', 1, true))
  ok (string.find (html, 'sheet-grid-fb', 1, true))
end)

test (
  'rows grow for a big font unless they have a height of their own',
  function ()
    local s =
      sheet_of ({ A1 = 'Big', A2 = 'Big too', A3 = 'small', A4 = 'one\ntwo' })
    s:set_style ({ r1 = 1, c1 = 1, r2 = 2, c2 = 1 }, { size = 20 })
    s:set_height (2, 40)
    local grown = draw.auto_heights (s)
    eq (grown, { [1] = 30, [4] = 38 })
    local tops = draw.grow_tops ({ 0, 24, 64, 88 }, grown)
    eq (tops, { 0, 30, 70, 94 })
  end
)

test (
  'row heights follow only the cells written since they were last worked out',
  function ()
    local s = sheet_of ()
    s:set_style ({ r1 = 1, c1 = 1, r2 = 200, c2 = 1 }, { wrap = true })
    for row = 1, 200 do
      s:set (row, 1, 'word ' .. row)
    end
    local measured = 0
    ---@param text string
    ---@return number
    local function measure (text)
      measured = measured + 1
      -- Two lines of 16 pixels for long text, one for short.
      return #text > 20 and 36 or 20
    end
    eq (draw.auto_heights (s, measure), {})
    eq (measured, 200)
    -- Wrapped text grows its row as it is typed, and only that cell is measured again.
    s:set (7, 1, 'a much longer text that wraps')
    eq (draw.auto_heights (s, measure), { [7] = 37 })
    eq (measured, 201)
    -- Nothing written, nothing measured.
    draw.auto_heights (s, measure)
    eq (measured, 201)
    -- A big font and line breaks still grow rows, and clearing the text shrinks it back.
    s:set (9, 2, 'one\ntwo')
    s:set (7, 1, '')
    eq (draw.auto_heights (s, measure), { [9] = 38 })
    eq (measured, 201)
    -- A new column width may change every wrapped row, so they are all measured again.
    s:set_width (1, 300)
    draw.auto_heights (s, measure)
    eq (measured, 400)
    -- Without a measure, wrapped text is guessed from its length.
    s:set (3, 1, string.rep ('long words ', 30))
    local grown = draw.auto_heights (s)
    ok ((grown[3] or 0) > 24, 'the row grew')
  end
)

test ('columns are drawn near the view, with padding for the rest', function ()
  local s = sheet_of ({ A1 = 'frozen', E1 = 'shown', Z1 = 'far' })
  s:set_freeze (0, 1)
  local geo = geo_for (s)
  local parts = draw.table_parts (s, geo, {
    first = 1,
    last = 5,
    col_first = 4,
    col_last = 8,
    styles = draw.new_styles (),
  })
  eq ({ parts.col_first, parts.col_last }, { 4, 8 })
  -- The header, the frozen A, a pad for B and C, D to H, and a pad for I to Z.
  eq (count (parts.cols, '<col '), 1 + 1 + 1 + 5 + 1)
  ok (string.find (parts.cols, 'width:200px', 1, true), 'B and C pad')
  ok (string.find (parts.cols, 'width:1800px', 1, true), 'I to Z pad')
  ok (
    string.find (parts.head, '>A<', 1, true)
      and string.find (parts.head, '>H<', 1, true)
  )
  ok (
    not string.find (parts.head, '>C<', 1, true)
      and not string.find (parts.head, '>Z<', 1, true)
  )
  local row1 = parts.rows[1]
  eq (row1.key, 'r1')
  ok (
    string.find (row1.html, 'frozen', 1, true)
      and string.find (row1.html, 'shown', 1, true)
  )
  ok (not string.find (row1.html, 'far', 1, true))
  eq (count (row1.html, '<td'), 1 + 1 + 5 + 1)
  eq (parts.width, W + 2600)
  -- A merged block the window cuts is drawn whole.
  s:merge ({ r1 = 2, c1 = 3, r2 = 2, c2 = 5 })
  parts = draw.table_parts (s, geo_for (s), {
    first = 1,
    last = 5,
    col_first = 4,
    col_last = 8,
    styles = draw.new_styles (),
  })
  eq (parts.col_first, 3)
end)

test ('only the rows that changed are written again', function ()
  local s = sheet_of ({ A1 = 'one', A2 = 'two', A3 = 'three' })
  local styles = draw.new_styles ()
  ---@return Sheet.GridParts
  local function parts_of ()
    return draw.table_parts (s, geo_for (s), {
      first = 1,
      last = 10,
      styles = styles,
    })
  end
  local drawn, order = {}, {} ---@type Sheet.GridDrawn, string[]
  ---@param parts Sheet.GridParts
  ---@return Sheet.GridRowDiff
  local function apply (parts)
    local diff = draw.diff_rows (drawn, order, parts.rows)
    for _, part in ipairs (diff.write) do
      drawn[part.key] = part
    end
    for _, key in ipairs (diff.drop) do
      drawn[key] = nil
    end
    order = diff.order
    return diff
  end
  local first = apply (parts_of ())
  eq (#first.write, 11)
  ok (first.moved)
  local again = apply (parts_of ())
  eq (#again.write, 0)
  ok (not again.moved)
  s:set (2, 1, 'TWO')
  local edit = apply (parts_of ())
  eq (#edit.write, 1)
  eq (edit.write[1].key, 'r2')
  ok (not edit.moved)
  -- Scrolling down drops the rows above and pads them.
  local scrolled = draw.diff_rows (
    drawn,
    order,
    draw.table_parts (s, geo_for (s), {
      first = 4,
      last = 12,
      styles = styles,
    }).rows
  )
  ok (scrolled.moved)
  eq (scrolled.drop, { 'r1', 'r2', 'r3' })
end)

test ('charts go in the pane of their top left corner', function ()
  local s = sheet_of ()
  s:set_freeze (2, 0)
  local ops = require ('sheet_ops') --[[@as Sheet.OpsModule]]
  ops.add_chart (s, {
    id = 'top',
    type = 'column',
    range = 'A1:B3',
    x = 10,
    y = 10,
    w = 100,
    h = 80,
  })
  ops.add_chart (s, {
    id = 'low',
    type = 'column',
    range = 'A1:B3',
    x = 10,
    y = 200,
    w = 100,
    h = 80,
  })
  local panes = draw.charts_html (s, geo_for (s), function ()
    return '<svg></svg>'
  end, 'low')
  ok (string.find (panes.tr, 'chart:top', 1, true))
  ok (string.find (panes.br, 'chart:low', 1, true))
  eq (count (panes.br, 'sheet%-grid%-hdl%-'), 8)
end)

test ('drag_box moves and resizes a chart and keeps a smallest size', function ()
  local box = { x = 100, y = 100, w = 200, h = 150 }
  eq (
    draw.drag_box (box, 'move', 20, -500, 60),
    { x = 120, y = 0, w = 200, h = 150 }
  )
  eq (
    draw.drag_box (box, 'se', 30, 40, 60),
    { x = 100, y = 100, w = 230, h = 190 }
  )
  eq (
    draw.drag_box (box, 'nw', 500, 0, 60),
    { x = 240, y = 100, w = 60, h = 150 }
  )
end)
