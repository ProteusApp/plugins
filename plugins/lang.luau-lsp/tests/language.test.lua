local language = require ('lib.language') --[[@as Proteus.LanguageSpec]]

---The words of a list, as a set.
---@param words string|string[]|nil
---@return table<string, true>
local function set (words)
  local out = {}
  if type (words) == 'string' then
    for w in words:gmatch ('%S+') do
      out[w] = true
    end
  elseif type (words) == 'table' then
    for _, w in ipairs (words) do
      out[w] = true
    end
  end
  return out
end

test ('the language is luau, for .luau files, with -- comments', function ()
  eq (language.name, 'luau')
  eq (language.extensions, { 'luau' })
  eq ((language --[[@as table]]).comment, '--')
end)

test ('the words Luau adds to Lua are keywords', function ()
  local keywords = set (language.keywords)
  for _, w in ipairs ({ 'continue', 'type', 'export', 'typeof' }) do
    ok (keywords[w], w .. ' is a keyword')
  end
end)

test ('every block keyword is a keyword too, so it is colored', function ()
  local keywords = set (language.keywords)
  for w in pairs (set (language.block_keywords)) do
    ok (keywords[w], w .. ' is in keywords')
  end
end)

test ('no word is in two lists', function ()
  local seen = {}
  for _, field in ipairs ({ 'keywords', 'types', 'builtins', 'atoms' }) do
    for w in pairs (set (language[field])) do
      ok (not seen[w], w .. ' is in ' .. tostring (seen[w]) .. ' and ' .. field)
      seen[w] = field
    end
  end
end)
