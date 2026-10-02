-- git_text: the small text helpers the other git modules share.

---@class Git.TextModule
local M = {}

---------------------------------------------------------------------------------------------
-- Small text helpers
---------------------------------------------------------------------------------------------

---Splits on one plain character and keeps empty fields.
---@param s string
---@param sep string
---@return string[]
function M.split (s, sep)
  local out = {} ---@type string[]
  local start = 1
  while true do
    local i = s:find (sep, start, true)
    if not i then
      out[#out + 1] = s:sub (start)
      return out
    end
    out[#out + 1] = s:sub (start, i - 1)
    start = i + 1
  end
end

---Splits text into lines. A newline at the very end does not start another line.
---@param text string
---@return string[]
function M.lines_of (text)
  local out = M.split (text, '\n')
  if out[#out] == '' then
    out[#out] = nil
  end
  return out
end

---@param s string
---@return string
function M.trim (s)
  local out = s:gsub ('^%s+', ''):gsub ('%s+$', '')
  return out
end

---@param s string
---@return string
function M.strip_cr (s)
  if s:sub (-1) == '\r' then
    return s:sub (1, -2)
  end
  return s
end

---@param s string?
---@return integer
function M.int (s)
  return math.floor (tonumber (s) or 0)
end

return M
