-- sheet_grid_mouse: the mouse on the Sheet app's grid. Pressing selects cells, rows and
-- columns, a drag selects a block, fills from the fill handle, moves a block by its edge,
-- sizes a row or a column by its header's edge, or moves and sizes a chart, and the view
-- scrolls while a drag passes its edge. A double click edits a cell or auto-fits a header,
-- and a note shows beside its cell while the pointer rests there. sheet_grid.lua installs it.

local calc = require ('sheet_grid_calc') --[[@as Sheet.GridCalcModule]]
local draw = require ('sheet_grid_draw') --[[@as Sheet.GridDrawModule]]
local ops = require ('sheet_ops') --[[@as Sheet.OpsModule]]

local HEAD_W, HEAD_H = calc.HEAD_W, calc.HEAD_H

---@param rect Sheet.Rect
---@param r integer
---@param c integer
---@return boolean
local function inside (rect, r, c)
  return r >= rect.r1 and r <= rect.r2 and c >= rect.c1 and c <= rect.c2
end

---@class Sheet.GridMouseModule
local M = {}

---@param grid Sheet.GridView
---@param K Sheet.GridKit The parts of the grid that only its own modules use.
function M.install (grid, K)
  local G = grid
  local app, env = G.app, G.env
  local drag_style, read_scroll, map_y, scroll_rect =
    K.drag_style, K.read_scroll, K.map_y, K.scroll_rect
  local select_cols, select_rows, open_chart =
    K.select_cols, K.select_rows, K.open_chart

  -- The mouse ------------------------------------------------------------------------------

  local stop_scroller = nil ---@type fun()?

  ---@param x number
  ---@param y number
  local function drag_to (x, y)
    local d = G.drag
    local s, geo = G.sheet (), G.geo
    if not d or not s or not geo then
      return
    end
    d.x, d.y = x, y
    local sr = scroll_rect ()
    if d.kind == 'csize' or d.kind == 'rsize' then
      local col = d.kind == 'csize'
      local delta = (col and x or y) - d.start
      local lo = col and 24 or 12
      local size = math.max (lo, (d.size or 0) + delta)
      local i = d.index or 1
      local edges = col and geo.lefts or geo.tops
      local frozen = col and geo.fc or geo.fr
      local head = col and HEAD_W or HEAD_H
      local scroll = col and G.sx or G.sy
      local at = head + edges[i] + size - (i > frozen and scroll or 0)
      if col then
        G.guide:style ({
          display = 'block',
          left = at .. 'px',
          top = '0',
          width = '2px',
          height = '100%',
        })
      else
        G.guide:style ({
          display = 'block',
          top = at .. 'px',
          left = '0',
          height = '2px',
          width = '100%',
        })
      end
      return
    end
    if d.kind == 'chart' then
      local box = d.box
      if not box or not d.chart then
        return
      end
      local now = draw.drag_box (
        box,
        d.handle or 'move',
        x - (d.row or 0),
        y - (d.col or 0),
        60
      )
      d.now = now
      drag_style:set (
        '.sheet-grid-chart[data-item="chart:'
          .. calc.escape (d.chart)
          .. '"]{left:'
          .. (HEAD_W + now.x)
          .. 'px!important;top:'
          .. (HEAD_H + map_y (now.y))
          .. 'px!important;width:'
          .. now.w
          .. 'px!important;height:'
          .. now.h
          .. 'px!important}'
      )
      return
    end
    local hit = calc.hit (geo, x - sr.left, y - sr.top, G.sx, G.sy)
    local key = hit.row .. ',' .. hit.col
    if key == d.last then
      return
    end
    d.last = key
    if d.kind == 'cells' then
      G.sel.er, G.sel.ec = hit.row, hit.col
      G.place ()
    elseif d.kind == 'rows' then
      select_rows (hit.row, true)
    elseif d.kind == 'cols' then
      select_cols (hit.col, true)
    elseif d.kind == 'point' then
      G.point_at (hit.row, hit.col, true)
    elseif d.kind == 'fill' then
      d.target = calc.fill_target (G.sel_rect (), hit.row, hit.col)
      G.set_box ('target', d.target)
    elseif d.kind == 'move' then
      d.target = calc.move_target (
        G.sel_rect (),
        d.row or 1,
        d.col or 1,
        hit.row,
        hit.col,
        s.rows,
        s.cols
      )
      G.set_box ('target', d.target)
    end
  end

  ---Scrolls while a drag holds the pointer past the edge of the view.
  local function auto_scroll ()
    local d = G.drag
    local geo = G.geo
    if not d or not geo then
      return
    end
    local kinds = {
      cells = true,
      rows = true,
      cols = true,
      point = true,
      fill = true,
      move = true,
    }
    if not kinds[d.kind] then
      return
    end
    local sr = scroll_rect ()
    local x, y = d.x - sr.left, d.y - sr.top
    local dx, dy = 0, 0
    if x > G.vw - 4 then
      dx = 30
    elseif x < HEAD_W + geo.fw and G.sx > 0 and d.kind ~= 'rows' then
      dx = -30
    end
    if y > G.vh - 4 then
      dy = 24
    elseif y < HEAD_H + geo.fh and G.sy > 0 and d.kind ~= 'cols' then
      dy = -24
    end
    if dx == 0 and dy == 0 then
      if stop_scroller then
        stop_scroller ()
        stop_scroller = nil
      end
      return
    end
    if stop_scroller then
      return
    end
    stop_scroller = app.timer.every (40, function ()
      local dd = G.drag
      if not dd then
        if stop_scroller then
          stop_scroller ()
          stop_scroller = nil
        end
        return
      end
      if dx ~= 0 then
        G.scroll:set ('scrollLeft', math.max (0, G.sx + dx))
      end
      if dy ~= 0 then
        G.scroll:set ('scrollTop', math.max (0, G.sy + dy))
      end
      read_scroll ()
      if G.needs_draw () then
        G.draw ()
      end
      dd.last = nil
      drag_to (dd.x, dd.y)
    end)
  end

  ---@param kind 'cells'|'rows'|'cols'|'point'|'fill'|'move'|'csize'|'rsize'|'chart'
  ---@param ev Proteus.DomEvent
  ---@return Sheet.GridDrag
  local function start_drag (kind, ev)
    local d = { kind = kind, start = 0, x = ev.x or 0, y = ev.y or 0 } ---@type Sheet.GridDrag
    G.drag = d
    if kind ~= 'fill' then
      G.area:class ('sheet-grid-busy', true)
    end
    return d
  end

  local function end_drag ()
    local d = G.drag
    G.drag = nil
    G.area:class ('sheet-grid-busy', false)
    if stop_scroller then
      stop_scroller ()
      stop_scroller = nil
    end
    return d
  end

  app.dom.on_global ('mousemove', function (ev)
    if G.drag then
      drag_to (ev.x or 0, ev.y or 0)
      auto_scroll ()
    end
    return nil
  end)

  app.dom.on_global ('mouseup', function ()
    local d = end_drag ()
    if not d then
      return nil
    end
    local s = G.sheet ()
    if not s then
      return nil
    end
    if d.kind == 'csize' or d.kind == 'rsize' then
      G.guide:style ('display', 'none')
      local col = d.kind == 'csize'
      local delta = (col and d.x or d.y) - d.start
      local size = math.max (col and 24 or 12, (d.size or 0) + delta)
      if math.abs (delta) >= 1 and d.index then
        local rect = G.sel_rect ()
        local idx = d.index --[[@as integer]]
        local lo, hi = idx, idx
        -- A size set on one of several whole rows or columns goes on all of them.
        if
          col
          and rect.r1 == 1
          and rect.r2 >= s.rows
          and d.index >= rect.c1
          and d.index <= rect.c2
        then
          lo, hi = rect.c1, rect.c2
        elseif
          not col
          and rect.c1 == 1
          and rect.c2 >= s.cols
          and d.index >= rect.r1
          and d.index <= rect.r2
        then
          lo, hi = rect.r1, rect.r2
        end
        G.change (col and 'Column width' or 'Row height', function (_, sh)
          if col then
            sh:set_widths (lo, hi, size)
          else
            sh:set_heights (lo, hi, size)
          end
        end)
      end
    elseif d.kind == 'fill' then
      G.set_box ('target', nil)
      local target = d.target
      if target then
        local src = G.sel_rect ()
        local done = G.change ('Fill', function (_, sh)
          return ops.fill (sh, src, target)
        end) --[[@as Sheet.Rect?]]
        G.select (done or target)
      end
    elseif d.kind == 'move' then
      G.set_box ('target', nil)
      local target = d.target
      local src = G.sel_rect ()
      if target and (target.r1 ~= src.r1 or target.c1 ~= src.c1) then
        G.change ('Move', function (_, sh)
          local taken = sh:copy (src)
          taken.cut = true
          sh:paste (target.r1, target.c1, taken)
        end)
        G.drop_clip ()
        G.select (target)
      end
    elseif d.kind == 'chart' then
      local now, id = d.now, d.chart
      drag_style:set ('')
      if now and id and d.box then
        local b = d.box --[[@as Sheet.GridBox]]
        local box = now --[[@as Sheet.GridBox]]
        if box.x ~= b.x or box.y ~= b.y or box.w ~= b.w or box.h ~= b.h then
          G.change ('Move chart', function (_, sh)
            ops.update_chart (sh, id, {
              x = math.floor (box.x + 0.5),
              y = math.floor (box.y + 0.5),
              w = math.floor (box.w + 0.5),
              h = math.floor (box.h + 0.5),
            })
          end)
        end
      end
    end
    G.place_boxes ()
    return nil
  end)

  ---True when a point lies in the button area at the right of a cell.
  ---@param x number
  ---@param row integer
  ---@param col integer
  ---@return boolean
  local function on_button (x, row, col)
    local rect = G.cell_rect (row, col)
    return rect ~= nil and x >= rect.right - calc.BUTTON_W and x <= rect.right
  end

  ---The link on the cell a click landed on, or on the merged block it starts.
  ---@param s Sheet.Sheet
  ---@param hit Sheet.GridHit
  ---@return string?
  local function link_at (s, hit)
    if hit.zone ~= 'cell' or hit.past_x ~= 0 or hit.past_y ~= 0 then
      return nil
    end
    local m = s:merge_at (hit.row, hit.col)
    if m then
      return s:link (m.r1, m.c1)
    end
    return s:link (hit.row, hit.col)
  end

  ---Opens the filter menu of a column, or the dropdown of a list cell, when a click lands on
  ---its button. Returns true when it did.
  ---@param x number
  ---@param row integer
  ---@param col integer
  ---@return boolean
  local function press_button (x, row, col)
    local s = G.sheet ()
    if not s then
      return false
    end
    local f = s.filter
    if
      f
      and row == f.rect.r1
      and col >= f.rect.c1
      and col <= f.rect.c2
      and on_button (x, row, col)
    then
      local rect = G.cell_rect (row, col) --[[@as Proteus.Rect]]
      local bx = rect.right - calc.BUTTON_W
      env.emit ('filter_menu', col, {
        x = bx,
        y = rect.top,
        w = calc.BUTTON_W,
        h = rect.h,
        left = bx,
        top = rect.top,
        right = rect.right,
        bottom = rect.bottom,
      })
      return true
    end
    if ops.dropdown (s, row, col) and on_button (x, row, col) then
      G.open_dropdown (row, col)
      return true
    end
    return false
  end

  local last_fill = 0
  -- When a double press on the fill handle last filled, so the browser's double-click that
  -- follows, now over another cell, does not start an edit there.
  local filled_at = 0

  G.scroll:on ('mouseenter', function ()
    G.srect = nil
    return nil
  end)

  G.scroll:on ('mousedown', function (ev)
    local s = G.sheet ()
    if not s or not G.geo then
      return nil
    end
    G.srect = nil
    local item = ev.item or ''
    local x, y = ev.x or 0, ev.y or 0
    G.tip:style ('display', 'none')
    -- Charts.
    local chart_id, handle = string.match (item, '^chart:(.-):(%a+)$')
    if not chart_id then
      chart_id = string.match (item, '^chart:(.+)$')
    end
    if chart_id then
      if G.edit then
        G.finish_edit (0, 0)
      end
      local spec = ops.chart_by_id (s, chart_id)
      if spec and ev.button == 0 then
        G.select_chart (chart_id)
        local d = start_drag ('chart', ev)
        d.chart = chart_id
        d.handle = handle or 'move'
        d.box = { x = spec.x, y = spec.y, w = spec.w, h = spec.h }
        d.row, d.col = math.floor (x), math.floor (y)
      elseif spec then
        G.select_chart (chart_id)
      end
      G.focus ()
      return 'prevent'
    end
    local hit = G.hit_at (x, y) --[[@as Sheet.GridHit]]
    if ev.button == 2 then
      -- A right-click outside the selection selects what is under it first.
      if G.edit then
        return nil
      end
      local rect = G.sel_rect ()
      if hit.zone == 'cell' and not inside (rect, hit.row, hit.col) then
        G.select_cell (hit.row, hit.col)
      elseif
        hit.zone == 'col'
        and not (
          hit.col >= rect.c1
          and hit.col <= rect.c2
          and rect.r1 == 1
          and rect.r2 >= s.rows
        )
      then
        select_cols (hit.col)
      elseif
        hit.zone == 'row'
        and not (
          hit.row >= rect.r1
          and hit.row <= rect.r2
          and rect.c1 == 1
          and rect.c2 >= s.cols
        )
      then
        select_rows (hit.row)
      end
      G.focus ()
      return 'prevent'
    end
    if ev.button ~= 0 then
      return nil
    end
    local csize = tonumber (string.match (item, '^csize:(%d+)$'))
    local rsize = tonumber (string.match (item, '^rsize:(%d+)$'))
    if csize or rsize then
      if G.edit then
        G.finish_edit (0, 0)
      end
      local d = start_drag (csize and 'csize' or 'rsize', ev)
      d.index = math.floor (csize or rsize --[[@as number]])
      d.start = csize and x or y
      d.size = csize and s:width (d.index) or s:height (d.index)
      drag_to (x, y)
      return 'prevent'
    end
    if item == 'fill' and not G.edit then
      -- The handle hides while it is dragged, so a double-click never reaches it. A second
      -- press soon after the first counts as one instead.
      local now = app.util.now ()
      if now - last_fill < 400 then
        last_fill = 0
        filled_at = now
        G.fill_to_end ()
        return 'prevent'
      end
      last_fill = now
      start_drag ('fill', ev)
      return 'prevent'
    end
    if item == 'move' and not G.edit then
      local d = start_drag ('move', ev)
      d.row, d.col = hit.row, hit.col
      d.last = hit.row .. ',' .. hit.col
      return 'prevent'
    end
    if G.edit then
      if
        hit.zone == 'cell'
        and G.point_at (
          hit.row,
          hit.col,
          ev.shift == true and G.edit.point ~= nil
        )
      then
        local d = start_drag ('point', ev)
        d.last = hit.row .. ',' .. hit.col
        return 'prevent'
      end
      if not G.finish_edit (0, 0) then
        return 'prevent'
      end
    end
    if hit.zone == 'corner' then
      G.select ({ r1 = 1, c1 = 1, r2 = s.rows, c2 = s.cols })
    elseif hit.zone == 'col' then
      select_cols (hit.col, ev.shift)
      local d = start_drag ('cols', ev)
      d.last = hit.row .. ',' .. hit.col
    elseif hit.zone == 'row' then
      select_rows (hit.row, ev.shift)
      local d = start_drag ('rows', ev)
      d.last = hit.row .. ',' .. hit.col
    elseif not ev.shift and press_button (x, hit.row, hit.col) then
      G.select_cell (hit.row, hit.col)
    elseif (ev.ctrl or ev.meta) and not ev.shift and link_at (s, hit) then
      -- Ctrl+click follows a link, as in other spreadsheets.
      G.select_cell (hit.row, hit.col)
      local m = s:merge_at (hit.row, hit.col)
      G.follow_link (m and m.r1 or hit.row, m and m.c1 or hit.col)
    else
      G.select_cell (hit.row, hit.col, ev.shift)
      local d = start_drag ('cells', ev)
      d.last = hit.row .. ',' .. hit.col
    end
    G.focus ()
    return 'prevent'
  end)

  G.scroll:on ('dblclick', function (ev)
    local s = G.sheet ()
    if not s then
      return nil
    end
    local item = ev.item or ''
    local chart_id = string.match (item, '^chart:([^:]+)')
    if chart_id then
      open_chart (chart_id)
      return 'prevent'
    end
    if item == 'fill' or app.util.now () - filled_at < 600 then
      return 'prevent'
    end
    local csize = tonumber (string.match (item, '^csize:(%d+)$'))
    if csize then
      local rect = G.sel_rect ()
      local cols = { math.floor (csize) } ---@type integer[]
      if
        rect.r1 == 1
        and rect.r2 >= s.rows
        and csize >= rect.c1
        and csize <= rect.c2
      then
        cols = {}
        for c = rect.c1, rect.c2 do
          cols[#cols + 1] = c
        end
      end
      G.autofit (cols)
      return 'prevent'
    end
    local rsize = tonumber (string.match (item, '^rsize:(%d+)$'))
    if rsize then
      G.autofit_row ({ math.floor (rsize) })
      return 'prevent'
    end
    local hit = G.hit_at (ev.x or 0, ev.y or 0)
    if hit and hit.zone == 'cell' and not G.edit then
      if press_button (ev.x or 0, hit.row, hit.col) then
        return 'prevent'
      end
      G.select_cell (hit.row, hit.col)
      G.begin_edit ('cell', s:edit_text (G.sel.r, G.sel.c), false)
      return 'prevent'
    end
    return nil
  end)

  -- Notes show beside their cell while the pointer rests on it.
  local tip_cell = ''
  local cancel_tip = nil ---@type fun()?
  G.scroll:on ('mousemove', function (ev)
    if G.drag then
      return nil
    end
    local s = G.sheet ()
    local hit = s and G.hit_at (ev.x or 0, ev.y or 0)
    local key = ''
    local note = nil ---@type string?
    if
      s
      and hit
      and hit.zone == 'cell'
      and hit.past_x == 0
      and hit.past_y == 0
    then
      local m = s:merge_at (hit.row, hit.col)
      local r, c = hit.row, hit.col
      if m then
        r, c = m.r1, m.c1
      end
      note = s:note (r, c)
      local link = s:link (r, c)
      if link then
        local how = string.sub (link, 1, 1) == '#' and 'go there' or 'copy it'
        note = (note and (note .. '\n\n') or '')
          .. link
          .. '\nCtrl+click to '
          .. how
          .. '.'
      end
      if note then
        key = r .. ',' .. c
      end
    end
    if key == tip_cell then
      return nil
    end
    tip_cell = key
    if cancel_tip then
      cancel_tip ()
      cancel_tip = nil
    end
    G.tip:style ('display', 'none')
    if note and hit then
      local text = note
      local row, col = hit.row, hit.col
      cancel_tip = app.timer.after (250, function ()
        cancel_tip = nil
        local rect = G.cell_rect (row, col)
        if not rect or G.drag or G.edit then
          return
        end
        G.tip:text (text)
        G.tip:style ({
          display = 'block',
          left = (rect.right + 6) .. 'px',
          top = rect.top .. 'px',
        })
      end)
    end
    return nil
  end)

  G.scroll:on ('mouseleave', function ()
    tip_cell = ''
    if cancel_tip then
      cancel_tip ()
      cancel_tip = nil
    end
    G.tip:style ('display', 'none')
    return nil
  end)
end

return M
