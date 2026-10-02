local lf = require ('log_filter') --[[@as Logs.FilterModule]]
local lq = require ('log_query') --[[@as Logs.QueryModule]]

---@param text string
---@return Logs.Query
local function q (text)
  return lf.parse_query (text)
end

---@param n integer
---@param text string
---@param prev? number
---@return Logs.Line
local function line (n, text, prev)
  return lf.make_line (n, text, false, prev)
end

-- 2024-03-01T12:00:00Z, in milliseconds since 1970.
local NOON = 1709294400000

test ('a /regular expression/ filters and hides lines', function ()
  local query = q ('/time(d)? ?out/ -/^debug/')
  eq (#query.regexes, 1)
  eq (#query.exclude_regexes, 1)
  ok (lf.matches ('Request TIMED OUT', query))
  ok (lf.matches ('timeout after 3s', query))
  ok (not lf.matches ('debug: timeout', query))
  ok (not lf.matches ('all good', query))
  ok (not lf.is_empty (query))
  local spaced = q ('/connection reset by/ peer')
  ok (lf.matches ('Connection reset by peer', spaced))
  eq (spaced.terms, { 'peer' })
  local slash = q ('/a\\/b/')
  ok (lf.matches ('path a/b', slash))
end)

test ('a broken regular expression says why and hides nothing', function ()
  local query = q ('/(oops/ error')
  eq (
    query.problem,
    'The regular expression /(oops/ is not valid: a ( has no ).'
  )
  eq (#query.regexes, 0)
  ok (lf.matches ('an error', query))
end)

test ('highlight marks what a regular expression matched', function ()
  eq (lf.highlight ('id=42 and id=7', q ('/id=\\d+/')), {
    { from = 1, to = 5 },
    { from = 11, to = 14 },
  })
end)

test (
  'make_line finds the time, and a line without one takes the last',
  function ()
    local first = line (1, '2024-03-01T12:00:00Z ERROR boom')
    eq (first.time, NOON)
    ok (first.stamped)
    local trace = line (2, '    at main (app.js:10:5)', first.time)
    eq (trace.time, NOON)
    ok (not trace.stamped)
    eq (line (3, 'no time').time, nil)
  end
)

test ('after: and before: keep a span of time', function ()
  local early = line (1, '2024-03-01T11:00:00Z early')
  local noon = line (2, '2024-03-01T12:00:00Z noon')
  local late = line (3, '2024-03-01T13:30:00Z late')
  local none = line (4, 'no time at all')
  local span = q ('after:2024-03-01T11:30 before:13:00')
  ok (lf.has_time (span))
  ok (not lf.matches_line (early, span))
  ok (lf.matches_line (noon, span))
  ok (not lf.matches_line (late, span))
  ok (
    not lf.matches_line (none, span),
    'a line with no time is outside any span'
  )
  local since = q ('since:-45m')
  ok (lf.matches_line (late, since, late.time))
  ok (not lf.matches_line (noon, since, late.time))
  ok (lf.matches_line (noon, q ('until:12:00')))
  eq (
    q ('after:soon').problem,
    'The time in after: is not one it reads. Write 2024-03-01T12:00, 12:00 or -15m.'
  )
  ok (lf.is_empty (q ('after:soon')))
end)

test ('matches_line keeps the lower-case text for the next filter', function ()
  local l = line (1, 'Hello World')
  eq (l.lower, nil)
  ok (lf.matches_line (l, q ('world')))
  eq (l.lower, 'hello world')
  ok (lf.matches_line (l, q ('level:other')), 'a level filter needs no text')
end)

test (
  'scan keeps every matching line, and the last few on their own',
  function ()
    local r = lf.ring (10)
    for i = 1, 6 do
      r:push (line (i, (i % 2 == 0 and 'ERROR ' or 'INFO ') .. i))
    end
    local result = lf.scan (r, q ('level:error'), {}, 2)
    eq (#result.all, 3)
    eq (result.matched, 3)
    eq ({ result.shown[1].n, result.shown[2].n }, { 4, 6 })
  end
)

test ('merge puts several sources in order of time', function ()
  local a = {
    line (1, '2024-03-01T12:00:00Z a1'),
    line (2, '2024-03-01T12:00:02Z a2'),
    line (3, '  a2 goes on', NOON + 2000),
  }
  local b = {
    line (1, '2024-03-01T12:00:01Z b1'),
    line (2, '2024-03-01T12:00:03Z b2'),
  }
  for i, l in ipairs (a) do
    l.id = i
  end
  for i, l in ipairs (b) do
    l.id = 10 + i
  end
  local merged = lf.merge ({ a, b })
  local texts = {} ---@type string[]
  for i, l in ipairs (merged) do
    texts[i] = l.plain:match ('(%S+)$')
  end
  eq (texts, { 'a1', 'b1', 'a2', 'on', 'b2' })
  eq (
    lf.newest ((function ()
      local r = lf.ring (5)
      for _, l in ipairs (a) do
        r:push (l)
      end
      r:push (line (4, 'no time'))
      return r
    end) ()),
    NOON + 2000
  )
end)

test ('a whole file reads from its first line', function ()
  eq ({ lf.follow_command ('/var/log/a.log', 'linux', true) }, {
    'tail',
    { '-n', '+1', '-F', '/var/log/a.log' },
  })
  local _, args = lf.follow_command ('C:\\a.log', 'windows', true)
  ok (not args[3]:find ('-Tail', 1, true))
  ok (
    lf.spec_key ({ kind = 'file', path = '/a' })
      ~= lf.spec_key ({ kind = 'file', path = '/a', whole = true })
  )
  eq (lf.clean_specs ({ { kind = 'file', path = '/a', whole = true } }), {
    { kind = 'file', path = '/a', whole = true },
  })
end)

test (
  'row_html names the source and carries the line id in the merged view',
  function ()
    local l = line (7, 'hello')
    l.id = 99
    local html = lf.row_html (l, q (''), { name = 'app.log', n = 2 })
    ok (html:find ('data-item="99"', 1, true))
    ok (html:find ('<span class="logs-tag logs-tag-2">app.log</span>', 1, true))
    ok (lf.row_html (line (7, 'x'), q ('')):find ('data-item="7"', 1, true))
  end
)

-- log_query ---------------------------------------------------------------------------------

test ('log_filter hands out the filter of log_query', function ()
  ok (lf.parse_query == lq.parse_query)
  ok (lf.is_empty == lq.is_empty)
  ok (lf.has_time == lq.has_time)
  ok (lf.matches == lq.matches)
  ok (lf.matches_line == lq.matches_line)
  ok (lf.highlight == lq.highlight)
end)

test ('a regular expression reads an escaped slash', function ()
  local query = lq.parse_query ('/a\\/b/')
  eq (query.problem, nil)
  ok (lq.matches ('x a/b y', query))
  ok (not lq.matches ('x a b y', query))
end)

test ('matches_line checks the level before the words', function ()
  local query = lq.parse_query ('-level:debug boom')
  ok (lq.matches_line (line (1, 'ERROR boom'), query))
  ok (not lq.matches_line (line (2, 'DEBUG boom'), query))
  ok (not lq.matches_line (line (3, 'ERROR bang'), query))
end)

test ('matches finds the level only when the query needs it', function ()
  ok (lq.matches ('DEBUG boom', lq.parse_query ('boom')))
  ok (lq.matches ('DEBUG boom', lq.parse_query ('level:error'), 'error'))
  ok (not lq.matches ('DEBUG boom', lq.parse_query ('level:error')))
end)

test (
  'is:marked keeps the bookmarked lines, and -is:marked hides them',
  function ()
    local marked = line (1, 'kept')
    marked.marked = true
    local plain = line (2, 'other')
    local query = q ('is:marked')
    ok (query.marked)
    ok (not lf.is_empty (query))
    ok (lf.matches_line (marked, query))
    ok (not lf.matches_line (plain, query))
    local hide = q ('-is:bookmarked')
    ok (not lf.matches_line (marked, hide))
    ok (lf.matches_line (plain, hide))
  end
)
