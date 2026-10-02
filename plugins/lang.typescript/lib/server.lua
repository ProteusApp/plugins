-- server: one typescript-language-server for every language that asks for it. The app's
-- lsp.client serves one editor language per server, so this builds the same thing from the
-- app's lsp modules, with one conversation and one pair of documents and provider for each
-- language served. TypeScript, JavaScript, JSX and TSX then share one server, which knows
-- how the files import each other and uses far less memory than one server each.
--
-- The server starts with the first file of a served language. It applies the edits that
-- Organize Imports sends back to the file in front, where the shared client declines them.

local disk = require ('disk_paths') --[[@as DiskPaths]]
local documents_module = require ('lsp.documents') --[[@as Lsp.DocumentsModule]]
local edits = require ('lib.edits') --[[@as LangTypescript.EditsModule]]
local extra_module = require ('lsp.extra') --[[@as Lsp.ExtraModule]]
local messages_module = require ('lsp.messages') --[[@as Lsp.MessagesModule]]
local paths_module = require ('lsp.paths') --[[@as Lsp.PathsModule]]
local program_module = require ('lib.program') --[[@as LangTypescript.ProgramModule]]
local protocol = require ('lsp.protocol') --[[@as Lsp.Protocol]]
local provider_module = require ('lsp.provider') --[[@as Lsp.ProviderModule]]
local rpc_module = require ('lsp.rpc') --[[@as Lsp.RpcModule]]

-- What the editor can do with the server's answers. The same as lsp.client's, and it also
-- applies edits, for Organize Imports.
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
  workspace = {
    configuration = true,
    workspaceFolders = true,
    applyEdit = true,
  },
  window = { workDoneProgress = true },
}

---An editor language and its name in the protocol.
---@class LangTypescript.ServeSpec
---@field language string Such as `'jsx'`.
---@field language_id string Such as `'javascriptreact'`.

---One editor language the server serves.
---@class LangTypescript.Served
---@field spec LangTypescript.ServeSpec
---@field users integer How many times it was asked for and not yet given back.
---@field documents Lsp.Documents
---@field provider Proteus.ProviderFactory
---@field remove_provider? fun()

---@class LangTypescript.Server
---@field start fun(doc: Proteus.DocInfo?)
---@field stop fun()
---@field serve fun(spec: LangTypescript.ServeSpec): fun() Adds a language, and gives a function that takes it away.
---@field serves fun(language: string): boolean
---@field organize_imports fun()

---@class LangTypescript.ServerModule
local M = {}

---@param ctx LangTypescript.Context
---@param tool Proteus.ToolHandle
---@return LangTypescript.Server
function M.install (ctx, tool)
  local app, settings, editor = ctx.app, ctx.settings, ctx.editor
  local ready = false
  local starting = false
  local languages = {} ---@type table<string, LangTypescript.Served>
  local server ---@type LangTypescript.Server

  local paths = paths_module.new (app, editor)
  local to_disk, from_disk = paths.to_disk, paths.from_disk
  local rpc = rpc_module.new (app, tool)
  local extra = extra_module.new (app, to_disk)

  ---@param language string
  ---@return LangTypescript.Served?
  local function served (language)
    local entry = languages[language]
    return entry and entry.users > 0 and entry or nil
  end

  ---Opens a definition's file. A restricted plugin cannot send `file:open`, so a workspace
  ---path goes through the editor service.
  ---@param path string
  ---@param where Proteus.OpenOptions
  local function open (path, where)
    local shown = from_disk (path)
    if disk.is_absolute (shown) then
      editor.open_external (shown, where)
    else
      editor.open_file (shown, where)
    end
  end

  ---Applies a workspace edit to the file in front, which is the only one the editor can
  ---change. Gives the answer the server gets, as JSON.
  ---@param params any
  ---@return string
  local function apply_edit (params)
    local doc = editor.current ()
    local changed = false
    for _, file in
      ipairs (edits.files (type (params) == 'table' and params.edit))
    do
      local path = protocol.path (file.uri)
      local here = doc
        and disk.same (to_disk (doc --[[@as Proteus.DocInfo]]), path, app.os)
      if not doc or not here then
        tool.log ('info', 'an edit to ' .. path .. ' was declined')
        return '{"applied":false,"failureReason":"the file is not in front"}'
      end
      doc.replace (edits.apply (doc.text (), file.edits))
      changed = true
    end
    return changed and '{"applied":true}' or '{"applied":false}'
  end

  local messages = messages_module.new (app, {
    source = 'typescript',
    name = 'TypeScript',
    tool = tool,
    diagnostics = app.use ('diagnostics'),
    config = function ()
      return nil
    end,
    from_disk = from_disk,
    notify = function (text)
      ctx.notify ('warn', text)
    end,
  })

  ---Gives the editor the server's help for a language, and tells the server about its open
  ---files.
  ---@param entry LangTypescript.Served
  local function attach (entry)
    if entry.remove_provider then
      return
    end
    entry.remove_provider =
      editor.set_provider (entry.spec.language, entry.provider)
    for _, doc in ipairs (editor.docs ()) do
      entry.documents.open (doc)
    end
  end

  ---@param entry LangTypescript.Served
  local function detach (entry)
    if entry.remove_provider then
      entry.remove_provider ()
      entry.remove_provider = nil
    end
    entry.documents.reset ()
  end

  local function forget ()
    ready = false
    for _, entry in pairs (languages) do
      detach (entry)
    end
    messages.clear ()
  end

  ---@type Lsp.RpcHandlers
  local handlers = {
    on_request = function (msg)
      if msg.method == 'workspace/applyEdit' then
        return apply_edit (msg.params)
      end
      return messages.on_request (msg)
    end,
    on_notification = function (msg)
      -- The server says which TypeScript it found: the project's own, or its fallback.
      if
        msg.method == '$/typescriptVersion' and type (msg.params) == 'table'
      then
        tool.log (
          'info',
          'TypeScript '
            .. tostring (msg.params.version)
            .. ' from '
            .. tostring (msg.params.source)
        )
        return
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
  local function first_doc ()
    for _, doc in ipairs (editor.docs ()) do
      if served (doc.language) then
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
  ---@param found LangTypescript.Launch
  ---@param root string
  ---@param libraries LangTypescript.Libraries
  local function launch (found, root, libraries)
    tool.set_path (found.script)
    rpc.start (found.program, found.args, root, handlers)
    tool.set_state ('starting')
    rpc.request ('initialize', {
      clientInfo = { name = 'Proteus' },
      rootUri = protocol.uri (root),
      workspaceFolders = {
        { uri = protocol.uri (root), name = disk.name (root) },
      },
      initializationOptions = {
        hostInfo = 'proteus',
        -- Left out when empty, since an empty table could go out as `[]`.
        tsserver = (libraries.path or libraries.fallback) and {
          path = libraries.path,
          fallbackPath = libraries.fallback,
        } or nil,
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
      local info = (result --[[@as { serverInfo?: { version?: string } }]]).serverInfo
      local version = type (info) == 'table' and info.version or found.version
      tool.set_version (version and tostring (version) or nil)
      tool.set_state ('running')
      for _, entry in pairs (languages) do
        if entry.users > 0 then
          attach (entry)
        end
      end
    end)
  end

  ---Tells the Tools panel the editor languages the server serves. An older app has no
  ---`set_languages`, and then the server shows in the status bar for every file.
  ---@param list string[]
  local function set_languages (list)
    if tool.set_languages then
      tool.set_languages (list)
    end
  end

  ---Tells the Tools panel which editor languages the server serves now, so its status bar
  ---item shows only for their files.
  local function tell_languages ()
    local list = {} ---@type string[]
    for language, entry in pairs (languages) do
      if entry.users > 0 then
        list[#list + 1] = language
      end
    end
    table.sort (list)
    set_languages (list)
  end

  ---@param spec LangTypescript.ServeSpec
  ---@return LangTypescript.Served
  local function make_entry (spec)
    local entry ---@type LangTypescript.Served
    local function is_ready ()
      return ready and entry.users > 0
    end
    local documents = documents_module.new (app, rpc, {
      language = spec.language,
      language_id = spec.language_id,
      to_disk = to_disk,
      ready = is_ready,
    })
    entry = {
      spec = spec,
      users = 0,
      documents = documents,
      provider = provider_module.new (rpc, documents, {
        language = spec.language,
        ready = is_ready,
        extra = extra,
        open = open,
      }),
    }
    return entry
  end

  app.on ('editor:opened', function (doc)
    ---@cast doc Proteus.DocInfo
    local entry = served (doc.language)
    if not entry then
      return
    end
    if rpc.running () then
      entry.documents.open (doc)
    else
      server.start (doc)
    end
  end)

  server = {
    start = function (doc)
      if rpc.running () or starting then
        return
      end
      if settings.get ('typescript.enabled') ~= true then
        tool.set_state (
          'stopped',
          'switched off in Settings (typescript.enabled)'
        )
        return
      end
      doc = doc or first_doc ()
      if not doc then
        tool.set_state (
          'stopped',
          'starts when a TypeScript or JavaScript file opens'
        )
        return
      end
      local root = root_for (doc)
      starting = true
      program_module.find (app, tool, root, function (found, why)
        if not found then
          starting = false
          tool.set_path (nil)
          tool.set_state ('missing', why)
          return
        end
        local own = settings.get ('typescript.project_typescript') == true
        program_module.libraries (app, root, found, function (libraries)
          starting = false
          if not own then
            -- The server looks in the project by itself, so naming the other TypeScript
            -- is what keeps the project's out.
            libraries = { path = libraries.fallback }
          end
          if libraries.path then
            tool.log ('info', 'TypeScript from ' .. libraries.path)
          end
          launch (found, root, libraries)
        end)
      end)
    end,

    stop = function ()
      rpc.stop ()
      forget ()
      tool.set_state ('stopped')
    end,

    serve = function (spec)
      local entry = languages[spec.language]
      if not entry then
        entry = make_entry (spec)
        languages[spec.language] = entry
      end
      entry.users = entry.users + 1
      tell_languages ()
      if ready then
        attach (entry)
      elseif not rpc.running () then
        server.start (nil)
      end
      local given_back = false
      return function ()
        if given_back then
          return
        end
        given_back = true
        entry.users = entry.users - 1
        if entry.users == 0 then
          detach (entry)
        end
        tell_languages ()
      end
    end,

    serves = function (language)
      return served (language) ~= nil
    end,

    organize_imports = function ()
      local current = editor.current ()
      local entry = current and served (current.language)
      if not current or not entry then
        return
      end
      if not ready then
        ctx.notify ('info', 'The TypeScript language server is not running.')
        return
      end
      -- The server reads the file as it was last sent, so waiting edits go first.
      for _, doc in ipairs (editor.docs ()) do
        if doc.path == current.path then
          entry.documents.sync (doc)
        end
      end
      rpc.request ('workspace/executeCommand', {
        command = '_typescript.organizeImports',
        arguments = {
          to_disk (current --[[@as Proteus.DocInfo]]),
        },
      }, function (_, err)
        if err then
          tool.log ('err', 'Organize Imports: ' .. tostring (err.message))
          ctx.notify (
            'warn',
            'Organize Imports failed. The Tools panel has why.'
          )
        end
      end)
    end,
  }

  local watched = { 'typescript.enabled', 'typescript.project_typescript' }
  for _, key in ipairs (watched) do
    local first = true
    settings.watch (key, function ()
      if first then
        first = false
        return
      end
      server.stop ()
      server.start (nil)
    end)
  end

  return server
end

return M
