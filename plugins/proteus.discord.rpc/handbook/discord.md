---
title: discord: Rich Presence
section: Data and integrations
order: 101
keywords: discord rich presence rpc status activity playing details state vars buttons images idle show names
---

# discord: Rich Presence

The `proteus.discord.rpc` plugin shows what is happening in Proteus on the user's Discord profile, the way the Discord extensions for VS Code do. Each app shows its own lines: the editor shows the file being edited, Git shows the branch, and Todo shows how much is left.

It stays off until the user switches it on. It needs the desktop app on Windows, with the Discord desktop app running. A small PowerShell script carries the messages to Discord, and when Discord is closed it tries again every 15 seconds. On other systems it never starts the script, and its commands say it works on Windows only.

The marketplace installs it from the registry. It asks for two permissions: `process` to start the PowerShell script, and `files` to follow the editor, so it can show the file being edited.

## Switching it on

Three commands in the **Discord** category change it:

| Command | What it does |
|---------|--------------|
| **Discord: Turn Rich Presence On or Off** (`discord.toggle`) | Shows or stops showing what you are doing. |
| **Discord: Show or Hide Names in Rich Presence** (`discord.names`) | Keeps file, plugin, repository, branch and project names off Discord, or shows them again. |
| **Discord: Open Rich Presence Settings** (`discord.settings`) | Opens Settings, where its settings are under **discord**. |

## Settings

Its settings live in Settings under `discord.`, so each profile keeps its own and a project folder's `.proteus/settings.json` can set them. A change applies at once.

| Setting | Default | What it does |
|---------|---------|--------------|
| `discord.enabled` | `false` | Shows the presence. |
| `discord.client_id` | `''`, the Proteus application | The Discord application whose name shows after "Playing". Set it to your own application's id to show another name. |
| `discord.show_names` | `true` | False keeps the words `file`, `plugin`, `repo`, `branch` and `project` off Discord, so lines that use them are skipped. |
| `discord.idle_minutes` | `10` | Minutes without activity before the first line says **Idle**. `0` never does. |
| `discord.images` | `{}` | The large image, by app id such as `editor` or `git`, or `default` for every app. A value is an art asset name from the Discord application, or an image address. |

Older versions kept these in `data/proteus.discord.rpc/discord.json`, shared by every profile. The first profile that starts this version moves that file's values into its own settings, for each setting not set there yet, and deletes the file.

Typing, saving, switching tabs, showing a panel or running a command counts as activity.

## What each app shows

The app is picked by the profile's id, or else by the plugins that run. Each line is a list of choices, and the first one whose words are all known shows.

| App | Runs when | First line | Second line |
|-----|-----------|------------|-------------|
| `git` | `proteus.git` runs | Working on {repo}, or Managing a Git repository | On branch {branch}, or Git |
| `api` | `proteus.api` runs | Testing an API | API Client |
| `logs` | `proteus.logs` runs | Reading logs | Logs |
| `sheet` | `proteus.sheet` runs | Working in a spreadsheet | Sheet |
| `kanban` | `proteus.kanban` runs | Moving cards along | Kanban |
| `notes` | `proteus.notes` runs | Writing notes | Notes |
| `todo` | `proteus.todo` runs | Checking off tasks | {left} left to do, or All done |
| `code` | `proteus.code.project` runs | Editing {file}, Working on {project}, or Writing code | In {project}, or Code Editor |
| `editor` | `proteus.ws.explorer` runs | Editing {file}, or Browsing the workspace | In {plugin}, or Building with Proteus |
| `nodal` | `proteus.nodal.app` runs | Wiring {file}, or Wiring blocks together | Nodal |
| any other | | Using {profile}, or Using Proteus | ProteusApp |

The time since Proteus started counts up beside the lines.

These words are filled in by the app:

| Word | Comes from |
|------|------------|
| `{profile}` | The profile's name. |
| `{file}` | The name of the file in the active editor tab. |
| `{language}` | Its language, such as Lua or TypeScript. The editors show it when the pointer rests on the large image, while one is set in `images`. |
| `{plugin}` | The plugin the file belongs to, in the Plugin Editor. |
| `{project}` | The open folder's name, from `proteus.code.project`. |
| `{repo}` and `{branch}` | The Git repository and branch, from `proteus.git`. |
| `{left}` | How many to-dos are left, from `proteus.todo`. |

## The `discord` service

A plugin shows its own presence through the `discord` service. List `proteus.discord.rpc` in `optional` so it starts first, and use `app.try_use`, since the user may run a profile without it. The service needs the `net` permission, since what a plugin sets shows on the user's Discord profile. Without it, `app.try_use` gives `nil` and logs a warning once.

```lua
local discord = app.try_use ('discord')
if discord then
  discord.set ({ details = 'Reviewing a diff', state = 'On branch {branch}' })
  discord.vars ({ branch = 'main' })
end
```

Each plugin gets its own handle. What a plugin sets goes away when it stops.

| Function | What it does |
|----------|--------------|
| `discord.set (presence)` | Lays this plugin's presence over the app's lines. It replaces what the plugin set before. |
| `discord.clear ()` | Takes the plugin's presence away, so the app's lines show again. |
| `discord.vars (vars)` | Fills words in braces, in the app's lines and in every presence. |
| `discord.connected ()` | True while Discord is listening. |

## `discord.set`

`discord.set (presence)` takes a [Proteus.DiscordPresence](types/services.md#proteus.discordpresence). Every field is optional, and a field left out keeps the app's text.

| Field | Type | What it does |
|-------|------|--------------|
| `details` | string | The first line, such as what the user is doing. |
| `state` | string | The second line. |
| `start` | integer | When it began, in seconds, such as `os.time ()`. Discord counts up from it. |
| `finish` | integer | When it ends, in seconds. Discord counts down to it. |
| `large_image` | string | An art asset name from the Discord application, or an image address. |
| `large_text` | string | Shown when the pointer rests on the large image. |
| `small_image` | string | An art asset name, or an image address. |
| `small_text` | string | Shown when the pointer rests on the small image. |
| `buttons` | table | Up to two links, each `{ label = ..., url = ... }`. |

This focus timer shows the task and counts down 25 minutes:

```lua
local discord = app.try_use ('discord')

---@param task string
local function focus (task)
  if not discord then
    return
  end
  discord.vars ({ task = task })
  discord.set ({
    details = 'Focusing on {task}',
    state = 'Focus timer',
    finish = os.time () + 25 * 60,
    buttons = {
      {
        label = 'Get Proteus plugins',
        url = 'https://github.com/ProteusApp/plugins',
      },
    },
  })
  app.timer.after (25 * 60 * 1000, function ()
    discord.clear ()
  end)
end

focus ('the release notes')
```

How presences combine:

- The plugin that set one most recently wins, field by field, over the app's lines and over older presences.
- A text field is filled from the words known. A field with a word that has no value is skipped, so the line underneath shows instead.
- While the user is idle, only the app's own lines show, with **Idle** as the first line. Presences wait until the user is back.
- Discord refuses lines longer than 128 bytes, so longer ones are cut and end in `...`.

## `discord.clear`

`discord.clear ()` takes the plugin's presence away. Its words stay. The presence also goes when the plugin stops, so a plugin that shows one for its whole life needs no clear.

```lua
local discord = app.try_use ('discord')

app.on ('editor:saved', function ()
  if discord then
    discord.clear ()
  end
end)
```

## `discord.vars`

`discord.vars (vars)` fills words in braces, such as `{ branch = 'main' }` for `'On branch {branch}'`. Numbers become text. `false` removes a word, so the lines that use it are skipped again. Each plugin's words are its own, and they go away when it stops.

Todo uses it to say how much is left:

```lua
local discord = app.try_use ('discord')

---@param left integer
local function show_left (left)
  if discord then
    discord.vars ({ left = left > 0 and left or false })
  end
end

show_left (3) -- "3 left to do"
show_left (0) -- "All done"
```

A plugin that runs inside an app can fill that app's words too. A word no app line uses, such as `{task}` above, only matters in presences.

## `discord.connected`

`discord.connected ()` is true while Discord is listening. It is false while Rich Presence is off, on other systems than Windows, and while Discord is closed.

```lua
local discord = app.try_use ('discord')

app.use ('commands').register ({
  id = 'focus.discord_status',
  title = 'Is Discord Listening?',
  run = function ()
    local on = discord ~= nil and discord.connected ()
    app.log (
      on and 'Discord shows your presence.' or 'Discord is not listening.'
    )
  end,
})
```

## How often it updates

Discord takes about five updates every 20 seconds, so the plugin waits at least 4 seconds between updates, and sends nothing when the presence did not change. Calling `set` or `vars` often costs nothing.

## Related pages

- [Services and events](proteus/services-and-events.md) covers `optional` and `app.try_use`.
- [The builtin apps](proteus/apps.md) lists the apps and what they do.
- [Proteus.Discord](types/services.md#proteus.discord) in the reference.
