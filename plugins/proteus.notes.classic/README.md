# Notes (classic)

The Notes app written by hand in Lua. The **Notes** profile runs `proteus.notes`, the same app built as a Nodal graph, so no profile runs this one. It stays as an example of an app written as plain code, to read beside the graph. Add it to a profile of your own to run it.

## What it does

- A list of notes on the left, with a search box, and the open note filling the window.
- **Ctrl+N** makes a new note, **Ctrl+E** switches between writing and a Markdown preview, and **Ctrl+Shift+F** searches.
- Notes are saved as you type, as Markdown files in `data/notes`, the same folder the graph app uses. The first line of a note is its title.
- Right-click a note to open or delete it.

It fills the main area, so it does not run beside `proteus.ui.tabs`.

## Permissions

| Permission | Why |
|------------|-----|
| `workspace` | It keeps the notes in `data/notes`, which is not its own `data/proteus.notes.classic` folder. |
