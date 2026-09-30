-- schemas: the JSON schemas Taplo uses for completion, hover help and checks. Any plugin adds
-- one as a `schema` association in the file association system, as lang.rust does for
-- Cargo.toml. SchemaStore's catalog covers many common files as well, while the
-- `toml.schema_catalog` setting is on.

-- SchemaStore's list of schemas and the files each one is for.
local CATALOG = 'https://www.schemastore.org/api/json/catalog.json'

---@class LangToml.Schemas
---@field config fun(): table Taplo's settings, with every schema association.
---@field on_change fun(fn: fun()) Runs `fn` whenever an association comes or goes.

---@class LangToml.SchemasModule
local M = {}

---@param settings Proteus.Settings
---@param files Proteus.Files
---@return LangToml.Schemas
function M.install (settings, files)
  local current = {} ---@type Proteus.FileAssociation[]
  local listeners = {} ---@type fun()[]

  local function changed ()
    for _, fn in ipairs (listeners) do
      fn ()
    end
  end

  files.handle ('schema', function (list)
    current = list
    changed ()
  end)
  settings.watch ('toml.schema_catalog', changed)

  ---@type LangToml.Schemas
  return {
    config = function ()
      -- Taplo matches each regular expression against a file's address. A schema for another
      -- kind of file, such as JSON, never matches a TOML file, so every one can go in.
      local associations = {} ---@type table<string, string>
      for _, a in ipairs (current) do
        associations[files.to_regex (a.pattern)] = tostring (a.value)
      end
      local catalog = settings.get ('toml.schema_catalog') == true
      return {
        schema = {
          enabled = true,
          catalogs = catalog and { CATALOG } or {},
          -- Left out when empty, since an empty table could go out as `[]`.
          associations = next (associations) and associations or nil,
        },
      }
    end,
    on_change = function (fn)
      listeners[#listeners + 1] = fn
    end,
  }
end

return M
