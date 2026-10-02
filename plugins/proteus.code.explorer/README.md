# Project Explorer

A file tree of the folder open in the Code Editor, in the left dock (**Ctrl+Shift+E**). It reads each folder from disk as it opens, and keeps up with changes made outside the app.

- New files and folders, renames and copies are typed into the tree itself.
- Dragging items onto a folder moves them there. Delete moves items to the Recycle Bin or Trash.
- **Ctrl+C**, **Ctrl+X** and **Ctrl+V** copy, cut and paste files. **F2** renames, and typed letters jump to a name.
- A letter after a name shows what Git sees, from `proteus.git`. A dot marks a file with unsaved edits.
- **Find in Folder…** in the right-click menu opens Search, from `proteus.code.search`, kept to that folder.
- Files that belong with another file sit under it, such as `package-lock.json` under `package.json` and `app.js` under `app.ts`. The arrow before the file opens the group, and so do **Right** and **Left**. Delete, cut, copy and drag take a closed group along with the file on top.

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
| `code.explorer.hide` | `.git`, `.DS_Store`, `Thumbs.db`, `desktop.ini` | Names the tree leaves out. Before 0.3.0 this was `explorer.hide`. |
| `code.explorer.nest` | lock files under `package.json` and `Cargo.toml`, `tsconfig.*.json` and `*.tsbuildinfo` under `tsconfig.json`, and built files under `*.ts` and `*.js` | Which files sit under which. See below. |

`code.explorer.nest` maps a name pattern for the file on top to the patterns of the files under it. `*` matches any run of characters and `?` matches one. The first `*` in the key is kept, and `${capture}` in a pattern below stands for what it matched. A value can be a list of patterns or one string split by commas. That means an entry from VS Code's `explorer.fileNesting.patterns` works as long as it uses only `${capture}`. Use `{}` to turn nesting off.

```json
{
  "tsconfig.json": ["tsconfig.*.json", "*.tsbuildinfo"],
  "*.ts": ["${capture}.js", "${capture}.d.ts"]
}
```

Nesting goes one level deep. A file that another file wants under it never holds files of its own.

Its commands are `code.explorer.refresh` and `code.explorer.collapse`, and the tree's keys run hidden `code.explorer.*` commands while the tree has the focus.

## Permissions

- `files` reads and changes the folder on disk, and reveals items in the file manager. The `project` and `editor` services need it too, and so do the `editor:*` and `git:status` events it follows.
