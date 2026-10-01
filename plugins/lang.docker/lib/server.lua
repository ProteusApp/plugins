-- server: runs docker-langserver for Dockerfiles. It starts for the first Dockerfile that
-- opens.
--
-- The app's lsp.client inserts the server's completion items over the word before the cursor,
-- which breaks flags and variables, and it cannot ask the server to format. So this builds the
-- same client from the app's lsp modules, with lib/provider.lua for the editor's help and a
-- `format` function for Format Document.

local config = require ('lib.config') --[[@as LangDocker.ConfigModule]]
local disk = require ('disk_paths') --[[@as DiskPaths]]
local documents_module = require ('lsp.documents') --[[@as Lsp.DocumentsModule]]
local edits = require ('lib.edits') --[[@as LangDocker.EditsModule]]
local messages_module = require ('lsp.messages') --[[@as Lsp.MessagesModule]]
local program_module = require ('lib.program') --[[@as LangDocker.ProgramModule]]
local protocol = require ('lsp.protocol') --[[@as Lsp.Protocol]]
local provider_module = require ('lib.provider') --[[@as LangDocker.ProviderModule]]
local rpc_module = require ('lsp.rpc') --[[@as Lsp.RpcModule]]

-- The editor's name for Dockerfiles, which the protocol uses too.
local LANGUAGE = 'dockerfile'

-- How the formatter indents the lines that continue an instruction.
local FORMAT_OPTIONS = { tabSize = 4, insertSpaces = true }

-- What the editor can do with the server's answers. These are lsp.client's.
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
    hover = { contentFormat = { 'markdown', 'plaintext' } },
    definition = { linkSupport = true },
    publishDiagnostics = { relatedInformation = false },
  },
  workspace = { configuration = true, workspaceFolders = true },
  window = { workDoneProgress = true },
}

---@class LangDocker.Server
---@field start fun(doc: Proteus.DocInfo?)
---@field stop fun()
---@field format fun(doc: Proteus.DocInfo, text: string, done: fun(text: string?)) Asks the server to format a Dockerfile.

---@class LangDocker.ServerModule
local M = {}

---@param ctx LangDocker.Context
---@param tool Proteus.ToolHandle
---@return LangDocker.Server
function M.install (ctx, tool)
  local app, settings, editor = ctx.app, ctx.settings, ctx.editor
  local to_disk, from_disk = ctx.paths.to_disk, ctx.paths.from_disk
  local ready = false
  local starting = false
  local remove_provider = nil ---@type fun()?
  local server ---@type LangDocker.Server

  local rpc = rpc_module.new (app, tool)

  local function is_ready ()
    return ready
  end

  local documents = documents_module.new (app, rpc, {
    language = LANGUAGE,
    language_id = LANGUAGE,
    to_disk = to_disk,
    ready = is_ready,
  })
  local provider = provider_module.new (rpc, documents, {
    language = LANGUAGE,
    ready = is_ready,
    open = function (path, where)
      local shown = from_disk (path)
      if disk.is_absolute (shown) then
        editor.open_external (shown, where)
      else
        editor.open_file (shown, where)
      end
    end,
  })
  local messages = messages_module.new (app, {
    source = 'docker',
    name = 'Dockerfile',
    tool = tool,
    diagnostics = app.use ('diagnostics'),
    config = config.section,
    from_disk = from_disk,
    notify = ctx.notify,
  })

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

  ---@return Proteus.DocInfo?
  local function first_dockerfile ()
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
  ---@param found LangDocker.Launch
  ---@param root string
  local function launch (found, root)
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
      if settings.get ('docker.enabled') ~= true then
        tool.set_state ('stopped', 'switched off in Settings (docker.enabled)')
        return
      end
      doc = doc or first_dockerfile ()
      if not doc then
        tool.set_state ('stopped', 'starts when a Dockerfile opens')
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

    format = function (doc, text, done)
      if not ready then
        done (nil)
        return
      end
      -- The server formats its own copy, which is the document's text. Text that another
      -- formatter changed first is left alone.
      if text ~= doc.text () then
        done (nil)
        return
      end
      rpc.request ('textDocument/formatting', {
        textDocument = { uri = documents.sync (doc) },
        options = FORMAT_OPTIONS,
      }, function (result, err)
        if err or type (result) ~= 'table' then
          tool.log ('err', 'format: ' .. tostring (err and err.message))
          done (nil)
          return
        end
        done (edits.apply (text, result --[[@as LangDocker.TextEdit[] ]]))
      end)
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

  local first = true
  settings.watch ('docker.enabled', function ()
    if first then
      first = false
      return
    end
    server.stop ()
    server.start (nil)
  end)

  return server
end

return M
