-- provider: completion and hover help for JSON files, answered by the server. It works like
-- the app's lsp.provider, with two differences. Completion items become plain text that fits
-- around the quotes already typed, and the editor learns where that text starts. The server
-- has no go to definition, so neither does this.

local completion = require ('lib.completion') --[[@as LangJson.CompletionModule]]
local protocol = require ('lsp.protocol') --[[@as Lsp.Protocol]]

---@class LangJson.ProviderOptions
---@field language string The editor's language, `'json'`.
---@field ready fun(): boolean True once the server has started.
---@field extra fun(doc: Proteus.DocInfo, pos: Proteus.CodePosition, respond: fun(result: Lsp.Extra?)) Completion from `completion` associations.

---@class LangJson.ProviderModule
local M = {}

---@param rpc Lsp.Rpc
---@param documents Lsp.Documents
---@param opts LangJson.ProviderOptions
---@return Proteus.ProviderFactory
function M.new (rpc, documents, opts)
  ---The server's items, with what each inserts when the text from `from` is replaced.
  ---@param raw_items table[]
  ---@param line string
  ---@param pos Proteus.CodePosition
  ---@param from integer
  ---@return Proteus.CompletionItem[]
  local function convert (raw_items, line, pos, from)
    local items = {} ---@type Proteus.CompletionItem[]
    for _, raw in ipairs (raw_items) do
      local item = protocol.completion (raw --[[@as Lsp.CompletionItem]])
      item.insert = completion.insert (raw, line, pos, from)
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
    rpc.request ('textDocument/completion', {
      textDocument = { uri = documents.sync (doc) },
      position = pos,
    }, function (result)
      if type (result) == 'table' then
        server = (result.items or result) --[[@as table[] ]]
      end
      finish ()
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
    rpc.request ('textDocument/hover', {
      textDocument = { uri = documents.sync (doc) },
      position = pos,
    }, function (result)
      respond (
        type (result) == 'table' and protocol.markdown (result.contents) or nil
      )
    end)
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
      hover = function (pos, respond)
        hover (doc, pos, respond)
      end,
    }
  end
end

return M
