-- edits: applies the changes Ruff sends back for Organize Imports and Fix All. The server
-- counts columns in UTF-16 units, as the protocol does, so a column is turned into a byte
-- position by walking the line's characters. Nothing here calls the host, so the tests reach
-- it.

---One change to a file's text.
---@class LangPython.TextEdit
---@field range Lsp.Range
---@field newText string

---The changes for one file.
---@class LangPython.FileEdits
---@field uri string
---@field edits LangPython.TextEdit[]

---@class LangPython.EditsModule
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
---@param list LangPython.TextEdit[]
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

---The text edits in a workspace edit, file by file. A server sends them either as
---`documentChanges` or as `changes`. Creating, renaming and deleting files are left out.
---@param edit any
---@return LangPython.FileEdits[]
function M.files (edit)
  local out = {} ---@type LangPython.FileEdits[]
  if type (edit) ~= 'table' then
    return out
  end
  if type (edit.documentChanges) == 'table' then
    for _, change in ipairs (edit.documentChanges) do
      local doc = type (change) == 'table' and change.textDocument
      if type (doc) == 'table' and type (change.edits) == 'table' then
        out[#out + 1] = { uri = tostring (doc.uri), edits = change.edits }
      end
    end
    return out
  end
  if type (edit.changes) == 'table' then
    for uri, list in pairs (edit.changes) do
      out[#out + 1] = { uri = tostring (uri), edits = list }
    end
    table.sort (out, function (a, b)
      return a.uri < b.uri
    end)
  end
  return out
end

return M
