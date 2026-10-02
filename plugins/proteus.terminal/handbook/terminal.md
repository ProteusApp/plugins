---
title: Terminal
section: Editor and languages
order: 88
keywords: terminal shell console pty split panes profiles bash zsh pwsh powershell cmd git bash working folder cwd open in terminal run selection rename close all terminal.shell terminal.profiles terminal.default_profile
---

# Terminal

`proteus.terminal` puts real terminals in the bottom dock. It runs in the Code Editor (the `code` profile), and in the Plugin Editor or any other profile with the bottom dock once it is installed from the marketplace. **Ctrl+`** shows or hides the panel, and **Ctrl+Shift+`** opens another terminal. In the Plugin Editor **Ctrl+`** belongs to the Console, so **Ctrl+Shift+`** opens a terminal there.

Each tab of the panel holds one terminal, or several split side by side. **Split Terminal** (**Ctrl+Shift+5**, or the button beside **+**) opens one to the right of the terminal with the focus, in the same tab. A click in a terminal gives it the focus, and the tab is named after what that terminal runs.

## Where a terminal starts

A new terminal starts in the first of these folders it has:

1. the folder it was opened for, such as **Open in Terminal** on a folder in the Code Editor's file tree, or **New Terminal in Folder…**
2. its profile's `cwd`
3. the folder open in the Code Editor
4. the workspace folder, where your plugins are

## Profiles

A profile is a program a terminal runs, with its arguments, its variables and its folder. The default profile runs the `terminal.shell` setting, and the system shell when that is empty: PowerShell on Windows, or the login shell elsewhere. The `terminal.profiles` setting adds more:

```json
[
  { "name": "Git Bash", "program": "C:/Program Files/Git/bin/bash.exe", "args": ["-l"] },
  { "name": "Node", "program": "node", "env": { "NODE_ENV": "development" }, "cwd": "C:/code/site" }
]
```

| Field | What it is |
|-------|------------|
| `name` | What menus show. Two profiles cannot share a name. |
| `program` | The program. The system shell when it is empty or left out. |
| `args` | Its arguments, a list of text. |
| `env` | Variables added to the app's own. |
| `cwd` | The folder it starts in, a full path. |

The arrow beside **+** lists the profiles, and **New Terminal with Profile…** picks one. `terminal.default_profile` names the profile a new terminal runs. A profile that is broken is left out, and a notice says why.

## Settings

| Key | Type | What it does | Default |
|-----|------|--------------|---------|
| `terminal.shell` | string | The program the default profile runs, with any arguments, such as `pwsh -NoLogo` or `bash -l`. Quotes keep a path with spaces in one piece. | empty, the system shell |
| `terminal.profiles` | json | More profiles, as above. | none |
| `terminal.default_profile` | string | The name of the profile a new terminal runs. | empty, the default profile |
| `terminal.font_size` | number | The terminals' font size. | `13` |

## Commands

| Command | Key | What it does |
|---------|-----|--------------|
| `terminal.new` | **Ctrl+Shift+`** | Opens a terminal in a tab of its own. |
| `terminal.new_profile` | | Opens a terminal with the profile picked. |
| `terminal.new_in_folder` | | Opens a terminal in the folder picked. |
| `terminal.split` | **Ctrl+Shift+5** | Opens a terminal beside the one with the focus. |
| `terminal.rename` | | Names the terminal with the focus. An empty name lets its program name it again. |
| `terminal.next`, `terminal.previous` | | Moves the focus to the next or the previous terminal. |
| `terminal.run_selection` | | Types the text selected in the editor into the terminal with the focus, and runs it. |
| `terminal.restart` | | Starts the program of the terminal with the focus again. |
| `terminal.close` | | Closes the terminal with the focus. A middle click on a tab does too. |
| `terminal.close_all` | | Closes every terminal and stops their programs. |

The panel is shared, so other plugins may show it with `terminal.show.terminal`, as the Code Editor's folder page does.

## The `terminal` service

Other plugins open terminals through the `terminal` service. `terminal.open (opts)` shows the panel and opens a terminal. It returns false where there are none, as in a browser. Every field of `opts` is optional:

| Field | What it does |
|-------|--------------|
| `cwd` | The folder it starts in, a full path. |
| `profile` | The name of a profile. The default profile when it is unknown. |
| `name` | The name on its tab, which the program's own title does not change. |
| `split` | Opens it beside the terminal with the focus, in the same tab. |

`terminal.profiles ()` returns the profiles' names, `''` first for the default profile.

```lua
local terminal = app.try_use ('terminal')
if terminal then
  terminal.open ({ cwd = '/home/ana/site', name = 'Site', split = true })
  app.log ('profiles:', table.concat (terminal.profiles (), ', '))
end
```

A plugin that may run without it lists `proteus.terminal` in `optional` and asks with `app.try_use`, as above. The Code Editor's file tree does so for **Open in Terminal**.

The service takes full paths, so a restricted plugin needs the `files` permission to use it. It types nothing into a terminal: the user does.

## Permissions

`proteus.terminal` runs restricted. It asks for `process` to run the programs, `files` to start them in folders on disk and to read the selection for **Run Selected Text in Terminal**, and `clipboard` for **Paste** in the terminal's right-click menu.

## See also

- [Widgets](proteus.lib.ui/widgets.md#the-terminal), for a terminal of a plugin's own.
- [Project](proteus.code.project/project.md), the Code Editor's folder.
- [Proteus.Terminal](types/services.md#proteus.terminal) in the reference.
