-- sheet_panel_find: the find bar, the filter menu, and the note and link editors of the Sheet
-- app.
--
-- The find bar sits at the top right of the grid. Matches light up as the query changes, and
-- the selection moves to the nearest one. Each box is drawn over its cell from `ctl.cell_rect`,
-- all of them as one HTML string, and drawn again when the grid scrolls. The filter menu opens
-- from a filter button in a header row. The note and link editors open beside their cell and
-- save when they close.

local model = require ('sheet_model') --[[@as Sheet.ModelModule]]
local ops = require ('sheet_ops') --[[@as Sheet.OpsModule]]
local pop = require ('sheet_panel_pop') --[[@as Sheet.PanelPopModule]]
local text = require ('sheet_panel_text') --[[@as Sheet.PanelTextModule]]

---The floating parts, as sheet_panels drives them.
---@class Sheet.FloatPanels
---@field find fun(replace: boolean) Opens the find bar, with the replace row when asked.
---@field note fun() Opens the note editor on the active cell.
---@field link fun() Opens the link editor on the active cell.
---@field filter_menu fun(col: integer, rect: Proteus.Rect) Opens a filter column's menu under its button.

---What the find bar searches for.
---@class Sheet.FindState
---@field query string
---@field with string
---@field case boolean
---@field whole boolean
---@field formulas boolean
---@field all boolean True to search every sheet.
---@field replace boolean True while the replace row shows.
---@field matches Sheet.Match[]

---@class Sheet.PanelFindModule
local M = {}

-- More boxes than this would cost too many calls into the page on each scroll.
local MAX_BOXES = 400
-- The filter menu lists this many values at most. The search box reaches the rest.
local MAX_VALUES = 500

-- lang=css
local CSS = [[
.sheet-pop-find {
  position: fixed;
  z-index: 2400;
  width: 440px;
  max-width: calc(100vw - 16px);
  display: flex;
  flex-direction: column;
  gap: 6px;
  padding: 6px;
  background: var(--bg-elev);
  color: var(--fg);
  border: 1px solid var(--border);
  border-radius: calc(var(--radius) + 2px);
  box-shadow: var(--shadow);
  font-family: var(--font-ui);
  font-size: var(--font-size);
}
.sheet-pop-find-row {
  display: flex;
  align-items: center;
  gap: 2px;
}
.sheet-pop-find-box {
  flex: 1;
  min-width: 0;
  display: flex;
  align-items: center;
  gap: 4px;
  padding: 0 4px 0 8px;
  height: 28px;
  border: 1px solid var(--border);
  border-radius: var(--radius);
  background: var(--bg);
}
.sheet-pop-find-box:focus-within {
  border-color: var(--accent);
}
.sheet-pop-find-box input {
  flex: 1;
  min-width: 0;
  border: none;
  outline: none;
  background: transparent;
  color: var(--fg);
  font: inherit;
}
.sheet-pop-find-box .ui-icon {
  color: var(--fg-faint);
}
.sheet-pop-find-count {
  flex: none;
  font-size: 12px;
  color: var(--fg-muted);
  font-variant-numeric: tabular-nums;
  white-space: nowrap;
}
.sheet-pop-find-count.none {
  color: var(--danger);
}
.sheet-pop-find-btn {
  flex: none;
  height: 26px;
  min-width: 26px;
  padding: 0 4px;
  display: inline-grid;
  place-items: center;
  border: 1px solid transparent;
  border-radius: var(--radius);
  background: transparent;
  color: var(--fg-muted);
  cursor: pointer;
  font: inherit;
}
.sheet-pop-find-btn:hover:not(:disabled) {
  background: var(--bg-hover);
  color: var(--fg);
}
.sheet-pop-find-btn:disabled {
  opacity: 0.35;
  cursor: default;
}
.sheet-pop-find-btn.on {
  background: var(--bg-active);
  color: var(--accent);
  border-color: color-mix(in srgb, var(--accent) 40%, transparent);
}
.sheet-pop-find-word {
  padding: 0 8px;
  font-size: 12px;
  color: var(--fg);
  border-color: var(--border);
}
.sheet-pop-find-toggles {
  display: flex;
  gap: 1px;
  margin-left: 2px;
}
.sheet-pop-marks {
  position: fixed;
  inset: 0;
  z-index: 6;
  pointer-events: none;
}
.sheet-pop-mark {
  position: fixed;
  box-sizing: border-box;
  border-radius: 2px;
  background: color-mix(in srgb, var(--warning) 22%, transparent);
  border: 1px solid color-mix(in srgb, var(--warning) 70%, transparent);
}
.sheet-pop-mark.now {
  background: color-mix(in srgb, var(--warning) 38%, transparent);
  border: 2px solid var(--warning);
}
.sheet-pop-menu {
  width: 272px;
  padding: 4px;
}
.sheet-pop-item {
  display: flex;
  align-items: center;
  gap: 10px;
  width: 100%;
  padding: 5px 8px;
  border: none;
  border-radius: var(--radius);
  background: transparent;
  color: var(--fg);
  text-align: left;
  cursor: pointer;
  font: inherit;
}
.sheet-pop-item:hover {
  background: var(--bg-hover);
}
.sheet-pop-item .ui-icon {
  color: var(--fg-muted);
}
.sheet-pop-sep {
  height: 1px;
  margin: 4px 2px;
  background: var(--border);
}
.sheet-pop-section {
  display: flex;
  flex-direction: column;
  gap: 6px;
  padding: 4px 6px 6px;
}
.sheet-pop-head {
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 0.04em;
  text-transform: uppercase;
  color: var(--fg-muted);
}
.sheet-pop-menu select,
.sheet-pop-menu .ui-input {
  width: 100%;
  padding: 4px 7px;
}
.sheet-pop-menu select {
  border-radius: var(--radius);
  border: 1px solid var(--border);
  background: var(--bg);
  color: var(--fg);
  outline: none;
}
.sheet-pop-pair {
  display: flex;
  gap: 6px;
}
.sheet-pop-pair .ui-input {
  flex: 1;
  min-width: 0;
}
.sheet-pop-links {
  display: flex;
  align-items: center;
  gap: 10px;
  font-size: 12px;
}
.sheet-pop-links button {
  border: none;
  background: transparent;
  color: var(--accent);
  padding: 0;
  cursor: pointer;
  font: inherit;
}
.sheet-pop-links span {
  margin-left: auto;
  color: var(--fg-faint);
}
.sheet-pop-values {
  max-height: 210px;
  overflow: auto;
  border: 1px solid var(--border);
  border-radius: var(--radius);
  background: var(--bg);
  padding: 2px 0;
}
.sheet-pop-value {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 3px 8px;
  cursor: pointer;
  user-select: none;
}
.sheet-pop-value:hover {
  background: var(--bg-hover);
}
.sheet-pop-value .box {
  flex: none;
  width: 14px;
  height: 14px;
  border-radius: 3px;
  border: 1px solid var(--fg-faint);
  display: grid;
  place-items: center;
}
.sheet-pop-value.on .box {
  background: var(--accent);
  border-color: var(--accent);
  color: var(--accent-fg);
}
.sheet-pop-value .name {
  flex: 1;
  min-width: 0;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.sheet-pop-value .name.blank {
  color: var(--fg-muted);
  font-style: italic;
}
.sheet-pop-value .count {
  flex: none;
  color: var(--fg-faint);
  font-size: 11px;
  font-variant-numeric: tabular-nums;
}
.sheet-pop-more {
  padding: 4px 8px;
  color: var(--fg-faint);
  font-size: 12px;
}
.sheet-pop-foot {
  display: flex;
  justify-content: flex-end;
  gap: 8px;
  padding: 6px;
}
.sheet-pop-note {
  width: 250px;
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.sheet-pop-note-head {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 12px;
  color: var(--fg-muted);
}
.sheet-pop-note textarea {
  width: 100%;
  min-height: 96px;
  resize: vertical;
  line-height: 1.45;
}
]]

local TICK = '<svg width="10" height="10" viewBox="0 0 24 24" fill="none" '
  .. 'stroke="currentColor" stroke-width="4" stroke-linecap="round" '
  .. 'stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg>'

---@param env Sheet.PanelEnv
---@return Sheet.FloatPanels
function M.install (env)
  local app, ctl, ui = env.app, env.ctl, env.ui
  local escape = app.util.escape
  ui.css (CSS)

  -- Moving to another sheet ---------------------------------------------------------------

  ---Shows another sheet of the book, and keeps the keyboard in the find bar.
  ---@param index integer
  local function show_sheet (index)
    local book = ctl.book ()
    if not book or book.active == index then
      return
    end
    local had = app.dom.active ()
    ctl.show_sheet (index)
    if had then
      ui.wrap (had):focus ()
    end
  end

  -- The find bar -------------------------------------------------------------------------

  ---@type Sheet.FindState
  local state = {
    query = '',
    with = '',
    case = false,
    whole = false,
    formulas = false,
    all = false,
    replace = false,
    matches = {},
  }
  local bar = nil ---@type Proteus.El?
  local marks = nil ---@type Proteus.El?
  local query_input = nil ---@type Proteus.El?
  local with_input = nil ---@type Proteus.El?
  local count_label = nil ---@type Proteus.El?
  local replace_row = nil ---@type Proteus.El?
  local fold_button = nil ---@type Proteus.El?
  local offs = {} ---@type fun()[]
  local marks_html = ''
  local mark_queued = false

  ---@return Sheet.FindOptions
  local function find_opts ()
    return {
      case = state.case,
      whole = state.whole,
      formulas = state.formulas,
      sheet = not state.all and ctl.sheet () or nil,
    }
  end

  ---The match the active cell sits on, and its place in the list.
  ---@return Sheet.Match?
  ---@return integer?
  local function match_here ()
    local sheet = ctl.sheet ()
    if not sheet then
      return nil, nil
    end
    local _, row, col = ctl.selection ()
    for i, m in ipairs (state.matches) do
      if m.sheet == sheet and m.row == row and m.col == col then
        return m, i
      end
    end
    return nil, nil
  end

  local function draw_marks ()
    mark_queued = false
    if not marks or not bar then
      return
    end
    local sheet = ctl.sheet ()
    local parts = {} ---@type string[]
    local _, here = match_here ()
    local shown = 0
    for i, m in ipairs (state.matches) do
      if shown >= MAX_BOXES then
        break
      end
      if m.sheet == sheet then
        local r = ctl.cell_rect (m.row, m.col)
        if r then
          shown = shown + 1
          parts[#parts + 1] = '<div class="sheet-pop-mark'
            .. (i == here and ' now' or '')
            .. '" style="left:'
            .. math.floor (r.left)
            .. 'px;top:'
            .. math.floor (r.top)
            .. 'px;width:'
            .. math.ceil (r.w)
            .. 'px;height:'
            .. math.ceil (r.h)
            .. 'px"></div>'
        end
      end
    end
    local html = table.concat (parts)
    if html ~= marks_html then
      marks_html = html
      marks:html (html)
    end
  end

  local function marks_soon ()
    if mark_queued then
      return
    end
    mark_queued = true
    app.timer.after (16, draw_marks)
  end

  local function show_count ()
    if not count_label then
      return
    end
    local _, here = match_here ()
    local none = state.query ~= '' and #state.matches == 0
    count_label:text (
      state.query == '' and '' or text.match_label (here, #state.matches)
    )
    count_label:class ('none', none)
  end

  ---Places the bar at the top right of the grid's cells.
  local function place_bar ()
    if not bar then
      return
    end
    local area = ctl.grid_rect () or ctl.root ():rect ()
    local top = area.top + 8
    local vp = app.dom.viewport ()
    local right = math.max (8, vp.w - area.right + 8)
    bar:style ({
      top = math.floor (top) .. 'px',
      right = math.floor (right) .. 'px',
    })
  end

  ---Selects a match, showing its sheet first.
  ---@param m Sheet.Match
  local function go (m)
    local book = ctl.book ()
    if not book then
      return
    end
    local index = book:index_of (m.sheet)
    if index then
      show_sheet (index)
    end
    ctl.select ({ r1 = m.row, c1 = m.col, r2 = m.row, c2 = m.col }, m.row, m.col)
    show_count ()
    marks_soon ()
  end

  ---Works out the matches again. With `move`, the selection goes to the nearest match when
  ---it is not on one.
  ---@param move boolean
  local function search (move)
    local book = ctl.book ()
    local sheet = ctl.sheet ()
    if not book or not sheet or state.query == '' then
      state.matches = {}
    else
      state.matches = ops.find_all (book, state.query, find_opts ())
    end
    if move and #state.matches > 0 and not match_here () and book and sheet then
      local _, row, col = ctl.selection ()
      -- One step back first, so the cell the selection is on counts as the next one.
      local m = ops.find_next (
        book,
        state.query,
        { sheet = sheet, row = row, col = col - 1 },
        find_opts ()
      )
      if m then
        go (m)
      end
    end
    show_count ()
    marks_soon ()
  end

  ---@param back boolean
  local function step (back)
    local book = ctl.book ()
    local sheet = ctl.sheet ()
    if not book or not sheet or state.query == '' then
      return
    end
    local _, row, col = ctl.selection ()
    local m = ops.find_next (
      book,
      state.query,
      { sheet = sheet, row = row, col = col },
      find_opts (),
      back
    )
    if m then
      go (m)
    else
      show_count ()
    end
  end

  local function replace_one ()
    local book = ctl.book ()
    if not book or state.query == '' then
      return
    end
    local m = match_here ()
    if not m then
      step (false)
      return
    end
    local with, query, opts = state.with, state.query, find_opts ()
    local changed = ctl.change ('Replace', function (b)
      return ops.replace (b, m --[[@as Sheet.Match]], query, with, opts)
    end)
    if changed == false then
      ctl.say (
        'info',
        'This match comes from a formula. Turn on Search in formulas to change the formula.'
      )
    end
    search (false)
    step (false)
  end

  local function replace_all ()
    local book = ctl.book ()
    if not book or state.query == '' then
      return
    end
    local with, query, opts = state.with, state.query, find_opts ()
    local n = ctl.change ('Replace all', function (b)
      return ops.replace_all (b, query, with, opts)
    end)
    search (false)
    if type (n) == 'number' and n > 0 then
      ctl.say (
        'success',
        'Replaced text in ' .. n .. (n == 1 and ' cell.' or ' cells.')
      )
    else
      ctl.say ('info', 'Nothing was replaced.')
    end
  end

  local function close_bar ()
    for _, off in ipairs (offs) do
      off ()
    end
    offs = {}
    if bar then
      bar:remove ()
    end
    if marks then
      marks:remove ()
    end
    bar, marks, query_input, with_input, count_label, replace_row, fold_button =
      nil, nil, nil, nil, nil, nil, nil
    marks_html = ''
    ctl.focus ()
  end

  local function show_replace ()
    if replace_row then
      replace_row:show (state.replace)
    end
    if fold_button then
      fold_button:set_children ({
        ui.icon (state.replace and 'chevron-down' or 'chevron-right', 14),
      })
      fold_button:set (
        'title',
        state.replace and 'Hide replace' or 'Show replace (Ctrl+H)'
      )
    end
  end

  ---@param icon string
  ---@param title string
  ---@param run fun(el: Proteus.El)
  ---@param on? boolean
  ---@return Proteus.El
  local function bar_button (icon, title, run, on)
    local el = ui.h ('button', {
      class = 'sheet-pop-find-btn' .. (on and ' on' or ''),
      title = title,
      ui.icon (icon, 15),
    })
    el:on ('mousedown', function ()
      return true
    end)
    el:on ('click', function ()
      run (el)
      return nil
    end)
    return el
  end

  ---@param field 'case'|'whole'|'formulas'|'all'
  ---@param icon string
  ---@param title string
  ---@return Proteus.El
  local function toggle (field, icon, title)
    local flags = state --[[@as table<string, boolean>]]
    return bar_button (icon, title, function (el)
      flags[field] = not flags[field]
      el:class ('on', flags[field] == true)
      search (true)
    end, flags[field] == true)
  end

  local function build_bar ()
    local q = ui.h ('input', {
      value = state.query,
      placeholder = 'Find in sheet',
      spellcheck = false,
    })
    local w = ui.h ('input', {
      value = state.with,
      placeholder = 'Replace with',
      spellcheck = false,
    })
    local count = ui.span ({ class = 'sheet-pop-find-count' })
    local fold = bar_button ('chevron-right', 'Show replace', function ()
      state.replace = not state.replace
      show_replace ()
      if state.replace and with_input then
        with_input:focus ()
      end
    end)
    q:on ('input', function (ev)
      state.query = ev.value or ''
      search (true)
      return nil
    end)
    q:on ('keydown', function (ev)
      if ev.key == 'Enter' then
        step (ev.shift == true)
        return 'stop'
      elseif ev.key == 'Escape' then
        close_bar ()
        return 'stop'
      elseif ev.ctrl and (ev.key == 'f' or ev.key == 'F') then
        q:select ()
        return 'stop'
      elseif ev.ctrl and (ev.key == 'h' or ev.key == 'H') then
        state.replace = true
        show_replace ()
        w:focus ()
        return 'stop'
      end
      return nil
    end)
    w:on ('input', function (ev)
      state.with = ev.value or ''
      return nil
    end)
    w:on ('keydown', function (ev)
      if ev.key == 'Enter' then
        if ev.ctrl then
          replace_all ()
        else
          replace_one ()
        end
        return 'stop'
      elseif ev.key == 'Escape' then
        close_bar ()
        return 'stop'
      elseif ev.ctrl and (ev.key == 'f' or ev.key == 'F') then
        q:focus ()
        q:select ()
        return 'stop'
      end
      return nil
    end)
    local replace = ui.div ({
      class = 'sheet-pop-find-row',
      ui.span ({ style = 'width:26px;flex:none' }),
      ui.div ({
        class = 'sheet-pop-find-box',
        ui.icon ('replace', 14),
        w,
      }),
      ui.h ('button', {
        class = 'sheet-pop-find-btn sheet-pop-find-word',
        title = 'Replace in this cell and find the next (Enter)',
        'Replace',
        onclick = function ()
          replace_one ()
          return nil
        end,
      }),
      ui.h ('button', {
        class = 'sheet-pop-find-btn sheet-pop-find-word',
        title = 'Replace every match (Ctrl+Enter)',
        'Replace all',
        onclick = function ()
          replace_all ()
          return nil
        end,
      }),
    })
    local el = ui.div ({
      class = 'sheet-pop-find',
      ui.div ({
        class = 'sheet-pop-find-row',
        fold,
        ui.div ({
          class = 'sheet-pop-find-box',
          ui.icon ('search', 14),
          q,
          count,
        }),
        bar_button ('arrow-up', 'Previous match (Shift+Enter)', function ()
          step (true)
        end),
        bar_button ('arrow-down', 'Next match (Enter)', function ()
          step (false)
        end),
        ui.div ({
          class = 'sheet-pop-find-toggles',
          toggle ('case', 'case-sensitive', 'Match case'),
          toggle ('whole', 'whole-word', 'Match the whole cell'),
          toggle ('formulas', 'square-function', 'Search in formulas'),
          toggle ('all', 'layers', 'Search every sheet'),
        }),
        bar_button ('x', 'Close (Escape)', close_bar),
      }),
      replace,
    })
    bar, query_input, with_input, count_label, replace_row, fold_button =
      el, q, w, count, replace, fold
    marks = ui.div ({ class = 'sheet-pop-marks' })
    ctl.root ():append (marks)
    ctl.root ():append (el)
    place_bar ()
    show_replace ()
    offs[#offs + 1] = ctl.on ('selection', function ()
      show_count ()
      marks_soon ()
    end)
    offs[#offs + 1] = ctl.on ('changed', function ()
      search (false)
    end)
    offs[#offs + 1] = ctl.on ('sheet', function ()
      search (false)
    end)
    offs[#offs + 1] = ctl.on ('book', close_bar)
    offs[#offs + 1] = ctl.on ('view', marks_soon)
    offs[#offs + 1] = ctl.on ('scroll', marks_soon)
    offs[#offs + 1] = app.dom.on_global ('resize', function ()
      place_bar ()
      marks_soon ()
      return nil
    end)
  end

  ---@param replace boolean
  local function open_find (replace)
    if not ctl.sheet () then
      return
    end
    pop.close (env)
    if replace then
      state.replace = true
    end
    if not bar then
      build_bar ()
    else
      place_bar ()
      show_replace ()
    end
    search (true)
    local target = (replace and state.query ~= '') and with_input or query_input
    if target then
      target:focus ()
      target:select ()
    end
  end

  -- The filter menu ----------------------------------------------------------------------

  ---@param col integer
  ---@param rect Proteus.Rect
  local function filter_menu (col, rect)
    local sheet = ctl.sheet ()
    if not sheet or not sheet.filter then
      return
    end
    local f = sheet.filter --[[@as Sheet.LiveFilter]]
    local test = f.columns[col] or {}
    local values = ops.filter_values (sheet, col)
    local keep = {} ---@type table<string, boolean>
    for _, v in ipairs (values) do
      keep[v.text] = v.shown
    end
    local search_text = ''

    local options = { { value = 'none', label = 'None' } } ---@type { value: string, label: string }[]
    for _, c in ipairs (text.CONDITIONS) do
      if c.filter then
        options[#options + 1] = { value = c.id, label = c.label }
      end
    end
    local cond_id = test.op or 'none'
    local cond = ui.h ('select', {})
    for _, o in ipairs (options) do
      cond:append (ui.option ({ value = o.value, o.label }))
    end
    cond:set ('value', cond_id)
    local a_box = ui.input ({ value = test.value or '', placeholder = 'Value' })
    local b_box = ui.input ({ value = test.value2 or '', placeholder = 'And' })
    local pair = ui.div ({ class = 'sheet-pop-pair', a_box, b_box })
    local function show_cond ()
      local c = text.condition (cond_id)
      local kind = c and c.input or 'none'
      pair:show (kind == 'one' or kind == 'two')
      b_box:show (kind == 'two')
    end
    cond:on ('change', function (ev)
      cond_id = ev.value or 'none'
      show_cond ()
      return nil
    end)
    show_cond ()

    local list = ui.div ({ class = 'sheet-pop-values' })
    local tally = ui.span ({})
    ---@return Sheet.FilterValue[]
    local function listed ()
      local out = {} ---@type Sheet.FilterValue[]
      local needle = string.lower (search_text)
      for _, v in ipairs (values) do
        if
          needle == ''
          or string.find (string.lower (v.text), needle, 1, true)
        then
          out[#out + 1] = v
        end
      end
      return out
    end
    local function draw_list ()
      local parts = {} ---@type string[]
      local rows = listed ()
      for i, v in ipairs (rows) do
        if i > MAX_VALUES then
          parts[#parts + 1] = '<div class="sheet-pop-more">'
            .. (#rows - MAX_VALUES)
            .. ' more. Search to find them.</div>'
          break
        end
        local on = keep[v.text]
        parts[#parts + 1] = '<div class="sheet-pop-value'
          .. (on and ' on' or '')
          .. '" data-item="'
          .. i
          .. '"><span class="box">'
          .. (on and TICK or '')
          .. '</span><span class="name'
          .. (v.text == '' and ' blank' or '')
          .. '">'
          .. (v.text == '' and '(Blanks)' or escape (v.text))
          .. '</span><span class="count">'
          .. v.count
          .. '</span></div>'
      end
      if #rows == 0 then
        parts[1] = '<div class="sheet-pop-more">No values match.</div>'
      end
      list:html (table.concat (parts))
      local kept = 0
      for _, v in ipairs (values) do
        if keep[v.text] then
          kept = kept + 1
        end
      end
      tally:text (kept .. ' of ' .. #values .. ' shown')
    end
    list:on ('click', function (ev)
      local i = tonumber (ev.item or '')
      local v = i and listed ()[i]
      if v then
        keep[v.text] = not keep[v.text]
        draw_list ()
      end
      return nil
    end)
    ---@param on boolean
    local function set_all (on)
      for _, v in ipairs (listed ()) do
        keep[v.text] = on
      end
      draw_list ()
    end
    local finder =
      ui.input ({ placeholder = 'Search values', spellcheck = false })
    finder:on ('input', function (ev)
      search_text = ev.value or ''
      draw_list ()
      return nil
    end)
    draw_list ()

    local function apply ()
      local next_test = {} ---@type Sheet.FilterColumn
      local all_kept = true
      local kept = {} ---@type string[]
      for _, v in ipairs (values) do
        if keep[v.text] then
          kept[#kept + 1] = v.text
        else
          all_kept = false
        end
      end
      if not all_kept then
        next_test.values = kept
      end
      local c = text.condition (cond_id)
      if c then
        next_test.op = c.op or c.id
        if c.input == 'one' or c.input == 'two' then
          next_test.value = a_box:value ()
        end
        if c.input == 'two' then
          next_test.value2 = b_box:value ()
        end
      end
      pop.close (env)
      ctl.change ('Filter', function (_, s)
        ops.filter_column (
          s,
          col,
          (next_test.values or next_test.op) and next_test or nil
        )
      end)
    end

    ---@param desc boolean
    local function sort (desc)
      pop.close (env)
      local problem = ctl.change (
        desc and 'Sort Z to A' or 'Sort A to Z',
        function (_, s)
          local live = s.filter
          if not live then
            return nil
          end
          local good, why = ops.sort (
            s,
            live.rect,
            { { col = col, desc = desc } },
            {
              header = true,
            }
          )
          if not good then
            return why
          end
          return nil
        end
      )
      if type (problem) == 'string' then
        ctl.say ('warn', problem)
      end
    end

    ---@param icon string
    ---@param label string
    ---@param run fun()
    ---@return Proteus.El
    local function item (icon, label, run)
      return ui.h ('button', {
        class = 'sheet-pop-item',
        ui.icon (icon, 15),
        label,
        onclick = function ()
          run ()
          return nil
        end,
      })
    end

    local el = ui.div ({
      class = 'sheet-pop-menu',
      item ('arrow-down-az', 'Sort A to Z', function ()
        sort (false)
      end),
      item ('arrow-down-za', 'Sort Z to A', function ()
        sort (true)
      end),
      ui.div ({ class = 'sheet-pop-sep' }),
      ui.div ({
        class = 'sheet-pop-section',
        ui.span ({ class = 'sheet-pop-head', 'Filter by condition' }),
        cond,
        pair,
      }),
      ui.div ({ class = 'sheet-pop-sep' }),
      ui.div ({
        class = 'sheet-pop-section',
        ui.span ({ class = 'sheet-pop-head', 'Filter by values' }),
        ui.div ({
          class = 'sheet-pop-links',
          ui.h ('button', {
            'Select all',
            onclick = function ()
              set_all (true)
              return nil
            end,
          }),
          ui.h ('button', {
            'Clear',
            onclick = function ()
              set_all (false)
              return nil
            end,
          }),
          tally,
        }),
        finder,
        list,
      }),
      ui.div ({
        class = 'sheet-pop-foot',
        ui.button ({
          'Cancel',
          onclick = function ()
            pop.close (env)
            return nil
          end,
        }),
        ui.button ({
          'OK',
          variant = 'primary',
          onclick = function ()
            apply ()
            return nil
          end,
        }),
      }),
    })
    el:on ('keydown', function (ev)
      if ev.key == 'Enter' and not ev.shift then
        apply ()
        return 'stop'
      end
      return nil
    end)
    pop.open (env, el, rect)
  end

  -- The note editor ----------------------------------------------------------------------

  local function open_note ()
    local sheet = ctl.sheet ()
    if not sheet then
      return
    end
    local _, row, col = ctl.selection ()
    local old = sheet:note (row, col) or ''
    local box = ui.input ({
      multiline = true,
      value = old,
      placeholder = 'Type a note',
      spellcheck = true,
    })
    local saved = false
    local function save ()
      if saved then
        return
      end
      saved = true
      local now = string.match (box:value () or '', '^%s*(.-)%s*$')
      if now == string.match (old, '^%s*(.-)%s*$') then
        return
      end
      ctl.change (now == '' and 'Delete note' or 'Note', function (_, s)
        s:set_note (row, col, now ~= '' and now or nil)
      end)
    end
    box:on ('keydown', function (ev)
      if ev.key == 'Enter' and ev.ctrl then
        pop.close (env)
        return 'stop'
      end
      return nil
    end)
    local el = ui.div ({
      class = 'sheet-pop-note',
      ui.div ({
        class = 'sheet-pop-note-head',
        ui.icon ('sticky-note', 14),
        ui.span ({ 'Note on ' .. model.address (row, col) }),
      }),
      box,
    })
    local anchor = ctl.cell_rect (row, col) or pop.cell_anchor (env)
    pop.open (env, el, anchor, { side = 'right', on_close = save })
    box:focus ()
  end

  -- The link editor ----------------------------------------------------------------------

  local function open_link ()
    local sheet = ctl.sheet ()
    if not sheet then
      return
    end
    local _, row, col = ctl.selection ()
    local old = sheet:link (row, col) or ''
    local box = ui.input ({
      value = old,
      placeholder = 'https://example.com, or #Sheet2!A1',
      spellcheck = false,
    })
    local saved = false
    local function save ()
      if saved then
        return
      end
      saved = true
      local now = string.match (box:value () or '', '^%s*(.-)%s*$')
      if now == old then
        return
      end
      ctl.change (now == '' and 'Remove link' or 'Link', function (_, s)
        s:set_link (row, col, now ~= '' and now or nil)
      end)
    end
    box:on ('keydown', function (ev)
      if ev.key == 'Enter' then
        pop.close (env)
        return 'stop'
      end
      return nil
    end)
    local el = ui.div ({
      class = 'sheet-pop-note',
      ui.div ({
        class = 'sheet-pop-note-head',
        ui.icon ('link', 14),
        ui.span ({ 'Link on ' .. model.address (row, col) }),
      }),
      box,
      ui.div ({
        class = 'sheet-pop-note-head',
        'Ctrl+click the cell to follow it. Clear the box to remove it.',
      }),
    })
    local anchor = ctl.cell_rect (row, col) or pop.cell_anchor (env)
    pop.open (env, el, anchor, { side = 'right', on_close = save })
    box:focus ()
  end

  ---@type Sheet.FloatPanels
  local api = {
    find = open_find,
    note = open_note,
    link = open_link,
    filter_menu = filter_menu,
  }
  return api
end

return M
