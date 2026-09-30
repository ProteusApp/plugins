# TOML

TOML support for the Proteus code editor, built on [Taplo](https://taplo.tamasfe.dev), the language server behind VS Code's Even Better TOML.

## What it does

- **Completion, hover help and checks** from JSON schemas. A file gets a schema from SchemaStore's catalog of common files, such as `Cargo.toml` and `pyproject.toml`, or from a `schema` file association that any plugin adds.
- **Formatting.** Format Document (Shift+Alt+F) runs `taplo fmt`, with the project's `.taplo.toml` when it has one.

The language server starts when the first TOML file opens.

## What it needs

Nothing to install. When `taplo` is not on the PATH, the plugin offers to download the official release, checked against its pinned checksum. `cargo install taplo-cli --locked` or `scoop install taplo` puts one on the PATH instead.

## Schemas for other plugins

A plugin gives its own TOML files completion and checks by adding a file association, with no need to know this plugin exists:

```lua
app.use ('files').associate ({
  kind = 'schema',
  pattern = 'myplugin.toml',
  value = 'https://example.com/myplugin.schema.json',
})
```

List `core.files` in the plugin's `depends`. `lang.rust` does this for `Cargo.toml` and Rust's other TOML files.

## Settings

| Setting | Default | What it does |
|---------|---------|--------------|
| `toml.enabled` | `true` | Runs the TOML language server. |
| `toml.schema_catalog` | `true` | Fetches schemas for common files from schemastore.org. |
| `toml.format` | `true` | Formats TOML files with Taplo. |
