local css = require ('logs_css') --[[@as string]]

test ('logs_css holds the styles of each part of the screen', function ()
  ok (type (css) == 'string')
  for _, class in ipairs ({
    'logs',
    'logs-bar',
    'logs-chip',
    'logs-list',
    'logs-row',
    'logs-detail',
    'logs-src',
    'logs-head',
    'logs-hcol',
  }) do
    ok (css:find ('.' .. class .. ' ', 1, true), 'no rule for .' .. class)
  end
end)

test ('logs_css uses no selector a restricted plugin loses', function ()
  -- The app drops these from a restricted plugin's CSS, so a rule with one would never apply.
  for _, pattern in ipairs ({ ':has%(', ':host%-context%(', ' of ' }) do
    ok (not css:find (pattern), 'the CSS uses ' .. pattern)
  end
end)
