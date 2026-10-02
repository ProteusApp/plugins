-- Every icon pack in the registry, a plugin that depends on the icons service and nothing else
-- but the files service, gives a look to every kind of file and folder in the app's
-- lib/file_kinds.lua, each look is a Lucide icon or a short badge, and each fixed color stands
-- out from the background of every theme: 3:1, as WCAG asks of icons. A color may be a theme
-- variable, which follows the theme, or `light-dark(light, dark)`, whose first color shows on
-- light themes and second on dark ones.

local contract = require ('theme_contract') --[[@as ThemeContract]]
local file_kinds = require ('file_kinds') --[[@as FileKinds]]

local ICONS = { ['core.icons'] = true, ['proteus.core.icons'] = true }
local THEMES = { ['core.themes'] = true, ['proteus.core.themes'] = true }

---True when a plugin's table names one of `wanted` in `depends`.
---@param plugin table
---@param wanted table<string, true>
---@return boolean
local function depends_on (plugin, wanted)
  for _, dep in ipairs (plugin.depends or {}) do
    if wanted[dep] then
      return true
    end
  end
  return false
end

---What a pack plugin registers when it starts: its packs and its associations.
---@param plugin table
---@return table[] packs
---@return table[] associations
local function start (plugin)
  local packs, list = {}, {}
  local app = {
    use = function (name)
      if name == 'icons' then
        return {
          register = function (spec)
            packs[#packs + 1] = spec
          end,
        }
      end
      assert (name == 'files', 'uses only icons and files, not ' .. name)
      return {
        associate = function (a)
          list[#list + 1] = a
        end,
      }
    end,
  }
  if plugin.activate then
    plugin.activate (app)
  end
  return packs, list
end

-- The backgrounds icons sit on, in the explorers and the tabs: bg and bg-alt of every theme in
-- the registry, and of the app's dark and light defaults.
local backgrounds = { light = {}, dark = {} }
do
  local all = {
    midnight = { id = 'midnight', dark = true },
    daylight = { id = 'daylight', dark = false },
  }
  local list = { all.midnight, all.daylight }
  for _, id in ipairs (plugin_ids ()) do
    local plugin = load_plugin (id)
    if depends_on (plugin, THEMES) then
      for _, theme in ipairs (plugin.themes or {}) do
        all[theme.id] = theme
        list[#list + 1] = theme
      end
    end
  end
  for _, theme in ipairs (list) do
    local vars = contract.resolve (theme, function (tid)
      return all[tid]
    end)
    local into = theme.dark == false and backgrounds.light or backgrounds.dark
    into[#into + 1] = { theme.id, vars.bg }
    into[#into + 1] = { theme.id, vars['bg-alt'] }
  end
end

---What is wrong with a color, measured against the backgrounds of light or dark themes.
---@param color string
---@param scheme 'light'|'dark'
---@return string?
local function stands_out (color, scheme)
  for _, bg in ipairs (backgrounds[scheme]) do
    local ratio = contract.contrast (color, bg[2])
    if not ratio then
      return color .. ' is not a color'
    end
    if ratio < 3 then
      return string.format (
        '%s is %.2f:1 on %s of %s, under 3:1',
        color,
        ratio,
        bg[2],
        bg[1]
      )
    end
  end
  return nil
end

---What is wrong with a look, or nil.
---@param look any
---@param folder boolean
---@return string?
local function look_problem (look, folder)
  if type (look) ~= 'table' then
    return 'is not a table'
  end
  local icon, text = look.icon, look.text
  if
    icon ~= nil
    and not (type (icon) == 'string' and icon:match ('^[a-z][a-z0-9-]*$'))
  then
    return 'has an icon that is not a Lucide name'
  end
  if
    text ~= nil and not (type (text) == 'string' and #text >= 1 and #text <= 3)
  then
    return 'has a badge that is not one to three letters'
  end
  if icon == nil and text == nil then
    return 'has neither an icon nor a badge'
  end
  if folder and type (look.open) ~= 'string' then
    return 'is a folder without an open icon'
  end
  local color = look.color
  if
    color == nil
    or (type (color) == 'string' and color:match ('^var%(%-%-[a-z0-9-]+%)$'))
  then
    return nil
  end
  if type (color) ~= 'string' then
    return 'has a color that is not text'
  end
  local light, dark = color:match ('^light%-dark%((#%x+), (#%x+)%)$')
  if light then
    return stands_out (light, 'light') or stands_out (dark, 'dark')
  end
  if not contract.parse (color) then
    return 'has the color '
      .. color
      .. ', which is not a hex, a theme variable or light-dark()'
  end
  return stands_out (color, 'light') or stands_out (color, 'dark')
end

-- A pack plugin depends on the icons service, and on nothing but it and the files service.
local PACK_DEPENDS = {
  ['core.icons'] = true,
  ['proteus.core.icons'] = true,
  ['core.files'] = true,
  ['proteus.core.files'] = true,
}

---True when a plugin is an icon pack.
---@param plugin table
---@return boolean
local function is_pack (plugin)
  for _, dep in ipairs (plugin.depends or {}) do
    if not PACK_DEPENDS[dep] then
      return false
    end
  end
  return depends_on (plugin, ICONS)
end

local packs = {}
for _, id in ipairs (plugin_ids ()) do
  local plugin = load_plugin (id)
  if is_pack (plugin) then
    packs[#packs + 1] = { id = id, plugin = plugin }
  end
end

test ('the registry has icon packs to check', function ()
  ok (#packs > 0)
end)

for _, entry in ipairs (packs) do
  test (
    entry.id .. ' draws every kind of file, and reads on every theme',
    function ()
      local registered, list = start (entry.plugin)
      ok (#registered > 0, 'it registers a pack')
      local features = {}
      for _, f in ipairs ((entry.plugin.requires or {}).features or {}) do
        features[f] = true
      end
      ok (features.icons, 'it needs the feature icons')
      local problems = {} ---@type string[]
      for _, pack in ipairs (registered) do
        local where = entry.id .. ': ' .. tostring (pack.id)
        ok (type (pack.id) == 'string', where .. ' has an id')
        ok (
          type (pack.name) == 'string' and pack.name ~= '',
          where .. ' has a name'
        )
        for _, field in ipairs ({ 'file', 'folder' }) do
          local problem = look_problem (pack[field], field == 'folder')
          if problem then
            problems[#problems + 1] = where
              .. ': its '
              .. field
              .. ' icon '
              .. problem
          end
        end
        if pack.kinds then
          ok (
            features['file-kinds'],
            where .. ' has kinds, so it needs the feature file-kinds'
          )
          local known = {}
          for _, kind in ipairs (file_kinds.all ()) do
            known[kind.id] = kind
            local problem =
              look_problem (pack.kinds[kind.id], kind.folder == true)
            if problem then
              problems[#problems + 1] = where
                .. ': '
                .. kind.id
                .. ' '
                .. problem
            end
          end
          for kid in pairs (pack.kinds) do
            if not known[kid] then
              problems[#problems + 1] = where
                .. ': '
                .. tostring (kid)
                .. ' is no kind of file'
            end
          end
        end
      end
      for _, a in ipairs (list) do
        local value = a.value or {}
        local where = entry.id .. ': ' .. tostring (a.pattern)
        eq (a.kind, 'icon', where)
        local problem = look_problem (value, value.folder == true)
        if problem then
          problems[#problems + 1] = where .. ' ' .. problem
        end
      end
      ok (#problems == 0, table.concat (problems, '\n'))
    end
  )
end
