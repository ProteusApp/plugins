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

local disk = require ('disk_paths') --[[@as DiskPaths]]
local groups = require ('terminal_groups') --[[@as Terminal.Groups]]
local profiles = require ('terminal_profiles') --[[@as Terminal.Profiles]]

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

---@type Proteus.Plugin
return {
  name = 'Terminal',
  description = 'Terminals in the bottom dock, with split panes and shell profiles, for the Plugin Editor and the Code Editor.',
  version = '2.0.1',
  -- `process` runs the shell in each terminal. `files` lets it start in a folder on disk, such
  -- as the Code Editor's, which the `project` service hands out, and lets Run Selection read
  -- the editor. `clipboard` is for Paste in its menu.
  permissions = { 'process', 'files', 'clipboard' },
  requires = { proteus = '>=0.3.1', features = { 'permissions' } },
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
      description = 'The program the default profile runs, with any arguments, such as pwsh -NoLogo or bash -l. Quote a path with spaces. Empty runs the system shell.',
      sensitive = true,
    })
    settings.define ('terminal.profiles', {
      title = 'Terminal profiles',
      type = 'json',
      default = {},
      description = 'More programs a terminal can run. Each has a name and a program, and may have args, env and cwd, such as { "name": "Git Bash", "program": "C:/Program Files/Git/bin/bash.exe", "args": ["-l"] }.',
      -- It names programs to run, so a profile or a project folder cannot set it.
      sensitive = true,
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

    ---@param term Terminal.Term
    close_term = function (term)
      if term.closed then
        return
      end
      term.closed = true
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

    ---Opens a terminal, in a tab of its own or split beside the one with the focus.
    ---@param opts? Proteus.TerminalOpenOptions
    ---@return Terminal.Term?
    local function new_term (opts)
      if not desktop then
        return nil
      end
      local o = opts or {}
      local profile = profiles.pick (
        all_profiles (),
        o.profile,
        tostring (settings.get ('terminal.default_profile') or '')
      )
      local id = next_id
      next_id = next_id + 1
      local cwd = profiles.cwd (o.cwd, profile, root, workspace)
      local term ---@type Terminal.Term
      local widget = ui.widget ('terminal', {
        program = profile.program,
        args = profile.args,
        env = profile.env,
        cwd = cwd,
        font_size = tonumber (settings.get ('terminal.font_size')) or 13,
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
            draw ()
          end
        end,
        on_title = function (title)
          if term and not term.closed and title ~= '' then
            term.title = title
            draw ()
          end
        end,
      })
      local name = o.name and o.name ~= '' and o.name or nil
      term = {
        id = id,
        title = profile.label,
        name = name,
        cwd = cwd,
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
      focus_term (term)
      return term
    end

    ---@param opts? Proteus.TerminalOpenOptions
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
        term.widget:widget ('restart')
        focus_term (term)
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
        if opening then
          return
        elseif desktop and not term then
          new_term ()
        elseif term then
          focus_term (term)
        end
      end,
    })

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
