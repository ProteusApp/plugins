-- links: the links and images of a Markdown file, before and after the app turns it into HTML.
--
-- The app's safe renderer keeps only web links, so a link to another file or to a heading
-- would lose its address. Before rendering, every link and image points at a numbered
-- address under HOST instead, and the real one waits in a list. After rendering, each link
-- carries its real address for the click, and each image becomes a placeholder with its
-- text, since the preview cannot load a file by its path. It needs no `app`, so the tests
-- load it as it is.

---What a link points at.
---@class LangMarkdown.Target
---@field kind 'anchor'|'web'|'file'|'other'
---@field url? string For `web` and `other`.
---@field path? string For `file`: the path as written, without its `#heading`.
---@field anchor? string For `anchor`, and for `file` when it names a heading.

---@class LangMarkdown.LinksModule
local M = {}

-- The stand-in address. Nothing is ever fetched from it.
M.HOST = 'https://markdown.preview/'
local HOST_PATTERN = M.HOST:gsub ('%p', '%%%0') .. '(%d+)'

-- Words that stand for the boxes of a task list, since the safe renderer drops check boxes.
M.TASK_OPEN = 'MDPREVIEWTASKOPEN'
M.TASK_DONE = 'MDPREVIEWTASKDONE'

-- The kinds of picture a page may show from its own text.
local DATA_IMAGE = '^data:image/[%w.+-]+[;,]'

---Escapes text for HTML, in an attribute or between tags.
---@param s string
---@return string
function M.escape (s)
  return (
    s:gsub ('&', '&amp;')
      :gsub ('<', '&lt;')
      :gsub ('>', '&gt;')
      :gsub ('"', '&quot;')
  )
end

---Turns `%20` and the like back into the characters they stand for.
---@param s string
---@return string
local function decode (s)
  return (
    s:gsub ('%%(%x%x)', function (hex)
      return string.char (tonumber (hex, 16))
    end)
  )
end

---Marks the box at the start of a task list item, such as `- [ ] buy milk`, with a word the
---renderer leaves alone.
---@param line string
---@return string
function M.task_line (line)
  ---@param lead string
  ---@param mark string
  ---@param gap string
  ---@return string
  local function swap (lead, mark, gap)
    return lead .. (mark == ' ' and M.TASK_OPEN or M.TASK_DONE) .. gap
  end
  local out, n = line:gsub ('^([>%s]*[-*+][ \t]+)%[([ xX])%]([ \t])', swap)
  if n == 0 then
    out = line:gsub ('^([>%s]*%d+[.)][ \t]+)%[([ xX])%]([ \t])', swap)
  end
  return out
end

---Where a link's address ends, when it has no angle brackets: at a space, or at a `)` that
---closes no `(` inside the address.
---@param text string
---@param start integer
---@return integer last The address's last character.
local function address_end (text, start)
  local depth, i = 0, start
  while i <= #text do
    local c = text:sub (i, i)
    if c:match ('%s') then
      break
    elseif c == '\\' then
      i = i + 1
    elseif c == '(' then
      depth = depth + 1
    elseif c == ')' then
      if depth == 0 then
        break
      end
      depth = depth - 1
    end
    i = i + 1
  end
  return i - 1
end

---Points every link and image at a numbered address under HOST, reference definitions
---included. Code spans keep their text. Returns the new text and the real addresses, by
---number.
---@param text string
---@return string text
---@return string[] targets
function M.rewrite (text)
  local targets = {} ---@type string[]

  ---@param target string
  ---@return string
  local function keep (target)
    targets[#targets + 1] = target
    return M.HOST .. #targets
  end

  -- Reference definitions, such as `[home]: <./README.md> "Home"`.
  text = text:gsub ('[^\n]+', function (line)
    local lead, rest = line:match ('^( ? ? ?%[[^%]]+%]:[ \t]*)(.*)$')
    if not lead or rest == '' then
      return nil
    end
    local inside, after = rest:match ('^<([^>]*)>(.*)$')
    if inside then
      return lead .. keep (inside) .. after
    end
    local target = rest:match ('^%S+')
    return lead .. keep (target) .. rest:sub (#target + 1)
  end)

  local out = {} ---@type string[]
  local i, n = 1, #text
  while i <= n do
    local c = text:sub (i, i)
    if c == '`' then
      -- A code span, or a fenced block, runs to the next run of as many backticks.
      local ticks = text:match ('^`+', i)
      local close = text:find (ticks, i + #ticks, true)
      local stop = close and (close + #ticks - 1) or (i + #ticks - 1)
      out[#out + 1] = text:sub (i, stop)
      i = stop + 1
    elseif c == '\\' then
      out[#out + 1] = text:sub (i, i + 1)
      i = i + 2
    elseif c == ']' and text:sub (i + 1, i + 1) == '(' then
      local start = i + 2
      local lead = text:match ('^[ \t]*', start)
      start = start + #lead
      local target, rest ---@type string?, integer?
      if text:sub (start, start) == '<' then
        local close = text:find ('>', start, true)
        if close then
          target, rest = text:sub (start + 1, close - 1), close + 1
        end
      else
        local last = address_end (text, start)
        if last >= start then
          target, rest = text:sub (start, last), last + 1
        end
      end
      if target and rest and target ~= '' then
        out[#out + 1] = '](' .. lead .. keep (target)
        i = rest
      else
        out[#out + 1] = c
        i = i + 1
      end
    else
      local stop = text:find ('[`\\%]]', i + 1) or (n + 1)
      out[#out + 1] = text:sub (i, stop - 1)
      i = stop
    end
  end
  return table.concat (out), targets
end

---Puts the real addresses back into the HTML the renderer made. A link gets its address in
---`data-item` as `go:<address>`, for the click, and in its tooltip. An image becomes a
---placeholder with its text, unless it is a picture inside the file itself. Inside code,
---the text shows as it was written.
---@param html string
---@param targets string[]
---@return string
function M.finish (html, targets)
  ---@param n string
  ---@return string
  local function real (n)
    return targets[tonumber (n)] or ''
  end

  ---@param chunk string
  ---@return string
  local function as_written (chunk)
    return (
      chunk
        :gsub (HOST_PATTERN, function (n)
          return M.escape (real (n))
        end)
        :gsub (M.TASK_OPEN, '[ ]')
        :gsub (M.TASK_DONE, '[x]')
    )
  end

  html =
    html:gsub ('<pre.-</pre>', as_written):gsub ('<code.-</code>', as_written)

  html = html
    :gsub ('data%-item="link:' .. HOST_PATTERN .. '"', function (n)
      return 'data-item="go:' .. M.escape (real (n)) .. '"'
    end)
    :gsub ('title="' .. HOST_PATTERN .. '"', function (n)
      return 'title="' .. M.escape (real (n)) .. '"'
    end)

  html = html:gsub ('<img[^>]*>', function (tag)
    local src = tag:match ('%ssrc="([^"]*)"') or ''
    local alt = tag:match ('%salt="([^"]*)"') or ''
    local n = src:match ('^' .. HOST_PATTERN .. '$')
    local shown = n and M.escape (real (n)) or src
    if n and real (n):match (DATA_IMAGE) then
      return '<img class="md-img" src="' .. shown .. '" alt="' .. alt .. '">'
    end
    return '<span class="md-image" title="'
      .. shown
      .. '">'
      .. (alt ~= '' and alt or 'image')
      .. '</span>'
  end)

  -- A list item that starts with a box shows no bullet. The class marks it, since a
  -- restricted plugin's style sheet cannot ask what an element holds with :has().
  html = html
    :gsub ('<li><p>(' .. M.TASK_OPEN .. ')', '<li class="md-task"><p>%1')
    :gsub ('<li><p>(' .. M.TASK_DONE .. ')', '<li class="md-task"><p>%1')
    :gsub ('<li>(' .. M.TASK_OPEN .. ')', '<li class="md-task">%1')
    :gsub ('<li>(' .. M.TASK_DONE .. ')', '<li class="md-task">%1')
    :gsub (M.TASK_OPEN, '<span class="md-check"></span>')
    :gsub (M.TASK_DONE, '<span class="md-check done"></span>')
  return as_written (html)
end

---What a link's address points at.
---@param target string
---@return LangMarkdown.Target?
function M.classify (target)
  if target == '' then
    return nil
  end
  if target:sub (1, 1) == '#' then
    return { kind = 'anchor', anchor = decode (target:sub (2)) }
  end
  if target:sub (1, 2) == '//' then
    return { kind = 'web', url = 'https:' .. target }
  end
  local scheme = target:match ('^(%a[%w+.-]*):')
  -- One letter is a Windows drive, such as `C:/notes/a.md`, not a scheme.
  if scheme and #scheme > 1 then
    local s = scheme:lower ()
    if s == 'http' or s == 'https' or s == 'mailto' then
      return { kind = 'web', url = target }
    end
    return { kind = 'other', url = target }
  end
  local path, anchor = target:match ('^([^#]*)#?(.*)$')
  path = decode ((path:gsub ('%?.*$', '')))
  if path == '' then
    return { kind = 'anchor', anchor = decode (anchor) }
  end
  return {
    kind = 'file',
    path = path,
    anchor = anchor ~= '' and decode (anchor) or nil,
  }
end

---Tidies a path: forward slashes, with `.` and `..` worked out. Nil when `..` climbs above
---the top of a path that has no root, such as a workspace path.
---@param path string
---@return string?
function M.normalize (path)
  path = path:gsub ('\\', '/')
  local prefix = path:match ('^%a:/')
    or path:match ('^//')
    or path:match ('^/')
    or ''
  local rest = path:sub (#prefix + 1)
  local stack = {} ---@type string[]
  for seg in rest:gmatch ('[^/]+') do
    if seg == '..' then
      if #stack > 0 then
        stack[#stack] = nil
      elseif prefix == '' then
        return nil
      end
    elseif seg ~= '.' then
      stack[#stack + 1] = seg
    end
  end
  return prefix .. table.concat (stack, '/')
end

---The path a relative link leads to, from the file the link is in. A path that starts with
---`/` starts at `root`: the open folder as a full path, or `''` for the top of the
---workspace. Without a root, it is a full path on disk.
---@param from string The path of the file the link is in.
---@param path string The link's path.
---@param root? string
---@return string?
function M.resolve (from, path, root)
  path = path:gsub ('\\', '/')
  if path:match ('^%a:/') then
    return M.normalize (path)
  end
  if path:sub (1, 1) == '/' then
    if root == '' then
      return M.normalize (path:sub (2))
    end
    return M.normalize ((root or '') .. path)
  end
  local folder = from:gsub ('\\', '/'):match ('^(.*)/[^/]*$')
  if not folder then
    return M.normalize (path)
  end
  return M.normalize (folder .. '/' .. path)
end

return M
