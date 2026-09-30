---
title: Writing handbook pages
section: Writing plugins
order: 19
keywords: docs documentation contribute handbook page markdown front matter
---

# Writing handbook pages

Any plugin can add pages to the Handbook. A page is a Markdown file in a `handbook` folder inside the plugin's own folder. The Handbook finds it by itself, so the plugin needs no code and no dependency, and the page costs nothing when the Handbook is not installed.

```text
plugins/mine/my.clock/
  init.lua
  handbook/
    clock.md
    alarms.md
```

Each file is one page. Its id is the plugin's id and the file's name without `.md`, such as `my.clock/clock`. The app's own chapters live in `docs/handbook/`, and their ids start with `proteus/`, such as `proteus/first-plugin`.

A page from a plugin that is not running still shows, marked **Off**, so the Handbook documents every plugin the app has.

## Front matter

A page can start with a few settings between two `---` lines:

```markdown
---
title: Alarms
section: Clock
order: 20
keywords: timer alert reminder
---

# Alarms

An alarm rings once at the time it is set for.
```

| Key | What it sets |
|-----|--------------|
| `title` | The page's name in the contents and in search. Without it, the first `# ` heading names the page, then the file name. |
| `section` | The group the page is listed under. Without it, the plugin's name. |
| `order` | A number that sorts the page in its section, lowest first. It is 100 without one. A section sorts by the lowest `order` among its pages. |
| `keywords` | Words search finds the page by, beyond its title, headings and text. |

The app's own chapters use these sections and orders, so a plugin's page can sit beside them:

| Section | Orders |
|---------|--------|
| Start here | 1 to 9 |
| Writing plugins | 10 to 29 |
| The app table | 30 to 49 |
| Building screens | 50 to 69 |
| Commands, keys and settings | 70 to 79 |
| Editor and languages | 80 to 99 |
| Data and integrations | 100 to 119 |
| Profiles and the workspace | 120 to 139 |
| Nodal | 200 to 239 |
| Reference | 900 and up |

## Links

A link to another page names its file. A link to a heading adds `#` and the heading's anchor.

| Link | Goes to |
|------|---------|
| `[Alarms](alarms.md)` | A page of the same plugin |
| `[Setting one](alarms.md#setting-one)` | A heading on that page |
| `[Below](#setting-one)` | A heading on this page |
| `[Commands](core.commands/commands.md)` | Another plugin's page |
| `[Services](proteus/services-and-events.md)` | One of the app's chapters |
| `[Proteus.Commands](types/services.md#proteus.commands)` | The reference built from the app's types |
| `[lucide.dev](https://lucide.dev/icons)` | A web page, which opens in the browser |

A heading's anchor is its text in lower case, with spaces turned into `-` and every character other than letters, digits, `-`, `_` and `.` left out. `## Setting one` is `#setting-one`, and ``## `commands.register` `` is `#commands.register`.

## Code examples

A fenced block with a language shows as code, with a **Copy** button. Lua is colored.

````markdown
```lua
local status = app.use ('status')
status.add ({ text = 'Ready', align = 'right' })
```
````

Write examples a reader can paste and run. Each `lua` block should be complete Lua that parses on its own, with no `...` standing in for code. A block that only makes sense inside `activate` can use `app` as it is. Use `text` for a block that is not code, such as a folder tree.

## Pages from code

A page can also come from code, for text that changes while the app runs. List `handbook` in `optional`, then add the page through the `handbook` service:

```lua
---@type Proteus.Plugin
return {
  name = 'Build status',
  version = '1.0.0',
  optional = { 'handbook' },
  activate = function (app)
    local handbook = app.try_use ('handbook')
    if not handbook then
      return
    end
    local page = handbook.add ({
      id = 'status',
      title = 'Build status',
      section = 'Builds',
      markdown = '# Build status\n\nNothing has run yet.',
    })
    app.timer.after (5000, function ()
      page.set ('# Build status\n\nThe last build passed.')
    end)
  end,
}
```

The page goes away when the plugin stops. A plugin that starts before the Handbook, such as one that ran before the Handbook was installed, adds nothing until it starts again, which is why files suit pages that do not change.

`handbook.open ('my.clock/alarms#setting-one')` shows the Handbook at a page, which suits a help button. It returns false when there is no such page.

## House style

- Short, plain sentences that say what happens: "The page goes away when the plugin stops."
- One idea per page. Split a page that covers two things.
- Start with what the thing is for, then the smallest example that works, then the details.
- Show every option in a table or a list, with what it does.
- Name keys in **bold**, such as **Ctrl+Shift+P**, and menu paths the same way, such as **File > Open**.
