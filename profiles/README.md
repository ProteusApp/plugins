# Profiles

Each folder here is one approved profile, named by its id. A profile is a list of plugins with its settings, held in `profile.lua`, and `proteus.json` beside it is written by the registry. The Proteus marketplace installs a profile into `profiles/<id>.lua` in the workspace, together with any listed plugin it names that the workspace lacks.

The app profiles, `api`, `code`, `git`, `kanban`, `logs`, `nodal`, `notes` and `sheet`, start from the app's `shell` base with `extends = 'shell'`, and each runs `proteus.marketplace`, so a plugin can be installed from inside the app with **Ctrl+Shift+X**. In an app without tabs, the marketplace's pages float over the window. Kanban and Notes have no side panels of their own, so they show the left sidebar as an icon bar, where the marketplace's icon sits.
