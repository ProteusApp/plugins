-- ruff: runs `ruff server` beside basedpyright. The editor keeps one provider of completion
-- and hover help per language, and basedpyright has it. So this builds a client from the
-- app's lsp modules the way lsp.client does, minus the provider. It keeps the open Python
-- files in step with Ruff and lists Ruff's problems under the `ruff` source. Organize Imports
-- and Fix All ask Ruff for its code actions and apply the edits to the file in front.
--
-- Ruff from the project's virtual environment comes first, beside its Python. Then the one
-- on the PATH, then a download. The formatter in lib/format.lua uses the same program.

local disk = require ('disk_paths') --[[@as DiskPaths]]
local documents_module = require ('lsp.documents') --[[@as Lsp.DocumentsModule]]
local edits = require ('lib.edits') --[[@as LangPython.EditsModule]]
local messages_module = require ('lsp.messages') --[[@as Lsp.MessagesModule]]
local paths_module = require ('lsp.paths') --[[@as Lsp.PathsModule]]
local protocol = require ('lsp.protocol') --[[@as Lsp.Protocol]]
local release = require ('lib.release') --[[@as Proteus.ToolRelease]]
local rpc_module = require ('lsp.rpc') --[[@as Lsp.RpcModule]]
local venv = require ('lib.venv') --[[@as LangPython.VenvModule]]

-- What Proteus can do with Ruff's answers: keep files in step and show problems. Code
-- actions come back with their edits, since resolving them later is not offered.
local CAPABILITIES = {
  textDocument = {
    synchronization = { didSave = true },
    publishDiagnostics = { relatedInformation = false },
    codeAction = {
      codeActionLiteralSupport = {
        codeActionKind = {
          valueSet = { 'source.organizeImports.ruff', 'source.fixAll.ruff' },
        },
      },
    },
  },
  workspace = { configuration = true, workspaceFolders = true },
  window = { workDoneProgress = true },
}

---@class LangPython.Ruff
---@field start fun(doc: Proteus.DocInfo?)
---@field stop fun()
---@field restart fun()
---@field program fun(root: string?, cb: fun(path: string?)) Finds Ruff for a folder.
---@field action fun(kind: string, title: string) Applies a code action to the file in front.
---@field tool Proteus.ToolHandle

---@class LangPython.RuffModule
local M = {}

---@param ctx LangPython.Context
---@return LangPython.Ruff
function M.install (ctx)
  local app, settings, editor = ctx.app, ctx.settings, ctx.editor
  local ready = false
  local starting = false
  local found = {} ---@type table<string, string> Ruff for each folder.
  local ruff ---@type LangPython.Ruff

  local tool = app.use ('tools').register ({
    id = 'ruff',
    name = 'Ruff',
    description = 'Lint problems, fixes and formatting for Python.',
    program = 'ruff',
    kind = 'server',
    install = 'pip install ruff, or uv tool install ruff',
    homepage = 'https://docs.astral.sh/ruff/',
    settings = { 'python.ruff', 'python.format' },
    release = release,
    start = function ()
      ruff.start (nil)
    end,
    stop = function ()
      ruff.stop ()
    end,
    check = function ()
      ruff.restart ()
    end,
  })

  local paths = paths_module.new (app, editor)
  local to_disk, from_disk = paths.to_disk, paths.from_disk

  ---@return boolean
  local function is_ready ()
    return ready
  end

  local rpc = rpc_module.new (app, tool)
  local documents = documents_module.new (app, rpc, {
    language = 'python',
    language_id = 'python',
    to_disk = to_disk,
    ready = is_ready,
  })
  local messages = messages_module.new (app, {
    source = 'ruff',
    name = 'Ruff',
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
    ---@cast doc Proteus.DocInfo
    if doc.language ~= 'python' then
      return
    end
    if rpc.running () then
      documents.open (doc)
    else
      ruff.start (doc)
    end
  end)

  ---Starts the program and asks it to initialize.
  ---@param program string
  ---@param root string
  local function launch (program, root)
    tool.set_path (program)
    rpc.start (program, { 'server' }, root, handlers)
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
      local info = (result --[[@as { serverInfo?: { version?: string } }]]).serverInfo
      tool.set_version (
        type (info) == 'table' and tostring (info.version) or nil
      )
      tool.set_state ('running')
      for _, doc in ipairs (editor.docs ()) do
        documents.open (doc)
      end
    end)
  end

  ---The open document a path names, with its version, as the documents module wants it.
  ---@param path string
  ---@return Proteus.DocInfo?
  local function open_doc (path)
    for _, doc in ipairs (editor.docs ()) do
      if doc.path == path then
        return doc
      end
    end
    return nil
  end

  ---Applies the edits of the first action Ruff offers to the file in front.
  ---@param current Proteus.CurrentDoc The file in front, which can change.
  ---@param doc Proteus.DocInfo The same file, as the documents module knows it.
  ---@param result any
  ---@param title string
  local function apply (current, doc, result, title)
    local action = type (result) == 'table' and result[1] or nil
    local edit = type (action) == 'table' and action.edit or nil
    local here = to_disk (doc)
    local text = current.text ()
    local changed = text
    for _, file in ipairs (edits.files (edit)) do
      if disk.same (protocol.path (file.uri), here, app.os) then
        changed = edits.apply (changed, file.edits)
      end
    end
    if changed == text then
      ctx.notify ('info', title .. ': nothing to change.')
      return
    end
    current.replace (changed)
  end

  ruff = {
    tool = tool,

    program = function (root, cb)
      local cached = root and found[root]
      if cached then
        cb (cached)
        return
      end
      ctx.python.find (root, function (python)
        ---@param path string?
        local function done (path)
          if path and root then
            found[root] = path
          end
          cb (path)
        end
        local beside = python and venv.beside (python.path, 'ruff', app.os)
        if not beside then
          tool.locate (done)
          return
        end
        app.fs.stat_path (beside, function (stat)
          if stat and stat.exists and not stat.dir then
            done (beside)
          else
            tool.locate (done)
          end
        end)
      end)
    end,

    start = function (doc)
      if rpc.running () or starting then
        return
      end
      if settings.get ('python.ruff') ~= true then
        tool.set_state ('stopped', 'switched off in Settings (python.ruff)')
        return
      end
      if not ctx.desktop then
        tool.set_state ('missing', 'running programs needs the desktop app')
        return
      end
      doc = doc or ctx.first_doc ()
      local root = doc and ctx.root_for (doc)
      if not root then
        tool.set_state ('stopped', 'starts when a Python file opens')
        return
      end
      starting = true
      ruff.program (root, function (program)
        starting = false
        if not program then
          tool.set_path (nil)
          tool.set_state ('missing', 'ruff is not on the PATH')
          return
        end
        launch (program, root)
      end)
    end,

    stop = function ()
      rpc.stop ()
      forget ()
      tool.set_state ('stopped')
    end,

    restart = function ()
      found = {}
      ruff.stop ()
      ruff.start (nil)
    end,

    action = function (kind, title)
      local current = editor.current ()
      if not current or current.language ~= 'python' then
        return
      end
      local doc = open_doc (current.path)
      if not ready or not doc then
        ctx.notify ('info', 'Ruff is not running. The Tools panel says why.')
        return
      end
      -- Ruff reads the file as it was last sent, so waiting edits go first.
      local uri = documents.sync (doc)
      local version = doc.version ()
      local start = { line = 0, character = 0 }
      rpc.request ('textDocument/codeAction', {
        textDocument = { uri = uri },
        range = { start = start, ['end'] = start },
        context = { diagnostics = {}, only = { kind } },
      }, function (result, err)
        if err then
          tool.log ('err', title .. ': ' .. tostring (err.message))
          ctx.notify ('warn', title .. ' failed. The Tools panel has why.')
          return
        end
        -- The edits fit the text Ruff was sent, so a file edited since keeps its text.
        if doc.version () ~= version then
          ctx.notify ('info', title .. ': the file changed. Try again.')
          return
        end
        apply (current, doc, result, title)
      end)
    end,
  }

  -- A new interpreter may bring its own Ruff.
  local first = true
  settings.watch ('python.interpreter', function ()
    if first then
      first = false
      return
    end
    found = {}
  end)

  local first_ruff = true
  settings.watch ('python.ruff', function ()
    if first_ruff then
      first_ruff = false
      return
    end
    ruff.stop ()
    ruff.start (nil)
  end)

  return ruff
end

return M
