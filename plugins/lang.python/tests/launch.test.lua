local launch = require ('lib.launch') --[[@as LangPython.LaunchModule]]

test (
  'package_dirs looks in the project first, then beside the program',
  function ()
    eq (
      launch.package_dirs (
        'C:/code/app',
        [[C:\Users\me\AppData\Roaming\npm\basedpyright-langserver]]
      ),
      {
        'C:/code/app/node_modules/basedpyright',
        'C:/Users/me/AppData/Roaming/npm/node_modules/basedpyright',
        'C:/Users/me/AppData/Roaming/lib/node_modules/basedpyright',
      }
    )
  end
)

test ('package_dirs finds a global package above a bin folder', function ()
  eq (launch.package_dirs (nil, '/usr/local/bin/basedpyright-langserver'), {
    '/usr/local/bin/node_modules/basedpyright',
    '/usr/local/lib/node_modules/basedpyright',
  })
  eq (launch.package_dirs ('', nil), {})
end)

test ('bin reads the language server from package.json', function ()
  -- The bin field of basedpyright 1.40.1.
  local manifest = {
    bin = {
      basedpyright = 'index.js',
      ['basedpyright-langserver'] = 'langserver.index.js',
      pyright = 'index.js',
      ['pyright-langserver'] = 'langserver.index.js',
    },
  }
  eq (launch.bin (manifest, launch.PROGRAM), 'langserver.index.js')
  eq (launch.bin ({ bin = { other = 'x.js' } }, launch.PROGRAM), nil)
  eq (launch.bin (nil, launch.PROGRAM), nil)
end)

test ('runs_directly refuses npm scripts on Windows only', function ()
  eq (
    launch.runs_directly ('C:/npm/basedpyright-langserver.cmd', 'windows'),
    false
  )
  eq (launch.runs_directly ('C:/npm/basedpyright-langserver', 'windows'), false)
  eq (
    launch.runs_directly (
      'C:/app/.venv/Scripts/basedpyright-langserver.exe',
      'windows'
    ),
    true
  )
  eq (launch.runs_directly ('/usr/bin/basedpyright-langserver', 'linux'), true)
end)
