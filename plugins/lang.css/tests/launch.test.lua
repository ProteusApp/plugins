local launch = require ('lib.launch') --[[@as LangCss.LaunchModule]]

test (
  'package_dirs looks in the project first, then beside the program',
  function ()
    eq (
      launch.package_dirs (
        'C:/code/app',
        [[C:\Users\me\AppData\Roaming\npm\vscode-css-language-server]]
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
  eq (launch.package_dirs (nil, '/usr/local/bin/vscode-css-language-server'), {
    '/usr/local/bin/node_modules/vscode-langservers-extracted',
    '/usr/local/lib/node_modules/vscode-langservers-extracted',
  })
  eq (launch.package_dirs ('', nil), {})
end)

test ('bin reads the CSS server from package.json', function ()
  local name = 'vscode-css-language-server'
  local manifest = {
    bin = {
      ['vscode-json-language-server'] = 'bin/vscode-json-language-server',
      [name] = './bin/vscode-css-language-server',
    },
  }
  eq (launch.bin (manifest, name), 'bin/vscode-css-language-server')
  eq (launch.bin ({ bin = { other = 'x.js' } }, name), nil)
  eq (launch.bin (nil, name), nil)
end)

test ('runs_directly refuses npm scripts on Windows only', function ()
  eq (
    launch.runs_directly ('C:/npm/vscode-css-language-server.cmd', 'windows'),
    false
  )
  eq (
    launch.runs_directly ('C:/npm/vscode-css-language-server', 'windows'),
    false
  )
  eq (launch.runs_directly ('C:/tools/server.exe', 'windows'), true)
  eq (
    launch.runs_directly ('/usr/bin/vscode-css-language-server', 'linux'),
    true
  )
end)
