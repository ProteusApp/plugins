# Shell

Shell script support for the Proteus code editor, built on [bash-language-server](https://github.com/bash-lsp/bash-language-server), [ShellCheck](https://www.shellcheck.net) and [shfmt](https://github.com/mvdan/sh).

## What it does

- **Completion** of commands, builtins, keywords, and the variables and functions a script defines or sources.
- **Hover help.** A variable or function shows where it was defined. A command or builtin shows its `help` or `man` page, where the computer has one. Windows has neither, so there only the script's own names get help.
- **Go to definition** (F12) on a function or a variable.
- **Problems from ShellCheck** in the Problems panel (Ctrl+Shift+M), such as a variable that needs quotes. ShellCheck does not read zsh, so `.zsh` files, `.zshrc` and any script whose `#!` line runs zsh get no ShellCheck problems.
- **Formatting.** Format Document (Shift+Alt+F) runs shfmt. It follows the project's `.editorconfig` unless `shell.indent` says otherwise, and reads bash, POSIX or zsh from the file's name and its `#!` line.

The editor treats `.sh`, `.bash`, `.zsh`, `.bashrc`, `.zshrc` and `.profile` files as shell scripts. The language server starts when the first one opens. PowerShell is a different language, and this plugin does not cover it.

## What it needs

Node.js on the PATH. When the server is nowhere else, the first shell script file that opens has npm install bash-language-server 5.8.1 into the app's cache folder. The **Download missing tools** setting, `tools.download`, can make it ask first or never do it. To install it yourself instead:

```text
npm install --global bash-language-server
```

A project that has `bash-language-server` in its own `node_modules` uses that copy.

ShellCheck and shfmt each have a row in the **Tools** panel. When one is not on the PATH, the plugin offers to download its official release, checked against a pinned checksum. Both download on Windows, Linux and macOS, though not on Windows on ARM. There a package manager installs ShellCheck:

```text
brew install shellcheck
sudo apt install shellcheck
```

## Settings

| Setting | Default | What it does |
|---------|---------|--------------|
| `shell.enabled` | `true` | Runs the shell language server. |
| `shell.shellcheck` | `true` | Shows ShellCheck's problems. |
| `shell.format` | `true` | Formats shell scripts with shfmt. |
| `shell.indent` | `-1` | How shfmt indents. `-1` follows the project's `.editorconfig`, and uses tabs without one. `0` uses tabs, and a larger number uses that many spaces. A number of 0 or more replaces every shfmt setting in `.editorconfig`. |

## How it is built

`lib/server.lua` builds the language server's client from the app's `lsp` modules, since it drops ShellCheck's problems for zsh scripts, which `lib/dialect.lua` recognizes. It gives the server the ShellCheck that `lib/helper.lua` finds, as its `bashIde.shellcheckPath` setting, and tells the server again whenever that changes. explainshell stays off, so hover help never asks a web site. `lib/provider.lua` and `lib/completion.lua` fit completion items to the word before the cursor, such as the rest of an option after `ls --al`. `lib/format.lua` runs `shfmt --filename <file> -` with the text on standard input. `lib/release.lua` pins the downloads. `lib/program.lua` finds `node` and the server's script, since npm's files on Windows cannot start on their own, and `lib/launch.lua` lists where the script may be.
