-- discord_config: the plugin's settings, which proteus.core.settings keeps for each profile, and
-- the move of the older settings file into them. It calls no host function, so the tests
-- reach it.

---The settings as the plugin uses them.
---@class Discord.Config
---@field enabled boolean
---@field client_id string
---@field show_names boolean False keeps file, plugin and repository names off Discord.
---@field idle_minutes number Minutes without activity before the presence says Idle. 0 never does.
---@field images table<string, string> An art asset name or image URL by app id, such as `editor`, or `default` for every app.

---@class Discord.Setting
---@field key string
---@field old string Its key in the older settings file.
---@field spec Proteus.SettingSpec

---@class Discord.ConfigModule
local M = {}

-- The Proteus application on Discord. Its name is what shows after "Playing".
M.CLIENT_ID = '562297553253564438'

-- The older settings file, shared by every profile. Its values move into Settings.
M.OLD_FILE = 'data/proteus.discord.rpc/discord.json'

---@type Discord.Setting[]
M.SETTINGS = {
  {
    key = 'discord.enabled',
    old = 'enabled',
    spec = {
      title = 'Rich Presence',
      type = 'boolean',
      default = false,
      description = 'Shows what you are doing in Proteus on your Discord profile. It works on Windows, with the Discord desktop app running.',
    },
  },
  {
    key = 'discord.show_names',
    old = 'show_names',
    spec = {
      title = 'Show names',
      type = 'boolean',
      default = true,
      description = 'Shows file, plugin, repository, branch and project names. Off keeps them off Discord.',
    },
  },
  {
    key = 'discord.idle_minutes',
    old = 'idle_minutes',
    spec = {
      title = 'Idle after',
      type = 'number',
      default = 10,
      description = 'Minutes without activity before the first line says Idle. 0 never does.',
    },
  },
  {
    key = 'discord.client_id',
    old = 'client_id',
    spec = {
      title = 'Application id',
      type = 'string',
      default = '',
      description = 'The Discord application whose name shows after "Playing". Empty uses the Proteus application.',
    },
  },
  {
    key = 'discord.images',
    old = 'images',
    spec = {
      title = 'Images',
      type = 'table',
      default = {},
      description = 'The large image by app id, such as editor or git, or default for every app. A value is an art asset name or an image address.',
    },
  },
}

-- The Lua type each setting's value has.
local LUA_TYPES = {
  boolean = 'boolean',
  number = 'number',
  string = 'string',
  table = 'table',
}

---The settings as the plugin uses them, read through `get`.
---@param get fun(key: string): any
---@return Discord.Config
function M.read (get)
  local id = get ('discord.client_id')
  local images = get ('discord.images')
  return {
    enabled = get ('discord.enabled') == true,
    client_id = type (id) == 'string' and id ~= '' and id or M.CLIENT_ID,
    show_names = get ('discord.show_names') ~= false,
    idle_minutes = tonumber (get ('discord.idle_minutes')) or 10,
    images = type (images) == 'table' and images or {},
  }
end

---Each setting's default, by key, for when proteus.core.settings does not run.
---@param key string
---@return any
function M.default (key)
  for _, s in ipairs (M.SETTINGS) do
    if s.key == key then
      return s.spec.default
    end
  end
  return nil
end

---What the older settings file moves into Settings: each value of the right type, by setting
---key, unless the user already set that key.
---@param raw table<string, any> The older file's contents.
---@param is_set fun(key: string): boolean
---@return table<string, any>
function M.moved (raw, is_set)
  local out = {} ---@type table<string, any>
  for _, s in ipairs (M.SETTINGS) do
    local value = raw[s.old]
    if
      value ~= nil
      and type (value) == LUA_TYPES[s.spec.type]
      and not is_set (s.key)
    then
      out[s.key] = value
    end
  end
  return out
end

return M
