-- server: runs rust-analyzer through the shared language server client. It starts for the
-- first Rust file that opens, or at once for a folder that holds a crate, and restarts when
-- one of its settings changes.

local client_module = require ('lsp.client') --[[@as Lsp.ClientModule]]
local disk = require ('disk_paths') --[[@as DiskPaths]]
local program_module = require ('lib.program') --[[@as LangRust.ProgramModule]]
local release = require ('lib.release') --[[@as Proteus.ToolRelease]]

-- The settings that belong to the server. Changing one restarts it.
local SETTINGS =
  { 'rust.analyzer_enabled', 'rust.analyzer_path', 'rust.check_command' }

---@class LangRust.Server
---@field start fun(doc: Proteus.DocInfo?) Starts it for this file's crate, or for the open folder.
---@field stop fun()

---@class LangRust.ServerModule
local M = {}

---@param ctx LangRust.Context
---@return LangRust.Server
function M.install (ctx)
  local app, settings, editor = ctx.app, ctx.settings, ctx.editor
  local starting = false
  local server ---@type LangRust.Server

  ---What rust-analyzer reads as its settings, at start and whenever it asks again.
  ---@return table
  local function config ()
    return {
      check = {
        command = tostring (settings.get ('rust.check_command') or 'check'),
      },
      checkOnSave = true,
      cargo = { buildScripts = { enable = true } },
      procMacro = { enable = true },
    }
  end

  local tool = ctx.tools.register ({
    id = 'rust-analyzer',
    name = 'rust-analyzer',
    description = 'Completion, hover help, go to definition and problems for Rust.',
    program = 'rust-analyzer',
    kind = 'server',
    install = 'rustup component add rust-analyzer',
    homepage = 'https://rust-analyzer.github.io',
    settings = SETTINGS,
    release = release,
    start = function ()
      server.start (nil)
    end,
    stop = function ()
      server.stop ()
    end,
    check = function ()
      server.stop ()
      server.start (nil)
    end,
  })

  local client = client_module.new (app, {
    name = 'rust-analyzer',
    language = 'rust',
    source = 'rust',
    tool = tool,
    config = function (section)
      return section == 'rust-analyzer' and config () or nil
    end,
  })

  ---The folder the server works on, and the crates to name to it. rust-analyzer finds a
  ---Cargo.toml in its folder or one level down by itself, so only a deeper crate is named.
  ---@param doc Proteus.DocInfo?
  ---@param cb fun(root: string?, linked: string[])
  local function root_for (doc, cb)
    if not doc then
      cb (ctx.project_root, {})
      return
    end
    ctx.crates.of (disk.parent (client.to_disk (doc)), function (crate)
      local root = ctx.project_root or crate
      if not root or not crate then
        cb (root, {})
        return
      end
      local rel = disk.relative (root, crate, app.os)
      local _, slashes = (rel or ''):gsub ('/', '')
      local deep = rel == nil or (rel ~= '' and slashes >= 1)
      cb (root, deep and { crate .. '/Cargo.toml' } or {})
    end)
  end

  ---@return Proteus.DocInfo?
  local function first_rust_doc ()
    for _, doc in ipairs (editor.docs ()) do
      if doc.language == 'rust' then
        return doc
      end
    end
    return nil
  end

  server = {
    start = function (doc)
      if client.running () or starting then
        return
      end
      if settings.get ('rust.analyzer_enabled') ~= true then
        tool.set_state (
          'stopped',
          'switched off in Settings (rust.analyzer_enabled)'
        )
        return
      end
      doc = doc or first_rust_doc ()
      if not doc and not ctx.project_root then
        tool.set_state ('stopped', 'starts when a Rust file opens')
        return
      end
      starting = true
      program_module.find (app, settings, tool, function (program)
        if not program then
          starting = false
          tool.set_state ('missing', 'no working rust-analyzer is installed')
          return
        end
        tool.set_path (program)
        root_for (doc, function (root, linked)
          starting = false
          if not root then
            tool.set_state ('stopped', 'starts when a Rust file opens')
            return
          end
          local options = config ()
          if #linked > 0 then
            options.linkedProjects = linked
          end
          client.start (program, {}, root, options)
        end)
      end)
    end,
    stop = function ()
      client.stop ()
    end,
  }

  app.on ('editor:opened', function (doc)
    ---@cast doc Proteus.DocInfo
    if doc.language == 'rust' and not client.running () then
      server.start (doc)
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
