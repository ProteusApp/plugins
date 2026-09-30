# Reviewing and running the registry

## Review a submission

Each submission becomes a pull request labeled `[AUTOMATED] Plugin Request`, with a checklist. Read every file before merging. A merge is what makes the plugin or profile installable.

A profile is one `profile.lua` that lists plugins and settings. Check that every plugin it names ships with Proteus or is listed here, and that its settings hold nothing personal.

Check that:

- the code does what the description says, and nothing else
- it reads and writes only the files its purpose needs
- it sends nothing over the network, and runs no programs, beyond what its purpose needs
- it holds no secrets, tokens or personal data
- it does not load code from elsewhere at run time, such as a script fetched from a URL

Approve a submission by commenting `/approve` on its issue. Text after the command on the same line is fine, such as `/approve thanks!`. The workflow checks three things first:

- the person commenting can write to this repository
- the pull request is the one the workflow opened for that issue
- the pull request has not changed since the comment, so an approval covers only code that was there to read

It then merges the pull request, rebuilds the index and closes the issue. A reaction on the comment shows the result: a rocket for merged, and a confused face with a reply when it could not merge. Merging the pull request by hand works too.

Close the pull request to turn a submission down, with a comment that says why. The author can publish a fixed version, which opens a new submission.

To take a plugin or profile down, delete its folder in a pull request. The index workflow drops it from `index.json`. Copies already installed stay on users' machines.

## Set up the repository

The workflows need three things, set once.

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
