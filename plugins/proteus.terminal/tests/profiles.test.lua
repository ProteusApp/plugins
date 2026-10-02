local profiles = require ('terminal_profiles') --[[@as Terminal.Profiles]]

test ('the default profile runs terminal.shell, or the system shell', function ()
  local list, problems = profiles.read (nil, '')
  eq (problems, {})
  eq (list, {
    { name = '', label = 'Default shell', program = '', args = {}, env = {} },
  })
  local pwsh = profiles.read ({}, ' pwsh ')
  eq (pwsh[1].program, 'pwsh')
  eq (pwsh[1].label, 'pwsh')
end)

test (
  'read keeps named profiles with their arguments, variables and folder',
  function ()
    local list, problems = profiles.read ({
      {
        name = 'Git Bash',
        program = 'C:/Git/bin/bash.exe',
        args = { '-l', 2 },
      },
      {
        name = ' Node ',
        program = 'node',
        env = { NODE_ENV = 'development', DEBUG = 1 },
        cwd = 'C:/code',
      },
    }, '')
    eq (problems, {})
    eq (list[2], {
      name = 'Git Bash',
      label = 'Git Bash',
      program = 'C:/Git/bin/bash.exe',
      args = { '-l', '2' },
      env = {},
    })
    eq (list[3], {
      name = 'Node',
      label = 'Node',
      program = 'node',
      args = {},
      env = { NODE_ENV = 'development', DEBUG = '1' },
      cwd = 'C:/code',
    })
  end
)

test ('read leaves out broken entries and says why', function ()
  local list, problems = profiles.read ({
    'bash',
    { program = 'bash' },
    { name = 'A', program = 3 },
    { name = 'B', args = 'x' },
    { name = 'C', env = { ['A=B'] = 'x' } },
    { name = 'D', env = { [''] = 'x' } },
    { name = 'E', cwd = false },
    { name = 'F' },
    { name = 'f' },
  }, '')
  eq (#list, 2)
  eq (list[2].name, 'F')
  eq (list[2].program, '')
  eq (problems, {
    'terminal.profiles entry 1 is not a table',
    'terminal.profiles entry 2 has no name',
    'A: program is not text',
    'B: args is not a list of text',
    'C: env is not a table of names and values',
    'D: env is not a table of names and values',
    'E: cwd is not text',
    'terminal.profiles entry 9: the name f is taken',
  })
  local _, bad = profiles.read ('bash', '')
  eq (bad, { 'terminal.profiles is not a list' })
end)

test (
  'pick takes the profile asked for, then the default setting, then the first',
  function ()
    local list = profiles.read ({ { name = 'Bash' }, { name = 'Zsh' } }, '')
    eq (profiles.pick (list, 'zsh', 'Bash').name, 'Zsh')
    eq (profiles.pick (list, 'Fish', 'bash').name, 'Bash')
    eq (profiles.pick (list, nil, 'nothing').name, '')
    eq (profiles.pick (list, '', 'Bash').name, '')
    eq (profiles.find (list, 'nope'), nil)
  end
)

test (
  'cwd takes the folder asked for, the profile, the open folder, then the workspace',
  function ()
    local list = profiles.read ({ { name = 'Here', cwd = '/srv' } }, '')
    eq (profiles.cwd ('/tmp', list[2], '/code', '/ws'), '/tmp')
    eq (profiles.cwd (nil, list[2], '/code', '/ws'), '/srv')
    eq (profiles.cwd ('', list[1], '/code', '/ws'), '/code')
    eq (profiles.cwd (nil, list[1], nil, '/ws'), '/ws')
    eq (profiles.cwd (nil, list[1], nil, nil), '')
  end
)

test ('as_input ends every line with Enter', function ()
  eq (profiles.as_input ('ls'), 'ls\r')
  eq (profiles.as_input ('cd src\r\nls\n'), 'cd src\rls\r')
end)

test (
  'the default profile splits terminal.shell into a program and its arguments',
  function ()
    local program, args = profiles.from_shell ('pwsh -NoLogo')
    eq (program, 'pwsh')
    eq (args, { '-NoLogo' })
    local list = profiles.read ({}, '"C:/Program Files/Git/bin/bash.exe" -l')
    eq (list[1].program, 'C:/Program Files/Git/bin/bash.exe')
    eq (list[1].args, { '-l' })
  end
)
