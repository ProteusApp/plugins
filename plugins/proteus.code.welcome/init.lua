-- proteus.code.welcome: what the Code Editor's main area shows while no file is open.
--
-- With no folder open, it is the Welcome page: open a folder, one of the folders opened
-- before, a single file, or a clone of a Git repository. With a folder open, it is the
-- folder's own page: its name, and the commands worth knowing, each with its key. Neither is
-- a tab, so neither closes. Each gives way when a file opens, and comes back when the last
-- tab closes.

local disk = require ('disk_paths') --[[@as DiskPaths]]

-- lang=css
local CSS = [[
.cw { max-width: 920px; margin: 0 auto; padding: 44px 32px 80px; }
.cw h1 { font-size: 30px; margin: 0; letter-spacing: -.01em; }
.cw .lead { color: var(--fg-muted); font-size: 15px; margin: 8px 0 26px; line-height: 1.6; max-width: 640px; }
.cw h2 { font-size: 12px; text-transform: uppercase; letter-spacing: .07em; color: var(--fg-faint); margin: 30px 0 12px; }
.cw-columns { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 12px 40px; }
.cw-actions { display: flex; flex-direction: column; gap: 4px; }
.cw-link { display: flex; align-items: center; gap: 10px; padding: 6px 8px; margin: 0 -8px; border: none;
  border-radius: var(--radius); background: none; color: var(--fg); font: inherit; text-align: left; cursor: pointer; }
.cw-link:hover { background: var(--bg-hover); }
.cw-link .ui-icon { flex: none; color: var(--accent); }
.cw-link .name { flex: none; }
.cw-link .sub { margin-left: auto; min-width: 0; font-size: 12px; color: var(--fg-faint); overflow: hidden;
  text-overflow: ellipsis; white-space: nowrap; }
.cw-empty { color: var(--fg-faint); font-size: 13px; }
.cf kbd { font-family: var(--font-mono); font-size: 11px; background: var(--bg-elev); border: 1px solid var(--border);
  border-radius: 4px; padding: 0 5px; color: var(--fg); white-space: nowrap; }
.cf { min-height: 100%; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 28px;
  padding: 40px 24px; }
.cf-title { display: flex; align-items: center; gap: 14px; max-width: 100%; }
.cf-title > .ui-icon { flex: none; color: var(--fg-faint); }
.cf-name { font-size: 24px; font-weight: 600; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.cf-path { font-size: 12px; color: var(--fg-faint); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.cf-list { display: grid; grid-template-columns: minmax(200px, max-content) max-content; gap: 2px 28px; }
.cf-row { display: contents; }
.cf-row > * { display: flex; align-items: center; min-height: 30px; cursor: pointer; }
.cf-row .label { gap: 10px; color: var(--fg-muted); }
.cf-row .label .ui-icon { color: var(--fg-faint); }
.cf-row:hover .label { color: var(--fg); }
.cf-row:hover .label .ui-icon { color: var(--accent); }
.cf-row .key { justify-content: flex-end; }
]]

---A command the folder page offers.
---@class CodeWelcome.Entry
---@field ids string[] The command, by the ids it may have. The first one there is used.
---@field label string
---@field icon string

-- The folder page's list. A command that is not there, such as one from a plugin switched
-- off, is left out, and so is one this plugin may not run. A plugin offers its command to
-- others by marking it `shared`. A view's command has the id of its plugin's names, such as
-- `terminal.show.terminal`, or `views.show.<id>` for a view of a plugin that ships with the app.
---@type CodeWelcome.Entry[]
local FOLDER_COMMANDS = {
  { ids = { 'file.quick_open' }, label = 'Go to File', icon = 'file-search' },
  {
    ids = { 'search.find_in_files' },
    label = 'Find in Files',
    icon = 'search',
  },
  { ids = { 'file.new' }, label = 'New File', icon = 'file-plus' },
  {
    ids = { 'terminal.show.terminal', 'views.show.terminal' },
    label = 'Show Terminal',
    icon = 'square-terminal',
  },
  {
    ids = { 'git.show_changes', 'views.show.git.changes' },
    label = 'Source Control',
    icon = 'git-branch',
  },
  { ids = { 'palette.open' }, label = 'Run a Command', icon = 'command' },
  {
    ids = { 'project.recent' },
    label = 'Open Recent Folder',
    icon = 'history',
  },
  {
    ids = { 'code.plugin_new' },
    label = 'New Plugin in This Folder',
    icon = 'blocks',
  },
  { ids = { 'marketplace.open' }, label = 'Marketplace', icon = 'store' },
}

---@type Proteus.Plugin
return {
  name = 'Welcome',
  description = 'What the Code Editor shows while no file is open: the Welcome page, or the folder.',
  version = '1.2.0',
  -- `files` for the `project` service: the open folder, and the folders opened before.
  permissions = { 'files' },
  requires = { proteus = '>=0.3.0', features = { 'permissions' } },
  depends = {
    'proteus.lib.ui',
    'proteus.ui.tabs',
    'proteus.core.commands',
    'proteus.code.project',
  },
  optional = {
    'proteus.core.keys',
    'proteus.editor.core',
    'proteus.git',
    'proteus.code.search',
    'proteus.terminal',
    'proteus.ui.palette',
    'proteus.ui.settings',
    'proteus.core.themes',
    'proteus.code.plugins',
    'proteus.marketplace',
  },
  activate = function (app)
    local ui = app.use ('ui')
    local tabs = app.use ('tabs')
    local commands = app.use ('commands')
    local project = app.use ('project')
    local keys = app.try_use ('keys')
    ui.css (CSS)

    ---@param id string
    ---@return fun()
    local function run (id)
      return function ()
        commands.run (id)
      end
    end

    ---True when the command is there and this plugin may run it. A command of another plugin
    ---runs from here only when it is marked `shared`.
    ---@param id string
    ---@return boolean
    local function offered (id)
      return commands.get (id) ~= nil and commands.can_run (id)
    end

    ---The key a command is bound to now, such as `Ctrl+P`, or nil.
    ---@param id string
    ---@return string?
    local function key_of (id)
      return keys and keys.label (id) or nil
    end

    ---@param icon string
    ---@param label string
    ---@param sub string?
    ---@param fn fun()
    ---@return Proteus.El
    local function link (icon, label, sub, fn)
      return ui.button ({
        class = 'cw-link',
        title = sub or label,
        onclick = function ()
          fn ()
          return nil
        end,
        ui.icon (icon, 16),
        ui.span ({ class = 'name', label }),
        sub and ui.span ({ class = 'sub', sub }) or nil,
      })
    end

    ---The Welcome page, for when no folder is open.
    ---@return Proteus.El
    local function welcome ()
      local recent = ui.div ({ class = 'cw-actions' })
      local count = 0
      for _, path in ipairs (project.recent ()) do
        if count >= 8 then
          break
        end
        count = count + 1
        recent:append (
          link (
            'folder',
            disk.name (path),
            disk.native (disk.parent (path), app.os),
            function ()
              project.open (path)
            end
          )
        )
      end
      if count == 0 then
        recent:append (ui.div ({
          class = 'cw-empty',
          'Folders you open show up here.',
        }))
      end

      local start = ui.div ({
        class = 'cw-actions',
        link ('folder-open', 'Open Folder…', nil, project.pick),
        offered ('file.open_disk') and link (
          'file',
          'Open File…',
          key_of ('file.open_disk'),
          run ('file.open_disk')
        ) or nil,
        offered ('file.new') and link (
          'file-plus',
          'New File…',
          key_of ('file.new'),
          run ('file.new')
        ) or nil,
        offered ('git.clone') and link (
          'git-branch',
          'Clone a Git Repository…',
          nil,
          run ('git.clone')
        ) or nil,
      })

      -- The outer box fills the main area and scrolls. The inner one holds the page's width.
      return ui.div ({
        ui.div ({
          class = 'cw',
          ui.h1 ({ 'Code Editor' }),
          ui.p ({
            class = 'lead',
            'Open a folder to edit its files, search them, run a terminal in it, and commit '
              .. 'to Git. A folder can bring its own Proteus plugins in .proteus/plugins, and the '
              .. 'Marketplace adds more.',
          }),
          ui.div ({
            class = 'cw-columns',
            ui.div ({ ui.h2 ({ 'Start' }), start }),
            ui.div ({ ui.h2 ({ 'Recent' }), recent }),
          }),
          ui.div ({
            class = 'cw-columns',
            ui.div ({
              ui.h2 ({ 'Make it yours' }),
              ui.div ({
                class = 'cw-actions',
                offered ('theme.choose') and link (
                  'palette',
                  'Change the Theme',
                  nil,
                  run ('theme.choose')
                ) or nil,
                offered ('settings.open')
                    and link ('settings', 'Settings', nil, run ('settings.open'))
                  or nil,
                offered ('marketplace.open') and link (
                  'store',
                  'Marketplace',
                  'Plugins and profiles',
                  run ('marketplace.open')
                ) or nil,
                link (
                  'puzzle',
                  'Open the Plugin Editor',
                  'A window of its own',
                  function ()
                    app.window.open ('editor')
                  end
                ),
              }),
            }),
          }),
        }),
      })
    end

    ---The folder's page, for when a folder is open and no file is.
    ---@param root string
    ---@return Proteus.El
    local function folder_page (root)
      local list = ui.div ({ class = 'cf-list' })
      for _, entry in ipairs (FOLDER_COMMANDS) do
        local id = nil ---@type string?
        for _, candidate in ipairs (entry.ids) do
          if not id and offered (candidate) then
            id = candidate
          end
        end
        if id then
          local command = id
          local key = key_of (command)
          list:append (ui.div ({
            class = 'cf-row',
            onclick = function ()
              commands.run (command)
              return nil
            end,
            ui.span ({
              class = 'label',
              ui.icon (entry.icon, 16),
              entry.label,
            }),
            ui.span ({ class = 'key', key and ui.h ('kbd', key) or nil }),
          }))
        end
      end
      return ui.div ({
        class = 'cf',
        ui.div ({
          class = 'cf-title',
          ui.icon ('folder-open', 34),
          ui.div ({
            style = { minWidth = '0' },
            ui.div ({ class = 'cf-name', project.name () or root }),
            ui.div ({ class = 'cf-path', disk.native (root, app.os) }),
          }),
        }),
        list,
      })
    end

    local page = nil ---@type Proteus.El?

    local function show ()
      local root = project.root ()
      local old = page
      page = root and folder_page (root) or welcome ()
      tabs.set_empty (page)
      if old then
        old:remove ()
      end
    end

    -- The page waits until every plugin has started and registered its commands, so each
    -- command it lists is there to find. A key bound later shows up too.
    local pending = nil ---@type fun()?
    local function show_soon ()
      if pending then
        pending ()
      end
      pending = app.timer.after (0, function ()
        pending = nil
        show ()
      end)
    end
    show_soon ()
    app.on ('keys:changed', show_soon)
    app.on ('commands:changed', show_soon)
  end,
}
