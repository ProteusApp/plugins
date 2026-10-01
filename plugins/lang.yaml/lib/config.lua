-- config: the settings yaml-language-server asks for, built from this plugin's settings and
-- the schema associations. Nothing here calls the host, so the tests reach it.

local globs = require ('lib.globs') --[[@as LangYaml.GlobsModule]]

-- SchemaStore's list of schemas and the files each one is for.
local CATALOG = 'https://www.schemastore.org/api/json/catalog.json'

-- YAML is indented with two spaces, and the server indents what it inserts to match.
local TAB_SIZE = 2

---What the plugin's settings say, for one answer to the server.
---@class LangYaml.Options
---@field associations { pattern: string, value: any }[] The `schema` file associations.
---@field schema_store boolean Uses SchemaStore's catalog.
---@field custom_tags any The `yaml.custom_tags` setting, a list such as `{ '!Ref scalar' }`.
---@field validate boolean
---@field key_ordering boolean
---@field version string `'1.2'` or `'1.1'`.

---@class LangYaml.ConfigModule
local M = {}

---The custom tags the server checks, from the setting. Anything but a string is left out.
---@param value any
---@return string[]
function M.tags (value)
  local out = {} ---@type string[]
  if type (value) ~= 'table' then
    return out
  end
  for _, tag in ipairs (value) do
    local text = type (tag) == 'string' and tag:match ('^%s*(.-)%s*$') or ''
    if text ~= '' then
      out[#out + 1] = text
    end
  end
  return out
end

---The `yaml` section.
---@param opts LangYaml.Options
---@return table
function M.yaml (opts)
  local tags = M.tags (opts.custom_tags)
  return {
    validate = opts.validate,
    hover = true,
    completion = true,
    keyOrdering = opts.key_ordering,
    yamlVersion = opts.version == '1.1' and '1.1' or '1.2',
    -- Prettier formats YAML in Proteus, so the server's own formatter stays off.
    format = { enable = false },
    schemaStore = { enable = opts.schema_store, url = CATALOG },
    -- Sent even when empty. The server only reads its keys, so `[]` clears the schemas that
    -- went before, while leaving it out would keep them.
    schemas = globs.schemas (opts.associations),
    -- Left out when empty, since an empty table could go out as `[]`.
    customTags = #tags > 0 and tags or nil,
  }
end

---The answer to one section the server asks for. It asks for `yaml`, `http`, `[yaml]` and
---`editor`. `http` holds a proxy, which Proteus does not set, so it goes out as `null`.
---@param section string
---@param opts LangYaml.Options
---@return table?
function M.section (section, opts)
  if section == 'yaml' then
    return M.yaml (opts)
  elseif section == '[yaml]' then
    return { ['editor.tabSize'] = TAB_SIZE }
  elseif section == 'editor' then
    return { tabSize = TAB_SIZE, detectIndentation = false }
  end
  return nil
end

return M
