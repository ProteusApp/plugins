# Proteus plugins

This repository holds the community plugins for [Proteus](https://github.com/ProteusApp), the desktop app made entirely of Lua plugins. Every plugin here was reviewed by a maintainer before it was merged. The Proteus store lists these plugins and installs them.

**Warning:** a plugin is trusted code. Once it runs, it can read and write any file the user can, the same as an editor extension. Review lowers that risk but does not remove it.

## Install a plugin

Open the Plugin Editor and choose **Plugins > Store**. The store lists every plugin in `index.json`. **Install** copies the plugin into `plugins/community/<id>` in the workspace, exactly as it was when it was approved.

## Publish a plugin

Write the plugin in the Plugin Editor, then choose **Plugins > Publish Plugin**. Proteus asks to sign in with GitHub. The sign-in grants one permission: opening issues on this repository.

Publishing then takes these steps:

1. Proteus opens an issue labeled `[AUTOMATED] Plugin Request`. It holds a manifest and every file of the plugin as a code block that folds shut. A large plugin continues in comments on the same issue, and a very large file splits into numbered parts.
2. The submission workflow checks the plugin against the rules below. When it passes, the workflow opens a pull request with the files in `plugins/<id>/`, and links it on the issue. When it fails, the workflow explains why on the issue.
3. A maintainer reviews the code in the pull request.
4. The maintainer approves it by commenting `/approve` on the issue, or by merging the pull request. The index workflow rebuilds `index.json`, and the store lists the plugin.

A pull request opened by hand is welcome too. It must follow the same layout and pass the same check.

## Update a plugin

Raise `version` in the plugin's `init.lua`, save it, and choose **Plugins > Publish Plugin** again. The new version goes through the same review. Only the plugin's first author can update it, and the version must go up. Once the update is approved, the store offers **Update** to everyone who installed the plugin.

## The rules

- The id is lower case letters, digits, dots, dashes and underscores, such as `my.plugin`. It cannot be the id of a plugin that ships with Proteus. `reserved.json` lists those.
- The plugin has an `init.lua` at its top, a name, a one-sentence description, and a version such as `1.0.0`.
- Every file is text, of a kind a reviewer can read: `.lua`, `.md`, `.json`, `.css`, `.txt`, `.toml`, `.yml`, `.yaml`, `.html` or `.svg`.
- A plugin holds up to 200 files and 2 MB, with no file over 512 KB and no folder more than three deep.

## Layout

| Path | What it holds |
|------|---------------|
| `plugins/<id>/` | One plugin's files, plus `proteus.json`, which the registry writes |
| `index.json` | Every approved plugin, with the commit to install it from |
| `reserved.json` | Ids that belong to the plugins shipped with Proteus |
| `scripts/` | The rules and the workflows' code |
| `test/` | Tests for the scripts, run with `node --test` |

`REVIEWING.md` covers the maintainers' side: the review checklist and how the repository is set up.
