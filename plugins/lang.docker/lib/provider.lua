-- provider: completion, hover help and go to definition for Dockerfiles, answered by the
-- server. It works like the app's lsp.provider, except that completion tells the editor where
-- the server's text starts, which lib/completion.lua works out.

local completion = require ('lib.completion') --[[@as LangDocker.CompletionModule]]
local protocol = require ('lsp.protocol') --[[@as Lsp.Protocol]]

---@class LangDocker.ProviderOptions
---@field language string The editor's language, `'dockerfile'`.
---@field ready fun(): boolean True once the server has started.
---@field open fun(path: string, where: Proteus.OpenOptions) Opens a definition's full path.

---@class LangDocker.ProviderModule
local M = {}

---@param pos Proteus.CodePosition
---@param uri string
---@return table
local function at (pos, uri)
  return { textDocument = { uri = uri }, position = pos }
end

---@param rpc Lsp.Rpc
---@param documents Lsp.Documents
---@param opts LangDocker.ProviderOptions
---@return Proteus.ProviderFactory
function M.new (rpc, documents, opts)
  -- The last completion list as the server sent it, by label. Resolving an item for its
  -- documentation sends the server's own copy back.
  local last_items = {} ---@type table<string, table>

  ---@param doc Proteus.DocInfo
  ---@param pos Proteus.CodePosition
  ---@param respond fun(result: Proteus.CompletionResult?)
  local function complete (doc, pos, respond)
    if not opts.ready () then
      respond (nil)
      return
    end
    rpc.request (
      'textDocument/completion',
      at (pos, documents.sync (doc)),
      function (result)
        if type (result) ~= 'table' then
          respond (nil)
          return
        end
        local raw_items = (result.items or result) --[[@as table[] ]]
        local line = completion.line (doc.text (), pos.line)
        local from = completion.from (raw_items, line, pos)
        last_items = {}
        local items = {} ---@type Proteus.CompletionItem[]
        for _, raw in ipairs (raw_items) do
          local item = protocol.completion (raw --[[@as Lsp.CompletionItem]])
          item.insert = completion.insert (raw, line, pos, from)
          last_items[item.label] = raw
          items[#items + 1] = item
        end
        respond ({ items = items, from = from })
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

  ---Goes to where a build stage or a variable is named, such as the `FROM ... AS build` that
  ---`COPY --from=build` points at.
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
