-- completion: turns the server's completion items into text the editor can insert.
--
-- The server writes most items as snippets, even though the client asks for plain text. A
-- property comes as `color: $0;` and a function as `var($1)`. The editor inserts plain text
-- and leaves the cursor at its end. So an item's text stops where the snippet would put the
-- cursor first: `color: ` and `var(`. The cursor lands where the value goes.
--
-- The server also names the part of the line an item replaces, such as all of
-- `background-im`. The editor's own idea of the word stops at a `-`, so the plugin tells the
-- editor where the server's part starts.
--
-- Nothing here calls the app, so the tests reach it.

-- The protocol's number for an item whose text is a snippet.
local SNIPPET = 2

---@class LangCss.CompletionModule
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

---The column where the word before the cursor starts, counting `-`, `$` and `@` as part of
---it, the way CSS, SCSS and Less names do.
---@param line string
---@param col integer
---@return integer
function M.word_start (line, col)
  local stop = M.offset (line, col)
  local i = stop
  while i > 0 and line:sub (i, i):match ('[%w_%-%$@]') do
    i = i - 1
  end
  return col - (stop - i)
end

---Snippet text as plain text, up to the first place the snippet puts the cursor. `$1`, `$0`,
---`${1}`, `${1:text}` and `${1|a,b|}` each mark such a place. `\$`, `\}` and `\\` are the
---characters themselves. A `$` before a name, such as a Sass variable, stays as it is.
---@param snippet string
---@return string
function M.plain (snippet)
  local out = {} ---@type string[]
  local i, n = 1, #snippet
  while i <= n do
    local c = snippet:sub (i, i)
    local after = snippet:sub (i + 1, i + 1)
    if c == '\\' and after:match ('[%$}\\]') then
      out[#out + 1] = after
      i = i + 2
    elseif
      c == '$' and (after:match ('%d') or snippet:find ('^{%d', i + 1))
    then
      break
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat (out)
end

---The text an item inserts, before it is fitted to the line.
---@param raw table The server's completion item.
---@return string?
function M.text (raw)
  local edit = type (raw.textEdit) == 'table' and raw.textEdit or nil
  local text = edit and edit.newText or raw.insertText or raw.label
  if type (text) ~= 'string' then
    return nil
  end
  if raw.insertTextFormat == SNIPPET then
    text = M.plain (text)
  end
  return text
end

---Where an item's replaced part starts on the cursor's line, or nil when it names none there.
---@param raw table
---@param pos Proteus.CodePosition
---@return integer?
function M.start (raw, pos)
  local edit = type (raw.textEdit) == 'table' and raw.textEdit or nil
  local range = edit and (edit.range or edit.replace)
  if
    type (range) ~= 'table'
    or range.start.line ~= pos.line
    or range.start.character > pos.character
  then
    return nil
  end
  return range.start.character
end

---The column where the editor's replaced text starts: the earliest start the server names, or
---else the word before the cursor.
---@param raws table[] The server's completion items.
---@param line string The cursor's line.
---@param pos Proteus.CodePosition
---@return integer
function M.from (raws, line, pos)
  local from = nil ---@type integer?
  for _, raw in ipairs (raws) do
    local start = M.start (raw, pos)
    if start and (not from or start < from) then
      from = start
    end
  end
  return from or M.word_start (line, pos.character)
end

---What the editor inserts for an item, when it replaces the line from column `from` to the
---cursor. An item whose own part starts later gets the text between the two in front.
---@param raw table The server's completion item.
---@param line string The cursor's line.
---@param pos Proteus.CodePosition
---@param from integer
---@return string?
function M.insert (raw, line, pos, from)
  local text = M.text (raw)
  if not text then
    return nil
  end
  local start = M.start (raw, pos) or M.word_start (line, pos.character)
  if start > from then
    text = M.slice (line, from, start) .. text
  elseif start < from then
    -- Typed already, such as a `$` before the word, and left in place.
    local typed = M.slice (line, start, from)
    if text:sub (1, #typed) == typed then
      text = text:sub (#typed + 1)
    end
  end
  return text
end

return M
