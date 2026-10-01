local launch = require ('lib.launch') --[[@as LangJson.LaunchModule]]

test (
  'package_dirs looks in the project first, then beside the program',
  function ()
    eq (
      launch.package_dirs (
        'C:/code/app',
        [[C:\Users\me\AppData\Roaming\npm\vscode-json-language-server]]
      ),
      {
        'C:/code/app/node_modules/vscode-langservers-extracted',
        'C:/Users/me/AppData/Roaming/npm/node_modules/vscode-langservers-extracted',
        'C:/Users/me/AppData/Roaming/lib/node_modules/vscode-langservers-extracted',
      }
    )
  end
)

test ('package_dirs finds a global package above a bin folder', function ()
  eq (launch.package_dirs (nil, '/usr/local/bin/vscode-json-language-server'), {
    '/usr/local/bin/node_modules/vscode-langservers-extracted',
    '/usr/local/lib/node_modules/vscode-langservers-extracted',
  })
  eq (launch.package_dirs ('', nil), {})
end)

test ('bin reads the JSON server from package.json', function ()
  local name = 'vscode-json-language-server'
  local manifest = {
    bin = {
      ['vscode-css-language-server'] = 'bin/vscode-css-language-server',
      [name] = './bin/vscode-json-language-server',
    },
  }
  eq (launch.bin (manifest, name), 'bin/vscode-json-language-server')
  eq (launch.bin ({ bin = { other = 'x.js' } }, name), nil)
  eq (launch.bin (nil, name), nil)
end)

test ('runs_directly refuses npm scripts on Windows only', function ()
  eq (
    launch.runs_directly ('C:/npm/vscode-json-language-server.cmd', 'windows'),
    false
  )
  eq (
    launch.runs_directly ('C:/npm/vscode-json-language-server', 'windows'),
    false
  )
  eq (launch.runs_directly ('C:/tools/server.exe', 'windows'), true)
  eq (
    launch.runs_directly ('/usr/bin/vscode-json-language-server', 'linux'),
    true
  )
end)
