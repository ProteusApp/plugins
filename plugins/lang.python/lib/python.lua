-- python: finds the project's Python. The `python.interpreter` setting wins. Then comes the
-- one picked with Select Interpreter for this folder, then a `.venv` or `venv` folder in the
-- project, then `python` or `python3` on the PATH. A Python on the PATH must run before it
-- counts, since Windows puts a `python` on the PATH that only opens the Microsoft Store.

local disk = require ('disk_paths') --[[@as DiskPaths]]
local venv = require ('lib.venv') --[[@as LangPython.VenvModule]]

-- Where the folders' picks are kept in the plugin's store, by folder.
local STORE_KEY = 'interpreters'

---A Python, and how it was found.
---@class LangPython.Found
---@field path string
---@field how 'setting'|'picked'|'venv'|'path'

---@class LangPython.Python
---@field find fun(root: string?, cb: fun(found: LangPython.Found?)) The Python for a folder.
---@field choices fun(root: string?, cb: fun(list: LangPython.Found[])) Every Python found for a folder.
---@field picked fun(root: string): string? The Python picked for a folder.
---@field pick fun(root: string, path: string?) Keeps a folder's pick, or forgets it with nil.

---@class LangPython.PythonModule
local M = {}

---@param app Proteus.App
---@param settings Proteus.Settings
---@return LangPython.Python
function M.new (app, settings)
  ---@param root string
  ---@return string
  local function key (root)
    local path = disk.normalize (root)
    return disk.folds_case (app.os) and path:lower () or path
  end

  ---The paths in a list that are files on disk, in order.
  ---@param paths string[]
  ---@param cb fun(found: string[])
  local function existing (paths, cb)
    local out = {} ---@type string[]
    ---@param i integer
    local function step (i)
      local path = paths[i]
      if not path then
        cb (out)
        return
      end
      app.fs.stat_path (path, function (stat)
        if stat and stat.exists and not stat.dir then
          out[#out + 1] = path
        end
        step (i + 1)
      end)
    end
    step (1)
  end

  ---The Pythons on the PATH that run, by their own paths, without repeats.
  ---@param cb fun(found: string[])
  local function on_path (cb)
    local out = {} ---@type string[]
    local seen = {} ---@type table<string, true>
    ---@param i integer
    local function step (i)
      local name = venv.PATH_NAMES[i]
      if not name then
        cb (out)
        return
      end
      app.process.which (name, function (program)
        if not program then
          step (i + 1)
          return
        end
        app.process.run (program, { '-c', venv.WHERE }, nil, function (result)
          local path = result
            and result.code == 0
            and venv.executable (result.stdout)
          if path and not seen[key (path)] then
            seen[key (path)] = true
            out[#out + 1] = path
          end
          step (i + 1)
        end)
      end)
    end
    step (1)
  end

  ---@param root string
  ---@return string?
  local function picked (root)
    local picks = app.store.get (STORE_KEY, {})
    local path = type (picks) == 'table' and picks[key (root)] or nil
    return type (path) == 'string' and path ~= '' and path or nil
  end

  ---@type LangPython.Python
  return {
    find = function (root, cb)
      local wanted = tostring (settings.get ('python.interpreter') or '')
      if wanted ~= '' then
        cb ({ path = disk.normalize (wanted), how = 'setting' })
        return
      end
      local chosen = root and picked (root)
      if chosen then
        cb ({ path = chosen, how = 'picked' })
        return
      end
      existing (venv.candidates (root, app.os), function (envs)
        if envs[1] then
          cb ({ path = envs[1], how = 'venv' })
          return
        end
        on_path (function (list)
          cb (list[1] and { path = list[1], how = 'path' } or nil)
        end)
      end)
    end,

    choices = function (root, cb)
      existing (venv.candidates (root, app.os), function (envs)
        on_path (function (list)
          local out = {} ---@type LangPython.Found[]
          for _, path in ipairs (envs) do
            out[#out + 1] = { path = path, how = 'venv' }
          end
          for _, path in ipairs (list) do
            out[#out + 1] = { path = path, how = 'path' }
          end
          cb (out)
        end)
      end)
    end,

    picked = picked,

    pick = function (root, path)
      local picks = app.store.get (STORE_KEY, {})
      if type (picks) ~= 'table' then
        picks = {}
      end
      picks[key (root)] = path and disk.normalize (path) or nil
      app.store.set (STORE_KEY, picks)
    end,
  }
end

return M
