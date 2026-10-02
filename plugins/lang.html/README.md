# HTML

HTML support for the Proteus code editor, built on the HTML language server from VS Code, as the npm package [vscode-langservers-extracted](https://github.com/hrsh7th/vscode-langservers-extracted) ships it.

## What it does

- **Completion and hover help** for tags, attributes and their values. Inside `<style>` and `<script>`, the server completes and explains CSS and JavaScript too.
- **Problems** in the page, and in the CSS and JavaScript inside it, in the Problems panel.
- **An HTML5 page.** On a line of its own, `!` or `html:5` completes to a whole page with its head and body. Press Ctrl+Space after `!`, since a lone `!` does not open the list by itself.
- **Closing tags.** After `</`, the first item in the list closes the element that is still open. Type the first letter of the name, or press Ctrl+Space. The editor does not tell a plugin when `>` is typed, so the tag does not close by itself.
- **A live preview.** **HTML: Open Preview** shows the HTML file in front, rendered, in a panel beside the code. It shows the file again a moment after typing stops, and follows the tab in front. While a file of another kind is in front, it keeps the last page.

Prettier ships with Proteus and formats HTML already, so the server's own formatter stays off.

The language server starts when the first `.html` or `.htm` file opens.

## What the preview can show

The page runs in a web view, which loads nothing by address. Inline `<style>` and `<script>` work. Linked stylesheets, scripts, images and fonts do not load, and a note above the page says so. An image written into the page as a `data:` address does show.

The page's scripts do not run unless `html.preview_scripts` is on. Off, the preview takes the script elements out, and stops attributes such as `onclick` as well.

## What it needs

Node.js, and the server from npm:

```sh
npm install --global vscode-langservers-extracted
```

This puts `vscode-html-language-server` on the PATH. On Windows, npm makes a `vscode-html-language-server.cmd` file, and the plugin looks for that one.

## Vue and Svelte files

The editor reads `.vue` and `.svelte` files as HTML. They never start the server. But while it runs, it helps in them as if they were plain HTML, since a language server serves every file of its language. The skeleton, the closing tag and the preview are for `.html` and `.htm` files alone.

## Settings

| Setting | Default | What it does |
|---------|---------|--------------|
| `html.enabled` | `true` | Runs the HTML language server. |
| `html.validate` | `true` | Lists problems in the CSS and JavaScript inside `<style>` and `<script>`. |
| `html.preview_scripts` | `false` | Lets the page's own scripts run in the preview. |

## Permissions

- `process` runs the language server.
- `files` lets the plugin use the `editor` service, which hands over the text of open files, for the server and the preview.
