# TypeScript

TypeScript support for the Proteus code editor, built on [typescript-language-server](https://github.com/typescript-language-server/typescript-language-server), which runs TypeScript's own `tsserver`.

## What it does

- **Completion, hover help and go to definition.** The server answers while code is typed. F12 or Ctrl+click jumps to where a name is defined, in the project or in a package's types.
- **Problems.** Type errors show as underlines and in the Problems panel (Ctrl+Shift+M).
- **Organize Imports.** **TypeScript: Organize Imports** (Shift+Alt+O) sorts the file's imports, merges them and drops the unused ones.
- **The project's TypeScript.** When the open folder has TypeScript in `node_modules`, the server checks the code with that version, so it matches the project's own build.
- **`tsconfig.json`.** `tsconfig.json` and files such as `tsconfig.app.json` get their JSON schema as a file association. A JSON language plugin then gives them completion and checks.

Formatting comes from Prettier, which ships with Proteus, so this plugin adds no formatter.

The language server starts when the first TypeScript file opens.

## One server for several languages

`lang.javascript` and `lang.react` run on this plugin's server, instead of each starting a server of their own. The server then knows how TypeScript, JavaScript, JSX and TSX files import each other, and uses one process's memory.

Another plugin adds a language through the `typescript` service. It lists `lang.typescript` in `depends`:

```lua
local remove = app.use ('typescript').serve ({
  language = 'jsx',
  language_id = 'javascriptreact',
})
```

`language` is the editor's name for the language, and `language_id` the server's. The language goes away when the plugin that asked for it stops, or when it calls `remove ()`.

## What it needs

Node.js, and the language server with TypeScript:

```text
npm install --global typescript-language-server typescript@6
```

A project that has `typescript-language-server` in its own `node_modules` uses that copy. TypeScript 7 is a native program without `tsserver`, so the server cannot run it. A project on TypeScript 7 is checked by the TypeScript 6 installed beside the server.

The **Tools** panel shows the server's state, version and log, with buttons to start, stop and look again.

## Settings

| Setting | Default | What it does |
|---------|---------|--------------|
| `typescript.enabled` | `true` | Runs the TypeScript language server. |
| `typescript.project_typescript` | `true` | Checks the code with the project's own TypeScript when it has one. Off, the TypeScript beside the server checks it. |

## How it is built

The app's `lsp.client` serves one language per server, so `lib/server.lua` builds the same thing from the app's `lsp` modules: one conversation with the server, and one set of open files and editor help for each language served. It also applies the edits Organize Imports sends back. `program.lua` finds `node` and the server's script, since npm's `.cmd` file on Windows cannot start on its own, and `launch.lua` lists where the script may be. `edits.lua` applies a server's edits to a file's text.
