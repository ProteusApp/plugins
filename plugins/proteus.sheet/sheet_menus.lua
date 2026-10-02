-- sheet_menus: the right-click menus of the Sheet app: on cells, on row and column headers, on
-- charts, and on the workbooks in the Workbooks view. Most items run the grid's actions or
-- another part's command, greyed out while it cannot run.

local model = require ('sheet_model') --[[@as Sheet.ModelModule]]
local ops = require ('sheet_ops') --[[@as Sheet.OpsModule]]

---@class Sheet.MenusModule
local M = {}

---@param env Sheet.AppEnv
function M.install (env)
  local commands, menus, grid, emit =
    env.commands, env.menus, env.grid, env.emit
  local files = env.files
  local list, new_workbook, open_file =
    files.list, files.new_workbook, files.open_file
  local rename_file, duplicate_file, delete_file =
    files.rename_file, files.duplicate_file, files.delete_file

  ---A menu item that runs another part's command, greyed out while it cannot run.
  ---@param label string
  ---@param icon string
  ---@param id string
  ---@return Proteus.MenuItem
  local function run_item (label, icon, id)
    return {
      label = label,
      icon = icon,
      disabled = not commands.can_run (id),
      run = function ()
        commands.run (id)
      end,
    }
  end

  ---Filters the sheet to the rows that show the active cell's value in its column.
  local function filter_by_value ()
    local s = grid.sheet ()
    if not s then
      return
    end
    local r, c = grid.sel.r, grid.sel.c
    local value = (s:display (r, c))
    grid.change ('Filter', function (_, sh)
      local f = sh.filter
      if
        not f
        or r <= f.rect.r1
        or r > f.rect.r2
        or c < f.rect.c1
        or c > f.rect.c2
      then
        f = ops.filter_around (sh, r, c)
      end
      if f and r > f.rect.r1 then
        ops.filter_column (sh, c, { values = { value } })
      end
    end)
  end

  ---@return Proteus.MenuItem[]
  local function cell_items ()
    local s = grid.sheet ()
    local has_note = s and s:note (grid.sel.r, grid.sel.c) ~= nil
    local has_link = s and s:link (grid.sel.r, grid.sel.c) ~= nil
    ---@type Proteus.MenuItem[]
    local items = {
      {
        label = 'Cut',
        icon = 'scissors',
        key = 'Ctrl+X',
        run = function ()
          grid.copy (true)
        end,
      },
      {
        label = 'Copy',
        icon = 'copy',
        key = 'Ctrl+C',
        run = function ()
          grid.copy (false)
        end,
      },
      {
        label = 'Paste',
        icon = 'clipboard-paste',
        key = 'Ctrl+V',
        run = function ()
          grid.paste ()
        end,
      },
      {
        label = 'Paste values only',
        icon = 'clipboard-type',
        key = 'Ctrl+Shift+V',
        run = function ()
          grid.paste ({ only = 'values' })
        end,
      },
      {
        label = 'Paste formats only',
        icon = 'clipboard-paste',
        run = function ()
          grid.paste ({ only = 'formats' })
        end,
      },
      {
        label = 'Paste transposed',
        icon = 'clipboard-paste',
        run = function ()
          grid.paste ({ transpose = true })
        end,
      },
      { separator = true },
      {
        label = grid.count_label ('Insert %s above', 'row'),
        icon = 'between-horizontal-start',
        run = function ()
          grid.insert ('row', false)
        end,
      },
      {
        label = grid.count_label ('Insert %s below', 'row'),
        icon = 'between-horizontal-start',
        run = function ()
          grid.insert ('row', true)
        end,
      },
      {
        label = grid.count_label ('Insert %s left', 'col'),
        icon = 'between-vertical-start',
        run = function ()
          grid.insert ('col', false)
        end,
      },
      {
        label = grid.count_label ('Insert %s right', 'col'),
        icon = 'between-vertical-start',
        run = function ()
          grid.insert ('col', true)
        end,
      },
      {
        label = grid.count_label ('Delete %s', 'row'),
        icon = 'square-minus',
        run = function ()
          grid.delete ('row')
        end,
      },
      {
        label = grid.count_label ('Delete %s', 'col'),
        icon = 'square-minus',
        run = function ()
          grid.delete ('col')
        end,
      },
      { separator = true },
      { label = 'Clear', icon = 'eraser', key = 'Del', run = grid.clear },
      run_item (
        'Sort A to Z by this column',
        'arrow-up-narrow-wide',
        'sheet.sort_az'
      ),
      run_item (
        'Sort Z to A by this column',
        'arrow-down-wide-narrow',
        'sheet.sort_za'
      ),
      {
        label = 'Filter by this value',
        icon = 'funnel',
        run = filter_by_value,
      },
      { separator = true },
      run_item (
        has_note and 'Edit note' or 'Insert note',
        'sticky-note',
        'sheet.note'
      ),
      run_item (has_link and 'Edit link' or 'Insert link', 'link', 'sheet.link'),
      run_item ('Insert chart', 'chart-column', 'sheet.chart'),
      run_item ('Conditional formatting', 'palette', 'sheet.rules'),
      run_item ('Data validation', 'list-checks', 'sheet.validation'),
    }
    if has_link then
      for i, item in ipairs (items) do
        if item.label == 'Edit link' then
          table.insert (
            items,
            i + 1,
            run_item ('Follow link', 'external-link', 'sheet.follow_link')
          )
          break
        end
      end
    end
    return items
  end

  ---@param axis 'row'|'col'
  ---@return Proteus.MenuItem[]
  local function header_items (axis)
    local s = grid.sheet ()
    local rect = grid.sel_rect ()
    local row = axis == 'row'
    ---@type Proteus.MenuItem[]
    local items = {
      {
        label = grid.count_label (
          row and 'Insert %s above' or 'Insert %s left',
          axis
        ),
        icon = row and 'between-horizontal-start' or 'between-vertical-start',
        run = function ()
          grid.insert (axis, false)
        end,
      },
      {
        label = grid.count_label (
          row and 'Insert %s below' or 'Insert %s right',
          axis
        ),
        icon = row and 'between-horizontal-start' or 'between-vertical-start',
        run = function ()
          grid.insert (axis, true)
        end,
      },
      {
        label = grid.count_label ('Delete %s', axis),
        icon = 'square-minus',
        run = function ()
          grid.delete (axis)
        end,
      },
      { separator = true },
      {
        label = grid.count_label ('Hide %s', axis),
        icon = 'eye-off',
        run = function ()
          grid.hide (axis, true)
        end,
      },
      {
        label = row and 'Unhide rows' or 'Unhide columns',
        icon = 'eye',
        run = function ()
          grid.hide (axis, false)
        end,
      },
      {
        label = grid.count_label ('Resize %s…', axis),
        icon = row and 'move-vertical' or 'move-horizontal',
        run = function ()
          grid.ask_size (axis)
        end,
      },
    }
    if not row then
      items[#items + 1] = {
        label = 'Auto-fit width',
        icon = 'move-horizontal',
        run = function ()
          grid.autofit ()
        end,
      }
    end
    items[#items + 1] = { separator = true }
    local fr, fc = 0, 0
    if s then
      fr, fc = s:freeze ()
    end
    if row then
      items[#items + 1] = {
        label = 'Freeze up to row ' .. rect.r2,
        icon = 'snowflake',
        run = function ()
          grid.freeze (rect.r2, nil)
        end,
      }
    else
      items[#items + 1] = {
        label = 'Freeze up to column ' .. model.col_name (rect.c2),
        icon = 'snowflake',
        run = function ()
          grid.freeze (nil, rect.c2)
        end,
      }
    end
    if (row and fr > 0) or (not row and fc > 0) then
      items[#items + 1] = {
        label = row and 'Unfreeze rows' or 'Unfreeze columns',
        icon = 'snowflake',
        run = function ()
          if row then
            grid.freeze (0, nil)
          else
            grid.freeze (nil, 0)
          end
        end,
      }
    end
    if not row then
      items[#items + 1] = { separator = true }
      items[#items + 1] =
        run_item ('Sort sheet A to Z', 'arrow-up-narrow-wide', 'sheet.sort_az')
      items[#items + 1] = run_item (
        'Sort sheet Z to A',
        'arrow-down-wide-narrow',
        'sheet.sort_za'
      )
    end
    return items
  end

  if menus then
    menus.attach (grid.scroll, function (ev)
      if grid.edit or not files.book () then
        return nil
      end
      local chart_id = string.match (ev.item or '', '^chart:([^:]+)')
      if chart_id then
        grid.select_chart (chart_id)
        return {
          {
            label = 'Edit chart',
            icon = 'chart-column',
            run = function ()
              for _, id in ipairs ({ 'sheet.edit_chart' }) do
                if commands.get (id) then
                  commands.run (id, chart_id)
                  return
                end
              end
              emit ('chart', chart_id)
            end,
          },
          {
            label = 'Delete chart',
            icon = 'trash',
            key = 'Del',
            danger = true,
            run = grid.delete_chart,
          },
        }
      end
      local hit = grid.hit_at (ev.x or 0, ev.y or 0)
      if not hit or hit.zone == 'corner' then
        return nil
      end
      if hit.zone == 'row' then
        return header_items ('row')
      elseif hit.zone == 'col' then
        return header_items ('col')
      end
      return cell_items ()
    end)

    menus.attach (list, function (ev)
      local n = ev.item
      if not n then
        return {
          { label = 'New workbook', icon = 'file-plus', run = new_workbook },
        }
      end
      return {
        {
          label = 'Open',
          icon = 'folder-open',
          run = function ()
            open_file (n)
          end,
        },
        {
          label = 'Rename…',
          icon = 'pencil',
          run = function ()
            rename_file (n)
          end,
        },
        {
          label = 'Duplicate',
          icon = 'copy-plus',
          run = function ()
            duplicate_file (n)
          end,
        },
        { separator = true },
        {
          label = 'Delete…',
          icon = 'trash',
          danger = true,
          run = function ()
            delete_file (n)
          end,
        },
      }
    end)
  end
end

return M
