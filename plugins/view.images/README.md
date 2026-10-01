# Image viewer

Opens pictures in a tab of their own, instead of as text in the code editor. It works for PNG, JPEG (`jpg`, `jpeg` and `jfif`), GIF, WebP, AVIF, BMP, ICO and SVG files.

## What it does

- **Fits the picture to the tab** when it opens. A photo never grows past its own size, so it stays sharp. Pixel art grows by whole steps, so every pixel stays the same size.
- **Zooms and moves.** Ctrl and the mouse wheel zoom around the pointer. The bar has buttons to fit, to show the actual size, and to zoom in and out. A drag moves the picture, and so does the wheel.
- **Shows clear parts** over a checkerboard in the colors of the theme.
- **Sharp square pixels** for pixel art. They turn on by themselves for pictures up to 256 pixels across, and the grid button in the bar turns them on or off.
- **Plays animations.** Animated GIF and WebP files play as they would in a browser.
- **Opens an SVG as text.** The **View as Text** button opens the file in the code editor.
- **Reads the file again** when it changes on disk, and when the reload button is pressed.

The bar shows the size of the picture in pixels, the size of the file and the zoom.

With the picture clicked, these keys work: `+` and `-` zoom, `0` fits the picture, `1` shows its actual size, and `P` turns sharp pixels on or off.

## What it needs

Proteus 0.3.0 or newer, with web views that can read files from disk. The plugin asks for the `files` permission. It needs it to open pictures from the editor and to send each file to its page.

## Commands

| Command | What it does |
|---------|--------------|
| `images.fit` | Fits the picture to the tab. |
| `images.actual_size` | Shows the picture at its actual size. |
| `images.zoom_in` | Zooms in. |
| `images.zoom_out` | Zooms out. |
| `images.toggle_pixelated` | Turns sharp square pixels on or off. |
| `images.view_as_text` | Opens the SVG in front in the code editor. |
| `images.reload` | Reads the picture in front again. |

## Settings

| Setting | Default | What it does |
|---------|---------|--------------|
| `images.checkerboard` | `true` | Shows a checkerboard behind the clear parts of a picture. |
| `images.pixelated` | `auto` | Draws pixels as sharp squares: `auto` for pictures up to 256 pixels across, `always`, or `never`. |
