local definitions = require ('lib.definitions') --[[@as LangLuau.DefinitionsModule]]

local DAY = 24 * 60 * 60 * 1000

test ('Roblox mode keeps the definitions and their documentation', function ()
  local files = definitions.files (true)
  eq (#files, 2)
  eq (files[1].kind, 'definitions')
  eq (files[1].name, 'globalTypes.PluginSecurity.d.luau')
  eq (
    files[1].url,
    'https://luau-lsp.pages.dev/type-definitions/globalTypes.PluginSecurity.d.luau'
  )
  eq (files[2].kind, 'docs')
  eq (files[2].url, 'https://luau-lsp.pages.dev/api-docs/en-us.json')
end)

test ('plain Luau keeps only the documentation for the Luau library', function ()
  eq (definitions.files (false), {
    {
      name = 'luau-api-docs.json',
      url = 'https://luau-lsp.pages.dev/api-docs/luau-en-us.json',
      kind = 'docs',
    },
  })
end)

test ('a file is due for a new copy after a day', function ()
  local now = 1790000000000
  eq (definitions.stale (now - 60 * 1000, now), false)
  eq (definitions.stale (now - DAY + 1, now), false)
  eq (definitions.stale (now - DAY - 1, now), true)
end)

test ('a file with no known time is due', function ()
  eq (definitions.stale (0, 1790000000000), true)
end)
