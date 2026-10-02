local lt = require ('log_time') --[[@as Logs.TimeModule]]

-- 2024-03-01T12:00:00Z, in milliseconds since 1970.
local NOON = 1709294400000

test ('parse_stamp reads ISO 8601 and the forms near it', function ()
  eq (lt.parse_stamp ('2024-03-01T12:00:00Z'), NOON)
  eq (lt.parse_stamp ('2024-03-01 12:00:00'), NOON)
  eq (lt.parse_stamp ('2024/03/01 12:00:00.250'), NOON + 250)
  eq (lt.parse_stamp ('2024-03-01 12:00:00,5'), NOON + 500)
  eq (lt.parse_stamp ('2024-03-01T14:00:00+02:00'), NOON)
  eq (lt.parse_stamp ('2024-03-01T05:00:00-0700'), NOON)
  eq (lt.parse_stamp ('2024-03-01T12:00'), NOON)
  eq (lt.parse_stamp ('1970-01-01T00:00:00Z'), 0)
  eq (lt.parse_stamp ('2000-02-29T00:00:00Z'), 951782400000)
  eq (lt.parse_stamp ('no time here'), nil)
  eq (lt.parse_stamp ('2024-13-01 12:00:00'), nil)
end)

test ('line_time finds the time in the common log formats', function ()
  eq (lt.line_time ('2024-03-01T12:00:00Z INFO started', 2024), NOON)
  eq (lt.line_time ('[2024-03-01 12:00:00] local.ERROR: boom', 2024), NOON)
  eq (
    lt.line_time (
      '{"level":"info","time":"2024-03-01T12:00:00Z","msg":"hi"}',
      2024
    ),
    NOON
  )
  eq (lt.line_time ('{"ts":1709294400.5,"msg":"hi"}', 2024), NOON + 500)
  eq (lt.line_time ('{"timestamp":1709294400000}', 2024), NOON)
  eq (lt.line_time ('level=info ts=2024-03-01T12:00:00Z msg=hi', 2024), NOON)
  eq (lt.line_time ('time="2024-03-01 12:00:00" level=warn', 2024), NOON)
  eq (
    lt.line_time (
      '127.0.0.1 - - [01/Mar/2024:05:00:00 -0700] "GET / HTTP/1.1" 200',
      2024
    ),
    NOON
  )
  eq (lt.line_time ('Mar  1 12:00:00 host sshd[1]: hello', 2024), NOON)
  eq (lt.line_time ('<34>Mar 1 12:00:00 host app: hi', 2024), NOON)
  eq (lt.line_time ('I0301 12:00:00.000250 1 main.go:1] up', 2024), NOON)
  eq (lt.line_time ('12:00:01 INFO up', 2024), 43201000)
  eq (lt.line_time ('    at main (app.js:10:5)', 2024), nil)
end)

test ('parse_when reads moments, times of day and times back', function ()
  eq (lt.parse_when ('2024-03-01'), { kind = 'at', ms = NOON - 12 * 3600000 })
  eq (lt.parse_when ('2024-03-01T12:00'), { kind = 'at', ms = NOON })
  eq (lt.parse_when ('12:30'), { kind = 'day', ms = 45000000 })
  eq (lt.parse_when ('9:05:30'), { kind = 'day', ms = 32730000 })
  eq (lt.parse_when ('-15m'), { kind = 'ago', ms = 900000 })
  eq (lt.parse_when ('-2h'), { kind = 'ago', ms = 7200000 })
  eq (lt.parse_when ('-1d'), { kind = 'ago', ms = 86400000 })
  eq (lt.parse_when ('25:00'), nil)
  eq (lt.parse_when ('soon'), nil)
end)

test ('passes compares a moment, a time of day, or a time back', function ()
  ok (lt.passes (NOON, { kind = 'at', ms = NOON }, nil, false))
  ok (not lt.passes (NOON - 1, { kind = 'at', ms = NOON }, nil, false))
  ok (lt.passes (NOON - 1, { kind = 'at', ms = NOON }, nil, true))
  ok (lt.passes (NOON + lt.DAY, { kind = 'day', ms = 12 * 3600000 }, nil, false))
  ok (not lt.passes (NOON, { kind = 'day', ms = 13 * 3600000 }, nil, false))
  ok (lt.passes (NOON, { kind = 'ago', ms = 60000 }, NOON + 30000, false))
  ok (not lt.passes (NOON, { kind = 'ago', ms = 60000 }, NOON + 90000, false))
end)
