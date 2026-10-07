-- server: runs csharp-ls through the shared language server client, on the Godot project of
-- the first C# file that opens. It first runs `dotnet restore`, which fetches the GodotSharp
-- package that holds Godot's API, so completion knows Node, GD and the rest.

local client_module = require ('lsp.client')
local disk = require ('disk_paths')
local program = require ('lib.program') --[[@as LangCsharp.ProgramModule]]

-- The settings that belong to the server. Changing one restarts it.
local SETTINGS =
  { 'csharp.server_enabled', 'csharp.server_path', 'csharp.dotnet_path' }

---@class LangCsharp.Server
---@field start fun(doc: Proteus.DocInfo?) Starts it for this file's project, or the open folder's.
---@field stop fun()
---@field restart fun()
---@field install fun() Installs csharp-ls, then starts it.
---@field project fun(): LangCsharp.GodotProject? The project it runs on.
---@field from_disk fun(path: string): string The editor's path for a full path.

---@class LangCsharp.ServerModule
local M = {}

---@param ctx LangCsharp.Context
---@return LangCsharp.Server
function M.install (ctx)
  local app, settings, editor = ctx.app, ctx.settings, ctx.editor
  local starting = false
  local current = nil ---@type LangCsharp.GodotProject?
  local restored = {} ---@type table<string, true>
  local server ---@type LangCsharp.Server

  local tool = ctx.tools.register ({
    id = 'csharp-ls',
    name = 'csharp-ls',
    description = 'Completion, hover help, go to definition and problems for C#, Godot API included.',
    program = 'csharp-ls',
    kind = 'server',
    install = 'Run C#: Install csharp-ls from the palette, or dotnet tool install --global csharp-ls.',
    languages = { 'csharp' },
    homepage = 'https://github.com/razzmatazz/csharp-language-server',
    settings = SETTINGS,
    start = function ()
      server.start (nil)
    end,
    stop = function ()
      server.stop ()
    end,
    check = function ()
      server.restart ()
    end,
  })

  local client = client_module.new (app, {
    name = 'csharp-ls',
    language = 'csharp',
    source = 'csharp',
    tool = tool,
  })

  ---@param stream 'out'|'err'|'info'
  ---@param text string
  local function log (stream, text)
    for line in (text .. '\n'):gmatch ('([^\n]*)\n') do
      if line:find ('%S') then
        tool.log (stream, (line:gsub ('\r$', '')))
      end
    end
  end

  ---Runs `dotnet restore` once a session for a project, then `done`, whatever it gave.
  ---@param project LangCsharp.GodotProject
  ---@param done fun()
  local function restore (project, done)
    local target = project.csproj or project.solution
    if not target or restored[target] then
      done ()
      return
    end
    tool.set_state ('starting', 'dotnet restore')
    log ('info', 'dotnet restore ' .. target)
    app.process.run (
      program.dotnet (settings),
      { 'restore', target, '--nologo' },
      { cwd = project.root },
      function (result, err)
        if result and result.code == 0 then
          restored[target] = true
        else
          log ('err', tostring (err or (result and result.stdout) or ''))
          ctx.notify (
            'warn',
            'dotnet restore failed, so Godot names may not complete. The Tools panel has its output.'
          )
        end
        done ()
      end
    )
  end

  ---The project for a file, or for the open folder.
  ---@param doc Proteus.DocInfo?
  ---@param cb fun(project: LangCsharp.GodotProject?)
  local function project_for (doc, cb)
    local dir = doc and disk.parent (client.to_disk (doc)) or ctx.project_root
    if not dir then
      cb (nil)
      return
    end
    ctx.projects.of (dir, cb)
  end

  ---@return Proteus.DocInfo?
  local function first_doc ()
    for _, doc in ipairs (editor.docs ()) do
      if doc.language == 'csharp' then
        return doc
      end
    end
    return nil
  end

  ---Offers to install csharp-ls, once a session.
  local offered = false
  local function offer ()
    if offered then
      return
    end
    offered = true
    ctx.notify (
      'info',
      'C# completion needs csharp-ls, which installs with dotnet.',
      {
        timeout = 15000,
        action = {
          label = 'Install csharp-ls',
          run = function ()
            server.install ()
          end,
        },
      }
    )
  end

  server = {
    start = function (doc)
      if client.running () or starting then
        return
      end
      if settings.get ('csharp.server_enabled') ~= true then
        tool.set_state (
          'stopped',
          'switched off in Settings (csharp.server_enabled)'
        )
        return
      end
      doc = doc or first_doc ()
      if not doc and not ctx.project_root then
        tool.set_state ('stopped', 'starts when a C# file opens')
        return
      end
      starting = true
      project_for (doc, function (project)
        if not project or not project.solution then
          starting = false
          tool.set_state (
            'stopped',
            project and 'no .sln or .csproj next to project.godot yet'
              or 'no project.godot above this file'
          )
          return
        end
        program.find (app, settings, function (path)
          if not path then
            starting = false
            tool.set_state ('missing', 'csharp-ls is not installed')
            offer ()
            return
          end
          tool.set_path (path)
          restore (project, function ()
            starting = false
            current = project
            client.start (path, { '--solution', project.solution }, project.root)
          end)
        end)
      end)
    end,
    stop = function ()
      client.stop ()
      current = nil
    end,
    restart = function ()
      server.stop ()
      ctx.projects.forget ()
      server.start (nil)
    end,
    install = function ()
      tool.set_state ('starting', 'installing csharp-ls')
      ctx.notify ('info', 'Installing csharp-ls…')
      program.install (app, settings, log, function (path, why)
        if not path then
          tool.set_state ('missing', why)
          ctx.notify ('error', 'csharp-ls did not install: ' .. tostring (why))
          return
        end
        ctx.notify ('success', 'Installed csharp-ls.')
        server.restart ()
      end)
    end,
    project = function ()
      return current
    end,
    from_disk = client.from_disk,
  }

  app.on ('editor:opened', function (doc)
    ---@cast doc Proteus.DocInfo
    if doc.language == 'csharp' and not client.running () then
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
      server.restart ()
    end)
  end

  return server
end

return M
