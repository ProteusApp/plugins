-- program: finds how to start the language server. The project's own copy of
-- vscode-langservers-extracted wins over the global one. Either way, `node` runs the
-- package's script, since npm's files on Windows cannot start on their own.

local launch = require ('lib.launch') --[[@as LangJson.LaunchModule]]

---How to start the server.
---@class LangJson.Launch
---@field program string
---@field args string[]
---@field script string What the Tools panel shows as the program's place.
---@field version? string The package's version.

---@class LangJson.ProgramModule
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

---Finds `node` and the server's script. `cb` gets nil and the reason when either is missing.
---When the package is nowhere, the Tools panel offers to install it.
---@param app Proteus.App
---@param tool Proteus.ToolHandle
---@param root string? The project folder.
---@param cb fun(found: LangJson.Launch?, why: string?)
function M.find (app, tool, root, cb)
  ---@param program string?
  local function search (program)
    first_script (
      app,
      launch.package_dirs (root, program),
      function (script, version)
        if not script then
          -- Outside Windows, npm's program is the script itself and starts on its own.
          if program and launch.runs_directly (program, app.os) then
            cb ({ program = program, args = { '--stdio' }, script = program })
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
            args = { script, '--stdio' },
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

return M
