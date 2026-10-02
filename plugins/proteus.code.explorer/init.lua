-- proteus.code.explorer: a file tree of the project folder in the left dock, for the Code Editor.
--
-- It reads each folder from disk as it opens, and keeps up with changes made outside the app.
-- New files, new folders, renames and copies are typed into the tree itself, and a name is
-- relative to its folder. Dragging items onto a folder moves them there. Delete moves items
-- to the Recycle Bin. A letter after a name shows what Git sees: M changed, U new, A added,
-- D deleted, R renamed, and ! a conflict. A dot marks a file with unsaved edits.
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
-- Paths inside the tree are relative to the project folder, which is ''. They become full
-- paths only where they leave it: on disk, in the editor, and in the `code:disk_renamed`,
-- `code:search_folder` and `code:open_terminal` events.

local disk = require ('disk_paths') --[[@as DiskPaths]]
local paths = require ('explorer_paths') --[[@as Explorer.PathsModule]]

-- lang=css
local CSS = [[
.explorer { position: relative; display: flex; flex-direction: column; height: 100%; }
.explorer-head { display: flex; align-items: center; gap: 2px; padding: 4px 6px 4px 12px; flex: none; }
.explorer-head .title { flex: 1; font-size: 11px; font-weight: 600; letter-spacing: .04em; text-transform: uppercase;
  color: var(--fg-muted); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.explorer-tree { flex: 1; overflow: auto; padding-bottom: 12px; outline: none;
  --tree-guide: color-mix(in srgb, var(--fg-faint) 40%, transparent);
  --tree-drop: color-mix(in srgb, var(--accent) 26%, transparent); }
.explorer-tree.drop-root { background-color: var(--tree-drop); }
.icon-button { display: inline-grid; place-items: center; width: 24px; height: 24px; border: none; padding: 0;
  border-radius: var(--radius); background: none; color: var(--fg-muted); cursor: pointer; }
.icon-button:hover { background: var(--bg-hover); color: var(--fg); }
.tree-row { display: flex; align-items: center; gap: 4px; height: 24px; padding: 0 8px 0 calc(8px + var(--depth, 0) * 20px);
  cursor: pointer; white-space: nowrap; color: var(--fg); user-select: none;
  background-image: repeating-linear-gradient(to right, transparent 0 7px, var(--tree-guide) 7px 8px, transparent 8px 20px);
  background-size: calc(var(--depth, 0) * 20px) 100%; background-position: 8px 0; background-repeat: no-repeat; }
.tree-row:hover { background-color: var(--bg-hover); }
.tree-row.selected { background-color: var(--bg-active); }
.explorer-tree:focus .tree-row.cursor { box-shadow: inset 0 0 0 1px var(--accent); }
.tree-row.drop { background-color: var(--tree-drop); }
.tree-row.cut { opacity: .5; }
.tree-twisty { flex: none; display: inline-grid; place-items: center; width: 16px; color: var(--fg-muted); }
.tree-row .ui-icon { color: var(--fg-muted); }
.tree-row .tree-name { flex: 1; margin-left: 2px; overflow: hidden; text-overflow: ellipsis; }
.tree-row.dotfile .tree-name { color: var(--fg-muted); }
.tree-row.ignored .tree-name { color: var(--fg-faint); }
.tree-mark { flex: none; display: none; width: 7px; height: 7px; border-radius: 50%; background: var(--fg-muted); }
.tree-row.unsaved .tree-mark { display: block; }
.tree-badge { flex: none; font-size: 10px; font-weight: 700; width: 14px; text-align: center; color: var(--fg-faint); }
.tree-row.git-modified .tree-name, .tree-row.git-modified .tree-badge { color: var(--warning); }
.tree-row.git-added .tree-name, .tree-row.git-added .tree-badge,
.tree-row.git-untracked .tree-name, .tree-row.git-untracked .tree-badge { color: var(--success); }
.tree-row.git-deleted .tree-name, .tree-row.git-deleted .tree-badge,
.tree-row.git-conflicted .tree-name, .tree-row.git-conflicted .tree-badge { color: var(--danger); }
.tree-row.git-renamed .tree-name, .tree-row.git-renamed .tree-badge { color: var(--accent); }
.tree-row.git-inside .tree-badge { color: var(--warning); }
.tree-row.editing { position: relative; cursor: default; }
.tree-input { flex: 1; min-width: 0; height: 20px; margin-left: 2px; padding: 0 4px; font: inherit; color: var(--fg);
  background: var(--bg); border: 1px solid var(--accent); border-radius: 3px; outline: none; }
.tree-input.invalid { border-color: var(--danger); }
.tree-error { position: absolute; z-index: 5; top: 100%; left: calc(8px + var(--depth, 0) * 20px + 41px); right: 8px;
  padding: 4px 8px; font-size: 12px; white-space: normal; color: var(--fg); background: var(--bg-elev);
  border: 1px solid var(--danger); border-radius: 0 0 3px 3px; }
.tree-empty { padding: 16px 12px; font-size: 12px; color: var(--fg-faint); }
.tree-note { padding: 2px 8px 2px calc(30px + var(--depth, 0) * 20px); font-size: 12px; color: var(--fg-faint); }
.tree-find { position: absolute; left: 12px; right: 12px; bottom: 8px; padding: 3px 8px; pointer-events: none;
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-size: 12px; color: var(--fg);
  background: var(--bg-elev); border: 1px solid var(--accent); border-radius: var(--radius); box-shadow: var(--shadow); }
.tree-find.none { border-color: var(--danger); }
.tree-ghost { position: fixed; z-index: 1000; pointer-events: none; max-width: 320px; padding: 3px 8px;
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-size: 12px; color: var(--fg);
  background: var(--bg-elev); border: 1px solid var(--border); border-radius: var(--radius); box-shadow: var(--shadow); }
.tree-ghost.refused { color: var(--fg-muted); }
.explorer-tree.dragging, .explorer-tree.dragging * { cursor: grabbing !important; }
]]

-- The pointer moves this far before a press on a row turns into a drag, so a click still opens it.
local DRAG_START = 5
-- A closed folder opens once a dragged item rests on it this many milliseconds.
local HOVER_OPEN = 600
-- A drag near the top or bottom edge of the tree, within this many pixels, scrolls it.
local SCROLL_EDGE = 24
-- Typed letters build one search until the keys rest this many milliseconds.
local FIND_RESET = 1000
-- A second click on a folder this soon after the first is a double-click, which leaves it open.
local DOUBLE_CLICK = 400
-- The most file changes Undo remembers.
local UNDO_LIMIT = 50

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
---@class CodeExplorer.Entry
---@field name string
---@field path string From the project folder, with `/`.
---@field dir boolean
---@field ignored? boolean `.gitignore` leaves it out.

---A row drawn in the tree.
---@class CodeExplorer.Row
---@field row Proteus.El
---@field entry CodeExplorer.Entry
---@field index integer Its place from the top, starting at 1.

---A name being typed into the tree: a rename, a copy, or a new file or folder inside `dir`.
---@class CodeExplorer.Edit
---@field kind 'rename'|'copy'|'file'|'folder'
---@field dir string The folder the typed name is relative to.
---@field entry? CodeExplorer.Entry The item being renamed or copied.
---@field value string The text the box starts with.
---@field input? Proteus.El
---@field error? Proteus.El
---@field done? boolean

---One item a drop or a paste moves.
---@class CodeExplorer.Move
---@field from string
---@field to string

---Items being dragged onto another folder.
---@class CodeExplorer.Drag
---@field entries CodeExplorer.Entry[]
---@field ghost Proteus.El
---@field dir? string The folder under the pointer. '' is the project folder.
---@field moves? CodeExplorer.Move[] What moves where if the items are let go now.
---@field y? number
---@field top number
---@field bottom number
---@field cancel_open? fun()
---@field stop fun()

---A change to the folder that Undo takes back: items that moved, items made, or items moved
---to the trash.
---@class CodeExplorer.Step
---@field kind 'move'|'made'|'trash'
---@field moves? CodeExplorer.Move[] For `move`.
---@field paths? string[] For `made` and `trash`.
---@field what string What the change was, for the menu, such as `'Rename'`.

---Items copied or cut with Ctrl+C or Ctrl+X, waiting for Ctrl+V.
---@class CodeExplorer.Clip
---@field cut boolean
---@field paths string[]

---A key the tree answers while it has the focus.
---@class CodeExplorer.Shortcut
---@field combo string
---@field id string
---@field title string
---@field run fun()

---The icon a plugin draws when no icon pack has one.
---@param entry CodeExplorer.Entry
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

---The chosen icon pack's icon for an entry, or the builtin one.
---@param icons Proteus.Icons
---@param entry CodeExplorer.Entry
---@param open boolean
---@return string|Proteus.FileIcon
local function icon_for (icons, entry, open)
  local found ---@type Proteus.FileIcon?
  if entry.dir then
    found = icons.folder (entry.path, open)
  else
    found = icons.file (entry.path)
  end
  return found or builtin_icon (entry, open)
end

---@type Proteus.Plugin
return {
  name = 'Project Explorer',
  description = 'A file tree of the folder open in the Code Editor, read from disk as folders open.',
  version = '1.2.0',
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
  },
  conflicts = { 'proteus.ws.explorer' },
  -- `files` to read and change the folder on disk, and for the `project` and `editor` services.
  permissions = { 'files' },
  requires = { proteus = '>=0.3.0', features = { 'permissions' } },
  activate = function (app)
    -- Full paths on disk need `files`, as the `project` service does.
    app.protect_event ('code:disk_renamed', { needs = 'files' })
    app.protect_event ('code:search_folder', { needs = 'files' })
    app.protect_event ('code:open_terminal', { needs = 'files' })
    local ui = app.use ('ui')
    local views = app.use ('views')
    local icons = app.use ('icons')
    local project = app.use ('project')
    local settings = app.use ('settings')
    ui.css (CSS)

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

    -- With no folder open there is no tree. The Welcome page opens a folder instead.
    if not root then
      return
    end

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

    ---The full path of a path in the tree.
    ---@param rel string
    ---@return string
    local function abs (rel)
      return disk.join (root or '', rel)
    end

    ---The path in the tree of a full path, or nil outside the folder.
    ---@param full string?
    ---@return string?
    local function rel_of (full)
      if not root or type (full) ~= 'string' then
        return nil
      end
      return disk.relative (root, full, app.os)
    end

    local store_key = 'expanded:' .. (root or '')
    ---@type table<string, boolean>
    local expanded = app.store.get (store_key, {})
    if type (expanded) ~= 'table' then
      expanded = {}
    end
    ---@type string?
    local active_path = nil
    -- The selection. Keys act on the cursor row, and Shift stretches the selection from the anchor.
    local picked = {} ---@type table<string, boolean>
    local cursor = nil ---@type string?
    local anchor = nil ---@type string?
    local edit = nil ---@type CodeExplorer.Edit?
    local drag = nil ---@type CodeExplorer.Drag?
    -- The folder files dragged in from the system would land in, while they are over the tree.
    local os_drop = nil ---@type string?
    local clip = nil ---@type CodeExplorer.Clip?
    -- A row to scroll to once it is drawn, such as a file just opened in a folder not yet read.
    local reveal_next = nil ---@type string?
    local unsaved = {} ---@type table<string, boolean>
    local git_kind = {} ---@type table<string, string> Path to what Git says about it.
    local git_inside = {} ---@type table<string, boolean> Folders with changes inside.
    local find_text = ''
    -- Changes Undo takes back, the last one at the end.
    local undo_steps = {} ---@type CodeExplorer.Step[]
    local undoing = false
    local tree = ui.div ({ class = 'explorer-tree', attrs = { tabindex = 0 } })
    local find_label = ui.div ({ class = 'tree-find' })
    find_label:show (false)
    local rows = {} ---@type CodeExplorer.Row[]
    local row_at = {} ---@type table<string, CodeExplorer.Row>

    -- Folders as read from disk, by their path in the tree. A folder not read yet has none.
    local listing = {} ---@type table<string, CodeExplorer.Entry[]>
    local failed = {} ---@type table<string, string>
    local loading = {} ---@type table<string, boolean>
    local again = {} ---@type table<string, boolean>
    local waiters = {} ---@type table<string, fun()[]>

    ---@return Proteus.Notify?
    local function notify ()
      return app.try_use ('notify')
    end
    ---@return Proteus.Picker?
    local function picker ()
      return app.try_use ('picker')
    end
    ---@param err any
    ---@return string
    local function first_line (err)
      return tostring (err):match ('^[^\n]*') or ''
    end
    ---@param err any
    local function report (err)
      local n = notify ()
      if n then
        n.error (first_line (err))
      else
        app.error (err)
      end
    end

    ---The path in the tree of the file in the tab in front, if it is in the folder.
    ---@return string?
    local function active_tab_path ()
      local tabs = app.try_use ('tabs')
      local tab = tabs and tabs.active ()
      local path = rel_of (tab and tab.data and tab.data.path or nil)
      return path ~= '' and path or nil
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

    ---Tells the editor, and any plugin listening, that something in the tree moved, so open
    ---files follow it.
    ---@param from string In the tree.
    ---@param to string In the tree.
    local function moved_on_disk (from, to)
      local editor = app.try_use ('editor')
      if editor then
        editor.disk_renamed (abs (from), abs (to))
      end
      app.emit ('code:disk_renamed', abs (from), abs (to))
    end

    ---Remembers a change for Undo.
    ---@param step CodeExplorer.Step
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

    ---@type fun()
    local render

    local render_pending = false
    local function render_soon ()
      if render_pending then
        return
      end
      render_pending = true
      app.timer.after (0, function ()
        render_pending = false
        render ()
      end)
    end

    local function save_expanded ()
      app.store.set (store_key, expanded)
    end

    ---Opens every folder down to `path`, and `path` itself.
    ---@param path string
    local function expand_to (path)
      local d = path
      while d ~= '' do
        expanded[d] = true
        d = paths.parent (d)
      end
      save_expanded ()
    end

    ---True while the tree itself has the keyboard focus.
    ---@return boolean
    local function focused ()
      return app.dom.active () == tree.id
    end

    ---@param path string?
    ---@param cls string
    ---@param on boolean
    local function mark (path, cls, on)
      local r = path and row_at[path]
      if r then
        r.row:class (cls, on)
      end
    end

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
        render_soon ()
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
          render_soon ()
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
        render_soon ()
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

    -- Selection --------------------------------------------------------------------------

    ---Changes the selection without drawing the tree again.
    ---@param list string[]
    ---@param at string? The row the keys act on next.
    ---@param reveal? boolean Scrolls that row into view.
    local function select_paths (list, at, reveal)
      local now = {} ---@type table<string, boolean>
      for _, p in ipairs (list) do
        now[p] = true
      end
      for p in pairs (picked) do
        if not now[p] then
          mark (p, 'selected', false)
        end
      end
      for p in pairs (now) do
        if not picked[p] then
          mark (p, 'selected', true)
        end
      end
      picked = now
      if cursor ~= at then
        mark (cursor, 'cursor', false)
        cursor = at
        mark (at, 'cursor', true)
      end
      local r = reveal and at and row_at[at]
      if r then
        r.row:scroll_into_view ()
      end
    end

    ---Selects one row, or nothing.
    ---@param path string?
    ---@param reveal? boolean
    local function select_one (path, reveal)
      select_paths (path and { path } or {}, path, reveal)
      anchor = path
    end

    ---Selects every row from the anchor to `path`.
    ---@param path string
    local function select_range (path)
      local from = anchor and row_at[anchor]
      local to = row_at[path]
      if not (from and to) then
        select_one (path, true)
        return
      end
      local list = {} ---@type string[]
      for i = math.min (from.index, to.index), math.max (from.index, to.index) do
        list[#list + 1] = rows[i].entry.path
      end
      select_paths (list, path, true)
    end

    ---Adds a row to the selection, or takes it out.
    ---@param path string
    local function toggle_pick (path)
      local list = {} ---@type string[]
      for p in pairs (picked) do
        if p ~= path then
          list[#list + 1] = p
        end
      end
      if not picked[path] then
        list[#list + 1] = path
      end
      select_paths (list, path)
      anchor = path
    end

    local function select_all ()
      local list = {} ---@type string[]
      for _, r in ipairs (rows) do
        list[#list + 1] = r.entry.path
      end
      select_paths (list, cursor or list[1])
    end

    ---@return integer
    local function picked_count ()
      local n = 0
      for _ in pairs (picked) do
        n = n + 1
      end
      return n
    end

    ---The selected items, top to bottom, without any that sit inside another selected folder.
    ---@return CodeExplorer.Entry[]
    local function chosen ()
      local list = {} ---@type string[]
      for _, r in ipairs (rows) do
        if picked[r.entry.path] then
          list[#list + 1] = r.entry.path
        end
      end
      local out = {} ---@type CodeExplorer.Entry[]
      for _, p in ipairs (paths.outermost (list)) do
        out[#out + 1] = row_at[p].entry
      end
      return out
    end

    ---Keeps open folders, the selection, unsaved marks and the clipboard after `from` moves
    ---to `to`. What was read inside `from` is read again at its new place.
    ---@param from string
    ---@param to string
    local function follow_move (from, to)
      ---@param p string?
      ---@return string?
      local function moved (p)
        if p and paths.inside (p, from) then
          return to .. p:sub (#from + 1)
        end
        return p
      end
      expanded = paths.rekey (expanded, from, to)
      save_expanded ()
      picked = paths.rekey (picked, from, to)
      unsaved = paths.rekey (unsaved, from, to)
      cursor, anchor, active_path =
        moved (cursor), moved (anchor), moved (active_path)
      if clip then
        for i, p in ipairs (clip.paths) do
          clip.paths[i] = moved (p) or p
        end
      end
      for d in pairs (listing) do
        if paths.inside (d, from) then
          listing[d] = nil
        end
      end
    end

    ---The folder new and pasted items go into: the folder at the cursor, or the folder of the
    ---file at the cursor.
    ---@return string
    local function target_dir ()
      local r = cursor and row_at[cursor]
      if r then
        return r.entry.dir and r.entry.path or paths.parent (r.entry.path)
      end
      return ''
    end

    ---Why nothing can be made at `path`, or nil when it can, as far as the folders read so far
    ---tell. The disk has the last word when the change is made.
    ---@param path string
    ---@param from? string The path being renamed. A change of case alone is allowed.
    ---@return string? problem
    local function check_path (path, from)
      if known (path) and not (from and from:lower () == path:lower ()) then
        return (path:match ('[^/]+$') or path) .. ' already exists here'
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

    -- Typing a name ----------------------------------------------------------------------

    ---Ends the typing, and draws the tree with any change that came in meanwhile.
    local function end_edit ()
      local e = edit
      if not e or e.done then
        return
      end
      e.done = true
      edit = nil
      render ()
    end

    ---@param e CodeExplorer.Edit
    ---@param problem string?
    local function show_problem (e, problem)
      if e.input then
        e.input:class ('invalid', problem ~= nil)
      end
      if e.error then
        e.error:text (problem or ''):show (problem ~= nil)
      end
    end

    ---The path the typed name points at, or nil and the reason it cannot be used.
    ---@param e CodeExplorer.Edit
    ---@return string? path
    ---@return string? problem
    local function typed_path (e)
      local path, problem =
        paths.resolve (e.dir, e.input and e.input:value () or '')
      if not path then
        return nil, problem
      end
      local from = e.kind == 'rename' and e.entry and e.entry.path or nil
      if path == from then
        return path
      end
      problem = check_path (path, from)
      if problem then
        return nil, problem
      end
      return path
    end

    ---Carries out the typed edit on disk and ends the typing. Returns the reason when the
    ---name cannot be used, and leaves the typing open. The tree shows the result once the
    ---disk has it.
    ---@param e CodeExplorer.Edit
    ---@param by_key boolean True for Enter, which also moves the selection to the result.
    ---@return string? problem
    local function commit (e, by_key)
      local path, problem = typed_path (e)
      if not path then
        return problem
      end
      local entry = e.entry
      local kind = e.kind
      end_edit ()
      ---@param err string?
      local function finish (err)
        if err then
          report (err)
          return
        end
        if kind == 'rename' and entry then
          record ({
            kind = 'move',
            moves = { { from = entry.path, to = path } },
            what = 'Rename',
          })
        else
          local made = { copy = 'Duplicate', folder = 'New Folder' }
          record ({
            kind = 'made',
            paths = { path },
            what = made[kind] or 'New File',
          })
        end
        if kind == 'folder' then
          expand_to (path)
        elseif paths.parent (path) ~= '' then
          expand_to (paths.parent (path))
        end
        local dirs = { paths.parent (path) }
        if entry then
          dirs[#dirs + 1] = paths.parent (entry.path)
        end
        refresh (dirs, function ()
          if by_key then
            select_one (path)
          end
          reveal_next = path
          if kind == 'file' then
            open_file (path)
          elseif by_key then
            tree:focus ()
          end
        end)
      end
      if kind == 'rename' and entry then
        if path == entry.path then
          return nil
        end
        local from = entry.path
        app.fs.move_path (abs (from), abs (path), function (_, err)
          if not err then
            follow_move (from, path)
            moved_on_disk (from, path)
          end
          finish (err)
        end)
      elseif kind == 'copy' and entry then
        app.fs.copy_path (abs (entry.path), abs (path), function (_, err)
          finish (err)
        end)
      elseif kind == 'folder' then
        create ('folder', path, finish)
      else
        create ('file', path, finish)
      end
      return nil
    end

    ---The text box for the edit in progress, with the message that shows under it.
    ---@param e CodeExplorer.Edit
    ---@return Proteus.Child[]
    local function text_box (e)
      local input = ui.h ('input', {
        class = 'tree-input',
        value = e.value,
        spellcheck = false,
        attrs = { ['aria-label'] = e.kind == 'rename' and 'New name' or 'Name' },
      })
      local err = ui.div ({ class = 'tree-error' })
      err:show (false)
      e.input, e.error = input, err
      input:on ('keydown', function (ev)
        if ev.composing then
          return nil
        end
        if ev.key == 'Enter' then
          local problem = commit (e, true)
          if problem then
            show_problem (e, problem)
          end
          return 'stop'
        end
        if ev.key == 'Escape' then
          end_edit ()
          tree:focus ()
          return 'stop'
        end
        return nil
      end)
      input:on ('input', function ()
        if (input:value () or ''):match ('^%s*$') then
          show_problem (e, nil)
        else
          local _, problem = typed_path (e)
          show_problem (e, problem)
        end
      end)
      -- Clicking away keeps a name that works and drops one that does not.
      input:on ('blur', function ()
        if e.done then
          return
        end
        if (input:value () or ''):match ('^%s*$') or commit (e, false) then
          end_edit ()
        end
      end)
      return { input, err }
    end

    ---@param kind 'file'|'folder'
    ---@param dir string
    local function start_create (kind, dir)
      end_edit ()
      if dir ~= '' then
        expand_to (dir)
      end
      edit = { kind = kind, dir = dir, value = '' }
      render ()
    end

    ---@param entry CodeExplorer.Entry
    local function start_rename (entry)
      end_edit ()
      select_one (entry.path)
      edit = {
        kind = 'rename',
        dir = paths.parent (entry.path),
        entry = entry,
        value = entry.name,
      }
      render ()
    end

    ---Opens a text box for a copy of `entry` beside it.
    ---@param entry CodeExplorer.Entry
    local function start_copy (entry)
      end_edit ()
      local dir = paths.parent (entry.path)
      if dir ~= '' then
        expand_to (dir)
      end
      local value = paths.copy_name (entry.name, entry.dir, function (name)
        return known (paths.join (dir, name)) ~= nil
      end)
      edit = { kind = 'copy', dir = dir, entry = entry, value = value }
      render ()
    end

    local function rename_cursor ()
      local r = cursor and row_at[cursor]
      if r then
        start_rename (r.entry)
      end
    end

    ---@return string
    local function bin_name ()
      return app.os == 'windows' and 'the Recycle Bin' or 'the Trash'
    end

    ---Moves items to the Recycle Bin, after asking. An item the bin refuses, such as one on a
    ---network drive, can be deleted for good instead, after asking again.
    ---@param list CodeExplorer.Entry[]
    local function delete (list)
      local p = picker ()
      if #list == 0 or not p then
        return
      end
      local what = #list == 1 and list[1].name or (#list .. ' items')
      p.confirm ({
        message = 'Move ' .. what .. ' to ' .. bin_name () .. '?',
        yes = 'Move to ' .. (app.os == 'windows' and 'Recycle Bin' or 'Trash'),
        on_yes = function ()
          -- The selection moves to the row after the last one deleted, so Delete can be
          -- pressed again.
          local last = row_at[list[#list].path]
          local first = row_at[list[1].path]
          local next_row = nil ---@type CodeExplorer.Row?
          for i = (last and last.index or #rows) + 1, #rows do
            local gone = false
            for _, e in ipairs (list) do
              gone = gone or paths.inside (rows[i].entry.path, e.path)
            end
            if not gone then
              next_row = rows[i]
              break
            end
          end
          next_row = next_row or (first and rows[first.index - 1])
          -- What went to the trash, which Undo brings back.
          local trashed = {} ---@type string[]
          ---@type { left: integer }
          local trash = { left = 0 }
          select_one (next_row and next_row.entry.path or nil)
          for _, e in ipairs (list) do
            local entry = e
            trash.left = trash.left + 1
            app.fs.trash_path (abs (entry.path), function (_, err)
              if not err then
                trashed[#trashed + 1] = entry.path
                trash.left = trash.left - 1
                if trash.left == 0 then
                  record ({ kind = 'trash', paths = trashed, what = 'Delete' })
                end
                refresh ({ paths.parent (entry.path) })
                return
              end
              trash.left = trash.left - 1
              if trash.left == 0 then
                record ({ kind = 'trash', paths = trashed, what = 'Delete' })
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

    local function delete_chosen ()
      delete (chosen ())
    end

    ---Opens a file, or opens or closes a folder.
    ---@param entry CodeExplorer.Entry
    ---@param keep_focus boolean Leaves the keyboard focus in the tree.
    local function activate_row (entry, keep_focus)
      if entry.dir then
        expanded[entry.path] = not expanded[entry.path] or nil
        save_expanded ()
        render ()
      else
        open_file (entry.path, keep_focus and { keep_focus = true } or nil)
      end
    end

    -- Copy, cut and paste ----------------------------------------------------------------

    local function clear_clip ()
      local c = clip
      if c and c.cut then
        for _, p in ipairs (c.paths) do
          mark (p, 'cut', false)
        end
      end
      clip = nil
    end

    ---@param cut boolean
    local function set_clip (cut)
      local list = chosen ()
      if #list == 0 then
        return
      end
      clear_clip ()
      local list_paths = {} ---@type string[]
      for _, e in ipairs (list) do
        list_paths[#list_paths + 1] = e.path
        if cut then
          mark (e.path, 'cut', true)
        end
      end
      clip = { cut = cut, paths = list_paths }
    end

    ---Copies or moves the clipboard's items into `dir`. A copy that meets a name already
    ---there, or one an earlier item of this paste takes, gets a free name instead. Every item
    ---is worked out first, then they all go at once, and the tree is read again when the last
    ---one is done.
    ---@param dir string
    local function paste (dir)
      local c = clip
      if not c then
        return
      end
      local moves = {} ---@type CodeExplorer.Move[]
      -- The paths this paste has given out, compared the way the system compares names.
      local claimed = {} ---@type table<string, boolean>
      ---@param path string
      ---@return boolean
      local function taken (path)
        return known (path) ~= nil
          or claimed[fold and path:lower () or path] == true
      end
      for _, from in ipairs (c.paths) do
        local name = from:match ('[^/]+$') or from ---@type string
        local to, problem = nil, nil ---@type string?, string?
        if c.cut then
          to, problem = paths.drop_path (from, dir)
        else
          local entry = known (from)
          to = paths.join (dir, name)
          if taken (to) then
            to = paths.join (
              dir,
              paths.copy_name (name, entry ~= nil and entry.dir, function (n)
                return taken (paths.join (dir, n))
              end)
            )
          end
        end
        problem = problem or (to and check_path (to))
        if problem then
          report (problem)
        elseif to then
          claimed[fold and to:lower () or to] = true
          moves[#moves + 1] = { from = from, to = to }
        end
      end
      local cut = c.cut
      if cut then
        clear_clip ()
      end
      if #moves == 0 then
        return
      end
      local done = {} ---@type string[]
      local done_moves = {} ---@type CodeExplorer.Move[]
      local left = #moves
      local function finish ()
        if cut then
          record ({ kind = 'move', moves = done_moves, what = 'Move' })
        else
          record ({ kind = 'made', paths = done, what = 'Paste' })
        end
        if dir ~= '' then
          expand_to (dir)
        end
        local dirs = { dir }
        for _, m in ipairs (moves) do
          dirs[#dirs + 1] = paths.parent (m.from)
        end
        refresh (dirs, function ()
          if #done > 0 then
            select_paths (done, done[1])
            anchor = done[1]
            reveal_next = done[1]
          end
        end)
      end
      for _, m in ipairs (moves) do
        local move = m
        ---@param _ any
        ---@param err string?
        local function after (_, err)
          if err then
            report (err)
          else
            if cut then
              follow_move (move.from, move.to)
              moved_on_disk (move.from, move.to)
            end
            done[#done + 1] = move.to
            done_moves[#done_moves + 1] = move
          end
          left = left - 1
          if left == 0 then
            finish ()
          end
        end
        if cut then
          app.fs.move_path (abs (move.from), abs (move.to), after)
        else
          app.fs.copy_path (abs (move.from), abs (move.to), after)
        end
      end
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
              expand_to (paths.parent (path))
            end
          end
          left = left - 1
          if left > 0 then
            return
          end
          undoing = false
          refresh (dirs, function ()
            if #back > 0 then
              select_paths (back, back[1])
              anchor = back[1]
              reveal_next = back[1]
            end
          end)
        end
        if step.kind == 'move' then
          for _, m in
            ipairs (list --[[@as CodeExplorer.Move[] ]])
          do
            local move = m
            dirs[#dirs + 1] = paths.parent (move.from)
            dirs[#dirs + 1] = paths.parent (move.to)
            app.fs.move_path (abs (move.to), abs (move.from), function (_, err)
              if not err then
                follow_move (move.to, move.from)
                moved_on_disk (move.to, move.from)
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

    ---The label of the menu item that undoes the last change, or nil with nothing to undo.
    ---@return string?
    local function undo_label ()
      local step = undo_steps[#undo_steps]
      return step and ('Undo ' .. step.what) or nil
    end

    -- Type to find -----------------------------------------------------------------------

    local stop_find = nil ---@type fun()?

    local function end_find ()
      find_text = ''
      find_label:show (false)
      if stop_find then
        stop_find ()
        stop_find = nil
      end
    end

    ---Looks for the typed text, from the cursor row on.
    ---@param next_one boolean Starts past the cursor row, so the same letter again moves on.
    local function run_find (next_one)
      if stop_find then
        stop_find ()
      end
      stop_find = app.timer.after (FIND_RESET, end_find)
      local names = {} ---@type string[]
      for i, r in ipairs (rows) do
        names[i] = r.entry.name
      end
      local here = cursor and row_at[cursor]
      local start = here and (here.index + (next_one and 1 or 0)) or 1
      local i = paths.find (names, start, find_text)
      find_label:text ('Find: ' .. find_text)
      find_label:class ('none', i == nil)
      find_label:show (true)
      if i then
        select_one (rows[i].entry.path, true)
      end
    end

    ---@param ch string
    local function type_find (ch)
      find_text = find_text .. ch
      run_find (#find_text == 1)
    end

    local function find_back ()
      if find_text == '' then
        return
      end
      find_text = find_text:gsub ('[^\128-\191][\128-\191]*$', '')
      if find_text == '' then
        end_find ()
      else
        run_find (false)
      end
    end

    -- The right-click menu ---------------------------------------------------------------

    ---@param list CodeExplorer.Entry[]
    ---@param full boolean
    local function copy_paths (list, full)
      local lines = {} ---@type string[]
      for _, e in ipairs (list) do
        lines[#lines + 1] = full and disk.native (abs (e.path), app.os)
          or e.path
      end
      app.system.clipboard (table.concat (lines, '\n'))
    end

    ---@return string
    local function reveal_label ()
      if app.os == 'windows' then
        return 'Reveal in File Explorer'
      elseif app.os == 'macos' then
        return 'Reveal in Finder'
      end
      return 'Reveal in File Manager'
    end

    local function collapse_all ()
      expanded = {}
      save_expanded ()
      render ()
    end

    ---The right-click menu for the selection, or for the empty space below the rows.
    ---@param entry CodeExplorer.Entry?
    ---@return Proteus.MenuItem[]
    local function items_for (entry)
      ---@type Proteus.MenuItem[]
      local items = {}
      ---@param item Proteus.MenuItem
      local function add (item)
        items[#items + 1] = item
      end
      local sep = { separator = true } ---@type Proteus.MenuItem
      local list = chosen ()

      if entry and #list > 1 then
        add ({
          label = 'Cut',
          icon = 'scissors',
          key = 'Ctrl+X',
          run = function ()
            set_clip (true)
          end,
        })
        add ({
          label = 'Copy',
          icon = 'copy',
          key = 'Ctrl+C',
          run = function ()
            set_clip (false)
          end,
        })
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
        add (sep)
      end
      add ({
        label = 'New File…',
        icon = 'file-plus',
        run = function ()
          start_create ('file', dir)
        end,
      })
      add ({
        label = 'New Folder…',
        icon = 'folder-plus',
        run = function ()
          start_create ('folder', dir)
        end,
      })
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
      local terminal = app.kernel.plugin ('proteus.terminal')
      if
        terminal
        and terminal.status == 'active'
        and app.platform ~= 'browser'
        and (not entry or entry.dir)
      then
        add ({
          label = 'Open in Terminal',
          icon = 'square-terminal',
          run = function ()
            app.emit ('code:open_terminal', abs (dir))
          end,
        })
      end
      add (sep)
      if entry then
        add ({
          label = 'Cut',
          icon = 'scissors',
          key = 'Ctrl+X',
          run = function ()
            set_clip (true)
          end,
        })
        add ({
          label = 'Copy',
          icon = 'copy',
          key = 'Ctrl+C',
          run = function ()
            set_clip (false)
          end,
        })
      end
      add ({
        label = 'Paste',
        icon = 'clipboard-paste',
        key = 'Ctrl+V',
        disabled = clip == nil,
        run = function ()
          paste (dir)
        end,
      })
      if entry then
        add ({
          label = 'Duplicate…',
          icon = 'copy-plus',
          run = function ()
            start_copy (entry)
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
          label = reveal_label (),
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
            start_rename (entry)
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
        local undo_title = undo_label ()
        if undo_title then
          add ({
            label = undo_title,
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
          run = collapse_all,
        })
        add ({
          label = reveal_label (),
          icon = 'folder-search',
          run = function ()
            app.system.open_path (
              disk.native (root or '', app.os),
              function (_, err)
                if err then
                  report (err)
                end
              end
            )
          end,
        })
      end
      return items
    end

    local menus = app.try_use ('menus')
    if menus then
      local m = menus
      m.attach (tree, function (ev)
        if ev.editable then
          return m.edit_items (ev)
        end
        local r = ev.item and row_at[ev.item]
        if r and not picked[r.entry.path] then
          select_one (r.entry.path)
        end
        return items_for (r and r.entry or nil)
      end)
    end

    -- Drawing ----------------------------------------------------------------------------

    local marked = false

    ---Marks the folder a drag would drop into, with everything drawn inside it.
    local function mark_drop ()
      local d = drag
      local dir = d and d.moves and d.dir or os_drop
      tree:class ('drop-root', dir == '')
      if not dir and not marked then
        return
      end
      marked = false
      for _, r in ipairs (rows) do
        local on = dir ~= nil and dir ~= '' and paths.inside (r.entry.path, dir)
        r.row:class ('drop', on)
        marked = marked or on
      end
    end

    local cut_now = {} ---@type table<string, boolean>

    ---@param entry CodeExplorer.Entry
    ---@param depth integer
    ---@return Proteus.El
    local function row_for (entry, depth)
      local e = edit
      local p = entry.path
      local renaming = e ~= nil
        and e.kind == 'rename'
        and e.entry ~= nil
        and e.entry.path == p
      local open = entry.dir and expanded[p] == true
      local kind = git_kind[p]
      local badge = kind and GIT_LETTER[kind] or ''
      if badge == '' and entry.dir and git_inside[p] then
        badge = '•'
      end
      ---@type string[]
      local classes = { 'tree-row' }
      ---@param on any
      ---@param name string
      local function add_class (on, name)
        if on then
          classes[#classes + 1] = name
        end
      end
      add_class (entry.name:sub (1, 1) == '.', 'dotfile')
      add_class (entry.ignored, 'ignored')
      add_class (picked[p], 'selected')
      add_class (p == cursor, 'cursor')
      add_class (renaming, 'editing')
      add_class (cut_now[p], 'cut')
      add_class (unsaved[p], 'unsaved')
      add_class (kind, 'git-' .. (kind or ''))
      add_class (entry.dir and git_inside[p], 'git-inside')
      return ui.div ({
        class = classes,
        style = { ['--depth'] = depth },
        title = p,
        -- Clicks on the row being renamed stay with its text box.
        ['data-item'] = not renaming and p or nil,
        ui.span ({
          class = 'tree-twisty',
          entry.dir
              and ui.icon (open and 'chevron-down' or 'chevron-right', 14)
            or nil,
        }),
        ui.icon (icon_for (icons, entry, open), 15),
        renaming and e and text_box (e)
          or ui.span ({ class = 'tree-name', entry.name }),
        ui.span ({ class = 'tree-mark', title = 'Unsaved changes' }),
        ui.span ({
          class = 'tree-badge',
          title = kind or (badge ~= '' and 'Changes inside' or ''),
          badge,
        }),
      })
    end

    ---The row that holds the text box for a new file, folder or copy.
    ---@param e CodeExplorer.Edit
    ---@param depth integer
    ---@return Proteus.El
    local function new_row (e, depth)
      ---@type string|Proteus.FileIcon
      local icon = e.kind == 'folder' and 'folder' or 'file'
      if e.kind == 'copy' and e.entry then
        icon = icon_for (icons, e.entry, false)
      end
      return ui.div ({
        class = 'tree-row editing',
        style = { ['--depth'] = depth },
        ui.span ({ class = 'tree-twisty' }),
        ui.icon (icon, 15),
        text_box (e),
      })
    end

    render = function ()
      -- Drawing the tree while a name is typed would throw the text box away, so it waits
      -- until the typing ends, which draws the tree again.
      if edit and edit.input then
        return
      end
      if not root then
        return
      end
      local e = edit
      local list = {} ---@type Proteus.El[]
      rows, row_at = {}, {}
      cut_now = {}
      if clip and clip.cut then
        for _, p in ipairs (clip.paths) do
          cut_now[p] = true
        end
      end
      ---@param dir string
      ---@param depth integer
      local function walk (dir, depth)
        local entries = listing[dir]
        if not entries then
          load (dir)
          return
        end
        if failed[dir] then
          list[#list + 1] = ui.div ({
            class = 'tree-note',
            style = { ['--depth'] = depth },
            failed[dir],
          })
        end
        -- A new folder is typed at the top of its folder, and a new file below the folders.
        ---@type CodeExplorer.Edit?
        local creating = e and e.kind ~= 'rename' and e.dir == dir and e or nil
        local goes_first = creating ~= nil
          and (
            creating.kind == 'folder'
            or (
              creating.kind == 'copy'
              and creating.entry ~= nil
              and creating.entry.dir
            )
          )
        for _, entry in ipairs (entries) do
          if creating and (goes_first or not entry.dir) then
            list[#list + 1] = new_row (creating, depth)
            creating = nil
          end
          local row = row_for (entry, depth)
          list[#list + 1] = row
          local r = { row = row, entry = entry, index = #rows + 1 }
          rows[r.index] = r
          row_at[entry.path] = r
          if entry.dir and expanded[entry.path] then
            walk (entry.path, depth + 1)
          end
        end
        if creating then
          list[#list + 1] = new_row (creating, depth)
        end
      end
      walk ('', 0)
      -- Rows no longer drawn leave the selection, once their folders have been read.
      for p in pairs (picked) do
        if not row_at[p] and listing[paths.parent (p)] then
          picked[p] = nil
        end
      end
      if cursor and not row_at[cursor] and listing[paths.parent (cursor)] then
        cursor = nil
      end
      if anchor and not row_at[anchor] and listing[paths.parent (anchor)] then
        anchor = nil
      end
      if #list == 0 then
        list[1] = ui.div ({
          class = 'tree-empty',
          listing[''] and 'This folder is empty.' or 'Reading the folder…',
        })
      end
      tree:set_children (list)
      mark_drop ()
      local input = e and e.input
      if e and not input then
        -- The item being renamed is gone, so there is nothing left to type into.
        edit = nil
      elseif e and input then
        input:focus ()
        local stem = 0
        if e.entry and e.kind ~= 'file' and e.kind ~= 'folder' then
          stem = paths.stem_units (e.value, e.entry.dir)
        end
        input:call ('setSelectionRange', 0, stem)
        input:scroll_into_view ()
      end
      local target = reveal_next and row_at[reveal_next]
      if target then
        reveal_next = nil
        target.row:scroll_into_view ()
      end
    end

    -- Dragging to move -------------------------------------------------------------------

    ---Ends the drag. With `drop`, the items move to the folder under the pointer.
    ---@param drop boolean
    local function finish_drag (drop)
      local d = drag
      if not d then
        return
      end
      drag = nil
      d.stop ()
      if d.cancel_open then
        d.cancel_open ()
      end
      d.ghost:show (false)
      tree:class ('dragging', false)
      mark_drop ()
      local moves = d.moves
      if not (drop and moves) then
        return
      end
      local done = {} ---@type string[]
      local moved = {} ---@type CodeExplorer.Move[]
      local dirs = { d.dir or '' }
      local pending = #moves
      for _, m in ipairs (moves) do
        local move = m
        dirs[#dirs + 1] = paths.parent (move.from)
        app.fs.move_path (abs (move.from), abs (move.to), function (_, err)
          pending = pending - 1
          if err then
            report (err)
          else
            follow_move (move.from, move.to)
            moved_on_disk (move.from, move.to)
            done[#done + 1] = move.to
            moved[#moved + 1] = move
          end
          if pending == 0 then
            record ({ kind = 'move', moves = moved, what = 'Move' })
            if d.dir and d.dir ~= '' then
              expand_to (d.dir)
            end
            refresh (dirs, function ()
              if #done > 0 then
                select_paths (done, done[1])
                anchor = done[1]
              end
            end)
          end
        end)
      end
    end

    ---Follows the pointer during a drag, and works out where a drop would land.
    ---@param ev Proteus.DomEvent
    local function drag_move (ev)
      local d = drag
      if not d then
        return
      end
      local x, y = ev.x or 0, ev.y or 0
      d.y = y
      d.ghost:style ({ left = (x + 14) .. 'px', top = (y + 10) .. 'px' })
      local dir = nil ---@type string?
      local over = nil ---@type CodeExplorer.Row?
      if ev.target and app.dom.contains (tree.id, ev.target) then
        over = ev.item and row_at[ev.item] or nil
        if over then
          dir = over.entry.dir and over.entry.path
            or paths.parent (over.entry.path)
        else
          dir = ''
        end
      end
      if dir == d.dir then
        return
      end
      d.dir = dir
      if d.cancel_open then
        d.cancel_open ()
        d.cancel_open = nil
      end
      local moves, problem = nil, nil ---@type CodeExplorer.Move[]?, string?
      if dir then
        moves = {}
        for _, e in ipairs (d.entries) do
          local to, why = paths.drop_path (e.path, dir)
          why = why or (to and check_path (to)) or nil
          if why then
            moves, problem = nil, why
            break
          end
          if to then
            moves[#moves + 1] = { from = e.path, to = to }
          end
        end
        if moves and #moves == 0 then
          moves = nil
        end
      end
      d.moves = moves
      local what = #d.entries == 1 and d.entries[1].name
        or (#d.entries .. ' items')
      local where = dir == '' and (project.name () or 'the folder')
        or (dir or '')
      d.ghost:text (
        problem or (moves and ('Move ' .. what .. ' to ' .. where)) or what
      )
      d.ghost:class ('refused', problem ~= nil)
      mark_drop ()
      if over and over.entry.dir and not expanded[over.entry.path] then
        local folder = over.entry.path
        d.cancel_open = app.timer.after (HOVER_OPEN, function ()
          if drag == d and d.dir == folder then
            d.cancel_open = nil
            expanded[folder] = true
            save_expanded ()
            render ()
          end
        end)
      end
    end

    -- The label that follows the pointer during a drag. It floats over the whole window, so
    -- it sits on the window itself, made once and shown for each drag.
    local drag_ghost = nil ---@type Proteus.El?

    ---@param entries CodeExplorer.Entry[]
    local function start_drag (entries)
      local what = #entries == 1 and entries[1].name or (#entries .. ' items')
      local ghost = drag_ghost
      if not ghost then
        ghost = ui.mount (ui.div ({ class = 'tree-ghost' }))
        drag_ghost = ghost
      end
      ghost:text (what)
      ghost:class ('refused', false)
      ghost:show (true)
      tree:class ('dragging', true)
      local off_key = app.dom.on_global ('keydown', function (ev)
        if ev.key == 'Escape' then
          finish_drag (false)
          return 'stop'
        end
        return nil
      end, { capture = true })
      local off_blur = app.dom.on_global ('blur', function ()
        finish_drag (false)
      end)
      local stop_scroll = app.timer.every (16, function ()
        local d = drag
        local y = d and d.y
        if not (d and y) then
          return
        end
        local step = y < d.top + SCROLL_EDGE and -8
          or (y > d.bottom - SCROLL_EDGE and 8 or 0)
        if step ~= 0 then
          tree:set ('scrollTop', (tree:get ('scrollTop') or 0) + step)
        end
      end)
      local rect = tree:rect ()
      drag = {
        entries = entries,
        ghost = ghost,
        top = rect.top,
        bottom = rect.bottom,
        stop = function ()
          off_key ()
          off_blur ()
          stop_scroll ()
        end,
      }
    end

    local recent_toggle = nil ---@type string?

    ---Follows a press on a row. Letting go on the same row opens it and leaves the focus in
    ---the tree. Items that move far enough turn into a drag instead.
    ---@param entry CodeExplorer.Entry
    ---@param ev Proteus.DomEvent
    ---@param group CodeExplorer.Entry[] What a drag would carry.
    local function press_row (entry, ev, group)
      local sx, sy = ev.x or 0, ev.y or 0
      local off_move, off_up ---@type fun(), fun()
      off_move = app.dom.on_global ('mousemove', function (mv)
        if not drag then
          local dx, dy = (mv.x or 0) - sx, (mv.y or 0) - sy
          if dx * dx + dy * dy < DRAG_START * DRAG_START then
            return nil
          end
          start_drag (group)
        end
        drag_move (mv)
        return nil
      end)
      off_up = app.dom.on_global ('mouseup', function (up)
        off_move ()
        off_up ()
        if drag then
          finish_drag (true)
          return nil
        end
        if up.item ~= entry.path or not row_at[entry.path] then
          return nil
        end
        if #group > 1 then
          select_one (entry.path)
        end
        if entry.dir and recent_toggle == entry.path then
          return nil
        end
        activate_row (entry, true)
        if entry.dir then
          recent_toggle = entry.path
          app.timer.after (DOUBLE_CLICK, function ()
            if recent_toggle == entry.path then
              recent_toggle = nil
            end
          end)
        end
        return nil
      end)
    end

    tree:on ('mousedown', function (ev)
      if ev.button ~= 0 then
        return nil
      end
      local r = ev.item and row_at[ev.item]
      if not r then
        if not edit and not (ev.ctrl or ev.meta or ev.shift) then
          select_one (nil)
        end
        return nil
      end
      local path = r.entry.path ---@type string
      if ev.ctrl or ev.meta then
        toggle_pick (path)
        return nil
      end
      if ev.shift then
        select_range (path)
        return nil
      end
      local group = { r.entry }
      if picked[path] and picked_count () > 1 then
        -- A press on a row that is already selected keeps the others, so they can be dragged.
        group = chosen ()
        local list = {} ---@type string[]
        for p in pairs (picked) do
          list[#list + 1] = p
        end
        select_paths (list, path)
      else
        select_one (path)
      end
      press_row (r.entry, ev, group)
      return nil
    end)

    -- A double-click moves the focus into the editor.
    tree:on ('dblclick', function (ev)
      local r = ev.item and row_at[ev.item]
      if r and not r.entry.dir then
        open_file (r.entry.path)
      end
      return nil
    end)

    tree:on ('blur', function ()
      end_find ()
    end)

    -- Files dropped from the system -------------------------------------------------------

    local cancel_os_open = nil ---@type fun()?

    ---The folder a drop on a row lands in: the folder itself, or the folder of a file. Below
    ---the rows it is the project folder.
    ---@param item string?
    ---@return string dir
    ---@return CodeExplorer.Row? row
    local function drop_dir (item)
      local r = item and row_at[item] or nil
      if not r then
        return '', nil
      end
      return r.entry.dir and r.entry.path or paths.parent (r.entry.path), r
    end

    local function end_os_drag ()
      if cancel_os_open then
        cancel_os_open ()
        cancel_os_open = nil
      end
      if os_drop then
        os_drop = nil
        mark_drop ()
      end
    end

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
        ---@param path string
        ---@return boolean
        local function taken (path)
          return known (path) ~= nil
            or claimed[fold and path:lower () or path] == true
        end
        local made = {} ---@type string[]
        local pending = #found
        if pending == 0 then
          return
        end
        for _, f in ipairs (found) do
          local name = disk.name (f.from)
          local to = paths.join (dir, name)
          if taken (to) then
            to = paths.join (
              dir,
              paths.copy_name (name, f.dir, function (n)
                return taken (paths.join (dir, n))
              end)
            )
          end
          claimed[fold and to:lower () or to] = true
          local target = to
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
              expand_to (dir)
            end
            refresh ({ dir }, function ()
              if #made > 0 then
                select_paths (made, made[1])
                anchor = made[1]
                reveal_next = made[1]
              end
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

    tree:on ('filedragover', function (ev)
      if drag or edit then
        return nil
      end
      local dir, r = drop_dir (ev.item)
      if dir == os_drop then
        return true
      end
      end_os_drag ()
      os_drop = dir
      mark_drop ()
      -- A closed folder opens once the files rest on it, as in a drag inside the tree.
      if r and r.entry.dir and not expanded[r.entry.path] then
        local folder = r.entry.path
        cancel_os_open = app.timer.after (HOVER_OPEN, function ()
          cancel_os_open = nil
          if os_drop == folder then
            expanded[folder] = true
            save_expanded ()
            render ()
          end
        end)
      end
      return true
    end)
    tree:on ('filedragleave', function ()
      end_os_drag ()
      return nil
    end)
    tree:on ('filedrop', function (ev)
      end_os_drag ()
      local list = ev.paths
      if drag or edit or type (list) ~= 'table' or #list == 0 then
        return nil
      end
      drop_files (list, (drop_dir (ev.item)))
      return true
    end)

    -- Keys -------------------------------------------------------------------------------

    -- These keys are commands bound ahead of everything else, so while the tree has the
    -- focus they reach it rather than another plugin's shortcut.
    ---@type CodeExplorer.Shortcut[]
    local shortcuts = {
      { combo = 'f2', id = 'rename', title = 'Rename', run = rename_cursor },
      {
        combo = 'delete',
        id = 'delete',
        title = 'Delete',
        run = delete_chosen,
      },
      {
        combo = 'ctrl+c',
        id = 'copy',
        title = 'Copy',
        run = function ()
          set_clip (false)
        end,
      },
      {
        combo = 'ctrl+x',
        id = 'cut',
        title = 'Cut',
        run = function ()
          set_clip (true)
        end,
      },
      {
        combo = 'ctrl+v',
        id = 'paste',
        title = 'Paste',
        run = function ()
          paste (target_dir ())
        end,
      },
      {
        combo = 'ctrl+a',
        id = 'select_all',
        title = 'Select All',
        run = select_all,
      },
      {
        combo = 'ctrl+z',
        id = 'undo',
        title = 'Undo',
        run = undo,
      },
      {
        combo = 'backspace',
        id = 'find_back',
        title = 'Take Back a Typed Letter',
        run = find_back,
      },
    }
    local shortcut_for = {} ---@type table<string, CodeExplorer.Shortcut>
    local commands = app.try_use ('commands')
    local keys = app.try_use ('keys')
    for _, s in ipairs (shortcuts) do
      shortcut_for[s.combo] = s
      if commands then
        local id = 'code.explorer.' .. s.id
        commands.register ({
          id = id,
          category = 'Explorer',
          title = s.title,
          hidden = true,
          when = focused,
          run = s.run,
        })
        if keys then
          keys.bind (s.combo, id)
        end
      end
    end

    tree:on ('keydown', function (ev)
      if edit or drag or ev.composing then
        return nil
      end
      local key = ev.key or ''
      local ctrl = ev.ctrl or ev.meta
      local s = shortcut_for[(ctrl and 'ctrl+' or '') .. key:lower ()]
      if s and not ev.alt then
        s.run ()
        return 'stop'
      end
      if ctrl or ev.alt then
        return nil
      end
      local r = cursor and row_at[cursor]
      ---@param index integer
      local function go (index)
        local target = rows[math.max (1, math.min (#rows, index))]
        if not target then
          return
        end
        if ev.shift then
          select_range (target.entry.path)
        else
          select_one (target.entry.path, true)
        end
      end
      if key == 'ArrowDown' then
        go (r and r.index + 1 or 1)
      elseif key == 'ArrowUp' then
        go (r and r.index - 1 or #rows)
      elseif key == 'PageDown' then
        go (r and r.index + 10 or 1)
      elseif key == 'PageUp' then
        go (r and r.index - 10 or 1)
      elseif key == 'Home' then
        go (1)
      elseif key == 'End' then
        go (#rows)
      elseif key == 'ArrowRight' and r then
        local entry = r.entry
        if entry.dir and not expanded[entry.path] then
          activate_row (entry, true)
        elseif entry.dir then
          local child = rows[r.index + 1]
          if child and paths.parent (child.entry.path) == entry.path then
            select_one (child.entry.path, true)
          end
        end
      elseif key == 'ArrowLeft' and r then
        local entry = r.entry
        if entry.dir and expanded[entry.path] then
          activate_row (entry, true)
        elseif row_at[paths.parent (entry.path)] then
          select_one (paths.parent (entry.path), true)
        end
      elseif key == 'Enter' and r then
        activate_row (r.entry, false)
      elseif key == ' ' and find_text == '' and r then
        activate_row (r.entry, true)
      elseif key == 'Escape' then
        if find_text ~= '' then
          end_find ()
        elseif clip then
          clear_clip ()
        elseif picked_count () > 1 then
          select_one (cursor)
        else
          return nil
        end
      elseif utf8.len (key) == 1 then
        type_find (key)
      else
        return nil
      end
      return 'stop'
    end)

    -- Keeping up with the disk, tabs, edits and Git --------------------------------------

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

    for _, key in ipairs ({ 'project.exclude', 'code.explorer.gitignore' }) do
      settings.watch (key, function ()
        if root and listing[''] then
          refresh_all ()
        end
      end)
    end

    app.on ('tabs:changed', function ()
      local path = active_tab_path ()
      if path == active_path then
        return
      end
      active_path = path
      if not path or path == '' then
        return
      end
      if paths.parent (path) ~= '' then
        expand_to (paths.parent (path))
      end
      select_one (path)
      reveal_next = path
      render ()
    end)

    local editor = app.try_use ('editor')
    if editor then
      for _, info in ipairs (editor.docs ()) do
        local rel = rel_of (info.path)
        if rel and info.dirty () then
          unsaved[rel] = true
        end
      end
    end
    app.on ('editor:dirty', function (full, on)
      local rel = rel_of (full)
      if rel then
        unsaved[rel] = on and true or nil
        mark (rel, 'unsaved', on == true)
      end
    end)
    app.on ('editor:closed', function (full)
      local rel = rel_of (full)
      if rel then
        unsaved[rel] = nil
        mark (rel, 'unsaved', false)
      end
    end)
    -- A moved document closes at its old path and opens again at the new one, edits and all.
    app.on ('editor:opened', function (info)
      local rel = rel_of (info.path)
      if rel and info.dirty () then
        unsaved[rel] = true
        mark (rel, 'unsaved', true)
      end
    end)

    -- Another icon pack, or new icons in this one.
    app.on ('icons:changed', function ()
      render ()
    end)

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
      render_soon ()
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
          title = disk.native (root, app.os),
          project.name () or root,
        }),
        head_button ('file-plus', 'New file', function ()
          start_create ('file', target_dir ())
        end),
        head_button ('folder-plus', 'New folder', function ()
          start_create ('folder', target_dir ())
        end),
        head_button ('refresh-cw', 'Refresh', refresh_all),
        head_button ('list-collapse', 'Collapse all', collapse_all),
      }),
      tree,
      find_label,
    })
    render ()

    views.add ('left', {
      id = 'explorer',
      title = 'Explorer',
      icon = 'files',
      order = 10,
      key = 'ctrl+shift+e',
      content = content,
    })

    -- Other plugins add sections under the tree, such as the folder's own Proteus plugins. A
    -- restricted plugin adds sections only to its own views, so the explorer adds them for it.
    app.provide ('code.explorer', {
      ---@param spec Proteus.ViewSectionSpec
      ---@return Proteus.ViewSection?
      add_section = function (spec)
        return views.add_section ('explorer', spec)
      end,
    })

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
        run = collapse_all,
      })
      commands.register ({
        id = 'code.explorer.reveal_active',
        category = 'Explorer',
        title = 'Reveal Active File in Explorer',
        icon = 'locate',
        when = function ()
          return active_tab_path () ~= nil
        end,
        run = function ()
          local path = active_tab_path ()
          if not path then
            return
          end
          views.show ('explorer')
          if paths.parent (path) ~= '' then
            expand_to (paths.parent (path))
          end
          select_one (path)
          reveal_next = path
          render ()
          tree:focus ()
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
