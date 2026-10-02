-- python.find against a fake app: a folder's own .venv counts only while the folder is trusted.

-- lib/python.lua needs the app's disk_paths, which the tests cannot reach, so it loads here
-- with a stand-in that does what python.lua asks of it.
local DISK = {
  normalize = function (path)
    return (path:gsub ('\\', '/'))
  end,
  folds_case = function ()
    return false
  end,
}
local modules = {
  disk_paths = DISK,
  ['lib.venv'] = require ('lib.venv'),
} ---@type table<string, any>
local env = {
  require = function (name)
    return modules[name]
  end,
  ipairs = ipairs,
  tostring = tostring,
  type = type,
}
local python_module = assert (
  load (read ('plugins/lang.python/lib/python.lua'), '@lib/python.lua', 't', env)
) () --[[@as LangPython.PythonModule]]

---A fake app where every path in `files` exists and nothing is on the PATH.
---@param files table<string, true>
---@return Proteus.App
local function fake_app (files)
  local store = {} ---@type table<string, any>
  local app = {
    os = 'linux',
    fs = {
      stat_path = function (path, cb)
        cb ({ exists = files[path] == true, dir = false })
      end,
    },
    process = {
      which = function (_, cb)
        cb (nil)
      end,
    },
    store = {
      get = function (key, default)
        local v = store[key]
        if v == nil then
          return default
        end
        return v
      end,
      set = function (key, value)
        store[key] = value
      end,
    },
  }
  return app --[[@as Proteus.App]]
end

local SETTINGS = {
  get = function ()
    return ''
  end,
} --[[@as Proteus.Settings]]

---@param untrusted boolean
---@return LangPython.Found?
local function find (untrusted)
  local app = fake_app ({ ['/home/me/app/.venv/bin/python'] = true })
  local python = python_module.new (app, SETTINGS, untrusted)
  local result = nil ---@type LangPython.Found?
  python.find ('/home/me/app', function (found)
    result = found
  end)
  return result
end

test ('a trusted folder’s .venv is its Python', function ()
  eq (find (false), { path = '/home/me/app/.venv/bin/python', how = 'venv' })
end)

test ('a folder the user does not trust keeps its .venv out', function ()
  eq (find (true), nil)
end)

test ('a Python picked for the folder counts either way', function ()
  local app = fake_app ({})
  local python = python_module.new (app, SETTINGS, true)
  python.pick ('/home/me/app', '/home/me/app/.venv/bin/python')
  local result = nil ---@type LangPython.Found?
  python.find ('/home/me/app', function (found)
    result = found
  end)
  eq (result, { path = '/home/me/app/.venv/bin/python', how = 'picked' })
end)
