-- Every theme in the registry meets the app's theme contract, lib/theme_contract.lua: it sets
-- only variables the app knows, each color is one a browser reads, and after the variables it
-- leaves out are filled in, text stands out from what it sits on as WCAG asks. Its CSS is plain
-- CSS that loads nothing from elsewhere.

local contract = require ('theme_contract') --[[@as ThemeContract]]

local THEMES = { ['core.themes'] = true, ['proteus.core.themes'] = true }

---True when a plugin's table names `wanted` in `depends`.
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

---The themes a plugin adds: the ones it lists in `themes`, and the ones it registers when it
---starts.
---@param plugin table
---@return table[]
local function themes_of (plugin)
  local out = {}
  for _, theme in ipairs (plugin.themes or {}) do
    out[#out + 1] = theme
  end
  if plugin.activate then
    local app = {
      use = function (name)
        assert (name == 'themes', 'uses only the themes service')
        return {
          register = function (spec)
            out[#out + 1] = spec
          end,
        }
      end,
    }
    plugin.activate (app)
  end
  return out
end

-- Every theme in the registry, and the builtin ones a theme may extend.
local all = {
  midnight = { id = 'midnight', dark = true },
  daylight = { id = 'daylight', dark = false },
}
local by_plugin = {}
for _, id in ipairs (plugin_ids ()) do
  local plugin = load_plugin (id)
  if depends_on (plugin, THEMES) then
    by_plugin[#by_plugin + 1] = { id = id, plugin = plugin }
    for _, theme in ipairs (themes_of (plugin)) do
      all[theme.id] = theme
    end
  end
end

---@param id string
---@return table?
local function find (id)
  return all[id]
end

local known = contract.defaults (true)

test ('the registry has themes to check', function ()
  ok (#by_plugin > 0)
end)

for _, entry in ipairs (by_plugin) do
  test (entry.id .. ' meets the theme contract', function ()
    local plugin = entry.plugin
    local themes = themes_of (plugin)
    ok (#themes > 0, 'it adds a theme')
    if plugin.themes then
      local features = {}
      for _, f in ipairs ((plugin.requires or {}).features or {}) do
        features[f] = true
      end
      ok (
        features['theme-data'],
        'a plugin that lists themes as data needs the feature theme-data'
      )
    end
    for _, theme in ipairs (themes) do
      local where = entry.id .. ': ' .. tostring (theme.id)
      ok (type (theme.id) == 'string', where .. ' has an id')
      ok (
        type (theme.name) == 'string' and theme.name ~= '',
        where .. ' has a name'
      )
      ok (type (theme.dark) == 'boolean', where .. ' says whether it is dark')
      for key, value in pairs (theme.vars or {}) do
        ok (
          known[key] ~= nil,
          where .. ' sets ' .. key .. ', which no theme has'
        )
        if contract.parse (known[key] or '') then
          ok (
            contract.parse (value),
            where
              .. ': '
              .. key
              .. ' is '
              .. tostring (value)
              .. ', not a color'
          )
        end
      end
      eq (contract.check (contract.resolve (theme, find), theme.dark), {}, where)
      local css = theme.css
      if css ~= nil then
        ok (type (css) == 'string', where .. ': css is text')
        ok (not css:find ('url%s*%('), where .. ' loads no file or address')
        ok (not css:find ('@import'), where .. ' imports nothing')
        ok (not css:find ('expression%s*%('), where .. ' runs no script')
        local depth = 0
        for c in css:gmatch ('[{}]') do
          depth = depth + (c == '{' and 1 or -1)
          ok (depth >= 0, where .. ' closes no brace it did not open')
        end
        eq (depth, 0, where .. ' closes every brace')
      end
    end
  end)
end
