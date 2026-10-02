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
    eq (launch.untrusted (nil, layer), false, 'no project service')
    eq (launch.untrusted (project (nil, false), layer), false, 'no folder open')
    eq (launch.untrusted (project ('C:/code/app', false), layer), true)
    eq (launch.untrusted (project ('C:/code/app', true), layer), false)
    eq (
      launch.untrusted (
        project ('C:/code/app'),
        { loaded = false, trusted = true }
      ),
      false,
      'an older project service: the kernel says'
    )
    eq (launch.untrusted (project ('C:/code/app'), layer), true)
  end
)

test (
  'choose_libraries keeps the project’s TypeScript out unless it may be used',
  function ()
    local both = {
      path = 'C:/app/node_modules/typescript/lib',
      fallback = 'C:/g/typescript/lib',
    }
    eq (launch.choose_libraries (both, true), both)
    eq (launch.choose_libraries (both, false), { path = 'C:/g/typescript/lib' })
    eq (
      launch.choose_libraries (
        { path = 'C:/app/node_modules/typescript/lib' },
        false
      ),
      nil,
      'with no other, the server would find the project’s by itself'
    )
    eq (launch.choose_libraries ({}, true), {})
  end
)
