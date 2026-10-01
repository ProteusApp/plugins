-- actions: completion in GitHub workflow and action files. After `uses:` it offers popular
-- actions with their newest major version. After `owner/repo@` it asks GitHub for the
-- repository's tags, newest first, and keeps each answer for the session. Inside `${{ }}` and
-- `if:` it offers contexts, their properties, the file's step and job ids, and functions.
--
-- A language server for YAML asks for this completion, so it shows only while one runs.

local context = require ('lib.actions_context') --[[@as LangGitfiles.ActionsContextModule]]
local data = require ('lib.actions_data') --[[@as LangGitfiles.ActionsDataModule]]

-- GitHub's API refuses a request that does not say who sends it.
local USER_AGENT =
  'Proteus lang.gitfiles (https://github.com/ProteusApp/plugins)'
local TAGS = 'https://api.github.com/repos/%s/tags?per_page=100'
-- The most tags the list shows.
local MAX_TAGS = 30

---One tag in GitHub's answer.
---@class LangGitfiles.Tag
---@field name string

---@class LangGitfiles.ActionsModule
local M = {}

---@param list LangGitfiles.ExprName[]
---@param kind string
---@param detail? string
---@return Proteus.CompletionItem[]
local function names (list, kind, detail)
  local items = {} ---@type Proteus.CompletionItem[]
  for _, n in ipairs (list) do
    items[#items + 1] =
      { label = n.name, kind = kind, detail = detail, documentation = n.doc }
  end
  return items
end

---@param ids string[]
---@param detail string
---@return Proteus.CompletionItem[]
local function id_items (ids, detail)
  local items = {} ---@type Proteus.CompletionItem[]
  for _, id in ipairs (ids) do
    items[#items + 1] = { label = id, kind = 'variable', detail = detail }
  end
  return items
end

---The completion list inside an expression.
---@param object string? The names before the last dot.
---@param lines string[] The file, for its step and job ids.
---@return Proteus.CompletionItem[]
function M.expression_items (object, lines)
  if not object then
    local items = names (data.contexts, 'module', 'context')
    for _, f in ipairs (data.functions) do
      items[#items + 1] = {
        label = f.name,
        kind = 'function',
        detail = f.signature,
        documentation = f.doc,
        -- A status function takes nothing, so it goes in whole.
        insert = f.signature:find ('()', 1, true) and f.signature
          or (f.name .. '('),
      }
    end
    return items
  end
  if object == 'steps' then
    return id_items (context.step_ids (lines), 'step')
  elseif object == 'needs' then
    return id_items (context.job_ids (lines), 'job')
  elseif object:match ('^steps%.[%w_%-]+$') then
    return names (data.step, 'property')
  elseif object:match ('^needs%.[%w_%-]+$') then
    return names (data.need, 'property')
  end
  return names (data.properties[object] or {}, 'property', object)
end

---The completion list after `uses:`.
---@return Proteus.CompletionItem[]
function M.action_items ()
  local items = {} ---@type Proteus.CompletionItem[]
  for _, a in ipairs (data.actions) do
    items[#items + 1] = {
      label = a.repo,
      kind = 'module',
      detail = a.version,
      documentation = a.doc,
      insert = a.repo .. '@' .. a.version,
    }
  end
  return items
end

---Tag names from GitHub's answer, newest first.
---@param found any The decoded answer.
---@return string[]
function M.tag_names (found)
  local list = {} ---@type string[]
  if type (found) ~= 'table' then
    return list
  end
  for _, tag in
    ipairs (found --[[@as LangGitfiles.Tag[] ]])
  do
    if type (tag) == 'table' and type (tag.name) == 'string' then
      list[#list + 1] = tag.name
    end
  end
  return context.sort_tags (list)
end

---@param app Proteus.App
---@return fun(doc: Proteus.DocInfo, pos: Proteus.CodePosition, respond: fun(result: Proteus.CompletionResult?))
function M.new (app)
  local cache = {} ---@type table<string, string[]>
  local waiting = {} ---@type table<string, fun(tags: string[]?)[]>

  ---Asks GitHub for a repository's tags once, and hands every caller the same answer.
  ---@param repo string
  ---@param cb fun(tags: string[]?)
  local function tags (repo, cb)
    local key = repo:lower ()
    if cache[key] then
      cb (cache[key])
      return
    end
    if waiting[key] then
      table.insert (waiting[key], cb)
      return
    end
    waiting[key] = { cb }
    app.net.fetch ({
      url = TAGS:format (repo),
      headers = {
        ['User-Agent'] = USER_AGENT,
        Accept = 'application/vnd.github+json',
      },
    }, function (reply)
      local list = nil ---@type string[]?
      if reply and reply.status == 200 then
        local ok, found = pcall (app.json.decode, reply.body)
        list = ok and M.tag_names (found) or nil
      end
      -- A failed request is tried again next time, so a moment offline does not stick. GitHub
      -- also refuses after 60 requests an hour from one address.
      if list then
        cache[key] = list
      end
      local callers = waiting[key] or {}
      waiting[key] = nil
      for _, fn in ipairs (callers) do
        app.try (fn, list)
      end
    end)
  end

  ---@param repo string
  ---@param respond fun(items: Proteus.CompletionItem[])
  local function versions (repo, respond)
    tags (repo, function (list)
      local items = {} ---@type Proteus.CompletionItem[]
      if not list then
        -- Without GitHub's answer, the bundled version is all there is.
        local known = data.action (repo)
        if known then
          items[1] = { label = known.version, kind = 'constant' }
        end
      end
      local shown = list or {}
      for i = 1, math.min (#shown, MAX_TAGS) do
        items[#items + 1] = {
          label = shown[i],
          kind = 'constant',
          detail = i == 1 and 'newest' or nil,
        }
      end
      respond (items)
    end)
  end

  return function (doc, pos, respond)
    local lines = context.lines (doc.text ())
    local at = context.at (lines, pos.line, pos.character)
    if not at then
      respond (nil)
      return
    end
    ---@param items Proteus.CompletionItem[]
    local function answer (items)
      respond ({ items = items, from = at and at.from or nil })
    end
    if at.where == 'version' and at.repo then
      versions (at.repo, answer)
    elseif at.where == 'action' then
      answer (M.action_items ())
    else
      answer (M.expression_items (at.object, lines))
    end
  end
end

return M
