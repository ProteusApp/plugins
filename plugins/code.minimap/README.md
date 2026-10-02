# Minimap

Shows the file in front in miniature, inside the editor at its right or left edge. It works in the Code Editor and in the Plugin Editor, since both edit files with the same editor.

The picture colors comments, strings, keywords, constants and numbers with the theme's code colors. It redraws a moment after the text changes, and when another tab comes to the front.

A box shades the lines on screen and follows the editor as it scrolls. A click on the picture scrolls the editor so that line sits in the middle of the screen, and dragging down the picture keeps scrolling. The cursor stays where it was. When the file is taller than the editor, the picture scrolls along with it so the box stays in sight.

Selected lines show as full-width bands in the accent color. Lines with problems from the diagnostics service show as red bands for errors, yellow for warnings, and blue for hints and notes. A line with several problems shows the worst one.

A file longer than 10,000 lines is drawn up to line 10,000, and a note under the picture says so. **Toggle Minimap** in the command palette hides it and brings it back.

## Settings

| Key | What it does | Default |
|-----|--------------|---------|
| `minimap.show` | `always`, `hover` to show it only while the pointer is over it, or `off`. While it waits for the pointer, clicks go through to the text. | `always` |
| `minimap.placement` | `over` lays it over the edge of the text. `beside` gives it room of its own, so the text gets narrower. | `over` |
| `minimap.side` | The edge it sits at: `right` or `left`. | `right` |
| `minimap.width` | Its width in pixels, from 40 to 400. | 120 |
| `minimap.size` | How tall each line of the picture is: `small` is 2 pixels, `medium` is 3 and `large` is 4. | `medium` |
| `minimap.slider` | `always` shades the lines on screen all the time. `hover` shades them only while the pointer is over the minimap. | `always` |
| `minimap.colors` | Colors the code. Off, it is drawn in one color. | true |
| `minimap.marks` | Shows the selection and problems as bands. | true |

## Older versions of Proteus

The minimap sits inside the editor on a Proteus whose editor has room at its sides for plugins. An older Proteus shows it in the right dock instead. The box and the selection bands need an editor that says where it is scrolled and what is selected. Without that, a click moves the cursor to the line, and a band marks that line.

## Permissions

- `files` lets the plugin use the `editor` service, which hands over the text of the file in front. The plugin only reads that text to draw it. It reads and writes no files itself.
