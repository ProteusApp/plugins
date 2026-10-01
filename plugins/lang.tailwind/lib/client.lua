-- client: the conversation with the Tailwind server, built from the app's lsp modules. The
-- app's lsp.client serves one editor language, and gives the editor its help for it. This
-- one serves every file that holds classes, and gives the editor nothing directly. Other
-- plugins own those languages, and the editor keeps one helper per language. So completion
-- reaches the editor through file associations instead, which lib/completion.lua answers.
-- The server's problems go to the Problems panel as usual.

local disk = require ('disk_paths') --[[@as DiskPaths]]
local documents_module = require ('lib.documents') --[[@as LangTailwind.DocumentsModule]]
local languages = require ('lib.languages') --[[@as LangTailwind.LanguagesModule]]
local messages_module = require ('lsp.messages') --[[@as Lsp.MessagesModule]]
local paths_module = require ('lsp.paths') --[[@as Lsp.PathsModule]]
local protocol = require ('lsp.protocol') --[[@as Lsp.Protocol]]
local rpc_module = require ('lsp.rpc') --[[@as Lsp.RpcModule]]

-- What the plugin can do with the server's answers. Snippets stay off, though the server
-- sends a few anyway.
local CAPABILITIES = {
  textDocument = {
    synchronization = { didSave = true },
    completion = {
      completionItem = {
        snippetSupport = false,
        documentationFormat = { 'markdown', 'plaintext' },
        resolveSupport = { properties = { 'documentation', 'detail' } },
      },
    },
    publishDiagnostics = { relatedInformation = false },
  },
  workspace = { configuration = true, workspaceFolders = true },
  window = { workDoneProgress = true },
}

---@class LangTailwind.ClientOptions
---@field tool Proteus.ToolHandle Shows the server's state and the conversation.
---@field config fun(section: string): any What the server gets when it asks for a settings section.
---@field notify fun(text: string) Shows a warning.

---@class LangTailwind.Client
---@field start fun(found: LangTailwind.Launch, root: string)
---@field stop fun()
---@field running fun(): boolean True from start until the server stops.
---@field ready fun(): boolean True once the server has started.
---@field request fun(method: string, params: any, cb: Lsp.Callback)
---@field notify fun(method: string, params: any)
---@field sync fun(doc: Proteus.DocInfo): string Sends waiting edits, then gives the file's address.
---@field serves fun(doc: Proteus.DocInfo): boolean True for a file the server hears about.

---@class LangTailwind.ClientModule
local M = {}

---@param app Proteus.App
---@param opts LangTailwind.ClientOptions
---@return LangTailwind.Client
function M.new (app, opts)
  local editor = app.use ('editor')
  local tool = opts.tool
  local ready = false

  local paths = paths_module.new (app, editor)

  ---@return boolean
  local function is_ready ()
    return ready
  end

  ---@param doc Proteus.DocInfo
  ---@return string?
  local function language_id (doc)
    return languages.language_id (doc.path)
  end

  local rpc = rpc_module.new (app, tool)
  local documents = documents_module.new (app, rpc, {
    language_id = language_id,
    to_disk = paths.to_disk,
    ready = is_ready,
  })
  local messages = messages_module.new (app, {
    source = 'tailwind',
    name = 'Tailwind CSS',
    tool = tool,
    diagnostics = app.use ('diagnostics'),
    config = opts.config,
    from_disk = paths.from_disk,
    notify = opts.notify,
  })

  local function forget ()
    ready = false
    documents.reset ()
    messages.clear ()
  end

  ---@type Lsp.RpcHandlers
  local handlers = {
    on_request = messages.on_request,
    on_notification = messages.on_notification,
    on_exit = function (code)
      forget ()
      tool.set_state (
        code == 0 and 'stopped' or 'error',
        code ~= 0 and ('it exited with code ' .. tostring (code)) or nil
      )
    end,
    on_error = function (err)
      forget ()
      tool.set_state ('error', err)
    end,
  }

  app.on ('editor:opened', function (doc)
    documents.open (doc --[[@as Proteus.DocInfo]])
  end)

  ---@type LangTailwind.Client
  return {
    start = function (found, root)
      tool.set_path (found.script)
      rpc.start (found.program, found.args, root, handlers)
      tool.set_state ('starting')
      rpc.request ('initialize', {
        clientInfo = { name = 'Proteus' },
        rootUri = protocol.uri (root),
        workspaceFolders = {
          { uri = protocol.uri (root), name = disk.name (root) },
        },
        capabilities = CAPABILITIES,
      }, function (result, err)
        if err or type (result) ~= 'table' then
          tool.set_state (
            'error',
            'it did not start: ' .. tostring (err and err.message)
          )
          return
        end
        ready = true
        -- An empty Lua table could go out as `[]`, and the protocol wants an object here.
        rpc.raw ('{"jsonrpc":"2.0","method":"initialized","params":{}}')
        tool.set_version (found.version)
        tool.set_state ('running')
        for _, doc in ipairs (editor.docs ()) do
          documents.open (doc)
        end
      end)
    end,
    stop = function ()
      rpc.stop ()
      forget ()
      tool.set_state ('stopped')
    end,
    running = rpc.running,
    ready = is_ready,
    request = rpc.request,
    notify = rpc.notify,
    sync = documents.sync,
    serves = function (doc)
      return language_id (doc) ~= nil
    end,
  }
end

return M
