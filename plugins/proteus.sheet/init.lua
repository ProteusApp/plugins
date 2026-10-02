-- proteus.sheet: a spreadsheet with formulas, formats, charts and several sheets per workbook.
-- Each workbook is a file in data/proteus.sheet/, listed in the Workbooks view of the left dock.
-- An Excel or CSV file on disk opens in place too, and Save writes it back in its own format.
--
-- This file puts the window together, keeps the open workbook and its file, and registers the
-- grid's commands. The grid itself lives in sheet_grid.lua and the modules it loads. The
-- formatting toolbar, the side panels and their commands live in sheet_toolbar.lua and
-- sheet_panels.lua, which reach the grid through the controller built here, described in
-- sheet_ctl.lua. The workbook model lives in sheet_book.lua, sheet_model.lua and sheet_ops.lua.

local book_mod = require ('sheet_book') --[[@as Sheet.BookModule]]
local ctl_mod = require ('sheet_ctl') --[[@as Sheet.CtlModule]]
local grid_mod = require ('sheet_grid') --[[@as Sheet.GridModule]]
local model = require ('sheet_model') --[[@as Sheet.ModelModule]]
local ops = require ('sheet_ops') --[[@as Sheet.OpsModule]]

local DIR = 'data/proteus.sheet'
local EXT = '.sheet.json'
-- How many workbooks Open recent offers.
local RECENT = 8

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

---A workbook open from an Excel or CSV file on disk, which Save writes back in its format.
---@class Sheet.DiskFile
---@field path string The file's full path.
---@field kind 'xlsx'|'csv'
---@field sep string The separator of a CSV file.
---@field name string The file's name, for the tab.
---@field lossless boolean True when the file opened with nothing left out, so changes save by themselves as in a workbook. Otherwise Save writes them.
---@field warned? string The warnings the last save gave, so saving by itself repeats none.

-- The kinds of files that open in place, by extension.
---@type table<string, 'xlsx'|'csv'>
local DISK_KINDS = { xlsx = 'xlsx', csv = 'csv', tsv = 'csv' }

---@param text string
---@return string
local function trim (text)
  return (string.match (text, '^%s*(.-)%s*$'))
end

---A file name made safe for a workbook, from any text.
---@param text string
---@return string
local function safe_name (text)
  return book_mod.safe_file_name (text)
end

---@type Proteus.Plugin
return {
  name = 'Sheet',
  description = 'A spreadsheet with formulas, charts and several sheets per workbook, saved in data/proteus.sheet.',
  version = '1.2.0',
  requires = { proteus = '>=0.3.0', features = { 'permissions' } },
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
    ui.css (CSS)

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

    -- Saving ---------------------------------------------------------------------------------

    ---@param n string
    ---@return string
    local function path_of (n)
      return DIR .. '/' .. n .. EXT
    end

    ---@type fun(done?: fun(ok: boolean), quiet?: boolean)
    local save_disk

    local function save_now ()
      if cancel_save then
        cancel_save ()
        cancel_save = nil
      end
      if disk then
        -- A file that opened with something left out saves only when asked, so a slip of the
        -- keys does not drop the rest of the file.
        if pending and disk.lossless then
          save_disk (nil, true)
        end
        return
      end
      local b, n = book, file
      if not pending or not b or not n then
        return
      end
      pending = false
      local ok, err = pcall (function ()
        app.fs.write (path_of (n), book_mod.encode (b))
      end)
      if not ok then
        say ('error', 'Could not save "' .. n .. '": ' .. tostring (err))
      end
    end

    local function dirty ()
      pending = true
      if cancel_save then
        cancel_save ()
      end
      if disk and tab then
        tab.set_dirty (true)
      end
      if disk and not disk.lossless then
        return
      end
      cancel_save = app.timer.after (600, save_now)
    end

    local grid = grid_mod.new (app, { emit = emit, say = say, dirty = dirty })

    -- The window -----------------------------------------------------------------------------

    local toolhost = ui.div ({ class = 'sheet-toolhost' })
    ---@type fun()
    local new_workbook
    local empty = ui.div ({
      class = 'sheet-empty',
      ui.div ({ class = 'sheet-empty-title', 'No workbook open' }),
      ui.div ({ 'Make a workbook, or pick one in the Workbooks list.' }),
      ui.button ({
        'New workbook',
        icon = 'file-plus',
        variant = 'primary',
        onclick = function ()
          new_workbook ()
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
      local open = book ~= nil
      grid.bar:show (open)
      grid.area:show (open)
      grid.tabs_bar:show (open)
      empty:show (not open)
    end

    -- The controller -------------------------------------------------------------------------

    ---@type Sheet.Ctl
    local ctl = {
      book = function ()
        return book
      end,
      sheet = function ()
        return grid.sheet ()
      end,
      file = function ()
        return file or (disk and disk.name)
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

    -- Workbook files -------------------------------------------------------------------------

    ---@return string[]
    local function file_names ()
      local out = {} ---@type string[]
      for _, e in ipairs (app.fs.list (DIR)) do
        local n = not e.dir and string.match (e.name, '^(.+)%.sheet%.json$')
        if n then
          out[#out + 1] = n
        end
      end
      table.sort (out, function (a, b)
        return string.lower (a) < string.lower (b)
      end)
      return out
    end

    ---@param base string
    ---@return string
    local function unique_name (base)
      local taken = {} ---@type table<string, boolean>
      for _, n in ipairs (file_names ()) do
        taken[string.lower (n)] = true
      end
      if not taken[string.lower (base)] then
        return base
      end
      local i = 2
      while taken[string.lower (base .. ' ' .. i)] do
        i = i + 1
      end
      return base .. ' ' .. i
    end

    ---Why a workbook name cannot be used, or nil when it can.
    ---@param n string
    ---@param except? string The workbook being renamed, which may keep its name.
    ---@return string?
    local function name_problem (n, except)
      local problem = book_mod.file_name_problem (n)
      if problem then
        return problem
      end
      for _, other in ipairs (file_names ()) do
        if string.lower (other) == string.lower (n) and other ~= except then
          return 'A workbook with that name exists already.'
        end
      end
      return nil
    end

    ---@param n string
    local function remember_recent (n)
      local list = app.store.get ('recent', {}) ---@type string[]
      local out = { n } ---@type string[]
      for _, other in ipairs (type (list) == 'table' and list or {}) do
        if other ~= n and #out < RECENT then
          out[#out + 1] = other
        end
      end
      app.store.set ('recent', out)
    end

    ---@type fun()
    local render_list

    ---True when the open file may be left now. A file on disk with changes that do not save
    ---by themselves asks first, and runs `go` once they are saved or let go.
    ---@param go fun()
    ---@return boolean
    local function can_leave (go)
      local d = disk
      if not d or not pending or d.lossless then
        return true
      end
      ---@param ok boolean
      local function after_save (ok)
        if ok then
          go ()
        end
      end
      if not picker then
        save_disk (after_save)
        return false
      end
      picker.confirm ({
        message = '"'
          .. d.name
          .. '" has changes that are not saved. Save them before going on?',
        yes = 'Save',
        no = 'Discard',
        on_yes = function ()
          save_disk (after_save)
        end,
        on_no = function ()
          pending = false
          go ()
        end,
      })
      return false
    end

    local function close_file ()
      if not can_leave (close_file) then
        return
      end
      save_now ()
      book, file, disk = nil, nil, nil
      pending = false
      if tab then
        tab.set_dirty (false)
      end
      grid.set_book (nil)
      app.store.set ('last', nil)
      show_screen ()
      if tab then
        tab.set_title ('Sheet')
      end
      render_list ()
      emit ('book')
    end

    ---@param n string
    ---@return boolean
    local function open_file (n)
      if grid.edit then
        grid.finish_edit (0, 0, false)
      end
      if not can_leave (function ()
        open_file (n)
      end) then
        return false
      end
      save_now ()
      local text = app.fs.read (path_of (n))
      if not text then
        say ('error', 'The workbook "' .. n .. '" is gone.')
        render_list ()
        return false
      end
      local opened, problem = book_mod.decode (text)
      if not opened then
        say ('error', '"' .. n .. '" could not be read. ' .. tostring (problem))
        return false
      end
      book, file, disk = opened, n, nil
      pending = false
      if tab then
        tab.set_dirty (false)
      end
      app.store.set ('last', n)
      remember_recent (n)
      show_screen ()
      grid.set_book (opened)
      render_list ()
      if tab then
        tab.set_title (n)
      end
      emit ('book')
      grid.focus ()
      return true
    end

    ---@param n string
    ---@param b Sheet.Book
    local function create (n, b)
      app.fs.write (path_of (n), book_mod.encode (b))
      open_file (n)
    end

    new_workbook = function ()
      local suggestion = unique_name ('Workbook')
      if not picker then
        create (suggestion, book_mod.new ())
        return
      end
      picker.input ({
        prompt = 'Name the new workbook',
        value = suggestion,
        validate = function (text)
          return name_problem (trim (text))
        end,
        on_submit = function (text)
          create (trim (text), book_mod.new ())
        end,
        on_cancel = grid.focus,
      })
    end

    local function open_picker ()
      local names = file_names ()
      if not picker then
        return
      end
      if #names == 0 then
        say ('info', 'There are no workbooks yet.')
        return
      end
      ---@type Proteus.PickItem[]
      local items = {}
      for _, n in ipairs (names) do
        items[#items + 1] = {
          label = n,
          icon = 'sheet',
          value = n,
          detail = n == file and 'open' or nil,
        }
      end
      picker.pick ({
        items = items,
        placeholder = 'Open a workbook',
        on_pick = function (item)
          open_file (item.value --[[@as string]])
        end,
        on_cancel = grid.focus,
      })
    end

    local function open_recent ()
      if not picker then
        return
      end
      local list = app.store.get ('recent', {}) ---@type string[]
      local have = {} ---@type table<string, boolean>
      for _, n in ipairs (file_names ()) do
        have[n] = true
      end
      ---@type Proteus.PickItem[]
      local items = {}
      for _, n in ipairs (type (list) == 'table' and list or {}) do
        if have[n] then
          items[#items + 1] = {
            label = n,
            icon = 'sheet',
            value = n,
            detail = n == file and 'open' or nil,
          }
        end
      end
      if #items == 0 then
        say ('info', 'No workbooks were opened lately.')
        return
      end
      picker.pick ({
        items = items,
        placeholder = 'Open a recent workbook',
        on_pick = function (item)
          open_file (item.value --[[@as string]])
        end,
        on_cancel = grid.focus,
      })
    end

    ---@param n string
    local function rename_file (n)
      if not picker then
        return
      end
      picker.input ({
        prompt = 'Rename the workbook "' .. n .. '"',
        value = n,
        validate = function (text)
          return name_problem (trim (text), n)
        end,
        on_submit = function (text)
          local new = trim (text)
          if new == n then
            return
          end
          if file == n then
            save_now ()
          end
          local ok, err = pcall (app.fs.rename, path_of (n), path_of (new))
          if not ok then
            say ('error', 'Could not rename "' .. n .. '": ' .. tostring (err))
            return
          end
          if file == n then
            file = new
            app.store.set ('last', new)
            remember_recent (new)
            if tab then
              tab.set_title (new)
            end
            emit ('book')
          end
          render_list ()
        end,
        on_cancel = grid.focus,
      })
    end

    ---@param n string
    local function duplicate_file (n)
      if file == n then
        save_now ()
      end
      local text = app.fs.read (path_of (n))
      if not text then
        say ('error', 'The workbook "' .. n .. '" is gone.')
        return
      end
      local copy_name = unique_name (n .. ' copy')
      app.fs.write (path_of (copy_name), text)
      open_file (copy_name)
    end

    ---@param n string
    local function delete_file (n)
      local function go ()
        if file == n then
          pending = false
          close_file ()
        end
        app.fs.remove (path_of (n))
        if not book then
          local rest = file_names ()
          if rest[1] then
            open_file (rest[1])
          end
        end
        render_list ()
      end
      if picker then
        picker.confirm ({
          message = 'Delete the workbook "' .. n .. '"? This cannot be undone.',
          yes = 'Delete',
          on_yes = go,
          on_no = grid.focus,
        })
      else
        go ()
      end
    end

    -- Importing and exporting ----------------------------------------------------------------

    ---@param what string
    ---@return boolean
    local function desktop_only (what)
      if app.platform == 'browser' then
        say ('warn', what .. ' needs the desktop app.')
        return true
      end
      return false
    end

    ---Picks a file on disk and hands its full path to `fn`.
    ---@param title string
    ---@param filters Proteus.DialogFilter[]
    ---@param fn fun(path: string)
    local function pick_file (title, filters, fn)
      app.fs.pick_open (
        { title = title, filters = filters },
        function (paths, err)
          safely (title, function ()
            if err then
              say ('error', 'Could not pick a file: ' .. err)
              return
            end
            local path = paths and paths[1]
            if path then
              fn (path)
            end
          end)
        end
      )
    end

    ---The workbook name a file on disk suggests.
    ---@param path string
    ---@return string
    local function base_of (path)
      local base = string.match (path, '([^/\\]+)$') or ''
      return safe_name ((string.gsub (base, '%.[^%.]*$', '')))
    end

    ---The separator of CSV text: a tab when the first line holds tabs and no commas.
    ---@param path string
    ---@param text string
    ---@return string
    local function separator (path, text)
      local first = string.match (text, '^[^\r\n]*') or ''
      if
        string.match (string.lower (path), '%.tsv$')
        or (
          string.find (first, '\t', 1, true)
          and not string.find (first, ',', 1, true)
        )
      then
        return '\t'
      end
      return ','
    end

    ---Asks how to read CSV text that holds numbers starting with 0, such as `00123`: as text
    ---that keeps its zeros, or as numbers. Text without any reads as numbers without asking.
    ---@param text string
    ---@param sep string
    ---@param fn fun(keep_zeros: boolean)
    local function ask_zeros (text, sep, fn)
      if not picker or not ops.leading_zeros (text, sep) then
        fn (false)
        return
      end
      picker.pick ({
        placeholder = 'Some cells start with 0, such as 00123',
        items = {
          {
            label = 'Keep them as text, with their zeros',
            icon = 'type',
            value = 'text',
          },
          { label = 'Read them as numbers', icon = 'hash', value = 'numbers' },
        },
        on_pick = function (item)
          safely ('Reading CSV', function ()
            fn (item.value == 'text')
          end)
        end,
        on_cancel = grid.focus,
      })
    end

    ---Imports a CSV file into a new workbook, or into a new sheet of the open one.
    ---@param into_sheet boolean
    local function import_csv (into_sheet)
      if desktop_only ('Import CSV') then
        return
      end
      if into_sheet and not book then
        into_sheet = false
      end
      pick_file (
        'Import CSV',
        { { name = 'CSV files', extensions = { 'csv', 'tsv', 'txt' } } },
        function (path)
          app.fs.read_file (path, function (text, read_err)
            safely ('Import CSV', function ()
              if not text then
                say (
                  'error',
                  'Could not read ' .. path .. ': ' .. tostring (read_err)
                )
                return
              end
              text = string.gsub (text, '^\239\187\191', '')
              local sep = separator (path, text)
              local base = base_of (path)
              ask_zeros (text, sep, function (keep)
                local opts = { keep_zeros = keep }
                if into_sheet then
                  grid.change ('Import CSV', function (b)
                    ops.import_csv (b, text, base, sep, opts)
                  end)
                  say ('success', 'Imported ' .. base .. ' into a new sheet.')
                  return
                end
                -- A new book's empty first sheet goes, leaving the one the text fills. Each
                -- cell reads as if typed, so "$1,200" becomes a number with a money format.
                local made = book_mod.new ()
                local filled = ops.import_csv (made, text, base, sep, opts)
                made:delete_sheet (1)
                local rows = filled:used ()
                local n = unique_name (base)
                create (n, made)
                say (
                  'success',
                  'Imported ' .. rows .. ' rows into "' .. n .. '".'
                )
              end)
            end)
          end)
        end
      )
    end

    local function import_xlsx ()
      if desktop_only ('Import Excel') then
        return
      end
      pick_file (
        'Import Excel',
        { { name = 'Excel workbooks', extensions = { 'xlsx' } } },
        function (path)
          app.fs.read_zip (path, function (files, err)
            safely ('Import Excel', function ()
              if not files then
                say (
                  'error',
                  'Could not read ' .. path .. ': ' .. tostring (err)
                )
                return
              end
              local made, warnings = ops.read_xlsx (files)
              if not made then
                say ('error', tostring (warnings))
                return
              end
              local n = unique_name (base_of (path))
              create (n, made)
              local list = type (warnings) == 'table' and warnings or {}
              if #list > 0 then
                say (
                  'warn',
                  'Imported "'
                    .. n
                    .. '". Some parts were left out: '
                    .. table.concat (list, ' ')
                )
              else
                say ('success', 'Imported "' .. n .. '".')
              end
            end)
          end)
        end
      )
    end

    local function export_csv ()
      local s, n = grid.sheet (), file or (disk and base_of (disk.path))
      if not s or not n or desktop_only ('Export CSV') then
        return
      end
      local text = ops.export_csv (s)
      app.fs.pick_save ({
        title = 'Export CSV',
        default_path = n .. ' - ' .. s.name .. '.csv',
        filters = { { name = 'CSV files', extensions = { 'csv' } } },
      }, function (path, err)
        safely ('Export CSV', function ()
          if err then
            say ('error', 'Could not pick a file: ' .. err)
            return
          end
          if not path then
            return
          end
          app.fs.write_file (path, text, function (_, write_err)
            if write_err then
              say ('error', 'Could not write ' .. path .. ': ' .. write_err)
            else
              say ('success', 'Exported "' .. s.name .. '" to ' .. path)
            end
          end)
        end)
      end)
    end

    local function export_xlsx ()
      local b, n = book, file or (disk and base_of (disk.path))
      if not b or not n or desktop_only ('Export Excel') then
        return
      end
      local files, warnings = ops.write_xlsx (b)
      app.fs.pick_save ({
        title = 'Export Excel',
        default_path = n .. '.xlsx',
        filters = { { name = 'Excel workbooks', extensions = { 'xlsx' } } },
      }, function (path, err)
        safely ('Export Excel', function ()
          if err then
            say ('error', 'Could not pick a file: ' .. err)
            return
          end
          if not path then
            return
          end
          app.fs.write_zip (path, files, function (_, write_err)
            if write_err then
              say ('error', 'Could not write ' .. path .. ': ' .. write_err)
            elseif #warnings > 0 then
              say (
                'warn',
                'Exported to ' .. path .. '. ' .. table.concat (warnings, ' ')
              )
            else
              say ('success', 'Exported "' .. n .. '" to ' .. path)
            end
          end)
        end)
      end)
    end

    -- Files on disk, opened in place ------------------------------------------------------------

    ---Writes the open file on disk back in its own format. `done` hears whether it worked.
    ---`quiet` leaves out the message when all went well, as autosaving does.
    save_disk = function (done, quiet)
      local d, b = disk, book
      if not d or not b then
        if done then
          done (false)
        end
        return
      end
      local at = b.edits
      ---@param err? string
      ---@param warnings string[]
      local function finished (err, warnings)
        if err then
          say ('error', 'Could not save ' .. d.path .. ': ' .. tostring (err))
          if done then
            done (false)
          end
          return
        end
        if disk == d and book == b and b.edits == at then
          pending = false
          if tab then
            tab.set_dirty (false)
          end
        end
        local warned = table.concat (warnings, ' ')
        if #warnings > 0 and not (quiet and warned == d.warned) then
          say ('warn', 'Saved ' .. d.name .. '. ' .. warned)
        elseif #warnings == 0 and not quiet then
          say ('success', 'Saved ' .. d.name .. '.')
        end
        d.warned = warned
        if done then
          done (true)
        end
      end
      if d.kind == 'xlsx' then
        local ok, files, warnings = pcall (ops.write_xlsx, b)
        if not ok then
          finished (tostring (files), {})
          return
        end
        app.fs.write_zip (d.path, files, function (_, err)
          finished (err, warnings)
        end)
        return
      end
      local warnings = {} ---@type string[]
      if #b.sheets > 1 then
        warnings[1] = 'A CSV file holds one sheet, so it keeps only "'
          .. b.sheets[1].name
          .. '".'
      end
      local text = ops.export_csv (b.sheets[1], nil, d.sep)
      app.fs.write_file (d.path, text, function (_, err)
        finished (err, warnings)
      end)
    end

    ---True for a full path on disk, rather than a path in the workspace.
    ---@param path string
    ---@return boolean
    local function on_disk (path)
      return string.match (path, '^/') ~= nil
        or string.match (path, '^%a:[/\\]') ~= nil
        or string.match (path, '^\\\\') ~= nil
    end

    ---The kind of a file that opens in place, from its extension, or nil.
    ---@param path string
    ---@return ('xlsx'|'csv')?
    local function disk_kind (path)
      local ext = string.lower (string.match (path, '%.([^%.\\/]+)$') or '')
      return DISK_KINDS[ext]
    end

    ---Opens an Excel or CSV file on disk in place, in the window, without making a workbook of
    ---it. Save writes it back in its own format.
    ---@param path string
    local function open_disk (path)
      local kind = disk_kind (path)
      if not kind then
        say ('warn', 'Only Excel (.xlsx) and CSV files open in place.')
        return
      end
      if desktop_only ('Opening a file on disk') then
        return
      end
      if grid.edit then
        grid.finish_edit (0, 0, false)
      end
      if not can_leave (function ()
        open_disk (path)
      end) then
        return
      end
      save_now ()
      local name = string.match (path, '([^/\\]+)$') or path
      ---@param made Sheet.Book
      ---@param lossless boolean
      ---@param sep string
      local function show (made, lossless, sep)
        -- Reading the file made undo steps, which are no edit of the user's.
        made.done, made.undone = {}, {}
        book, file, pending = made, nil, false
        disk = {
          path = path,
          kind = kind,
          sep = sep,
          name = name,
          lossless = lossless,
        }
        app.store.set ('last', nil)
        show_screen ()
        grid.set_book (made)
        render_list ()
        if tab then
          tab.set_dirty (false)
          tab.set_title (name)
          tab.focus ()
        end
        emit ('book')
        grid.focus ()
      end
      if kind == 'xlsx' then
        app.fs.read_zip (path, function (files, err)
          safely ('Opening ' .. name, function ()
            if not files then
              say ('error', 'Could not read ' .. path .. ': ' .. tostring (err))
              return
            end
            local made, warnings = ops.read_xlsx (files)
            if not made then
              say ('error', tostring (warnings))
              return
            end
            local list = type (warnings) == 'table' and warnings or {}
            show (made, #list == 0, ',')
            if #list > 0 then
              say (
                'warn',
                'Opened "'
                  .. name
                  .. '". Some parts were left out, so changes save only when you choose Save: '
                  .. table.concat (list, ' ')
              )
            end
          end)
        end)
        return
      end
      app.fs.read_file (path, function (text, err)
        safely ('Opening ' .. name, function ()
          if not text then
            say ('error', 'Could not read ' .. path .. ': ' .. tostring (err))
            return
          end
          text = string.gsub (text, '^\239\187\191', '')
          local sep = separator (path, text)
          ask_zeros (text, sep, function (keep)
            local made = book_mod.new ()
            ops.import_csv (
              made,
              text,
              base_of (path),
              sep,
              { keep_zeros = keep }
            )
            made:delete_sheet (1)
            show (made, true, sep)
          end)
        end)
      end)
    end

    local function pick_disk ()
      if desktop_only ('Opening a file on disk') then
        return
      end
      pick_file ('Open', {
        {
          name = 'Excel and CSV files',
          extensions = { 'xlsx', 'csv', 'tsv' },
        },
      }, open_disk)
    end

    -- The Code Editor's explorer and other plugins open Excel and CSV files here.
    local editor = app.try_use ('editor')
    if editor then
      editor.add_opener (function (path)
        if
          type (path) ~= 'string'
          or not on_disk (path)
          or not disk_kind (path)
        then
          return false
        end
        open_disk (path)
        return true
      end)
    end
    local file_kinds = app.try_use ('files')
    if file_kinds then
      for ext in pairs (DISK_KINDS) do
        file_kinds.associate ({
          kind = 'icon',
          pattern = '*.' .. ext,
          value = { icon = 'sheet', color = 'var(--syn-string)' },
        })
      end
    end

    -- The Workbooks view -----------------------------------------------------------------------

    local list = ui.div ({ class = 'sheet-list' })
    local sheet_icon = app.util.icon ('sheet', 15) or ''
    render_list = function ()
      local names = file_names ()
      if #names == 0 then
        list:html ('<div class="ui-empty">No workbooks yet.</div>')
        return
      end
      local parts = {} ---@type string[]
      for _, n in ipairs (names) do
        local safe = app.util.escape (n)
        parts[#parts + 1] = '<div class="sheet-item'
          .. (n == file and ' active' or '')
          .. '" data-item="'
          .. safe
          .. '" title="'
          .. safe
          .. '">'
          .. sheet_icon
          .. '<span>'
          .. safe
          .. '</span></div>'
      end
      list:html (table.concat (parts))
    end
    list:on ('click', function (ev)
      if ev.item and ev.item ~= file then
        open_file (ev.item)
      end
      return nil
    end)
    views.add ('left', {
      id = 'sheet.list',
      title = 'Workbooks',
      icon = 'sheet',
      order = 1,
      content = ui.div ({
        class = 'sheet-side',
        ui.div ({
          class = 'sheet-side-head',
          ui.button ({
            'New workbook',
            icon = 'file-plus',
            onclick = function ()
              new_workbook ()
            end,
          }),
        }),
        list,
      }),
    })

    -- Commands -------------------------------------------------------------------------------

    ---True when a workbook is open and in view.
    ---@return boolean
    local function active ()
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
        return file ~= nil
      end,
      run = function ()
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
        return file ~= nil
      end,
      run = function ()
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
        return file ~= nil
      end,
      run = function ()
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
        if book then
          grid.delete_sheet (book.active)
        end
      end,
    })

    ---Keeps the labels that change with the book in step: Undo Sort, Hide gridlines.
    local function relabel ()
      local b = book
      local undo_label = b and b:undo_label ()
      local redo_label = b and b:redo_label ()
      undo_cmd.menu_title = undo_label
          and ('Undo ' .. string.lower (undo_label))
        or nil
      redo_cmd.menu_title = redo_label
          and ('Redo ' .. string.lower (redo_label))
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

    -- Right-click menus ----------------------------------------------------------------------

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
        run_item (
          has_link and 'Edit link' or 'Insert link',
          'link',
          'sheet.link'
        ),
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
        items[#items + 1] = run_item (
          'Sort sheet A to Z',
          'arrow-up-narrow-wide',
          'sheet.sort_az'
        )
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
        if grid.edit or not book then
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
      tab = tabs.open ({
        id = 'proteus.sheet',
        title = 'Sheet',
        icon = 'sheet',
        content = root,
        closable = false,
        on_focus = function ()
          if book and not grid.edit then
            grid.focus ()
          end
        end,
      })
    else
      shell.mount ('main', root)
    end

    -- A workbook changed in another window loads again here, unless this window has changes of
    -- its own waiting to be saved.
    ---@param path any
    ---@param remote any
    app.on ('fs:changed', function (path, remote)
      if
        type (path) ~= 'string'
        or string.sub (path, 1, #DIR + 1) ~= DIR .. '/'
      then
        return
      end
      render_list ()
      if
        remote
        and file
        and path == path_of (file)
        and not pending
        and not grid.edit
      then
        local text = app.fs.read (path)
        local fresh = text and book_mod.decode (text)
        if fresh then
          local keep = grid.sel_rect ()
          book = fresh
          grid.set_book (fresh)
          grid.select (keep)
          emit ('book')
        end
      end
    end)

    app.dispose (save_now)

    if #file_names () == 0 and not app.store.get ('seeded', false) then
      app.store.set ('seeded', true)
      app.fs.write (path_of ('Budget'), book_mod.encode (book_mod.example ()))
    end
    local last = app.store.get ('last') ---@type string?
    local names = file_names ()
    local start = nil ---@type string?
    for _, n in ipairs (names) do
      if n == last then
        start = n
      end
    end
    start = start or names[1]
    show_screen ()
    render_list ()
    if start and open_file (start) then
      shell.set_visible ('left', false)
    end
  end,
}
