# Docker

Dockerfile and Compose support for the Proteus code editor, built on [docker-langserver](https://github.com/rcjsuen/dockerfile-language-server-nodejs) and [Hadolint](https://github.com/hadolint/hadolint).

## What it does

- **Completion** for instructions, their flags such as `COPY --chown=`, build stage names after `--from=`, and variables after `$`.
- **Hover help** for each instruction, with an example and a link to Docker's reference.
- **Go to definition** (F12 or Ctrl+click) from a stage name or a variable to where it is named.
- **Problems.** The language server finds mistakes such as a missing argument or an unknown flag. Hadolint adds best-practice findings, such as an image without a tag or `apt-get install` without `-y`. Both show in the Problems panel (Ctrl+Shift+M).
- **Formatting.** Format Document (Shift+Alt+F) asks the language server to tidy the file. It takes the spaces off the start of each instruction, and indents the lines that continue one by four spaces.
- **Compose files.** `compose.yaml`, `docker-compose.yml` and the files that add to them, such as `compose.override.yaml`, get the Compose Specification's JSON schema. A YAML plugin that reads `schema` file associations, such as `lang.yaml`, then gives them completion, hover help and checks.

Hadolint runs when a Dockerfile opens and each time it is saved. It reads a `.hadolint.yaml` in the file's folder, so a project can turn rules off there.

The language server starts when the first Dockerfile opens.

## Which files count as Dockerfiles

The editor knows a Dockerfile by its whole name: `Dockerfile` or `Containerfile`. Files such as `Dockerfile.dev`, `prod.Dockerfile` or `api.dockerfile` open as plain text, and this plugin does not serve them. A plugin cannot teach the editor new names for a language it ships, so renaming such a file to `Dockerfile`, in a folder of its own, is the way to get the help.

## What it needs

Node.js on the PATH. When the server is nowhere else, the first Dockerfile file that opens has npm install dockerfile-language-server-nodejs 0.15.0 into the app's cache folder. The **Download missing tools** setting, `tools.download`, can make it ask first or never do it. To install it yourself instead:

```text
npm install --global dockerfile-language-server-nodejs
```

A project that has `dockerfile-language-server-nodejs` in its own `node_modules` uses that copy.

Hadolint needs nothing to install. When `hadolint` is not on the PATH, the plugin offers to download the official release, checked against its pinned checksum. Hadolint publishes no file for Windows on ARM, so there it must be on the PATH. `brew install hadolint` or `scoop install hadolint` puts one there.

The **Tools** panel shows both programs, their state and their logs.

## Settings

| Setting | Default | What it does |
|---------|---------|--------------|
| `docker.enabled` | `true` | Runs the Dockerfile language server. |
| `docker.hadolint` | `true` | Checks Dockerfiles with Hadolint when they open and when they are saved. |
| `docker.format` | `true` | Formats Dockerfiles with the language server. |

## How it is built

The app's `lsp.client` inserts a completion item over the word before the cursor, as the editor finds it. docker-langserver replaces from the `--` of a flag or the `$` of a variable, so `--chown=` would come out as `----chown=`. `lib/server.lua` builds the same client from the app's `lsp` modules instead, and `completion.lua` tells the editor where each item starts. The server also asks for its settings in two sections, and leaves out any check the answer does not name, so `config.lua` names every check. `edits.lua` applies the server's formatting edits to the text. `program.lua` finds `node` and the server's script, since npm's files on Windows cannot start on their own, and `launch.lua` lists where the script may be. `lint.lua` runs Hadolint, and `hadolint.lua` turns its JSON output into problems.
