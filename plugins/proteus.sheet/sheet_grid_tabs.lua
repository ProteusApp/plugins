-- sheet_grid_tabs: the bar along the bottom of the Sheet app's grid. It holds a button that adds
-- a sheet, a button that lists every sheet, one tab per sheet, and the numbers of the selection
-- when the window has no status bar. sheet_grid.lua installs it into the grid.
--
-- A click on a tab shows its sheet, a double-click renames it in place, and a drag moves it.
-- While a formula is typed, a click on a tab keeps the edit open, so a click on a cell there
-- puts in a reference to the other sheet.

local calc = require ('sheet_grid_calc') --[[@as Sheet.GridCalcModule]]

---@class Sheet.GridTabsModule
local M = {}

-- How far the pointer moves before a press on a tab becomes a drag.
local DRAG_START = 5

-- lang=css
local CSS = [[
.sheet-grid-tabs { flex: none; display: flex; align-items: stretch; height: 32px; padding: 0 6px 0 4px;
  gap: 2px; background: var(--bg-alt); border-top: 1px solid var(--border); user-select: none; }
.sheet-grid-tbtn { flex: none; display: inline-flex; align-items: center; justify-content: center; width: 28px;
  margin: 4px 0; border: 0; border-radius: var(--radius); background: transparent; color: var(--fg-muted);
  cursor: pointer; }
.sheet-grid-tbtn:hover { background: var(--bg-hover); color: var(--fg); }
.sheet-grid-strip { flex: 1; min-width: 0; display: flex; align-items: stretch; gap: 1px; overflow-x: auto;
  scrollbar-width: none; padding-left: 4px; }
.sheet-grid-tab { flex: none; display: flex; align-items: center; max-width: 220px; padding: 0 14px;
  margin-bottom: 3px; border-radius: 0 0 var(--radius) var(--radius); color: var(--fg-muted); cursor: pointer;
  white-space: nowrap; overflow: hidden; text-overflow: ellipsis; font-size: 12.5px; position: relative; }
.sheet-grid-tab:hover { background: var(--bg-hover); color: var(--fg); }
.sheet-grid-tab.sheet-grid-on { background: var(--bg); color: var(--accent); font-weight: 600;
  box-shadow: 0 1px 3px var(--border); }
.sheet-grid-tab.sheet-grid-db::before, .sheet-grid-tab.sheet-grid-da::after { content: ''; position: absolute;
  top: 4px; bottom: 4px; width: 2px; background: var(--accent); }
.sheet-grid-tab.sheet-grid-db::before { left: 0; }
.sheet-grid-tab.sheet-grid-da::after { right: 0; }
.sheet-grid-tab .ui-input { height: 22px; width: 130px; padding: 0 6px; font-size: 12.5px; }
.sheet-grid-tab .ui-input.sheet-grid-bad { border-color: var(--danger); }
.sheet-grid-stats { flex: none; display: flex; align-items: center; gap: 14px; padding: 0 8px;
  color: var(--fg-muted); font-size: 12px; font-variant-numeric: tabular-nums; }
.sheet-grid-stats b { font-weight: 500; color: var(--fg); }
]]

---@param grid Sheet.GridView
function M.install (grid)
  local G = grid
  local app, ui, env = G.app, G.ui, G.env
  ui.css (CSS)
  local picker, menus, status = G.picker, G.menus, G.status

  local strip = ui.div ({ class = 'sheet-grid-strip' })
  local stats_el = ui.div ({ class = 'sheet-grid-stats' })
  G.tabs_bar = ui.div ({
    class = 'sheet-grid-tabs',
    ui.h ('button', {
      class = 'sheet-grid-tbtn',
      title = 'Add a sheet',
      icon = 'plus',
      onmousedown = function ()
        return 'prevent'
      end,
      onclick = function ()
        G.add_sheet ()
      end,
    }),
    ui.h ('button', {
      class = 'sheet-grid-tbtn',
      title = 'All sheets',
      icon = 'menu',
      onmousedown = function ()
        return 'prevent'
      end,
      onclick = function ()
        G.pick_sheet ()
      end,
    }),
    strip,
    stats_el,
  })

  local tab_els = {} ---@type Proteus.El[]
  local drawn = ''
  local renaming = nil ---@type integer?

  ---Draws the tabs again when the sheets, their names or the active one changed.
  function G.tabs_draw ()
    local book = G.cur_book
    local names = book and book:names () or {}
    local key = table.concat (names, '\0') .. '|' .. (book and book.active or 0)
    if key == drawn or renaming then
      return
    end
    drawn = key
    tab_els = {}
    local children = {} ---@type Proteus.El[]
    for i, n in ipairs (names) do
      local el = ui.div ({
        class = 'sheet-grid-tab',
        title = n,
        attrs = { ['data-item'] = 'tab:' .. i },
        n,
      })
      if book and i == book.active then
        el:class ('sheet-grid-on', true)
      end
      tab_els[i] = el
      children[i] = el
    end
    strip:set_children (children)
    local active = book and tab_els[book.active]
    if active then
      active:call ('scrollIntoView', false)
    end
  end

  local function redraw_tabs ()
    drawn = ''
    G.tabs_draw ()
  end

  -- Sheet actions --------------------------------------------------------------------------

  function G.add_sheet ()
    local book = G.cur_book
    if not book then
      return
    end
    if G.edit and not G.finish_edit (0, 0, false) then
      return
    end
    G.change ('Add sheet', function (b)
      local s, problem = b:add_sheet ()
      if not s then
        error (problem or 'The sheet could not be added.', 0)
      end
    end)
    G.focus ()
  end

  ---@param index integer
  function G.duplicate_sheet (index)
    local book = G.cur_book
    if not book or not book.sheets[index] then
      return
    end
    G.change ('Duplicate sheet', function (b)
      b:duplicate_sheet (index)
    end)
    G.focus ()
  end

  ---@param index integer
  function G.delete_sheet (index)
    local book = G.cur_book
    local s = book and book.sheets[index]
    if not book or not s then
      return
    end
    if #book.sheets <= 1 then
      env.say ('warn', 'A workbook needs at least one sheet.')
      return
    end
    local function go ()
      G.change ('Delete sheet', function (b)
        local ok, problem = b:delete_sheet (index)
        if not ok then
          error (problem or 'The sheet could not be deleted.', 0)
        end
      end)
      G.focus ()
    end
    if picker then
      picker.confirm ({
        message = 'Delete the sheet "'
          .. s.name
          .. '"? Formulas that read it will show #REF!. Undo brings it back.',
        yes = 'Delete',
        on_yes = go,
        on_no = G.focus,
      })
    else
      go ()
    end
  end

  ---Moves a sheet one place left or right.
  ---@param index integer
  ---@param delta integer
  function G.move_sheet (index, delta)
    local book = G.cur_book
    if not book then
      return
    end
    local to = index + delta
    if to < 1 or to > #book.sheets then
      return
    end
    G.change ('Move sheet', function (b)
      b:move_sheet (index, to)
    end)
  end

  ---Shows the next sheet, or the one before with -1.
  ---@param delta integer
  function G.step_sheet (delta)
    local book = G.cur_book
    if not book or #book.sheets < 2 then
      return
    end
    local n = #book.sheets
    G.show_sheet ((book.active - 1 + delta) % n + 1)
  end

  function G.pick_sheet ()
    local book = G.cur_book
    if not book or not picker then
      return
    end
    ---@type Proteus.PickItem[]
    local items = {}
    for i, n in ipairs (book:names ()) do
      items[#items + 1] = {
        label = n,
        icon = 'sheet',
        value = i,
        detail = i == book.active and 'showing' or nil,
      }
    end
    picker.pick ({
      items = items,
      placeholder = 'Go to a sheet',
      on_pick = function (item)
        G.show_sheet (item.value --[[@as integer]])
        G.focus ()
      end,
      on_cancel = G.focus,
    })
  end

  ---Renames a sheet in place on its tab.
  ---@param index integer
  function G.rename_sheet (index)
    local book = G.cur_book
    local s = book and book.sheets[index]
    local el = tab_els[index]
    if not book or not s then
      return
    end
    if not el then
      redraw_tabs ()
      el = tab_els[index]
      if not el then
        return
      end
    end
    if G.edit and not G.finish_edit (0, 0, false) then
      return
    end
    renaming = index
    local old = s.name
    local input = ui.input ({ value = old, spellcheck = false })
    local done = false

    ---@param keep boolean
    local function finish (keep)
      if done then
        return
      end
      done = true
      renaming = nil
      local name = string.match (input:value () or '', '^%s*(.-)%s*$') or ''
      if keep and name ~= old then
        local problem = book:name_problem (name, s)
        if problem then
          env.say ('warn', problem)
        else
          G.change ('Rename sheet', function (b)
            local ok, err = b:rename_sheet (index, name)
            if not ok then
              error (err or 'The sheet could not be renamed.', 0)
            end
          end)
        end
      end
      redraw_tabs ()
      G.focus ()
    end

    input:on ('keydown', function (ev)
      if ev.key == 'Enter' then
        finish (true)
        return 'stop'
      end
      if ev.key == 'Escape' then
        finish (false)
        return 'stop'
      end
      return nil
    end)
    input:on ('input', function ()
      local name = string.match (input:value () or '', '^%s*(.-)%s*$') or ''
      local problem = name ~= old and book:name_problem (name, s) or nil
      input:class ('sheet-grid-bad', problem ~= nil)
      input:attr ('title', problem or '')
      return nil
    end)
    input:on ('blur', function ()
      finish (true)
      return nil
    end)
    input:on ('mousedown', function ()
      return 'stop'
    end)
    el:set_children ({ input })
    input:focus ()
    input:select ()
  end

  -- The mouse on the tabs ------------------------------------------------------------------

  ---The sheet index of a tab from an event's item.
  ---@param item? string
  ---@return integer?
  local function tab_index (item)
    local n = tonumber (string.match (item or '', '^tab:(%d+)$'))
    return n and math.floor (n) or nil
  end

  ---@class Sheet.GridTabDrag
  ---@field from integer
  ---@field x number
  ---@field moving boolean
  ---@field middles number[]
  ---@field gap? integer

  local tab_drag = nil ---@type Sheet.GridTabDrag?

  local function clear_marks ()
    for _, el in ipairs (tab_els) do
      el:class ('sheet-grid-db', false)
      el:class ('sheet-grid-da', false)
    end
  end

  strip:on ('mousedown', function (ev)
    local index = tab_index (ev.item)
    local book = G.cur_book
    if not index or not book or ev.button ~= 0 or renaming then
      return nil
    end
    local edit = G.edit
    if edit then
      -- A formula being typed stays open, so its next reference can name this sheet.
      G.show_sheet (index)
      return 'prevent'
    end
    G.show_sheet (index)
    tab_drag = { from = index, x = ev.x or 0, moving = false, middles = {} }
    return 'prevent'
  end)

  app.dom.on_global ('mousemove', function (ev)
    local d = tab_drag
    if not d then
      return nil
    end
    local x = ev.x or 0
    if not d.moving then
      if math.abs (x - d.x) < DRAG_START then
        return nil
      end
      d.moving = true
      for i, el in ipairs (tab_els) do
        local r = el:rect ()
        d.middles[i] = r.left + r.w / 2
      end
    end
    local gap = calc.drop_index (d.middles, x)
    if gap == d.gap then
      return nil
    end
    d.gap = gap
    clear_marks ()
    if gap <= #tab_els then
      tab_els[gap]:class ('sheet-grid-db', true)
    elseif tab_els[#tab_els] then
      tab_els[#tab_els]:class ('sheet-grid-da', true)
    end
    return nil
  end)

  app.dom.on_global ('mouseup', function ()
    local d = tab_drag
    tab_drag = nil
    if not d or not d.moving then
      return nil
    end
    clear_marks ()
    local to = calc.moved_index (d.from, d.gap or d.from)
    if to ~= d.from then
      G.change ('Move sheet', function (b)
        b:move_sheet (d.from, to)
      end)
    end
    G.focus ()
    return nil
  end)

  strip:on ('dblclick', function (ev)
    local index = tab_index (ev.item)
    if index and not G.edit then
      G.rename_sheet (index)
      return 'prevent'
    end
    return nil
  end)

  if menus then
    menus.attach (strip, function (ev)
      local book = G.cur_book
      local index = tab_index (ev.item)
      if not book then
        return nil
      end
      if not index then
        return {
          { label = 'Add sheet', icon = 'plus', run = G.add_sheet },
        }
      end
      G.show_sheet (index)
      local n = #book.sheets
      ---@type Proteus.MenuItem[]
      return {
        {
          label = 'Rename',
          icon = 'pencil',
          run = function ()
            G.rename_sheet (index)
          end,
        },
        {
          label = 'Duplicate',
          icon = 'copy-plus',
          run = function ()
            G.duplicate_sheet (index)
          end,
        },
        {
          label = 'Delete…',
          icon = 'trash',
          danger = true,
          disabled = n <= 1,
          run = function ()
            G.delete_sheet (index)
          end,
        },
        { separator = true },
        {
          label = 'Move left',
          icon = 'arrow-left',
          disabled = index <= 1,
          run = function ()
            G.move_sheet (index, -1)
          end,
        },
        {
          label = 'Move right',
          icon = 'arrow-right',
          disabled = index >= n,
          run = function ()
            G.move_sheet (index, 1)
          end,
        },
      }
    end)
  end

  -- The numbers of the selection ------------------------------------------------------------

  local sum_item = status
    and status.add ({ id = 'sheet.stats', text = '', align = 'right', order = 5 })
  local size_item = status
    and status.add ({ id = 'sheet.size', text = '', align = 'right', order = 6 })

  ---Shows the numbers of the selection, or hides them with nil.
  ---@param text? string
  ---@param size? string
  function G.show_stats (text, size)
    if sum_item and size_item then
      sum_item.set (text or '')
      sum_item.show (text ~= nil)
      size_item.set (size or '')
      size_item.show (size ~= nil)
      stats_el:show (false)
      return
    end
    if not text and not size then
      stats_el:html ('')
      return
    end
    stats_el:html (
      (text and ('<span>' .. calc.escape (text) .. '</span>') or '')
        .. (size and ('<span>' .. calc.escape (size) .. '</span>') or '')
    )
  end

  ---@param n number
  ---@return string
  local function pretty (n)
    return app.util.format_number (n, nil, { maximumFractionDigits = 4 })
  end

  local function stats_now ()
    local s = G.sheet ()
    if not s then
      G.show_stats (nil, nil)
      return
    end
    local rect = G.sel_rect ()
    if rect.r1 == rect.r2 and rect.c1 == rect.c2 then
      G.show_stats (nil, nil)
      return
    end
    local size = calc.size_label (rect)
    local numbers = {} ---@type number[]
    for _, cell in ipairs (s:cells_in (rect)) do
      if not s:row_hidden (cell.row) and not s:col_hidden (cell.col) then
        local v = s:value (cell.row, cell.col)
        if type (v) == 'number' then
          numbers[#numbers + 1] = v
        end
      end
    end
    if #numbers == 0 then
      G.show_stats (nil, size)
      return
    end
    local st = calc.stats (numbers)
    G.show_stats (
      'Sum '
        .. pretty (st.sum)
        .. '   Avg '
        .. pretty (st.average or 0)
        .. '   Count '
        .. st.count
        .. '   Min '
        .. pretty (st.min or 0)
        .. '   Max '
        .. pretty (st.max or 0),
      size
    )
  end

  local cancel_stats = nil ---@type fun()?

  ---Works out the numbers of the selection a moment after it stops moving.
  function G.stats_later ()
    if cancel_stats then
      cancel_stats ()
    end
    cancel_stats = app.timer.after (60, function ()
      cancel_stats = nil
      local ok, err = pcall (stats_now)
      if not ok then
        app.warn ('Sheet: the selection numbers failed: ' .. tostring (err))
      end
    end)
  end
end

return M
