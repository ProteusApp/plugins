-- proteus.terminal: terminals in the bottom dock. In the Code Editor they start in the open
-- folder. Anywhere else they start in the home folder, in any profile with the bottom dock.
--
-- Ctrl+` shows or hides the panel, and Ctrl+Shift+` opens another terminal. Each terminal has
-- a tab along the top of the panel, named after what it runs. The `terminal.shell` setting
-- picks the program. Empty runs the system shell: PowerShell on Windows, or the login shell
-- elsewhere.

local disk = require ('disk_paths') --[[@as DiskPaths]]

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
.term-tool { flex: none; display: inline-grid; place-items: center; width: 22px; height: 22px; padding: 0;
  border: none; border-radius: var(--radius); background: none; color: var(--fg-muted); cursor: pointer; }
.term-tool:hover { background: var(--bg-hover); color: var(--fg); }
.term-gap { flex: 1; }
.term-body { flex: 1; min-height: 0; position: relative; }
.term-pane { position: absolute; inset: 0; }
.term-none { padding: 16px 12px; font-size: 12px; color: var(--fg-faint); }
]]

---One terminal and its tab.
---@class CodeTerminal.Term
---@field id integer
---@field title string
---@field widget Proteus.El
---@field pane Proteus.El
---@field tab Proteus.El
---@field name Proteus.El
---@field exited boolean

---@type Proteus.Plugin
return {
  name = 'Terminal',
  description = 'Terminals in the bottom dock, which start in the folder open in the Code Editor.',
  version = '1.0.1',
  -- `process` runs the shell in each terminal. `files` lets it start in the Code Editor's
  -- folder, which the `project` service hands out. `clipboard` is for Paste in its menu.
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
  },
  activate = function (app)
    local ui = app.use ('ui')
    local views = app.use ('views')
    -- Outside the Code Editor there is no folder, and a terminal starts in the home folder.
    local project = app.try_use ('project')
    local settings = app.use ('settings')
    local commands = app.try_use ('commands')
    ui.css (CSS)

    settings.define ('terminal.shell', {
      title = 'Terminal program',
      type = 'string',
      default = '',
      description = 'The program each new terminal runs, such as pwsh, cmd or bash. Empty runs the system shell.',
      sensitive = true,
    })
    settings.define ('terminal.font_size', {
      title = 'Terminal font size',
      type = 'number',
      default = 13,
    })

    local root = project and project.root () or nil
    local desktop = app.platform ~= 'browser'
    local terms = {} ---@type CodeTerminal.Term[]
    local active = nil ---@type CodeTerminal.Term?
    local next_id = 1

    local tab_row = ui.div ({ style = { display = 'contents' } })
    local body = ui.div ({ class = 'term-body' })

    ---@param term CodeTerminal.Term?
    local function focus_term (term)
      active = term
      for _, t in ipairs (terms) do
        t.pane:show (t == term)
        t.tab:class ('active', t == term)
      end
      if term then
        local w = term.widget
        app.timer.after (0, function ()
          w:widget ('fit')
          w:widget ('focus')
        end)
      end
    end

    ---@param term CodeTerminal.Term
    local function close_term (term)
      for i, t in ipairs (terms) do
        if t == term then
          table.remove (terms, i)
          break
        end
      end
      term.tab:remove ()
      term.pane:remove ()
      if active == term then
        focus_term (terms[#terms])
      end
    end

    ---@return CodeTerminal.Term
    local function new_term ()
      local id = next_id
      next_id = next_id + 1
      local term ---@type CodeTerminal.Term
      local shell = tostring (settings.get ('terminal.shell') or '')
      local widget = ui.widget ('terminal', {
        program = shell,
        cwd = root or '',
        font_size = tonumber (settings.get ('terminal.font_size')) or 13,
        on_started = function ()
          if term then
            term.exited = false
            term.tab:class ('exited', false)
          end
        end,
        on_exit = function (code)
          if term then
            term.exited = true
            term.tab:class ('exited', true)
            term.name:text (
              term.title .. ' (exited ' .. tostring (code or 0) .. ')'
            )
          end
        end,
        on_title = function (title)
          if term and title ~= '' then
            term.title = title
            term.name:text (title)
          end
        end,
      })
      local name = ui.span ({
        class = 'term-tab-name',
        shell ~= '' and shell or 'Terminal',
      })
      local tab = ui.button ({
        class = 'term-tab',
        title = 'Terminal ' .. id,
        ui.icon ('terminal', 13),
        name,
      })
      term = {
        id = id,
        title = shell ~= '' and shell or 'Terminal',
        widget = widget,
        pane = ui.div ({ class = 'term-pane', widget }),
        tab = tab,
        name = name,
        exited = false,
      }
      tab:on ('click', function ()
        focus_term (term)
        return nil
      end)
      tab:on ('mousedown', function (ev)
        -- A middle click closes the terminal, as it closes a tab.
        if ev.button == 1 then
          close_term (term)
          return 'stop'
        end
        return nil
      end)
      terms[#terms + 1] = term
      tab_row:append (tab)
      body:append (term.pane)
      focus_term (term)
      return term
    end

    local function restart ()
      local term = active
      if term then
        term.widget:widget ('restart')
        focus_term (term)
      end
    end

    ---@param icon string
    ---@param title string
    ---@param run fun()
    ---@return Proteus.El
    local function tool (icon, title, run)
      return ui.button ({
        class = 'term-tool',
        title = title,
        ui.icon (icon, 14),
        onclick = function ()
          run ()
          return nil
        end,
      })
    end

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
          ui.span ({ class = 'term-gap' }),
          tool ('rotate-ccw', 'Restart', restart),
          tool ('eraser', 'Clear', function ()
            if active then
              active.widget:widget ('clear')
            end
          end),
          tool ('trash-2', 'Close Terminal', function ()
            if active then
              close_term (active)
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
        if desktop and #terms == 0 then
          new_term ()
        elseif active then
          focus_term (active)
        end
      end,
    })

    settings.watch ('terminal.font_size', function (size)
      for _, t in ipairs (terms) do
        t.widget:widget ('set_font_size', tonumber (size) or 13)
      end
    end)

    if commands then
      commands.register ({
        id = 'terminal.new',
        category = 'Terminal',
        title = 'New Terminal',
        key = 'ctrl+shift+`',
        icon = 'plus',
        menu = 'View',
        order = 60,
        when = function ()
          return desktop
        end,
        run = function ()
          views.show ('terminal')
          new_term ()
        end,
      })
      commands.register ({
        id = 'terminal.restart',
        category = 'Terminal',
        title = 'Restart Terminal',
        icon = 'rotate-ccw',
        when = function ()
          return active ~= nil
        end,
        run = restart,
      })
      commands.register ({
        id = 'terminal.close',
        category = 'Terminal',
        title = 'Close Terminal',
        icon = 'trash-2',
        when = function ()
          return active ~= nil
        end,
        run = function ()
          if active then
            close_term (active)
          end
        end,
      })
    end

    local menus = app.try_use ('menus')
    if menus and desktop then
      menus.attach (body, function (ev)
        if ev.editable then
          return menus.edit_items (ev)
        end
        ---@type Proteus.MenuItem[]
        local items = {}
        if root then
          items[#items + 1] = {
            label = 'Copy Folder Path',
            icon = 'copy',
            run = function ()
              app.system.clipboard (disk.native (root or '', app.os))
            end,
          }
        end
        for _, item in ipairs ({
          {
            label = 'Paste',
            icon = 'clipboard-paste',
            run = function ()
              app.system.clipboard_read (function (text)
                if text and active then
                  active.widget:widget ('send', text)
                end
              end)
            end,
          },
          { separator = true },
          {
            label = 'Clear',
            icon = 'eraser',
            run = function ()
              if active then
                active.widget:widget ('clear')
              end
            end,
          },
          {
            label = 'Restart',
            icon = 'rotate-ccw',
            run = restart,
          },
        } --[[@as Proteus.MenuItem[] ]]) do
          items[#items + 1] = item
        end
        return items
      end)
    end
  end,
}
