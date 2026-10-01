# Search

Finds text in every file of the folder open in the Code Editor, in the left dock. **Ctrl+Shift+F** opens it, with the text selected in the editor as the search.

Typing searches after a short pause, and Enter searches at once. The buttons beside the box match case, match whole words, and read the text as a regular expression. Files to include and exclude take glob patterns, such as `src/**` or `*.test.ts`. What `.gitignore` leaves out, and the folders in the `project.exclude` setting, are never searched. A click on a match opens the file at that line.

The `code:search_folder` event, with a full path, opens the panel kept to one folder. The explorer's **Find in Folder…** sends it. The `search.find_in_files` command is shared, so any plugin may run it.

## Permissions

- `files` searches the folder on disk. The `project` and `editor` services need it too.
