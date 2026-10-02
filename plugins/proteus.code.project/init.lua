-- proteus.code.project: the folder the Code Editor works on. It opens a folder, keeps a list of the
-- folders opened before, watches the folder for changes made outside the app, and names the
-- window after it.
--
-- Other plugins reach it through the `project` service. Every path is a full path with `/`.
-- Opening another folder reloads the window, so each plugin starts again in the new folder
-- and reads `project.root ()` once. Changes on disk arrive as the `code:disk_changed` event,
-- and the editor hears of them through its service, so open files reload.
--
-- A folder named when the app starts opens first, as in `proteus C:\code\app` or
-- `proteus --folder C:\code\app`. Otherwise the folder that was open last opens again.
--
-- A folder can carry its own Proteus setup in a `.proteus` folder: settings, plugins of its
-- own and profiles. The kernel mounts it before any plugin loads, so this plugin tells the
-- kernel which folder is open. A `.proteus` folder can run code, so it stays off until the
-- user trusts the folder.

local disk = require ('disk_paths') --[[@as DiskPaths]]
local exclude = require ('exclude') --[[@as CodeProject.Exclude]]
local file_glob = require ('file_glob') --[[@as FileGlob]]

local MAX_RECENT = 12

---@type Proteus.Plugin
return {
  name = 'Project',
  description = 'The folder the Code Editor works on: Open Folder, recent folders, and changes on disk.',
  version = '1.1.3',
  -- `files` for the folder on disk and the `project` service, which hands out its paths.
  -- `kernel` to tell the kernel which folder is open, open another and trust its .proteus files.
  permissions = { 'files', 'kernel' },
  requires = { proteus = '>=0.3.1', features = { 'permissions' } },
  depends = { 'proteus.core.commands', 'proteus.core.settings' },
  optional = {
    'proteus.ui.notify',
    'proteus.ui.palette',
    'proteus.ui.statusbar',
  },
  activate = function (app)
    -- The folder's paths need `files`, as the `project` service does.
    app.protect_event ('code:disk_changed', { needs = 'files' })
    local commands = app.use ('commands')
    local settings = app.use ('settings')
    local notify = app.try_use ('notify')
    local picker = app.try_use ('picker')
    local bar = app.try_use ('status')
    local desktop = app.platform ~= 'browser'

    settings.define ('project.exclude', {
      title = 'Files and folders the Code Editor leaves out',
      type = 'json',
      default = exclude.DEFAULT,
      description = 'Glob patterns, such as node_modules, *.min.js or docs/build. The file tree, Search and Go to File leave out what matches, and everything inside a folder that matches.',
    })
    -- `project.exclude` once held folder names for search alone, and the file tree hid the
    -- names in `code.explorer.hide`. One setting holds both now, so what the user had set in
    -- either is kept, once.
    if not app.store.get ('exclude_merged') then
      app.store.set ('exclude_merged', true)
      local merged = exclude.migrate (
        settings.source ('project.exclude') == 'user'
            and settings.get ('project.exclude')
          or nil,
        settings.source ('code.explorer.hide') == 'user'
            and settings.get ('code.explorer.hide')
          or nil
      )
      if merged then
        settings.set ('project.exclude', merged)
      end
    end
    settings.define ('project.reopen', {
      title = 'Reopen the last folder',
      type = 'boolean',
      default = true,
      description = 'Opens the folder that was open last when the Code Editor starts.',
    })

    ---@param text string
    local function fail (text)
      if notify then
        notify.error (text)
      else
        app.warn (text)
      end
    end

    -- Folders -------------------------------------------------------------------------------

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

    ---@param path string
    local function remember (path)
      local list = { path }
      for _, p in ipairs (recent) do
        if not disk.same (p, path, app.os) and #list < MAX_RECENT then
          list[#list + 1] = p
        end
      end
      recent = list
      app.store.set ('recent', recent)
    end

    ---@param path string
    local function forget (path)
      local list = {} ---@type string[]
      for _, p in ipairs (recent) do
        if not disk.same (p, path, app.os) then
          list[#list + 1] = p
        end
      end
      recent = list
      app.store.set ('recent', recent)
    end

    -- A fresh start of the app takes the folder it was started with, if any. A reload keeps
    -- the folder that was open, which is also how Open Folder reaches the next page.
    local launch = app.kernel.launch
    local fresh = launch.started ~= nil
      and app.store.get ('started') ~= launch.started
    app.store.set ('started', launch.started)
    local current = app.store.get ('current', nil)
    local reopen = not fresh or settings.get ('project.reopen') ~= false
    local root = nil ---@type string?
    if desktop and fresh and launch.folder then
      root = disk.normalize (launch.folder)
    elseif
      desktop
      and reopen
      and type (current) == 'string'
      and current ~= ''
    then
      root = disk.normalize (current)
    end
    app.store.set ('current', root or false)
    if root then
      remember (root)
    end
    local name = root and disk.name (root) or nil
    -- The next start mounts this folder's `.proteus` files. When the ones in use now belong
    -- to another folder, the window reloads at once.
    app.kernel.set_folder (root or false)
    local layer = app.kernel.project ()

    local fold = disk.folds_case (app.os)

    ---The patterns of `project.exclude`, written so a walk on disk reads them the same way.
    ---@return string[]
    local function excluded ()
      return exclude.for_walk (exclude.clean (settings.get ('project.exclude')))
    end

    ---True when the path from the root, or a folder above it, fits `project.exclude`.
    ---@param rel string
    ---@param dir? boolean
    ---@return boolean
    local function excludes (rel, dir)
      return type (rel) == 'string'
        and exclude.matches (file_glob, excluded (), rel, dir, fold)
    end

    ---Reloads the window into `path`, or into no folder. With the editor's session on, open
    ---files and unsaved edits come back when the folder opens again. With it off, unsaved
    ---edits would be lost, so it asks first.
    ---@param path string|false
    local function switch_to (path)
      local function go ()
        app.store.set ('current', path)
        app.store.flush ()
        app.kernel.open_folder (path)
      end
      local editor = app.try_use ('editor')
      local unsaved = 0
      for _, info in ipairs (editor and editor.docs () or {}) do
        if info.dirty () then
          unsaved = unsaved + 1
        end
      end
      if
        unsaved == 0
        or settings.get ('editor.restore_session') ~= false
        or not picker
      then
        go ()
        return
      end
      picker.confirm ({
        message = (
          unsaved == 1 and 'A file has unsaved changes.'
          or (unsaved .. ' files have unsaved changes.')
        ) .. ' Leave without saving?',
        yes = 'Leave',
        on_yes = go,
      })
    end

    ---@param path string
    local function open (path)
      local full = disk.normalize (path)
      app.fs.stat_path (full, function (stat, err)
        if not stat or not stat.exists then
          forget (full)
          fail (err or (full .. ' is not there any more.'))
          return
        end
        if not stat.dir then
          fail (full .. ' is a file. Open a folder.')
          return
        end
        switch_to (full)
      end)
    end

    local function pick ()
      if not desktop then
        fail ('Opening a folder needs the desktop app.')
        return
      end
      app.fs.pick_open (
        { directory = true, title = 'Open Folder', default_path = root },
        function (paths, err)
          if err then
            fail (err)
            return
          end
          local path = paths and paths[1]
          if path then
            open (path)
          end
        end
      )
    end

    local function open_recent ()
      if not picker then
        return
      end
      local items = {} ---@type Proteus.PickItem[]
      for _, path in ipairs (recent) do
        if not (root and disk.same (path, root, app.os)) then
          items[#items + 1] = {
            label = disk.name (path),
            detail = disk.native (path, app.os),
            icon = 'folder',
            value = path,
          }
        end
      end
      picker.pick ({
        items = items,
        placeholder = 'Open a recent folder',
        empty = 'No other folders yet. Open Folder adds them here.',
        on_pick = function (item)
          open (tostring (item.value))
        end,
      })
    end

    -- Files ---------------------------------------------------------------------------------

    local files_cache = nil ---@type string[]?
    local files_known = {} ---@type table<string, boolean>
    -- True when the walk stopped at its limit, so the list is not every file.
    local files_cut = false
    local waiting = nil ---@type (fun(files: string[]?, err: string?, truncated: boolean?))[]?
    -- Goes up each time the list goes stale, so a walk that ends after a change is not kept.
    local generation = 0

    local function forget_files ()
      files_cache = nil
      files_known = {}
      generation = generation + 1
    end

    settings.watch ('project.exclude', forget_files)

    ---@param cb fun(files: string[]?, err: string?, truncated: boolean?)
    local function files (cb)
      if not root then
        cb (nil, 'No folder is open.')
        return
      end
      if files_cache then
        cb (files_cache, nil, files_cut)
        return
      end
      if waiting then
        waiting[#waiting + 1] = cb
        return
      end
      waiting = { cb }
      local started_at = generation
      app.fs.walk_dir (root, { exclude = excluded () }, function (result, err)
        local list = waiting or {}
        waiting = nil
        local found = result and result.files or nil
        local cut = result ~= nil and result.truncated == true
        if found and started_at == generation then
          files_cache = found
          files_cut = cut
          files_known = {}
          for _, rel in ipairs (found) do
            files_known[rel] = true
          end
        end
        for _, fn in ipairs (list) do
          app.try (fn, found, err, cut)
        end
      end)
    end

    -- The folder's own setup ----------------------------------------------------------------

    local function trust ()
      if root then
        app.kernel.trust_folder (root, true)
        app.kernel.reload_window ()
      end
    end

    ---Asks the user to trust the open folder, for a plugin that waits on it. `reason` says
    ---what is waiting, such as 'Git'. Trusting reloads the window.
    ---@param reason? string
    local function ask_trust (reason)
      if not root or layer.trusted then
        return
      end
      local text = 'Trust the folder '
        .. (name or root)
        .. '? '
        .. (reason and (tostring (reason) .. ' waits for it. ') or '')
        .. 'Its .proteus files, its Git settings and its build scripts can run programs, so trust only a folder from someone you trust.'
      if picker then
        picker.confirm ({ message = text, yes = 'Trust Folder', on_yes = trust })
      elseif notify then
        notify.warn (
          text,
          { timeout = 0, action = { label = 'Trust Folder', run = trust } }
        )
      end
    end

    local offered = false
    ---Offers to use the folder's `.proteus` files, which are there but not in use.
    local function offer ()
      if offered or not root or not notify then
        return
      end
      offered = true
      if layer.trusted then
        notify.info ('This folder has new .proteus files. Reload to use them.', {
          timeout = 0,
          action = {
            label = 'Reload',
            run = function ()
              app.kernel.reload_window ()
            end,
          },
        })
        return
      end
      notify.warn (
        'This folder has a .proteus folder. It can change settings and add plugins, and a plugin you then allow a permission such as process gets full access to this computer. It stays off until you trust the folder.',
        { timeout = 0, action = { label = 'Trust Folder', run = trust } }
      )
    end

    -- A trusted folder whose files are not in use yet reloads by itself, from set_folder.
    if root and desktop and not layer.trusted then
      app.fs.stat_path (root .. '/.proteus', function (stat)
        if stat and stat.exists and stat.dir then
          offer ()
        end
      end)
    end

    ---True for a path inside the folder's `.proteus` folder, or that folder itself.
    ---@param rel string?
    ---@return boolean
    local function in_layer (rel)
      return rel ~= nil and (rel == '.proteus' or rel:sub (1, 9) == '.proteus/')
    end

    -- Changes on disk -----------------------------------------------------------------------

    if root then
      local folder = root
      app.fs.stat_path (folder, function (stat)
        if stat and stat.exists and stat.dir then
          return
        end
        forget (folder)
        fail (disk.native (folder, app.os) .. ' is not there any more.')
        app.store.set ('current', false)
      end)
      app.fs.watch_dir (folder, function (ev)
        -- A file that only changed keeps the list. Anything that came, went or moved does not,
        -- unless it is where the list never looks: what .gitignore leaves out, such as build
        -- output and logs, and what `project.exclude` leaves out.
        local stale = ev.overflow
        local patterns = excluded ()
        for _, change in ipairs (ev.changes) do
          local rel = disk.relative (folder, change.path, app.os)
          local unlisted = change.ignored == true
            or (
              rel ~= nil
              and exclude.matches (
                file_glob,
                patterns,
                rel,
                change.kind == 'dir',
                fold
              )
            )
          if
            not unlisted
            and (change.kind ~= 'file' or (rel ~= nil and not files_known[rel]))
          then
            stale = true
          end
          if
            not layer.loaded
            and change.kind ~= 'remove'
            and in_layer (rel)
          then
            offer ()
          end
        end
        if stale then
          forget_files ()
        end
        -- The editor starts after this plugin, so it is looked up when the change comes.
        local editor = app.try_use ('editor')
        if editor then
          editor.disk_changed (ev.changes, ev)
        end
        app.emit ('code:disk_changed', ev.changes, ev)
      end, function (err)
        app.warn ('not watching ' .. folder .. ' for changes: ' .. err)
      end)
    end

    -- The window ----------------------------------------------------------------------------

    if name then
      app.window.set_title (name .. ' - ' .. app.kernel.profile ().name)
    end
    -- The open folder's name in the status bar. A click opens a recent folder. With no folder
    -- open there is nothing to name, and the Welcome page offers Open Folder instead.
    if bar and root then
      bar.add ({
        id = 'project.folder',
        icon = 'folder',
        text = name or root,
        tooltip = disk.native (root, app.os),
        order = 0,
        run = open_recent,
      })
    end
    if bar and layer.loaded and layer.dir then
      local settings_file = layer.dir .. '/settings.json'
      bar.add ({
        id = 'project.layer',
        icon = 'layers',
        text = '.proteus',
        tooltip = "This folder's .proteus files are in use: "
          .. disk.native (layer.dir, app.os),
        order = 1,
        run = function ()
          local editor = app.try_use ('editor')
          if editor and app.fs.exists ('settings.json', 'project') then
            editor.open_file (settings_file)
          end
        end,
      })
    end

    -- Commands ------------------------------------------------------------------------------

    ---@return boolean
    local function has_root ()
      return root ~= nil
    end

    ---@return string
    local function reveal_label ()
      if app.os == 'windows' then
        return 'Reveal Folder in File Explorer'
      elseif app.os == 'macos' then
        return 'Reveal Folder in Finder'
      end
      return 'Reveal Folder in File Manager'
    end

    commands.register ({
      id = 'project.open',
      category = 'File',
      title = 'Open Folder…',
      icon = 'folder-open',
      menu = 'File',
      group = 'folder',
      order = 1,
      toolbar = 11,
      -- It only shows the Open Folder dialog, so any plugin may offer it.
      shared = true,
      when = function ()
        return desktop
      end,
      run = pick,
    })
    commands.register ({
      id = 'project.recent',
      category = 'File',
      title = 'Open Recent Folder…',
      menu_title = 'Open Recent',
      key = 'ctrl+r',
      icon = 'history',
      menu = 'File',
      group = 'folder',
      order = 2,
      -- It only shows the list of folders, and the user picks one, so any plugin may offer it.
      shared = true,
      when = function ()
        return desktop
      end,
      -- The menu bar lists the folders in a submenu. The key and the palette search them.
      menu_items = function ()
        local items = {} ---@type Proteus.MenuItem[]
        for _, path in ipairs (recent) do
          if not (root and disk.same (path, root, app.os)) then
            items[#items + 1] = {
              label = disk.name (path),
              tooltip = disk.native (path, app.os),
              icon = 'folder',
              run = function ()
                open (path)
              end,
            }
          end
        end
        if #items == 0 then
          items[1] = { label = 'No other folders yet', disabled = true }
        end
        items[#items + 1] = { separator = true }
        items[#items + 1] = {
          label = 'Search Recent Folders…',
          icon = 'search',
          run = open_recent,
        }
        return items
      end,
      run = open_recent,
    })
    commands.register ({
      id = 'project.close',
      category = 'File',
      title = 'Close Folder',
      icon = 'folder-x',
      menu = 'File',
      group = 'folder',
      order = 3,
      when = has_root,
      run = function ()
        switch_to (false)
      end,
    })
    commands.register ({
      id = 'project.reveal',
      category = 'File',
      title = reveal_label (),
      icon = 'folder-search',
      menu = 'File',
      group = 'folder',
      order = 4,
      when = has_root,
      run = function ()
        if root then
          app.system.open_path (disk.native (root, app.os), function (_, err)
            if err then
              fail (err)
            end
          end)
        end
      end,
    })
    commands.register ({
      id = 'project.trust',
      category = 'File',
      title = 'Trust This Folder',
      icon = 'shield-check',
      when = function ()
        return root ~= nil and not layer.trusted
      end,
      run = trust,
    })
    commands.register ({
      id = 'project.untrust',
      category = 'File',
      title = 'Stop Trusting This Folder',
      icon = 'shield-off',
      when = function ()
        return root ~= nil and layer.trusted
      end,
      run = function ()
        if root then
          app.kernel.trust_folder (root, false)
          app.kernel.reload_window ()
        end
      end,
    })
    commands.register ({
      id = 'project.copy_path',
      category = 'File',
      title = 'Copy Folder Path',
      icon = 'copy',
      when = has_root,
      run = function ()
        if root then
          app.system.clipboard (disk.native (root, app.os))
        end
      end,
    })

    -- The service ---------------------------------------------------------------------------

    ---@type Proteus.Project
    local service = {
      root = function ()
        return root
      end,
      name = function ()
        return name
      end,
      open = open,
      pick = pick,
      close = function ()
        if root then
          switch_to (false)
        end
      end,
      recent = function ()
        return { table.unpack (recent) }
      end,
      forget = forget,
      files = files,
      relative = function (path)
        return root and disk.relative (root, path, app.os) or nil
      end,
      absolute = function (rel)
        return root and disk.join (root, rel) or nil
      end,
      excluded = excluded,
      excludes = excludes,
      trusted = function ()
        return root ~= nil and layer.trusted
      end,
      ask_trust = ask_trust,
    }
    app.provide ('project', service, { needs = 'files' })
  end,
}
