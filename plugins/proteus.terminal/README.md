# Terminal

Real terminals in the bottom dock. **Ctrl+`** shows or hides the panel, and **Ctrl+Shift+`** opens another terminal. Each terminal has a tab along the top of the panel, named after what it runs. A middle click on the tab closes it.

It works in any profile with the bottom dock, `proteus.ui.views`. In the Code Editor each terminal starts in the open folder. Elsewhere it starts in the home folder.

The panel is shared, so other plugins may show it, as the Code Editor's folder page does with `terminal.show.terminal`.

## Settings

| Setting | Default | What it does |
|---------|---------|--------------|
| `terminal.shell` | empty | The program each new terminal runs, such as `pwsh`, `cmd` or `bash`. Empty runs the system shell. |
| `terminal.font_size` | `13` | The terminals' font size. |

`terminal.shell` names the program that runs, so only your own choice sets it. A profile or a folder's `.proteus/settings.json` cannot.

## Permissions

- `process` runs the shell in each terminal.
- `files` lets a terminal start in the Code Editor's folder, which the `project` service hands out.
- `clipboard` reads the clipboard for **Paste** in the terminal's right-click menu.
