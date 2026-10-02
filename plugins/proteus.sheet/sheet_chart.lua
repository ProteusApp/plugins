-- sheet_chart: charts for the Sheet app, drawn as SVG text.
--
-- `data_from` reads a block of cell values into categories and series. `render` draws a column,
-- bar, line, area, pie, doughnut or scatter chart from them as one SVG string. The module draws
-- nothing on screen and calls no host function.
--
-- Text and lines use the theme's CSS variables, so a chart follows the light and dark themes.
-- A pure module cannot measure text, so every text width here is an estimate from the number of
-- characters.

---@alias Sheet.ChartKind 'column'|'bar'|'line'|'area'|'pie'|'doughnut'|'scatter'

---A chart on a sheet, as the workbook file keeps it.
---@class Sheet.ChartSpec
---@field id string
---@field type Sheet.ChartKind
---@field stacked? boolean
---@field range string The cells the chart reads, such as `A4:C10`.
---@field series_in? 'cols'|'rows'
---@field headers? boolean
---@field title? string
---@field legend? 'top'|'bottom'|'right'|'none'
---@field x_title? string The title of the category axis, or the x axis of a scatter chart.
---@field y_title? string The title of the value axis.
---@field colors? string[] Colours that replace the palette's, in series order.
---@field x number
---@field y number
---@field w number
---@field h number

---@class Sheet.ChartSeries
---@field name string
---@field values (number|nil)[] One entry per category. Nil is a missing number.

---@class Sheet.ChartData
---@field categories string[]
---@field series Sheet.ChartSeries[]
---@field numbers? (number|nil)[] The category cells as numbers, when they held numbers.

---The working out behind `data_from`.
---@class Sheet.ChartPlan
---@field rows integer
---@field cols integer
---@field by_rows boolean
---@field ni integer How many lines run along the categories.
---@field nj integer How many lines run along the series.
---@field at fun(i: integer, j: integer): Sheet.Value
---@field labels boolean
---@field headers boolean

---Where a chart's parts sit in the block it reads. See `layout_of`.
---@class Sheet.ChartLayout
---@field rows integer
---@field cols integer
---@field by_rows boolean True when each series runs along a row.
---@field labels boolean True when the first column, or row with `by_rows`, holds the categories.
---@field headers boolean True when the first row, or column with `by_rows`, names the series.
---@field series integer[] The column of each series in the block, or its row with `by_rows`.

---@class Sheet.ChartType
---@field id Sheet.ChartKind
---@field label string
---@field icon string A Lucide icon name.

---@class Sheet.ChartDataOptions
---@field series_in? 'cols'|'rows'
---@field headers? boolean True when the first row names the series, or the first column when the series run along rows. Nil works it out.
---@field labels? boolean True when the first column holds the categories, or the first row when the series run along rows. Nil works it out.
---@field format? fun(n: number): string Shows number categories as text.

---@class Sheet.ChartOptions
---@field width number
---@field height number
---@field format? fun(n: number): string Shows values on the value axis and in tooltips.

---A legend entry.
---@class Sheet.ChartKey
---@field name string
---@field color string
---@field shape 'box'|'line'|'dot'

---The SVG being written, and the space still free for the plot.
---@class Sheet.ChartCanvas
---@field out string[]
---@field width number
---@field height number
---@field left number
---@field right number
---@field top number
---@field bottom number
---@field small boolean True when the legend and the axis titles do not fit.
---@field tiny boolean True when the tick and category labels do not fit either.
---@field format? fun(n: number): string
---@field colors string[]

---@class Sheet.ChartPoint
---@field series integer
---@field index integer
---@field x number
---@field y number

---@class Sheet.ChartSlice
---@field index integer
---@field value number

---@class Sheet.ChartModule
---@field types Sheet.ChartType[]
---@field palette string[]
local M = {}

M.types = {
  { id = 'column', label = 'Column', icon = 'chart-column' },
  { id = 'bar', label = 'Bar', icon = 'chart-bar' },
  { id = 'line', label = 'Line', icon = 'chart-line' },
  { id = 'area', label = 'Area', icon = 'chart-area' },
  { id = 'pie', label = 'Pie', icon = 'chart-pie' },
  { id = 'doughnut', label = 'Doughnut', icon = 'donut' },
  { id = 'scatter', label = 'Scatter', icon = 'chart-scatter' },
}

-- These eight read on both the light and the dark theme, and each colour stays apart from its
-- neighbour for colour-blind readers too. The order matters for that, so keep it.
M.palette = {
  '#3987e5',
  '#d95926',
  '#199e70',
  '#c98500',
  '#d55181',
  '#008300',
  '#9085e9',
  '#e66767',
}

local PAD = 8
local FONT = 11
local TITLE_FONT = 13
-- The width of an average character, as a share of the font size.
local CHAR = 0.6
local WIDE = 1.0
local LEGEND_ROW = 18
local SWATCH = 10
local BAR_MAX = 24
local GAP = 2
local RADIUS = 4
-- A line shows a dot on each point when it has fewer points than this.
local DOT_LIMIT = 30
-- Past this many points, a line or an area gives no hover targets, to keep the SVG small.
local HIT_LIMIT = 1000
local LN10 = math.log (10)
local ELLIPSIS = '…'
local LABELS = ' style="fill:var(--fg-muted)"'

---@type table<string, Sheet.ChartType>
local BY_ID = {}
for _, t in ipairs (M.types) do
  BY_ID[t.id] = t
end

---------------------------------------------------------------------------------------------
-- Numbers and text
---------------------------------------------------------------------------------------------

---@param x number
---@return number
local function log10 (x)
  return math.log (x) / LN10
end

---@param n number
---@return boolean
local function finite (n)
  return n == n and n ~= math.huge and n ~= -math.huge
end

---Writes a coordinate with at most two decimals.
---@param n number
---@return string
local function num (n)
  local s = string.gsub (string.format ('%.2f', n), '%.?0+$', '')
  if s == '-0' then
    return '0'
  end
  return s
end

---Shows a number the way a cell shows it in General format.
---@param n number
---@return string
local function general (n)
  if not finite (n) then
    return '#NUM!'
  end
  if n == math.floor (n) and math.abs (n) < 1e15 then
    return string.format ('%d', n)
  end
  return (string.gsub (string.format ('%.10g', n), 'e', 'E'))
end

---The fewest decimals that show every multiple of `step` exactly.
---@param step number
---@return integer
local function decimals (step)
  for d = 0, 12 do
    local x = step * 10 ^ d
    local whole = math.floor (x + 0.5)
    if whole >= 1 and math.abs (x - whole) < 1e-6 * x then
      return d
    end
  end
  return 12
end

---Shows an axis tick in a short form such as `1.2k`, `3.4M` or `0.25`. `step` is the distance
---between ticks, which sets how many decimals the label needs.
---@param n number
---@param step? number
---@return string
function M.short (n, step)
  if not finite (n) then
    return general (n)
  end
  if n == 0 then
    return '0'
  end
  local a = math.abs (n)
  local unit, suffix = 1, ''
  if a >= 1e12 then
    unit, suffix = 1e12, 'T'
  elseif a >= 1e9 then
    unit, suffix = 1e9, 'B'
  elseif a >= 1e6 then
    unit, suffix = 1e6, 'M'
  elseif a >= 1e3 then
    unit, suffix = 1e3, 'k'
  end
  local d ---@type integer
  if step and step > 0 then
    d = decimals (step / unit)
  else
    d = math.max (0, 2 - math.floor (log10 (a / unit) + 1e-9))
  end
  local s = string.format ('%.' .. d .. 'f', n / unit)
  if d > 0 then
    s = string.gsub (string.gsub (s, '0+$', ''), '%.$', '')
  end
  if s == '-0' then
    s = '0'
  end
  return s .. suffix
end

local ENTITIES = {
  ['&'] = '&amp;',
  ['<'] = '&lt;',
  ['>'] = '&gt;',
  ['"'] = '&quot;',
  ["'"] = '&#39;',
}

---@param s string
---@return string
local function esc (s)
  return (string.gsub (s, '[&<>"\']', ENTITIES))
end

---Puts text on one line. Line breaks and other control characters become spaces, which also
---keeps them out of the SVG, where most of them are not valid.
---@param s any
---@return string
local function clean (s)
  if s == nil then
    return ''
  end
  return (string.gsub (tostring (s), '%c', ' '))
end

---@param s any
---@return string
local function trim (s)
  return (string.match (clean (s), '^%s*(.-)%s*$'))
end

---The width of one character, from its first byte. Characters from U+3000 on, such as
---Chinese and Japanese, are about twice as wide as Latin ones.
---@param b integer
---@return integer size The bytes the character takes.
---@return number width As a share of the font size.
local function char_at (b)
  if b < 0x80 then
    return 1, CHAR
  elseif b >= 0xF0 then
    return 4, WIDE
  elseif b >= 0xE0 then
    return 3, b >= 0xE3 and WIDE or CHAR
  elseif b >= 0xC0 then
    return 2, CHAR
  end
  return 1, 0
end

---@param s string
---@param size number
---@return number
local function width_of (s, size)
  local w, i = 0, 1
  while i <= #s do
    local n, cw = char_at (string.byte (s, i))
    w = w + cw
    i = i + n
  end
  return w * size
end

---Cuts text short with an ellipsis so it fits in `max` pixels.
---@param s string
---@param max number
---@param size number
---@return string
local function clip (s, max, size)
  if width_of (s, size) <= max then
    return s
  end
  local room = max - width_of (ELLIPSIS, size)
  if room < 0 then
    return ''
  end
  local w, i = 0, 1
  while i <= #s do
    local n, cw = char_at (string.byte (s, i))
    if (w + cw) * size > room then
      break
    end
    w = w + cw
    i = i + n
  end
  return string.sub (s, 1, i - 1) .. ELLIPSIS
end

---Shows any cell value as text.
---@param v Sheet.Value
---@param format? fun(n: number): string
---@return string
local function value_text (v, format)
  local t = type (v)
  if v == nil then
    return ''
  elseif t == 'number' then
    local n = v --[[@as number]]
    if format then
      return clean (format (n))
    end
    return general (n)
  elseif t == 'string' then
    return clean (v)
  elseif t == 'boolean' then
    return v and 'TRUE' or 'FALSE'
  end
  return clean ((v --[[@as Sheet.Error]]).code)
end

---------------------------------------------------------------------------------------------
-- Ticks
---------------------------------------------------------------------------------------------

---Tick values for an axis from `min` to `max`, about `count` of them, a tidy step apart: 1, 2
---or 5 times a power of ten. The first tick is at or below `min` and the last at or above
---`max`. A single value gets an axis that reaches zero.
---@param min number
---@param max number
---@param count? integer
---@return number[] ticks
---@return number step
function M.nice_ticks (min, max, count)
  count = math.max (2, math.floor (count or 5))
  if not finite (min) or not finite (max) then
    return { 0, 1 }, 1
  end
  if min > max then
    min, max = max, min
  end
  if min == max then
    if min > 0 then
      min = 0
    elseif min < 0 then
      max = 0
    else
      max = 1
    end
  end
  local raw = (max - min) / count
  local step = 10 ^ math.floor (log10 (raw) + 1e-9)
  local err = raw / step
  if err >= math.sqrt (50) then
    step = step * 10
  elseif err >= math.sqrt (10) then
    step = step * 5
  elseif err >= math.sqrt (2) then
    step = step * 2
  end
  local first = math.floor (min / step + 1e-9)
  local last = math.ceil (max / step - 1e-9)
  local ticks = {} ---@type number[]
  for i = first, last do
    -- Twelve digits drop the float noise, so 3 * 0.1 gives 0.3.
    ticks[#ticks + 1] = tonumber (string.format ('%.12g', i * step)) --[[@as number]]
  end
  return ticks, step
end

---Widens a range to reach zero when the data keeps at least half of the axis: when the value
---nearest zero is under half the one furthest from it.
---@param lo number
---@param hi number
---@return number lo
---@return number hi
local function with_zero (lo, hi)
  if lo > 0 and lo < hi / 2 then
    return 0, hi
  elseif hi < 0 and hi > lo / 2 then
    return lo, 0
  end
  return lo, hi
end

---Picks ticks for an axis `length` pixels long, as many as fit. `room` says how many pixels
---each tick needs.
---@param lo number
---@param hi number
---@param length number
---@param per number Pixels per tick to aim for.
---@param room fun(ticks: number[], step: number): number
---@return number[] ticks
---@return number step
local function fit_ticks (lo, hi, length, per, room)
  local count = math.max (2, math.floor (length / per))
  while true do
    local ticks, step = M.nice_ticks (lo, hi, count)
    if count <= 2 or length / (#ticks - 1) >= room (ticks, step) then
      return ticks, step
    end
    count = count - 1
  end
end

---Maps a value between the first and the last tick to a pixel between `a` and `b`.
---@param ticks number[]
---@param a number
---@param b number
---@return fun(v: number): number
local function scale (ticks, a, b)
  local lo, hi = ticks[1], ticks[#ticks]
  return function (v)
    return a + (v - lo) / (hi - lo) * (b - a)
  end
end

---Puts a one-pixel line on the pixel grid, so it draws sharp.
---@param p number
---@return number
local function crisp (p)
  return math.floor (p) + 0.5
end

---------------------------------------------------------------------------------------------
-- Reading a range
---------------------------------------------------------------------------------------------

---How a block of values splits into categories and series, before any value is read: its
---size once blank rows and columns at the end are dropped, which way the series run, and
---whether the first row and column hold headings. Nil for a block with nothing in it.
---@param values Sheet.Value[][]
---@param opts Sheet.ChartDataOptions
---@return Sheet.ChartPlan?
local function plan_of (values, opts)
  local rows, cols = 0, 0
  for r, row in pairs (values) do
    if math.type (r) == 'integer' and type (row) == 'table' then
      rows = math.max (rows, r)
      for c in pairs (row) do
        if math.type (c) == 'integer' then
          cols = math.max (cols, c)
        end
      end
    end
  end

  ---@param r integer
  ---@param c integer
  ---@return Sheet.Value
  local function cell (r, c)
    local row = values[r]
    if type (row) ~= 'table' then
      return nil
    end
    local v = row[c]
    if type (v) == 'string' and not string.find (v, '%S') then
      return nil
    end
    return v
  end

  ---@param r integer
  ---@return boolean
  local function blank_row (r)
    for c = 1, cols do
      if cell (r, c) ~= nil then
        return false
      end
    end
    return true
  end

  ---@param c integer
  ---@return boolean
  local function blank_col (c)
    for r = 1, rows do
      if cell (r, c) ~= nil then
        return false
      end
    end
    return true
  end

  -- A chart often reads more rows than hold data, to make room for more.
  while rows > 0 and blank_row (rows) do
    rows = rows - 1
  end
  while cols > 0 and blank_col (cols) do
    cols = cols - 1
  end
  if rows == 0 or cols == 0 then
    return nil
  end

  local by_rows = opts.series_in == 'rows'
  if opts.series_in == nil then
    by_rows = cols > rows
  end
  -- From here on, i counts along the categories and j along the series.
  local ni, nj = rows, cols
  if by_rows then
    ni, nj = cols, rows
  end

  ---@param i integer
  ---@param j integer
  ---@return Sheet.Value
  local function at (i, j)
    if by_rows then
      return cell (j, i)
    end
    return cell (i, j)
  end

  local labels = opts.labels
  if labels == nil then
    labels = false
    if nj >= 2 then
      for i = 2, ni do
        if type (at (i, 1)) == 'string' then
          labels = true
          break
        end
      end
      -- A blank top left corner over text headings marks the first column as the categories,
      -- even when it holds numbers or dates.
      if not labels and at (1, 1) == nil and ni >= 2 then
        local heads = false
        for j = 2, nj do
          if type (at (1, j)) == 'string' then
            heads = true
          end
        end
        local below = false
        for i = 2, ni do
          if at (i, 1) ~= nil then
            below = true
          end
        end
        labels = heads and below
      end
    end
  else
    labels = labels and nj >= 2
  end

  local headers = opts.headers
  if headers == nil then
    headers = false
    if ni >= 2 then
      for j = labels and 2 or 1, nj do
        if type (at (1, j)) == 'string' then
          headers = true
          break
        end
      end
    end
  else
    headers = headers and ni >= 2
  end

  ---@type Sheet.ChartPlan
  return {
    rows = rows,
    cols = cols,
    by_rows = by_rows,
    ni = ni,
    nj = nj,
    at = at,
    labels = labels,
    headers = headers,
  }
end

---Reads a block of cell values into categories and series. `values` holds rows, top to
---bottom. Text, booleans and errors in the data count as missing numbers.
---@param values Sheet.Value[][]
---@param opts? Sheet.ChartDataOptions
---@return Sheet.ChartData
function M.data_from (values, opts)
  opts = opts or {}
  local plan = plan_of (values, opts)
  if not plan then
    return { categories = {}, series = {} }
  end
  local ni, nj, at = plan.ni, plan.nj, plan.at
  local labels, headers = plan.labels, plan.headers
  local first_i = headers and 2 or 1
  local first_j = labels and 2 or 1

  local categories = {} ---@type string[]
  local numbers = {} ---@type (number|nil)[]
  local all_numbers = labels
  local any_number = false
  for i = first_i, ni do
    local k = i - first_i + 1
    if labels then
      local v = at (i, 1)
      categories[k] = value_text (v, opts.format)
      if type (v) == 'number' then
        numbers[k] = v --[[@as number]]
        any_number = true
      elseif v ~= nil then
        all_numbers = false
      end
    else
      categories[k] = tostring (k)
    end
  end

  local series = {} ---@type Sheet.ChartSeries[]
  for j = first_j, nj do
    local vals = {} ---@type (number|nil)[]
    local used = headers and at (1, j) ~= nil
    for i = first_i, ni do
      local v = at (i, j)
      if v ~= nil then
        used = true
      end
      if
        type (v) == 'number' and finite (v --[[@as number]])
      then
        vals[i - first_i + 1] = v --[[@as number]]
      end
    end
    -- A column with nothing in it, not even a heading, is a gap in the range, not a series.
    if used then
      local name = headers and value_text (at (1, j)) or ''
      if name == '' then
        name = 'Series ' .. (#series + 1)
      end
      series[#series + 1] = { name = name, values = vals }
    end
  end

  ---@type Sheet.ChartData
  local data = { categories = categories, series = series }
  if all_numbers and any_number then
    data.numbers = numbers
  end
  return data
end

---Where the parts of a chart sit in the block it reads, counting from 1 in the block: the
---rows and columns that hold data, which way the series run, whether the first row and
---column hold headings, and the line of the block each series reads. An Excel file names
---each series by its cells, so this is what it writes.
---@param values Sheet.Value[][]
---@param opts? Sheet.ChartDataOptions
---@return Sheet.ChartLayout?
function M.layout_of (values, opts)
  local plan = plan_of (values, opts or {})
  if not plan then
    return nil
  end
  local first_i = plan.headers and 2 or 1
  local series = {} ---@type integer[]
  for j = plan.labels and 2 or 1, plan.nj do
    local used = plan.headers and plan.at (1, j) ~= nil
    for i = first_i, plan.ni do
      if plan.at (i, j) ~= nil then
        used = true
      end
    end
    if used then
      series[#series + 1] = j
    end
  end
  ---@type Sheet.ChartLayout
  return {
    rows = plan.rows,
    cols = plan.cols,
    by_rows = plan.by_rows,
    labels = plan.labels,
    headers = plan.headers,
    series = series,
  }
end

---------------------------------------------------------------------------------------------
-- Writing SVG
---------------------------------------------------------------------------------------------

---Fills `$1`, `$2` and so on in a piece of SVG. Numbers get at most two decimals, and text is
---escaped.
---@param template string
---@param ... string|number
---@return string
local function svg (template, ...)
  local args = { ... }
  return (
    string.gsub (template, '%$(%d+)', function (k)
      local v = args[tonumber (k)]
      if type (v) == 'number' then
        return num (v)
      end
      return esc (tostring (v))
    end)
  )
end

---@param c Sheet.ChartCanvas
---@param s string
local function add (c, s)
  c.out[#c.out + 1] = s
end

---A tooltip, as the first child of the mark it belongs to.
---@param s string
---@return string
local function tip (s)
  return '<title>' .. esc (clean (s)) .. '</title>'
end

---Writes a text element. `s` is plain text, and this escapes it.
---@param c Sheet.ChartCanvas
---@param x number
---@param y number
---@param s string
---@param anchor? 'middle'|'end'
---@param attrs? string More attributes, each with a leading space.
local function text (c, x, y, s, anchor, attrs)
  local align = anchor and (' text-anchor="' .. anchor .. '"') or ''
  local open = svg ('<text x="$1" y="$2"', x, y) .. align .. (attrs or '')
  add (c, open .. '>' .. esc (s) .. '</text>')
end

---The colour of series or slice `i`.
---@param c Sheet.ChartCanvas
---@param i integer
---@return string
local function color (c, i)
  local own = c.colors[i]
  if type (own) == 'string' and own ~= '' then
    return own
  end
  return M.palette[(i - 1) % #M.palette + 1]
end

---How bright a colour looks, from 0 for black to 1 for white, as the WCAG contrast rules
---measure it.
---@param hex string Six hex digits.
---@return number
local function luminance (hex)
  local sum = 0
  for i, weight in ipairs ({ 0.2126, 0.7152, 0.0722 }) do
    local v = tonumber (string.sub (hex, i * 2 - 1, i * 2), 16) / 255
    if v <= 0.04045 then
      v = v / 12.92
    else
      v = ((v + 0.055) / 1.055) ^ 2.4
    end
    sum = sum + weight * v
  end
  return sum
end

local INK = '#1b1d23'
local INK_LUMINANCE = luminance ('1b1d23')

---White or near black, whichever has more contrast on a fill colour.
---@param fill string
---@return string
local function ink_on (fill)
  local hex = string.match (fill, '^#(%x+)$')
  if hex and #hex == 3 then
    hex = string.gsub (hex, '.', '%0%0')
  end
  if not hex or #hex ~= 6 then
    return '#ffffff'
  end
  local l = luminance (hex)
  local on_white = 1.05 / (l + 0.05)
  local on_ink = (l + 0.05) / (INK_LUMINANCE + 0.05)
  return on_ink > on_white and INK or '#ffffff'
end

---Writes a short message in the middle of the free space, in place of a chart.
---@param c Sheet.ChartCanvas
---@param s string
local function message (c, s)
  text (
    c,
    (c.left + c.right) / 2,
    (c.top + c.bottom) / 2 + FONT * 0.35,
    clip (s, c.right - c.left, FONT + 1),
    'middle',
    ' class="sc-message" style="fill:var(--fg-muted);font-size:12px"'
  )
end

---The path of a bar with its far end rounded. `side` names the far end, and nil leaves every
---corner square.
---@param x number
---@param y number
---@param w number
---@param h number
---@param side? 'top'|'bottom'|'left'|'right'
---@return string
local function bar_path (x, y, w, h, side)
  local r = 0
  if side == 'top' or side == 'bottom' then
    r = math.min (RADIUS, w / 2, h)
  elseif side then
    r = math.min (RADIUS, h / 2, w)
  end
  local x2, y2 = x + w, y + h
  if r < 0.5 then
    return svg ('M$1 $2H$3V$4H$1Z', x, y, x2, y2)
  elseif side == 'top' then
    return svg (
      'M$1 $2V$3A$4 $4 0 0 1 $5 $6H$7A$4 $4 0 0 1 $8 $3V$2Z',
      x,
      y2,
      y + r,
      r,
      x + r,
      y,
      x2 - r,
      x2
    )
  elseif side == 'bottom' then
    return svg (
      'M$1 $2V$3A$4 $4 0 0 0 $5 $6H$7A$4 $4 0 0 0 $8 $3V$2Z',
      x,
      y,
      y2 - r,
      r,
      x + r,
      y2,
      x2 - r,
      x2
    )
  elseif side == 'right' then
    return svg (
      'M$1 $2H$3A$4 $4 0 0 1 $5 $6V$7A$4 $4 0 0 1 $3 $8H$1Z',
      x,
      y,
      x2 - r,
      r,
      x2,
      y + r,
      y2 - r,
      y2
    )
  end
  return svg (
    'M$1 $2H$3A$4 $4 0 0 0 $5 $6V$7A$4 $4 0 0 0 $3 $8H$1Z',
    x2,
    y,
    x + r,
    r,
    x,
    y + r,
    y2 - r,
    y2
  )
end

---------------------------------------------------------------------------------------------
-- Title and legend
---------------------------------------------------------------------------------------------

---@param c Sheet.ChartCanvas
---@param title string
local function draw_title (c, title)
  text (
    c,
    c.width / 2,
    c.top + TITLE_FONT,
    clip (title, c.right - c.left, TITLE_FONT * 1.05),
    'middle',
    ' class="sc-title" style="fill:var(--fg);font-size:13px;font-weight:600"'
  )
  c.top = c.top + TITLE_FONT + 10
end

---@param c Sheet.ChartCanvas
---@param key Sheet.ChartKey
---@param x number The left edge of the swatch.
---@param y number The middle of the row.
---@param name string The name, already cut to fit.
local function draw_key (c, key, x, y, name)
  local mark ---@type string
  if key.shape == 'line' then
    mark = svg (
      '<rect x="$1" y="$2" width="$3" height="2" rx="1" fill="$4"/>',
      x,
      y - 1,
      SWATCH,
      key.color
    )
  elseif key.shape == 'dot' then
    mark = svg (
      '<circle cx="$1" cy="$2" r="4" fill="$3"/>',
      x + SWATCH / 2,
      y,
      key.color
    )
  else
    mark = svg (
      '<rect x="$1" y="$2" width="$3" height="$3" rx="2" fill="$4"/>',
      x,
      y - SWATCH / 2,
      SWATCH,
      key.color
    )
  end
  add (c, '<g class="sc-key">' .. mark)
  text (c, x + SWATCH + 5, y + FONT * 0.35, name)
  add (c, '</g>')
end

---Draws the legend down the right side of the free space, and takes that space from the
---plot.
---@param c Sheet.ChartCanvas
---@param keys Sheet.ChartKey[]
---@param names string[]
local function legend_right (c, keys, names)
  local max_text = (c.right - c.left) * 0.35 - SWATCH - 5
  local fit = math.floor ((c.bottom - c.top) / LEGEND_ROW)
  if max_text < 24 or fit < 1 then
    return
  end
  local count = #keys
  if count > fit then
    count = fit - 1
  end
  local more = #keys - count
  local more_text = '+' .. more .. ' more'
  local text_w = more > 0 and width_of (more_text, FONT) or 0
  for i = 1, count do
    names[i] = clip (names[i], max_text, FONT)
    text_w = math.max (text_w, width_of (names[i], FONT))
  end
  local x = c.right - SWATCH - 5 - text_w
  local lines = count + (more > 0 and 1 or 0)
  local y = (c.top + c.bottom) / 2 - (lines - 1) * LEGEND_ROW / 2
  for i = 1, count do
    draw_key (c, keys[i], x, y, names[i])
    y = y + LEGEND_ROW
  end
  if more > 0 then
    text (c, x, y + FONT * 0.35, more_text, nil, ' class="sc-more"')
  end
  c.right = x - 14
end

---Draws the legend in rows above or below the free space, and takes that space from the
---plot. Keys that do not fit in three rows are counted in a note at the end.
---@param c Sheet.ChartCanvas
---@param keys Sheet.ChartKey[]
---@param names string[]
---@param side 'top'|'bottom'
local function legend_rows (c, keys, names, side)
  local SPACE = 14
  local avail = c.right - c.left
  local max_rows = math.max (
    1,
    math.min (3, math.floor ((c.bottom - c.top) * 0.3 / LEGEND_ROW))
  )
  local widths = {} ---@type number[]
  ---@type { keys: integer[], w: number }[]
  local rows = { { keys = {}, w = 0 } }
  local placed = 0
  for i = 1, #keys do
    names[i] = clip (names[i], math.min (140, avail - SWATCH - 5), FONT)
    widths[i] = SWATCH + 5 + width_of (names[i], FONT)
    local row = rows[#rows]
    if #row.keys > 0 and row.w + SPACE + widths[i] > avail then
      if #rows == max_rows then
        break
      end
      row = { keys = {}, w = 0 }
      rows[#rows + 1] = row
    end
    row.w = row.w + (#row.keys > 0 and SPACE or 0) + widths[i]
    row.keys[#row.keys + 1] = i
    placed = i
  end
  local more_text = nil ---@type string?
  local last = rows[#rows]
  while placed < #keys do
    more_text = '+' .. (#keys - placed) .. ' more'
    local more_w = width_of (more_text, FONT)
    if #last.keys == 0 or last.w + SPACE + more_w <= avail then
      last.w = last.w + (#last.keys > 0 and SPACE or 0) + more_w
      break
    end
    local i = table.remove (last.keys) --[[@as integer]]
    last.w = math.max (0, last.w - SPACE - widths[i])
    placed = placed - 1
  end
  local height = #rows * LEGEND_ROW
  local y = c.bottom - height + LEGEND_ROW / 2
  if side == 'top' then
    y = c.top + LEGEND_ROW / 2
  end
  for r, row in ipairs (rows) do
    local x = c.left + (avail - row.w) / 2
    for _, i in ipairs (row.keys) do
      draw_key (c, keys[i], x, y, names[i])
      x = x + widths[i] + SPACE
    end
    if r == #rows and more_text then
      text (c, x, y + FONT * 0.35, more_text, nil, ' class="sc-more"')
    end
    y = y + LEGEND_ROW
  end
  if side == 'top' then
    c.top = c.top + height + 6
  else
    c.bottom = c.bottom - height - 6
  end
end

---@param c Sheet.ChartCanvas
---@param keys Sheet.ChartKey[]
---@param side string
local function draw_legend (c, keys, side)
  local names = {} ---@type string[]
  for i, key in ipairs (keys) do
    names[i] = clean (key.name)
  end
  add (c, '<g class="sc-legend"' .. LABELS .. '>')
  if side == 'right' then
    legend_right (c, keys, names)
  else
    legend_rows (c, keys, names, side == 'top' and 'top' or 'bottom')
  end
  add (c, '</g>')
end

---------------------------------------------------------------------------------------------
-- Axes
---------------------------------------------------------------------------------------------

---@param c Sheet.ChartCanvas
---@param t number
---@param step number
---@return string
local function tick_text (c, t, step)
  if c.format then
    return clean (c.format (t))
  end
  return M.short (t, step)
end

---@param c Sheet.ChartCanvas
---@param ticks number[]
---@param step number
---@return string[]
local function tick_texts (c, ticks, step)
  local out = {} ---@type string[]
  for i, t in ipairs (ticks) do
    out[i] = tick_text (c, t, step)
  end
  return out
end

---@param texts string[]
---@return number
local function widest (texts)
  local w = 0
  for _, s in ipairs (texts) do
    w = math.max (w, width_of (s, FONT))
  end
  return w
end

---The axis title to draw, or nil when there is none or no room for it.
---@param c Sheet.ChartCanvas
---@param s? string
---@return string?
local function axis_title (c, s)
  if c.small or s == nil then
    return nil
  end
  local t = trim (s)
  if t == '' then
    return nil
  end
  return t
end

---Writes an axis title across the bottom, or up the left side when `up` is true.
---@param c Sheet.ChartCanvas
---@param s string
---@param x number
---@param y number
---@param max number
---@param up boolean
local function draw_axis_title (c, s, x, y, max, up)
  local attrs = ' class="sc-axis-title"' .. LABELS
  if up then
    attrs = attrs .. svg (' transform="rotate(-90 $1 $2)"', x, y)
  end
  text (c, x, y, clip (s, max, FONT), 'middle', attrs)
end

---Gridlines across the plot at each tick.
---@param c Sheet.ChartCanvas
---@param ticks number[]
---@param at fun(v: number): number
---@param upright boolean True for upright lines, one per tick along the x axis.
---@param from number
---@param to number
local function grid (c, ticks, at, upright, from, to)
  add (c, '<g class="sc-grid" style="stroke:var(--border)" stroke-width="1">')
  for _, t in ipairs (ticks) do
    local p = crisp (at (t))
    if upright then
      add (c, svg ('<line x1="$1" y1="$2" x2="$1" y2="$3"/>', p, from, to))
    else
      add (c, svg ('<line x1="$1" y1="$2" x2="$3" y2="$2"/>', from, p, to))
    end
  end
  add (c, '</g>')
end

---How many categories apart the shown labels sit, so that none overlap.
---@param need number The pixels one label needs.
---@param band number The pixels one category takes.
---@return integer
local function label_every (need, band)
  if band <= 0 then
    return 1
  end
  return math.max (1, math.ceil (need / band - 1e-9))
end

---------------------------------------------------------------------------------------------
-- Marks
---------------------------------------------------------------------------------------------

---@param c Sheet.ChartCanvas
---@param v number
---@return string
local function value_label (c, v)
  if c.format then
    return clean (c.format (v))
  end
  return general (v)
end

---A tooltip text such as `Groceries, Actual: 482.35`.
---@param c Sheet.ChartCanvas
---@param data Sheet.ChartData
---@param s integer
---@param i integer
---@return string
local function tip_text (c, data, s, i)
  local series = data.series[s]
  return data.categories[i]
    .. ', '
    .. series.name
    .. ': '
    .. value_label (c, series.values[i] or 0)
end

---Draws one bar. `from` and `to` are pixels on the value axis, from the base to the end.
---@param c Sheet.ChartCanvas
---@param horizontal boolean
---@param along number Where the bar starts across the category axis.
---@param thick number
---@param from number
---@param to number
---@param fill string
---@param round boolean True to round the far end.
---@param title string
local function bar (c, horizontal, along, thick, from, to, fill, round, title)
  local lo, hi = math.min (from, to), math.max (from, to)
  local side = nil ---@type 'top'|'bottom'|'left'|'right'|nil
  local d ---@type string
  if horizontal then
    if round then
      side = to > from and 'right' or 'left'
    end
    d = bar_path (lo, along, hi - lo, thick, side)
  else
    if round then
      side = to < from and 'top' or 'bottom'
    end
    d = bar_path (along, lo, thick, hi - lo, side)
  end
  add (
    c,
    svg ('<path class="sc-bar" d="$1" fill="$2">', d, fill)
      .. tip (title)
      .. '</path>'
  )
end

---@param c Sheet.ChartCanvas
---@param data Sheet.ChartData
---@param i integer
---@param thick number
---@param horizontal boolean
---@param pos fun(i: integer): number The middle of category `i`.
---@param at fun(v: number): number
local function stack (c, data, i, thick, horizontal, pos, at)
  -- Only the last segment on each side of zero gets a rounded end.
  local last_up, last_down = 0, 0
  for s, series in ipairs (data.series) do
    local v = series.values[i]
    if v and v > 0 then
      last_up = s
    elseif v and v < 0 then
      last_down = s
    end
  end
  local up, down = 0, 0 ---@type number, number
  for s, series in ipairs (data.series) do
    local v = series.values[i]
    if v and v ~= 0 then
      local base = v > 0 and up or down ---@type number
      local top = base + v ---@type number
      local from, to = at (base), at (top)
      -- A small gap between segments keeps them apart.
      if base ~= 0 and math.abs (to - from) > GAP + 0.5 then
        from = from + (to > from and GAP or -GAP)
      end
      local round = s == last_up or s == last_down
      bar (
        c,
        horizontal,
        pos (i) - thick / 2,
        thick,
        from,
        to,
        color (c, s),
        round,
        tip_text (c, data, s, i)
      )
      if v > 0 then
        up = top
      else
        down = top
      end
    end
  end
end

---@param c Sheet.ChartCanvas
---@param data Sheet.ChartData
---@param stacked boolean
---@param horizontal boolean
---@param pos fun(i: integer): number The middle of category `i`.
---@param band number
---@param at fun(v: number): number
local function draw_bars (c, data, stacked, horizontal, pos, band, at)
  local n = #data.categories
  local m = #data.series
  local group = band * 0.72
  add (c, '<g class="sc-bars">')
  if stacked then
    local thick = math.min (BAR_MAX, group)
    for i = 1, n do
      stack (c, data, i, thick, horizontal, pos, at)
    end
  else
    local gap = m > 1 and GAP or 0
    local thick = math.min (BAR_MAX, (group - gap * (m - 1)) / m)
    if thick < 1 then
      gap = 0
      thick = math.max (0.5, group / m)
    end
    local total = thick * m + gap * (m - 1)
    local zero = at (0)
    for i = 1, n do
      local start = pos (i) - total / 2
      for s, series in ipairs (data.series) do
        local v = series.values[i]
        if v and v ~= 0 then
          bar (
            c,
            horizontal,
            start + (s - 1) * (thick + gap),
            thick,
            zero,
            at (v),
            color (c, s),
            true,
            tip_text (c, data, s, i)
          )
        end
      end
    end
  end
  add (c, '</g>')
end

---A dot with a tooltip. A hover target has no colour, and a shown dot has a ring in the
---background colour, so it stands out where it crosses a line.
---@param c Sheet.ChartCanvas
---@param shown boolean
---@param x number
---@param y number
---@param r number
---@param fill string
---@param title string
local function dot (c, shown, x, y, r, fill, title)
  local open ---@type string
  if shown then
    open = svg (
      '<circle class="sc-dot" cx="$1" cy="$2" r="$3" fill="$4" style="stroke:var(--bg)" stroke-width="1.5">',
      x,
      y,
      r,
      fill
    )
  else
    open = svg (
      '<circle class="sc-hit" cx="$1" cy="$2" r="$3" fill="transparent">',
      x,
      y,
      r
    )
  end
  add (c, open .. tip (title) .. '</circle>')
end

---Draws the dots of a line or an area. With few points, every dot shows. With many, the dots
---are hidden hover targets, and only a point with no neighbour shows, so it does not vanish.
---@param c Sheet.ChartCanvas
---@param data Sheet.ChartData
---@param pos fun(i: integer): number
---@param at fun(v: number): number
---@param tops (number|nil)[][] Where each point sits, per series.
---@param show boolean True to show every dot.
local function draw_points (c, data, pos, at, tops, show)
  local n = #data.categories
  add (c, '<g class="sc-points">')
  for s, series in ipairs (data.series) do
    local vals = series.values
    for i = 1, n do
      local top = tops[s][i]
      if vals[i] and top then
        local alone = vals[i - 1] == nil and vals[i + 1] == nil
        local title = tip_text (c, data, s, i)
        if show or alone then
          dot (c, true, pos (i), at (top), 4, color (c, s), title)
        elseif n <= HIT_LIMIT then
          dot (c, false, pos (i), at (top), 5, '', title)
        end
      end
    end
  end
  add (c, '</g>')
end

---@param c Sheet.ChartCanvas
---@param s integer
---@param d string
---@return string
local function line_path (c, s, d)
  return svg (
    '<path class="sc-line" d="$1" fill="none" stroke="$2" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>',
    d,
    color (c, s)
  )
end

---@param c Sheet.ChartCanvas
---@param data Sheet.ChartData
---@param pos fun(i: integer): number
---@param at fun(v: number): number
local function draw_lines (c, data, pos, at)
  local n = #data.categories
  local tops = {} ---@type (number|nil)[][]
  add (c, '<g class="sc-lines">')
  for s, series in ipairs (data.series) do
    local d = {} ---@type string[]
    local pen = false
    for i = 1, n do
      local v = series.values[i]
      if v then
        d[#d + 1] = svg (pen and 'L$1 $2' or 'M$1 $2', pos (i), at (v))
      end
      -- A missing value lifts the pen, so the line breaks there.
      pen = v ~= nil
    end
    if #d > 0 then
      add (c, line_path (c, s, table.concat (d)))
    end
    tops[s] = series.values
  end
  add (c, '</g>')
  draw_points (c, data, pos, at, tops, n < DOT_LIMIT)
end

---Areas fill down to zero, or to the area below when stacked. A missing value counts as zero.
---@param c Sheet.ChartCanvas
---@param data Sheet.ChartData
---@param stacked boolean
---@param pos fun(i: integer): number
---@param at fun(v: number): number
local function draw_areas (c, data, stacked, pos, at)
  local n = #data.categories
  local base = {} ---@type number[]
  for i = 1, n do
    base[i] = 0
  end
  local tops = {} ---@type number[][]
  local fills = {} ---@type string[]
  local lines = {} ---@type string[]
  for s, series in ipairs (data.series) do
    local top = {} ---@type number[]
    local edge = {} ---@type string[]
    local under = {} ---@type string[]
    for i = 1, n do
      top[i] = base[i] + (series.values[i] or 0)
      edge[i] = svg (i == 1 and 'M$1 $2' or 'L$1 $2', pos (i), at (top[i]))
      local k = n - i + 1
      under[i] = svg ('L$1 $2', pos (k), at (base[k]))
    end
    fills[s] = svg (
      '<path class="sc-area" d="$1Z" fill="$2" fill-opacity="$3"/>',
      table.concat (edge) .. table.concat (under),
      color (c, s),
      stacked and 0.55 or 0.2
    )
    lines[s] = line_path (c, s, table.concat (edge))
    tops[s] = top
    if stacked then
      base = top
    end
  end
  add (c, '<g class="sc-areas">' .. table.concat (fills) .. '</g>')
  add (c, '<g class="sc-lines">' .. table.concat (lines) .. '</g>')
  draw_points (c, data, pos, at, tops, n == 1)
end

---------------------------------------------------------------------------------------------
-- Chart types
---------------------------------------------------------------------------------------------

---The smallest and the largest value a chart must show, or nil when there are no numbers.
---@param data Sheet.ChartData
---@param stacked boolean
---@return number? lo
---@return number? hi
local function value_range (data, stacked)
  local lo, hi = nil, nil ---@type number?, number?
  for i = 1, #data.categories do
    local up, down, any = 0, 0, false
    for _, series in ipairs (data.series) do
      local v = series.values[i]
      if v and stacked then
        any = true
        if v > 0 then
          up = up + v
        else
          down = down + v
        end
      elseif v then
        lo = math.min (lo or v, v)
        hi = math.max (hi or v, v)
      end
    end
    if any then
      lo = math.min (lo or down, down)
      hi = math.max (hi or up, up)
    end
  end
  return lo, hi
end

---Column, bar, line and area charts: categories along one axis, values along the other.
---@param c Sheet.ChartCanvas
---@param spec Sheet.ChartSpec
---@param data Sheet.ChartData
---@param kind Sheet.ChartKind
local function category_chart (c, spec, data, kind)
  local n = #data.categories
  local stacked = spec.stacked == true and kind ~= 'line'
  local lo, hi = value_range (data, stacked)
  if not lo or not hi then
    message (c, 'No numbers to chart')
    return
  end
  if kind == 'line' then
    lo, hi = with_zero (lo, hi)
  else
    lo, hi = math.min (lo, 0), math.max (hi, 0)
  end
  local cat_title = axis_title (c, spec.x_title)
  local val_title = axis_title (c, spec.y_title)
  local labels = {} ---@type string[]
  for i, s in ipairs (data.categories) do
    labels[i] = clean (s)
  end

  if kind == 'bar' then
    local top = c.top + 2
    local bottom = val_title and c.bottom - FONT - 6 or c.bottom
    local plot_bottom = bottom - (c.tiny and 0 or FONT + 8)
    local band = math.max (1, plot_bottom - top) / n
    local label_w = 0
    if not c.tiny then
      label_w = math.min ((c.right - c.left) * 0.35, widest (labels))
    end
    local left = c.left
      + (cat_title and FONT + 8 or 0)
      + (label_w > 0 and label_w + 8 or 0)
    local right = c.right

    ---@param ticks number[]
    ---@param step number
    ---@return number
    local function room (ticks, step)
      return widest (tick_texts (c, ticks, step)) + 12
    end

    local ticks, step = fit_ticks (lo, hi, right - left, 80, room)
    if not c.tiny then
      -- The last tick label sits centred on the right edge of the plot.
      right = c.right - width_of (tick_text (c, ticks[#ticks], step), FONT) / 2
      ticks, step = fit_ticks (lo, hi, math.max (1, right - left), 80, room)
    end
    right = math.max (left + 1, right)
    local at = scale (ticks, left, right)

    ---@param i integer
    ---@return number
    local function pos (i)
      return top + (i - 0.5) * band
    end

    grid (c, ticks, at, true, top, plot_bottom)
    draw_bars (c, data, stacked, true, pos, band, at)
    if not c.tiny then
      add (c, '<g class="sc-ticks"' .. LABELS .. '>')
      for _, t in ipairs (ticks) do
        local y = plot_bottom + 6 + FONT * 0.8
        text (c, at (t), y, tick_text (c, t, step), 'middle')
      end
      add (c, '</g>')
      add (c, '<g class="sc-cats"' .. LABELS .. '>')
      for i = 1, n, label_every (FONT + 3, band) do
        local s = clip (labels[i], label_w, FONT)
        text (c, left - 8, pos (i) + FONT * 0.35, s, 'end')
      end
      add (c, '</g>')
    end
    if cat_title then
      local x, y = c.left + FONT * 0.8, (top + plot_bottom) / 2
      draw_axis_title (c, cat_title, x, y, plot_bottom - top, true)
    end
    if val_title then
      local x = (left + right) / 2
      draw_axis_title (c, val_title, x, c.bottom - 2, c.right - c.left, false)
    end
    return
  end

  local top = c.top + FONT / 2
  local bottom = cat_title and c.bottom - FONT - 6 or c.bottom
  local plot_bottom = bottom - (c.tiny and 0 or FONT + 8)
  local ticks, step = fit_ticks (
    lo,
    hi,
    math.max (1, plot_bottom - top),
    36,
    function ()
      return FONT + 6
    end
  )
  local texts = tick_texts (c, ticks, step)
  local left = c.left + (val_title and FONT + 8 or 0)
  if not c.tiny then
    left = left + widest (texts) + 6
  end
  local right = math.max (left + 1, c.right)
  local band = (right - left) / n
  local at = scale (ticks, plot_bottom, top)

  ---@param i integer
  ---@return number
  local function pos (i)
    return left + (i - 0.5) * band
  end

  grid (c, ticks, at, false, left, right)
  if kind == 'column' then
    draw_bars (c, data, stacked, false, pos, band, at)
  elseif kind == 'area' then
    draw_areas (c, data, stacked, pos, at)
  else
    draw_lines (c, data, pos, at)
  end
  if not c.tiny then
    add (c, '<g class="sc-ticks"' .. LABELS .. '>')
    for i, t in ipairs (ticks) do
      text (c, left - 6, at (t) + FONT * 0.35, texts[i], 'end')
    end
    add (c, '</g>')
    local every = label_every (math.min (90, widest (labels)) + 8, band)
    add (c, '<g class="sc-cats"' .. LABELS .. '>')
    for i = 1, n, every do
      local x = pos (i)
      -- A label may spread over the categories it skips, but not past the edge.
      local max = math.min (every * band - 8, 2 * math.min (x, c.width - x))
      local s = clip (labels[i], max, FONT)
      text (c, x, plot_bottom + 6 + FONT * 0.8, s, 'middle')
    end
    add (c, '</g>')
  end
  if cat_title then
    local x = (left + right) / 2
    draw_axis_title (c, cat_title, x, c.bottom - 2, c.right - c.left, false)
  end
  if val_title then
    local x, y = c.left + FONT * 0.8, (top + plot_bottom) / 2
    draw_axis_title (c, val_title, x, y, plot_bottom - top, true)
  end
end

---The slices of a pie: the positive values of the first series.
---@param data Sheet.ChartData
---@return Sheet.ChartSlice[]
local function pie_slices (data)
  local slices = {} ---@type Sheet.ChartSlice[]
  local series = data.series[1]
  for i = 1, #data.categories do
    local v = series.values[i]
    if v and v > 0 then
      slices[#slices + 1] = { index = i, value = v }
    end
  end
  return slices
end

---The path of one slice from angle `a` to angle `b`, clockwise from twelve o'clock. A slice
---with a hole is a piece of a ring.
---@param cx number
---@param cy number
---@param r number
---@param inner number The radius of the hole, or 0.
---@param a number
---@param b number
---@return string
local function slice_path (cx, cy, r, inner, a, b)
  local sa, ca, sb, cb = math.sin (a), math.cos (a), math.sin (b), math.cos (b)
  local large = b - a > math.pi and 1 or 0
  if inner > 0 then
    return svg (
      'M$1 $2A$3 $3 0 $4 1 $5 $6L$7 $8A$9 $9 0 $4 0 $10 $11Z',
      cx + r * sa,
      cy - r * ca,
      r,
      large,
      cx + r * sb,
      cy - r * cb,
      cx + inner * sb,
      cy - inner * cb,
      inner,
      cx + inner * sa,
      cy - inner * ca
    )
  end
  return svg (
    'M$1 $2L$3 $4A$5 $5 0 $6 1 $7 $8Z',
    cx,
    cy,
    cx + r * sa,
    cy - r * ca,
    r,
    large,
    cx + r * sb,
    cy - r * cb
  )
end

---The path of a whole circle, or a whole ring when `inner` is above 0. An arc cannot run all
---the way round, so each circle is two half circles.
---@param cx number
---@param cy number
---@param r number
---@param inner number
---@return string
local function circle_path (cx, cy, r, inner)
  local d =
    svg ('M$1 $2A$3 $3 0 1 1 $1 $4A$3 $3 0 1 1 $1 $2Z', cx, cy - r, r, cy + r)
  if inner > 0 then
    d = d
      .. svg (
        'M$1 $2A$3 $3 0 1 0 $1 $4A$3 $3 0 1 0 $1 $2Z',
        cx,
        cy - inner,
        inner,
        cy + inner
      )
  end
  return d
end

---@param c Sheet.ChartCanvas
---@param data Sheet.ChartData
---@param hole boolean True for a doughnut.
local function draw_pie (c, data, hole)
  local slices = pie_slices (data)
  local total = 0 ---@type number
  for _, slice in ipairs (slices) do
    total = total + slice.value
  end
  local cx = (c.left + c.right) / 2
  local cy = (c.top + c.bottom) / 2
  local r = math.min (c.right - c.left, c.bottom - c.top) / 2 - 2
  if r < 4 then
    return
  end
  local inner = hole and r * 0.58 or 0
  -- A thin ring in the background colour between slices keeps neighbours apart.
  add (
    c,
    '<g class="sc-slices" style="stroke:var(--bg)" stroke-width="1.5" stroke-linejoin="round">'
  )
  local a = 0 ---@type number
  ---@type { a: number, b: number, fill: string, pct: number }[]
  local marks = {}
  for _, slice in ipairs (slices) do
    local b = a + slice.value / total * 2 * math.pi ---@type number
    local fill = color (c, slice.index)
    local d, rule ---@type string, string
    if #slices == 1 then
      d = circle_path (cx, cy, r, inner)
      rule = ' fill-rule="evenodd"'
    else
      d = slice_path (cx, cy, r, inner, a, b)
      rule = ''
    end
    local pct = slice.value / total * 100 ---@type number
    local title = data.categories[slice.index]
      .. ': '
      .. value_label (c, slice.value)
      .. ' ('
      .. string.format ('%.1f', pct)
      .. '%)'
    add (
      c,
      svg ('<path class="sc-slice" d="$1" fill="$2"', d, fill)
        .. rule
        .. '>'
        .. tip (title)
        .. '</path>'
    )
    marks[#marks + 1] = { a = a, b = b, fill = fill, pct = pct }
    a = b
  end
  add (c, '</g>')
  if c.tiny then
    return
  end
  -- Percentages go on the slices that have room for them.
  local at_r = hole and (r + inner) / 2 or r * 0.62
  local ring = r - inner
  add (c, '<g class="sc-pcts" style="font-weight:600">')
  for _, mark in ipairs (marks) do
    local label = math.floor (mark.pct + 0.5) .. '%'
    local arc = (mark.b - mark.a) * at_r
    if arc >= width_of (label, FONT) + 6 and ring >= FONT + 6 and r >= 30 then
      local mid = (mark.a + mark.b) / 2
      local x = cx + at_r * math.sin (mid)
      local y = cy - at_r * math.cos (mid) + FONT * 0.35
      local ink = svg (' fill="$1"', ink_on (mark.fill))
      text (c, x, y, label, 'middle', ink)
    end
  end
  add (c, '</g>')
end

---The points of a scatter chart. The first series holds the x values and each other series
---holds y values. With one series, x is the category number or the category's position.
---@param data Sheet.ChartData
---@return Sheet.ChartPoint[] points
---@return integer first The first series that holds y values.
local function scatter_points (data)
  local n = #data.categories
  local first = 2
  local xs = {} ---@type (number|nil)[]
  if #data.series >= 2 then
    xs = data.series[1].values
  else
    first = 1
    for i = 1, n do
      xs[i] = data.numbers and data.numbers[i] or i
    end
  end
  local points = {} ---@type Sheet.ChartPoint[]
  for s = first, #data.series do
    local ys = data.series[s].values
    for i = 1, n do
      local x, y = xs[i], ys[i]
      if x and y then
        points[#points + 1] = { series = s, index = i, x = x, y = y }
      end
    end
  end
  return points, first
end

---@param c Sheet.ChartCanvas
---@param data Sheet.ChartData
---@param p Sheet.ChartPoint
---@return string
local function point_tip (c, data, p)
  local title = data.series[p.series].name
    .. ': ('
    .. general (p.x)
    .. ', '
    .. value_label (c, p.y)
    .. ')'
  -- Categories read from text name the points.
  local name = data.categories[p.index] or ''
  if data.numbers == nil and name ~= '' and name ~= tostring (p.index) then
    title = name .. ', ' .. title
  end
  return title
end

---@param c Sheet.ChartCanvas
---@param spec Sheet.ChartSpec
---@param data Sheet.ChartData
local function draw_scatter (c, spec, data)
  local points, first = scatter_points (data)
  local x_lo, x_hi = points[1].x, points[1].x
  local y_lo, y_hi = points[1].y, points[1].y
  for _, p in ipairs (points) do
    x_lo, x_hi = math.min (x_lo, p.x), math.max (x_hi, p.x)
    y_lo, y_hi = math.min (y_lo, p.y), math.max (y_hi, p.y)
  end
  x_lo, x_hi = with_zero (x_lo, x_hi)
  y_lo, y_hi = with_zero (y_lo, y_hi)
  local x_title = axis_title (c, spec.x_title)
  local y_title = axis_title (c, spec.y_title)

  local top = c.top + FONT / 2
  local bottom = x_title and c.bottom - FONT - 6 or c.bottom
  local plot_bottom = bottom - (c.tiny and 0 or FONT + 8)
  local y_ticks, y_step = fit_ticks (
    y_lo,
    y_hi,
    math.max (1, plot_bottom - top),
    36,
    function ()
      return FONT + 6
    end
  )
  local y_texts = tick_texts (c, y_ticks, y_step)
  local left = c.left + (y_title and FONT + 8 or 0)
  if not c.tiny then
    left = left + widest (y_texts) + 6
  end

  ---@param ticks number[]
  ---@param step number
  ---@return number
  local function room (ticks, step)
    local w = 0
    for _, t in ipairs (ticks) do
      w = math.max (w, width_of (M.short (t, step), FONT))
    end
    return w + 12
  end

  local right = c.right
  local x_ticks, x_step =
    fit_ticks (x_lo, x_hi, math.max (1, right - left), 80, room)
  if not c.tiny then
    right = c.right - width_of (M.short (x_ticks[#x_ticks], x_step), FONT) / 2
    x_ticks, x_step =
      fit_ticks (x_lo, x_hi, math.max (1, right - left), 80, room)
  end
  right = math.max (left + 1, right)
  local at_x = scale (x_ticks, left, right)
  local at_y = scale (y_ticks, plot_bottom, top)

  grid (c, y_ticks, at_y, false, left, right)
  grid (c, x_ticks, at_x, true, top, plot_bottom)
  local r = #points > 200 and 3 or 4
  add (c, '<g class="sc-points">')
  for _, p in ipairs (points) do
    local fill = color (c, p.series - first + 1)
    dot (c, true, at_x (p.x), at_y (p.y), r, fill, point_tip (c, data, p))
  end
  add (c, '</g>')
  if not c.tiny then
    add (c, '<g class="sc-ticks"' .. LABELS .. '>')
    for i, t in ipairs (y_ticks) do
      text (c, left - 6, at_y (t) + FONT * 0.35, y_texts[i], 'end')
    end
    local y = plot_bottom + 6 + FONT * 0.8
    for _, t in ipairs (x_ticks) do
      text (c, at_x (t), y, M.short (t, x_step), 'middle')
    end
    add (c, '</g>')
  end
  if x_title then
    local x = (left + right) / 2
    draw_axis_title (c, x_title, x, c.bottom - 2, c.right - c.left, false)
  end
  if y_title then
    local x, y = c.left + FONT * 0.8, (top + plot_bottom) / 2
    draw_axis_title (c, y_title, x, y, plot_bottom - top, true)
  end
end

---------------------------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------------------------

---@param data Sheet.ChartData
---@return boolean
local function has_numbers (data)
  for _, series in ipairs (data.series) do
    for i = 1, #data.categories do
      if series.values[i] then
        return true
      end
    end
  end
  return false
end

---The legend entries for a chart, or a message to show in place of the chart when there is
---nothing to draw.
---@param c Sheet.ChartCanvas
---@param data Sheet.ChartData
---@param kind Sheet.ChartKind
---@return Sheet.ChartKey[] keys
---@return string? problem
local function keys_of (c, data, kind)
  local keys = {} ---@type Sheet.ChartKey[]
  if #data.series == 0 or #data.categories == 0 then
    return keys, 'No data to chart'
  elseif kind == 'pie' or kind == 'doughnut' then
    for _, slice in ipairs (pie_slices (data)) do
      local name = data.categories[slice.index]
      local fill = color (c, slice.index)
      keys[#keys + 1] = { name = name, color = fill, shape = 'box' }
    end
    if #keys == 0 then
      return keys, 'No positive numbers to chart'
    end
  elseif kind == 'scatter' then
    local points, first = scatter_points (data)
    if #points == 0 then
      return keys, 'No points to chart'
    end
    for s = first, #data.series do
      local fill = color (c, s - first + 1)
      keys[#keys + 1] =
        { name = data.series[s].name, color = fill, shape = 'dot' }
    end
  elseif not has_numbers (data) then
    return keys, 'No numbers to chart'
  else
    local shape = kind == 'line' and 'line' or 'box'
    for s, series in ipairs (data.series) do
      keys[#keys + 1] =
        { name = series.name, color = color (c, s), shape = shape }
    end
  end
  return keys, nil
end

---Draws a chart as an SVG string of `opts.width` by `opts.height` pixels, with a clear
---background.
---@param spec Sheet.ChartSpec
---@param data Sheet.ChartData
---@param opts Sheet.ChartOptions
---@return string
function M.render (spec, data, opts)
  local width = math.max (1, math.floor (tonumber (opts.width) or 400))
  local height = math.max (1, math.floor (tonumber (opts.height) or 300))
  local kind = BY_ID[spec.type] and spec.type or 'column'
  ---@type Sheet.ChartCanvas
  local c = {
    out = {},
    width = width,
    height = height,
    left = PAD,
    right = width - PAD,
    top = PAD,
    bottom = height - PAD,
    small = width < 240 or height < 150,
    tiny = width < 140 or height < 100,
    format = opts.format,
    colors = spec.colors or {},
  }
  local title = trim (spec.title or '')
  local label = title ~= '' and title or (BY_ID[kind].label .. ' chart')
  add (
    c,
    svg (
      '<svg xmlns="http://www.w3.org/2000/svg" class="sheet-chart" width="$1" height="$2" viewBox="0 0 $1 $2" role="img" aria-label="$3" style="font-family:var(--font-ui);font-size:$4px">',
      width,
      height,
      label,
      FONT
    )
  )
  if title ~= '' and height >= 60 then
    draw_title (c, title)
  end
  data = {
    categories = data.categories or {},
    series = data.series or {},
    numbers = data.numbers,
  }
  local keys, problem = keys_of (c, data, kind)
  if problem then
    message (c, problem)
  else
    local pie = kind == 'pie' or kind == 'doughnut'
    local side = spec.legend or 'bottom'
    local wanted = #keys >= 2 or (pie and #keys >= 1)
    if side ~= 'none' and not c.small and wanted then
      draw_legend (c, keys, side)
    end
    if pie then
      draw_pie (c, data, kind == 'doughnut')
    elseif kind == 'scatter' then
      draw_scatter (c, spec, data)
    else
      category_chart (c, spec, data, kind)
    end
  end
  add (c, '</svg>')
  return table.concat (c.out)
end

return M
