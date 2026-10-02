-- sheet_panel_side: the Sheet app's side panels, in the right dock.
--
-- Five panels share the dock, each a view with its own tab and a module of its own: Chart
-- (sheet_panel_chart), Formatting for conditional formatting (sheet_panel_rules), Validation
-- (sheet_panel_validation), Names (sheet_panel_names) and Sort (sheet_panel_sort). This module
-- holds the builders they share, the frame of each panel, and what follows the grid. The chart
-- panel applies each change as it is made, as one undo step. The rule panels list the rules as
-- cards and edit one at a time in a form, which saves on Done. A panel draws again after a
-- change only when what it shows went out of date, so a box being typed in keeps its focus.

local chart_mod = require ('sheet_panel_chart') --[[@as Sheet.ChartPanelModule]]
local model = require ('sheet_model') --[[@as Sheet.ModelModule]]
local names_mod = require ('sheet_panel_names') --[[@as Sheet.NamesPanelModule]]
local pop = require ('sheet_panel_pop') --[[@as Sheet.PanelPopModule]]
local rules_mod = require ('sheet_panel_rules') --[[@as Sheet.RulesPanelModule]]
local sort_mod = require ('sheet_panel_sort') --[[@as Sheet.SortPanelModule]]
local validation_mod = require ('sheet_panel_validation') --[[@as Sheet.ValidationPanelModule]]

---@alias Sheet.PanelName 'chart'|'rules'|'validation'|'sort'|'names'

---The side panels, as sheet_panels drives them.
---@class Sheet.SidePanels
---@field open fun(which: Sheet.PanelName, arg?: any) Shows a panel. The chart panel takes a chart id.
---@field chart_selected fun(id?: string) The grid selected a chart, or none.

---@class Sheet.PanelSideModule
local M = {}

-- lang=css
local CSS = [[
.sheet-panel {
  display: flex;
  flex-direction: column;
  height: 100%;
  min-height: 0;
  color: var(--fg);
  font-family: var(--font-ui);
  font-size: var(--font-size);
}
.sheet-panel-head {
  flex: none;
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 12px 12px 8px 14px;
}
.sheet-panel-title {
  flex: 1;
  min-width: 0;
  font-size: 14px;
  font-weight: 600;
}
.sheet-panel-body {
  flex: 1;
  min-height: 0;
  overflow: auto;
  padding: 2px 14px 18px;
  display: flex;
  flex-direction: column;
  gap: 14px;
}
.sheet-panel-field {
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.sheet-panel-label {
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 0.04em;
  text-transform: uppercase;
  color: var(--fg-muted);
}
.sheet-panel-hint {
  font-size: 12px;
  color: var(--fg-muted);
  line-height: 1.45;
}
.sheet-panel .ui-input,
.sheet-panel-select {
  width: 100%;
}
.sheet-panel-select {
  padding: 5px 7px;
  border-radius: var(--radius);
  border: 1px solid var(--border);
  background: var(--bg);
  color: var(--fg);
  outline: none;
}
.sheet-panel-select:focus {
  border-color: var(--accent);
}
.sheet-panel-mono {
  font-family: var(--font-mono);
}
.sheet-panel-bad,
.sheet-panel .sheet-panel-bad {
  border-color: var(--danger);
}
.sheet-panel-row {
  display: flex;
  align-items: center;
  gap: 8px;
}
.sheet-panel-row > .ui-input,
.sheet-panel-row > .sheet-panel-select {
  flex: 1;
  min-width: 0;
}
.sheet-panel-seg {
  display: flex;
  border: 1px solid var(--border);
  border-radius: var(--radius);
  overflow: hidden;
  background: var(--bg);
}
.sheet-panel-seg button {
  flex: 1;
  padding: 5px 8px;
  border: none;
  background: transparent;
  color: var(--fg-muted);
  cursor: pointer;
  font: inherit;
  white-space: nowrap;
}
.sheet-panel-seg button + button {
  border-left: 1px solid var(--border);
}
.sheet-panel-seg button:hover {
  color: var(--fg);
  background: var(--bg-hover);
}
.sheet-panel-seg button.on {
  background: var(--bg-active);
  color: var(--accent);
  font-weight: 600;
}
.sheet-panel-types {
  display: grid;
  grid-template-columns: repeat(7, 1fr);
  gap: 4px;
}
.sheet-panel-type {
  height: 34px;
  display: grid;
  place-items: center;
  border: 1px solid var(--border);
  border-radius: var(--radius);
  background: var(--bg);
  color: var(--fg-muted);
  cursor: pointer;
}
.sheet-panel-type:hover {
  color: var(--fg);
  background: var(--bg-hover);
}
.sheet-panel-type.on {
  border-color: var(--accent);
  background: var(--bg-active);
  color: var(--accent);
}
.sheet-panel-check {
  display: flex;
  align-items: center;
  gap: 8px;
  cursor: pointer;
  user-select: none;
}
.sheet-panel-check input {
  margin: 0;
  accent-color: var(--accent);
}
.sheet-panel-list {
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.sheet-panel-card {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 8px 8px 8px 10px;
  border: 1px solid var(--border);
  border-radius: var(--radius);
  background: var(--bg-elev);
  cursor: pointer;
}
.sheet-panel-card:hover {
  border-color: color-mix(in srgb, var(--accent) 55%, var(--border));
}
.sheet-panel-card-main {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 2px;
}
.sheet-panel-range {
  font-family: var(--font-mono);
  font-size: 11px;
  color: var(--fg-muted);
}
.sheet-panel-desc {
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.sheet-panel-preview {
  flex: none;
  width: 46px;
  height: 26px;
  display: grid;
  place-items: center;
  border-radius: 4px;
  border: 1px solid var(--border);
  background: var(--bg);
  color: var(--fg);
  font-size: 12px;
  overflow: hidden;
}
.sheet-panel-tools {
  flex: none;
  display: flex;
  gap: 1px;
  opacity: 0;
}
.sheet-panel-card:hover .sheet-panel-tools {
  opacity: 1;
}
.sheet-panel-icon {
  width: 24px;
  height: 24px;
  display: grid;
  place-items: center;
  border: none;
  border-radius: var(--radius);
  background: transparent;
  color: var(--fg-muted);
  cursor: pointer;
  padding: 0;
}
.sheet-panel-icon:hover:not(:disabled) {
  background: var(--bg-hover);
  color: var(--fg);
}
.sheet-panel-icon:disabled {
  opacity: 0.3;
  cursor: default;
}
.sheet-panel-empty {
  padding: 18px 8px;
  text-align: center;
  color: var(--fg-faint);
  line-height: 1.5;
}
.sheet-panel-actions {
  display: flex;
  align-items: center;
  gap: 8px;
}
.sheet-panel-actions .sheet-panel-spacer {
  flex: 1;
}
.sheet-panel-wide {
  width: 100%;
  justify-content: center;
}
.sheet-panel-color {
  width: 30px;
  height: 24px;
  flex: none;
  padding: 0;
  border-radius: 4px;
  border: 1px solid color-mix(in srgb, var(--fg) 25%, transparent);
  cursor: pointer;
}
.sheet-panel-color.none {
  background: linear-gradient(
    to top right,
    transparent 45%,
    var(--danger) 45% 55%,
    transparent 55%
  ) !important;
}
.sheet-panel-toggles {
  display: flex;
  gap: 2px;
}
.sheet-panel-toggle {
  width: 30px;
  height: 28px;
  display: grid;
  place-items: center;
  border: 1px solid transparent;
  border-radius: var(--radius);
  background: transparent;
  color: var(--fg);
  cursor: pointer;
  padding: 0;
}
.sheet-panel-toggle:hover {
  background: var(--bg-hover);
}
.sheet-panel-toggle.on {
  background: var(--bg-active);
  color: var(--accent);
}
.sheet-panel-sample {
  height: 30px;
  display: grid;
  place-items: center;
  border: 1px solid var(--border);
  border-radius: var(--radius);
  background: var(--bg);
  color: var(--fg);
}
.sheet-panel-meta {
  display: flex;
  align-items: center;
  gap: 8px;
}
.sheet-panel-badge {
  flex: none;
  padding: 0 6px;
  border-radius: 9px;
  font-size: 11px;
  line-height: 17px;
  background: var(--bg-active);
  color: var(--fg-muted);
}
.sheet-panel-key {
  display: flex;
  gap: 6px;
  align-items: center;
}
.sheet-panel-key .sheet-panel-select {
  flex: 1;
  min-width: 0;
}
.sheet-panel-key .sheet-panel-seg {
  flex: none;
}
.sheet-panel-link {
  align-self: flex-start;
  border: none;
  background: transparent;
  color: var(--accent);
  padding: 2px 0;
  cursor: pointer;
  font: inherit;
  display: inline-flex;
  align-items: center;
  gap: 4px;
}
.sheet-panel-link:disabled {
  color: var(--fg-faint);
  cursor: default;
}
.sheet-panel-sep {
  height: 1px;
  background: var(--border);
  margin: 2px 0;
}
]]

---@type table<Sheet.PanelName, { id: string, title: string, heading: string, order: number }>
local VIEWS = {
  chart = {
    id = 'sheet.panel.chart',
    title = 'Chart',
    heading = 'Chart',
    order = 10,
  },
  rules = {
    id = 'sheet.panel.rules',
    title = 'Formatting',
    heading = 'Conditional formatting',
    order = 11,
  },
  validation = {
    id = 'sheet.panel.validation',
    title = 'Validation',
    heading = 'Data validation',
    order = 12,
  },
  sort = {
    id = 'sheet.panel.sort',
    title = 'Sort',
    heading = 'Sort range',
    order = 13,
  },
  names = {
    id = 'sheet.panel.names',
    title = 'Names',
    heading = 'Defined names',
    order = 14,
  },
}

---@param env Sheet.PanelEnv
---@return Sheet.SidePanels
function M.install (env)
  local app, ctl, ui = env.app, env.ctl, env.ui
  local views = app.try_use ('views')
  local shell = app.try_use ('shell')
  ui.css (CSS)

  local current = nil ---@type Sheet.PanelName?
  local bodies = {} ---@type table<Sheet.PanelName, Proteus.El>
  local renders = {} ---@type table<Sheet.PanelName, fun()>

  ---@param name Sheet.PanelName
  ---@return boolean
  local function visible (name)
    return current == name and (not shell or shell.is_visible ('right'))
  end

  ---@param name Sheet.PanelName
  local function render (name)
    local fn = renders[name]
    if fn then
      fn ()
    end
  end

  -- Small builders ---------------------------------------------------------------------

  ---@param label string
  ---@param ... Proteus.Child
  ---@return Proteus.El
  local function field (label, ...)
    return ui.div ({
      class = 'sheet-panel-field',
      ui.span ({ class = 'sheet-panel-label', label }),
      ...,
    })
  end

  ---@param message string
  ---@return Proteus.El
  local function empty (message)
    return ui.div ({ class = 'sheet-panel-empty', message })
  end

  ---@param options { value: string, label: string }[]
  ---@param value string
  ---@param on_change fun(value: string)
  ---@return Proteus.El
  local function select (options, value, on_change)
    local el = ui.h ('select', { class = 'sheet-panel-select' })
    for _, o in ipairs (options) do
      el:append (ui.option ({ value = o.value, o.label }))
    end
    el:set ('value', value)
    el:on ('change', function (ev)
      on_change (ev.value or '')
      return nil
    end)
    return el
  end

  ---A row of buttons of which one is on.
  ---@param options { value: string, label: string }[]
  ---@param value string
  ---@param on_pick fun(value: string)
  ---@return Proteus.El
  local function segmented (options, value, on_pick)
    local el = ui.div ({ class = 'sheet-panel-seg' })
    local buttons = {} ---@type Proteus.El[]
    for i, o in ipairs (options) do
      local b = ui.h ('button', {
        class = o.value == value and 'on' or nil,
        o.label,
      })
      b:on ('click', function ()
        for j, other in ipairs (buttons) do
          other:class ('on', j == i)
        end
        on_pick (o.value)
        return nil
      end)
      buttons[i] = b
      el:append (b)
    end
    return el
  end

  ---@param label string
  ---@param on boolean
  ---@param on_change fun(on: boolean)
  ---@return Proteus.El
  local function check (label, on, on_change)
    local box = ui.h ('input', { type = 'checkbox', checked = on })
    box:on ('change', function (ev)
      on_change (ev.checked == true)
      return nil
    end)
    return ui.label ({ class = 'sheet-panel-check', box, ui.span ({ label }) })
  end

  ---A text box that reports its text on Enter and when it loses focus after a change.
  ---@param value string
  ---@param on_commit fun(value: string, el: Proteus.El)
  ---@param opts? { placeholder?: string, mono?: boolean }
  ---@return Proteus.El
  local function input (value, on_commit, opts)
    local o = opts or {}
    local el = ui.input ({
      value = value,
      placeholder = o.placeholder,
      spellcheck = false,
      class = o.mono and 'sheet-panel-mono' or nil,
    })
    local last = value
    ---@param text_now string
    local function commit (text_now)
      if text_now ~= last then
        last = text_now
        on_commit (text_now, el)
      end
    end
    el:on ('keydown', function (ev)
      if ev.key == 'Enter' then
        commit (el:value ())
        return 'stop'
      end
      return nil
    end)
    el:on ('change', function (ev)
      commit (ev.value or '')
      return nil
    end)
    return el
  end

  ---A swatch button that opens the colour palette.
  ---@param color? string
  ---@param title string
  ---@param on_pick fun(color?: string)
  ---@return Proteus.El
  local function color_button (color, title, on_pick)
    local el = ui.h ('button', { class = 'sheet-panel-color', title = title })
    local now = color
    ---@param c? string
    local function show (c)
      el:style ('background', c or 'transparent')
      el:class ('none', c == nil)
    end
    show (now)
    el:on ('click', function ()
      if env.pop and env.pop.opts.owner == el then
        pop.close (env)
        return nil
      end
      pop.palette (env, el:rect (), now, function (c)
        now = c or nil
        show (now)
        on_pick (now)
      end, { owner = el, keep_focus = true })
      return nil
    end)
    return el
  end

  ---@param icon string
  ---@param title string
  ---@param run fun()
  ---@param disabled? boolean
  ---@return Proteus.El
  local function icon_button (icon, title, run, disabled)
    local el = ui.h ('button', {
      class = 'sheet-panel-icon',
      title = title,
      disabled = disabled or false,
      ui.icon (icon, 14),
    })
    el:on ('click', function ()
      run ()
      return 'stop'
    end)
    return el
  end

  ---The selection as range text, such as `B2:D9`.
  ---@return string
  local function selection_text ()
    local rect = ctl.selection ()
    return model.range_name (rect)
  end

  ---A range typed in a form, tidied, or nil with the box marked when it does not read.
  ---@param el Proteus.El
  ---@param value string
  ---@return Sheet.Rect?
  local function read_range (el, value)
    local rect = model.parse_range (value)
    el:class ('sheet-panel-bad', rect == nil)
    return rect
  end

  -- The frame of each panel --------------------------------------------------------------

  ---@param name Sheet.PanelName
  ---@return Proteus.El
  local function frame (name)
    local spec = VIEWS[name]
    local body = ui.div ({ class = 'sheet-panel-body' })
    bodies[name] = body
    return ui.div ({
      class = 'sheet-panel',
      ui.div ({
        class = 'sheet-panel-head',
        ui.span ({ class = 'sheet-panel-title', spec.heading }),
        icon_button ('x', 'Close the panel', function ()
          if shell then
            shell.set_visible ('right', false)
          end
          ctl.focus ()
        end),
      }),
      body,
    })
  end

  -- The panels -------------------------------------------------------------------------

  ---What each panel gets: the controller, the bodies and drawing functions of every panel, and
  ---the small builders above.
  ---@class Sheet.SidePanelKit
  local kit = {
    env = env,
    ctl = ctl,
    ui = ui,
    bodies = bodies,
    renders = renders,
    field = field,
    empty = empty,
    select = select,
    segmented = segmented,
    check = check,
    input = input,
    color_button = color_button,
    icon_button = icon_button,
    selection_text = selection_text,
    read_range = read_range,
  }
  local chart_panel = chart_mod.install (kit)
  local rules_panel = rules_mod.install (kit)
  local checks_panel = validation_mod.install (kit)
  local names_panel = names_mod.install (kit)
  local sort_panel = sort_mod.install (kit)

  -- The views --------------------------------------------------------------------------

  ---@type Sheet.PanelName[]
  local NAMES = { 'chart', 'rules', 'validation', 'sort', 'names' }
  local has_views = views ~= nil
  if views then
    for _, name in ipairs (NAMES) do
      local spec = VIEWS[name]
      local panel_name = name
      views.add ('right', {
        id = spec.id,
        title = spec.title,
        order = spec.order,
        content = frame (name),
        on_show = function ()
          current = panel_name
          render (panel_name)
        end,
      })
    end
    -- The panels open when a command asks for one, not at start.
    if shell then
      shell.set_visible ('right', false)
    end
  end

  ---@param which Sheet.PanelName
  ---@param arg? any
  local function open (which, arg)
    if not has_views or not views then
      ctl.say ('warn', 'The side panels need the Views plugin.')
      return
    end
    if which == 'chart' and type (arg) == 'string' then
      chart_panel.set_id (arg)
    elseif which == 'rules' then
      rules_panel.reset ()
    elseif which == 'validation' then
      checks_panel.reset ()
    elseif which == 'sort' then
      sort_panel.reset ()
    elseif which == 'names' then
      names_panel.reset ()
    end
    -- Showing the view runs its on_show, which draws it.
    views.show (VIEWS[which].id)
  end

  -- Following the grid ------------------------------------------------------------------

  ctl.on ('book', function ()
    chart_panel.set_id (nil)
    rules_panel.reset ()
    checks_panel.reset ()
    names_panel.reset ()
    sort_panel.reset ()
    if current then
      render (current)
    end
  end)
  ctl.on ('sheet', function ()
    chart_panel.set_id (nil)
    rules_panel.reset ()
    checks_panel.reset ()
    sort_panel.reset ()
    if current and visible (current) then
      render (current)
    end
  end)
  ctl.on ('selection', function ()
    if
      visible ('rules')
      and not rules_panel.editing ()
      and rules_panel.scope () == 'selection'
    then
      renders.rules ()
    elseif
      visible ('validation')
      and not checks_panel.editing ()
      and checks_panel.scope () == 'selection'
    then
      renders.validation ()
    end
  end)
  ctl.on ('changed', function ()
    if visible ('chart') then
      chart_panel.check ()
    elseif visible ('rules') and not rules_panel.editing () then
      renders.rules ()
    elseif visible ('validation') and not checks_panel.editing () then
      renders.validation ()
    elseif visible ('names') and not names_panel.editing () then
      renders.names ()
    end
  end)

  ---@type Sheet.SidePanels
  local api = {
    open = open,
    chart_selected = function (id)
      if id and id ~= chart_panel.id () then
        chart_panel.set_id (id)
        if visible ('chart') then
          renders.chart ()
        end
      end
    end,
  }
  return api
end

return M
