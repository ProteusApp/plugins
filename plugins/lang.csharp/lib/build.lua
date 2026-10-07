-- build: the Godot side. Build runs `dotnet build` and puts its errors in the Problems
-- panel. Run builds, then starts the game with Godot. Open in Godot starts the Godot editor
-- on the project, or on one of its scenes, unless one is open on it already. The output of
-- each shows in the Tools panel, under Godot (C#).

local disk = require ('disk_paths')
local godot = require ('lib.godot') --[[@as LangCsharp.GodotModule]]
local program = require ('lib.program') --[[@as LangCsharp.ProgramModule]]

-- Names the build's problems in the Problems panel.
local SOURCE = 'dotnet build'

---@class LangCsharp.Build
---@field build fun(done?: fun(ok: boolean))
---@field run fun()
---@field stop fun()
---@field open_editor fun()
---@field open_scene fun(path: string) Starts the Godot editor on a scene, given its full path.

---@class LangCsharp.BuildModule
local M = {}

---@param ctx LangCsharp.Context
---@param server LangCsharp.Server
---@return LangCsharp.Build
function M.install (ctx, server)
  local app, settings = ctx.app, ctx.settings
  local tool = ctx.tools.register ({
    id = 'csharp-godot',
    name = 'Godot (C#)',
    description = 'Builds the C# project, and runs the game or the editor.',
    program = 'godot',
    kind = 'command',
    install = 'Install the .NET build of Godot 4 from godotengine.org, and set its path in Settings if it is not on the PATH.',
    homepage = 'https://godotengine.org',
    settings = { 'csharp.godot_path', 'csharp.godot_args' },
  })
  tool.set_state ('stopped')
  local shown = {} ---@type string[] Paths that have build problems in the Problems panel.
  local game = nil ---@type Proteus.ProcessHandle?
  local busy = false

  ---@param stream 'out'|'err'|'info'
  ---@param text string
  local function log (stream, text)
    for line in (text .. '\n'):gmatch ('([^\n]*)\n') do
      if line:find ('%S') then
        tool.log (stream, (line:gsub ('\r$', '')))
      end
    end
  end

  ---The project of the file in front, or of the open folder, or nil with a warning.
  ---@param cb fun(project: LangCsharp.GodotProject)
  local function with_project (cb)
    local doc = ctx.editor.current ()
    local dir = doc and doc.external and disk.parent (doc.path)
      or (doc and disk.parent (disk.join (ctx.workspace, doc.path)))
      or ctx.project_root
    local running = server.project ()
    if running and (not dir or disk.inside (dir, running.root, app.os)) then
      cb (running)
      return
    end
    if not dir then
      ctx.notify ('warn', 'Open a C# file or a Godot project folder first.')
      return
    end
    ctx.projects.of (dir, function (project)
      if not project then
        ctx.notify ('warn', 'No project.godot is above this file.')
        return
      end
      cb (project)
    end)
  end

  ---Finds the Godot program.
  ---@param cb fun(path: string?)
  local function find_godot (cb)
    local names = godot.programs (settings.get ('csharp.godot_path'))
    local i = 0
    local function step ()
      i = i + 1
      local name = names[i]
      if not name then
        cb (nil)
        return
      end
      if disk.is_absolute (name) then
        cb (name)
        return
      end
      app.process.which (name, function (found)
        if found then
          cb (found)
        else
          step ()
        end
      end)
    end
    step ()
  end

  ---Tells whether a Godot editor already has the project open. Godot has no lock file and
  ---no way to hand a running editor a file, so this reads the running programs. Windows has
  ---no pgrep, so there the answer is always no.
  ---@param project LangCsharp.GodotProject
  ---@param cb fun(open: boolean)
  local function editor_open (project, cb)
    if app.os == 'windows' then
      cb (false)
      return
    end
    app.process.run ('pgrep', { '-af', 'godot' }, nil, function (result)
      cb (
        result ~= nil
          and godot.editor_running (result.stdout or '', project.root)
      )
    end)
  end

  ---Starts the Godot editor on the project, and on a scene in it when `scene` is a
  ---`res://` path. With an editor already open on the project, it says so instead, since a
  ---second editor on one project fights the first over its files.
  ---@param project LangCsharp.GodotProject
  ---@param scene? string
  local function start_editor (project, scene)
    editor_open (project, function (open)
      if open then
        local name = project.info.name or disk.name (project.root)
        ctx.notify (
          'info',
          scene
              and ('Godot already has ' .. name .. ' open. Open ' .. scene .. ' there.')
            or ('Godot already has ' .. name .. ' open.')
        )
        return
      end
      find_godot (function (path)
        if not path then
          ctx.notify (
            'warn',
            'Godot was not found. Set its path in Settings (csharp.godot_path).'
          )
          return
        end
        local args = { '--path', project.root, '--editor' }
        if scene then
          args[#args + 1] = '--scene'
          args[#args + 1] = scene
        end
        for _, arg in
          ipairs (godot.split_args (settings.get ('csharp.godot_args')))
        do
          args[#args + 1] = arg
        end
        log ('info', path .. ' ' .. table.concat (args, ' '))
        app.process.spawn (path, args, {
          cwd = project.root,
          framing = 'lines',
          on_message = function (line)
            log ('out', line)
          end,
          on_stderr = function (line)
            log ('err', line)
          end,
          on_error = function (why)
            ctx.notify ('error', 'Godot did not start: ' .. why)
          end,
        })
      end)
    end)
  end

  ---Puts a build's problems in the Problems panel, in place of the last build's.
  ---@param project LangCsharp.GodotProject
  ---@param problems LangCsharp.Problem[]
  local function show (project, problems)
    local diagnostics = app.try_use ('diagnostics')
    if not diagnostics then
      return
    end
    for _, path in ipairs (shown) do
      diagnostics.set (SOURCE, path, {})
    end
    shown = {}
    local by_path = {} ---@type table<string, Proteus.Diagnostic[]>
    for _, p in ipairs (problems) do
      local full = disk.is_absolute (p.path) and disk.normalize (p.path)
        or disk.join (project.root, p.path)
      local path = server.from_disk (full)
      local list = by_path[path]
      if not list then
        list = {}
        by_path[path] = list
        shown[#shown + 1] = path
      end
      list[#list + 1] = {
        line = p.line - 1,
        character = p.col - 1,
        severity = p.severity,
        message = p.message,
        source = SOURCE,
        code = p.code,
      }
    end
    for path, list in pairs (by_path) do
      diagnostics.set (SOURCE, path, list)
    end
  end

  ---@param project LangCsharp.GodotProject
  ---@param done? fun(ok: boolean)
  local function build_project (project, done)
    local target = project.csproj or project.solution
    if not target then
      ctx.notify (
        'warn',
        'This project has no .csproj yet. In Godot, use Project > Tools > C# > Create C# solution.'
      )
      if done then
        done (false)
      end
      return
    end
    if busy then
      return
    end
    busy = true
    tool.set_state ('running', 'building')
    log ('info', 'dotnet build ' .. target)
    app.process.run (
      program.dotnet (settings),
      { 'build', target, '--nologo', '-v:q', '-clp:NoSummary' },
      { cwd = project.root },
      function (result, err)
        busy = false
        tool.set_state ('stopped')
        local text = result and (result.stdout .. '\n' .. result.stderr)
          or tostring (err)
        log ('out', text)
        local problems = godot.build_problems (text)
        show (project, problems)
        local errors = 0
        for _, p in ipairs (problems) do
          if p.severity == 'error' then
            errors = errors + 1
          end
        end
        local ok = result ~= nil and result.code == 0
        if ok then
          ctx.notify (
            'success',
            'Built ' .. (project.info.name or 'the project') .. '.'
          )
        else
          ctx.notify (
            'error',
            errors > 0
                and ('The build has ' .. errors .. (errors == 1 and ' error' or ' errors') .. '. The Problems panel lists them.')
              or 'The build failed. The Tools panel has its output, under Godot (C#).'
          )
        end
        if done then
          done (ok)
        end
      end
    )
  end

  ---@type LangCsharp.Build
  local build = {
    build = function (done)
      with_project (function (project)
        build_project (project, done)
      end)
    end,
    run = function ()
      with_project (function (project)
        build_project (project, function (ok)
          if not ok then
            return
          end
          find_godot (function (path)
            if not path then
              ctx.notify (
                'warn',
                'Godot was not found. Set its path in Settings (csharp.godot_path).'
              )
              return
            end
            if game and game.alive () then
              game.kill ()
            end
            tool.set_path (path)
            tool.set_state ('running', 'the game runs')
            local args = { '--path', project.root }
            for _, arg in
              ipairs (godot.split_args (settings.get ('csharp.godot_args')))
            do
              args[#args + 1] = arg
            end
            log ('info', path .. ' ' .. table.concat (args, ' '))
            game = app.process.spawn (path, args, {
              cwd = project.root,
              framing = 'lines',
              on_message = function (line)
                log ('out', line)
              end,
              on_stderr = function (line)
                log ('err', line)
              end,
              on_exit = function (code)
                tool.set_state ('stopped')
                log (
                  'info',
                  code and ('The game stopped, with exit code ' .. code .. '.')
                    or 'The game stopped.'
                )
              end,
              on_error = function (why)
                tool.set_state ('error', why)
                ctx.notify ('error', 'Godot did not start: ' .. why)
              end,
            })
          end)
        end)
      end)
    end,
    stop = function ()
      if game and game.alive () then
        game.kill ()
      end
    end,
    open_editor = function ()
      with_project (function (project)
        start_editor (project, nil)
      end)
    end,
    open_scene = function (path)
      path = disk.normalize (path)
      ctx.projects.of (disk.parent (path), function (project)
        local scene = project and godot.res_path (project.root, path)
        if not project or not scene then
          ctx.notify ('warn', 'No project.godot is above this scene.')
          return
        end
        start_editor (project, scene)
      end)
    end,
  }
  return build
end

return M
