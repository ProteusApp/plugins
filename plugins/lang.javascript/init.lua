-- lang.javascript: JavaScript in the code editor, on lang.typescript's language server.
--
-- The server gives JavaScript files completion with documentation, hover help, go to
-- definition (F12 or Ctrl+click) and problems. It is the same server TypeScript files use,
-- so the two kinds of file know about each other. jsconfig.json and package.json get their
-- JSON schemas as file associations, and package.json completes npm package names and
-- versions from the npm registry.
--
-- The parts live in lib/:
--   npm              package names and versions in package.json, from the npm registry
--   package_context  where the cursor is in a package.json

local npm = require ('lib.npm') --[[@as LangJavascript.NpmModule]]

-- JSON schemas for JavaScript's own settings files, from schemastore.org.
local SCHEMAS = {
  ['jsconfig.json'] = 'https://www.schemastore.org/jsconfig.json',
  ['package.json'] = 'https://www.schemastore.org/package.json',
}

---@type Proteus.Plugin
return {
  name = 'JavaScript',
  description = 'JavaScript on the TypeScript language server: completion, hover help, go to definition and problems, with npm packages completed in package.json.',
  version = '1.0.1',
  requires = { proteus = '>=0.3.0', features = { 'permissions' } },
  -- npm package names and versions come from registry.npmjs.org. Completing them reads the
  -- package.json being edited, and a `completion` association needs `files` for that.
  permissions = { 'net', 'files' },
  depends = { 'lang.typescript', 'proteus.core.settings', 'proteus.core.files' },
  activate = function (app)
    local settings = app.use ('settings')
    settings.define ('javascript.npm_completion', {
      title = 'Complete npm packages in package.json',
      type = 'boolean',
      default = true,
      description = 'Offers package names and versions from registry.npmjs.org in the dependency lists of package.json.',
    })

    local typescript = app.use ('typescript') --[[@as LangTypescript.Service]]
    typescript.serve ({ language = 'javascript', language_id = 'javascript' })

    local files = app.use ('files')
    for pattern, schema in pairs (SCHEMAS) do
      files.associate ({ kind = 'schema', pattern = pattern, value = schema })
    end
    files.associate ({
      kind = 'completion',
      pattern = 'package.json',
      value = npm.new (app, function ()
        return settings.get ('javascript.npm_completion') == true
      end),
    })
  end,
}
