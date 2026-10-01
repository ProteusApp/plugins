# Kanban (classic)

The Kanban app written by hand in Lua. The **Kanban** profile runs `proteus.kanban`, the same app built as a Nodal graph, so no profile runs this one. It stays as an example of an app written as plain code, to read beside the graph. Add it to a profile of your own to run it.

## What it does

- Boards on the left, the open board in the middle, and the card being edited on the right.
- Drag cards and columns with the mouse. A column can have a limit, and a card has labels, a due date and notes.
- Search the cards and show only some labels. Undo and redo every change.
- Each board is a JSON file in `data/kanban`, the same folder the graph app uses. It saves a moment after each change, and a board changed elsewhere loads again.

`kanban_board.lua` holds the board logic, with no drawing, and `tests/kanban.test.lua` tests it.

## Permissions

| Permission | Why |
|------------|-----|
| `workspace` | It keeps the boards in `data/kanban`, which is not its own `data/proteus.kanban.classic` folder. |
