-- proteus.git: a Git client for any folder that holds a repository. It runs the real git program
-- and shows the changed files, the diff of each one, and the history. The left dock holds the
-- Changes and History views, and the main area shows a diff or a commit.
--
-- Inside the Code Editor, where the `project` service runs, it works on the open folder
-- instead of a repository picked here. The Changes view becomes Source Control, a diff opens
-- in a tab that can close, and the standalone app's toolbar and keys stay out of the way. It
-- sends each file's Git state as the `git:status` event, which colours the file tree.
--
-- git_parse holds the parsing, the command lines and the HTML, so its tests reach them. This
-- file holds the screen, the commands and the calls to git.

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
.git-line { display: flex; font-family: var(--font-mono); line-height: 19px; white-space: pre; }
.git-ln { flex: none; width: 48px; padding-right: 8px; text-align: right; color: var(--fg-faint); user-select: none; }
.git-sign { flex: none; width: 16px; text-align: center; color: var(--fg-faint); user-select: none; }
.git-code { flex: 1; padding-right: 16px; tab-size: 4; }
.git-l-add { background: color-mix(in srgb, var(--success) 15%, transparent); }
.git-l-add .git-sign { color: var(--success); }
.git-l-del { background: color-mix(in srgb, var(--danger) 15%, transparent); }
.git-l-del .git-sign { color: var(--danger); }
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
---@field kind 'file'|'commit'
---@field group? string `'s'` for the Staged list, `'u'` for the Changes list.
---@field path? string
---@field hash? string

---@param s string
---@return boolean
local function blank (s)
  return not s:find ('%S')
end

---@type Proteus.Plugin
return {
  name = 'Git',
  description = 'Stage, commit, branch and browse the history of a Git repository.',
  version = '1.2.0',
  requires = { proteus = '>=0.3.0', features = { 'permissions' } },
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
      local full = m.base_args ()
      for _, a in ipairs (args) do
        full[#full + 1] = a
      end
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
    ---@param opts? { stdin?: string }
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
        embedded and ui.div ({
          class = 'git-head-tools',
          head_tool ('refresh-cw', 'Refresh', 'git.refresh'),
          head_tool ('download', 'Fetch', 'git.fetch'),
          head_tool ('arrow-down-to-line', 'Pull', 'git.pull'),
          head_tool ('arrow-up-from-line', 'Push', 'git.push'),
          head_tool ('history', 'History', 'git.show_history'),
        }) or nil,
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
      elseif embedded and not_repo then
        text = 'This folder is not a Git repository'
      elseif embedded then
        text = 'Reading the repository…'
      end
      local button = ''
      if desktop and git_found and embedded and not_repo then
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
    local function draw_files (files, opts, key)
      if key == shown_key then
        return
      end
      local same_file = shown_key ~= nil
        and shown_key:match ('^[^\n]*') == key:match ('^[^\n]*')
      shown_files = files
      shown_staged = opts.staged == true
      shown_key = key
      show_main (m.diff_html (files, opts), same_file)
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
        staged = e.staged,
        label = label,
        empty = 'No changes to show.',
      }
      local prefix = (e.staged and 's:' or 'u:') .. e.path .. '\n'
      if e.kind == 'untracked' and e.path:sub (-1) == '/' then
        shown_files, shown_key = {}, nil
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
        draw_files (files, opts, prefix .. res.stdout)
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
        local top = show.commit and m.commit_html (show.commit) or ''
        show_main (
          top
            .. m.diff_html (
              show.files,
              { empty = 'This commit changes no files.', cut = show.cut }
            )
        )
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
            recent = m.remember (recent, top, MAX_RECENT)
            app.store.set ('recent', recent)
            app.store.set ('reopen', true)
          end
          render_side ()
          render_head ()
          changes_list:html ('')
          history_list:html ('')
          show_placeholder ()
          git (
            { 'config', '--get', 'status.showUntrackedFiles' },
            nil,
            function (cfg)
              untracked_mode = cfg and cfg.code == 0 and cfg.stdout or nil
              refresh ()
            end
          )
        end
      )
    end

    local function close_repo ()
      repo, status, commits, selection, shown_key = nil, nil, {}, nil, nil
      app.store.set ('reopen', false)
      render_side ()
      render_bar ()
      show_placeholder ()
    end

    -- Actions -------------------------------------------------------------------------------

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
        content = ui.div ({ class = 'git-side', head, changes_list, commit_box }),
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
        items[#items + 1] = { separator = true }
        items[#items + 1] = {
          label = 'Open File',
          icon = 'file',
          disabled = e.kind == 'deleted',
          run = function ()
            if embedded and editor then
              editor.open_file (full)
              return
            end
            app.system.open_path (m.native (full, app.os), function (_, err)
              if err then
                fail (err)
              end
            end)
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
    commands.register ({
      id = 'git.file_history',
      category = 'Git',
      title = 'Show File History',
      icon = 'file-clock',
      when = function ()
        return has_repo () and current_file () ~= nil
      end,
      run = function ()
        local path = current_file ()
        if path then
          history_of (path)
        end
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
          if folder then
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
