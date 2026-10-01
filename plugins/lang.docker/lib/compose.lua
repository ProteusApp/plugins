-- compose: the JSON schema for Compose files, as `schema` file associations. A YAML plugin
-- that reads them, such as lang.yaml, gives these files completion, hover help and checks.
-- This plugin does not need one to be there.
-- Nothing here calls the app, so the tests reach it.

---@class LangDocker.ComposeModule
local M = {}

-- The Compose Specification's schema, as SchemaStore's catalog lists it.
M.SCHEMA =
  'https://raw.githubusercontent.com/compose-spec/compose-go/master/schema/compose-spec.json'

-- The names Docker Compose looks for, and the files that add to them, such as
-- `compose.override.yaml`. A pattern without `/` matches the file name in any folder.
M.PATTERNS = {
  'docker-compose.yml',
  'docker-compose.yaml',
  'docker-compose.*.yml',
  'docker-compose.*.yaml',
  'compose.yml',
  'compose.yaml',
  'compose.*.yml',
  'compose.*.yaml',
}

---One association for each pattern.
---@return Proteus.FileAssociation[]
function M.associations ()
  local out = {} ---@type Proteus.FileAssociation[]
  for _, pattern in ipairs (M.PATTERNS) do
    out[#out + 1] = { kind = 'schema', pattern = pattern, value = M.SCHEMA }
  end
  return out
end

return M
