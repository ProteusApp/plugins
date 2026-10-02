local config = require ('lib.config') --[[@as LangPython.ConfigModule]]

test ('mode keeps a mode basedpyright knows', function ()
  eq (config.mode ('strict'), 'strict')
  eq (config.mode ('all'), 'all')
  eq (config.mode ('off'), 'off')
end)

test ('mode falls back to standard', function ()
  eq (config.mode ('loud'), 'standard')
  eq (config.mode (nil), 'standard')
  eq (config.mode (3), 'standard')
end)

test ('the python section names the interpreter', function ()
  eq (
    config.section (
      'python',
      { python = 'C:/app/.venv/Scripts/python.exe', mode = 'basic' }
    ),
    { pythonPath = 'C:/app/.venv/Scripts/python.exe' }
  )
end)

test ('the python section is nil without an interpreter', function ()
  eq (config.section ('python', { mode = 'basic' }), nil)
end)

test ('the basedpyright sections hold the mode', function ()
  local state = { mode = 'strict' }
  eq (config.section ('basedpyright', state), {
    analysis = { typeCheckingMode = 'strict' },
  })
  eq (config.section ('basedpyright.analysis', state), {
    typeCheckingMode = 'strict',
  })
end)

test ('other sections are nil', function ()
  local state = { python = '/usr/bin/python3', mode = 'basic' }
  eq (config.section ('pyright', state), nil)
  eq (config.section ('python.analysis', state), nil)
  eq (config.section ('', state), nil)
end)

test ('all gives both sections for a change of settings', function ()
  eq (config.all ({ python = '/usr/bin/python3', mode = 'off' }), {
    python = { pythonPath = '/usr/bin/python3' },
    basedpyright = { analysis = { typeCheckingMode = 'off' } },
  })
  eq (config.all ({ mode = 'all' }), {
    basedpyright = { analysis = { typeCheckingMode = 'all' } },
  })
end)
