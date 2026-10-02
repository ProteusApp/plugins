-- Tests for git_html, which draws the Git client's lists and diffs as HTML. tests/git.test.lua
-- reaches the same functions through git_parse.

local html = require ('git_html') --[[@as Git.HtmlModule]]
local m = require ('git_parse') --[[@as Git.ParseModule]]

---@param path string
---@param code string
---@param kind Git.Kind
---@param staged boolean
---@return Git.Entry
local function entry (path, code, kind, staged)
  return {
    path = path,
    code = code,
    kind = kind,
    letter = kind:sub (1, 1):upper (),
    staged = staged,
  }
end

---@param text string
---@param part string
---@return integer
local function count (text, part)
  local n, at = 0, 1
  while true do
    local i = text:find (part, at, true)
    if not i then
      return n
    end
    n, at = n + 1, i + #part
  end
end

test ('git_parse hands out every function of git_html', function ()
  for k, v in pairs (html) do
    eq (m[k], v, k)
  end
  eq (m.LIST_LIMIT, 500)
end)

test ('escape covers attribute values', function ()
  eq (
    html.escape ([[<a href="x">'&'</a>]]),
    '&lt;a href=&quot;x&quot;&gt;&#39;&amp;&#39;&lt;/a&gt;'
  )
  eq (html.escape (12), '12')
  eq (html.thousands (0), '0')
  eq (html.thousands (100000), '100,000')
end)

test ('a row offers Discard only for a change it can throw away', function ()
  ---@type Git.Status
  local st = {
    ahead = 0,
    behind = 0,
    gone = false,
    detached = false,
    initial = false,
    staged = { entry ('src/s.txt', 'M ', 'modified', true) },
    unstaged = {
      entry ('src/lib/u.txt', ' M', 'modified', false),
      entry ('n.txt', '??', 'untracked', false),
      entry ('c.txt', 'UU', 'conflicted', false),
    },
  }
  local out = html.changes_html (st)
  eq (count (out, 'data-item="discard:'), 2)
  ok (out:find ('data-item="discard:u:src/lib/u.txt"', 1, true))
  ok (out:find ('data-item="discard:u:n.txt"', 1, true))
  ok (out:find ('data-item="unstage:s:src/s.txt"', 1, true))
  ok (out:find ('title="Mark Resolved"', 1, true))
  -- The row shows the file name, then its folder.
  ok (
    out:find (
      '<span class="git-name">u.txt</span><span class="git-dir">src/lib</span>',
      1,
      true
    )
  )
end)

test ('changes_html draws a list whole when asked', function ()
  local list = {} ---@type Git.Entry[]
  for i = 1, 4 do
    list[i] = entry ('f' .. i .. '.txt', '??', 'untracked', false)
  end
  ---@type Git.Status
  local st = {
    ahead = 0,
    behind = 0,
    gone = false,
    detached = false,
    initial = false,
    staged = {},
    unstaged = list,
  }
  local cut = html.changes_html (st, { limit = 2 })
  eq (count (cut, 'data-item="open:'), 2)
  ok (cut:find ('data-item="show-all-u">Show all 4 files', 1, true))
  local whole = html.changes_html (st, { limit = 2, all = { u = true } })
  eq (count (whole, 'data-item="open:'), 4)
  eq (count (whole, 'show-all-u'), 0)
end)

test ('welcome_html names each recent repository by its folder', function ()
  local out = html.welcome_html ({ 'C:/work/my repo' })
  ok (out:find ('<span class="git-recent-name">my repo</span>', 1, true))
  ok (out:find ('data-item="recent:C:/work/my repo"', 1, true))
end)

test ('conflict_html leaves out Open File for a deleted file', function ()
  local both = html.conflict_html (entry ('d.txt', 'DD', 'conflicted', false))
  eq (count (both, 'conflict:open'), 0)
  eq (count (both, 'Accept Current (delete)'), 1)
  eq (count (both, 'Accept Incoming (delete)'), 1)
  local added = html.conflict_html (entry ('a.txt', 'AA', 'conflicted', false))
  eq (count (added, 'conflict:open'), 1)
  ok (added:find ('Both sides added this file.', 1, true))
end)
