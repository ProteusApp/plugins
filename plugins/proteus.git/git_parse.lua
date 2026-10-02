-- git_parse: reads what the git program prints, and builds the command lines, patches and
-- HTML the Git client needs. It calls no host function and draws nothing, so the tests reach
-- all of it.
--
-- Status comes from `git status -z`. `parse_status` also reads the output without `-z`, where
-- Git quotes a path that holds a space or an unusual character, and `unquote` reads it back.

---@alias Git.Kind 'modified'|'added'|'deleted'|'renamed'|'copied'|'typechange'|'untracked'|'conflicted'

---One changed file in the Staged list or the Changes list.
---@class Git.Entry
---@field path string The path from the repository root.
---@field old_path? string The path before a rename or a copy.
---@field code string The two status letters Git printed, such as `'M '` or `'??'`.
---@field kind Git.Kind
---@field letter string The letter the list shows, such as `'M'`.
---@field staged boolean

---What `git status --porcelain=v1 --branch` reports.
---@class Git.Status
---@field branch? string nil on a detached HEAD.
---@field upstream? string Such as `'origin/main'`.
---@field ahead integer Commits here that the upstream does not have.
---@field behind integer Commits on the upstream that are not here.
---@field gone boolean True when the upstream branch no longer exists.
---@field detached boolean
---@field initial boolean True in a repository with no commits yet.
---@field staged Git.Entry[]
---@field unstaged Git.Entry[] Unstaged, untracked and conflicted files.

---A branch or tag name on a commit in the history.
---@class Git.Ref
---@field name string Such as `'main'`, `'origin/main'` or `'v1.0'`.
---@field kind 'head'|'branch'|'remote'|'tag'
---@field current boolean True for the branch HEAD points at.

---One commit in the history list.
---@class Git.Commit
---@field hash string
---@field short string
---@field author string
---@field date string Relative, such as `'3 days ago'`.
---@field refs Git.Ref[]
---@field parents string[] Full hashes. Empty for the first commit.
---@field subject string

---@class Git.Branch
---@field name string Such as `'main'`, or `'origin/main'` for a remote branch.
---@field remote boolean
---@field current boolean
---@field upstream? string

---@alias Git.LineKind 'add'|'del'|'ctx'|'meta'

---One line of a diff hunk.
---@class Git.Line
---@field kind Git.LineKind `'meta'` is the `\ No newline at end of file` line.
---@field text string The line without its prefix and without a carriage return at the end.
---@field raw string The line exactly as Git printed it, for building patches.
---@field old? integer The line number on the old side.
---@field new? integer The line number on the new side.

---@class Git.Hunk
---@field header string The whole `@@` line.
---@field old_start integer
---@field old_count integer
---@field new_start integer
---@field new_count integer
---@field lines Git.Line[]
---@field partial? boolean True when reading stopped inside it, so it cannot be staged.

---One file in a diff.
---@class Git.FileDiff
---@field path string The path to show: the new one, or the old one for a deleted file.
---@field old_path? string nil for a new file.
---@field new_path? string nil for a deleted file.
---@field new_file boolean
---@field deleted boolean
---@field renamed boolean
---@field binary boolean
---@field combined boolean A conflict diff with a column for each side. It cannot be staged by hunk.
---@field old_mode? string
---@field new_mode? string
---@field header string[] The lines before the first hunk, which a patch needs.
---@field hunks Git.Hunk[]
---@field added integer
---@field removed integer

---The commit header `git show` prints before its diff.
---@class Git.CommitInfo
---@field hash string
---@field short string
---@field author string
---@field email string
---@field date string
---@field relative string
---@field parents string[]
---@field subject string
---@field body string The message after the subject line.

---@class Git.Show
---@field commit? Git.CommitInfo
---@field files Git.FileDiff[]
---@field cut boolean True when reading stopped at the line limit.

---@class Git.DiffOptions
---@field buttons? boolean Adds a Stage Hunk or Unstage Hunk button to each hunk.
---@field staged? boolean The buttons unstage instead of stage.
---@field max_lines? integer How many diff lines to draw. 5,000 when nil.
---@field label? string A tag beside each file path, such as `'Staged'`.
---@field empty? string The text to show when there is no file.
---@field cut? boolean True when `parse_diff` stopped at `max_lines`, so there is more.

---What the History view lists: every commit, the ones a search finds, or one file's.
---@class Git.LogQuery
---@field skip? integer Commits to leave out at the top, for the next page.
---@field search? string Text to find in commit messages, or `author:<name>` for the author.
---@field path? string A file, from the repository root, whose history to list.

---@class Git.LogOptions
---@field more? boolean Ends the list in a Load More row.
---@field graph? string[] SVG to draw at the start of each row, as `git_graph.rows_svg` gives.
---@field empty? string What to say when there is no commit.

---One entry of `git stash list`.
---@class Git.Stash
---@field ref string Such as `'stash@{0}'`.
---@field message string Such as `'On main: try the new parser'`.
---@field date string Relative, such as `'2 hours ago'`.

---A merge, rebase, cherry-pick or revert that stopped part way, for conflicts.
---@alias Git.Operation 'merge'|'rebase'|'cherry-pick'|'revert'

---@class Git.ListOptions
---@field selected? string The key of the selected row, such as `'u:src/a.txt'`.
---@field icons? table<string, string> SVG for the row buttons: `stage`, `unstage` and `discard`.
---@field limit? integer How many rows each list draws before a Show All row. `LIST_LIMIT` when nil.
---@field all? table<string, boolean> Lists to draw whole, by `'s'` or `'u'`.

---An item in the Switch Branch list.
---@class Git.Choice
---@field label string
---@field detail? string
---@field icon string
---@field action 'create'|'switch'|'track'
---@field name? string The branch to switch to.

---@class Git.ParseModule
local M = {}

local US = '\31'
local RS = '\30'
local NO_NEWLINE = 'No newline at end of file'

M.LOG_FORMAT = '--format=%H%x1f%h%x1f%an%x1f%ar%x1f%D%x1f%P%x1f%s%x1e'
M.SHOW_FORMAT = '--format=%H%x1f%h%x1f%an%x1f%ae%x1f%ad%x1f%ar%x1f%P%x1f%B%x1e'
M.BRANCH_FORMAT = '--format=%(HEAD)%09%(refname)%09%(upstream:short)'
M.STASH_FORMAT = '--format=%gd%x1f%gs%x1f%cr'

-- How many rows each list in the Changes view draws until Show All is clicked. A repository
-- with thousands of new files stays quick to draw.
M.LIST_LIMIT = 500
-- How many diff lines are read and drawn.
M.MAX_LINES = 5000

---@type table<string, Git.Kind>
local KIND = {
  M = 'modified',
  A = 'added',
  D = 'deleted',
  R = 'renamed',
  C = 'copied',
  T = 'typechange',
}

---@type table<Git.Kind, string>
local LETTER = {
  modified = 'M',
  added = 'A',
  deleted = 'D',
  renamed = 'R',
  copied = 'C',
  typechange = 'T',
  untracked = 'U',
  conflicted = '!',
}

---@type table<Git.Kind, string>
local KIND_TITLE = {
  modified = 'Modified',
  added = 'Added',
  deleted = 'Deleted',
  renamed = 'Renamed',
  copied = 'Copied',
  typechange = 'Type changed',
  untracked = 'Untracked',
  conflicted = 'Conflict',
}

-- Both sides of a merge touched these files. Git lists each one once.
---@type table<string, boolean>
local CONFLICT = {
  DD = true,
  AU = true,
  UD = true,
  UA = true,
  DU = true,
  AA = true,
  UU = true,
}

---@type table<string, string>
local C_ESCAPES = {
  a = '\a',
  b = '\b',
  f = '\f',
  n = '\n',
  r = '\r',
  t = '\t',
  v = '\v',
  ['\\'] = '\\',
  ['"'] = '"',
}

---@type table<string, string>
local HTML_ESCAPES = {
  ['&'] = '&amp;',
  ['<'] = '&lt;',
  ['>'] = '&gt;',
  ['"'] = '&quot;',
  ["'"] = '&#39;',
}

---------------------------------------------------------------------------------------------
-- Small text helpers
---------------------------------------------------------------------------------------------

---Splits on one plain character and keeps empty fields.
---@param s string
---@param sep string
---@return string[]
local function split (s, sep)
  local out = {} ---@type string[]
  local start = 1
  while true do
    local i = s:find (sep, start, true)
    if not i then
      out[#out + 1] = s:sub (start)
      return out
    end
    out[#out + 1] = s:sub (start, i - 1)
    start = i + 1
  end
end

---Splits text into lines. A newline at the very end does not start another line.
---@param text string
---@return string[]
local function lines_of (text)
  local out = split (text, '\n')
  if out[#out] == '' then
    out[#out] = nil
  end
  return out
end

---@param s string
---@return string
local function trim (s)
  local out = s:gsub ('^%s+', ''):gsub ('%s+$', '')
  return out
end

---@param s string
---@return string
local function strip_cr (s)
  if s:sub (-1) == '\r' then
    return s:sub (1, -2)
  end
  return s
end

---@param s string?
---@return integer
local function int (s)
  return math.floor (tonumber (s) or 0)
end

---Escapes text for HTML, attribute values included.
---@param s any
---@return string
function M.escape (s)
  local out = tostring (s):gsub ('[&<>"\']', HTML_ESCAPES)
  return out
end

---Writes 5000 as `'5,000'`.
---@param n integer
---@return string
function M.thousands (n)
  local s = tostring (n):reverse ():gsub ('(%d%d%d)', '%1,'):reverse ()
  local out = s:gsub ('^,', '')
  return out
end

---------------------------------------------------------------------------------------------
-- Quoted paths
---------------------------------------------------------------------------------------------

---Reads the inside of a C-style quoted string, as Git writes an unusual path.
---@param inner string
---@return string
local function unescape (inner)
  local out = {} ---@type string[]
  local i = 1
  while i <= #inner do
    local c = inner:sub (i, i)
    if c ~= '\\' then
      out[#out + 1] = c
      i = i + 1
    else
      local oct = inner:match ('^[0-7][0-7][0-7]', i + 1)
      if oct then
        out[#out + 1] = string.char (math.floor (tonumber (oct, 8) or 0))
        i = i + 4
      else
        local e = inner:sub (i + 1, i + 1)
        out[#out + 1] = C_ESCAPES[e] or e
        i = i + 2
      end
    end
  end
  return table.concat (out)
end

---Reads a path Git may have quoted, such as `"src/my file.txt"` or `"caf\303\251.txt"`.
---A path without quotes comes back as it is.
---@param s string
---@return string
function M.unquote (s)
  if #s < 2 or s:sub (1, 1) ~= '"' or s:sub (-1) ~= '"' then
    return s
  end
  return unescape (s:sub (2, -2))
end

---Reads a quoted string that starts at `i`. Returns its value and the position after it.
---@param s string
---@param i integer
---@return string value
---@return integer next
local function read_quoted (s, i)
  local j = i + 1
  while j <= #s do
    local c = s:sub (j, j)
    if c == '\\' then
      j = j + 2
    elseif c == '"' then
      return unescape (s:sub (i + 1, j - 1)), j + 1
    else
      j = j + 1
    end
  end
  return unescape (s:sub (i + 1)), #s + 1
end

---Quotes a path the way Git does when it holds a quote, a backslash or a control character.
---@param path string
---@return string
local function quote_path (path)
  if not path:find ('[%c"\\]') then
    return path
  end
  local out = path:gsub ('[%c"\\]', function (c)
    for k, v in pairs (C_ESCAPES) do
      if v == c then
        return '\\' .. k
      end
    end
    return string.format ('\\%03o', c:byte ())
  end)
  return '"' .. out .. '"'
end

---------------------------------------------------------------------------------------------
-- git status
---------------------------------------------------------------------------------------------

---@param kind Git.Kind
---@param code string
---@param path string
---@param old_path string?
---@param staged boolean
---@return Git.Entry
local function entry (kind, code, path, old_path, staged)
  return {
    path = path,
    old_path = old_path,
    code = code,
    kind = kind,
    letter = LETTER[kind],
    staged = staged,
  }
end

---Adds one status line to the right list, or to both for a file with staged and unstaged
---changes.
---@param st Git.Status
---@param code string
---@param path string
---@param old string?
local function add_entry (st, code, path, old)
  if code == '!!' then
    return
  end
  if code == '??' then
    st.unstaged[#st.unstaged + 1] = entry ('untracked', code, path, nil, false)
    return
  end
  if CONFLICT[code] then
    st.unstaged[#st.unstaged + 1] = entry ('conflicted', code, path, nil, false)
    return
  end
  local x, y = code:sub (1, 1), code:sub (2, 2)
  if x ~= ' ' then
    local moved = (x == 'R' or x == 'C') and old or nil
    st.staged[#st.staged + 1] =
      entry (KIND[x] or 'modified', code, path, moved, true)
  end
  if y ~= ' ' then
    local moved = (y == 'R' or y == 'C') and old or nil
    st.unstaged[#st.unstaged + 1] =
      entry (KIND[y] or 'modified', code, path, moved, false)
  end
end

---Reads the `## ` line: the branch, its upstream, and how far apart they are.
---@param st Git.Status
---@param line string The text after `## `.
local function read_branch (st, line)
  local s = line
  local rest = s:match ('^No commits yet on (.*)$')
    or s:match ('^Initial commit on (.*)$')
  if rest then
    st.initial = true
    s = rest
  end
  if s:find ('^HEAD %(no branch%)') then
    st.detached = true
    return
  end
  local info = s:match (' %[([^%]]*)%]$')
  if info then
    s = s:sub (1, #s - #info - 3)
    st.gone = info == 'gone'
    st.ahead = int (info:match ('ahead (%d+)'))
    st.behind = int (info:match ('behind (%d+)'))
  end
  local b, u = s:match ('^(.-)%.%.%.(.+)$')
  if b then
    st.branch, st.upstream = b, u
  else
    st.branch = s
  end
end

---Reads one path, or two for a rename (`old -> new`). Either may be quoted.
---@param line string
---@param i integer Where the first path starts.
---@param pair boolean True when the status letters say a second path may follow.
---@return string first
---@return string? second
local function read_paths (line, i, pair)
  local first, j ---@type string, integer
  if line:sub (i, i) == '"' then
    first, j = read_quoted (line, i)
  else
    local arrow = pair and line:find (' -> ', i, true)
    if not arrow then
      return line:sub (i), nil
    end
    first, j = line:sub (i, arrow - 1), arrow
  end
  if pair and line:sub (j, j + 3) == ' -> ' then
    local k = j + 4
    if line:sub (k, k) == '"' then
      local second = read_quoted (line, k)
      return first, second
    end
    return first, line:sub (k)
  end
  return first, nil
end

---Reads `git status --porcelain=v1 --branch` output, with or without `-z`.
---@param text string
---@return Git.Status
function M.parse_status (text)
  ---@type Git.Status
  local st = {
    ahead = 0,
    behind = 0,
    gone = false,
    detached = false,
    initial = false,
    staged = {},
    unstaged = {},
  }
  if text:find ('\0', 1, true) then
    -- With -z a rename puts the new path in the entry and the old path in the next field.
    local fields = split (text, '\0')
    local i = 1
    while i <= #fields do
      local f = fields[i]
      if f:sub (1, 3) == '## ' then
        read_branch (st, f:sub (4))
      elseif #f > 3 then
        local code = f:sub (1, 2)
        local old = nil ---@type string?
        if code:find ('[RC]') then
          i = i + 1
          old = fields[i]
        end
        add_entry (st, code, f:sub (4), old)
      end
      i = i + 1
    end
    return st
  end
  for _, raw in ipairs (lines_of (text)) do
    local line = strip_cr (raw)
    if line:sub (1, 3) == '## ' then
      read_branch (st, line:sub (4))
    elseif #line > 3 then
      local code = line:sub (1, 2)
      local first, second = read_paths (line, 4, code:find ('[RC]') ~= nil)
      if second then
        add_entry (st, code, second, first)
      else
        add_entry (st, code, first, nil)
      end
    end
  end
  return st
end

---The number of files with changes, counting a file in both lists once.
---@param st Git.Status
---@return integer
function M.change_count (st)
  local seen = {} ---@type table<string, boolean>
  local n = 0
  for _, list in ipairs ({ st.staged, st.unstaged }) do
    for _, e in ipairs (list) do
      if not seen[e.path] then
        seen[e.path] = true
        n = n + 1
      end
    end
  end
  return n
end

---Such as `'↑2 ↓1'`: commits to push and commits to pull. Empty when both are zero.
---@param st Git.Status
---@return string
function M.sync_text (st)
  if st.gone then
    return 'upstream gone'
  end
  local parts = {} ---@type string[]
  if st.ahead > 0 then
    parts[#parts + 1] = '↑' .. st.ahead
  end
  if st.behind > 0 then
    parts[#parts + 1] = '↓' .. st.behind
  end
  return table.concat (parts, ' ')
end

---The branch name, or a word for a detached HEAD.
---@param st Git.Status
---@return string
function M.branch_text (st)
  if st.detached or not st.branch then
    return 'detached HEAD'
  end
  return st.branch
end

---Such as `'3 changes'`.
---@param n integer
---@return string
function M.count_text (n)
  if n == 0 then
    return 'No changes'
  end
  return n .. (n == 1 and ' change' or ' changes')
end

---Finds a file in the Staged list (`'s'`) or the Changes list (`'u'`).
---@param st Git.Status?
---@param group string
---@param path string
---@return Git.Entry?
function M.find_entry (st, group, path)
  if not st then
    return nil
  end
  for _, e in ipairs (group == 's' and st.staged or st.unstaged) do
    if e.path == path then
      return e
    end
  end
  return nil
end

---The row to keep selected after a refresh: the same file in the same list, or the same file
---in the other list after it was staged or unstaged whole.
---@param st Git.Status
---@param group string
---@param path string
---@return Git.Entry?
function M.reselect (st, group, path)
  return M.find_entry (st, group, path)
    or M.find_entry (st, group == 's' and 'u' or 's', path)
end

---------------------------------------------------------------------------------------------
-- git log and git branch
---------------------------------------------------------------------------------------------

---@param name string
---@param current boolean
---@return Git.Ref?
local function ref_of (name, current)
  local tag = name:match ('^tag: (.+)$') ---@type string?
  if tag then
    local short = tag:gsub ('^refs/tags/', '')
    return { name = short, kind = 'tag', current = false }
  end
  if name:find ('/HEAD$') or name:find ('^refs/stash') then
    return nil
  end
  local remote = name:match ('^refs/remotes/(.+)$')
  if remote then
    return { name = remote, kind = 'remote', current = false }
  end
  local branch = name:match ('^refs/heads/(.+)$') or name
  return { name = branch, kind = 'branch', current = current }
end

---Reads `%D`, such as `HEAD -> refs/heads/main, refs/remotes/origin/main, tag: refs/tags/v1`.
---Short names without `refs/` work too, but a remote branch then reads as a branch.
---@param text string
---@return Git.Ref[]
local function read_refs (text)
  local refs = {} ---@type Git.Ref[]
  for _, part in ipairs (split (text, ',')) do
    local item = trim (part)
    local target = item:match ('^HEAD %-> (.+)$')
    local ref = nil ---@type Git.Ref?
    if target then
      ref = ref_of (target, true)
    elseif item == 'HEAD' then
      ref = { name = 'HEAD', kind = 'head', current = true }
    elseif item ~= '' then
      ref = ref_of (item, false)
    end
    if ref then
      refs[#refs + 1] = ref
    end
  end
  return refs
end

---Reads `git log` output in `LOG_FORMAT`. Output without the parents field, as before 1.2.0,
---reads too, with no parents.
---@param text string
---@return Git.Commit[]
function M.parse_log (text)
  local out = {} ---@type Git.Commit[]
  for _, chunk in ipairs (split (text, RS)) do
    local rec = chunk:gsub ('^%s+', '')
    local f = split (rec, US)
    if #f >= 6 then
      local parents = {} ---@type string[]
      local first = 6
      if #f >= 7 then
        for p in f[6]:gmatch ('%x+') do
          parents[#parents + 1] = p
        end
        first = 7
      end
      out[#out + 1] = {
        hash = f[1],
        short = f[2],
        author = f[3],
        date = f[4],
        refs = read_refs (f[5]),
        parents = parents,
        subject = table.concat (f, US, first),
      }
    end
  end
  return out
end

---Reads `git branch -a` output in `BRANCH_FORMAT`: local branches first, then remote ones.
---Full names (`refs/heads/x`) tell the two apart. Short names count as local.
---@param text string
---@return Git.Branch[]
function M.parse_branches (text)
  local locals = {} ---@type Git.Branch[]
  local remotes = {} ---@type Git.Branch[]
  for _, raw in ipairs (lines_of (text)) do
    ---@type string?, string?, string?
    local head, name, upstream = strip_cr (raw):match ('^(.)\t([^\t]*)\t?(.*)$')
    -- A detached HEAD shows as `(HEAD detached at abc1234)`.
    if name and name ~= '' and name:sub (1, 1) ~= '(' then
      local short = name:match ('^refs/heads/(.+)$')
      local remote = false
      if not short then
        short = name:match ('^refs/remotes/(.+)$')
          or name:match ('^remotes/(.+)$')
        remote = short ~= nil
        short = short or name
      end
      if not short:find ('/HEAD$') then
        ---@type Git.Branch
        local b = {
          name = short,
          remote = remote,
          current = head == '*',
          upstream = upstream ~= '' and upstream or nil,
        }
        if remote then
          remotes[#remotes + 1] = b
        else
          locals[#locals + 1] = b
        end
      end
    end
  end
  for _, b in ipairs (remotes) do
    locals[#locals + 1] = b
  end
  return locals
end

---The Switch Branch list: a way to make a new branch, then every branch.
---@param branches Git.Branch[]
---@return Git.Choice[]
function M.branch_choices (branches)
  ---@type Git.Choice[]
  local out = {
    { label = 'Create new branch…', icon = 'plus', action = 'create' },
  }
  for _, b in ipairs (branches) do
    if b.remote then
      out[#out + 1] = {
        label = b.name,
        detail = 'remote',
        icon = 'cloud',
        action = 'track',
        name = b.name,
      }
    else
      out[#out + 1] = {
        label = b.name,
        detail = b.current and 'current branch' or b.upstream,
        icon = b.current and 'check' or 'git-branch',
        action = 'switch',
        name = b.name,
      }
    end
  end
  return out
end

---The command that switches to a picked branch. A remote branch with a local branch of the
---same name switches to the local one, since `--track` would refuse to make it again.
---@param choice Git.Choice
---@param branches Git.Branch[]
---@return string[]?
function M.switch_args (choice, branches)
  local name = choice.name
  if not name then
    return nil
  end
  if choice.action == 'switch' then
    return { 'switch', name }
  end
  if choice.action == 'track' then
    local short = name:match ('^[^/]+/(.+)$')
    for _, b in ipairs (branches) do
      if not b.remote and b.name == short then
        return { 'switch', short }
      end
    end
    return { 'switch', '--track', name }
  end
  return nil
end

---A reason a new branch name is not allowed, or nil when it is fine.
---@param name string
---@return string?
function M.check_branch_name (name)
  if name == '' then
    return 'Type a name for the branch.'
  end
  if name:find ('[%s~^:?*%[\\%c]') then
    return 'A branch name cannot hold spaces or any of ~ ^ : ? * [ \\'
  end
  if
    name:find ('%.%.')
    or name:find ('//')
    or name:find ('@{', 1, true)
    or name == '@'
  then
    return 'A branch name cannot hold .., // or @{'
  end
  if
    name:find ('^[%-/.]')
    or name:find ('[/.]$')
    or name:find ('%.lock$')
    or name:find ('/%.')
  then
    return 'A branch name cannot start with - / or . or end with / . or .lock'
  end
  return nil
end

---------------------------------------------------------------------------------------------
-- Command lines
---------------------------------------------------------------------------------------------

---What every git command starts with. With `--literal-pathspecs` Git reads each path as a
---file name, not a pattern, so discarding a file called `*.log` never deletes the other `.log`
---files, and staging `f[1].txt` never stages `f1.txt`.
---@return string[]
function M.base_args ()
  return { '--literal-pathspecs', '-c', 'core.quotepath=false' }
end

---The variables a command that reaches a remote runs with. The app has no terminal, so a
---password or passphrase prompt would wait for ever: Git and ssh fail at once instead, and
---say why. A `core.sshCommand` of the user's own is left as it is.
---@param ssh_command? string What `git config core.sshCommand` printed.
---@return table<string, string>
function M.remote_env (ssh_command)
  local env = { GIT_TERMINAL_PROMPT = '0' } ---@type table<string, string>
  if not ssh_command or trim (ssh_command) == '' then
    env.GIT_SSH_COMMAND = 'ssh -o BatchMode=yes'
  end
  return env
end

---Zero bytes separate the entries, so paths come back exactly as they are, with no quoting.
---New files are listed one by one, so each can be staged and shown, unless the repository's
---`status.showUntrackedFiles` setting asks for `normal` (a new folder is one row) or `no`.
---@param untracked? string What `git config status.showUntrackedFiles` printed.
---@return string[]
function M.status_args (untracked)
  local mode = untracked and trim (untracked) or ''
  if mode ~= 'no' and mode ~= 'normal' then
    mode = 'all'
  end
  return {
    'status',
    '--porcelain=v1',
    '-z',
    '--branch',
    '--untracked-files=' .. mode,
  }
end

---How long to wait after a status read before the window's focus reads it again. A read that
---took long, in a large repository, waits ten times as long, so switching windows does not
---keep Git busy.
---@param took number Milliseconds the last read took.
---@return number
function M.focus_gap (took)
  return math.min (60000, math.max (1000, took * 10))
end

---What a search box's text adds to `git log`. Plain text is found in the message, and
---`author:<name>` in the author's name or email. Both ignore case and read the text as it is,
---not as a pattern.
---@param text string
---@return string[]
function M.search_args (text)
  local query = trim (text)
  if query == '' then
    return {}
  end
  local author = query:match ('^author:%s*(.+)$')
  if author then
    return { '--regexp-ignore-case', '--fixed-strings', '--author=' .. author }
  end
  return { '--regexp-ignore-case', '--fixed-strings', '--grep=' .. query }
end

---`n` commits for the History view. They come newest first, but never before a commit that
---came after them, so the graph can draw them. A file's history follows it across renames.
---@param n integer
---@param query? Git.LogQuery
---@return string[]
function M.log_args (n, query)
  local q = query or {}
  local args = {
    'log',
    '-n',
    tostring (n),
    '--date-order',
    '--decorate=full',
    M.LOG_FORMAT,
  }
  if q.skip and q.skip > 0 then
    args[#args + 1] = '--skip=' .. q.skip
  end
  for _, a in ipairs (M.search_args (q.search or '')) do
    args[#args + 1] = a
  end
  if q.path then
    args[#args + 1] = '--follow'
    args[#args + 1] = '--'
    args[#args + 1] = q.path
  end
  return args
end

---Adds a page of commits to the list, leaving out any it has already, as when a commit
---arrived between the two pages.
---@param list Git.Commit[]
---@param page Git.Commit[]
---@return Git.Commit[]
function M.append_commits (list, page)
  local seen = {} ---@type table<string, boolean>
  local out = {} ---@type Git.Commit[]
  for _, c in ipairs (list) do
    seen[c.hash] = true
    out[#out + 1] = c
  end
  for _, c in ipairs (page) do
    if not seen[c.hash] then
      seen[c.hash] = true
      out[#out + 1] = c
    end
  end
  return out
end

---@return string[]
function M.branch_args ()
  return { 'branch', '-a', M.BRANCH_FORMAT }
end

---The diff of one changed file. The fixed prefixes keep a user's `diff.noprefix` setting from
---changing the output, since `git apply` needs `a/` and `b/`.
---@param e Git.Entry
---@return string[]
function M.diff_args (e)
  local args = {
    'diff',
    '--no-color',
    '--no-ext-diff',
    '--src-prefix=a/',
    '--dst-prefix=b/',
  }
  if e.staged then
    args[#args + 1] = '--cached'
  end
  args[#args + 1] = '--'
  args[#args + 1] = e.path
  if e.old_path then
    args[#args + 1] = e.old_path
  end
  return args
end

---A commit's header and diff. A merge shows its changes against the first parent.
---@param hash string
---@return string[]
function M.show_args (hash)
  return {
    'show',
    '--no-color',
    '--no-ext-diff',
    '--src-prefix=a/',
    '--dst-prefix=b/',
    '-m',
    '--first-parent',
    '--date=format-local:%Y-%m-%d %H:%M',
    M.SHOW_FORMAT,
    '--patch',
    hash,
  }
end

---@param e Git.Entry
---@return string[]
function M.stage_args (e)
  return { 'add', '-A', '--', e.path }
end

---Unstages a file. `git reset` also works in a repository with no commits yet.
---@param e Git.Entry
---@return string[]
function M.unstage_args (e)
  local args = { 'reset', '-q', '--', e.path }
  if e.old_path then
    args[#args + 1] = e.old_path
  end
  return args
end

---Throws away a file's unstaged changes. An untracked file, or one added with `git add -N`,
---is deleted. A conflict has no clean version to go back to, so it gives nil.
---@param e Git.Entry
---@return string[]?
function M.discard_args (e)
  if e.staged or e.kind == 'conflicted' then
    return nil
  end
  if e.kind == 'untracked' then
    return { 'clean', '-f', '-q', '--', e.path }
  end
  if e.kind == 'added' then
    return { 'rm', '-f', '-q', '--', e.path }
  end
  return { 'restore', '--worktree', '--', e.path }
end

---@param reverse boolean True to unstage the patch.
---@return string[]
function M.apply_args (reverse)
  local args = { 'apply', '--cached' }
  if reverse then
    args[#args + 1] = '--reverse'
  end
  args[#args + 1] = '-'
  return args
end

---@param amend boolean
---@return string[]
function M.commit_args (amend)
  local args = { 'commit', '-F', '-' }
  if amend then
    args[#args + 1] = '--amend'
  end
  return args
end

---True when the current branch has an upstream to push to, so a plain `git push` works.
---@param st Git.Status
---@return boolean
function M.has_upstream (st)
  return st.upstream ~= nil and not st.gone
end

---The remote a branch with no upstream is pushed to: the one `branch.<name>.remote` names,
---or the only remote there is, or `origin` among several. nil and a message when none fits.
---@param configured? string What `git config branch.<name>.remote` printed.
---@param remotes string What `git remote` printed, one name a line.
---@return string? remote
---@return string? why
function M.push_remote (configured, remotes)
  local named = configured and trim (configured) or ''
  if named ~= '' and named ~= '.' then
    return named, nil
  end
  local names = {} ---@type string[]
  for _, line in ipairs (lines_of (remotes)) do
    local name = trim (strip_cr (line))
    if name ~= '' then
      names[#names + 1] = name
    end
  end
  if #names == 1 then
    return names[1], nil
  end
  for _, name in ipairs (names) do
    if name == 'origin' then
      return name, nil
    end
  end
  if #names == 0 then
    return nil, 'This repository has no remote to push to.'
  end
  return nil,
    'This branch has no upstream, and the repository has several remotes. Set one with git push -u <remote> <branch>.'
end

---Pushes the current branch. One with no upstream yet gets it on `remote`, which
---`push_remote` picks.
---@param st Git.Status
---@param remote? string
---@return string[]? args
---@return string? why A message when it cannot push.
function M.push_args (st, remote)
  if st.detached or not st.branch then
    return nil, 'Switch to a branch before pushing.'
  end
  if M.has_upstream (st) then
    return { 'push' }, nil
  end
  if not remote then
    return nil, 'This repository has no remote to push to.'
  end
  return { 'push', '-u', remote, st.branch }, nil
end

---------------------------------------------------------------------------------------------
-- Merge, rebase, cherry-pick, revert and reset
---------------------------------------------------------------------------------------------

---@type table<Git.Operation, string>
local OPERATION_TEXT = {
  merge = 'Merging',
  rebase = 'Rebasing',
  ['cherry-pick'] = 'Cherry-picking',
  revert = 'Reverting',
}

---The operation that stopped part way, read from the names in the `.git` folder, as
---`app.fs.list_dir` gives them: folders end in `/`.
---@param names string[]
---@return Git.Operation?
function M.operation (names)
  local has = {} ---@type table<string, boolean>
  for _, n in ipairs (names) do
    has[(n:gsub ('/$', ''))] = true
  end
  if has['rebase-merge'] or has['rebase-apply'] then
    return 'rebase'
  elseif has.MERGE_HEAD then
    return 'merge'
  elseif has.CHERRY_PICK_HEAD then
    return 'cherry-pick'
  elseif has.REVERT_HEAD then
    return 'revert'
  end
  return nil
end

---Such as `'Merging. Resolve the 2 conflicts and stage them, then continue.'`.
---@param op Git.Operation
---@param conflicts integer
---@return string
function M.operation_text (op, conflicts)
  local text = OPERATION_TEXT[op] or op
  if conflicts > 0 then
    return text
      .. '. Resolve '
      .. (conflicts == 1 and 'the conflict and stage it' or ('the ' .. conflicts .. ' conflicts and stage them'))
      .. ', then continue.'
  end
  return text .. '. Continue to finish it.'
end

---How many files have conflicts.
---@param st Git.Status
---@return integer
function M.conflict_count (st)
  local n = 0
  for _, e in ipairs (st.unstaged) do
    if e.kind == 'conflicted' then
      n = n + 1
    end
  end
  return n
end

---True when a merge, rebase, cherry-pick or revert stopped at conflicts, rather than failing.
---@param res Proteus.RunResult?
---@return boolean
function M.stopped_at_conflict (res)
  if not res then
    return false
  end
  local text = (res.stdout or '') .. '\n' .. (res.stderr or '')
  return text:find ('CONFLICT', 1, true) ~= nil
    or text:find ('could not apply', 1, true) ~= nil
end

---The variables a merge, rebase, cherry-pick or revert runs with: the app has no terminal for
---an editor, so Git takes the message it wrote itself.
---@return table<string, string>
function M.operation_env ()
  return { GIT_EDITOR = 'true' }
end

---Finishes an operation once its conflicts are resolved. A merge commits with the message in
---the commit box when there is one, read from stdin, or else with Git's own.
---@param op Git.Operation
---@param own_message boolean
---@return string[]
function M.continue_args (op, own_message)
  if op == 'merge' then
    if own_message then
      return { 'commit', '-F', '-' }
    end
    return { 'commit', '--no-edit' }
  end
  return { op, '--continue' }
end

---Gives up an operation and goes back to where it started.
---@param op Git.Operation
---@return string[]
function M.abort_args (op)
  return { op, '--abort' }
end

---Merges a branch into the current one.
---@param branch string
---@return string[]
function M.merge_args (branch)
  return { 'merge', '--no-edit', branch }
end

---Replays the current branch's own commits on top of another branch.
---@param branch string
---@return string[]
function M.rebase_args (branch)
  return { 'rebase', branch }
end

---Copies a commit onto the current branch. A merge commit copies its changes against its
---first parent.
---@param hash string
---@param parents integer
---@return string[]
function M.cherry_pick_args (hash, parents)
  if parents > 1 then
    return { 'cherry-pick', '-m', '1', hash }
  end
  return { 'cherry-pick', hash }
end

---Makes a commit that undoes a commit. A merge commit is undone against its first parent.
---@param hash string
---@param parents integer
---@return string[]
function M.revert_args (hash, parents)
  if parents > 1 then
    return { 'revert', '--no-edit', '-m', '1', hash }
  end
  return { 'revert', '--no-edit', hash }
end

---Moves the current branch to a commit. `soft` keeps the changes since then staged, `mixed`
---keeps them unstaged, and `hard` throws them away with every uncommitted change.
---@param mode 'soft'|'mixed'|'hard'
---@param hash string
---@return string[]
function M.reset_args (mode, hash)
  return { 'reset', '--' .. mode, hash }
end

---Deletes a local branch. Without `force`, Git refuses one whose commits are not merged.
---@param name string
---@param force boolean
---@return string[]
function M.delete_branch_args (name, force)
  return { 'branch', force and '-D' or '-d', name }
end

---@param old string
---@param new string
---@return string[]
function M.rename_branch_args (old, new)
  return { 'branch', '-m', old, new }
end

---True when Git refused to delete a branch because its commits are merged nowhere.
---@param res Proteus.RunResult?
---@return boolean
function M.not_merged (res)
  return res ~= nil
    and (res.stderr or ''):find ('not fully merged', 1, true) ~= nil
end

---Branches to merge or rebase onto: every branch but the current one, local ones first.
---@param branches Git.Branch[]
---@return Git.Branch[]
function M.other_branches (branches)
  local out = {} ---@type Git.Branch[]
  for _, b in ipairs (branches) do
    if not b.current then
      out[#out + 1] = b
    end
  end
  return out
end

---------------------------------------------------------------------------------------------
-- Conflicts
---------------------------------------------------------------------------------------------

---The commands that resolve a conflict with one side's version: `ours` is the current
---branch's (HEAD), and `theirs` the one coming in. A side that deleted the file deletes it.
---Each list runs in turn.
---@param e Git.Entry
---@param side 'ours'|'theirs'
---@return string[][]
function M.resolve_args (e, side)
  local letter = side == 'ours' and e.code:sub (1, 1) or e.code:sub (2, 2)
  if letter == 'D' then
    return { { 'rm', '-q', '--', e.path } }
  end
  return {
    { 'checkout', '--' .. side, '--', e.path },
    { 'add', '--', e.path },
  }
end

---Marks a conflict resolved by staging the file as it is, or its deletion when it is gone.
---@param e Git.Entry
---@return string[]
function M.mark_resolved_args (e)
  return { 'add', '-A', '--', e.path }
end

---True when text still holds a conflict marker line Git wrote.
---@param text string
---@return boolean
function M.has_markers (text)
  local at = 1
  while true do
    local i = text:find ('<<<<<<< ', at, true)
    if not i then
      return false
    end
    if i == 1 or text:sub (i - 1, i - 1) == '\n' then
      return text:find ('\n=======', i, true) ~= nil
        and text:find ('\n>>>>>>> ', i, true) ~= nil
    end
    at = i + 1
  end
end

---What each side of a conflict did, in words, such as `'Both changed it'`.
---@type table<string, string>
local CONFLICT_TEXT = {
  UU = 'Both sides changed this file.',
  AA = 'Both sides added this file.',
  DD = 'Both sides deleted this file.',
  AU = 'The current branch added this file, and the incoming side changed it.',
  UA = 'The incoming side added this file, and the current branch changed it.',
  DU = 'The current branch deleted this file, and the incoming side changed it.',
  UD = 'The incoming side deleted this file, and the current branch changed it.',
}

---The bar above a conflicted file's diff, with a button for each way to resolve it. Each
---carries `data-item="conflict:<ours|theirs|resolved|open>"`.
---@param e Git.Entry
---@return string
function M.conflict_html (e)
  ---@param action string
  ---@param label string
  ---@param title string
  ---@param primary? boolean
  ---@return string
  local function button (action, label, title, primary)
    return '<button class="ui-button'
      .. (primary and ' primary' or '')
      .. '" data-item="conflict:'
      .. action
      .. '" title="'
      .. M.escape (title)
      .. '">'
      .. M.escape (label)
      .. '</button>'
  end
  local out = {
    '<div class="git-conflict"><div class="git-conflict-text">',
    M.escape (CONFLICT_TEXT[e.code] or 'This file has a conflict.'),
    ' Edit it to keep what you want, then mark it resolved, or take one side whole.</div>',
    '<div class="git-conflict-btns">',
    button (
      'ours',
      e.code:sub (1, 1) == 'D' and 'Accept Current (delete)' or 'Accept Current',
      "Keep the current branch's version"
    ),
    button (
      'theirs',
      e.code:sub (2, 2) == 'D' and 'Accept Incoming (delete)'
        or 'Accept Incoming',
      'Take the version coming in'
    ),
    button ('resolved', 'Mark Resolved', 'Stage the file as it is now', true),
  }
  if e.code ~= 'DD' and e.code:sub (1, 1) ~= 'D' then
    out[#out + 1] = button ('open', 'Open File', 'Edit the file')
  end
  out[#out + 1] = '</div></div>'
  return table.concat (out)
end

---------------------------------------------------------------------------------------------
-- git stash
---------------------------------------------------------------------------------------------

---Saves the changes away and leaves the files as the last commit has them. `untracked` takes
---the new files too.
---@param message string Empty for Git's own message.
---@param untracked boolean
---@return string[]
function M.stash_args (message, untracked)
  local args = { 'stash', 'push' }
  if untracked then
    args[#args + 1] = '--include-untracked'
  end
  local text = trim (message)
  if text ~= '' then
    args[#args + 1] = '--message'
    args[#args + 1] = text
  end
  return args
end

---@return string[]
function M.stash_list_args ()
  return { 'stash', 'list', M.STASH_FORMAT }
end

---Reads `git stash list` output in `STASH_FORMAT`, newest first.
---@param text string
---@return Git.Stash[]
function M.parse_stashes (text)
  local out = {} ---@type Git.Stash[]
  for _, raw in ipairs (lines_of (text)) do
    local f = split (strip_cr (raw), US)
    if #f >= 3 and f[1]:find ('^stash@{%d+}$') then
      out[#out + 1] = { ref = f[1], message = f[2], date = f[3] }
    end
  end
  return out
end

---What one of the stash actions runs: `apply` keeps the stash, `pop` drops it once it
---applies cleanly, and `drop` throws it away.
---@param action 'apply'|'pop'|'drop'
---@param ref string
---@return string[]
function M.stash_action_args (action, ref)
  if action == 'drop' then
    return { 'stash', 'drop', '--quiet', ref }
  end
  return { 'stash', action, ref }
end

---The diff a stash holds, against the commit it was made on.
---@param ref string
---@return string[]
function M.stash_show_args (ref)
  return {
    'stash',
    'show',
    '--patch',
    '--no-color',
    '--no-ext-diff',
    '--src-prefix=a/',
    '--dst-prefix=b/',
    ref,
  }
end

---------------------------------------------------------------------------------------------
-- git diff
---------------------------------------------------------------------------------------------

---@param s string
---@param prefix string
---@return string
local function drop_prefix (s, prefix)
  if s:sub (1, #prefix) == prefix then
    return s:sub (#prefix + 1)
  end
  return s
end

---Reads a `---` or `+++` path. Git ends a name that holds a space with a tab.
---@param s string
---@param prefix string
---@return string?
local function header_path (s, prefix)
  local name = s:gsub ('\t$', '')
  if name == '/dev/null' then
    return nil
  end
  return drop_prefix (M.unquote (name), prefix)
end

---Reads the two paths of a `diff --git a/x b/y` line. When neither is quoted and the file was
---not renamed, the line holds the same name twice, which splits it even when it has spaces.
---@param rest string The text after `diff --git `.
---@return string old
---@return string new
local function git_line_paths (rest)
  if rest:sub (1, 1) == '"' then
    local a, j = read_quoted (rest, 1)
    local tail = rest:sub (j + 1)
    local b = tail:sub (1, 1) == '"' and read_quoted (tail, 1) or tail
    return drop_prefix (a, 'a/'), drop_prefix (b, 'b/')
  end
  local q = rest:find (' "', 1, true)
  if q and rest:sub (-1) == '"' then
    local b = read_quoted (rest, q + 1)
    return drop_prefix (rest:sub (1, q - 1), 'a/'), drop_prefix (b, 'b/')
  end
  if #rest % 2 == 1 then
    local half = math.floor ((#rest - 1) / 2)
    local a, b = rest:sub (1, half), rest:sub (half + 2)
    if a:sub (3) == b:sub (3) then
      return drop_prefix (a, 'a/'), drop_prefix (b, 'b/')
    end
  end
  local s = rest:find (' b/', 1, true)
  if s then
    return drop_prefix (rest:sub (1, s - 1), 'a/'), rest:sub (s + 3)
  end
  return rest, rest
end

---@param line string
---@return Git.FileDiff
local function start_file (line)
  ---@type Git.FileDiff
  local f = {
    path = '',
    new_file = false,
    deleted = false,
    renamed = false,
    binary = false,
    combined = false,
    header = { line },
    hunks = {},
    added = 0,
    removed = 0,
  }
  local rest = line:match ('^diff %-%-git (.*)$')
  if rest then
    f.old_path, f.new_path = git_line_paths (rest)
  else
    local name = M.unquote (line:match ('^diff %-%-%a+ (.*)$') or '')
    f.combined = true
    f.old_path, f.new_path = name, name
  end
  return f
end

---Reads one header line between `diff --git` and the first hunk.
---@param f Git.FileDiff
---@param line string
local function read_header (f, line)
  f.header[#f.header + 1] = line
  if line:find ('^new file mode ') then
    f.new_file = true
    f.new_mode = line:sub (15)
  elseif line:find ('^deleted file mode ') then
    f.deleted = true
    f.old_mode = line:sub (19)
  elseif line:find ('^old mode ') then
    f.old_mode = line:sub (10)
  elseif line:find ('^new mode ') then
    f.new_mode = line:sub (10)
  elseif line:find ('^rename from ') then
    f.renamed = true
    f.old_path = M.unquote (line:sub (13))
  elseif line:find ('^rename to ') then
    f.renamed = true
    f.new_path = M.unquote (line:sub (11))
  elseif line:find ('^copy from ') then
    f.old_path = M.unquote (line:sub (11))
  elseif line:find ('^copy to ') then
    f.new_path = M.unquote (line:sub (9))
  elseif line:find ('^%-%-%- ') then
    f.old_path = header_path (line:sub (5), 'a/')
  elseif line:find ('^%+%+%+ ') then
    f.new_path = header_path (line:sub (5), 'b/')
  elseif line:find ('^Binary files ') or line == 'GIT binary patch' then
    f.binary = true
  end
end

---Reads `-12,3` or `+12` into a start line and a count.
---@param s string
---@return integer start
---@return integer count
local function read_range (s)
  local a, b = s:match ('^[%-+](%d+),?(%d*)$')
  return int (a), (b == nil or b == '') and 1 or int (b)
end

---Reads a hunk header. A combined diff has one `-` range for each side of the merge.
---@param line string
---@return Git.Hunk? hunk
---@return integer columns How many prefix characters each line has.
local function read_hunk_header (line)
  local ats, ranges = line:match ('^(@@+) (.-) @@+')
  if not ats then
    return nil, 0
  end
  ---@type Git.Hunk
  local h = {
    header = line,
    old_start = 0,
    old_count = 0,
    new_start = 0,
    new_count = 0,
    lines = {},
  }
  local seen_old = false
  for part in tostring (ranges):gmatch ('%S+') do
    if part:sub (1, 1) == '-' and not seen_old then
      h.old_start, h.old_count = read_range (part)
      seen_old = true
    elseif part:sub (1, 1) == '+' then
      h.new_start, h.new_count = read_range (part)
    end
  end
  return h, #ats - 1
end

---@param f Git.FileDiff
local function finish_file (f)
  if f.new_file then
    f.old_path = nil
  end
  if f.deleted then
    f.new_path = nil
  end
  f.path = f.new_path or f.old_path or ''
  for _, h in ipairs (f.hunks) do
    for _, l in ipairs (h.lines) do
      if l.kind == 'add' then
        f.added = f.added + 1
      elseif l.kind == 'del' then
        f.removed = f.removed + 1
      end
    end
  end
end

---Reads `git diff` output, and the diff part of `git show`. Text before the first `diff` line,
---such as a commit header, is skipped. With `max_lines` it stops after that many hunk lines,
---so a huge diff is never read whole: the hunk it stopped in is marked `partial`, and the
---second result is true.
---@param text string
---@param max_lines? integer
---@return Git.FileDiff[] files
---@return boolean cut
function M.parse_diff (text, max_lines)
  local files = {} ---@type Git.FileDiff[]
  local f = nil ---@type Git.FileDiff?
  local h = nil ---@type Git.Hunk?
  local cols = 1
  local old_left, new_left = 0, 0
  local old_no, new_no = 0, 0
  local max = max_lines or math.huge
  local count = 0
  local cut = false
  local pos = 1
  while pos <= #text do
    local stop = text:find ('\n', pos, true)
    local raw = text:sub (pos, (stop or #text + 1) - 1)
    pos = (stop or #text) + 1
    local c = raw:sub (1, 1)
    local plain_line = h
      and cols == 1
      and (old_left > 0 or new_left > 0)
      and (c == ' ' or c == '+' or c == '-' or c == '\\' or raw == '')
    local prefix = raw:sub (1, cols)
    local combined_line = h
      and cols > 1
      and #raw >= cols
      and prefix:find ('^[ +%-]+$') ~= nil
    if (plain_line or combined_line) and count >= max then
      cut = true
      if h then
        h.partial = true
      end
      break
    end
    if plain_line or combined_line then
      count = count + 1
    end
    if h and c == '\\' then
      h.lines[#h.lines + 1] =
        { kind = 'meta', text = NO_NEWLINE, raw = strip_cr (raw) }
    elseif h and plain_line then
      local body = strip_cr (raw:sub (2))
      if c == '+' then
        h.lines[#h.lines + 1] =
          { kind = 'add', text = body, raw = raw, new = new_no }
        new_no, new_left = new_no + 1, new_left - 1
      elseif c == '-' then
        h.lines[#h.lines + 1] =
          { kind = 'del', text = body, raw = raw, old = old_no }
        old_no, old_left = old_no + 1, old_left - 1
      else
        h.lines[#h.lines + 1] = {
          kind = 'ctx',
          text = body,
          raw = raw == '' and ' ' or raw,
          old = old_no,
          new = new_no,
        }
        old_no, new_no = old_no + 1, new_no + 1
        old_left, new_left = old_left - 1, new_left - 1
      end
    elseif h and combined_line then
      local body = strip_cr (raw:sub (cols + 1))
      if prefix:find ('-', 1, true) then
        h.lines[#h.lines + 1] = { kind = 'del', text = body, raw = raw }
      elseif prefix:find ('+', 1, true) then
        h.lines[#h.lines + 1] =
          { kind = 'add', text = body, raw = raw, new = new_no }
        new_no = new_no + 1
      else
        h.lines[#h.lines + 1] =
          { kind = 'ctx', text = body, raw = raw, new = new_no }
        new_no = new_no + 1
      end
    elseif raw:find ('^diff %-%-git ') or raw:find ('^diff %-%-cc ') then
      f = start_file (raw)
      files[#files + 1] = f
      h = nil
    elseif f and c == '@' then
      local hunk, columns = read_hunk_header (raw)
      if hunk then
        h = hunk
        cols = columns
        f.hunks[#f.hunks + 1] = hunk
        old_left, new_left = hunk.old_count, hunk.new_count
        old_no, new_no = hunk.old_start, hunk.new_start
      end
    elseif f and not h then
      read_header (f, raw)
    end
  end
  for _, file in ipairs (files) do
    finish_file (file)
  end
  return files, cut
end

---Reads `git show` output in `SHOW_FORMAT`: the commit, then its diff, up to `max_lines`
---lines of it.
---@param text string
---@param max_lines? integer
---@return Git.Show
function M.parse_show (text, max_lines)
  local cut = text:find (RS, 1, true)
  if not cut then
    local files, more = M.parse_diff (text, max_lines)
    return { commit = nil, files = files, cut = more }
  end
  local f = split (text:sub (1, cut - 1), US)
  local message = (f[8] or ''):gsub ('%s+$', '')
  local subject, body = message:match ('^([^\n]*)\n?(.*)$')
  ---@type Git.CommitInfo
  local commit = {
    hash = f[1] or '',
    short = f[2] or '',
    author = f[3] or '',
    email = f[4] or '',
    date = f[5] or '',
    relative = f[6] or '',
    parents = {},
    subject = subject or '',
    body = trim (body or ''),
  }
  for p in (f[7] or ''):gmatch ('%S+') do
    commit.parents[#commit.parents + 1] = p
  end
  local files, more = M.parse_diff (text:sub (cut + 1), max_lines)
  return { commit = commit, files = files, cut = more }
end

---@param start integer
---@param count integer
---@return string
local function range_text (start, count)
  if count == 1 then
    return tostring (start)
  end
  return start .. ',' .. count
end

---A patch that holds one hunk, with the file headers `git apply` needs. The counts in the
---`@@` line come from the lines themselves. Returns nil for a binary or a conflict diff.
---@param file Git.FileDiff
---@param hunk Git.Hunk
---@return string?
function M.hunk_patch (file, hunk)
  if file.binary or file.combined or hunk.partial then
    return nil
  end
  local out = {} ---@type string[]
  for _, line in ipairs (file.header) do
    out[#out + 1] = line
  end
  local old_n, new_n = 0, 0
  for _, l in ipairs (hunk.lines) do
    if l.kind == 'ctx' then
      old_n, new_n = old_n + 1, new_n + 1
    elseif l.kind == 'del' then
      old_n = old_n + 1
    elseif l.kind == 'add' then
      new_n = new_n + 1
    end
  end
  out[#out + 1] = '@@ -'
    .. range_text (hunk.old_start, old_n)
    .. ' +'
    .. range_text (hunk.new_start, new_n)
    .. ' @@'
  for _, l in ipairs (hunk.lines) do
    out[#out + 1] = l.raw
  end
  return table.concat (out, '\n') .. '\n'
end

---A diff for a file Git does not track yet: every line is added. `text` is nil for a file
---that is not text.
---@param path string
---@param text string?
---@return Git.FileDiff
function M.untracked_diff (path, text)
  local a, b = quote_path ('a/' .. path), quote_path ('b/' .. path)
  local tab = (b:sub (1, 1) ~= '"' and path:find (' ', 1, true)) and '\t' or ''
  ---@type Git.FileDiff
  local f = {
    path = path,
    new_path = path,
    new_file = true,
    deleted = false,
    renamed = false,
    binary = false,
    combined = false,
    new_mode = '100644',
    header = { 'diff --git ' .. a .. ' ' .. b, 'new file mode 100644' },
    hunks = {},
    added = 0,
    removed = 0,
  }
  if text == nil or text:find ('\0', 1, true) then
    f.binary = true
    return f
  end
  if text == '' then
    return f
  end
  f.header[#f.header + 1] = '--- /dev/null'
  f.header[#f.header + 1] = '+++ ' .. b .. tab
  local rows = split (text, '\n')
  local ends_with_newline = rows[#rows] == ''
  if ends_with_newline then
    rows[#rows] = nil
  end
  ---@type Git.Hunk
  local h = {
    header = '@@ -0,0 +' .. range_text (1, #rows) .. ' @@',
    old_start = 0,
    old_count = 0,
    new_start = 1,
    new_count = #rows,
    lines = {},
  }
  for i, row in ipairs (rows) do
    h.lines[i] =
      { kind = 'add', text = strip_cr (row), raw = '+' .. row, new = i }
  end
  if not ends_with_newline then
    h.lines[#h.lines + 1] =
      { kind = 'meta', text = NO_NEWLINE, raw = '\\ ' .. NO_NEWLINE }
  end
  f.hunks[1] = h
  f.added = #rows
  return f
end

---------------------------------------------------------------------------------------------
-- HTML
---------------------------------------------------------------------------------------------

local esc = M.escape

---@param text string
---@return string
local function note (text)
  return '<div class="git-note">' .. esc (text) .. '</div>'
end

---@param f Git.FileDiff
---@return string
local function empty_file_text (f)
  if f.old_mode and f.new_mode and f.old_mode ~= f.new_mode then
    return 'The file mode changed from '
      .. f.old_mode
      .. ' to '
      .. f.new_mode
      .. '.'
  end
  if f.renamed then
    return 'Renamed with no changes inside.'
  end
  if f.new_file then
    return 'An empty file.'
  end
  return 'No changes to show.'
end

---@param f Git.FileDiff
---@param opts Git.DiffOptions
---@return string
local function file_head (f, opts)
  local out = { '<div class="git-file-head"><span class="git-file-path">' }
  if f.renamed and f.old_path and f.old_path ~= f.path then
    out[#out + 1] = '<span class="git-file-old">'
      .. esc (f.old_path)
      .. '</span> → '
  end
  out[#out + 1] = esc (f.path) .. '</span>'
  local tags = {} ---@type string[]
  if opts.label then
    tags[#tags + 1] = opts.label
  end
  if f.new_file then
    tags[#tags + 1] = 'New'
  elseif f.deleted then
    tags[#tags + 1] = 'Deleted'
  elseif f.renamed then
    tags[#tags + 1] = 'Renamed'
  end
  for _, t in ipairs (tags) do
    out[#out + 1] = '<span class="git-file-tag">' .. esc (t) .. '</span>'
  end
  out[#out + 1] = '<span class="git-file-stat"><span class="git-stat-add">+'
    .. f.added
    .. '</span><span class="git-stat-del">−'
    .. f.removed
    .. '</span></span></div>'
  return table.concat (out)
end

---@type table<Git.LineKind, string>
local SIGN = { add = '+', del = '−', ctx = '', meta = '' }

---@param l Git.Line
---@return string
local function line_html (l)
  return '<div class="git-line git-l-'
    .. l.kind
    .. '"><span class="git-ln">'
    .. (l.old or '')
    .. '</span><span class="git-ln">'
    .. (l.new or '')
    .. '</span><span class="git-sign">'
    .. SIGN[l.kind]
    .. '</span><span class="git-code">'
    .. esc (l.text)
    .. '</span></div>'
end

---The diff for the main area, as one HTML string. Each hunk button carries
---`data-item="hunk:<file>:<hunk>"`, both counted from 1.
---@param files Git.FileDiff[]
---@param opts? Git.DiffOptions
---@return string
function M.diff_html (files, opts)
  opts = opts or {}
  local max = opts.max_lines or 5000
  local total = 0
  for _, f in ipairs (files) do
    for _, h in ipairs (f.hunks) do
      total = total + #h.lines
    end
  end
  local out = { '<div class="git-diff">' }
  if #files == 0 then
    out[#out + 1] = note (opts.empty or 'No changes.')
  end
  local shown = 0
  local cut = false
  for fi, f in ipairs (files) do
    if cut then
      break
    end
    out[#out + 1] = '<div class="git-file">'
    out[#out + 1] = file_head (f, opts)
    if f.binary then
      out[#out + 1] = note ('Binary file')
    elseif #f.hunks == 0 then
      out[#out + 1] = note (empty_file_text (f))
    end
    for hi, h in ipairs (f.hunks) do
      if shown >= max then
        cut = true
        break
      end
      out[#out + 1] = '<div class="git-hunk-head"><span class="git-hunk-text">'
        .. esc (h.header)
        .. '</span>'
      if opts.buttons and not f.combined and not f.binary and not h.partial then
        out[#out + 1] = '<button class="git-hunk-btn" data-item="hunk:'
          .. fi
          .. ':'
          .. hi
          .. '">'
          .. (opts.staged and 'Unstage Hunk' or 'Stage Hunk')
          .. '</button>'
      end
      out[#out + 1] = '</div>'
      for _, l in ipairs (h.lines) do
        if shown >= max then
          cut = true
          break
        end
        out[#out + 1] = line_html (l)
        shown = shown + 1
      end
    end
    out[#out + 1] = '</div>'
  end
  if opts.cut then
    out[#out + 1] = note (
      'Showing the first '
        .. M.thousands (shown)
        .. ' lines. The rest is left out.'
    )
  elseif cut then
    out[#out + 1] = note (
      'Showing the first '
        .. M.thousands (max)
        .. ' of '
        .. M.thousands (total)
        .. ' lines.'
    )
  end
  out[#out + 1] = '</div>'
  return table.concat (out)
end

---The commit header above a commit's diff: the whole message, the author and the date.
---@param c Git.CommitInfo
---@return string
function M.commit_html (c)
  local out = {
    '<div class="git-commit-view"><div class="git-commit-title">',
    esc (c.subject),
    '</div>',
  }
  if c.body ~= '' then
    out[#out + 1] = '<div class="git-commit-body">' .. esc (c.body) .. '</div>'
  end
  out[#out + 1] = '<div class="git-commit-info"><span>'
    .. esc (c.author)
    .. ' &lt;'
    .. esc (c.email)
    .. '&gt;</span><span>'
    .. esc (c.date)
    .. (c.relative ~= '' and (' (' .. esc (c.relative) .. ')') or '')
    .. '</span><span class="git-hash">'
    .. esc (c.hash)
    .. '</span></div>'
  if #c.parents > 1 then
    local shorts = {} ---@type string[]
    for _, p in ipairs (c.parents) do
      shorts[#shorts + 1] = esc (p:sub (1, 7))
    end
    out[#out + 1] = '<div class="git-commit-info">A merge of '
      .. table.concat (shorts, ' and ')
      .. '. The changes shown are against the first.</div>'
  end
  out[#out + 1] = '</div>'
  return table.concat (out)
end

---The header above a stash's diff: its message, its name and when it was made.
---@param st Git.Stash
---@return string
function M.stash_html (st)
  return '<div class="git-commit-view"><div class="git-commit-title">'
    .. esc (st.message)
    .. '</div><div class="git-commit-info"><span class="git-hash">'
    .. esc (st.ref)
    .. '</span><span>'
    .. esc (st.date)
    .. '</span></div></div>'
end

---Splits a path into its file name and its folder.
---@param path string
---@return string name
---@return string folder Empty for a file at the top.
function M.split_path (path)
  local clean = path:gsub ('/$', '')
  local dir, name = clean:match ('^(.*)/([^/]*)$')
  if not dir then
    return clean, ''
  end
  return name, dir
end

---The folder name `git clone` gives a repository: the last part of its address, without
---`.git`. Empty when the address has no name at its end.
---@param url string
---@return string
function M.clone_name (url)
  local trimmed = url:match ('^%s*(.-)%s*$') or '' ---@type string
  local text = trimmed:gsub ('[/\\]+$', '')
  local last = text:match ('([^/\\:]+)$') or '' ---@type string
  local name = last:gsub ('%.git$', '')
  return name
end

---Reads a `data-item` value such as `'stage:u:src/a.txt'` into its action, its list (`'s'` or
---`'u'`) and its path.
---@param item string?
---@return string? action
---@return string? group
---@return string? path
function M.parse_item (item)
  if not item then
    return nil, nil, nil
  end
  local action, group, path = item:match ('^([%w_-]+):([su]):(.*)$')
  if action then
    return action, group, path
  end
  return item, nil, nil
end

---@param e Git.Entry
---@param opts Git.ListOptions
---@return string
local function row_html (e, opts)
  local group = e.staged and 's' or 'u'
  local key = group .. ':' .. e.path
  local name, dir = M.split_path (e.path)
  local icons = opts.icons or {}
  local tools = {} ---@type string[]
  ---@param action string
  ---@param title string
  ---@param icon string
  local function tool (action, title, icon)
    tools[#tools + 1] = '<button class="git-tool" data-item="'
      .. esc (action .. ':' .. key)
      .. '" title="'
      .. esc (title)
      .. '">'
      .. (icons[icon] or esc (title:sub (1, 1)))
      .. '</button>'
  end
  if e.staged then
    tool ('unstage', 'Unstage', 'unstage')
  elseif e.kind == 'conflicted' then
    tool ('stage', 'Mark Resolved', 'stage')
  else
    if M.discard_args (e) then
      tool ('discard', 'Discard Changes', 'discard')
    end
    tool ('stage', 'Stage', 'stage')
  end
  local title = e.old_path and (e.old_path .. ' → ' .. e.path) or e.path
  return '<div class="git-row'
    .. (opts.selected == key and ' active' or '')
    .. '" data-item="'
    .. esc ('open:' .. key)
    .. '" title="'
    .. esc (title .. ' (' .. KIND_TITLE[e.kind] .. ')')
    .. '"><span class="git-letter git-k-'
    .. e.kind
    .. '">'
    .. esc (e.letter)
    .. '</span><span class="git-name">'
    .. esc (name)
    .. '</span><span class="git-dir">'
    .. esc (dir)
    .. '</span><span class="git-tools">'
    .. table.concat (tools)
    .. '</span></div>'
end

---@param title string
---@param count integer
---@param action string
---@param label string
---@return string
local function group_head (title, count, action, label)
  return '<div class="git-group"><span class="git-group-title">'
    .. esc (title)
    .. '</span><span class="ui-badge">'
    .. count
    .. '</span><button class="git-group-btn" data-item="'
    .. action
    .. '">'
    .. esc (label)
    .. '</button></div>'
end

---Draws the rows of one list, up to the limit, then a Show All row.
---@param out string[]
---@param list Git.Entry[]
---@param group string
---@param opts Git.ListOptions
local function rows_html (out, list, group, opts)
  local limit = opts.limit or M.LIST_LIMIT
  if opts.all and opts.all[group] then
    limit = #list
  end
  for i, e in ipairs (list) do
    if i > limit then
      out[#out + 1] = '<div class="git-row git-more" data-item="show-all-'
        .. group
        .. '">Show all '
        .. M.thousands (#list)
        .. ' files</div>'
      return
    end
    out[#out + 1] = row_html (e, opts)
  end
end

---The Staged and Changes lists as one HTML string. A row carries
---`data-item="open:<s|u>:<path>"` and its buttons `stage:`, `unstage:` or `discard:`. A list
---longer than `opts.limit` ends in a `show-all-<s|u>` row.
---@param st Git.Status
---@param opts? Git.ListOptions
---@return string
function M.changes_html (st, opts)
  opts = opts or {}
  local out = {} ---@type string[]
  if #st.staged > 0 then
    out[#out + 1] =
      group_head ('Staged', #st.staged, 'unstage-all', 'Unstage All')
    rows_html (out, st.staged, 's', opts)
  end
  local conflicts, changes = {}, {} ---@type Git.Entry[], Git.Entry[]
  for _, e in ipairs (st.unstaged) do
    if e.kind == 'conflicted' then
      conflicts[#conflicts + 1] = e
    else
      changes[#changes + 1] = e
    end
  end
  if #conflicts > 0 then
    out[#out + 1] = '<div class="git-group"><span class="git-group-title">Merge Changes</span>'
      .. '<span class="ui-badge">'
      .. #conflicts
      .. '</span></div>'
    rows_html (out, conflicts, 'u', opts)
  end
  if #changes > 0 then
    out[#out + 1] = group_head ('Changes', #changes, 'stage-all', 'Stage All')
    rows_html (out, changes, 'u', opts)
  end
  if #out == 0 then
    out[1] = '<div class="ui-empty">No changes</div>'
  end
  return table.concat (out)
end

---The history list as one HTML string. Each row carries `data-item="<hash>"`, and the Load
---More row `data-item="more"`.
---@param commits Git.Commit[]
---@param selected? string The hash of the selected commit.
---@param opts? Git.LogOptions
---@return string
function M.log_html (commits, selected, opts)
  local o = opts or {}
  if #commits == 0 then
    return '<div class="ui-empty">'
      .. esc (o.empty or 'No commits yet')
      .. '</div>'
  end
  local out = {} ---@type string[]
  local graph = o.graph
  if graph then
    out[1] = '<div class="git-graph-list">'
  end
  for i, c in ipairs (commits) do
    local refs = {} ---@type string[]
    for _, r in ipairs (c.refs) do
      refs[#refs + 1] = '<span class="git-ref git-ref-'
        .. r.kind
        .. (r.current and ' git-ref-current' or '')
        .. '">'
        .. esc (r.name)
        .. '</span>'
    end
    out[#out + 1] = '<div class="git-commit'
      .. (c.hash == selected and ' active' or '')
      .. '" data-item="'
      .. esc (c.hash)
      .. '">'
      .. (graph and graph[i] or '')
      .. '<div class="git-commit-text"><div class="git-commit-subject">'
      .. table.concat (refs)
      .. '<span class="git-subject-text">'
      .. esc (c.subject)
      .. '</span></div><div class="git-commit-meta"><span class="git-hash">'
      .. esc (c.short)
      .. '</span><span>'
      .. esc (c.author)
      .. '</span><span>'
      .. esc (c.date)
      .. '</span></div></div></div>'
  end
  if graph then
    out[#out + 1] = '</div>'
  end
  if o.more then
    out[#out + 1] =
      '<div class="git-row git-more" data-item="more">Load more commits</div>'
  end
  return table.concat (out)
end

---The screen with no repository open: a button to open one, then the recent ones. The button
---carries `data-item="open"` and each recent row `data-item="recent:<path>"`.
---@param recent string[]
---@param icon? string SVG to show at the top.
---@return string
function M.welcome_html (recent, icon)
  local out = {
    '<div class="git-welcome">',
    icon and ('<div class="git-welcome-icon">' .. icon .. '</div>') or '',
    '<div class="git-welcome-title">No repository open</div>',
    '<div class="git-welcome-text">Open a folder that holds a Git repository.</div>',
    '<button class="ui-button primary" data-item="open">Open Repository</button>',
  }
  if #recent > 0 then
    out[#out + 1] = '<div class="git-recent-title">Recent</div>'
    for _, path in ipairs (recent) do
      local name = M.split_path (path)
      out[#out + 1] = '<div class="git-recent" data-item="'
        .. esc ('recent:' .. path)
        .. '"><span class="git-recent-name">'
        .. esc (name)
        .. '</span><span class="git-recent-path">'
        .. esc (path)
        .. '</span></div>'
    end
  end
  out[#out + 1] = '</div>'
  return table.concat (out)
end

---A plain message for the main area, such as when Git is missing.
---@param title string
---@param text string
---@return string
function M.message_html (title, text)
  return '<div class="git-welcome"><div class="git-welcome-title">'
    .. esc (title)
    .. '</div><div class="git-welcome-text">'
    .. esc (text)
    .. '</div></div>'
end

---------------------------------------------------------------------------------------------
-- Paths, lists and messages
---------------------------------------------------------------------------------------------

---Joins the repository folder and a path inside it.
---@param root string
---@param rel string
---@return string
function M.join (root, rel)
  local base = root:gsub ('[/\\]+$', '')
  return base .. '/' .. rel
end

---A full path as a path from the repository root, or nil when it is outside. Windows ignores
---the case of letters in paths, so the comparison there does too.
---@param root string
---@param full string
---@param os? string
---@return string?
function M.relative (root, full, os)
  local base = root:gsub ('\\', '/'):gsub ('/+$', '')
  local path = full:gsub ('\\', '/')
  local head = path:sub (1, #base + 1)
  local want = base .. '/'
  if os == 'windows' then
    head, want = head:lower (), want:lower ()
  end
  if head ~= want or #path <= #want then
    return nil
  end
  return path:sub (#want + 1)
end

---The folder that holds a path.
---@param path string
---@return string
function M.parent (path)
  local clean = path:gsub ('[/\\]+$', '')
  return clean:match ('^(.*)[/\\][^/\\]*$') or clean
end

---A path with the separators the system's file manager expects.
---@param path string
---@param os string Such as `'windows'`.
---@return string
function M.native (path, os)
  if os == 'windows' then
    local out = path:gsub ('/', '\\')
    return out
  end
  return path
end

---Puts a repository at the front of the recent list, without repeats, and keeps `max`.
---@param list string[]
---@param path string
---@param max integer
---@return string[]
function M.remember (list, path, max)
  local out = { path } ---@type string[]
  for _, p in ipairs (list) do
    if p ~= path and #out < max then
      out[#out + 1] = p
    end
  end
  return out
end

---The text to show when a git command fails: what Git printed on stderr, or on stdout when
---stderr is empty, or the reason it could not start. Long output keeps its first lines.
---@param res Proteus.RunResult?
---@param err string?
---@return string
function M.error_text (res, err)
  local text = err or ''
  if res then
    text = trim (res.stderr or '')
    if text == '' then
      text = trim (res.stdout or '')
    end
  end
  if text == '' then
    return 'Git failed with no message.'
  end
  local lines = lines_of (text)
  if #lines > 8 then
    text = table.concat (lines, '\n', 1, 8) .. '\n…'
  end
  return text
end

---The first line Git printed, for a short report such as `'Already up to date.'`.
---@param res Proteus.RunResult
---@return string
function M.summary (res)
  for _, s in ipairs ({ res.stdout or '', res.stderr or '' }) do
    local first = trim (s):match ('^[^\n]*') or ''
    if first ~= '' then
      return strip_cr (first)
    end
  end
  return ''
end

---True when a file could not be read because it is not text.
---@param err string?
---@return boolean
function M.is_binary_error (err)
  return err ~= nil and err:lower ():find ('utf%-8') ~= nil
end

return M
