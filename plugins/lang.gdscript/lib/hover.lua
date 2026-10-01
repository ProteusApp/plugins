-- hover: tidies the help Godot shows for a name. Godot turns its documentation into Markdown,
-- but leaves some of its own markup behind: `br` where a line should break, `codeblocks`
-- and `gdscript` around examples, and `#` at the start of lines from `##` comments, which
-- Markdown reads as headings. VS Code's Godot extension mends the same marks. Nothing here
-- calls the host, so the tests reach it.

---@class LangGdscript.HoverModule
local M = {}

-- Each of Godot's marks, and the Markdown it stands for.
local MARKS = {
  { '`br`', '\n\n' },
  { '`codeblocks`', '' },
  { '`/codeblocks`', '' },
  { '`gdscript`', '\nGDScript:\n```gdscript' },
  { '`/gdscript`', '```' },
  { '`csharp`', '\nC#:\n```csharp' },
  { '`/csharp`', '```' },
}

---Replaces every copy of a piece of text, with no pattern characters.
---@param text string
---@param from string
---@param to string
---@return string
local function replace (text, from, to)
  local parts = {} ---@type string[]
  local start = 1
  while true do
    local first, last = text:find (from, start, true)
    if not first then
      break
    end
    parts[#parts + 1] = text:sub (start, first - 1)
    parts[#parts + 1] = to
    start = last + 1
  end
  parts[#parts + 1] = text:sub (start)
  return table.concat (parts)
end

---Godot's help as Markdown the editor shows well, or nil when there is none.
---@param markdown string?
---@return string?
function M.clean (markdown)
  if type (markdown) ~= 'string' then
    return nil
  end
  local text = markdown
  for _, mark in ipairs (MARKS) do
    text = replace (text, mark[1], mark[2])
  end
  local lines = {} ---@type string[]
  local in_code = false
  for line in (text .. '\n'):gmatch ('([^\n]*)\n') do
    if line:match ('^%s*```') then
      in_code = not in_code
    elseif not in_code and #lines > 0 then
      -- A `#` inside an example is a comment, so only lines outside one lose it.
      line = line:gsub ('^#+%s*', '')
    end
    lines[#lines + 1] = line
  end
  text = table.concat (lines, '\n'):gsub ('\n+$', '')
  if not text:find ('%S') then
    return nil
  end
  return text
end

return M
