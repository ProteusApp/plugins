-- lib.page: reads one handbook page. It splits the front matter from the Markdown, splits the
-- Markdown into text, headings and code blocks, gives each heading an anchor, and resolves
-- the links between pages. Nothing here touches the app, so tests load it directly.

---@class Handbook.Block
---@field kind 'text'|'heading'|'code'
---@field text string Markdown for text, the heading's text, or the code.
---@field level? integer A heading's level, 1 to 6.
---@field anchor? string A heading's anchor.
---@field lang? string A code block's language, or `''`.

---@class Handbook.Heading
---@field level integer
---@field text string
---@field anchor string

---@class Handbook.Doc
---@field front table<string, string>
---@field title? string The front matter's title, else the first `# ` heading.
---@field blocks Handbook.Block[]
---@field headings Handbook.Heading[]

---@class Handbook.Ref
---@field url? string A web address, for a link that leaves the Handbook.
---@field source? string The plugin id, `proteus` or `types`.
---@field name? string The page's name within its source.
---@field anchor? string A heading's anchor, or nil for the top of the page.

local M = {}

---A heading's anchor: its text in lower case, spaces as `-`, and only letters, digits, `-`,
---`_` and `.` kept.
---@param text string
---@return string
function M.slug (text)
  local s = text:lower ():gsub ('[^%w%s%-_.]', '')
  s = s:gsub ('^%s+', ''):gsub ('%s+$', ''):gsub ('%s+', '-')
  return s
end

---Splits `---` front matter from the rest of a page. A line that is not `key: value` ends
---nothing and is skipped.
---@param text string
---@return table<string, string> front
---@return string body
function M.split_front (text)
  text = text:gsub ('\r\n', '\n')
  if text:sub (1, 4) ~= '---\n' then
    return {}, text
  end
  local close = text:find ('\n%-%-%-\n', 4)
  if not close then
    local last = text:find ('\n%-%-%-$', 4)
    if not last then
      return {}, text
    end
    close = last
  end
  local front = {} ---@type table<string, string>
  for line in text:sub (5, close):gmatch ('[^\n]+') do
    local key, value = line:match ('^([%w_]+):%s*(.-)%s*$')
    if key then
      front[key] = value
    end
  end
  return front, text:sub (close + 5)
end

---@param line string
---@return string? mark
---@return string? info
---@return integer indent
local function fence_open (line)
  local indent, mark, info = line:match ('^( *)(```+)%s*([^`]*)$')
  if not mark then
    indent, mark, info = line:match ('^( *)(~~~+)%s*(.*)$')
  end
  if not mark or #indent > 3 then
    return nil, nil, 0
  end
  return mark, info, #indent
end

---Reads a page's Markdown into blocks.
---@param text string
---@return Handbook.Doc
function M.parse (text)
  local front, body = M.split_front (text)
  local blocks = {} ---@type Handbook.Block[]
  local headings = {} ---@type Handbook.Heading[]
  local used = {} ---@type table<string, true>
  local lines = {} ---@type string[]
  local title = front.title ~= '' and front.title or nil

  local function flush ()
    local chunk = table.concat (lines, '\n')
    lines = {}
    if chunk:find ('%S') then
      blocks[#blocks + 1] = { kind = 'text', text = chunk }
    end
  end

  local fence, lang, indent, code = nil, '', 0, {} ---@type string?, string, integer, string[]
  for line in (body .. '\n'):gmatch ('([^\n]*)\n') do
    if fence then
      local close = line:match ('^ *([`~]+)%s*$')
      if
        close
        and close:sub (1, 1) == fence:sub (1, 1)
        and #close >= #fence
      then
        blocks[#blocks + 1] =
          { kind = 'code', text = table.concat (code, '\n'), lang = lang }
        fence, code = nil, {}
      else
        -- A fence inside a list is indented, and so are its lines.
        local strip = (line:match ('^ *') --[[@as string]]):sub (1, indent)
        code[#code + 1] = line:sub (#strip + 1)
      end
    else
      local mark, info, spaces = fence_open (line)
      local hashes, heading = line:match ('^ ? ? ?(#+)%s+(.-)%s*$') ---@type string?, string?
      if mark then
        flush ()
        fence, indent, code = mark, spaces, {}
        lang = (((info or ''):match ('^(%S*)') or '') --[[@as string]]):lower ()
      elseif hashes and #hashes <= 6 then
        flush ()
        heading = (heading --[[@as string]]):gsub ('%s+#+$', '')
        local base = M.slug (heading)
        local anchor, n = base, 1
        while used[anchor] do
          n = n + 1
          anchor = base .. '-' .. n
        end
        used[anchor] = true
        blocks[#blocks + 1] =
          { kind = 'heading', text = heading, level = #hashes, anchor = anchor }
        headings[#headings + 1] =
          { level = #hashes, text = heading, anchor = anchor }
        if not title and #hashes == 1 then
          title = heading
        end
      else
        lines[#lines + 1] = line
      end
    end
  end
  if fence then
    -- A block that never closes runs to the end of the page, as Markdown has it.
    blocks[#blocks + 1] =
      { kind = 'code', text = table.concat (code, '\n'), lang = lang }
  end
  flush ()
  return { front = front, title = title, blocks = blocks, headings = headings }
end

---Heading text as plain words: no backticks, stars or link targets.
---@param text string
---@return string
function M.plain (text)
  local s = text:gsub ('!?%[([^%]]*)%]%([^)]*%)', '%1')
  s = s:gsub ('[`*_]', ''):gsub ('<[^>]+>', '')
  return s
end

---Resolves a link's target, written on the page `from_source/from_name`.
---@param target string
---@param from_source string
---@param from_name string
---@return Handbook.Ref
function M.resolve (target, from_source, from_name)
  if target:match ('^%a[%w+.-]*:') then
    return { url = target }
  end
  local path, anchor = target:match ('^([^#]*)#?(.*)$') ---@type string, string
  path = path:gsub ('^%./', ''):gsub ('%.md$', '')
  local ref = { source = from_source, name = from_name } ---@type Handbook.Ref
  if path:find ('/') then
    ref.source, ref.name = path:match ('^([^/]+)/(.+)$')
  elseif path ~= '' then
    ref.name = path
  end
  if anchor ~= '' then
    ref.anchor = anchor
  end
  return ref
end

---The id of the page a reference names, such as `core.commands/commands`.
---@param ref Handbook.Ref
---@return string
function M.id_of (ref)
  return (ref.source or '') .. '/' .. (ref.name or '')
end

---Splits `core.commands/commands#register` into a page id and an anchor.
---@param text string
---@return string id
---@return string? anchor
function M.split_id (text)
  local id, anchor = text:match ('^([^#]*)#?(.*)$')
  return id, anchor ~= '' and anchor or nil
end

---Calls `fn` on the target of every Markdown link and image in `text`, outside code spans,
---and puts back what it returns.
---@param text string
---@param fn fun(target: string): string
---@return string
function M.map_links (text, fn)
  local out = {} ---@type string[]
  local i, n = 1, #text
  while i <= n do
    local c = text:sub (i, i)
    if c == '`' then
      local ticks = text:match ('^`+', i)
      local close = text:find (ticks, i + #ticks, true)
      -- A run of backticks without a match is just backticks.
      local stop = close and (close + #ticks - 1) or (i + #ticks - 1)
      out[#out + 1] = text:sub (i, stop)
      i = stop + 1
    elseif c == ']' and text:sub (i + 1, i + 1) == '(' then
      local start = i + 2
      local lead = text:match ('^%s*', start)
      start = start + #lead
      local target, rest ---@type string?, integer?
      if text:sub (start, start) == '<' then
        local close = text:find ('>', start, true)
        if close then
          target, rest = text:sub (start + 1, close - 1), close + 1
        end
      else
        local t = text:match ('^[^%s)]+', start)
        if t then
          target, rest = t, start + #t
        end
      end
      if target and rest then
        out[#out + 1] = '](' .. lead .. fn (target)
        i = rest
      else
        out[#out + 1] = c
        i = i + 1
      end
    else
      local stop = text:find ('[`%]]', i + 1) or (n + 1)
      out[#out + 1] = text:sub (i, stop - 1)
      i = stop
    end
  end
  return table.concat (out)
end

return M
