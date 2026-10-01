# Font viewer

Opens font files in a tab that shows the font, instead of as text in the code editor. It works for TrueType and OpenType fonts (`ttf`, `otf`), collections of them (`ttc`, `otc`), and web fonts (`woff`, `woff2`).

## What it does

- **Names the font.** The top of the tab shows the family and the style in the font itself, with its version, its designer and its maker.
- **Shows its sizes**: units per em, the number of glyphs and characters, the ascender, the descender, the line gap, the x-height, the cap height and the weight.
- **A sample to type in.** The text box changes every sample on the page, and the slider beside it sizes the large one.
- **The sample at twelve sizes**, from 10 to 96 pixels.
- **The alphabet, digits and punctuation.**
- **Every character the font has**, each with its code, such as `U+0041`. A large font shows them 1500 at a time.
- **Each font of a collection.** A `ttc` file holds several fonts, and a picker shows each one.
- **Reads the file again** when it changes on disk, and when the reload button is pressed.

The font's copyright and license notes are at the bottom.

A WOFF2 file keeps its tables packed in a form that some versions of the app cannot unpack. There the font still draws, but the tab shows the file name in place of the font's names, and no list of characters.

## What it needs

Proteus 0.3.0 or newer, with web views that can read files from disk. The plugin asks for the `files` permission. It needs it to open fonts from the editor and to send each file to its page.

## Commands

| Command | What it does |
|---------|--------------|
| `fonts.reload` | Reads the font in front again. |

## Settings

| Setting | Default | What it does |
|---------|---------|--------------|
| `fonts.sample` | `The quick brown fox jumps over the lazy dog.` | The text a font shows when it opens, at the top and at each size. |
