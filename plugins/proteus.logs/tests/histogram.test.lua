local lf = require ('log_filter') --[[@as Logs.FilterModule]]
local lh = require ('log_histogram') --[[@as Logs.HistogramModule]]

-- 2024-03-01T12:00:00Z, in milliseconds since 1970.
local NOON = 1709294400000

---@param texts string[]
---@return Logs.Line[]
local function lines_of (texts)
  local out = {} ---@type Logs.Line[]
  local prev = nil ---@type number?
  for i, text in ipairs (texts) do
    out[i] = lf.make_line (i, text, false, prev)
    prev = out[i].time
  end
  return out
end

test ('log_filter hands out log_histogram', function ()
  ok (lf.histogram == lh.build)
  ok (lf.with_range == lh.with_range)
  ok (lf.without_range == lh.without_range)
end)

test ('build cuts the time into round bars, and counts each level', function ()
  local lines = lines_of ({
    '2024-03-01T12:00:05Z ERROR a',
    '2024-03-01T12:00:20Z INFO b',
    '    at a trace line',
    '2024-03-01T12:04:59Z WARN c',
  })
  local h = assert (lh.build (lines, 1, 10))
  eq (h.step, 30000, 'five minutes in ten bars of 30 seconds')
  eq (h.from, NOON)
  eq (#h.bins, 10)
  eq (h.bins[1].total, 3, 'a line with no time counts with the line above')
  eq (h.bins[1].levels.error, 1)
  eq (h.bins[10].levels.warn, 1)
  eq (h.max, 3)
  eq (h.lines, 4)
  local later = assert (lh.build (lines, 4, 10))
  eq (later.lines, 1, 'it counts from `first` on')
  eq (lh.build (lines_of ({ 'no time here' }), 1, 10), nil)
  local one = assert (lh.build (lines_of ({ '2024-03-01T12:00:00Z x' }), 1, 10))
  eq (#one.bins, 1)
end)

test ('span gives the time of a run of bars, in either order', function ()
  local h = assert (
    lh.build (
      lines_of ({ '2024-03-01T12:00:00Z a', '2024-03-01T12:09:00Z b' }),
      1,
      10
    )
  )
  eq (h.step, 60000)
  eq ({ lh.span (h, 3, 2) }, { NOON + 60000, NOON + 3 * 60000 - 1 })
end)

test ('the axis says how long a bar is and when it starts', function ()
  eq (lh.step_text (5 * 60000), '5 minutes')
  eq (lh.step_text (1000), '1 second')
  eq (lh.step_text (500), '500 milliseconds')
  eq (lh.step_text (2 * 86400000), '2 days')
  eq (lh.time_label (NOON, 60000), '2024-03-01 12:00')
  eq (lh.time_label (NOON, 1000), '2024-03-01 12:00:00')
  eq (lh.time_label (NOON + 250, 100), '2024-03-01 12:00:00.250')
  eq (lh.time_label (NOON, 86400000), '2024-03-01')
  eq (lh.time_label (3600000, 60000), '01:00', 'a time of day shows no date')
end)

test ('bars_html stacks each level and names each bar', function ()
  local h = assert (lh.build (
    lines_of ({
      '2024-03-01T12:00:00Z ERROR a',
      '2024-03-01T12:00:00Z INFO b',
      '2024-03-01T12:00:02Z INFO c',
    }),
    1,
    2
  ))
  local html = lh.bars_html (h)
  ok (
    html:find (
      '<div class="logs-hbin" data-item="1" title="2024-03-01 12:00:00 to 2024-03-01 12:00:02: 2 lines, 1 error"><i class="logs-hb-error" style="height:50.00%"></i><i class="logs-hb-info" style="height:50.00%"></i></div>',
      1,
      true
    ),
    html
  )
  ok (html:find ('data-item="2"', 1, true), html)
end)

test (
  'with_range puts a span in the filter, and it keeps those lines',
  function ()
    eq (
      lh.with_range ('error after:-15m  BEFORE:12:00', NOON, NOON + 59999),
      'error after:2024-03-01T12:00:00 before:2024-03-01T12:00:59.999'
    )
    eq (
      lh.with_range ('', NOON, NOON + 999),
      'after:2024-03-01T12:00:00 before:2024-03-01T12:00:00.999'
    )
    eq (lh.without_range ('a since:1 b until:2 c'), 'a b c')
    local query = lf.parse_query (lh.with_range ('', NOON, NOON + 59999))
    eq (query.problem, nil)
    local lines = lines_of ({
      '2024-03-01T11:59:59.999Z early',
      '2024-03-01T12:00:00Z first',
      '2024-03-01T12:00:59.999Z last',
      '2024-03-01T12:01:00Z late',
    })
    local kept = {} ---@type integer[]
    for _, l in ipairs (lines) do
      if lf.matches_line (l, query) then
        kept[#kept + 1] = l.n
      end
    end
    eq (kept, { 2, 3 })
  end
)
