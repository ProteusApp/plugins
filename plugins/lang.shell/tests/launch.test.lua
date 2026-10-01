local launch = require ('lib.launch') --[[@as LangShell.LaunchModule]]

test (
  'package_dirs looks in the project first, then beside the program',
  function ()
    eq (
      launch.package_dirs (
        'C:/code/app',
        [[C:\Users\me\AppData\Roaming\npm\bash-language-server]]
      ),
      {
        'C:/code/app/node_modules/bash-language-server',
        'C:/Users/me/AppData/Roaming/npm/node_modules/bash-language-server',
        'C:/Users/me/AppData/Roaming/lib/node_modules/bash-language-server',
      }
    )
    eq (launch.package_dirs (nil, '/usr/local/bin/bash-language-server'), {
      '/usr/local/bin/node_modules/bash-language-server',
      '/usr/local/lib/node_modules/bash-language-server',
    })
    eq (launch.package_dirs ('', nil), {})
  end
)

test ('bin reads the server script from package.json', function ()
  -- As bash-language-server 5.8.1 names it.
  local manifest = { bin = { ['bash-language-server'] = 'out/cli.js' } }
  eq (launch.bin (manifest, 'bash-language-server'), 'out/cli.js')
  eq (
    launch.bin ({ bin = './out/cli.js' }, 'bash-language-server'),
    'out/cli.js'
  )
  eq (launch.bin ({ bin = { other = 'x.js' } }, 'bash-language-server'), nil)
  eq (launch.bin (nil, 'bash-language-server'), nil)
end)

test ('runs_directly refuses npm scripts on Windows only', function ()
  eq (launch.runs_directly ('C:/npm/bash-language-server.cmd', 'windows'), false)
  eq (launch.runs_directly ('C:/npm/bash-language-server', 'windows'), false)
  eq (launch.runs_directly ('C:/tools/server.exe', 'windows'), true)
  eq (launch.runs_directly ('/usr/bin/bash-language-server', 'linux'), true)
end)
