-- lib/greetings.lua: the part of the plugin that touches nothing on screen. It makes a
-- greeting, keeps the list of them, and writes the list as Markdown. Keeping this apart from
-- init.lua lets tests/ check it without starting the app.

---@class Template.GreetingsModule
local M = {}

-- The most greetings the list keeps. Older ones drop off the end.
M.LIMIT = 20

---A greeting, such as `Hello, Ada!`. A name of only spaces greets the world.
---@param word string The setting's word, such as `Hello`.
---@param name? string
---@return string
function M.make (word, name)
  local who = tostring (name or ''):gsub ('^%s+', ''):gsub ('%s+$', '')
  if who == '' then
    who = 'world'
  end
  local start = tostring (word or ''):gsub ('^%s+', ''):gsub ('%s+$', '')
  if start == '' then
    start = 'Hello'
  end
  return start .. ', ' .. who .. '!'
end

---A new list with `text` first, and no more than `LIMIT` greetings.
---@param list string[]
---@param text string
---@return string[]
function M.add (list, text)
  local out = { text }
  for _, old in ipairs (list) do
    if #out >= M.LIMIT then
      break
    end
    out[#out + 1] = old
  end
  return out
end

---The list as a Markdown file, newest first.
---@param list string[]
---@return string
function M.markdown (list)
  local lines = { '# Greetings', '' }
  if #list == 0 then
    lines[#lines + 1] = 'None yet.'
  end
  for _, text in ipairs (list) do
    lines[#lines + 1] = '- ' .. text
  end
  return table.concat (lines, '\n') .. '\n'
end

return M
