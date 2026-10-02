---
title: The plugin template
section: Writing plugins
order: 15
keywords: template starter example skeleton new plugin copy command setting panel view service types folder tests handbook readme
---

# The plugin template

The Plugin Template is a small plugin with one of each part most plugins need. Start from a copy of it when a plugin will grow past one command. It keeps a list of greetings, which is just enough to show how the parts fit together.

## Start a plugin from it

In the Plugin Editor, **Plugins > New Plugin** (**Ctrl+Alt+N**) and the **Template** start copy it into `plugins/mine/<your id>`, with every name changed to yours. With the id `my.clock`, the command `template.greet` becomes `clock.greet`, the service `template` becomes `clock`, the class `Template.Service` becomes `Clock.Service`, and the folder `template/` becomes `clock/`. The README and this page start over as short drafts for you to fill in.

To install it as it is and try it first, find **Plugin Template** in the **Marketplace**.

## What each part shows

| Part | Where | What it shows |
|------|-------|---------------|
| Command | `init.lua` | `commands.register` adds **Greetings: Say a Greeting** to the palette and the Plugins menu |
| Setting | `init.lua` | `settings.define` adds `template.greeting`, the word each greeting starts with, to **Settings** |
| Panel | `init.lua` | `views.add` puts a view built with the ui library in the right dock |
| Service | `init.lua`, `types/template.lua` | `app.provide` offers `greet` and `list` to other plugins, and the type file describes them |
| Folder | `init.lua` | `folders = { 'template' }` claims a workspace folder, and each greeting is written to `template/greetings.md` |
| Logic | `lib/greetings.lua` | The part that touches nothing on screen, kept apart so tests can load it |
| Tests | `tests/template.test.lua` | Checks the logic, and starts the plugin on a stand-in app to check what it adds |
| Handbook page | `handbook/template.md` | This page. Any Markdown file in `handbook/` is a page |
| README | `README.md` | What the plugin does and what it needs, for the marketplace and the registry |

## Names

A plugin from the marketplace, or one of your own, runs restricted. It names its commands, settings, services and events after the first or the last part of its id, so `my.clock` may use `my` or `clock`. The template uses the last part, `template`. The Handbook's [Permissions](proteus/permissions.md) page explains the rule.

## Using the service

Another plugin lists `proteus.template` in `optional`, and asks for the service:

```lua
local greetings = app.try_use ('template') --[[@as Template.Service?]]
if greetings then
  app.log (greetings.greet ('Ada')) -- Hello, Ada!
end
```

The Reference has a page for `types/template.lua`, built while the plugin runs.

## Testing

The registry runs every `tests/*.test.lua` with `npm test`. A test file gets `test`, `eq` and `ok`, and `require` loads a module from the plugin's own folder, such as `require ('lib.greetings')` or `require ('init')`.

```lua
local greetings = require ('lib.greetings')

test ('no name greets the world', function ()
  eq (greetings.make ('Hello', nil), 'Hello, world!')
end)
```

## Publishing

Raise `version` in `init.lua`, then **Plugins > Publish Plugin**. [Publishing](proteus/publishing.md) covers the review.
