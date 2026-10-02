local lf = require ('log_filter') --[[@as Logs.FilterModule]]
local lx = require ('log_export') --[[@as Logs.ExportModule]]

-- 2024-03-01T12:00:00Z, in milliseconds since 1970.
local NOON = 1709294400000

test ('log_filter hands out log_export', function ()
  ok (lf.as_text == lx.as_text)
  ok (lf.as_csv == lx.as_csv)
  ok (lf.is_csv == lx.is_csv)
end)

test ('as_text writes each line without its colour codes', function ()
  local lines = {
    lf.make_line (1, '\27[31mERROR\27[0m boom'),
    lf.make_line (2, 'plain'),
  }
  eq (lx.as_text (lines), 'ERROR boom\nplain\n')
  eq (lx.as_text ({}), '')
end)

test (
  'as_csv quotes what needs it and names the source in the merged view',
  function ()
    local first = lf.make_line (7, '2024-03-01T12:00:00.250Z WARN a, "b"')
    local second = lf.make_line (8, 'no time', false, first.time)
    eq (
      lx.as_csv ({ first, second }),
      'line,time,level,text\r\n'
        .. '7,2024-03-01T12:00:00.250,warn,"2024-03-01T12:00:00.250Z WARN a, ""b"""\r\n'
        .. '8,2024-03-01T12:00:00.250,other,no time\r\n'
    )
    local csv = lx.as_csv ({ second }, function ()
      return 'app.log'
    end)
    ok (csv:find ('line,time,level,source,text', 1, true), csv)
    ok (csv:find (',other,app.log,no time', 1, true), csv)
    ok (lx.is_csv ('/tmp/OUT.CSV'))
    ok (not lx.is_csv ('/tmp/out.log'))
    eq (lx.time_text (NOON), '2024-03-01T12:00:00')
  end
)
