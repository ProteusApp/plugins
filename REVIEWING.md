# Reviewing and running the registry

## Review a submission

Each submission becomes a pull request labeled `[AUTOMATED] Plugin Request`, with a checklist. Read every file before merging. A merge is what makes the plugin or profile installable.

A profile is one `profile.lua` that lists plugins and settings. Check that every plugin it names ships with Proteus or is listed here, and that its settings hold nothing personal. Its settings must not name a program to run, a path to one, or a place code comes from, such as `terminal.shell`, `luals.path` or `marketplace.repository`. Proteus leaves out a profile's value for a setting defined with `sensitive = true`, but a plugin may not mark one that should be, so read each key.

The check workflow runs on each version: the rules, the plugin's tests, StyLua and selene, a comparison of what `init.lua` declares with `proteus.json`, and each vendored file against its published package. GitHub starts no workflow for a pull request the submission workflow opens, so the submission workflow starts the check on the branch itself. It shows on the pull request's commit. The pull request lists the plugin's permissions. Proteus enforces them, so a plugin without any cannot reach the network, run programs or touch files outside the workspace folders it claims.

Check that:

- the code does what the description says, and nothing else
- it asks only for the permissions its purpose needs. `files`, `process`, `workspace` and `kernel` amount to full access, so each needs a clear reason, and its code gets the closest reading
- it reads and writes only the files its purpose needs
- it sends nothing over the network, and runs no programs, beyond what its purpose needs
- a web view page loads nothing from elsewhere. Proteus blocks it anyway, but code that tries is a warning sign
- it holds no secrets, tokens or personal data
- it does not load code from elsewhere at run time, such as a script fetched from a URL
- a setting that names a program to run, a path to one, or a place code comes from is defined with `sensitive = true`, so a profile or a folder's `.proteus/settings.json` cannot choose it
- it runs nothing from the open folder, such as its build scripts, its Git hooks or a program in `node_modules`, until the user trusts the folder (`app.kernel.project ().trusted`)

Approve a submission by commenting `/approve <commit>` on its issue, with the first seven or more characters of the commit you read. The bot's comment on the issue names the current one, such as `/approve 1a2b3c4`. Text after the commit on the same line is fine, such as `/approve 1a2b3c4 thanks!`. The workflow checks four things first:

- the person commenting can write to this repository
- the pull request is the one the workflow opened for that issue
- its head is the commit the comment names, so an approval covers only the code that was read
- the check workflow passed on that commit

It then merges exactly that commit, rebuilds the index and closes the issue. A reaction on the comment shows the result: a rocket for merged, and a confused face with a reply when it could not merge. Merging the pull request by hand works too.

Close the pull request to turn a submission down, with a comment that says why. The author can publish a fixed version, which opens a new submission.

To take a plugin or profile down, delete its folder in a pull request, and add its id to `removed.json` with its owner's login and GitHub user id, from its `proteus.json`. The check refuses the pull request without that entry. The id then stays with its owner: nobody else can publish under it, so the marketplace never offers their code as an update to people who installed the old one. The index workflow drops it from `index.json`. Copies already installed stay on users' machines.

Leave `index.json` out of pull requests. The index workflow writes it after each merge, and the check refuses a pull request that changes it. The app installs each entry's files from the commit it names and shows its permissions before the install, so the check also holds every entry to that commit. The index keeps the earlier versions of each folder's history too, back to where the folder was last gone or someone else published it, and the app installs those the same way, so the check holds each of them to its commit as well. Taking a plugin down drops its earlier versions with it.

Authors take back what they sent from Proteus, with **Withdraw from the Registry**:

- A submission still in review: Proteus closes its issue. The workflow then closes the pull request and deletes its branch. A maintainer closing an issue leaves the pull request alone.
- A listed plugin or profile: Proteus opens an issue titled `Removal request: <id>`, or `Profile removal request: <id>`. When the person who opened it is the author `proteus.json` names, the workflow opens a pull request that deletes the folder and keeps the id with them in `removed.json`, and anyone else gets a comment saying no. Approve it like a submission, with `/approve` on the issue or by merging.

## Set up the repository

The workflows need four things, set once.

### 1. Let the workflows open pull requests

In **Settings > Actions > General**, under **Workflow permissions**, tick **Allow GitHub Actions to create and approve pull requests**.

### 2. Register the GitHub App that publishes

Publishing from Proteus signs in through a GitHub App, so the sign-in grants one permission on one repository. The registry's app is [Proteus App Plugin Manager](https://github.com/apps/proteus-app-plugin-manager), with client ID `Iv23liVZi1fS3WSDlLzi`. A replacement is registered in **Settings > Developer settings > GitHub Apps > New GitHub App**, with these settings:

| Field | Value |
|-------|-------|
| GitHub App name | `Proteus Plugins`, or any free name |
| Homepage URL | The Proteus repository |
| Callback URL | Leave empty |
| Expire user authorization tokens | Either. An expiring token lasts eight hours, and Proteus renews it with the refresh token, which device flow allows without the client secret. |
| Request user authorization (OAuth) during installation | Off |
| Enable Device Flow | **On**. Proteus signs in with it. |
| Webhook | Untick **Active** |
| Repository permissions | **Issues: Read and write**. Leave the rest at No access. |
| Account permissions | None |
| Where can this GitHub App be installed? | Only on this account |

Then install the app on the ProteusApp organization, with access to **only** the `plugins` repository.

The app's **Client ID** goes in Proteus, as the `store.client_id` setting's default in the `plugin.store` plugin. A client ID is public, and device flow needs no client secret, so none is generated or stored.

A user's token from this app can open issues and comment on this repository, and do nothing else. Proteus keeps it in the system's credential store, such as Windows Credential Manager or the macOS Keychain, until the user signs out. A user can also revoke it on GitHub under **Settings > Applications**.

### 3. Keep the label

The label `[AUTOMATED] Plugin Request` marks submissions and their pull requests. The workflow puts it on, since GitHub drops a label that an author without push access asks for.

### 4. Protect main

In **Settings > Rules > Rulesets**, add a branch ruleset for `main` with:

- **Require status checks to pass**, with the check `check` from GitHub Actions. A merge by hand then waits for the check too, as `/approve` does.
- **Require a pull request before merging**, with **Require review from Code Owners**. `.github/CODEOWNERS` names who reviews changes to `index.json`, `removed.json`, `reserved.json`, the workflows and the scripts, since the app trusts what they say. A submission's pull request touches only its own folder, so `/approve` still merges it.
- **Block force pushes**.

Give the `github-actions` app no bypass. The index workflow commits `index.json` straight to main, so either let it bypass the pull request rule alone, or turn that rule off and keep the other two.
