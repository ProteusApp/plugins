# Kanban

Boards of cards in columns. Drag cards along as work moves. Install the **Kanban** profile from the marketplace to run it as an app of its own. The profile runs the marketplace too, so more plugins install from inside the app: press **Ctrl+Shift+X**.

This plugin is a Nodal graph built as an app, with no code blocks. The graph ships with Proteus as `graphs/kanban.ndg`. Open it in the Plugin Editor with Nodal on (**Add Nodal** on its home page), or in the **Nodal** profile, to see how it works.

## What it does

- Make, open, rename, duplicate and delete boards. Each board is a JSON file in `data/kanban`. **Open Board** picks one by name, and **Duplicate Board** writes a copy of the open board under a new name and opens it.
- Add columns and cards, and drag them. A card has a title, labels, a due date, a priority, a checklist and notes.
- Search the cards, or show only one label. Archived cards keep their own list.
- The **Boards** panel in the left dock lists the boards and the archived cards, and the **Card** panel in the right dock changes the picked card, so the board fills the window. Each panel has a tab and a **Show** command of its own, such as `kanban.show.kanban.nodal.side`.
- **Ctrl+N** adds a card, **Ctrl+F** searches, and **Ctrl+Z** and **Ctrl+Y** undo and redo.

## How it is built

The app's `fixtures.kanban ()` builds the graph, and `scripts/build-graphs.mjs` writes it, `init.lua` and the copy `kanban.ndg` beside it, the way Nodal's **Build as App** does. None of them is edited by hand. `tests/graph.test.lua` fails when `init.lua` no longer carries that graph in Nodal's own wrapper.

Its commands are named after it, such as `kanban.nodal.n72` for **New Card**, since it runs restricted. It needs Proteus 0.3.1, the first version with Nodal's docks.

## Permissions

| Permission | Why |
|------------|-----|
| `workspace` | It keeps the boards in `data/kanban`, which is not its own `data/proteus.kanban` folder, so boards from older versions open there too. |
