-- schemas: the JSON schemas the server uses for completion, hover help and checks. Any plugin
-- adds one as a `schema` association in the file association system, as lang.typescript does
-- for tsconfig.json. SchemaStore's catalog covers many common files as well, while the
-- `json.schema_catalog` setting is on.
--
-- The server takes schemas in its `json.schemas` setting, each with the address and a list of
-- file patterns. It downloads each schema itself when a file first needs it. It does not read
-- SchemaStore's catalog, so the plugin fetches the catalog and turns it into that list.

-- SchemaStore's list of schemas and the files each one is for.
local CATALOG = 'https://www.schemastore.org/api/json/catalog.json'

-- The endings of the file patterns the server can use. The catalog also lists YAML and TOML
-- files, which never reach a JSON server.
local JSON_ENDINGS = { json = true, jsonc = true, json5 = true }

---One schema for the server: its address, and the files it is for.
---@class LangJson.Schema
---@field fileMatch string[]
---@field url string

---@class LangJson.Schemas
---@field list fun(): LangJson.Schema[] Every schema, from associations and the catalog.
---@field on_change fun(fn: fun()) Runs `fn` whenever a schema comes or goes.
---@field need fun() Fetches the catalog, once, while `json.schema_catalog` is on.

---@class LangJson.SchemasModule
local M = {}

---A pattern from the file association system as the server's file pattern. The server puts
---`**/` before every pattern and matches it against the file's address, such as
---`file:///c:/code/app/package.json`. So a pattern without `/` matches the name in any
---folder, and one with `/` the end of a path. A full Windows path gets its drive letter in
---lower case, the way the address has it.
---@param pattern string
---@return string
function M.glob (pattern)
  local out = pattern:gsub ('\\', '/')
  local drive, rest = out:match ('^/?(%a):(/.*)$')
  if drive then
    return drive:lower () .. ':' .. rest
  end
  if out:sub (1, 1) == '/' or out:sub (1, 3) == '**/' then
    return out
  end
  return '**/' .. out
end

---True for a catalog pattern that can name a JSON file.
---@param pattern string
---@return boolean
local function names_json (pattern)
  local ext = pattern:match ('%.([^./]+)$')
  return ext ~= nil and JSON_ENDINGS[ext:lower ()] == true
end

---The JSON schemas in SchemaStore's catalog, each with the patterns for JSON files.
---@param catalog any The decoded catalog.
---@return LangJson.Schema[]
function M.from_catalog (catalog)
  local out = {} ---@type LangJson.Schema[]
  local schemas = type (catalog) == 'table' and catalog.schemas or nil
  if type (schemas) ~= 'table' then
    return out
  end
  for _, s in ipairs (schemas) do
    if type (s) == 'table' and type (s.url) == 'string' then
      local matches = {} ---@type string[]
      for _, pattern in
        ipairs (type (s.fileMatch) == 'table' and s.fileMatch or {})
      do
        if type (pattern) == 'string' and names_json (pattern) then
          matches[#matches + 1] = pattern
        end
      end
      if #matches > 0 then
        out[#out + 1] = { fileMatch = matches, url = s.url }
      end
    end
  end
  return out
end

---The same file pattern with or without a leading `**/`.
---@param pattern string
---@return string
local function bare (pattern)
  return (pattern:gsub ('^%*%*/', ''))
end

---Every schema for the server. The associations come first, one entry for each address. A
---catalog pattern that an association also names is left out, so the association's schema
---wins for those files. An association that holds the schema itself, or a function that
---builds it, is left out too, since the code editor gives those files its own help.
---@param associations Proteus.FileAssociation[]
---@param catalog LangJson.Schema[]
---@return LangJson.Schema[]
function M.merge (associations, catalog)
  local out = {} ---@type LangJson.Schema[]
  local by_url = {} ---@type table<string, LangJson.Schema>
  local taken = {} ---@type table<string, true>
  for _, a in ipairs (associations) do
    local url = a.value
    if type (url) == 'string' then
      local glob = M.glob (tostring (a.pattern))
      local entry = by_url[url]
      if not entry then
        entry = { fileMatch = {}, url = url }
        by_url[url] = entry
        out[#out + 1] = entry
      end
      if not taken[bare (glob)] then
        taken[bare (glob)] = true
        entry.fileMatch[#entry.fileMatch + 1] = glob
      end
    end
  end
  for _, s in ipairs (catalog) do
    local matches = {} ---@type string[]
    for _, pattern in ipairs (s.fileMatch) do
      if not taken[bare (pattern)] then
        matches[#matches + 1] = pattern
      end
    end
    if #matches > 0 then
      out[#out + 1] = { fileMatch = matches, url = s.url }
    end
  end
  return out
end

---The server's settings, as `workspace/didChangeConfiguration` sends them.
---@param schemas LangJson.Schema[]
---@param validate boolean
---@return table
function M.settings (schemas, validate)
  return {
    json = {
      validate = { enable = validate },
      -- Left out when empty, since an empty table could go out as `{}`.
      schemas = #schemas > 0 and schemas or nil,
    },
    -- Without this the server downloads schemas without checking certificates.
    http = { proxyStrictSSL = true },
  }
end

---@param app Proteus.App
---@param settings Proteus.Settings
---@param files Proteus.Files
---@param log fun(level: 'info'|'err', text: string) Writes to the tool's log.
---@return LangJson.Schemas
function M.install (app, settings, files, log)
  local current = {} ---@type Proteus.FileAssociation[]
  local catalog = nil ---@type LangJson.Schema[]?
  local loading = false
  local wanted = false
  local listeners = {} ---@type fun()[]

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
      if not ok then
        log (
          'err',
          "SchemaStore's catalog did not load: "
            .. tostring (err or (reply and reply.status))
        )
        return
      end
      catalog = M.from_catalog (decoded)
      log ('info', #catalog .. " schemas from SchemaStore's catalog")
      changed ()
    end)
  end

  -- The catalog waits until the server starts, so the app fetches nothing while no JSON
  -- file is open. A fetch that failed runs again at the next start.
  local function maybe_load ()
    local on = settings.get ('json.schema_catalog') == true
    if wanted and on and not catalog and not loading then
      load_catalog ()
    end
  end

  files.handle ('schema', function (list)
    current = list
    changed ()
  end)
  settings.watch ('json.schema_catalog', function ()
    maybe_load ()
    changed ()
  end)

  ---@type LangJson.Schemas
  return {
    list = function ()
      local use = settings.get ('json.schema_catalog') == true and catalog or {}
      return M.merge (current, use)
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
