-- lib.library: every page the Handbook knows, from files, from code and from type files. It
-- reads each page when something first asks for it, sorts pages into sections, and keeps the
-- search index until a page changes.

local page = require ('lib.page')
local search = require ('lib.search')

local M = {}

---@alias Handbook.Origin 'file'|'code'|'types'

---@class Handbook.Source
---@field source string The plugin id, `proteus` for the app's chapters, or `types`.
---@field name string The page's name within its source.
---@field markdown string|fun(): string The page's text, or a function that makes it.
---@field origin Handbook.Origin
---@field plugin_name? string The name of the plugin the page belongs to.
---@field active? boolean False when that plugin is not running.
---@field path? string The file the page comes from.

---@class Handbook.Page
---@field id string Such as `core.commands/commands`.
---@field source string
---@field name string
---@field origin Handbook.Origin
---@field title string
---@field section string
---@field order number
---@field keywords? string
---@field plugin_name? string
---@field active boolean
---@field path? string
---@field doc Handbook.Doc

---@class Handbook.Section
---@field name string
---@field order number
---@field pages Handbook.Page[]

---@class Handbook.Library
---@field set fun(id: string, src: Handbook.Source)
---@field remove fun(id: string)
---@field has fun(id: string): boolean
---@field get fun(id: string): Handbook.Page?
---@field list fun(): Handbook.Page[]
---@field sections fun(): Handbook.Section[]
---@field ids fun(): string[]
---@field find fun(query: string, limit?: integer): Handbook.Hit[]
---@field neighbors fun(id: string): Handbook.Page?, Handbook.Page?
---@field version fun(): integer

---@return Handbook.Library
function M.new ()
  local sources = {} ---@type table<string, Handbook.Source>
  local pages = {} ---@type table<string, Handbook.Page>
  local sorted ---@type Handbook.Page[]?
  local entries ---@type Handbook.Entry[]?
  local version = 0

  local function changed ()
    sorted, entries = nil, nil
    version = version + 1
  end

  ---@param id string
  ---@return Handbook.Page?
  local function get (id)
    local cached = pages[id]
    if cached then
      return cached
    end
    local src = sources[id]
    if not src then
      return nil
    end
    local text = src.markdown
    if type (text) == 'function' then
      local ok, made = pcall (text)
      text = ok and tostring (made)
        or (
          '# '
          .. src.name
          .. '\n\nThis page could not be built: '
          .. tostring (made)
        )
    end
    local doc = page.parse (text --[[@as string]])
    local front = doc.front
    local p = {
      id = id,
      source = src.source,
      name = src.name,
      origin = src.origin,
      title = doc.title or src.name,
      section = (front.section and front.section ~= '') and front.section
        or src.plugin_name
        or src.source,
      order = tonumber (front.order) or 100,
      keywords = front.keywords,
      plugin_name = src.plugin_name,
      active = src.active ~= false,
      path = src.path,
      doc = doc,
    }
    pages[id] = p
    return p
  end

  ---@return Handbook.Page[]
  local function list ()
    if sorted then
      return sorted
    end
    local all = {} ---@type Handbook.Page[]
    for id in pairs (sources) do
      all[#all + 1] = get (id)
    end
    local first = {} ---@type table<string, number>
    for _, p in ipairs (all) do
      first[p.section] = math.min (first[p.section] or math.huge, p.order)
    end
    table.sort (all, function (a, b)
      if a.section ~= b.section then
        local fa, fb = first[a.section], first[b.section]
        if fa ~= fb then
          return fa < fb
        end
        return a.section < b.section
      end
      if a.order ~= b.order then
        return a.order < b.order
      end
      if a.title ~= b.title then
        return a.title < b.title
      end
      return a.id < b.id
    end)
    sorted = all
    return all
  end

  ---@type Handbook.Library
  return {
    set = function (id, src)
      local old = sources[id]
      if
        old
        and old.markdown == src.markdown
        and old.active == src.active
        and old.plugin_name == src.plugin_name
      then
        return
      end
      sources[id] = src
      pages[id] = nil
      changed ()
    end,
    remove = function (id)
      if sources[id] then
        sources[id], pages[id] = nil, nil
        changed ()
      end
    end,
    has = function (id)
      return sources[id] ~= nil
    end,
    get = get,
    list = list,
    sections = function ()
      local out = {} ---@type Handbook.Section[]
      for _, p in ipairs (list ()) do
        local last = out[#out]
        if not last or last.name ~= p.section then
          last = { name = p.section, order = p.order, pages = {} }
          out[#out + 1] = last
        end
        last.pages[#last.pages + 1] = p
      end
      return out
    end,
    ids = function ()
      local out = {} ---@type string[]
      for id in pairs (sources) do
        out[#out + 1] = id
      end
      table.sort (out)
      return out
    end,
    find = function (query, limit)
      if not entries then
        local items = {} ---@type Handbook.IndexPage[]
        for _, p in ipairs (list ()) do
          items[#items + 1] = {
            id = p.id,
            title = p.title,
            section = p.section,
            keywords = p.keywords,
            doc = p.doc,
          }
        end
        entries = search.index (items)
      end
      return search.find (entries, query, limit)
    end,
    neighbors = function (id)
      local all = list ()
      for i, p in ipairs (all) do
        if p.id == id then
          return all[i - 1], all[i + 1]
        end
      end
      return nil, nil
    end,
    version = function ()
      return version
    end,
  }
end

return M
