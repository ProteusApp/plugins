local nesting = require ('file_nesting') --[[@as CodeExplorer.Nesting]]

---@param value any
---@param names string[]
---@param fold? boolean
---@return table<string, string[]>
local function group (value, names, fold)
  return nesting.group (names, nesting.rules (value, fold), fold)
end

local TS = {
  ['tsconfig.json'] = { 'tsconfig.*.json', '*.tsbuildinfo' },
  ['*.ts'] = { '${capture}.js', '${capture}.js.map', '${capture}.d.ts' },
  ['*.js'] = { '${capture}.js.map', '${capture}.min.js' },
}

-- rules ----------------------------------------------------------------------------------

test ('rules reads lists and comma-separated strings', function ()
  local rules = nesting.rules ({
    ['b.json'] = 'b.lock, b.log ,',
    ['a.json'] = { 'a.lock' },
  })
  eq (#rules, 2)
  eq (rules[1].under, { 'a.lock' })
  eq (rules[2].under, { 'b.lock', 'b.log' })
  eq (rules[1].captures, false)
end)

test ('rules skips anything that is not a name pattern', function ()
  eq (nesting.rules (nil), {})
  eq (nesting.rules ('package.json'), {})
  eq (nesting.rules ({ 'package.json' }), {})
  eq (
    nesting.rules ({
      ['a.json'] = 12,
      ['b.json'] = {},
      ['c.json'] = { 'sub/c.lock', 4 },
      ['d/e.json'] = { 'e.lock' },
    }),
    {}
  )
end)

test ('rules notes when the top pattern captures', function ()
  ok (nesting.rules ({ ['*.ts'] = { '${capture}.js' } })[1].captures)
end)

-- group ----------------------------------------------------------------------------------

test ('group puts tsconfig files and build info under tsconfig.json', function ()
  eq (
    group (TS, {
      'package.json',
      'tsconfig.app.json',
      'tsconfig.app.tsbuildinfo',
      'tsconfig.json',
      'tsconfig.node.json',
    }),
    {
      ['tsconfig.json'] = {
        'tsconfig.app.json',
        'tsconfig.app.tsbuildinfo',
        'tsconfig.node.json',
      },
    }
  )
end)

test ('group fills in what the top pattern captured', function ()
  eq (group (TS, { 'app.d.ts', 'app.js', 'app.ts', 'main.js' }), {
    ['app.ts'] = { 'app.d.ts', 'app.js' },
  })
end)

test ('group nests one level deep', function ()
  eq (group (TS, { 'app.js', 'app.js.map', 'app.min.js', 'app.ts' }), {
    ['app.ts'] = { 'app.js', 'app.js.map' },
  })
  eq (group (TS, { 'app.js', 'app.js.map', 'app.min.js' }), {
    ['app.js'] = { 'app.js.map', 'app.min.js' },
  })
end)

test ('group leaves two files that want each other side by side', function ()
  local both = { ['*.a'] = { '${capture}.b' }, ['*.b'] = { '${capture}.a' } }
  eq (group (both, { 'x.a', 'x.b' }), {})
end)

test ('group gives a file two files want to the first of them', function ()
  local rules =
    { ['one.txt'] = { 'shared.log' }, ['two.txt'] = { 'shared.log' } }
  eq (group (rules, { 'one.txt', 'shared.log', 'two.txt' }), {
    ['one.txt'] = { 'shared.log' },
  })
end)

test ('group keeps a file from nesting under itself', function ()
  eq (group ({ ['*.txt'] = { '*.txt' } }, { 'a.txt' }), {})
end)

test ('group takes characters Lua patterns use in names literally', function ()
  local rules = { ['*.ts'] = { '${capture}.js', '${capture}.*.map' } }
  eq (group (rules, { 'a(1)%.js', 'a(1)%.js.map', 'a(1)%.ts', 'a(1)x.js' }), {
    ['a(1)%.ts'] = { 'a(1)%.js', 'a(1)%.js.map' },
  })
end)

test ('group ignores case only when asked', function ()
  local rules = { ['package.json'] = { 'yarn.lock' } }
  eq (group (rules, { 'Package.JSON', 'Yarn.lock' }), {})
  eq (group (rules, { 'Package.JSON', 'Yarn.lock' }, true), {
    ['Package.JSON'] = { 'Yarn.lock' },
  })
end)

test ('group nests nothing with no rules', function ()
  eq (group ({}, { 'package.json', 'package-lock.json' }), {})
end)

test ('group puts a Godot .uid file under the file it names', function ()
  local rules = { ['*'] = { '${capture}.uid' } }
  eq (group (rules, { 'Player.cs', 'Player.cs.uid', 'icon.svg', 'Main.tscn' }), {
    ['Player.cs'] = { 'Player.cs.uid' },
  })
end)
