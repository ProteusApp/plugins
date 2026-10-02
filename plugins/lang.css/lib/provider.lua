-- provider: completion, hover help and go to definition for CSS files, answered by the
-- server. It works like the app's lsp.provider, with three differences.
--
-- - Completion items become plain text, and the editor learns where the replaced part
--   starts, which lib/completion.lua works out.
-- - Each item already carries its documentation, and the server cannot resolve one, so the
--   provider never asks.
-- - The server finds no definition for an `@import`. It does list the file each one points
--   to as a link, so go to definition on an `@import` opens that file.

local completion = require ('lib.completion') --[[@as LangCss.CompletionModule]]
local protocol = require ('lsp.protocol') --[[@as Lsp.Protocol]]

---@class LangCss.ProviderOptions
---@field ready fun(): boolean True once the server has started.
---@field open fun(path: string, where: Proteus.OpenOptions) Opens a definition's full path.
---@field extra fun(doc: Proteus.DocInfo, pos: Proteus.CodePosition, respond: fun(result: Lsp.Extra?)) Completion from `completion` associations.

---@class LangCss.ProviderModule
local M = {}

---True when a range holds the position.
---@param range any
---@param pos Proteus.CodePosition
---@return boolean
local function holds (range, pos)
  if type (range) ~= 'table' then
    return false
  end
  local start, stop = range.start, range['end']
  local after_start = pos.line > start.line
    or (pos.line == start.line and pos.character >= start.character)
  local before_end = pos.line < stop.line
    or (pos.line == stop.line and pos.character <= stop.character)
  return after_start and before_end
end

---@param rpc Lsp.Rpc
---@param documents Lsp.Documents
---@param opts LangCss.ProviderOptions
---@return Proteus.ProviderFactory
function M.new (rpc, documents, opts)
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
      local raws = server or {}
      local line = completion.line (doc.text (), pos.line)
      local from = completion.from (raws, line, pos)
      local items = {} ---@type Proteus.CompletionItem[]
      if extra and #extra.items > 0 then
        from = extra.from or from
        for _, item in ipairs (extra.items) do
          items[#items + 1] = item
        end
      end
      for _, raw in ipairs (raws) do
        local item = protocol.completion (raw --[[@as Lsp.CompletionItem]])
        item.insert = completion.insert (raw, line, pos, from)
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

  ---Opens the file of the `@import` under the cursor, when there is one.
  ---@param uri string
  ---@param pos Proteus.CodePosition
  local function follow_link (uri, pos)
    rpc.request (
      'textDocument/documentLink',
      { textDocument = { uri = uri } },
      function (links)
        if type (links) ~= 'table' then
          return
        end
        for _, link in ipairs (links) do
          if
            type (link) == 'table'
            and type (link.target) == 'string'
            and link.target:match ('^file:')
            and holds (link.range, pos)
          then
            opts.open (protocol.path (link.target), { line = 1, col = 1 })
            return
          end
        end
      end
    )
  end

  ---@param doc Proteus.DocInfo
  ---@param pos Proteus.CodePosition
  local function definition (doc, pos)
    if not opts.ready () then
      return
    end
    local uri = documents.sync (doc)
    rpc.request ('textDocument/definition', {
      textDocument = { uri = uri },
      position = pos,
    }, function (result)
      local path, where = protocol.location (result)
      if path and where then
        opts.open (path, where)
      else
        follow_link (uri, pos)
      end
    end)
  end

  ---@type Proteus.ProviderFactory
  return function (doc)
    ---@type Proteus.CodeProvider
    return {
      complete = function (pos, respond)
        complete (doc, pos, respond)
      end,
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
