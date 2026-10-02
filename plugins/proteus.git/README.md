# Git

A Git client for any folder that holds a repository. It runs the real `git` program and shows the changed files, the diff of each one, and the history. Install the **Git** profile from the marketplace to run it as an app of its own.

## What it does

- **Changes.** The Changes view lists staged, changed and new files. Stage, unstage or discard a file, or a single hunk in its diff. Git reads each path as a file name, never a pattern, so discarding a file called `*.log` leaves the other `.log` files alone.
- **Commits.** Write a message and commit, or amend the last commit.
- **Branches and remotes.** Switch or create a branch, and fetch, pull and push. The status bar shows the branch and the commits to push and to pull. A branch pushed for the first time goes to the remote its `branch.<name>.remote` setting names, or to the only remote, or to `origin` among several.
- **No hidden prompts.** Fetch, pull, push and clone never ask for a password or a passphrase on a terminal, since the app has none: Git and ssh fail at once and the error says why. Sign in through a credential helper or an ssh agent instead. A `core.sshCommand` of your own is kept as it is. **Cancel** (or a click on the busy item in the status bar) stops one that is still running.
- **History.** The History view lists the last 200 commits, and a click shows a commit's diff.
- **Clone and init.** Clone a repository or start a new one in any folder.
- **Large repositories.** Each list in the Changes view draws its first 500 files, and **Show all** draws the rest. A diff or a commit reads its first 5,000 lines and leaves out the rest, and a hunk cut short cannot be staged. Coming back to the window reads the status again, but where that takes long it waits ten times as long between reads, up to a minute. A repository whose `status.showUntrackedFiles` setting is `normal` lists a new folder as one row, and `no` leaves new files out.

## In the Code Editor

When the `project` service runs, as in the Code Editor, it works on the open folder. The Changes view becomes Source Control (Ctrl+Shift+G), a diff opens in a tab that can close, and Open File opens the file in the editor. It sends each file's Git state as the `git:status` event, which colours the file tree, and refreshes when the folder sends `code:disk_changed` or a file is saved.

`git:status` carries full paths on disk, so a plugin hears it only with the `files` permission.

## What it needs

Git on the PATH. In a browser it shows that it needs the desktop app.

## Permissions

| Permission | Why |
|------------|-----|
| `process` | It runs the `git` program for every action. |
| `files` | It works on a repository anywhere on disk: it reads the changed files for their diffs, opens a file or its folder, and asks for a folder in the system's dialog. It also uses the Code Editor's `project` and `editor` services. |
