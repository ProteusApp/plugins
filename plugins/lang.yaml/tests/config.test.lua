local config = require ('lib.config') --[[@as LangYaml.ConfigModule]]

---@param over table?
---@return LangYaml.Options
local function options (over)
  local opts = {
    associations = {},
    schema_store = true,
    custom_tags = {},
    validate = true,
    key_ordering = false,
    version = '1.2',
  }
  for k, v in pairs (over or {}) do
    opts[k] = v
  end
  return opts
end

test ('the yaml section holds every setting, with the formatter off', function ()
  eq (config.yaml (options ()), {
    validate = true,
    hover = true,
    completion = true,
    keyOrdering = false,
    yamlVersion = '1.2',
    format = { enable = false },
    schemaStore = {
      enable = true,
      url = 'https://www.schemastore.org/api/json/catalog.json',
    },
    schemas = {},
  })
end)

test (
  'custom tags go out without blanks or values that are not text',
  function ()
    local section = config.yaml (options ({
      custom_tags = { '!Ref scalar', '  !GetAtt sequence ', '', 3, false },
    }))
    eq (section.customTags, { '!Ref scalar', '!GetAtt sequence' })
  end
)

test ('custom tags are left out when there are none', function ()
  eq (config.yaml (options ({ custom_tags = 'not a list' })).customTags, nil)
  eq (config.yaml (options ({ custom_tags = {} })).customTags, nil)
end)

test ('the settings change what goes out', function ()
  local section = config.yaml (options ({
    schema_store = false,
    validate = false,
    key_ordering = true,
    version = '1.1',
    associations = { { pattern = 'x.yml', value = 'https://x.json' } },
  }))
  eq (section.schemaStore.enable, false)
  eq (section.validate, false)
  eq (section.keyOrdering, true)
  eq (section.yamlVersion, '1.1')
  eq (section.schemas, { ['https://x.json'] = { '**/x.yml' } })
end)

test ('an unknown version reads as 1.2', function ()
  eq (config.yaml (options ({ version = '9' })).yamlVersion, '1.2')
end)

test ('each section the server asks for gets an answer', function ()
  ok (config.section ('yaml', options ()).schemaStore)
  eq (config.section ('[yaml]', options ()), { ['editor.tabSize'] = 2 })
  eq (
    config.section ('editor', options ()),
    { tabSize = 2, detectIndentation = false }
  )
  eq (config.section ('http', options ()), nil)
  eq (config.section ('redhat', options ()), nil)
end)
