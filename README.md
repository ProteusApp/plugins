# Proteus plugins

This repository holds the community plugins and profiles for [Proteus](https://github.com/ProteusApp), the desktop app made entirely of Lua plugins. A plugin is a folder of Lua code. A profile is a list of plugins with its settings, which turns Proteus into a different app. Everything here was reviewed by a maintainer before it was merged. The Proteus marketplace lists it and installs it.

**Warning:** a plugin is trusted code. Once it runs, it can read and write any file the user can, the same as an editor extension. Review lowers that risk but does not remove it.

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

## The rules

- The id is lower case letters, digits, dots, dashes and underscores, such as `my.plugin`. It cannot be the id of a plugin or profile that ships with Proteus. `reserved.json` lists those: `ids` and `prefixes` for plugins, and `profiles` for profiles. A plugin and a profile may share an id.
- A plugin has an `init.lua` at its top, a name, a one-sentence description, and a version such as `1.0.0`.
- A profile has a `profile.lua` at its top, a name, a one-sentence description, a version, and at least one plugin in its `plugins` list.
- Every file is text, of a kind a reviewer can read: `.lua`, `.md`, `.json`, `.css`, `.txt`, `.toml`, `.yml`, `.yaml`, `.html` or `.svg`.
- A plugin holds up to 200 files and 2 MB, with no file over 512 KB and no folder more than three deep.

## Layout

| Path | What it holds |
|------|---------------|
| `plugins/<id>/` | One plugin's files, plus `proteus.json`, which the registry writes |
| `profiles/<id>/` | One profile's `profile.lua`, plus `proteus.json` with `"kind": "profile"` |
| `index.json` | Every approved plugin in `plugins`, and every profile in `profiles`, with the commit to install it from |
| `reserved.json` | Ids that belong to the plugins and profiles shipped with Proteus |
| `scripts/` | The rules and the workflows' code |
| `test/` | Tests for the scripts, run with `node --test` |

`REVIEWING.md` covers the maintainers' side: the review checklist and how the repository is set up.
