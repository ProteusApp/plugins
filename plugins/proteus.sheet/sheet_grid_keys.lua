-- sheet_grid_keys: the keys on the Sheet app's grid while no cell is being edited: the arrows,
-- paging and jumps, Shift to grow the selection, and the keys that act on a selected chart.
-- Anything else types into the waiting cell editor. sheet_grid.lua installs it.

local calc = require ('sheet_grid_calc') --[[@as Sheet.GridCalcModule]]
local ops = require ('sheet_ops') --[[@as Sheet.OpsModule]]

local HEAD_H = calc.HEAD_H

---@type table<string, { [1]: integer, [2]: integer }>
local ARROWS = {
  ArrowUp = { -1, 0 },
  ArrowDown = { 1, 0 },
  ArrowLeft = { 0, -1 },
  ArrowRight = { 0, 1 },
}

---@class Sheet.GridKeysModule
local M = {}

---@param grid Sheet.GridView
---@param K Sheet.GridKit The parts of the grid that only its own modules use.
function M.install (grid, K)
  local G = grid
  local read_scroll, delete_chart = K.read_scroll, K.delete_chart
  local select_cols, select_rows = K.select_cols, K.select_rows

  -- Keys -----------------------------------------------------------------------------------

  ---Keys on the grid while no cell is being edited. Shortcuts that belong to commands reach
  ---core.keys first.
  ---@param ev Proteus.DomEvent
  ---@return Proteus.EventResult
  function G.grid_key (ev)
    local s = G.sheet ()
    if not s or ev.composing then
      return nil
    end
    local key = ev.key or ''
    local mod = ev.ctrl == true or ev.meta == true
    if G.chart_id then
      if key == 'Delete' or key == 'Backspace' then
        delete_chart ()
        return 'prevent'
      end
      if key == 'Escape' then
        G.select_chart (nil)
        return 'prevent'
      end
      if not mod and #key == 1 then
        G.select_chart (nil)
      end
    end
    local dir = ARROWS[key]
    if dir then
      if
        key == 'ArrowDown'
        and ev.alt
        and ops.dropdown (s, G.sel.r, G.sel.c)
      then
        G.open_dropdown (G.sel.r, G.sel.c)
        return 'prevent'
      end
      G.move (dir[1], dir[2], ev.shift == true, mod)
      return 'prevent'
    end
    if key == 'Enter' then
      if mod then
        return 'prevent'
      end
      local text = s:edit_text (G.sel.r, G.sel.c)
      if
        not ev.shift
        and text ~= ''
        and G.sel_rect ().r1 == G.sel_rect ().r2
      then
        G.begin_edit ('cell', text, false)
      else
        G.move (ev.shift and -1 or 1, 0)
      end
      return 'prevent'
    end
    if key == 'Tab' then
      G.move (0, ev.shift and -1 or 1)
      return 'prevent'
    end
    if key == 'Home' then
      if mod then
        -- A1 may sit in a frozen pane, where it shows at any scroll, so scroll back too.
        G.scroll:set ('scrollLeft', 0)
        G.scroll:set ('scrollTop', 0)
        read_scroll ()
        G.select_cell (1, 1, ev.shift)
        G.draw ()
      else
        G.select_cell (G.sel.r, 1, ev.shift)
      end
      return 'prevent'
    end
    if key == 'End' and mod then
      local rows, cols = s:used ()
      G.select_cell (math.max (1, rows), math.max (1, cols), ev.shift)
      return 'prevent'
    end
    if (key == 'PageDown' or key == 'PageUp') and not mod then
      local geo = G.geo
      local page = 20
      if geo then
        local first, last = calc.seen_rows (geo, G.sy, G.vh)
        page = math.max (1, last - first - 1)
      end
      local sign = key == 'PageDown' and 1 or -1
      local target = math.max (
        1,
        math.min (s.rows, (ev.shift and G.sel.er or G.sel.r) + sign * page)
      )
      if not ev.shift then
        G.scroll:set (
          'scrollTop',
          math.max (0, G.sy + sign * (G.vh - HEAD_H - (geo and geo.fh or 0)))
        )
        read_scroll ()
      end
      G.select_cell (target, ev.shift and G.sel.ec or G.sel.c, ev.shift)
      return 'prevent'
    end
    if key == 'F2' then
      G.begin_edit ('cell', s:edit_text (G.sel.r, G.sel.c), false)
      return 'prevent'
    end
    if key == 'Delete' or key == 'Backspace' then
      G.clear ()
      return 'prevent'
    end
    if key == 'Escape' then
      G.drop_clip ()
      return 'prevent'
    end
    if key == ' ' and (ev.shift or mod) and not ev.alt then
      if mod then
        select_cols (G.sel.c, false, true)
      else
        select_rows (G.sel.r, false, true)
      end
      return 'prevent'
    end
    if mod and string.lower (key) == 'v' and ev.shift then
      G.paste_mode = { only = 'values' }
    end
    -- Anything else types into the waiting editor box. Ctrl+V pastes into it.
    return nil
  end
end

return M
