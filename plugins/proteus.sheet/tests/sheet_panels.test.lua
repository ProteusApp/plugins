-- Tests for sheet_panel_text: the rule descriptions, the quick sum, the sort and chart blocks,
-- and the small parsers behind the Sheet app's toolbar and panels.

local m = require ('sheet_model') --[[@as Sheet.ModelModule]]
local ops = require ('sheet_ops') --[[@as Sheet.OpsModule]]
local t = require ('sheet_panel_text') --[[@as Sheet.PanelTextModule]]

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
  local s = m.new ()
  for addr, text in pairs (cells or {}) do
    local row, col = m.parse_address (addr)
    assert (row and col, addr)
    s:set (row --[[@as integer]], col --[[@as integer]], text)
  end
  return s
end

test ('rules read as one short line', function ()
  eq (
    t.describe_rule ({
      range = 'A1:A9',
      type = 'compare',
      op = '>',
      value = '100',
    }),
    'Greater than 100'
  )
  eq (
    t.describe_rule ({
      range = 'A1',
      type = 'compare',
      op = 'between',
      value = '1',
      value2 = '9',
    }),
    'Is between 1 and 9'
  )
  eq (
    t.describe_rule ({
      range = 'A1',
      type = 'text',
      op = 'contains',
      value = 'late',
    }),
    'Text contains "late"'
  )
  eq (t.describe_rule ({ range = 'A1', type = 'blank' }), 'Is empty')
  eq (t.describe_rule ({ range = 'A1', type = 'top', count = 3 }), 'Top 3')
  eq (
    t.describe_rule ({
      range = 'A1',
      type = 'bottom',
      count = 10,
      percent = true,
    }),
    'Bottom 10%'
  )
  eq (
    t.describe_rule ({ range = 'A1', type = 'formula', formula = '=$B1>5' }),
    'Formula =$B1>5'
  )
  eq (
    t.describe_rule ({
      range = 'A1',
      type = 'scale',
      min_color = '#ff0000',
      max_color = '#00ff00',
    }),
    'Colour scale'
  )
  eq (t.describe_rule ({ range = 'A1', type = 'nonsense' }), 'Unknown rule')
end)

test ('a form condition turns into rule fields and back', function ()
  eq (t.rule_fields ('>=', '5'), { type = 'compare', op = '>=', value = '5' })
  eq (
    t.rule_fields ('not_between', '1', '2'),
    { type = 'compare', op = 'not_between', value = '1', value2 = '2' }
  )
  eq (t.rule_fields ('top_percent', '15'), {
    type = 'top',
    count = 15,
    percent = true,
  })
  eq (t.rule_fields ('bottom', 'x'), { type = 'bottom', count = 10 })
  eq (t.rule_fields ('formula', 'B1>2'), { type = 'formula', formula = '=B1>2' })
  eq (t.rule_fields ('duplicate'), { type = 'duplicate' })
  for _, c in ipairs (t.CONDITIONS) do
    local fields = t.rule_fields (c.id, '1', '2')
    fields.range = 'A1'
    eq (
      t.condition_of (fields --[[@as Sheet.Rule]]),
      c.id,
      'round trip of ' .. c.id
    )
  end
end)

test ('the filter menu offers only the tests a filter can run', function ()
  local ids = {} ---@type string[]
  for _, c in ipairs (t.CONDITIONS) do
    if c.filter then
      ids[#ids + 1] = c.id
    end
  end
  eq (#ids, 15)
  local s = sheet_of ({ A1 = 'Name', A2 = 'apple', A3 = 'pear', A4 = '' })
  ops.set_filter (s, r ('A1:A4'))
  for _, c in ipairs (t.CONDITIONS) do
    if c.filter then
      ok (
        ops.filter_column (
          s,
          1,
          { op = c.op or c.id, value = 'a', value2 = 'z' }
        ),
        c.id
      )
    end
  end
end)

test ('validation rules read as one short line', function ()
  eq (
    t.describe_validation ({
      range = 'A1',
      type = 'list',
      values = { 'OK', 'Over' },
    }),
    'List: OK, Over'
  )
  eq (
    t.describe_validation ({
      range = 'A1',
      type = 'number',
      op = 'between',
      value = '1',
      value2 = '9',
    }),
    'Number between 1 and 9'
  )
  eq (
    t.describe_validation ({
      range = 'A1',
      type = 'number',
      op = '>',
      value = '0',
      integer = true,
    }),
    'Whole number greater than 0'
  )
  eq (t.describe_validation ({ range = 'A1', type = 'number' }), 'Any number')
end)

test ('a list box splits by lines, or by commas on one line', function ()
  eq (t.list_values ('OK, Over ,, OK'), { 'OK', 'Over' })
  eq (t.list_values ('Yes, please\nNo\n\n'), { 'Yes, please', 'No' })
  eq (t.list_values (''), {})
end)

test ('every number format shows a sample', function ()
  local by_id = {} ---@type table<string, string>
  for _, choice in ipairs (t.format_choices ()) do
    ok (choice.example ~= '', choice.id)
    by_id[choice.id] = choice.example
  end
  eq (by_id.currency, '$1,000.12')
  eq (by_id.percent, '10.12%')
  eq (by_id.financial, '(1,000.12)')
  eq (by_id.date, '9/29/2026')
end)

test ('colours and sizes typed by hand', function ()
  eq (t.parse_color ('#FFAA00'), '#ffaa00')
  eq (t.parse_color (' abc '), '#aabbcc')
  eq (t.parse_color ('#12345'), nil)
  eq (t.parse_color ('red'), nil)
  eq (t.parse_size ('14'), 14)
  eq (t.parse_size ('10.26'), 10.5)
  eq (t.parse_size ('2'), nil)
  eq (t.parse_size ('big'), nil)
  eq (#t.COLORS, 50)
  eq (t.is_dark ('#000000'), true)
  eq (t.is_dark ('#3c78d8'), true)
  eq (t.is_dark ('#ffff00'), false)
  eq (t.is_dark ('#f4cccc'), false)
end)

test ('the find count', function ()
  eq (t.match_label (nil, 0), 'No matches')
  eq (t.match_label (nil, 1), '1 match')
  eq (t.match_label (nil, 4), '4 matches')
  eq (t.match_label (3, 12), '3 of 12')
end)

test (
  'a quick sum in one cell adds the numbers above, or else to the left',
  function ()
    local s = sheet_of ({
      B1 = 'Cost',
      B2 = '5',
      B3 = '7',
      B4 = '=B2+B3',
      D2 = '1',
      E2 = '2',
    })
    eq (t.sum_range (s, 5, 2), r ('B2:B4'))
    eq (t.sum_plan (s, r ('B5'), 5, 2, 'SUM'), { text = '=SUM(B2:B4)' })
    eq (t.sum_plan (s, r ('F2'), 2, 6, 'MAX'), { text = '=MAX(D2:E2)' })
    eq (t.sum_plan (s, r ('H9'), 9, 8, 'AVERAGE'), { text = '=AVERAGE(' })
  end
)

test ('a quick sum over a block fills under each column', function ()
  local s = sheet_of ({
    A1 = 'Name',
    B1 = '1',
    C1 = '2',
    A2 = 'x',
    B2 = '3',
    C2 = '4',
  })
  eq (t.sum_plan (s, r ('A1:C2'), 1, 1, 'SUM'), {
    cells = { { 3, 2, '=SUM(B1:B2)' }, { 3, 3, '=SUM(C1:C2)' } },
    rect = r ('A3:C3'),
  })
  -- An empty last row takes the sums itself.
  eq (t.sum_plan (s, r ('B1:C3'), 1, 2, 'SUM'), {
    cells = { { 3, 2, '=SUM(B1:B2)' }, { 3, 3, '=SUM(C1:C2)' } },
    rect = r ('B3:C3'),
  })
  eq (t.sum_plan (s, r ('B1:C1'), 1, 2, 'COUNT'), {
    cells = { { 1, 4, '=COUNT(B1:C1)' } },
    rect = r ('D1'),
  })
  eq (t.sum_plan (s, r ('A1:A2'), 1, 1, 'SUM'), { cells = {}, rect = r ('A3') })
  -- A total already under the block stops the sums from writing over it.
  s:set (3, 2, 'Total')
  eq (t.sum_plan (s, r ('B1:C2'), 1, 2, 'SUM').busy, true)
  eq (t.sum_plan (s, r ('B1:C1'), 1, 2, 'SUM').busy, nil)
end)

test ('a quick sort picks the filter, the selection or the sheet', function ()
  local s = sheet_of ({
    A1 = 'Title',
    A2 = 'Name',
    B2 = 'Score',
    A3 = 'b',
    B3 = '2',
    A4 = 'a',
    B4 = '1',
  })
  local block, header = t.sort_block (s, r ('B3'), 3, 2)
  eq ({ block, header }, { r ('A1:B4'), false })
  s:set_freeze (2, 0)
  block, header = t.sort_block (s, r ('B3'), 3, 2)
  eq ({ block, header }, { r ('A3:B4'), false })
  block, header = t.sort_block (s, r ('A3:A4'), 3, 1)
  eq ({ block, header }, { r ('A3:A4'), false })
  ops.set_filter (s, r ('A2:B4'))
  block, header = t.sort_block (s, r ('B3'), 3, 2)
  eq ({ block, header }, { r ('A2:B4'), true })
  local empty = sheet_of ()
  eq ({ t.sort_block (empty, r ('A1'), 1, 1) }, { nil, false })
end)

test ('a new chart reads the selection or the block around the cell', function ()
  local s = sheet_of ({ A1 = 'Month', B1 = 'Sales', A2 = 'Jan', B2 = '5' })
  eq (t.chart_block (s, r ('B2'), 2, 2), r ('A1:B2'))
  eq (t.chart_block (s, r ('A1:A2'), 1, 1), r ('A1:A2'))
  eq (t.chart_block (s, r ('F9'), 9, 6), nil)
end)

test ('a first row of text over numbers reads as a header', function ()
  local s = sheet_of ({
    A1 = 'Name',
    B1 = 'Score',
    A2 = 'Ann',
    B2 = '7',
    A3 = 'Bo',
    B3 = '9',
  })
  eq (t.guess_header (s, r ('A1:B3')), true)
  eq (t.guess_header (s, r ('A2:B3')), false)
  eq (t.guess_header (s, r ('A1:A3')), false)
  eq (t.guess_header (s, r ('A1:B1')), false)
  ops.set_filter (s, r ('A1:A3'))
  eq (t.guess_header (s, r ('A1:A3')), true)
end)

test ('columns are named by letter and header', function ()
  local s = sheet_of ({ B1 = 'Score' })
  eq (t.column_label (s, 1, 2), 'Column B: Score')
  eq (t.column_label (s, 1, 3), 'Column C')
  eq (t.column_label (s, nil, 2), 'Column B')
end)
