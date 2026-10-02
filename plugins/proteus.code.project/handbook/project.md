---
title: Project
section: Editor and languages
order: 87
keywords: project folder open folder root name recent forget files relative absolute excluded pick close code:disk_changed code:disk_renamed code:search_folder disk changes code editor workspace folder gitignore project.exclude project.reopen
---

# Project

The `project` service is the folder the Code Editor works on. It opens a folder, remembers the folders opened before, lists the folder's files and watches them for changes made outside the app. It comes from `proteus.code.project`, which runs in the Code Editor (the `code` profile). Both come from the marketplace.

```lua
local project = app.use ('project')
local root = project.root ()
if root then
  app.log ('Working on ' .. project.name () .. ' at ' .. root)
end
```

Every path is a full path with `/`, such as `C:/code/app/src/main.rs` or `/home/me/app/src/main.rs`.

**Opening another folder reloads the window.** Every plugin starts again in the new folder, so a plugin reads `root` once when it starts and never needs to follow a change.

## `project.root` and `project.name`

`project.root ()` returns the open folder, or nil when none is open. `project.name ()` returns the folder's name, such as `'app'`, or nil.

```lua
local project = app.use ('project')
local status = app.use ('status')
status.add ({
  text = project.name () or 'No folder',
  icon = 'folder',
  align = 'left',
})
```

A plugin that works with or without a folder lists `proteus.code.project` in `optional` and asks with `app.try_use ('project')`. In the Plugin Editor there is no `project` service.

```lua
local project = app.try_use ('project')
local root = project and project.root () or nil
app.log (root and ('folder: ' .. root) or 'no folder open')
```

## `project.files`

`project.files (cb)` lists every file in the folder as paths from the root, sorted, such as `'src/main.rs'`. It skips what `.gitignore` leaves out, and every folder whose name is in the `project.exclude` setting. The list is kept until files come or go, so a second call answers at once. With no folder open, `cb` gets nil and an error.

```lua
local project = app.use ('project')
project.files (function (list, err)
  if not list then
    app.warn (err)
    return
  end
  local lua = 0
  for _, rel in ipairs (list) do
    if rel:match ('%.lua$') then
      lua = lua + 1
    end
  end
  app.log (lua .. ' Lua files of ' .. #list)
end)
```

## `project.relative` and `project.absolute`

`project.relative (path)` turns a full path into a path from the root. It returns `''` for the root itself, and nil for a path outside the folder. `project.absolute (rel)` turns a path from the root into a full path.

```lua
local project = app.use ('project')
local readme = project.absolute ('README.md')
app.log (readme) -- such as C:/code/app/README.md
app.log (project.relative (readme)) -- README.md
app.use ('editor').open_external (readme)
```

## `project.excluded`

`project.excluded ()` returns the folder names that search and **Go to File** leave out, from the `project.exclude` setting.

```lua
local skip = {}
for _, name in ipairs (app.use ('project').excluded ()) do
  skip[name] = true
end
app.log (skip.node_modules and 'node_modules is skipped' or 'searching all')
```

## Opening and closing folders

| Function | What it does |
|----------|--------------|
| `project.open (path)` | Opens a folder. A path that is not a folder shows an error. |
| `project.pick ()` | Shows the **Open Folder** dialog, then opens the folder picked. Needs the desktop app. |
| `project.close ()` | Closes the folder. The window reloads with no folder open. |
| `project.recent ()` | Returns the folders opened before, newest first, up to twelve. |
| `project.forget (path)` | Takes a folder off the recent list. |

Opening or closing reloads the window. When the `editor.restore_session` setting is on, open files and unsaved edits come back the next time the folder opens. When it is off and a file has unsaved edits, the user is asked first.

A command that opens the most recent other folder:

```lua
local project = app.use ('project')
app.use ('commands').register ({
  id = 'jump.back',
  title = 'Back to the Last Folder',
  run = function ()
    for _, path in ipairs (project.recent ()) do
      if path ~= project.root () then
        project.open (path)
        return
      end
    end
  end,
})
```

The app can start in a folder: `proteus C:\code\app` or `proteus --folder C:\code\app`. Otherwise the Code Editor opens the folder that was open last, while the `project.reopen` setting is on.

## Changes on disk

The service watches the open folder. When files change outside the app, it tells the editor, so open files reload, and sends `code:disk_changed` with the list of changes and the whole event. Each change has `path`, a full path, and `kind`, which says what is at the path now: `'file'`, `'dir'` or `'remove'`.

| Field of the event | What it is |
|--------------------|------------|
| `changes` | The list of changes. |
| `overflow` | True when too much changed to list, so read everything again. |
| `git` | True when Git's own records changed, such as the branch or a new commit. |

```lua
local project = app.use ('project')
app.on ('code:disk_changed', function (changes, ev)
  if ev.overflow then
    app.log ('many files changed')
    return
  end
  for _, change in ipairs (changes) do
    app.log (change.kind, project.relative (change.path))
  end
end)
```

When `proteus.code.explorer` renames or moves a file, it tells the editor, so open tabs follow it, and sends `code:disk_renamed` with the old and the new full path. **Find in Folder** in its right-click menu sends `code:search_folder` with the folder's full path, and `proteus.code.search` opens its panel with the search kept to that folder.

```lua
app.on ('code:disk_renamed', function (from, to)
  app.log ('moved ' .. from .. ' to ' .. to)
end)
```

A plugin of its own that changes the folder tells the editor the same way, through the `editor` service:

```lua
local editor = app.use ('editor')
local project = app.use ('project')
local from = project.absolute ('notes.txt')
local to = project.absolute ('docs/notes.txt')
app.fs.move_path (from, to, function (_, err)
  if not err then
    editor.disk_renamed (from, to)
  end
end)
```

All three events carry full paths on disk, so a restricted plugin hears them only with the `files` permission. `proteus.code.project` [protects](proteus/services-and-events.md#app.protect_event) `code:disk_changed`, and `proteus.code.explorer` protects `code:disk_renamed` and `code:search_folder`.

## Settings

| Key | Type | What it does | Default |
|-----|------|--------------|---------|
| `project.exclude` | json | Folder names that search and **Go to File** skip wherever they are, on top of `.gitignore`. | `node_modules`, `target`, `dist`, `build`, `out`, `.venv`, `venv`, `__pycache__`, `dist-newstyle`, `.stack-work`, `.next`, `.cache`, `coverage` |
| `project.reopen` | boolean | Opens the last folder when the Code Editor starts. | true |

## Commands

| Command | Key | What it does |
|---------|-----|--------------|
| `project.open` | | **File > Open Folder…**. Shared, so any plugin may run it. |
| `project.recent` | **Ctrl+R** | **File > Open Recent Folder…**. Shared, so any plugin may run it. |
| `project.close` | | **File > Close Folder** |
| `project.reveal` | | Shows the folder in the system file manager. |
| `project.copy_path` | | Copies the folder's path. |
| `project.trust` | | Trusts the folder's `.proteus` files and reloads. |
| `project.untrust` | | Stops using the folder's `.proteus` files and reloads. |

The status bar shows the folder's name, and a click on it opens a recent folder. The window's title names the folder too.

## The folder's own setup

A folder can carry its own Proteus setup in a `.proteus` folder: settings, plugins of its own and profiles. It can run code, so it stays off until the user trusts the folder. Each of its plugins asks the user before it gets a permission, and one such as `process` gives full access to the computer. While it is in use, a **.proteus** item shows in the status bar, and a click on it opens `.proteus/settings.json`. See [A folder's own .proteus setup](proteus/project-folders.md).

## Restricted plugins

The `project` service needs the `files` permission. A restricted plugin without it cannot `use` it, and does not hear `code:disk_changed`, `code:disk_renamed`, `code:search_folder` or `git:status`, which carry full paths. See [Permissions](proteus/permissions.md#events).

`proteus.code.project` runs restricted too. It asks for `files` for the folder on disk, `kernel` to open folders and trust their `.proteus` files, and `net` to name the folder on Discord through `proteus.discord.rpc`.

## See also

- [Editor](proteus.editor.core/editor.md) for opening the folder's files.
- [The Plugin Editor and the Code Editor](proteus/two-editors.md)
- [Proteus.Project](types/services.md#proteus.project) and [Proteus.DirEvent](types/proteus.md#proteus.direvent) in the reference.
