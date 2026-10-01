local launch = require ('lib.launch') --[[@as LangTypescript.LaunchModule]]

test (
  'package_dirs looks in the project first, then beside the program',
  function ()
    eq (
      launch.package_dirs (
        'C:/code/app',
        [[C:\nvm4w\nodejs\typescript-language-server.cmd]]
      ),
      {
        'C:/code/app/node_modules/typescript-language-server',
        'C:/nvm4w/nodejs/node_modules/typescript-language-server',
        'C:/nvm4w/lib/node_modules/typescript-language-server',
      }
    )
  end
)

test ('package_dirs finds a global package above a bin folder', function ()
  eq (launch.package_dirs (nil, '/usr/local/bin/typescript-language-server'), {
    '/usr/local/bin/node_modules/typescript-language-server',
    '/usr/local/lib/node_modules/typescript-language-server',
  })
  eq (launch.package_dirs ('', nil), {})
end)

test ('bin reads a program from package.json', function ()
  local name = 'typescript-language-server'
  eq (launch.bin ({ bin = { [name] = 'lib/cli.mjs' } }, name), 'lib/cli.mjs')
  eq (launch.bin ({ bin = './lib/cli.js' }, name), 'lib/cli.js')
  eq (launch.bin ({ bin = { other = 'x.js' } }, name), nil)
  eq (launch.bin (nil, name), nil)
end)

test ('runs_directly refuses npm scripts on Windows only', function ()
  eq (
    launch.runs_directly ('C:/npm/typescript-language-server.cmd', 'windows'),
    false
  )
  eq (
    launch.runs_directly ('C:/npm/typescript-language-server', 'windows'),
    false
  )
  eq (launch.runs_directly ('C:/node/node.EXE', 'windows'), true)
  eq (
    launch.runs_directly ('/usr/bin/typescript-language-server', 'linux'),
    true
  )
end)
