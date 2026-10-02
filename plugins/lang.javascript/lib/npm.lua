-- npm: completes package names and versions in package.json from the npm registry. Names come
-- from the registry's search. Versions come from the short form of a package's record, the
-- one npm itself reads to install, with deprecated versions left out. Each answer is kept for
-- the session.

local context = require ('lib.package_context') --[[@as LangJavascript.PackageContextModule]]

local SEARCH = 'https://registry.npmjs.org/-/v1/search?size=20&text='
local REGISTRY = 'https://registry.npmjs.org/'
-- The short record lists each version without its readme and file lists.
local SHORT =
  'application/vnd.npm.install-v1+json; q=1.0, application/json; q=0.8'
-- A search starts from this many letters, so one keystroke does not search everything.
local MIN_SEARCH = 2
local MAX_VERSIONS = 12

---A version split into its parts.
---@class LangJavascript.Version
---@field major integer
---@field minor integer
---@field patch integer
---@field pre string The part after `-`, or `''` for a release.

---A package's versions, newest first.
---@class LangJavascript.Versions
---@field latest? string The version npm installs by default.
---@field list string[]

---@class LangJavascript.NpmModule
local M = {}

---@param version string
---@return LangJavascript.Version?
function M.parse (version)
  local major, minor, patch, rest =
    version:match ('^v?(%d+)%.(%d+)%.(%d+)(.*)$')
  if not major then
    return nil
  end
  return {
    major = tonumber (major) --[[@as integer]],
    minor = tonumber (minor) --[[@as integer]],
    patch = tonumber (patch) --[[@as integer]],
    pre = rest:match ('^%-([^+]*)') or '',
  }
end

---True when `a` is newer than `b`. A pre-release comes before its release.
---@param a string
---@param b string
---@return boolean
function M.newer (a, b)
  local x, y = M.parse (a), M.parse (b)
  if not x or not y then
    return a > b
  end
  for _, part in ipairs ({ 'major', 'minor', 'patch' }) do
    if x[part] ~= y[part] then
      return x[part] > y[part]
    end
  end
  if x.pre == '' or y.pre == '' then
    return x.pre == '' and y.pre ~= ''
  end
  return x.pre > y.pre
end

---A package's name as it goes in an address. A scoped name keeps its `@` and has its `/`
---written as `%2F`, as the registry asks.
---@param name string
---@return string
function M.address (name)
  return (name:gsub ('/', '%%2F'))
end

---The versions in a package's record, newest first, without deprecated ones. A
---pre-release only comes when `with_pre` is true.
---@param record any The decoded record.
---@param with_pre boolean
---@return LangJavascript.Versions
function M.versions (record, with_pre)
  local list = {} ---@type string[]
  if type (record) ~= 'table' then
    return { list = list }
  end
  for version, info in
    pairs (type (record.versions) == 'table' and record.versions or {})
  do
    local v = tostring (version)
    local parsed = M.parse (v)
    local deprecated = type (info) == 'table' and info.deprecated
    if parsed and not deprecated and (with_pre or parsed.pre == '') then
      list[#list + 1] = v
    end
  end
  table.sort (list, M.newer)
  local tags = record['dist-tags']
  local latest = type (tags) == 'table' and tags.latest
  return { latest = latest and tostring (latest) or nil, list = list }
end

---Completion items for a registry search answer.
---@param found any
---@return Proteus.CompletionItem[]
function M.name_items (found)
  local items = {} ---@type Proteus.CompletionItem[]
  local objects = type (found) == 'table' and found.objects or {}
  for _, object in ipairs (objects) do
    local p = type (object) == 'table' and object.package
    if type (p) == 'table' and p.name then
      items[#items + 1] = {
        label = tostring (p.name),
        kind = 'module',
        detail = p.version and tostring (p.version) or nil,
        documentation = p.description and tostring (p.description) or nil,
      }
    end
  end
  return items
end

---Completion items for a package's versions: the one npm installs by default, then the
---others, newest first.
---@param versions LangJavascript.Versions
---@return Proteus.CompletionItem[]
function M.version_items (versions)
  local items = {} ---@type Proteus.CompletionItem[]
  local latest = versions.latest
  if latest then
    items[1] = { label = latest, kind = 'constant', detail = 'latest' }
  end
  local shown = 0
  for _, v in ipairs (versions.list) do
    if v ~= latest and shown < MAX_VERSIONS then
      shown = shown + 1
      items[#items + 1] = { label = v, kind = 'constant' }
    end
  end
  return items
end

---@param app Proteus.App
---@param enabled fun(): boolean True while npm completion is switched on.
---@return fun(doc: Proteus.DocInfo, pos: Proteus.CodePosition, respond: fun(result: Lsp.Extra?))
function M.new (app, enabled)
  local cache = {} ---@type table<string, any>
  local waiting = {} ---@type table<string, fun(value: any)[]>

  ---Fetches an address once, and hands every caller the same decoded answer.
  ---@param url string
  ---@param headers table<string, string>
  ---@param decode fun(body: string): any
  ---@param cb fun(value: any)
  local function fetch (url, headers, decode, cb)
    if cache[url] ~= nil then
      cb (cache[url])
      return
    end
    if waiting[url] then
      table.insert (waiting[url], cb)
      return
    end
    waiting[url] = { cb }
    app.net.fetch ({ url = url, headers = headers }, function (reply)
      local ok, value = false, nil
      if reply and reply.status == 200 then
        ok, value = pcall (decode, reply.body)
      end
      -- A failed request is tried again next time, so a moment offline does not stick.
      if ok then
        cache[url] = value
      end
      local list = waiting[url] or {}
      waiting[url] = nil
      for _, fn in ipairs (list) do
        app.try (fn, ok and value or false)
      end
    end)
  end

  ---@param word string
  ---@param respond fun(items: Proteus.CompletionItem[])
  local function names (word, respond)
    local query = word:gsub ('[^%w%-%._~@/]', ''):gsub ('@', '%%40')
    fetch (SEARCH .. M.address (query), {}, app.json.decode, function (found)
      respond (M.name_items (found))
    end)
  end

  ---@param name string
  ---@param typed string
  ---@param respond fun(items: Proteus.CompletionItem[])
  local function versions (name, typed, respond)
    local with_pre = typed:find ('-', 1, true) ~= nil
    -- Only the versions are kept, since a popular package's record is large.
    fetch (REGISTRY .. M.address (name), { Accept = SHORT }, function (body)
      local record = app.json.decode (body)
      return {
        releases = M.versions (record, false),
        all = M.versions (record, true),
      }
    end, function (found)
      if type (found) ~= 'table' then
        respond ({})
        return
      end
      respond (M.version_items (with_pre and found.all or found.releases))
    end)
  end

  return function (doc, pos, respond)
    if not enabled () then
      respond (nil)
      return
    end
    local at = context.at (context.lines (doc.text ()), pos.line, pos.character)
    ---@param items Proteus.CompletionItem[]
    local function answer (items)
      respond ({ items = items, from = at and at.from or nil })
    end
    if at and at.where == 'version' and at.name then
      versions (at.name, at.word, answer)
    elseif at and at.where == 'name' and #at.word >= MIN_SEARCH then
      names (at.word, answer)
    else
      respond (nil)
    end
  end
end

return M
