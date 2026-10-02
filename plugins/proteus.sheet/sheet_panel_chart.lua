-- sheet_panel_chart: the Chart panel of the Sheet app, in the right dock. It edits the chart
-- the grid selected: its type, its block of cells, its titles, legend and colours. Each change
-- applies as it is made, as one undo step. sheet_panel_side installs it.

local chart = require ('sheet_chart') --[[@as Sheet.ChartModule]]
local model = require ('sheet_model') --[[@as Sheet.ModelModule]]
local ops = require ('sheet_ops') --[[@as Sheet.OpsModule]]
local pop = require ('sheet_panel_pop') --[[@as Sheet.PanelPopModule]]

---@class Sheet.ChartPanelModule
local M = {}

---@type { value: string, label: string }[]
local LEGENDS = {
  { value = 'bottom', label = 'Bottom' },
  { value = 'top', label = 'Top' },
  { value = 'right', label = 'Right' },
  { value = 'none', label = 'None' },
}

---@type table<string, boolean>
local STACKABLE = { column = true, bar = true, area = true }

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

---@param K Sheet.SidePanelKit
---@return Sheet.ChartPanel
function M.install (K)
  local env, ctl, ui, bodies = K.env, K.ctl, K.ui, K.bodies
  local renders, field, empty, select = K.renders, K.field, K.empty, K.select
  local segmented, check, input, read_range =
    K.segmented, K.check, K.input, K.read_range

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

  ---@class Sheet.ChartPanel
  local panel = {
    ---@return string?
    id = function ()
      return chart_id
    end,
    ---@param id string?
    set_id = function (id)
      chart_id = id
    end,
    check = chart_check,
  }
  return panel
end

return M
