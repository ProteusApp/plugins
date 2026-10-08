# Project Explorer

A file tree of the folder open in the Code Editor, in the left dock (**Ctrl+Shift+E**). It reads each folder from disk as it opens, and keeps up with changes made outside the app.

- New files and folders, renames and copies are typed into the tree itself.
- Dragging items onto a folder moves them there. Files and folders dragged in from the system's file manager are copied into the folder they are dropped on. Delete moves items to the Recycle Bin or Trash.
- **Ctrl+C**, **Ctrl+X** and **Ctrl+V** copy, cut and paste files. **F2** renames, and typed letters jump to a name.
- **Ctrl+Z** in the tree takes back the last rename, move, paste, drop, new file or delete. A delete comes back from the Recycle Bin or Trash, on Windows and Linux. Taking back a copy or a new file moves it to the trash, after asking.
- A letter after a name shows what Git sees, from `proteus.git`. A dot marks a file with unsaved edits. What `.gitignore` leaves out shows dimmed.
- **Find in Folder…** in the right-click menu opens Search, from `proteus.code.search`, kept to that folder.
- **Open in Terminal** in a folder's right-click menu opens a terminal there, from `proteus.terminal`.
- Files that belong with another file sit under it, such as `package-lock.json` under `package.json` and `app.js` under `app.ts`. The arrow before the file opens the group. Delete, cut, copy and drag take a closed group along with the file on top.
- The tree follows the tab in front. **Reveal Active File in Explorer** finds it again after the tree moved on.

When it moves a file, open tabs follow it, and it sends `code:disk_renamed` with the old and the new full path. **Find in Folder** sends `code:search_folder` with the folder's full path. Both need `files` to hear.

Other plugins add to the tree through the `code.explorer` service. What a plugin adds goes away when it stops.

- `add_section (spec)` adds a section under the tree, as `proteus.code.plugins` does.
- `add_nesting (rules)` adds files to nest, written the way `code.explorer.nest` writes them. A pattern the setting holds wins over the plugin's.
- `add_menu_item (spec)` adds an item to a file's right-click menu. `when` gets the file's full path and says whether the item shows, and `run` gets it too. Since it hands out full paths, a restricted plugin needs `files`. When two plugins add an item with the same label, the first one shows. With `folders = true` the item shows on a folder's right-click menu instead, and on the tree's empty space, and `when` and `run` get the folder's full path.

The Godot plugins use the last two:

```lua
local explorer = app.try_use ('code.explorer')
if explorer and explorer.add_nesting then
  explorer.add_nesting ({ ['*'] = { '${capture}.uid' } })
  explorer.add_menu_item ({
    label = 'Open in the Godot Editor',
    icon = 'app-window',
    when = function (path)
      return path:sub (-5) == '.tscn'
    end,
    run = function (path)
      app.log ('open', path)
    end,
  })
end
```

## Settings

| Setting | Default | What it does |
|---------|---------|--------------|
| `code.explorer.gitignore` | `false` | Leaves out what `.gitignore` ignores, such as build output, instead of showing it dimmed. |
| `code.explorer.nest` | lock files under `package.json` and `Cargo.toml`, `tsconfig.*.json` and `*.tsbuildinfo` under `tsconfig.json`, and built files under `*.ts` and `*.js` | Which files sit under which. See below. |

The tree leaves out what the `project.exclude` setting of `proteus.code.project` matches, which Search and **Go to File** leave out too. It takes glob patterns, such as `node_modules`, `*.min.js` or `docs/build`. It took over `code.explorer.hide`, and kept what was set there.

`code.explorer.nest` maps a name pattern for the file on top to the patterns of the files under it. `*` matches any run of characters and `?` matches one. The first `*` in the key is kept, and `${capture}` in a pattern below stands for what it matched. A value can be a list of patterns or one string split by commas. So an entry from VS Code's `explorer.fileNesting.patterns` works, as long as it uses only `${capture}`. Use `{}` to turn these off. Rules from other plugins stay while those plugins run.

```json
{
  "tsconfig.json": ["tsconfig.*.json", "*.tsbuildinfo"],
  "*.ts": ["${capture}.js", "${capture}.d.ts"]
}
```

Nesting goes one level deep. A file that another file wants under it never holds files of its own.

Its commands are `code.explorer.refresh`, `code.explorer.collapse`, `code.explorer.reveal_active` and `code.explorer.undo_last`, and the tree's keys run hidden `code.explorer.*` commands while the tree has the focus.

The tree itself, with its selection, keys, typed names, dragging and clipboard, is `lib/file_tree.lua` in Proteus, which the Plugin Editor's Plugins panel draws too. So this plugin needs the `file-tree` feature.

## Permissions

- `files` reads and changes the folder on disk, and reveals items in the file manager. The `project` and `editor` services need it too, and so do the `editor:*` and `git:status` events it follows.
