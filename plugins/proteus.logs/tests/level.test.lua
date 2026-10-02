local lf = require ('log_filter') --[[@as Logs.FilterModule]]
local ll = require ('log_level') --[[@as Logs.LevelModule]]

test ('log_filter hands out the levels of log_level', function ()
  ok (lf.LEVELS == ll.LEVELS)
  ok (lf.detect_level == ll.detect_level)
  ok (lf.zero_levels == ll.zero_levels)
end)

test ('LEVELS lists every level, worst first', function ()
  eq (ll.LEVELS, { 'error', 'warn', 'info', 'debug', 'other' })
end)

test ('zero_levels gives a fresh count each time', function ()
  local a = ll.zero_levels ()
  eq (a, { error = 0, warn = 0, info = 0, debug = 0, other = 0 })
  a.error = 3
  eq (ll.zero_levels ().error, 0)
end)

test (
  'level_named takes whole words, then the first name a prefix fits',
  function ()
    eq (ll.level_named ('warning'), 'warn')
    eq (ll.level_named ('crit'), 'error')
    eq (ll.level_named ('w'), 'warn')
    eq (ll.level_named ('inf'), 'info')
    eq (ll.level_named ('tr'), 'debug')
    eq (ll.level_named ('o'), 'other')
    eq (ll.level_named ('fat'), 'error')
    eq (ll.level_named ('banana'), nil)
  end
)

test ('detect_level reads pino numbers and quoted logfmt values', function ()
  eq (ll.detect_level ('{"level":50,"msg":"x"}'), 'error')
  eq (ll.detect_level ('{"level":40,"msg":"x"}'), 'warn')
  eq (ll.detect_level ('{"level":30,"msg":"x"}'), 'info')
  eq (ll.detect_level ('{"level":20,"msg":"x"}'), 'debug')
  eq (ll.detect_level ('ts=1 level="warning" msg=x'), 'warn')
  eq (ll.detect_level ('msg="level=error inside" lvl=info'), 'info')
end)

test ('detect_level gives other to a line with no level', function ()
  eq (ll.detect_level ('just some text'), 'other')
  eq (ll.detect_level (''), 'other')
end)
