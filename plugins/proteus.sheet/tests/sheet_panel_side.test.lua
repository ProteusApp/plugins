-- Tests for sheet_panel_side and the panel modules it installs: Chart, Formatting, Validation,
-- Names and Sort. A fake dock shows a panel by running its on_show, and every element is a
-- stand-in, so the tests see what the panels register and open.

local book_mod = require ('sheet_book') --[[@as Sheet.BookModule]]
local ctl_mod = require ('sheet_ctl') --[[@as Sheet.CtlModule]]
local side = require ('sheet_panel_side') --[[@as Sheet.PanelSideModule]]

---Something that takes any call and any field, and gives back another such thing.
---@return any
local function anything ()
  return setmetatable ({}, {
    __index = function (_, k)
      if type (k) == 'number' then
        return nil
      end
      return function ()
        return anything ()
      end
    end,
    __call = function ()
      return anything ()
    end,
  })
end

---Installs the side panels over the example book. Returns the panels, the views they added,
---the ids shown in order, and the controller's emit.
---@return Sheet.SidePanels panels
---@return table<string, Proteus.ViewSpec> views
---@return string[] shown
---@return fun(event: Sheet.CtlEvent, ...: any) emit
local function install ()
  local book = book_mod.example ()
  local on, emit = ctl_mod.events ()
  local views = {} ---@type table<string, Proteus.ViewSpec>
  local shown = {} ---@type string[]
  local services = {
    views = {
      add = function (_, spec)
        views[spec.id] = spec
      end,
      show = function (id)
        shown[#shown + 1] = id
        views[id].on_show ()
      end,
    },
    shell = {
      is_visible = function ()
        return true
      end,
      set_visible = function () end,
    },
  }
  local ctl = setmetatable ({
    book = function ()
      return book
    end,
    sheet = function ()
      return book:active_sheet ()
    end,
    selection = function ()
      return { r1 = 5, c1 = 2, r2 = 10, c2 = 4 }, 5, 2
    end,
    change = function (_, fn)
      return fn (book, book:active_sheet ())
    end,
    editing = function ()
      return false
    end,
    on = on,
    emit = emit,
  }, {
    __index = function ()
      return function () end
    end,
  })
  local app = setmetatable ({
    try_use = function (name)
      return services[name]
    end,
  }, {
    __index = function ()
      return anything ()
    end,
  })
  ---@type Sheet.PanelEnv
  local env = {
    app = app --[[@as Proteus.App]],
    ctl = ctl --[[@as Sheet.Ctl]],
    ui = anything () --[[@as Proteus.UI]],
    commands = anything () --[[@as Proteus.Commands]],
    line = 'thin',
    actions = {},
  }
  return side.install (env), views, shown, emit
end

test ('each panel is a view of the right dock', function ()
  local _, views = install ()
  local titles = {} ---@type string[]
  for _, spec in pairs (views) do
    titles[#titles + 1] = spec.title
  end
  table.sort (titles)
  eq (titles, { 'Chart', 'Formatting', 'Names', 'Sort', 'Validation' })
end)

test ('every panel opens and draws over the example book', function ()
  local panels, _, shown, emit = install ()
  for _, name in ipairs ({ 'rules', 'validation', 'names', 'sort' }) do
    panels.open (name --[[@as Sheet.PanelName]])
    emit ('selection', 5, 2)
    emit ('changed')
  end
  panels.open ('chart', 'c1')
  emit ('changed')
  panels.chart_selected ('c1')
  emit ('sheet')
  emit ('book')
  eq (shown, {
    'sheet.panel.rules',
    'sheet.panel.validation',
    'sheet.panel.names',
    'sheet.panel.sort',
    'sheet.panel.chart',
  })
end)
