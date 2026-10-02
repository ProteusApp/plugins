-- proteus.git: a Git client for any folder that holds a repository. It runs the real git program
-- and shows the changed files, the diff of each one, and the history. The left dock holds the
-- Changes and History views, and the main area shows a diff or a commit.
--
-- Inside the Code Editor, where the `project` service runs, it works on the open folder
-- instead of a repository picked here. The Changes view becomes Source Control, a diff opens
-- in a tab that can close, and the standalone app's toolbar and keys stay out of the way. It
-- sends each file's Git state as the `git:status` event, which colours the file tree.
--
-- git_parse holds the parsing, and hands out the command lines from git_args, the HTML from
-- git_html and the paths from git_paths, so the tests reach all of them. This file holds the
-- screen, the commands and the calls to git.

local blame = require ('git_blame') --[[@as Git.BlameModule]]
local graph = require ('git_graph') --[[@as Git.GraphModule]]
local m = require ('git_parse') --[[@as Git.ParseModule]]

local MAX_RECENT = 10
-- How many commits the History view reads at a time.
local LOG_PAGE = 200

-- lang=css
local CSS = [[
.git-side { display: flex; flex-direction: column; height: 100%; min-height: 0; }
.git-head { flex: none; padding: 10px 10px 6px; border-bottom: 1px solid var(--border); }
.git-repo { display: flex; align-items: center; gap: 6px; font-weight: 600; min-width: 0; }
.git-repo-name { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.git-head-branch { display: flex; align-items: center; gap: 6px; margin-top: 4px; min-width: 0; }
.git-branch-btn { padding: 2px 6px; font-size: 12px; color: var(--fg-muted); min-width: 0; overflow: hidden; }
.git-sync { font-size: 12px; color: var(--fg-faint); white-space: nowrap; }
.git-list { flex: 1; min-height: 0; overflow: auto; padding: 2px 0 8px; }
.git-group { display: flex; align-items: center; gap: 6px; padding: 8px 8px 4px 12px; font-size: 11px; font-weight: 600;
  letter-spacing: .04em; text-transform: uppercase; color: var(--fg-muted); }
.git-group-btn { margin-left: auto; border: none; background: none; color: var(--fg-muted); font: inherit; font-size: 11px;
  font-weight: 400; text-transform: none; letter-spacing: 0; cursor: pointer; padding: 2px 6px; border-radius: var(--radius); }
.git-group-btn:hover { background: var(--bg-hover); color: var(--fg); }
.git-row { display: flex; align-items: center; gap: 6px; height: 26px; padding: 0 6px 0 12px; cursor: pointer; }
.git-row:hover { background: var(--bg-hover); }
.git-row.active { background: var(--bg-active); }
.git-letter { flex: none; width: 14px; text-align: center; font-family: var(--font-mono); font-size: 12px; font-weight: 700; }
.git-k-modified { color: var(--warning); }
.git-k-added, .git-k-untracked { color: var(--success); }
.git-k-deleted, .git-k-conflicted { color: var(--danger); }
.git-k-renamed, .git-k-copied, .git-k-typechange { color: var(--accent); }
.git-name { flex: none; max-width: 70%; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.git-dir { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-size: 12px;
  color: var(--fg-faint); }
.git-more { justify-content: center; font-size: 12px; color: var(--accent); }
.git-tools { flex: none; display: none; gap: 2px; }
.git-row:hover .git-tools { display: flex; }
.git-tool { display: inline-grid; place-items: center; width: 22px; height: 22px; padding: 0; border: none;
  border-radius: var(--radius); background: transparent; color: var(--fg-muted); cursor: pointer; }
.git-tool:hover { background: var(--bg-active); color: var(--fg); }
.git-side-empty { display: flex; flex-direction: column; align-items: center; gap: 12px; }
.git-head-top { display: flex; align-items: center; gap: 6px; min-width: 0; }
.git-head-top .git-repo { flex: 1; }
.git-head-tools { flex: none; display: flex; gap: 2px; }
.git-op { flex: none; display: flex; flex-direction: column; gap: 6px; padding: 8px 10px;
  border-bottom: 1px solid var(--border); background: color-mix(in srgb, var(--warning) 12%, transparent);
  font-size: 12px; }
.git-op-btns { display: flex; gap: 6px; }
.git-conflict { position: sticky; left: 0; display: flex; flex-direction: column; gap: 8px; padding: 12px 16px;
  border-bottom: 1px solid var(--border); background: color-mix(in srgb, var(--danger) 10%, transparent); }
.git-conflict-btns { display: flex; flex-wrap: wrap; gap: 6px; }
.git-commit-box { flex: none; display: flex; flex-direction: column; gap: 6px; padding: 8px 10px 10px;
  border-top: 1px solid var(--border); }
.git-message { width: 100%; min-height: 64px; max-height: 40vh; resize: vertical; line-height: 1.4; }
.git-commit-row { display: flex; align-items: center; gap: 8px; }
.git-amend { display: inline-flex; align-items: center; gap: 5px; margin-right: auto; color: var(--fg-muted);
  font-size: 12px; cursor: pointer; }
.git-amend input { margin: 0; accent-color: var(--accent); }
.git-history-tools { flex: none; display: flex; flex-direction: column; gap: 6px; padding: 8px 10px;
  border-bottom: 1px solid var(--border); }
.git-search { width: 100%; }
.git-filter { display: flex; align-items: center; gap: 6px; font-size: 12px; color: var(--fg-muted); min-width: 0; }
.git-filter-text { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.git-commit { display: flex; align-items: center; gap: 4px; padding: 6px 10px; cursor: pointer;
  border-bottom: 1px solid var(--border); }
.git-commit-text { flex: 1; min-width: 0; }
.git-graph-list .git-commit { height: 46px; padding: 0 10px 0 2px; border-bottom: none; }
.git-graph { flex: none; overflow: hidden; }
.git-graph path { fill: none; stroke-width: 2; }
.git-graph .git-dot { stroke-width: 2; }
.git-graph .git-dot-merge { fill: var(--bg) !important; }
.git-lane-0 { stroke: var(--accent); fill: var(--accent); }
.git-lane-1 { stroke: var(--success); fill: var(--success); }
.git-lane-2 { stroke: var(--warning); fill: var(--warning); }
.git-lane-3 { stroke: var(--danger); fill: var(--danger); }
.git-lane-4 { stroke: #a371f7; fill: #a371f7; }
.git-lane-5 { stroke: #39c5cf; fill: #39c5cf; }
.git-lane-6 { stroke: #f778ba; fill: #f778ba; }
.git-lane-7 { stroke: #8b949e; fill: #8b949e; }
.git-commit:hover { background: var(--bg-hover); }
.git-commit.active { background: var(--bg-active); }
.git-commit-subject { display: flex; align-items: center; gap: 4px; min-width: 0; }
.git-subject-text { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.git-commit-meta { display: flex; gap: 8px; margin-top: 2px; font-size: 11px; color: var(--fg-faint); white-space: nowrap;
  overflow: hidden; }
.git-hash { font-family: var(--font-mono); }
.git-ref { flex: none; max-width: 120px; padding: 0 5px; border-radius: 8px; font-size: 10px; line-height: 16px;
  background: var(--bg-active); color: var(--fg-muted); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.git-ref-current, .git-ref-head { background: var(--accent); color: var(--accent-fg); }
.git-ref-remote { background: color-mix(in srgb, var(--accent) 20%, transparent); color: var(--fg); }
.git-ref-tag { background: color-mix(in srgb, var(--warning) 25%, transparent); color: var(--fg); }
.git-main { flex: 1; min-height: 0; display: flex; flex-direction: column; background: var(--bg); }
.git-main-body { flex: 1; min-height: 0; overflow: auto; }
.git-diff { display: inline-block; min-width: 100%; padding-bottom: 24px; font-size: 12px; }
.git-file { margin-bottom: 12px; }
.git-file-head { position: sticky; top: 0; z-index: 1; display: flex; align-items: center; gap: 8px; padding: 6px 12px;
  background: var(--bg-alt); border-bottom: 1px solid var(--border); font-size: 13px; }
.git-file-path { font-weight: 600; white-space: nowrap; }
.git-file-old { font-weight: 400; color: var(--fg-muted); }
.git-file-tag { padding: 0 6px; border-radius: 9px; font-size: 11px; line-height: 17px; background: var(--bg-active);
  color: var(--fg-muted); }
.git-file-stat { display: flex; gap: 8px; margin-left: auto; font-family: var(--font-mono); font-size: 12px; }
.git-stat-add { color: var(--success); }
.git-stat-del { color: var(--danger); }
.git-hunk-head { display: flex; align-items: center; gap: 8px; padding: 2px 12px; line-height: 22px;
  font-family: var(--font-mono); color: var(--fg-muted); background: color-mix(in srgb, var(--accent) 10%, transparent); }
.git-hunk-text { white-space: pre; }
.git-hunk-btn { position: sticky; right: 8px; flex: none; margin-left: auto; padding: 1px 8px; font: 11px var(--font-ui);
  border: 1px solid var(--border); border-radius: var(--radius); background: var(--bg-elev); color: var(--fg);
  cursor: pointer; }
.git-hunk-btn:hover { background: var(--bg-hover); }
.git-hunk-btn.git-lines-btn { display: none; margin-left: auto; }
.git-hunk-btn.git-lines-btn + .git-hunk-btn { margin-left: 0; }
.git-hunk-picked .git-lines-btn { display: inline-block; }
.git-gutter { display: flex; flex: none; cursor: pointer; }
.git-gutter:hover .git-ln { color: var(--fg); }
.git-picked .git-gutter { background: var(--accent); }
.git-picked .git-gutter span { color: var(--accent-fg); }
.git-line { display: flex; font-family: var(--font-mono); line-height: 19px; white-space: pre; }
.git-ln { flex: none; width: 48px; padding-right: 8px; text-align: right; color: var(--fg-faint); user-select: none; }
.git-sign { flex: none; width: 16px; text-align: center; color: var(--fg-faint); user-select: none; }
.git-code { flex: 1; padding-right: 16px; tab-size: 4; }
.git-l-add { background: color-mix(in srgb, var(--success) 15%, transparent); }
.git-l-add .git-sign { color: var(--success); }
.git-l-del { background: color-mix(in srgb, var(--danger) 15%, transparent); }
.git-l-del .git-sign { color: var(--danger); }
.git-l-add .git-w { background: color-mix(in srgb, var(--success) 35%, transparent); border-radius: 2px; }
.git-l-del .git-w { background: color-mix(in srgb, var(--danger) 35%, transparent); border-radius: 2px; }
.git-diff-split { display: block; }
.git-split { display: grid; grid-template-columns: 1fr 1fr; font-family: var(--font-mono); line-height: 19px; }
.git-half { display: flex; min-width: 0; }
.git-half + .git-half { border-left: 1px solid var(--border); }
.git-half .git-code { white-space: pre-wrap; overflow-wrap: anywhere; padding-right: 8px; tab-size: 4; }
.git-half.git-l-add { background: color-mix(in srgb, var(--success) 15%, transparent); }
.git-half.git-l-del { background: color-mix(in srgb, var(--danger) 15%, transparent); }
.git-half.git-l-add .git-sign { color: var(--success); }
.git-half.git-l-del .git-sign { color: var(--danger); }
.git-half-empty { background: var(--bg-alt); }
.git-blame { display: inline-block; min-width: 100%; padding-bottom: 24px; font-size: 12px; }
.git-blame-line { display: flex; font-family: var(--font-mono); line-height: 19px; white-space: pre; }
.git-blame-first { border-top: 1px solid var(--border); }
.git-blame-info { flex: none; display: flex; gap: 8px; width: 300px; padding: 0 8px 0 12px; overflow: hidden;
  font-family: var(--font-ui); color: var(--fg-muted); }
.git-blame-hash { color: var(--accent); cursor: pointer; }
.git-blame-hash:hover { text-decoration: underline; }
.git-blame-who { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; }
.git-blame-day { flex: none; color: var(--fg-faint); }
.git-l-meta .git-code { color: var(--fg-faint); font-style: italic; }
.git-note { padding: 12px 16px; color: var(--fg-muted); }
.git-commit-view { padding: 16px 16px 12px; border-bottom: 1px solid var(--border); }
.git-commit-title { font-size: 16px; font-weight: 600; }
.git-commit-body { margin-top: 8px; white-space: pre-wrap; line-height: 1.5; color: var(--fg-muted); }
.git-commit-info { display: flex; flex-wrap: wrap; gap: 12px; margin-top: 8px; font-size: 12px; color: var(--fg-faint); }
.git-welcome { min-height: 100%; display: flex; flex-direction: column; align-items: center; justify-content: center;
  gap: 10px; padding: 32px; text-align: center; }
.git-welcome-icon { color: var(--fg-faint); }
.git-welcome-title { font-size: 18px; font-weight: 600; }
.git-welcome-text { max-width: 480px; color: var(--fg-muted); white-space: pre-wrap; }
.git-recent-title { margin-top: 18px; font-size: 11px; font-weight: 600; letter-spacing: .04em; text-transform: uppercase;
  color: var(--fg-faint); }
.git-recent { display: flex; flex-direction: column; align-items: flex-start; width: min(480px, 100%); padding: 6px 10px;
  border-radius: var(--radius); text-align: left; cursor: pointer; }
.git-recent:hover { background: var(--bg-hover); }
.git-recent-name { font-weight: 600; }
.git-recent-path { max-width: 100%; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-size: 12px;
  color: var(--fg-faint); }
]]

---What the main area shows.
---@class Git.Selection
---@field kind 'file'|'commit'|'stash'|'blame'
---@field group? string `'s'` for the Staged list, `'u'` for the Changes list.
---@field path? string
---@field hash? string
---@field ref? string A stash, such as `'stash@{0}'`.
---@field stash? Git.Stash

---@param s string
---@return boolean
local function blank (s)
  return not s:find ('%S')
end

---@type Proteus.Plugin
return {
  name = 'Git',
  description = 'Stage, commit, branch and browse the history of a Git repository.',
  version = '1.3.2',
  requires = { proteus = '>=0.3.1', features = { 'permissions' } },
  -- It runs the git program, and reads the changed files in a repository anywhere on disk.
  permissions = { 'files', 'process' },
  depends = {
    'proteus.lib.ui',
    'proteus.ui.shell',
    'proteus.ui.views',
    'proteus.core.commands',
  },
  optional = {
    'proteus.ui.toolbar',
    'proteus.ui.statusbar',
    'proteus.ui.palette',
    'proteus.ui.notify',
    'proteus.core.keys',
    'proteus.ui.menus',
    'proteus.ui.tabs',
    'proteus.code.project',
  },
  activate = function (app)
    -- The status holds full paths in the project folder, which need `files`.
    app.protect_event ('git:status', { needs = 'files' })
    local ui = app.use ('ui')
    local shell = app.use ('shell')
    local views = app.use ('views')
    local commands = app.use ('commands')
    local bar = app.try_use ('status')
    local notify = app.try_use ('notify')
    local picker = app.try_use ('picker')
    local menus = app.try_use ('menus')
    -- Inside the Code Editor, the repository is the open folder.
    local project = app.try_use ('project')
    local editor = app.try_use ('editor')
    local embedded = project ~= nil
    local folder = project and project.root () or nil
    ui.css (CSS)

    local esc = m.escape
    local desktop = app.platform ~= 'browser'
    local git_found = nil ---@type boolean? nil while the check runs
    local repo = nil ---@type string? The repository root, with forward slashes.
    local status = nil ---@type Git.Status?
    local commits = {} ---@type Git.Commit[]
    -- True when the last page of history was full, so there may be more.
    local log_more = false
    -- The search box's text, and the file whose history the History view lists.
    local log_search = ''
    local log_path = nil ---@type string?
    -- The graph beside the history, drawn again when the commits change.
    local graph_rows = {} ---@type string[]
    local graph_for = nil ---@type Git.Commit[]?
    local selection = nil ---@type Git.Selection?
    -- What the main area draws now. The hunk buttons point into `shown_files`.
    local shown_files = {} ---@type Git.FileDiff[]
    local shown_staged = false
    -- Diffs show the old and the new file side by side.
    local split_view = app.store.get ('split', false) == true
    -- The lines picked in the diff, by `'<file>:<hunk>'`, then by line position.
    local picked = {} ---@type table<string, table<integer, boolean>>
    -- How the file diff on show was drawn, to draw it again when a line is picked.
    local shown_opts = nil ---@type Git.DiffOptions?
    local shown_top = ''
    local shown_key = nil ---@type string?
    local busy = nil ---@type string? Such as 'Pushing…' while a remote command runs.
    local refreshing = false
    local refresh_again = false
    local history_open = false
    -- True when the Code Editor's folder holds no repository.
    local not_repo = false
    -- Each load counts up, so an answer that arrives after a newer request is dropped.
    local diff_seq = 0
    local log_seq = 0
    -- What the repository's status.showUntrackedFiles says, read when it opens.
    local untracked_mode = nil ---@type string?
    -- The repository's .git folder, and the operation that stopped there part way.
    local git_dir = nil ---@type string?
    local operation = nil ---@type Git.Operation?
    -- The lists drawn whole after Show All, by 's' or 'u'.
    local show_all = {} ---@type table<string, boolean>
    -- When the last status read ended, and how long it took, in milliseconds.
    local status_done_at = 0
    local status_took = 0

    local recent = {} ---@type string[]
    local saved = app.store.get ('recent', {})
    if type (saved) == 'table' then
      for _, p in
        ipairs (saved --[[@as any[] ]])
      do
        if type (p) == 'string' then
          recent[#recent + 1] = p
        end
      end
    end

    -- A repository's own settings can make Git run programs, so the client runs git only in a
    -- folder the user trusts. Inside the Code Editor that is the folder the kernel trusts, and
    -- the user trusts it once for everything in it. The standalone app keeps its own list of
    -- the repositories the user chose to trust.
    local untrusted = embedded
      and folder ~= nil
      and app.kernel.project ().trusted ~= true
    local trusted_repos = {} ---@type string[]
    local stored_trust = app.store.get ('trusted', nil)
    if type (stored_trust) == 'table' then
      for _, p in
        ipairs (stored_trust --[[@as any[] ]])
      do
        if type (p) == 'string' then
          trusted_repos[#trusted_repos + 1] = p
        end
      end
    else
      -- Repositories opened before the list existed were the user's choice already.
      for _, p in ipairs (recent) do
        trusted_repos[#trusted_repos + 1] = m.folder_key (p, app.os)
      end
      app.store.set ('trusted', trusted_repos)
    end

    ---@param path string
    local function trust_repo (path)
      if not m.is_trusted (trusted_repos, path, app.os) then
        trusted_repos[#trusted_repos + 1] = m.folder_key (path, app.os)
        app.store.set ('trusted', trusted_repos)
      end
    end

    ---@type table<string, string>
    local ICONS = {
      stage = app.util.icon ('plus', 15) or '+',
      unstage = app.util.icon ('minus', 15) or '-',
      discard = app.util.icon ('undo-2', 15) or 'x',
    }

    -- Messages ------------------------------------------------------------------------------

    ---@param text string
    local function fail (text)
      if notify then
        notify.error (text)
      else
        app.warn (text)
      end
    end

    ---@param text string
    local function done (text)
      if notify then
        notify.success (text)
      else
        app.log (text)
      end
    end

    ---@param text string
    local function tell (text)
      if notify then
        notify.info (text)
      else
        app.log (text)
      end
    end

    ---Asks before something that cannot be undone. Without the palette there is no way to
    ---ask, so it does nothing.
    ---@param message string
    ---@param yes string
    ---@param fn fun()
    local function confirm (message, yes, fn)
      if not picker then
        fail ('This needs the command palette to ask first.')
        return
      end
      picker.confirm ({ message = message, yes = yes, on_yes = fn })
    end

    -- Running git ---------------------------------------------------------------------------

    ---Runs git in the open repository, or in `opts.cwd`. `cb` gets the result, or an error
    ---text when git could not start. An error inside `cb` is logged, not raised. The handle
    ---cancels it, and is nil when git could not start.
    ---@param args string[]
    ---@param opts? { cwd?: string, stdin?: string, env?: table<string, string> }
    ---@param cb fun(res: Proteus.RunResult?, err: string?)
    ---@return Proteus.RunHandle?
    local function git (args, opts, cb)
      local full = m.command (args)
      local o = opts or {}
      ---@param res Proteus.RunResult?
      ---@param err string?
      local function reply (res, err)
        local good, problem = pcall (cb, res, err)
        if not good then
          app.error (problem)
        end
      end
      local started, handle = pcall (
        app.process.run,
        'git',
        full,
        { cwd = o.cwd or repo, stdin = o.stdin, env = o.env },
        reply
      )
      if not started then
        reply (nil, tostring (handle))
        return nil
      end
      return handle
    end

    ---@type fun()
    local refresh

    ---Runs a git command that changes something. Shows Git's error when it fails, runs
    ---`after` when it works, and refreshes either way.
    ---@param args string[]
    ---@param opts? { stdin?: string, env?: table<string, string> }
    ---@param after? fun(res: Proteus.RunResult)
    local function act (args, opts, after)
      git (args, opts, function (res, err)
        if not res or res.code ~= 0 then
          fail (m.error_text (res, err))
        elseif after then
          after (res)
        end
        refresh ()
      end)
    end

    -- Screen parts --------------------------------------------------------------------------

    local repo_name = ui.span ({ class = 'git-repo-name' })
    local branch_label = ui.span ({})
    local sync_label = ui.span ({ class = 'git-sync' })
    ---@param icon string
    ---@param title string
    ---@param id string
    ---@return Proteus.El
    local function head_tool (icon, title, id)
      return ui.button ({
        class = 'git-tool',
        title = title,
        ui.icon (icon, 15),
        onclick = function ()
          commands.run (id)
          return nil
        end,
      })
    end

    local head = ui.div ({
      class = 'git-head',
      ui.div ({
        class = 'git-head-top',
        ui.div ({ class = 'git-repo', ui.icon ('folder-git-2', 15), repo_name }),
        embedded
            and ui.div ({
              class = 'git-head-tools',
              head_tool ('refresh-cw', 'Refresh', 'git.refresh'),
              head_tool ('download', 'Fetch', 'git.fetch'),
              head_tool ('arrow-down-to-line', 'Pull', 'git.pull'),
              head_tool ('arrow-up-from-line', 'Push', 'git.push'),
              head_tool ('history', 'History', 'git.show_history'),
              head_tool ('columns-2', 'Side-by-Side Diff', 'git.toggle_split'),
            })
          or nil,
      }),
      ui.div ({
        class = 'git-head-branch',
        ui.button ({
          class = 'git-branch-btn',
          variant = 'ghost',
          title = 'Switch Branch (Ctrl+Shift+B)',
          icon = 'git-branch',
          branch_label,
          onclick = function ()
            commands.run ('git.branch')
            return nil
          end,
        }),
        sync_label,
      }),
    })
    local changes_list = ui.div ({ class = 'git-list' })
    ---@param label string
    ---@param id string
    ---@param variant? string
    ---@return Proteus.El
    local function op_button (label, id, variant)
      return ui.button ({
        label,
        variant = variant,
        onclick = function ()
          commands.run (id)
          return nil
        end,
      })
    end
    local op_text = ui.span ({})
    local op_skip = op_button ('Skip', 'git.skip')
    op_skip:set ('title', 'Leave out this commit and go on')
    local op_bar = ui.div ({
      class = 'git-op',
      op_text,
      ui.div ({
        class = 'git-op-btns',
        op_button ('Continue', 'git.continue', 'primary'),
        op_skip,
        op_button ('Abort', 'git.abort', 'ghost'),
      }),
    })
    op_bar:show (false)
    local message = ui.input ({
      multiline = true,
      class = 'git-message',
      placeholder = 'Message (Ctrl+Enter to commit)',
      spellcheck = true,
    })
    local amend = ui.h ('input', { type = 'checkbox' })
    local commit_box = ui.div ({
      class = 'git-commit-box',
      message,
      ui.div ({
        class = 'git-commit-row',
        ui.label ({
          class = 'git-amend',
          title = 'Change the last commit instead of making a new one',
          amend,
          'Amend',
        }),
        ui.button ({
          'Commit',
          variant = 'primary',
          icon = 'check',
          onclick = function ()
            commands.run ('git.commit')
            return nil
          end,
        }),
      }),
    })
    local history_list = ui.div ({ class = 'git-list' })
    local history_search = ui.input ({
      class = 'git-search',
      placeholder = 'Search messages, or author:name',
      spellcheck = false,
    })
    local filter_text = ui.span ({ class = 'git-filter-text' })
    local history_filter = ui.div ({
      class = 'git-filter',
      ui.icon ('file-clock', 14),
      filter_text,
      ui.button ({
        class = 'git-tool',
        title = 'Show every commit',
        ui.icon ('x', 14),
        onclick = function ()
          commands.run ('git.history_all')
          return nil
        end,
      }),
    })
    history_filter:show (false)
    local history_tools = ui.div ({
      class = 'git-history-tools',
      history_search,
      history_filter,
    })
    local main_body = ui.div ({ class = 'git-main-body' })
    local root = ui.div ({ class = 'git-main', main_body })

    local tabs = app.try_use ('tabs')
    ---@type fun()
    local forget_selection
    ---Brings the diff tab to the front, opening it again if it was closed. Inside the Code
    ---Editor the tab can close, since the editor's own tabs share the main area.
    local function show_root ()
      if not (embedded and tabs) then
        return
      end
      tabs.open ({
        id = 'proteus.git',
        title = 'Changes',
        icon = 'git-compare',
        content = root,
        on_close = function ()
          -- The content is kept for the next time the tab opens.
          root:detach ()
          forget_selection ()
          return true
        end,
      })
    end
    if embedded then
      root:detach ()
    elseif tabs then
      tabs.open ({
        id = 'proteus.git',
        title = 'Git',
        icon = 'git-branch',
        content = root,
        closable = false,
      })
    else
      shell.mount ('main', root)
    end

    local st_branch = bar
      and bar.add ({
        id = 'git.branch',
        icon = 'git-branch',
        tooltip = 'Switch Branch',
        command = 'git.branch',
        order = 1,
      })
    local st_sync = bar
      and bar.add ({
        id = 'git.sync',
        tooltip = 'Commits to push (↑) and to pull (↓)',
        order = 2,
      })
    local st_changes = bar and bar.add ({ id = 'git.changes', order = 3 })
    local st_busy = bar
      and bar.add ({
        id = 'git.busy',
        icon = 'loader-circle',
        tooltip = 'Click to cancel',
        align = 'right',
        order = 1,
        command = 'git.cancel',
      })

    -- Drawing -------------------------------------------------------------------------------

    ---@param html string
    ---@param keep_scroll? boolean
    local function show_main (html, keep_scroll)
      local top = keep_scroll and main_body:get ('scrollTop') or 0
      main_body:html (html)
      main_body:set ('scrollTop', top)
    end

    local function render_bar ()
      local st = repo and status or nil
      if st_branch then
        st_branch.show (st ~= nil)
        st_branch.set (st and m.branch_text (st) or '')
      end
      if st_sync then
        local sync = st and m.sync_text (st) or ''
        st_sync.show (sync ~= '')
        st_sync.set (sync)
      end
      if st_changes then
        st_changes.show (st ~= nil)
        st_changes.set (st and m.count_text (m.change_count (st)) or '')
      end
      if st_busy then
        st_busy.show (busy ~= nil)
        st_busy.set (busy or '')
      end
    end

    local function render_head ()
      if not repo then
        return
      end
      repo_name:text ((m.split_path (repo)))
      repo_name:set ('title', repo)
      branch_label:text (status and m.branch_text (status) or '…')
      sync_label:text (status and m.sync_text (status) or '')
    end

    local function render_operation ()
      local op = repo and status and operation or nil
      op_bar:show (op ~= nil)
      if op and status then
        op_text:text (m.operation_text (op, m.conflict_count (status)))
        op_skip:show (op == 'rebase')
      end
    end

    local function render_changes ()
      if not repo or not status then
        return
      end
      local sel = selection
      local key = nil ---@type string?
      if sel and sel.kind == 'file' then
        key = (sel.group or '') .. ':' .. (sel.path or '')
      end
      changes_list:html (
        m.changes_html (
          status,
          { selected = key, icons = ICONS, all = show_all }
        )
      )
    end

    local function render_history ()
      if not repo then
        return
      end
      local sel = selection
      local hash = sel and sel.kind == 'commit' and sel.hash or nil
      -- A search or one file's history leaves commits out, so it has no graph to draw.
      local filtered = log_path ~= nil or not blank (log_search)
      if not filtered and graph_for ~= commits then
        graph_rows, graph_for = graph.rows_svg (commits), commits
      end
      history_list:html (m.log_html (commits, hash, {
        more = log_more,
        empty = filtered and 'No commits match' or nil,
        graph = not filtered and graph_rows or nil,
      }))
    end

    -- The side views with no repository open: a short reason and, when it can work, a button.
    local function render_side ()
      local open = repo ~= nil
      head:show (open)
      commit_box:show (open)
      history_tools:show (open)
      if open then
        return
      end
      local text = 'No repository open'
      if not desktop then
        text = 'Needs the desktop app'
      elseif git_found == false then
        text = 'Git is not installed'
      elseif untrusted then
        text = 'Git waits until you trust this folder'
      elseif embedded and not_repo then
        text = 'This folder is not a Git repository'
      elseif embedded then
        text = 'Reading the repository…'
      end
      local button = ''
      if
        desktop
        and git_found
        and untrusted
        and project
        and project.ask_trust
      then
        button =
          '<button class="ui-button" data-item="trust">Trust Folder</button>'
      elseif desktop and git_found and embedded and not_repo then
        button =
          '<button class="ui-button" data-item="init">Initialize Repository</button>'
      elseif desktop and git_found and not embedded then
        button =
          '<button class="ui-button" data-item="open">Open Repository</button>'
      end
      changes_list:html (
        '<div class="ui-empty git-side-empty"><div>'
          .. esc (text)
          .. '</div>'
          .. button
          .. '</div>'
      )
      history_list:html ('<div class="ui-empty">' .. esc (text) .. '</div>')
    end

    -- The main area when no file or commit is picked.
    local function show_placeholder ()
      shown_files, shown_key = {}, nil
      shown_opts = nil
      if not desktop then
        show_main (
          m.message_html (
            'The Git client needs the desktop app',
            'It runs the git program, which a browser cannot do.'
          )
        )
      elseif git_found == nil then
        show_main ('')
      elseif not git_found then
        show_main (
          m.message_html (
            'Git is not installed',
            'Install Git from git-scm.com, then open this app again.'
          )
        )
      elseif untrusted then
        show_main (
          m.message_html (
            'Git waits until you trust this folder',
            "A repository's own settings can make Git run programs, so Git runs here once you trust the folder."
          )
        )
      elseif not repo then
        show_main (m.welcome_html (recent, app.util.icon ('git-branch', 40)))
      elseif status and m.change_count (status) == 0 then
        show_main (
          m.message_html ('No changes', 'The files match the last commit.')
        )
      else
        show_main (
          m.message_html (
            'No file selected',
            'Pick a file on the left to see its changes.'
          )
        )
      end
    end

    ---Draws a diff. `key` is the file's list and path on its first line, then the diff text.
    ---The same key again draws nothing, and a new diff of the same file keeps the scroll
    ---position, so staging one hunk does not jump back to the top.
    ---@param files Git.FileDiff[]
    ---@param opts Git.DiffOptions
    ---@param key string
    ---@param top? string HTML above the diff.
    local function draw_files (files, opts, key, top)
      if key == shown_key then
        return
      end
      local same_file = shown_key ~= nil
        and shown_key:match ('^[^\n]*') == key:match ('^[^\n]*')
      shown_files = files
      shown_staged = opts.staged == true
      shown_key = key
      picked = {}
      opts.picked = picked
      shown_opts, shown_top = opts, top or ''
      show_main (shown_top .. m.diff_html (files, opts), same_file)
    end

    ---@param e Git.Entry
    local function show_entry (e)
      local current = repo
      if not current then
        return
      end
      diff_seq = diff_seq + 1
      local seq = diff_seq
      local label = e.staged and 'Staged' or 'Unstaged'
      if e.kind == 'untracked' then
        label = 'Untracked'
      elseif e.kind == 'conflicted' then
        label = 'Conflict'
      end
      ---@type Git.DiffOptions
      local opts = {
        buttons = e.kind ~= 'conflicted',
        -- A new file is staged whole: git apply cannot add part of a file Git does not know.
        lines = e.kind ~= 'conflicted' and e.kind ~= 'untracked',
        staged = e.staged,
        label = label,
        empty = 'No changes to show.',
        split = split_view,
      }
      local prefix = (e.staged and 's:' or 'u:')
        .. e.path
        .. (split_view and ':split' or '')
        .. '\n'
      if e.kind == 'untracked' and e.path:sub (-1) == '/' then
        shown_files, shown_key = {}, nil
        shown_opts = nil
        show_main (
          m.message_html ('A new folder', 'Stage it to add every file in it.')
        )
        return
      end
      if e.kind == 'untracked' then
        app.fs.read_file (m.join (current, e.path), function (text, err)
          if seq ~= diff_seq then
            return
          end
          if err and not m.is_binary_error (err) then
            shown_key = nil
            show_main (m.message_html ('Could not read the file', err))
            return
          end
          local files = { m.untracked_diff (e.path, text) }
          draw_files (files, opts, prefix .. (text or '\0binary'))
        end)
        return
      end
      git (m.diff_args (e), nil, function (res, err)
        if seq ~= diff_seq then
          return
        end
        if not res or res.code ~= 0 then
          shown_key = nil
          show_main (
            m.message_html ('Could not show the diff', m.error_text (res, err))
          )
          return
        end
        local files, cut = m.parse_diff (res.stdout, m.MAX_LINES)
        opts.cut = cut
        local top = e.kind == 'conflicted' and m.conflict_html (e) or nil
        draw_files (files, opts, prefix .. res.stdout, top)
      end)
    end

    ---@param e Git.Entry
    local function select_entry (e)
      show_root ()
      selection =
        { kind = 'file', group = e.staged and 's' or 'u', path = e.path }
      shown_key = nil
      render_changes ()
      render_history ()
      show_entry (e)
    end

    ---@param hash string
    local function select_commit (hash)
      show_root ()
      selection = { kind = 'commit', hash = hash }
      shown_key = nil
      render_changes ()
      render_history ()
      diff_seq = diff_seq + 1
      local seq = diff_seq
      git (m.show_args (hash), nil, function (res, err)
        if seq ~= diff_seq then
          return
        end
        if not res or res.code ~= 0 then
          show_main (
            m.message_html (
              'Could not show this commit',
              m.error_text (res, err)
            )
          )
          return
        end
        local show = m.parse_show (res.stdout, m.MAX_LINES)
        shown_files, shown_staged, shown_key = show.files, false, 'c:' .. hash
        shown_opts = nil
        local top = show.commit and m.commit_html (show.commit) or ''
        show_main (top .. m.diff_html (show.files, {
          empty = 'This commit changes no files.',
          cut = show.cut,
          split = split_view,
        }))
      end)
    end

    ---Shows what a stash holds.
    ---@param st Git.Stash
    local function show_stash (st)
      show_root ()
      selection = { kind = 'stash', ref = st.ref, stash = st }
      shown_key = nil
      render_changes ()
      render_history ()
      diff_seq = diff_seq + 1
      local seq = diff_seq
      git (m.stash_show_args (st.ref), nil, function (res, err)
        if seq ~= diff_seq then
          return
        end
        if not res or res.code ~= 0 then
          show_main (
            m.message_html ('Could not show the stash', m.error_text (res, err))
          )
          return
        end
        local files, cut = m.parse_diff (res.stdout, m.MAX_LINES)
        shown_files, shown_staged, shown_key = files, false, 'z:' .. st.ref
        shown_opts = nil
        show_main (m.stash_html (st) .. m.diff_html (files, {
          empty = 'This stash holds no changes.',
          cut = cut,
          split = split_view,
        }))
      end)
    end

    ---Shows who last changed each line of a file, as it is on disk now.
    ---@param path string From the repository root.
    local function show_blame (path)
      show_root ()
      selection = { kind = 'blame', path = path }
      shown_files, shown_key = {}, nil
      shown_opts = nil
      render_changes ()
      render_history ()
      diff_seq = diff_seq + 1
      local seq = diff_seq
      show_main (m.message_html ('Reading the blame…', path))
      git (blame.args (path), nil, function (res, err)
        if seq ~= diff_seq then
          return
        end
        if not res or res.code ~= 0 then
          show_main (
            m.message_html ('Could not show the blame', m.error_text (res, err))
          )
          return
        end
        show_main (blame.html (path, blame.parse (res.stdout)))
      end)
    end

    -- Loading -------------------------------------------------------------------------------

    ---Reads the history again: as many commits as are listed now, or a page when `more` asks
    ---for the next one.
    ---@param more? boolean
    local function load_history (more)
      if not repo or not git_found then
        return
      end
      if status and status.initial then
        commits, log_more = {}, false
        render_history ()
        return
      end
      log_seq = log_seq + 1
      local seq = log_seq
      local n = more and LOG_PAGE or math.max (LOG_PAGE, #commits)
      ---@type Git.LogQuery
      local query = {
        skip = more and #commits or 0,
        search = log_search,
        path = log_path,
      }
      git (m.log_args (n, query), nil, function (res, err)
        if seq ~= log_seq then
          return
        end
        if not res or res.code ~= 0 then
          commits, log_more = {}, false
          history_list:html (
            '<div class="ui-empty">'
              .. esc (m.error_text (res, err))
              .. '</div>'
          )
          return
        end
        local page = m.parse_log (res.stdout)
        log_more = #page >= n
        commits = more and m.append_commits (commits, page) or page
        render_history ()
      end)
    end

    ---Lists one file's history, or every commit again when `path` is nil.
    ---@param path string?
    local function history_of (path)
      log_path = path
      filter_text:text (path and ('History of ' .. path) or '')
      filter_text:set ('title', path or '')
      history_filter:show (path ~= nil)
      commits, log_more = {}, false
      history_list:html ('')
      views.show ('git.history')
      load_history ()
    end

    ---Tells other plugins, such as a file tree, what Git says about each changed file. A file
    ---both staged and changed again reports the change that is not staged yet.
    local function announce ()
      local map = {} ---@type table<string, string>
      local top = repo
      local st = status
      if top and st then
        for _, e in ipairs (st.staged) do
          map[m.join (top, e.path)] = e.kind
        end
        for _, e in ipairs (st.unstaged) do
          map[m.join (top, e.path)] = e.kind
        end
      end
      app.emit ('git:status', map)
    end

    forget_selection = function ()
      selection, shown_key = nil, nil
      render_changes ()
      render_history ()
    end

    -- A refresh that is asked for while one runs waits for it, then runs once.
    refresh = function ()
      if not repo or not git_found then
        return
      end
      if refreshing then
        refresh_again = true
        return
      end
      refreshing = true
      local at = repo
      local started = app.util.now ()
      git (m.status_args (untracked_mode), nil, function (res, err)
        refreshing = false
        status_done_at = app.util.now ()
        status_took = status_done_at - started
        if at == repo and (not res or res.code ~= 0) then
          status = nil
          selection = nil
          shown_key = nil
          changes_list:html ('')
          show_main (
            m.message_html (
              'Could not read the repository',
              m.error_text (res, err)
            )
          )
          render_bar ()
        elseif at == repo and res then
          status = m.parse_status (res.stdout)
          announce ()
          render_head ()
          local dir = git_dir
          if dir then
            app.fs.list_dir (dir, function (names)
              if at == repo then
                operation = names and m.operation (names) or nil
                render_operation ()
              end
            end)
          end
          local sel = selection
          if sel and sel.kind == 'file' then
            local e = m.reselect (status, sel.group or 'u', sel.path or '')
            if e then
              sel.group = e.staged and 's' or 'u'
              show_entry (e)
            else
              selection = nil
              show_placeholder ()
            end
          elseif not sel then
            show_placeholder ()
          end
          render_changes ()
          render_bar ()
          if history_open then
            load_history ()
          end
        end
        if refresh_again then
          refresh_again = false
          refresh ()
        end
      end)
    end

    ---@param path string
    ---@param quiet? boolean True at start, where a folder that moved away needs no message.
    local function open_repo (path, quiet)
      if untrusted then
        return
      end
      if not embedded and not m.is_trusted (trusted_repos, path, app.os) then
        if quiet then
          return
        end
        confirm (
          'Trust '
            .. path
            .. "? A repository's own settings can make Git run programs, such as hooks when you commit. Trust only a repository from someone you trust.",
          'Trust and Open',
          function ()
            trust_repo (path)
            open_repo (path)
          end
        )
        return
      end
      git (
        { 'rev-parse', '--show-toplevel' },
        { cwd = path },
        function (res, err)
          local top = res
              and res.code == 0
              and res.stdout:match ('^%s*(.-)%s*$')
            or ''
          if top == '' then
            if embedded then
              not_repo = true
              render_side ()
              announce ()
              return
            end
            if quiet then
              return
            end
            if res and res.stderr:find ('not a git repository', 1, true) then
              fail (path .. ' is not in a Git repository.')
            else
              fail (m.error_text (res, err))
            end
            return
          end
          -- A message typed for another repository does not belong here.
          if top ~= repo then
            message:value ('')
            amend:checked (false)
          end
          repo = top
          not_repo = false
          status, commits, selection, shown_key = nil, {}, nil, nil
          show_all = {}
          log_more, log_path, log_search = false, nil, ''
          history_search:value ('')
          history_filter:show (false)
          if not embedded then
            trust_repo (top)
            recent = m.remember (recent, top, MAX_RECENT)
            app.store.set ('recent', recent)
            app.store.set ('reopen', true)
          end
          render_side ()
          render_head ()
          changes_list:html ('')
          history_list:html ('')
          show_placeholder ()
          operation, git_dir = nil, nil
          render_operation ()
          git ({ 'rev-parse', '--absolute-git-dir' }, nil, function (dir)
            git_dir = dir
                and dir.code == 0
                and dir.stdout:match ('^%s*(.-)%s*$')
              or nil
            git (
              { 'config', '--get', 'status.showUntrackedFiles' },
              nil,
              function (cfg)
                untracked_mode = cfg and cfg.code == 0 and cfg.stdout or nil
                refresh ()
              end
            )
          end)
        end
      )
    end

    local function close_repo ()
      repo, status, commits, selection, shown_key = nil, nil, {}, nil, nil
      operation, git_dir = nil, nil
      render_operation ()
      app.store.set ('reopen', false)
      render_side ()
      render_bar ()
      show_placeholder ()
    end

    -- Actions -------------------------------------------------------------------------------

    ---Opens a file of the repository in the Code Editor, or else in the system's own app.
    ---@param full string
    local function open_file (full)
      if embedded and editor then
        editor.open_file (full)
        return
      end
      app.system.open_path (m.native (full, app.os), function (_, err)
        if err then
          fail (err)
        end
      end)
    end

    ---Runs git commands one after another, stopping at the first that fails, then refreshes.
    ---@param list string[][]
    ---@param after? fun()
    local function act_all (list, after)
      local i = 0
      local function step ()
        i = i + 1
        local args = list[i]
        if not args then
          if after then
            after ()
          end
          refresh ()
          return
        end
        git (args, nil, function (res, err)
          if not res or res.code ~= 0 then
            fail (m.error_text (res, err))
            refresh ()
            return
          end
          step ()
        end)
      end
      step ()
    end

    ---Resolves a conflict: `ours` or `theirs` takes that side's version whole, and `resolved`
    ---stages the file as it is, asking first when it still holds conflict markers.
    ---@param e Git.Entry
    ---@param how 'ours'|'theirs'|'resolved'
    local function resolve (e, how)
      local name = (m.split_path (e.path))
      if how ~= 'resolved' then
        local side = how --[[@as 'ours'|'theirs']]
        act_all (m.resolve_args (e, side), function ()
          done ('Resolved ' .. name .. '.')
        end)
        return
      end
      local current = repo
      if not current then
        return
      end
      local function mark ()
        act (m.mark_resolved_args (e), nil, function ()
          done ('Resolved ' .. name .. '.')
        end)
      end
      app.fs.read_file (m.join (current, e.path), function (text)
        if text and m.has_markers (text) then
          confirm (
            name .. ' still holds conflict markers. Mark it resolved anyway?',
            'Mark Resolved',
            mark
          )
        else
          mark ()
        end
      end)
    end

    local function pick_repo ()
      app.fs.pick_open (
        { directory = true, title = 'Open Repository' },
        function (paths, err)
          if err then
            fail (err)
            return
          end
          local path = paths and paths[1]
          if path then
            open_repo (path)
          end
        end
      )
    end

    local function open_recent ()
      if not picker then
        return
      end
      if #recent == 0 then
        tell ('No recent repositories yet.')
        return
      end
      local items = {} ---@type Proteus.PickItem[]
      for _, path in ipairs (recent) do
        items[#items + 1] = {
          label = (m.split_path (path)),
          detail = path,
          icon = 'folder-git-2',
          value = path,
        }
      end
      picker.pick ({
        items = items,
        placeholder = 'Open a recent repository',
        on_pick = function (item)
          open_repo (item.value --[[@as string]])
        end,
      })
    end

    ---@param e Git.Entry
    local function discard (e)
      local args = m.discard_args (e)
      if not args then
        return
      end
      local name = (m.split_path (e.path))
      local question = 'Discard the changes to "'
        .. name
        .. '"? This cannot be undone.'
      local yes = 'Discard'
      if e.kind == 'untracked' or e.kind == 'added' then
        question = 'Delete "'
          .. name
          .. '"? Git has no copy of it to bring back.'
        yes = 'Delete'
      end
      confirm (question, yes, function ()
        act (args)
      end)
    end

    ---@param fi integer
    ---@param hi integer
    local function apply_hunk (fi, hi)
      local f = shown_files[fi]
      local h = f and f.hunks[hi]
      if not f or not h then
        return
      end
      local sel = selection
      local e = sel
        and sel.kind == 'file'
        and m.find_entry (status, sel.group or '', sel.path or '')
      -- An untracked file is one hunk. git add stores it with the line endings the
      -- repository asks for, which git apply would not do.
      if e and e.kind == 'untracked' then
        act (m.stage_args (e))
        return
      end
      local patch = m.hunk_patch (f, h)
      if not patch then
        fail ('This hunk cannot be staged on its own.')
        return
      end
      act (m.apply_args (shown_staged), { stdin = patch })
    end

    ---Stages, or unstages, the lines picked in one hunk.
    ---@param fi integer
    ---@param hi integer
    local function apply_lines (fi, hi)
      local f = shown_files[fi]
      local h = f and f.hunks[hi]
      if not f or not h then
        return
      end
      local patch =
        m.lines_patch (f, h, picked[fi .. ':' .. hi] or {}, shown_staged)
      if not patch then
        fail (
          'Pick the lines to '
            .. (shown_staged and 'unstage' or 'stage')
            .. ' first.'
        )
        return
      end
      act (m.apply_args (shown_staged), { stdin = patch })
    end

    local function commit ()
      local st = status
      if not repo or not st then
        return
      end
      local text = message:value ()
      local amending = amend:checked ()
      if blank (text) then
        fail ('Write a commit message first.')
        message:focus ()
        return
      end
      if #st.staged == 0 and not amending then
        fail ('Stage some changes first.')
        return
      end
      git (m.commit_args (amending), { stdin = text }, function (res, err)
        if not res or res.code ~= 0 then
          fail (m.error_text (res, err))
        else
          message:value ('')
          amend:checked (false)
          local summary = m.summary (res)
          done (summary ~= '' and summary or 'Committed.')
        end
        refresh ()
      end)
    end

    ---@param hash string
    local function checkout (hash)
      local short = hash:sub (1, 7)
      confirm (
        'Check out commit '
          .. short
          .. '? HEAD will point at it instead of at a branch.',
        'Check Out',
        function ()
          act ({ 'switch', '--detach', hash }, nil, function ()
            done ('Checked out ' .. short .. '.')
          end)
        end
      )
    end

    local function new_branch ()
      if not picker then
        fail ('New Branch needs the command palette.')
        return
      end
      picker.input ({
        prompt = 'Name of the new branch',
        placeholder = 'feature/my-change',
        select = false,
        validate = m.check_branch_name,
        on_submit = function (name)
          act ({ 'switch', '-c', name }, nil, function ()
            done ('Switched to the new branch ' .. name .. '.')
          end)
        end,
      })
    end

    local function switch_branch ()
      if not picker then
        fail ('Switch Branch needs the command palette.')
        return
      end
      git (m.branch_args (), nil, function (res, err)
        if not res or res.code ~= 0 then
          fail (m.error_text (res, err))
          return
        end
        local branches = m.parse_branches (res.stdout)
        local items = {} ---@type Proteus.PickItem[]
        for _, c in ipairs (m.branch_choices (branches)) do
          items[#items + 1] =
            { label = c.label, detail = c.detail, icon = c.icon, value = c }
        end
        picker.pick ({
          items = items,
          placeholder = 'Switch to a branch',
          on_pick = function (item)
            local choice = item.value --[[@as Git.Choice]]
            if choice.action == 'create' then
              new_branch ()
              return
            end
            local args = m.switch_args (choice, branches)
            local name = choice.name or ''
            if choice.action == 'track' then
              name = name:match ('^[^/]+/(.+)$') or name
            end
            if args then
              act (args, nil, function ()
                done ('Switched to ' .. name .. '.')
              end)
            end
          end,
        })
      end)
    end

    ---Saves the changes away, with a message the user may type. `untracked` takes new files
    ---too.
    ---@param untracked boolean
    local function stash (untracked)
      if not picker then
        fail ('Stash needs the command palette to ask for a message.')
        return
      end
      picker.input ({
        prompt = untracked and 'Stash the changes and new files'
          or 'Stash the changes',
        placeholder = "A message, or nothing for Git's own",
        select = false,
        on_submit = function (text)
          act (m.stash_args (text, untracked), nil, function (res)
            local summary = m.summary (res)
            done (summary ~= '' and summary or 'Stashed.')
          end)
        end,
      })
    end

    ---Applies, pops or drops a stash. Dropping asks first.
    ---@param action 'apply'|'pop'|'drop'
    ---@param st Git.Stash
    local function stash_action (action, st)
      ---@type table<string, string>
      local DONE = {
        apply = 'Applied ',
        pop = 'Applied and dropped ',
        drop = 'Dropped ',
      }
      local function run ()
        act (m.stash_action_args (action, st.ref), nil, function ()
          done (DONE[action] .. st.ref .. '.')
          local sel = selection
          if sel and sel.kind == 'stash' and action ~= 'apply' then
            selection, shown_key = nil, nil
            show_placeholder ()
          end
        end)
      end
      if action == 'drop' then
        confirm (
          'Drop ' .. st.ref .. ' (' .. st.message .. ')? This cannot be undone.',
          'Drop',
          run
        )
      else
        run ()
      end
    end

    ---Lists the stashes, then what to do with the one picked.
    local function pick_stash ()
      if not picker then
        fail ('Stashes needs the command palette.')
        return
      end
      git (m.stash_list_args (), nil, function (res, err)
        if not res or res.code ~= 0 then
          fail (m.error_text (res, err))
          return
        end
        local list = m.parse_stashes (res.stdout)
        if #list == 0 then
          tell ('There are no stashes.')
          return
        end
        local items = {} ---@type Proteus.PickItem[]
        for _, st in ipairs (list) do
          items[#items + 1] = {
            label = st.message,
            detail = st.ref .. ' · ' .. st.date,
            icon = 'archive',
            value = st,
          }
        end
        picker.pick ({
          items = items,
          placeholder = 'Pick a stash',
          on_pick = function (item)
            local st = item.value --[[@as Git.Stash]]
            picker.pick ({
              placeholder = st.message,
              items = {
                {
                  label = 'Apply',
                  detail = 'and keep the stash',
                  icon = 'archive-restore',
                  value = 'apply',
                },
                {
                  label = 'Pop',
                  detail = 'apply, then drop the stash',
                  icon = 'package-open',
                  value = 'pop',
                },
                { label = 'Show Changes', icon = 'file-diff', value = 'show' },
                {
                  label = 'Drop',
                  detail = 'throw it away',
                  icon = 'trash-2',
                  value = 'drop',
                },
              },
              on_pick = function (choice)
                local what = choice.value --[[@as string]]
                if what == 'show' then
                  show_stash (st)
                else
                  stash_action (what --[[@as 'apply'|'pop'|'drop']], st)
                end
              end,
            })
          end,
        })
      end)
    end

    -- Merge, rebase, cherry-pick, revert and reset -----------------------------------------

    ---Runs a merge, rebase, cherry-pick or revert. One that stops at conflicts says so, and the
    ---bar above the Changes list then offers Continue and Abort.
    ---@param args string[]
    ---@param success string
    ---@param opts? { stdin?: string }
    ---@param after? fun()
    local function run_operation (args, success, opts, after)
      local env = m.operation_env ()
      git (args, { env = env, stdin = opts and opts.stdin }, function (res, err)
        if res and res.code == 0 then
          done (success)
          if after then
            after ()
          end
        elseif m.stopped_at_conflict (res) then
          tell (
            'Stopped at conflicts. Resolve them and stage them, then Continue.'
          )
          views.show ('git.changes')
        else
          fail (m.error_text (res, err))
        end
        refresh ()
      end)
    end

    ---Lists the branches other than the current one, then calls `fn` with the one picked.
    ---@param placeholder string
    ---@param locals_only boolean
    ---@param fn fun(name: string)
    local function pick_branch (placeholder, locals_only, fn)
      if not picker then
        fail ('This needs the command palette.')
        return
      end
      git (m.branch_args (), nil, function (res, err)
        if not res or res.code ~= 0 then
          fail (m.error_text (res, err))
          return
        end
        local items = {} ---@type Proteus.PickItem[]
        for _, b in ipairs (m.other_branches (m.parse_branches (res.stdout))) do
          if not (locals_only and b.remote) then
            items[#items + 1] = {
              label = b.name,
              detail = b.remote and 'remote' or b.upstream,
              icon = b.remote and 'cloud' or 'git-branch',
              value = b.name,
            }
          end
        end
        if #items == 0 then
          tell ('There is no other branch.')
          return
        end
        picker.pick ({
          items = items,
          placeholder = placeholder,
          on_pick = function (item)
            fn (item.value --[[@as string]])
          end,
        })
      end)
    end

    local function merge_branch ()
      pick_branch ('Merge a branch into the current one', false, function (name)
        run_operation (m.merge_args (name), 'Merged ' .. name .. '.')
      end)
    end

    local function rebase_branch ()
      pick_branch (
        'Rebase the current branch onto a branch',
        false,
        function (name)
          local st = status
          local here = st and m.branch_text (st) or 'the current branch'
          confirm (
            'Rebase '
              .. here
              .. ' onto '
              .. name
              .. '? Its own commits get new hashes, so a branch already pushed needs a forced push.',
            'Rebase',
            function ()
              run_operation (
                m.rebase_args (name),
                'Rebased onto ' .. name .. '.'
              )
            end
          )
        end
      )
    end

    ---@param c Git.Commit
    local function cherry_pick (c)
      run_operation (
        m.cherry_pick_args (c.hash, #c.parents),
        'Cherry-picked ' .. c.short .. '.'
      )
    end

    ---@param c Git.Commit
    local function revert (c)
      confirm (
        'Revert ' .. c.short .. '? A new commit undoes its changes.',
        'Revert',
        function ()
          run_operation (
            m.revert_args (c.hash, #c.parents),
            'Reverted ' .. c.short .. '.'
          )
        end
      )
    end

    ---@param c Git.Commit
    local function reset_to (c)
      if not picker then
        fail ('Reset needs the command palette.')
        return
      end
      picker.pick ({
        placeholder = 'Reset the current branch to ' .. c.short,
        items = {
          {
            label = 'Soft',
            detail = 'keep the changes since then, staged',
            icon = 'git-commit-horizontal',
            value = 'soft',
          },
          {
            label = 'Mixed',
            detail = 'keep the changes since then, not staged',
            icon = 'git-commit-horizontal',
            value = 'mixed',
          },
          {
            label = 'Hard',
            detail = 'throw away the commits since then and every change',
            icon = 'triangle-alert',
            value = 'hard',
          },
        },
        on_pick = function (item)
          local mode = item.value --[[@as 'soft'|'mixed'|'hard']]
          local function run ()
            act (m.reset_args (mode, c.hash), nil, function ()
              done ('Reset to ' .. c.short .. '.')
            end)
          end
          if mode == 'hard' then
            confirm (
              'Reset hard to '
                .. c.short
                .. '? Every uncommitted change is lost, and the commits after it leave the branch.',
              'Reset',
              run
            )
          else
            run ()
          end
        end,
      })
    end

    ---@param c Git.Commit
    local function branch_here (c)
      if not picker then
        return
      end
      picker.input ({
        prompt = 'Name of the new branch at ' .. c.short,
        placeholder = 'feature/my-change',
        select = false,
        validate = m.check_branch_name,
        on_submit = function (name)
          act ({ 'switch', '-c', name, c.hash }, nil, function ()
            done ('Switched to the new branch ' .. name .. '.')
          end)
        end,
      })
    end

    local function delete_branch ()
      pick_branch ('Delete a branch', true, function (name)
        confirm ('Delete the branch ' .. name .. '?', 'Delete', function ()
          git (m.delete_branch_args (name, false), nil, function (res, err)
            if res and res.code == 0 then
              done ('Deleted ' .. name .. '.')
            elseif m.not_merged (res) then
              confirm (
                name
                  .. ' has commits that no other branch has. Delete it anyway? They are lost.',
                'Delete Anyway',
                function ()
                  act (m.delete_branch_args (name, true), nil, function ()
                    done ('Deleted ' .. name .. '.')
                  end)
                end
              )
            else
              fail (m.error_text (res, err))
            end
            refresh ()
          end)
        end)
      end)
    end

    local function rename_branch ()
      local st = status
      local old = st and not st.detached and st.branch or nil
      if not picker or not old then
        fail ('Switch to a branch to rename it.')
        return
      end
      picker.input ({
        prompt = 'New name for ' .. old,
        value = old,
        validate = m.check_branch_name,
        on_submit = function (name)
          if name ~= old then
            act (m.rename_branch_args (old, name), nil, function ()
              done ('Renamed ' .. old .. ' to ' .. name .. '.')
            end)
          end
        end,
      })
    end

    local function continue_operation ()
      local op, st = operation, status
      if not op or not st then
        return
      end
      if m.conflict_count (st) > 0 then
        fail ('Resolve the conflicts and stage them first.')
        return
      end
      local text = message:value ()
      local own = op == 'merge' and not blank (text)
      ---@type table<Git.Operation, string>
      local FINISHED = {
        merge = 'Merged.',
        rebase = 'Rebased.',
        ['cherry-pick'] = 'Cherry-picked.',
        revert = 'Reverted.',
      }
      run_operation (
        m.continue_args (op, own),
        FINISHED[op],
        { stdin = own and text or nil },
        function ()
          if own then
            message:value ('')
          end
        end
      )
    end

    local function abort_operation ()
      local op = operation
      if not op then
        return
      end
      confirm (
        'Abort? The files go back to how they were before it started.',
        'Abort',
        function ()
          act (m.abort_args (op), nil, function ()
            done ('Aborted.')
          end)
        end
      )
    end

    -- The fetch, pull, push or clone running now, which Cancel stops.
    local remote_run = nil ---@type Proteus.RunHandle?
    local cancelled = false

    ---Runs a git command that reaches a remote, with no password prompt that could wait for
    ---ever, and shows it as busy until it ends. `cb` gets nothing when it was cancelled.
    ---@param label string What the status bar shows, such as `'Pushing…'`.
    ---@param args string[]
    ---@param cwd string?
    ---@param cb fun(res: Proteus.RunResult?, err: string?)
    local function run_remote (label, args, cwd, cb)
      busy = label
      cancelled = false
      render_bar ()
      git (
        { 'config', '--get', 'core.sshCommand' },
        { cwd = cwd },
        function (cfg)
          if cancelled then
            busy = nil
            render_bar ()
            return
          end
          local own = cfg and cfg.code == 0 and cfg.stdout or nil
          remote_run = git (
            args,
            { cwd = cwd, env = m.remote_env (own) },
            function (res, err)
              remote_run = nil
              busy = nil
              render_bar ()
              if cancelled then
                tell ('Cancelled.')
                if repo then
                  refresh ()
                end
                return
              end
              cb (res, err)
            end
          )
        end
      )
    end

    local function cancel_remote ()
      if busy == nil then
        return
      end
      cancelled = true
      if remote_run then
        remote_run.cancel ()
      end
    end

    ---@type table<string, { label: string, done: string }>
    local REMOTE = {
      fetch = { label = 'Fetching…', done = 'Fetched.' },
      pull = { label = 'Pulling…', done = 'Pulled.' },
      push = { label = 'Pushing…', done = 'Pushed.' },
    }

    ---Finds the remote a branch with no upstream is pushed to, then calls `cb` with it.
    ---@param st Git.Status
    ---@param cb fun(remote: string?)
    local function find_push_remote (st, cb)
      if m.has_upstream (st) or not st.branch then
        cb (nil)
        return
      end
      local key = 'branch.' .. st.branch .. '.remote'
      git ({ 'config', '--get', key }, nil, function (cfg)
        git ({ 'remote' }, nil, function (res, err)
          if not res or res.code ~= 0 then
            fail (m.error_text (res, err))
            return
          end
          local configured = cfg and cfg.code == 0 and cfg.stdout or nil
          local name, why = m.push_remote (configured, res.stdout)
          if not name then
            fail (why or 'Cannot push now.')
            return
          end
          cb (name)
        end)
      end)
    end

    ---Fetch, Pull and Push can take a while, so they run one at a time and show in the status
    ---bar while they run. Clicking it there, or Cancel, stops one.
    ---@param op 'fetch'|'pull'|'push'
    ---@param push_remote? string The remote a branch with no upstream goes to.
    local function remote (op, push_remote)
      local st = status
      if busy or not repo or not st then
        return
      end
      local args = { op }
      if op == 'push' then
        if not m.has_upstream (st) and st.branch and not push_remote then
          find_push_remote (st, function (name)
            remote ('push', name)
          end)
          return
        end
        local push, why = m.push_args (st, push_remote)
        if not push then
          fail (why or 'Cannot push now.')
          return
        end
        args = push
      end
      local spec = REMOTE[op]
      run_remote (spec.label, args, repo, function (res, err)
        if not res or res.code ~= 0 then
          fail (m.error_text (res, err))
        elseif op == 'pull' then
          local summary = m.summary (res)
          done (summary ~= '' and (spec.done .. ' ' .. summary) or spec.done)
        else
          done (spec.done)
        end
        refresh ()
      end)
    end

    -- Tags and remotes ----------------------------------------------------------------------

    ---@param c Git.Commit
    local function tag_here (c)
      if not picker then
        fail ('Create Tag needs the command palette.')
        return
      end
      picker.input ({
        prompt = 'Name of the new tag on ' .. c.short,
        placeholder = 'v1.0.0',
        select = false,
        validate = m.check_tag_name,
        on_submit = function (name)
          picker.input ({
            prompt = 'A message for ' .. name .. ', or nothing for a plain tag',
            select = false,
            on_submit = function (text)
              act (m.tag_args (name, c.hash, text), nil, function ()
                done ('Tagged ' .. c.short .. ' as ' .. name .. '.')
              end)
            end,
          })
        end,
      })
    end

    ---Lists the tags, then calls `fn` with the one picked. `all` adds an item for every tag,
    ---which passes nil.
    ---@param placeholder string
    ---@param all boolean
    ---@param fn fun(name: string?)
    local function pick_tag (placeholder, all, fn)
      if not picker then
        fail ('This needs the command palette.')
        return
      end
      git (m.tag_list_args (), nil, function (res, err)
        if not res or res.code ~= 0 then
          fail (m.error_text (res, err))
          return
        end
        local tags = m.parse_tags (res.stdout)
        if #tags == 0 then
          tell ('There are no tags.')
          return
        end
        local items = {} ---@type Proteus.PickItem[]
        if all then
          items[1] = { label = 'Every tag', icon = 'tags', value = false }
        end
        for _, t in ipairs (tags) do
          items[#items + 1] = { label = t, icon = 'tag', value = t }
        end
        picker.pick ({
          items = items,
          placeholder = placeholder,
          on_pick = function (item)
            fn (item.value or nil)
          end,
        })
      end)
    end

    ---Lists the remotes, then calls `fn` with the one picked. With `only_one`, a repository
    ---with a single remote picks it without asking.
    ---@param placeholder string
    ---@param only_one boolean
    ---@param fn fun(r: Git.Remote)
    local function pick_remote (placeholder, only_one, fn)
      git ({ 'remote', '-v' }, nil, function (res, err)
        if not res or res.code ~= 0 then
          fail (m.error_text (res, err))
          return
        end
        local remotes = m.parse_remotes (res.stdout)
        if #remotes == 0 then
          tell ('This repository has no remote.')
          return
        end
        if only_one and #remotes == 1 then
          fn (remotes[1])
          return
        end
        if not picker then
          fail ('This needs the command palette.')
          return
        end
        local items = {} ---@type Proteus.PickItem[]
        for _, r in ipairs (remotes) do
          items[#items + 1] =
            { label = r.name, detail = r.url, icon = 'cloud', value = r }
        end
        picker.pick ({
          items = items,
          placeholder = placeholder,
          on_pick = function (item)
            fn (item.value --[[@as Git.Remote]])
          end,
        })
      end)
    end

    local function delete_tag ()
      pick_tag ('Delete a tag', false, function (name)
        if not name then
          return
        end
        confirm (
          'Delete the tag '
            .. name
            .. '? A copy already pushed stays on the remote.',
          'Delete',
          function ()
            act ({ 'tag', '-d', name }, nil, function ()
              done ('Deleted the tag ' .. name .. '.')
            end)
          end
        )
      end)
    end

    local function push_tag ()
      pick_tag ('Push a tag', true, function (name)
        pick_remote ('Push it to', true, function (r)
          if busy then
            return
          end
          run_remote (
            'Pushing…',
            m.push_tag_args (r.name, name),
            repo,
            function (res, err)
              if not res or res.code ~= 0 then
                fail (m.error_text (res, err))
              else
                done (
                  'Pushed ' .. (name or 'every tag') .. ' to ' .. r.name .. '.'
                )
              end
              refresh ()
            end
          )
        end)
      end)
    end

    local function add_remote ()
      if not picker then
        fail ('Add Remote needs the command palette.')
        return
      end
      picker.input ({
        prompt = 'Name of the new remote',
        placeholder = 'upstream',
        select = false,
        validate = m.check_remote_name,
        on_submit = function (name)
          picker.input ({
            prompt = 'Address of ' .. name,
            placeholder = 'https://github.com/owner/repo.git',
            select = false,
            validate = function (text)
              return blank (text) and 'Type an address' or nil
            end,
            on_submit = function (url)
              local address = url:match ('^%s*(.-)%s*$') or url
              act ({ 'remote', 'add', '--', name, address }, nil, function ()
                done ('Added the remote ' .. name .. '.')
              end)
            end,
          })
        end,
      })
    end

    local function remove_remote ()
      pick_remote ('Remove a remote', false, function (r)
        confirm (
          'Remove the remote '
            .. r.name
            .. '? Its branches here go too, but nothing on the remote changes.',
          'Remove',
          function ()
            act ({ 'remote', 'remove', r.name }, nil, function ()
              done ('Removed the remote ' .. r.name .. '.')
            end)
          end
        )
      end)
    end

    local function rename_remote ()
      pick_remote ('Rename a remote', false, function (r)
        if not picker then
          return
        end
        picker.input ({
          prompt = 'New name for ' .. r.name,
          value = r.name,
          validate = m.check_remote_name,
          on_submit = function (name)
            if name ~= r.name then
              act ({ 'remote', 'rename', r.name, name }, nil, function ()
                done ('Renamed the remote ' .. r.name .. ' to ' .. name .. '.')
              end)
            end
          end,
        })
      end)
    end

    local function set_remote_url ()
      pick_remote ('Change the address of a remote', false, function (r)
        if not picker then
          return
        end
        picker.input ({
          prompt = 'New address of ' .. r.name,
          value = r.url,
          validate = function (text)
            return blank (text) and 'Type an address' or nil
          end,
          on_submit = function (url)
            local address = url:match ('^%s*(.-)%s*$') or url
            act ({ 'remote', 'set-url', '--', r.name, address }, nil, function ()
              done ('Changed the address of ' .. r.name .. '.')
            end)
          end,
        })
      end)
    end

    -- Views and events ----------------------------------------------------------------------

    -- Inside the Code Editor the views come after the file tree and Search, and with no
    -- folder open they stay away, as there is nothing to show.
    if not (embedded and not folder) then
      views.add ('left', {
        id = 'git.changes',
        title = embedded and 'Source Control' or 'Changes',
        icon = 'git-branch',
        order = embedded and 20 or 1,
        key = embedded and 'ctrl+shift+g' or nil,
        content = ui.div ({
          class = 'git-side',
          head,
          op_bar,
          changes_list,
          commit_box,
        }),
      })
      views.add ('left', {
        id = 'git.history',
        title = 'History',
        icon = 'history',
        order = embedded and 21 or 2,
        content = ui.div ({ class = 'git-side', history_tools, history_list }),
        on_show = function ()
          history_open = true
          load_history ()
        end,
      })
    end
    ---@param id string
    app.on ('views:shown', function (id)
      for _, v in ipairs (views.list ('left')) do
        if v.id == id then
          history_open = id == 'git.history'
        end
      end
    end)

    changes_list:on ('click', function (ev)
      local item = ev.item
      if item == 'open' then
        commands.run ('git.open')
        return true
      elseif item == 'init' then
        commands.run ('git.init')
        return true
      elseif item == 'trust' then
        if project and project.ask_trust then
          project.ask_trust ('Git')
        end
        return true
      elseif item == 'stage-all' then
        commands.run ('git.stage_all')
        return true
      elseif item == 'unstage-all' then
        commands.run ('git.unstage_all')
        return true
      elseif item == 'show-all-s' or item == 'show-all-u' then
        show_all[item:sub (-1)] = true
        render_changes ()
        return true
      end
      local action, group, path = m.parse_item (item)
      local e = group and path and m.find_entry (status, group, path)
      if not e then
        return nil
      end
      if action == 'open' then
        select_entry (e)
      elseif action == 'stage' then
        act (m.stage_args (e))
      elseif action == 'unstage' then
        act (m.unstage_args (e))
      elseif action == 'discard' then
        discard (e)
      end
      return true
    end)

    -- The search runs a moment after typing stops, or at once on Enter.
    local search_timer = nil ---@type fun()?
    local function run_search ()
      if search_timer then
        search_timer ()
        search_timer = nil
      end
      local text = history_search:value ()
      if text == log_search then
        return
      end
      log_search = text
      commits, log_more = {}, false
      load_history ()
    end
    history_search:on ('input', function ()
      if search_timer then
        search_timer ()
      end
      search_timer = app.timer.after (300, function ()
        search_timer = nil
        run_search ()
      end)
      return nil
    end)
    history_search:on ('keydown', function (ev)
      if ev.key == 'Enter' then
        run_search ()
        return true
      elseif ev.key == 'Escape' and history_search:value () ~= '' then
        history_search:value ('')
        run_search ()
        return true
      end
      return nil
    end)

    history_list:on ('click', function (ev)
      local hash = ev.item
      if hash == 'more' then
        load_history (true)
        return true
      end
      if hash and hash:find ('^%x+$') then
        select_commit (hash)
        return true
      end
      return nil
    end)

    main_body:on ('click', function (ev)
      local item = ev.item
      if not item then
        return nil
      end
      local blamed = item:match ('^blame:(%x+)$')
      if blamed then
        select_commit (blamed)
        return true
      end
      local how = item:match ('^conflict:(%a+)$')
      if how then
        local sel = selection
        local e = sel
          and sel.kind == 'file'
          and m.find_entry (status, sel.group or '', sel.path or '')
        local current = repo
        if e and e.kind == 'conflicted' and current then
          if how == 'open' then
            open_file (m.join (current, e.path))
          elseif how == 'ours' or how == 'theirs' or how == 'resolved' then
            resolve (e, how)
          end
        end
        return true
      end
      -- A click on a line's numbers picks it, or puts it back, and draws the diff again with
      -- the line marked.
      local pf, ph, pl = item:match ('^line:(%d+):(%d+):(%d+)$')
      if pf then
        local opts = shown_opts
        if opts then
          local key = pf .. ':' .. ph
          local set = picked[key] or {}
          picked[key] = set
          local li = math.floor (tonumber (pl) or 0)
          set[li] = not set[li] or nil
          if not next (set) then
            picked[key] = nil
          end
          opts.picked = picked
          show_main (shown_top .. m.diff_html (shown_files, opts), true)
        end
        return true
      end
      local lf, lh = item:match ('^lines:(%d+):(%d+)$')
      if lf then
        apply_lines (
          math.floor (tonumber (lf) or 0),
          math.floor (tonumber (lh) or 0)
        )
        return true
      end
      local fi, hi = item:match ('^hunk:(%d+):(%d+)$')
      if fi then
        apply_hunk (
          math.floor (tonumber (fi) or 0),
          math.floor (tonumber (hi) or 0)
        )
        return true
      end
      if item == 'open' then
        commands.run ('git.open')
        return true
      end
      local path = item:match ('^recent:(.*)$')
      if path then
        open_repo (path)
        return true
      end
      return nil
    end)

    message:on ('keydown', function (ev)
      if ev.key == 'Enter' and (ev.ctrl or ev.meta) then
        commands.run ('git.commit')
        return true
      end
      return nil
    end)

    -- Ticking Amend with an empty box brings back the last commit's message to edit.
    amend:on ('change', function (ev)
      local st = status
      if
        not ev.checked
        or not st
        or st.initial
        or not blank (message:value ())
      then
        return nil
      end
      git ({ 'log', '-1', '--format=%B' }, nil, function (res)
        if res and res.code == 0 and blank (message:value ()) then
          local last = res.stdout:gsub ('%s+$', '')
          message:value (last)
        end
      end)
      return nil
    end)

    -- Coming back to the window reads the status again, in case files changed outside. In a
    -- large repository, where that takes a while, it waits a little longer between reads.
    local focus_timer = nil ---@type fun()?
    app.dom.on_global ('focus', function ()
      if focus_timer then
        return nil
      end
      local wait = status_done_at + m.focus_gap (status_took) - app.util.now ()
      if wait <= 0 then
        refresh ()
        return nil
      end
      focus_timer = app.timer.after (wait, function ()
        focus_timer = nil
        refresh ()
      end)
      return nil
    end)

    -- Inside the Code Editor, a save or any change on disk shows up in the lists soon after.
    if embedded then
      local soon = nil ---@type fun()?
      local function refresh_soon ()
        if soon then
          soon ()
        end
        soon = app.timer.after (300, function ()
          soon = nil
          refresh ()
        end)
      end
      -- proteus.code.project sends what changed in the folder as `code:disk_changed`.
      app.on ('code:disk_changed', refresh_soon)
      app.on ('editor:saved', refresh_soon)
    end

    if menus then
      menus.attach (changes_list, function (ev)
        local _, group, path = m.parse_item (ev.item)
        local e = group and path and m.find_entry (status, group, path)
        local current = repo
        if not e or not current then
          return nil
        end
        local full = m.join (current, e.path)
        ---@type Proteus.MenuItem[]
        local items = {}
        if e.staged then
          items[#items + 1] = {
            label = 'Unstage',
            icon = 'minus',
            run = function ()
              act (m.unstage_args (e))
            end,
          }
        else
          items[#items + 1] = {
            label = 'Stage',
            icon = 'plus',
            run = function ()
              act (m.stage_args (e))
            end,
          }
        end
        if m.discard_args (e) then
          items[#items + 1] = {
            label = 'Discard Changes',
            icon = 'undo-2',
            danger = true,
            run = function ()
              discard (e)
            end,
          }
        end
        if e.kind == 'conflicted' then
          items = {
            {
              label = 'Accept Current',
              icon = 'arrow-left',
              run = function ()
                resolve (e, 'ours')
              end,
            },
            {
              label = 'Accept Incoming',
              icon = 'arrow-right',
              run = function ()
                resolve (e, 'theirs')
              end,
            },
            {
              label = 'Mark Resolved',
              icon = 'check',
              run = function ()
                resolve (e, 'resolved')
              end,
            },
          }
        end
        items[#items + 1] = { separator = true }
        items[#items + 1] = {
          label = 'Open File',
          icon = 'file',
          disabled = e.kind == 'deleted',
          run = function ()
            open_file (full)
          end,
        }
        items[#items + 1] = {
          label = 'File History',
          icon = 'file-clock',
          disabled = e.kind == 'untracked' or e.kind == 'added',
          run = function ()
            history_of (e.path)
          end,
        }
        items[#items + 1] = {
          label = 'Blame',
          icon = 'user-round-pen',
          disabled = e.kind == 'untracked'
            or e.kind == 'added'
            or e.kind == 'deleted'
            or e.kind == 'conflicted',
          run = function ()
            show_blame (e.path)
          end,
        }
        items[#items + 1] = {
          label = 'Reveal in Folder',
          icon = 'folder-open',
          run = function ()
            local where = m.native (m.parent (full), app.os)
            app.system.open_path (where, function (_, err)
              if err then
                fail (err)
              end
            end)
          end,
        }
        items[#items + 1] = {
          label = 'Copy Path',
          icon = 'copy',
          run = function ()
            app.system.clipboard (m.native (full, app.os))
          end,
        }
        return items
      end)

      menus.attach (history_list, function (ev)
        local hash = ev.item
        if not hash or not hash:find ('^%x+$') then
          return nil
        end
        local c = nil ---@type Git.Commit?
        for _, one in ipairs (commits) do
          if one.hash == hash then
            c = one
          end
        end
        local idle_now = operation == nil and busy == nil
        return {
          {
            label = 'Copy Hash',
            icon = 'copy',
            run = function ()
              app.system.clipboard (hash)
              tell ('Copied ' .. hash:sub (1, 7) .. '.')
            end,
          },
          {
            label = 'Check Out This Commit',
            icon = 'git-commit-horizontal',
            run = function ()
              checkout (hash)
            end,
          },
          {
            label = 'Create Tag Here…',
            icon = 'tag',
            disabled = not c,
            run = function ()
              if c then
                tag_here (c)
              end
            end,
          },
          {
            label = 'Create Branch Here…',
            icon = 'git-branch-plus',
            disabled = not c,
            run = function ()
              if c then
                branch_here (c)
              end
            end,
          },
          { separator = true },
          {
            label = 'Cherry-Pick',
            icon = 'git-pull-request-arrow',
            disabled = not c or not idle_now,
            run = function ()
              if c then
                cherry_pick (c)
              end
            end,
          },
          {
            label = 'Revert',
            icon = 'undo-2',
            disabled = not c or not idle_now,
            run = function ()
              if c then
                revert (c)
              end
            end,
          },
          {
            label = 'Reset Current Branch to Here…',
            icon = 'rotate-ccw',
            danger = true,
            disabled = not c or not idle_now,
            run = function ()
              if c then
                reset_to (c)
              end
            end,
          },
        }
      end)
    end

    -- Commands ------------------------------------------------------------------------------

    ---@return boolean
    local function can_open ()
      return desktop and git_found == true
    end

    ---@return boolean
    local function has_repo ()
      return repo ~= nil and git_found == true
    end

    ---@return boolean
    local function idle ()
      return has_repo () and busy == nil
    end

    ---Asks for a repository's address and a folder to put it in, clones it there, and opens
    ---the clone. Inside the Code Editor the clone opens as the folder.
    local function clone ()
      if not picker then
        fail ('Clone needs the command palette to ask for the address.')
        return
      end
      picker.input ({
        prompt = 'Address of the repository to clone',
        placeholder = 'https://github.com/owner/repo.git',
        select = false,
        validate = function (text)
          if blank (text) then
            return 'Type an address'
          end
          if m.clone_name (text) == '' then
            return 'The address needs a repository name at its end'
          end
          return nil
        end,
        on_submit = function (text)
          local url = text:match ('^%s*(.-)%s*$') or text
          local name = m.clone_name (url)
          app.fs.pick_open (
            { directory = true, title = 'Choose the folder the clone goes in' },
            function (paths, err)
              if err then
                fail (err)
                return
              end
              local parent = paths and paths[1]
              if not parent then
                return
              end
              local target = m.join ((parent:gsub ('\\', '/')), name)
              tell ('Cloning ' .. name .. '…')
              run_remote (
                'Cloning…',
                { 'clone', '--', url, name },
                parent,
                function (res, run_err)
                  if not res or res.code ~= 0 then
                    fail (m.error_text (res, run_err))
                    return
                  end
                  done ('Cloned ' .. name .. '.')
                  if project then
                    project.open (target)
                  else
                    -- A clone brings no .git/config from elsewhere, so it is safe to open.
                    trust_repo (target)
                    open_repo (target)
                  end
                end
              )
            end
          )
        end,
      })
    end

    -- The standalone app picks its repository. Inside the Code Editor the folder is the
    -- repository, and Ctrl+O and Ctrl+R belong to the editor.
    if not embedded then
      commands.register ({
        id = 'git.open',
        category = 'Git',
        title = 'Open Repository',
        key = 'ctrl+o',
        icon = 'folder-open',
        toolbar = 1,
        when = can_open,
        run = pick_repo,
      })
      commands.register ({
        id = 'git.recent',
        category = 'Git',
        title = 'Open Recent',
        icon = 'clock',
        toolbar = 2,
        when = can_open,
        run = open_recent,
      })
    end
    commands.register ({
      id = 'git.clone',
      category = 'Git',
      title = 'Clone Repository…',
      icon = 'git-branch-plus',
      menu = embedded and 'File' or nil,
      group = 'folder',
      order = 5,
      when = function ()
        return can_open () and busy == nil
      end,
      run = clone,
    })
    commands.register ({
      id = 'git.init',
      category = 'Git',
      title = 'Initialize Repository',
      icon = 'git-branch-plus',
      when = function ()
        return embedded and folder ~= nil and not_repo and git_found == true
      end,
      run = function ()
        local here = folder
        if not here then
          return
        end
        git ({ 'init' }, { cwd = here }, function (res, err)
          if not res or res.code ~= 0 then
            fail (m.error_text (res, err))
            return
          end
          done ('Made a Git repository in ' .. (m.split_path (here)) .. '.')
          open_repo (here)
        end)
      end,
    })
    commands.register ({
      id = 'git.refresh',
      category = 'Git',
      title = 'Refresh',
      key = not embedded and 'ctrl+r' or nil,
      icon = 'refresh-cw',
      toolbar = not embedded and 3 or nil,
      -- Always runnable, so Ctrl+R never falls through and reloads the window.
      run = function ()
        if has_repo () then
          refresh ()
        end
      end,
    })
    commands.register ({
      id = 'git.branch',
      category = 'Git',
      title = 'Switch Branch',
      key = 'ctrl+shift+b',
      icon = 'git-branch',
      toolbar = not embedded and 4 or nil,
      when = has_repo,
      run = switch_branch,
    })
    commands.register ({
      id = 'git.fetch',
      category = 'Git',
      title = 'Fetch',
      icon = 'download',
      toolbar = not embedded and 5 or nil,
      when = idle,
      run = function ()
        remote ('fetch')
      end,
    })
    commands.register ({
      id = 'git.pull',
      category = 'Git',
      title = 'Pull',
      icon = 'arrow-down-to-line',
      toolbar = not embedded and 6 or nil,
      when = idle,
      run = function ()
        remote ('pull')
      end,
    })
    commands.register ({
      id = 'git.push',
      category = 'Git',
      title = 'Push',
      icon = 'arrow-up-from-line',
      toolbar = not embedded and 7 or nil,
      when = idle,
      run = function ()
        remote ('push')
      end,
    })
    commands.register ({
      id = 'git.cancel',
      category = 'Git',
      title = 'Cancel Fetch, Pull, Push or Clone',
      icon = 'circle-x',
      when = function ()
        return busy ~= nil
      end,
      run = cancel_remote,
    })
    commands.register ({
      id = 'git.commit',
      category = 'Git',
      title = 'Commit',
      icon = 'check',
      when = has_repo,
      run = commit,
    })
    ---@return boolean
    local function can_operate ()
      return idle () and operation == nil
    end
    commands.register ({
      id = 'git.merge',
      category = 'Git',
      title = 'Merge Branch…',
      icon = 'git-merge',
      when = can_operate,
      run = merge_branch,
    })
    commands.register ({
      id = 'git.rebase',
      category = 'Git',
      title = 'Rebase onto Branch…',
      icon = 'git-pull-request-arrow',
      when = can_operate,
      run = rebase_branch,
    })
    commands.register ({
      id = 'git.continue',
      category = 'Git',
      title = 'Continue Merge, Rebase, Cherry-Pick or Revert',
      icon = 'play',
      when = function ()
        return has_repo () and operation ~= nil
      end,
      run = continue_operation,
    })
    commands.register ({
      id = 'git.abort',
      category = 'Git',
      title = 'Abort Merge, Rebase, Cherry-Pick or Revert',
      icon = 'circle-x',
      when = function ()
        return has_repo () and operation ~= nil
      end,
      run = abort_operation,
    })
    commands.register ({
      id = 'git.skip',
      category = 'Git',
      title = 'Skip This Commit of the Rebase',
      icon = 'skip-forward',
      when = function ()
        return has_repo () and operation == 'rebase'
      end,
      run = function ()
        run_operation ({ 'rebase', '--skip' }, 'Skipped the commit.')
      end,
    })
    commands.register ({
      id = 'git.delete_branch',
      category = 'Git',
      title = 'Delete Branch…',
      icon = 'trash-2',
      when = has_repo,
      run = delete_branch,
    })
    commands.register ({
      id = 'git.rename_branch',
      category = 'Git',
      title = 'Rename Branch…',
      icon = 'pencil',
      when = has_repo,
      run = rename_branch,
    })
    commands.register ({
      id = 'git.toggle_split',
      category = 'Git',
      title = 'Toggle Side-by-Side Diff',
      icon = 'columns-2',
      toolbar = not embedded and 8 or nil,
      run = function ()
        split_view = not split_view
        app.store.set ('split', split_view)
        local sel = selection
        if not sel then
          return
        end
        if sel.kind == 'file' then
          local e = m.find_entry (status, sel.group or '', sel.path or '')
          if e then
            shown_key = nil
            show_entry (e)
          end
        elseif sel.kind == 'commit' and sel.hash then
          select_commit (sel.hash)
        elseif sel.kind == 'stash' and sel.stash then
          show_stash (sel.stash)
        end
      end,
    })
    commands.register ({
      id = 'git.delete_tag',
      category = 'Git',
      title = 'Delete Tag…',
      icon = 'tag',
      when = has_repo,
      run = delete_tag,
    })
    commands.register ({
      id = 'git.push_tag',
      category = 'Git',
      title = 'Push Tag…',
      icon = 'tag',
      when = idle,
      run = push_tag,
    })
    commands.register ({
      id = 'git.add_remote',
      category = 'Git',
      title = 'Add Remote…',
      icon = 'cloud',
      when = has_repo,
      run = add_remote,
    })
    commands.register ({
      id = 'git.remove_remote',
      category = 'Git',
      title = 'Remove Remote…',
      icon = 'cloud-off',
      when = has_repo,
      run = remove_remote,
    })
    commands.register ({
      id = 'git.rename_remote',
      category = 'Git',
      title = 'Rename Remote…',
      icon = 'cloud',
      when = has_repo,
      run = rename_remote,
    })
    commands.register ({
      id = 'git.set_remote_url',
      category = 'Git',
      title = 'Change Remote Address…',
      icon = 'cloud',
      when = has_repo,
      run = set_remote_url,
    })
    commands.register ({
      id = 'git.stash',
      category = 'Git',
      title = 'Stash Changes…',
      icon = 'archive',
      when = has_repo,
      run = function ()
        stash (false)
      end,
    })
    commands.register ({
      id = 'git.stash_all',
      category = 'Git',
      title = 'Stash Changes and New Files…',
      icon = 'archive',
      when = has_repo,
      run = function ()
        stash (true)
      end,
    })
    commands.register ({
      id = 'git.stash_pop',
      category = 'Git',
      title = 'Pop Latest Stash',
      icon = 'package-open',
      when = has_repo,
      run = function ()
        act ({ 'stash', 'pop' }, nil, function ()
          done ('Applied and dropped the latest stash.')
        end)
      end,
    })
    commands.register ({
      id = 'git.stashes',
      category = 'Git',
      title = 'Stashes…',
      icon = 'archive',
      when = has_repo,
      run = pick_stash,
    })
    commands.register ({
      id = 'git.stage_all',
      category = 'Git',
      title = 'Stage All Changes',
      icon = 'plus',
      when = has_repo,
      run = function ()
        act ({ 'add', '-A' })
      end,
    })
    commands.register ({
      id = 'git.unstage_all',
      category = 'Git',
      title = 'Unstage All Changes',
      icon = 'minus',
      when = has_repo,
      run = function ()
        act ({ 'reset', '-q' })
      end,
    })
    commands.register ({
      id = 'git.show_changes',
      category = 'Git',
      title = 'Show Changes',
      icon = 'git-branch',
      run = function ()
        views.show ('git.changes')
      end,
    })
    commands.register ({
      id = 'git.history_all',
      category = 'Git',
      title = 'Show Every Commit',
      icon = 'history',
      when = function ()
        return has_repo () and log_path ~= nil
      end,
      run = function ()
        history_of (nil)
      end,
    })
    -- Inside the Code Editor, the file in front.
    ---@return string?
    local function current_file ()
      local doc = editor and editor.current ()
      local top = repo
      if not doc or not top then
        return nil
      end
      return m.relative (top, doc.path, app.os)
    end
    ---Calls `fn` with the file in front in the Code Editor, or else one picked in the
    ---system's dialog, as a path from the repository root.
    ---@param fn fun(path: string)
    local function with_file (fn)
      local path = current_file ()
      local top = repo
      if path or not top then
        if path then
          fn (path)
        end
        return
      end
      app.fs.pick_open ({
        title = 'Pick a file in the repository',
        default_path = m.native (top, app.os),
      }, function (paths, err)
        if err then
          fail (err)
          return
        end
        local picked_path = paths and paths[1]
        if not picked_path then
          return
        end
        local rel = m.relative (top, picked_path, app.os)
        if rel then
          fn (rel)
        else
          fail ('That file is not in this repository.')
        end
      end)
    end
    commands.register ({
      id = 'git.file_history',
      category = 'Git',
      title = 'Show File History',
      icon = 'file-clock',
      when = has_repo,
      run = function ()
        with_file (history_of)
      end,
    })
    commands.register ({
      id = 'git.blame',
      category = 'Git',
      title = 'Blame File',
      icon = 'user-round-pen',
      when = has_repo,
      run = function ()
        with_file (show_blame)
      end,
    })
    commands.register ({
      id = 'git.show_history',
      category = 'Git',
      title = 'Show History',
      icon = 'history',
      run = function ()
        views.show ('git.history')
      end,
    })
    -- The standalone app's own chrome, which the Code Editor has already.
    if not embedded then
      commands.register ({
        id = 'git.close',
        category = 'Git',
        title = 'Close Repository',
        icon = 'x',
        when = has_repo,
        run = close_repo,
      })
      commands.register ({
        id = 'git.theme',
        category = 'Git',
        title = 'Change Theme',
        icon = 'palette',
        toolbar = 90,
        toolbar_align = 'right',
        run = function ()
          commands.run ('theme.choose')
        end,
      })
      commands.register ({
        id = 'git.switch_app',
        category = 'Git',
        title = 'Switch App',
        icon = 'layers',
        toolbar = 91,
        toolbar_align = 'right',
        run = function ()
          commands.run ('profile.switch')
        end,
      })
    end

    -- Start ---------------------------------------------------------------------------------

    render_side ()
    render_bar ()
    show_placeholder ()
    if desktop then
      local started = pcall (app.process.which, 'git', function (path)
        git_found = path ~= nil
        render_side ()
        show_placeholder ()
        if git_found and embedded then
          if folder and not untrusted then
            open_repo (folder, true)
          end
        elseif git_found and recent[1] and app.store.get ('reopen', true) then
          open_repo (recent[1], true)
        end
      end)
      if not started then
        git_found = false
        render_side ()
        show_placeholder ()
      end
    end
  end,
}
