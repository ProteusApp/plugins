# Markdown

Markdown support for the Proteus code editor, built on [Marksman](https://github.com/artempyanykh/marksman), with a live preview.

## What it does

- **Completion, go to definition and problems** from Marksman. `[[` or `](#` offers the headings of the folder's files. **F12** on a link jumps to its heading. A link to a heading that is not there shows in the Problems panel.
- **A live preview.** It renders the file a moment after the typing stops. Headings, lists, task lists, tables, quotes and code blocks show with the theme's colors.

The language server starts when the first Markdown file opens. Prettier ships inside Proteus and formats Markdown already, so this plugin adds no formatter.

## The preview

| Command | Key | What it does |
|---------|-----|--------------|
| **Markdown: Open Preview** | Ctrl+Shift+V | Opens the preview in a tab of its own, in place of the code. |
| **Markdown: Open Preview to the Side** | Ctrl+Alt+V | Opens the preview inside the editor, beside the text. |
| **Markdown: Close Preview to the Side** | | Closes it again. So does the X on its top bar. |

Both commands are in the **View** menu too. Proteus has no two-key shortcuts, so VS Code's Ctrl+K V is Ctrl+Alt+V here.

The preview at the side moves with the editor into each document that comes to the front. It shows the Markdown file in front, and hides for any other file. Drag its left edge to make it wider or narrower. It stays open the next time Proteus starts.

The preview tab switches to each Markdown file that comes to the front, unless `markdown.preview_follow` is off.

While the editor scrolls, the preview scrolls to the same place. It goes by the headings, so a long section with no heading scrolls in proportion to its length.

Links in the preview work like this:

- A link to a heading, such as `#setup`, scrolls the preview to it.
- A link to another file, such as `docs/guide.md` or `../README.md#install`, opens that file in the editor. A link to a heading in it scrolls the preview there.
- A web link opens in the browser.

### Images

The preview cannot read a picture from a file by its path, and Proteus does not load pictures from the web. So an image shows as a box with its text, and its address shows when the pointer rests on it. A picture written into the file itself, as a `data:image/...` address, shows as it is.

### What it leaves out

The preview renders Markdown with Proteus's safe renderer. It leaves out scripts, styles, forms and embedded pages, and a link written in HTML loses its address. Code blocks show without colors.

## What it needs

Nothing to install. When `marksman` is not on the PATH, the plugin offers to download the official release, checked against its pinned checksum. `brew install marksman` or `scoop install marksman` puts one on the PATH instead.

## Settings

| Setting | Default | What it does |
|---------|---------|--------------|
| `markdown.enabled` | `true` | Runs the Markdown language server. |
| `markdown.preview_follow` | `true` | The preview tab switches to each Markdown file that comes to the front. |
| `markdown.preview_sync_scroll` | `true` | Scrolls the preview along with the editor. |
| `markdown.preview_width` | `520` | The width of the preview at the side, in pixels, from 240 to 1600. |

## Older versions of Proteus

The preview to the side sits inside the editor on a Proteus whose editor has room at its sides for plugins. An older Proteus shows it in the right dock instead.

## Permissions

- `process` runs Marksman, and downloads it when it is missing.
- `files` lets Marksman read the folder's Markdown files. It also lets the plugin use the `editor` service, which hands over the text the preview shows.
- `net` opens a web link from the preview in the browser. The plugin fetches nothing from the web.
