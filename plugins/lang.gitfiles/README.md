# Git Files

Support for Git's own files and GitHub's in the Proteus code editor.

## What it does

- **Languages** for `.gitignore`, `.gitattributes` and `.gitconfig`, so their comments are colored. Ignore files written the same way, such as `.dockerignore`, `.npmignore`, `.prettierignore`, `.eslintignore`, `.stylelintignore` and `.vscodeignore`, open as `.gitignore`. `.gitmodules` opens as `.gitconfig`.
- **Help in .gitignore.** Completion offers common patterns, such as `node_modules/` and `.DS_Store`. Hovering a line says what it matches: whether it holds only folders, whether it is tied to this folder, and what `!`, `**`, `*` and `?` do in it.
- **Help in .gitattributes.** Completion offers attributes, such as `text`, `eol`, `binary`, `diff`, `merge`, `filter`, `export-ignore` and GitHub's `linguist-` attributes, and then their values, such as `eol=lf` or `filter=lfs`. Hovering an attribute says what it does.
- **Add a .gitignore Template…** picks a template for a language, an editor or a system, such as Node, Python, Rust, macOS or VS Code. It adds the template to the `.gitignore` in front, or else to the one at the top of the open folder, and makes that file when there is none. Lines the file holds already are not added twice.
- **Add This File to .gitignore** adds the file in front to the `.gitignore` of its repository.
- **Schemas for GitHub's files**: workflows, `action.yml`, `dependabot.yml`, issue and discussion forms, `FUNDING.yml`, `release.yml` and more, from schemastore.org.
- **GitHub Actions completion** in workflows and `action.yml`. After `uses:` it offers popular actions with their newest major version, such as `actions/checkout@v7`. After `owner/repo@` it asks GitHub for the repository's tags, newest first. Inside `${{ }}` and after `if:` it offers contexts such as `github` and `runner`, their properties, the file's step and job ids, and functions such as `contains` and `hashFiles`, each with a short note on what it does.
- **Icons** for these files in every icon pack, unless the pack has its own.

The languages, the commands and the file associations work on their own. The checks against GitHub's schemas and the Actions completion need a YAML language server, such as the one `lang.yaml` runs.

## Coloring

A `#` line shows in the comment color, and so does a `;` line in a Git config file. A pattern such as `**/*.log` stays a pattern. A Proteus without comment marks for languages colors these files with its rules for C instead. There `/*` starts what C reads as a block comment, and the rest of the file shows in the comment color.

## Permissions

- `files` lets the plugin use the `editor` service, for completion and hover help, and read and write the `.gitignore` the commands change.
- `net` lets Actions completion ask GitHub's API for an action's tags. GitHub answers 60 such requests an hour from one address, so each answer is kept until Proteus closes.
