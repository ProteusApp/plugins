# Minimap

Shows the file in front in miniature, in a panel in the right dock. It works in the Code Editor and in the Plugin Editor, since both edit files with the same editor.

The picture colors comments, strings, keywords, constants and numbers with the theme's code colors. It redraws a moment after the text changes, and when another tab comes to the front.

A box shades the lines on screen and follows the editor as it scrolls. A click on the picture scrolls the editor so that line sits in the middle of the screen, and dragging down the picture keeps scrolling. The cursor stays where it was. When the file is taller than the panel, the picture scrolls along with the editor so the box stays in sight.

Shading the lines on screen needs a Proteus whose editor says where it is scrolled. An older Proteus shows no box. There a click moves the cursor to the line instead, and a band marks that line.

A file longer than 10,000 lines is drawn up to line 10,000, and a note under the picture says so.

## Settings

| Key | What it does | Default |
|-----|--------------|---------|
| `minimap.size` | How tall each line of the picture is: `small` is 2 pixels, `medium` is 3 and `large` is 4. | `medium` |

## Permissions

- `files` lets the plugin use the `editor` service, which hands over the text of the file in front. The plugin only reads that text to draw it. It reads and writes no files itself.
