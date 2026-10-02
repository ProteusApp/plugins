# Search

Finds and replaces text in every file of the folder open in the Code Editor, in the left dock. **Ctrl+Shift+F** opens it, with the text selected in the editor as the search, and **Ctrl+Shift+H** opens it with the replace box.

Typing searches after a short pause, and Enter searches at once. A new search stops the one still running, and so do **Escape** and **Stop** in the status line. The buttons beside the box match case, match whole words, and read the text as a regular expression. **Up** and **Down** in the box go back through earlier searches.

Files to include and exclude take glob patterns, such as `src/**` or `*.test.ts`. The book button beside them keeps the search to the files open in the editor. What `.gitignore` leaves out, and what the `project.exclude` setting matches, are never searched. When files change on disk, the results follow.

## Replace

The arrow before the box opens the replace box. Each match then shows what it becomes, crossed out and followed by the new text. With a regular expression, `$1` or `${name}` stands for a group, and `${1}x` keeps a group apart from the letters after it.

- The button on a match replaces that match.
- The button on a file replaces every match in that file.
- **Replace All** beside the box, or **Ctrl+Alt+Enter**, replaces every match listed, after asking.

A file open in the editor changes there, as one edit that **Ctrl+Z** in that file takes back, and stays unsaved. Any other file changes on disk. **Undo** in the status line, or **Undo the Last Replace in Files**, takes back the last replace in every file it changed, unless the file changed again since.

## Keys

| Key | What it does |
|-----|--------------|
| **Ctrl+Down** in a box | Moves to the results. |
| **Up**, **Down**, **Home**, **End**, **Page Up**, **Page Down** | Move through the results. |
| **Left**, **Right** | Fold and unfold a file. |
| **Enter** | Opens a match, or folds a file. |
| **Space** | Opens a match and keeps the focus in the results. |
| **Escape** | Goes back to the search box. |
| **F4**, **Shift+F4** | Open the next or the previous match, from anywhere. |

## Events and commands

The `code:search_folder` event, with a full path, opens the panel kept to one folder. The explorer's **Find in Folder…** sends it. The `search.find_in_files` command is shared, so any plugin may run it. The others are `search.replace_in_files`, `search.next_match`, `search.previous_match`, `search.stop`, `search.refresh` and `search.undo_replace`.

## Permissions

- `files` searches the folder on disk and writes what Replace changes. The `project` and `editor` services need it too.
