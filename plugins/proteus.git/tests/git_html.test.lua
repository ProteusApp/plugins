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

---------------------------------------------------------------------------------------------
-- Syntax colors
---------------------------------------------------------------------------------------------

local DIFF_LUA = [[
diff --git a/src/a.lua b/src/a.lua
index c4352f8..bd17d1b 100644
--- a/src/a.lua
+++ b/src/a.lua
@@ -1,3 +1,3 @@
 local a = 1
-local b = 2 < 3
+local b = 4 < 3
 return a
]]

---Escapes the way the app's highlighter does, as numeric entities.
---@param s string
---@return string
local function num_escape (s)
  local out = s:gsub ('[&<>"\']', function (c)
    return '&#' .. c:byte () .. ';'
  end)
  return out
end

---A stand-in for app.util.highlight: `local` is a keyword and digits are numbers. It keeps
---each call's text and language in `calls`.
---@param calls { code: string, lang: string }[]
---@return fun(code: string, lang: string): string
local function fake_highlight (calls)
  return function (code, lang)
    calls[#calls + 1] = { code = code, lang = lang }
    local out = {} ---@type string[]
    for word, rest in code:gmatch ('([%w_]*)([^%w_]*)') do
      if word == 'local' then
        out[#out + 1] = '<span class="syn-keyword">local</span>'
      elseif word:find ('^%d+$') then
        out[#out + 1] = '<span class="syn-number">' .. word .. '</span>'
      else
        out[#out + 1] = num_escape (word)
      end
      out[#out + 1] = num_escape (rest)
    end
    return table.concat (out)
  end
end

test ('code_language names the language of a file', function ()
  local paths = require ('git_paths') --[[@as Git.PathsModule]]
  eq (paths.code_language ('src/a.lua'), 'lua')
  eq (paths.code_language ('web/App.TSX'), 'typescript')
  eq (paths.code_language ('C:\\r\\main.rs'), 'rust')
  eq (paths.code_language ('docker/Dockerfile'), 'dockerfile')
  eq (paths.code_language ('notes.txt'), nil)
  eq (paths.code_language ('Makefile'), nil)
end)

test ('syntax_lines reads colored HTML back into runs, line by line', function ()
  eq (
    html.syntax_lines (
      '<span class="syn-keyword">if</span> a &#60; b\n<span class="syn-string x">&quot;&amp;&quot;</span>'
    ),
    {
      {
        { text = 'if', class = 'syn-keyword' },
        { text = ' a < b', class = '' },
      },
      { { text = '"&"', class = 'syn-string' } },
    }
  )
  eq (html.syntax_lines ('a\n\nb'), {
    { { text = 'a', class = '' } },
    {},
    { { text = 'b', class = '' } },
  })
  -- Anything but flat spans and text is refused, so it never reaches the page.
  eq (html.syntax_lines ('<b>x</b>'), nil)
  eq (html.syntax_lines ('<span class="a"><span>x</span></span>'), nil)
  eq (html.syntax_lines ('&bogus;'), nil)
  eq (html.syntax_lines ('&#8364;'), nil)
end)

test (
  'diff_html colors lines by the file language and keeps the changed words',
  function ()
    local calls = {} ---@type { code: string, lang: string }[]
    local files = m.parse_diff (DIFF_LUA)
    local opts = {
      highlight = fake_highlight (calls),
      language = m.code_language,
    }
    local out = html.diff_html (files, opts)
    -- Each side of the hunk is colored as one text: the old with its removed line, the new
    -- with its added one.
    eq (calls, {
      { code = 'local a = 1\nlocal b = 2 < 3\nreturn a', lang = 'lua' },
      { code = 'local a = 1\nlocal b = 4 < 3\nreturn a', lang = 'lua' },
    })
    ok (
      out:find (
        '<span class="git-code"><span class="syn-keyword">local</span> a = <span class="syn-number">1</span></span>',
        1,
        true
      ),
      'a context line is colored'
    )
    -- The changed word keeps its color inside its mark, and the text stays escaped.
    ok (
      out:find (
        '<span class="git-code"><span class="syn-keyword">local</span> b = <span class="git-w"><span class="syn-number">2</span></span> &lt; <span class="syn-number">3</span></span>',
        1,
        true
      ),
      'the removed line'
    )
    ok (
      out:find (
        '<span class="git-w"><span class="syn-number">4</span></span>',
        1,
        true
      ),
      'the added line'
    )
    -- Picking a line draws the diff again from the colors already worked out.
    html.diff_html (files, opts)
    eq (#calls, 2)
    -- The side-by-side view is colored too.
    opts.split = true
    local split = html.diff_html (files, opts)
    ok (split:find ('git-half', 1, true) and split:find ('syn-number', 1, true))
  end
)

test ('diff_html leaves lines plain without a language or a match', function ()
  local calls = {} ---@type { code: string, lang: string }[]
  local files = m.parse_diff (DIFF_LUA)
  local plain = html.diff_html (files, {
    highlight = fake_highlight (calls),
    language = function ()
      return nil
    end,
  })
  eq (#calls, 0)
  ok (not plain:find ('syn-', 1, true))
  -- A highlighter that changes the text, or fails, colors nothing.
  local odd = html.diff_html (m.parse_diff (DIFF_LUA), {
    highlight = function (code)
      return (code:gsub ('local', 'nonlocal'))
    end,
    language = m.code_language,
  })
  ok (odd:find ('<span class="git-code">local a = 1</span>', 1, true))
  local broken = html.diff_html (m.parse_diff (DIFF_LUA), {
    highlight = function ()
      error ('no')
    end,
    language = m.code_language,
  })
  ok (broken:find ('<span class="git-code">local a = 1</span>', 1, true))
  -- Without a highlighter the diff is drawn as before.
  ok (not html.diff_html (m.parse_diff (DIFF_LUA)):find ('syn-', 1, true))
end)
