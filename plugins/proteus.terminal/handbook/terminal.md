---
title: Terminal
section: Editor and languages
order: 88
keywords: terminal shell console pty split panes profiles bash zsh pwsh powershell cmd git bash working folder cwd open in terminal run selection rename close all terminal.shell terminal.profiles terminal.default_profile tasks tasks.json run task build test problem matcher problems reload terminal.tasks
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

## Tasks

A task is a command with a name, such as the build or the tests. **Run Task…** lists the tasks and runs the one picked in a terminal tab of its own, named after the task. Running it again runs it in the same tab. **Run Build Task** and **Run Test Task** run the task of their group at once when there is only one, or the one marked `default`, and otherwise ask. **Run Last Task Again** does what it says.

Tasks come from two places:

1. the open folder's `.proteus/tasks.json`, for everyone who opens the folder
2. the `terminal.tasks` setting, for you alone

A folder's `.proteus` files only load once you trust the folder, and `.proteus/tasks.json` is one of them. A folder you have not trusted never runs its tasks. **Run Task…** says so when it has a `tasks.json`.

```json
{
  "tasks": [
    { "label": "Build", "command": "npm run build", "group": "build", "problems": "tsc" },
    { "label": "Test", "program": "cargo", "args": ["test"], "group": "test", "problems": "rustc" },
    { "label": "Site", "command": "npm start", "cwd": "web", "env": { "PORT": "8080" } }
  ]
}
```

The `terminal.tasks` setting holds the list alone, without `"tasks"` around it. It is a sensitive setting: only your own choice counts, so neither a profile nor a folder's `.proteus/settings.json` can add tasks through it.

| Field | What it is |
|-------|------------|
| `label` | The task's name. Two tasks cannot share one. |
| `command` | A command line, which runs in `sh` (`cmd` on Windows), so `&&`, `|` and `*` work. |
| `program` | A program, run as it is with `args`, instead of `command`. A task has one or the other. |
| `args` | A list of text, added to `command`, or passed to `program`. |
| `cwd` | The folder it runs in: inside the open folder, or a full path. The open folder, or else the workspace folder, when it is left out. |
| `env` | Variables added to the app's own. |
| `group` | `build` or `test`, for **Run Build Task** and **Run Test Task**. |
| `default` | `true` for the task its group runs at once. |
| `problems` | A problem matcher, or a list of them, as below. |
| `detail` | What the list of tasks shows under the label. |

A task that is broken is left out, and a notice says why.

### Problem matchers

A problem matcher reads a task's output line by line and sends the problems it finds to the Problems panel, under the source `task: <label>`. A file named without a full path is found from the task's folder. The task's problems start over each time it runs, and go when its terminal closes.

| Name | What it reads |
|------|---------------|
| `gcc` | `file:line:col: error: message`, from gcc and clang, and the same form from many other tools. `clang` and `go` are other names for it. |
| `tsc` | `file(line,col): error TS2322: message` from the TypeScript compiler, and its `--pretty` form. |
| `rustc` | `error[E0308]: message` and the `--> file:line:col` line after it, from rustc and Cargo. `cargo` is another name for it. |
| `eslint` | ESLint's default output: a file, then `line:col  error  message  rule` for each problem. |
| `lua` | `file:line:col: (W211) message` from luacheck, the gcc form from selene, and `lua: file:line: message` from Lua itself. |

## After a reload

The window reloads when a plugin changes, among other times. The terminals keep running meanwhile, and come back into the same tabs, split the same way, with their names. Each shows what its program printed while the window reloaded. A program that stopped meanwhile shows that it did. A terminal waits 30 seconds for the window to come back, and stops after that, as every terminal does when the window closes.

## Settings

| Key | Type | What it does | Default |
|-----|------|--------------|---------|
| `terminal.shell` | string | The program the default profile runs, such as `pwsh`, `cmd` or `bash`. | empty, the system shell |
| `terminal.profiles` | json | More profiles, as above. | none |
| `terminal.default_profile` | string | The name of the profile a new terminal runs. | empty, the default profile |
| `terminal.font_size` | number | The terminals' font size. | `13` |
| `terminal.tasks` | json | Tasks to run, beside the folder's, as above. | none |

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
| `terminal.run_task` | | Runs the task picked, in a terminal tab of its own. |
| `terminal.run_build_task`, `terminal.run_test_task` | | Runs the build or the test task. |
| `terminal.rerun_task` | | Runs the last task again. |

The panel is shared, so other plugins may show it with `terminal.show.terminal`, as the Code Editor's folder page does.

## The `terminal` service

Other plugins open terminals through the `terminal` service. `terminal.open (opts)` shows the panel and opens a terminal. It returns false where there are none, as in a browser. Every field of `opts` is optional:

| Field | What it does |
|-------|--------------|
| `cwd` | The folder it starts in, a full path. |
| `profile` | The name of a profile. The default profile when it is unknown. |
| `name` | The name on its tab, which the program's own title does not change. |
| `split` | Opens it beside the terminal with the focus, in the same tab. |

`terminal.profiles ()` returns the profiles' names, `''` first for the default profile. `terminal.tasks ()` returns the tasks' labels, and `terminal.run_task (label)` runs one, returning false when there is no such task.

```lua
local terminal = app.try_use ('terminal')
if terminal then
  terminal.open ({ cwd = '/home/ana/site', name = 'Site', split = true })
  app.log ('profiles:', table.concat (terminal.profiles (), ', '))
  if not terminal.run_task ('Build') then
    app.log ('tasks:', table.concat (terminal.tasks (), ', '))
  end
end
```

A plugin that may run without it lists `proteus.terminal` in `optional` and asks with `app.try_use`, as above. The Code Editor's file tree does so for **Open in Terminal**.

The service takes full paths, so a restricted plugin needs the `files` permission to use it. It types nothing into a terminal: the user does.

## Permissions

`proteus.terminal` runs restricted. It asks for `process` to run the programs, `files` to start them in folders on disk, to read the selection for **Run Selected Text in Terminal** and to see whether an untrusted folder has tasks, and `clipboard` for **Paste** in the terminal's right-click menu.

It needs Proteus 0.3.1 or later, for the features `terminal-sessions`, which keeps terminals through a reload, and `terminal-lines`, which hands a task's output to its problem matchers.

## See also

- [Widgets](proteus.lib.ui/widgets.md#the-terminal), for a terminal of a plugin's own, and [Terminals that survive a reload](proteus.lib.ui/widgets.md#terminals-that-survive-a-reload).
- [Problems](proteus.tools.diagnostics/diagnostics.md), the panel a task's problems go to.
- [Project](proteus.code.project/project.md), the Code Editor's folder.
- [Proteus.Terminal](types/services.md#proteus.terminal) in the reference.
