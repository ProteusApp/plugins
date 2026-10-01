-- server: runs vscode-json-language-server for JSON files. It starts for the first JSON file
-- that opens, and hears again whenever a schema comes or goes.
--
-- The app's lsp.client cannot do three things this server needs, so this builds the same
-- client from the app's lsp modules. The server never asks for its settings, so they go out
-- once it starts and again after each change. Each file goes out as `json` or `jsonc`, by its
-- name, where lsp.client gives every file one name. And completion items fit around the
-- quotes already typed, which lib/provider.lua does.

local disk = require ('disk_paths') --[[@as DiskPaths]]
local documents_module = require ('lsp.documents') --[[@as Lsp.DocumentsModule]]
local extra_module = require ('lsp.extra') --[[@as Lsp.ExtraModule]]
local language = require ('lib.language') --[[@as LangJson.LanguageModule]]
local messages_module = require ('lsp.messages') --[[@as Lsp.MessagesModule]]
local paths_module = require ('lsp.paths') --[[@as Lsp.PathsModule]]
local program_module = require ('lib.program') --[[@as LangJson.ProgramModule]]
local protocol = require ('lsp.protocol') --[[@as Lsp.Protocol]]
local provider_module = require ('lib.provider') --[[@as LangJson.ProviderModule]]
local rpc_module = require ('lsp.rpc') --[[@as Lsp.RpcModule]]
local schemas_module = require ('lib.schemas') --[[@as LangJson.SchemasModule]]

-- The editor's name for JSON files.
local LANGUAGE = 'json'

-- What the editor can do with the server's answers. These are lsp.client's, less go to
-- definition, which this server does not offer.
local CAPABILITIES = {
  textDocument = {
    synchronization = { didSave = true },
    completion = {
      completionItem = {
        snippetSupport = false,
        documentationFormat = { 'markdown', 'plaintext' },
      },
    },
    hover = { contentFormat = { 'markdown', 'plaintext' } },
    publishDiagnostics = { relatedInformation = false },
  },
  workspace = { configuration = true, workspaceFolders = true },
  window = { workDoneProgress = true },
}

---@class LangJson.Server
---@field start fun(doc: Proteus.DocInfo?)
---@field stop fun()

---@class LangJson.ServerModule
local M = {}

---@param ctx LangJson.Context
---@param tool Proteus.ToolHandle
---@return LangJson.Server
function M.install (ctx, tool)
  local app, settings, editor = ctx.app, ctx.settings, ctx.editor
  local ready = false
  local starting = false
  local remove_provider = nil ---@type fun()?
  local server ---@type LangJson.Server

  local paths = paths_module.new (app, editor)
  local to_disk, from_disk = paths.to_disk, paths.from_disk
  local rpc = rpc_module.new (app, tool)

  local function is_ready ()
    return ready
  end

  -- The documents go out through this, which names each file `json` or `jsonc` as it opens.
  ---@type Lsp.Rpc
  local named = {
    running = rpc.running,
    start = rpc.start,
    stop = rpc.stop,
    request = rpc.request,
    notify = function (method, params)
      if method == 'textDocument/didOpen' then
        local doc = params.textDocument
        doc.languageId = language.language_id (protocol.path (doc.uri))
      end
      rpc.notify (method, params)
    end,
    raw = rpc.raw,
    log = rpc.log,
  }

  local documents = documents_module.new (app, named, {
    language = LANGUAGE,
    language_id = LANGUAGE,
    to_disk = to_disk,
    ready = is_ready,
  })
  local provider = provider_module.new (rpc, documents, {
    language = LANGUAGE,
    ready = is_ready,
    extra = extra_module.new (app, to_disk),
  })
  local messages = messages_module.new (app, {
    source = 'json',
    name = 'JSON',
    tool = tool,
    diagnostics = app.use ('diagnostics'),
    config = function ()
      return nil
    end,
    from_disk = from_disk,
    notify = ctx.notify,
  })

  ---Sends the server its settings: the schemas, and whether it checks files.
  local function configure ()
    if ready then
      rpc.notify ('workspace/didChangeConfiguration', {
        settings = schemas_module.settings (
          ctx.schemas.list (),
          settings.get ('json.validate') == true
        ),
      })
    end
  end

  local function forget ()
    ready = false
    documents.reset ()
    messages.clear ()
    if remove_provider then
      remove_provider ()
      remove_provider = nil
    end
  end

  ---@type Lsp.RpcHandlers
  local handlers = {
    on_request = messages.on_request,
    on_notification = function (msg)
      local params = msg.params
      if
        msg.method == 'textDocument/publishDiagnostics'
        and type (params) == 'table'
        and not language.checked (protocol.path (tostring (params.uri)))
      then
        params.diagnostics = {}
      end
      messages.on_notification (msg)
    end,
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

  ---@return Proteus.DocInfo?
  local function first_json_doc ()
    for _, doc in ipairs (editor.docs ()) do
      if doc.language == LANGUAGE then
        return doc
      end
    end
    return nil
  end

  ---The folder the server works on: the open folder, or else the file's own folder.
  ---@param doc Proteus.DocInfo
  ---@return string
  local function root_for (doc)
    local project = app.try_use ('project')
    return project and project.root () or disk.parent (to_disk (doc))
  end

  ---Starts the program and asks it to initialize.
  ---@param found LangJson.Launch
  ---@param root string
  local function launch (found, root)
    ctx.schemas.need ()
    tool.set_path (found.script)
    rpc.start (found.program, found.args, root, handlers)
    tool.set_state ('starting')
    rpc.request ('initialize', {
      clientInfo = { name = 'Proteus' },
      rootUri = protocol.uri (root),
      workspaceFolders = {
        { uri = protocol.uri (root), name = disk.name (root) },
      },
      -- Prettier formats JSON in Proteus, so the server does not.
      initializationOptions = { provideFormatter = false },
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
      configure ()
      tool.set_version (found.version)
      tool.set_state ('running')
      remove_provider = editor.set_provider (LANGUAGE, provider)
      for _, doc in ipairs (editor.docs ()) do
        documents.open (doc)
      end
    end)
  end

  server = {
    start = function (doc)
      if rpc.running () or starting then
        return
      end
      if settings.get ('json.enabled') ~= true then
        tool.set_state ('stopped', 'switched off in Settings (json.enabled)')
        return
      end
      doc = doc or first_json_doc ()
      if not doc then
        tool.set_state ('stopped', 'starts when a JSON file opens')
        return
      end
      local root = root_for (doc)
      starting = true
      program_module.find (app, root, function (found, why)
        starting = false
        if not found then
          tool.set_path (nil)
          tool.set_state ('missing', why)
          return
        end
        launch (found, root)
      end)
    end,
    stop = function ()
      rpc.stop ()
      forget ()
      tool.set_state ('stopped')
    end,
  }

  app.on ('editor:opened', function (doc)
    ---@cast doc Proteus.DocInfo
    if doc.language ~= LANGUAGE then
      return
    end
    if rpc.running () then
      documents.open (doc)
    else
      server.start (doc)
    end
  end)

  ctx.schemas.on_change (configure)

  local first_validate = true
  settings.watch ('json.validate', function ()
    if first_validate then
      first_validate = false
      return
    end
    configure ()
  end)

  local first_enabled = true
  settings.watch ('json.enabled', function ()
    if first_enabled then
      first_enabled = false
      return
    end
    server.stop ()
    server.start (nil)
  end)

  return server
end

return M
