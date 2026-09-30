# Handbook

The full documentation of Proteus, in a panel in the right dock. **Ctrl+Shift+H** shows it, and **Shift+F1** goes straight to any page or heading.

It shows three kinds of pages:

- The app's own chapters, from `docs/handbook/` in the app.
- The pages every plugin keeps in a `handbook` folder of its own, or adds from code through the `handbook` service.
- The Reference, built from the app's `types/` files, and any plugin's `types` folder, as the app runs.

Search matches titles, headings and text. Examples are colored and have a **Copy** button, links move between pages, and any page opens in a tab for a long read.

## Permissions

`net`, only to open a web link from a page in the browser. The Handbook reads the workspace, which every plugin may, and writes nothing but the page it last showed.

## For plugin authors

Put Markdown files in a `handbook` folder in your plugin's folder, and they show up as pages. `handbook/writing-pages.md` here explains the front matter, links and examples, and it is a page in the Handbook too.

## Layout

| Path | What it holds |
|------|---------------|
| `init.lua` | The panel, finding pages, and the `handbook` service |
| `lib/page.lua` | Reading a page: front matter, headings and anchors, links |
| `lib/render.lua` | The HTML for code blocks and links |
| `lib/highlight.lua` | Coloring code |
| `lib/reference.lua` | Turning a type file into a page |
| `lib/search.lua` | Search |
| `lib/library.lua` | Every page, sorted into sections |
| `types/handbook.lua` | Types for the `handbook` service |
| `handbook/` | The Handbook's own pages |
| `tests/` | Tests for everything in `lib/` |
