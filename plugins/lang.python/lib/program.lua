-- program: finds how to start basedpyright. A copy installed with pip into the project's
-- virtual environment comes first, beside its Python. Then the project's own npm copy, then
-- the one on the PATH. An npm copy runs as `node` on the package's script, since npm's files
-- on Windows cannot start on their own.

local launch = require ('lib.launch') --[[@as LangPython.LaunchModule]]
local venv = require ('lib.venv') --[[@as LangPython.VenvModule]]

-- The argument that makes the server talk over its standard input and output.
local STDIO = '--stdio'

---How to start the server.
---@class LangPython.Launch
---@field program string
---@field args string[]
---@field script string What the Tools panel shows as the program's place.
---@field version? string The package's version.

---@class LangPython.ProgramModule
local M = {}

---Reads and decodes a JSON file on disk, or gives nil.
---@param app Proteus.App
---@param path string
---@param cb fun(value: any)
local function read_json (app, path, cb)
  app.fs.read_file (path, function (text)
    local ok, value = false, nil
    if text then
      ok, value = pcall (app.json.decode, text)
    end
    cb (ok and value or nil)
  end)
end

---Finds the server's script in the first of these package folders that has one.
---@param app Proteus.App
---@param dirs string[]
---@param cb fun(script: string?, version: string?)
local function first_script (app, dirs, cb)
  ---@param i integer
  local function try (i)
    local dir = dirs[i]
    if not dir then
      cb (nil, nil)
      return
    end
    read_json (app, dir .. '/package.json', function (manifest)
      local rel = launch.bin (manifest, launch.PROGRAM)
      if rel then
        local version = manifest.version
        cb (dir .. '/' .. rel, version and tostring (version) or nil)
      else
        try (i + 1)
      end
    end)
  end
  try (1)
end

---Finds the server through npm's files, or on the PATH.
---@param app Proteus.App
---@param tool Proteus.ToolHandle
---@param root string? The project folder.
---@param cb fun(found: LangPython.Launch?, why: string?)
local function from_npm (app, tool, root, cb)
  ---@param program string?
  local function search (program)
    first_script (
      app,
      launch.package_dirs (root, program),
      function (script, version)
        if not script then
          if program and launch.runs_directly (program, app.os) then
            cb ({ program = program, args = { STDIO }, script = program })
          else
            cb (nil, launch.PROGRAM .. ' is not installed')
            tool.offer ()
          end
          return
        end
        app.process.which ('node', function (node)
          if not node then
            cb (nil, 'node is not on the PATH')
            return
          end
          cb ({
            program = node,
            args = { script, STDIO },
            script = script,
            version = version,
          })
        end)
      end
    )
  end
  -- The PATH first, then the copy the Tools panel installed.
  app.process.which (launch.PROGRAM, function (on_path)
    if on_path then
      search (on_path)
    else
      tool.cached (search)
    end
  end)
end

---Finds the server. `cb` gets nil and the reason when it is not installed.
---@param app Proteus.App
---@param tool Proteus.ToolHandle
---@param root string? The project folder.
---@param python string? The project's Python.
---@param cb fun(found: LangPython.Launch?, why: string?)
function M.find (app, tool, root, python, cb)
  if not python then
    from_npm (app, tool, root, cb)
    return
  end
  local beside = venv.beside (python, launch.PROGRAM, app.os)
  app.fs.stat_path (beside, function (stat)
    if stat and stat.exists and not stat.dir then
      cb ({ program = beside, args = { STDIO }, script = beside })
      return
    end
    from_npm (app, tool, root, cb)
  end)
end

return M
