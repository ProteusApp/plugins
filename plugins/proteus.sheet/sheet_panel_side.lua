-- sheet_panel_side: the Sheet app's side panels, in the right dock.
--
-- Four panels share the dock, each a view with its own tab: Chart, Formatting (conditional
-- formatting), Validation and Sort. The chart panel applies each change as it is made, as one
-- undo step. The rule panels list the rules as cards and edit one at a time in a form, which
-- saves on Done. A panel draws again after a change only when what it shows went out of date,
-- so a box being typed in keeps its focus.

local chart = require ('sheet_chart') --[[@as Sheet.ChartModule]]
local format = require ('sheet_format') --[[@as Sheet.FormatModule]]
local formula = require ('sheet_formula') --[[@as Sheet.FormulaModule]]
local model = require ('sheet_model') --[[@as Sheet.ModelModule]]
local ops = require ('sheet_ops') --[[@as Sheet.OpsModule]]
local pop = require ('sheet_panel_pop') --[[@as Sheet.PanelPopModule]]
local text = require ('sheet_panel_text') --[[@as Sheet.PanelTextModule]]

---@alias Sheet.PanelName 'chart'|'rules'|'validation'|'sort'|'names'

---The side panels, as sheet_panels drives them.
---@class Sheet.SidePanels
---@field open fun(which: Sheet.PanelName, arg?: any) Shows a panel. The chart panel takes a chart id.
---@field chart_selected fun(id?: string) The grid selected a chart, or none.

---A rule being edited in the conditional formatting form.
---@class Sheet.RuleDraft
---@field index? integer The rule's place in the sheet's list, or nil for a new rule.
---@field range string
---@field cond string A condition id from `sheet_panel_text`.
---@field a string
---@field b string
---@field style Sheet.Style
---@field min_color string
---@field mid_color? string
---@field max_color string
---@field bar_color string
---@field icons string The icon set of an icon set rule.
---@field reverse boolean True to give the lowest values the first icon.
---@field stop boolean Stop if true.

---A defined name being edited.
---@class Sheet.NameDraft
---@field old? string The name as it was, or nil for a new one.
---@field name string
---@field formula string

---A validation rule being edited.
---@class Sheet.ValidationDraft
---@field index? integer
---@field range string
---@field type 'list'|'number'|'date'|'length'|'formula'
---@field items string The items one per line, or a reference to cells such as `=$A$1:$A$9`.
---@field formula string The formula of a formula rule.
---@field op string
---@field a string
---@field b string
---@field integer boolean
---@field message string
---@field strict boolean

---One key of the sort form.
---@class Sheet.SortRow
---@field col integer
---@field desc boolean

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

---@type { value: string, label: string }[]
local LEGENDS = {
  { value = 'bottom', label = 'Bottom' },
  { value = 'top', label = 'Top' },
  { value = 'right', label = 'Right' },
  { value = 'none', label = 'None' },
}

---@type table<string, boolean>
local STACKABLE = { column = true, bar = true, area = true }

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

---@param t table
---@return table
local function copy (t)
  local out = {} ---@type table<any, any>
  for k, v in
    pairs (t --[[@as table<any, any>]])
  do
    out[k] = v
  end
  return out
end

---The chart fields the panel shows, to tell whether a change came from somewhere else.
---@param spec Sheet.ChartSpec
---@return string
local function chart_key (spec)
  return table.concat ({
    spec.id,
    spec.type,
    spec.range,
    tostring (spec.series_in),
    tostring (spec.headers),
    tostring (spec.stacked),
    spec.title or '',
    spec.legend or '',
    spec.x_title or '',
    spec.y_title or '',
  }, '\1')
end

---The icon of a chart type.
---@param kind string
---@return string
local function chart_icon (kind)
  for _, t in ipairs (chart.types) do
    if t.id == kind then
      return t.icon
    end
  end
  return 'chart-column'
end

---The CSS a rule's style shows in a small preview box.
---@param style? Sheet.Style
---@return string
local function style_css (style)
  local s = style or {}
  local parts = {} ---@type string[]
  if s.fill then
    parts[#parts + 1] = 'background:' .. s.fill
  end
  if s.color then
    parts[#parts + 1] = 'color:' .. s.color
  elseif s.fill then
    parts[#parts + 1] = 'color:'
      .. (text.is_dark (s.fill) and '#ffffff' or '#1f1f1f')
  end
  if s.bold then
    parts[#parts + 1] = 'font-weight:700'
  end
  if s.italic then
    parts[#parts + 1] = 'font-style:italic'
  end
  local lines = {} ---@type string[]
  if s.strike then
    lines[#lines + 1] = 'line-through'
  end
  if s.underline then
    lines[#lines + 1] = 'underline'
  end
  if #lines > 0 then
    parts[#parts + 1] = 'text-decoration:' .. table.concat (lines, ' ')
  end
  return table.concat (parts, ';')
end

---The CSS background of a colour scale or data bar preview.
---@param rule Sheet.Rule
---@return string
local function rule_background (rule)
  if rule.type == 'scale' then
    local stops = { rule.min_color or text.SCALE_MIN }
    if rule.mid_color then
      stops[#stops + 1] = rule.mid_color
    end
    stops[#stops + 1] = rule.max_color or text.SCALE_MAX
    return 'background:linear-gradient(90deg,'
      .. table.concat (stops, ',')
      .. ')'
  end
  local color = rule.color or text.BAR_COLOR
  return 'background:linear-gradient(90deg,'
    .. color
    .. ' 0 62%,transparent 62%)'
end

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

  -- Chart ------------------------------------------------------------------------------

  local chart_id = nil ---@type string?
  local chart_shown = nil ---@type string? The fields the chart form shows, from `chart_key`.

  ---@param id string
  ---@param label string
  ---@param fn fun(sheet: Sheet.Sheet)
  local function chart_change (id, label, fn)
    ctl.change (label, function (_, sheet)
      if ops.chart_by_id (sheet, id) then
        fn (sheet)
      end
      -- Noted before the grid reports the change, so the panel knows it made it.
      local spec = ops.chart_by_id (sheet, id)
      chart_shown = spec and chart_key (spec) or nil
    end)
  end

  ---@param id string
  ---@param patch table<string, any>
  local function chart_update (id, patch)
    chart_change (id, 'Change chart', function (sheet)
      ops.update_chart (sheet, id, patch)
    end)
  end

  ---Puts one field of a chart back to automatic.
  ---@param id string
  ---@param name string
  local function chart_clear (id, name)
    chart_change (id, 'Change chart', function (sheet)
      local spec = ops.chart_by_id (sheet, id)
      if spec and spec[name] ~= nil then
        ops.update_chart (sheet, id, {}, { name })
      end
    end)
  end

  renders.chart = function ()
    local body = bodies.chart
    body:clear ()
    chart_shown = nil
    local sheet = ctl.sheet ()
    if not sheet then
      body:append (empty ('Open a workbook to work with charts.'))
      return
    end
    local spec = chart_id and ops.chart_by_id (sheet, chart_id) or nil
    if not spec then
      body:append (
        ui.div ({
          class = 'sheet-panel-hint',
          'Select a chart on the sheet to change it, or insert one from the selected cells.',
        }),
        ui.button ({
          'Insert chart',
          icon = 'chart-column',
          variant = 'primary',
          class = 'sheet-panel-wide',
          onclick = function ()
            pop.act (env, 'sheet.chart')
            return nil
          end,
        })
      )
      if #sheet.charts > 0 then
        local list = ui.div ({ class = 'sheet-panel-list' })
        for i, c in ipairs (sheet.charts) do
          local label = (c.title and c.title ~= '') and c.title
            or ('Chart ' .. i)
          local card = ui.div ({
            class = 'sheet-panel-card',
            ui.icon (chart_icon (c.type), 16),
            ui.div ({
              class = 'sheet-panel-card-main',
              ui.span ({ class = 'sheet-panel-desc', label }),
              ui.span ({ class = 'sheet-panel-range', c.range }),
            }),
          })
          card:on ('click', function ()
            ctl.select_chart (c.id)
            chart_id = c.id
            renders.chart ()
            return nil
          end)
          list:append (card)
        end
        body:append (field ('Charts on this sheet', list))
      end
      return
    end
    local id = spec.id
    chart_shown = chart_key (spec)

    local types = ui.div ({ class = 'sheet-panel-types' })
    local type_buttons = {} ---@type Proteus.El[]
    for i, t in ipairs (chart.types) do
      local b = ui.h ('button', {
        class = 'sheet-panel-type' .. (t.id == spec.type and ' on' or ''),
        title = t.label,
        ui.icon (t.icon, 18),
      })
      b:on ('click', function ()
        for j, other in ipairs (type_buttons) do
          other:class ('on', j == i)
        end
        chart_update (id, { type = t.id })
        renders.chart ()
        return nil
      end)
      type_buttons[i] = b
      types:append (b)
    end

    local range = input (spec.range, function (value, el)
      local rect = read_range (el, value)
      if rect then
        local name = model.range_name (rect)
        el:value (name)
        chart_update (id, { range = name })
      end
    end, { mono = true })

    local series = segmented (
      {
        { value = 'auto', label = 'Automatic' },
        { value = 'cols', label = 'Columns' },
        { value = 'rows', label = 'Rows' },
      },
      spec.series_in or 'auto',
      function (value)
        if value == 'auto' then
          chart_clear (id, 'series_in')
        else
          chart_update (id, { series_in = value })
        end
      end
    )

    local headers = select (
      {
        { value = 'auto', label = 'Automatic' },
        { value = 'yes', label = 'First row and column' },
        { value = 'no', label = 'None' },
      },
      spec.headers == nil and 'auto' or (spec.headers and 'yes' or 'no'),
      function (value)
        if value == 'auto' then
          chart_clear (id, 'headers')
        else
          chart_update (id, { headers = value == 'yes' })
        end
      end
    )

    ---@param key string
    ---@param placeholder string
    ---@return Proteus.El
    local function title_box (key, placeholder)
      local spec_fields = spec --[[@as table<string, any>]]
      return input (spec_fields[key] or '', function (value)
        chart_update (id, { [key] = value })
      end, { placeholder = placeholder })
    end

    local legend = select (LEGENDS, spec.legend or 'bottom', function (value)
      chart_update (id, { legend = value })
    end)

    local pie = spec.type == 'pie' or spec.type == 'doughnut'
    body:append (
      field ('Chart type', types),
      field ('Data range', range),
      field ('Series in', series),
      field ('Headers', headers),
      STACKABLE[spec.type]
          and check ('Stack the series', spec.stacked == true, function (on)
            chart_update (id, { stacked = on })
          end)
        or nil,
      ui.div ({ class = 'sheet-panel-sep' }),
      field ('Title', title_box ('title', 'No title')),
      not pie
          and field (
            spec.type == 'scatter' and 'X axis title' or 'Category axis title',
            title_box ('x_title', 'None')
          )
        or nil,
      not pie
          and field (
            spec.type == 'scatter' and 'Y axis title' or 'Value axis title',
            title_box ('y_title', 'None')
          )
        or nil,
      field ('Legend', legend),
      ui.div ({ class = 'sheet-panel-sep' }),
      ui.div ({
        class = 'sheet-panel-actions',
        ui.button ({
          'Delete chart',
          icon = 'trash-2',
          variant = 'danger',
          onclick = function ()
            ctl.change ('Delete chart', function (_, s)
              ops.delete_chart (s, id)
            end)
            ctl.select_chart (nil)
            chart_id = nil
            renders.chart ()
            return nil
          end,
        }),
      })
    )
  end

  ---Draws the chart panel again when its chart changed in a way the form did not make,
  ---such as an undo.
  local function chart_check ()
    local sheet = ctl.sheet ()
    local spec = sheet and chart_id and ops.chart_by_id (sheet, chart_id) or nil
    local key = spec and chart_key (spec) or nil
    if key ~= chart_shown then
      renders.chart ()
    end
  end

  -- Conditional formatting --------------------------------------------------------------

  local rules_scope = 'selection' ---@type 'selection'|'all'
  local rule_draft = nil ---@type Sheet.RuleDraft?

  ---@param rule? Sheet.Rule
  ---@param index? integer
  ---@return Sheet.RuleDraft
  local function new_rule_draft (rule, index)
    if rule then
      local style = copy (rule.style or {}) --[[@as Sheet.Style]]
      return {
        index = index,
        range = rule.range,
        cond = text.condition_of (rule),
        a = rule.formula
          or (rule.count and tostring (rule.count))
          or rule.value
          or '',
        b = rule.value2 or '',
        style = style,
        min_color = rule.min_color or text.SCALE_MIN,
        mid_color = rule.mid_color,
        max_color = rule.max_color or text.SCALE_MAX,
        bar_color = rule.color or text.BAR_COLOR,
        icons = rule.icons or 'arrows',
        reverse = rule.reverse == true,
        stop = rule.stop == true,
      }
    end
    return {
      range = selection_text (),
      cond = '>',
      a = '',
      b = '',
      style = { color = text.RULE_COLOR, fill = text.RULE_FILL },
      min_color = text.SCALE_MIN,
      mid_color = text.SCALE_MID,
      max_color = text.SCALE_MAX,
      bar_color = text.BAR_COLOR,
      icons = 'arrows',
      reverse = false,
      stop = false,
    }
  end

  ---@param draft Sheet.RuleDraft
  ---@return Sheet.Rule
  local function rule_of (draft)
    local rule = text.rule_fields (draft.cond, draft.a, draft.b) --[[@as Sheet.Rule]]
    rule.range = draft.range
    if rule.type == 'scale' then
      rule.min_color = draft.min_color
      rule.mid_color = draft.mid_color
      rule.max_color = draft.max_color
    elseif rule.type == 'bar' then
      rule.color = draft.bar_color
    elseif rule.type == 'icons' then
      rule.icons = draft.icons
      rule.reverse = draft.reverse or nil
    else
      local style = {} ---@type table<string, any>
      for k, v in
        pairs (draft.style --[[@as table<string, any>]])
      do
        if v ~= false and v ~= nil then
          style[k] = v
        end
      end
      rule.style = style --[[@as Sheet.Style]]
    end
    rule.stop = draft.stop or nil
    return rule
  end

  ---The rule list: cards for the rules in scope, and Add rule.
  ---@param body Proteus.El
  ---@param sheet Sheet.Sheet
  local function rules_list (body, sheet)
    local sel = ctl.selection ()
    body:append (segmented (
      {
        { value = 'selection', label = 'This selection' },
        { value = 'all', label = 'Whole sheet' },
      },
      rules_scope,
      function (value)
        rules_scope = value == 'all' and 'all' or 'selection'
        renders.rules ()
      end
    ))
    local list = ui.div ({ class = 'sheet-panel-list' })
    local count = 0
    for i, rule in ipairs (sheet.rules) do
      local rect = model.parse_range (rule.range)
      local shown = rules_scope == 'all'
        or (rect ~= nil and model.overlaps (rect, sel))
      if shown then
        count = count + 1
        local preview ---@type Proteus.El
        if rule.type == 'scale' or rule.type == 'bar' then
          preview = ui.div ({
            class = 'sheet-panel-preview',
            style = rule_background (rule),
          })
        else
          preview = ui.div ({
            class = 'sheet-panel-preview',
            style = style_css (rule.style),
            '123',
          })
        end
        local index = i
        local card = ui.div ({
          class = 'sheet-panel-card',
          title = 'Edit this rule',
          preview,
          ui.div ({
            class = 'sheet-panel-card-main',
            ui.span ({ class = 'sheet-panel-desc', text.describe_rule (rule) }),
            ui.span ({ class = 'sheet-panel-range', rule.range }),
          }),
          ui.div ({
            class = 'sheet-panel-tools',
            icon_button (
              'arrow-up',
              'Move up, so it wins over the rules below it',
              function ()
                ctl.change ('Move rule', function (_, s)
                  local a, b = s.rules[index - 1], s.rules[index]
                  ops.set_rule (s, index - 1, b)
                  ops.set_rule (s, index, a)
                end)
              end,
              index == 1
            ),
            icon_button (
              'arrow-down',
              'Move down, so the rules above it win over it',
              function ()
                ctl.change ('Move rule', function (_, s)
                  local a, b = s.rules[index], s.rules[index + 1]
                  ops.set_rule (s, index, b)
                  ops.set_rule (s, index + 1, a)
                end)
              end,
              index == #sheet.rules
            ),
            icon_button ('trash-2', 'Delete the rule', function ()
              ctl.change ('Delete rule', function (_, s)
                ops.set_rule (s, index, nil)
              end)
            end),
          }),
        })
        card:on ('click', function ()
          rule_draft = new_rule_draft (rule, index)
          renders.rules ()
          return nil
        end)
        list:append (card)
      end
    end
    if count == 0 then
      list:append (
        empty (
          rules_scope == 'all' and 'This sheet has no rules yet.'
            or 'No rules touch the selected cells.'
        )
      )
    end
    body:append (
      list,
      ui.button ({
        'Add rule',
        icon = 'plus',
        class = 'sheet-panel-wide',
        onclick = function ()
          rule_draft = new_rule_draft ()
          renders.rules ()
          return nil
        end,
      }),
      ui.div ({
        class = 'sheet-panel-hint',
        'A rule higher in the list wins where two set the same thing, and a rule set to stop keeps the rules below it from applying.',
      })
    )
  end

  ---The form for one rule.
  ---@param body Proteus.El
  ---@param draft Sheet.RuleDraft
  local function rules_form (body, draft)
    local range = input (draft.range, function (value, el)
      local rect = read_range (el, value)
      if rect then
        draft.range = model.range_name (rect)
        el:value (draft.range)
      end
    end, { mono = true })

    local a_box = input (draft.a, function (value)
      draft.a = value
    end)
    local b_box = input (draft.b, function (value)
      draft.b = value
    end)
    local and_word = ui.span ({ class = 'sheet-panel-hint', 'and' })
    local values =
      ui.div ({ class = 'sheet-panel-row', a_box, and_word, b_box })
    local values_hint = ui.div ({ class = 'sheet-panel-hint' })

    local sample = ui.div ({ class = 'sheet-panel-sample', 'Sample 123' })
    local function show_sample ()
      sample:attr ('style', style_css (draft.style))
    end
    ---@param field_name 'bold'|'italic'|'strike'|'underline'
    ---@param icon string
    ---@param title string
    ---@return Proteus.El
    local function style_toggle (field_name, icon, title)
      local on = draft.style[field_name] == true
      local b = ui.h ('button', {
        class = 'sheet-panel-toggle' .. (on and ' on' or ''),
        title = title,
        ui.icon (icon, 15),
      })
      b:on ('click', function ()
        local flags = draft.style --[[@as table<string, boolean?>]]
        local now = not (flags[field_name] == true)
        flags[field_name] = now or nil
        b:class ('on', now)
        show_sample ()
        return nil
      end)
      return b
    end
    local style_part = field (
      'Formatting style',
      ui.div ({
        class = 'sheet-panel-row',
        ui.div ({
          class = 'sheet-panel-toggles',
          style_toggle ('bold', 'bold', 'Bold'),
          style_toggle ('italic', 'italic', 'Italic'),
          style_toggle ('underline', 'underline', 'Underline'),
          style_toggle ('strike', 'strikethrough', 'Strikethrough'),
        }),
        ui.span ({ class = 'sheet-panel-spacer', style = 'flex:1' }),
        ui.span ({ class = 'sheet-panel-hint', 'Text' }),
        color_button (draft.style.color, 'Text colour', function (c)
          draft.style.color = c
          show_sample ()
        end),
        ui.span ({ class = 'sheet-panel-hint', 'Fill' }),
        color_button (draft.style.fill, 'Fill colour', function (c)
          draft.style.fill = c
          show_sample ()
        end),
      }),
      sample
    )
    show_sample ()

    local gradient = ui.div ({ class = 'sheet-panel-sample' })
    local function show_gradient ()
      gradient:attr (
        'style',
        rule_background ({
          range = '',
          type = 'scale',
          min_color = draft.min_color,
          mid_color = draft.mid_color,
          max_color = draft.max_color,
        })
      )
    end
    local mid_button = color_button (
      draft.mid_color,
      'Midpoint colour',
      function (c)
        draft.mid_color = c
        show_gradient ()
      end
    )
    local scale_part = field (
      'Colour scale',
      ui.div ({
        class = 'sheet-panel-row',
        ui.span ({ class = 'sheet-panel-hint', 'Lowest' }),
        color_button (
          draft.min_color,
          'Colour of the lowest value',
          function (c)
            draft.min_color = c or text.SCALE_MIN
            show_gradient ()
          end
        ),
        ui.span ({ class = 'sheet-panel-hint', 'Middle' }),
        mid_button,
        ui.span ({ class = 'sheet-panel-hint', 'Highest' }),
        color_button (
          draft.max_color,
          'Colour of the highest value',
          function (c)
            draft.max_color = c or text.SCALE_MAX
            show_gradient ()
          end
        ),
      }),
      gradient,
      ui.div ({
        class = 'sheet-panel-hint',
        'Reset the middle colour for a scale of two colours.',
      })
    )
    show_gradient ()

    local bar_part = field (
      'Data bar',
      ui.div ({
        class = 'sheet-panel-row',
        ui.span ({ class = 'sheet-panel-hint', 'Bar colour' }),
        color_button (draft.bar_color, 'Bar colour', function (c)
          draft.bar_color = c or text.BAR_COLOR
        end),
      })
    )

    local icons_part = field (
      'Icon set',
      select (text.ICON_SETS, draft.icons, function (value)
        draft.icons = value
      end),
      check ('Lowest values get the first icon', draft.reverse, function (on)
        draft.reverse = on
      end),
      ui.div ({
        class = 'sheet-panel-hint',
        'The top third of the range from the lowest value to the highest gets the first icon, the middle third the second, and the rest the last.',
      })
    )

    local function show_condition ()
      local c = text.condition (draft.cond) or text.CONDITIONS[1]
      local kind = c.input
      values:show (kind ~= 'none')
      b_box:show (kind == 'two')
      and_word:show (kind == 'two')
      a_box:set (
        'placeholder',
        kind == 'count' and '10'
          or kind == 'formula' and '=$B1>100'
          or 'Value or number'
      )
      a_box:class ('sheet-panel-mono', kind == 'formula')
      values_hint:show (kind == 'formula' or kind == 'count')
      if kind == 'formula' then
        values_hint:text (
          'Write the formula for the top left cell of the range. It moves to each cell as a copied formula does.'
        )
      elseif kind == 'count' then
        values_hint:text (
          c.percent and 'The percent of values to mark.'
            or 'How many values to mark.'
        )
      end
      style_part:show (
        c.type ~= 'scale' and c.type ~= 'bar' and c.type ~= 'icons'
      )
      scale_part:show (c.type == 'scale')
      bar_part:show (c.type == 'bar')
      icons_part:show (c.type == 'icons')
    end

    local options = {} ---@type { value: string, label: string }[]
    for _, c in ipairs (text.CONDITIONS) do
      options[#options + 1] = { value = c.id, label = c.label }
    end
    local cond = select (options, draft.cond, function (value)
      draft.cond = value
      show_condition ()
    end)
    show_condition ()

    ---@return boolean
    local function valid ()
      local rect = read_range (range, range:value ())
      if not rect then
        return false
      end
      draft.range = model.range_name (rect)
      draft.a = a_box:value ()
      draft.b = b_box:value ()
      local c = text.condition (draft.cond)
      local good = true
      if
        c and (c.input == 'one' or c.input == 'two' or c.input == 'formula')
      then
        a_box:class ('sheet-panel-bad', draft.a == '')
        good = draft.a ~= ''
      end
      if c and c.input == 'two' then
        b_box:class ('sheet-panel-bad', draft.b == '')
        good = good and draft.b ~= ''
      end
      if c and c.input == 'count' then
        local n = tonumber (draft.a)
        a_box:class ('sheet-panel-bad', not n or n <= 0)
        good = n ~= nil and n > 0
      end
      return good
    end

    local stop = check (
      'Stop if true: the rules below do not apply where this one holds',
      draft.stop,
      function (on)
        draft.stop = on
      end
    )
    body:append (
      field ('Apply to range', range),
      field ('Format cells if', cond, values, values_hint),
      style_part,
      scale_part,
      bar_part,
      icons_part,
      stop,
      ui.div ({
        class = 'sheet-panel-actions',
        draft.index and ui.button ({
          'Delete',
          variant = 'danger',
          onclick = function ()
            local index = draft.index
            ctl.change ('Delete rule', function (_, s)
              ops.set_rule (s, index --[[@as integer]], nil)
            end)
            rule_draft = nil
            renders.rules ()
            return nil
          end,
        }) or nil,
        ui.span ({ class = 'sheet-panel-spacer' }),
        ui.button ({
          'Cancel',
          onclick = function ()
            rule_draft = nil
            renders.rules ()
            return nil
          end,
        }),
        ui.button ({
          'Done',
          variant = 'primary',
          onclick = function ()
            if not valid () then
              return nil
            end
            local rule = rule_of (draft)
            local index = draft.index
            ctl.change (index and 'Change rule' or 'Add rule', function (_, s)
              if index and s.rules[index] then
                ops.set_rule (s, index, rule)
              else
                ops.add_rule (s, rule)
              end
            end)
            rule_draft = nil
            renders.rules ()
            return nil
          end,
        }),
      })
    )
  end

  renders.rules = function ()
    local body = bodies.rules
    body:clear ()
    local sheet = ctl.sheet ()
    if not sheet then
      rule_draft = nil
      body:append (empty ('Open a workbook to add formatting rules.'))
      return
    end
    if rule_draft then
      rules_form (body, rule_draft)
    else
      rules_list (body, sheet)
    end
  end

  -- Data validation --------------------------------------------------------------------

  local checks_scope = 'selection' ---@type 'selection'|'all'
  local check_draft = nil ---@type Sheet.ValidationDraft?

  ---@param v? Sheet.Validation
  ---@param index? integer
  ---@return Sheet.ValidationDraft
  local function new_check_draft (v, index)
    if v then
      local items = table.concat (v.values or {}, '\n')
      if v.type == 'list' and type (v.formula) == 'string' then
        items = v.formula
      end
      return {
        index = index,
        range = v.range,
        type = v.type or 'list',
        items = items,
        formula = v.type == 'formula' and v.formula or '',
        op = v.op or 'between',
        a = v.value or '',
        b = v.value2 or '',
        integer = v.integer == true,
        message = v.message or '',
        strict = v.strict ~= false,
      }
    end
    return {
      range = selection_text (),
      type = 'list',
      items = '',
      formula = '',
      op = 'between',
      a = '',
      b = '',
      integer = false,
      message = '',
      strict = true,
    }
  end

  ---@param body Proteus.El
  ---@param sheet Sheet.Sheet
  local function checks_list (body, sheet)
    local sel = ctl.selection ()
    body:append (segmented (
      {
        { value = 'selection', label = 'This selection' },
        { value = 'all', label = 'Whole sheet' },
      },
      checks_scope,
      function (value)
        checks_scope = value == 'all' and 'all' or 'selection'
        renders.validation ()
      end
    ))
    local list = ui.div ({ class = 'sheet-panel-list' })
    local count = 0
    for i, v in ipairs (sheet.validation) do
      local rect = model.parse_range (v.range)
      if checks_scope == 'all' or (rect and model.overlaps (rect, sel)) then
        count = count + 1
        local index = i
        local card = ui.div ({
          class = 'sheet-panel-card',
          title = 'Edit this rule',
          ui.icon (
            v.type == 'list' and 'list'
              or v.type == 'date' and 'calendar'
              or v.type == 'length' and 'type'
              or v.type == 'formula' and 'sigma'
              or 'hash',
            16
          ),
          ui.div ({
            class = 'sheet-panel-card-main',
            ui.span ({
              class = 'sheet-panel-desc',
              text.describe_validation (v),
            }),
            ui.div ({
              class = 'sheet-panel-meta',
              ui.span ({ class = 'sheet-panel-range', v.range }),
              ui.span ({
                class = 'sheet-panel-badge',
                v.strict == false and 'Warns' or 'Refuses',
              }),
            }),
          }),
          ui.div ({
            class = 'sheet-panel-tools',
            icon_button ('trash-2', 'Delete the rule', function ()
              ctl.change ('Delete validation', function (_, s)
                ops.set_validation (s, index, nil)
              end)
            end),
          }),
        })
        card:on ('click', function ()
          check_draft = new_check_draft (v, index)
          renders.validation ()
          return nil
        end)
        list:append (card)
      end
    end
    if count == 0 then
      list:append (
        empty (
          checks_scope == 'all' and 'This sheet has no validation rules yet.'
            or 'No validation rules cover the selected cells.'
        )
      )
    end
    body:append (
      list,
      ui.button ({
        'Add rule',
        icon = 'plus',
        class = 'sheet-panel-wide',
        onclick = function ()
          check_draft = new_check_draft ()
          renders.validation ()
          return nil
        end,
      }),
      ui.div ({
        class = 'sheet-panel-hint',
        'Where rules cover the same cell, the last one decides.',
      })
    )
  end

  ---@param body Proteus.El
  ---@param draft Sheet.ValidationDraft
  local function checks_form (body, draft)
    local range = input (draft.range, function (value, el)
      local rect = read_range (el, value)
      if rect then
        draft.range = model.range_name (rect)
        el:value (draft.range)
      end
    end, { mono = true })
    local items = ui.input ({
      multiline = true,
      value = draft.items,
      placeholder = 'Yes\nNo\nMaybe',
      spellcheck = false,
      rows = 5,
    })
    local list_part = field (
      'Items',
      items,
      ui.div ({
        class = 'sheet-panel-hint',
        'One item per line, or split by commas on one line, or cells such as =$A$1:$A$9. The cell gets a dropdown of them.',
      })
    )
    local a_box = input (draft.a, function (value)
      draft.a = value
    end, { placeholder = 'Number' })
    local b_box = input (draft.b, function (value)
      draft.b = value
    end, { placeholder = 'Number' })
    local formula_box = input (draft.formula, function (value)
      draft.formula = value
    end, { placeholder = '=AND(A1>0, A1<=$B$1)', mono = true })
    local formula_part = field (
      'Formula',
      formula_box,
      ui.div ({
        class = 'sheet-panel-hint',
        'Write the formula for the top left cell of the range. A value goes in when it gives TRUE.',
      })
    )
    local and_word = ui.span ({ class = 'sheet-panel-hint', 'and' })
    local function show_op ()
      local two = draft.op == 'between' or draft.op == 'not_between'
      b_box:show (two)
      and_word:show (two)
    end
    local op_options = {} ---@type { value: string, label: string }[]
    for _, o in ipairs (text.VALIDATION_OPS) do
      op_options[#op_options + 1] = { value = o.id, label = o.label }
    end
    local op = select (op_options, draft.op, function (value)
      draft.op = value
      show_op ()
    end)
    show_op ()
    local whole = check ('Whole numbers only', draft.integer, function (on)
      draft.integer = on
    end)
    local number_part = field (
      'Value',
      op,
      ui.div ({ class = 'sheet-panel-row', a_box, and_word, b_box }),
      whole
    )
    local function show_type ()
      local kind = draft.type
      list_part:show (kind == 'list')
      number_part:show (kind == 'number' or kind == 'date' or kind == 'length')
      formula_part:show (kind == 'formula')
      whole:show (kind == 'number')
      local hint = kind == 'date' and '1/1/2026'
        or kind == 'length' and 'Characters'
        or 'Number'
      a_box:set ('placeholder', hint)
      b_box:set ('placeholder', hint)
    end
    show_type ()
    local message = input (draft.message, function (value)
      draft.message = value
    end, { placeholder = 'Leave empty for the default message' })

    ---@return boolean
    local function valid ()
      local rect = read_range (range, range:value ())
      if not rect then
        return false
      end
      draft.range = model.range_name (rect)
      draft.items = items:value ()
      draft.a = a_box:value ()
      draft.b = b_box:value ()
      draft.formula = formula_box:value ()
      draft.message = message:value ()
      if draft.type == 'list' then
        local source = string.match (draft.items, '^%s*(=.-)%s*$')
        local good = #text.list_values (draft.items) > 0
        if source then
          good = formula.parse (source) ~= nil
        end
        items:class ('sheet-panel-bad', not good)
        return good
      elseif draft.type == 'formula' then
        local good = formula.is_formula (draft.formula)
          and formula.parse (draft.formula) ~= nil
        formula_box:class ('sheet-panel-bad', not good)
        return good
      end
      ---@param s string
      ---@return boolean
      local function readable (s)
        if draft.type == 'date' then
          return type (format.parse_input (s)) == 'number'
        end
        return tonumber (s) ~= nil
      end
      local two = draft.op == 'between' or draft.op == 'not_between'
      local good_a = readable (draft.a)
      local good_b = not two or readable (draft.b)
      a_box:class ('sheet-panel-bad', not good_a)
      b_box:class ('sheet-panel-bad', not good_b)
      return good_a and good_b
    end

    ---@return Sheet.Validation
    local function rule_of_draft ()
      local rule = { range = draft.range, type = draft.type } ---@type Sheet.Validation
      local source = string.match (draft.items, '^%s*(=.-)%s*$')
      if draft.type == 'list' and source then
        rule.formula = formula.normalize (source)
      elseif draft.type == 'list' then
        rule.values = text.list_values (draft.items)
      elseif draft.type == 'formula' then
        rule.formula = formula.normalize (draft.formula)
      else
        rule.op = draft.op
        rule.value = draft.a
        if draft.op == 'between' or draft.op == 'not_between' then
          rule.value2 = draft.b
        end
        rule.integer = draft.type == 'number' and draft.integer or nil
      end
      if draft.message ~= '' then
        rule.message = draft.message
      end
      if not draft.strict then
        rule.strict = false
      end
      return rule
    end

    body:append (
      field ('Apply to range', range),
      field (
        'Criteria',
        select (
          {
            { value = 'list', label = 'List of items' },
            { value = 'number', label = 'Number' },
            { value = 'date', label = 'Date' },
            { value = 'length', label = 'Text length' },
            { value = 'formula', label = 'Formula' },
          },
          draft.type,
          function (value)
            if
              value == 'number'
              or value == 'date'
              or value == 'length'
              or value == 'formula'
            then
              draft.type = value
            else
              draft.type = 'list'
            end
            show_type ()
          end
        )
      ),
      list_part,
      number_part,
      formula_part,
      field ('Message for data that breaks the rule', message),
      field (
        'When data breaks the rule',
        segmented (
          {
            { value = 'refuse', label = 'Refuse it' },
            { value = 'warn', label = 'Show a warning' },
          },
          draft.strict and 'refuse' or 'warn',
          function (value)
            draft.strict = value == 'refuse'
          end
        )
      ),
      ui.div ({
        class = 'sheet-panel-actions',
        draft.index and ui.button ({
          'Delete',
          variant = 'danger',
          onclick = function ()
            local index = draft.index
            ctl.change ('Delete validation', function (_, s)
              ops.set_validation (s, index --[[@as integer]], nil)
            end)
            check_draft = nil
            renders.validation ()
            return nil
          end,
        }) or nil,
        ui.span ({ class = 'sheet-panel-spacer' }),
        ui.button ({
          'Cancel',
          onclick = function ()
            check_draft = nil
            renders.validation ()
            return nil
          end,
        }),
        ui.button ({
          'Done',
          variant = 'primary',
          onclick = function ()
            if not valid () then
              return nil
            end
            local rule = rule_of_draft ()
            local index = draft.index
            ctl.change (
              index and 'Change validation' or 'Add validation',
              function (_, s)
                if index and s.validation[index] then
                  ops.set_validation (s, index, rule)
                else
                  ops.add_validation (s, rule)
                end
              end
            )
            check_draft = nil
            renders.validation ()
            return nil
          end,
        }),
      })
    )
  end

  renders.validation = function ()
    local body = bodies.validation
    body:clear ()
    local sheet = ctl.sheet ()
    if not sheet then
      check_draft = nil
      body:append (empty ('Open a workbook to add validation rules.'))
      return
    end
    if check_draft then
      checks_form (body, check_draft)
    else
      checks_list (body, sheet)
    end
  end

  -- Defined names ----------------------------------------------------------------------

  local name_draft = nil ---@type Sheet.NameDraft?

  ---A new name's formula: the selection on the sheet that shows, such as
  ---`=Sheet1!$B$2:$B$9`.
  ---@return string
  local function selection_formula ()
    local rect = ctl.selection ()
    local sheet = ctl.sheet ()
    ---@param row integer
    ---@param col integer
    ---@return string
    local function fixed (row, col)
      return '$' .. model.col_name (col) .. '$' .. row
    end
    local text_now = fixed (rect.r1, rect.c1)
    if rect.r1 ~= rect.r2 or rect.c1 ~= rect.c2 then
      text_now = text_now .. ':' .. fixed (rect.r2, rect.c2)
    end
    return '='
      .. formula.quote_sheet (sheet and sheet.name or 'Sheet1')
      .. '!'
      .. text_now
  end

  ---@param body Proteus.El
  ---@param book Sheet.Book
  local function names_list (body, book)
    local list = ui.div ({ class = 'sheet-panel-list' })
    for _, n in ipairs (book.defined_names) do
      local item = n
      local card = ui.div ({
        class = 'sheet-panel-card',
        title = 'Edit this name',
        ui.icon ('tag', 16),
        ui.div ({
          class = 'sheet-panel-card-main',
          ui.span ({ class = 'sheet-panel-desc', item.name }),
          ui.span ({ class = 'sheet-panel-range', item.formula }),
        }),
        ui.div ({
          class = 'sheet-panel-tools',
          icon_button ('trash-2', 'Delete the name', function ()
            ctl.change ('Delete name', function (b)
              b:delete_name (item.name)
            end)
          end),
        }),
      })
      card:on ('click', function ()
        name_draft =
          { old = item.name, name = item.name, formula = item.formula }
        renders.names ()
        return nil
      end)
      list:append (card)
    end
    if #book.defined_names == 0 then
      list:append (empty ('This workbook has no names yet.'))
    end
    body:append (
      list,
      ui.button ({
        'Define name',
        icon = 'plus',
        class = 'sheet-panel-wide',
        onclick = function ()
          name_draft = { name = '', formula = selection_formula () }
          renders.names ()
          return nil
        end,
      }),
      ui.div ({
        class = 'sheet-panel-hint',
        'A formula anywhere in the workbook can use a name in place of what it stands for, such as =SUM(Sales).',
      })
    )
  end

  ---@param body Proteus.El
  ---@param draft Sheet.NameDraft
  local function names_form (body, draft)
    local name_box = input (draft.name, function (value)
      draft.name = value
    end, { placeholder = 'Sales' })
    local formula_box = input (draft.formula, function (value)
      draft.formula = value
    end, { placeholder = '=Sheet1!$B$2:$B$9', mono = true })
    body:append (
      field ('Name', name_box),
      field (
        'Stands for',
        formula_box,
        ui.div ({
          class = 'sheet-panel-hint',
          'A reference such as =Sheet1!$B$2:$B$9, a value such as =0.2, or a function such as =LAMBDA(x, x*2).',
        })
      ),
      ui.div ({
        class = 'sheet-panel-actions',
        draft.old and ui.button ({
          'Delete',
          variant = 'danger',
          onclick = function ()
            local old = draft.old --[[@as string]]
            ctl.change ('Delete name', function (b)
              b:delete_name (old)
            end)
            name_draft = nil
            renders.names ()
            return nil
          end,
        }) or nil,
        ui.span ({ class = 'sheet-panel-spacer' }),
        ui.button ({
          'Cancel',
          onclick = function ()
            name_draft = nil
            renders.names ()
            return nil
          end,
        }),
        ui.button ({
          'Done',
          variant = 'primary',
          onclick = function ()
            draft.name = string.match (name_box:value (), '^%s*(.-)%s*$')
            draft.formula = string.match (formula_box:value (), '^%s*(.-)%s*$')
            local problem = ctl.change (
              draft.old and 'Change name' or 'Define name',
              function (b)
                local done, why =
                  b:set_name (draft.name, draft.formula, draft.old)
                if not done then
                  return why or 'The name could not be defined.'
                end
                return nil
              end
            )
            if type (problem) == 'string' then
              ctl.say ('warn', problem)
              return nil
            end
            name_draft = nil
            renders.names ()
            return nil
          end,
        }),
      })
    )
    name_box:focus ()
  end

  renders.names = function ()
    local body = bodies.names
    body:clear ()
    local book = ctl.book ()
    if not book then
      name_draft = nil
      body:append (empty ('Open a workbook to define names.'))
      return
    end
    if name_draft then
      names_form (body, name_draft)
    else
      names_list (body, book)
    end
  end

  -- Sort range -------------------------------------------------------------------------

  local sort_range = nil ---@type Sheet.Rect?
  local sort_header = false
  local sort_rows = {} ---@type Sheet.SortRow[]

  ---Starts the sort form from the selection, or the block around a single cell.
  local function sort_reset ()
    local sheet = ctl.sheet ()
    sort_range, sort_header, sort_rows = nil, false, {}
    if not sheet then
      return
    end
    local rect, row, col = ctl.selection ()
    sort_range = text.chart_block (sheet, rect, row, col) or rect
    sort_header = text.guess_header (sheet, sort_range)
    local key_col = math.max (sort_range.c1, math.min (col, sort_range.c2))
    sort_rows = { { col = key_col, desc = false } }
  end

  renders.sort = function ()
    local body = bodies.sort
    body:clear ()
    local sheet = ctl.sheet ()
    if sheet and not sort_range then
      sort_reset ()
    end
    if not sheet or not sort_range then
      body:append (empty ('Open a workbook to sort its rows.'))
      return
    end
    local keys = ui.div ({ class = 'sheet-panel-list' })
    local add = ui.h ('button', {
      class = 'sheet-panel-link',
      ui.icon ('plus', 14),
      'Add another sort column',
    })

    -- The key rows are drawn again on their own when the range's columns change, so a
    -- click elsewhere in the panel still lands.
    local function draw_keys ()
      local rect = sort_range --[[@as Sheet.Rect]]
      local column_options = {} ---@type { value: string, label: string }[]
      for c = rect.c1, rect.c2 do
        column_options[#column_options + 1] = {
          value = tostring (c),
          label = text.column_label (sheet, sort_header and rect.r1 or nil, c),
        }
      end
      keys:clear ()
      for i, key in ipairs (sort_rows) do
        keys:append (ui.div ({
          class = 'sheet-panel-key',
          select (column_options, tostring (key.col), function (value)
            local n = tonumber (value)
            if n then
              key.col = math.floor (n)
            end
          end),
          segmented (
            {
              { value = 'asc', label = 'A to Z' },
              { value = 'desc', label = 'Z to A' },
            },
            key.desc and 'desc' or 'asc',
            function (value)
              key.desc = value == 'desc'
            end
          ),
          icon_button ('x', 'Remove this sort column', function ()
            table.remove (sort_rows, i)
            renders.sort ()
          end, #sort_rows == 1),
        }))
      end
      add:set ('disabled', #sort_rows >= #column_options)
    end

    local range = input (model.range_name (sort_range), function (value, el)
      local r = read_range (el, value)
      if not r then
        return
      end
      local old = sort_range --[[@as Sheet.Rect]]
      sort_range = r
      el:value (model.range_name (r))
      if r.c1 ~= old.c1 or r.c2 ~= old.c2 then
        for _, key in ipairs (sort_rows) do
          key.col = math.max (r.c1, math.min (key.col, r.c2))
        end
        draw_keys ()
      end
    end, { mono = true })

    add:on ('click', function ()
      local rect = sort_range --[[@as Sheet.Rect]]
      local used = {} ---@type table<integer, boolean>
      for _, key in ipairs (sort_rows) do
        used[key.col] = true
      end
      for c = rect.c1, rect.c2 do
        if not used[c] then
          sort_rows[#sort_rows + 1] = { col = c, desc = false }
          break
        end
      end
      draw_keys ()
      return nil
    end)
    draw_keys ()

    body:append (
      field (
        'Range',
        ui.div ({
          class = 'sheet-panel-row',
          range,
          icon_button ('scan', 'Use the selected cells', function ()
            sort_reset ()
            renders.sort ()
          end),
        })
      ),
      check ('The range has a header row', sort_header, function (on)
        sort_header = on
        draw_keys ()
      end),
      field ('Sort by', keys),
      add,
      ui.div ({
        class = 'sheet-panel-actions',
        ui.span ({ class = 'sheet-panel-spacer' }),
        ui.button ({
          'Sort',
          icon = 'arrow-up-down',
          variant = 'primary',
          onclick = function ()
            local rect = sort_range --[[@as Sheet.Rect]]
            local keys_list = {} ---@type Sheet.SortKey[]
            for _, key in ipairs (sort_rows) do
              keys_list[#keys_list + 1] = { col = key.col, desc = key.desc }
            end
            local header = sort_header
            local problem = ctl.change ('Sort range', function (_, s)
              local good, why =
                ops.sort (s, rect, keys_list, { header = header })
              if not good then
                return why
              end
              return nil
            end)
            if type (problem) == 'string' then
              ctl.say ('warn', problem)
            else
              ctl.select (rect)
            end
            return nil
          end,
        }),
      })
    )
  end

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
      chart_id = arg
    elseif which == 'rules' then
      rule_draft = nil
    elseif which == 'validation' then
      check_draft = nil
    elseif which == 'sort' then
      sort_reset ()
    elseif which == 'names' then
      name_draft = nil
    end
    -- Showing the view runs its on_show, which draws it.
    views.show (VIEWS[which].id)
  end

  -- Following the grid ------------------------------------------------------------------

  ctl.on ('book', function ()
    chart_id, rule_draft, check_draft, name_draft = nil, nil, nil, nil
    sort_reset ()
    if current then
      render (current)
    end
  end)
  ctl.on ('sheet', function ()
    chart_id, rule_draft, check_draft = nil, nil, nil
    sort_reset ()
    if current and visible (current) then
      render (current)
    end
  end)
  ctl.on ('selection', function ()
    if visible ('rules') and not rule_draft and rules_scope == 'selection' then
      renders.rules ()
    elseif
      visible ('validation')
      and not check_draft
      and checks_scope == 'selection'
    then
      renders.validation ()
    end
  end)
  ctl.on ('changed', function ()
    if visible ('chart') then
      chart_check ()
    elseif visible ('rules') and not rule_draft then
      renders.rules ()
    elseif visible ('validation') and not check_draft then
      renders.validation ()
    elseif visible ('names') and not name_draft then
      renders.names ()
    end
  end)

  ---@type Sheet.SidePanels
  local api = {
    open = open,
    chart_selected = function (id)
      if id and id ~= chart_id then
        chart_id = id
        if visible ('chart') then
          renders.chart ()
        end
      end
    end,
  }
  return api
end

return M
