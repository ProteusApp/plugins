-- Tests for the parts init.lua installs, against a small fake app: sheet_files keeps the
-- workbook files, and sheet_commands and sheet_menus register what acts on them.

local commands_mod = require ('sheet_commands') --[[@as Sheet.CommandsModule]]
local files_mod = require ('sheet_files') --[[@as Sheet.FilesModule]]
local menus_mod = require ('sheet_menus') --[[@as Sheet.MenusModule]]

---An object whose every field is a function that does nothing and returns another such
---object, except the fields given.
---@param fields? table<string, any>
---@return any
local function anything (fields)
  local t = fields or {}
  return setmetatable (t, {
    __index = function (_, k)
      if k == 'edit' or type (k) == 'number' then
        return nil
      end
      return function ()
        return anything ()
      end
    end,
  })
end

---A fake app with its files and store in memory, and the timers it asked for.
---@return table app
---@return table<string, string> fs
---@return (fun())[] timers
local function fake_app ()
  local fs = {} ---@type table<string, string>
  local store = {} ---@type table<string, any>
  local timers = {} ---@type (fun())[]
  local app = {
    platform = 'desktop',
    try_use = function ()
      return nil
    end,
    on = function () end,
    dispose = function () end,
    util = {
      icon = function ()
        return ''
      end,
      escape = function (s)
        return s
      end,
    },
    timer = {
      after = function (_, fn)
        timers[#timers + 1] = fn
        return function () end
      end,
    },
    store = {
      get = function (k, d)
        if store[k] == nil then
          return d
        end
        return store[k]
      end,
      set = function (k, v)
        store[k] = v
      end,
    },
    fs = {
      list = function (dir)
        local out = {}
        for path in pairs (fs) do
          local name = string.match (path, '^' .. dir .. '/([^/]+)$')
          if name then
            out[#out + 1] = { name = name, dir = false }
          end
        end
        return out
      end,
      read = function (path)
        return fs[path]
      end,
      write = function (path, text)
        fs[path] = text
      end,
      remove = function (path)
        fs[path] = nil
      end,
      rename = function (a, b)
        fs[b], fs[a] = fs[a], nil
      end,
    },
  }
  return app, fs, timers
end

---@return Sheet.Files files
---@return table<string, string> fs
---@return (fun())[] timers
---@return string[] events
local function install ()
  local app, fs, timers = fake_app ()
  local events = {} ---@type string[]
  local files = files_mod.install ({
    app = app --[[@as Proteus.App]],
    ui = anything () --[[@as Proteus.UI]],
    views = anything () --[[@as Proteus.Views]],
    grid = anything ({
      sel_rect = function ()
        return { r1 = 1, c1 = 1, r2 = 1, c2 = 1 }
      end,
    }) --[[@as Sheet.GridView]],
    say = function (kind, text)
      events[#events + 1] = kind .. ': ' .. text
    end,
    safely = function (_, fn)
      fn ()
    end,
    emit = function (event)
      events[#events + 1] = event
    end,
    show_screen = function () end,
  })
  return files, fs, timers, events
end

local BUDGET = 'data/proteus.sheet/Budget.sheet.json'

test ('the first start writes the example and opens it', function ()
  local files, fs = install ()
  eq (files.book (), nil)
  ok (files.start (), 'a workbook opened')
  ok (fs[BUDGET] ~= nil, 'the example is written')
  eq (files.file (), 'Budget')
  eq (assert (files.book ()):names (), { 'Budget', 'Income' })
  eq (files.disk (), nil)
end)

test (
  'a change saves a moment later, and new, duplicate and delete work on files',
  function ()
    local files, fs, timers = install ()
    files.start ()
    local before = fs[BUDGET]
    local book = assert (files.book ())
    book:active_sheet ():set (1, 1, 'Changed')
    files.dirty ()
    eq (#timers, 1, 'the save waits')
    timers[1] ()
    ok (fs[BUDGET] ~= before, 'the timer saved the workbook')
    files.new_workbook ()
    eq (files.file (), 'Workbook')
    ok (fs['data/proteus.sheet/Workbook.sheet.json'] ~= nil)
    files.duplicate_file ('Budget')
    eq (files.file (), 'Budget copy')
    files.delete_file ('Budget copy')
    eq (fs['data/proteus.sheet/Budget copy.sheet.json'], nil)
    ok (files.book () ~= nil, 'another workbook opens in its place')
  end
)

---@param files Sheet.Files
---@return table<string, Proteus.CommandSpec> by_id
---@return (fun(ev: table): Proteus.MenuItem[]?)[] menus
local function install_parts (files)
  local by_id = {} ---@type table<string, Proteus.CommandSpec>
  local menus = {} ---@type (fun(ev: table): Proteus.MenuItem[]?)[]
  ---@type Sheet.AppEnv
  local env = {
    keys_label = function (combo)
      return combo
    end,
    views = anything () --[[@as Proteus.Views]],
    commands = anything ({
      register = function (spec)
        ok (by_id[spec.id] == nil, spec.id .. ' is registered once')
        by_id[spec.id] = spec
        return spec
      end,
    }) --[[@as Proteus.Commands]],
    menus = anything ({
      attach = function (_, fn)
        menus[#menus + 1] = fn
      end,
    }) --[[@as Proteus.Menus]],
    grid = anything ({
      view_opts = { gridlines = true, formulas = false },
      sel = { r = 1, c = 1 },
    }) --[[@as Sheet.GridView]],
    files = files,
    on = function ()
      return function () end
    end,
    emit = function () end,
  }
  commands_mod.install (env)
  menus_mod.install (env)
  return by_id, menus
end

test ('the commands act on the open workbook file', function ()
  local files = install ()
  local by_id = install_parts (files)
  for id, spec in pairs (by_id) do
    eq (spec.category, 'Sheet', id)
  end
  local rename = assert (by_id['sheet.rename'], 'sheet.rename')
  eq (rename.when (), false, 'no workbook is open yet')
  files.start ()
  eq (rename.when (), true)
  ok (by_id['sheet.undo'] and by_id['sheet.new'] and by_id['sheet.save'])
end)

test (
  'the workbook list has a menu for each workbook and one for none',
  function ()
    local files = install ()
    local _, menus = install_parts (files)
    eq (#menus, 2, 'one for the grid and one for the workbook list')
    local none = assert (menus[2] ({}))
    eq (none[1].label, 'New workbook')
    local labels = {} ---@type string[]
    for _, item in ipairs (assert (menus[2] ({ item = 'Budget' }))) do
      labels[#labels + 1] = item.label or '-'
    end
    eq (labels, { 'Open', 'Rename…', 'Duplicate', '-', 'Delete…' })
    eq (
      menus[1] ({ x = 0, y = 0 }),
      nil,
      'no menu on the grid without a workbook'
    )
  end
)
