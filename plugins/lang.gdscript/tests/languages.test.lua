local languages = require ('lib.languages')

---The words of a spec field, as a list.
---@param value string|string[]|nil
---@return string[]
local function words (value)
  if type (value) == 'table' then
    return value
  end
  local out = {}
  for w in tostring (value or ''):gmatch ('%S+') do
    out[#out + 1] = w
  end
  return out
end

test ('every word fits the rules ui.language checks', function ()
  for _, spec in ipairs ({ languages.gdscript, languages.resource }) do
    ok (spec.name:match ('^%l[%l%d_-]*$') and #spec.name <= 32, spec.name)
    for _, field in ipairs ({ 'keywords', 'types', 'builtins', 'atoms' }) do
      for _, w in ipairs (words (spec[field])) do
        ok (
          w:match ('^[%a_$][%w_$]*$') and #w <= 64,
          spec.name .. ' ' .. field .. ': ' .. w
        )
      end
    end
  end
end)

test ('each block keyword is a keyword too, so it is colored', function ()
  local known = {}
  for _, w in ipairs (words (languages.gdscript.keywords)) do
    known[w] = true
  end
  for _, w in ipairs (words (languages.gdscript.block_keywords)) do
    ok (known[w], w .. ' is not in keywords')
  end
end)

test ('a word appears once in each list', function ()
  for _, spec in ipairs ({ languages.gdscript, languages.resource }) do
    for _, field in ipairs ({ 'keywords', 'types', 'builtins', 'atoms' }) do
      local seen = {}
      for _, w in ipairs (words (spec[field])) do
        ok (not seen[w], spec.name .. ' ' .. field .. ' has ' .. w .. ' twice')
        seen[w] = true
      end
    end
  end
end)

test ('GDScript files are .gd and comments start with #', function ()
  eq (languages.gdscript.extensions, { 'gd' })
  eq (languages.gdscript.comment, '#')
  eq (languages.gdscript.attribute, '@')
end)

test (
  'scenes, resources and project files get the resource language',
  function ()
    eq (languages.resource.extensions, { 'tscn', 'tres', 'godot', 'import' })
    eq (languages.resource.comment, ';')
  end
)
