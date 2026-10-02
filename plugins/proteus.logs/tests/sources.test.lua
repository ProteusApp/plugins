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
