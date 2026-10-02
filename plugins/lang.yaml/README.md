# YAML

YAML support for the Proteus code editor, built on [yaml-language-server](https://github.com/redhat-developer/yaml-language-server), the language server behind VS Code's YAML extension.

## What it does

- **Completion, hover help and checks** from JSON schemas. A file gets a schema from SchemaStore's catalog of common files, such as `docker-compose.yml` and `.gitlab-ci.yml`, or from a `schema` file association that any plugin adds.
- **Custom tags**, such as CloudFormation's `!Ref` and `!GetAtt`, once they are listed in `yaml.custom_tags`.

Prettier, which ships with Proteus, formats YAML. The language server's own formatter stays off.

The language server starts when the first YAML file opens.

## What it needs

yaml-language-server runs on Node.js, which must be on the PATH. When the server is nowhere else, the first YAML file that opens has npm install yaml-language-server 1.24.0 into the app's cache folder. The **Download missing tools** setting, `tools.download`, can make it ask first or never do it. To install it yourself instead, run `npm install --global yaml-language-server`.

## Schemas for other plugins

A plugin gives its own YAML files completion and checks by adding a file association, with no need to know this plugin exists:

```lua
app.use ('files').associate ({
  kind = 'schema',
  pattern = '.myplugin/config.yml',
  value = 'https://example.com/myplugin.schema.json',
})
```

List `proteus.core.files` in the plugin's `depends`. `lang.gitfiles` does this for GitHub's workflow files.

When one association names a file in full, such as `.github/ISSUE_TEMPLATE/config.yml`, another schema's wildcard pattern that also fits it, such as `.github/ISSUE_TEMPLATE/*.yml`, leaves that file out. So the file is checked against its own schema alone.

## Settings

| Setting | Default | What it does |
|---------|---------|--------------|
| `yaml.enabled` | `true` | Runs the YAML language server. |
| `yaml.schema_store` | `true` | Fetches schemas for common files from schemastore.org. |
| `yaml.custom_tags` | `[]` | Tags the server accepts, each with the kind of value it takes, such as `["!Ref scalar", "!GetAtt sequence"]`. |
| `yaml.validate` | `true` | Shows what does not fit the schema in the Problems panel. |
| `yaml.key_ordering` | `false` | Marks keys that are not in alphabetical order as problems. |
| `yaml.version` | `1.2` | The YAML version files are read as. In `1.1`, words such as `yes` and `no` are booleans. |
