# Project Explorer

A file tree of the folder open in the Code Editor, in the left dock (**Ctrl+Shift+E**). It reads each folder from disk as it opens, and keeps up with changes made outside the app.

- New files and folders, renames and copies are typed into the tree itself.
- Dragging items onto a folder moves them there. Files and folders dragged in from the system's file manager are copied into the folder they are dropped on. Delete moves items to the Recycle Bin or Trash.
- **Ctrl+C**, **Ctrl+X** and **Ctrl+V** copy, cut and paste files. **F2** renames, and typed letters jump to a name.
- **Ctrl+Z** in the tree takes back the last rename, move, paste, drop, new file or delete. A delete comes back from the Recycle Bin or Trash, on Windows and Linux. Taking back a copy or a new file moves it to the trash, after asking.
- A letter after a name shows what Git sees, from `proteus.git`. A dot marks a file with unsaved edits. What `.gitignore` leaves out shows dimmed.
- **Find in Folder…** in the right-click menu opens Search, from `proteus.code.search`, kept to that folder.
- **Open in Terminal** in a folder's right-click menu opens a terminal there, from `proteus.terminal`.
- The tree follows the tab in front. **Reveal Active File in Explorer** finds it again after the tree moved on.

When it moves a file, open tabs follow it, and it sends `code:disk_renamed` with the old and the new full path. **Find in Folder** sends `code:search_folder` with the folder's full path. Both need `files` to hear.

Other plugins add sections under the tree through the `code.explorer` service, as `proteus.code.plugins` does:

```lua
local explorer = app.try_use ('code.explorer')
if explorer then
  explorer.add_section ({ id = 'my.notes', title = 'Notes', content = app.use ('ui').div ({}) })
end
```

## Settings

| Setting | Default | What it does |
|---------|---------|--------------|
| `code.explorer.gitignore` | `false` | Leaves out what `.gitignore` ignores, such as build output, instead of showing it dimmed. |

The tree leaves out what the `project.exclude` setting of `proteus.code.project` matches, which Search and **Go to File** leave out too. It takes glob patterns, such as `node_modules`, `*.min.js` or `docs/build`. It took over `code.explorer.hide`, and kept what was set there.

Its commands are `code.explorer.refresh`, `code.explorer.collapse`, `code.explorer.reveal_active` and `code.explorer.undo_last`, and the tree's keys run hidden `code.explorer.*` commands while the tree has the focus.

## Permissions

- `files` reads and changes the folder on disk, and reveals items in the file manager. The `project` and `editor` services need it too, and so do the `editor:*` and `git:status` events it follows.
