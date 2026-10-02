local words = require ('shell_words') --[[@as Terminal.ShellWords]]

test ('split takes a program and its arguments', function ()
  local program, args = words.split ('pwsh -NoLogo')
  eq (program, 'pwsh')
  eq (args, { '-NoLogo' })
  program, args = words.split ('  bash   -l  ')
  eq (program, 'bash')
  eq (args, { '-l' })
end)

test ('split keeps quoted spaces and backslashes', function ()
  local program, args = words.split (
    '"C:\\Program Files\\Git\\bin\\bash.exe" --login -c \'echo a b\''
  )
  eq (program, 'C:\\Program Files\\Git\\bin\\bash.exe')
  eq (args, { '--login', '-c', 'echo a b' })
  local empty, none = words.split ('cmd ""')
  eq (empty, 'cmd')
  eq (none, { '' })
end)

test ('split reads an unquoted .exe path with spaces as one program', function ()
  local program, args =
    words.split ('C:\\Program Files\\PowerShell\\7\\pwsh.exe')
  eq (program, 'C:\\Program Files\\PowerShell\\7\\pwsh.exe')
  eq (args, {})
end)

test ('split gives an empty program for an empty value', function ()
  local program, args = words.split ('   ')
  eq (program, '')
  eq (args, {})
end)
