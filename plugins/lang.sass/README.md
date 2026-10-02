# Sass

Sass support for the Proteus code editor, built on [Some Sass](https://wkillerud.github.io/some-sass/), a language server for SCSS and the indented Sass syntax.

## What it does

- **Completion** for variables, mixins, functions and placeholders, including the ones other files bring in with `@use`, `@forward` and `@import`.
- **Hover help** with the SassDoc comments of a name, and the documentation of Sass's built-in modules.
- **Go to definition** (F12) across files.
- **Problems** in the Problems panel, such as a deprecated function.

It works in `.scss` files and in indented `.sass` files. Plain `.css` files get the same help when `sass.css` is on and the CSS plugin is not running. `.less` files are left alone, since Some Sass does not read Less.

The language server starts when the first `.scss` or `.sass` file opens. Sass files also get a pink brush icon, unless the icon pack has its own.

## What it needs

Node.js 20 or later on the PATH. When the server is nowhere else, the first Sass or SCSS file that opens has npm install some-sass-language-server 2.3.8 into the app's cache folder. The **Download missing tools** setting, `tools.download`, can make it ask first or never do it. To install it yourself instead:

```sh
npm install --global some-sass-language-server
```

## Formatting

Prettier comes with Proteus and already formats `.scss` files, so this plugin adds no formatter. Nothing formats indented `.sass` files, since Prettier does not read that syntax.

## With the CSS plugin

The editor puts `.scss`, `.css` and `.less` files in one language, `css`, and keeps one helper for each language. The CSS plugin, `lang.css`, owns that language when it runs. It hands `.scss` files to this plugin, and keeps `.css` and `.less` files for its own server. So both plugins can run at once, and neither takes the other's files.

When the profile runs both, lang.css starts first. When it is switched on later, this plugin hears it arrive and moves `.scss` files over to it then. While Some Sass is not running, lang.css's own server helps with `.scss` files instead.

Without lang.css, this plugin becomes the helper for `css` once its server starts. It gives no help in `.css` files while `sass.css` is off.

## Settings

| Setting | Default | What it does |
|---------|---------|--------------|
| `sass.enabled` | `true` | Runs the Sass language server. |
| `sass.css` | `false` | Uses Some Sass for plain `.css` files too, while lang.css is not running. |
| `sass.load_paths` | `[]` | Folders, from the top of the open folder, where `@use` and `@import` look for files. `node_modules` is always one. |
| `sass.use_only` | `false` | Suggests only names from files loaded with `@use` or `@forward`. |
