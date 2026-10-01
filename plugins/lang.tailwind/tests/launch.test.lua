local launch = require ('lib.launch') --[[@as LangTailwind.LaunchModule]]

test (
  'package_dirs looks in the project first, then beside the program',
  function ()
    eq (
      launch.package_dirs (
        'C:/code/app',
        [[C:\Users\me\AppData\Roaming\npm\tailwindcss-language-server]]
      ),
      {
        'C:/code/app/node_modules/@tailwindcss/language-server',
        'C:/Users/me/AppData/Roaming/npm/node_modules/@tailwindcss/language-server',
        'C:/Users/me/AppData/Roaming/lib/node_modules/@tailwindcss/language-server',
      }
    )
  end
)

test ('package_dirs finds a global package above a bin folder', function ()
  eq (launch.package_dirs (nil, '/usr/local/bin/tailwindcss-language-server'), {
    '/usr/local/bin/node_modules/@tailwindcss/language-server',
    '/usr/local/lib/node_modules/@tailwindcss/language-server',
  })
  eq (launch.package_dirs ('', nil), {})
end)

test ("bin reads the server's script from package.json", function ()
  local name = 'tailwindcss-language-server'
  -- What @tailwindcss/language-server 0.16 lists.
  local manifest = {
    bin = {
      ['css-language-server'] = './bin/css-language-server',
      [name] = './bin/tailwindcss-language-server',
    },
  }
  eq (launch.bin (manifest, name), 'bin/tailwindcss-language-server')
  eq (launch.bin ({ bin = { other = 'x.js' } }, name), nil)
  eq (launch.bin (nil, name), nil)
end)

test ('runs_directly refuses npm scripts on Windows only', function ()
  eq (
    launch.runs_directly ('C:/npm/tailwindcss-language-server.cmd', 'windows'),
    false
  )
  eq (
    launch.runs_directly ('C:/npm/tailwindcss-language-server', 'windows'),
    false
  )
  eq (launch.runs_directly ('C:/tools/server.exe', 'windows'), true)
  eq (
    launch.runs_directly (
      '/opt/homebrew/bin/tailwindcss-language-server',
      'macos'
    ),
    true
  )
end)
