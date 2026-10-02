-- Tests for the mouse and the keys on the Sheet app's grid, from sheet_grid_mouse and
-- sheet_grid_keys. The grid is built over a fake page: every element keeps the handlers put
-- on it, and the grid's scrolling box is 900 by 600 pixels at the top left of the window.

local book_mod = require ('sheet_book') --[[@as Sheet.BookModule]]
local calc = require ('sheet_grid_calc') --[[@as Sheet.GridCalcModule]]
local grid_mod = require ('sheet_grid') --[[@as Sheet.GridModule]]

local W, H = calc.HEAD_W, calc.HEAD_H

---@class Sheet.TestHandler
---@field name string
---@field fn fun(ev: table): any

---A grid over a fake page, showing the example book.
---@return Sheet.GridView grid
---@return fun(name: string, ev: table) fire Runs the handlers whose name ends with `name`.
local function grid_of ()
  local handlers = {} ---@type Sheet.TestHandler[]
  local element_mt = {} ---@type table
  ---@param name string
  ---@return table
  local function element (name)
    return setmetatable ({ name = name }, element_mt)
  end
  element_mt.__index = function (t, k)
    if type (k) == 'number' then
      return nil
    elseif k == 'on' then
      return function (self, ev, fn)
        handlers[#handlers + 1] = { name = self.name .. ':' .. ev, fn = fn }
        return function () end
      end
    elseif k == 'get' then
      return function (_, what)
        return ({
          clientHeight = 600,
          clientWidth = 900,
          scrollTop = 0,
          scrollLeft = 0,
        })[what]
      end
    elseif k == 'rect' then
      return function ()
        return { x = 0, y = 0, left = 0, top = 0, width = 900, height = 600 }
      end
    end
    return function ()
      return element (t.name .. '.' .. k)
    end
  end
  local ui = setmetatable ({}, {
    __index = function (_, k)
      return function ()
        return element (k)
      end
    end,
  })
  local dom = setmetatable ({
    on_global = function (ev, fn)
      handlers[#handlers + 1] = { name = 'window:' .. ev, fn = fn }
      return function () end
    end,
    focus_info = function ()
      return { editable = false }
    end,
  }, {
    __index = function (_, k)
      return function ()
        return element ('dom.' .. k)
      end
    end,
  })
  local app = setmetatable ({
    use = function ()
      return ui
    end,
    try_use = function ()
      return nil
    end,
    dom = dom,
    timer = {
      after = function ()
        return function () end
      end,
    },
  }, {
    __index = function (_, k)
      return element ('app.' .. k)
    end,
  })
  local grid = grid_mod.new (app --[[@as Proteus.App]], {
    emit = function () end,
    say = function () end,
    dirty = function () end,
  })
  grid.set_book (book_mod.example ())
  ---@param name string
  ---@param ev table
  local function fire (name, ev)
    for _, h in ipairs (handlers) do
      if string.sub (h.name, -#name) == name then
        h.fn (ev)
      end
    end
  end
  return grid, fire
end

---A key going down on the grid.
---@param name string
---@param shift? boolean
---@return Proteus.DomEvent
local function key (name, shift)
  return { type = 'keydown', key = name, shift = shift }
end

---@param grid Sheet.GridView
---@return integer[]
local function sel (grid)
  return { grid.sel.r, grid.sel.c, grid.sel.er, grid.sel.ec }
end

test (
  'the arrows move the active cell, and Shift grows the selection',
  function ()
    local grid = grid_of ()
    eq (sel (grid), { 1, 1, 1, 1 })
    eq (grid.grid_key (key ('ArrowDown')), 'prevent')
    eq (grid.grid_key (key ('ArrowRight')), 'prevent')
    eq (sel (grid), { 2, 2, 2, 2 })
    grid.grid_key (key ('ArrowDown', true))
    grid.grid_key (key ('ArrowRight', true))
    eq (sel (grid), { 2, 2, 3, 3 })
    eq (grid.grid_key (key ('a')), nil, 'a letter types into the cell editor')
  end
)

test ('a press selects a cell, and a drag selects a block', function ()
  local grid, fire = grid_of ()
  local geo = assert (grid.geo, 'the grid has its geometry')
  ---@param row integer
  ---@param col integer
  ---@return table
  local function at (row, col)
    return {
      x = W + geo.lefts[col] + 5,
      y = H + geo.tops[row] + 5,
      button = 0,
      buttons = 1,
    }
  end
  fire ('div:mousedown', at (6, 2))
  eq (sel (grid), { 6, 2, 6, 2 })
  fire ('window:mousemove', at (8, 3))
  fire ('window:mouseup', at (8, 3))
  eq (sel (grid), { 6, 2, 8, 3 })
end)
