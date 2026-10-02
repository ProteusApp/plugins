# Terminal

Real terminals in the bottom dock, for the Plugin Editor, the Code Editor and any profile with the bottom dock, `proteus.ui.views`. **Ctrl+`** shows or hides the panel, and **Ctrl+Shift+`** opens another terminal.

- **Tabs and split panes.** Each tab holds one terminal, or several side by side. **Split Terminal** (**Ctrl+Shift+5**) opens one beside the terminal with the focus. A middle click on a tab closes its terminal, and **Close All Terminals** closes them all.
- **Profiles.** The default profile runs `terminal.shell`, or the system shell. `terminal.profiles` adds programs with their arguments, variables and folder, and the arrow beside **+** lists them.
- **A working folder.** A terminal starts in the folder open in the Code Editor, or else in the workspace folder. **New Terminal in Folder…** picks another, and the Code Editor's file tree has **Open in Terminal** on every folder.
- **Rename** names a terminal, and **Run Selected Text in Terminal** types the editor's selection into it.

The panel is shared, so other plugins may show it, as the Code Editor's folder page does with `terminal.show.terminal`. Plugins with the `files` permission open terminals through the `terminal` service. Its Handbook page, **Terminal**, covers the settings, the commands and the service.

## Settings

| Setting | Default | What it does |
|---------|---------|--------------|
| `terminal.shell` | empty | The program the default profile runs, such as `pwsh`, `cmd` or `bash`. Empty runs the system shell. |
| `terminal.profiles` | none | More profiles: `[{ "name": "Git Bash", "program": "C:/Program Files/Git/bin/bash.exe", "args": ["-l"] }]`, each with optional `args`, `env` and `cwd`. |
| `terminal.default_profile` | empty | The name of the profile a new terminal runs. |
| `terminal.font_size` | `13` | The terminals' font size. |

`terminal.shell` names the program that runs, so only your own choice sets it. A profile or a folder's `.proteus/settings.json` cannot.

## Permissions

- `process` runs the program in each terminal.
- `files` lets a terminal start in a folder on disk, such as the Code Editor's, which the `project` service hands out, and lets **Run Selected Text in Terminal** read the editor.
- `clipboard` reads the clipboard for **Paste** in the terminal's right-click menu.
