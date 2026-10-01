-- provider: completion, hover help and go to definition for shell scripts, answered by the
-- server. It works like the app's lsp.provider, with one difference: completion items become
-- text that fits the word before the cursor, which lib/completion.lua works out, and the
-- editor learns where that word starts.

local completion = require ('lib.completion') --[[@as LangShell.CompletionModule]]
local protocol = require ('lsp.protocol') --[[@as Lsp.Protocol]]

---@class LangShell.ProviderOptions
---@field language string The editor's language, `'shell'`.
---@field ready fun(): boolean True once the server has started.
---@field open fun(path: string, where: Proteus.OpenOptions) Opens a definition's full path.
---@field extra fun(doc: Proteus.DocInfo, pos: Proteus.CodePosition, respond: fun(result: Lsp.Extra?)) Completion from `completion` associations.

---@class LangShell.ProviderModule
local M = {}

---@param pos Proteus.CodePosition
---@param uri string
---@return table
local function at (pos, uri)
  return { textDocument = { uri = uri }, position = pos }
end

---@param rpc Lsp.Rpc
---@param documents Lsp.Documents
---@param opts LangShell.ProviderOptions
---@return Proteus.ProviderFactory
function M.new (rpc, documents, opts)
  -- The last completion list as the server sent it, by label. Resolving an item for its
  -- documentation sends the server's own copy back.
  local last_items = {} ---@type table<string, table>

  ---The server's items, with what each inserts when the text from `from` is replaced.
  ---@param raw_items table[]
  ---@param line string
  ---@param pos Proteus.CodePosition
  ---@param from integer
  ---@return Proteus.CompletionItem[]
  local function convert (raw_items, line, pos, from)
    last_items = {}
    local items = {} ---@type Proteus.CompletionItem[]
    for _, raw in ipairs (raw_items) do
      local item = protocol.completion (raw --[[@as Lsp.CompletionItem]])
      item.insert = completion.insert (raw, line, pos, from)
      last_items[item.label] = raw
      items[#items + 1] = item
    end
    return items
  end

  ---Asks the server and the associations at once, then answers with both lists. The
  ---associations' items come first, as with the app's other language servers.
  ---@param doc Proteus.DocInfo
  ---@param pos Proteus.CodePosition
  ---@param respond fun(result: Proteus.CompletionResult?)
  local function complete (doc, pos, respond)
    if not opts.ready () then
      respond (nil)
      return
    end
    local waiting = 2
    local extra = nil ---@type Lsp.Extra?
    local server = nil ---@type table[]?
    local function finish ()
      waiting = waiting - 1
      if waiting > 0 then
        return
      end
      if not extra and not server then
        respond (nil)
        return
      end
      local line = completion.line (doc.text (), pos.line)
      local from = completion.word_start (line, pos.character)
      local items = {} ---@type Proteus.CompletionItem[]
      if extra and #extra.items > 0 then
        from = extra.from or from
        for _, item in ipairs (extra.items) do
          items[#items + 1] = item
        end
      end
      for _, item in ipairs (convert (server or {}, line, pos, from)) do
        items[#items + 1] = item
      end
      respond ({ items = items, from = from })
    end
    opts.extra (doc, pos, function (result)
      extra = result
      finish ()
    end)
    rpc.request (
      'textDocument/completion',
      at (pos, documents.sync (doc)),
      function (result)
        if type (result) == 'table' then
          server = (result.items or result) --[[@as table[] ]]
        end
        finish ()
      end
    )
  end

  ---@param item Proteus.CompletionItem
  ---@param respond fun(text: string?)
  local function resolve (item, respond)
    local raw = last_items[item.label]
    if not raw or not opts.ready () then
      respond (nil)
      return
    end
    rpc.request ('completionItem/resolve', raw, function (result)
      respond (
        type (result) == 'table' and protocol.markdown (result.documentation)
          or nil
      )
    end)
  end

  ---@param doc Proteus.DocInfo
  ---@param pos Proteus.CodePosition
  ---@param respond fun(text: string?)
  local function hover (doc, pos, respond)
    if not opts.ready () then
      respond (nil)
      return
    end
    rpc.request (
      'textDocument/hover',
      at (pos, documents.sync (doc)),
      function (result)
        respond (
          type (result) == 'table' and protocol.markdown (result.contents)
            or nil
        )
      end
    )
  end

  ---@param doc Proteus.DocInfo
  ---@param pos Proteus.CodePosition
  local function definition (doc, pos)
    if not opts.ready () then
      return
    end
    rpc.request (
      'textDocument/definition',
      at (pos, documents.sync (doc)),
      function (result)
        local path, where = protocol.location (result)
        if path and where then
          opts.open (path, where)
        end
      end
    )
  end

  ---@type Proteus.ProviderFactory
  return function (doc)
    if doc.language ~= opts.language then
      return nil
    end
    ---@type Proteus.CodeProvider
    return {
      complete = function (pos, respond)
        complete (doc, pos, respond)
      end,
      resolve = resolve,
      hover = function (pos, respond)
        hover (doc, pos, respond)
      end,
      definition = function (pos)
        definition (doc, pos)
      end,
    }
  end
end

return M
