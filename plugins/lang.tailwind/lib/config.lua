-- config: the `tailwindCSS` settings section the server asks for, from the plugin's
-- settings. The server fills in its own defaults for anything left out, so only what the
-- settings say goes out. Nothing here calls the app, so the tests reach it.

---@class LangTailwind.ConfigModule
local M = {}

-- The levels a problem rule may have.
local LEVELS = { ignore = true, warning = true, error = true }

---The strings in a list, without empty ones. With `pairs_too`, a list of two strings counts
---too, the way a class pattern names the call around the classes and then the classes.
---@param value any
---@param pairs_too? boolean
---@return any[]
local function strings (value, pairs_too)
  local out = {} ---@type any[]
  if type (value) ~= 'table' then
    return out
  end
  for _, item in ipairs (value) do
    if type (item) == 'string' and item ~= '' then
      out[#out + 1] = item
    elseif
      pairs_too
      and type (item) == 'table'
      and #item == 2
      and type (item[1]) == 'string'
      and type (item[2]) == 'string'
    then
      out[#out + 1] = { item[1], item[2] }
    end
  end
  return out
end

---The `tailwindCSS` section.
---@param class_attributes any `tailwind.class_attributes`, a list of attribute names.
---@param class_regex any `tailwind.class_regex`, a list of regular expressions, or of pairs.
---@param lint any `tailwind.lint`, a level for each problem rule.
---@return table
function M.section (class_attributes, class_regex, lint)
  local section = { emmetCompletions = false } ---@type table<string, any>
  local attributes = strings (class_attributes)
  -- Left out when empty, so the server keeps its own list.
  if #attributes > 0 then
    section.classAttributes = attributes
  end
  local regex = strings (class_regex, true)
  if #regex > 0 then
    section.experimental = { classRegex = regex }
  end
  local rules = {} ---@type table<string, string>
  if type (lint) == 'table' then
    for rule, level in pairs (lint) do
      if type (rule) == 'string' and LEVELS[level] then
        rules[rule] = level
      end
    end
  end
  if next (rules) then
    section.lint = rules
  end
  return section
end

return M
