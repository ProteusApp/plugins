-- server: runs luau-lsp for Luau files through the app's language server client. It starts
-- for the first Luau file that opens, and starts again when one of its settings changes.
--
-- Before it starts, it settles Roblox mode from the folder and `luau-lsp.roblox`, and makes sure
-- the files the server loads are in the data folder. In Roblox mode it also runs Rojo, so the
-- server knows the project's instances.

local client_module = require ('lsp.client') --[[@as Lsp.ClientModule]]
local definitions_module = require ('lib.definitions') --[[@as LangLuau.DefinitionsModule]]
local disk = require ('disk_paths') --[[@as DiskPaths]]
local launch = require ('lib.launch') --[[@as LangLuau.LaunchModule]]
local project = require ('lib.project') --[[@as LangLuau.ProjectModule]]
local protocol = require ('lsp.protocol') --[[@as Lsp.Protocol]]
local sourcemap_module = require ('lib.sourcemap') --[[@as LangLuau.SourcemapModule]]

-- luau-lsp asks for its settings under this name.
local SECTION = 'luau-lsp'

-- The settings that belong to the server. Changing one starts it again.
local SETTINGS = { 'luau-lsp.enabled', 'luau-lsp.roblox', 'luau-lsp.sourcemap' }

---@class LangLuau.Server
---@field start fun(doc: Proteus.DocInfo?)
---@field stop fun()

---@class LangLuau.ServerModule
local M = {}

M.SETTINGS = SETTINGS

---@param ctx LangLuau.Context
---@param tool Proteus.ToolHandle
---@return LangLuau.Server
function M.install (ctx, tool)
  local app, settings, editor = ctx.app, ctx.settings, ctx.editor
  local starting = false
  -- Each start and stop counts up, so a start that a stop overtook goes no further.
  local run = 0
  local server ---@type LangLuau.Server
  -- What the running server was started with.
  local root = nil ---@type string?
  local roblox = false

  local definitions = definitions_module.install (
    app,
    disk.join (ctx.workspace, 'data/' .. app.id),
    tool.log
  )
  local sourcemap = sourcemap_module.install (ctx, tool)

  ---@return boolean
  local function use_sourcemap ()
    return roblox and settings.get ('luau-lsp.sourcemap') == true
  end

  local client = client_module.new (app, {
    name = 'luau-lsp',
    language = 'luau',
    source = 'luau',
    tool = tool,
    config = function (section)
      if section == SECTION then
        return launch.settings (roblox, use_sourcemap ())
      end
      return nil
    end,
  })

  ---Tells the server that files on disk changed.
  ---@param events { uri: string, type: integer }[]
  local function tell (events)
    if client.ready () and #events > 0 then
      client.notify ('workspace/didChangeWatchedFiles', { changes = events })
    end
  end

  ---@return Proteus.DocInfo?
  local function first_luau_doc ()
    for _, doc in ipairs (editor.docs ()) do
      if doc.language == 'luau' then
        return doc
      end
    end
    return nil
  end

  ---The folder the server works on: the open folder, or else the file's own folder.
  ---@param doc Proteus.DocInfo
  ---@return string
  local function root_for (doc)
    return ctx.project_root or disk.parent (client.to_disk (doc))
  end

  ---Starts the program on a folder, once Roblox mode and the files it loads are settled.
  ---@param program string
  ---@param folder string
  local function launch_in (program, folder)
    local mine = run
    app.fs.list_dir (folder, function (names)
      if mine ~= run then
        return
      end
      names = names or {}
      roblox = project.roblox (settings.get ('luau-lsp.roblox'), names)
      tool.log (
        'info',
        roblox and 'Roblox mode is on' or 'Roblox mode is off, for plain Luau'
      )
      -- The first start in a mode waits for its files to download.
      tool.set_state ('starting')
      definitions.ensure (roblox, function (files)
        if mine ~= run then
          return
        end
        starting = false
        if roblox and not files.definitions then
          ctx.notify (
            "Roblox's type definitions did not download, so Roblox names are unknown. The Tools panel has the reason."
          )
        end
        root = folder
        client.start (program, launch.server_args (files), folder, nil)
        if use_sourcemap () then
          local path = disk.join (folder, launch.SOURCEMAP)
          sourcemap.start (folder, names, function ()
            tell ({ { uri = protocol.uri (path), type = 2 } })
          end)
        end
      end)
    end)
  end

  server = {
    start = function (doc)
      if client.running () or starting then
        return
      end
      if settings.get ('luau-lsp.enabled') ~= true then
        tool.set_state ('stopped', 'switched off in Settings (luau-lsp.enabled)')
        return
      end
      if not ctx.desktop then
        tool.set_state ('stopped', 'running programs needs the desktop app')
        return
      end
      doc = doc or first_luau_doc ()
      if not doc then
        tool.set_state ('stopped', 'starts when a Luau file opens')
        return
      end
      local folder = root_for (doc)
      starting = true
      run = run + 1
      local mine = run
      tool.locate (function (program)
        if mine ~= run then
          return
        end
        if not program then
          starting = false
          tool.set_state ('missing', 'luau-lsp is not on the PATH')
          return
        end
        tool.set_path (program)
        launch_in (program, folder)
      end)
    end,
    stop = function ()
      run = run + 1
      starting = false
      sourcemap.stop ()
      client.stop ()
      root = nil
    end,
  }

  app.on ('editor:opened', function (doc)
    ---@cast doc Proteus.DocInfo
    if doc.language == 'luau' and not client.running () then
      server.start (doc)
    end
  end)

  -- The Code Editor reports files that change on disk in its folder, such as after a Git
  -- checkout. The server hears about the Luau files among them, and about its own settings
  -- files, since it cannot watch the folder itself.
  app.on ('code:disk_changed', function (changes)
    if root then
      tell (
        launch.file_events (
          changes --[[@as Proteus.DirChange[] ]],
          root,
          protocol.uri
        )
      )
    end
  end)

  for _, key in ipairs (SETTINGS) do
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
