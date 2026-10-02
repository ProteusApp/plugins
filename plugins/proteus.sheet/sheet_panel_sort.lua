-- sheet_panel_sort: the Sort panel of the Sheet app. It sorts a block of cells by one or more
-- columns, with or without a header row. sheet_panel_side installs it.

local model = require ('sheet_model') --[[@as Sheet.ModelModule]]
local ops = require ('sheet_ops') --[[@as Sheet.OpsModule]]
local text = require ('sheet_panel_text') --[[@as Sheet.PanelTextModule]]

---One key of the sort form.
---@class Sheet.SortRow
---@field col integer
---@field desc boolean

---@class Sheet.SortPanelModule
local M = {}

---@param K Sheet.SidePanelKit
---@return Sheet.SortPanel
function M.install (K)
  local ctl, ui, bodies, renders = K.ctl, K.ui, K.bodies, K.renders
  local field, empty, select, segmented =
    K.field, K.empty, K.select, K.segmented
  local check, input, icon_button, read_range =
    K.check, K.input, K.icon_button, K.read_range

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

  ---@class Sheet.SortPanel
  local panel = {
    reset = sort_reset,
  }
  return panel
end

return M
