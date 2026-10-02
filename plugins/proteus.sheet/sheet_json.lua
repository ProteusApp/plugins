-- sheet_json: the JSON reader of the Sheet app, for `.sheet.json` files. `parse_json` reads
-- JSON text into Lua values: objects become tables with string keys, arrays become lists, and
-- null becomes nil. It refuses text nested deeper than it can read safely. The module is pure.

---@class Sheet.JsonModule
local M = {}

local JSON_DEPTH = 100
local UNESCAPE = {
  ['"'] = '"',
  ['\\'] = '\\',
  ['/'] = '/',
  b = '\b',
  f = '\f',
  n = '\n',
  r = '\r',
  t = '\t',
}

-- Marks the errors the reader raises, apart from any other error.
local JSON_FAIL = 'json: '

---@class Sheet.JsonReader
---@field text string
---@field pos integer

---@param r Sheet.JsonReader
---@param message string
local function json_fail (r, message)
  error (JSON_FAIL .. message .. ' at byte ' .. r.pos .. '.', 0)
end

---@param r Sheet.JsonReader
local function json_space (r)
  local _, e = string.find (r.text, '^[ \t\r\n]*', r.pos)
  r.pos = (e or r.pos - 1) + 1
end

---@param r Sheet.JsonReader
---@return string
local function json_read_string (r)
  local text = r.text
  local parts = {} ---@type string[]
  local pos = r.pos + 1
  while true do
    local s, e = string.find (text, '["\\]', pos)
    if not s then
      r.pos = #text
      json_fail (r, 'A text has no closing quote')
    end
    ---@cast s integer
    ---@cast e integer
    parts[#parts + 1] = string.sub (text, pos, s - 1)
    if string.sub (text, s, s) == '"' then
      r.pos = e + 1
      return table.concat (parts)
    end
    local ch = string.sub (text, s + 1, s + 1)
    if ch == 'u' then
      local hex = string.match (text, '^%x%x%x%x', s + 2)
      if not hex then
        r.pos = s
        json_fail (r, 'A \\u escape needs four hex digits')
      end
      local code = tonumber (hex, 16) --[[@as integer]]
      pos = s + 6
      if code >= 0xD800 and code <= 0xDBFF then
        local low = string.match (text, '^\\u(%x%x%x%x)', pos)
        local lc = low and tonumber (low, 16)
        if lc and lc >= 0xDC00 and lc <= 0xDFFF then
          code = 0x10000 + (code - 0xD800) * 0x400 + (lc - 0xDC00)
          pos = pos + 6
        end
      end
      parts[#parts + 1] = utf8.char (code)
    else
      local out = UNESCAPE[ch]
      if not out then
        r.pos = s
        json_fail (r, 'An escape in a text is not valid')
      end
      parts[#parts + 1] = out
      pos = s + 2
    end
  end
end

---@param r Sheet.JsonReader
---@param depth integer
---@return any
local function json_value (r, depth)
  if depth > JSON_DEPTH then
    json_fail (r, 'The data nests too deeply')
  end
  json_space (r)
  local text = r.text
  local ch = string.sub (text, r.pos, r.pos)
  if ch == '{' then
    local out = {} ---@type table<string, any>
    r.pos = r.pos + 1
    json_space (r)
    if string.sub (text, r.pos, r.pos) == '}' then
      r.pos = r.pos + 1
      return out
    end
    while true do
      json_space (r)
      if string.sub (text, r.pos, r.pos) ~= '"' then
        json_fail (r, 'A key must be a text in quotes')
      end
      local key = json_read_string (r)
      json_space (r)
      if string.sub (text, r.pos, r.pos) ~= ':' then
        json_fail (r, 'A ":" is missing after a key')
      end
      r.pos = r.pos + 1
      out[key] = json_value (r, depth + 1)
      json_space (r)
      local sep = string.sub (text, r.pos, r.pos)
      r.pos = r.pos + 1
      if sep == '}' then
        return out
      elseif sep ~= ',' then
        r.pos = r.pos - 1
        json_fail (r, 'A "," or "}" is missing')
      end
    end
  elseif ch == '[' then
    local out = {} ---@type any[]
    r.pos = r.pos + 1
    json_space (r)
    if string.sub (text, r.pos, r.pos) == ']' then
      r.pos = r.pos + 1
      return out
    end
    while true do
      out[#out + 1] = json_value (r, depth + 1)
      json_space (r)
      local sep = string.sub (text, r.pos, r.pos)
      r.pos = r.pos + 1
      if sep == ']' then
        return out
      elseif sep ~= ',' then
        r.pos = r.pos - 1
        json_fail (r, 'A "," or "]" is missing')
      end
    end
  elseif ch == '"' then
    return json_read_string (r)
  end
  for word, value in pairs ({ ['true'] = true, ['false'] = false }) do
    if string.sub (text, r.pos, r.pos + #word - 1) == word then
      r.pos = r.pos + #word
      return value
    end
  end
  if string.sub (text, r.pos, r.pos + 3) == 'null' then
    r.pos = r.pos + 4
    return nil
  end
  local num = string.match (text, '^-?%d+%.?%d*[eE]?[+-]?%d*', r.pos)
  local n = num and tonumber (num)
  if not n then
    json_fail (r, 'A value is not valid JSON')
  end
  r.pos = r.pos + #num
  return n
end

---Reads JSON text into Lua values. Returns nil and a message when the text is not JSON.
---@param text string
---@return any
---@return string? problem
function M.parse_json (text)
  if type (text) ~= 'string' then
    return nil, 'There is no text to read.'
  end
  ---@type Sheet.JsonReader
  local r = { text = text, pos = 1 }
  local ok, result = pcall (json_value, r, 0)
  if not ok then
    local text_error = tostring (result)
    if string.sub (text_error, 1, #JSON_FAIL) == JSON_FAIL then
      return nil, string.sub (text_error, #JSON_FAIL + 1)
    end
    return nil, text_error
  end
  json_space (r)
  if r.pos <= #text then
    return nil, 'There is more text after the data at byte ' .. r.pos .. '.'
  end
  return result, nil
end

return M
