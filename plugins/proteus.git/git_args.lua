-- git_args: the command lines the Git client runs, and the variables they run with. Each
-- list leaves out what every git command starts with, `base_args ()`, which the client puts
-- in front. It calls no host function, so the tests reach all of it.

local T = require ('git_text') --[[@as Git.TextModule]]

local lines_of, strip_cr, trim = T.lines_of, T.strip_cr, T.trim

---What the History view lists: every commit, the ones a search finds, or one file's.
---@class Git.LogQuery
---@field skip? integer Commits to leave out at the top, for the next page.
---@field search? string Text to find in commit messages, or `author:<name>` for the author.
---@field path? string A file, from the repository root, whose history to list.

---@class Git.ArgsModule
local M = {}

M.LOG_FORMAT = '--format=%H%x1f%h%x1f%an%x1f%ar%x1f%D%x1f%P%x1f%s%x1e'
M.SHOW_FORMAT = '--format=%H%x1f%h%x1f%an%x1f%ae%x1f%ad%x1f%ar%x1f%P%x1f%B%x1e'
M.BRANCH_FORMAT = '--format=%(HEAD)%09%(refname)%09%(upstream:short)'
M.STASH_FORMAT = '--format=%gd%x1f%gs%x1f%cr'

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

---------------------------------------------------------------------------------------------
-- Merge, rebase, cherry-pick, revert and reset
---------------------------------------------------------------------------------------------

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

---------------------------------------------------------------------------------------------
-- Tags and remotes
---------------------------------------------------------------------------------------------

---Makes a tag on a commit: an annotated one with a message, or a lightweight one without.
---@param name string
---@param hash string
---@param message string
---@return string[]
function M.tag_args (name, hash, message)
  local text = trim (message)
  if text == '' then
    return { 'tag', name, hash }
  end
  return { 'tag', '-a', name, '-m', text, hash }
end

---Every tag, newest first.
---@return string[]
function M.tag_list_args ()
  return { 'tag', '--list', '--sort=-creatordate' }
end

---Pushes one tag to a remote, or every tag when `name` is nil.
---@param remote string
---@param name? string
---@return string[]
function M.push_tag_args (remote, name)
  if name then
    return { 'push', remote, 'refs/tags/' .. name }
  end
  return { 'push', remote, '--tags' }
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

return M
