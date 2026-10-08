-- proteus.code.explorer: a file tree of the project folder in the left dock, for the Code Editor.
--
-- It reads each folder from disk as it opens, and keeps up with changes made outside the app.
-- New files, new folders, renames and copies are typed into the tree itself, and a name is
-- relative to its folder. Dragging items onto a folder moves them there. Delete moves items
-- to the Recycle Bin. A letter after a name shows what Git sees: M changed, U new, A added,
-- D deleted, R renamed, and ! a conflict. A dot marks a file with unsaved edits. Open in
-- Terminal on a folder opens a terminal there, through proteus.terminal.
--
-- With the tree focused:
--   Up, Down, Home, End   move the selection, and Shift stretches it
--   Left, Right           close and open folders
--   Enter                 opens a file in the editor. Space opens it and keeps the focus here.
--   F2, Delete            rename and delete
--   Ctrl+C, Ctrl+X, Ctrl+V   copy, cut and paste files
--   Ctrl+A                selects every row
--   Ctrl+Z                takes back the last rename, move, paste, drop, new item or delete
--   letters               jump to the next name that starts with them
-- Ctrl+click adds a row to the selection, and Shift+click selects a run of rows.
--
-- Files dropped from the system are copied into the folder under the pointer. What the
-- `project.exclude` setting matches is left out. What .gitignore leaves out shows dimmed, or
-- is left out with `code.explorer.gitignore`.
--
-- The tree itself, with its selection, keys, typing, dragging and clipboard, is the app's
-- `lib/file_tree.lua`, which the Plugin Editor's Plugins panel draws too. This file reads the
-- folder from disk, changes it, and adds Git, the trash and Undo.
--
-- Files that belong with another file sit under it, such as package-lock.json under
-- package.json, by the `code.explorer.nest` setting and the rules other plugins add. The
-- shared tree draws the groups. This file works out who goes where, with file_nesting.lua.
--
-- Paths inside the tree are relative to the project folder, which is ''. They become full
-- paths only where they leave it: on disk, in the editor, and in the `code:disk_renamed` and
-- `code:search_folder` events.

local disk = require ('disk_paths') --[[@as DiskPaths]]
local file_tree = require ('file_tree') --[[@as FileTree.Module]]
local nesting = require ('file_nesting') --[[@as CodeExplorer.Nesting]]
local paths = require ('explorer_paths') --[[@as Explorer.PathsModule]]

-- lang=css
local CSS = [[
.explorer-head .title { font-weight: 600; letter-spacing: .04em; text-transform: uppercase; }
.tree-row.dotfile .tree-name { color: var(--fg-muted); }
.tree-row.ignored .tree-name { color: var(--fg-faint); }
.tree-row.git-modified .tree-name, .tree-row.git-modified .tree-badge { color: var(--diff-change, var(--warning)); }
.tree-row.git-added .tree-name, .tree-row.git-added .tree-badge,
.tree-row.git-untracked .tree-name, .tree-row.git-untracked .tree-badge { color: var(--diff-add, var(--success)); }
.tree-row.git-deleted .tree-name, .tree-row.git-deleted .tree-badge { color: var(--diff-remove, var(--danger)); }
.tree-row.git-conflicted .tree-name, .tree-row.git-conflicted .tree-badge { color: var(--danger); }
.tree-row.git-renamed .tree-name, .tree-row.git-renamed .tree-badge { color: var(--accent); }
.tree-row.git-inside .tree-badge { color: var(--diff-change, var(--warning)); }
]]

-- The most file changes Undo remembers.
local UNDO_LIMIT = 50

-- Files the tree draws under another file unless the setting says otherwise.
local NEST = {
  ['package.json'] = {
    'package-lock.json',
    'npm-shrinkwrap.json',
    'yarn.lock',
    'pnpm-lock.yaml',
    'pnpm-workspace.yaml',
    'bun.lock',
    'bun.lockb',
    '.npmrc',
    '.yarnrc.yml',
  },
  ['tsconfig.json'] = { 'tsconfig.*.json', '*.tsbuildinfo' },
  ['Cargo.toml'] = { 'Cargo.lock' },
  ['*.ts'] = {
    '${capture}.js',
    '${capture}.js.map',
    '${capture}.d.ts',
    '${capture}.d.ts.map',
  },
  ['*.js'] = { '${capture}.js.map', '${capture}.min.js', '${capture}.d.ts' },
}

-- The letter shown after a name for each thing Git can say about a file.
---@type table<string, string>
local GIT_LETTER = {
  modified = 'M',
  typechange = 'M',
  added = 'A',
  untracked = 'U',
  deleted = 'D',
  renamed = 'R',
  copied = 'C',
  conflicted = '!',
}

---A file or folder in the tree.
---@class CodeExplorer.Entry: FileTree.Entry
---@field name string
---@field path string From the root of the tree, with `/`.
---@field dir boolean
---@field kids? CodeExplorer.Entry[] Files drawn under this file, by `code.explorer.nest`.
---@field nested_in? string The path of the file this one is drawn under.
---@field ignored? boolean `.gitignore` leaves it out.

---An item another plugin adds to the right-click menu of a file.
---@class CodeExplorer.MenuItemSpec
---@field label string
---@field icon? string
---@field when? fun(path: string): boolean Shows the item only for files it is true for. `path` is the full path on disk.
---@field run fun(path: string) Gets the full path on disk.
---@field folders? boolean Shows the item on folders instead, and on the tree's empty space, which stands for its root. `path` is then the folder's full path.

---The icon a plugin draws when no icon pack has one.
---@param entry FileTree.Entry
---@param open boolean
---@return string
local function builtin_icon (entry, open)
  local name = entry.name:lower ()
  if entry.dir then
    return open and 'folder-open' or 'folder'
  elseif name:match ('%.md$') or name:match ('%.txt$') then
    return 'file-text'
  elseif
    name:match ('%.json$')
    or name:match ('%.ya?ml$')
    or name:match ('%.toml$')
  then
    return 'file-json'
  elseif
    name:match ('%.png$')
    or name:match ('%.jpe?g$')
    or name:match ('%.gif$')
    or name:match ('%.svg$')
    or name:match ('%.ico$')
    or name:match ('%.webp$')
  then
    return 'file-image'
  elseif name:match ('^%.') or name:match ('lock$') then
    return 'file-cog'
  elseif name:match ('%.[%w]+$') then
    return 'file-code'
  end
  return 'file'
end

---@type Proteus.Plugin
return {
  name = 'Project Explorer',
  description = 'A file tree of the folder open in the Code Editor, read from disk as folders open.',
  version = '1.5.0',
  depends = {
    'proteus.lib.ui',
    'proteus.ui.views',
    'proteus.code.project',
    'proteus.core.settings',
    'proteus.core.icons',
  },
  optional = {
    'proteus.core.keys',
    'proteus.core.commands',
    'proteus.ui.menus',
    'proteus.ui.palette',
    'proteus.ui.notify',
    'proteus.ui.tabs',
    'proteus.editor.core',
    -- Open in Terminal on a folder opens a terminal there.
    'proteus.terminal',
  },
  conflicts = { 'proteus.ws.explorer' },
  -- `files` to read and change the folder on disk, and for the `project` and `editor` services.
  permissions = { 'files' },
  -- `file-tree` is the shared tree in the app's lib/file_tree.lua.
  requires = { proteus = '>=0.3.1', features = { 'permissions', 'file-tree' } },
  activate = function (app)
    -- Full paths on disk need `files`, as the `project` service does.
    app.protect_event ('code:disk_renamed', { needs = 'files' })
    app.protect_event ('code:search_folder', { needs = 'files' })
    local ui = app.use ('ui')
    local views = app.use ('views')
    local icons = app.use ('icons')
    local project = app.use ('project')
    local settings = app.use ('settings')

    local root = project.root ()
    local fold = disk.folds_case (app.os)

    -- What the tree leaves out is the `project.exclude` setting, which Search and Go to File
    -- share. This one says what to do with what .gitignore leaves out.
    settings.define ('code.explorer.gitignore', {
      title = 'Hide what .gitignore leaves out',
      type = 'boolean',
      default = false,
      description = 'Leaves out of the Code Editor file tree what .gitignore ignores, such as build output. Off, it shows dimmed.',
    })
    settings.define ('code.explorer.nest', {
      title = 'Files the file tree nests',
      type = 'json',
      default = NEST,
      description = 'Maps a file name pattern to the patterns of the files drawn under it, such as {"package.json": ["yarn.lock"]}. '
        .. 'The first * in a key is kept, and ${capture} below stands for it, so {"*.ts": ["${capture}.js"]} puts app.js under app.ts. '
        .. 'Use {} to turn these off. Rules from other plugins, such as Godot .uid files, stay while those plugins run.',
    })

    -- With no folder open there is no tree. The Welcome page opens a folder instead.
    if not root then
      return
    end
    local folder = root

    ---True for a path the tree leaves out: what `project.exclude` matches, and with the
    ---`code.explorer.gitignore` setting, what .gitignore leaves out.
    ---@param path string In the tree.
    ---@param is_dir boolean
    ---@param ignored boolean
    ---@return boolean
    local function hidden (path, is_dir, ignored)
      if ignored and settings.get ('code.explorer.gitignore') == true then
        return true
      end
      -- A `project` service from before 1.1.0 has no patterns to match.
      return project.excludes ~= nil and project.excludes (path, is_dir)
    end

    -- Nest rules from other plugins, by plugin id. Each maps a pattern to the patterns under
    -- it, the same way the setting does.
    local plugin_nests = {} ---@type table<string, table<string, string[]>>
    local nest_rules = {} ---@type CodeExplorer.NestRule[]

    ---Reads the setting and the plugins' rules into `nest_rules`. A pattern the setting holds
    ---wins over a plugin's rule for the same pattern.
    local function read_nest_rules ()
      local merged = {} ---@type table<string, any>
      local ids = {} ---@type string[]
      for id in pairs (plugin_nests) do
        ids[#ids + 1] = id
      end
      table.sort (ids)
      for _, id in ipairs (ids) do
        for top, under in pairs (plugin_nests[id]) do
          merged[top] = under
        end
      end
      local value = settings.get ('code.explorer.nest')
      if type (value) == 'table' then
        for top, under in pairs (value) do
          merged[top] = under
        end
      end
      nest_rules = nesting.rules (merged, fold)
    end
    read_nest_rules ()

    ---Marks which files of a folder sit under another file.
    ---@param list CodeExplorer.Entry[] The folder's entries.
    local function nest_entries (list)
      local names = {} ---@type string[]
      local by_name = {} ---@type table<string, CodeExplorer.Entry>
      for _, e in ipairs (list) do
        e.kids, e.nested_in = nil, nil
        if not e.dir then
          names[#names + 1] = e.name
          by_name[e.name] = e
        end
      end
      for top, kids in pairs (nesting.group (names, nest_rules, fold)) do
        local parent = by_name[top]
        parent.kids = {}
        for _, name in ipairs (kids) do
          local kid = by_name[name]
          kid.nested_in = parent.path
          parent.kids[#parent.kids + 1] = kid
        end
      end
    end

    ---The full path of a path in the tree.
    ---@param rel string
    ---@return string
    local function abs (rel)
      return disk.join (folder, rel)
    end

    ---The path in the tree of a full path, or nil outside the folder.
    ---@param full any
    ---@return string?
    local function rel_of (full)
      if type (full) ~= 'string' then
        return nil
      end
      return disk.relative (folder, full, app.os)
    end

    local git_kind = {} ---@type table<string, string> Path to what Git says about it.
    local git_inside = {} ---@type table<string, boolean> Folders with changes inside.
    -- Changes Undo takes back, the last one at the end.
    local undo_steps = {} ---@type FileTree.Step[]
    local undoing = false

    -- Folders as read from disk, by their path in the tree. A folder not read yet has none.
    local listing = {} ---@type table<string, CodeExplorer.Entry[]>
    local failed = {} ---@type table<string, string>
    local loading = {} ---@type table<string, boolean>
    local again = {} ---@type table<string, boolean>
    local waiters = {} ---@type table<string, fun()[]>

    ---@return Proteus.Picker?
    local function picker ()
      return app.try_use ('picker')
    end
    local first_line = file_tree.first_line
    ---@param err any
    local function report (err)
      local n = app.try_use ('notify')
      if n then
        n.error (first_line (err))
      else
        app.error (err)
      end
    end

    ---Opens a file of the tree in the editor.
    ---@param path string In the tree.
    ---@param opts? Proteus.OpenOptions
    local function open_file (path, opts)
      local editor = app.try_use ('editor')
      if editor then
        editor.open_file (abs (path), opts)
      end
    end

    ---Remembers a change for Undo.
    ---@param step FileTree.Step
    local function record (step)
      if undoing then
        return
      end
      local list = step.moves or step.paths or {}
      if #list == 0 then
        return
      end
      undo_steps[#undo_steps + 1] = step
      if #undo_steps > UNDO_LIMIT then
        table.remove (undo_steps, 1)
      end
    end

    ---@type FileTree
    local tree

    -- Reading folders ----------------------------------------------------------------------

    ---Reads a folder from disk, then draws the tree. `done` runs once it is read. A folder
    ---asked for again while it is being read is read once more afterwards, so a change that
    ---arrived meanwhile is not missed.
    ---@param dir string
    ---@param done? fun()
    local function load (dir, done)
      if done then
        local list = waiters[dir] or {}
        waiters[dir] = list
        list[#list + 1] = done
      end
      if loading[dir] then
        again[dir] = true
        return
      end
      loading[dir] = true
      -- The folder's names, and the ones .gitignore leaves out, come in any order.
      local names, err, skipped = nil, nil, nil ---@type string[]?, string?, table<string, boolean>?
      local function both_read ()
        if not names and not err or not skipped then
          return
        end
        loading[dir] = nil
        if not names then
          failed[dir] = first_line (err or 'Could not read this folder')
          listing[dir] = {}
        else
          failed[dir] = nil
          local list = {} ---@type CodeExplorer.Entry[]
          for _, raw in ipairs (names) do
            local is_dir = raw:sub (-1) == '/'
            local name = is_dir and raw:sub (1, -2) or raw
            local path = paths.join (dir, name)
            local ignored = skipped[raw] == true
            if not hidden (path, is_dir, ignored) then
              list[#list + 1] = {
                name = name,
                path = path,
                dir = is_dir,
                ignored = ignored or nil,
              }
            end
          end
          table.sort (list, function (a, b)
            if a.dir ~= b.dir then
              return a.dir
            end
            return a.name:lower () < b.name:lower ()
          end)
          nest_entries (list)
          listing[dir] = list
        end
        if again[dir] then
          again[dir] = nil
          load (dir)
          return
        end
        local list = waiters[dir] or {}
        waiters[dir] = nil
        for _, fn in ipairs (list) do
          app.try (fn)
        end
        tree.render_soon ()
      end
      if not app.fs.ignored_names then
        -- An older Proteus cannot tell what .gitignore leaves out.
        skipped = {}
      end
      app.fs.list_dir (abs (dir), function (found, list_err)
        names, err =
          found, list_err or (not found and 'Could not read this folder') or nil
        both_read ()
      end)
      if not app.fs.ignored_names then
        return
      end
      app.fs.ignored_names (abs (dir), function (found)
        skipped = {}
        for _, raw in
          ipairs (found or {} --[[@as string[] ]])
        do
          skipped[raw] = true
        end
        both_read ()
      end)
    end

    ---Reads folders again, then runs `after` and draws the tree. Folders never read stay
    ---unread until they open.
    ---@param dirs string[]
    ---@param after? fun()
    local function refresh (dirs, after)
      local left = 0
      local finished = false
      local function one_done ()
        left = left - 1
        if left == 0 and not finished then
          finished = true
          if after then
            after ()
          end
          tree.render_soon ()
        end
      end
      local seen = {} ---@type table<string, boolean>
      for _, d in ipairs (dirs) do
        if not seen[d] and (listing[d] or d == '') then
          seen[d] = true
          left = left + 1
        end
      end
      if left == 0 then
        finished = true
        if after then
          after ()
        end
        tree.render_soon ()
        return
      end
      for d in pairs (seen) do
        load (d, one_done)
      end
    end

    ---Reads every folder read so far again.
    local function refresh_all ()
      local dirs = {} ---@type string[]
      for d in pairs (listing) do
        dirs[#dirs + 1] = d
      end
      refresh (dirs)
    end

    ---The entry at `path` if its folder has been read, compared the way the system compares
    ---names.
    ---@param path string
    ---@return CodeExplorer.Entry?
    local function known (path)
      local list = listing[paths.parent (path)]
      if not list then
        return nil
      end
      local want = fold and path:lower () or path
      for _, e in ipairs (list) do
        if (fold and e.path:lower () or e.path) == want then
          return e
        end
      end
      return nil
    end

    ---Makes an empty file or a folder at `path`, unless something is there already.
    ---@param kind 'file'|'folder'
    ---@param path string
    ---@param cb fun(err: string?)
    local function create (kind, path, cb)
      local full = abs (path)
      app.fs.stat_path (full, function (stat)
        if stat and stat.exists then
          cb ((path:match ('[^/]+$') or path) .. ' already exists here')
          return
        end
        if kind == 'folder' then
          app.fs.make_dir (full, function (_, err)
            cb (err)
          end)
          return
        end
        app.fs.make_dir (disk.parent (full), function (_, err)
          if err then
            cb (err)
            return
          end
          app.fs.write_file (full, '', function (_, write_err)
            cb (write_err)
          end)
        end)
      end)
    end

    ---@return string
    local function bin_name ()
      return app.os == 'windows' and 'the Recycle Bin' or 'the Trash'
    end

    ---A sentence naming the files with unsaved edits inside the items, or '' when none has
    ---any. The editor says which documents have unsaved edits.
    ---@param list FileTree.Entry[]
    ---@return string
    local function unsaved_note (list)
      local files = {} ---@type string[]
      local editor = app.try_use ('editor')
      for _, info in ipairs (editor and editor.docs () or {}) do
        local path = rel_of (info.path)
        if path and info.dirty () then
          for _, e in ipairs (list) do
            if paths.inside (path, e.path) then
              files[#files + 1] = path
              break
            end
          end
        end
      end
      if #files == 0 then
        return ''
      end
      table.sort (files)
      local names = files[1]
      if #files > 3 then
        names = table.concat (files, ', ', 1, 3)
          .. ' and '
          .. (#files - 3)
          .. ' more'
      elseif #files > 1 then
        names = table.concat (files, ', ', 1, #files - 1)
          .. ' and '
          .. files[#files]
      end
      return ' '
        .. names
        .. (#files == 1 and ' has' or ' have')
        .. ' unsaved changes, which are lost.'
    end

    ---Moves items to the Recycle Bin, after asking. An item the bin refuses, such as one on a
    ---network drive, can be deleted for good instead, after asking again. The question names
    ---any file in them with unsaved edits.
    ---@param list FileTree.Entry[]
    local function delete (list)
      local p = picker ()
      if #list == 0 or not p then
        return
      end
      local what = #list == 1 and list[1].name or (#list .. ' items')
      p.confirm ({
        message = 'Move '
          .. what
          .. ' to '
          .. bin_name ()
          .. '?'
          .. unsaved_note (list),
        yes = 'Move to ' .. (app.os == 'windows' and 'Recycle Bin' or 'Trash'),
        on_yes = function ()
          tree.select_after (list)
          -- What went to the trash, which Undo brings back.
          local trashed = {} ---@type string[]
          local left = #list
          for _, e in ipairs (list) do
            local entry = e
            app.fs.trash_path (abs (entry.path), function (_, err)
              left = left - 1
              if not err then
                trashed[#trashed + 1] = entry.path
              end
              if left == 0 then
                record ({ kind = 'trash', paths = trashed, what = 'Delete' })
              end
              if not err then
                refresh ({ paths.parent (entry.path) })
                return
              end
              p.confirm ({
                message = entry.name
                  .. ' could not go to '
                  .. bin_name ()
                  .. ' ('
                  .. first_line (err)
                  .. '). Delete it for good?',
                yes = 'Delete for Good',
                on_yes = function ()
                  app.fs.delete_path (abs (entry.path), function (_, del_err)
                    if del_err then
                      report (del_err)
                    end
                    refresh ({ paths.parent (entry.path) })
                  end)
                end,
              })
            end)
          end
        end,
      })
    end

    -- Undo -------------------------------------------------------------------------------

    ---Takes back the last change made in the tree: items that moved go back, items it made go
    ---to the trash, and items it moved to the trash come back.
    local function undo ()
      local step = undo_steps[#undo_steps]
      if not step or undoing then
        return
      end
      local list = step.moves or step.paths or {}
      local function go ()
        if undo_steps[#undo_steps] ~= step or undoing then
          return
        end
        undo_steps[#undo_steps] = nil
        undoing = true
        local left = #list
        local dirs, back = {}, {} ---@type string[], string[]
        ---@param err string?
        ---@param path string?
        local function one_done (err, path)
          if err then
            report (err)
          elseif path then
            back[#back + 1] = path
            if paths.parent (path) ~= '' then
              tree.expand_to (paths.parent (path))
            end
          end
          left = left - 1
          if left > 0 then
            return
          end
          undoing = false
          refresh (dirs, function ()
            tree.select (back, true)
          end)
        end
        if step.kind == 'move' then
          for _, m in
            ipairs (list --[[@as FileTree.Move[] ]])
          do
            local move = m
            dirs[#dirs + 1] = paths.parent (move.from)
            dirs[#dirs + 1] = paths.parent (move.to)
            app.fs.move_path (abs (move.to), abs (move.from), function (_, err)
              if not err then
                tree.follow_move (move.to, move.from)
              end
              one_done (err, not err and move.from or nil)
            end)
          end
        elseif step.kind == 'made' then
          for _, p in
            ipairs (list --[[@as string[] ]])
          do
            dirs[#dirs + 1] = paths.parent (p)
            app.fs.trash_path (abs (p), function (_, err)
              one_done (err)
            end)
          end
        elseif not app.fs.untrash_path then
          undoing = false
          report (
            'This version of Proteus cannot bring files back from the trash.'
          )
        else
          for _, p in
            ipairs (list --[[@as string[] ]])
          do
            local path = p
            dirs[#dirs + 1] = paths.parent (path)
            app.fs.untrash_path (abs (path), function (_, err)
              one_done (err, not err and path or nil)
            end)
          end
        end
      end
      -- What the tree made may have been changed since, so taking it away asks first. It goes
      -- to the trash, where it can come back.
      local p = picker ()
      if step.kind ~= 'made' or not p then
        go ()
        return
      end
      local first = list[1] --[[@as string]]
      local what = #list == 1 and (first:match ('[^/]+$') or first)
        or (#list .. ' items')
      p.confirm ({
        message = 'Undo '
          .. step.what
          .. ' and move '
          .. what
          .. ' to '
          .. bin_name ()
          .. '?',
        yes = 'Undo ' .. step.what,
        on_yes = go,
      })
    end

    -- Files dropped from the system -------------------------------------------------------

    ---Copies files and folders from elsewhere on disk into `dir`. A name already there gets a
    ---free name instead, as a paste does.
    ---@param sources string[] Full paths.
    ---@param dir string In the tree.
    local function drop_files (sources, dir)
      local found = {} ---@type { from: string, dir: boolean }[]
      local left = #sources
      ---Works out every name once all the sources are known, then copies them all.
      local function copy_all ()
        local claimed = {} ---@type table<string, boolean>
        local made = {} ---@type string[]
        local pending = #found
        if pending == 0 then
          return
        end
        for _, f in ipairs (found) do
          local target =
            tree.free_path (dir, disk.name (f.from), f.dir, claimed)
          app.fs.copy_path (f.from, abs (target), function (_, err)
            if err then
              report (err)
            else
              made[#made + 1] = target
            end
            pending = pending - 1
            if pending > 0 then
              return
            end
            record ({ kind = 'made', paths = made, what = 'Drop' })
            if dir ~= '' then
              tree.expand_to (dir)
            end
            refresh ({ dir }, function ()
              tree.select (made, true)
            end)
          end)
        end
      end
      for _, src in ipairs (sources) do
        local from = disk.normalize (src)
        app.fs.stat_path (from, function (stat)
          if stat and stat.exists then
            found[#found + 1] = { from = from, dir = stat.dir }
          end
          left = left - 1
          if left == 0 then
            copy_all ()
          end
        end)
      end
    end

    -- The right-click menu ---------------------------------------------------------------

    -- Items other plugins add to a file's menu, in the order they were added.
    local plugin_items = {} ---@type { owner: string, spec: CodeExplorer.MenuItemSpec }[]

    ---@param list FileTree.Entry[]
    ---@param full boolean
    local function copy_paths (list, full)
      local lines = {} ---@type string[]
      for _, e in ipairs (list) do
        lines[#lines + 1] = full and disk.native (abs (e.path), app.os)
          or e.path
      end
      app.system.clipboard (table.concat (lines, '\n'))
    end

    ---The right-click menu for the selection, or for the empty space below the rows.
    ---@param entry FileTree.Entry?
    ---@return Proteus.MenuItem[]
    local function items_for (entry)
      ---@type Proteus.MenuItem[]
      local items = {}
      ---@param item Proteus.MenuItem
      local function add (item)
        items[#items + 1] = item
      end
      local sep = { separator = true } ---@type Proteus.MenuItem
      local list = tree.chosen ()
      local reveal_label = file_tree.reveal_label (app.os)
      ---@param cut boolean
      ---@return Proteus.MenuItem
      local function clip_item (cut)
        return {
          label = cut and 'Cut' or 'Copy',
          icon = cut and 'scissors' or 'copy',
          key = cut and 'Ctrl+X' or 'Ctrl+C',
          run = function ()
            tree.set_clip (cut)
          end,
        }
      end

      if entry and #list > 1 then
        add (clip_item (true))
        add (clip_item (false))
        add (sep)
        add ({
          label = 'Copy Paths',
          icon = 'copy',
          run = function ()
            copy_paths (list, true)
          end,
        })
        add ({
          label = 'Copy Relative Paths',
          icon = 'copy',
          run = function ()
            copy_paths (list, false)
          end,
        })
        add (sep)
        add ({
          label = 'Delete ' .. #list .. ' Items',
          icon = 'trash-2',
          key = 'Delete',
          danger = true,
          run = function ()
            delete (list)
          end,
        })
        return items
      end

      local path = entry and entry.path or ''
      local dir = (not entry or entry.dir) and path or paths.parent (path)

      if entry and not entry.dir then
        add ({
          label = 'Open',
          icon = 'file',
          run = function ()
            open_file (path)
          end,
        })
        -- Two plugins may add the same item, such as both Godot plugins. The first one shows.
        local full = abs (path)
        local shown = {} ---@type table<string, boolean>
        for _, item in ipairs (plugin_items) do
          local spec = item.spec
          if
            not spec.folders
            and not shown[spec.label]
            and (not spec.when or app.try (spec.when, full) == true)
          then
            shown[spec.label] = true
            add ({
              label = spec.label,
              icon = spec.icon,
              run = function ()
                app.try (spec.run, full)
              end,
            })
          end
        end
        add (sep)
      end
      add ({
        label = 'New File…',
        icon = 'file-plus',
        run = function ()
          tree.start_create ('file', dir)
        end,
      })
      add ({
        label = 'New Folder…',
        icon = 'folder-plus',
        run = function ()
          tree.start_create ('folder', dir)
        end,
      })
      if not entry or entry.dir then
        local full = abs (dir)
        local shown = {} ---@type table<string, boolean>
        for _, item in ipairs (plugin_items) do
          local spec = item.spec
          if
            spec.folders
            and not shown[spec.label]
            and (not spec.when or app.try (spec.when, full) == true)
          then
            shown[spec.label] = true
            add ({
              label = spec.label,
              icon = spec.icon,
              run = function ()
                app.try (spec.run, full)
              end,
            })
          end
        end
      end
      local search = app.kernel.plugin ('proteus.code.search')
      if search and search.status == 'active' and (not entry or entry.dir) then
        add ({
          label = 'Find in Folder…',
          icon = 'search',
          run = function ()
            app.emit ('code:search_folder', abs (dir))
          end,
        })
      end
      local terminal = app.try_use ('terminal') --[[@as Proteus.Terminal?]]
      if terminal and (not entry or entry.dir) then
        add ({
          label = 'Open in Terminal',
          icon = 'square-terminal',
          run = function ()
            terminal.open ({ cwd = abs (dir) })
          end,
        })
      end
      add (sep)
      if entry then
        add (clip_item (true))
        add (clip_item (false))
      end
      add ({
        label = 'Paste',
        icon = 'clipboard-paste',
        key = 'Ctrl+V',
        disabled = tree.clip () == nil,
        run = function ()
          tree.paste (dir)
        end,
      })
      if entry then
        add ({
          label = 'Duplicate…',
          icon = 'copy-plus',
          run = function ()
            tree.start_copy (entry)
          end,
        })
        add (sep)
        add ({
          label = 'Copy Path',
          icon = 'copy',
          run = function ()
            copy_paths ({ entry }, true)
          end,
        })
        add ({
          label = 'Copy Relative Path',
          icon = 'copy',
          run = function ()
            copy_paths ({ entry }, false)
          end,
        })
        add ({
          label = reveal_label,
          icon = 'folder-search',
          run = function ()
            app.system.reveal (abs (path), function (_, err)
              if err then
                report (err)
              end
            end)
          end,
        })
        add (sep)
        add ({
          label = 'Rename…',
          icon = 'pencil',
          key = 'F2',
          run = function ()
            tree.start_rename (entry)
          end,
        })
        add ({
          label = 'Delete',
          icon = 'trash-2',
          key = 'Delete',
          danger = true,
          run = function ()
            delete ({ entry })
          end,
        })
      else
        add (sep)
        local step = undo_steps[#undo_steps]
        if step then
          add ({
            label = 'Undo ' .. step.what,
            icon = 'undo-2',
            key = 'Ctrl+Z',
            run = undo,
          })
        end
        add ({
          label = 'Refresh',
          icon = 'refresh-cw',
          run = refresh_all,
        })
        add ({
          label = 'Collapse All',
          icon = 'list-collapse',
          run = tree.collapse_all,
        })
        add ({
          label = reveal_label,
          icon = 'folder-search',
          run = function ()
            app.system.open_path (disk.native (folder, app.os), function (_, err)
              if err then
                report (err)
              end
            end)
          end,
        })
      end
      return items
    end

    -- The tree ---------------------------------------------------------------------------

    ---@param from string
    ---@param to string
    ---@param cb fun(err: string?)
    local function move (from, to, cb)
      app.fs.move_path (abs (from), abs (to), function (_, err)
        cb (err)
      end)
    end

    tree = file_tree.new (app, ui, icons, {
      store_key = 'expanded:' .. folder,
      commands = 'code.explorer',
      fold = fold,
      ---@param dir string
      ---@return FileTree.Entry[]?
      ---@return string?
      list = function (dir)
        if not listing[dir] then
          load (dir)
          return nil
        end
        return listing[dir], failed[dir]
      end,
      find = known,
      move = move,
      ---@param from string
      ---@param to string
      ---@param cb fun(err: string?)
      copy = function (from, to, cb)
        app.fs.copy_path (abs (from), abs (to), function (_, err)
          cb (err)
        end)
      end,
      create = create,
      delete = delete,
      ---@param entry FileTree.Entry
      ---@param how FileTree.How
      open = function (entry, how)
        if not entry.dir then
          open_file (entry.path, how.keep_focus and { keep_focus = true } or nil)
        end
      end,
      menu = items_for,
      ---@param entry FileTree.Entry
      ---@return FileTree.Look
      look = function (entry)
        local p = entry.path
        local kind = git_kind[p]
        local badge = kind and GIT_LETTER[kind] or ''
        local inside = entry.dir and git_inside[p] or false
        if badge == '' and inside then
          badge = '•'
        end
        local classes = {} ---@type string[]
        if entry.name:sub (1, 1) == '.' then
          classes[#classes + 1] = 'dotfile'
        end
        if
          (entry --[[@as CodeExplorer.Entry]]).ignored
        then
          classes[#classes + 1] = 'ignored'
        end
        if kind then
          classes[#classes + 1] = 'git-' .. kind
        end
        if inside then
          classes[#classes + 1] = 'git-inside'
        end
        return {
          classes = classes,
          badge = badge,
          badge_title = kind or (badge ~= '' and 'Changes inside' or ''),
        }
      end,
      icon = builtin_icon,
      empty = function ()
        return listing[''] and 'This folder is empty.'
          or 'Reading the folder…'
      end,
      ---@param path string
      ---@return boolean
      settled = function (path)
        return listing[paths.parent (path)] ~= nil
      end,
      rel = rel_of,
      root_name = function ()
        return project.name () or 'the folder'
      end,
      refresh = refresh,
      ---Tells the editor, and any plugin listening, that something in the tree moved, so
      ---open files follow it. What was read inside it is read again at its new place.
      ---@param from string
      ---@param to string
      moved = function (from, to)
        for d in pairs (listing) do
          if paths.inside (d, from) then
            listing[d] = nil
          end
        end
        local editor = app.try_use ('editor')
        if editor then
          editor.disk_renamed (abs (from), abs (to))
        end
        app.emit ('code:disk_renamed', abs (from), abs (to))
      end,
      record = record,
      drop_files = drop_files,
      shortcuts = {
        { combo = 'ctrl+z', id = 'undo', title = 'Undo', run = undo },
      },
      report = report,
    })

    -- After the tree's own styles, so these win.
    ui.css (CSS)

    -- Keeping up with the disk and Git ---------------------------------------------------

    -- A change reads its folder again, if that folder has been read. Too many changes to
    -- list read every folder again.
    local changed_dirs = {} ---@type table<string, boolean>
    local changes_pending = false
    app.on ('code:disk_changed', function (changes, ev)
      if type (ev) == 'table' and ev.overflow then
        refresh_all ()
        return
      end
      for _, change in
        ipairs (changes or {} --[[@as Proteus.DirChange[] ]])
      do
        local rel = rel_of (change.path)
        if rel and rel ~= '' then
          changed_dirs[paths.parent (rel)] = true
          if change.kind ~= 'file' then
            changed_dirs[rel] = true
          end
        end
      end
      if changes_pending then
        return
      end
      changes_pending = true
      app.timer.after (100, function ()
        changes_pending = false
        local dirs = {} ---@type string[]
        for d in pairs (changed_dirs) do
          if listing[d] then
            dirs[#dirs + 1] = d
          end
        end
        changed_dirs = {}
        if #dirs > 0 then
          refresh (dirs)
        end
      end)
    end)

    ---Groups the folders read so far again, without reading the disk.
    local function regroup ()
      read_nest_rules ()
      for _, list in pairs (listing) do
        nest_entries (list)
      end
      tree.render_soon ()
    end
    settings.watch ('code.explorer.nest', regroup)

    for _, key in ipairs ({ 'project.exclude', 'code.explorer.gitignore' }) do
      settings.watch (key, function ()
        if listing[''] then
          refresh_all ()
        end
      end)
    end

    app.on ('git:status', function (map)
      git_kind, git_inside = {}, {}
      for full, kind in
        pairs (map or {} --[[@as table<string, string>]])
      do
        local rel = rel_of (full)
        if rel and rel ~= '' then
          git_kind[rel] = kind
          local d = paths.parent (rel)
          while d ~= '' and not git_inside[d] do
            git_inside[d] = true
            d = paths.parent (d)
          end
        end
      end
      tree.render_soon ()
    end)

    -- The panel --------------------------------------------------------------------------

    ---@param icon string
    ---@param title string
    ---@param run fun()
    ---@return Proteus.El
    local function head_button (icon, title, run)
      return ui.button ({
        class = 'icon-button',
        title = title,
        ui.icon (icon, 15),
        onclick = run,
      })
    end

    local content = ui.div ({
      class = 'explorer',
      ui.div ({
        class = 'explorer-head',
        ui.span ({
          class = 'title',
          title = disk.native (folder, app.os),
          project.name () or folder,
        }),
        head_button ('file-plus', 'New file', function ()
          tree.start_create ('file', tree.target_dir ())
        end),
        head_button ('folder-plus', 'New folder', function ()
          tree.start_create ('folder', tree.target_dir ())
        end),
        head_button ('refresh-cw', 'Refresh', refresh_all),
        head_button ('list-collapse', 'Collapse all', tree.collapse_all),
      }),
      tree.el,
      tree.find_label,
    })
    tree.render ()

    views.add ('left', {
      id = 'explorer',
      title = 'Explorer',
      icon = 'files',
      order = 10,
      key = 'ctrl+shift+e',
      content = content,
    })

    -- Other plugins add to the tree: sections under it, such as the folder's own Proteus
    -- plugins, files to nest, and items in a file's right-click menu. A restricted plugin
    -- adds sections only to its own views, so the explorer adds them for it. What a plugin
    -- added goes away when it stops.
    app.provide_scoped ('code.explorer', function (consumer)
      local id = consumer.id
      consumer.dispose (function ()
        for i = #plugin_items, 1, -1 do
          if plugin_items[i].owner == id then
            table.remove (plugin_items, i)
          end
        end
        if plugin_nests[id] then
          plugin_nests[id] = nil
          regroup ()
        end
      end)
      return {
        ---@param spec Proteus.ViewSectionSpec
        ---@return Proteus.ViewSection?
        add_section = function (spec)
          return views.add_section ('explorer', spec)
        end,
        ---Adds files to nest, as `code.explorer.nest` names them. A pattern the setting
        ---holds wins over the plugin's.
        ---@param rules table<string, string[]>
        add_nesting = function (rules)
          if type (rules) ~= 'table' then
            error ('add_nesting takes a table of patterns', 2)
          end
          local mine = plugin_nests[id] or {}
          for top, under in pairs (rules) do
            if type (top) == 'string' and type (under) == 'table' then
              local list = {} ---@type string[]
              for _, v in ipairs (under) do
                if type (v) == 'string' then
                  list[#list + 1] = v
                end
              end
              mine[top] = list
            end
          end
          plugin_nests[id] = mine
          regroup ()
        end,
        ---Adds an item to a file's right-click menu. It hands the plugin full paths on disk,
        ---so a restricted plugin needs `files`.
        ---@param spec CodeExplorer.MenuItemSpec
        add_menu_item = function (spec)
          local allowed = consumer.trusted ~= false
          for _, p in ipairs (consumer.permissions or {}) do
            if p == 'files' then
              allowed = true
            end
          end
          if not allowed then
            error ('add_menu_item needs the files permission', 2)
          end
          if
            type (spec) ~= 'table'
            or type (spec.label) ~= 'string'
            or type (spec.run) ~= 'function'
          then
            error ('add_menu_item needs a label and a run function', 2)
          end
          plugin_items[#plugin_items + 1] = {
            owner = id,
            spec = {
              label = spec.label,
              icon = spec.icon,
              when = spec.when,
              run = spec.run,
              folders = spec.folders == true,
            },
          }
        end,
      }
    end)

    local commands = app.try_use ('commands')
    if commands then
      commands.register ({
        id = 'code.explorer.refresh',
        category = 'Explorer',
        title = 'Refresh',
        icon = 'refresh-cw',
        run = refresh_all,
      })
      commands.register ({
        id = 'code.explorer.collapse',
        category = 'Explorer',
        title = 'Collapse All',
        icon = 'list-collapse',
        run = tree.collapse_all,
      })
      commands.register ({
        id = 'code.explorer.reveal_active',
        category = 'Explorer',
        title = 'Reveal Active File in Explorer',
        icon = 'locate',
        when = function ()
          return tree.active_tab () ~= nil
        end,
        run = function ()
          local path = tree.active_tab ()
          if not path then
            return
          end
          views.show ('explorer')
          tree.reveal (path)
          tree.focus ()
        end,
      })
      commands.register ({
        id = 'code.explorer.undo_last',
        category = 'Explorer',
        title = 'Undo the Last File Change',
        icon = 'undo-2',
        when = function ()
          return #undo_steps > 0
        end,
        run = undo,
      })
    end
  end,
}
