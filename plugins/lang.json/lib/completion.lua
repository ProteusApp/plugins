-- completion: turns the server's completion items into text the editor can insert. The server
-- writes each item as a snippet, such as `"name": "$1"`, and names the part of the line it
-- replaces, which starts at the opening quote and may end after the cursor. The editor
-- inserts plain text over what is typed before the cursor. So the item loses its `$1` marks,
-- and the text it would put back before the cursor or after it comes off.
-- Nothing here calls the app, so the tests reach it.

---@class LangJson.CompletionModule
local M = {}

---One line of a text, counted from 0, without its line break.
---@param text string
---@param row integer
---@return string
function M.line (text, row)
  local n = 0
  for line in (text .. '\n'):gmatch ('([^\n]*)\n') do
    if n == row then
      return (line:gsub ('\r$', ''))
    end
    n = n + 1
  end
  return ''
end

---How many bytes of a line hold its first `col` characters. The editor and the server count
---a line's characters as UTF-16 does, so a character beyond the first 65536 counts as two.
---@param line string
---@param col integer
---@return integer
function M.offset (line, col)
  local i, units, n = 1, 0, #line
  while i <= n and units < col do
    local b = line:byte (i)
    local size = b >= 0xF0 and 4 or b >= 0xE0 and 3 or b >= 0xC0 and 2 or 1
    units = units + (size == 4 and 2 or 1)
    i = i + size
  end
  return i - 1
end

---The part of a line between two columns.
---@param line string
---@param from integer
---@param to integer
---@return string
function M.slice (line, from, to)
  return line:sub (M.offset (line, from) + 1, M.offset (line, to))
end

---The column where the word before the cursor starts, the way the editor finds it: letters,
---digits and `_`.
---@param line string
---@param col integer
---@return integer
function M.word_start (line, col)
  local stop = M.offset (line, col)
  local i = stop
  while i > 0 and line:sub (i, i):match ('[%w_]') do
    i = i - 1
  end
  return col - (stop - i)
end

---Snippet text as plain text. `$1` and `$0` go, `${1:text}` leaves its text, `${1|a,b|}`
---leaves its first choice, and `\$` is a plain `$`.
---@param s string
---@param i integer Where to start.
---@param inner boolean True inside `${...}`, where `}` ends the text.
---@return string text
---@return integer next Where the text after it starts.
local function parse (s, i, inner)
  local out = {} ---@type string[]
  local n = #s
  while i <= n do
    local c = s:sub (i, i)
    local after = s:sub (i + 1, i + 1)
    if c == '\\' and after:match ('[%$}\\,|]') then
      out[#out + 1] = after
      i = i + 2
    elseif inner and c == '}' then
      return table.concat (out), i + 1
    elseif c == '$' and after:match ('%d') then
      local _, stop = s:find ('^%d+', i + 1)
      i = stop + 1
    elseif c == '$' and after == '{' and s:find ('^%d', i + 2) then
      local _, stop = s:find ('^%d+', i + 2)
      local mark = s:sub (stop + 1, stop + 1)
      if mark == ':' then
        local text, next_i = parse (s, stop + 2, true)
        out[#out + 1] = text
        i = next_i
      elseif mark == '|' then
        local close = s:find ('|}', stop + 2, true)
        local choices = close and s:sub (stop + 2, close - 1) or ''
        out[#out + 1] = choices:match ('^[^,]*')
        i = close and close + 2 or n + 1
      elseif mark == '}' then
        i = stop + 2
      else
        out[#out + 1] = c
        i = i + 1
      end
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat (out), i
end

---Snippet text as plain text.
---@param snippet string
---@return string
function M.plain (snippet)
  return (parse (snippet, 1, false))
end

---What the editor inserts for a server's item, when it replaces the line from column `from`
---to the cursor.
---@param raw table The server's completion item.
---@param line string The cursor's line.
---@param pos Proteus.CodePosition The cursor.
---@param from integer
---@return string?
function M.insert (raw, line, pos, from)
  local edit = type (raw.textEdit) == 'table' and raw.textEdit or nil
  local text = edit and edit.newText or raw.insertText or raw.label
  if type (text) ~= 'string' then
    return nil
  end
  if raw.insertTextFormat == 2 then
    text = M.plain (text)
  end
  local range = edit and (edit.range or edit.replace)
  if
    type (range) ~= 'table'
    or range.start.line ~= pos.line
    or range['end'].line ~= pos.line
  then
    return text
  end
  local start, stop = range.start.character, range['end'].character
  if start < from then
    -- Such as the opening quote: typed already, and left in place.
    local typed = M.slice (line, start, from)
    if text:sub (1, #typed) == typed then
      text = text:sub (#typed + 1)
    end
  elseif start > from then
    text = M.slice (line, from, start) .. text
  end
  if stop > pos.character then
    -- Such as the closing quote after the cursor, which stays where it is.
    local tail = M.slice (line, pos.character, stop)
    if text:sub (-#tail) == tail then
      text = text:sub (1, -#tail - 1)
    else
      local cut = text:find (tail, 1, true)
      if cut then
        text = text:sub (1, cut - 1)
      end
    end
  end
  return text
end

return M
