# GDScript

GDScript support for the Proteus code editor, built on the language server inside the [Godot](https://godotengine.org) 4 editor.

## What it does

- **Colors** for GDScript files (`.gd`), with `#` comments and annotations such as `@export`.
- **Completion, hover help, go to definition and problems**, from the Godot editor's language server.
- **Scenes and resources.** `.tscn`, `.tres`, `project.godot` and `.import` files get colors of their own.
- **`res://` paths.** F12 on a path in quotes, such as `preload ("res://enemy.tscn")` or `path="res://player.gd"` in a scene, opens that file.

## How it connects

Godot's language server is not a program of its own. The Godot editor runs it while a project is open, and listens on a port on this computer, 6005 unless Godot's settings say otherwise. When the first GDScript file opens, the plugin connects to that port. The folder that holds `project.godot` is the project.

So the usual way is to open the project in the Godot editor, then edit its scripts in Proteus. If Godot is not running, the Tools panel says so. **Reconnect to Godot** in the command palette tries again once Godot is open. Opening another GDScript file tries again too.

Godot serves only the project it has open. A script from another project gets no help. Newer versions of Godot also show a warning then.

## Starting Godot from Proteus

With `gdscript.start_godot` on, the plugin starts Godot itself when nothing listens on the port. It runs the editor with no window, on the project, with its language server on the port:

```text
godot --path <project folder> --editor --headless --lsp-port 6005
```

It tries the port once a second until Godot answers, and stops Godot when Proteus closes or the plugin stops. Godot's output goes to its log in the Tools panel.

This needs Godot 4.2 or newer, since older versions need a window for the language server. The first start on a large project can take a while, because Godot scans and imports its files first. Godot without a window is less tested than the editor itself, so opening the project in the Godot editor stays the more reliable way.

The plugin looks for `godot` or `godot4` on the PATH. On Windows, Godot usually has a longer name, such as `Godot_v4.3-stable_win64.exe`. Put its full path in `gdscript.godot_path`.

## Formatting

Godot's language server has no formatter, so this plugin adds none.

## Settings

| Setting | Default | What it does |
|---------|---------|--------------|
| `gdscript.port` | `6005` | The port Godot's language server listens on. Godot's own setting is **Network > Language Server > Remote Port**. |
| `gdscript.start_godot` | `false` | Starts Godot with no window when it is not running. |
| `gdscript.godot_path` | empty | The full path of the Godot program. When empty, `godot` or `godot4` on the PATH. |

`gdscript.start_godot` and `gdscript.godot_path` decide what program runs, so only your own choice sets them. A profile or a folder's `.proteus/settings.json` cannot.
