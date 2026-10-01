# Project Plugins

Builds Proteus plugins in the open folder's `.proteus/plugins`. A plugin there belongs to the project: it starts for everyone who opens the folder and trusts it.

- **Plugins > New Plugin in This Folder…** (**Ctrl+Alt+N**, `code.plugin_new`) makes one from a template and opens its `init.lua`.
- **Plugins > Save and Reload This Plugin** (**F5**, `code.plugin_reload`) reloads the plugin of the file in front.
- `code.plugin_list` opens one of the folder's plugins.
- A **Proteus Plugins** section under the explorer's tree lists them, with a dot for running or failed. A plugin that fails to start says so, with a way to its code.

The Plugin Editor's `proteus.dev.tools` uses the same keys for the workspace, so the two never run together. Before 0.3.0 the commands were `project.plugin_new`, `project.plugin_reload` and `project.plugin_list`.

## Permissions

- `files` writes the folder's `.proteus` files on disk before they are in use, and opens them in the editor. The `project` and `editor` services need it too.
- `workspace` writes them through the folder's layer while it is in use, so a new plugin starts at once.
- `kernel` reloads the folder's plugins, and trusts the folder so its plugins start.
