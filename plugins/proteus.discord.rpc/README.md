# Discord Rich Presence

Shows what you are doing in Proteus on your Discord profile, the way the Discord extensions for VS Code do. Each app has its own lines: the editor shows the file being edited, Git shows the branch, and Notes shows "Writing notes". The Handbook page **discord: Rich Presence** covers all of it.

## What it does

- It stays off until you switch it on with **Discord: Turn Rich Presence On or Off**.
- **Discord: Show or Hide Names in Rich Presence** keeps file, plugin, repository, branch and project names off Discord.
- **Discord: Open Rich Presence Settings** opens Settings. Its settings are under `discord.`, and each profile keeps its own. The first profile that starts it moves the values of the older `data/proteus.discord.rpc/discord.json` into its settings, and deletes that file.
- Other plugins add their own lines and words through the `discord` service, which needs `net`, since what they add shows on a public profile. The Code Editor's folder name it reads by itself.

## What it needs

The desktop app on Windows, with the Discord desktop app running. A small PowerShell script carries the messages to Discord. When Discord is closed, it tries again every 15 seconds. On other systems it never starts the script.

## Permissions

| Permission | Why |
|------------|-----|
| `process` | It starts the PowerShell script that talks to Discord, since a plugin cannot open Discord's pipe itself. |
| `files` | It follows the editor, through the `editor` service and the `editor:*` events, to show the name and language of the file being edited. It also reads the Code Editor's open folder through the `project` service. |

The `discord` service it provides needs the `net` permission, since what a plugin sets shows on your public Discord profile. A plugin without `net` gets no `discord` service.
