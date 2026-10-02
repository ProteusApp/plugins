-- log_text: small text helpers the log viewer's modules share. It escapes text for HTML,
-- trims it, makes a sentence of a message, writes numbers with commas, cuts text to a size
-- without splitting a character, and splits text into lines.

---@class Logs.TextModule
---@field escape fun(text: string): string
---@field trim fun(text: string): string
---@field sentence fun(text: string): string
---@field group fun(n: number): string
---@field clip fun(text: string, max: integer): string
---@field split_lines fun(text: string): string[]

---@type table<string, string>
local HTML = {
  ['&'] = '&amp;',
  ['<'] = '&lt;',
  ['>'] = '&gt;',
  ['"'] = '&quot;',
  ["'"] = '&#39;',
}

---@param text string
---@return string
local function escape (text)
  return (text:gsub ('[&<>"\']', HTML))
end

---@param text string
---@return string
local function trim (text)
  return (text:gsub ('^%s+', ''):gsub ('%s+$', ''))
end

---A message from elsewhere as a sentence: a capital first letter and a stop at the end.
---@param text string
---@return string
local function sentence (text)
  local out = trim (text):gsub ('^%l', string.upper)
  if out ~= '' and not out:find ('[%.!?]$') then
    out = out .. '.'
  end
  return out
end

---A whole number with commas between each group of three digits.
---@param n number
---@return string
local function group (n)
  local digits = tostring (math.floor (math.abs (n)))
  local grouped = digits:reverse ():gsub ('(%d%d%d)', '%1,'):reverse () ---@type string
  if grouped:sub (1, 1) == ',' then
    grouped = grouped:sub (2)
  end
  return (n < 0 and '-' or '') .. grouped
end

---Cuts text to at most `max` bytes without splitting a UTF-8 character.
---@param text string
---@param max integer
---@return string
local function clip (text, max)
  if #text <= max then
    return text
  end
  local cut = max
  local byte = text:byte (cut + 1) or 0
  while cut > 0 and byte >= 128 and byte < 192 do
    cut = cut - 1
    byte = text:byte (cut + 1) or 0
  end
  return text:sub (1, cut)
end

---Splits text into lines. A newline at the very end does not make an empty last line.
---@param text string
---@return string[]
local function split_lines (text)
  ---@type string[]
  local out = {}
  if text == '' then
    return out
  end
  local norm = text:gsub ('\r\n', '\n'):gsub ('\r', '\n')
  for piece in (norm .. '\n'):gmatch ('([^\n]*)\n') do
    out[#out + 1] = piece
  end
  if norm:sub (-1) == '\n' then
    out[#out] = nil
  end
  return out
end

---@type Logs.TextModule
local M = {
  escape = escape,
  trim = trim,
  sentence = sentence,
  group = group,
  clip = clip,
  split_lines = split_lines,
}

return M
