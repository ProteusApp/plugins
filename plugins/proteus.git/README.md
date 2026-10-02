# Git

A Git client for any folder that holds a repository. It runs the real `git` program and shows the changed files, the diff of each one, and the history. Install the **Git** profile from the marketplace to run it as an app of its own.

## What it does

- **Changes.** The Changes view lists staged, changed and new files. Stage, unstage or discard a file, or a single hunk in its diff. A click on an added or removed line's numbers picks it, and **Stage Lines** (or **Unstage Lines**) beside its hunk stages only the picked lines. A new file is staged whole, since Git has no earlier version to add part of it to. Where a removed line is followed by the line that replaced it, the words that changed are marked on both. **Toggle Side-by-Side Diff** shows the old file on the left and the new one on the right, and the client remembers the choice. Git reads each path as a file name, never a pattern, so discarding a file called `*.log` leaves the other `.log` files alone.
- **Commits.** Write a message and commit, or amend the last commit.
- **Merge, rebase, cherry-pick, revert and reset.** **Merge Branch…** merges another branch into the current one, and **Rebase onto Branch…** replays the current branch's own commits on top of another. A commit's menu in the History view cherry-picks it, reverts it, resets the current branch to it (soft, mixed, or hard after a question) or starts a branch there. One that stops at conflicts shows a bar above the Changes list with **Continue**, **Abort** and, for a rebase, **Skip**. Continue on a merge commits with the message in the box, or Git's own when it is empty. None of them opens an editor: Git takes the message it wrote.
- **Conflicts.** Files with conflicts gather under **Merge Changes**. A click shows the conflict with a bar that says what each side did, and offers **Accept Current** (the current branch's version), **Accept Incoming** (the version coming in), **Mark Resolved** and **Open File**. A side that deleted the file deletes it. Mark Resolved asks first when the file still holds conflict markers. The same actions are in the file's menu.
- **Delete and rename branches.** **Delete Branch…** deletes a local branch, and asks again before deleting one whose commits no other branch has. **Rename Branch…** renames the current branch.
- **Tags and remotes.** **Create Tag Here…** in a commit's menu tags it, with a message for an annotated tag or none for a plain one. **Delete Tag…** deletes one here, and **Push Tag…** pushes one, or every tag, to a remote. **Add Remote…**, **Remove Remote…**, **Rename Remote…** and **Change Remote Address…** manage the remotes.
- **Stashes.** **Stash Changes…** saves the changes away with a message, and leaves the files as the last commit has them. **Stash Changes and New Files…** takes new files too. **Stashes…** lists them, to apply one, pop it (apply, then drop), show what it holds, or drop it. **Pop Latest Stash** brings back the newest.
- **Branches and remotes.** Switch or create a branch, and fetch, pull and push. The status bar shows the branch and the commits to push and to pull. A branch pushed for the first time goes to the remote its `branch.<name>.remote` setting names, or to the only remote, or to `origin` among several.
- **No hidden prompts.** Fetch, pull, push and clone never ask for a password or a passphrase on a terminal, since the app has none: Git and ssh fail at once and the error says why. Sign in through a credential helper or an ssh agent instead. A `core.sshCommand` of your own is kept as it is. **Cancel** (or a click on the busy item in the status bar) stops one that is still running.
- **History.** The History view lists 200 commits at a time, and **Load more commits** at its end reads the next 200. A graph beside the list draws each branch in a lane of its own colour, with lines from every commit to its parents, so merges show where they joined. A click shows a commit's diff. The search box finds commits by their message, or by their author with `author:<name>`, ignoring case. **File History** in a changed file's menu, or **Git: Show File History** for the file in front in the Code Editor, lists the commits that changed one file, following it across renames. A search or a file's history leaves commits out, so it draws no graph.
- **Blame.** **Blame** in a changed file's menu, or **Git: Blame File** for the file in front in the Code Editor (or one picked in a dialog), shows who last changed each line, with the commit's short hash, author and day where its lines start. A click on the hash shows that commit. **Git: Show File History** picks a file the same way.
- **Clone and init.** Clone a repository or start a new one in any folder.
- **Large repositories.** Each list in the Changes view draws its first 500 files, and **Show all** draws the rest. A diff or a commit reads its first 5,000 lines and leaves out the rest, and a hunk cut short cannot be staged. Coming back to the window reads the status again, but where that takes long it waits ten times as long between reads, up to a minute. A repository whose `status.showUntrackedFiles` setting is `normal` lists a new folder as one row, and `no` leaves new files out.

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
| `files` | It works on a repository anywhere on disk: it reads the changed files for their diffs, lists its `.git` folder to find a merge or rebase that stopped part way, opens a file or its folder, and asks for a folder or a file in the system's dialog. It also uses the Code Editor's `project` and `editor` services. |
