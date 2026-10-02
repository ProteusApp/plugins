local lf = require ('log_filter') --[[@as Logs.FilterModule]]
local ls = require ('log_sources') --[[@as Logs.SourcesModule]]

test ('log_filter hands out the sources of log_sources', function ()
  ok (lf.follow_command == ls.follow_command)
  ok (lf.shell_command == ls.shell_command)
  ok (lf.source_name == ls.source_name)
  ok (lf.source_title == ls.source_title)
  ok (lf.state_label == ls.state_label)
  ok (lf.spec_key == ls.spec_key)
  ok (lf.remember == ls.remember)
  ok (lf.clean_specs == ls.clean_specs)
  ok (lf.clean_levels == ls.clean_levels)
end)

test ('follow_command reads a whole file from its first line', function ()
  local program, args = ls.follow_command ('/var/log/app.log', 'linux', true)
  eq (program, 'tail')
  eq (args, { '-n', '+1', '-F', '/var/log/app.log' })
  local _, win = ls.follow_command ('C:\\app.log', 'windows', true)
  ok (not win[3]:find ('-Tail', 1, true))
  ok (win[3]:find ('-Wait', 1, true) ~= nil)
end)

test ('source_name cuts a long command and names a Windows path', function ()
  eq (ls.source_name ({ kind = 'file', path = 'C:\\logs\\app.log' }), 'app.log')
  local long = string.rep ('x', 80)
  local name = ls.source_name ({ kind = 'command', command = long })
  eq (name, string.rep ('x', 57) .. '…')
  eq (ls.source_name ({ kind = 'paste' }), 'Pasted text')
end)

test ('spec_key tells a whole file from its tail', function ()
  local tail = ls.spec_key ({ kind = 'file', path = '/a.log' })
  local whole = ls.spec_key ({ kind = 'file', path = '/a.log', whole = true })
  ok (tail ~= whole)
  eq (tail, ls.spec_key ({ kind = 'file', path = '/a.log', name = 'x' }))
end)

test ('remember keeps only the saved fields and at most max specs', function ()
  local list = {
    { kind = 'command', command = 'a' },
    { kind = 'command', command = 'b' },
  } ---@type Logs.SourceSpec[]
  local out = ls.remember (list, {
    kind = 'file',
    path = '/x.log',
    name = 'dropped',
  }, 2)
  eq (out, {
    { kind = 'file', path = '/x.log' },
    { kind = 'command', command = 'a' },
  })
end)

test ('state_label says the code a program ended with', function ()
  eq (ls.state_label ('exited', 0), 'Exited with code 0')
  eq (ls.state_label ('exited'), 'Exited')
  eq (ls.state_label ('pasted'), 'Pasted')
end)

test ('clean_levels keeps the order it was given', function ()
  eq (ls.clean_levels ({ 'debug', 'nope', 'error' }), { 'debug', 'error' })
  eq (ls.clean_levels ('error'), {})
end)

test ('rotation_base names the file a rotated log is written to now', function ()
  eq (ls.rotation_base ('app.log'), 'app.log')
  eq (ls.rotation_base ('app.log.1'), 'app.log')
  eq (ls.rotation_base ('app.log.12.gz'), 'app.log')
  eq (ls.rotation_base ('app.log-20240301.gz'), 'app.log')
  eq (ls.rotation_base ('app.log.gz'), 'app.log')
end)

test ('rotated_files lists the older files, oldest first', function ()
  eq (
    ls.rotated_files ('app.log', {
      'app.log',
      'app.log.1',
      'app.log.10.gz',
      'app.log.2.gz',
      'other.log.1',
      'app.log.3/',
      'app.logs.1',
    }),
    { 'app.log.10.gz', 'app.log.2.gz', 'app.log.1' }
  )
  eq (
    ls.rotated_files ('a.log', {
      'a.log-20240302',
      'a.log-20240301.gz',
      'a.log',
    }),
    { 'a.log-20240301.gz', 'a.log-20240302' }
  )
  eq (ls.rotated_files ('a+b.log', { 'a+b.log.1' }), { 'a+b.log.1' })
end)

test (
  'follow_command reads a gzip file once, with gzip or PowerShell',
  function ()
    ok (ls.is_gzip ('/var/log/app.log.2.GZ'))
    ok (not ls.is_gzip ('/var/log/app.log'))
    eq ({ ls.follow_command ('/var/log/app.log.2.gz', 'linux') }, {
      'gzip',
      { '-dc', '/var/log/app.log.2.gz' },
    })
    local program, args = ls.follow_command ([[C:\logs\it's.gz]], 'windows')
    eq (program, 'powershell')
    ok (args[3]:find ('GZipStream', 1, true), args[3])
    ok (args[3]:find ([[Read-Gzip 'C:\logs\it''s.gz']], 1, true), args[3])
    ok (not args[3]:find ('-Wait', 1, true), 'a gzip file does not grow')
  end
)

test (
  'follow_command reads the rotated files first, then follows the log',
  function ()
    local program, args = ls.follow_command (
      '/var/log/app.log',
      'linux',
      true,
      { '/var/log/app.log.2.gz', '/var/log/app.log.1' }
    )
    eq (program, 'sh')
    eq (args[1], '-c')
    ok (args[2]:find ('gzip -dc', 1, true), args[2])
    ok (args[2]:find ('exec tail -n +1 -F "$b"', 1, true), args[2])
    eq ({ args[3], args[4], args[5], args[6] }, {
      'sh',
      '/var/log/app.log',
      '/var/log/app.log.2.gz',
      '/var/log/app.log.1',
    })
    local _, win = ls.follow_command (
      'C:\\logs\\app.log',
      'windows',
      true,
      { 'C:\\logs\\app.log.2.gz', 'C:\\logs\\app.log.1' }
    )
    local script = win[3]
    local gz = script:find ([[Read-Gzip 'C:\logs\app.log.2.gz']], 1, true)
    local one =
      script:find ([[-LiteralPath 'C:\logs\app.log.1' -Encoding]], 1, true)
    local now = script:find ([[-LiteralPath 'C:\logs\app.log' -Wait]], 1, true)
    ok (gz and one and now and gz < one and one < now, script)
    ok (not script:find ('-Tail', 1, true), script)
  end
)

test (
  'a rotated log is a source of its own, and a file that read to its end says so',
  function ()
    local plain = { kind = 'file', path = '/a.log', whole = true }
    local rotated = { kind = 'file', path = '/a.log', rotated = true }
    ok (ls.spec_key (plain) ~= ls.spec_key (rotated))
    eq (
      ls.spec_key ({ kind = 'file', path = '/a.log' }),
      'file\n/a.log\n\n',
      'the key of a source opened before stays the same'
    )
    ok (ls.reads_whole (rotated))
    ok (ls.reads_whole ({ kind = 'file', path = '/a.log.1.gz' }))
    ok (not ls.reads_whole ({ kind = 'file', path = '/a.log' }))
    eq (
      ls.clean_specs ({ rotated, { kind = 'file', path = '/b', format = 7 } }),
      {
        { kind = 'file', path = '/a.log', rotated = true },
        { kind = 'file', path = '/b' },
      }
    )
    eq (ls.state_label ('exited', 0, true), 'Read to the end')
    eq (ls.state_label ('exited', 1, true), 'Exited with code 1')
  end
)
