-- proteus.sheet: a spreadsheet with formulas, formats, charts and several sheets per workbook.
-- Each workbook is a file in data/proteus.sheet/, listed in the Workbooks view of the left dock.
-- An Excel or CSV file on disk opens in place too, and Save writes it back in its own format.
--
-- This file puts the window together. The open workbook and its file live in sheet_files.lua,
-- the grid's commands in sheet_commands.lua and the right-click menus in sheet_menus.lua. The
-- grid itself lives in sheet_grid.lua and the modules it loads. The formatting toolbar, the
-- side panels and their commands live in sheet_toolbar.lua and sheet_panels.lua, which reach
-- the grid through the controller built here, described in sheet_ctl.lua. The workbook model
-- lives in sheet_book.lua, sheet_model.lua and sheet_ops.lua.

local commands_mod = require ('sheet_commands') --[[@as Sheet.CommandsModule]]
local ctl_mod = require ('sheet_ctl') --[[@as Sheet.CtlModule]]
local files_mod = require ('sheet_files') --[[@as Sheet.FilesModule]]
local grid_mod = require ('sheet_grid') --[[@as Sheet.GridModule]]
local menus_mod = require ('sheet_menus') --[[@as Sheet.MenusModule]]

-- lang=css
local CSS = [[
.sheet-root { flex: 1; height: 100%; min-height: 0; min-width: 0; display: flex; flex-direction: column;
  background: var(--bg); color: var(--fg); font-family: var(--font-ui); font-size: 13px; }
.sheet-toolhost { flex: none; }
.sheet-toolhost:empty { display: none; }
.sheet-empty { flex: 1; display: flex; flex-direction: column; align-items: center; justify-content: center;
  gap: 12px; color: var(--fg-muted); }
.sheet-empty-title { font-size: 16px; color: var(--fg); }
.sheet-side { display: flex; flex-direction: column; height: 100%; }
.sheet-side-head { padding: 10px; }
.sheet-side-head .ui-button { width: 100%; justify-content: center; }
.sheet-list { flex: 1; overflow: auto; padding: 0 6px 10px; }
.sheet-item { display: flex; align-items: center; gap: 8px; padding: 7px 10px; border-radius: var(--radius);
  cursor: pointer; white-space: nowrap; overflow: hidden; }
.sheet-item span { overflow: hidden; text-overflow: ellipsis; }
.sheet-item .icon, .sheet-item svg { color: var(--fg-muted); flex: none; }
.sheet-item:hover { background: var(--bg-hover); }
.sheet-item.active { background: var(--bg-active); }
]]

---@type Proteus.Plugin
return {
  name = 'Sheet',
  description = 'A spreadsheet with formulas, charts and several sheets per workbook, saved in data/proteus.sheet.',
  version = '1.3.1',
  requires = { proteus = '>=0.3.1', features = { 'permissions', 'menus' } },
  -- Import, Export and opening a file in place read and write CSV and Excel files anywhere on
  -- disk, and Paste reads the clipboard. The Excel reader runs here in Lua, so it needs the
  -- file itself, which `files` gives and a file grant, made for web views, does not.
  permissions = { 'clipboard', 'files' },
  depends = {
    'proteus.lib.ui',
    'proteus.ui.shell',
    'proteus.ui.views',
    'proteus.core.commands',
  },
  optional = {
    'proteus.ui.toolbar',
    'proteus.ui.statusbar',
    'proteus.ui.palette',
    'proteus.ui.notify',
    'proteus.core.keys',
    'proteus.ui.menus',
    'proteus.ui.menubar',
    'proteus.ui.tabs',
    'proteus.core.files',
    'proteus.editor.core',
  },
  activate = function (app)
    local ui = app.use ('ui')
    local shell = app.use ('shell')
    local views = app.use ('views')
    local commands = app.use ('commands')
    local tabs = app.try_use ('tabs')
    local notify = app.try_use ('notify')
    local picker = app.try_use ('picker')
    local menus = app.try_use ('menus')
    local keys = app.try_use ('keys')
    ui.css (CSS)

    ---A key as menus show it on this computer, such as Ctrl+V, or Cmd+V on a Mac.
    ---@param combo string
    ---@return string?
    local function keys_label (combo)
      return keys and keys.pretty (keys.normalize (combo)) or nil
    end

    local book = nil ---@type Sheet.Book?
    local file = nil ---@type string?
    local disk = nil ---@type Sheet.DiskFile?
    local pending = false
    local cancel_save = nil ---@type fun()?
    local tab = nil ---@type Proteus.Tab?
    local on, emit = ctl_mod.events ()

    ---@param kind 'info'|'success'|'warn'|'error'
    ---@param text string
    local function say (kind, text)
      if notify then
        notify[kind] (text)
      else
        app.log (text)
      end
    end

    ---Runs `fn`, and shows an error it raises instead of letting it out of a callback.
    ---@param what string
    ---@param fn fun()
    local function safely (what, fn)
      local ok, err = pcall (fn)
      if not ok then
        say ('error', what .. ' failed: ' .. tostring (err))
      end
    end

    -- The workbook files, installed once the window and the controller are built.
    ---@type Sheet.Files
    local files

    local grid = grid_mod.new (app, {
      emit = emit,
      say = say,
      dirty = function ()
        files.dirty ()
      end,
    })

    -- The window -----------------------------------------------------------------------------

    local toolhost = ui.div ({ class = 'sheet-toolhost' })
    local empty = ui.div ({
      class = 'sheet-empty',
      ui.div ({ class = 'sheet-empty-title', 'No workbook open' }),
      ui.div ({ 'Make a workbook, or pick one in the Workbooks list.' }),
      ui.button ({
        'New workbook',
        icon = 'file-plus',
        variant = 'primary',
        onclick = function ()
          files.new_workbook ()
        end,
      }),
    })
    local root = ui.div ({
      class = 'sheet-root',
      toolhost,
      grid.bar,
      grid.area,
      grid.tabs_bar,
      empty,
    })

    local function show_screen ()
      local open = files.book () ~= nil
      grid.bar:show (open)
      grid.area:show (open)
      grid.tabs_bar:show (open)
      empty:show (not open)
    end

    -- The controller -------------------------------------------------------------------------

    ---@type Sheet.Ctl
    local ctl = {
      book = function ()
        return files.book ()
      end,
      sheet = function ()
        return grid.sheet ()
      end,
      file = function ()
        local disk = files.disk ()
        return files.file () or (disk and disk.name)
      end,
      selection = function ()
        return grid.sel_rect (), grid.sel.r, grid.sel.c
      end,
      select = function (rect, row, col)
        grid.select (rect, row, col)
      end,
      show_sheet = function (index)
        grid.show_sheet (index)
      end,
      grid_rect = function ()
        return grid.grid_rect ()
      end,
      change = function (label, fn)
        return grid.change (label, fn)
      end,
      redraw = function ()
        grid.draw ()
        grid.redraw_charts ()
      end,
      editing = function ()
        return grid.edit ~= nil
      end,
      type_text = function (text)
        grid.type_text (text)
      end,
      cell_rect = function (row, col)
        return grid.cell_rect (row, col)
      end,
      follow_link = function (row, col)
        grid.follow_link (row, col)
      end,
      measure = function (text, style)
        return grid.measure (text, style)
      end,
      root = function ()
        return root
      end,
      focus = function ()
        grid.focus ()
      end,
      chart = function ()
        return grid.chart_id
      end,
      select_chart = function (id)
        grid.select_chart (id)
      end,
      view = function ()
        return {
          gridlines = grid.view_opts.gridlines,
          formulas = grid.view_opts.formulas,
        }
      end,
      on = on,
      emit = emit,
      say = say,
    }

    -- Workbook files, commands and menus ------------------------------------------------------

    files = files_mod.install ({
      app = app,
      ui = ui,
      views = views,
      picker = picker,
      grid = grid,
      say = say,
      safely = safely,
      emit = emit,
      show_screen = show_screen,
    })
    ---@type Sheet.AppEnv
    local env = {
      views = views,
      commands = commands,
      tabs = tabs,
      menus = menus,
      grid = grid,
      files = files,
      on = on,
      emit = emit,
      keys_label = keys_label,
    }
    commands_mod.install (env)
    menus_mod.install (env)

    -- The toolbar and the side panels ---------------------------------------------------------

    local toolbar = require ('sheet_toolbar') --[[@as Sheet.ToolbarModule]]
    local panels = require ('sheet_panels') --[[@as Sheet.PanelsModule]]
    safely ('The toolbar', function ()
      toolbar.mount (app, ctl, toolhost)
    end)
    safely ('The side panels', function ()
      panels.install (app, ctl)
    end)

    -- Start ----------------------------------------------------------------------------------

    if tabs then
      files.set_tab (tabs.open ({
        id = 'proteus.sheet',
        title = 'Sheet',
        icon = 'sheet',
        content = root,
        closable = false,
        on_focus = function ()
          if files.book () and not grid.edit then
            grid.focus ()
          end
        end,
      }))
    else
      shell.mount ('main', root)
    end

    if files.start () then
      shell.set_visible ('left', false)
    end
  end,
}
