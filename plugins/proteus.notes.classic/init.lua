-- proteus.notes.classic: a notes app, written by hand. The notes profile runs proteus.notes, the
-- same app built as a Nodal graph. Each note is a Markdown file in data/notes/, which both
-- keep, so the editor profile can open them too. The first line of a note is its title.

local DIR = 'data/notes'

-- lang=css
local CSS = [[
.notes-side { display: flex; flex-direction: column; height: 100%; }
.notes-search { margin: 10px; }
.notes-list { flex: 1; overflow: auto; padding: 0 6px 10px; }
.note-row { padding: 9px 10px; border-radius: var(--radius); cursor: pointer; }
.note-row:hover { background: var(--bg-hover); }
.note-row.active { background: var(--bg-active); }
.note-row .t { font-weight: 600; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.note-row .s { color: var(--fg-muted); font-size: 12px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; margin-top: 2px; }
.notes-main { flex: 1; min-height: 0; display: flex; justify-content: center; overflow: auto; background: var(--bg); }
.notes-page { width: min(760px, 100%); padding: 40px 36px 80px; display: flex; flex-direction: column; }
.notes-text { flex: 1; min-height: 70vh; width: 100%; border: none; outline: none; resize: none; background: none;
  color: var(--fg); font: 16px/1.75 var(--notes-font, Georgia, "Iowan Old Style", serif); }
.notes-preview { font: 16px/1.75 var(--notes-font, Georgia, "Iowan Old Style", serif); }
.notes-preview h1 { font-size: 28px; line-height: 1.3; }
.notes-empty { margin: auto; color: var(--fg-faint); text-align: center; }
]]

local WELCOME = [[
# Welcome to Notes

This app is the same program as the Plugin Editor, started with a different profile.
It runs the toolbar, status bar and theme plugins, plus one plugin called `proteus.notes.classic`.

- **Ctrl+N** makes a new note
- **Ctrl+E** switches between writing and a Markdown preview
- **Ctrl+Shift+P** finds any command, including **Switch Profile**

Notes are saved as you type, as Markdown files in `data/notes/`.
]]

---@param text string?
---@return string
local function title_of (text)
  ---@type string
  local first = (text or ''):match ('^%s*([^\n]*)') or ''
  first = first:gsub ('^#+%s*', '')
  return first ~= '' and first or 'Untitled'
end

---@param text string?
---@return string
local function snippet_of (text)
  ---@type string
  local rest = (text or ''):match ('^[^\n]*\n(.*)$') or ''
  rest = rest:gsub ('[#*_`>%-]', ''):gsub ('%s+', ' '):gsub ('^%s+', '')
  return rest:sub (1, 90)
end

-- A row in the note list, kept so a right-click can find its note.
---@class Notes.Row
---@field row Proteus.El
---@field id string

---@type Proteus.Plugin
return {
  name = 'Notes (classic)',
  description = 'Write and search Markdown notes.',
  version = '1.0.0',
  -- Notes live in data/notes, beside the ones the Notes graph app keeps.
  permissions = { 'workspace' },
  requires = { proteus = '>=0.3.0', features = { 'permissions' } },
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
  },
  -- Notes fills the main area, which is where tabs go too.
  conflicts = { 'proteus.ui.tabs' },
  activate = function (app)
    local ui = app.use ('ui')
    local shell = app.use ('shell')
    local views = app.use ('views')
    local commands = app.use ('commands')
    local status = app.try_use ('status')
    ui.css (CSS)

    -- Note ids, most recently edited first.
    ---@type string[]
    local order = app.store.get ('order', {})
    ---@type string?
    local current = nil
    local query = ''
    local preview = false
    ---@type fun()?
    local save_timer = nil

    ---@param id string
    ---@return string
    local function path_of (id)
      return DIR .. '/' .. id .. '.md'
    end

    ---@return string[]
    local function all_ids ()
      ---@type table<string, boolean>
      local seen = {}
      ---@type string[]
      local ids = {}
      for _, id in ipairs (order) do
        if app.fs.exists (path_of (id)) and not seen[id] then
          seen[id] = true
          ids[#ids + 1] = id
        end
      end
      for _, e in ipairs (app.fs.list (DIR)) do
        local id = e.name:match ('^(.+)%.md$')
        if id and not seen[id] then
          seen[id] = true
          ids[#ids + 1] = id
        end
      end
      return ids
    end

    ---@param id string
    local function bump (id)
      for i, x in ipairs (order) do
        if x == id then
          table.remove (order, i)
          break
        end
      end
      table.insert (order, 1, id)
      app.store.set ('order', order)
    end

    -- Screen parts ---------------------------------------------------------------------------

    local list = ui.div ({ class = 'notes-list' })
    local text = ui.h ('textarea', {
      class = 'notes-text',
      spellcheck = true,
      placeholder = 'Start writing. The first line is the title.',
    })
    local pv = ui.div ({ class = 'notes-preview ui-markdown' })
    local empty = ui.div ({
      class = 'notes-empty',
      ui.div ({ 'No note open' }),
      ui.div ({ class = 'ui-muted', 'Ctrl+N makes one' }),
    })
    local page = ui.div ({ class = 'notes-page', text, pv })
    local main = ui.div ({ class = 'notes-main', page, empty })
    shell.mount ('main', main)

    local st_words = status
      and status.add ({
        id = 'notes.words',
        text = '',
        align = 'right',
        order = 10,
      })
    local st_saved = status
      and status.add ({
        id = 'notes.saved',
        text = '',
        align = 'right',
        order = 20,
      })

    ---@type fun()
    local render_list
    ---@type Notes.Row[]
    local note_rows = {}

    local function show_mode ()
      local open = current ~= nil
      page:show (open)
      empty:show (not open)
      text:show (open and not preview)
      pv:show (open and preview)
      if open and preview then
        pv:html (app.util.markdown (text:value ()))
      end
    end

    ---@param s string
    ---@return integer
    local function count_words (s)
      local n = 0
      for _ in s:gmatch ('%S+') do
        n = n + 1
      end
      return n
    end

    local function save_now ()
      if save_timer then
        save_timer ()
        save_timer = nil
      end
      if not current then
        return
      end
      local body = text:value () or ''
      if body ~= (app.fs.read (path_of (current)) or '') then
        app.fs.write (path_of (current), body)
        bump (current)
      end
      if st_saved then
        st_saved.set ('Saved')
      end
      render_list ()
    end

    ---@param id string?
    local function open (id)
      save_now ()
      current = id
      app.store.set ('last', id)
      text:value (id and (app.fs.read (path_of (id)) or '') or '')
      if st_words then
        st_words.set (count_words (text:value ()) .. ' words')
      end
      if st_saved then
        st_saved.set ('')
      end
      show_mode ()
      render_list ()
      if id and not preview then
        text:focus ()
      end
    end

    text:on ('input', function ()
      if st_saved then
        st_saved.set ('Editing…')
      end
      if st_words then
        st_words.set (count_words (text:value ()) .. ' words')
      end
      if save_timer then
        save_timer ()
      end
      save_timer = app.timer.after (400, save_now)
    end)

    render_list = function ()
      ---@type Proteus.El[]
      local rows = {}
      note_rows = {}
      for _, id in ipairs (all_ids ()) do
        local body = app.fs.read (path_of (id)) or ''
        if query == '' or body:lower ():find (query:lower (), 1, true) then
          local row = ui.div ({
            class = 'note-row' .. (id == current and ' active' or ''),
            ui.div ({ class = 't', title_of (body) }),
            ui.div ({ class = 's', snippet_of (body) }),
          })
          row:on ('click', function ()
            open (id)
          end)
          rows[#rows + 1] = row
          note_rows[#note_rows + 1] = { row = row, id = id }
        end
      end
      if #rows == 0 then
        rows[1] = ui.div ({
          class = 'ui-empty',
          query == '' and 'No notes yet' or 'Nothing matches',
        })
      end
      list:set_children (rows)
    end

    ---@param body string?
    local function new_note (body)
      local id = 'note-' .. app.util.now ()
      app.fs.write (path_of (id), body or '')
      bump (id)
      preview = false
      open (id)
    end

    local search = ui.input ({
      class = 'notes-search',
      placeholder = 'Search notes',
      oninput = function (ev)
        query = ev.value or ''
        render_list ()
      end,
    })

    views.add ('left', {
      id = 'notes',
      title = 'Notes',
      icon = 'notebook-pen',
      order = 1,
      content = ui.div ({ class = 'notes-side', search, list }),
    })

    -- Notes changed elsewhere (for example in the editor profile) show up here.
    ---@param path string
    app.on ('fs:changed', function (path)
      if not path:match ('^' .. DIR) then
        return
      end
      render_list ()
    end)

    commands.register ({
      id = 'notes.new',
      category = 'Notes',
      title = 'New Note',
      key = 'ctrl+n',
      icon = 'square-pen',
      toolbar = 1,
      run = function ()
        new_note ('')
      end,
    })
    ---@param id string
    local function delete_note (id)
      local function go ()
        if current == id then
          save_now ()
          current = nil
        end
        app.fs.remove (path_of (id))
        if current == nil then
          open (all_ids ()[1])
        else
          render_list ()
        end
      end
      local picker = app.try_use ('picker')
      local title = title_of (app.fs.read (path_of (id)) or '')
      if picker then
        picker.confirm ({
          message = 'Delete "' .. title .. '"?',
          yes = 'Delete',
          on_yes = go,
        })
      else
        go ()
      end
    end

    commands.register ({
      id = 'notes.delete',
      category = 'Notes',
      title = 'Delete Note',
      icon = 'trash-2',
      toolbar = 2,
      when = function ()
        return current ~= nil
      end,
      run = function ()
        if current then
          delete_note (current)
        end
      end,
    })

    local menus = app.try_use ('menus')
    if menus then
      menus.attach (list, function (ev)
        for _, nr in ipairs (note_rows) do
          if app.dom.contains (nr.row.id, ev.target) then
            return {
              {
                label = 'Open',
                icon = 'file-text',
                run = function ()
                  open (nr.id)
                end,
              },
              {
                label = 'New Note',
                icon = 'square-pen',
                run = function ()
                  new_note ('')
                end,
              },
              { separator = true },
              {
                label = 'Delete',
                icon = 'trash-2',
                danger = true,
                run = function ()
                  delete_note (nr.id)
                end,
              },
            }
          end
        end
        return {
          {
            label = 'New Note',
            icon = 'square-pen',
            run = function ()
              new_note ('')
            end,
          },
        }
      end)
    end
    commands.register ({
      id = 'notes.preview',
      category = 'Notes',
      title = 'Toggle Preview',
      key = 'ctrl+e',
      icon = 'eye',
      toolbar = 3,
      when = function ()
        return current ~= nil
      end,
      run = function ()
        save_now ()
        preview = not preview
        show_mode ()
      end,
    })
    commands.register ({
      id = 'notes.search',
      category = 'Notes',
      title = 'Search Notes',
      key = 'ctrl+shift+f',
      icon = 'search',
      toolbar = 4,
      run = function ()
        views.show ('notes')
        search:focus ()
      end,
    })
    commands.register ({
      id = 'notes.theme',
      category = 'Notes',
      title = 'Change Theme',
      icon = 'palette',
      toolbar = 90,
      toolbar_align = 'right',
      run = function ()
        commands.run ('theme.choose')
      end,
    })
    commands.register ({
      id = 'notes.switch_app',
      category = 'Notes',
      title = 'Switch App',
      icon = 'layers',
      toolbar = 91,
      toolbar_align = 'right',
      run = function ()
        commands.run ('profile.switch')
      end,
    })

    app.dispose (save_now)

    if #all_ids () == 0 then
      app.fs.write (path_of ('welcome'), WELCOME)
    end
    ---@type string?
    local last = app.store.get ('last')
    if last and app.fs.exists (path_of (last)) then
      open (last)
    else
      open (all_ids ()[1])
    end
  end,
}
