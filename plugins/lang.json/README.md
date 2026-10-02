# JSON

JSON support for the Proteus code editor, built on `vscode-json-language-server`, the language server behind VS Code's own JSON support.

## What it does

- **Completion, hover help and checks** from JSON schemas. A file gets a schema from SchemaStore's catalog of common files, such as `package.json` and `.prettierrc.json`, or from a `schema` file association that any plugin adds.
- **Problems.** Syntax errors, and values that break the schema, show in the Problems panel (Ctrl+Shift+M).
- **Completion from other plugins.** The editor asks `completion` file associations only while a language server runs for the file. With this plugin running, `lang.javascript` completes npm package names in `package.json`.
- **Comments where they belong.** `.jsonc` files, and settings files such as `tsconfig.json` and `.vscode/settings.json`, may hold comments and trailing commas. Other JSON files may not.

The editor treats `.json`, `.jsonc`, `.json5` and `.ndg` files as JSON. JSON5 allows more than the server reads, such as keys without quotes, so `.json5` files get completion and hover help but no problems.

Formatting comes from Prettier, which ships with Proteus, so this plugin adds no formatter.

The language server starts when the first JSON file opens.

## What it needs

Node.js on the PATH. When the server is nowhere else, the first JSON file that opens has npm install vscode-langservers-extracted 4.10.0 into the app's cache folder. The **Download missing tools** setting, `tools.download`, can make it ask first or never do it. To install it yourself instead:

```text
npm install --global vscode-langservers-extracted
```

A project that has `vscode-langservers-extracted` in its own `node_modules` uses that copy. The **Tools** panel shows the server's state, version and log, with buttons to start, stop and look again.

## Schemas for other plugins

A plugin gives its own JSON files completion and checks by adding a file association, with no need to know this plugin exists:

```lua
app.use ('files').associate ({
  kind = 'schema',
  pattern = 'myplugin.json',
  value = 'https://example.com/myplugin.schema.json',
})
```

List `proteus.core.files` in the plugin's `depends`. `lang.typescript` does this for `tsconfig.json`, and `lang.javascript` for `package.json` and `jsconfig.json`. A pattern without `/` matches the file name in any folder. A plugin's schema for a pattern wins over the catalog's for the same pattern.

## Settings

| Setting | Default | What it does |
|---------|---------|--------------|
| `json.enabled` | `true` | Runs the JSON language server. |
| `json.schema_catalog` | `true` | Fetches the list of schemas for common files from schemastore.org. |
| `json.validate` | `true` | Shows syntax errors and schema problems in the Problems panel. |

## How it is built

The server never asks for its settings, so `lib/server.lua` sends them once it starts and again after each change. That needs more than the app's `lsp.client` offers, so it builds the same client from the app's `lsp` modules. It also names each file `json` or `jsonc` as it opens. `schemas.lua` turns associations and SchemaStore's catalog into the server's `json.schemas` setting, and the server downloads each schema itself. `provider.lua` and `completion.lua` turn the server's completion items into plain text that fits around the quotes already typed. `program.lua` finds `node` and the server's script, since npm's files on Windows cannot start on their own, and `launch.lua` lists where the script may be.
