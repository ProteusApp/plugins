local presence = require ('discord_presence') --[[@as Discord.PresenceModule]]

---@param ids string[]
---@return table<string, boolean>
local function running (ids)
  local set = {} ---@type table<string, boolean>
  for _, id in ipairs (ids) do
    set[id] = true
  end
  return set
end

---@param id string
---@return Discord.Preset
local function preset (id)
  return presence.detect (id, {})
end

---@param overrides? { idle?: boolean, start?: integer, image?: string }
---@return Discord.BuildOptions
local function opts (overrides)
  local o = overrides or {}
  return { idle = o.idle == true, start = o.start, image = o.image }
end

-- detect ---------------------------------------------------------------------------------

test ('detect picks the app named by a builtin profile', function ()
  eq (preset ('git').id, 'git')
  eq (preset ('notes').id, 'notes')
  eq (preset ('nodal').id, 'nodal')
end)

test (
  'detect finds the app in a copy of a profile by the plugins it runs',
  function ()
    eq (
      presence.detect (
        'editor-mine',
        running ({
          'proteus.editor.core',
          'proteus.ws.explorer',
          'proteus.nodal.app',
        })
      ).id,
      'editor'
    )
    eq (
      presence.detect (
        'my-nodal',
        running ({ 'proteus.editor.core', 'proteus.nodal.app' })
      ).id,
      'nodal'
    )
    eq (presence.detect ('work', running ({ 'proteus.kanban' })).id, 'kanban')
  end
)

test (
  'detect lets an app plugin win over the editor running beside it',
  function ()
    eq (
      presence.detect (
        'mixed',
        running ({ 'proteus.ws.explorer', 'proteus.git' })
      ).id,
      'git'
    )
  end
)

test ('detect falls back for a profile it does not know', function ()
  eq (presence.detect ('blank', running ({ 'proteus.hello' })).id, 'default')
end)

-- fill and pick --------------------------------------------------------------------------

test ('fill puts each word in place', function ()
  eq (
    presence.fill (
      'Editing {file} in {plugin}',
      { file = 'init.lua', plugin = 'proteus.git' }
    ),
    'Editing init.lua in proteus.git'
  )
  eq (presence.fill ('No words', {}), 'No words')
end)

test ('fill gives nothing when a word is missing or empty', function ()
  eq (presence.fill ('On branch {branch}', {}), nil)
  eq (presence.fill ('On branch {branch}', { branch = '' }), nil)
end)

test ('pick takes the first line whose words are all known', function ()
  local lines = { 'Editing {file}', 'Browsing the workspace' }
  eq (presence.pick (lines, { file = 'a.lua' }), 'Editing a.lua')
  eq (presence.pick (lines, {}), 'Browsing the workspace')
  eq (presence.pick ('Reading logs', {}), 'Reading logs')
  eq (presence.pick (nil, {}), nil)
end)

-- build ----------------------------------------------------------------------------------

test ('build shows the app lines with the start time', function ()
  local p = presence.build (
    preset ('git'),
    {},
    { repo = 'proteus', branch = 'main' },
    opts ({ start = 100 })
  )
  eq (p.details, 'Working on proteus')
  eq (p.state, 'On branch main')
  eq (p.start, 100)
  eq (p.large_image, nil)
  eq (p.large_text, nil)
end)

test ('build names the image after the app when there is one', function ()
  local editor = preset ('editor')
  eq (
    presence.build (editor, {}, { language = 'Lua' }, opts ({ image = 'lua' })).large_text,
    'Writing Lua'
  )
  eq (
    presence.build (editor, {}, {}, opts ({ image = 'logo' })).large_text,
    'Plugin Editor'
  )
  eq (
    presence.build (preset ('logs'), {}, {}, opts ({ image = 'logo' })).large_text,
    'Proteus Logs'
  )
end)

test ('build lays plugin presences over the app lines, newest last', function ()
  local layers = {
    { owner = 'a', presence = { details = 'From a', state = 'State a' } },
    {
      owner = 'b',
      presence = {
        details = 'From b',
        buttons = { { label = 'Open', url = 'https://x' } },
      },
    },
  }
  local p = presence.build (preset ('notes'), layers, {}, opts ())
  eq (p.details, 'From b')
  eq (p.state, 'State a')
  eq (p.buttons, { { label = 'Open', url = 'https://x' } })
end)

test (
  'build keeps the text underneath when a plugin line has an unknown word',
  function ()
    local layers = { { owner = 'a', presence = { state = 'Track {track}' } } }
    eq (presence.build (preset ('notes'), layers, {}, opts ()).state, 'Notes')
    eq (
      presence.build (preset ('notes'), layers, { track = 'Intro' }, opts ()).state,
      'Track Intro'
    )
  end
)

test (
  'build shows Idle with the app state and leaves plugin presences out',
  function ()
    local layers = { { owner = 'a', presence = { details = 'Playing music' } } }
    local p = presence.build (
      preset ('todo'),
      layers,
      { left = '3' },
      opts ({ idle = true })
    )
    eq (p.details, 'Idle')
    eq (p.state, '3 left to do')
  end
)

test (
  'build cuts long text to 128 bytes without splitting a character',
  function ()
    local name = string.rep ('é', 80) .. '.lua'
    local p = presence.build (preset ('editor'), {}, { file = name }, opts ())
    local details = assert (p.details, 'the presence has details')
    ok (#details <= 128)
    ok (details:sub (-3) == '...')
    ok (utf8.len (details) ~= nil)
  end
)

test ('build pads a one-byte line, which Discord would refuse', function ()
  local layers = { { owner = 'a', presence = { state = 'x' } } }
  eq (presence.build (preset ('notes'), layers, {}, opts ()).state, 'x ')
end)

-- settings -------------------------------------------------------------------------------

local config = require ('discord_config') --[[@as Discord.ConfigModule]]

test ('the settings read with their defaults', function ()
  local c = config.read (config.default)
  eq (c.enabled, false)
  eq (c.show_names, true)
  eq (c.idle_minutes, 10)
  eq (c.client_id, config.CLIENT_ID)
  eq (c.images, {})
  local mine = config.read (function (key)
    return ({
      ['discord.enabled'] = true,
      ['discord.client_id'] = '123',
      ['discord.images'] = { default = 'logo' },
    })[key]
  end)
  eq (mine.enabled, true)
  eq (mine.client_id, '123')
  eq (mine.images, { default = 'logo' })
end)

test (
  'the older settings file moves into the settings the user has not set',
  function ()
    local moved = config.moved ({
      enabled = true,
      show_names = false,
      idle_minutes = 'soon',
      client_id = '123',
      images = { git = 'git-logo' },
      other = 1,
    }, function (key)
      return key == 'discord.client_id'
    end)
    eq (moved, {
      ['discord.enabled'] = true,
      ['discord.show_names'] = false,
      ['discord.images'] = { git = 'git-logo' },
    })
  end
)

test ('every setting is under discord. and has a default', function ()
  for _, s in ipairs (config.SETTINGS) do
    ok (s.key:find ('^discord%.'), s.key)
    ok (s.spec.default ~= nil, s.key)
    ok (s.spec.description, s.key)
  end
end)
