---
title: Using the Handbook
section: Start here
order: 5
keywords: help docs documentation search find panel shortcut
---

# Using the Handbook

The Handbook is the documentation of Proteus, in a panel in the right dock. It holds the app's own chapters, pages from every plugin that has them, and a reference built from the app's types.

**Ctrl+Shift+H** shows or hides it. **Help > Handbook** does the same.

## Finding a page

- Type in the search box at the top. Titles come first, then headings, then pages that mention every word, with the line that matched. **Enter** opens the first result, and **Escape** clears the search.
- **Shift+F1**, or **Help > Handbook: Go to a Page…**, lists every page and heading in the palette box.
- The list button beside the search box shows the contents: every page, grouped into sections.

## Reading a page

- The line above the title names the section and the plugin the page comes from. **Off** means that plugin is not running in this window, so what the page describes is not here right now.
- **On this page** lists the page's headings. A click jumps to one.
- **Copy** above an example puts its code on the clipboard.
- A link to another page opens it in the panel. A link marked **↗** opens in the browser.
- The arrows go back and forward through the pages seen.
- **Previous** and **Next** at the bottom walk through the Handbook in order.
- The button at the right of the search box opens the page in a tab, which suits a long read.

## The reference

The **Reference** section is built from the type files in `types/`, the same ones the Lua language server reads, so it always matches the app. It has a heading for every class, alias and function. A plugin that ships a `types` folder gets reference pages of its own.

## Adding pages

Any plugin can add pages. See [Writing handbook pages](writing-pages.md).

## From another plugin

A plugin can open the Handbook at a page, such as from a help button, through the `handbook` service:

```lua
local handbook = app.try_use ('handbook')
if handbook then
  handbook.open ('core.commands/commands#commands.register')
end
```

List `handbook` in `optional`, so it starts first when the profile runs it. `handbook.find (query)` searches the pages, and `handbook.pages ()` lists them.

| Command | Key | What it does |
|---------|-----|--------------|
| `handbook.show` | **Ctrl+Shift+H** | Shows or hides the panel |
| `handbook.find` | **Shift+F1** | Goes to a page or heading from the palette box |
| `handbook.search` | | Puts the cursor in the search box |
| `handbook.contents` | | Shows the contents |
