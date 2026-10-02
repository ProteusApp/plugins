-- schemas: the JSON schemas Taplo uses for completion, hover help and checks. A plugin adds
-- one as a `schema` association in the file association system, as lang.rust does for
-- Cargo.toml. SchemaStore's catalog covers many common files as well, while the
-- `toml.schema_catalog` setting is on.
--
-- Taplo fetches the address a schema names, and the addresses inside it. So a schema reaches
-- Taplo only from a plugin that could reach the network itself: one that ships with Proteus,
-- or one with the `net` permission. Any other plugin could otherwise send workspace data out
-- in an address.
--
-- Taplo 0.10.0 refuses SchemaStore's catalog, because the catalog now names a different
-- `$schema` address than the one Taplo checks for. So the plugin fetches the catalog itself,
-- keeps its TOML schemas, and writes them with the address Taplo expects to
-- data/lang.toml/schema-catalog.json. Taplo reads that file as its catalog. Taplo ranks the
-- catalog below the associations, so a plugin's own schema still wins for its files.

-- SchemaStore's list of schemas and the files each one is for.
local CATALOG = 'https://www.schemastore.org/api/json/catalog.json'

-- The `$schema` address Taplo 0.10.0 accepts in a SchemaStore catalog.
local TAPLO_CATALOG_SCHEMA = 'https://json.schemastore.org/schema-catalog.json'

-- Where the catalog for Taplo is kept, in the workspace. A copy from an earlier session is
-- used until a new one loads, or when the network is down.
local CACHE = 'data/lang.toml/schema-catalog.json'

---One schema in a SchemaStore catalog.
---@class LangToml.CatalogSchema
---@field name string
---@field description string
---@field url string
---@field fileMatch string[]

---A SchemaStore catalog, in the form Taplo 0.10.0 reads.
---@class LangToml.Catalog
---@field ["$schema"] string
---@field schemas LangToml.CatalogSchema[]

---@class LangToml.Schemas
---@field config fun(): table Taplo's settings, with every schema association.
---@field on_change fun(fn: fun()) Runs `fn` whenever an association comes or goes.
---@field need fun() Fetches the catalog, once, while `toml.schema_catalog` is on.

---@class LangToml.SchemasModule
local M = {}

---The TOML schemas in SchemaStore's catalog, as a catalog Taplo 0.10.0 reads. Each schema
---keeps only its patterns for TOML files.
---@param catalog any The decoded catalog.
---@return LangToml.Catalog
function M.for_taplo (catalog)
  local out = {} ---@type LangToml.CatalogSchema[]
  local schemas = type (catalog) == 'table' and catalog.schemas or nil
  for _, s in ipairs (type (schemas) == 'table' and schemas or {}) do
    if type (s) == 'table' and type (s.url) == 'string' then
      local matches = {} ---@type string[]
      for _, pattern in
        ipairs (type (s.fileMatch) == 'table' and s.fileMatch or {})
      do
        if
          type (pattern) == 'string' and pattern:lower ():match ('%.toml$')
        then
          matches[#matches + 1] = pattern
        end
      end
      if #matches > 0 then
        out[#out + 1] = {
          name = type (s.name) == 'string' and s.name or '',
          description = type (s.description) == 'string' and s.description
            or '',
          url = s.url,
          fileMatch = matches,
        }
      end
    end
  end
  return { ['$schema'] = TAPLO_CATALOG_SCHEMA, schemas = out }
end

---True when a schema association may reach Taplo: its value is an address, and the plugin
---that added it ships with Proteus or has the `net` permission.
---@param association Proteus.FileAssociation
---@param plugin_of fun(id: string): Proteus.PluginInfo?
---@return boolean
function M.allowed (association, plugin_of)
  local owner = association.owner
  if type (association.value) ~= 'string' or type (owner) ~= 'string' then
    return false
  end
  local info = plugin_of (owner)
  if not info then
    return false
  end
  if info.trusted then
    return true
  end
  for _, permission in ipairs (info.permissions or {}) do
    if permission == 'net' then
      return true
    end
  end
  return false
end

---@param app Proteus.App
---@param settings Proteus.Settings
---@param files Proteus.Files
---@param workspace string The workspace's full path.
---@param log fun(level: 'info'|'err', text: string) Writes to the tool's log.
---@return LangToml.Schemas
function M.install (app, settings, files, workspace, log)
  local protocol = require ('lsp.protocol') --[[@as Lsp.Protocol]]
  local disk = require ('disk_paths') --[[@as DiskPaths]]
  local address = protocol.uri (disk.join (workspace, CACHE))
  local current = {} ---@type Proteus.FileAssociation[]
  local ready = app.fs.exists (CACHE)
  local fetched, loading, wanted = false, false, false
  local listeners = {} ---@type fun()[]
  local refused = {} ---@type table<string, boolean>

  local function changed ()
    for _, fn in ipairs (listeners) do
      fn ()
    end
  end

  local function load_catalog ()
    loading = true
    app.net.fetch ({ url = CATALOG }, function (reply, err)
      loading = false
      local ok, decoded = false, nil
      if reply and reply.status == 200 then
        ok, decoded = pcall (app.json.decode, reply.body)
      end
      local catalog = ok and M.for_taplo (decoded) or nil
      if not catalog or #catalog.schemas == 0 then
        log (
          'err',
          "SchemaStore's catalog did not load: "
            .. tostring (err or (reply and reply.status))
        )
        return
      end
      fetched = true
      app.fs.write (CACHE, app.json.encode (catalog))
      ready = true
      log (
        'info',
        #catalog.schemas .. " TOML schemas from SchemaStore's catalog"
      )
      changed ()
    end)
  end

  -- The catalog waits until the server starts, so the app fetches nothing while no TOML
  -- file is open. A fetch that failed runs again at the next start.
  local function maybe_load ()
    local on = settings.get ('toml.schema_catalog') == true
    if wanted and on and not fetched and not loading then
      load_catalog ()
    end
  end

  files.handle ('schema', function (list)
    current = list
    changed ()
  end)
  settings.watch ('toml.schema_catalog', function ()
    maybe_load ()
    changed ()
  end)

  ---@type LangToml.Schemas
  return {
    config = function ()
      -- Taplo matches each regular expression against a file's address. A schema for another
      -- kind of file, such as JSON, never matches a TOML file, so every one can go in.
      local associations = {} ---@type table<string, string>
      for _, a in ipairs (current) do
        if M.allowed (a, app.kernel.plugin) then
          associations[files.to_regex (a.pattern)] = a.value --[[@as string]]
        elseif type (a.value) == 'string' and not refused[a.pattern] then
          refused[a.pattern] = true
          log (
            'err',
            'Left out the schema '
              .. tostring (a.owner)
              .. ' added for '
              .. a.pattern
              .. ': only a plugin with the net permission can have Taplo fetch one.'
          )
        end
      end
      local catalog = settings.get ('toml.schema_catalog') == true and ready
      return {
        schema = {
          enabled = true,
          catalogs = catalog and { address } or {},
          -- Left out when empty, since an empty table could go out as `[]`.
          associations = next (associations) and associations or nil,
        },
      }
    end,
    on_change = function (fn)
      listeners[#listeners + 1] = fn
    end,
    need = function ()
      wanted = true
      maybe_load ()
    end,
  }
end

return M
