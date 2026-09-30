# Proteus plugins

This repository holds the community plugins and profiles for [Proteus](https://github.com/ProteusApp), the desktop app made entirely of Lua plugins. A plugin is a folder of Lua code. A profile is a list of plugins with its settings, which turns Proteus into a different app. Everything here was reviewed by a maintainer before it was merged. The Proteus marketplace lists it and installs it.

A plugin from this registry does not get the run of the computer. Proteus runs it restricted: in a Lua environment of its own, able to draw, keep its own data and write in the workspace folders it claims, and nothing more unless its `permissions` ask for it. The marketplace shows what a plugin, and every plugin it brings along, asks for before it installs. `files`, `process`, `workspace` and `kernel` amount to full access, so review matters most for a plugin that asks for one of them.

## Install a plugin or a profile

Open the **Marketplace** in Proteus (Ctrl+Shift+X) and pick **Community**. It lists every plugin and profile in `index.json`. **Install** copies a plugin into `plugins/community/<id>` in the workspace, exactly as it was when it was approved. In the Code Editor it can go into the open folder's `.proteus/plugins/community/<id>` instead, for everyone who opens that folder. A profile installs into `profiles/<id>.lua`, together with any plugin from this registry that it runs.

## Publish a plugin or a profile

Write the plugin in the Plugin Editor, then choose **Plugins > Publish Plugin**. For a profile, choose **Profile > Publish Profile**. Proteus asks to sign in with GitHub. The sign-in grants one permission: opening issues on this repository.

Publishing then takes these steps:

1. Proteus opens an issue labeled `[AUTOMATED] Plugin Request`. It holds a manifest and every file of the plugin as a code block that folds shut. A profile's manifest says `"kind": "profile"` and lists the plugins it runs, and its one file is `profile.lua`. A large plugin continues in comments on the same issue, and a very large file splits into numbered parts.
2. The submission workflow checks the submission against the rules below. When it passes, the workflow opens a pull request with the files in `plugins/<id>/`, or `profiles/<id>/` for a profile, and links it on the issue. When it fails, the workflow explains why on the issue.
3. A maintainer reviews the code in the pull request.
4. The maintainer approves it by commenting `/approve` on the issue, or by merging the pull request. The index workflow rebuilds `index.json`, and the marketplace lists it.

A pull request opened by hand is welcome too. It must follow the same layout and pass the same check.

## Update a plugin

Raise `version` in the plugin's `init.lua`, or in the table a profile returns, save it, and publish again. The new version goes through the same review. Only the first author can update a plugin or profile, and the version must go up. Once the update is approved, the marketplace offers **Update** to everyone who installed it.

## What a plugin declares

A plugin's `init.lua` returns its table, and these fields say what it needs from Proteus:

| Field | What it says |
|-------|--------------|
| `permissions` | What it may do beyond drawing and keeping its own data: `net` (HTTP and opening web pages), `clipboard` (reading it), `midi` (hearing MIDI keyboards), `files` (any file on disk), `process` (running programs and terminals), `workspace` (writing anywhere in the workspace) and `kernel` (starting and stopping plugins). The last four amount to full access. |
| `folders` | Workspace folders it writes its files in, such as `shaders`. It may always write in `data/<id>/`. Folders Proteus uses, such as `plugins` and `data`, cannot be claimed. |
| `requires` | `proteus`, the versions it runs on, such as `>=0.2.0`, and `features`, what it needs of the app, such as `webview` or `languages`. The marketplace refuses a plugin this Proteus cannot run. |
| `depends` | Plugins that must start first. Each ships with Proteus or is listed here, and the marketplace installs the listed ones along with it. |

A restricted plugin names its services, events, commands and settings after the first or the last part of its id, such as `rust.restart` for `lang.rust`, never after a part the app's own plugins use.

## The rules

- The id is lower case letters, digits, dots, dashes and underscores, such as `my.plugin`. It cannot be the id of a plugin or profile that ships with Proteus. `reserved.json` lists those: `ids` and `prefixes` for plugins, and `profiles` for profiles. A plugin and a profile may share an id.
- A plugin has an `init.lua` at its top, a name, a one-sentence description, and a version such as `1.0.0`.
- A profile has a `profile.lua` at its top, a name, a one-sentence description, a version, and at least one plugin in its `plugins` list.
- Every file is text a reviewer can read, of any kind: UTF-8, without control characters other than tabs and line breaks, without the characters that reorder text on screen, and without lines longer than 1000 characters, so no code hides in minified lines.
- What `init.lua` declares matches `proteus.json`: name, description, version, `depends`, `optional`, `permissions`, `folders` and `requires`. The marketplace reads `proteus.json` before an install, and Proteus runs what `init.lua` says, so they must agree.
- Every plugin in `depends`, or in a profile's `plugins`, ships with Proteus or is listed here.
- The Lua passes StyLua and selene with this repository's `stylua.toml` and `selene.toml`, and the plugin's tests pass.
- A plugin holds up to 200 files and 2 MB, with no file over 512 KB and no folder more than three deep.

## Layout

| Path | What it holds |
|------|---------------|
| `plugins/<id>/` | One plugin's files, plus `proteus.json`, which the registry writes |
| `profiles/<id>/` | One profile's `profile.lua`, plus `proteus.json` with `"kind": "profile"` |
| `plugins/<id>/tests/` | The plugin's own tests, `*.test.lua`, which the check runs |
| `plugins/<id>/handbook/` | Pages the plugin adds to the Handbook, as Markdown. The `handbook` plugin's `handbook/writing-pages.md` explains them. |
| `index.json` | Every approved plugin in `plugins`, and every profile in `profiles`, with the commit to install it from |
| `reserved.json` | Ids that belong to the plugins and profiles shipped with Proteus |
| `scripts/` | The rules and the workflows' code |
| `test/` | Tests for the scripts, run with `node --test` |
| `stylua.toml`, `selene.toml` | The Lua style and lint rules, the same as the app's. `tests.selene.toml` lints tests. |

## Test and check locally

`npm ci`, then `npm test` runs the scripts' tests and `scripts/lua-test.mjs`, which loads each `init.lua` as Proteus does, compares what it declares with `proteus.json`, and runs every plugin's `tests/*.test.lua`. `npm run check` holds every folder to the rules. `node scripts/manifest.mjs plugins/<id> --author <login>:<id>` writes the `proteus.json` of a folder added by hand. The check workflow runs all of this on each pull request, with pinned StyLua and selene releases.

`REVIEWING.md` covers the maintainers' side: the review checklist and how the repository is set up.
