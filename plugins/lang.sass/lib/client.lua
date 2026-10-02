-- client: one Some Sass server behind two of the editor's languages. It is built from the
-- same parts as the app's lsp.client, which serves only one language. The editor calls `.scss`
-- files `css` and `.sass` files `sass`, so this client gives its help to both, and asks
-- `language_id` which files in them it serves. Plain `.css` and `.less` files share the `css`
-- language, and the client leaves them alone unless `language_id` names them. lib/attach.lua
-- decides how the help reaches the editor, since lang.css may own `css`.

local attach_module = require ('lib.attach') --[[@as LangSass.AttachModule]]
local disk = require ('disk_paths') --[[@as DiskPaths]]
local documents_module = require ('lib.documents') --[[@as LangSass.DocumentsModule]]
local extra_module = require ('lsp.extra') --[[@as Lsp.ExtraModule]]
local messages_module = require ('lsp.messages') --[[@as Lsp.MessagesModule]]
local paths_module = require ('lsp.paths') --[[@as Lsp.PathsModule]]
local protocol = require ('lsp.protocol') --[[@as Lsp.Protocol]]
local provider_module = require ('lsp.provider') --[[@as Lsp.ProviderModule]]
local rpc_module = require ('lsp.rpc') --[[@as Lsp.RpcModule]]

-- What the editor can do with a server's answers. The same as the app's lsp.client.
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

---@class LangSass.ClientOptions
---@field name string The server's name.
---@field languages string[] The editor's languages to give help in, such as `{ 'css', 'sass' }`.
---@field language_id fun(doc: Proteus.DocInfo): string? What the server calls a file, or nil to leave it alone.
---@field source string Names the server's problems in the Problems panel.
---@field tool Proteus.ToolHandle Shows the server's state and the conversation.
---@field config fun(section: string): any What the server gets when it asks for a settings section.
---@field css fun(): LangSass.CssService? lang.css's service, while it runs.

---The app's Lsp.Client, and one more function.
---@class LangSass.Client: Lsp.Client
---@field reattach fun() Gives the help to the editor again, such as when lang.css starts.

---@class LangSass.ClientModule
local M = {}

---@param app Proteus.App
---@param opts LangSass.ClientOptions
---@return LangSass.Client
function M.new (app, opts)
  local editor = app.use ('editor')
  local tool = opts.tool
  local ready = false

  local paths = paths_module.new (app, editor)
  local to_disk, from_disk = paths.to_disk, paths.from_disk

  ---@return boolean
  local function is_ready ()
    return ready
  end

  local rpc = rpc_module.new (app, tool)
  local documents = documents_module.new (app, rpc, {
    language_id = opts.language_id,
    to_disk = to_disk,
    ready = is_ready,
  })

  -- One provider for each editor language, since each one answers only for its own. Each
  -- gives nothing for a file the server does not serve, such as a plain `.css` file.
  local providers = {} ---@type table<string, Proteus.ProviderFactory>
  local extra = extra_module.new (app, to_disk)
  for _, language in ipairs (opts.languages) do
    local factory = provider_module.new (rpc, documents, {
      language = language,
      ready = is_ready,
      extra = extra,
      open = function (path, where)
        local shown = from_disk (path)
        if disk.is_absolute (shown) then
          editor.open_external (shown, where)
        else
          editor.open_file (shown, where)
        end
      end,
    })
    providers[language] = function (doc)
      if not opts.language_id (doc) then
        return nil
      end
      return factory (doc)
    end
  end

  local attach = attach_module.new ({
    editor = editor,
    languages = opts.languages,
    providers = providers,
    css = opts.css,
  })

  local messages = messages_module.new (app, {
    source = opts.source,
    name = opts.name,
    tool = tool,
    diagnostics = app.use ('diagnostics'),
    config = opts.config,
    from_disk = from_disk,
    notify = function (text)
      local n = app.try_use ('notify')
      if n then
        n.warn (text)
      end
    end,
  })

  local function forget ()
    ready = false
    documents.reset ()
    messages.clear ()
    attach.detach ()
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

  ---@type LangSass.Client
  return {
    start = function (program, args, root, init_options)
      rpc.start (program, args, root, handlers)
      tool.set_state ('starting')
      rpc.request ('initialize', {
        clientInfo = { name = 'Proteus' },
        rootUri = protocol.uri (root),
        workspaceFolders = {
          { uri = protocol.uri (root), name = disk.name (root) },
        },
        initializationOptions = init_options,
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
        local info = (result --[[@as { serverInfo?: { version?: string } }]]).serverInfo
        tool.set_version (
          type (info) == 'table' and tostring (info.version) or nil
        )
        tool.set_state ('running')
        attach.attach ()
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
    to_disk = to_disk,
    from_disk = from_disk,
    reattach = function ()
      if ready then
        attach.attach ()
      end
    end,
  }
end

return M
