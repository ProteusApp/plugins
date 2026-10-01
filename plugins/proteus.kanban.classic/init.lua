-- proteus.kanban.classic: a kanban board, written by hand. The kanban profile runs proteus.kanban,
-- the same app built as a Nodal graph. Cards sit in columns and move along as work moves.
--
-- Each board is a JSON file in data/kanban/, so the editor profile can open it too. The board
-- logic lives in kanban_board.lua, where the tests reach it. This file draws the board, drags
-- cards and columns with the mouse, edits a card in the right dock, and saves a moment after
-- each change.
--
-- Cards are real elements rather than one HTML string, because a drag reads where each card
-- sits with el:rect(). Each column keeps its elements and redraws only the cards that changed,
-- so typing in the card panel stays quick.

local m = require ('kanban_board') --[[@as Kanban.BoardModule]]

local DIR = 'data/kanban'
local TAB_ID = 'kanban'
local PANEL_ID = 'kanban.card'
local BOARDS_ID = 'kanban.boards'
local SAVE_DELAY = 500
-- The pointer moves this far before a press turns into a drag, so a click still opens a card.
local DRAG_START = 4

-- lang=css
local CSS = [[
.kanban-c-red { --kanban-c: var(--kanban-red, #d9443f); }
.kanban-c-orange { --kanban-c: var(--kanban-orange, #d0621a); }
.kanban-c-yellow { --kanban-c: var(--kanban-yellow, #a07f00); }
.kanban-c-green { --kanban-c: var(--kanban-green, #2e8f55); }
.kanban-c-blue { --kanban-c: var(--kanban-blue, #2f73d4); }
.kanban-c-purple { --kanban-c: var(--kanban-purple, #8752c9); }

.kanban { flex: 1; display: flex; flex-direction: column; height: 100%; min-height: 0; background: var(--bg);
  color: var(--fg); font-family: var(--font-ui); }
.kanban-head { flex: none; display: flex; align-items: center; gap: 10px; padding: 10px 16px;
  border-bottom: 1px solid var(--border); }
.kanban-title { margin: 0; padding: 2px 6px; min-width: 0; font-size: 17px; font-weight: 600;
  white-space: nowrap; overflow: hidden; text-overflow: ellipsis; border-radius: var(--radius); cursor: default; }
.kanban-title:hover { background: var(--bg-hover); }
.kanban-title-input { width: 280px; font-size: 16px; font-weight: 600; }
.kanban-spacer { flex: 1; }
.kanban-search-wrap { position: relative; display: flex; align-items: center; }
.kanban-search-wrap > .ui-icon { position: absolute; left: 9px; color: var(--fg-faint); pointer-events: none; }
.kanban-search { width: 230px; padding-left: 29px; }
.kanban-filter { width: 150px; }

.kanban-row { flex: 1; min-height: 0; display: flex; align-items: flex-start; gap: 12px;
  padding: 14px 16px 16px; overflow-x: auto; overflow-y: hidden; }
.kanban-col { flex: none; width: 272px; max-height: 100%; display: flex; flex-direction: column;
  background: var(--bg-alt); border: 1px solid var(--border); border-radius: calc(var(--radius) + 4px); }
.kanban-col.kanban-over { border-top: 3px solid var(--warning); }
.kanban-col-head { flex: none; display: flex; align-items: center; gap: 6px; padding: 8px 6px 6px 12px;
  cursor: grab; user-select: none; }
.kanban-col-title { flex: 1; min-width: 0; font-weight: 600; white-space: nowrap; overflow: hidden;
  text-overflow: ellipsis; }
.kanban-count { flex: none; padding: 0 7px; border-radius: 9px; font-size: 11px; line-height: 18px;
  background: var(--bg-active); color: var(--fg-muted); }
.kanban-over .kanban-col-title, .kanban-over .kanban-count { color: var(--warning); }
.kanban-over .kanban-count { background: color-mix(in srgb, var(--warning) 16%, transparent); font-weight: 600; }
.kanban-menu { flex: none; display: inline-grid; place-items: center; width: 26px; height: 24px; border: none;
  border-radius: var(--radius); background: transparent; color: var(--fg-muted); cursor: pointer; }
.kanban-menu:hover { background: var(--bg-hover); color: var(--fg); }
.kanban-col-input { flex: 1; font-weight: 600; }
.kanban-cards { flex: 0 1 auto; min-height: 6px; overflow-y: auto; display: flex; flex-direction: column;
  gap: 8px; padding: 2px 8px 4px; }

.kanban-card { flex: none; padding: 8px 10px; border: 1px solid var(--border); border-radius: var(--radius);
  background: var(--bg-elev); cursor: pointer; user-select: none; }
.kanban-card:hover { border-color: var(--fg-faint); }
.kanban-card.kanban-selected { border-color: var(--accent); box-shadow: 0 0 0 1px var(--accent); }
.kanban-card.kanban-dim { opacity: .3; }
.kanban-hidden { display: none !important; }
.kanban-card-title { line-height: 1.4; white-space: pre-wrap; overflow-wrap: anywhere; }
.kanban-labels { display: flex; flex-wrap: wrap; gap: 4px; margin-bottom: 6px; }
.kanban-chip { max-width: 100%; padding: 0 7px; border-radius: 8px; font-size: 11px; font-weight: 600;
  line-height: 17px; color: #fff; background: var(--kanban-c); white-space: nowrap; overflow: hidden;
  text-overflow: ellipsis; }
.kanban-bar { width: 36px; height: 7px; border-radius: 4px; background: var(--kanban-c); }
.kanban-meta { display: flex; align-items: center; gap: 8px; margin-top: 7px; font-size: 11.5px;
  color: var(--fg-faint); }
.kanban-due { display: inline-flex; align-items: center; gap: 4px; padding: 1px 6px; border-radius: 4px; }
.kanban-due-overdue { color: var(--danger); background: color-mix(in srgb, var(--danger) 14%, transparent);
  font-weight: 600; }
.kanban-due-soon { color: var(--warning); background: color-mix(in srgb, var(--warning) 16%, transparent);
  font-weight: 600; }
.kanban-due-later { color: var(--fg-faint); }
.kanban-has-notes { display: inline-flex; color: var(--fg-faint); }

.kanban-foot { flex: none; padding: 4px 8px 8px; }
.kanban-add { width: 100%; justify-content: flex-start; color: var(--fg-muted); }
.kanban-add-input { width: 100%; resize: none; line-height: 1.4; background: var(--bg-elev); }
.kanban-add-actions { display: flex; align-items: center; gap: 6px; margin-top: 6px; }
.kanban-icon-button { padding: 4px 6px; }
.kanban-addcol { flex: none; width: 272px; }
.kanban-addcol-button { width: 100%; justify-content: flex-start; padding: 9px 12px;
  border: 1px dashed var(--border); color: var(--fg-muted); }
.kanban-addcol-input { width: 100%; }

.kanban-placeholder { flex: none; border: 1px dashed var(--fg-faint); border-radius: var(--radius);
  background: var(--bg-active); }
.kanban-col-placeholder { flex: none; border: 1px dashed var(--fg-faint);
  border-radius: calc(var(--radius) + 4px); background: var(--bg-active); }
.kanban-ghost { position: fixed; left: 0; top: 0; z-index: 2500; margin: 0; pointer-events: none;
  border-color: var(--accent); box-shadow: var(--shadow); font-family: var(--font-ui); font-size: var(--font-size); }
.kanban-col-ghost { position: fixed; left: 0; top: 0; z-index: 2500; pointer-events: none; color: var(--fg);
  background: var(--bg-alt); border: 1px solid var(--accent); border-radius: calc(var(--radius) + 4px);
  box-shadow: var(--shadow); font-family: var(--font-ui); font-size: var(--font-size); }
.kanban-col-ghost-body { padding: 4px 12px 14px; color: var(--fg-muted); }
.kanban.kanban-dragging, .kanban.kanban-dragging * { cursor: grabbing !important; user-select: none !important; }

.kanban-empty { margin: auto; max-width: 420px; display: flex; flex-direction: column; align-items: center;
  gap: 10px; padding: 40px; text-align: center; color: var(--fg-muted); }
.kanban-empty > .ui-icon { color: var(--fg-faint); }
.kanban-empty-title { font-size: 16px; font-weight: 600; color: var(--fg); }

.kanban-side { display: flex; flex-direction: column; height: 100%; }
.kanban-side-bar { flex: none; padding: 8px 8px 2px; }
.kanban-boards { flex: 1; overflow: auto; padding: 4px 6px 10px; }
.kanban-board-row { display: flex; align-items: center; gap: 8px; padding: 7px 10px; border-radius: var(--radius);
  cursor: pointer; }
.kanban-board-row:hover { background: var(--bg-hover); }
.kanban-board-row.kanban-active { background: var(--bg-active); }
.kanban-board-row > .icon { color: var(--fg-muted); }
.kanban-board-name { flex: 1; min-width: 0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.kanban-board-count { font-size: 11px; color: var(--fg-muted); }
.kanban-boards .ui-button { margin-top: 12px; }

.kanban-panel { display: flex; flex-direction: column; gap: 16px; padding: 14px 14px 20px; }
.kanban-p-top { display: flex; align-items: flex-start; gap: 6px; }
.kanban-p-title { flex: 1; padding: 6px 8px; font-size: 17px; font-weight: 600; }
.kanban-p-field { display: flex; flex-direction: column; gap: 6px; }
.kanban-p-label { font-size: 11px; font-weight: 600; letter-spacing: .04em; text-transform: uppercase;
  color: var(--fg-muted); }
.kanban-p-row { display: flex; align-items: center; justify-content: space-between; gap: 6px; }
.kanban-p-select { width: 100%; }
.kanban-p-labels { display: flex; flex-wrap: wrap; gap: 6px; }
.kanban-toggle { display: inline-flex; align-items: center; gap: 6px; max-width: 100%; padding: 3px 10px 3px 7px;
  border: 1px solid var(--border); border-radius: 13px; background: var(--bg); color: var(--fg); font-size: 12px;
  cursor: pointer; }
.kanban-toggle:hover { border-color: var(--fg-faint); }
.kanban-toggle.kanban-on { border-color: var(--kanban-c); font-weight: 600;
  background: color-mix(in srgb, var(--kanban-c) 18%, var(--bg)); }
.kanban-swatch { flex: none; width: 12px; height: 12px; border-radius: 50%; background: var(--kanban-c); }
.kanban-p-due-row { display: flex; align-items: center; gap: 6px; }
.kanban-p-due { flex: 1; }
.kanban-p-notes { width: 100%; min-height: 180px; resize: vertical; line-height: 1.5; }
.kanban-p-preview { min-height: 60px; overflow-wrap: anywhere; }
.kanban-small { padding: 2px 8px; font-size: 12px; }
.kanban-p-foot { display: flex; align-items: center; justify-content: space-between; gap: 8px; padding-top: 12px;
  border-top: 1px solid var(--border); }
.kanban-p-created { font-size: 12px; color: var(--fg-faint); }
]]

---What the board keeps for one column on screen.
---@class Kanban.ColView
---@field id string
---@field el Proteus.El
---@field head Proteus.El
---@field list Proteus.El
---@field foot Proteus.El
---@field add_btn Proteus.El
---@field box? Proteus.El The open "Add a card" box.
---@field input? Proteus.El The text area in that box.
---@field column? Kanban.Column The column as last drawn.
---@field head_html string
---@field cards table<string, Proteus.El> Card elements by card id.
---@field drawn table<string, Kanban.Card> Each card as last drawn.
---@field dimmed table<string, boolean>
---@field order string[] Card ids as drawn.
---@field renaming boolean

---A mouse press on a card or a column header, before it turns into a drag.
---@class Kanban.Press
---@field kind 'card'|'column'
---@field id string
---@field off fun() Stops listening to the mouse.

---A column as a card drag sees it, measured once when the drag starts.
---@class Kanban.DragColumn
---@field id string
---@field view Kanban.ColView
---@field top number
---@field bottom number
---@field cards Kanban.Span[] The other cards, top to bottom.
---@field ids string[] Their ids.
---@field scroll0 number The list's scroll position when the drag started.

---A card or a column on the move.
---@class Kanban.Drag
---@field kind 'card'|'column'
---@field id string
---@field ghost Proteus.El The copy that follows the pointer.
---@field placeholder Proteus.El The gap where the item will land.
---@field source Proteus.El The item itself, hidden while it moves.
---@field dx number
---@field dy number
---@field x number
---@field y number
---@field tilt string
---@field row_rect Proteus.Rect
---@field scroll0 number The board's sideways scroll when the drag started.
---@field spans Kanban.Span[] Every column across for a card, or the other columns for a column.
---@field cols Kanban.DragColumn[] For a card drag.
---@field ids string[] The other columns, for a column drag.
---@field target? integer The column the card would land in.
---@field index? integer Where the item would land.
---@field stop fun()

---@type Proteus.Plugin
return {
  name = 'Kanban (classic)',
  description = 'Cards in columns, dragged along as work moves.',
  version = '1.0.0',
  -- Boards live in data/kanban, beside the ones the Kanban graph app keeps.
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
    'proteus.ui.tabs',
  },
  activate = function (app)
    local ui = app.use ('ui')
    local shell = app.use ('shell')
    local views = app.use ('views')
    local commands = app.use ('commands')
    local tabs = app.try_use ('tabs')
    local status = app.try_use ('status')
    local menus = app.try_use ('menus')
    local picker = app.try_use ('picker')
    local notify = app.try_use ('notify')
    ui.css (CSS)

    local esc = app.util.escape
    local ICON_DUE = app.util.icon ('calendar', 12) or ''
    local ICON_NOTES = app.util.icon ('text-align-start', 13) or ''
    local ICON_MENU = app.util.icon ('ellipsis', 16) or ''
    local ICON_BOARD = app.util.icon ('square-kanban', 15) or ''

    -- State ---------------------------------------------------------------------------------

    local path = nil ---@type string?
    local history = nil ---@type Kanban.History?
    local last_text = nil ---@type string? What the open board's file held when last read or written.
    local selected = nil ---@type string?
    local panel_card = nil ---@type string?
    local query = ''
    local filter = '' -- A label id, or empty for every card.
    local today = os.date ('%Y-%m-%d') --[[@as string]]
    local save_timer = nil ---@type fun()?
    -- True while this plugin changes files itself, so its own changes do not reload the board.
    local own_write = false
    local seq = 0
    local drag = nil ---@type Kanban.Drag?
    local press = nil ---@type Kanban.Press?
    local preview = false
    local drafts = {} ---@type table<string, string>
    local col_views = {} ---@type table<string, Kanban.ColView>
    local drawn_order = {} ---@type string[]
    local drawn_labels = nil ---@type Kanban.Label[]?
    local drawn_today = nil ---@type string?
    local drawn_title = nil ---@type string?
    local filter_labels = nil ---@type Kanban.Label[]?
    local shown = nil ---@type boolean?
    local tab = nil ---@type Proteus.Tab?

    ---@return string
    local function new_id ()
      seq = seq + 1
      return string.format ('%x-%x', math.floor (app.util.now ()), seq)
    end

    ---@return Kanban.Board?
    local function current ()
      return history and history.present or nil
    end

    ---True while the user types in a field, so keys such as Delete and Ctrl+Z stay theirs.
    ---@return boolean
    local function typing ()
      return app.dom.focus_info ().editable
    end

    ---True when the board is what the user sees. Inside the editor, another tab may be in front.
    ---@return boolean
    local function on_screen ()
      if not tabs then
        return true
      end
      local active = tabs.active ()
      return active ~= nil and active.id == TAB_ID
    end

    ---@return boolean
    local function ready ()
      return current () ~= nil and on_screen ()
    end

    ---@return boolean
    local function card_ready ()
      return selected ~= nil and ready () and not typing ()
    end

    ---@param kind 'info'|'success'|'warn'|'error'
    ---@param text string
    local function tell (kind, text)
      if not notify then
        app.log (text)
      elseif kind == 'error' then
        notify.error (text)
      elseif kind == 'warn' then
        notify.warn (text)
      elseif kind == 'success' then
        notify.success (text)
      else
        notify.info (text)
      end
    end

    ---@param message string
    ---@param yes string
    ---@param fn fun()
    local function confirm (message, yes, fn)
      if picker then
        picker.confirm ({ message = message, yes = yes, on_yes = fn })
      else
        fn ()
      end
    end

    ---@param opts Proteus.InputOptions
    local function ask (opts)
      if picker then
        picker.input (opts)
      elseif opts.on_submit then
        opts.on_submit (opts.value or '')
      end
    end

    ---@param n integer
    ---@return string
    local function cards_text (n)
      return n .. (n == 1 and ' card' or ' cards')
    end

    ---A number property of an element, such as its scroll position.
    ---@param el Proteus.El
    ---@param prop string
    ---@return number
    local function num (el, prop)
      return tonumber (el:get (prop)) or 0
    end

    -- Files ---------------------------------------------------------------------------------

    ---@param name string A file name without the folder or `.json`.
    ---@return string
    local function path_for (name)
      return DIR .. '/' .. name .. '.json'
    end

    ---Board files, sorted by name.
    ---@return string[]
    local function board_paths ()
      local out = {} ---@type string[]
      for _, e in ipairs (app.fs.list (DIR)) do
        if not e.dir and e.name:match ('%.json$') then
          out[#out + 1] = e.path
        end
      end
      table.sort (out, function (a, b)
        return a:lower () < b:lower ()
      end)
      return out
    end

    ---File names in use, in lower case, leaving out `except`.
    ---@param except? string
    ---@return table<string, boolean>
    local function taken_names (except)
      local out = {} ---@type table<string, boolean>
      for _, p in ipairs (board_paths ()) do
        local name = p:match ('([^/]+)%.json$')
        if p ~= except and name then
          out[name:lower ()] = true
        end
      end
      return out
    end

    ---Reads a board file. Returns nil and a reason when it cannot.
    ---@param p string
    ---@return Kanban.Board?
    ---@return string? err
    ---@return string? text
    local function read_board (p)
      local text = app.fs.read (p)
      if not text then
        return nil, 'The file is missing.'
      end
      local ok, raw = pcall (app.json.decode, text)
      if not ok then
        return nil, 'The file is not valid JSON.'
      end
      return m.normalize (raw, new_id), nil, text
    end

    ---Writes a file, and shows a failure instead of raising it.
    ---@param p string
    ---@param text string
    ---@return boolean
    local function write (p, text)
      own_write = true
      local ok, err = pcall (app.fs.write, p, text)
      own_write = false
      if not ok then
        tell ('error', 'Could not save ' .. p .. ': ' .. tostring (err))
      end
      return ok
    end

    ---@param from string
    ---@param to string
    ---@return boolean
    local function rename_file (from, to)
      own_write = true
      local ok, err = pcall (app.fs.rename, from, to)
      own_write = false
      if not ok then
        tell ('error', 'Could not rename ' .. from .. ': ' .. tostring (err))
      end
      return ok
    end

    local function save_now ()
      if save_timer then
        save_timer ()
        save_timer = nil
      end
      local board = current ()
      if not path or not board then
        return
      end
      -- The file name follows the board's title, as long as no other board has that name.
      local name = m.file_name (board.title)
      local want = path_for (name)
      if
        want ~= path
        and not taken_names (path)[name:lower ()]
        and rename_file (path, want)
      then
        path = want
        app.store.set ('last', want)
      end
      local text = m.encode (board)
      if text ~= last_text and write (path, text) then
        last_text = text
      end
    end

    local function schedule_save ()
      if save_timer then
        save_timer ()
      end
      save_timer = app.timer.after (SAVE_DELAY, save_now)
    end

    -- Screen parts --------------------------------------------------------------------------

    local title_el = ui.h2 ({
      class = 'kanban-title',
      title = 'Double-click to rename the board',
    })
    local search = ui.input ({
      class = 'kanban-search',
      placeholder = 'Search cards',
      title = 'Search titles, notes and labels (Ctrl+F)',
    })
    local filter_el = ui.h ('select', {
      class = 'ui-input kanban-filter',
      title = 'Show only cards with this label',
    })
    local head = ui.div ({
      class = 'kanban-head',
      title_el,
      ui.div ({ class = 'kanban-spacer' }),
      ui.div ({ class = 'kanban-search-wrap', ui.icon ('search', 14), search }),
      filter_el,
    })
    local addcol = ui.div ({ class = 'kanban-addcol' })
    local row = ui.div ({ class = 'kanban-row', addcol })
    local empty = ui.div ({
      class = 'kanban-empty',
      ui.icon ('square-kanban', 40),
      ui.div ({ class = 'kanban-empty-title', 'No board open' }),
      ui.div ({
        'A board holds cards in columns, such as To do, Doing and Done.',
      }),
      ui.button ({
        'New Board',
        icon = 'plus',
        variant = 'primary',
        onclick = function ()
          commands.run ('kanban.new_board')
        end,
      }),
    })
    local root = ui.div ({ class = 'kanban', head, row, empty })

    local st_cards = status
      and status.add ({
        id = 'kanban.cards',
        text = '',
        icon = 'square-kanban',
        align = 'right',
        order = 10,
      })
    local st_due = status
      and status.add ({
        id = 'kanban.overdue',
        text = '',
        icon = 'calendar-x',
        tooltip = 'Cards past their due date',
        align = 'right',
        order = 11,
      })

    -- Functions defined further down.
    local render ---@type fun(full?: boolean)
    local refresh ---@type fun(full?: boolean)
    local refresh_panel ---@type fun(force?: boolean)
    local open_card ---@type fun(id: string)
    local close_panel ---@type fun()
    local open_add ---@type fun(id: string)
    local render_boards_soon ---@type fun()
    local rename_column_inline ---@type fun(id: string)

    -- Drawing -------------------------------------------------------------------------------

    ---A label's own name, which is empty until the user names it.
    ---@param board Kanban.Board
    ---@param id string
    ---@return string
    local function own_name (board, id)
      for _, label in ipairs (board.labels) do
        if label.id == id then
          return label.name
        end
      end
      return ''
    end

    ---@param card Kanban.Card
    ---@param board Kanban.Board
    ---@return string
    local function card_html (card, board)
      local parts = {} ---@type string[]
      if #card.labels > 0 then
        parts[#parts + 1] = '<div class="kanban-labels">'
        for _, id in ipairs (card.labels) do
          local name = own_name (board, id)
          if name ~= '' then
            parts[#parts + 1] = '<span class="kanban-chip kanban-c-'
              .. id
              .. '" title="'
              .. esc (name)
              .. '">'
              .. esc (name)
              .. '</span>'
          else
            parts[#parts + 1] = '<span class="kanban-bar kanban-c-'
              .. id
              .. '" title="'
              .. esc (m.LABEL_COLOURS[id] or id)
              .. '"></span>'
          end
        end
        parts[#parts + 1] = '</div>'
      end
      parts[#parts + 1] = '<div class="kanban-card-title">'
        .. esc (card.title)
        .. '</div>'
      local has_notes = card.notes:match ('%S') ~= nil
      if card.due or has_notes then
        parts[#parts + 1] = '<div class="kanban-meta">'
        if card.due then
          parts[#parts + 1] = '<span class="kanban-due kanban-due-'
            .. (m.due_state (card, today) or 'later')
            .. '" title="Due '
            .. esc (card.due)
            .. '">'
            .. ICON_DUE
            .. esc (m.due_label (card.due, today))
            .. '</span>'
        end
        if has_notes then
          parts[#parts + 1] = '<span class="kanban-has-notes" title="This card has notes">'
            .. ICON_NOTES
            .. '</span>'
        end
        parts[#parts + 1] = '</div>'
      end
      return table.concat (parts)
    end

    ---@param column Kanban.Column
    ---@return string
    local function head_html (column)
      local id = esc (column.id)
      local count = tostring (#column.cards)
      local tip = 'Cards in this column'
      if column.limit then
        count = count .. ' / ' .. column.limit
        tip = 'Cards, and the most this column should hold'
      end
      return '<span class="kanban-col-title" data-item="title:'
        .. id
        .. '" title="Double-click to rename">'
        .. esc (column.title)
        .. '</span><span class="kanban-count" title="'
        .. tip
        .. '">'
        .. count
        .. '</span><button class="kanban-menu" data-item="menu:'
        .. id
        .. '" title="Column actions">'
        .. ICON_MENU
        .. '</button>'
    end

    ---Splits a `data-item` such as `card:abc` into its kind and id.
    ---@param item string?
    ---@return string? kind
    ---@return string id
    local function parse (item)
      if not item then
        return nil, ''
      end
      local kind, id = item:match ('^(%a+):(.*)$')
      return kind, id or ''
    end

    ---@param id string
    ---@return Kanban.ColView
    local function make_view (id)
      local head_el = ui.div ({
        class = 'kanban-col-head',
        ['data-item'] = 'head:' .. id,
      })
      local list =
        ui.div ({ class = 'kanban-cards', ['data-item'] = 'list:' .. id })
      local add_btn = ui.button ({
        'Add a card',
        icon = 'plus',
        variant = 'ghost',
        class = 'kanban-add',
        onclick = function ()
          open_add (id)
        end,
      })
      local foot = ui.div ({
        class = 'kanban-foot',
        ['data-item'] = 'foot:' .. id,
        add_btn,
      })
      ---@type Kanban.ColView
      local view = {
        id = id,
        el = ui.div ({
          class = 'kanban-col',
          ['data-item'] = 'col:' .. id,
          head_el,
          list,
          foot,
        }),
        head = head_el,
        list = list,
        foot = foot,
        add_btn = add_btn,
        head_html = '',
        cards = {},
        drawn = {},
        dimmed = {},
        order = {},
        renaming = false,
      }
      col_views[id] = view
      return view
    end

    ---@param view Kanban.ColView
    ---@param card Kanban.Card
    ---@param board Kanban.Board
    ---@return Proteus.El
    local function make_card (view, card, board)
      local dim = not m.matches (card, query, board.labels, filter)
      local cls = 'kanban-card'
      if card.id == selected then
        cls = cls .. ' kanban-selected'
      end
      if dim then
        cls = cls .. ' kanban-dim'
      end
      local el = ui.div ({
        class = cls,
        ['data-item'] = 'card:' .. card.id,
        html = card_html (card, board),
      })
      view.cards[card.id] = el
      view.drawn[card.id] = card
      view.dimmed[card.id] = dim
      return el
    end

    ---@param view Kanban.ColView
    ---@param column Kanban.Column
    ---@param board Kanban.Board
    ---@param full boolean
    local function draw_column (view, column, board, full)
      local ids = {} ---@type string[]
      for i, card in ipairs (column.cards) do
        ids[i] = card.id
      end
      local same = not full
        and view.column ~= nil
        and table.concat (ids, '\n') == table.concat (view.order, '\n')
      view.column = column
      view.el:class ('kanban-over', m.over_limit (column))
      if not view.renaming then
        local html = head_html (column)
        if html ~= view.head_html then
          view.head_html = html
          view.head:html (html)
        end
      end
      if same then
        -- The same cards in the same order: swap only the cards that changed.
        for _, card in ipairs (column.cards) do
          if view.drawn[card.id] ~= card then
            local old = view.cards[card.id]
            view.list:insert_before (make_card (view, card, board), old)
            if old then
              old:remove ()
            end
          end
        end
        return
      end
      view.list:clear ()
      view.cards, view.drawn, view.dimmed, view.order = {}, {}, {}, ids
      for _, card in ipairs (column.cards) do
        view.list:append (make_card (view, card, board))
      end
    end

    ---@param id string
    ---@return Proteus.El?
    local function card_el (id)
      for _, view in pairs (col_views) do
        local el = view.cards[id]
        if el then
          return el
        end
      end
      return nil
    end

    ---@param id string?
    local function select_card (id)
      if selected == id then
        return
      end
      local old = selected and card_el (selected)
      if old then
        old:class ('kanban-selected', false)
      end
      selected = id
      local el = id and card_el (id)
      if el then
        el:class ('kanban-selected', true)
        el:scroll_into_view ()
      end
    end

    ---Dims the cards the search or the label filter leaves out.
    local function apply_dim ()
      local board = current ()
      if not board then
        return
      end
      for _, column in ipairs (board.columns) do
        local view = col_views[column.id]
        if view then
          for _, card in ipairs (column.cards) do
            local dim = not m.matches (card, query, board.labels, filter)
            local el = view.cards[card.id]
            if el and view.dimmed[card.id] ~= dim then
              view.dimmed[card.id] = dim
              el:class ('kanban-dim', dim)
            end
          end
        end
      end
    end

    ---@param board Kanban.Board
    local function draw_filter (board)
      if board.labels == filter_labels then
        return
      end
      filter_labels = board.labels
      local parts = { '<option value="">All labels</option>' }
      for _, id in ipairs (m.LABELS) do
        parts[#parts + 1] = '<option value="'
          .. id
          .. '"'
          .. (filter == id and ' selected' or '')
          .. '>'
          .. esc (m.label_name (board.labels, id))
          .. '</option>'
      end
      filter_el:html (table.concat (parts))
    end

    render = function (full)
      local board = current ()
      if shown ~= (board ~= nil) then
        shown = board ~= nil
        empty:show (not shown)
        head:show (shown)
        row:show (shown)
      end
      if not board then
        for key, view in pairs (col_views) do
          view.el:remove ()
          col_views[key] = nil
        end
        drawn_order, drawn_title = {}, nil
        return
      end
      -- New label names and a new day change how every card looks.
      if board.labels ~= drawn_labels or today ~= drawn_today then
        full = true
      end
      drawn_labels, drawn_today = board.labels, today
      if board.title ~= drawn_title then
        drawn_title = board.title
        title_el:text (board.title)
        if tab then
          tab.set_title (board.title)
        end
      end
      draw_filter (board)
      local keep = {} ---@type table<string, boolean>
      local order = {} ---@type string[]
      for _, column in ipairs (board.columns) do
        keep[column.id] = true
        order[#order + 1] = column.id
        local view = col_views[column.id] or make_view (column.id)
        if full or view.column ~= column then
          draw_column (view, column, board, full == true)
        end
      end
      for key, view in pairs (col_views) do
        if not keep[key] then
          view.el:remove ()
          col_views[key] = nil
        end
      end
      if table.concat (order, '\n') ~= table.concat (drawn_order, '\n') then
        for _, key in ipairs (order) do
          row:insert_before (col_views[key].el, addcol)
        end
        drawn_order = order
      end
    end

    local function update_status ()
      if not st_cards or not st_due then
        return
      end
      local board = current ()
      st_cards.show (board ~= nil)
      st_due.show (board ~= nil)
      if not board then
        return
      end
      local counts = m.counts (board, today)
      st_cards.set (cards_text (counts.cards))
      st_due.set (counts.overdue .. ' overdue')
      st_due.accent (counts.overdue > 0)
    end

    refresh = function (full)
      local board = current ()
      if board and selected and not m.find_card (board, selected) then
        selected = nil
      end
      render (full)
      if panel_card and not (board and m.find_card (board, panel_card)) then
        close_panel ()
      else
        refresh_panel ()
      end
      update_status ()
      render_boards_soon ()
    end

    -- Changes -------------------------------------------------------------------------------

    ---Makes `board` the present board, as one undo step, and saves it soon.
    ---@param board Kanban.Board
    ---@param merge? string Changes with the same key make one step, such as typing a title.
    local function commit (board, merge)
      if history and m.history_push (history, board, merge) then
        refresh ()
        schedule_save ()
      end
    end

    local function undo ()
      if history and m.history_undo (history) then
        refresh ()
        schedule_save ()
      end
    end

    local function redo ()
      if history and m.history_redo (history) then
        refresh ()
        schedule_save ()
      end
    end

    ---@param direction Kanban.Direction
    local function nudge (direction)
      local board = current ()
      if not board or not selected then
        return
      end
      commit (m.nudge (board, selected, direction))
      local el = card_el (selected)
      if el then
        el:scroll_into_view ()
      end
    end

    -- The "Add a card" box ------------------------------------------------------------------

    ---@param view Kanban.ColView
    ---@param keep_draft boolean
    local function close_add (view, keep_draft)
      local box, input = view.box, view.input
      if not box or not input then
        return
      end
      view.box, view.input = nil, nil
      local text = input:value () or ''
      drafts[view.id] = (keep_draft and text ~= '') and text or nil
      box:remove ()
      view.add_btn:show (true)
    end

    open_add = function (id)
      local view = col_views[id]
      if not current () or not view then
        return
      end
      for _, other in pairs (col_views) do
        if other ~= view then
          close_add (other, true)
        end
      end
      if view.input then
        view.input:focus ()
        return
      end
      local input = ui.input ({
        multiline = true,
        class = 'kanban-add-input',
        placeholder = 'Card title',
        rows = 2,
      })
      input:value (drafts[id] or '')

      local function submit ()
        local board = current ()
        if not board then
          return
        end
        local next_board, card_id =
          m.add_card (board, id, input:value () or '', new_id, app.util.now ())
        if card_id then
          drafts[id] = nil
          input:value ('')
          commit (next_board)
          view.list:set ('scrollTop', num (view.list, 'scrollHeight'))
        end
        input:focus ()
      end

      local box = ui.div ({
        class = 'kanban-add-box',
        input,
        ui.div ({
          class = 'kanban-add-actions',
          ui.button ({
            'Add card',
            variant = 'primary',
            -- Keeping focus in the box stops it closing before the click lands.
            onmousedown = function ()
              return true
            end,
            onclick = submit,
          }),
          ui.button ({
            ui.icon ('x', 16),
            variant = 'ghost',
            class = 'kanban-icon-button',
            title = 'Close (Escape)',
            onmousedown = function ()
              return true
            end,
            onclick = function ()
              close_add (view, false)
            end,
          }),
        }),
      })
      input:on ('keydown', function (ev)
        if ev.key == 'Enter' and not ev.shift and not ev.composing then
          submit ()
          return true
        end
        if ev.key == 'Escape' then
          close_add (view, false)
          return 'stop'
        end
        return nil
      end)
      input:on ('blur', function ()
        close_add (view, true)
      end)
      view.box, view.input = box, input
      view.add_btn:show (false)
      view.foot:append (box)
      input:focus ()
      box:scroll_into_view ()
    end

    -- The "Add column" slot ------------------------------------------------------------------

    local addcol_input = nil ---@type Proteus.El?
    local addcol_btn ---@type Proteus.El

    local function close_addcol ()
      local input = addcol_input
      if not input then
        return
      end
      addcol_input = nil
      input:remove ()
      addcol:append (addcol_btn)
    end

    local function scroll_to_end ()
      row:set ('scrollLeft', num (row, 'scrollWidth'))
    end

    local function open_addcol ()
      if not current () then
        return
      end
      if addcol_input then
        addcol_input:focus ()
        return
      end
      local input = ui.input ({
        class = 'kanban-addcol-input',
        placeholder = 'Column name',
      })
      addcol_input = input
      addcol_btn:detach ()
      addcol:append (input)
      input:on ('keydown', function (ev)
        if ev.key == 'Enter' then
          local board = current ()
          local text = input:value () or ''
          if board and text:match ('%S') then
            local next_board = m.add_column (board, text, new_id)
            input:value ('')
            commit (next_board)
            scroll_to_end ()
          end
          return true
        end
        if ev.key == 'Escape' then
          close_addcol ()
          return 'stop'
        end
        return nil
      end)
      input:on ('blur', function ()
        close_addcol ()
      end)
      input:focus ()
      scroll_to_end ()
    end

    addcol_btn = ui.button ({
      'Add column',
      icon = 'plus',
      variant = 'ghost',
      class = 'kanban-addcol-button',
      onclick = open_addcol,
    })
    addcol:append (addcol_btn)

    -- Renaming in place ---------------------------------------------------------------------

    ---Puts a text field in place for a rename. `finish` gets the text, or nil when cancelled.
    ---@param input Proteus.El
    ---@param finish fun(text: string?)
    local function edit_in_place (input, finish)
      local done = false
      ---@param keep boolean
      local function stop (keep)
        if done then
          return
        end
        done = true
        finish (keep and (input:value () or '') or nil)
      end
      input:on ('keydown', function (ev)
        if ev.key == 'Enter' then
          stop (true)
          return true
        end
        if ev.key == 'Escape' then
          stop (false)
          return 'stop'
        end
        return nil
      end)
      input:on ('blur', function ()
        stop (true)
      end)
      input:focus ()
      input:select ()
    end

    local function rename_title_inline ()
      local board = current ()
      if not board then
        return
      end
      local input =
        ui.input ({ class = 'kanban-title-input', value = board.title })
      title_el:show (false)
      head:insert_before (input, title_el)
      edit_in_place (input, function (text)
        input:remove ()
        title_el:show (true)
        local now_board = current ()
        if text and now_board then
          commit (m.set_title (now_board, text))
        end
      end)
    end

    rename_column_inline = function (id)
      local board = current ()
      local view = col_views[id]
      local column = board and m.find_column (board, id)
      if not view or not column or view.renaming then
        return
      end
      view.renaming = true
      local input =
        ui.input ({ class = 'kanban-col-input', value = column.title })
      view.head:clear ()
      view.head:append (input)
      edit_in_place (input, function (text)
        view.renaming = false
        view.head_html = ''
        local now_board = current ()
        if text and now_board then
          commit (m.rename_column (now_board, id, text))
        end
        -- Nothing changed, so the header still holds the field. Draw it again.
        local after = current ()
        local col = after and m.find_column (after, id)
        if view.head_html == '' and col and col_views[id] == view then
          view.head_html = head_html (col)
          view.head:html (view.head_html)
        end
      end)
    end

    -- Column and card actions ---------------------------------------------------------------

    ---@param id string
    local function set_limit (id)
      local board = current ()
      local column = board and m.find_column (board, id)
      if not column then
        return
      end
      ask ({
        prompt = 'The most cards "'
          .. column.title
          .. '" should hold. Leave it empty for no limit.',
        value = column.limit and tostring (column.limit) or '',
        placeholder = 'No limit',
        validate = function (text)
          if text:match ('^%s*$') or tonumber (text) then
            return nil
          end
          return 'Type a number, or leave it empty.'
        end,
        on_submit = function (text)
          local now_board = current ()
          if now_board then
            commit (m.set_limit (now_board, id, tonumber (text)))
          end
        end,
      })
    end

    ---@param id string
    ---@param step integer
    local function shift_column (id, step)
      local board = current ()
      if not board then
        return
      end
      local _, index = m.find_column (board, id)
      if index then
        commit (m.move_column (board, id, index + step))
      end
    end

    ---@param id string
    local function delete_column (id)
      local board = current ()
      local column = board and m.find_column (board, id)
      if not column then
        return
      end
      local function go ()
        local now_board = current ()
        if now_board then
          commit (m.remove_column (now_board, id))
        end
      end
      if #column.cards == 0 then
        go ()
        return
      end
      confirm (
        'Delete the column "'
          .. column.title
          .. '" and its '
          .. cards_text (#column.cards)
          .. '?',
        'Delete',
        go
      )
    end

    ---@param id string
    ---@return Proteus.MenuItem[]
    local function column_items (id)
      local board = current ()
      if not board then
        return {}
      end
      local column, index = m.find_column (board, id)
      if not column or not index then
        return {}
      end
      return {
        {
          label = 'Add a Card',
          icon = 'plus',
          run = function ()
            open_add (id)
          end,
        },
        {
          label = 'Rename',
          icon = 'pencil',
          run = function ()
            rename_column_inline (id)
          end,
        },
        {
          label = 'Set Limit',
          icon = 'gauge',
          run = function ()
            set_limit (id)
          end,
        },
        { separator = true },
        {
          label = 'Move Left',
          icon = 'arrow-left',
          disabled = index == 1,
          run = function ()
            shift_column (id, -1)
          end,
        },
        {
          label = 'Move Right',
          icon = 'arrow-right',
          disabled = index == #board.columns,
          run = function ()
            shift_column (id, 1)
          end,
        },
        { separator = true },
        {
          label = 'Delete Column',
          icon = 'trash-2',
          danger = true,
          run = function ()
            delete_column (id)
          end,
        },
      }
    end

    ---@param id string
    local function delete_card (id)
      local board = current ()
      local found = board and m.find_card (board, id)
      if not found then
        return
      end
      confirm (
        'Delete the card "' .. found.card.title .. '"?',
        'Delete',
        function ()
          local now_board = current ()
          if now_board then
            commit (m.remove_card (now_board, id))
          end
        end
      )
    end

    ---@param id string
    local function duplicate_card (id)
      local board = current ()
      if not board then
        return
      end
      local next_board, copy =
        m.duplicate_card (board, id, new_id, app.util.now ())
      commit (next_board)
      if copy then
        select_card (copy)
      end
    end

    ---@param id string
    ---@param column_id string
    local function move_card_to (id, column_id)
      local board = current ()
      local target = board and m.find_column (board, column_id)
      if board and target then
        commit (m.move_card (board, id, column_id, #target.cards + 1))
        local el = card_el (id)
        if el then
          el:scroll_into_view ()
        end
      end
    end

    ---The columns a card can move to, as menu items.
    ---@param id string
    ---@return Proteus.MenuItem[]
    local function move_items (id)
      local board = current ()
      local found = board and m.find_card (board, id)
      local items = {} ---@type Proteus.MenuItem[]
      if not board or not found then
        return items
      end
      for _, column in ipairs (board.columns) do
        if column.id ~= found.column.id then
          items[#items + 1] = {
            label = 'Move to ' .. column.title,
            icon = 'move',
            run = function ()
              move_card_to (id, column.id)
            end,
          }
        end
      end
      return items
    end

    ---@param id string
    local function pick_column_for (id)
      local board = current ()
      local found = board and m.find_card (board, id)
      if not board or not found or not picker then
        return
      end
      local items = {} ---@type Proteus.PickItem[]
      for _, column in ipairs (board.columns) do
        if column.id ~= found.column.id then
          items[#items + 1] = {
            label = column.title,
            detail = cards_text (#column.cards),
            icon = 'columns-3',
            value = column.id,
          }
        end
      end
      picker.pick ({
        prompt = 'Move "' .. found.card.title .. '" to',
        placeholder = 'Column',
        items = items,
        empty = 'No other column',
        on_pick = function (item)
          move_card_to (id, item.value)
        end,
      })
    end

    ---@param id string
    ---@return Proteus.MenuItem[]
    local function card_items (id)
      ---@type Proteus.MenuItem[]
      local items = {
        {
          label = 'Open',
          icon = 'panel-right-open',
          run = function ()
            open_card (id)
          end,
        },
      }
      if picker then
        items[#items + 1] = {
          label = 'Move To',
          icon = 'move',
          run = function ()
            pick_column_for (id)
          end,
        }
      else
        for _, item in ipairs (move_items (id)) do
          items[#items + 1] = item
        end
      end
      items[#items + 1] = {
        label = 'Duplicate',
        icon = 'copy',
        run = function ()
          duplicate_card (id)
        end,
      }
      items[#items + 1] = { separator = true }
      items[#items + 1] = {
        label = 'Delete',
        icon = 'trash-2',
        danger = true,
        run = function ()
          delete_card (id)
        end,
      }
      return items
    end

    -- Dragging ------------------------------------------------------------------------------

    ---Moves the placeholder to where the pointer says the item will land. It compares the
    ---pointer with where things stood when the drag began, which gives the same answer while
    ---the gap moves around.
    local function retarget ()
      local d = drag
      if not d then
        return
      end
      local ax = d.x + (num (row, 'scrollLeft') - d.scroll0)
      if d.kind == 'card' then
        local ci = m.span_at (d.spans, ax)
        local col = ci and d.cols[ci]
        if not ci or not col then
          return
        end
        local ay = d.y + (num (col.view.list, 'scrollTop') - col.scroll0)
        local index = m.drop_index (col.cards, ay)
        if ci ~= d.target or index ~= d.index then
          d.target, d.index = ci, index
          local before = col.ids[index]
          col.view.list:insert_before (
            d.placeholder,
            before and col.view.cards[before] or nil
          )
        end
        return
      end
      local index = m.drop_index (d.spans, ax)
      if index ~= d.index then
        d.index = index
        local before = d.ids[index]
        local view = before and col_views[before]
        row:insert_before (d.placeholder, view and view.el or addcol)
      end
    end

    ---@param x number
    ---@param y number
    local function drag_move (x, y)
      local d = drag
      if not d then
        return
      end
      d.x, d.y = x, y
      d.ghost:style (
        'transform',
        string.format (
          'translate(%dpx, %dpx) rotate(%s)',
          math.floor (x - d.dx),
          math.floor (y - d.dy),
          d.tilt
        )
      )
      retarget ()
    end

    ---Scrolls the board sideways, or a column down, while the pointer sits near an edge.
    local function autoscroll ()
      local d = drag
      if not d then
        return
      end
      local moved = false
      local rr = d.row_rect
      local sx = m.edge_speed (d.x, rr.left, rr.right, 60, 20)
      if sx ~= 0 then
        row:set ('scrollLeft', num (row, 'scrollLeft') + sx)
        moved = true
      end
      local col = d.kind == 'card' and d.target and d.cols[d.target] or nil
      if col then
        local sy = m.edge_speed (d.y, col.top, col.bottom, 40, 14)
        if sy ~= 0 then
          col.view.list:set ('scrollTop', num (col.view.list, 'scrollTop') + sy)
          moved = true
        end
      end
      if moved then
        retarget ()
      end
    end

    ---Ends the drag. With `drop`, the item moves to where the placeholder shows.
    ---@param drop boolean
    local function finish_drag (drop)
      local d = drag
      if not d then
        return
      end
      drag = nil
      d.stop ()
      if press then
        press.off ()
        press = nil
      end
      d.ghost:remove ()
      d.placeholder:remove ()
      if d.source:alive () then
        d.source:class ('kanban-hidden', false)
      end
      root:class ('kanban-dragging', false)
      local board = current ()
      if not drop or not board or not d.index then
        return
      end
      if d.kind == 'column' then
        commit (m.move_column (board, d.id, d.index))
        return
      end
      local col = d.target and d.cols[d.target]
      if col then
        commit (m.move_card (board, d.id, col.id, d.index))
        select_card (d.id)
      end
    end

    ---Measures every column and card, hides the card, and puts the placeholder in its place.
    ---@param board Kanban.Board
    ---@param id string
    ---@param x number
    ---@param y number
    ---@return Kanban.Drag?
    local function card_drag (board, id, x, y)
      local found = m.find_card (board, id)
      local home = found and col_views[found.column.id]
      local el = home and home.cards[id]
      if not found or not home or not el then
        return nil
      end
      local r = el:rect ()
      local spans = {} ---@type Kanban.Span[]
      local cols = {} ---@type Kanban.DragColumn[]
      local target = nil ---@type integer?
      for _, column in ipairs (board.columns) do
        local view = col_views[column.id]
        if view then
          local cr = view.el:rect ()
          local lr = view.list:rect ()
          local cards = {} ---@type Kanban.Span[]
          local ids = {} ---@type string[]
          for _, card in ipairs (column.cards) do
            local cel = view.cards[card.id]
            if card.id ~= id and cel then
              local rr = cel:rect ()
              cards[#cards + 1] = { top = rr.top, h = rr.h }
              ids[#ids + 1] = card.id
            end
          end
          spans[#spans + 1] = { top = cr.left, h = cr.w }
          cols[#cols + 1] = {
            id = column.id,
            view = view,
            top = lr.top,
            bottom = lr.bottom,
            cards = cards,
            ids = ids,
            scroll0 = num (view.list, 'scrollTop'),
          }
          if view == home then
            target = #cols
          end
        end
      end
      local ghost = ui.div ({
        class = 'kanban-card kanban-ghost',
        style = { width = r.w .. 'px' },
        html = card_html (found.card, board),
      })
      local placeholder = ui.div ({
        class = 'kanban-placeholder',
        style = { height = r.h .. 'px' },
      })
      home.list:insert_before (placeholder, el)
      el:class ('kanban-hidden', true)
      return {
        kind = 'card',
        id = id,
        ghost = ghost,
        placeholder = placeholder,
        source = el,
        dx = x - r.left,
        dy = y - r.top,
        x = x,
        y = y,
        tilt = '3deg',
        row_rect = row:rect (),
        scroll0 = num (row, 'scrollLeft'),
        spans = spans,
        cols = cols,
        ids = {},
        target = target,
        index = found.index,
        stop = function () end,
      }
    end

    ---Measures the other columns, hides the column, and puts the placeholder in its place.
    ---@param board Kanban.Board
    ---@param id string
    ---@param x number
    ---@param y number
    ---@return Kanban.Drag?
    local function column_drag (board, id, x, y)
      local column, index = m.find_column (board, id)
      local home = col_views[id]
      if not column or not index or not home then
        return nil
      end
      local r = home.el:rect ()
      local spans = {} ---@type Kanban.Span[]
      local ids = {} ---@type string[]
      for _, other in ipairs (board.columns) do
        local view = col_views[other.id]
        if other.id ~= id and view then
          local cr = view.el:rect ()
          spans[#spans + 1] = { top = cr.left, h = cr.w }
          ids[#ids + 1] = other.id
        end
      end
      local ghost = ui.div ({
        class = 'kanban-col-ghost',
        style = { width = r.w .. 'px' },
        html = '<div class="kanban-col-head">'
          .. head_html (column)
          .. '</div><div class="kanban-col-ghost-body">'
          .. cards_text (#column.cards)
          .. '</div>',
      })
      local placeholder = ui.div ({
        class = 'kanban-col-placeholder',
        style = { width = r.w .. 'px', height = r.h .. 'px' },
      })
      row:insert_before (placeholder, home.el)
      home.el:class ('kanban-hidden', true)
      return {
        kind = 'column',
        id = id,
        ghost = ghost,
        placeholder = placeholder,
        source = home.el,
        dx = x - r.left,
        dy = y - r.top,
        x = x,
        y = y,
        tilt = '2deg',
        row_rect = row:rect (),
        scroll0 = num (row, 'scrollLeft'),
        spans = spans,
        cols = {},
        ids = ids,
        index = index,
        stop = function () end,
      }
    end

    ---@param p Kanban.Press
    ---@param x number
    ---@param y number
    local function start_drag (p, x, y)
      local board = current ()
      if not board then
        return
      end
      local d ---@type Kanban.Drag?
      if p.kind == 'card' then
        d = card_drag (board, p.id, x, y)
      else
        d = column_drag (board, p.id, x, y)
      end
      if not d then
        return
      end
      -- The ghost is fixed to the window. It goes in the board, since a plugin reaches only
      -- its own elements.
      root:append (d.ghost)
      root:class ('kanban-dragging', true)
      local off_key = app.dom.on_global ('keydown', function (ev)
        if ev.key == 'Escape' then
          finish_drag (false)
          return 'stop'
        end
        return nil
      end, { capture = true })
      local off_blur = app.dom.on_global ('blur', function ()
        finish_drag (false)
      end)
      local stop_timer = app.timer.every (16, autoscroll)
      d.stop = function ()
        off_key ()
        off_blur ()
        stop_timer ()
      end
      drag = d
      drag_move (x, y)
    end

    ---Follows a press on a card or a column header. It turns into a drag once the pointer
    ---moves far enough. A card that is let go before that opens.
    ---@param kind 'card'|'column'
    ---@param id string
    ---@param ev Proteus.DomEvent
    local function begin_press (kind, id, ev)
      local sx, sy = ev.x or 0, ev.y or 0
      local off_move, off_up ---@type fun(), fun()
      ---@type Kanban.Press
      local p = {
        kind = kind,
        id = id,
        off = function ()
          off_move ()
          off_up ()
        end,
      }
      press = p
      off_move = app.dom.on_global ('mousemove', function (mv)
        local x, y = mv.x or 0, mv.y or 0
        if not drag then
          local dx, dy = x - sx, y - sy
          if dx * dx + dy * dy < DRAG_START * DRAG_START then
            return nil
          end
          start_drag (p, x, y)
        end
        drag_move (x, y)
        return nil
      end)
      off_up = app.dom.on_global ('mouseup', function ()
        p.off ()
        if press == p then
          press = nil
        end
        if drag then
          finish_drag (true)
        elseif kind == 'card' then
          open_card (id)
        end
        return nil
      end)
    end

    row:on ('mousedown', function (ev)
      if ev.button ~= 0 or press or drag then
        return nil
      end
      local kind, id = parse (ev.item)
      if kind == 'card' then
        begin_press ('card', id, ev)
      elseif kind == 'head' or kind == 'title' then
        local view = col_views[id]
        if view and not view.renaming then
          begin_press ('column', id, ev)
        end
      end
      return nil
    end)

    row:on ('click', function (ev)
      local kind, id = parse (ev.item)
      if kind == 'menu' and menus then
        menus.popup (column_items (id), ev.x or 0, ev.y or 0)
        return true
      end
      return nil
    end)

    row:on ('dblclick', function (ev)
      local kind, id = parse (ev.item)
      if kind == 'title' then
        rename_column_inline (id)
        return true
      end
      if kind == 'list' then
        open_add (id)
        return true
      end
      return nil
    end)

    title_el:on ('dblclick', function ()
      rename_title_inline ()
      return true
    end)

    search:on ('input', function (ev)
      query = ev.value or ''
      apply_dim ()
    end)
    search:on ('keydown', function (ev)
      if ev.key ~= 'Escape' then
        return nil
      end
      if query ~= '' then
        query = ''
        search:value ('')
        apply_dim ()
      else
        search:blur ()
      end
      return 'stop'
    end)
    filter_el:on ('change', function (ev)
      filter = ev.value or ''
      apply_dim ()
    end)

    if menus then
      menus.attach (row, function (ev)
        if ev.editable then
          return nil
        end
        local kind, id = parse (ev.item)
        if kind == 'card' then
          select_card (id)
          return card_items (id)
        end
        if kind and kind ~= 'card' then
          return column_items (id)
        end
        return {
          {
            label = 'Add Column',
            icon = 'plus',
            run = open_addcol,
          },
        }
      end)
    end

    -- The card panel ------------------------------------------------------------------------

    local p_title = ui.input ({
      class = 'kanban-p-title',
      placeholder = 'Card title',
      spellcheck = true,
    })
    local p_column = ui.h ('select', { class = 'ui-input kanban-p-select' })
    local p_labels = ui.div ({ class = 'kanban-p-labels' })
    local p_due = ui.input ({ type = 'date', class = 'kanban-p-due' })
    local p_notes = ui.input ({
      multiline = true,
      class = 'kanban-p-notes',
      placeholder = 'Add notes. Markdown works here.',
      spellcheck = true,
    })
    local p_preview = ui.div ({ class = 'kanban-p-preview ui-markdown' })
    local p_mode = ui.button ({ variant = 'ghost', class = 'kanban-small' })
    local p_created = ui.span ({ class = 'kanban-p-created' })
    local panel_columns = ''

    ---@return Kanban.Found?
    local function panel_found ()
      local board = current ()
      if not board or not panel_card then
        return nil
      end
      return m.find_card (board, panel_card)
    end

    ---@param fields Kanban.CardFields
    ---@param merge? string
    local function update_panel_card (fields, merge)
      local board = current ()
      if board and panel_card then
        commit (m.update_card (board, panel_card, fields), merge)
      end
    end

    local function show_mode ()
      p_notes:show (not preview)
      p_preview:show (preview)
      p_mode:set_children ({
        ui.icon (preview and 'pencil' or 'eye', 14),
        preview and 'Edit' or 'Preview',
      })
      local found = panel_found ()
      if preview and found then
        local notes = found.card.notes
        p_preview:html (
          notes:match ('%S') and app.util.markdown (notes)
            or '<p class="ui-muted">No notes yet.</p>'
        )
      end
    end

    p_title:on ('input', function (ev)
      if panel_card then
        update_panel_card ({ title = ev.value or '' }, 'title:' .. panel_card)
      end
    end)
    p_title:on ('keydown', function (ev)
      if ev.key == 'Enter' then
        p_title:blur ()
        return true
      end
      return nil
    end)
    p_title:on ('blur', function ()
      if history then
        m.history_seal (history)
      end
      -- An empty title is not saved, so show the saved one again.
      local found = panel_found ()
      if found and not (p_title:value () or ''):match ('%S') then
        p_title:value (found.card.title)
      end
    end)
    p_column:on ('change', function (ev)
      if panel_card and ev.value then
        move_card_to (panel_card, ev.value)
      end
    end)
    p_labels:on ('click', function (ev)
      local board = current ()
      if board and panel_card and ev.item then
        commit (m.toggle_label (board, panel_card, ev.item))
      end
    end)
    p_due:on ('change', function (ev)
      update_panel_card ({ due = ev.value or '' })
    end)
    p_notes:on ('input', function (ev)
      if panel_card then
        update_panel_card ({ notes = ev.value or '' }, 'notes:' .. panel_card)
      end
    end)
    p_notes:on ('blur', function ()
      if history then
        m.history_seal (history)
      end
    end)
    p_mode:on ('click', function ()
      preview = not preview
      show_mode ()
    end)

    ---@param label_id string
    local function rename_label (label_id)
      local board = current ()
      if not board then
        return
      end
      local colour = m.LABEL_COLOURS[label_id] or label_id
      ask ({
        prompt = 'A name for the '
          .. colour:lower ()
          .. ' label. Leave it empty to show only the colour.',
        value = own_name (board, label_id),
        placeholder = colour,
        on_submit = function (text)
          local now_board = current ()
          if now_board then
            commit (m.rename_label (now_board, label_id, text))
          end
        end,
      })
    end

    local function pick_label ()
      local board = current ()
      if not board or not picker then
        return
      end
      local items = {} ---@type Proteus.PickItem[]
      for _, id in ipairs (m.LABELS) do
        items[#items + 1] = {
          label = m.label_name (board.labels, id),
          detail = m.LABEL_COLOURS[id],
          icon = 'tag',
          value = id,
        }
      end
      picker.pick ({
        placeholder = 'Pick a label to rename',
        items = items,
        on_pick = function (item)
          rename_label (item.value)
        end,
      })
    end

    if menus then
      menus.attach (p_labels, function (ev)
        local id = ev.item
        if not id then
          return nil
        end
        return {
          {
            label = 'Rename Label',
            icon = 'pencil',
            run = function ()
              rename_label (id)
            end,
          },
        }
      end)
    end

    ---@param label string
    ---@param ... Proteus.Child
    ---@return Proteus.El
    local function field (label, ...)
      return ui.div ({
        class = 'kanban-p-field',
        ui.div ({ class = 'kanban-p-label', label }),
        ...,
      })
    end

    local p_body = ui.div ({
      class = 'kanban-panel',
      ui.div ({
        class = 'kanban-p-top',
        p_title,
        ui.button ({
          ui.icon ('x', 16),
          variant = 'ghost',
          class = 'kanban-icon-button',
          title = 'Close (Escape)',
          onclick = function ()
            close_panel ()
          end,
        }),
      }),
      field ('Column', p_column),
      ui.div ({
        class = 'kanban-p-field',
        ui.div ({
          class = 'kanban-p-row',
          ui.div ({ class = 'kanban-p-label', 'Labels' }),
          ui.button ({
            'Rename',
            variant = 'ghost',
            class = 'kanban-small',
            title = 'Name the labels on this board',
            onclick = pick_label,
          }),
        }),
        p_labels,
      }),
      field (
        'Due date',
        ui.div ({
          class = 'kanban-p-due-row',
          p_due,
          ui.button ({
            'Clear',
            variant = 'ghost',
            class = 'kanban-small',
            onclick = function ()
              p_due:value ('')
              update_panel_card ({ due = '' })
            end,
          }),
        })
      ),
      ui.div ({
        class = 'kanban-p-field',
        ui.div ({
          class = 'kanban-p-row',
          ui.div ({ class = 'kanban-p-label', 'Notes' }),
          p_mode,
        }),
        p_notes,
        p_preview,
      }),
      ui.div ({
        class = 'kanban-p-foot',
        p_created,
        ui.button ({
          'Delete Card',
          icon = 'trash-2',
          variant = 'danger',
          onclick = function ()
            if panel_card then
              delete_card (panel_card)
            end
          end,
        }),
      }),
    })
    local p_empty = ui.div ({
      class = 'ui-empty',
      'No card open. Click a card to see it here.',
    })
    local panel = ui.div ({ p_body, p_empty })
    show_mode ()

    local body_open = nil ---@type boolean?

    ---Shows the card fields when a card is open, and a short note when none is.
    local function show_panel_body ()
      local open = panel_found () ~= nil
      if open ~= body_open then
        body_open = open
        p_body:show (open)
        p_empty:show (not open)
      end
    end

    refresh_panel = function (force)
      local board = current ()
      local found = panel_found ()
      show_panel_body ()
      if not board or not found then
        return
      end
      local card = found.card
      local focus = app.dom.active ()
      if force or (focus ~= p_title.id and p_title:value () ~= card.title) then
        p_title:value (card.title)
      end
      local options = {} ---@type string[]
      for _, column in ipairs (board.columns) do
        options[#options + 1] = '<option value="'
          .. esc (column.id)
          .. '">'
          .. esc (column.title)
          .. '</option>'
      end
      local html = table.concat (options)
      if html ~= panel_columns then
        panel_columns = html
        p_column:html (html)
      end
      p_column:value (found.column.id)
      local toggles = {} ---@type string[]
      for _, id in ipairs (m.LABELS) do
        local on = false
        for _, have in ipairs (card.labels) do
          on = on or have == id
        end
        toggles[#toggles + 1] = '<button class="kanban-toggle kanban-c-'
          .. id
          .. (on and ' kanban-on' or '')
          .. '" data-item="'
          .. id
          .. '" title="'
          .. (on and 'Take this label off' or 'Put this label on')
          .. '"><span class="kanban-swatch"></span>'
          .. esc (m.label_name (board.labels, id))
          .. '</button>'
      end
      p_labels:html (table.concat (toggles))
      if force or focus ~= p_due.id then
        p_due:value (card.due or '')
      end
      if force or (focus ~= p_notes.id and p_notes:value () ~= card.notes) then
        p_notes:value (card.notes)
      end
      if preview then
        show_mode ()
      end
      local created = ''
      if card.created > 0 then
        local day = os.date ('%b %d, %Y', math.floor (card.created / 1000)) --[[@as string]]
        created = 'Created ' .. day
      end
      p_created:text (created)
    end

    open_card = function (id)
      select_card (id)
      panel_card = id
      refresh_panel (true)
      views.show (PANEL_ID)
    end

    close_panel = function ()
      panel_card = nil
      show_panel_body ()
      -- A field in a hidden panel would keep the keys, so take focus back to the board.
      local focus = app.dom.active ()
      if focus and app.dom.contains (panel.id, focus) then
        app.dom.call (focus, 'blur')
      end
      if not shell.is_visible ('right') then
        return
      end
      -- Hide the dock when the card is all it holds. Otherwise show the next panel in it.
      for _, v in ipairs (views.list ('right')) do
        if v.id ~= PANEL_ID then
          views.show (v.id)
          return
        end
      end
      shell.set_visible ('right', false)
    end

    -- Boards --------------------------------------------------------------------------------

    local boards_el = ui.div ({ class = 'kanban-boards' })
    local boards_timer = nil ---@type fun()?

    ---A board's title and card count, from the open board or from its file.
    ---@param p string
    ---@return string title
    ---@return integer count
    local function board_info (p)
      local board = p == path and current () or nil
      if not board then
        local raw = app.fs.read_json (p, false)
        if type (raw) == 'table' then
          board = m.normalize (raw, new_id)
        end
      end
      if not board then
        return p:match ('([^/]+)%.json$') or p, 0
      end
      return board.title, m.counts (board, today).cards
    end

    local function render_boards ()
      local parts = {} ---@type string[]
      for _, p in ipairs (board_paths ()) do
        local title, count = board_info (p)
        parts[#parts + 1] = '<div class="kanban-board-row'
          .. (p == path and ' kanban-active' or '')
          .. '" data-item="board:'
          .. esc (p)
          .. '" title="'
          .. esc (p)
          .. '">'
          .. ICON_BOARD
          .. '<span class="kanban-board-name">'
          .. esc (title)
          .. '</span><span class="kanban-board-count">'
          .. count
          .. '</span></div>'
      end
      if #parts == 0 then
        parts[1] = '<div class="ui-empty">No boards yet.<br>'
          .. '<button class="ui-button primary" data-item="new:">New Board</button></div>'
      end
      boards_el:html (table.concat (parts))
    end

    render_boards_soon = function ()
      if boards_timer then
        return
      end
      boards_timer = app.timer.after (80, function ()
        boards_timer = nil
        render_boards ()
      end)
    end

    ---Opens a board file. Returns false when it cannot be read.
    ---@param p string
    ---@return boolean
    local function open_board (p)
      if p == path and history then
        return true
      end
      finish_drag (false)
      save_now ()
      local board, err, text = read_board (p)
      if not board then
        tell ('error', 'Could not open ' .. p .. '. ' .. (err or ''))
        return false
      end
      path, last_text = p, text
      history = m.history_new (board)
      selected, panel_card = nil, nil
      for key, view in pairs (col_views) do
        view.el:remove ()
        col_views[key] = nil
      end
      drawn_order, filter_labels = {}, nil
      app.store.set ('last', p)
      close_panel ()
      refresh (true)
      render_boards ()
      return true
    end

    ---@param name string
    local function create_board (name)
      local board = m.new_board (name, new_id)
      local p =
        path_for (m.unique_name (m.file_name (board.title), taken_names ()))
      if write (p, m.encode (board)) then
        open_board (p)
      end
    end

    local function new_board_prompt ()
      ask ({
        prompt = 'A name for the new board',
        placeholder = 'Such as Launch or Home',
        value = '',
        validate = function (text)
          if text:match ('%S') then
            return nil
          end
          return 'Type a name for the board.'
        end,
        on_submit = create_board,
      })
    end

    ---@param p string
    local function rename_board (p)
      local title = board_info (p)
      ask ({
        prompt = 'A new name for the board',
        value = title,
        on_submit = function (text)
          if p == path and history then
            commit (m.set_title (history.present, text))
            save_now ()
          else
            local board = read_board (p)
            local renamed = board and m.set_title (board, text)
            if board and renamed and renamed ~= board then
              local target = path_for (
                m.unique_name (m.file_name (renamed.title), taken_names (p))
              )
              if write (p, m.encode (renamed)) and target ~= p then
                rename_file (p, target)
              end
            end
          end
          render_boards ()
        end,
      })
    end

    ---@param p string
    local function duplicate_board (p)
      local board = p == path and current () or read_board (p)
      if not board then
        return
      end
      local copy = m.set_title (board, board.title .. ' copy')
      local target =
        path_for (m.unique_name (m.file_name (copy.title), taken_names ()))
      if write (target, m.encode (copy)) then
        render_boards ()
        tell ('success', 'Made "' .. copy.title .. '".')
      end
    end

    ---@param p string
    local function delete_board (p)
      local title, count = board_info (p)
      confirm (
        'Delete the board "'
          .. title
          .. '" and its '
          .. cards_text (count)
          .. '?',
        'Delete',
        function ()
          if p == path then
            if save_timer then
              save_timer ()
              save_timer = nil
            end
            path, history, last_text = nil, nil, nil
            selected = nil
            close_panel ()
          end
          own_write = true
          local ok, err = pcall (app.fs.remove, p)
          own_write = false
          if not ok then
            tell ('error', 'Could not delete ' .. p .. ': ' .. tostring (err))
          end
          if not path then
            local rest = board_paths ()
            if not (rest[1] and open_board (rest[1])) then
              refresh (true)
            end
          end
          render_boards ()
        end
      )
    end

    local function pick_board ()
      if not picker then
        return
      end
      local items = {} ---@type Proteus.PickItem[]
      for _, p in ipairs (board_paths ()) do
        local title, count = board_info (p)
        items[#items + 1] = {
          label = title,
          detail = cards_text (count),
          icon = 'square-kanban',
          value = p,
        }
      end
      picker.pick ({
        placeholder = 'Open a board',
        items = items,
        empty = 'No boards yet',
        on_pick = function (item)
          open_board (item.value)
        end,
      })
    end

    boards_el:on ('click', function (ev)
      local kind, p = parse (ev.item)
      if kind == 'board' then
        open_board (p)
      elseif kind == 'new' then
        new_board_prompt ()
      end
    end)

    if menus then
      menus.attach (boards_el, function (ev)
        local kind, p = parse (ev.item)
        if kind ~= 'board' then
          return {
            { label = 'New Board', icon = 'plus', run = new_board_prompt },
          }
        end
        return {
          {
            label = 'Open',
            icon = 'folder-open',
            run = function ()
              open_board (p)
            end,
          },
          {
            label = 'Rename',
            icon = 'pencil',
            run = function ()
              rename_board (p)
            end,
          },
          {
            label = 'Duplicate',
            icon = 'copy',
            run = function ()
              duplicate_board (p)
            end,
          },
          { separator = true },
          {
            label = 'Delete',
            icon = 'trash-2',
            danger = true,
            run = function ()
              delete_board (p)
            end,
          },
        }
      end)
    end

    local side = ui.div ({
      class = 'kanban-side',
      ui.div ({
        class = 'kanban-side-bar',
        ui.button ({
          'New Board',
          icon = 'plus',
          variant = 'ghost',
          class = 'kanban-small',
          onclick = new_board_prompt,
        }),
      }),
      boards_el,
    })

    -- Commands ------------------------------------------------------------------------------

    ---@param spec Proteus.CommandSpec
    local function command (spec)
      spec.category = 'Kanban'
      commands.register (spec)
    end

    ---@return boolean
    local function has_path ()
      return path ~= nil
    end

    command ({
      id = 'kanban.new_board',
      title = 'New Board',
      icon = 'folder-plus',
      toolbar = 1,
      run = new_board_prompt,
    })
    command ({
      id = 'kanban.new_card',
      title = 'New Card',
      key = 'ctrl+n',
      icon = 'square-plus',
      toolbar = 2,
      when = function ()
        local board = current ()
        return board ~= nil and #board.columns > 0 and on_screen ()
      end,
      run = function ()
        local board = current ()
        local first = board and board.columns[1]
        if first then
          open_add (first.id)
        end
      end,
    })
    command ({
      id = 'kanban.new_column',
      title = 'New Column',
      icon = 'columns-3',
      toolbar = 3,
      when = ready,
      run = open_addcol,
    })
    command ({
      id = 'kanban.undo',
      title = 'Undo',
      key = 'ctrl+z',
      icon = 'undo-2',
      toolbar = 4,
      when = function ()
        return history ~= nil
          and #history.past > 0
          and on_screen ()
          and not typing ()
      end,
      run = undo,
    })
    command ({
      id = 'kanban.redo',
      title = 'Redo',
      key = { 'ctrl+y', 'ctrl+shift+z' },
      icon = 'redo-2',
      toolbar = 5,
      when = function ()
        return history ~= nil
          and #history.future > 0
          and on_screen ()
          and not typing ()
      end,
      run = redo,
    })
    command ({
      id = 'kanban.search',
      title = 'Search Cards',
      key = 'ctrl+f',
      icon = 'search',
      toolbar = 6,
      when = ready,
      run = function ()
        search:focus ()
        search:select ()
      end,
    })
    command ({
      id = 'kanban.open_board',
      title = 'Open Board',
      icon = 'folder-open',
      run = pick_board,
    })
    command ({
      id = 'kanban.rename_board',
      title = 'Rename Board',
      icon = 'pencil',
      when = has_path,
      run = function ()
        if path then
          rename_board (path)
        end
      end,
    })
    command ({
      id = 'kanban.duplicate_board',
      title = 'Duplicate Board',
      icon = 'copy',
      when = has_path,
      run = function ()
        if path then
          duplicate_board (path)
        end
      end,
    })
    command ({
      id = 'kanban.delete_board',
      title = 'Delete Board',
      icon = 'trash-2',
      when = has_path,
      run = function ()
        if path then
          delete_board (path)
        end
      end,
    })
    command ({
      id = 'kanban.open_card',
      title = 'Open Card',
      icon = 'panel-right-open',
      when = card_ready,
      run = function ()
        if selected then
          open_card (selected)
        end
      end,
    })
    command ({
      id = 'kanban.close_card',
      title = 'Close Card',
      icon = 'x',
      when = function ()
        return panel_card ~= nil
      end,
      run = close_panel,
    })
    command ({
      id = 'kanban.move_card',
      title = 'Move Card To',
      icon = 'move',
      when = card_ready,
      run = function ()
        if selected then
          pick_column_for (selected)
        end
      end,
    })
    command ({
      id = 'kanban.duplicate_card',
      title = 'Duplicate Card',
      key = 'ctrl+d',
      icon = 'copy',
      when = card_ready,
      run = function ()
        if selected then
          duplicate_card (selected)
        end
      end,
    })
    command ({
      id = 'kanban.delete_card',
      title = 'Delete Card',
      key = 'delete',
      icon = 'trash-2',
      when = card_ready,
      run = function ()
        if selected then
          delete_card (selected)
        end
      end,
    })
    ---@type { [1]: Kanban.Direction, [2]: string }[]
    local moves = {
      { 'left', 'Move Card Left' },
      { 'right', 'Move Card Right' },
      { 'up', 'Move Card Up' },
      { 'down', 'Move Card Down' },
    }
    for _, move in ipairs (moves) do
      command ({
        id = 'kanban.move_' .. move[1],
        title = move[2],
        key = 'alt+arrow' .. move[1],
        icon = 'arrow-' .. move[1],
        when = card_ready,
        run = function ()
          nudge (move[1])
        end,
      })
    end
    command ({
      id = 'kanban.rename_label',
      title = 'Rename Label',
      icon = 'tag',
      when = ready,
      run = pick_label,
    })
    command ({
      id = 'kanban.theme',
      title = 'Change Theme',
      icon = 'palette',
      toolbar = 90,
      toolbar_align = 'right',
      run = function ()
        commands.run ('theme.choose')
      end,
    })
    command ({
      id = 'kanban.switch_app',
      title = 'Switch App',
      icon = 'layers',
      toolbar = 91,
      toolbar_align = 'right',
      run = function ()
        commands.run ('profile.switch')
      end,
    })

    -- Keys, file changes and the clock ------------------------------------------------------

    -- Escape closes the card panel, then clears the selection. Fields, menus and the palette
    -- handle their own Escape first and stop it there.
    app.dom.on_global ('keydown', function (ev)
      if ev.key ~= 'Escape' or drag or not on_screen () then
        return nil
      end
      if panel_card and shell.is_visible ('right') then
        close_panel ()
        return 'stop'
      end
      if selected and not typing () then
        select_card (nil)
        return 'stop'
      end
      return nil
    end)

    -- A board changed elsewhere, such as in the editor or another window, loads again here.
    ---@param p string
    app.on ('fs:changed', function (p)
      if
        own_write
        or type (p) ~= 'string'
        or p:sub (1, #DIR + 1) ~= DIR .. '/'
      then
        return
      end
      if p == path and history then
        local text = app.fs.read (p)
        if text and text ~= last_text then
          local ok, raw = pcall (app.json.decode, text)
          if ok then
            last_text = text
            if m.history_push (history, m.normalize (raw, new_id)) then
              refresh ()
            end
          end
        end
      end
      render_boards_soon ()
    end)

    -- Due dates read "Today" and "Tomorrow", so the board draws again when the day changes.
    app.timer.every (60000, function ()
      local day = os.date ('%Y-%m-%d') --[[@as string]]
      if day ~= today then
        today = day
        refresh (true)
      end
    end)

    app.dispose (function ()
      finish_drag (false)
      save_now ()
    end)

    -- Start ---------------------------------------------------------------------------------

    if tabs then
      tab = tabs.open ({
        id = TAB_ID,
        title = 'Kanban',
        icon = 'kanban',
        content = root,
        closable = false,
      })
    else
      shell.mount ('main', root)
    end
    views.add ('left', {
      id = BOARDS_ID,
      title = 'Boards',
      icon = 'folder-kanban',
      order = 1,
      content = side,
    })
    views.add ('right', {
      id = PANEL_ID,
      title = 'Card',
      icon = 'square-kanban',
      content = panel,
    })
    if #views.list ('right') <= 1 then
      shell.set_visible ('right', false)
    end
    show_panel_body ()

    if not app.store.get ('seeded', false) and #board_paths () == 0 then
      write (
        path_for ('Getting started'),
        m.encode (m.example (new_id, app.util.now (), today))
      )
    end
    app.store.set ('seeded', true)
    local last = app.store.get ('last')
    if
      not (
        type (last) == 'string'
        and app.fs.exists (last)
        and open_board (last)
      )
    then
      local first = board_paths ()[1]
      if not (first and open_board (first)) then
        refresh (true)
        render_boards ()
      end
    end
  end,
}
