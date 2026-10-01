-- program: finds how to start the language server, and which TypeScript it should use. The
-- project's own copy of typescript-language-server wins over the global one. Either way,
-- `node` runs the package's script, since npm's `.cmd` file cannot start on its own.

local disk = require ('disk_paths') --[[@as DiskPaths]]
local launch = require ('lib.launch') --[[@as LangTypescript.LaunchModule]]

---How to start the server.
---@class LangTypescript.Launch
---@field program string
---@field args string[]
---@field script string What the Tools panel shows as the program's place.
---@field version? string The package's version.
---@field package_dir? string The server's package folder.

---Which TypeScript the server runs.
---@class LangTypescript.Libraries
---@field path? string The project's own TypeScript library folder.
---@field fallback? string The one beside the server's package, for a project without a usable one.

---@class LangTypescript.ProgramModule
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
---@param cb fun(script: string?, version: string?, dir: string?)
local function first_script (app, dirs, cb)
  ---@param i integer
  local function try (i)
    local dir = dirs[i]
    if not dir then
      cb (nil, nil, nil)
      return
    end
    read_json (app, dir .. '/package.json', function (manifest)
      local rel = launch.bin (manifest, launch.PACKAGE)
      if rel then
        local version = manifest.version
        cb (dir .. '/' .. rel, version and tostring (version) or nil, dir)
      else
        try (i + 1)
      end
    end)
  end
  try (1)
end

---Finds `node` and the server's script. `cb` gets nil and the reason when either is missing.
---@param app Proteus.App
---@param root string? The project folder.
---@param cb fun(found: LangTypescript.Launch?, why: string?)
function M.find (app, root, cb)
  app.process.which (launch.PACKAGE, function (program)
    first_script (
      app,
      launch.package_dirs (root, program),
      function (script, version, dir)
        if not script then
          -- Outside Windows, npm's program is the script itself and starts on its own.
          if program and launch.runs_directly (program, app.os) then
            cb ({ program = program, args = { '--stdio' }, script = program })
          else
            cb (nil, 'typescript-language-server is not installed')
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
            package_dir = dir,
          })
        end)
      end
    )
  end)
end

---The TypeScript library folder at `lib`, when it holds the server part. TypeScript 7 is a
---native program without one, so it cannot serve.
---@param app Proteus.App
---@param lib string?
---@param cb fun(lib: string?)
local function usable (app, lib, cb)
  if not lib then
    cb (nil)
    return
  end
  app.fs.stat_path (lib .. '/tsserver.js', function (stat)
    cb (stat and stat.exists and not stat.dir and lib or nil)
  end)
end

---The project's own TypeScript, when `root` is given and it has one the server can run, and
---the TypeScript installed beside the server's package. The server falls back to the second
---when the project's TypeScript is missing or cannot run.
---@param app Proteus.App
---@param root string?
---@param found LangTypescript.Launch
---@param cb fun(libraries: LangTypescript.Libraries)
function M.libraries (app, root, found, cb)
  local own = root and disk.join (root, 'node_modules/typescript/lib') or nil
  local beside = found.package_dir
      and (disk.parent (found.package_dir) .. '/typescript/lib')
    or nil
  usable (app, own, function (path)
    usable (app, beside, function (fallback)
      cb ({ path = path, fallback = fallback })
    end)
  end)
end

return M
