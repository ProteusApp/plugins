-- sheet_commands: the File, Edit, View and Insert commands of the Sheet app, with their keys
-- and menu places. They act on the grid and on the workbook files through what init.lua
-- hands them. The Format, Data and more Insert commands live in sheet_panels.lua.

---@class Sheet.CommandsModule
local M = {}

---@param env Sheet.AppEnv
function M.install (env)
  local views, commands, tabs = env.views, env.commands, env.tabs
  local grid, files, on = env.grid, env.files, env.on
  local save_now, save_disk = files.save_now, files.save_disk
  local new_workbook, open_picker, open_recent, pick_disk =
    files.new_workbook, files.open_picker, files.open_recent, files.pick_disk
  local rename_file, duplicate_file, delete_file =
    files.rename_file, files.duplicate_file, files.delete_file
  local import_csv, import_xlsx, export_csv, export_xlsx =
    files.import_csv, files.import_xlsx, files.export_csv, files.export_xlsx

  ---True when a workbook is open and in view.
  ---@return boolean
  local function active ()
    local book = files.book ()
    if not book then
      return false
    end
    if tabs then
      local current = tabs.active ()
      return current ~= nil and current.id == 'proteus.sheet'
    end
    return true
  end

  ---True when the grid has the keys, or nothing that takes text does.
  ---@return boolean
  local function idle ()
    return active () and not grid.typing ()
  end

  ---True while keys may act on the cell: the grid has them, or a cell is being edited.
  ---@return boolean
  local function cell_keys ()
    return active () and (grid.edit ~= nil or not grid.typing ())
  end

  ---True unless another part's text box has the keys, such as the find bar.
  ---@return boolean
  local function keys_free ()
    return grid.edit ~= nil or not grid.typing ()
  end

  ---@param spec Proteus.CommandSpec
  ---@return Proteus.CommandSpec
  local function command (spec)
    spec.category = 'Sheet'
    return commands.register (spec)
  end

  -- File
  command ({
    id = 'sheet.new',
    title = 'New workbook',
    key = 'ctrl+n',
    icon = 'file-plus',
    menu = 'File',
    group = 'a',
    order = 10,
    when = keys_free,
    run = function ()
      new_workbook ()
    end,
  })
  command ({
    id = 'sheet.open',
    title = 'Open workbook…',
    menu_title = 'Open…',
    key = 'ctrl+o',
    icon = 'folder-open',
    menu = 'File',
    group = 'a',
    order = 11,
    when = keys_free,
    run = open_picker,
  })
  command ({
    id = 'sheet.open_disk',
    title = 'Open Excel or CSV file…',
    icon = 'folder-open',
    menu = 'File',
    group = 'a',
    order = 13,
    when = keys_free,
    run = pick_disk,
  })
  command ({
    id = 'sheet.save',
    title = 'Save',
    key = 'ctrl+s',
    icon = 'save',
    menu = 'File',
    group = 'a',
    order = 14,
    when = function ()
      return active () and keys_free ()
    end,
    run = function ()
      local disk = files.disk ()
      if grid.edit then
        grid.finish_edit (0, 0, false)
      end
      if disk then
        save_disk ()
      else
        save_now ()
      end
    end,
  })
  command ({
    id = 'sheet.open_recent',
    title = 'Open recent…',
    icon = 'clock',
    menu = 'File',
    group = 'a',
    order = 12,
    run = open_recent,
  })
  command ({
    id = 'sheet.import_csv',
    title = 'Import CSV as a new workbook…',
    icon = 'file-input',
    menu = 'File',
    group = 'b',
    order = 20,
    run = function ()
      import_csv (false)
    end,
  })
  command ({
    id = 'sheet.import_csv_sheet',
    title = 'Import CSV as a new sheet…',
    icon = 'file-input',
    menu = 'File',
    group = 'b',
    order = 21,
    when = function ()
      local book = files.book ()
      return book ~= nil
    end,
    run = function ()
      import_csv (true)
    end,
  })
  command ({
    id = 'sheet.import_xlsx',
    title = 'Import Excel workbook…',
    icon = 'file-input',
    menu = 'File',
    group = 'b',
    order = 22,
    run = import_xlsx,
  })
  command ({
    id = 'sheet.export_csv',
    title = 'Export sheet as CSV…',
    icon = 'file-output',
    menu = 'File',
    group = 'c',
    order = 30,
    when = function ()
      local book = files.book ()
      return book ~= nil
    end,
    run = export_csv,
  })
  command ({
    id = 'sheet.export_xlsx',
    title = 'Export workbook as Excel…',
    icon = 'file-output',
    menu = 'File',
    group = 'c',
    order = 31,
    when = function ()
      local book = files.book ()
      return book ~= nil
    end,
    run = export_xlsx,
  })
  command ({
    id = 'sheet.rename',
    title = 'Rename workbook…',
    icon = 'pencil',
    menu = 'File',
    group = 'd',
    order = 40,
    when = function ()
      local file = files.file ()
      return file ~= nil
    end,
    run = function ()
      local file = files.file ()
      if file then
        rename_file (file)
      end
    end,
  })
  command ({
    id = 'sheet.duplicate',
    title = 'Duplicate workbook',
    icon = 'copy-plus',
    menu = 'File',
    group = 'd',
    order = 41,
    when = function ()
      local file = files.file ()
      return file ~= nil
    end,
    run = function ()
      local file = files.file ()
      if file then
        duplicate_file (file)
      end
    end,
  })
  command ({
    id = 'sheet.delete',
    title = 'Delete workbook…',
    icon = 'trash',
    menu = 'File',
    group = 'd',
    order = 42,
    when = function ()
      local file = files.file ()
      return file ~= nil
    end,
    run = function ()
      local file = files.file ()
      if file then
        delete_file (file)
      end
    end,
  })

  -- Edit
  local undo_cmd = command ({
    id = 'sheet.undo',
    title = 'Undo',
    key = 'ctrl+z',
    icon = 'undo-2',
    menu = 'Edit',
    group = 'a',
    order = 10,
    when = function ()
      local book = files.book ()
      return idle () and book ~= nil and book:can_undo ()
    end,
    run = function ()
      grid.undo (true)
    end,
  })
  local redo_cmd = command ({
    id = 'sheet.redo',
    title = 'Redo',
    key = { 'ctrl+y', 'ctrl+shift+z' },
    icon = 'redo-2',
    menu = 'Edit',
    group = 'a',
    order = 11,
    when = function ()
      local book = files.book ()
      return idle () and book ~= nil and book:can_redo ()
    end,
    run = function ()
      grid.undo (false)
    end,
  })
  command ({
    id = 'sheet.cut',
    title = 'Cut',
    key = 'ctrl+x',
    icon = 'scissors',
    menu = 'Edit',
    group = 'b',
    order = 20,
    when = idle,
    run = function ()
      grid.copy (true)
    end,
  })
  command ({
    id = 'sheet.copy',
    title = 'Copy',
    key = 'ctrl+c',
    icon = 'copy',
    menu = 'Edit',
    group = 'b',
    order = 21,
    when = idle,
    run = function ()
      grid.copy (false)
    end,
  })
  -- Ctrl+V and Ctrl+Shift+V paste through the waiting cell editor, which needs no clipboard
  -- permission, so the paste commands carry no key.
  command ({
    id = 'sheet.paste',
    title = 'Paste',
    icon = 'clipboard-paste',
    menu = 'Edit',
    group = 'b',
    order = 22,
    when = idle,
    run = function ()
      grid.paste ()
    end,
  })
  command ({
    id = 'sheet.paste_values',
    title = 'Paste values only',
    icon = 'clipboard-type',
    menu = 'Edit',
    group = 'b',
    order = 23,
    when = idle,
    run = function ()
      grid.paste ({ only = 'values' })
    end,
  })
  command ({
    id = 'sheet.paste_formats',
    title = 'Paste formats only',
    icon = 'clipboard-paste',
    menu = 'Edit',
    group = 'b',
    order = 24,
    when = idle,
    run = function ()
      grid.paste ({ only = 'formats' })
    end,
  })
  command ({
    id = 'sheet.paste_transposed',
    title = 'Paste transposed',
    icon = 'clipboard-paste',
    menu = 'Edit',
    group = 'b',
    order = 25,
    when = idle,
    run = function ()
      grid.paste ({ transpose = true })
    end,
  })
  command ({
    id = 'sheet.select_all',
    title = 'Select all',
    key = 'ctrl+a',
    icon = 'text-cursor-input',
    menu = 'Edit',
    group = 'c',
    order = 30,
    when = idle,
    run = grid.select_all,
  })
  command ({
    id = 'sheet.clear',
    title = 'Clear cells',
    icon = 'eraser',
    menu = 'Edit',
    group = 'c',
    order = 31,
    when = idle,
    run = grid.clear,
  })
  command ({
    id = 'sheet.fill_down',
    title = 'Fill down',
    key = 'ctrl+d',
    icon = 'arrow-down-to-line',
    menu = 'Edit',
    group = 'd',
    order = 40,
    when = idle,
    run = function ()
      grid.fill (true)
    end,
  })
  command ({
    id = 'sheet.fill_right',
    title = 'Fill right',
    key = 'ctrl+r',
    icon = 'arrow-right-to-line',
    menu = 'Edit',
    group = 'd',
    order = 41,
    when = idle,
    run = function ()
      grid.fill (false)
    end,
  })
  command ({
    id = 'sheet.delete_row',
    title = 'Delete rows',
    icon = 'square-minus',
    menu = 'Edit',
    group = 'e',
    order = 50,
    when = idle,
    run = function ()
      grid.delete ('row')
    end,
  })
  command ({
    id = 'sheet.delete_col',
    title = 'Delete columns',
    icon = 'square-minus',
    menu = 'Edit',
    group = 'e',
    order = 51,
    when = idle,
    run = function ()
      grid.delete ('col')
    end,
  })
  command ({
    id = 'sheet.find_menu',
    title = 'Find…',
    icon = 'search',
    menu = 'Edit',
    group = 'f',
    order = 60,
    hidden = true,
    when = function ()
      return active () and commands.get ('sheet.find') ~= nil
    end,
    run = function ()
      commands.run ('sheet.find')
    end,
  })

  -- View
  command ({
    id = 'sheet.workbooks',
    title = 'Workbooks',
    icon = 'panel-left',
    menu = 'View',
    group = 'a',
    order = 10,
    run = function ()
      views.toggle ('sheet.list')
    end,
  })
  local grid_cmd = command ({
    id = 'sheet.gridlines',
    title = 'Show gridlines',
    icon = 'grid-3-x-3',
    menu = 'View',
    group = 'b',
    order = 20,
    when = active,
    run = function ()
      grid.set_view ('gridlines', not grid.view_opts.gridlines)
    end,
  })
  local formulas_cmd = command ({
    id = 'sheet.show_formulas',
    title = 'Show formulas',
    key = 'ctrl+`',
    icon = 'code',
    menu = 'View',
    group = 'b',
    order = 21,
    when = idle,
    run = function ()
      grid.set_view ('formulas', not grid.view_opts.formulas)
    end,
  })
  command ({
    id = 'sheet.freeze_row',
    title = 'Freeze 1 row',
    icon = 'snowflake',
    menu = 'View',
    group = 'c',
    order = 30,
    when = active,
    run = function ()
      grid.freeze (1, nil)
    end,
  })
  command ({
    id = 'sheet.freeze_rows_here',
    title = 'Freeze rows up to the selection',
    icon = 'snowflake',
    menu = 'View',
    group = 'c',
    order = 31,
    when = active,
    run = function ()
      grid.freeze (grid.sel_rect ().r2, nil)
    end,
  })
  command ({
    id = 'sheet.freeze_col',
    title = 'Freeze 1 column',
    icon = 'snowflake',
    menu = 'View',
    group = 'c',
    order = 32,
    when = active,
    run = function ()
      grid.freeze (nil, 1)
    end,
  })
  command ({
    id = 'sheet.freeze_cols_here',
    title = 'Freeze columns up to the selection',
    icon = 'snowflake',
    menu = 'View',
    group = 'c',
    order = 33,
    when = active,
    run = function ()
      grid.freeze (nil, grid.sel_rect ().c2)
    end,
  })
  command ({
    id = 'sheet.unfreeze',
    title = 'Unfreeze',
    icon = 'snowflake',
    menu = 'View',
    group = 'c',
    order = 34,
    when = function ()
      local s = grid.sheet ()
      if not active () or not s then
        return false
      end
      local fr, fc = s:freeze ()
      return fr > 0 or fc > 0
    end,
    run = function ()
      grid.freeze (0, 0)
    end,
  })
  command ({
    id = 'sheet.hide_rows',
    title = 'Hide rows',
    icon = 'eye-off',
    menu = 'View',
    group = 'd',
    order = 40,
    when = idle,
    run = function ()
      grid.hide ('row', true)
    end,
  })
  command ({
    id = 'sheet.hide_cols',
    title = 'Hide columns',
    icon = 'eye-off',
    menu = 'View',
    group = 'd',
    order = 41,
    when = idle,
    run = function ()
      grid.hide ('col', true)
    end,
  })
  command ({
    id = 'sheet.unhide_rows',
    title = 'Unhide rows',
    icon = 'eye',
    menu = 'View',
    group = 'd',
    order = 42,
    when = idle,
    run = function ()
      grid.hide ('row', false)
    end,
  })
  command ({
    id = 'sheet.unhide_cols',
    title = 'Unhide columns',
    icon = 'eye',
    menu = 'View',
    group = 'd',
    order = 43,
    when = idle,
    run = function ()
      grid.hide ('col', false)
    end,
  })
  command ({
    id = 'sheet.next_sheet',
    title = 'Next sheet',
    key = 'ctrl+pagedown',
    icon = 'arrow-right',
    menu = 'View',
    group = 'e',
    order = 50,
    when = cell_keys,
    run = function ()
      grid.step_sheet (1)
    end,
  })
  command ({
    id = 'sheet.prev_sheet',
    title = 'Previous sheet',
    key = 'ctrl+pageup',
    icon = 'arrow-left',
    menu = 'View',
    group = 'e',
    order = 51,
    when = cell_keys,
    run = function ()
      grid.step_sheet (-1)
    end,
  })
  command ({
    id = 'sheet.goto',
    title = 'Go to cell…',
    key = 'ctrl+g',
    icon = 'locate',
    menu = 'View',
    group = 'e',
    order = 52,
    when = function ()
      return active () and keys_free ()
    end,
    run = function ()
      grid.namebox:focus ()
    end,
  })
  command ({
    id = 'sheet.theme',
    title = 'Change theme…',
    icon = 'palette',
    menu = 'View',
    group = 'z',
    order = 90,
    run = function ()
      commands.run ('theme.choose')
    end,
  })
  command ({
    id = 'sheet.switch_app',
    title = 'Switch app…',
    icon = 'layers',
    menu = 'View',
    group = 'z',
    order = 91,
    run = function ()
      commands.run ('profile.switch')
    end,
  })

  -- Insert
  command ({
    id = 'sheet.row_above',
    title = 'Insert row above',
    icon = 'between-horizontal-start',
    menu = 'Insert',
    group = 'a',
    order = 10,
    when = idle,
    run = function ()
      grid.insert ('row', false)
    end,
  })
  command ({
    id = 'sheet.row_below',
    title = 'Insert row below',
    icon = 'between-horizontal-start',
    menu = 'Insert',
    group = 'a',
    order = 11,
    when = idle,
    run = function ()
      grid.insert ('row', true)
    end,
  })
  command ({
    id = 'sheet.col_left',
    title = 'Insert column left',
    icon = 'between-vertical-start',
    menu = 'Insert',
    group = 'a',
    order = 12,
    when = idle,
    run = function ()
      grid.insert ('col', false)
    end,
  })
  command ({
    id = 'sheet.col_right',
    title = 'Insert column right',
    icon = 'between-vertical-start',
    menu = 'Insert',
    group = 'a',
    order = 13,
    when = idle,
    run = function ()
      grid.insert ('col', true)
    end,
  })
  command ({
    id = 'sheet.add_sheet',
    title = 'Insert sheet',
    key = 'shift+f11',
    icon = 'plus',
    menu = 'Insert',
    group = 'b',
    order = 20,
    when = function ()
      return active () and keys_free ()
    end,
    run = grid.add_sheet,
  })
  command ({
    id = 'sheet.insert_date',
    title = 'Insert date',
    key = 'ctrl+;',
    icon = 'calendar',
    menu = 'Insert',
    group = 'd',
    order = 40,
    when = cell_keys,
    run = function ()
      local t = os.date ('*t') --[[@as osdate]]
      grid.type_text (string.format ('%d/%d/%d', t.month, t.day, t.year))
    end,
  })
  command ({
    id = 'sheet.insert_time',
    title = 'Insert time',
    key = { 'ctrl+shift+;', 'ctrl+shift+:' },
    icon = 'clock',
    menu = 'Insert',
    group = 'd',
    order = 41,
    when = cell_keys,
    run = function ()
      local t = os.date ('*t') --[[@as osdate]]
      local hour = t.hour % 12
      if hour == 0 then
        hour = 12
      end
      grid.type_text (
        string.format (
          '%d:%02d:%02d %s',
          hour,
          t.min,
          t.sec,
          t.hour < 12 and 'AM' or 'PM'
        )
      )
    end,
  })

  -- Format
  command ({
    id = 'sheet.row_height',
    title = 'Row height…',
    icon = 'move-vertical',
    menu = 'Format',
    group = 'y',
    order = 80,
    when = idle,
    run = function ()
      grid.ask_size ('row')
    end,
  })
  command ({
    id = 'sheet.col_width',
    title = 'Column width…',
    icon = 'move-horizontal',
    menu = 'Format',
    group = 'y',
    order = 81,
    when = idle,
    run = function ()
      grid.ask_size ('col')
    end,
  })
  command ({
    id = 'sheet.autofit',
    title = 'Auto-fit column width',
    icon = 'move-horizontal',
    menu = 'Format',
    group = 'y',
    order = 82,
    when = idle,
    run = function ()
      grid.autofit ()
    end,
  })

  -- Palette-only helpers for the sheet tabs.
  command ({
    id = 'sheet.rename_sheet',
    title = 'Rename sheet',
    icon = 'pencil',
    when = active,
    run = function ()
      local book = files.book ()
      if book then
        grid.rename_sheet (book.active)
      end
    end,
  })
  command ({
    id = 'sheet.duplicate_sheet',
    title = 'Duplicate sheet',
    icon = 'copy-plus',
    when = active,
    run = function ()
      local book = files.book ()
      if book then
        grid.duplicate_sheet (book.active)
      end
    end,
  })
  command ({
    id = 'sheet.delete_sheet',
    title = 'Delete sheet…',
    icon = 'trash',
    when = active,
    run = function ()
      local book = files.book ()
      if book then
        grid.delete_sheet (book.active)
      end
    end,
  })

  ---Keeps the labels that change with the book in step: Undo Sort, Hide gridlines.
  local function relabel ()
    local b = files.book ()
    local undo_label = b and b:undo_label ()
    local redo_label = b and b:redo_label ()
    undo_cmd.menu_title = undo_label and ('Undo ' .. string.lower (undo_label))
      or nil
    redo_cmd.menu_title = redo_label and ('Redo ' .. string.lower (redo_label))
      or nil
    grid_cmd.menu_title = grid.view_opts.gridlines and 'Hide gridlines'
      or 'Show gridlines'
    formulas_cmd.menu_title = grid.view_opts.formulas and 'Show values'
      or 'Show formulas'
  end
  on ('changed', relabel)
  on ('book', relabel)
  on ('view', relabel)
  relabel ()
end

return M
