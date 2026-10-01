# CSS

CSS and Less support for the Proteus code editor, built on `vscode-css-language-server`, the language server behind VS Code's own CSS help.

## What it does

- **Completion** of properties, values, at-rules, and the variables a file defines.
- **Hover help** for a property, with the browsers that support it and a link to MDN.
- **Problems** in the Problems panel, such as an unknown property or an empty rule.
- **Go to definition** (F12) for a custom property, a Less or SCSS variable, and the file an `@import` names.

It works in `.css` and `.less` files, and in `.scss` files when no other plugin serves them. The language server starts when the first of those files opens.

A completed property stops after the colon, so the cursor waits where the value goes.

## What it needs

Node.js, and the servers from npm:

```sh
npm install --global vscode-langservers-extracted
```

A copy in the open folder's `node_modules` wins over the global one. The Tools panel shows CSS as missing until one is installed. **Look again** finds it after the install.

## Formatting

Prettier comes with Proteus and already formats `.css`, `.less` and `.scss` files, so this plugin adds no formatter.

## With the Sass plugin

The editor puts `.css`, `.scss` and `.less` files in one language, `css`, and keeps one helper for each language. So this plugin owns that language, and hands each file on by its extension. The Sass plugin, `lang.sass`, claims `.scss` files, and Some Sass helps with them. This plugin's server keeps `.css` and `.less` files. Both plugins run at once, in either order, and neither takes the other's files.

While Some Sass is not running, this plugin's server helps with `.scss` files instead.

Another plugin claims files the same way, through the `css` service. It lists `lang.css` in `optional` and needs the `files` permission:

```lua
local css = app.try_use ('css')
if css then
  local give_back = css.route ({
    extensions = { 'scss' },
    factory = function (doc)
      -- Return a provider for this file, or nil.
    end,
  })
end
```

The claim goes back when that plugin stops, or when it calls `give_back ()`.

## Settings

| Setting | Default | What it does |
|---------|---------|--------------|
| `css.enabled` | `true` | Runs the CSS language server. |
| `css.validate` | `true` | Shows syntax errors and the lint rules below in the Problems panel. |
| `css.lint.unknown_properties` | `warning` | A property name CSS does not know, such as a typo. |
| `css.lint.unknown_at_rules` | `warning` | An at-rule CSS does not know. Set it to `ignore` for Tailwind rules such as `@apply`. |
| `css.lint.empty_rules` | `warning` | A rule with nothing between its braces. |
| `css.lint.duplicate_properties` | `ignore` | The same property twice in one rule. |
| `css.lint.important` | `ignore` | Any use of `!important`. |
| `css.lint.id_selector` | `ignore` | A selector that names an id, such as `#main`. |

Each lint rule is `ignore`, `warning` or `error`, and applies to CSS, Less and SCSS alike.
