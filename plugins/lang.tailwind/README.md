# Tailwind CSS

Tailwind CSS class names in the Proteus code editor, from [Tailwind's own language server](https://github.com/tailwindlabs/tailwindcss-intellisense), the one behind VS Code's Tailwind CSS IntelliSense. It works with Tailwind 4 and Tailwind 3.

## What it does

- **Class completion** inside `class="..."`, `className="..."` and `@apply`. Each class shows the CSS it makes, and each color class shows its color value. Variants such as `hover:` and `md:` come too.
- **Problems** in the Problems panel, such as two classes that set the same property (`p-2 p-4`), an `@apply` of a class that does not exist, or a variant in an odd order.

Classes complete in `.html`, `.htm`, `.vue`, `.svelte`, `.css`, `.scss`, `.js`, `.ts`, `.jsx`, `.tsx`, `.md` and `.mdx` files.

The server starts when the first such file opens, and only when the open folder uses Tailwind. A folder does when it has a `tailwind.config.js` file (or `.cjs`, `.mjs`, `.ts`), or a stylesheet with `@import "tailwindcss"`, or `tailwindcss` in a `package.json`. The server then finds each Tailwind project in the folder on its own.

## It works beside other language plugins

Other plugins own the languages classes live in: `lang.html`, `lang.css`, `lang.sass`, `lang.javascript`, `lang.typescript`, `lang.react` and `lang.markdown`. The editor keeps one helper per language, so this plugin never takes theirs. It adds its classes to their completion, and they show first.

This has three results.

- **Classes need the host's language server.** Completion appears in a file only while that language's own server runs. HTML's server starts with an `.html` file, so a `.vue` or `.svelte` file gets classes once an `.html` file has opened.
- **No hover help.** Hovering a class does not show its CSS, since only the language's owner answers hovers. The CSS shows in the completion list instead.
- **No color swatches.** The editor shows no colored squares beside color classes.

The CSS shows for the first matches in the list. The server sends every class each time, more than twenty thousand in Tailwind 4, so asking about each one would be too slow.

## What it needs

- **Node.js** on the PATH.
- **The language server.** `npm install --global @tailwindcss/language-server` installs it. A copy in the project's own `node_modules` wins over the global one.
- **The project's own `tailwindcss` package**, installed with `npm install`. Tailwind 3 needs it to read `tailwind.config.js`. Tailwind 4 uses it when it is there, and the server's built-in copy otherwise.

The Tools panel shows the server's state. **Tailwind CSS: Restart the Language Server** starts it again, and looks for Tailwind in the folder again.

## Settings

| Setting | Default | What it does |
|---------|---------|--------------|
| `tailwind.enabled` | `true` | Runs the Tailwind CSS language server. |
| `tailwind.class_attributes` | `["class", "className", "ngClass", "class:list"]` | The attributes whose values hold classes. |
| `tailwind.class_regex` | `[]` | Regular expressions for other places classes go, such as calls to `cva` or `clsx`. Each one captures the classes. A pair of them finds the call first, then the classes inside it. |
| `tailwind.lint` | `{}` | A level for each kind of problem: `"ignore"`, `"warning"` or `"error"`. `{"cssConflict": "error"}` makes conflicting classes errors. A kind left out keeps the server's level. |

The kinds of problem are `cssConflict`, `invalidApply`, `invalidScreen`, `invalidVariant`, `invalidConfigPath`, `invalidTailwindDirective` and `recommendedVariantOrder`.
