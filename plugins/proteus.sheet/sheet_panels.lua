-- sheet_panels: the Format, Data and Insert commands of the Sheet app, and the parts they open.
--
-- Every command changes the book through `ctl.change`, so each is one undo step that the grid
-- draws and saves. The side panels live in sheet_panel_side.lua, and the find bar, the filter
-- menu and the note editor in sheet_panel_find.lua. The toolbar in sheet_toolbar.lua runs the
-- same actions through the table the parts share.
--
-- A shortcut's `when` is false while the keyboard is in a text box outside the grid, such as
-- the find bar or a panel, so those boxes keep their own keys. Formatting shortcuts still act
-- on the whole cell while a cell is being edited, as in other spreadsheets.

local find = require ('sheet_panel_find') --[[@as Sheet.PanelFindModule]]
local format = require ('sheet_format') --[[@as Sheet.FormatModule]]
local formula = require ('sheet_formula') --[[@as Sheet.FormulaModule]]
local model = require ('sheet_model') --[[@as Sheet.ModelModule]]
local ops = require ('sheet_ops') --[[@as Sheet.OpsModule]]
local pop = require ('sheet_panel_pop') --[[@as Sheet.PanelPopModule]]
local side = require ('sheet_panel_side') --[[@as Sheet.PanelSideModule]]
local text = require ('sheet_panel_text') --[[@as Sheet.PanelTextModule]]

---A command of the panels: the command spec, whose `run` is also the shared action.
---@class Sheet.PanelCommand: Proteus.CommandSpec
---@field editing? boolean True when the command may run while a cell is being edited. Commands with a key default to false.

---The format code of a preset in the format menu.
---@param id string
---@return string
local function preset (id)
  for _, p in ipairs (format.presets) do
    if p.id == id then
      return p.code
    end
  end
  return 'General'
end

---@type Sheet.PanelsModule
local M = {
  install = function (app, ctl)
    local env = pop.env (app, ctl)
    local commands = env.commands
    local picker = env.picker
    local panels = side.install (env)
    local floats = find.install (env)

    ---@return boolean
    local function has_sheet ()
      return ctl.sheet () ~= nil
    end

    ---@return boolean
    local function keys_ok ()
      return pop.keys_ok (env)
    end

    ---@return boolean
    local function keys_ok_idle ()
      return pop.keys_ok (env) and not ctl.editing ()
    end

    ---Registers a command, and keeps its `run` as the action the toolbar calls.
    ---@param spec Sheet.PanelCommand
    ---@return Proteus.CommandSpec
    local function command (spec)
      spec.category = 'Sheet'
      if not spec.when then
        if spec.key then
          spec.when = spec.editing and keys_ok or keys_ok_idle
        else
          spec.when = has_sheet
        end
      end
      env.actions[spec.id] = spec.run
      return commands.register (spec)
    end

    ---The selected block, and the active cell.
    ---@return Sheet.Rect
    ---@return integer row
    ---@return integer col
    local function selection ()
      return ctl.selection ()
    end

    ---Runs model calls on the selection as one undo step.
    ---@param label string
    ---@param fn fun(sheet: Sheet.Sheet, rect: Sheet.Rect, row: integer, col: integer): any?
    ---@return any
    local function on_selection (label, fn)
      local rect, row, col = selection ()
      return ctl.change (label, function (_, sheet)
        return fn (sheet, rect, row, col)
      end)
    end

    ---@param label string
    ---@param patch Sheet.StylePatch
    local function style (label, patch)
      on_selection (label, function (sheet, rect)
        sheet:set_style (rect, patch)
      end)
    end

    ---@param label string
    ---@param field string
    local function toggle (label, field)
      on_selection (label, function (sheet, rect)
        sheet:toggle_style (rect, field)
      end)
    end

    ---@param label string
    ---@param code? string
    local function number_format (label, code)
      on_selection (label, function (sheet, rect)
        sheet:set_format (rect, (code ~= 'General') and code or nil)
      end)
    end

    ---The style of the active cell.
    ---@return Sheet.Style
    local function style_now ()
      local sheet = ctl.sheet ()
      if not sheet then
        return {}
      end
      local _, row, col = selection ()
      return sheet:style_at (row, col)
    end

    ---True when any cell of a block but its top left one holds text.
    ---@param sheet Sheet.Sheet
    ---@param rect Sheet.Rect
    ---@return boolean
    local function loses_text (sheet, rect)
      for _, cell in ipairs (sheet:cells_in (rect)) do
        if cell.text ~= '' and (cell.row ~= rect.r1 or cell.col ~= rect.c1) then
          return true
        end
      end
      return false
    end

    ---Merges the selection, after asking when the merge drops text.
    ---@param across boolean
    local function merge (across)
      local sheet = ctl.sheet ()
      if not sheet then
        return
      end
      local rect = selection ()
      if rect.c1 == rect.c2 and (across or rect.r1 == rect.r2) then
        ctl.say ('info', 'Select more than one cell to merge.')
        return
      end
      local function go ()
        local problem = ctl.change (
          across and 'Merge across' or 'Merge',
          function (_, s)
            local good, why = s:merge (rect, across)
            if good == false then
              return why
            end
            return nil
          end
        )
        if type (problem) == 'string' then
          ctl.say ('warn', problem)
        end
      end
      local drops = false
      if across then
        for r = rect.r1, rect.r2 do
          if
            loses_text (sheet, { r1 = r, c1 = rect.c1, r2 = r, c2 = rect.c2 })
          then
            drops = true
          end
        end
      else
        drops = loses_text (sheet, rect)
      end
      if drops and picker then
        picker.confirm ({
          message = across
              and 'Merging keeps only the leftmost value of each row.'
            or 'Merging keeps only the top left value.',
          yes = 'Merge',
          on_yes = go,
        })
      else
        go ()
      end
    end

    ---Sorts by the active column, from the block `sort_block` picks.
    ---@param desc boolean
    local function quick_sort (desc)
      local sheet = ctl.sheet ()
      if not sheet then
        return
      end
      local rect, row, col = selection ()
      local block, header = text.sort_block (sheet, rect, row, col)
      if not block then
        ctl.say ('info', 'There is nothing to sort.')
        return
      end
      local problem = ctl.change (
        desc and 'Sort Z to A' or 'Sort A to Z',
        function (_, s)
          local good, why = ops.sort (s, block, { { col = col, desc = desc } }, {
            header = header,
          })
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

    ---Types a function name at the cursor, or starts a formula with it.
    ---@param name string
    local function type_function (name)
      if ctl.editing () then
        ctl.type_text (name .. '(')
      else
        ctl.type_text ('=' .. name .. '(')
      end
    end

    ---A quick sum: types into the active cell, or fills a row of formulas under a block.
    ---@param fn string
    local function sum (fn)
      local sheet = ctl.sheet ()
      if not sheet then
        return
      end
      if ctl.editing () then
        ctl.type_text (fn .. '(')
        return
      end
      local rect, row, col = selection ()
      local plan = text.sum_plan (sheet, rect, row, col, fn)
      if plan.text then
        ctl.type_text (plan.text)
        return
      end
      local cells = plan.cells or {}
      if #cells == 0 then
        ctl.say ('info', 'There are no numbers in the selection to add up.')
        return
      end
      if plan.busy then
        ctl.say (
          'info',
          'The cells under the selection are not empty. Select the numbers and an empty row under them.'
        )
        return
      end
      ctl.change (fn, function (_, s)
        s:set_many (cells)
      end)
      if plan.rect then
        ctl.select (plan.rect, cells[1][1], cells[1][2])
      end
    end
    env.panels = { sum = sum }

    -- Format: numbers -------------------------------------------------------------------

    command ({
      id = 'sheet.number_format',
      title = 'Number format…',
      menu = 'Format',
      group = 'number',
      order = 10,
      icon = 'hash',
      run = function (code)
        if type (code) == 'string' then
          number_format ('Number format', code)
          return
        end
        if not picker then
          return
        end
        local current = style_now ().format
        local items = {} ---@type Proteus.PickItem[]
        for _, choice in ipairs (text.format_choices ()) do
          local on = current == choice.code
            or (current == nil and choice.id == 'general')
          items[#items + 1] = {
            label = choice.label,
            detail = choice.example,
            hint = on and 'current' or choice.code,
            icon = on and 'check' or 'hash',
            value = choice.code,
          }
        end
        picker.pick ({
          placeholder = 'Pick a number format',
          items = items,
          on_pick = function (item)
            number_format ('Number format', item.value --[[@as string]])
          end,
        })
      end,
    })
    command ({
      id = 'sheet.custom_format',
      title = 'Custom number format…',
      menu = 'Format',
      group = 'number',
      order = 11,
      run = function (code)
        if type (code) == 'string' then
          number_format ('Number format', code)
          return
        end
        if not picker then
          return
        end
        picker.input ({
          prompt = 'A format code, such as #,##0.00 or yyyy-mm-dd. Leave it empty for Automatic.',
          value = style_now ().format or '',
          placeholder = '#,##0.00',
          on_submit = function (code_text)
            local trimmed = string.match (code_text, '^%s*(.-)%s*$')
            number_format (
              'Number format',
              trimmed ~= '' and trimmed or 'General'
            )
          end,
        })
      end,
    })
    command ({
      id = 'sheet.format_number',
      title = 'Format as number',
      key = 'ctrl+shift+1',
      editing = true,
      run = function ()
        number_format ('Number format', preset ('number'))
      end,
    })
    command ({
      id = 'sheet.format_date',
      title = 'Format as date',
      key = 'ctrl+shift+3',
      editing = true,
      run = function ()
        number_format ('Date format', preset ('date'))
      end,
    })
    command ({
      id = 'sheet.format_currency',
      title = 'Format as currency',
      key = 'ctrl+shift+4',
      editing = true,
      icon = 'dollar-sign',
      run = function ()
        number_format ('Currency format', preset ('currency'))
      end,
    })
    command ({
      id = 'sheet.format_percent',
      title = 'Format as percent',
      key = 'ctrl+shift+5',
      editing = true,
      icon = 'percent',
      run = function ()
        number_format ('Percent format', preset ('percent'))
      end,
    })
    command ({
      id = 'sheet.decimals_more',
      title = 'More decimal places',
      icon = 'decimals-arrow-right',
      run = function ()
        on_selection ('More decimals', function (sheet, rect)
          sheet:adjust_decimals (rect, 1)
        end)
      end,
    })
    command ({
      id = 'sheet.decimals_less',
      title = 'Fewer decimal places',
      icon = 'decimals-arrow-left',
      run = function ()
        on_selection ('Fewer decimals', function (sheet, rect)
          sheet:adjust_decimals (rect, -1)
        end)
      end,
    })

    -- Format: text ---------------------------------------------------------------------

    command ({
      id = 'sheet.bold',
      title = 'Bold',
      menu = 'Format',
      group = 'text',
      order = 20,
      icon = 'bold',
      key = 'ctrl+b',
      editing = true,
      run = function ()
        toggle ('Bold', 'bold')
      end,
    })
    command ({
      id = 'sheet.italic',
      title = 'Italic',
      menu = 'Format',
      group = 'text',
      order = 21,
      icon = 'italic',
      key = 'ctrl+i',
      editing = true,
      run = function ()
        toggle ('Italic', 'italic')
      end,
    })
    command ({
      id = 'sheet.underline',
      title = 'Underline',
      menu = 'Format',
      group = 'text',
      order = 22,
      icon = 'underline',
      key = 'ctrl+u',
      editing = true,
      run = function ()
        toggle ('Underline', 'underline')
      end,
    })
    command ({
      id = 'sheet.strike',
      title = 'Strikethrough',
      menu = 'Format',
      group = 'text',
      order = 23,
      icon = 'strikethrough',
      key = 'ctrl+5',
      editing = true,
      run = function ()
        toggle ('Strikethrough', 'strike')
      end,
    })
    command ({
      id = 'sheet.font_size',
      title = 'Font size…',
      menu = 'Format',
      group = 'text',
      order = 24,
      icon = 'type',
      run = function (size)
        if type (size) == 'number' then
          style ('Font size', { size = size })
          return
        end
        if not picker then
          return
        end
        picker.input ({
          prompt = 'Font size in pixels, from '
            .. text.MIN_SIZE
            .. ' to '
            .. text.MAX_SIZE
            .. '.',
          value = tostring (style_now ().size or text.DEFAULT_SIZE),
          validate = function (value)
            if not text.parse_size (value) then
              return 'Type a number from '
                .. text.MIN_SIZE
                .. ' to '
                .. text.MAX_SIZE
                .. '.'
            end
            return nil
          end,
          on_submit = function (value)
            local n = text.parse_size (value)
            if n then
              style ('Font size', { size = n })
            end
          end,
        })
      end,
    })

    ---Sets a colour field from a colour, removes it for false, or opens the palette for nil.
    ---@param field 'color'|'fill'
    ---@param label string
    ---@param color? string|false
    local function paint (field, label, color)
      if color == nil then
        pop.palette (
          env,
          pop.cell_anchor (env),
          style_now ()[field],
          function (c)
            paint (field, label, c)
          end
        )
        return
      end
      if field == 'color' then
        style (label, { color = color })
      else
        style (label, { fill = color })
      end
    end

    command ({
      id = 'sheet.text_color',
      title = 'Text colour…',
      menu = 'Format',
      group = 'text',
      order = 25,
      icon = 'baseline',
      run = function (color)
        paint ('color', 'Text colour', color)
      end,
    })
    command ({
      id = 'sheet.fill_color',
      title = 'Fill colour…',
      menu = 'Format',
      group = 'text',
      order = 26,
      icon = 'paint-bucket',
      run = function (color)
        paint ('fill', 'Fill colour', color)
      end,
    })

    -- Format: alignment ----------------------------------------------------------------

    ---@param id string
    ---@param title string
    ---@param order number
    ---@param icon string
    ---@param key? string
    ---@param patch Sheet.StylePatch
    local function align_command (id, title, order, icon, key, patch)
      command ({
        id = id,
        title = title,
        menu = 'Format',
        group = 'align',
        order = order,
        icon = icon,
        key = key,
        editing = key ~= nil,
        run = function ()
          style ('Align', patch)
        end,
      })
    end
    align_command (
      'sheet.align_left',
      'Align left',
      30,
      'align-left',
      'ctrl+shift+l',
      { align = 'left' }
    )
    align_command (
      'sheet.align_center',
      'Align centre',
      31,
      'align-center',
      'ctrl+shift+e',
      { align = 'center' }
    )
    align_command (
      'sheet.align_right',
      'Align right',
      32,
      'align-right',
      'ctrl+shift+r',
      { align = 'right' }
    )
    align_command (
      'sheet.valign_top',
      'Align top',
      33,
      'arrow-up-to-line',
      nil,
      { valign = 'top' }
    )
    align_command (
      'sheet.valign_middle',
      'Align middle',
      34,
      'fold-vertical',
      nil,
      { valign = 'middle' }
    )
    align_command (
      'sheet.valign_bottom',
      'Align bottom',
      35,
      'arrow-down-to-line',
      nil,
      { valign = 'bottom' }
    )
    command ({
      id = 'sheet.wrap',
      title = 'Wrap text',
      menu = 'Format',
      group = 'align',
      order = 36,
      icon = 'wrap-text',
      run = function ()
        toggle ('Wrap text', 'wrap')
      end,
    })

    -- Format: cells --------------------------------------------------------------------

    command ({
      id = 'sheet.merge',
      title = 'Merge cells',
      menu = 'Format',
      group = 'cells',
      order = 40,
      icon = 'table-cells-merge',
      run = function ()
        merge (false)
      end,
    })
    command ({
      id = 'sheet.merge_across',
      title = 'Merge across',
      menu = 'Format',
      group = 'cells',
      order = 41,
      run = function ()
        merge (true)
      end,
    })
    command ({
      id = 'sheet.unmerge',
      title = 'Unmerge',
      menu = 'Format',
      group = 'cells',
      order = 42,
      icon = 'table-cells-split',
      run = function ()
        local changed = on_selection ('Unmerge', function (sheet, rect)
          return sheet:unmerge (rect)
        end)
        if changed == false then
          ctl.say ('info', 'The selection has no merged cells.')
        end
      end,
    })
    command ({
      id = 'sheet.borders',
      title = 'Borders…',
      menu = 'Format',
      group = 'cells',
      order = 43,
      icon = 'grid2x2',
      run = function (preset_id, line, color)
        if type (preset_id) ~= 'string' then
          pop.borders (env, pop.cell_anchor (env), function (p, l, c)
            env.actions['sheet.borders'] (p, l, c)
          end)
          return
        end
        on_selection ('Borders', function (sheet, rect)
          sheet:set_borders (
            rect,
            preset_id --[[@as Sheet.BorderPreset]],
            line,
            color
          )
        end)
      end,
    })
    command ({
      id = 'sheet.rules',
      title = 'Conditional formatting…',
      menu = 'Format',
      group = 'rules',
      order = 50,
      icon = 'paintbrush',
      run = function ()
        panels.open ('rules')
      end,
    })
    command ({
      id = 'sheet.clear_format',
      title = 'Clear formatting',
      menu = 'Format',
      group = 'rules',
      order = 51,
      icon = 'remove-formatting',
      key = 'ctrl+\\',
      editing = true,
      run = function ()
        on_selection ('Clear formatting', function (sheet, rect)
          sheet:clear_format (rect)
        end)
      end,
    })

    -- Data -----------------------------------------------------------------------------

    command ({
      id = 'sheet.sort_az',
      title = 'Sort sheet A to Z',
      menu = 'Data',
      group = 'sort',
      order = 10,
      icon = 'arrow-down-az',
      run = function ()
        quick_sort (false)
      end,
    })
    command ({
      id = 'sheet.sort_za',
      title = 'Sort sheet Z to A',
      menu = 'Data',
      group = 'sort',
      order = 11,
      icon = 'arrow-down-za',
      run = function ()
        quick_sort (true)
      end,
    })
    command ({
      id = 'sheet.sort_range',
      title = 'Sort range…',
      menu = 'Data',
      group = 'sort',
      order = 12,
      icon = 'arrow-up-down',
      run = function ()
        panels.open ('sort')
      end,
    })
    local filter_cmd = command ({
      id = 'sheet.filter',
      title = 'Create or remove filter',
      menu_title = 'Create filter',
      menu = 'Data',
      group = 'filter',
      order = 20,
      icon = 'filter',
      key = 'ctrl+shift+f',
      run = function ()
        local sheet = ctl.sheet ()
        if not sheet then
          return
        end
        if sheet.filter then
          ctl.change ('Remove filter', function (_, s)
            ops.remove_filter (s)
          end)
          return
        end
        local rect, row, col = selection ()
        local block = text.chart_block (sheet, rect, row, col)
        if not block or block.r1 == block.r2 then
          ctl.say (
            'info',
            'Select the data to filter, with its header row, or a cell inside it.'
          )
          return
        end
        ctl.change ('Filter', function (_, s)
          ops.set_filter (s, block)
        end)
      end,
    })
    command ({
      id = 'sheet.filter_reapply',
      title = 'Reapply filter',
      menu = 'Data',
      group = 'filter',
      order = 21,
      icon = 'refresh-cw',
      when = function ()
        local sheet = ctl.sheet ()
        return sheet ~= nil and sheet.filter ~= nil
      end,
      run = function ()
        local changed = ctl.change ('Reapply filter', function (_, s)
          return ops.reapply_filter (s)
        end)
        if changed == false then
          ctl.say ('info', 'The filter already shows the right rows.')
        end
      end,
    })
    command ({
      id = 'sheet.remove_duplicates',
      title = 'Remove duplicates',
      menu = 'Data',
      group = 'clean',
      order = 25,
      icon = 'copy-minus',
      when = function ()
        return ctl.sheet () ~= nil
      end,
      run = function ()
        local sheet = ctl.sheet ()
        if not sheet then
          return
        end
        local rect, row, col = selection ()
        local block = text.chart_block (sheet, rect, row, col)
        if not block then
          ctl.say ('info', 'Select the rows to check first.')
          return
        end
        local header = text.guess_header (sheet, block)
        local removed, problem = false, nil ---@type integer|false, string?
        ctl.change ('Remove duplicates', function (_, s)
          removed, problem =
            ops.remove_duplicates (s, block, { header = header })
        end)
        if removed == false then
          ctl.say ('warn', problem or 'The rows could not be checked.')
        elseif removed == 0 then
          ctl.say ('info', 'No duplicate rows were found.')
        else
          ctl.say (
            'success',
            'Removed '
              .. removed
              .. (removed == 1 and ' duplicate row.' or ' duplicate rows.')
          )
        end
      end,
    })
    command ({
      id = 'sheet.validation',
      title = 'Data validation…',
      menu = 'Data',
      group = 'check',
      order = 30,
      icon = 'shield-check',
      run = function ()
        panels.open ('validation')
      end,
    })
    command ({
      id = 'sheet.names',
      title = 'Defined names…',
      menu = 'Data',
      group = 'check',
      order = 31,
      icon = 'tag',
      run = function ()
        panels.open ('names')
      end,
    })
    command ({
      id = 'sheet.find',
      title = 'Find…',
      icon = 'search',
      key = 'ctrl+f',
      editing = true,
      run = function ()
        floats.find (false)
      end,
    })
    command ({
      id = 'sheet.replace',
      title = 'Find and replace…',
      menu = 'Data',
      group = 'find',
      order = 40,
      icon = 'replace',
      key = 'ctrl+h',
      editing = true,
      run = function ()
        floats.find (true)
      end,
    })

    -- Insert ---------------------------------------------------------------------------

    command ({
      id = 'sheet.chart',
      title = 'Chart',
      menu = 'Insert',
      group = 'objects',
      order = 10,
      icon = 'chart-column',
      run = function ()
        local sheet = ctl.sheet ()
        if not sheet then
          return
        end
        -- With a chart selected, the command opens it, so a double-click on a chart can
        -- run it too.
        local selected = ctl.chart ()
        if selected and ops.chart_by_id (sheet, selected) then
          panels.open ('chart', selected)
          return
        end
        local rect, row, col = selection ()
        local block = text.chart_block (sheet, rect, row, col)
        if not block then
          ctl.say ('info', 'Select the data for the chart first.')
          return
        end
        local layout = sheet:layout ()
        local x = (layout.lefts[block.c2 + 1] or 0) + 24
        local y = layout.tops[block.r1] or 0
        local spec = ctl.change ('Insert chart', function (_, s)
          return ops.add_chart (s, {
            id = '',
            type = 'column',
            range = model.range_name (block),
            x = x,
            y = y,
            w = 480,
            h = 300,
          })
        end)
        if type (spec) == 'table' then
          local id = (spec --[[@as Sheet.ChartSpec]]).id
          ctl.select_chart (id)
          panels.open ('chart', id)
        end
      end,
    })
    command ({
      id = 'sheet.edit_chart',
      title = 'Edit chart',
      icon = 'chart-column',
      when = function ()
        local sheet = ctl.sheet ()
        local id = ctl.chart ()
        return sheet ~= nil and id ~= nil and ops.chart_by_id (sheet, id) ~= nil
      end,
      run = function (id)
        panels.open ('chart', type (id) == 'string' and id or ctl.chart ())
      end,
    })
    command ({
      id = 'sheet.note',
      title = 'Note',
      menu = 'Insert',
      group = 'objects',
      order = 11,
      icon = 'sticky-note',
      key = 'shift+f2',
      run = function ()
        floats.note ()
      end,
    })
    command ({
      id = 'sheet.function',
      title = 'Function…',
      menu = 'Insert',
      group = 'function',
      order = 20,
      icon = 'square-function',
      when = has_sheet,
      run = function (name)
        if type (name) == 'string' then
          type_function (name)
          return
        end
        if not picker then
          return
        end
        local items = {} ---@type Proteus.PickItem[]
        for _, entry in ipairs (formula.catalog) do
          items[#items + 1] = {
            label = entry.name,
            detail = entry.summary,
            hint = entry.category,
            icon = 'square-function',
            value = entry.name,
          }
        end
        picker.pick ({
          placeholder = 'Find a function by name or by what it does',
          items = items,
          on_pick = function (item)
            type_function (item.value --[[@as string]])
          end,
        })
      end,
    })
    command ({
      id = 'sheet.autosum',
      title = 'Quick sum',
      icon = 'sigma',
      key = 'alt+=',
      editing = true,
      run = function (fn)
        sum (type (fn) == 'string' and fn or 'SUM')
      end,
    })

    -- Keeping the parts in step --------------------------------------------------------

    local function sync_titles ()
      local sheet = ctl.sheet ()
      filter_cmd.menu_title = (sheet and sheet.filter) and 'Remove filter'
        or 'Create filter'
    end
    for _, event in ipairs ({ 'book', 'sheet', 'changed' }) do
      ctl.on (event --[[@as Sheet.CtlEvent]], sync_titles)
    end
    sync_titles ()

    ctl.on ('filter_menu', function (col, rect)
      floats.filter_menu (col, rect)
    end)
    ctl.on ('chart', function (id)
      panels.chart_selected (id)
    end)
  end,
}

return M
