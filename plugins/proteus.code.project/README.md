# Project

The folder the Code Editor works on. **File > Open Folder…** opens one, **Ctrl+R** opens one of the folders opened before, and **File > Close Folder** closes it. Opening another folder reloads the window, so every plugin starts again in it. The status bar and the window's title name the folder.

Other plugins reach the folder through the `project` service: its root, its name, its files, and the folders opened before. It watches the folder for changes made outside the app. The editor hears of them, so open files reload, and plugins hear them as the `code:disk_changed` event. The `proteus.code.project/project` page of the Handbook covers the service.

A folder can carry its own Proteus setup in a `.proteus` folder. It stays off until the user trusts the folder.

## Settings

| Setting | Default | What it does |
|---------|---------|--------------|
| `project.exclude` | `node_modules`, `target`, `dist` and other build folders | Folder names that search and **Go to File** skip. |
| `project.reopen` | `true` | Opens the last folder when the Code Editor starts. |

## Permissions

- `files` reads the folder on disk and watches it. The `project` service hands out full paths, so it needs `files` too.
- `kernel` tells the kernel which folder is open, opens another one, and trusts or stops trusting the folder's `.proteus` files.
