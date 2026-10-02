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

test (
  'a folder the user does not trust is untrusted only in the Code Editor',
  function ()
    ---@param root string?
    ---@param trusted? boolean
    ---@return Proteus.Project
    local function project (root, trusted)
      return {
        root = function ()
          return root
        end,
        trusted = trusted ~= nil and function ()
          return trusted
        end or nil,
      } --[[@as Proteus.Project]]
    end
    local layer = { loaded = false, trusted = false } ---@type Proteus.ProjectLayer
    eq (venv.untrusted (nil, layer), false, 'no project service')
    eq (venv.untrusted (project (nil, false), layer), false, 'no folder open')
    eq (venv.untrusted (project ('/home/me/app', false), layer), true)
    eq (venv.untrusted (project ('/home/me/app', true), layer), false)
    eq (
      venv.untrusted (
        project ('/home/me/app'),
        { loaded = true, trusted = true }
      ),
      false,
      'an older project service: the kernel says'
    )
  end
)
