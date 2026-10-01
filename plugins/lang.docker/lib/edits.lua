-- edits: applies the changes the language server sends back for Format Document. The server
-- counts columns in UTF-16 units, as the protocol does, so a column is turned into a byte
-- position by walking the line's characters. Nothing here calls the host, so the tests reach
-- it.

---One change to a file's text.
---@class LangDocker.TextEdit
---@field range Lsp.Range
---@field newText string

---@class LangDocker.EditsModule
local M = {}

---The byte position, from 1, of a line and a column counted from 0. A line past the end
---gives the end of the text, and a column past the end of its line gives the line's end.
---@param text string
---@param line integer
---@param character integer UTF-16 units.
---@return integer
function M.offset (text, line, character)
  local pos = 1
  for _ = 1, line do
    local nl = text:find ('\n', pos, true)
    if not nl then
      return #text + 1
    end
    pos = nl + 1
  end
  local units = 0
  while units < character and pos <= #text do
    local b = text:byte (pos)
    if b == 10 then
      break
    end
    -- A character of four bytes lies outside the first 65536, so UTF-16 counts it twice.
    local size = b < 0x80 and 1 or b < 0xE0 and 2 or b < 0xF0 and 3 or 4
    units = units + (size == 4 and 2 or 1)
    pos = pos + size
  end
  return pos
end

---The text with every edit made. Each edit's range is read against the text as it was, as
---the protocol asks. Edits that start at the same place go in the order the list gives.
---@param text string
---@param list LangDocker.TextEdit[]
---@return string
function M.apply (text, list)
  local spans = {} ---@type { first: integer, last: integer, text: string, index: integer }[]
  for i, edit in ipairs (list) do
    local s, e = edit.range.start, edit.range['end']
    spans[#spans + 1] = {
      first = M.offset (text, s.line, s.character),
      last = M.offset (text, e.line, e.character),
      text = tostring (edit.newText or ''),
      index = i,
    }
  end
  -- From the end of the text back, so each edit leaves the places of the ones before it alone.
  table.sort (spans, function (a, b)
    if a.first ~= b.first then
      return a.first > b.first
    end
    return a.index > b.index
  end)
  for _, span in ipairs (spans) do
    text = text:sub (1, span.first - 1) .. span.text .. text:sub (span.last)
  end
  return text
end

return M
