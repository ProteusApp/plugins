-- sheet_grid_calc: the arithmetic behind the Sheet app's grid. Where rows and columns sit, which
-- cell a point lands on, which rows to draw, where the fill handle and a dragged block go, the
-- colours a cell's text needs, and the small HTML pieces for the formula helpers. It takes no
-- `app`, draws nothing and calls no host function, so the tests reach all of it.
--
-- The grid is drawn on a canvas inside a scrolling box. The canvas has the column letters along
-- its top, `HEAD_H` pixels tall, and the row numbers down its left, `HEAD_W` pixels wide. A point
-- in the canvas is the sheet's own pixel position plus those two. Frozen rows and columns stay
-- in place while the rest scrolls, so a point on screen maps to the canvas with the scroll
-- offset added only past the frozen part.

---The sizes and frozen panes the grid is laid out with.
---@class Sheet.GridGeo
---@field tops number[] `tops[r]` is the top of row r in the sheet's pixels. `tops[rows + 1]` is the full height.
---@field lefts number[] The same for columns.
---@field rows integer
---@field cols integer
---@field fr integer Frozen rows.
---@field fc integer Frozen columns.
---@field fh number The height of the frozen rows.
---@field fw number The width of the frozen columns.

---What a point in the grid lands on.
---@class Sheet.GridHit
---@field zone 'corner'|'col'|'row'|'cell'
---@field row integer
---@field col integer
---@field past_x integer -1 left of the cells, 1 right of them, 0 over them.
---@field past_y integer -1 above the cells, 1 below them, 0 over them.

---A box in pixels.
---@class Sheet.GridBox
---@field x number
---@field y number
---@field w number
---@field h number

---The statistics the status bar shows for a selection.
---@class Sheet.GridStats
---@field sum number
---@field count integer
---@field average? number
---@field min? number
---@field max? number

---@class Sheet.GridCalcModule
local M = {}

M.HEAD_W = 52
M.HEAD_H = 24
-- The width of the button area on the right of a cell with a list or a filter.
M.BUTTON_W = 18
-- How many colours the references in a formula cycle through.
M.REF_COLORS = 8

---@param text string
---@return string
function M.escape (text)
  return (
    string.gsub (text, '[&<>"\']', {
      ['&'] = '&amp;',
      ['<'] = '&lt;',
      ['>'] = '&gt;',
      ['"'] = '&quot;',
      ["'"] = '&#39;',
    })
  )
end

---The index whose span in `edges` holds `pos`, from 1 to `#edges - 1`. A span of no size is a
---hidden row or column, so the answer steps past it to one that shows.
---@param edges number[]
---@param pos number
---@return integer
function M.index_at (edges, pos)
  local n = #edges - 1
  if n < 1 then
    return 1
  end
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
  local found = lo
  while found < n and edges[found + 1] == edges[found] do
    found = found + 1
  end
  while found > 1 and edges[found + 1] == edges[found] do
    found = found - 1
  end
  return found
end

---The layout of a sheet with its frozen panes.
---@param tops number[]
---@param lefts number[]
---@param fr integer
---@param fc integer
---@return Sheet.GridGeo
function M.geometry (tops, lefts, fr, fc)
  local rows, cols = #tops - 1, #lefts - 1
  fr = math.max (0, math.min (fr, rows))
  fc = math.max (0, math.min (fc, cols))
  return {
    tops = tops,
    lefts = lefts,
    rows = rows,
    cols = cols,
    fr = fr,
    fc = fc,
    fh = tops[fr + 1],
    fw = lefts[fc + 1],
  }
end

---Which cell a point lands on. `x` and `y` count from the top left of the scrolling box's
---visible area, and `sx` and `sy` are its scroll offsets.
---@param geo Sheet.GridGeo
---@param x number
---@param y number
---@param sx number
---@param sy number
---@return Sheet.GridHit
function M.hit (geo, x, y, sx, sy)
  local cx = x - M.HEAD_W
  if cx >= geo.fw then
    cx = cx + sx
  end
  local cy = y - M.HEAD_H
  if cy >= geo.fh then
    cy = cy + sy
  end
  local past_x, past_y = 0, 0
  if cx < 0 then
    past_x = -1
  elseif cx >= geo.lefts[geo.cols + 1] then
    past_x = 1
  end
  if cy < 0 then
    past_y = -1
  elseif cy >= geo.tops[geo.rows + 1] then
    past_y = 1
  end
  local zone = 'cell'
  if x < M.HEAD_W and y < M.HEAD_H then
    zone = 'corner'
  elseif y < M.HEAD_H then
    zone = 'col'
  elseif x < M.HEAD_W then
    zone = 'row'
  end
  return {
    zone = zone,
    row = M.index_at (geo.tops, cy),
    col = M.index_at (geo.lefts, cx),
    past_x = past_x,
    past_y = past_y,
  }
end

---A position along one axis moved from one set of edges to another, such as a chart's top
---after rows grew: it keeps its row and its place inside the row.
---@param from number[]
---@param to number[]
---@param pos number
---@return number
function M.map_pos (from, to, pos)
  if from == to or pos <= 0 then
    return pos
  end
  local i = M.index_at (from, pos)
  local size = (to[i + 1] or to[i]) - to[i]
  return to[i] + math.min (pos - from[i], size)
end

---A block's box on the canvas, headers included.
---@param geo Sheet.GridGeo
---@param rect Sheet.Rect
---@return Sheet.GridBox
function M.canvas_box (geo, rect)
  local r2 = math.min (rect.r2, geo.rows)
  local c2 = math.min (rect.c2, geo.cols)
  local x = M.HEAD_W + geo.lefts[rect.c1]
  local y = M.HEAD_H + geo.tops[rect.r1]
  return {
    x = x,
    y = y,
    w = M.HEAD_W + geo.lefts[c2 + 1] - x,
    h = M.HEAD_H + geo.tops[r2 + 1] - y,
  }
end

---The part of a span of rows or columns that shows on screen, from `a` to `b`, or nil.
---@param edges number[]
---@param a integer
---@param b integer
---@param frozen integer
---@param fsize number
---@param scroll number
---@param head number
---@param size number The visible size of the scrolling box.
---@return number? lo
---@return number? hi
local function span_view (edges, a, b, frozen, fsize, scroll, head, size)
  local lo = head + edges[a] - (a > frozen and scroll or 0)
  local hi = head + edges[b + 1] - (b > frozen and scroll or 0)
  if a > frozen then
    lo = math.max (lo, head + fsize)
  elseif b > frozen then
    -- The block starts frozen, so it shows at least as far as the freeze line.
    hi = math.max (hi, head + fsize)
  end
  lo = math.max (lo, head)
  hi = math.min (hi, size)
  if hi <= lo then
    return nil, nil
  end
  return lo, hi
end

---Where a block shows inside the scrolling box's visible area, cut to what can be seen, or nil
---when none of it shows. `vw` and `vh` are the visible width and height.
---@param geo Sheet.GridGeo
---@param rect Sheet.Rect
---@param sx number
---@param sy number
---@param vw number
---@param vh number
---@return Sheet.GridBox?
function M.view_box (geo, rect, sx, sy, vw, vh)
  local r2 = math.min (rect.r2, geo.rows)
  local c2 = math.min (rect.c2, geo.cols)
  local x1, x2 =
    span_view (geo.lefts, rect.c1, c2, geo.fc, geo.fw, sx, M.HEAD_W, vw)
  local y1, y2 =
    span_view (geo.tops, rect.r1, r2, geo.fr, geo.fh, sy, M.HEAD_H, vh)
  if not x1 or not x2 or not y1 or not y2 then
    return nil
  end
  return { x = x1, y = y1, w = x2 - x1, h = y2 - y1 }
end

---The scroll offset along one axis that brings a span into view, or the same offset when it
---shows already. A frozen span always shows.
---@param edges number[]
---@param a integer
---@param b integer
---@param frozen integer
---@param fsize number
---@param scroll number
---@param room number The visible size, headers left out.
---@return number
local function reveal_axis (edges, a, b, frozen, fsize, scroll, room)
  if a <= frozen then
    return scroll
  end
  local top = edges[a] - fsize
  local bottom = edges[b + 1] - fsize
  local pane = room - fsize
  if top < scroll then
    return math.max (0, top)
  end
  if bottom > scroll + pane then
    return math.max (0, math.min (top, bottom - pane))
  end
  return scroll
end

---The scroll offsets that bring a block into view.
---@param geo Sheet.GridGeo
---@param rect Sheet.Rect
---@param sx number
---@param sy number
---@param vw number
---@param vh number
---@return number sx
---@return number sy
function M.reveal (geo, rect, sx, sy, vw, vh)
  local r2 = math.min (rect.r2, geo.rows)
  local c2 = math.min (rect.c2, geo.cols)
  local nx =
    reveal_axis (geo.lefts, rect.c1, c2, geo.fc, geo.fw, sx, vw - M.HEAD_W)
  local ny =
    reveal_axis (geo.tops, rect.r1, r2, geo.fr, geo.fh, sy, vh - M.HEAD_H)
  return nx, ny
end

---The rows the scrolling part shows, from the top of the view to its bottom.
---@param geo Sheet.GridGeo
---@param sy number
---@param vh number
---@return integer first
---@return integer last
function M.seen_rows (geo, sy, vh)
  local first = M.index_at (geo.tops, geo.fh + sy)
  local last = M.index_at (geo.tops, sy + math.max (0, vh - M.HEAD_H))
  first = math.max (first, geo.fr + 1)
  return first, math.max (first, last)
end

---The scrolling rows to draw: the ones in view plus `margin` more on each side. A sheet of no
---more than `all` rows draws every row.
---@param geo Sheet.GridGeo
---@param sy number
---@param vh number
---@param margin integer
---@param all integer
---@return integer first
---@return integer last
function M.draw_rows (geo, sy, vh, margin, all)
  if geo.rows <= all then
    return geo.fr + 1, geo.rows
  end
  local first, last = M.seen_rows (geo, sy, vh)
  return math.max (geo.fr + 1, first - margin),
    math.min (geo.rows, last + margin)
end

---True when the rows in view come near the edge of the rows drawn, so the table needs drawing
---again.
---@param geo Sheet.GridGeo
---@param sy number
---@param vh number
---@param first integer The first scrolling row drawn.
---@param last integer The last row drawn.
---@param slack integer
---@return boolean
function M.needs_rows (geo, sy, vh, first, last, slack)
  local seen_first, seen_last = M.seen_rows (geo, sy, vh)
  if first > geo.fr + 1 and seen_first - slack < first then
    return true
  end
  return last < geo.rows and seen_last + slack > last
end

---The block the fill handle fills when dragged to a cell: the source stretched down, up, right
---or left, whichever way the cell lies furthest. Nil while the cell is inside the source.
---@param src Sheet.Rect
---@param row integer
---@param col integer
---@return Sheet.Rect?
function M.fill_target (src, row, col)
  local down = row - src.r2
  local up = src.r1 - row
  local right = col - src.c2
  local left = src.c1 - col
  local best = math.max (down, up, right, left)
  if best <= 0 then
    return nil
  end
  if down == best then
    return { r1 = src.r1, c1 = src.c1, r2 = row, c2 = src.c2 }
  elseif up == best then
    return { r1 = row, c1 = src.c1, r2 = src.r2, c2 = src.c2 }
  elseif right == best then
    return { r1 = src.r1, c1 = src.c1, r2 = src.r2, c2 = col }
  end
  return { r1 = src.r1, c1 = col, r2 = src.r2, c2 = src.c2 }
end

---Where a block lands when it is dragged by the cell `grab_row`, `grab_col` to `row`, `col`,
---kept inside a sheet of `rows` by `cols`.
---@param src Sheet.Rect
---@param grab_row integer
---@param grab_col integer
---@param row integer
---@param col integer
---@param rows integer
---@param cols integer
---@return Sheet.Rect
function M.move_target (src, grab_row, grab_col, row, col, rows, cols)
  local h, w = src.r2 - src.r1, src.c2 - src.c1
  local r1 = src.r1 + row - grab_row
  local c1 = src.c1 + col - grab_col
  r1 = math.max (1, math.min (r1, rows - h))
  c1 = math.max (1, math.min (c1, cols - w))
  return { r1 = r1, c1 = c1, r2 = r1 + h, c2 = c1 + w }
end

---How far down a double-click on the fill handle fills: to the last filled row of the column
---beside the block, left or else right, counting from the block's bottom. Nil when there is
---nothing to follow. `filled (row, col)` tells whether a cell holds text.
---@param src Sheet.Rect
---@param rows integer
---@param cols integer
---@param filled fun(row: integer, col: integer): boolean
---@return integer?
function M.fill_down_to (src, rows, cols, filled)
  for _, col in ipairs ({ src.c1 - 1, src.c2 + 1 }) do
    if col >= 1 and col <= cols and filled (src.r2 + 1, col) then
      local last = src.r2 + 1
      while last < rows and filled (last + 1, col) do
        last = last + 1
      end
      return last
    end
  end
  return nil
end

---@param rect Sheet.Rect
---@return string Such as `3R x 2C`.
function M.size_label (rect)
  return (rect.r2 - rect.r1 + 1) .. 'R x ' .. (rect.c2 - rect.c1 + 1) .. 'C'
end

---The sum, count, average, least and greatest of some numbers.
---@param numbers number[]
---@return Sheet.GridStats
function M.stats (numbers)
  ---@type Sheet.GridStats
  local out = { sum = 0, count = #numbers }
  for _, n in ipairs (numbers) do
    out.sum = out.sum + n
    if not out.min or n < out.min then
      out.min = n
    end
    if not out.max or n > out.max then
      out.max = n
    end
  end
  if out.count > 0 then
    out.average = out.sum / out.count
  end
  return out
end

-- Colours ------------------------------------------------------------------------------------

---How light a colour looks, from 0 for black to 1 for white, or nil when it is not `#rgb` or
---`#rrggbb`.
---@param color string
---@return number?
function M.lightness (color)
  local hex = string.match (color, '^#(%x+)$')
  if not hex then
    return nil
  end
  if #hex == 3 then
    hex = string.gsub (hex, '(%x)', '%1%1')
  end
  if #hex ~= 6 and #hex ~= 8 then
    return nil
  end
  local r = tonumber (string.sub (hex, 1, 2), 16) / 255
  local g = tonumber (string.sub (hex, 3, 4), 16) / 255
  local b = tonumber (string.sub (hex, 5, 6), 16) / 255
  return 0.299 * r + 0.587 * g + 0.114 * b
end

---The text colour that reads well on a fill: dark on a light fill and light on a dark one, or
---nil when the fill is not a colour this can read.
---@param fill string
---@return string?
function M.text_on (fill)
  local light = M.lightness (fill)
  if not light then
    return nil
  end
  return light > 0.55 and '#1f2328' or '#f5f6f8'
end

-- How each border line style draws.
---@type table<string, string>
local LINES = {
  thin = '1px solid',
  medium = '2px solid',
  thick = '3px solid',
  dashed = '1px dashed',
  dotted = '1px dotted',
  double = '3px double',
}

---A CSS border for a line style and a colour, or nil for no line. A border with no colour of
---its own takes the text colour, so it shows in every theme.
---@param line? string
---@param color? string
---@return string?
function M.border_css (line, color)
  local how = line and LINES[line]
  if not how then
    return nil
  end
  return how .. ' ' .. (color or 'var(--fg)')
end

---What a drawn cell looks like, for its CSS class.
---@class Sheet.GridCellLook
---@field style Sheet.Style
---@field color? string The text colour.
---@field fill? string The background colour.
---@field align 'left'|'center'|'right'
---@field error? boolean
---@field bottom? string The CSS of the line under the cell.
---@field right? string The CSS of the line right of the cell.
---@field top? string A line along the top that no cell above draws.
---@field left? string A line along the left that no cell to the left draws.

---The CSS declarations for a drawn cell. They go on the cell, and `inner` on the element that
---holds its text.
---@param look Sheet.GridCellLook
---@return string cell
---@return string inner
function M.cell_css (look)
  local st = look.style
  local out = {} ---@type string[]
  local inner = {} ---@type string[]
  if st.bold then
    out[#out + 1] = 'font-weight:700'
  end
  if st.italic then
    out[#out + 1] = 'font-style:italic'
  end
  if st.underline and st.strike then
    out[#out + 1] = 'text-decoration:underline line-through'
  elseif st.underline then
    out[#out + 1] = 'text-decoration:underline'
  elseif st.strike then
    out[#out + 1] = 'text-decoration:line-through'
  end
  if st.size and st.size ~= 13 then
    out[#out + 1] = 'font-size:' .. st.size .. 'px'
  end
  local color = look.color
  if not color and look.fill then
    color = M.text_on (look.fill)
  end
  if color then
    out[#out + 1] = 'color:' .. color
  elseif look.error then
    out[#out + 1] = 'color:var(--danger)'
  end
  if look.fill then
    out[#out + 1] = 'background-color:' .. look.fill
  end
  if look.align ~= 'left' then
    out[#out + 1] = 'text-align:' .. look.align
  end
  if st.valign == 'top' then
    out[#out + 1] = 'vertical-align:top'
  elseif st.valign == 'middle' then
    out[#out + 1] = 'vertical-align:middle'
  end
  if look.bottom then
    out[#out + 1] = 'border-bottom:' .. look.bottom
  end
  if look.right then
    out[#out + 1] = 'border-right:' .. look.right
  end
  if look.top then
    out[#out + 1] = 'border-top:' .. look.top
  end
  if look.left then
    out[#out + 1] = 'border-left:' .. look.left
  end
  if st.wrap then
    inner[#inner + 1] = 'white-space:pre-wrap;overflow-wrap:anywhere'
  end
  return table.concat (out, ';'), table.concat (inner, ';')
end

-- The formula helpers --------------------------------------------------------------------------

---The arguments of a catalog syntax such as `SUMIF(range, criterion, [sum_range])`, in order.
---@param syntax string
---@return string name
---@return string[] args
function M.split_syntax (syntax)
  local name, inside = string.match (syntax, '^([^%(]*)%((.*)%)%s*$')
  if not name or not inside then
    return syntax, {}
  end
  local args = {} ---@type string[]
  local depth, start = 0, 1
  for i = 1, #inside do
    local ch = string.sub (inside, i, i)
    if ch == '[' or ch == '(' then
      depth = depth + 1
    elseif ch == ']' or ch == ')' then
      depth = depth - 1
    elseif ch == ',' and depth == 0 then
      args[#args + 1] = (
        string.match (string.sub (inside, start, i - 1), '^%s*(.-)%s*$')
      )
      start = i + 1
    end
  end
  local last = string.match (string.sub (inside, start), '^%s*(.-)%s*$')
  if last ~= '' or #args > 0 then
    args[#args + 1] = last
  end
  return name, args
end

---Which argument of a syntax is being typed when the caret is in argument `arg`. Past the
---last named argument, a list that ends in `...` repeats its last two, as in
---`SUM(number1, [number2], ...)`.
---@param args string[]
---@param arg integer
---@return integer?
function M.current_arg (args, arg)
  local n = #args
  if n == 0 then
    return nil
  end
  if arg <= n and args[arg] ~= '...' then
    return arg
  end
  if args[n] == '...' then
    local named = n - 1
    if arg <= named then
      return arg
    end
    return named
  end
  return nil
end

---The hint shown while the caret sits inside a function's arguments: its syntax with the
---argument being typed in bold, then its summary.
---@param fn Sheet.CatalogEntry
---@param arg integer
---@return string
function M.hint_html (fn, arg)
  local name, args = M.split_syntax (fn.syntax)
  local at = M.current_arg (args, arg)
  local parts = {} ---@type string[]
  for i, a in ipairs (args) do
    local safe = M.escape (a)
    parts[i] = i == at and ('<b>' .. safe .. '</b>') or safe
  end
  return '<div class="sheet-grid-hs">'
    .. M.escape (name)
    .. '('
    .. table.concat (parts, ', ')
    .. ')</div><div class="sheet-grid-hd">'
    .. M.escape (fn.summary)
    .. '</div>'
end

---The functions whose names start with `prefix`, ignoring case, at most `limit` of them.
---Shorter names come first, so SUM comes before SUBSTITUTE.
---@param catalog Sheet.CatalogEntry[]
---@param prefix string
---@param limit integer
---@return Sheet.CatalogEntry[]
function M.matching (catalog, prefix, limit)
  local up = string.upper (prefix)
  local found = {} ---@type Sheet.CatalogEntry[]
  for _, fn in ipairs (catalog) do
    if string.sub (fn.name, 1, #up) == up then
      found[#found + 1] = fn
    end
  end
  table.sort (found, function (a, b)
    if #a.name ~= #b.name then
      return #a.name < #b.name
    end
    return a.name < b.name
  end)
  local out = {} ---@type Sheet.CatalogEntry[]
  for i = 1, math.min (limit, #found) do
    out[i] = found[i]
  end
  return out
end

---A reference span in formula text, as `sheet_formula.ref_spans` gives it.
---@class Sheet.GridSpan
---@field from integer
---@field to integer The last byte.
---@field area Sheet.Area

---The key that makes two references to the same cells share a colour.
---@param area Sheet.Area
---@return string
function M.area_key (area)
  return string.lower (area.sheet or '')
    .. '!'
    .. (area.r1 or 0)
    .. ','
    .. (area.c1 or 0)
    .. ','
    .. (area.r2 or 0)
    .. ','
    .. (area.c2 or 0)
end

---The colour number, from 1 to `REF_COLORS`, of each reference span. The same cells get the
---same colour.
---@param spans Sheet.GridSpan[]
---@return integer[]
function M.span_colors (spans)
  local by_key = {} ---@type table<string, integer>
  local next_color = 0
  local out = {} ---@type integer[]
  for i, span in ipairs (spans) do
    local key = M.area_key (span.area)
    local n = by_key[key]
    if not n then
      n = next_color % M.REF_COLORS + 1
      next_color = next_color + 1
      by_key[key] = n
    end
    out[i] = n
  end
  return out
end

---The HTML of formula text with each reference in its colour, for the element that lies
---under a text box whose own text does not show. A line break at the very end gets a space
---after it, so the last line keeps its height.
---@param text string
---@param spans Sheet.GridSpan[]
---@param colors integer[]
---@return string
function M.mirror_html (text, spans, colors)
  local out = {} ---@type string[]
  local at = 1
  for i, span in ipairs (spans) do
    if span.from >= at and span.to >= span.from then
      out[#out + 1] = M.escape (string.sub (text, at, span.from - 1))
      out[#out + 1] = '<span class="sheet-grid-rc'
        .. colors[i]
        .. '">'
        .. M.escape (string.sub (text, span.from, span.to))
        .. '</span>'
      at = span.to + 1
    end
  end
  out[#out + 1] = M.escape (string.sub (text, at))
  if string.sub (text, -1) == '\n' then
    out[#out + 1] = ' '
  end
  return table.concat (out)
end

---The block an area of a formula covers on a sheet of `rows` by `cols`. Whole columns and
---whole rows run to the sheet's edge.
---@param area Sheet.Area
---@param rows integer
---@param cols integer
---@return Sheet.Rect?
function M.area_rect (area, rows, cols)
  if not area.r1 and not area.c1 then
    return nil
  end
  local r1 = area.r1 or 1
  local r2 = area.r2 or area.r1 or rows
  local c1 = area.c1 or 1
  local c2 = area.c2 or area.c1 or cols
  return {
    r1 = math.max (1, math.min (r1, r2)),
    c1 = math.max (1, math.min (c1, c2)),
    r2 = math.min (rows, math.max (r1, r2)),
    c2 = math.min (cols, math.max (c1, c2)),
  }
end

---Where a dragged sheet tab drops: the index before which it goes, from the middles of the
---tabs' boxes along the bar.
---@param middles number[]
---@param x number
---@return integer
function M.drop_index (middles, x)
  for i, mid in ipairs (middles) do
    if x < mid then
      return i
    end
  end
  return #middles + 1
end

---The place a dragged sheet moves to, from the index it came from and the gap it dropped in.
---@param from integer
---@param gap integer
---@return integer
function M.moved_index (from, gap)
  if gap > from then
    return gap - 1
  end
  return gap
end

---The rows or columns a command acts on: the selection's, grown to take in hidden ones right
---beside it when it holds none, so Unhide works from the neighbours of a hidden run.
---@param lo integer
---@param hi integer
---@param count integer
---@param hidden fun(i: integer): boolean
---@return integer lo
---@return integer hi
function M.unhide_span (lo, hi, count, hidden)
  for i = lo, hi do
    if hidden (i) then
      return lo, hi
    end
  end
  local a, b = lo, hi
  while a > 1 and hidden (a - 1) do
    a = a - 1
  end
  while b < count and hidden (b + 1) do
    b = b + 1
  end
  return a, b
end

return M
