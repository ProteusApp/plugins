-- Tests for git_parse. The samples are real output from git 2.54, captured in scratch
-- repositories with the same arguments the Git client passes. DIFF_CRLF is built by hand, and
-- SHOW_DEFAULT is shortened.

local m = require ('git_parse') --[[@as Git.ParseModule]]

---------------------------------------------------------------------------------------------
-- Samples
---------------------------------------------------------------------------------------------

local STATUS_WORK = [[
## main...origin/main [ahead 1, behind 1]
MM a.txt
A  added.txt
D  b.txt
 M bin.dat
 D del.txt
 A intent.txt
R  old.txt -> "new name.txt"
 M nonl.txt
 M "sp ace.txt"
?? café.txt
?? deep/dir/file.txt
]]

local STATUS_WORK_Z = '## main...origin/main [ahead 1, behind 1]\0MM a.txt\0'
  .. 'A  added.txt\0D  b.txt\0 M bin.dat\0 D del.txt\0 A intent.txt\0'
  .. 'R  new name.txt\0old.txt\0 M nonl.txt\0 M sp ace.txt\0?? café.txt\0'
  .. '?? deep/dir/file.txt\0'

local STATUS_EMPTY = [[
## No commits yet on main
?? a.txt
?? src/café.txt
?? "src/my file.txt"
]]

local STATUS_EMPTY_Z = '## No commits yet on main\0?? a.txt\0'
  .. '?? src/café.txt\0?? src/my file.txt\0'

local STATUS_CONFLICT = [[
## main...origin/main [ahead 1]
AA addadd.txt
UU both.txt
UD theydel.txt
DU wedel.txt
]]

local STATUS_CONFLICT_Z = '## main...origin/main [ahead 1]\0AA addadd.txt\0'
  .. 'UU both.txt\0UD theydel.txt\0DU wedel.txt\0'

local STATUS_GONE = '## gone...origin/gone [gone]\n'

local STATUS_DETACHED = '## HEAD (no branch)\n'

-- Without core.quotepath=false, Git writes the bytes of a non-ASCII letter as octal.
local STATUS_OCTAL = '## main\n?? "caf\\303\\251.txt"\n'

local LOG_FULL = '509d3036a0a49779fa76a02bd5516058681ded1a\031509d303\031Ada'
  .. '\0314 weeks ago\031HEAD -> refs/heads/main\031Second commit\030\n'
  .. '6258eaf43d5fe95c2ba9a130c66c99fc76e12393\0316258eaf\031Ada'
  .. '\0314 weeks ago\031tag: refs/tags/v1.0, refs/remotes/origin/feature/x,'
  .. ' refs/heads/gone, refs/heads/feature/x\031First commit\030\n'

local LOG_SHORT = '509d3036a0a49779fa76a02bd5516058681ded1a\031509d303\031Ada'
  .. '\0314 weeks ago\031HEAD -> main\031Second commit\030\n'
  .. '6258eaf43d5fe95c2ba9a130c66c99fc76e12393\0316258eaf\031Ada'
  .. '\0314 weeks ago\031tag: v1.0, origin/feature/x, gone, feature/x'
  .. '\031First commit\030\n'

local LOG_DETACHED = '41499c4dbc469917a9a86d5a0f970467b1ebd419\03141499c4\031Ada'
  .. '\0314 weeks ago\031HEAD\031Grow moved\030\n'
  .. 'c7e024743d0c31ea9dd86957c34ab92a60413783\031c7e0247\031Ada'
  .. '\0314 weeks ago\031\031Main changes\030\n'
  .. 'a5c7f87986b840b3f50e3058fc4d8c3ad125c3cf\031a5c7f87\031Ada'
  .. '\0314 weeks ago\031refs/remotes/origin/main, refs/heads/gone\031Base\030\n'

local BRANCHES = ' \trefs/heads/feature/x\torigin/feature/x\n'
  .. ' \trefs/heads/gone\torigin/gone\n'
  .. '*\trefs/heads/main\torigin/main\n'
  .. ' \trefs/remotes/origin/HEAD\t\n'
  .. ' \trefs/remotes/origin/feature/x\t\n'
  .. ' \trefs/remotes/origin/main\t\n'

local BRANCHES_DETACHED = '*\t(HEAD detached at 41499c4)\t\n'
  .. ' \trefs/heads/gone\torigin/gone\n'
  .. ' \trefs/heads/main\torigin/main\n'
  .. ' \trefs/heads/side\t\n'
  .. ' \trefs/heads/topic\t\n'
  .. ' \trefs/remotes/origin/main\t\n'

local DIFF_A_STAGED = [[
diff --git a/a.txt b/a.txt
index c4352f8..bd17d1b 100644
--- a/a.txt
+++ b/a.txt
@@ -1,5 +1,5 @@
 line 1
-line 2
+line two
 line 3
 line 4
 line 5
@@ -15,6 +15,6 @@ line 14
 line 15
 line 16
 line 17
-line 18
+line eighteen
 line 19
 line 20
]]

local DIFF_ADDED = [[
diff --git a/added.txt b/added.txt
new file mode 100644
index 0000000..d5f7fc3
--- /dev/null
+++ b/added.txt
@@ -0,0 +1 @@
+added
]]

local DIFF_DELETED = [[
diff --git a/del.txt b/del.txt
deleted file mode 100644
index 9c2a709..0000000
--- a/del.txt
+++ /dev/null
@@ -1,4 +0,0 @@
-line 1
-line 2
-line 3
-line 4
]]

local DIFF_BINARY = [[
diff --git a/bin.dat b/bin.dat
index 0f49c4a..4b9eb23 100644
Binary files a/bin.dat and b/bin.dat differ
]]

local DIFF_NO_NEWLINE = [[
diff --git a/nonl.txt b/nonl.txt
index 9ed40b4..530cc72 100644
--- a/nonl.txt
+++ b/nonl.txt
@@ -1,2 +1,2 @@
 one
-two
\ No newline at end of file
+TWO
\ No newline at end of file
]]

-- Git ends a --- or +++ name that holds a space with a tab.
local DIFF_SPACE = 'diff --git a/sp ace.txt b/sp ace.txt\n'
  .. 'index 9495c3c..a9365a4 100644\n'
  .. '--- a/sp ace.txt\t\n'
  .. '+++ b/sp ace.txt\t\n'
  .. '@@ -1 +1 @@\n'
  .. '-space\n'
  .. '+space changed\n'

local DIFF_QUOTED = 'diff --git "a/caf\\303\\251.txt" "b/caf\\303\\251.txt"\n'
  .. 'new file mode 100644\n'
  .. 'index 0000000..4ae8ef0\n'
  .. '--- /dev/null\n'
  .. '+++ "b/caf\\303\\251.txt"\n'
  .. '@@ -0,0 +1 @@\n'
  .. '+u\n'

local DIFF_CACHED_ALL = DIFF_A_STAGED
  .. DIFF_ADDED
  .. [[
diff --git a/b.txt b/b.txt
deleted file mode 100644
index 9681dbe..0000000
--- a/b.txt
+++ /dev/null
@@ -1,2 +0,0 @@
-bee
-extra
diff --git a/old.txt b/new name.txt
similarity index 100%
rename from old.txt
rename to new name.txt
]]

local DIFF_CONFLICT = [[
diff --cc both.txt
index ba2906d,2299c37..0000000
--- a/both.txt
+++ b/both.txt
@@@ -1,1 -1,1 +1,5 @@@
++<<<<<<< HEAD
 +main
++=======
+ side
++>>>>>>> side
]]

local DIFF_CRLF = 'diff --git a/w.txt b/w.txt\n'
  .. 'index 1a2b3c4..5d6e7f8 100644\n'
  .. '--- a/w.txt\n'
  .. '+++ b/w.txt\n'
  .. '@@ -1,2 +1,2 @@\n'
  .. ' one\r\n'
  .. '-two\r\n'
  .. '+TWO\r\n'

local SHOW_RENAME = 'bcb11c9e0973e1001c929958d8be34928a00b3a8\031bcb11c9\031Ada'
  .. '\031ada@example.com\0312026-09-01 10:00\0314 weeks ago'
  .. '\031849ddee79a619a91413f00590d4cccd633b19a5e'
  .. '\031Rename, add and delete\n'
  .. '\n'
  .. 'The body explains why.\n'
  .. '\n'
  .. 'It has two paragraphs.\n'
  .. '\030\n'
  .. '\n'
  .. 'diff --git a/both.txt b/both.txt\n'
  .. 'deleted file mode 100644\n'
  .. 'index ba2906d..0000000\n'
  .. '--- a/both.txt\n'
  .. '+++ /dev/null\n'
  .. '@@ -1 +0,0 @@\n'
  .. '-main\n'
  .. 'diff --git a/fresh.txt b/fresh.txt\n'
  .. 'new file mode 100644\n'
  .. 'index 0000000..92d5444\n'
  .. '--- /dev/null\n'
  .. '+++ b/fresh.txt\n'
  .. '@@ -0,0 +1 @@\n'
  .. '+fresh\n'
  .. 'diff --git a/moved.txt b/renamed file.txt\n'
  .. 'similarity index 100%\n'
  .. 'rename from moved.txt\n'
  .. 'rename to renamed file.txt\n'

local SHOW_MERGE = '849ddee79a619a91413f00590d4cccd633b19a5e\031849ddee\031Ada'
  .. '\031ada@example.com\0312026-09-01 10:00\0314 weeks ago'
  .. '\03141499c4dbc469917a9a86d5a0f970467b1ebd419'
  .. ' eb62962f84e5573f81cc76a5e82f8e61fcb08a8a'
  .. "\031Merge branch 'topic'\n"
  .. '\030\n'
  .. '\n'
  .. 'diff --git a/topic.txt b/topic.txt\n'
  .. 'new file mode 100644\n'
  .. 'index 0000000..0f62d67\n'
  .. '--- /dev/null\n'
  .. '+++ b/topic.txt\n'
  .. '@@ -0,0 +1 @@\n'
  .. '+topic\n'

-- git show with its own header format, which indents the message.
local SHOW_DEFAULT = [[
commit bcb11c9e0973e1001c929958d8be34928a00b3a8
Author: Ada <ada@example.com>
Date:   Tue Sep 1 10:00:00 2026 +0000

    Rename, add and delete

    The body explains why.

diff --git a/both.txt b/both.txt
deleted file mode 100644
index ba2906d..0000000
--- a/both.txt
+++ /dev/null
@@ -1 +0,0 @@
-main
diff --git a/fresh.txt b/fresh.txt
new file mode 100644
index 0000000..92d5444
--- /dev/null
+++ b/fresh.txt
@@ -0,0 +1 @@
+fresh
diff --git a/moved.txt b/renamed file.txt
similarity index 100%
rename from moved.txt
rename to renamed file.txt
]]

---------------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------------

---Each entry as `'<code>|<kind>|<path>'`, with `<-old` after a rename.
---@param list Git.Entry[]
---@return string[]
local function brief (list)
  local out = {} ---@type string[]
  for _, e in ipairs (list) do
    out[#out + 1] = e.code
      .. '|'
      .. e.kind
      .. '|'
      .. e.path
      .. (e.old_path and ('<-' .. e.old_path) or '')
  end
  return out
end

---@param path string
---@param code string
---@param kind Git.Kind
---@param staged boolean
---@param old_path? string
---@return Git.Entry
local function entry (path, code, kind, staged, old_path)
  return {
    path = path,
    old_path = old_path,
    code = code,
    kind = kind,
    letter = 'M',
    staged = staged,
  }
end

---@param html string
---@param part string
local function has (html, part)
  ok (html:find (part, 1, true), 'expected to find ' .. part)
end

---@param html string
---@param part string
local function lacks (html, part)
  ok (not html:find (part, 1, true), 'did not expect ' .. part)
end

---@param html string
---@param part string
---@return integer
local function count (html, part)
  local n, at = 0, 1
  while true do
    local i = html:find (part, at, true)
    if not i then
      return n
    end
    n, at = n + 1, i + #part
  end
end

---Each line of the first hunk as `'<kind> <old> <new> <text>'`.
---@param h Git.Hunk
---@return string[]
local function hunk_lines (h)
  local out = {} ---@type string[]
  for _, l in ipairs (h.lines) do
    out[#out + 1] = l.kind
      .. ' '
      .. tostring (l.old or '-')
      .. ' '
      .. tostring (l.new or '-')
      .. ' '
      .. l.text
  end
  return out
end

---------------------------------------------------------------------------------------------
-- git status
---------------------------------------------------------------------------------------------

test ('parse_status reads every kind of change', function ()
  local st = m.parse_status (STATUS_WORK)
  eq (st.branch, 'main')
  eq (st.upstream, 'origin/main')
  eq ({ st.ahead, st.behind, st.gone, st.detached, st.initial }, {
    1,
    1,
    false,
    false,
    false,
  })
  eq (brief (st.staged), {
    'MM|modified|a.txt',
    'A |added|added.txt',
    'D |deleted|b.txt',
    'R |renamed|new name.txt<-old.txt',
  })
  eq (brief (st.unstaged), {
    'MM|modified|a.txt',
    ' M|modified|bin.dat',
    ' D|deleted|del.txt',
    ' A|added|intent.txt',
    ' M|modified|nonl.txt',
    ' M|modified|sp ace.txt',
    '??|untracked|café.txt',
    '??|untracked|deep/dir/file.txt',
  })
  eq (st.staged[4], {
    path = 'new name.txt',
    old_path = 'old.txt',
    code = 'R ',
    kind = 'renamed',
    letter = 'R',
    staged = true,
  })
  eq (st.unstaged[7].letter, 'U')
  eq (st.unstaged[1].staged, false)
end)

test ('parse_status reads -z output the same way', function ()
  eq (m.parse_status (STATUS_WORK_Z), m.parse_status (STATUS_WORK))
  eq (m.parse_status (STATUS_EMPTY_Z), m.parse_status (STATUS_EMPTY))
  eq (m.parse_status (STATUS_CONFLICT_Z), m.parse_status (STATUS_CONFLICT))
end)

test ('parse_status reads a repository with no commits', function ()
  local st = m.parse_status (STATUS_EMPTY)
  eq (st.initial, true)
  eq (st.branch, 'main')
  eq (st.upstream, nil)
  eq (brief (st.unstaged), {
    '??|untracked|a.txt',
    '??|untracked|src/café.txt',
    '??|untracked|src/my file.txt',
  })
  eq (#st.staged, 0)
end)

test ('parse_status reads conflicts once, in the Changes list', function ()
  local st = m.parse_status (STATUS_CONFLICT)
  eq (st.ahead, 1)
  eq (st.behind, 0)
  eq (#st.staged, 0)
  eq (brief (st.unstaged), {
    'AA|conflicted|addadd.txt',
    'UU|conflicted|both.txt',
    'UD|conflicted|theydel.txt',
    'DU|conflicted|wedel.txt',
  })
  eq (st.unstaged[2].letter, '!')
end)

test ('parse_status reads a gone upstream and a detached HEAD', function ()
  local gone = m.parse_status (STATUS_GONE)
  eq ({ gone.branch, gone.upstream, gone.gone }, { 'gone', 'origin/gone', true })
  eq (m.sync_text (gone), 'upstream gone')
  local det = m.parse_status (STATUS_DETACHED)
  eq (det.detached, true)
  eq (det.branch, nil)
  eq (m.branch_text (det), 'detached HEAD')
  local plain = m.parse_status ('## main\n')
  eq ({ plain.branch, plain.upstream, plain.ahead }, { 'main', nil, 0 })
end)

test ('parse_status reads octal escapes in a quoted path', function ()
  local st = m.parse_status (STATUS_OCTAL)
  eq (st.unstaged[1].path, 'café.txt')
end)

test ('unquote reads C-style escapes in one pass', function ()
  eq (m.unquote ('plain.txt'), 'plain.txt')
  eq (m.unquote ('"src/my file.txt"'), 'src/my file.txt')
  eq (m.unquote ('"a\\"b\\\\c\\td"'), 'a"b\\c\td')
  eq (m.unquote ('"\\\\101"'), '\\101')
  eq (m.unquote ('"caf\\303\\251"'), 'café')
end)

test ('counts, sync text and the branch label', function ()
  local st = m.parse_status (STATUS_WORK)
  eq (m.change_count (st), 11)
  eq (m.sync_text (st), '↑1 ↓1')
  eq (m.sync_text (m.parse_status (STATUS_CONFLICT)), '↑1')
  eq (m.sync_text (m.parse_status ('## main...origin/main\n')), '')
  eq (m.branch_text (st), 'main')
  eq (m.count_text (0), 'No changes')
  eq (m.count_text (1), '1 change')
  eq (m.count_text (3), '3 changes')
end)

test ('find_entry and reselect follow a file across the lists', function ()
  local st = m.parse_status ('## main\nM  a.txt\n M b.txt\n')
  eq (m.find_entry (st, 's', 'a.txt') ~= nil, true)
  eq (m.find_entry (st, 'u', 'a.txt'), nil)
  eq (m.find_entry (nil, 'u', 'a.txt'), nil)
  local moved = m.reselect (st, 'u', 'a.txt')
  eq (moved and moved.staged, true)
  eq (m.reselect (st, 'u', 'b.txt') == st.unstaged[1], true)
  eq (m.reselect (st, 's', 'gone.txt'), nil)
end)

---------------------------------------------------------------------------------------------
-- git log and git branch
---------------------------------------------------------------------------------------------

test ('parse_log reads commits and full ref names', function ()
  local log = m.parse_log (LOG_FULL)
  eq (#log, 2)
  eq (log[1], {
    hash = '509d3036a0a49779fa76a02bd5516058681ded1a',
    short = '509d303',
    author = 'Ada',
    date = '4 weeks ago',
    refs = { { name = 'main', kind = 'branch', current = true } },
    subject = 'Second commit',
  })
  eq (log[2].refs, {
    { name = 'v1.0', kind = 'tag', current = false },
    { name = 'origin/feature/x', kind = 'remote', current = false },
    { name = 'gone', kind = 'branch', current = false },
    { name = 'feature/x', kind = 'branch', current = false },
  })
end)

test ('parse_log reads short ref names, a detached HEAD and no refs', function ()
  local short = m.parse_log (LOG_SHORT)
  eq (short[1].refs, { { name = 'main', kind = 'branch', current = true } })
  eq (short[2].refs[1], { name = 'v1.0', kind = 'tag', current = false })
  local det = m.parse_log (LOG_DETACHED)
  eq (det[1].refs, { { name = 'HEAD', kind = 'head', current = true } })
  eq (det[2].refs, {})
  eq (det[2].subject, 'Main changes')
  eq (det[3].refs[1], { name = 'origin/main', kind = 'remote', current = false })
  eq (m.parse_log (''), {})
end)

test ('parse_branches lists local branches, then remote ones', function ()
  eq (m.parse_branches (BRANCHES), {
    {
      name = 'feature/x',
      remote = false,
      current = false,
      upstream = 'origin/feature/x',
    },
    {
      name = 'gone',
      remote = false,
      current = false,
      upstream = 'origin/gone',
    },
    { name = 'main', remote = false, current = true, upstream = 'origin/main' },
    { name = 'origin/feature/x', remote = true, current = false },
    { name = 'origin/main', remote = true, current = false },
  })
  local det = m.parse_branches (BRANCHES_DETACHED)
  eq (#det, 5)
  eq (det[1].name, 'gone')
  eq (det[1].current, false)
  eq (det[5], { name = 'origin/main', remote = true, current = false })
  -- Short names cannot tell a remote branch from a local one.
  eq (m.parse_branches ('*\tmain\t\n')[1].remote, false)
end)

test ('branch_choices and switch_args', function ()
  local branches = m.parse_branches (BRANCHES)
  local choices = m.branch_choices (branches)
  eq (
    choices[1],
    { label = 'Create new branch…', icon = 'plus', action = 'create' }
  )
  eq (choices[4], {
    label = 'main',
    detail = 'current branch',
    icon = 'check',
    action = 'switch',
    name = 'main',
  })
  eq (choices[5].action, 'track')
  eq (m.switch_args (choices[1], branches), nil)
  eq (m.switch_args (choices[4], branches), { 'switch', 'main' })
  -- origin/feature/x has a local branch already, so it switches to that.
  eq (m.switch_args (choices[5], branches), { 'switch', 'feature/x' })
  ---@type Git.Choice
  local other = {
    label = 'origin/other',
    icon = 'cloud',
    action = 'track',
    name = 'origin/other',
  }
  eq (m.switch_args (other, branches), { 'switch', '--track', 'origin/other' })
end)

test ('check_branch_name refuses names Git refuses', function ()
  eq (m.check_branch_name ('feature/x-1'), nil)
  ok (m.check_branch_name (''))
  ok (m.check_branch_name ('two words'))
  ok (m.check_branch_name ('a..b'))
  ok (m.check_branch_name ('-x'))
  ok (m.check_branch_name ('x/'))
  ok (m.check_branch_name ('x.lock'))
  ok (m.check_branch_name ('a~1'))
  ok (m.check_branch_name ('a@{b'))
end)

---------------------------------------------------------------------------------------------
-- git diff
---------------------------------------------------------------------------------------------

test ('parse_diff reads hunks and line numbers', function ()
  local files = m.parse_diff (DIFF_A_STAGED)
  eq (#files, 1)
  local f = files[1]
  eq ({ f.path, f.old_path, f.new_path }, { 'a.txt', 'a.txt', 'a.txt' })
  eq ({ f.added, f.removed, f.binary, f.new_file, f.deleted }, {
    2,
    2,
    false,
    false,
    false,
  })
  eq (#f.hunks, 2)
  eq (hunk_lines (f.hunks[1]), {
    'ctx 1 1 line 1',
    'del 2 - line 2',
    'add - 2 line two',
    'ctx 3 3 line 3',
    'ctx 4 4 line 4',
    'ctx 5 5 line 5',
  })
  local h = f.hunks[2]
  eq ({ h.header, h.old_start, h.old_count, h.new_start, h.new_count }, {
    '@@ -15,6 +15,6 @@ line 14',
    15,
    6,
    15,
    6,
  })
  eq (hunk_lines (h)[4], 'del 18 - line 18')
  eq (hunk_lines (h)[7], 'ctx 20 20 line 20')
end)

test ('parse_diff reads new, deleted, binary and renamed files', function ()
  local files = m.parse_diff (DIFF_CACHED_ALL)
  eq (#files, 4)
  local added, deleted, renamed = files[2], files[3], files[4]
  eq ({ added.path, added.old_path, added.new_file }, { 'added.txt', nil, true })
  eq (hunk_lines (added.hunks[1]), { 'add - 1 added' })
  eq ({ deleted.path, deleted.new_path, deleted.deleted, deleted.removed }, {
    'b.txt',
    nil,
    true,
    2,
  })
  eq ({ renamed.path, renamed.old_path, renamed.renamed, #renamed.hunks }, {
    'new name.txt',
    'old.txt',
    true,
    0,
  })
  local bin = m.parse_diff (DIFF_BINARY)[1]
  eq ({ bin.path, bin.binary, #bin.hunks }, { 'bin.dat', true, 0 })
  local del = m.parse_diff (DIFF_DELETED)[1]
  eq ({ del.path, del.deleted, del.removed }, { 'del.txt', true, 4 })
end)

test (
  'parse_diff reads the no-newline marker, a spaced name and a quoted name',
  function ()
    local nonl = m.parse_diff (DIFF_NO_NEWLINE)[1]
    eq (hunk_lines (nonl.hunks[1]), {
      'ctx 1 1 one',
      'del 2 - two',
      'meta - - No newline at end of file',
      'add - 2 TWO',
      'meta - - No newline at end of file',
    })
    eq ({ nonl.added, nonl.removed }, { 1, 1 })
    local space = m.parse_diff (DIFF_SPACE)[1]
    eq ({ space.path, space.old_path, space.new_path }, {
      'sp ace.txt',
      'sp ace.txt',
      'sp ace.txt',
    })
    local quoted = m.parse_diff (DIFF_QUOTED)[1]
    eq (
      { quoted.path, quoted.old_path, quoted.new_file },
      { 'café.txt', nil, true }
    )
  end
)

test ('parse_diff reads a conflict diff with two prefix columns', function ()
  local f = m.parse_diff (DIFF_CONFLICT)[1]
  eq ({ f.path, f.combined, f.added }, { 'both.txt', true, 5 })
  eq (hunk_lines (f.hunks[1]), {
    'add - 1 <<<<<<< HEAD',
    'add - 2 main',
    'add - 3 =======',
    'add - 4 side',
    'add - 5 >>>>>>> side',
  })
end)

test (
  'parse_diff drops a carriage return from the text but keeps it in raw',
  function ()
    local h = m.parse_diff (DIFF_CRLF)[1].hunks[1]
    eq (h.lines[2].text, 'two')
    eq (h.lines[2].raw, '-two\r')
  end
)

test ('parse_show reads the commit and its diff', function ()
  local show = m.parse_show (SHOW_RENAME)
  local c = assert (show.commit, 'a commit')
  eq (c, {
    hash = 'bcb11c9e0973e1001c929958d8be34928a00b3a8',
    short = 'bcb11c9',
    author = 'Ada',
    email = 'ada@example.com',
    date = '2026-09-01 10:00',
    relative = '4 weeks ago',
    parents = { '849ddee79a619a91413f00590d4cccd633b19a5e' },
    subject = 'Rename, add and delete',
    body = 'The body explains why.\n\nIt has two paragraphs.',
  })
  eq (#show.files, 3)
  eq ({ show.files[1].path, show.files[1].deleted }, { 'both.txt', true })
  eq ({ show.files[2].path, show.files[2].new_file }, { 'fresh.txt', true })
  eq ({ show.files[3].old_path, show.files[3].path }, {
    'moved.txt',
    'renamed file.txt',
  })
  local merge = m.parse_show (SHOW_MERGE)
  eq (#assert (merge.commit).parents, 2)
  eq (assert (merge.commit).body, '')
  eq (merge.files[1].path, 'topic.txt')
end)

test ('parse_diff skips the header of plain git show output', function ()
  local files = m.parse_diff (SHOW_DEFAULT)
  eq (#files, 3)
  eq (files[1].path, 'both.txt')
  eq (m.parse_show (SHOW_DEFAULT).commit, nil)
end)

---------------------------------------------------------------------------------------------
-- Patches
---------------------------------------------------------------------------------------------

test ('hunk_patch builds a patch for one hunk', function ()
  local f = m.parse_diff (DIFF_A_STAGED)[1]
  eq (
    m.hunk_patch (f, f.hunks[2]),
    table.concat ({
      'diff --git a/a.txt b/a.txt',
      'index c4352f8..bd17d1b 100644',
      '--- a/a.txt',
      '+++ b/a.txt',
      '@@ -15,6 +15,6 @@',
      ' line 15',
      ' line 16',
      ' line 17',
      '-line 18',
      '+line eighteen',
      ' line 19',
      ' line 20',
      '',
    }, '\n')
  )
end)

test ('hunk_patch of a one-hunk file gives back the diff itself', function ()
  for _, text in ipairs ({
    DIFF_ADDED,
    DIFF_DELETED,
    DIFF_NO_NEWLINE,
    DIFF_SPACE,
    DIFF_QUOTED,
    DIFF_CRLF,
  }) do
    local f = m.parse_diff (text)[1]
    eq (m.hunk_patch (f, f.hunks[1]), text)
  end
end)

test ('hunk_patch refuses a binary or a conflict diff', function ()
  local a = m.parse_diff (DIFF_A_STAGED)[1]
  local bin = m.parse_diff (DIFF_BINARY)[1]
  local conflict = m.parse_diff (DIFF_CONFLICT)[1]
  eq (m.hunk_patch (bin, a.hunks[1]), nil)
  eq (m.hunk_patch (conflict, conflict.hunks[1]), nil)
end)

test ('untracked_diff shows every line as added', function ()
  local f = m.untracked_diff ('x y.txt', 'a\r\nb')
  eq ({ f.path, f.new_file, f.added, f.binary }, { 'x y.txt', true, 2, false })
  eq (hunk_lines (f.hunks[1]), {
    'add - 1 a',
    'add - 2 b',
    'meta - - No newline at end of file',
  })
  eq (
    m.hunk_patch (f, f.hunks[1]),
    'diff --git a/x y.txt b/x y.txt\nnew file mode 100644\n'
      .. '--- /dev/null\n+++ b/x y.txt\t\n@@ -0,0 +1,2 @@\n'
      .. '+a\r\n+b\n\\ No newline at end of file\n'
  )
  local one = m.untracked_diff ('one.txt', 'only\n')
  eq (one.hunks[1].header, '@@ -0,0 +1 @@')
  eq (#one.hunks[1].lines, 1)
  local quoted = m.untracked_diff ('q"uote.txt', 'x\n')
  eq (quoted.header[1], 'diff --git "a/q\\"uote.txt" "b/q\\"uote.txt"')
  eq (quoted.header[4], '+++ "b/q\\"uote.txt"')
end)

test (
  'untracked_diff marks a file that is not text, and an empty file',
  function ()
    eq (m.untracked_diff ('pic.png', nil).binary, true)
    eq (m.untracked_diff ('nul.bin', 'a\0b').binary, true)
    local empty = m.untracked_diff ('empty.txt', '')
    eq ({ empty.binary, #empty.hunks }, { false, 0 })
  end
)

---------------------------------------------------------------------------------------------
-- Command lines
---------------------------------------------------------------------------------------------

test ('command lines', function ()
  -- Paths are names, never patterns, so a file called *.log stands for itself alone.
  eq (m.base_args (), { '--literal-pathspecs', '-c', 'core.quotepath=false' })
  eq (m.status_args (), {
    'status',
    '--porcelain=v1',
    '-z',
    '--branch',
    '--untracked-files=all',
  })
  eq (m.log_args (200), { 'log', '-n', '200', '--decorate=full', m.LOG_FORMAT })
  eq (m.branch_args (), { 'branch', '-a', m.BRANCH_FORMAT })
  local renamed = entry ('new name.txt', 'R ', 'renamed', true, 'old.txt')
  eq (m.diff_args (renamed), {
    'diff',
    '--no-color',
    '--no-ext-diff',
    '--src-prefix=a/',
    '--dst-prefix=b/',
    '--cached',
    '--',
    'new name.txt',
    'old.txt',
  })
  eq (m.diff_args (entry ('a.txt', ' M', 'modified', false))[6], '--')
  local show = m.show_args ('abc123')
  eq (show[#show], 'abc123')
  ok (show[#show - 2] == m.SHOW_FORMAT)
  eq (m.stage_args (renamed), { 'add', '-A', '--', 'new name.txt' })
  eq (
    m.unstage_args (renamed),
    { 'reset', '-q', '--', 'new name.txt', 'old.txt' }
  )
  eq (m.apply_args (false), { 'apply', '--cached', '-' })
  eq (m.apply_args (true), { 'apply', '--cached', '--reverse', '-' })
  eq (m.commit_args (false), { 'commit', '-F', '-' })
  eq (m.commit_args (true), { 'commit', '-F', '-', '--amend' })
end)

test ('discard_args fits the kind of change', function ()
  eq (
    m.discard_args (entry ('n.txt', '??', 'untracked', false)),
    { 'clean', '-f', '-q', '--', 'n.txt' }
  )
  eq (
    m.discard_args (entry ('i.txt', ' A', 'added', false)),
    { 'rm', '-f', '-q', '--', 'i.txt' }
  )
  eq (
    m.discard_args (entry ('a.txt', ' M', 'modified', false)),
    { 'restore', '--worktree', '--', 'a.txt' }
  )
  eq (m.discard_args (entry ('b.txt', 'UU', 'conflicted', false)), nil)
  eq (m.discard_args (entry ('c.txt', 'M ', 'modified', true)), nil)
end)

test ('push_args sets an upstream when there is none', function ()
  local tracked = m.parse_status ('## main...origin/main\n')
  eq (m.has_upstream (tracked), true)
  eq (m.push_args (tracked), { 'push' })
  local fresh = m.parse_status ('## main\n')
  eq (m.has_upstream (fresh), false)
  eq (m.push_args (fresh, 'upstream'), { 'push', '-u', 'upstream', 'main' })
  local args, why = m.push_args (fresh)
  eq (args, nil)
  eq (why, 'This repository has no remote to push to.')
  eq (
    m.push_args (m.parse_status (STATUS_GONE), 'origin'),
    { 'push', '-u', 'origin', 'gone' }
  )
  args, why = m.push_args (m.parse_status (STATUS_DETACHED), 'origin')
  eq (args, nil)
  eq (why, 'Switch to a branch before pushing.')
end)

test ('push_remote picks the remote a new branch goes to', function ()
  -- The branch's own setting comes first.
  eq (m.push_remote ('fork\n', 'origin\nfork\n'), 'fork')
  -- Then the only remote, whatever its name.
  eq (m.push_remote (nil, 'github\n'), 'github')
  eq (m.push_remote ('', 'github\r\n'), 'github')
  -- Then origin among several.
  eq (m.push_remote (nil, 'fork\norigin\n'), 'origin')
  local name, why = m.push_remote (nil, 'fork\nmine\n')
  eq (name, nil)
  ok (why and why:find ('several remotes', 1, true), why)
  name, why = m.push_remote (nil, '')
  eq (name, nil)
  eq (why, 'This repository has no remote to push to.')
end)

test ('remote_env keeps Git and ssh from asking on a terminal', function ()
  eq (
    m.remote_env (nil),
    { GIT_TERMINAL_PROMPT = '0', GIT_SSH_COMMAND = 'ssh -o BatchMode=yes' }
  )
  eq (
    m.remote_env ('\n'),
    { GIT_TERMINAL_PROMPT = '0', GIT_SSH_COMMAND = 'ssh -o BatchMode=yes' }
  )
  -- A user's own ssh command is left alone.
  eq (m.remote_env ('ssh -i ~/.ssh/work\n'), { GIT_TERMINAL_PROMPT = '0' })
end)

---------------------------------------------------------------------------------------------
-- HTML
---------------------------------------------------------------------------------------------

test ('diff_html draws files, hunks and lines', function ()
  local files = m.parse_diff (DIFF_A_STAGED)
  local html = m.diff_html (files, { buttons = true, label = 'Unstaged' })
  has (html, '<span class="git-file-path">a.txt</span>')
  has (html, '<span class="git-file-tag">Unstaged</span>')
  has (html, '<span class="git-stat-add">+2</span>')
  has (html, '@@ -15,6 +15,6 @@ line 14')
  has (html, 'data-item="hunk:1:1"')
  has (html, 'data-item="hunk:1:2"')
  eq (count (html, 'Stage Hunk'), 2)
  eq (count (html, '<div class="git-line '), 13)
  has (
    html,
    '<div class="git-line git-l-del"><span class="git-ln">18</span>'
      .. '<span class="git-ln"></span><span class="git-sign">−</span>'
      .. '<span class="git-code">line 18</span></div>'
  )
  local staged = m.diff_html (files, { buttons = true, staged = true })
  eq (count (staged, 'Unstage Hunk'), 2)
  lacks (staged, 'Stage Hunk')
  lacks (m.diff_html (files), 'git-hunk-btn')
end)

test (
  'diff_html notes binary, empty and renamed files, and has no buttons for conflicts',
  function ()
    has (m.diff_html (m.parse_diff (DIFF_BINARY)), 'Binary file')
    has (m.diff_html ({}), 'No changes.')
    has (m.diff_html ({}, { empty = 'Nothing here.' }), 'Nothing here.')
    local all = m.diff_html (m.parse_diff (DIFF_CACHED_ALL))
    has (all, 'Renamed with no changes inside.')
    has (all, '<span class="git-file-old">old.txt</span> → new name.txt')
    has (m.diff_html ({ m.untracked_diff ('e.txt', '') }), 'An empty file.')
    lacks (
      m.diff_html (m.parse_diff (DIFF_CONFLICT), { buttons = true }),
      'git-hunk-btn'
    )
  end
)

test ('diff_html stops after max_lines and says so', function ()
  local html = m.diff_html (m.parse_diff (DIFF_A_STAGED), { max_lines = 3 })
  eq (count (html, '<div class="git-line '), 3)
  has (html, 'Showing the first 3 of 13 lines.')
  eq (m.thousands (5000), '5,000')
  eq (m.thousands (123), '123')
  eq (m.thousands (1234567), '1,234,567')
end)

test ('diff_html escapes the text it shows', function ()
  local f = m.untracked_diff ('<a>&.txt', '<b>"hi"</b>\n')
  local html = m.diff_html ({ f })
  has (html, '&lt;a&gt;&amp;.txt')
  has (html, '&lt;b&gt;&quot;hi&quot;&lt;/b&gt;')
  lacks (html, '<b>')
end)

test ('changes_html draws both lists with their buttons', function ()
  local st = m.parse_status (STATUS_WORK)
  local html = m.changes_html (st, {
    selected = 'u:a.txt',
    icons = { stage = '<svg>plus</svg>' },
  })
  has (html, 'data-item="unstage-all"')
  has (html, 'data-item="stage-all"')
  has (html, 'data-item="open:s:a.txt"')
  has (html, 'data-item="open:u:a.txt"')
  has (html, 'data-item="unstage:s:a.txt"')
  has (html, 'data-item="stage:u:a.txt"')
  has (html, 'data-item="discard:u:a.txt"')
  has (html, '<svg>plus</svg>')
  eq (count (html, 'git-row active'), 1)
  has (
    html,
    '<span class="git-name">file.txt</span><span class="git-dir">deep/dir</span>'
  )
  has (html, '<span class="git-letter git-k-untracked">U</span>')
  has (html, 'title="old.txt → new name.txt (Renamed)"')
  lacks (m.changes_html (m.parse_status (STATUS_CONFLICT)), 'discard:')
  has (m.changes_html (m.parse_status ('## main\n')), 'No changes')
  has (
    m.changes_html (m.parse_status ('## main\n?? a&b.txt\n')),
    'open:u:a&amp;b.txt'
  )
end)

test ('parse_item reads the action, the list and the path', function ()
  eq ({ m.parse_item ('stage:u:src/a:b.txt') }, { 'stage', 'u', 'src/a:b.txt' })
  eq ({ m.parse_item ('open:s:a.txt') }, { 'open', 's', 'a.txt' })
  eq ({ m.parse_item ('stage-all') }, { 'stage-all' })
  eq ({ m.parse_item (nil) }, {})
end)

test ('log_html, commit_html, welcome_html and message_html', function ()
  local log = m.parse_log (LOG_FULL)
  local html = m.log_html (log, log[2].hash)
  has (html, 'data-item="' .. log[1].hash .. '"')
  has (html, '<span class="git-ref git-ref-branch git-ref-current">main</span>')
  has (html, '<span class="git-ref git-ref-tag">v1.0</span>')
  eq (count (html, 'git-commit active'), 1)
  has (m.log_html ({}), 'No commits yet')

  local merge = assert (m.parse_show (SHOW_MERGE).commit, 'a merge')
  local head = m.commit_html (merge)
  has (head, 'Merge branch &#39;topic&#39;')
  has (head, 'Ada &lt;ada@example.com&gt;')
  has (head, '2026-09-01 10:00 (4 weeks ago)')
  has (head, 'A merge of 41499c4 and eb62962.')
  local body =
    m.commit_html (assert (m.parse_show (SHOW_RENAME).commit, 'a commit'))
  has (body, 'It has two paragraphs.')

  local welcome = m.welcome_html ({ 'C:/work/repo' }, '<svg/>')
  has (welcome, 'data-item="open"')
  has (welcome, 'data-item="recent:C:/work/repo"')
  has (welcome, '<span class="git-recent-name">repo</span>')
  has (welcome, '<svg/>')
  lacks (m.welcome_html ({}), 'Recent')
  has (m.message_html ('A <b>', 'text'), 'A &lt;b&gt;')
end)

---------------------------------------------------------------------------------------------
-- Paths and messages
---------------------------------------------------------------------------------------------

test ('paths', function ()
  eq ({ m.split_path ('src/lib/a.txt') }, { 'a.txt', 'src/lib' })
  eq ({ m.split_path ('a.txt') }, { 'a.txt', '' })
  eq ({ m.split_path ('C:/work/repo') }, { 'repo', 'C:/work' })
  eq (m.join ('C:/r/', 'a/b.txt'), 'C:/r/a/b.txt')
  eq (m.join ('C:/r', 'b.txt'), 'C:/r/b.txt')
  eq (m.parent ('C:/r/a/b.txt'), 'C:/r/a')
  eq (m.native ('C:/r/a', 'windows'), 'C:\\r\\a')
  eq (m.native ('/home/r/a', 'linux'), '/home/r/a')
end)

test ('clone_name takes the folder name git clone would', function ()
  eq (m.clone_name ('https://github.com/owner/repo.git'), 'repo')
  eq (m.clone_name ('https://github.com/owner/repo/'), 'repo')
  eq (m.clone_name ('git@github.com:owner/tool.git'), 'tool')
  eq (m.clone_name ('git@host:tool'), 'tool')
  eq (m.clone_name ('  C:\\code\\lib.git  '), 'lib')
  eq (m.clone_name ('   '), '')
end)

test ('remember keeps the newest first, without repeats', function ()
  eq (m.remember ({ 'a', 'b', 'c' }, 'b', 10), { 'b', 'a', 'c' })
  eq (m.remember ({ 'a', 'b', 'c' }, 'd', 2), { 'd', 'a' })
  eq (m.remember ({}, 'x', 10), { 'x' })
end)

test ('error_text and summary pick what Git printed', function ()
  eq (
    m.error_text ({
      code = 128,
      stdout = '',
      stderr = 'fatal: not a git repository (or any of the parent directories): .git\n',
    }, nil),
    'fatal: not a git repository (or any of the parent directories): .git'
  )
  eq (
    m.error_text ({ code = 1, stdout = 'nothing to commit\n', stderr = '' }, nil),
    'nothing to commit'
  )
  eq (m.error_text (nil, 'could not start git'), 'could not start git')
  eq (m.error_text (nil, nil), 'Git failed with no message.')
  local long = m.error_text (
    { code = 1, stdout = '', stderr = string.rep ('x\n', 20) },
    nil
  )
  eq (count (long, 'x'), 8)
  has (long, '…')
  eq (
    m.summary ({ code = 0, stdout = 'Already up to date.\n', stderr = '' }),
    'Already up to date.'
  )
  eq (
    m.summary ({
      code = 0,
      stdout = '',
      stderr = 'To C:/origin.git\n   6258eaf..509d303  main -> main\n',
    }),
    'To C:/origin.git'
  )
  eq (m.summary ({ code = 0, stdout = '', stderr = '' }), '')
  eq (m.is_binary_error ('C:/a.png: stream did not contain valid UTF-8'), true)
  eq (m.is_binary_error ('C:/a.txt: The system cannot find the file'), false)
  eq (m.is_binary_error (nil), false)
end)

---------------------------------------------------------------------------------------------
-- Large repositories
---------------------------------------------------------------------------------------------

test (
  'parse_diff stops at max_lines and marks the hunk it stopped in',
  function ()
    local files, cut = m.parse_diff (DIFF_A_STAGED, 8)
    eq (cut, true)
    eq (#files, 1)
    eq (#files[1].hunks, 2)
    eq (#files[1].hunks[1].lines, 6)
    eq (#files[1].hunks[2].lines, 2)
    eq (files[1].hunks[1].partial, nil)
    eq (files[1].hunks[2].partial, true)
    -- A hunk read only in part cannot be staged, and draws no button.
    eq (m.hunk_patch (files[1], files[1].hunks[2]), nil)
    local html = m.diff_html (files, { buttons = true, cut = cut })
    eq (count (html, 'Stage Hunk'), 1)
    has (html, 'Showing the first 8 lines. The rest is left out.')
    local all, more = m.parse_diff (DIFF_A_STAGED, 13)
    eq ({ more, #all[1].hunks[2].lines }, { false, 7 })
    local show = m.parse_show (SHOW_RENAME, 1)
    eq (show.cut, true)
    ok (show.commit)
  end
)

test ('status_args follows status.showUntrackedFiles', function ()
  eq (m.status_args ('normal\n')[5], '--untracked-files=normal')
  eq (m.status_args ('no')[5], '--untracked-files=no')
  eq (m.status_args ('all')[5], '--untracked-files=all')
  eq (m.status_args ('true')[5], '--untracked-files=all')
  eq (m.status_args (nil)[5], '--untracked-files=all')
end)

test ('focus_gap waits longer after a slow status read', function ()
  eq (m.focus_gap (20), 1000)
  eq (m.focus_gap (400), 4000)
  eq (m.focus_gap (30000), 60000)
end)

test ('changes_html draws a long list up to its limit', function ()
  local text = { '## main' }
  for i = 1, 12 do
    text[#text + 1] = '?? f' .. i .. '.txt'
  end
  local st = m.parse_status (table.concat (text, '\n') .. '\n')
  local html = m.changes_html (st, { limit = 5 })
  eq (count (html, 'data-item="open:u:'), 5)
  has (html, 'data-item="show-all-u">Show all 12 files')
  local whole = m.changes_html (st, { limit = 5, all = { u = true } })
  eq (count (whole, 'data-item="open:u:'), 12)
  lacks (whole, 'show-all-u')
  eq ({ m.parse_item ('show-all-u') }, { 'show-all-u' })
end)
