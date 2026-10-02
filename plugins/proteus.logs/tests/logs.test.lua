local lf = require ('log_filter') --[[@as Logs.FilterModule]]

local ESC = '\27'

---@param text string
---@return Logs.Query
local function q (text)
  return lf.parse_query (text)
end

---@param lines string[]
---@param capacity? integer
---@return Logs.Ring
local function ring_of (lines, capacity)
  local r = lf.ring (capacity or 100)
  for i, text in ipairs (lines) do
    r:push (lf.make_line (i, text, false))
  end
  return r
end

-- parse_query ------------------------------------------------------------------------------

test ('parse_query splits words, exclusions, phrases and a level', function ()
  local query = q ('Timeout -health "connection reset" level:error')
  eq (query.terms, { 'timeout' })
  eq (query.exclude, { 'health' })
  eq (query.phrases, { 'connection reset' })
  eq (query.level, 'error')
end)

test ('parse_query reads an empty or blank filter as no filter', function ()
  ok (lf.is_empty (q ('')))
  ok (lf.is_empty (q ('   ')))
  ok (not lf.is_empty (q ('x')))
  ok (not lf.is_empty (q ('level:warn')))
end)

test ('parse_query takes level names, short forms and prefixes', function ()
  eq (q ('level:warning').level, 'warn')
  eq (q ('level:WARN').level, 'warn')
  eq (q ('level:err').level, 'error')
  eq (q ('level:e').level, 'error')
  eq (q ('level:i').level, 'info')
  eq (q ('level:trace').level, 'debug')
  eq (q ('level:other').level, 'other')
end)

test ('parse_query keeps an unknown level as a plain word', function ()
  local query = q ('level:banana')
  eq (query.level, nil)
  eq (query.terms, { 'level:banana' })
  local half = q ('level:')
  eq (half.level, nil)
  eq (half.terms, {})
end)

test ('parse_query reads -level: as every level but that one', function ()
  local query = q ('-level:error -level:w boom')
  eq (query.skip, { error = true, warn = true })
  eq (query.level, nil)
  eq (query.exclude, {})
  eq (query.terms, { 'boom' })
  ok (not lf.is_empty (q ('-level:debug')))
  eq (q ('-level:banana').exclude, { 'level:banana' })
end)

test (
  'parse_query handles a lone dash, an open quote and an excluded phrase',
  function ()
    eq (q ('a - b').terms, { 'a', '-', 'b' })
    eq (q ('"not closed').phrases, { 'not closed' })
    eq (q ('-"two words" x').exclude, { 'two words' })
    eq (q ('-"two words" x').terms, { 'x' })
  end
)

-- detect_level -----------------------------------------------------------------------------

test ('detect_level finds a level word near the start', function ()
  eq (lf.detect_level ('2024-01-01 12:00:00 ERROR could not connect'), 'error')
  eq (lf.detect_level ('2024-01-01 12:00:00 WARN disk almost full'), 'warn')
  eq (lf.detect_level ('INFO:root:hello'), 'info')
  eq (lf.detect_level ('DEBUG entering loop'), 'debug')
  eq (lf.detect_level ('TRACE entering loop'), 'debug')
  eq (lf.detect_level ('npm ERR! code E404'), 'error')
  eq (lf.detect_level ('FATAL out of memory'), 'error')
  eq (lf.detect_level ('panic: runtime error'), 'error')
  eq (lf.detect_level ('CRITICAL database gone'), 'error')
  eq (lf.detect_level ('[2024-01-01T00:00:00Z WARNING app] slow'), 'warn')
end)

test (
  'detect_level reads any case when the word starts the line or is a tag',
  function ()
    eq (lf.detect_level ('error: failed to compile'), 'error')
    eq (lf.detect_level ('Error: Cannot find module'), 'error')
    eq (lf.detect_level ('12:00:01 info  server started'), 'info')
    eq (lf.detect_level ('src/main.c:10:5: warning: unused variable'), 'warn')
    eq (lf.detect_level ('[debug] cache hit'), 'debug')
    eq (lf.detect_level ('production.error: boom'), 'error')
  end
)

test ('detect_level leaves a level word inside a sentence alone', function ()
  eq (lf.detect_level ('Connected, and no error so far'), 'other')
  eq (lf.detect_level ('The request finished and an error was logged'), 'other')
  eq (lf.detect_level ('errors: 0'), 'other')
  eq (lf.detect_level ('error_count 3'), 'other')
  eq (lf.detect_level ('    at Object.<anonymous> (x.js:1:1)'), 'other')
  eq (lf.detect_level (''), 'other')
end)

test (
  'detect_level looks only at the first 80 characters for a bare word',
  function ()
    local pad = string.rep ('x', 85)
    eq (lf.detect_level (pad .. ' ERROR late'), 'other')
    eq (lf.detect_level (string.rep ('y', 70) .. ' ERROR'), 'error')
  end
)

test ('detect_level reads bracketed letters', function ()
  eq (lf.detect_level ('[E] boom'), 'error')
  eq (lf.detect_level ('[W] careful'), 'warn')
  eq (lf.detect_level ('12:00 [I] started'), 'info')
  eq (lf.detect_level ('[D] detail'), 'debug')
  eq (lf.detect_level ('[X] unknown'), 'other')
end)

test ('detect_level reads JSON fields anywhere in the line', function ()
  eq (lf.detect_level ('{"level":"error","msg":"x"}'), 'error')
  eq (lf.detect_level ('{"severity": "warning"}'), 'warn')
  eq (lf.detect_level ('{"msg":"ERROR in the text","level":"info"}'), 'info')
  eq (lf.detect_level ('{"Level":"Information"}'), 'info')
  eq (lf.detect_level ('{"@l":"W"}'), 'warn')
  eq (lf.detect_level ('{"level":50,"msg":"boom"}'), 'error')
  eq (lf.detect_level ('{"level":30,"msg":"fine"}'), 'info')
  local long = '{"msg":"' .. string.rep ('a', 120) .. '","level":"debug"}'
  eq (lf.detect_level (long), 'debug')
end)

test ('detect_level reads logfmt fields', function ()
  eq (lf.detect_level ('time=2024-01-01 level=warn msg="disk"'), 'warn')
  eq (lf.detect_level ('ts=1 lvl=ERROR msg=x'), 'error')
  eq (lf.detect_level ('sublevel=error x'), 'other')
  eq (lf.detect_level ('msg="level=error in config" level=info'), 'info')
  eq (lf.detect_level ('msg="say \\"level=error\\"" lvl=debug'), 'debug')
  eq (lf.detect_level ('msg="level=error in config"'), 'other')
  eq (lf.detect_level ("level='warning' msg=x"), 'warn')
  eq (lf.detect_level ('severity=E msg=x'), 'error')
end)

test ('detect_level reads glog and klog lines', function ()
  eq (
    lf.detect_level ('E1001 12:00:00.000000 1 file.go:12] could not sync'),
    'error'
  )
  eq (lf.detect_level ('W0102 03:04:05.678901   42 main.go:7] slow'), 'warn')
  eq (
    lf.detect_level ('I0102 03:04:05.678901 42 main.go:7] ERROR in text'),
    'info'
  )
  eq (lf.detect_level ('F1231 23:59:59.000000 1 x.go:1] gone'), 'error')
  eq (lf.detect_level ('E1001 is a model number'), 'other')
end)

test ('detect_level sees through colour codes', function ()
  eq (lf.detect_level (ESC .. '[31mERROR' .. ESC .. '[0m boom'), 'error')
  eq (lf.detect_level (ESC .. '[33m[W]' .. ESC .. '[0m careful'), 'warn')
end)

test ('detect_level picks the first level when a line has two', function ()
  eq (lf.detect_level ('[INFO] request failed: ERROR 500'), 'info')
end)

-- matches and highlight --------------------------------------------------------------------

test ('matches needs every word, in any case', function ()
  ok (lf.matches ('Connection TIMEOUT on db', q ('timeout db')))
  ok (not lf.matches ('Connection TIMEOUT', q ('timeout db')))
  ok (lf.matches ('anything', q ('')))
end)

test ('matches hides excluded words and needs whole phrases', function ()
  ok (not lf.matches ('GET /health 200', q ('-health')))
  ok (lf.matches ('GET /users 200', q ('-health')))
  ok (lf.matches ('connection reset by peer', q ('"connection reset"')))
  ok (not lf.matches ('reset the connection', q ('"connection reset"')))
  ok (not lf.matches ('a two words b', q ('-"two words"')))
end)

test ('matches keeps only the chosen level', function ()
  ok (lf.matches ('ERROR boom', q ('level:error')))
  ok (not lf.matches ('INFO fine', q ('level:error')))
  ok (lf.matches ('whatever', q ('level:error'), 'error'))
  ok (not lf.matches ('ERROR boom', q ('level:error boom -boom')))
end)

test ('matches hides the levels -level: names', function ()
  ok (not lf.matches ('ERROR boom', q ('-level:error')))
  ok (lf.matches ('INFO fine', q ('-level:error')))
  ok (lf.matches ('level error in the text', q ('-level:error')))
  ok (not lf.matches ('whatever', q ('-level:other')))
  ok (not lf.matches ('INFO fine', q ('-level:error -level:info')))
end)

test ('matches ignores colour codes', function ()
  local line = ESC .. '[31mERR' .. ESC .. '[0mOR here'
  ok (lf.matches (line, q ('error')))
  ok (not lf.matches (ESC .. '[31mx', q ('31m')))
end)

test ('highlight finds each match and joins overlaps', function ()
  eq (lf.highlight ('abc abc', q ('b')), {
    { from = 2, to = 2 },
    { from = 6, to = 6 },
  })
  eq (lf.highlight ('abcdef', q ('abc cde')), { { from = 1, to = 5 } })
  eq (lf.highlight ('abcdef', q ('ab cd')), { { from = 1, to = 4 } })
  eq (lf.highlight ('Hello World', q ('"o w"')), { { from = 5, to = 7 } })
  eq (lf.highlight ('abc', q ('-a level:error')), {})
end)

-- ANSI -------------------------------------------------------------------------------------

test ('strip_ansi drops colour codes and other escape sequences', function ()
  eq (lf.strip_ansi ('plain'), 'plain')
  eq (lf.strip_ansi (ESC .. '[1;31mred' .. ESC .. '[0m'), 'red')
  eq (lf.strip_ansi (ESC .. '[2K' .. ESC .. '[1Gdone'), 'done')
  eq (lf.strip_ansi (ESC .. ']0;title\7text'), 'text')
  eq (
    lf.strip_ansi (
      ESC .. ']8;;http://x' .. ESC .. '\\link' .. ESC .. ']8;;' .. ESC .. '\\'
    ),
    'link'
  )
  eq (lf.strip_ansi (ESC .. '(Bx'), 'x')
  eq (lf.strip_ansi ('a\rb\0c\tt'), 'abc\tt')
  eq (lf.strip_ansi ('cut ' .. ESC), 'cut ')
end)

test ('parse_ansi turns SGR codes into colour runs', function ()
  eq (
    lf.parse_ansi (
      'x'
        .. ESC
        .. '[31mred'
        .. ESC
        .. '[1mbold'
        .. ESC
        .. '[22mthin'
        .. ESC
        .. '[39mdef'
    ),
    {
      { text = 'x', bold = false },
      { text = 'red', fg = 1, bold = false },
      { text = 'bold', fg = 1, bold = true },
      { text = 'thin', fg = 1, bold = false },
      { text = 'def', bold = false },
    }
  )
  eq (lf.parse_ansi (ESC .. '[92mok' .. ESC .. '[m.'), {
    { text = 'ok', fg = 10, bold = false },
    { text = '.', bold = false },
  })
  eq (lf.parse_ansi (''), {})
end)

test (
  'parse_ansi reads 256-colour codes without mistaking their numbers',
  function ()
    eq (
      lf.parse_ansi (ESC .. '[38;5;9ma'),
      { { text = 'a', fg = 9, bold = false } }
    )
    eq (lf.parse_ansi (ESC .. '[38;5;200ma'), { { text = 'a', bold = false } })
    eq (
      lf.parse_ansi (ESC .. '[38;2;1;31;1ma'),
      { { text = 'a', bold = false } }
    )
    eq (
      lf.parse_ansi (ESC .. '[48;5;1;32ma'),
      { { text = 'a', fg = 2, bold = false } }
    )
  end
)

test ('parse_ansi joins runs that end up the same colour', function ()
  eq (
    lf.parse_ansi (ESC .. '[31ma' .. ESC .. '[31mb'),
    { { text = 'ab', fg = 1, bold = false } }
  )
end)

-- render_line and row_html -----------------------------------------------------------------

test ('render_line escapes the text', function ()
  eq (
    lf.render_line ('<a href="x">&\'', q ('')),
    '&lt;a href=&quot;x&quot;&gt;&amp;&#39;'
  )
end)

test ('render_line colours runs and marks matches', function ()
  eq (
    lf.render_line (ESC .. '[1;32mok' .. ESC .. '[0m done', q ('')),
    '<span class="logs-c2 logs-b">ok</span> done'
  )
  eq (
    lf.render_line ('a timeout here', q ('timeout')),
    'a <mark>timeout</mark> here'
  )
  eq (lf.render_line ('<b>', q ('b')), '&lt;<mark>b</mark>&gt;')
end)

test ('render_line marks a match that crosses a colour change', function ()
  local line = ESC .. '[31mERR' .. ESC .. '[0mOR here'
  eq (
    lf.render_line (line, q ('error')),
    '<span class="logs-c1"><mark>ERR</mark></span><mark>OR</mark> here'
  )
  local three = 'a' .. ESC .. '[32mb' .. ESC .. '[33mc' .. ESC .. '[0md'
  eq (
    lf.render_line (three, q ('abcd')),
    '<mark>a</mark><span class="logs-c2"><mark>b</mark></span><span class="logs-c3"><mark>c</mark></span><mark>d</mark>'
  )
end)

test ('render_line marks two matches in one run', function ()
  eq (
    lf.render_line ('x a y a z', q ('a')),
    'x <mark>a</mark> y <mark>a</mark> z'
  )
end)

test ('row_html tags the row with its number, level and stream', function ()
  local line = lf.make_line (42, 'ERROR <boom>', true)
  eq (
    lf.row_html (line, q ('')),
    '<div class="logs-row logs-lv-error logs-stderr" data-item="42"><span class="logs-n">42</span><span class="logs-t">ERROR &lt;boom&gt;</span></div>'
  )
end)

test ('row_html cuts a very long line short', function ()
  local line = lf.make_line (1, string.rep ('a', 5000), false)
  local html = lf.row_html (line, q (''))
  ok (#html < 4200, 'the row is cut')
  ok (html:find ('logs-more', 1, true), 'the row shows that it is cut')
  eq (#line.text, 5000, 'the line itself keeps its text')
end)

test ('clip never splits a UTF-8 character', function ()
  eq (lf.clip ('héllo', 2), 'h')
  eq (lf.clip ('héllo', 3), 'hé')
  eq (lf.clip ('abc', 10), 'abc')
end)

-- JSON -------------------------------------------------------------------------------------

test ('find_json takes a whole line of JSON', function ()
  eq (lf.find_json ('{"a":1,"b":[true,null]}'), '{"a":1,"b":[true,null]}')
  eq (lf.find_json ('  [1, 2, 3]  '), '[1, 2, 3]')
end)

test ('find_json takes JSON after a prefix', function ()
  eq (lf.find_json ('2024-01-01T00:00:00Z {"msg":"hi"}'), '{"msg":"hi"}')
  eq (lf.find_json ('[2024-01-01] INFO {"msg":"[x]"}'), '{"msg":"[x]"}')
  eq (lf.find_json ('[1] started {"ok":true}'), '{"ok":true}')
  eq (lf.find_json (ESC .. '[32mINFO' .. ESC .. '[0m {"a":"b"}'), '{"a":"b"}')
end)

test ('find_json refuses text that is not JSON', function ()
  eq (lf.find_json ('no json here'), nil)
  eq (lf.find_json ('[INFO] started'), nil)
  eq (lf.find_json ('{"a":1} and more'), nil)
  eq (lf.find_json ("{'a':1}"), nil)
  eq (lf.find_json ('{"a":01}'), nil)
  eq (lf.find_json ('{"a":1,}'), nil)
  eq (lf.find_json ('items: []'), nil)
  eq (lf.find_json ('{"a":"tab\there"}'), nil)
end)

test ('find_json reads escapes, numbers and nesting', function ()
  local text = '{"s":"a\\"b\\u00e9\\n","n":-1.5e+3,"z":0,"o":{"p":[[],{}]}}'
  eq (lf.find_json (text), text)
end)

test ('find_json gives up on very deep nesting', function ()
  local deep = string.rep ('[', 200) .. string.rep (']', 200)
  eq (lf.find_json (deep), nil)
end)

test ('pretty_json lays JSON out and keeps key order', function ()
  eq (
    lf.pretty_json ('{"b":1,"a":[1,2],"e":{},"f":[]}'),
    table.concat ({
      '{',
      '  "b": 1,',
      '  "a": [',
      '    1,',
      '    2',
      '  ],',
      '  "e": {},',
      '  "f": []',
      '}',
    }, '\n')
  )
  eq (lf.pretty_json ('"x"'), '"x"')
  eq (lf.pretty_json ('{"a":'), nil)
  eq (lf.pretty_json ('{} x'), nil)
end)

-- make_line and the ring -------------------------------------------------------------------

test (
  'make_line keeps the raw text and finds the plain text and level',
  function ()
    local line = lf.make_line (7, ESC .. '[31mERROR' .. ESC .. '[0m x', true)
    eq (line.n, 7)
    eq (line.plain, 'ERROR x')
    eq (line.level, 'error')
    eq (line.err, true)
    eq (lf.make_line (1, 'x').err, false)
  end
)

test ('the ring keeps the newest lines and reports the one it drops', function ()
  local r = lf.ring (3)
  eq (r:count (), 0)
  eq (r:get (1), nil)
  for i = 1, 3 do
    eq (r:push (lf.make_line (i, 'l' .. i)), nil)
  end
  eq (r:count (), 3)
  local dropped = r:push (lf.make_line (4, 'l4'))
  eq (dropped and dropped.n, 1)
  eq (r:count (), 3)
  eq ((r:get (1) or {}).n, 2)
  eq ((r:get (3) or {}).n, 4)
  eq (r:get (4), nil)
  eq (r:get (0), nil)
  for i = 5, 10 do
    r:push (lf.make_line (i, 'l' .. i))
  end
  eq ((r:get (1) or {}).n, 8)
  eq ((r:get (2) or {}).n, 9)
  eq ((r:get (3) or {}).n, 10)
end)

test ('the ring clears', function ()
  local r = ring_of ({ 'a', 'b' })
  r:clear ()
  eq (r:count (), 0)
  r:push (lf.make_line (9, 'c'))
  eq ((r:get (1) or {}).text, 'c')
end)

test ('find_line finds a line by its number after the ring wraps', function ()
  local r = lf.ring (4)
  for i = 1, 10 do
    r:push (lf.make_line (i, 'l' .. i))
  end
  eq ((lf.find_line (r, 7) or {}).text, 'l7')
  eq ((lf.find_line (r, 10) or {}).text, 'l10')
  eq (lf.find_line (r, 6), nil)
  eq (lf.find_line (r, 11), nil)
  eq (lf.find_line (lf.ring (2), 1), nil)
end)

test ('index_of finds a number in a sorted list', function ()
  eq (lf.index_of ({ 3, 5, 9, 12 }, 9), 3)
  eq (lf.index_of ({ 3, 5, 9, 12 }, 3), 1)
  eq (lf.index_of ({ 3, 5, 9, 12 }, 12), 4)
  eq (lf.index_of ({ 3, 5, 9, 12 }, 4), nil)
  eq (lf.index_of ({}, 1), nil)
end)

-- classify and scan ------------------------------------------------------------------------

test ('classify tells counted lines from lines a chip hides', function ()
  local line = lf.make_line (1, 'WARN low disk')
  local counted, visible = lf.classify (line, q ('disk'), {})
  eq ({ counted, visible }, { true, true })
  counted, visible = lf.classify (line, q ('disk'), { warn = true })
  eq ({ counted, visible }, { true, false })
  counted, visible = lf.classify (line, q ('cpu'), {})
  eq ({ counted, visible }, { false, false })
end)

test ('scan counts levels and keeps the last lines that pass', function ()
  local r = ring_of ({
    'ERROR one',
    'INFO two',
    'WARN three',
    'ERROR four',
    'plain five',
    'DEBUG six',
  })
  local all = lf.scan (r, q (''), {}, 100)
  eq (all.matched, 6)
  eq (all.levels, { error = 2, warn = 1, info = 1, debug = 1, other = 1 })
  eq (#all.shown, 6)
  eq (all.shown[1].n, 1)

  local no_errors = lf.scan (r, q (''), { error = true }, 100)
  eq (no_errors.matched, 4)
  eq (no_errors.levels.error, 2, 'a hidden level still counts on its chip')

  local last_two = lf.scan (r, q (''), {}, 2)
  eq (last_two.matched, 6)
  eq ({ last_two.shown[1].n, last_two.shown[2].n }, { 5, 6 })

  local words = lf.scan (r, q ('o'), {}, 100)
  eq (words.matched, 3)
  eq (words.levels, { error = 2, warn = 0, info = 1, debug = 0, other = 0 })
end)

-- Small helpers ----------------------------------------------------------------------------

test ('split_lines splits on any newline', function ()
  eq (lf.split_lines ('a\nb\r\nc\rd'), { 'a', 'b', 'c', 'd' })
  eq (lf.split_lines ('a\n\nb\n'), { 'a', '', 'b' })
  eq (lf.split_lines (''), {})
  eq (lf.split_lines ('\n'), { '' })
end)

test ('group puts commas in large numbers', function ()
  eq (lf.group (0), '0')
  eq (lf.group (999), '999')
  eq (lf.group (1000), '1,000')
  eq (lf.group (50000), '50,000')
  eq (lf.group (1234567), '1,234,567')
  eq (lf.group (-1234), '-1,234')
end)

test ('sentence starts with a capital and ends with a stop', function ()
  eq (
    lf.sentence ('could not start cmd: not found'),
    'Could not start cmd: not found.'
  )
  eq (lf.sentence ('Done!'), 'Done!')
  eq (lf.sentence ('  x.  '), 'X.')
  eq (lf.sentence (''), '')
end)

test ('trim takes spaces off both ends', function ()
  eq (lf.trim ('  a b \t'), 'a b')
  eq (lf.trim (''), '')
end)

-- Sources ----------------------------------------------------------------------------------

test ('follow_command follows a file with PowerShell on Windows', function ()
  local program, args = lf.follow_command ([[C:\logs\it's here.log]], 'windows')
  eq (program, 'powershell')
  eq (args[1], '-NoProfile')
  eq (args[2], '-Command')
  ok (
    args[3]:find (
      [[Get-Content -LiteralPath 'C:\logs\it''s here.log' -Tail 1000 -Wait -Encoding UTF8]],
      1,
      true
    ),
    args[3]
  )
end)

test (
  'follow_command doubles curly single quotes, which PowerShell also reads as quotes',
  function ()
    local _, args = lf.follow_command ('C:\\Ken’s.log', 'windows')
    ok (args[3]:find ("'C:\\Ken’’s.log'", 1, true), args[3])
  end
)

test ('follow_command uses tail elsewhere', function ()
  local program, args = lf.follow_command ('/var/log/syslog', 'linux')
  eq (program, 'tail')
  eq (args, { '-n', '1000', '-F', '/var/log/syslog' })
end)

test ('shell_command runs a line through the shell', function ()
  local program, args = lf.shell_command ('npm run dev', 'windows')
  eq (program, 'cmd')
  eq (args, { '/c', 'npm run dev' })
  program, args = lf.shell_command ('journalctl -f', 'macos')
  eq (program, 'sh')
  eq (args, { '-c', 'journalctl -f' })
end)

test ('source_name and source_title describe a source', function ()
  eq (lf.source_name ({ kind = 'file', path = 'C:\\logs\\app.log' }), 'app.log')
  eq (lf.source_name ({ kind = 'file', path = '/var/log/syslog' }), 'syslog')
  eq (
    lf.source_name ({ kind = 'command', command = '  npm run dev ' }),
    'npm run dev'
  )
  local long =
    lf.source_name ({ kind = 'command', command = string.rep ('x', 100) })
  eq (long, string.rep ('x', 57) .. '…')
  eq (
    lf.source_name ({ kind = 'paste', name = 'Pasted at 10:00' }),
    'Pasted at 10:00'
  )
  eq (lf.source_name ({ kind = 'paste' }), 'Pasted text')
  eq (
    lf.source_title ({ kind = 'command', command = 'ls', cwd = '/tmp' }),
    'ls\nin /tmp'
  )
  eq (lf.source_title ({ kind = 'file', path = '/a/b.log' }), '/a/b.log')
end)

test ('state_label names each state', function ()
  eq (lf.state_label ('running'), 'Running')
  eq (lf.state_label ('stopped'), 'Stopped')
  eq (lf.state_label ('exited', 0), 'Exited with code 0')
  eq (lf.state_label ('exited', 2), 'Exited with code 2')
  eq (lf.state_label ('exited'), 'Exited')
  eq (lf.state_label ('failed'), 'Failed to start')
  eq (lf.state_label ('pasted'), 'Pasted')
end)

test (
  'remember puts a source first, drops repeats and keeps the list short',
  function ()
    ---@type Logs.SourceSpec[]
    local list = {}
    list = lf.remember (list, { kind = 'file', path = 'a' }, 3)
    list = lf.remember (list, { kind = 'command', command = 'b', cwd = 'x' }, 3)
    list = lf.remember (list, { kind = 'file', path = 'a' }, 3)
    eq (list, {
      { kind = 'file', path = 'a' },
      { kind = 'command', command = 'b', cwd = 'x' },
    })
    list = lf.remember (list, { kind = 'command', command = 'b', cwd = 'y' }, 3)
    list = lf.remember (list, { kind = 'file', path = 'c' }, 3)
    eq (list, {
      { kind = 'file', path = 'c' },
      { kind = 'command', command = 'b', cwd = 'y' },
      { kind = 'file', path = 'a' },
    }, 'the oldest fell off')
  end
)

test ('clean_specs keeps only well-formed saved sources', function ()
  eq (lf.clean_specs (nil), {})
  eq (lf.clean_specs ({}), {})
  eq (lf.clean_specs ('x'), {})
  eq (
    lf.clean_specs ({
      { kind = 'file', path = 'a.log', extra = 1 },
      { kind = 'file' },
      { kind = 'command', command = '  ' },
      { kind = 'command', command = 'ls', cwd = '' },
      { kind = 'command', command = 'ls', cwd = '/tmp' },
      { kind = 'paste', name = 'x' },
      'junk',
    }),
    {
      { kind = 'file', path = 'a.log' },
      { kind = 'command', command = 'ls' },
      { kind = 'command', command = 'ls', cwd = '/tmp' },
    }
  )
end)

test ('clean_levels keeps only known level names', function ()
  eq (lf.clean_levels ({ 'error', 'nope', 'debug', 3 }), { 'error', 'debug' })
  eq (lf.clean_levels (nil), {})
end)
