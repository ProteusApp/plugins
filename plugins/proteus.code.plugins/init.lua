-- proteus.code.plugins: builds Proteus plugins inside the open folder, in its `.proteus/plugins`.
--
-- A plugin there belongs to the project. It starts by itself for everyone who opens the
-- folder and trusts it, and a save reloads it at once. This plugin makes new ones from a
-- template, lists them in a section under the Explorer, reloads one with F5, and says when
-- one fails to start. The Plugin Editor stays the place to change Proteus itself.

local folder = require ('proteus_folder') --[[@as ProteusFolder]]

local TEMPLATE = [[
-- %s: say what this plugin does for the project here.
--
-- It lives in this folder's .proteus/plugins, so everyone who opens the folder in Proteus
-- gets it. Save to reload it. The Handbook shows every service a plugin can use.
---@type Proteus.Plugin
return {
  name = '%s',
  description = 'A plugin for this project.',
  version = '0.1.0',
  depends = { 'proteus.core.commands' },
  optional = { 'proteus.ui.notify' },
  -- What the plugin may do beyond drawing and keeping its own data, such as 'net' or
  -- 'process'. The Handbook's Permissions page lists them.
  permissions = {},

  activate = function (app)
    local commands = app.use ('commands')

    commands.register ({
      id = '%s.hello',
      title = 'Say Hello',
      category = '%s',
      icon = 'smile', -- any Lucide icon name: https://lucide.dev/icons
      run = function ()
        local notify = app.try_use ('notify')
        local folder = app.kernel.project ().folder
        if notify then
          notify.success ('Hello from ' .. (folder and folder:match ('[^/]+$') or 'this project') .. '!')
        end
      end,
    })
  end,
}
]]

local README = [[
# %s

A Proteus plugin for this project. It lives in `.proteus/plugins/%s`, so everyone who opens the folder in the Code Editor and trusts it gets it.

Save `init.lua` and the plugin reloads. Its commands show in the palette under **%s**.
]]

-- lang=css
local CSS = [[
.pp { display: flex; flex-direction: column; padding: 2px 6px 8px; font-size: 12px; }
.pp-row { display: flex; align-items: center; gap: 8px; padding: 4px 8px; border-radius: var(--radius); cursor: pointer;
  min-width: 0; }
.pp-row:hover { background: var(--bg-hover); }
.pp-dot { flex: none; width: 7px; height: 7px; border-radius: 50%; background: var(--fg-faint); }
.pp-dot.active { background: var(--success); }
.pp-dot.failed { background: var(--danger); }
.pp-name { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; color: var(--fg); }
.pp-id { flex: none; font-family: var(--font-mono); font-size: 11px; color: var(--fg-faint); }
.pp-empty { padding: 6px 8px 4px; color: var(--fg-faint); line-height: 1.5; }
.pp-empty .ui-button { margin-top: 8px; padding: 3px 10px; font-size: 12px; }
.pp-tool { flex: none; display: inline-grid; place-items: center; width: 22px; height: 22px; padding: 0; border: none;
  border-radius: var(--radius); background: none; color: var(--fg-muted); cursor: pointer; }
.pp-tool:hover { background: var(--bg-hover); color: var(--fg); }
]]

---What `proteus.code.explorer` offers other plugins: a section under its tree.
---@class CodePlugins.Explorer
---@field add_section fun(spec: Proteus.ViewSectionSpec): Proteus.ViewSection?

---@type Proteus.Plugin
return {
  name = 'Project Plugins',
  description = "Builds Proteus plugins in the open folder's .proteus folder, for everyone who opens it.",
  version = '1.0.1',
  -- `files` to write the folder's .proteus files on disk, and for the `project` and `editor`
  -- services. `workspace` to write them through the folder's layer while it is in use, so a new
  -- plugin starts at once. `kernel` to reload the folder's plugins and trust the folder.
  permissions = { 'files', 'workspace', 'kernel' },
  requires = { proteus = '>=0.3.0', features = { 'permissions' } },
  depends = {
    'proteus.lib.ui',
    'proteus.core.commands',
    'proteus.code.project',
  },
  optional = {
    'proteus.ui.notify',
    'proteus.ui.palette',
    'proteus.ui.menus',
    'proteus.editor.core',
    'proteus.code.explorer',
    'proteus.marketplace',
  },
  -- The Plugin Editor's tools build plugins in the workspace with the same keys. The two
  -- editors stay apart, so they never run together.
  conflicts = { 'proteus.dev.tools' },
  activate = function (app)
    local ui = app.use ('ui')
    local commands = app.use ('commands')
    local project = app.use ('project')
    local notify = app.try_use ('notify')
    ui.css (CSS)

    ---@param kind 'info'|'success'|'warn'|'error'
    ---@param text string
    ---@param opts? Proteus.NotifyOptions
    local function say (kind, text, opts)
      if notify then
        notify[kind] (text, opts)
      else
        app.log (text)
      end
    end

    ---True while a folder is open on the desktop.
    ---@return boolean
    local function ready ()
      return project.root () ~= nil and folder.available (app)
    end

    ---The plugins the folder's `.proteus` folder holds, by name.
    ---@return Proteus.PluginInfo[]
    local function own ()
      local out = {} ---@type Proteus.PluginInfo[]
      for _, p in ipairs (app.kernel.plugins ()) do
        if p.source == 'project' then
          out[#out + 1] = p
        end
      end
      table.sort (out, function (a, b)
        return a.name:lower () < b.name:lower ()
      end)
      return out
    end

    ---The full path on disk of a file in the `.proteus` folder.
    ---@param rel string
    ---@return string?
    local function on_disk (rel)
      local dir = folder.dir (app)
      return dir and (dir .. '/' .. rel) or nil
    end

    ---The plugin a full path belongs to, when it is inside `.proteus/plugins`.
    ---@param path string
    ---@return string? id
    local function plugin_at (path)
      local dir = folder.dir (app)
      if not dir or path:sub (1, #dir + 1) ~= dir .. '/' then
        return nil
      end
      local rel = path:sub (#dir + 2)
      if rel:sub (1, 8) ~= 'plugins/' then
        return nil
      end
      return app.kernel.plugin_of (rel)
    end

    ---Opens a file in the editor.
    ---@param full string?
    local function open_file (full)
      local editor = app.try_use ('editor')
      if full and editor then
        editor.open_file (full)
      end
    end

    ---Opens a file once it is on disk. A write through the folder's layer reaches the disk a
    ---moment after it returns, so the editor would find nothing yet.
    ---@param full string?
    ---@param tries? integer
    local function open_when_written (full, tries)
      if not full then
        return
      end
      local path = full
      app.fs.stat_path (path, function (stat)
        local left = tries or 20
        if (stat and stat.exists) or left <= 0 then
          open_file (path)
          return
        end
        app.timer.after (50, function ()
          open_when_written (path, left - 1)
        end)
      end)
    end

    ---@param p Proteus.PluginInfo
    local function open_plugin (p)
      open_file (on_disk (p.path))
    end

    -- Making a plugin -----------------------------------------------------------------------

    ---What a plugin's commands start with: its id when the app leaves it the id's first part,
    ---and otherwise the one part it may use, such as `zig` for `lang.zig`, since the app's own
    ---plugins use `lang`.
    ---@param id string
    ---@return string
    local function prefix (id)
      local spaces = app.kernel.namespaces (id)
      local first = id:match ('^[^.]+')
      for _, space in ipairs (spaces) do
        if space == first then
          return id
        end
      end
      return spaces[1] or id
    end

    ---@param id string
    local function create (id)
      local name = id:gsub ('^%l', string.upper)
      local base = 'plugins/' .. id
      local files = {
        [base .. '/init.lua'] = TEMPLATE:format (id, name, prefix (id), name),
        [base .. '/README.md'] = README:format (name, id, name),
      }
      folder.write_all (app, files, function (ok, err)
        if not ok then
          say ('error', 'Could not make ' .. id .. ': ' .. tostring (err))
          return
        end
        open_when_written (on_disk (base .. '/init.lua'))
        if folder.loaded (app) then
          say (
            'success',
            'Made '
              .. id
              .. " in this folder's .proteus/plugins. It starts in a moment, and each save reloads it."
          )
        else
          folder.offer_reload (
            app,
            'Made ' .. id .. " in this folder's .proteus/plugins"
          )
        end
      end)
    end

    local function new_plugin ()
      if not ready () then
        say (
          'warn',
          'Open a folder first. Its plugins live in its .proteus folder.'
        )
        return
      end
      local picker = app.try_use ('picker')
      if not picker then
        return
      end
      picker.input ({
        prompt = 'Plugin id for this folder, like team.lint. It goes in .proteus/plugins.',
        placeholder = 'my.plugin',
        validate = function (id)
          if not id:match ('^[%a][%w_%-%.]*$') then
            return 'Start with a letter. Use letters, numbers, . _ or -'
          end
          if #app.kernel.namespaces (id) == 0 then
            return 'The app uses every part of '
              .. id
              .. ', so the plugin could not name its commands. Start it with something else, such as team.'
          end
          for _, p in ipairs (own ()) do
            if p.id == id then
              return 'This folder has a plugin called ' .. id .. ' already'
            end
          end
          local other = app.kernel.plugin (id)
          if other and other.status ~= 'missing' then
            return 'A plugin called '
              .. id
              .. ' exists already. A copy here would replace it.'
          end
          return nil
        end,
        on_submit = create,
      })
    end

    -- Reloading ----------------------------------------------------------------------------

    ---@param id string
    local function reload (id)
      local ok, err = app.kernel.reload (id)
      if ok then
        say ('success', 'Reloaded ' .. id .. '.')
      else
        say (
          'error',
          'Reloading ' .. id .. ' failed: ' .. tostring (err):match ('^[^\n]*')
        )
      end
    end

    local function reload_current ()
      local editor = app.try_use ('editor')
      local doc = editor and editor.current ()
      local id = doc and plugin_at (doc.path)
      if not doc or not id then
        say (
          'info',
          "Open a file of one of this folder's plugins, in .proteus/plugins, to reload it."
        )
        return
      end
      local plugin_id = id
      if doc.dirty then
        doc.save (function ()
          reload (plugin_id)
        end)
      else
        reload (plugin_id)
      end
    end

    -- A plugin of this folder that fails says so, with a way to its code.
    app.on ('kernel:plugin_failed', function (id, err)
      local info = app.kernel.plugin (tostring (id))
      if not info or info.source ~= 'project' then
        return
      end
      say (
        'error',
        info.name .. ' failed to start: ' .. tostring (err):match ('^[^\n]*'),
        {
          timeout = 0,
          action = {
            label = 'Open Its Code',
            run = function ()
              open_plugin (info)
            end,
          },
        }
      )
    end)

    -- The section under the Explorer --------------------------------------------------------

    -- The section sits under the explorer's tree. The explorer adds it, since a plugin adds
    -- sections only to its own views.
    local explorer = app.try_use ('code.explorer') --[[@as CodePlugins.Explorer?]]
    local list = ui.div ({ class = 'pp' })
    local section = nil ---@type Proteus.ViewSection?

    local function draw ()
      if not section then
        return
      end
      section.show (ready ())
      local rows = {} ---@type Proteus.Child[]
      for _, p in ipairs (own ()) do
        local dot = p.status == 'active' and 'pp-dot active'
          or (p.status == 'failed' and 'pp-dot failed' or 'pp-dot')
        rows[#rows + 1] = ui.div ({
          class = 'pp-row',
          title = p.error or (p.description ~= '' and p.description or p.id),
          ui.span ({ class = dot }),
          ui.span ({ class = 'pp-name', p.name }),
          ui.span ({ class = 'pp-id', p.id }),
          onclick = function ()
            open_plugin (p)
          end,
          oncontextmenu = function (ev)
            local menus = app.try_use ('menus')
            if not menus then
              return nil
            end
            menus.popup ({
              {
                label = 'Open init.lua',
                icon = 'file-code',
                run = function ()
                  open_plugin (p)
                end,
              },
              {
                label = 'Reload',
                icon = 'refresh-cw',
                run = function ()
                  reload (p.id)
                end,
              },
              {
                label = 'Show in the Marketplace',
                icon = 'store',
                disabled = app.try_use ('marketplace') == nil,
                run = function ()
                  local market = app.try_use ('marketplace')
                  if market then
                    market.open ('plugin', p.id)
                  end
                end,
              },
            }, ev.x or 0, ev.y or 0)
            return 'stop'
          end,
        })
      end
      if #rows == 0 then
        rows[1] = ui.div ({
          class = 'pp-empty',
          ui.div ({
            'Plugins made here live in .proteus/plugins and start for everyone who opens this folder.',
          }),
          ui.button ({
            'New Plugin…',
            icon = 'plus',
            onclick = function ()
              new_plugin ()
              return nil
            end,
          }),
        })
      end
      list:set_children (rows)
    end

    ---@param icon string
    ---@param title string
    ---@param fn fun()
    ---@return Proteus.El
    local function tool (icon, title, fn)
      return ui.h ('button', {
        class = 'pp-tool',
        title = title,
        ui.icon (icon, 14),
        onclick = function ()
          fn ()
          return 'stop'
        end,
      })
    end

    if explorer then
      section = explorer.add_section ({
        id = 'project-plugins',
        title = 'Proteus Plugins',
        icon = 'blocks',
        open = false,
        content = list,
        actions = {
          tool ('plus', 'New Plugin in This Folder', new_plugin),
          tool ('refresh-cw', 'Reload Every Plugin Here', function ()
            for _, p in ipairs (own ()) do
              if p.status == 'active' or p.status == 'failed' then
                reload (p.id)
              end
            end
          end),
        },
      })
      local added = section
      if added then
        app.dispose (function ()
          added.remove ()
        end)
      end
    end

    local pending = false
    local function soon ()
      if pending then
        return
      end
      pending = true
      app.timer.after (80, function ()
        pending = false
        draw ()
      end)
    end
    app.on ('kernel:plugin_started', soon)
    app.on ('kernel:plugin_stopped', soon)
    app.on ('kernel:plugin_failed', soon)
    app.on ('fs:changed', function (path)
      if path:sub (1, 8) == 'plugins/' then
        soon ()
      end
    end)
    draw ()

    -- Commands ------------------------------------------------------------------------------

    commands.register ({
      id = 'code.plugin_new',
      category = 'Project',
      title = 'New Plugin in This Folder…',
      icon = 'blocks',
      key = 'ctrl+alt+n',
      menu = 'Plugins',
      group = 'project',
      order = 1,
      -- It only asks for a name, so any plugin may offer it, as the Welcome page does.
      shared = true,
      when = ready,
      run = new_plugin,
    })
    commands.register ({
      id = 'code.plugin_reload',
      category = 'Project',
      title = 'Save and Reload This Plugin',
      icon = 'refresh-cw',
      key = 'f5',
      menu = 'Plugins',
      group = 'project',
      order = 2,
      when = function ()
        local editor = app.try_use ('editor')
        local doc = editor and editor.current ()
        return doc ~= nil and plugin_at (doc.path) ~= nil
      end,
      run = reload_current,
    })
    commands.register ({
      id = 'code.plugin_list',
      category = 'Project',
      title = "Open One of This Folder's Plugins…",
      icon = 'folder-git-2',
      when = ready,
      run = function ()
        local picker = app.try_use ('picker')
        if not picker then
          return
        end
        local items = {} ---@type Proteus.PickItem[]
        for _, p in ipairs (own ()) do
          items[#items + 1] = {
            label = p.name,
            detail = p.id .. '  ·  ' .. p.status,
            icon = 'blocks',
            value = p,
          }
        end
        picker.pick ({
          items = items,
          placeholder = "Open a plugin in this folder's .proteus/plugins",
          empty = 'No plugins here yet. New Plugin in This Folder makes one.',
          on_pick = function (item)
            open_plugin (item.value --[[@as Proteus.PluginInfo]])
          end,
        })
      end,
    })
  end,
}
