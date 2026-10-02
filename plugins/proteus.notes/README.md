# Notes

Markdown notes, saved as you type. Install the **Notes** profile from the marketplace to run it as an app of its own. The profile runs the marketplace too, so more plugins install from inside the app: press **Ctrl+Shift+X**.

This plugin is a Nodal graph built as an app. Every list, button and command in it is a block. The graph ships with Proteus as `graphs/notes.ndg`. Open it in the Plugin Editor or the **Nodal** profile to see how it works.

## What it does

- **Ctrl+N** makes a new note, and **Ctrl+E** shows or hides the Markdown preview.
- The list shows each note's title, its first line, with the first words after it under it.
- The search box finds notes by their text, and **Ctrl+Shift+F** (**Search Notes**) puts the cursor in it.
- Right-click a note to delete it, or to open it in the editor when the profile runs one.
- Notes are Markdown files in `data/notes`. The **Notes folder** setting (`notes.folder`) picks another folder in the workspace.
- The **Notes font** setting (`notes.font`) sets the font notes are written and shown in, such as `Georgia, serif`. Empty uses the theme's `--notes-font`, or a serif font.

## How it is built

The app's `scripts/build-graphs.mjs` writes `init.lua` from the graph, the way Nodal's **Build as App** does, and puts a copy of the graph beside it as `notes.ndg`. Neither is edited by hand. `tests/graph.test.lua` fails when `init.lua` no longer carries that graph in Nodal's own wrapper.

Its commands are named after it, such as `notes.nodal.n52` for **New Note**, since it runs restricted. It needs Proteus 0.3.1, the first version with Nodal's **Read files** and **For each** blocks.

## Permissions

| Permission | Why |
|------------|-----|
| `workspace` | It keeps the notes in `data/notes`, which is not its own `data/proteus.notes` folder, and opens a note in the editor. |

A notes folder outside the workspace would need `files` too, which it does not ask for.
