-- sheet_files: the workbook files of the Sheet app. It keeps the open workbook and its file,
-- saves a workbook a moment after each change, and makes, opens, renames, duplicates and
-- deletes the workbooks in data/proteus.sheet/. It imports and exports CSV and Excel files,
-- opens an Excel or CSV file on disk in place and saves it back in its own format, and draws
-- the Workbooks view. init.lua installs it and reaches the open workbook through it.

local book_mod = require ('sheet_book') --[[@as Sheet.BookModule]]
local ops = require ('sheet_ops') --[[@as Sheet.OpsModule]]

local DIR = 'data/proteus.sheet'
local EXT = '.sheet.json'
-- How many workbooks Open recent offers.
local RECENT = 8

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

---What sheet_files gets from init.lua.
---@class Sheet.FilesEnv
---@field app Proteus.App
---@field ui Proteus.UI
---@field views Proteus.Views
---@field picker? Proteus.Picker
---@field grid Sheet.GridView
---@field say fun(kind: 'info'|'success'|'warn'|'error', text: string)
---@field safely fun(what: string, fn: fun())
---@field emit fun(event: Sheet.CtlEvent, ...: any)
---@field show_screen fun() Shows the grid when a workbook is open, or the empty screen.

---@class Sheet.FilesModule
local M = {}

---@param env Sheet.FilesEnv
---@return Sheet.Files
function M.install (env)
  local app, ui, views, picker = env.app, env.ui, env.views, env.picker
  local grid, say, safely, emit = env.grid, env.say, env.safely, env.emit
  local show_screen = env.show_screen

  local book = nil ---@type Sheet.Book?
  local file = nil ---@type string?
  local disk = nil ---@type Sheet.DiskFile?
  local pending = false
  local cancel_save = nil ---@type fun()?
  local tab = nil ---@type Proteus.Tab?

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

  local function new_workbook ()
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
    app.fs.pick_open ({ title = title, filters = filters }, function (paths, err)
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
    end)
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
              say ('success', 'Imported ' .. rows .. ' rows into "' .. n .. '".')
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
              say ('error', 'Could not read ' .. path .. ': ' .. tostring (err))
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
          ops.import_csv (made, text, base_of (path), sep, { keep_zeros = keep })
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

  -- Start ---------------------------------------------------------------------------------

  ---Watches the workbook files, writes the example on first start and opens the workbook
  ---used last. Returns true when a workbook opened.
  ---@return boolean
  local function start_files ()
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
    return start ~= nil and open_file (start)
  end

  ---The open workbook and its file, and what the commands and menus do with them.
  ---@class Sheet.Files
  local files = {
    book = function ()
      return book
    end,
    file = function ()
      return file
    end,
    disk = function ()
      return disk
    end,
    ---@param t Proteus.Tab?
    set_tab = function (t)
      tab = t
    end,
    dirty = dirty,
    save_now = save_now,
    save_disk = save_disk,
    new_workbook = new_workbook,
    open_file = open_file,
    open_picker = open_picker,
    open_recent = open_recent,
    rename_file = rename_file,
    duplicate_file = duplicate_file,
    delete_file = delete_file,
    import_csv = import_csv,
    import_xlsx = import_xlsx,
    export_csv = export_csv,
    export_xlsx = export_xlsx,
    pick_disk = pick_disk,
    list = list,
    start = start_files,
  }
  return files
end

return M
