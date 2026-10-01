local launch = require ('lib.launch') --[[@as LangLuau.LaunchModule]]

test ('plain Luau loads only the documentation', function ()
  eq (
    launch.server_args ({ docs = 'C:/ws/data/lang.luau-lsp/luau-api-docs.json' }),
    {
      'lsp',
      '--no-flags-enabled',
      '--docs=C:/ws/data/lang.luau-lsp/luau-api-docs.json',
      '--stdio',
    }
  )
end)

test (
  'Roblox mode loads the definitions as @roblox, and their documentation',
  function ()
    eq (
      launch.server_args ({
        definitions = '/home/ana/ws/data/lang.luau-lsp/globalTypes.PluginSecurity.d.luau',
        docs = '/home/ana/ws/data/lang.luau-lsp/api-docs.json',
      }),
      {
        'lsp',
        '--no-flags-enabled',
        '--definitions:@roblox=/home/ana/ws/data/lang.luau-lsp/globalTypes.PluginSecurity.d.luau',
        '--docs=/home/ana/ws/data/lang.luau-lsp/api-docs.json',
        '--stdio',
      }
    )
  end
)

test ('a server with no files still starts', function ()
  eq (launch.server_args ({}), { 'lsp', '--no-flags-enabled', '--stdio' })
end)

test ('plain Luau tells the server it is not Roblox code', function ()
  local s = launch.settings (false, true)
  eq (s.platform, { type = 'standard' })
  eq (s.sourcemap.enabled, false)
end)

test (
  'Roblox mode reads the sourcemap while luau-lsp.sourcemap is on',
  function ()
    local s = launch.settings (true, true)
    eq (s.platform, { type = 'roblox' })
    eq (s.sourcemap, {
      enabled = true,
      autogenerate = false,
      sourcemapFile = 'sourcemap.json',
    })
    eq (launch.settings (true, false).sourcemap.enabled, false)
  end
)

test ('completion inserts names alone, and no imports', function ()
  eq (launch.settings (true, true).completion, {
    addParentheses = false,
    imports = { enabled = false },
  })
end)

---True when a table, or any table inside it, has no keys.
---@param t table
---@return boolean
local function has_empty (t)
  if next (t) == nil then
    return true
  end
  for _, v in pairs (t) do
    if type (v) == 'table' and has_empty (v) then
      return true
    end
  end
  return false
end

test ('the settings hold no empty table, which could go out as []', function ()
  for _, roblox in ipairs ({ true, false }) do
    for _, sourcemap in ipairs ({ true, false }) do
      ok (not has_empty (launch.settings (roblox, sourcemap)))
    end
  end
end)

test ('Rojo writes the sourcemap and watches the project', function ()
  eq (launch.rojo_args (), {
    'sourcemap',
    'default.project.json',
    '--output',
    'sourcemap.json',
    '--watch',
    '--include-non-scripts',
  })
end)

test ('StyLua reads Luau from its input, for the file at a path', function ()
  eq (launch.stylua_args ('C:/code/game/src/main.luau'), {
    '--syntax',
    'Luau',
    '--search-parent-directories',
    '--stdin-filepath',
    'C:/code/game/src/main.luau',
    '-',
  })
end)

test ('the server hears about Luau files and its own settings files', function ()
  ok (launch.watched ('C:/code/game/src/main.luau'))
  ok (launch.watched ('C:/code/game/src/old.lua'))
  ok (launch.watched ('C:/code/game/.luaurc'))
  ok (launch.watched ('C:/code/game/sourcemap.json'))
  ok (not launch.watched ('C:/code/game/README.md'))
  ok (not launch.watched ('C:/code/game/my-sourcemap.json'))
end)

test ('file events keep the changes under the folder, by kind', function ()
  local function uri (path)
    return 'file:///' .. path
  end
  local events = launch.file_events ({
    { path = 'C:/code/game/src/a.luau', kind = 'file' },
    { path = 'C:/code/game/src/b.luau', kind = 'remove' },
    { path = 'C:/code/game/src', kind = 'dir' },
    { path = 'C:/code/game/notes.txt', kind = 'file' },
    { path = 'C:/code/other/c.luau', kind = 'file' },
    { path = 'C:/code/game-two/d.luau', kind = 'file' },
  }, 'C:/code/game/', uri)
  eq (events, {
    { uri = 'file:///C:/code/game/src/a.luau', type = 2 },
    { uri = 'file:///C:/code/game/src/b.luau', type = 3 },
  })
end)
