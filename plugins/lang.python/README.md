# Python

Python support for the Proteus code editor, built on [basedpyright](https://docs.basedpyright.com) for types and [Ruff](https://docs.astral.sh/ruff/) for linting and formatting.

## What it does

- **Completion, hover help and go to definition** from basedpyright. F12 or Ctrl+click jumps to where a name is defined, in the project or in an installed package.
- **Type problems** from basedpyright, under the `python` source in the Problems panel (Ctrl+Shift+M).
- **Lint problems** from Ruff, under the `ruff` source. Ruff runs as a second language server beside basedpyright.
- **Formatting.** Format Document (Shift+Alt+F) runs `ruff format`.
- **Organize Imports** and **Fix All Ruff Problems** apply Ruff's own fixes to the file in front.
- **The project's Python.** basedpyright follows imports into the packages of the project's interpreter.

Both servers start when the first Python file opens.

## The project's Python

The plugin takes the first Python it finds:

1. The `python.interpreter` setting, for every folder.
2. The one picked with **Python: Select Interpreter** for this folder.
3. A `.venv` or `venv` folder in the project.
4. `python` or `python3` on the PATH.

**Select Interpreter** lists the virtual environments in the project and the Pythons on the PATH. It also takes any other path, and **Find automatically** forgets the pick.

## Project settings

basedpyright reads `pyrightconfig.json`, or `[tool.basedpyright]` in `pyproject.toml`. Their type checking mode wins over the `python.type_checking` setting. Ruff reads `ruff.toml`, `.ruff.toml`, or `[tool.ruff]` in `pyproject.toml`, for its problems and for formatting.

## What it needs

basedpyright, from npm or from pip:

```text
npm install --global basedpyright
pip install basedpyright
```

A copy installed into the project's virtual environment comes first, then the project's own `node_modules`, then the PATH. An npm copy also needs Node.js.

Ruff, from pip, uv or Homebrew:

```text
pip install ruff
uv tool install ruff
```

A Ruff in the project's virtual environment comes first, then the PATH. On Windows, when there is none, the plugin offers to download the official release, checked against its pinned checksum. Ruff ships Linux and macOS files only in a form the download cannot open, so there it must be installed.

The **Tools** panel shows each server's state, version and log, with buttons to start, stop and look again.

## Settings

| Setting | Default | What it does |
|---------|---------|--------------|
| `python.enabled` | `true` | Runs basedpyright. |
| `python.interpreter` | empty | The Python to check code against, for every folder. Empty finds one as above. |
| `python.type_checking` | `standard` | How strictly basedpyright checks types: `off`, `basic`, `standard`, `strict`, `recommended` or `all`. |
| `python.ruff` | `true` | Runs Ruff for lint problems. |
| `python.format` | `true` | Formats Python files with Ruff. |

## How it is built

The editor keeps one source of completion and hover help per language, and basedpyright is it, through the app's `lsp.client`. `lib/ruff.lua` builds Ruff's client from the app's `lsp` modules instead. It keeps the open files in step and lists the problems, and gives the editor no help of its own. `lib/edits.lua` applies Ruff's fixes to a file's text.
