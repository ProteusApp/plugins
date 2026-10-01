# Terminal (Nodal)

A terminal in the bottom dock, with a shell picker and a Restart button. It is a small Nodal graph built as an app, and shows how a graph drives a real terminal.

The graph ships with Proteus as `graphs/terminal.ndg`. Open it in the Plugin Editor or the **Nodal** profile to change it.

## What it does

- Pick PowerShell, cmd or bash. The terminal starts again with it.
- **Restart** starts the shell again.

It needs the desktop app. In a browser the terminal says it cannot start.

## How it is built

The app's `scripts/build-graphs.mjs` writes `init.lua` from the graph, the way Nodal's **Build as App** does, and puts a copy of the graph beside it as `terminal.ndg`. Neither is edited by hand. `tests/graph.test.lua` fails when `init.lua` no longer carries that graph in Nodal's own wrapper.

## Permissions

| Permission | Why |
|------------|-----|
| `process` | Its terminal runs a shell. |
