-- git_parse: reads what the git program prints, and builds the patches that stage part of a
-- file. It calls no host function and draws nothing, so the tests reach all of it.
--
-- The command lines are in git_args, the HTML in git_html, and the paths and messages in
-- git_paths. This module hands out their functions as well, so the client and the tests
-- reach all of them through it.
--
-- Status comes from `git status -z`. `parse_status` also reads the output without `-z`, where
-- Git quotes a path that holds a space or an unusual character, and `unquote` reads it back.

local A = require ('git_args') --[[@as Git.ArgsModule]]
local T = require ('git_text') --[[@as Git.TextModule]]
local html = require ('git_html') --[[@as Git.HtmlModule]]
local paths = require ('git_paths') --[[@as Git.PathsModule]]

local int, lines_of, split, strip_cr, trim =
  T.int, T.lines_of, T.split, T.strip_cr, T.trim

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

---One entry of `git stash list`.
---@class Git.Stash
---@field ref string Such as `'stash@{0}'`.
---@field message string Such as `'On main: try the new parser'`.
---@field date string Relative, such as `'2 hours ago'`.

---A merge, rebase, cherry-pick or revert that stopped part way, for conflicts.
---@alias Git.Operation 'merge'|'rebase'|'cherry-pick'|'revert'

---An item in the Switch Branch list.
---@class Git.Choice
---@field label string
---@field detail? string
---@field icon string
---@field action 'create'|'switch'|'track'
---@field name? string The branch to switch to.

---@class Git.ParseModule : Git.PathsModule, Git.ArgsModule, Git.HtmlModule
local M = {}

local US = '\31'
local RS = '\30'
local NO_NEWLINE = 'No newline at end of file'

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

---A reason a new branch, tag or remote name is not allowed, or nil when it is fine.
---@param name string
---@param what string Such as `'branch'`.
---@return string?
local function check_ref_name (name, what)
  local a = 'A ' .. what .. ' name'
  if name == '' then
    return 'Type a name for the ' .. what .. '.'
  end
  if name:find ('[%s~^:?*%[\\%c]') then
    return a .. ' cannot hold spaces or any of ~ ^ : ? * [ \\'
  end
  if
    name:find ('%.%.')
    or name:find ('//')
    or name:find ('@{', 1, true)
    or name == '@'
  then
    return a .. ' cannot hold .., // or @{'
  end
  if
    name:find ('^[%-/.]')
    or name:find ('[/.]$')
    or name:find ('%.lock$')
    or name:find ('/%.')
  then
    return a .. ' cannot start with - / or . or end with / . or .lock'
  end
  return nil
end

---A reason a new branch name is not allowed, or nil when it is fine.
---@param name string
---@return string?
function M.check_branch_name (name)
  return check_ref_name (name, 'branch')
end

---@param name string
---@return string?
function M.check_tag_name (name)
  return check_ref_name (name, 'tag')
end

---A remote's name becomes part of its branches' names, such as `origin/main`, so it holds
---no `/` either.
---@param name string
---@return string?
function M.check_remote_name (name)
  if name:find ('/', 1, true) then
    return 'A remote name cannot hold /'
  end
  return check_ref_name (name, 'remote')
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

---------------------------------------------------------------------------------------------
-- Tags and remotes
---------------------------------------------------------------------------------------------

---@class Git.Remote
---@field name string
---@field url string The address it fetches from.

---Reads `git tag --list`, one name a line.
---@param text string
---@return string[]
function M.parse_tags (text)
  local out = {} ---@type string[]
  for _, raw in ipairs (lines_of (text)) do
    local name = trim (strip_cr (raw))
    if name ~= '' then
      out[#out + 1] = name
    end
  end
  return out
end

---Reads `git remote -v`: each remote once, with the address it fetches from.
---@param text string
---@return Git.Remote[]
function M.parse_remotes (text)
  local out = {} ---@type Git.Remote[]
  local seen = {} ---@type table<string, boolean>
  for _, raw in ipairs (lines_of (text)) do
    local name, url = strip_cr (raw):match ('^(%S+)%s+(.-)%s+%((%a+)%)$')
    if name and not seen[name] then
      seen[name] = true
      out[#out + 1] = { name = name, url = url }
    end
  end
  return out
end

---------------------------------------------------------------------------------------------
-- git stash
---------------------------------------------------------------------------------------------

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

---A patch that stages, or with `reverse` unstages, only the picked lines of a hunk. The
---lines left out stay as they are on the side the patch applies to: when staging, a removed
---line becomes context and an added one is dropped, and when unstaging it is the other way
---round. Returns nil when no line is picked, or for a hunk `hunk_patch` refuses.
---@param file Git.FileDiff
---@param hunk Git.Hunk
---@param picked table<integer, boolean> Line positions in `hunk.lines`.
---@param reverse boolean
---@return string?
function M.lines_patch (file, hunk, picked, reverse)
  local keep_kind = reverse and 'add' or 'del'
  local lines = {} ---@type Git.Line[]
  local changes = 0
  local kept_last = true
  for i, l in ipairs (hunk.lines) do
    if l.kind == 'meta' then
      if kept_last then
        lines[#lines + 1] = l
      end
    elseif l.kind == 'ctx' or picked[i] then
      lines[#lines + 1] = l
      kept_last = true
      if l.kind ~= 'ctx' then
        changes = changes + 1
      end
    elseif l.kind == keep_kind then
      lines[#lines + 1] = {
        kind = 'ctx',
        text = l.text,
        raw = ' ' .. l.raw:sub (2),
        old = l.old,
        new = l.new,
      }
      kept_last = true
    else
      kept_last = false
    end
  end
  if changes == 0 then
    return nil
  end
  ---@type Git.Hunk
  local part = {
    header = hunk.header,
    old_start = hunk.old_start,
    old_count = hunk.old_count,
    new_start = hunk.new_start,
    new_count = hunk.new_count,
    lines = lines,
    partial = hunk.partial,
  }
  return M.hunk_patch (file, part)
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
-- The other modules
---------------------------------------------------------------------------------------------

-- Copies in their functions, so `require ('git_parse')` reaches them too.
for _, part in ipairs ({ A, html, paths }) do
  for k, v in pairs (part) do
    M[k] = v
  end
end

return M
