# Git

A Git client for any folder that holds a repository. It runs the real `git` program and shows the changed files, the diff of each one, and the history. Install the **Git** profile from the marketplace to run it as an app of its own.

## What it does

- **Changes.** The Changes view lists staged, changed and new files. Stage, unstage or discard a file, or a single hunk in its diff.
- **Commits.** Write a message and commit, or amend the last commit.
- **Branches and remotes.** Switch or create a branch, and fetch, pull and push. The status bar shows the branch and the commits to push and to pull.
- **History.** The History view lists the last 200 commits, and a click shows a commit's diff.
- **Clone and init.** Clone a repository or start a new one in any folder.

## In the Code Editor

When the `project` service runs, as in the Code Editor, it works on the open folder. The Changes view becomes Source Control (Ctrl+Shift+G), a diff opens in a tab that can close, and Open File opens the file in the editor. It sends each file's Git state as the `git:status` event, which colours the file tree, and refreshes when the folder sends `code:disk_changed` or a file is saved.

`git:status` carries full paths on disk, so a plugin hears it only with the `files` permission.

## Trusted repositories only

A repository's own settings, in `.git/config`, can make Git run programs: hooks when you commit, filters when it reads the status, and more. A folder that arrives as a zip, on a shared drive or on a USB stick brings that file along. So the client runs Git only in a repository you trust.

- In the Code Editor, that is a folder you trust. Until then the Source Control view says so and offers **Trust Folder**, which also lets the folder's `.proteus` files load.
- On its own, the client asks the first time it opens a repository, and remembers your answer. A repository you clone here is trusted at once, since a clone brings no settings from elsewhere.

Every command also turns off the settings that run a program without being asked for, such as `core.fsmonitor`, whatever the repository says.

## What it needs

Git on the PATH. In a browser it shows that it needs the desktop app.

## Permissions

| Permission | Why |
|------------|-----|
| `process` | It runs the `git` program for every action. |
| `files` | It works on a repository anywhere on disk: it reads the changed files for their diffs, opens a file or its folder, and asks for a folder in the system's dialog. It also uses the Code Editor's `project` and `editor` services. |
