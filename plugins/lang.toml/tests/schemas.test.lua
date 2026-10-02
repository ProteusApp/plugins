local schemas = require ('lib.schemas') --[[@as LangToml.SchemasModule]]

test ('for_taplo names the catalog address Taplo checks for', function ()
  local out = schemas.for_taplo ({
    ['$schema'] = 'https://www.schemastore.org/schema-catalog.json',
    schemas = {},
  })
  eq (out['$schema'], 'https://json.schemastore.org/schema-catalog.json')
  eq (out.schemas, {})
end)

test ('for_taplo keeps the TOML patterns of each schema', function ()
  local out = schemas.for_taplo ({
    schemas = {
      {
        name = 'Cargo Manifest',
        description = 'Rust packages',
        fileMatch = { 'Cargo.toml' },
        url = 'https://www.schemastore.org/cargo.json',
        versions = { ['1'] = 'https://example.com/v1.json' },
      },
      {
        name = 'Mixed',
        fileMatch = { 'a.json', 'a.TOML', '**/.config/b.toml', 'c.yml' },
        url = 'https://example.com/a.json',
      },
      {
        name = 'JSON only',
        fileMatch = { 'package.json' },
        url = 'https://example.com/package.json',
      },
      { name = 'No files', url = 'https://example.com/none.json' },
      { name = 'No address', fileMatch = { 'x.toml' } },
    },
  })
  eq (out.schemas, {
    {
      name = 'Cargo Manifest',
      description = 'Rust packages',
      url = 'https://www.schemastore.org/cargo.json',
      fileMatch = { 'Cargo.toml' },
    },
    {
      name = 'Mixed',
      description = '',
      url = 'https://example.com/a.json',
      fileMatch = { 'a.TOML', '**/.config/b.toml' },
    },
  })
end)

test (
  'for_taplo gives an empty list for something that is not a catalog',
  function ()
    eq (schemas.for_taplo (nil).schemas, {})
    eq (schemas.for_taplo ({ schemas = 'nope' }).schemas, {})
  end
)

test ('allowed takes a schema only from a plugin with the network', function ()
  local plugins = {
    ['proteus.lang.x'] = { trusted = true, permissions = {} },
    ['lang.rust'] = { trusted = false, permissions = { 'process', 'net' } },
    ['sneaky'] = { trusted = false, permissions = { 'clipboard' } },
  }
  ---@param id string
  ---@return Proteus.PluginInfo?
  local function plugin_of (id)
    return plugins[id] --[[@as Proteus.PluginInfo?]]
  end
  ---@param owner string?
  ---@param value any
  ---@return boolean
  local function allowed (owner, value)
    return schemas.allowed ({
      kind = 'schema',
      pattern = 'Cargo.toml',
      value = value,
      owner = owner,
    }, plugin_of)
  end
  eq (allowed ('proteus.lang.x', 'https://example.com/a.json'), true)
  eq (allowed ('lang.rust', 'https://example.com/a.json'), true)
  eq (allowed ('sneaky', 'https://example.com/?data=secret'), false)
  eq (allowed ('missing', 'https://example.com/a.json'), false)
  eq (allowed (nil, 'https://example.com/a.json'), false)
  eq (allowed ('lang.rust', { type = 'object' }), false)
end)
