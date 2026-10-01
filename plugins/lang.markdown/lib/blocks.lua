-- blocks: cuts a Markdown file into parts, one for each heading and the text under it, and
-- keeps the line each part starts on. The preview draws each part on its own, so a link to a
-- heading finds its place, and the line on top of the editor finds the matching place in the
-- preview. It needs no `app`, so the tests load it as it is.

---One heading and the text under it, up to the next heading. The text before the first
---heading is a part with no heading.
---@class LangMarkdown.Part
---@field line integer The line it starts on, from 1.
---@field text string Its Markdown.
---@field level? integer The heading's level, from 1 to 6.
---@field title? string The heading's text, as written.
---@field anchor? string The name a `#link` uses for the heading, as GitHub makes it.

---@class LangMarkdown.Split
---@field parts LangMarkdown.Part[]
---@field refs string[] Every reference definition, such as `[home]: ./README.md`.
---@field lines integer How many lines the file has.

---@class LangMarkdown.BlocksModule
local M = {}

---The heading's level and text, when the line is a heading that starts with `#`.
---@param line string
---@return integer? level
---@return string? title
local function atx (line)
  local hashes, rest = line:match ('^ ? ? ?(#+)(.*)$')
  if not hashes or #hashes > 6 or not (rest == '' or rest:match ('^[ \t]')) then
    return nil, nil
  end
  local title = rest:gsub ('^%s+', ''):gsub ('%s+$', '')
  -- A closing run of `#` goes, when a space comes before it, and so does a heading of only `#`.
  title = title:gsub ('^#+$', ''):gsub ('%s+#+$', '')
  return #hashes, title
end

---The opening of a fenced code block: its character and how many of them.
---@param line string
---@return { char: string, len: integer }?
local function fence_open (line)
  local ticks = line:match ('^ ? ? ?(```+)')
  if
    ticks
    and not line:sub (#line:match ('^ *') + #ticks + 1):find ('`', 1, true)
  then
    return { char = '`', len = #ticks }
  end
  local tildes = line:match ('^ ? ? ?(~~~+)')
  if tildes then
    return { char = '~', len = #tildes }
  end
  return nil
end

---True when the line closes the fenced code block.
---@param line string
---@param fence { char: string, len: integer }
---@return boolean
local function fence_closes (line, fence)
  local run = line:match ('^ ? ? ?([`~]+)%s*$')
  if not run or #run < fence.len then
    return false
  end
  return run == string.rep (fence.char, #run)
end

---True when the line starts something other than plain text, such as a list item or a quote,
---so a line of `-` or `=` under it is no heading.
---@param line string
---@return boolean
local function starts_block (line)
  return line:match ('^    ') ~= nil
    or line:match ('^ *\t') ~= nil
    or line:match ('^%s*[-*+][ \t]') ~= nil
    or line:match ('^%s*[-*+]$') ~= nil
    or line:match ('^%s*%d+[.)][ \t]') ~= nil
    or line:match ('^%s*>') ~= nil
    or line:match ('^%s*<') ~= nil
    or line:find ('|', 1, true) ~= nil
    or line:match ('^ ? ? ?%[[^%]]+%]:') ~= nil
end

---The name GitHub gives a heading for links: lower case, with the punctuation gone and a
---dash for each space. Links and images count by their text.
---@param title string
---@return string
function M.slug (title)
  local s = title
    :gsub ('!%[([^%]]*)%]%b()', '%1')
    :gsub ('%[([^%]]*)%]%b()', '%1')
    :gsub ('%[([^%]]*)%]%[[^%]]*%]', '%1')
    :gsub ('<[^>]*>', '')
    :lower ()
  -- Underscores around a word make it italic, and only those go.
  s = s:gsub ('^_+', '')
    :gsub ('_+$', '')
    :gsub ('(%s)_+', '%1')
    :gsub ('_+(%s)', '%1')
  s = s:gsub ('[^%w%s_%-\128-\255]', ''):gsub ('%s', '-')
  return s
end

---Cuts a file into parts at its headings. A heading inside a fenced code block is not one.
---Front matter between `---` lines at the top is left out. `each_line` may change each line
---outside code blocks, such as to mark the boxes of a task list.
---@param text string
---@param each_line? fun(line: string): string
---@return LangMarkdown.Split
function M.split (text, each_line)
  local lines = {} ---@type string[]
  for line in (text .. '\n'):gmatch ('([^\n]*)\n') do
    lines[#lines + 1] = (line:gsub ('\r$', ''))
  end
  local total = #lines

  local first = 1
  if lines[1] == '---' then
    for i = 2, total do
      if lines[i] == '---' or lines[i] == '...' then
        first = i + 1
        break
      end
    end
  end

  local heads = {} ---@type { line: integer, level: integer, title: string }[]
  local code = {} ---@type table<integer, boolean>
  local refs = {} ---@type string[]
  local fence = nil ---@type { char: string, len: integer }?
  -- The paragraph the lines above belong to, which a line of `=` or `-` makes a heading.
  local para = nil ---@type { start: integer, plain: boolean }?

  for i = first, total do
    local line = lines[i]
    local level, title = atx (line)
    if fence then
      code[i] = true
      if fence_closes (line, fence) then
        fence = nil
      end
    elseif fence_open (line) then
      fence = fence_open (line)
      code[i] = true
      para = nil
    elseif level then
      heads[#heads + 1] = { line = i, level = level, title = title or '' }
      para = nil
    elseif line:match ('^ ? ? ?=+%s*$') and para and para.plain then
      local words = table.concat (lines, ' ', para.start, i - 1)
      heads[#heads + 1] = { line = para.start, level = 1, title = words }
      para = nil
    elseif line:match ('^ ? ? ?%-+%s*$') then
      if para and para.plain then
        local words = table.concat (lines, ' ', para.start, i - 1)
        heads[#heads + 1] = { line = para.start, level = 2, title = words }
      end
      para = nil
    elseif line:match ('^%s*$') then
      para = nil
    else
      if line:match ('^ ? ? ?%[[^%]]+%]:') then
        refs[#refs + 1] = line
      end
      local plain = not starts_block (line)
      if not para then
        para = { start = i, plain = plain }
      elseif not plain then
        para.plain = false
      end
    end
  end

  ---@param from integer
  ---@param to integer
  ---@return string
  local function text_of (from, to)
    local out = {} ---@type string[]
    for i = from, to do
      local line = lines[i]
      if each_line and not code[i] then
        line = each_line (line)
      end
      out[#out + 1] = line
    end
    return table.concat (out, '\n')
  end

  local parts = {} ---@type LangMarkdown.Part[]
  local top = heads[1] and heads[1].line or (total + 1)
  if top > first then
    local before = text_of (first, top - 1)
    if before:find ('%S') then
      parts[1] = { line = first, text = before }
    end
  end

  local seen = {} ---@type table<string, integer>
  for n, head in ipairs (heads) do
    local stop = heads[n + 1] and (heads[n + 1].line - 1) or total
    local title = head.title:gsub ('^%s+', ''):gsub ('%s+$', '')
    local anchor = M.slug (title)
    local count = seen[anchor]
    seen[anchor] = (count or 0) + 1
    if count then
      anchor = anchor .. '-' .. count
    end
    parts[#parts + 1] = {
      line = head.line,
      text = text_of (head.line, stop),
      level = head.level,
      title = title,
      anchor = anchor,
    }
  end

  return { parts = parts, refs = refs, lines = total }
end

---The part a line falls in, and how far down that part it sits, from 0 at its first line to
---nearly 1 at its last. Nil when there are no parts.
---@param parts { line: integer }[] Parts in order, each with the line it starts on.
---@param line integer
---@param total integer How many lines the file has.
---@return integer? index
---@return number fraction
function M.locate (parts, line, total)
  if #parts == 0 then
    return nil, 0
  end
  local index = 1
  for i, part in ipairs (parts) do
    if part.line <= line then
      index = i
    else
      break
    end
  end
  local part = parts[index]
  if line < part.line then
    return index, 0
  end
  local next_line = parts[index + 1] and parts[index + 1].line or (total + 1)
  local span = math.max (1, next_line - part.line)
  return index, math.min (1, (line - part.line) / span)
end

return M
