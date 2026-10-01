local venv = require ('lib.venv') --[[@as LangPython.VenvModule]]

test (
  'candidates look in .venv, then venv, the way each system lays them out',
  function ()
    eq (venv.candidates ('C:/code/app', 'windows'), {
      'C:/code/app/.venv/Scripts/python.exe',
      'C:/code/app/venv/Scripts/python.exe',
    })
    eq (venv.candidates ('/home/me/app/', 'linux'), {
      '/home/me/app/.venv/bin/python',
      '/home/me/app/venv/bin/python',
    })
  end
)

test ('candidates are empty without a folder', function ()
  eq (venv.candidates (nil, 'linux'), {})
  eq (venv.candidates ('', 'windows'), {})
end)

test ('candidates take a Windows path with backslashes', function ()
  eq (
    venv.candidates ([[C:\code\app]], 'windows')[1],
    'C:/code/app/.venv/Scripts/python.exe'
  )
end)

test ('beside finds a tool next to the interpreter', function ()
  eq (
    venv.beside ('C:/code/app/.venv/Scripts/python.exe', 'ruff', 'windows'),
    'C:/code/app/.venv/Scripts/ruff.exe'
  )
  eq (
    venv.beside (
      '/home/me/app/.venv/bin/python',
      'basedpyright-langserver',
      'macos'
    ),
    '/home/me/app/.venv/bin/basedpyright-langserver'
  )
end)

test ('executable reads the path Python printed', function ()
  eq (
    venv.executable ('C:\\Python312\\python.exe\r\n'),
    'C:/Python312/python.exe'
  )
  eq (venv.executable ('\n  /usr/bin/python3  \n'), '/usr/bin/python3')
  eq (venv.executable (''), nil)
  eq (venv.executable (nil), nil)
end)
