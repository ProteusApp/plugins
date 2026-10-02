-- git_blame: reads `git blame --porcelain` and draws who last changed each line of a file. It
-- calls no host function, so the tests reach all of it.

---The commit a line last changed in.
---@class Git.BlameCommit
---@field hash string
---@field author string
---@field time integer Seconds since 1970.
---@field tz string Such as `'+0200'`.
---@field summary string The first line of its message.

---@class Git.BlameLine
---@field hash string
---@field line integer Its number in the file now, from 1.
---@field text string

---@class Git.Blame
---@field lines Git.BlameLine[]
---@field commits table<string, Git.BlameCommit>
---@field cut boolean True when reading stopped at the line limit.

---@class Git.BlameModule
local M = {}

-- How many lines of a file the blame view reads and draws.
M.MAX_LINES = 5000

---@type table<string, string>
local HTML_ESCAPES = {
  ['&'] = '&amp;',
  ['<'] = '&lt;',
  ['>'] = '&gt;',
  ['"'] = '&quot;',
  ["'"] = '&#39;',
}

---@param s any
---@return string
local function esc (s)
  local out = tostring (s):gsub ('[&<>"\']', HTML_ESCAPES)
  return out
end

---True for the hash Git gives lines that are not committed yet.
---@param hash string
---@return boolean
function M.uncommitted (hash)
  return not hash:find ('[^0]')
end

---The blame of the file as it is on disk now, from the repository root.
---@param path string
---@return string[]
function M.args (path)
  return { 'blame', '--porcelain', '--', path }
end

---Reads `git blame --porcelain` output, up to `max_lines` lines of the file.
---@param text string
---@param max_lines? integer
---@return Git.Blame
function M.parse (text, max_lines)
  local max = max_lines or M.MAX_LINES
  ---@type Git.Blame
  local out = { lines = {}, commits = {}, cut = false }
  local current = nil ---@type Git.BlameCommit?
  local number = 0
  local pos = 1
  while pos <= #text do
    local stop = text:find ('\n', pos, true)
    local raw = text:sub (pos, (stop or #text + 1) - 1)
    pos = (stop or #text) + 1
    if raw:sub (1, 1) == '\t' then
      if current then
        if #out.lines >= max then
          out.cut = true
          break
        end
        local body = raw:sub (2):gsub ('\r$', '')
        out.lines[#out.lines + 1] =
          { hash = current.hash, line = number, text = body }
      end
    else
      local hash, final = raw:match ('^(%x+) %d+ (%d+)')
      if hash and #hash >= 40 then
        number = math.floor (tonumber (final) or 0)
        current = out.commits[hash]
        if not current then
          current =
            { hash = hash, author = '', time = 0, tz = '+0000', summary = '' }
          out.commits[hash] = current
        end
      elseif current then
        local key, value = raw:match ('^(%S+) ?(.*)$')
        if key == 'author' then
          current.author = value
        elseif key == 'author-time' then
          current.time = math.floor (tonumber (value) or 0)
        elseif key == 'author-tz' then
          current.tz = value
        elseif key == 'summary' then
          current.summary = value
        end
      end
    end
  end
  return out
end

---The day a commit was made, in its author's own time zone, such as `'2026-09-01'`.
---@param c Git.BlameCommit
---@return string
function M.day (c)
  local sign, hh, mm = c.tz:match ('^([+-])(%d%d)(%d%d)$')
  local offset = 0
  if sign then
    offset = ((tonumber (hh) or 0) * 3600 + (tonumber (mm) or 0) * 60)
      * (sign == '-' and -1 or 1)
  end
  return tostring (os.date ('!%Y-%m-%d', c.time + offset))
end

---The blame as HTML: each line with, where a new commit starts, its short hash, author, day
---and subject. The hash carries `data-item="blame:<hash>"` to show that commit.
---@param path string
---@param blame Git.Blame
---@return string
function M.html (path, blame)
  local out = {
    '<div class="git-blame"><div class="git-file-head"><span class="git-file-path">',
    esc (path),
    '</span><span class="git-file-tag">Blame</span></div>',
  }
  if #blame.lines == 0 then
    out[#out + 1] = '<div class="git-note">The file is empty.</div>'
  end
  local last = nil ---@type string?
  for _, l in ipairs (blame.lines) do
    local info = ''
    local first = l.hash ~= last
    if first then
      local c = blame.commits[l.hash]
      if M.uncommitted (l.hash) then
        info = '<span class="git-blame-who">Not committed yet</span>'
      elseif c then
        info = '<span class="git-hash git-blame-hash" data-item="blame:'
          .. esc (c.hash)
          .. '" title="'
          .. esc (c.summary)
          .. '">'
          .. esc (c.hash:sub (1, 7))
          .. '</span><span class="git-blame-who">'
          .. esc (c.author)
          .. '</span><span class="git-blame-day">'
          .. esc (M.day (c))
          .. '</span>'
      end
    end
    last = l.hash
    out[#out + 1] = '<div class="git-blame-line'
      .. (first and ' git-blame-first' or '')
      .. '"><span class="git-blame-info">'
      .. info
      .. '</span><span class="git-ln">'
      .. l.line
      .. '</span><span class="git-code">'
      .. esc (l.text)
      .. '</span></div>'
  end
  if blame.cut then
    out[#out + 1] = '<div class="git-note">Showing the first '
      .. #blame.lines
      .. ' lines. The rest is left out.</div>'
  end
  out[#out + 1] = '</div>'
  return table.concat (out)
end

return M
