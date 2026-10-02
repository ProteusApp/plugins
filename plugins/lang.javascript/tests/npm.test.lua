local npm = require ('lib.npm') --[[@as LangJavascript.NpmModule]]

test (
  'newer orders versions by number, then a release after its pre-release',
  function ()
    ok (npm.newer ('1.10.0', '1.9.9'))
    ok (npm.newer ('2.0.0', '2.0.0-rc.1'))
    ok (not npm.newer ('2.0.0-beta.1', '2.0.0'))
    ok (npm.newer ('2.0.0-rc.1', '2.0.0-beta.2'))
  end
)

test ('address writes the slash of a scoped name', function ()
  eq (npm.address ('@types/node'), '@types%2Fnode')
  eq (npm.address ('react'), 'react')
end)

test (
  'versions lists releases newest first, without deprecated ones',
  function ()
    local record = {
      ['dist-tags'] = { latest = '18.3.1' },
      versions = {
        ['18.3.1'] = {},
        ['18.2.0'] = {},
        ['19.0.0-rc.0'] = {},
        ['17.0.2'] = { deprecated = 'use 18' },
        ['16.14.0'] = {},
      },
    }
    eq (
      npm.versions (record, false),
      { latest = '18.3.1', list = { '18.3.1', '18.2.0', '16.14.0' } }
    )
    eq (npm.versions (record, true).list[1], '19.0.0-rc.0')
    eq (npm.versions (nil, false), { list = {} })
  end
)

test ('version_items puts the latest first, once', function ()
  eq (
    npm.version_items ({
      latest = '2.0.0',
      list = { '2.1.0-rc.1', '2.0.0', '1.0.0' },
    }),
    {
      { label = '2.0.0', kind = 'constant', detail = 'latest' },
      { label = '2.1.0-rc.1', kind = 'constant' },
      { label = '1.0.0', kind = 'constant' },
    }
  )
end)

test ('name_items reads a registry search answer', function ()
  eq (
    npm.name_items ({
      objects = {
        {
          package = { name = 'react', version = '18.3.1', description = 'UI' },
        },
        { nothing = true },
      },
    }),
    {
      {
        label = 'react',
        kind = 'module',
        detail = '18.3.1',
        documentation = 'UI',
      },
    }
  )
  eq (npm.name_items (nil), {})
end)
