local compose = require ('lib.compose') --[[@as LangDocker.ComposeModule]]

---True when a file name fits a pattern without `/`, the way the files service matches one:
---`*` is any run of characters, and the rest is itself.
---@param pattern string
---@param name string
---@return boolean
local function fits (pattern, name)
  local lua = '^'
    .. pattern:gsub ('[%^%$%(%)%%%.%[%]%+%-%?]', '%%%0'):gsub ('%*', '.*')
    .. '$'
  return name:match (lua) ~= nil
end

---True when any of the plugin's patterns fits the name.
---@param name string
---@return boolean
local function any_fits (name)
  for _, pattern in ipairs (compose.PATTERNS) do
    if fits (pattern, name) then
      return true
    end
  end
  return false
end

test ('the patterns are the ones SchemaStore lists for Compose', function ()
  -- The catalog's `fileMatch` for "docker-compose.yml", without its leading `**/`.
  eq (compose.PATTERNS, {
    'docker-compose.yml',
    'docker-compose.yaml',
    'docker-compose.*.yml',
    'docker-compose.*.yaml',
    'compose.yml',
    'compose.yaml',
    'compose.*.yml',
    'compose.*.yaml',
  })
end)

test ('the patterns fit Compose files and nothing else', function ()
  for _, name in ipairs ({
    'compose.yaml',
    'compose.yml',
    'compose.override.yaml',
    'docker-compose.yml',
    'docker-compose.prod.yml',
    'docker-compose.dev.local.yaml',
  }) do
    ok (any_fits (name), name)
  end
  for _, name in ipairs ({
    'compose.json',
    'my-compose.yml',
    'docker-compose.yml.bak',
    'composer.yaml',
    'Dockerfile',
  }) do
    ok (not any_fits (name), name)
  end
end)

test ('associations give every pattern the schema', function ()
  local list = compose.associations ()
  eq (#list, #compose.PATTERNS)
  for i, a in ipairs (list) do
    eq (a, {
      kind = 'schema',
      pattern = compose.PATTERNS[i],
      value = 'https://raw.githubusercontent.com/compose-spec/compose-go/master/schema/compose-spec.json',
    })
  end
end)
