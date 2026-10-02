local tasks = require ('terminal_tasks') --[[@as Terminal.Tasks]]

test (
  'read takes tasks.json and the setting, and says what is wrong',
  function ()
    local taken = {}
    local list, problems = tasks.read ({
      tasks = {
        {
          label = ' Build ',
          command = 'npm run build',
          group = 'build',
          problems = 'tsc',
        },
        {
          label = 'Test',
          program = 'cargo',
          args = { 'test', 1 },
          env = { RUST_BACKTRACE = 1 },
          cwd = 'crates/core',
          group = 'test',
          default = true,
          problems = { 'rustc', 'gcc' },
          detail = 'Every crate',
        },
        { label = 'Nothing' },
        { label = 'Both', command = 'a', program = 'b' },
        { command = 'ls' },
        { label = 'build', command = 'again' },
        { label = 'Odd', command = 'x', group = 'deploy' },
        { label = 'Unknown', command = 'x', problems = 'cobol' },
        { label = 'Env', command = 'x', env = { ['A=B'] = 'c' } },
        'not a task',
      },
    }, 'folder', taken)
    eq (#list, 2)
    eq (list[1], {
      label = 'Build',
      command = 'npm run build',
      args = {},
      env = {},
      group = 'build',
      default = false,
      problems = { 'tsc' },
      source = 'folder',
    })
    eq (list[2].args, { 'test', '1' })
    eq (list[2].env, { RUST_BACKTRACE = '1' })
    eq (list[2].cwd, 'crates/core')
    eq (list[2].problems, { 'rustc', 'gcc' })
    eq (list[2].default, true)
    eq (list[2].detail, 'Every crate')
    eq (problems, {
      'Nothing: it needs a command or a program',
      'Both: it has both a command and a program',
      '.proteus/tasks.json task 5 has no label',
      'build: the label is taken',
      'Odd: group is build or test',
      'Unknown: there is no problem matcher called cobol',
      'Env: env is not a table of names and values',
      '.proteus/tasks.json task 10 is not a table',
    })

    -- The setting holds the list alone, and a label the folder took stays taken.
    local more, more_problems = tasks.read ({
      { label = 'Lint', command = 'selene .', problems = 'lua' },
      { label = 'TEST', command = 'x' },
    }, 'settings', taken)
    eq (#more, 1)
    eq (more[1].source, 'settings')
    eq (more_problems, { 'TEST: the label is taken' })

    local none, none_problems = tasks.read (nil, 'settings')
    eq ({ none, none_problems }, { {}, {} })
    local _, bad = tasks.read ({ tasks = 'build' }, 'folder')
    eq (bad, { '.proteus/tasks.json has no list of tasks' })
  end
)

test ('find, of_group and command_line pick a task and how it runs', function ()
  local list = tasks.read ({
    { label = 'Build', command = 'make', group = 'build' },
    { label = 'Build docs', command = 'make docs', group = 'build' },
    { label = 'Test', program = 'make', args = { 'test' }, group = 'test' },
  }, 'settings')
  eq (tasks.find (list, ' test ').label, 'Test')
  eq (tasks.find (list, 'nope'), nil)
  eq (tasks.find (list, nil), nil)

  local one, choices = tasks.of_group (list, 'build')
  eq (one, nil)
  eq (#choices, 2)
  local test_task = tasks.of_group (list, 'test')
  eq (test_task and test_task.label, 'Test')
  list[2].default = true
  eq ((tasks.of_group (list, 'build')).label, 'Build docs')

  eq ({ tasks.command_line (list[1], 'linux') }, { '/bin/sh', { '-c', 'make' } })
  eq (
    { tasks.command_line (list[1], 'windows') },
    { 'cmd.exe', { '/d', '/c', 'make' } }
  )
  eq ({ tasks.command_line (list[3], 'windows') }, { 'make', { 'test' } })
  local with_args = tasks.read ({
    { label = 'Echo', command = 'echo', args = { 'hi', 'there' } },
  }, 'settings')[1]
  eq (
    { tasks.command_line (with_args, 'macos') },
    { '/bin/sh', { '-c', 'echo hi there' } }
  )
end)

test ('a task runs in its folder, inside the open folder', function ()
  local function task (cwd)
    return tasks.read ({ { label = 'T', command = 'x', cwd = cwd } }, 'settings')[1]
  end
  eq (tasks.cwd (task (nil), '/code/site', '/ws'), '/code/site')
  eq (tasks.cwd (task (nil), nil, '/ws'), '/ws')
  eq (tasks.cwd (task ('web'), '/code/site/', '/ws'), '/code/site/web')
  eq (tasks.cwd (task ('./web'), '/code/site', '/ws'), '/code/site/web')
  eq (tasks.cwd (task ('/tmp'), '/code/site', '/ws'), '/tmp')
  eq (tasks.cwd (task ('C:\\build'), 'C:/code', '/ws'), 'C:\\build')
  eq (tasks.cwd (task ('web'), nil, nil), 'web')
end)

---@param names string[]
---@param lines string[]
---@return Terminal.Problem[]
local function scan (names, lines)
  local matcher = tasks.matcher (names)
  local out = {} ---@type Terminal.Problem[]
  for _, line in ipairs (lines) do
    local p = matcher and matcher.feed (line)
    if p then
      out[#out + 1] = p
    end
  end
  return out
end

test ('the gcc matcher reads file:line:col: severity: message', function ()
  eq (
    scan ({ 'gcc' }, {
      'gcc -c main.c',
      'main.c:3:5: error: expected ";" before "}" token',
      'src/util.c:10:1: warning: unused variable "x"',
      'C:/code/x.c:7:2: note: declared here',
      'main.go:12:4: undefined: foo',
      'make: *** [all] Error 1',
    }),
    {
      {
        file = 'main.c',
        line = 3,
        col = 5,
        severity = 'error',
        message = 'expected ";" before "}" token',
      },
      {
        file = 'src/util.c',
        line = 10,
        col = 1,
        severity = 'warning',
        message = 'unused variable "x"',
      },
      {
        file = 'C:/code/x.c',
        line = 7,
        col = 2,
        severity = 'info',
        message = 'declared here',
      },
      {
        file = 'main.go',
        line = 12,
        col = 4,
        severity = 'error',
        message = 'undefined: foo',
      },
    }
  )
end)

test ('the tsc matcher reads both of its forms', function ()
  eq (
    scan ({ 'tsc' }, {
      "src/a.ts(4,10): error TS2322: Type 'string' is not assignable to type 'number'.",
      'src/b.ts:2:1 - warning TS6133: x is declared but never used.',
      'Found 2 errors.',
    }),
    {
      {
        file = 'src/a.ts',
        line = 4,
        col = 10,
        severity = 'error',
        message = "Type 'string' is not assignable to type 'number'.",
        code = 'TS2322',
      },
      {
        file = 'src/b.ts',
        line = 2,
        col = 1,
        severity = 'warning',
        message = 'x is declared but never used.',
        code = 'TS6133',
      },
    }
  )
end)

test (
  'the rustc matcher joins a message to the place on a later line',
  function ()
    eq (
      scan ({ 'rustc' }, {
        '   Compiling app v0.1.0',
        'error[E0308]: mismatched types',
        '  --> src/main.rs:3:18',
        '   |',
        'warning: unused import: `std::io`',
        ' --> src/lib.rs:1:5',
        'warning: `app` (lib) generated 1 warning',
        'error: could not compile `app`',
      }),
      {
        {
          file = 'src/main.rs',
          line = 3,
          col = 18,
          severity = 'error',
          message = 'mismatched types',
          code = 'E0308',
        },
        {
          file = 'src/lib.rs',
          line = 1,
          col = 5,
          severity = 'warning',
          message = 'unused import: `std::io`',
        },
      }
    )
  end
)

test ('the eslint matcher reads the stylish form', function ()
  eq (
    scan ({ 'eslint' }, {
      '',
      '/code/site/src/app.js',
      "  3:7   error    'x' is assigned a value but never used  no-unused-vars",
      '  10:1  warning  Unexpected console statement            no-console',
      '',
      '✖ 2 problems (1 error, 1 warning)',
    }),
    {
      {
        file = '/code/site/src/app.js',
        line = 3,
        col = 7,
        severity = 'error',
        message = "'x' is assigned a value but never used",
        code = 'no-unused-vars',
      },
      {
        file = '/code/site/src/app.js',
        line = 10,
        col = 1,
        severity = 'warning',
        message = 'Unexpected console statement',
        code = 'no-console',
      },
    }
  )
end)

test ('the lua matcher reads luacheck and Lua itself', function ()
  eq (
    scan ({ 'lua' }, {
      'init.lua:4:7: (W211) unused variable x',
      'lua: main.lua:12: attempt to call a nil value',
      'Total: 1 warning / 0 errors in 1 file',
    }),
    {
      {
        file = 'init.lua',
        line = 4,
        col = 7,
        severity = 'warning',
        message = 'unused variable x',
        code = 'W211',
      },
      {
        file = 'main.lua',
        line = 12,
        col = 1,
        severity = 'error',
        message = 'attempt to call a nil value',
      },
    }
  )
  eq (tasks.matcher ({}), nil)
end)

test ('a problem goes to the Problems panel with a full path', function ()
  eq (tasks.full_path ('src/a.ts', '/code/site/'), '/code/site/src/a.ts')
  eq (tasks.full_path ('./a.c', 'C:\\code'), 'C:/code/a.c')
  eq (tasks.full_path ('/abs/a.c', '/code'), '/abs/a.c')
  eq (tasks.full_path ('D:\\x\\a.c', '/code'), 'D:/x/a.c')
  eq (
    tasks.diagnostic ({
      file = 'a.c',
      line = 3,
      col = 5,
      severity = 'error',
      message = 'bad',
      code = 'E1',
    }, 'task: Build'),
    {
      line = 2,
      character = 4,
      severity = 'error',
      message = 'bad',
      source = 'task: Build',
      code = 'E1',
    }
  )
end)
