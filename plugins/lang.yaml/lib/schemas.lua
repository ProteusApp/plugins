-- schemas: keeps what the server's settings are built from. Any plugin adds a JSON schema for
-- its YAML files as a `schema` association in the file association system, as lang.gitfiles
-- does for GitHub's workflow files. SchemaStore's catalog covers many common files as well,
-- while the `yaml.schema_store` setting is on.

-- The settings that change what the server is told. A change to one tells it again.
local WATCHED = {
  'yaml.schema_store',
  'yaml.custom_tags',
  'yaml.validate',
  'yaml.key_ordering',
  'yaml.version',
}

---@class LangYaml.Schemas
---@field options fun(): LangYaml.Options What the plugin's settings and the associations say now.
---@field on_change fun(fn: fun()) Runs `fn` whenever an association or a setting changes.

---@class LangYaml.SchemasModule
local M = {}

---@param settings Proteus.Settings
---@param files Proteus.Files
---@return LangYaml.Schemas
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
  for _, key in ipairs (WATCHED) do
    settings.watch (key, changed)
  end

  ---@type LangYaml.Schemas
  return {
    options = function ()
      ---@type LangYaml.Options
      return {
        associations = current,
        schema_store = settings.get ('yaml.schema_store') == true,
        custom_tags = settings.get ('yaml.custom_tags'),
        validate = settings.get ('yaml.validate') ~= false,
        key_ordering = settings.get ('yaml.key_ordering') == true,
        version = tostring (settings.get ('yaml.version') or '1.2'),
      }
    end,
    on_change = function (fn)
      listeners[#listeners + 1] = fn
    end,
  }
end

return M
