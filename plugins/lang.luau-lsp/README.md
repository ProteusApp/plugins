# Luau

Luau support for the Proteus code editor, built on [luau-lsp](https://github.com/JohnnyMorganz/luau-lsp), the language server behind VS Code's Luau extension. Luau is the typed Lua that Roblox uses.

## What it does

- **Colors for `.luau` files.** Luau's keywords, `true`, `false` and `nil`, and its common globals, such as `print`, `table`, `game`, `Instance` and `Vector3`, each get their color. A `--` comment colors to the end of the line.
- **Completion, hover help, go to definition and type problems** from luau-lsp. F12 or Ctrl+click jumps to a definition. The Problems panel lists type errors and lint warnings.
- **Roblox mode.** luau-lsp loads Roblox's types and API documentation, so `game:GetService("` offers every service, and hover help explains each class and method.
- **Rojo sourcemaps.** In Roblox mode, Rojo keeps `sourcemap.json` up to date while the server runs. That tells luau-lsp which instance each script is, so `game.ReplicatedStorage.Shared` and `require` calls get their types.
- **Formatting.** Format Document (Shift+Alt+F) runs StyLua on Luau files when `stylua` is on the PATH.

The language server starts when the first Luau file opens.

## Roblox mode

`luau-lsp.roblox` is `auto` at first. Then Roblox mode turns on for a folder that holds a Rojo project file, such as `default.project.json`, or a `.luaurc`. Set it to `on` or `off` to decide for every folder.

In Roblox mode, the plugin downloads Roblox's type definitions and API documentation from luau-lsp's site into `data/lang.luau-lsp/` in the workspace. Out of it, the plugin downloads only the documentation for Luau's own library, which gives hover help for names such as `print` and `table.insert`. These are the same files VS Code's extension uses. A new copy downloads at most once a day, and takes effect when the server next starts.

When the folder holds `default.project.json` and `rojo` is on the PATH, the plugin runs `rojo sourcemap default.project.json --output sourcemap.json --watch` in the folder while the server runs. Each time Rojo writes the file, the server reads it again. Turn `luau-lsp.sourcemap` off to leave `sourcemap.json` alone.

## What it needs

Nothing to install for the language server. When `luau-lsp` is not on the PATH, the plugin offers to download the official release, checked against its pinned checksum. `rokit add JohnnyMorganz/luau-lsp` or `aftman add JohnnyMorganz/luau-lsp` puts one on the PATH instead.

[Rojo](https://rojo.space) keeps the sourcemap up to date, and [StyLua](https://github.com/JohnnyMorganz/StyLua) formats. Each is optional, and each works only when it is on the PATH.

## What it does not do

- **`.lua` files stay with Lua.** They belong to the app's own `lua` language and its Lua language server, so this plugin cannot take them. Rename a Roblox script to `.luau` for luau-lsp to check it.
- **A `--[[ block ]]` comment colors only its first line.** The editor colors one line at a time, so the lines after the first look like code.
- **An older Proteus colors `--` as an operator.** The `comment` field of a language is new. Without it, `--` starts no comment, and `/*` starts one as in C.
- **The Studio plugin is not supported.** It sends the instance tree from Roblox Studio to VS Code's extension. Use Rojo's sourcemap instead.

## Settings

| Setting | Default | What it does |
|---------|---------|--------------|
| `luau-lsp.enabled` | `true` | Runs the Luau language server. |
| `luau-lsp.roblox` | `auto` | Loads Roblox's types and API documentation. `auto` turns it on for a folder with a Rojo project file or a `.luaurc`. |
| `luau-lsp.sourcemap` | `true` | In Roblox mode, runs Rojo to keep `sourcemap.json` up to date. |
| `luau-lsp.format` | `true` | Formats Luau files with StyLua. |

**Luau: Restart the Language Server** starts the server again, and looks for StyLua again.
