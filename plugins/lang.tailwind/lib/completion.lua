-- completion: class names from the Tailwind server, added to other plugins' completion. It
-- adds a `completion` file association for each kind of file that holds classes. The plugin
-- that runs a language server for such a file asks the association, and shows its items
-- before its own. The server decides where classes go: inside `class="..."` and `@apply` it
-- answers, and elsewhere it gives nothing.

local items = require ('lib.items') --[[@as LangTailwind.ItemsModule]]
local languages = require ('lib.languages') --[[@as LangTailwind.LanguagesModule]]

-- How many of the best items get their CSS. Each one is a question to the server.
local CSS_ITEMS = 30
-- How long to wait for the CSS before the list goes out without it.
local CSS_WAIT_MS = 400

---@class LangTailwind.CompletionModule
local M = {}

---Asks the server for the CSS of the first few items that lack it, then calls `done`. An
---item the server answers about is replaced with its answer.
---@param app Proteus.App
---@param client LangTailwind.Client
---@param picked table[]
---@param done fun()
local function add_css (app, client, picked, done)
  local left = 0
  local finished = false
  local stop_timer = nil ---@type fun()?
  local function finish ()
    if finished then
      return
    end
    finished = true
    if stop_timer then
      stop_timer ()
    end
    done ()
  end
  for i = 1, #picked do
    if left >= CSS_ITEMS then
      break
    end
    local raw = picked[i]
    if items.wants_css (raw) then
      left = left + 1
      client.request ('completionItem/resolve', raw, function (result)
        if type (result) == 'table' and not finished then
          picked[i] = result
        end
        left = left - 1
        if left == 0 then
          finish ()
        end
      end)
    end
  end
  if left == 0 then
    finish ()
    return
  end
  stop_timer = app.timer.after (CSS_WAIT_MS, finish)
end

---Adds the associations. Each answers nil until the server runs.
---@param app Proteus.App
---@param files Proteus.Files
---@param client LangTailwind.Client
function M.install (app, files, client)
  ---@param doc Proteus.DocInfo
  ---@param pos Proteus.CodePosition
  ---@param respond fun(result: Proteus.CompletionResult?)
  local function complete (doc, pos, respond)
    if not client.ready () or not languages.language_id (doc.path) then
      respond (nil)
      return
    end
    client.request ('textDocument/completion', {
      textDocument = { uri = client.sync (doc) },
      position = pos,
    }, function (result)
      local raws = type (result) == 'table' and (result.items or result) or {}
      if #raws == 0 then
        respond (nil)
        return
      end
      local line = items.line (doc.text (), pos.line)
      local from = items.from (raws, pos)
      local picked = items.pick (raws, items.slice (line, from, pos.character))
      if #picked == 0 then
        respond (nil)
        return
      end
      add_css (app, client, picked, function ()
        local list = {} ---@type Proteus.CompletionItem[]
        for _, raw in ipairs (picked) do
          list[#list + 1] = items.item (raw, line, pos, from)
        end
        respond ({ items = list, from = from })
      end)
    end)
  end

  for _, pattern in ipairs (languages.PATTERNS) do
    files.associate ({ kind = 'completion', pattern = pattern, value = complete })
  end
end

return M
