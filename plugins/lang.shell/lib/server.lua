-- server: runs bash-language-server for shell scripts. It starts for the first shell script
-- that opens, and hears again whenever ShellCheck is found or switched on or off.
--
-- The app's lsp.client cannot do two things this server needs, so this builds the same
-- client from the app's lsp modules. ShellCheck's problems in a zsh script are dropped, since
-- ShellCheck does not read zsh. And completion items fit the word before the cursor, which
-- lib/provider.lua does.

local config = require ('lib.config') --[[@as LangShell.ConfigModule]]
local dialect = require ('lib.dialect') --[[@as LangShell.DialectModule]]
local disk = require ('disk_paths') --[[@as DiskPaths]]
local documents_module = require ('lsp.documents') --[[@as Lsp.DocumentsModule]]
local extra_module = require ('lsp.extra') --[[@as Lsp.ExtraModule]]
local messages_module = require ('lsp.messages') --[[@as Lsp.MessagesModule]]
local program_module = require ('lib.program') --[[@as LangShell.ProgramModule]]
local protocol = require ('lsp.protocol') --[[@as Lsp.Protocol]]
local provider_module = require ('lib.provider') --[[@as LangShell.ProviderModule]]
local rpc_module = require ('lsp.rpc') --[[@as Lsp.RpcModule]]

-- The editor's name for shell scripts, and the protocol's.
local LANGUAGE = 'shell'
local LANGUAGE_ID = 'shellscript'

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

---@class LangShell.Server
---@field start fun(doc: Proteus.DocInfo?)
---@field stop fun()

---@class LangShell.ServerModule
local M = {}

---@param ctx LangShell.Context
---@param tool Proteus.ToolHandle
---@return LangShell.Server
function M.install (ctx, tool)
  local app, settings, editor = ctx.app, ctx.settings, ctx.editor
  local to_disk, from_disk = ctx.to_disk, ctx.from_disk
  local ready = false
  local starting = false
  local remove_provider = nil ---@type fun()?
  local server ---@type LangShell.Server

  local rpc = rpc_module.new (app, tool)

  local function is_ready ()
    return ready
  end

  ---The server's settings, with ShellCheck while it is found and switched on.
  ---@return table
  local function server_config ()
    local shellcheck = settings.get ('shell.shellcheck') == true
      and ctx.shellcheck.path ()
    return config.server (shellcheck or nil)
  end

  local documents = documents_module.new (app, rpc, {
    language = LANGUAGE,
    language_id = LANGUAGE_ID,
    to_disk = to_disk,
    ready = is_ready,
  })
  local provider = provider_module.new (rpc, documents, {
    language = LANGUAGE,
    ready = is_ready,
    extra = extra_module.new (app, to_disk),
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
    source = 'shell',
    name = 'Bash Language Server',
    tool = tool,
    diagnostics = app.use ('diagnostics'),
    config = function (section)
      return section == config.SECTION and server_config () or nil
    end,
    from_disk = from_disk,
    notify = ctx.notify,
  })

  ---Sends the server its settings again.
  local function configure ()
    if ready then
      rpc.notify ('workspace/didChangeConfiguration', {
        settings = { [config.SECTION] = server_config () },
      })
    end
  end

  ---True when problems for this full path belong to a zsh script.
  ---@param path string
  ---@return boolean
  local function is_zsh (path)
    for _, doc in ipairs (editor.docs ()) do
      if disk.same (to_disk (doc), path, app.os) then
        return dialect.is_zsh (path, doc.text ())
      end
    end
    return dialect.is_zsh (path, nil)
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
        and type (params.diagnostics) == 'table'
        and is_zsh (protocol.path (tostring (params.uri)))
      then
        local kept = {} ---@type table[]
        for _, d in ipairs (params.diagnostics) do
          if d.source ~= 'shellcheck' then
            kept[#kept + 1] = d
          end
        end
        params.diagnostics = kept
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
  local function first_shell_doc ()
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
  ---@param found LangShell.Launch
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
      if settings.get ('shell.enabled') ~= true then
        tool.set_state ('stopped', 'switched off in Settings (shell.enabled)')
        return
      end
      doc = doc or first_shell_doc ()
      if not doc then
        tool.set_state ('stopped', 'starts when a shell script opens')
        return
      end
      local root = root_for (doc)
      starting = true
      program_module.find (app, tool, root, function (found, why)
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

  ctx.shellcheck.on_change (configure)

  local first_shellcheck = true
  settings.watch ('shell.shellcheck', function ()
    if first_shellcheck then
      first_shellcheck = false
      return
    end
    configure ()
  end)

  local first_enabled = true
  settings.watch ('shell.enabled', function ()
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
