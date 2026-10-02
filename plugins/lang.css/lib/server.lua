-- server: runs vscode-css-language-server for CSS and Less files, and for SCSS files that no
-- other plugin serves. It starts for the first such file that opens.
--
-- The app's lsp.client cannot do what this server needs, so this builds the same client from
-- the app's lsp modules. Its documents tell the server which files are `css`, `less` and
-- `scss`, and leave alone the ones another plugin took through the router. Its provider
-- turns the server's snippets into plain text. The router hands the provider each file the
-- server serves.

local disk = require ('disk_paths') --[[@as DiskPaths]]
local documents_module = require ('lib.documents') --[[@as LangCss.DocumentsModule]]
local extra_module = require ('lsp.extra') --[[@as Lsp.ExtraModule]]
local languages = require ('lib.languages') --[[@as LangCss.LanguagesModule]]
local messages_module = require ('lsp.messages') --[[@as Lsp.MessagesModule]]
local paths_module = require ('lsp.paths') --[[@as Lsp.PathsModule]]
local program_module = require ('lib.program') --[[@as LangCss.ProgramModule]]
local protocol = require ('lsp.protocol') --[[@as Lsp.Protocol]]
local provider_module = require ('lib.provider') --[[@as LangCss.ProviderModule]]
local rpc_module = require ('lsp.rpc') --[[@as Lsp.RpcModule]]

-- What the editor can do with the server's answers. These are lsp.client's, less resolving
-- an item's documentation, which this server cannot do.
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
    definition = { linkSupport = true },
    publishDiagnostics = { relatedInformation = false },
  },
  workspace = { configuration = true, workspaceFolders = true },
  window = { workDoneProgress = true },
}

---@class LangCss.Server
---@field start fun(doc: Proteus.DocInfo?)
---@field stop fun()

---@class LangCss.ServerModule
local M = {}

---@param ctx LangCss.Context
---@param tool Proteus.ToolHandle
---@return LangCss.Server
function M.install (ctx, tool)
  local app, settings, editor, router =
    ctx.app, ctx.settings, ctx.editor, ctx.router
  local ready = false
  local starting = false
  local server ---@type LangCss.Server

  local paths = paths_module.new (app, editor)
  local to_disk, from_disk = paths.to_disk, paths.from_disk
  local rpc = rpc_module.new (app, tool)

  ---@return boolean
  local function is_ready ()
    return ready
  end

  ---What the server calls a file, or nil when it leaves the file alone.
  ---@param doc Proteus.DocInfo
  ---@return string?
  local function language_id (doc)
    return languages.language_id (doc.path, doc.language, router.routed)
  end

  ---The answer to the `css`, `less` and `scss` sections, which are all the same.
  ---@return table
  local function config ()
    local levels = {} ---@type table<string, any>
    for _, spec in ipairs (languages.LINT_RULES) do
      levels[spec.rule] = settings.get ('css.lint.' .. spec.key)
    end
    return languages.section (settings.get ('css.validate') == true, levels)
  end

  local documents = documents_module.new (app, rpc, {
    language_id = language_id,
    to_disk = to_disk,
    ready = is_ready,
  })
  local provider = provider_module.new (rpc, documents, {
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
    source = 'css',
    name = 'CSS',
    tool = tool,
    diagnostics = app.use ('diagnostics'),
    config = function (section)
      for _, name in ipairs (languages.SECTIONS) do
        if section == name then
          return config ()
        end
      end
      return nil
    end,
    from_disk = from_disk,
    notify = ctx.notify,
  })

  -- The help for the files no other plugin claimed. It gives none until the server runs, so
  -- the editor offers the words in the file meanwhile.
  router.own (function (doc)
    if ready and language_id (doc) then
      return provider (doc)
    end
    return nil
  end)

  ---Sends the server its settings again.
  local function configure ()
    if not ready then
      return
    end
    local section = config ()
    local all = {} ---@type table<string, table>
    for _, name in ipairs (languages.SECTIONS) do
      all[name] = section
    end
    rpc.notify ('workspace/didChangeConfiguration', { settings = all })
  end

  local function forget ()
    ready = false
    documents.reset ()
    messages.clear ()
    router.apply ()
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
  local function first_css_doc ()
    for _, doc in ipairs (editor.docs ()) do
      if language_id (doc) then
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
  ---@param found LangCss.Launch
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
      -- Prettier formats CSS, Less and SCSS in Proteus, so the server does not.
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
      tool.set_version (found.version)
      tool.set_state ('running')
      router.apply ()
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
      if settings.get ('css.enabled') ~= true then
        tool.set_state ('stopped', 'switched off in Settings (css.enabled)')
        return
      end
      doc = doc or first_css_doc ()
      if not doc then
        tool.set_state ('stopped', 'starts when a CSS or Less file opens')
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
    if not language_id (doc) then
      return
    end
    if rpc.running () then
      documents.open (doc)
    else
      server.start (doc)
    end
  end)

  -- A plugin took some files over or gave them back. The server lets go of the files it no
  -- longer serves and reads the ones it now does. A file given back may be the first this
  -- server serves, so it starts, a moment later, outside the plugin that gave the file back.
  router.on_change (function ()
    if ready then
      documents.refresh (editor.docs ())
    elseif not rpc.running () then
      app.timer.after (0, function ()
        server.start (nil)
      end)
    end
  end)

  ---Calls `fn` when a setting changes, but not for the first call `watch` makes at once.
  ---@param key string
  ---@param fn fun()
  local function on_change (key, fn)
    local first = true
    settings.watch (key, function ()
      if first then
        first = false
        return
      end
      fn ()
    end)
  end

  on_change ('css.enabled', function ()
    server.stop ()
    server.start (nil)
  end)
  on_change ('css.validate', configure)
  for _, spec in ipairs (languages.LINT_RULES) do
    on_change ('css.lint.' .. spec.key, configure)
  end

  return server
end

return M
