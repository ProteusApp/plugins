-- completion: where the server's completion items start, and the text each one inserts. The
-- server replaces from the `--` of a flag, or the `$` of a variable, such as `--chown=` over
-- `--ch`. The editor finds the word before the cursor by letters, digits and `_`, so on its
-- own it would keep the `--` and insert `----chown=`. So the editor learns the column where
-- the server's text starts, and an item that starts elsewhere fits around it.
-- Nothing here calls the app, so the tests reach it.

---@class LangDocker.CompletionModule
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

---The range an item replaces, when it lies on the cursor's line and starts before it.
---@param raw table The server's completion item.
---@param pos Proteus.CodePosition
---@return Lsp.Range?
local function range_of (raw, pos)
  local edit = type (raw.textEdit) == 'table' and raw.textEdit or nil
  local range = edit and (edit.range or edit.replace)
  if
    type (range) ~= 'table'
    or range.start.line ~= pos.line
    or range['end'].line ~= pos.line
    or range.start.character > pos.character
  then
    return nil
  end
  return range
end

---The column where the replaced text starts: the first item's own start, or else the word
---before the cursor.
---@param raw_items table[]
---@param line string
---@param pos Proteus.CodePosition
---@return integer
function M.from (raw_items, line, pos)
  local range = raw_items[1] and range_of (raw_items[1], pos)
  if range then
    return range.start.character
  end
  return M.word_start (line, pos.character)
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
  local range = range_of (raw, pos)
  if not range then
    return text
  end
  local start, stop = range.start.character, range['end'].character
  if start < from then
    -- Typed already, and left in place.
    local typed = M.slice (line, start, from)
    if text:sub (1, #typed) == typed then
      text = text:sub (#typed + 1)
    end
  elseif start > from then
    text = M.slice (line, from, start) .. text
  end
  if stop > pos.character then
    -- Text after the cursor that the item would replace stays where it is.
    local tail = M.slice (line, pos.character, stop)
    if text:sub (-#tail) == tail then
      text = text:sub (1, -#tail - 1)
    end
  end
  return text
end

return M
