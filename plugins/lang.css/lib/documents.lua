-- documents: keeps the server's copy of each open CSS file in step with the editor. It is the
-- app's lsp.documents, with two changes. That module serves one editor language and tells the
-- server one name for it. This one asks `language_id` about each file, so it tells the server
-- which files are `css`, `less` and `scss`, and leaves alone the ones another plugin serves.
-- And `refresh` sorts the open files again when another plugin takes some over or gives
-- them back.
--
-- An edit reaches the server after a short pause, or at once when a question about the file
-- needs the latest text.

local protocol = require ('lsp.protocol') --[[@as Lsp.Protocol]]

local CHANGE_DELAY_MS = 250

---@class LangCss.DocumentsOptions
---@field language_id fun(doc: Proteus.DocInfo): string? What the server calls the file, or nil to leave it alone.
---@field to_disk fun(doc: Proteus.DocInfo): string A document's full path.
---@field ready fun(): boolean True once the server has started.

---The app's Lsp.Documents, and one more function.
---@class LangCss.Documents: Lsp.Documents
---@field refresh fun(docs: Proteus.DocInfo[]) Closes the files the server no longer serves, and opens those it now does.

---@class LangCss.DocumentsModule
local M = {}

---@param app Proteus.App
---@param rpc Lsp.Rpc
---@param opts LangCss.DocumentsOptions
---@return LangCss.Documents
function M.new (app, rpc, opts)
  local opened = {} ---@type table<string, Proteus.DocInfo> By address.
  local waiting = {} ---@type table<string, fun()> Cancels a pending edit, by address.

  ---@param doc Proteus.DocInfo
  ---@return string
  local function uri_of (doc)
    return protocol.uri (opts.to_disk (doc))
  end

  ---@param uri string
  local function cancel (uri)
    local stop = waiting[uri]
    if stop then
      stop ()
      waiting[uri] = nil
    end
  end

  ---@param doc Proteus.DocInfo
  local function send_change (doc)
    local uri = uri_of (doc)
    cancel (uri)
    rpc.notify ('textDocument/didChange', {
      textDocument = { uri = uri, version = doc.version () },
      contentChanges = { { text = doc.text () } },
    })
  end

  ---Tells the server a file is gone from the editor, or no longer its to serve.
  ---@param uri string
  local function close (uri)
    cancel (uri)
    opened[uri] = nil
    rpc.notify ('textDocument/didClose', { textDocument = { uri = uri } })
  end

  ---@param doc Proteus.DocInfo
  local function open (doc)
    if not opts.ready () then
      return
    end
    local id = opts.language_id (doc)
    if not id then
      return
    end
    local uri = uri_of (doc)
    if opened[uri] then
      return
    end
    opened[uri] = doc
    rpc.notify ('textDocument/didOpen', {
      textDocument = {
        uri = uri,
        languageId = id,
        version = doc.version (),
        text = doc.text (),
      },
    })
  end

  app.on ('editor:changed', function (doc)
    ---@cast doc Proteus.DocInfo
    if not opts.ready () or not opts.language_id (doc) then
      return
    end
    local uri = uri_of (doc)
    if not opened[uri] then
      open (doc)
      return
    end
    cancel (uri)
    waiting[uri] = app.timer.after (CHANGE_DELAY_MS, function ()
      waiting[uri] = nil
      send_change (doc)
    end)
  end)

  app.on ('editor:saved', function (path)
    for uri, doc in pairs (opened) do
      if doc.path == path then
        if waiting[uri] then
          send_change (doc)
        end
        rpc.notify ('textDocument/didSave', { textDocument = { uri = uri } })
      end
    end
  end)

  app.on ('editor:closed', function (path)
    for uri, doc in pairs (opened) do
      if doc.path == path then
        close (uri)
      end
    end
  end)

  ---@type LangCss.Documents
  return {
    open = open,
    sync = function (doc)
      local uri = uri_of (doc)
      if not opened[uri] then
        open (doc)
      elseif waiting[uri] then
        send_change (doc)
      end
      return uri
    end,
    reset = function ()
      for uri in pairs (waiting) do
        cancel (uri)
      end
      opened = {}
    end,
    refresh = function (docs)
      for uri, doc in pairs (opened) do
        if not opts.language_id (doc) then
          close (uri)
        end
      end
      for _, doc in ipairs (docs) do
        open (doc)
      end
    end,
  }
end

return M
