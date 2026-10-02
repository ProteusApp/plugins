# Plugin Template

A start for a plugin of your own. It has one of each part most plugins need, and it keeps a list of greetings to show how they fit together:

- a command, **Greetings: Say a Greeting**, in the palette and the Plugins menu
- a setting, `template.greeting`, the word each greeting starts with
- a panel in the right dock, built with the ui library, that lists the greetings
- a service, `template`, that lets another plugin say one, with its type in `types/template.lua`
- a folder of its own, `template/`, where each greeting is written to `greetings.md`
- tests in `tests/`, and a Handbook page in `handbook/`

In the Plugin Editor, **New Plugin** and its **Template** start copy it under your own id, with every name changed to yours. The Handbook page **The plugin template** explains each part.

## Layout

| Path | What it holds |
|------|---------------|
| `init.lua` | The command, the setting, the panel and the service |
| `lib/greetings.lua` | Making a greeting, keeping the list, and writing it as Markdown |
| `types/template.lua` | The type of the `template` service |
| `tests/template.test.lua` | Tests of the logic and of what the plugin adds when it starts |
| `handbook/template.md` | Its page in the Handbook |

## Permissions

None. It writes only in `data/proteus.template/` and the `template` folder it claims.
