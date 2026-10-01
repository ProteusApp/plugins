local chart = require ('sheet_chart') --[[@as Sheet.ChartModule]]

---A full chart spec from the fields a test cares about.
---@param t table
---@return Sheet.ChartSpec
local function spec (t)
  t.id = t.id or 'c1'
  t.type = t.type or 'column'
  t.range = t.range or 'A1:C7'
  t.x, t.y, t.w, t.h = 0, 0, 480, 300
  return t --[[@as Sheet.ChartSpec]]
end

---@param kind Sheet.ChartKind
---@param values Sheet.Value[][]
---@param extra? table More spec fields.
---@param opts? table Render options besides the size.
---@return string
local function draw (kind, values, extra, opts)
  local s = extra or {}
  s.type = kind
  local o = opts or {}
  o.width = o.width or 480
  o.height = o.height or 300
  return chart.render (
    spec (s),
    chart.data_from (values),
    o --[[@as Sheet.ChartOptions]]
  )
end

---Counts the matches of a plain string.
---@param s string
---@param part string
---@return integer
local function count (s, part)
  local n, at = 0, 1
  while true do
    local from, to = string.find (s, part, at, true)
    if not from then
      return n
    end
    n = n + 1
    at = to + 1
  end
end

---The texts inside the group with a class, such as `sc-ticks`.
---@param svg string
---@param class string
---@return string[]
local function texts_in (svg, class)
  local out = {} ---@type string[]
  local pattern = '<g class="'
    .. string.gsub (class, '%-', '%%-')
    .. '"[^>]*>(.-)</g>'
  local body = string.match (svg, pattern)
  for s in string.gmatch (body or '', '<text[^>]*>(.-)</text>') do
    out[#out + 1] = s
  end
  return out
end

---The names in the legend, in order.
---@param svg string
---@return string[]
local function legend_of (svg)
  local out = {} ---@type string[]
  for s in string.gmatch (svg, '<g class="sc%-key">.-<text[^>]*>(.-)</text>') do
    out[#out + 1] = s
  end
  return out
end

---The tooltips, in order.
---@param svg string
---@return string[]
local function tips_of (svg)
  local out = {} ---@type string[]
  for s in string.gmatch (svg, '<title>(.-)</title>') do
    out[#out + 1] = s
  end
  return out
end

---Checks that the SVG is well-formed XML with one root: tags close in order, every attribute
---is quoted, and every `&` starts an entity. Returns what is wrong, or nil.
---@param s string
---@return string?
local function xml_error (s)
  if string.sub (s, 1, 4) ~= '<svg' or string.sub (s, -6) ~= '</svg>' then
    return 'the root is not one svg element'
  end
  for found in string.gmatch (s, '()&') do
    local pos = found --[[@as integer]]
    if
      not string.match (s, '^&%a+;', pos)
      and not string.match (s, '^&#%d+;', pos)
    then
      return 'a bare & at ' .. pos
    end
  end
  local stack = {} ---@type string[]
  local i = 1
  while true do
    local lt = string.find (s, '<', i, true)
    if not lt then
      break
    end
    if #stack == 0 and lt > 1 then
      return 'content after the root at ' .. lt
    end
    local gt = string.find (s, '>', lt, true)
    if not gt then
      return 'a tag that never ends at ' .. lt
    end
    local tag = string.sub (s, lt + 1, gt - 1)
    if string.sub (tag, 1, 1) == '/' then
      local name = string.match (tag, '^/([%w:%-]+)$')
      local open = table.remove (stack)
      if name == nil or name ~= open then
        return 'expected </'
          .. tostring (open)
          .. '> at '
          .. lt
          .. ', found <'
          .. tag
          .. '>'
      end
    else
      local name, rest = string.match (tag, '^([%w:%-]+)(.-)$')
      if not name then
        return 'a bad tag <' .. tag .. '>'
      end
      local closed = string.sub (rest, -1) == '/'
      if closed then
        rest = string.sub (rest, 1, -2)
      end
      local left = string.gsub (rest, '%s+[%w:%-]+="[^"<]*"', '')
      if string.find (left, '%S') then
        return 'bad attributes in <' .. name .. '>: ' .. left
      end
      if not closed then
        stack[#stack + 1] = name
      end
    end
    i = gt + 1
  end
  if #stack > 0 then
    return 'unclosed <' .. stack[#stack] .. '>'
  end
  return nil
end

---@param svg string
local function valid (svg)
  local err = xml_error (svg)
  ok (err == nil, err)
end

local BUDGET = {
  { 'Category', 'Planned', 'Actual' },
  { 'Rent', 1500, 1500 },
  { 'Groceries', 450, 482.35 },
  { 'Transport', 120, 96.4 },
  { 'Utilities', 180, 201 },
  { 'Fun', 200, 260 },
  { 'Savings', 400, 300 },
}

local PROFIT = {
  { 'Quarter', 'Profit', 'Costs' },
  { 'Q1', 1200, -300 },
  { 'Q2', -450, -600 },
  { 'Q3', 800, -200 },
  { 'Q4', 2300, -800 },
}

---@param n integer
---@return Sheet.Value[][]
local function wave (n)
  local rows = { { 'Day', 'A', 'B' } } ---@type Sheet.Value[][]
  for i = 1, n do
    rows[#rows + 1] = { 'D' .. i, 10 + i % 7, 20 - i % 5 }
  end
  return rows
end

---------------------------------------------------------------------------------------------
-- The XML checker
---------------------------------------------------------------------------------------------

test ('the checker in this file finds broken XML', function ()
  eq (xml_error ('<svg><g></g></svg>'), nil)
  eq (xml_error ('<svg a="1"><text x="2">a &amp; b</text></svg>'), nil)
  ok (xml_error ('<svg><g></svg>'))
  ok (xml_error ('<svg><text>a & b</text></svg>'))
  ok (xml_error ('<svg><rect x=1/></svg>'))
  ok (xml_error ('<svg></svg><svg></svg>'))
  ok (xml_error ('<svg><g>'))
end)

---------------------------------------------------------------------------------------------
-- Ticks
---------------------------------------------------------------------------------------------

test ('nice ticks step by 1, 2 or 5 times a power of ten', function ()
  eq (chart.nice_ticks (0, 100, 5), { 0, 20, 40, 60, 80, 100 })
  eq (chart.nice_ticks (0, 97, 5), { 0, 20, 40, 60, 80, 100 })
  eq (
    chart.nice_ticks (3, 97, 10),
    { 0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100 }
  )
  eq (chart.nice_ticks (0, 1, 5), { 0, 0.2, 0.4, 0.6, 0.8, 1 })
  eq (chart.nice_ticks (0, 7e6, 5), { 0, 1e6, 2e6, 3e6, 4e6, 5e6, 6e6, 7e6 })
  eq (chart.nice_ticks (-37, 52, 4), { -40, -20, 0, 20, 40, 60 })
  eq (chart.nice_ticks (100, 0, 5), chart.nice_ticks (0, 100, 5))
  eq (
    chart.nice_ticks (0.001, 0.0042, 5),
    { 0.001, 0.0015, 0.002, 0.0025, 0.003, 0.0035, 0.004, 0.0045 }
  )
  local _, step = chart.nice_ticks (0, 100, 5)
  eq (step, 20)
end)

test ('nice ticks for negative data, one value and no spread', function ()
  eq (chart.nice_ticks (-80, -10, 5), { -80, -70, -60, -50, -40, -30, -20, -10 })
  eq (chart.nice_ticks (5, 5, 5), { 0, 1, 2, 3, 4, 5 })
  eq (chart.nice_ticks (-3, -3, 5), { -3, -2.5, -2, -1.5, -1, -0.5, 0 })
  eq (chart.nice_ticks (0, 0, 5), { 0, 0.2, 0.4, 0.6, 0.8, 1 })
  eq (chart.nice_ticks (0 / 0, 1, 5), { 0, 1 })
  eq (chart.nice_ticks (0, math.huge, 5), { 0, 1 })
end)

test ('nice ticks cover the range with even, clean steps', function ()
  local ranges = {
    { 0, 1 },
    { 0, 9.99 },
    { 1, 2 },
    { 17, 18.5 },
    { -1, 1 },
    { -0.003, 0.0071 },
    { 12345, 67890 },
    { -5e9, 3e8 },
    { 0.1, 0.30000000000000004 },
    { 99.5, 100.5 },
    { 1e-7, 3e-7 },
    { -1e12, -1e11 },
  }
  for _, r in ipairs (ranges) do
    for asked = 2, 10 do
      local lo, hi = r[1], r[2]
      local ticks, step = chart.nice_ticks (lo, hi, asked)
      local what = lo .. '..' .. hi .. ' in ' .. asked
      ok (#ticks >= 2 and #ticks <= 2 * asked + 2, what .. ' tick count')
      local slack = step * 1e-6
      ok (ticks[1] <= lo + slack, what .. ' starts at or below the range')
      ok (ticks[#ticks] >= hi - slack, what .. ' ends at or above the range')
      local mantissa = step
        / 10 ^ math.floor (math.log (step) / math.log (10) + 1e-9)
      local tidy = false
      for _, want in ipairs ({ 1, 2, 5, 10 }) do
        tidy = tidy or math.abs (mantissa - want) < 1e-9
      end
      ok (tidy, what .. ' step ' .. step)
      for i = 2, #ticks do
        local d = ticks[i] - ticks[i - 1]
        ok (math.abs (d - step) < step * 1e-6, what .. ' even steps')
      end
      for _, t in ipairs (ticks) do
        eq (t, tonumber (string.format ('%.12g', t)), what .. ' no float noise')
      end
    end
  end
end)

test ('short tick labels', function ()
  eq (chart.short (0, 100), '0')
  eq (chart.short (250, 50), '250')
  eq (chart.short (1000, 500), '1k')
  eq (chart.short (1500, 500), '1.5k')
  eq (chart.short (1200, 200), '1.2k')
  eq (chart.short (-1500, 500), '-1.5k')
  eq (chart.short (3.4e6, 2e5), '3.4M')
  eq (chart.short (2e9, 1e9), '2B')
  eq (chart.short (7e12, 1e12), '7T')
  eq (chart.short (0.25, 0.05), '0.25')
  eq (chart.short (0.4, 0.2), '0.4')
  eq (chart.short (0.0015, 0.0005), '0.0015')
  eq (chart.short (1234.5), '1.23k')
  eq (chart.short (0.5), '0.5')
end)

---------------------------------------------------------------------------------------------
-- Reading a range
---------------------------------------------------------------------------------------------

test (
  'headings name the series and text in the first column names the categories',
  function ()
    local data = chart.data_from (BUDGET)
    eq (
      data.categories,
      { 'Rent', 'Groceries', 'Transport', 'Utilities', 'Fun', 'Savings' }
    )
    eq (#data.series, 2)
    eq (data.series[1].name, 'Planned')
    eq (data.series[1].values, { 1500, 450, 120, 180, 200, 400 })
    eq (data.series[2].name, 'Actual')
    eq (data.series[2].values, { 1500, 482.35, 96.4, 201, 260, 300 })
    eq (data.numbers, nil)
  end
)

test ('a block of numbers alone gets numbered categories and series', function ()
  local data = chart.data_from ({ { 1, 2 }, { 3, 4 }, { 5, 6 } })
  eq (data.categories, { '1', '2', '3' })
  eq (data.series[1], { name = 'Series 1', values = { 1, 3, 5 } })
  eq (data.series[2], { name = 'Series 2', values = { 2, 4, 6 } })
end)

test ('the longer side runs along the categories', function ()
  local wide = {
    { '', 'Jan', 'Feb', 'Mar' },
    { 'North', 1, 2, 3 },
    { 'South', 4, 5, 6 },
  }
  local data = chart.data_from (wide)
  eq (data.categories, { 'Jan', 'Feb', 'Mar' })
  eq (data.series[1], { name = 'North', values = { 1, 2, 3 } })
  eq (data.series[2], { name = 'South', values = { 4, 5, 6 } })

  local one_row = chart.data_from ({ { 1, 2, 3 } })
  eq (one_row.categories, { '1', '2', '3' })
  eq (one_row.series, { { name = 'Series 1', values = { 1, 2, 3 } } })

  local one_col = chart.data_from ({ { 'Sales' }, { 1 }, { 2 } })
  eq (one_col.categories, { '1', '2' })
  eq (one_col.series, { { name = 'Sales', values = { 1, 2 } } })
end)

test ('series_in picks the direction', function ()
  local by_rows = chart.data_from (BUDGET, { series_in = 'rows' })
  eq (by_rows.categories, { 'Planned', 'Actual' })
  eq (#by_rows.series, 6)
  eq (by_rows.series[2], { name = 'Groceries', values = { 450, 482.35 } })

  local wide = { { 'x', 'a', 'b', 'c' }, { 'y', 1, 2, 3 } }
  local by_cols = chart.data_from (wide, { series_in = 'cols' })
  eq (by_cols.categories, { 'y' })
  eq (by_cols.series[1], { name = 'a', values = { 1 } })
  eq (#by_cols.series, 3)
end)

test ('number categories', function ()
  -- A blank corner over text headings makes the first column the categories.
  local years =
    chart.data_from ({ { nil, 'A', 'B' }, { 2021, 1, 2 }, { 2022, 3, 4 } })
  eq (years.categories, { '2021', '2022' })
  eq (years.numbers, { 2021, 2022 })
  eq (years.series[1], { name = 'A', values = { 1, 3 } })

  -- With a heading in the corner, a column of numbers is a series unless labels says not.
  local rows = { { 'Year', 'Sales' }, { 2021, 5 }, { 2022, 7 } }
  local plain = chart.data_from (rows)
  eq (plain.categories, { '1', '2' })
  eq (plain.series[1], { name = 'Year', values = { 2021, 2022 } })
  local labelled = chart.data_from (rows, { labels = true })
  eq (labelled.categories, { '2021', '2022' })
  eq (labelled.series, { { name = 'Sales', values = { 5, 7 } } })

  ---@param n number
  ---@return string
  local function day (n)
    return 'day ' .. (n - 46293)
  end
  local dates = chart.data_from (
    { { nil, 'Temp' }, { 46294, 18 }, { 46295, 21.5 } },
    { format = day }
  )
  eq (dates.categories, { 'day 1', 'day 2' })
  eq (dates.numbers, { 46294, 46295 })
end)

test ('headers and labels can be turned off', function ()
  local data = chart.data_from (
    { { 'x', 'y' }, { 1, 2 }, { 3, 4 } },
    { headers = false }
  )
  eq (data.categories, { '1', '2', '3' })
  eq (data.series[1].name, 'Series 1')
  eq (data.series[1].values[1], nil)
  eq (data.series[1].values[2], 1)
  eq (data.series[2].values[3], 4)

  local no_labels = chart.data_from (BUDGET, { labels = false })
  eq (no_labels.categories, { '1', '2', '3', '4', '5', '6' })
  eq (no_labels.series[1].name, 'Category')
  eq (#no_labels.series, 3)
end)

test ('blanks are missing numbers and blank edges are dropped', function ()
  local data = chart.data_from ({
    { 'Name', 'Q1', '', 'Q2', nil },
    { 'a', nil, nil, 3 },
    { 'b', 2, '  ', nil },
    { 'c', '', nil, 5 },
    { nil, nil, nil, nil, nil },
    { '', ' ' },
  })
  eq (data.categories, { 'a', 'b', 'c' })
  -- The empty third column is a gap, not a series.
  eq (#data.series, 2)
  eq (data.series[1].name, 'Q1')
  eq (data.series[1].values[1], nil)
  eq (data.series[1].values[2], 2)
  eq (data.series[1].values[3], nil)
  eq (data.series[2].name, 'Q2')
  eq (data.series[2].values[1], 3)
  eq (data.series[2].values[3], 5)

  local gap =
    chart.data_from ({ { 'k', 'v' }, { 'a', 1 }, { nil, nil }, { 'b', 2 } })
  eq (gap.categories, { 'a', '', 'b' })
  eq (gap.series[1].values[3], 2)
end)

test (
  'errors, booleans and text that looks like a number are missing numbers',
  function ()
    local data = chart.data_from ({
      { 'Item', 'Qty' },
      { 'a', { code = '#DIV/0!' } },
      { 'b', true },
      { 'c', '12' },
      { 'd', 4 },
      { true, 1 },
      { { code = '#N/A' }, 2 },
    })
    eq (data.categories, { 'a', 'b', 'c', 'd', 'TRUE', '#N/A' })
    eq (data.series[1].values[1], nil)
    eq (data.series[1].values[2], nil)
    eq (data.series[1].values[3], nil)
    eq (data.series[1].values[4], 4)
    eq (data.series[1].values[6], 2)
  end
)

test ('an empty or blank range has no categories and no series', function ()
  eq (chart.data_from ({}), { categories = {}, series = {} })
  eq (
    chart.data_from ({ {}, { nil, ' ' }, { '' } }),
    { categories = {}, series = {} }
  )
end)

test ('line breaks in names become spaces', function ()
  local data =
    chart.data_from ({ { 'k', 'two\nlines' }, { 'a\tb', 1 }, { 'c', 2 } })
  eq (data.categories[1], 'a b')
  eq (data.series[1].name, 'two lines')
end)

---------------------------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------------------------

test ('the picker lists every type with a label and an icon', function ()
  -- The registry holds no copy of Lucide, so the icons are checked by name.
  local ids = {} ---@type string[]
  local icons = {} ---@type string[]
  for i, t in ipairs (chart.types) do
    ids[i] = t.id
    icons[i] = t.icon
    ok (t.label ~= '', t.id)
  end
  eq (icons, {
    'chart-column',
    'chart-bar',
    'chart-line',
    'chart-area',
    'chart-pie',
    'donut',
    'chart-scatter',
  })
  eq (ids, { 'column', 'bar', 'line', 'area', 'pie', 'doughnut', 'scatter' })
  eq (#chart.palette, 8)
end)

test ('a column chart draws one bar per value', function ()
  local svg = draw ('column', BUDGET, { title = 'Planned and actual' })
  valid (svg)
  eq (count (svg, 'class="sc-bar"'), 12)
  eq (
    texts_in (svg, 'sc-cats'),
    { 'Rent', 'Groceries', 'Transport', 'Utilities', 'Fun', 'Savings' }
  )
  eq (legend_of (svg), { 'Planned', 'Actual' })
  eq (
    texts_in (svg, 'sc-ticks'),
    { '0', '200', '400', '600', '800', '1k', '1.2k', '1.4k', '1.6k' }
  )
  eq (count (svg, 'Planned and actual</text>'), 1)
  eq (tips_of (svg)[4], 'Groceries, Actual: 482.35')
  ok (
    string.find (svg, 'width="480" height="300" viewBox="0 0 480 300"', 1, true)
  )
  ok (string.find (svg, 'fill="' .. chart.palette[1] .. '"', 1, true))
  ok (string.find (svg, 'fill="' .. chart.palette[2] .. '"', 1, true))
  -- Text and lines follow the theme.
  ok (string.find (svg, 'font-family:var(--font-ui)', 1, true))
  ok (string.find (svg, 'stroke:var(--border)', 1, true))
  ok (string.find (svg, 'fill:var(--fg-muted)', 1, true))
  ok (string.find (svg, 'fill:var(--fg)', 1, true))
end)

test ('a value format shows on the axis and in tooltips', function ()
  ---@param n number
  ---@return string
  local function money (n)
    return string.format ('$%.2f', n)
  end
  local svg = draw ('column', BUDGET, nil, { format = money })
  valid (svg)
  eq (tips_of (svg)[4], 'Groceries, Actual: $482.35')
  eq (texts_in (svg, 'sc-ticks')[1], '$0.00')
end)

test ('negative values go below zero and stacks split at zero', function ()
  local svg = draw ('column', PROFIT)
  valid (svg)
  eq (count (svg, 'class="sc-bar"'), 8)
  local ticks = texts_in (svg, 'sc-ticks')
  eq (ticks[1], '-1k')
  ok (string.find (table.concat (ticks, ' '), ' 0 ', 1, true))

  local stacked = draw ('column', PROFIT, { stacked = true })
  valid (stacked)
  eq (count (stacked, 'class="sc-bar"'), 8)
  -- Q2 has two negative values, so its stack reaches -1050.
  eq (texts_in (stacked, 'sc-ticks')[1], '-1.5k')
  eq (tips_of (stacked)[4], 'Q2, Costs: -600')
end)

test ('a bar chart lays the categories down the side', function ()
  local svg = draw ('bar', BUDGET, { stacked = false })
  valid (svg)
  eq (count (svg, 'class="sc-bar"'), 12)
  eq (texts_in (svg, 'sc-cats')[1], 'Rent')
  eq (texts_in (svg, 'sc-ticks'), { '0', '500', '1k', '1.5k' })
  local stacked = draw ('bar', PROFIT, { stacked = true })
  valid (stacked)
  eq (count (stacked, 'class="sc-bar"'), 8)
end)

test ('a line chart draws one line per series and a dot per point', function ()
  local svg = draw ('line', BUDGET)
  valid (svg)
  eq (count (svg, 'class="sc-line"'), 2)
  eq (count (svg, 'class="sc-dot"'), 12)
  eq (count (svg, 'class="sc-hit"'), 0)

  -- With many points the dots hide, and hover targets carry the tooltips.
  local many = draw ('line', wave (40))
  valid (many)
  eq (count (many, 'class="sc-dot"'), 0)
  eq (count (many, 'class="sc-hit"'), 80)
  eq (#tips_of (many), 80)
end)

test ('a missing value breaks the line', function ()
  local rows = wave (40)
  rows[11][2] = nil
  rows[21][2] = 'n/a'
  rows[23][2] = nil
  local svg = draw ('line', rows)
  valid (svg)
  local first = string.match (svg, '<path class="sc%-line" d="([^"]*)"')
  eq (count (first, 'M'), 4)
  -- The point between two gaps shows as a dot, so it does not vanish.
  eq (count (svg, 'class="sc-dot"'), 1)
  eq (count (svg, 'class="sc-hit"'), 76)
end)

test ('an area chart fills under each series', function ()
  local svg = draw ('area', BUDGET)
  valid (svg)
  eq (count (svg, 'class="sc-area"'), 2)
  eq (count (svg, 'class="sc-line"'), 2)
  eq (count (svg, 'fill-opacity="0.2"'), 2)
  eq (#tips_of (svg), 12)
  local stacked = draw ('area', BUDGET, { stacked = true })
  valid (stacked)
  eq (count (stacked, 'class="sc-area"'), 2)
  -- The stack reaches 3000 for Rent.
  local ticks = texts_in (stacked, 'sc-ticks')
  eq (ticks[#ticks], '3k')
end)

test ('a pie shows the first series, one slice per positive value', function ()
  local rows = {
    { 'Item', 'Cost', 'Other' },
    { 'Rent', 1500, 1 },
    { 'Food', 450, 1 },
    { 'Nothing', 0, 1 },
    { 'Refund', -20, 1 },
    { 'Blank', nil, 1 },
    { 'Fun', 50, 1 },
  }
  local svg = draw ('pie', rows)
  valid (svg)
  eq (count (svg, 'class="sc-slice"'), 3)
  eq (legend_of (svg), { 'Rent', 'Food', 'Fun' })
  eq (
    tips_of (svg),
    { 'Rent: 1500 (75.0%)', 'Food: 450 (22.5%)', 'Fun: 50 (2.5%)' }
  )
  -- Only the slices with room show their percentage.
  eq (texts_in (svg, 'sc-pcts'), { '75%', '23%' })
  -- Each slice keeps its category's colour, so leaving some out does not repaint the rest.
  ok (string.find (svg, 'd="[^"]*" fill="' .. chart.palette[6] .. '"'))

  local ring = draw ('doughnut', rows)
  valid (ring)
  eq (count (ring, 'class="sc-slice"'), 3)
end)

test ('percentages pick the text colour with more contrast', function ()
  local rows = { { 'k', 'v' }, { 'a', 1 }, { 'b', 1 } }
  local svg = draw ('pie', rows, { colors = { '#fafafa', '#111' } })
  local inks = {} ---@type string[]
  for ink in string.gmatch (svg, '<text[^>]* fill="(#%x+)">%d+%%</text>') do
    inks[#inks + 1] = ink
  end
  eq (inks, { '#1b1d23', '#ffffff' })
end)

test ('a pie with one slice is a whole circle', function ()
  local rows = { { 'k', 'v' }, { 'All', 5 }, { 'None', 0 } }
  local pie = draw ('pie', rows)
  valid (pie)
  eq (count (pie, 'class="sc-slice"'), 1)
  eq (legend_of (pie), { 'All' })
  eq (texts_in (pie, 'sc-pcts'), { '100%' })
  local ring = draw ('doughnut', rows)
  ok (string.find (ring, 'fill-rule="evenodd"', 1, true))
end)

test ('a scatter chart plots each later series against the first', function ()
  local rows = { { 'Height', 'Weight', 'Age' } } ---@type Sheet.Value[][]
  for i = 1, 10 do
    rows[#rows + 1] = { 150 + i * 4, 50 + i * 2, i % 3 == 0 and 'x' or 20 + i }
  end
  rows[#rows + 1] = { nil, 70, 30 }
  local svg = draw ('scatter', rows)
  valid (svg)
  -- Ten weights, and the seven ages that are numbers. The last row has no x.
  eq (count (svg, 'class="sc-dot"'), 17)
  eq (legend_of (svg), { 'Weight', 'Age' })
  eq (tips_of (svg)[1], 'Weight: (154, 52)')
  local ticks = texts_in (svg, 'sc-ticks')
  ok (#ticks > 4)

  local named =
    draw ('scatter', { { 'Who', 'x', 'y' }, { 'Ann', 1, 2 }, { 'Bo', 3, 4 } })
  eq (tips_of (named), { 'Ann, y: (1, 2)', 'Bo, y: (3, 4)' })
  -- One y series needs no legend.
  eq (legend_of (named), {})
end)

test ('a title, legend and axis titles go where the spec says', function ()
  local svg = draw ('column', BUDGET, {
    title = 'Budget',
    x_title = 'Category',
    y_title = 'Dollars',
    legend = 'right',
  })
  valid (svg)
  eq (count (svg, 'class="sc-title"'), 1)
  eq (count (svg, 'class="sc-axis-title"'), 2)
  ok (string.find (svg, 'rotate(-90', 1, true))
  eq (legend_of (svg), { 'Planned', 'Actual' })

  local none = draw ('column', BUDGET, { legend = 'none' })
  eq (count (none, 'sc-legend'), 0)
  local top = draw ('column', BUDGET, { legend = 'top' })
  eq (legend_of (top), { 'Planned', 'Actual' })

  -- One series needs no legend, since the title names it.
  local single = draw ('column', { { 'k', 'Sales' }, { 'a', 1 }, { 'b', 2 } })
  eq (count (single, 'sc-legend'), 0)
end)

test ('a crowded legend counts what it leaves out', function ()
  local series = {} ---@type Sheet.ChartSeries[]
  for i = 1, 40 do
    series[i] = { name = 'Series with a long name ' .. i, values = { i, i } }
  end
  local data = { categories = { 'a', 'b' }, series = series }
  local svg = chart.render (spec ({}), data, { width = 480, height = 300 })
  valid (svg)
  local shown = #legend_of (svg)
  ok (shown > 3 and shown < 40, 'shown ' .. shown)
  ok (string.find (svg, '+' .. (40 - shown) .. ' more', 1, true))
  local right = chart.render (
    spec ({ legend = 'right' }),
    data,
    { width = 480, height = 300 }
  )
  valid (right)
  shown = #legend_of (right)
  ok (shown > 3 and shown < 40, 'shown ' .. shown)
  ok (string.find (right, '+' .. (40 - shown) .. ' more', 1, true))
end)

test ('every text is escaped', function ()
  local rows = {
    { 'Name & <co>', '"Q1" <b>' },
    { '<script>alert(1)</script>', 5 },
    { "it's", 6 },
  }
  local svg = draw ('column', rows, {
    title = 'Tom & "Jerry" <3',
    x_title = '<x>',
    y_title = 'a&b',
    legend = 'bottom',
  })
  valid (svg)
  ok (string.find (svg, 'Tom &amp; &quot;Jerry&quot; &lt;3', 1, true))
  ok (string.find (svg, '&lt;script&gt;', 1, true))
  ok (string.find (svg, 'it&#39;s', 1, true))
  eq (string.find (svg, '<script', 1, true), nil)
  eq (string.find (svg, '<b>', 1, true), nil)

  -- A colour from the spec cannot break out of its attribute either.
  local colors = draw ('pie', BUDGET, { colors = { '"><script>' } })
  valid (colors)
  eq (string.find (colors, '<script', 1, true), nil)
end)

test ('every chart type draws valid SVG from awkward data', function ()
  local awkward = {
    { 'A\1B', 'x\0y', 'Ünïcödé 数据' },
    { '日本語のとても長いカテゴリー名', 1e15, -1e-9 },
    { '', { code = '#REF!' }, 0 },
    { 'z', -0.0, 3 },
  }
  for _, t in ipairs (chart.types) do
    for _, rows in ipairs ({ BUDGET, PROFIT, awkward, wave (60) }) do
      for _, size in ipairs ({ { 480, 300 }, { 200, 140 }, { 90, 60 }, { 1, 1 } }) do
        local svg = draw (t.id, rows, {
          title = 'T',
          x_title = 'X',
          y_title = 'Y',
          stacked = true,
        }, { width = size[1], height = size[2] })
        local err = xml_error (svg)
        ok (err == nil, t.id .. ' at ' .. size[1] .. ': ' .. tostring (err))
      end
    end
  end
end)

test ('an empty range or one without numbers draws a message', function ()
  local empty = draw ('column', {})
  valid (empty)
  ok (string.find (empty, 'No data to chart', 1, true))
  eq (count (empty, 'sc-bar'), 0)

  local words = draw ('line', { { 'a', 'b' }, { 'c', 'd' } })
  ok (string.find (words, 'No numbers to chart', 1, true))

  local negative = draw ('pie', { { 'k', 'v' }, { 'a', -1 }, { 'b', 0 } })
  ok (string.find (negative, 'No positive numbers to chart', 1, true))

  local lonely = draw ('scatter', { { 'x', 'y' }, { 1, 'a' }, { nil, 2 } })
  ok (string.find (lonely, 'No points to chart', 1, true))
end)

test ('small charts drop the legend and axis titles first', function ()
  local extra = { title = 'Budget', x_title = 'Category', y_title = 'Dollars' }
  local small = draw ('column', BUDGET, extra, { width = 220, height = 180 })
  valid (small)
  eq (count (small, 'sc-legend'), 0)
  eq (count (small, 'sc-axis-title'), 0)
  eq (count (small, 'class="sc-title"'), 1)
  ok (#texts_in (small, 'sc-ticks') > 0)

  local tiny = draw ('column', BUDGET, extra, { width = 120, height = 90 })
  valid (tiny)
  eq (count (tiny, 'sc-ticks'), 0)
  eq (count (tiny, 'class="sc-bar"'), 12)
end)

test ('category labels thin out and long ones are cut short', function ()
  local svg = draw ('column', wave (60))
  local labels = texts_in (svg, 'sc-cats')
  ok (#labels < 60 and #labels > 3, 'labels ' .. #labels)
  eq (labels[1], 'D1')

  local long = draw ('column', {
    { 'k', 'v' },
    { 'An extremely long product name that will not fit anywhere at all', 1 },
    { 'Short', 2 },
  })
  local first = texts_in (long, 'sc-cats')[1]
  ok (string.find (first, '…$'), first)
  -- The tooltip keeps the whole name.
  ok (string.find (long, 'will not fit anywhere at all, v: 1', 1, true))
end)

test ('spec colours replace the palette in order', function ()
  local svg = draw ('column', BUDGET, { colors = { '#123456' } })
  ok (string.find (svg, 'fill="#123456"', 1, true))
  ok (string.find (svg, 'fill="' .. chart.palette[2] .. '"', 1, true))
  eq (string.find (svg, 'fill="' .. chart.palette[1] .. '"', 1, true), nil)
end)

test ('an unknown type draws a column chart', function ()
  local svg = chart.render (
    spec ({ type = 'radar' }),
    chart.data_from (BUDGET),
    { width = 480, height = 300 }
  )
  valid (svg)
  eq (count (svg, 'class="sc-bar"'), 12)
end)
