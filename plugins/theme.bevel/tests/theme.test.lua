-- The theme sets every variable core.themes defines, with a color a browser reads, and its
-- CSS loads nothing from elsewhere.

local plugin = require ('init')

local KEYS = {
  'bg',
  'bg-alt',
  'bg-elev',
  'bg-hover',
  'bg-active',
  'fg',
  'fg-muted',
  'fg-faint',
  'border',
  'accent',
  'accent-fg',
  'danger',
  'warning',
  'success',
  'selection',
  'scrollbar',
  'shadow',
  'editor-bg',
  'editor-line',
  'syn-keyword',
  'syn-string',
  'syn-number',
  'syn-constant',
  'syn-comment',
  'syn-function',
  'syn-operator',
  'syn-property',
  'syn-builtin',
}

---The themes the plugin registers when it starts.
---@return table[]
local function registered ()
  local got = {}
  local app = {
    use = function (name)
      assert (
        name == 'themes',
        'uses only the themes service, not ' .. tostring (name)
      )
      return {
        register = function (spec)
          got[#got + 1] = spec
        end,
      }
    end,
  }
  plugin.activate (app)
  return got
end

test ('it registers its themes', function ()
  local ids = {}
  for i, t in ipairs (registered ()) do
    ids[i] = t.id
  end
  eq (ids, { 'bevel' })
end)

test ('every theme sets every variable', function ()
  for _, t in ipairs (registered ()) do
    ok (type (t.name) == 'string' and t.name ~= '', t.id .. ' has a name')
    ok (type (t.dark) == 'boolean', t.id .. ' says whether it is dark')
    for _, key in ipairs (KEYS) do
      ok (type (t.vars[key]) == 'string', t.id .. ' sets ' .. key)
    end
  end
end)

test ('every color is a hex color or rgba', function ()
  for _, t in ipairs (registered ()) do
    for key, value in pairs (t.vars) do
      if not (key == 'shadow' or key == 'radius' or key:find ('^font')) then
        local hex = value:match ('^#%x%x%x%x%x%x$')
        local rgba = value:match ('^rgba%(%d+,%d+,%d+,%.%d+%)$')
        ok (hex or rgba, t.id .. ': ' .. key .. ' is ' .. value)
      end
    end
  end
end)

test ('text stands out from the background', function ()
  ---@param hex string
  ---@return number
  local function luminance (hex)
    local sum = 0
    for i, w in ipairs ({ 0.2126, 0.7152, 0.0722 }) do
      local c = tonumber (hex:sub (2 * i, 2 * i + 1), 16) / 255
      c = c <= 0.03928 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
      sum = sum + w * c
    end
    return sum
  end
  for _, t in ipairs (registered ()) do
    for _, pair in ipairs ({
      { 'fg', 'bg' },
      { 'fg', 'editor-bg' },
      { 'accent-fg', 'accent' },
    }) do
      local a, b = luminance (t.vars[pair[1]]), luminance (t.vars[pair[2]])
      local ratio = (math.max (a, b) + 0.05) / (math.min (a, b) + 0.05)
      ok (
        ratio >= 4.5,
        t.id .. ': ' .. pair[1] .. ' on ' .. pair[2] .. ' is ' .. ratio
      )
    end
    ok (
      (luminance (t.vars.bg) < 0.2) == t.dark,
      t.id .. ' is as dark as it says'
    )
  end
end)

test ('its CSS is plain CSS that loads nothing', function ()
  for _, t in ipairs (registered ()) do
    ok (type (t.css) == 'string' and #t.css > 0, t.id .. ' has CSS')
    ok (not t.css:find ('url%s*%('), t.id .. ' loads no file or address')
    ok (not t.css:find ('@import'), t.id .. ' imports nothing')
    ok (not t.css:find ('expression%s*%('), t.id .. ' runs no script')
    local depth = 0
    for c in t.css:gmatch ('[{}]') do
      depth = depth + (c == '{' and 1 or -1)
      ok (depth >= 0, t.id .. ' closes no brace it did not open')
    end
    eq (depth, 0, t.id .. ' closes every brace')
  end
end)
