-- proteus.terminal: terminals in the bottom dock, for the Plugin Editor, the Code Editor and
-- any profile with the bottom dock. A terminal starts in the folder open in the Code Editor,
-- or else in the workspace folder.
--
-- Ctrl+` shows or hides the panel, and Ctrl+Shift+` opens another terminal. Each tab of the
-- panel holds one terminal, or several split side by side, and is named after what the one
-- with the focus runs. The `terminal.shell` setting picks the default program, and
-- `terminal.profiles` adds named programs with their arguments, variables and folder.
-- Other plugins with the `files` permission open terminals through the `terminal` service,
-- such as Open in Terminal in the Code Editor's file tree.
--
-- Run Task runs a task from the open folder's `.proteus/tasks.json`, once the user trusts the
-- folder, or from the `terminal.tasks` setting, in a terminal tab of its own. Its problem
-- matchers send what they find in its output to the Problems panel.
--
-- The terminals survive a reload of the window: the app keeps their programs running, and
-- the panel takes them back into the same tabs.

local disk = require ('disk_paths') --[[@as DiskPaths]]
local groups = require ('terminal_groups') --[[@as Terminal.Groups]]
local profiles = require ('terminal_profiles') --[[@as Terminal.Profiles]]
local session = require ('terminal_session') --[[@as Terminal.Session]]
local tasks = require ('terminal_tasks') --[[@as Terminal.Tasks]]

-- lang=css
local CSS = [[
.term { display: flex; flex-direction: column; height: 100%; min-height: 0; }
.term-bar { flex: none; display: flex; align-items: center; gap: 2px; padding: 3px 6px; overflow-x: auto;
  border-bottom: 1px solid var(--border); }
.term-tab { flex: none; display: inline-flex; align-items: center; gap: 6px; max-width: 220px; height: 22px;
  padding: 0 8px; border: none; border-radius: var(--radius); background: none; color: var(--fg-muted);
  font-size: 12px; cursor: pointer; }
.term-tab:hover { background: var(--bg-hover); color: var(--fg); }
.term-tab.active { background: var(--bg-active); color: var(--fg); }
.term-tab.exited { font-style: italic; }
.term-tab-name { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.term-count { flex: none; min-width: 14px; padding: 0 4px; border-radius: 7px; font-size: 10px; line-height: 14px;
  text-align: center; background: var(--bg-hover); color: var(--fg-muted); }
.term-tool { flex: none; display: inline-grid; place-items: center; width: 22px; height: 22px; padding: 0;
  border: none; border-radius: var(--radius); background: none; color: var(--fg-muted); cursor: pointer; }
.term-tool:hover { background: var(--bg-hover); color: var(--fg); }
.term-tool.narrow { width: 14px; margin-left: -2px; }
.term-gap { flex: 1; }
.term-body { flex: 1; min-height: 0; position: relative; }
.term-group { position: absolute; inset: 0; display: flex; }
.term-pane { position: relative; flex: 1 1 0; min-width: 0; border-top: 2px solid transparent; }
.term-pane + .term-pane { border-left: 1px solid var(--border); }
.term-group.split .term-pane.focused { border-top-color: var(--accent); }
.term-none { padding: 16px 12px; font-size: 12px; color: var(--fg-faint); }
]]

---One terminal and its pane.
---@class Terminal.Term
---@field id integer
---@field title string What the program calls itself, or what it runs.
---@field name? string A name the user gave it, which the program's title does not change.
---@field cwd string The folder it started in. `''` for the home folder.
---@field profile string The name of the profile it runs.
---@field task? string The label of the task it runs.
---@field matcher? Terminal.Matcher Reads the task's output for problems.
---@field found table<string, Proteus.Diagnostic[]> The problems its task found, by full path.
---@field published table<string, true> The paths whose problems went to the Problems panel.
---@field new_run boolean True once its program stopped, so the next line starts a new run.
---@field meta string What it keeps through a reload, as last sent.
---@field attaching boolean True until the panel knows whether the terminal from before a reload came back.
---@field widget Proteus.El
---@field pane Proteus.El
---@field exited boolean
---@field code? integer
---@field started boolean True while its program runs.
---@field pending string[] Text to type once its program has started.
---@field closed boolean True once it is gone. An exit reported after that is dropped.

---One tab of the panel and the group of terminals it shows.
---@class Terminal.Tab
---@field tab Proteus.El
---@field name Proteus.El
---@field count Proteus.El
---@field el Proteus.El
---@field panes string The ids of the terminals it shows, in order, as drawn last.

---How the panel opens a terminal: what the service takes, and what only the panel uses.
---@class Terminal.OpenOptions: Proteus.TerminalOpenOptions
---@field task? Terminal.Task Runs this task.
---@field attach? integer Takes back the terminal with this id, after a reload.
---@field saved? Terminal.Saved What that terminal kept through the reload.
---@field meta? string The text it kept, as the app gave it back.
---@field quiet? boolean Leaves the keyboard focus where it is.

---@type Proteus.Plugin
return {
  name = 'Terminal',
  description = 'Terminals in the bottom dock, with split panes and shell profiles, for the Plugin Editor and the Code Editor.',
  version = '2.1.0',
  -- `process` runs the shell in each terminal. `files` lets it start in a folder on disk, such
  -- as the Code Editor's, which the `project` service hands out, and lets Run Selection read
  -- the editor. `clipboard` is for Paste in its menu.
  permissions = { 'process', 'files', 'clipboard' },
  -- `terminal-sessions` keeps the terminals through a reload, and `terminal-lines` hands a
  -- task's output to its problem matchers.
  requires = {
    proteus = '>=0.3.1',
    features = { 'permissions', 'terminal-sessions', 'terminal-lines' },
  },
  depends = {
    'proteus.lib.ui',
    'proteus.ui.views',
    'proteus.core.settings',
  },
  optional = {
    'proteus.code.project',
    'proteus.core.commands',
    'proteus.core.keys',
    'proteus.ui.menus',
    'proteus.ui.palette',
    'proteus.ui.notify',
    'proteus.editor.core',
    'proteus.tools.diagnostics',
  },
  activate = function (app)
    local ui = app.use ('ui')
    local views = app.use ('views')
    -- Outside the Code Editor there is no folder, and a terminal starts in the workspace.
    local project = app.try_use ('project')
    local settings = app.use ('settings')
    local commands = app.try_use ('commands')
    ui.css (CSS)

    settings.define ('terminal.shell', {
      title = 'Terminal program',
      type = 'string',
      default = '',
      description = 'The program the default profile runs, such as pwsh, cmd or bash. Empty runs the system shell.',
    })
    settings.define ('terminal.profiles', {
      title = 'Terminal profiles',
      type = 'json',
      default = {},
      description = 'More programs a terminal can run. Each has a name and a program, and may have args, env and cwd, such as { "name": "Git Bash", "program": "C:/Program Files/Git/bin/bash.exe", "args": ["-l"] }.',
    })
    settings.define ('terminal.default_profile', {
      title = 'Default terminal profile',
      type = 'string',
      default = '',
      description = 'The name of the profile a new terminal runs. Empty runs the terminal program.',
    })
    settings.define ('terminal.font_size', {
      title = 'Terminal font size',
      type = 'number',
      default = 13,
    })
    settings.define ('terminal.tasks', {
      title = 'Tasks',
      type = 'json',
      default = {},
      description = 'Tasks Run Task offers, after those of the open folder\'s .proteus/tasks.json. Each has a label and a command or a program, such as { "label": "Build", "command": "npm run build", "group": "build", "problems": "tsc" }.',
    })

    local root = project and project.root () or nil
    -- An app older than app.fs.disk_path starts terminals in the home folder instead.
    local disk_path = app.fs.disk_path
    local workspace = disk_path and disk_path ('') or nil
    local desktop = app.platform ~= 'browser'
    local terms = {} ---@type table<integer, Terminal.Term>
    local tabs = {} ---@type table<integer, Terminal.Tab>
    local state = groups.new ()
    local next_id = 1

    ---@param kind 'info'|'warn'|'error'
    ---@param text string
    local function say (kind, text)
      local notify = app.try_use ('notify')
      if notify then
        notify[kind] (text)
      elseif kind ~= 'info' then
        app.warn (text)
      end
    end

    local warned = '' ---@type string
    ---Every profile, saying once what is wrong with the setting.
    ---@return Terminal.Profile[]
    local function all_profiles ()
      local list, problems = profiles.read (
        settings.get ('terminal.profiles'),
        tostring (settings.get ('terminal.shell') or '')
      )
      local text = table.concat (problems, '; ')
      if text ~= warned then
        warned = text
        if text ~= '' then
          say ('warn', 'Terminal profiles: ' .. text)
        end
      end
      return list
    end

    local tasks_warned = '' ---@type string
    ---Every task: the open folder's, then the setting's, saying once what is wrong with them.
    ---The folder's `.proteus/tasks.json` comes from its `.proteus` layer, which the app
    ---mounts only for a folder the user trusts. An untrusted folder's tasks are never read.
    ---@return Terminal.Task[]
    local function all_tasks ()
      local taken = {} ---@type table<string, true>
      local list, problems = {}, {} ---@type Terminal.Task[], string[]
      local text = app.fs.read ('tasks.json', 'project')
      if text then
        local ok, value = pcall (app.json.decode, text)
        if ok then
          list, problems = tasks.read (value, 'folder', taken)
        else
          problems[#problems + 1] = '.proteus/tasks.json is not JSON'
        end
      end
      local more, more_problems =
        tasks.read (settings.get ('terminal.tasks'), 'settings', taken)
      for _, t in ipairs (more) do
        list[#list + 1] = t
      end
      for _, p in ipairs (more_problems) do
        problems[#problems + 1] = p
      end
      local said = table.concat (problems, '; ')
      if said ~= tasks_warned then
        tasks_warned = said
        if said ~= '' then
          say ('warn', 'Tasks: ' .. said)
        end
      end
      return list
    end

    local tab_row = ui.div ({ style = { display = 'contents' } })
    local body = ui.div ({ class = 'term-body' })

    ---The terminal with the focus in the tab in front.
    ---@return Terminal.Term?
    local function active ()
      local _, focus = groups.current (state)
      return focus and terms[focus] or nil
    end

    ---@param term Terminal.Term
    ---@return string
    local function label (term)
      local text = term.name or term.title
      if term.exited then
        text = text .. ' (exited ' .. tostring (term.code or 0) .. ')'
      end
      return text
    end

    -- True while the tabs from before a reload are built again, when places are not final.
    local rebuilding = false

    ---Sends each terminal what it keeps through a reload, when that changed: where it sits,
    ---its names, its folder and what it runs.
    local function remember ()
      if rebuilding then
        return
      end
      for id, term in pairs (terms) do
        local where = session.place (state, id)
        if where and not term.closed then
          local text = app.json.encode ({
            group = where.group,
            pane = where.pane,
            front = where.front,
            focus = where.focus,
            name = term.name,
            title = term.title,
            cwd = term.cwd,
            profile = term.profile,
            task = term.task,
          })
          if text ~= term.meta then
            term.meta = text
            term.widget:widget ('set_meta', text)
          end
        end
      end
    end

    local focus_term ---@type fun(term: Terminal.Term?)
    local close_term ---@type fun(term: Terminal.Term)
    local tab_order = '' ---@type string

    ---Brings the tabs and panes on screen in line with the groups. An element moves only when
    ---the order changed, since moving a terminal takes its focus away.
    local function draw ()
      local seen = {} ---@type table<integer, true>
      local order = {} ---@type string[]
      for _, g in ipairs (state.list) do
        seen[g.id] = true
        order[#order + 1] = tostring (g.id)
        local t = tabs[g.id]
        if not t then
          local group = g
          local name = ui.span ({ class = 'term-tab-name' })
          local count = ui.span ({ class = 'term-count' })
          local tab = ui.button ({
            class = 'term-tab',
            ui.icon ('terminal', 13),
            name,
            count,
          })
          tab:on ('click', function ()
            focus_term (terms[group.focus])
            return nil
          end)
          tab:on ('mousedown', function (ev)
            -- A middle click closes the tab's terminal with the focus, as it closes a tab.
            if ev.button == 1 then
              local term = terms[group.focus]
              if term then
                close_term (term)
              end
              return 'stop'
            end
            return nil
          end)
          t = {
            tab = tab,
            name = name,
            count = count,
            el = ui.div ({ class = 'term-group' }),
            panes = '',
          }
          tabs[g.id] = t
          body:append (t.el)
        end
        local front = g.id == state.active
        local focused = terms[g.focus]
        t.tab:class ('active', front)
        t.tab:class ('exited', focused ~= nil and focused.exited)
        t.tab:attr (
          'title',
          #g.panes > 1 and (#g.panes .. ' terminals side by side') or 'Terminal'
        )
        t.name:text (focused and label (focused) or 'Terminal')
        t.count:text (tostring (#g.panes))
        t.count:show (#g.panes > 1)
        t.el:class ('split', #g.panes > 1)
        t.el:show (front)
        local panes = table.concat (g.panes, ',')
        for _, id in ipairs (g.panes) do
          local term = terms[id]
          if term then
            if panes ~= t.panes then
              t.el:append (term.pane)
            end
            term.pane:class ('focused', id == g.focus)
          end
        end
        t.panes = panes
      end
      local new_order = table.concat (order, ',')
      if new_order ~= tab_order then
        tab_order = new_order
        for _, g in ipairs (state.list) do
          tab_row:append (tabs[g.id].tab)
        end
      end
      for id, t in pairs (tabs) do
        if not seen[id] then
          t.tab:remove ()
          t.el:remove ()
          tabs[id] = nil
        end
      end
      remember ()
    end

    ---Gives a terminal the focus and brings its tab to the front.
    ---@param term Terminal.Term?
    focus_term = function (term)
      if term then
        groups.focus (state, term.id)
      end
      draw ()
      if term then
        local w = term.widget
        app.timer.after (0, function ()
          if not term.closed then
            w:widget ('fit')
            w:widget ('focus')
          end
        end)
      end
    end

    ---Sends a task's problems to the Problems panel, and clears the files it no longer has
    ---problems in.
    ---@param term Terminal.Term
    local function publish (term)
      local diagnostics = app.try_use ('diagnostics')
      if not diagnostics or not term.task then
        return
      end
      local source = 'task: ' .. term.task
      for path in pairs (term.published) do
        if not term.found[path] then
          diagnostics.set (source, path, {})
        end
      end
      term.published = {}
      for path, list in pairs (term.found) do
        diagnostics.set (source, path, list)
        term.published[path] = true
      end
    end

    local publish_queued = false
    local dirty = {} ---@type table<Terminal.Term, true>
    ---Sends a task's problems a moment later, so a burst of output sends them once.
    ---@param term Terminal.Term
    local function publish_soon (term)
      dirty[term] = true
      if publish_queued then
        return
      end
      publish_queued = true
      app.timer.after (150, function ()
        publish_queued = false
        local list = dirty
        dirty = {}
        for t in pairs (list) do
          publish (t)
        end
      end)
    end

    ---Starts a task's problems over, for a new run.
    ---@param term Terminal.Term
    ---@param names? string[] The problem matchers, when they changed.
    local function fresh_problems (term, names)
      if not term.task then
        return
      end
      local task = names and { problems = names }
        or tasks.find (all_tasks (), term.task)
      term.matcher = task and tasks.matcher (task.problems) or nil
      term.found = {}
      term.new_run = false
      publish_soon (term)
    end

    ---One line of a task's output, for its problem matchers.
    ---@param term Terminal.Term
    ---@param line string
    local function task_line (term, line)
      if term.new_run then
        fresh_problems (term)
      end
      local matcher = term.matcher
      local found = matcher and matcher.feed (line)
      if not found or not term.task then
        return
      end
      local path = tasks.full_path (found.file, term.cwd)
      local list = term.found[path] or {}
      term.found[path] = list
      list[#list + 1] = tasks.diagnostic (found, 'task: ' .. term.task)
      publish_soon (term)
    end

    ---@param term Terminal.Term
    ---@param code integer?
    local function task_ended (term, code)
      term.new_run = true
      publish (term)
      local count = 0
      for _, list in pairs (term.found) do
        count = count + #list
      end
      local text = (term.task or 'The task')
        .. (
          code == 0 and ' finished'
          or (' stopped with code ' .. tostring (code or '?'))
        )
      if count > 0 then
        text = text
          .. ', with '
          .. count
          .. (count == 1 and ' problem' or ' problems')
      end
      say (code == 0 and count == 0 and 'info' or 'warn', text .. '.')
    end

    ---@param term Terminal.Term
    close_term = function (term)
      if term.closed then
        return
      end
      term.closed = true
      if term.task then
        term.found = {}
        publish (term)
      end
      local next_focus = groups.remove (state, term.id)
      terms[term.id] = nil
      term.pane:remove ()
      focus_term (next_focus and terms[next_focus] or nil)
    end

    local function close_all ()
      for _, id in ipairs (groups.all (state)) do
        local term = terms[id]
        if term then
          term.closed = true
          if term.task then
            term.found = {}
            publish (term)
          end
          term.pane:remove ()
          terms[id] = nil
        end
        groups.remove (state, id)
      end
      draw ()
    end

    ---Types text into a terminal, or keeps it until its program has started.
    ---@param term Terminal.Term
    ---@param text string
    local function send (term, text)
      if term.started then
        term.widget:widget ('send', text)
      else
        term.pending[#term.pending + 1] = text
        if term.exited then
          term.widget:widget ('start')
        end
      end
    end

    local opening = false
    -- True until the terminals from before a reload are back.
    local restoring = desktop
    local shown_while_restoring = false

    ---Opens a terminal, in a tab of its own or split beside the one with the focus. It runs a
    ---profile, or a task, or takes back a terminal from before a reload.
    ---@param opts? Terminal.OpenOptions
    ---@return Terminal.Term?
    local function new_term (opts)
      if not desktop then
        return nil
      end
      local o = opts or {}
      local saved = o.saved
      local profile = profiles.pick (
        all_profiles (),
        saved and saved.profile or o.profile,
        tostring (settings.get ('terminal.default_profile') or '')
      )
      local task = o.task
      local task_label = task and task.label or (saved and saved.task)
      if not task and task_label then
        task = tasks.find (all_tasks (), task_label)
      end
      local id = next_id
      next_id = next_id + 1
      local cwd ---@type string
      if saved then
        cwd = saved.cwd
      elseif task then
        cwd = tasks.cwd (task, root, workspace)
      else
        cwd = profiles.cwd (o.cwd, profile, root, workspace)
      end
      local program, args, env = profile.program, profile.args, profile.env
      if task then
        program, args = tasks.command_line (task, app.os)
        env = task.env
      end
      local term ---@type Terminal.Term
      local widget = ui.widget ('terminal', {
        program = program,
        args = args,
        env = env,
        cwd = cwd,
        font_size = tonumber (settings.get ('terminal.font_size')) or 13,
        -- The program keeps running through a reload, and the panel takes it back.
        keep = true,
        attach = o.attach,
        autostart = o.attach == nil,
        on_attach = function (ok)
          if term and not term.closed then
            term.attaching = false
            -- A terminal that stopped for good while the window reloaded goes.
            if not ok then
              close_term (term)
            end
          end
        end,
        on_started = function ()
          if term and not term.closed then
            -- A terminal started again after it exited drops "(exited N)" from its tab.
            term.exited = false
            term.started = true
            local pending = term.pending
            term.pending = {}
            for _, text in ipairs (pending) do
              term.widget:widget ('send', text)
            end
            draw ()
          end
        end,
        on_exit = function (code)
          if term and not term.closed then
            term.exited = true
            term.started = false
            term.code = code
            -- The exit of a task that ended while the window reloaded was told already.
            if term.task and not term.attaching then
              task_ended (term, code)
            end
            draw ()
          end
        end,
        on_title = function (title)
          if term and not term.closed and title ~= '' then
            term.title = title
            draw ()
          end
        end,
        -- Only a task's output goes to its problem matchers.
        on_line = task_label and function (line)
          if term and not term.closed then
            task_line (term, line)
          end
        end or nil,
      })
      local name = o.name and o.name ~= '' and o.name or nil
      if saved then
        name = saved.name
      elseif task and not name then
        name = task.label
      end
      term = {
        id = id,
        title = saved and saved.title or profile.label,
        name = name,
        cwd = cwd,
        profile = profile.name,
        task = task_label,
        matcher = task and tasks.matcher (task.problems) or nil,
        found = {},
        published = {},
        new_run = false,
        meta = o.meta or '',
        attaching = o.attach ~= nil,
        widget = widget,
        pane = ui.div ({ class = 'term-pane', widget }),
        exited = false,
        started = false,
        pending = {},
        closed = false,
      }
      term.pane:on ('mousedown', function ()
        if not term.closed and active () ~= term then
          groups.focus (state, term.id)
          draw ()
        end
        return nil
      end)
      terms[id] = term
      if o.split then
        local beside = active ()
        groups.split (state, id, beside and beside.id or nil)
      else
        groups.add (state, id)
      end
      if o.quiet then
        draw ()
      else
        focus_term (term)
      end
      return term
    end

    ---@param opts? Terminal.OpenOptions
    ---@return Terminal.Term?
    local function open (opts)
      -- Showing the panel opens a terminal when it has none, so it waits for this one.
      opening = true
      views.show ('terminal')
      opening = false
      return new_term (opts)
    end

    local function restart ()
      local term = active ()
      if term then
        fresh_problems (term)
        term.widget:widget ('restart')
        focus_term (term)
      end
    end

    local last_task = nil ---@type string?

    ---Runs a task in a terminal tab of its own, or again in the one it ran in before.
    ---@param task Terminal.Task
    ---@return boolean
    local function run_task (task)
      if not desktop then
        return false
      end
      last_task = task.label
      for _, term in pairs (terms) do
        if
          not term.closed
          and term.task
          and term.task:lower () == task.label:lower ()
        then
          local program, args = tasks.command_line (task, app.os)
          term.cwd = tasks.cwd (task, root, workspace)
          term.widget:widget ('set_program', program, args, term.cwd)
          fresh_problems (term, task.problems)
          opening = true
          views.show ('terminal')
          opening = false
          term.widget:widget ('restart')
          focus_term (term)
          return true
        end
      end
      return open ({ task = task }) ~= nil
    end

    ---What a task runs, for a picker.
    ---@param task Terminal.Task
    ---@return string
    local function task_detail (task)
      local program, args = tasks.command_line (task, app.os)
      local line = task.command
      if not line then
        line = program
        for _, a in ipairs (args) do
          line = line .. ' ' .. a
        end
      end
      local from = task.source == 'folder' and 'the folder' or 'settings'
      return (task.detail or line) .. ' · from ' .. from
    end

    ---Asks which of the tasks to run.
    ---@param list Terminal.Task[]
    ---@param placeholder string
    local function pick_task (list, placeholder)
      local picker = app.try_use ('picker')
      if not picker then
        if list[1] then
          run_task (list[1])
        end
        return
      end
      local items = {} ---@type Proteus.PickItem[]
      for _, t in ipairs (list) do
        items[#items + 1] = {
          label = t.label,
          detail = task_detail (t),
          icon = t.group == 'test' and 'flask-conical'
            or t.group == 'build' and 'hammer'
            or 'play',
          value = t.label,
        }
      end
      picker.pick ({
        items = items,
        placeholder = placeholder,
        on_pick = function (item)
          local t = tasks.find (list, tostring (item.value or ''))
          if t then
            run_task (t)
          end
        end,
      })
    end

    ---Says so when the open folder has tasks that do not run because the user has not
    ---trusted it. Its file is only looked at, never read.
    local function tell_untrusted ()
      if not root or app.fs.read ('tasks.json', 'project') then
        return
      end
      app.fs.stat_path (root .. '/.proteus/tasks.json', function (stat)
        if stat and stat.exists and not stat.dir then
          say (
            'info',
            "The open folder's .proteus/tasks.json runs only once you trust the folder."
          )
        end
      end)
    end

    ---Run Task, or with a group, Run Build Task and Run Test Task: the group's default task
    ---runs at once, and otherwise a picker offers the tasks.
    ---@param group? 'build'|'test'
    local function choose_task (group)
      local list = all_tasks ()
      tell_untrusted ()
      if #list == 0 then
        say (
          'info',
          'There are no tasks. Add them to .proteus/tasks.json in the open folder, or to the terminal.tasks setting.'
        )
        return
      end
      if group then
        local one, choices = tasks.of_group (list, group)
        if one then
          run_task (one)
          return
        elseif #choices > 0 then
          pick_task (choices, 'Pick the ' .. group .. ' task to run')
          return
        end
      end
      pick_task (list, 'Pick a task to run')
    end

    local function rerun_task ()
      local task = tasks.find (all_tasks (), last_task)
      if task then
        run_task (task)
      else
        choose_task ()
      end
    end

    local function clear ()
      local term = active ()
      if term then
        term.widget:widget ('clear')
      end
    end

    ---Asks for a new name for the terminal with the focus. An empty name lets the program name
    ---it again.
    local function rename ()
      local term = active ()
      local picker = app.try_use ('picker')
      if not term or not picker then
        return
      end
      picker.input ({
        prompt = 'Name the terminal. Leave it empty to name it after its program.',
        value = term.name or term.title,
        on_submit = function (text)
          local trimmed = text:match ('^%s*(.-)%s*$') or ''
          term.name = trimmed ~= '' and trimmed or nil
          draw ()
        end,
      })
    end

    ---Asks which profile to run, then opens a terminal with it.
    ---@param split? boolean
    local function pick_profile (split)
      local picker = app.try_use ('picker')
      if not picker then
        open ({ split = split })
        return
      end
      local items = {} ---@type Proteus.PickItem[]
      for _, p in ipairs (all_profiles ()) do
        local detail = p.program ~= '' and p.program or 'the system shell'
        if #p.args > 0 then
          detail = detail .. ' ' .. table.concat (p.args, ' ')
        end
        items[#items + 1] = {
          label = p.label,
          detail = detail,
          icon = 'terminal',
          value = p.name,
        }
      end
      picker.pick ({
        items = items,
        placeholder = 'Pick a profile for the new terminal',
        on_pick = function (item)
          open ({ profile = tostring (item.value or ''), split = split })
        end,
      })
    end

    local function new_in_folder ()
      app.fs.pick_open (
        { title = 'Open a Terminal in a Folder', directory = true },
        function (paths)
          local dir = paths and paths[1]
          if dir then
            open ({ cwd = dir })
          end
        end
      )
    end

    ---Types the editor's selection into the terminal with the focus, opening one when there
    ---is none.
    local function run_selection ()
      local editor = app.try_use ('editor')
      local doc = editor and editor.current ()
      local text = doc and doc.selection () or ''
      if text == '' then
        say ('info', 'Select the text to run in the terminal first.')
        return
      end
      local term = active ()
      if term then
        views.show ('terminal')
      else
        term = open ()
      end
      if term then
        send (term, profiles.as_input (text))
        focus_term (term)
      end
    end

    ---@param step integer
    local function cycle (step)
      local id = groups.step (state, step)
      if id and terms[id] then
        focus_term (terms[id])
      end
    end

    ---@param icon string
    ---@param title string
    ---@param run fun(ev: Proteus.DomEvent)
    ---@param class? string
    ---@return Proteus.El
    local function tool (icon, title, run, class)
      return ui.button ({
        class = class and ('term-tool ' .. class) or 'term-tool',
        title = title,
        ui.icon (icon, 14),
        onclick = function (ev)
          run (ev)
          return nil
        end,
      })
    end

    ---The profiles, as menu items that open a terminal with each.
    ---@return Proteus.MenuItem[]
    local function profile_items ()
      local items = {} ---@type Proteus.MenuItem[]
      for _, p in ipairs (all_profiles ()) do
        local pname = p.name
        items[#items + 1] = {
          label = p.label,
          icon = 'terminal',
          run = function ()
            open ({ profile = pname })
          end,
        }
      end
      items[#items + 1] = { separator = true }
      items[#items + 1] = {
        label = 'Run Task…',
        icon = 'play',
        run = function ()
          choose_task ()
        end,
      }
      items[#items + 1] = {
        label = 'Split Terminal',
        icon = 'columns-2',
        run = function ()
          open ({ split = true })
        end,
      }
      items[#items + 1] = {
        label = 'New Terminal in Folder…',
        icon = 'folder-open',
        run = new_in_folder,
      }
      return items
    end

    local menus = app.try_use ('menus')

    local content ---@type Proteus.El
    if desktop then
      content = ui.div ({
        class = 'term',
        ui.div ({
          class = 'term-bar',
          tab_row,
          tool ('plus', 'New Terminal (Ctrl+Shift+`)', function ()
            new_term ()
          end),
          menus and tool ('chevron-down', 'Profiles', function (ev)
            menus.popup (profile_items (), ev.x or 0, ev.y or 0)
          end, 'narrow') or nil,
          tool ('columns-2', 'Split Terminal', function ()
            new_term ({ split = true })
          end),
          ui.span ({ class = 'term-gap' }),
          tool ('rotate-ccw', 'Restart', restart),
          tool ('eraser', 'Clear', clear),
          tool ('trash-2', 'Close Terminal', function ()
            local term = active ()
            if term then
              close_term (term)
            end
          end),
        }),
        body,
      })
    else
      content = ui.div ({
        class = 'term-none',
        'The terminal needs the desktop app.',
      })
    end

    ---Builds the tabs again from the terminals that kept running through a reload, and takes
    ---each one back.
    ---@param list Proteus.WaitingTerminal[]
    local function restore (list)
      local waiting = {} ---@type Terminal.Waiting[]
      for _, w in ipairs (list) do
        local ok, value = pcall (app.json.decode, w.meta or '')
        waiting[#waiting + 1] = {
          id = w.id,
          meta = w.meta,
          saved = session.read (ok and value or nil),
          ended = w.ended == true,
        }
      end
      local saved_groups, front = session.layout (waiting)
      local focused = {} ---@type table<integer, integer>
      rebuilding = true
      for gi, g in ipairs (saved_groups) do
        for pi, w in ipairs (g.items) do
          local term = new_term ({
            attach = w.id,
            saved = w.saved,
            meta = w.meta,
            split = pi > 1,
            quiet = true,
          })
          if term and pi == g.focus then
            focused[gi] = term.id
          end
        end
      end
      for gi, id in pairs (focused) do
        if gi ~= front then
          groups.focus (state, id)
        end
      end
      local front_id = front and focused[front]
      if front_id then
        groups.focus (state, front_id)
      end
      rebuilding = false
      draw ()
    end

    -- A terminal's program starts once the panel has a size, so a hidden panel waits.
    views.add ('bottom', {
      id = 'terminal',
      title = 'Terminal',
      icon = 'square-terminal',
      order = 10,
      key = 'ctrl+`',
      -- Other plugins may show it, such as the Code Editor's folder page.
      shared = true,
      content = content,
      on_show = function ()
        local term = active ()
        if restoring then
          -- The terminals from before a reload come back first.
          shown_while_restoring = true
          return
        elseif opening then
          return
        elseif desktop and not term then
          new_term ()
        elseif term then
          focus_term (term)
        end
      end,
    })

    if desktop then
      app.process.waiting_terminals (function (list)
        restoring = false
        if list and #list > 0 then
          restore (list)
        end
        if shown_while_restoring and not active () then
          new_term ()
        end
      end)
    end

    settings.watch ('terminal.font_size', function (size)
      for _, t in pairs (terms) do
        t.widget:widget ('set_font_size', tonumber (size) or 13)
      end
    end)
    settings.watch ('terminal.profiles', function ()
      all_profiles ()
    end)

    -- Full paths go in, so a restricted plugin needs `files` to open a terminal.
    app.provide ('terminal', {
      open = function (opts)
        local o = type (opts) == 'table' and opts or {}
        return open ({
          cwd = type (o.cwd) == 'string' and o.cwd or nil,
          profile = type (o.profile) == 'string' and o.profile or nil,
          name = type (o.name) == 'string' and o.name or nil,
          split = o.split == true,
        }) ~= nil
      end,
      profiles = function ()
        local out = {} ---@type string[]
        for i, p in ipairs (all_profiles ()) do
          out[i] = p.name
        end
        return out
      end,
      tasks = function ()
        local out = {} ---@type string[]
        for i, t in ipairs (all_tasks ()) do
          out[i] = t.label
        end
        return out
      end,
      run_task = function (wanted)
        local task = type (wanted) == 'string'
          and tasks.find (all_tasks (), wanted)
        return task and run_task (task) or false
      end,
    } --[[@as Proteus.Terminal]], { needs = 'files' })

    if commands then
      ---@return boolean
      local function has_term ()
        return active () ~= nil
      end
      ---@return boolean
      local function on_desktop ()
        return desktop
      end
      commands.register ({
        id = 'terminal.new',
        category = 'Terminal',
        title = 'New Terminal',
        key = 'ctrl+shift+`',
        icon = 'plus',
        menu = 'View',
        order = 60,
        when = on_desktop,
        run = function ()
          open ()
        end,
      })
      commands.register ({
        id = 'terminal.new_profile',
        category = 'Terminal',
        title = 'New Terminal with Profile…',
        icon = 'terminal',
        when = on_desktop,
        run = function ()
          pick_profile (false)
        end,
      })
      commands.register ({
        id = 'terminal.new_in_folder',
        category = 'Terminal',
        title = 'New Terminal in Folder…',
        icon = 'folder-open',
        when = on_desktop,
        run = new_in_folder,
      })
      commands.register ({
        id = 'terminal.split',
        category = 'Terminal',
        title = 'Split Terminal',
        key = 'ctrl+shift+5',
        icon = 'columns-2',
        when = on_desktop,
        run = function ()
          open ({ split = true })
        end,
      })
      commands.register ({
        id = 'terminal.rename',
        category = 'Terminal',
        title = 'Rename Terminal…',
        icon = 'pencil',
        when = has_term,
        run = rename,
      })
      commands.register ({
        id = 'terminal.next',
        category = 'Terminal',
        title = 'Focus Next Terminal',
        icon = 'arrow-right',
        when = has_term,
        run = function ()
          cycle (1)
        end,
      })
      commands.register ({
        id = 'terminal.previous',
        category = 'Terminal',
        title = 'Focus Previous Terminal',
        icon = 'arrow-left',
        when = has_term,
        run = function ()
          cycle (-1)
        end,
      })
      commands.register ({
        id = 'terminal.run_selection',
        category = 'Terminal',
        title = 'Run Selected Text in Terminal',
        icon = 'play',
        when = function ()
          local editor = app.try_use ('editor')
          return desktop and editor ~= nil and editor.current () ~= nil
        end,
        run = run_selection,
      })
      commands.register ({
        id = 'terminal.run_task',
        category = 'Terminal',
        title = 'Run Task…',
        icon = 'play',
        menu = 'View',
        order = 61,
        when = on_desktop,
        run = function ()
          choose_task ()
        end,
      })
      commands.register ({
        id = 'terminal.run_build_task',
        category = 'Terminal',
        title = 'Run Build Task',
        icon = 'hammer',
        when = on_desktop,
        run = function ()
          choose_task ('build')
        end,
      })
      commands.register ({
        id = 'terminal.run_test_task',
        category = 'Terminal',
        title = 'Run Test Task',
        icon = 'flask-conical',
        when = on_desktop,
        run = function ()
          choose_task ('test')
        end,
      })
      commands.register ({
        id = 'terminal.rerun_task',
        category = 'Terminal',
        title = 'Run Last Task Again',
        icon = 'repeat',
        when = on_desktop,
        run = rerun_task,
      })
      commands.register ({
        id = 'terminal.restart',
        category = 'Terminal',
        title = 'Restart Terminal',
        icon = 'rotate-ccw',
        when = has_term,
        run = restart,
      })
      commands.register ({
        id = 'terminal.close',
        category = 'Terminal',
        title = 'Close Terminal',
        icon = 'trash-2',
        when = has_term,
        run = function ()
          local term = active ()
          if term then
            close_term (term)
          end
        end,
      })
      commands.register ({
        id = 'terminal.close_all',
        category = 'Terminal',
        title = 'Close All Terminals',
        icon = 'trash',
        when = has_term,
        run = close_all,
      })
    end

    if menus and desktop then
      menus.attach (tab_row, function ()
        return {
          {
            label = 'Rename…',
            icon = 'pencil',
            run = rename,
          },
          {
            label = 'Split Terminal',
            icon = 'columns-2',
            run = function ()
              open ({ split = true })
            end,
          },
          { separator = true },
          {
            label = 'Close Terminal',
            icon = 'trash-2',
            run = function ()
              local term = active ()
              if term then
                close_term (term)
              end
            end,
          },
          {
            label = 'Close All Terminals',
            icon = 'trash',
            danger = true,
            run = close_all,
          },
        } --[[@as Proteus.MenuItem[] ]]
      end)
      menus.attach (body, function (ev)
        if ev.editable then
          return menus.edit_items (ev)
        end
        ---@type Proteus.MenuItem[]
        local items = {}
        local term = active ()
        local dir = term and term.cwd or ''
        if dir ~= '' then
          items[#items + 1] = {
            label = 'Copy Folder Path',
            icon = 'copy',
            run = function ()
              app.system.clipboard (disk.native (dir, app.os))
            end,
          }
        end
        for _, item in ipairs ({
          {
            label = 'Paste',
            icon = 'clipboard-paste',
            run = function ()
              app.system.clipboard_read (function (text)
                local target = active ()
                if text and target then
                  target.widget:widget ('send', text)
                end
              end)
            end,
          },
          { separator = true },
          {
            label = 'Split Terminal',
            icon = 'columns-2',
            run = function ()
              open ({ split = true })
            end,
          },
          {
            label = 'Rename…',
            icon = 'pencil',
            run = rename,
          },
          {
            label = 'Clear',
            icon = 'eraser',
            run = clear,
          },
          {
            label = 'Restart',
            icon = 'rotate-ccw',
            run = restart,
          },
          { separator = true },
          {
            label = 'Close Terminal',
            icon = 'trash-2',
            run = function ()
              local target = active ()
              if target then
                close_term (target)
              end
            end,
          },
        } --[[@as Proteus.MenuItem[] ]]) do
          items[#items + 1] = item
        end
        return items
      end)
    end
  end,
}
