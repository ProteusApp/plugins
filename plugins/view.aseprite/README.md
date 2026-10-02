# Aseprite viewer

Opens [Aseprite](https://www.aseprite.org) sprites, `.aseprite` and `.ase` files, in a tab of their own. The plugin reads the file itself, so Aseprite does not need to be installed.

## What it does

- **Draws the sprite** with sharp square pixels, over a checkerboard in the colors of the theme. RGBA, grayscale and indexed sprites all work. So do layer opacity, cel opacity, groups and the blend modes.
- **Plays the frames**, each for its own duration. The timeline under the sprite plays and pauses, steps one frame at a time, and has a slider to go to any frame.
- **Plays a tag on its own.** The tag picker lists the sprite's tags. Each plays forward, in reverse or there and back, as it is set in Aseprite.
- **Hides and shows layers.** The layer list at the side shows every layer and group, with a box to hide or show each one. Hidden layers and reference layers start hidden, as they would in an export.
- **Zooms and moves.** The sprite starts fitted to the tab, grown by whole steps. Ctrl and the mouse wheel zoom around the pointer, and a drag moves the sprite.
- **Reads the file again** when it changes on disk, such as when Aseprite saves it, and when the reload button is pressed.

The bar shows the size of the sprite in pixels, its frames, its color mode, the size of the file and the zoom.

With the sprite clicked, these keys work: Space plays or pauses, the left and right arrows step through the frames, `+` and `-` zoom, `0` fits the sprite and `1` shows its actual size.

Tilemap layers do not draw, and the layer list says so. The hue, saturation, color and luminosity blend modes draw as normal.

## What it needs

Proteus 0.3.0 or newer, with web views that can read files from disk. The plugin asks for the `files` permission. It needs it to open sprites from the editor and to send each file to its page.

## Commands

| Command | What it does |
|---------|--------------|
| `aseprite.play` | Plays or pauses the sprite in front. |
| `aseprite.next_frame` | Shows the next frame. |
| `aseprite.previous_frame` | Shows the frame before. |
| `aseprite.fit` | Fits the sprite to the tab. |
| `aseprite.actual_size` | Shows the sprite at its actual size. |
| `aseprite.zoom_in` | Zooms in. |
| `aseprite.zoom_out` | Zooms out. |
| `aseprite.reload` | Reads the sprite in front again. |

## Settings

| Setting | Default | What it does |
|---------|---------|--------------|
| `aseprite.autoplay` | `true` | Starts playing a sprite with more than one frame as soon as it opens. |
| `aseprite.checkerboard` | `true` | Shows a checkerboard behind the clear parts of a sprite. |
