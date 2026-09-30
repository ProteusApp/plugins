-- registry: completes crate names and versions in Cargo.toml from crates.io. Names come from
-- crates.io's search. Versions come from its sparse index, the small file per crate that
-- Cargo itself reads, with yanked versions left out. Each answer is kept for the session.

local context = require ('lib.cargo_context') --[[@as LangRust.CargoContextModule]]

-- crates.io asks every program that calls it to say who it is.
local USER_AGENT = 'Proteus lang.rust (https://github.com/ProteusApp/plugins)'
-- Most downloaded first. The editor keeps only the names that fit what is typed.
local SEARCH = 'https://crates.io/api/v1/crates?per_page=20&sort=downloads&q='
local INDEX = 'https://index.crates.io/'
-- A search starts from this many letters, so one keystroke does not search everything.
local MIN_SEARCH = 2
local MAX_VERSIONS = 12

---One crate in a crates.io search answer.
---@class LangRust.Crate
---@field name string
---@field description? string
---@field max_stable_version? string
---@field max_version? string
---@field newest_version? string

---@class LangRust.RegistryModule
local M = {}

---The index path for a crate, as Cargo's sparse index lays it out: `se/rd/serde`.
---@param name string
---@return string
function M.index_path (name)
  local n = name:lower ()
  if #n <= 2 then
    return #n .. '/' .. n
  elseif #n == 3 then
    return '3/' .. n:sub (1, 1) .. '/' .. n
  end
  return n:sub (1, 2) .. '/' .. n:sub (3, 4) .. '/' .. n
end

---The versions an index file lists, newest first, without yanked ones. A pre-release only
---comes when `with_pre` is true.
---@param body string One JSON record per line.
---@param with_pre boolean
---@return string[]
function M.versions (body, with_pre)
  local out = {} ---@type string[]
  for line in body:gmatch ('[^\n]+') do
    local vers = line:match ('"vers"%s*:%s*"([^"]+)"')
    local yanked = line:match ('"yanked"%s*:%s*true')
    if vers and not yanked and (with_pre or not vers:find ('-', 1, true)) then
      table.insert (out, 1, vers)
    end
  end
  return out
end

---@param app Proteus.App
---@return fun(doc: Proteus.DocInfo, pos: Proteus.CodePosition, respond: fun(result: Lsp.Extra?))
function M.new (app)
  local cache = {} ---@type table<string, any>
  local waiting = {} ---@type table<string, fun(value: any)[]>

  ---Fetches an address once, and hands every caller the same decoded answer.
  ---@param url string
  ---@param decode fun(body: string): any
  ---@param cb fun(value: any)
  local function fetch (url, decode, cb)
    if cache[url] ~= nil then
      cb (cache[url])
      return
    end
    if waiting[url] then
      table.insert (waiting[url], cb)
      return
    end
    waiting[url] = { cb }
    app.net.fetch (
      { url = url, headers = { ['User-Agent'] = USER_AGENT } },
      function (reply)
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
      end
    )
  end

  ---@param word string
  ---@param respond fun(items: Proteus.CompletionItem[])
  local function names (word, respond)
    local query = word:gsub ('[^%w_%-]', '')
    fetch (SEARCH .. query, app.json.decode, function (found)
      local items = {} ---@type Proteus.CompletionItem[]
      local crates = (type (found) == 'table' and found.crates or {}) --[[@as LangRust.Crate[] ]]
      for _, c in ipairs (crates) do
        local version = c.max_stable_version
          or c.max_version
          or c.newest_version
        items[#items + 1] = {
          label = tostring (c.name),
          kind = 'module',
          detail = version and tostring (version) or nil,
          documentation = c.description and tostring (c.description) or nil,
          insert = tostring (c.name)
            .. (version and (' = "' .. tostring (version) .. '"') or ''),
        }
      end
      respond (items)
    end)
  end

  ---@param crate string
  ---@param typed string
  ---@param respond fun(items: Proteus.CompletionItem[])
  local function versions (crate, typed, respond)
    local with_pre = typed:find ('-', 1, true) ~= nil
    fetch (INDEX .. M.index_path (crate), function (body)
      return body
    end, function (body)
      local items = {} ---@type Proteus.CompletionItem[]
      local list = type (body) == 'string' and M.versions (body, with_pre) or {}
      local newest = list[1]
      local short = newest and newest:match ('^(%d+%.%d+)%.')
      if short then
        items[1] =
          { label = short, kind = 'constant', detail = 'newest ' .. newest }
      end
      for i = 1, math.min (#list, MAX_VERSIONS) do
        items[#items + 1] = { label = list[i], kind = 'constant' }
      end
      respond (items)
    end)
  end

  return function (doc, pos, respond)
    local at = context.at (context.lines (doc.text ()), pos.line, pos.character)
    ---@param items Proteus.CompletionItem[]
    local function answer (items)
      respond ({ items = items, from = at and at.from or nil })
    end
    if at and at.where == 'version' and at.crate then
      versions (at.crate, at.word, answer)
    elseif at and at.where == 'name' and #at.word >= MIN_SEARCH then
      names (at.word, answer)
    else
      respond (nil)
    end
  end
end

return M
