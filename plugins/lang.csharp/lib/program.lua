-- program: finds csharp-ls, and installs it with dotnet when it is missing. The path in the
-- settings wins, then the one on the PATH, then the copy the plugin installed in the app's
-- cache folder. That copy's version suits the newest .NET runtime installed.

local godot = require ('lib.godot') --[[@as LangCsharp.GodotModule]]

---@class LangCsharp.ProgramModule
local M = {}

---The dotnet program, from the settings or the PATH.
---@param settings Proteus.Settings
---@return string
function M.dotnet (settings)
  local path =
    tostring (settings.get ('csharp.dotnet_path') or ''):match ('^%s*(.-)%s*$')
  return path ~= '' and path or 'dotnet'
end

---Where the plugin keeps its own csharp-ls, and its version. Nil with a reason when no
---.NET 8 or newer is installed.
---@param app Proteus.App
---@param settings Proteus.Settings
---@param cb fun(folder: string?, version: string?, why: string?)
function M.folder (app, settings, cb)
  app.process.run (
    M.dotnet (settings),
    { '--list-runtimes' },
    nil,
    function (result, err)
      if not result or result.code ~= 0 then
        cb (
          nil,
          nil,
          'dotnet did not run ('
            .. tostring (err or (result and result.stderr))
            .. '). Install the .NET 8 SDK, which Godot 4 C# needs anyway.'
        )
        return
      end
      local version = godot.server_version (godot.runtime_major (result.stdout))
      if not version then
        cb (nil, nil, 'csharp-ls needs .NET 8 or newer.')
        return
      end
      app.process.tool_folder (
        { id = 'csharp-ls', version = version },
        function (folder, why)
          cb (folder, version, why)
        end
      )
    end
  )
end

---@param app Proteus.App
---@param folder string
---@return string
local function exe (app, folder)
  return folder .. '/csharp-ls' .. (app.os == 'windows' and '.exe' or '')
end

---Finds a csharp-ls to run, or nil.
---@param app Proteus.App
---@param settings Proteus.Settings
---@param cb fun(program: string?)
function M.find (app, settings, cb)
  local wanted =
    tostring (settings.get ('csharp.server_path') or ''):match ('^%s*(.-)%s*$')
  if wanted ~= '' then
    cb (wanted)
    return
  end
  app.process.which ('csharp-ls', function (found)
    if found then
      cb (found)
      return
    end
    M.folder (app, settings, function (folder)
      if not folder then
        cb (nil)
        return
      end
      app.fs.list_dir (folder, function (names)
        for _, name in ipairs (names or {}) do
          if name == 'csharp-ls' or name == 'csharp-ls.exe' then
            cb (exe (app, folder))
            return
          end
        end
        cb (nil)
      end)
    end)
  end)
end

---Installs csharp-ls into the plugin's folder in the app's cache with
---`dotnet tool install`, then gives its path, or nil and why.
---@param app Proteus.App
---@param settings Proteus.Settings
---@param log fun(stream: 'out'|'err'|'info', text: string)
---@param cb fun(program: string?, why: string?)
function M.install (app, settings, log, cb)
  M.folder (app, settings, function (folder, version, why)
    if not folder or not version then
      cb (nil, why)
      return
    end
    local args = {
      'tool',
      'install',
      'csharp-ls',
      '--version',
      version,
      '--tool-path',
      folder,
    }
    log ('info', M.dotnet (settings) .. ' ' .. table.concat (args, ' '))
    app.process.run (M.dotnet (settings), args, nil, function (result, err)
      if result then
        log ('out', result.stdout)
        if result.stderr ~= '' then
          log ('err', result.stderr)
        end
      end
      -- A copy that is there already makes `tool install` fail, so look before saying so.
      M.find (app, settings, function (program)
        if program then
          cb (program)
        else
          cb (
            nil,
            tostring (err or (result and result.stderr) or 'it did not install')
          )
        end
      end)
    end)
  end)
end

return M
