-- items: turns the Tailwind server's completion items into the editor's.
--
-- The server sends every class it knows each time, more than twenty thousand in Tailwind 4,
-- whatever was typed. So the plugin keeps only the classes that fit the typed text before
-- the editor sees them, best first.
--
-- An item names the part of the line it replaces, which starts at the class, such as all of
-- `bg-re`. The editor's own idea of the word stops at a `-`, so the plugin tells the editor
-- where the class starts. A few items are snippets, such as `not-[${1}]:${0}`. The editor
-- inserts plain text, so their text stops where the snippet would put the cursor first.
--
-- The editor cannot ask this plugin for an item's documentation later. So the plugin asks
-- the server for the CSS of the first few items, and puts it in their documentation.
--
-- Nothing here calls the app, so the tests reach it.

-- The protocol's number for an item whose text is a snippet.
local SNIPPET = 2
-- The protocol's numbers for a color, and for a variant such as `hover:`.
local COLOR, MODULE = 16, 9

-- Completion kinds, by their number in the protocol.
local KINDS = {
  'text',
  'method',
  'function',
  'constructor',
  'field',
  'variable',
  'class',
  'interface',
  'module',
  'property',
  'unit',
  'value',
  'enum',
  'keyword',
  'snippet',
  'color',
  'file',
  'reference',
  'folder',
  'enum',
  'constant',
  'class',
  'event',
  'operator',
  'type',
}

---@class LangTailwind.ItemsModule
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

---Snippet text as plain text, up to the first place the snippet puts the cursor. `$1`, `$0`,
---`${1}`, `${1:text}` and `${1|a,b|}` each mark such a place. `\$`, `\}` and `\\` are the
---characters themselves.
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

---The text an item inserts, as plain text.
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
    or type (range.start) ~= 'table'
    or range.start.line ~= pos.line
    or range.start.character > pos.character
  then
    return nil
  end
  return range.start.character
end

---The column where the replaced text starts: the earliest start the server names, or else
---the cursor.
---@param raws table[] The server's completion items.
---@param pos Proteus.CodePosition
---@return integer
function M.from (raws, pos)
  local from = nil ---@type integer?
  for _, raw in ipairs (raws) do
    local start = M.start (raw, pos)
    if start and (not from or start < from) then
      from = start
    end
  end
  return from or pos.character
end

---What the editor inserts for an item, when it replaces the line from column `from` to the
---cursor. An item whose own part starts later gets the text between the two in front.
---@param raw table
---@param line string The cursor's line.
---@param pos Proteus.CodePosition
---@param from integer
---@return string?
function M.insert (raw, line, pos, from)
  local text = M.text (raw)
  if not text then
    return nil
  end
  local start = M.start (raw, pos) or from
  if start > from then
    text = M.slice (line, from, start) .. text
  end
  return text
end

---True when every character typed shows up in the label, in order, ignoring case. The
---editor then picks and orders the list by how well each one fits.
---@param label string
---@param typed string
---@return boolean
function M.fits (label, typed)
  local at = 1
  label = label:lower ()
  for i = 1, #typed do
    local found = label:find (typed:sub (i, i):lower (), at, true)
    if not found then
      return false
    end
    at = found + 1
  end
  return true
end

---The items that fit the typed text: those that start with it first, then the rest, each in
---the server's own order.
---@param raws table[]
---@param typed string
---@return table[]
function M.pick (raws, typed)
  local starts, others = {}, {} ---@type table[], table[]
  local lower = typed:lower ()
  for _, raw in ipairs (raws) do
    local label = type (raw) == 'table' and raw.label
    if type (label) == 'string' then
      if label:lower ():sub (1, #lower) == lower then
        starts[#starts + 1] = raw
      elseif M.fits (label, typed) then
        others[#others + 1] = raw
      end
    end
  end
  ---@param a table
  ---@param b table
  ---@return boolean
  local function before (a, b)
    local x, y =
      tostring (a.sortText or a.label), tostring (b.sortText or b.label)
    if x ~= y then
      return x < y
    end
    return tostring (a.label) < tostring (b.label)
  end
  table.sort (starts, before)
  table.sort (others, before)
  for _, raw in ipairs (others) do
    starts[#starts + 1] = raw
  end
  return starts
end

---True for an item whose CSS comes only when the server is asked about it. A variant, such
---as `hover:`, already says what it does.
---@param raw table
---@return boolean
function M.wants_css (raw)
  return raw.kind ~= MODULE and type (raw.documentation) ~= 'table'
end

---A class name as a CSS selector, such as `.w-1\/2` for `w-1/2`.
---@param label string
---@return string
function M.selector (label)
  return '.' .. (label:gsub ('[^%w%-_]', '\\%0'))
end

---The CSS for a class, from the server's one-line list of declarations, such as
---`overflow: hidden; white-space: nowrap;`.
---@param label string
---@param declarations string
---@return string
function M.rule (label, declarations)
  local lines = { M.selector (label) .. ' {' }
  for part in declarations:gmatch ('[^;]+') do
    local text = part:match ('^%s*(.-)%s*$')
    if text ~= '' then
      lines[#lines + 1] = '  ' .. text .. ';'
    end
  end
  lines[#lines + 1] = '}'
  return table.concat (lines, '\n')
end

---An item's documentation as Markdown, or nil when it has none yet.
---@param raw table
---@return string?
function M.documentation (raw)
  local doc = raw.documentation
  if
    type (doc) == 'table'
    and type (doc.value) == 'string'
    and doc.value ~= ''
  then
    return doc.value
  end
  local detail = type (raw.detail) == 'string' and raw.detail or nil
  if not detail or detail == '' then
    return nil
  end
  if raw.kind == MODULE then
    return '```css\n' .. detail .. '\n```'
  end
  return '```css\n' .. M.rule (tostring (raw.label), detail) .. '\n```'
end

---The editor's item for one of the server's.
---@param raw table
---@param line string The cursor's line.
---@param pos Proteus.CodePosition
---@param from integer
---@return Proteus.CompletionItem
function M.item (raw, line, pos, from)
  local color = raw.kind == COLOR and type (raw.documentation) == 'string'
  return {
    label = tostring (raw.label),
    kind = KINDS[raw.kind or 0],
    -- A color shows its value beside the name, such as `#fb2c36`.
    detail = color and raw.documentation or nil,
    documentation = M.documentation (raw),
    insert = M.insert (raw, line, pos, from),
  }
end

return M
