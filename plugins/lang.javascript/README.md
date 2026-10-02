# JavaScript

JavaScript support for the Proteus code editor, on the language server that `lang.typescript` runs.

## What it does

- **Completion, hover help and go to definition** in `.js`, `.mjs` and `.cjs` files. F12 or Ctrl+click jumps to where a name is defined, in the project or in a package.
- **Problems.** Syntax errors show as underlines and in the Problems panel (Ctrl+Shift+M). A file with `// @ts-check` at the top, or a `jsconfig.json` with `checkJs`, is type checked too.
- **One server with TypeScript.** JavaScript files share `lang.typescript`'s server, so a JavaScript file knows the types of the TypeScript files it imports, and the other way round.
- **Settings files.** `jsconfig.json` and `package.json` get their JSON schemas as file associations.
- **npm packages in `package.json`.** In `dependencies`, `devDependencies`, `peerDependencies` and `optionalDependencies`, typing a name searches the npm registry. Typing a version, as in `"react": "^`, lists the package's releases, the one npm installs by default first, without deprecated ones. A version with `-` in it lists pre-releases too.

The schemas and the npm completion show in `package.json` once a JSON language plugin runs, since they come beside that plugin's own help.

Formatting comes from Prettier, which ships with Proteus.

## What it needs

`lang.typescript` and what it needs: Node.js, with `typescript-language-server` and TypeScript installed. The marketplace installs `lang.typescript` along with this plugin.

It asks for `net`, to reach registry.npmjs.org, and `files`, to read the `package.json` it completes in.

## Settings

| Setting | Default | What it does |
|---------|---------|--------------|
| `javascript.npm_completion` | `true` | Completes npm package names and versions in `package.json`, from registry.npmjs.org. |

The server's own settings are `lang.typescript`'s.

## How it is built

`init.lua` asks `lang.typescript` to serve JavaScript and adds the file associations. `lib/npm.lua` asks the npm registry and keeps each answer for the session, and `lib/package_context.lua` works out whether a package's name or its version is being typed.
