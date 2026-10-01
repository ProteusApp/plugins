local schemas = require ('lib.schemas') --[[@as LangJson.SchemasModule]]

test ('glob lets a pattern match in any folder', function ()
  eq (schemas.glob ('package.json'), '**/package.json')
  eq (schemas.glob ('tsconfig.*.json'), '**/tsconfig.*.json')
  eq (schemas.glob ('.vscode/settings.json'), '**/.vscode/settings.json')
  eq (schemas.glob ([[.cargo\config.json]]), '**/.cargo/config.json')
end)

test ('glob keeps a pattern that already starts with **/ or /', function ()
  eq (schemas.glob ('**/*.ndg'), '**/*.ndg')
  eq (schemas.glob ('src/**/*.json'), '**/src/**/*.json')
  eq (schemas.glob ('/home/me/app/*.json'), '/home/me/app/*.json')
end)

test ('glob writes a Windows drive letter in lower case', function ()
  eq (schemas.glob ('C:/code/app/*.json'), 'c:/code/app/*.json')
  eq (schemas.glob ([[D:\data\a.json]]), 'd:/data/a.json')
  eq (schemas.glob ('/C:/code/a.json'), 'c:/code/a.json')
end)

test ('from_catalog keeps the JSON patterns of each schema', function ()
  local catalog = {
    schemas = {
      {
        name = 'package.json',
        fileMatch = { 'package.json' },
        url = 'https://www.schemastore.org/package.json',
      },
      {
        name = 'Mixed',
        fileMatch = { 'a.yml', 'a.json', 'b.JSONC', 'c.json5', '.arc' },
        url = 'https://example.com/a.json',
      },
      {
        name = 'YAML only',
        fileMatch = { '**/.github/workflows/*.yml' },
        url = 'https://example.com/workflow.json',
      },
      { name = 'No files', url = 'https://example.com/none.json' },
      { name = 'No address', fileMatch = { 'x.json' } },
    },
  }
  eq (schemas.from_catalog (catalog), {
    {
      fileMatch = { 'package.json' },
      url = 'https://www.schemastore.org/package.json',
    },
    {
      fileMatch = { 'a.json', 'b.JSONC', 'c.json5' },
      url = 'https://example.com/a.json',
    },
  })
end)

test ('from_catalog gives nothing for a broken catalog', function ()
  eq (schemas.from_catalog (nil), {})
  eq (schemas.from_catalog ({}), {})
  eq (schemas.from_catalog ({ schemas = 'no' }), {})
end)

test (
  'merge puts the associations first, one entry for each address',
  function ()
    local ts = 'https://www.schemastore.org/tsconfig.json'
    local list = schemas.merge ({
      { kind = 'schema', pattern = 'tsconfig.json', value = ts },
      { kind = 'schema', pattern = 'tsconfig.*.json', value = ts },
      {
        kind = 'schema',
        pattern = 'package.json',
        value = 'https://example.com/package.json',
      },
    }, {})
    eq (list, {
      { fileMatch = { '**/tsconfig.json', '**/tsconfig.*.json' }, url = ts },
      {
        fileMatch = { '**/package.json' },
        url = 'https://example.com/package.json',
      },
    })
  end
)

test ("merge leaves out the catalog's patterns an association names", function ()
  local list = schemas.merge ({
    {
      kind = 'schema',
      pattern = 'package.json',
      value = 'https://example.com/package.json',
    },
  }, {
    {
      fileMatch = { 'package.json' },
      url = 'https://www.schemastore.org/package.json',
    },
    {
      fileMatch = { 'package.json', 'other.json' },
      url = 'https://example.com/both.json',
    },
  })
  eq (list, {
    {
      fileMatch = { '**/package.json' },
      url = 'https://example.com/package.json',
    },
    { fileMatch = { 'other.json' }, url = 'https://example.com/both.json' },
  })
end)

test (
  'settings keep certificate checks on and leave out an empty list',
  function ()
    eq (schemas.settings ({}, true), {
      json = { validate = { enable = true } },
      http = { proxyStrictSSL = true },
    })
    local list = { { fileMatch = { '**/a.json' }, url = 'https://a' } }
    eq (schemas.settings (list, false), {
      json = { validate = { enable = false }, schemas = list },
      http = { proxyStrictSSL = true },
    })
  end
)

test ('merge leaves out a schema given as a table or a function', function ()
  local list = schemas.merge ({
    { kind = 'schema', pattern = 'a.json', value = { type = 'object' } },
    {
      kind = 'schema',
      pattern = 'b.json',
      value = function ()
        return { type = 'object' }
      end,
    },
    {
      kind = 'schema',
      pattern = 'c.json',
      value = 'https://example.com/c.json',
    },
  }, {})
  eq (list, {
    { fileMatch = { '**/c.json' }, url = 'https://example.com/c.json' },
  })
end)
