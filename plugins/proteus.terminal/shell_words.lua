-- shell_words: splits the `terminal.shell` setting into a program and its arguments, such as
-- `pwsh -NoLogo`. Quotes keep spaces in one word, as in `"C:\Program Files\Git\bin\bash.exe" -l`.
-- A backslash stays as it is, since Windows paths are full of them. A value with no quotes
-- that ends in `.exe` is one program, so an unquoted path with spaces keeps working.

---@class Terminal.ShellWords
local M = {}

---The program and its arguments. The program is '' for an empty value.
---@param text string
---@return string program
---@return string[] args
function M.split (text)
  local value = text:match ('^%s*(.-)%s*$') or ''
  if not value:find ('["\']') and value:lower ():find ('%.exe$') then
    return value, {}
  end
  local words = {} ---@type string[]
  local cur = {} ---@type string[]
  local has = false
  local quote = nil ---@type string?
  for i = 1, #value do
    local c = value:sub (i, i)
    if quote then
      if c == quote then
        quote = nil
      else
        cur[#cur + 1] = c
      end
    elseif c == '"' or c == "'" then
      quote = c
      has = true
    elseif c:find ('%s') then
      if has then
        words[#words + 1] = table.concat (cur)
      end
      cur, has = {}, false
    else
      cur[#cur + 1] = c
      has = true
    end
  end
  if has then
    words[#words + 1] = table.concat (cur)
  end
  local program = table.remove (words, 1) or ''
  return program, words
end

return M
