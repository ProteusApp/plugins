-- kanban_board: the logic behind proteus.kanban.classic, with no screen and no host calls.
--
-- Every change takes a board and returns a new board. The old board stays as it was, and the
-- parts that did not change are shared, so the undo history can keep every old board cheaply.
-- A change that changes nothing returns the same board, which tells the caller to skip it.
-- New ids come from a function the caller passes in, so tests get stable ids.

---@class Kanban.Card
---@field id string
---@field title string
---@field notes string Markdown.
---@field labels string[] Label ids such as `'red'`, in the order of `LABELS`.
---@field due? string A date as `YYYY-MM-DD`.
---@field created number Milliseconds since 1970.

---@class Kanban.Column
---@field id string
---@field title string
---@field limit? integer The header warns when the column holds more cards than this.
---@field cards Kanban.Card[]

---@class Kanban.Label
---@field id string One of `LABELS`.
---@field name string Empty until the user names it.

---@class Kanban.Board
---@field version integer
---@field title string
---@field labels Kanban.Label[] All six, in the order of `LABELS`.
---@field columns Kanban.Column[]

---What `update_card` may change. A field left nil stays as it was. An empty `due` clears it.
---@class Kanban.CardFields
---@field title? string
---@field notes? string
---@field labels? string[]
---@field due? string

---Where `find_card` found a card.
---@class Kanban.Found
---@field card Kanban.Card
---@field column Kanban.Column
---@field index integer The card's place in its column.
---@field column_index integer The column's place on the board.

---A card or a column on screen, along one axis: its start and its size.
---@class Kanban.Span
---@field top number
---@field h number

---@class Kanban.Counts
---@field cards integer
---@field overdue integer
---@field soon integer

---Boards for undo and redo. The newest past board is last, and so is the next redo.
---@class Kanban.History
---@field past Kanban.Board[]
---@field present Kanban.Board
---@field future Kanban.Board[]
---@field limit integer
---@field merge? string The key of the last change, so a burst of typing makes one step.

---@alias Kanban.NewId fun(): string
---@alias Kanban.DueState 'overdue'|'soon'|'later'
---@alias Kanban.Direction 'left'|'right'|'up'|'down'

---@class Kanban.BoardModule
local M = {}

M.VERSION = 1
M.HISTORY_LIMIT = 100

---The six label colours, in the order they show.
M.LABELS = { 'red', 'orange', 'yellow', 'green', 'blue', 'purple' }

---The colour names, for labels the user has not named.
---@type table<string, string>
M.LABEL_COLOURS = {
  red = 'Red',
  orange = 'Orange',
  yellow = 'Yellow',
  green = 'Green',
  blue = 'Blue',
  purple = 'Purple',
}

---The columns a new board starts with.
M.START_COLUMNS = { 'To do', 'Doing', 'Done' }

local MONTHS = {
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
}

---@param s string
---@return string
local function trim (s)
  return (s:gsub ('^%s+', ''):gsub ('%s+$', ''))
end

---@param list any[]
---@return any[]
local function copy_list (list)
  local out = {} ---@type any[]
  for i, v in ipairs (list) do
    out[i] = v
  end
  return out
end

---@param b Kanban.Board
---@param columns Kanban.Column[]
---@return Kanban.Board
local function with_columns (b, columns)
  return {
    version = b.version,
    title = b.title,
    labels = b.labels,
    columns = columns,
  }
end

---@param c Kanban.Column
---@param cards Kanban.Card[]
---@return Kanban.Column
local function with_cards (c, cards)
  return { id = c.id, title = c.title, limit = c.limit, cards = cards }
end

---@param c Kanban.Card
---@return Kanban.Card
local function copy_card (c)
  return {
    id = c.id,
    title = c.title,
    notes = c.notes,
    labels = c.labels,
    due = c.due,
    created = c.created,
  }
end

---A new board with one column swapped for another.
---@param b Kanban.Board
---@param index integer
---@param column Kanban.Column
---@return Kanban.Board
local function set_column (b, index, column)
  local columns = copy_list (b.columns) --[[@as Kanban.Column[] ]]
  columns[index] = column
  return with_columns (b, columns)
end

---@param value any
---@return any[]
local function as_list (value)
  local out = {} ---@type any[]
  if type (value) ~= 'table' then
    return out
  end
  for _, v in
    ipairs (value --[[@as any[] ]])
  do
    out[#out + 1] = v
  end
  return out
end

---@param value any
---@param fallback string
---@return string
local function as_text (value, fallback)
  if type (value) == 'string' then
    return value
  end
  if type (value) == 'number' then
    return tostring (value)
  end
  return fallback
end

---@param list string[]
---@param value string
---@return boolean
local function has (list, value)
  for _, v in ipairs (list) do
    if v == value then
      return true
    end
  end
  return false
end

-- Dates --------------------------------------------------------------------------------------

---The day number of a date, counted from 1970-01-01, for any year in the Gregorian calendar.
---@param y integer
---@param m integer
---@param d integer
---@return integer
local function days_from_civil (y, m, d)
  if m <= 2 then
    y = y - 1
  end
  local era = math.floor (y / 400)
  local yoe = y - era * 400
  local mp = (m + 9) % 12
  local doy = math.floor ((153 * mp + 2) / 5) + d - 1
  local doe = yoe * 365 + math.floor (yoe / 4) - math.floor (yoe / 100) + doy
  return era * 146097 + doe - 719468
end

---The date of a day number, the reverse of `days_from_civil`.
---@param z integer
---@return integer y
---@return integer m
---@return integer d
local function civil_from_days (z)
  z = z + 719468
  local era = math.floor (z / 146097)
  local doe = z - era * 146097
  local yoe = math.floor (
    (
      doe
      - math.floor (doe / 1460)
      + math.floor (doe / 36524)
      - math.floor (doe / 146096)
    ) / 365
  )
  local doy = doe - (365 * yoe + math.floor (yoe / 4) - math.floor (yoe / 100))
  local mp = math.floor ((5 * doy + 2) / 153)
  local d = doy - math.floor ((153 * mp + 2) / 5) + 1
  local m = mp < 10 and mp + 3 or mp - 9
  local y = yoe + era * 400
  if m <= 2 then
    y = y + 1
  end
  return y, m, d
end

---The year, month and day of a `YYYY-MM-DD` date, or nil when it is not a real date.
---@param date any
---@return integer? y
---@return integer? m
---@return integer? d
local function parse_date (date)
  if type (date) ~= 'string' then
    return nil
  end
  local text = date --[[@as string]]
  local ys, ms, ds = text:match ('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
  if not ys then
    return nil
  end
  local y = math.floor (tonumber (ys) or 0)
  local m = math.floor (tonumber (ms) or 0)
  local d = math.floor (tonumber (ds) or 0)
  if m < 1 or m > 12 or d < 1 then
    return nil
  end
  local ny, nm = y, m + 1
  if nm > 12 then
    ny, nm = y + 1, 1
  end
  local length = days_from_civil (ny, nm, 1) - days_from_civil (y, m, 1)
  if d > length then
    return nil
  end
  return y, m, d
end

---True for a real date written as `YYYY-MM-DD`.
---@param date any
---@return boolean
function M.valid_date (date)
  return parse_date (date) ~= nil
end

---The date `n` days after `date`, or before it when `n` is negative.
---@param date string
---@param n integer
---@return string
function M.add_days (date, n)
  local y, m, d = parse_date (date)
  if not (y and m and d) then
    return date
  end
  local ny, nm, nd = civil_from_days (days_from_civil (y, m, d) + n)
  return string.format ('%04d-%02d-%02d', ny, nm, nd)
end

---Days from `today` to `date`. Negative when `date` has passed.
---@param date string
---@param today string
---@return integer?
local function days_until (date, today)
  local y, m, d = parse_date (date)
  local ty, tm, td = parse_date (today)
  if not (y and m and d and ty and tm and td) then
    return nil
  end
  return days_from_civil (y, m, d) - days_from_civil (ty, tm, td)
end

---How close a card's due date is: `'overdue'` once it has passed, `'soon'` today or
---tomorrow, `'later'` after that, and nil for a card with no due date.
---@param card Kanban.Card
---@param today string
---@return Kanban.DueState?
function M.due_state (card, today)
  if not card.due then
    return nil
  end
  local n = days_until (card.due, today)
  if not n then
    return nil
  end
  if n < 0 then
    return 'overdue'
  end
  if n <= 1 then
    return 'soon'
  end
  return 'later'
end

---Short text for a due date, such as `'Today'`, `'Tomorrow'` or `'Mar 5'`.
---@param due string
---@param today string
---@return string
function M.due_label (due, today)
  local n = days_until (due, today)
  if n == 0 then
    return 'Today'
  end
  if n == 1 then
    return 'Tomorrow'
  end
  if n == -1 then
    return 'Yesterday'
  end
  local y, m, d = parse_date (due)
  local ty = parse_date (today)
  if not (y and m and d) then
    return due
  end
  local text = MONTHS[m] .. ' ' .. d
  if y ~= ty then
    text = text .. ', ' .. y
  end
  return text
end

-- Boards -------------------------------------------------------------------------------------

---@return Kanban.Label[]
local function start_labels ()
  local out = {} ---@type Kanban.Label[]
  for i, id in ipairs (M.LABELS) do
    out[i] = { id = id, name = '' }
  end
  return out
end

---Known label ids from a list, once each, in the order of `LABELS`.
---@param ids any
---@return string[]
function M.sort_labels (ids)
  local wanted = {} ---@type table<string, boolean>
  for _, id in ipairs (as_list (ids)) do
    if type (id) == 'string' then
      wanted[id] = true
    end
  end
  local out = {} ---@type string[]
  for _, id in ipairs (M.LABELS) do
    if wanted[id] then
      out[#out + 1] = id
    end
  end
  return out
end

---A new board with the three starting columns.
---@param title string
---@param new_id Kanban.NewId
---@return Kanban.Board
function M.new_board (title, new_id)
  local columns = {} ---@type Kanban.Column[]
  for i, name in ipairs (M.START_COLUMNS) do
    columns[i] = { id = new_id (), title = name, cards = {} }
  end
  local name = trim (title or '')
  return {
    version = M.VERSION,
    title = name ~= '' and name or 'Untitled board',
    labels = start_labels (),
    columns = columns,
  }
end

---Turns whatever a board file held into a sound board. It fills in missing fields, reads a
---list saved as `{}` as empty, drops labels it does not know, and gives a new id to a card
---or column whose id is missing or taken.
---@param raw any
---@param new_id Kanban.NewId
---@return Kanban.Board
function M.normalize (raw, new_id)
  local src = type (raw) == 'table' and raw or {} ---@type table<string, any>
  local seen = {} ---@type table<string, boolean>

  ---@param value any
  ---@return string
  local function fresh (value)
    local id = type (value) == 'number' and tostring (value) or value
    if type (id) ~= 'string' or id == '' or seen[id] then
      id = new_id ()
      while seen[id] do
        id = new_id ()
      end
    end
    seen[id] = true
    return id
  end

  -- Labels may come as a list of { id, name } or as a map from id to name.
  local names = {} ---@type table<string, string>
  if type (src.labels) == 'table' then
    for key, value in
      pairs (src.labels --[[@as table<any, any>]])
    do
      if type (value) == 'table' and type (value.id) == 'string' then
        names[value.id] = as_text (value.name, '')
      elseif type (key) == 'string' then
        names[key] = as_text (value, '')
      end
    end
  end
  local labels = start_labels ()
  for _, label in ipairs (labels) do
    label.name = names[label.id] or ''
  end

  local columns = {} ---@type Kanban.Column[]
  for _, rc in ipairs (as_list (src.columns)) do
    if type (rc) == 'table' then
      local cards = {} ---@type Kanban.Card[]
      for _, rk in ipairs (as_list (rc.cards)) do
        if type (rk) == 'table' then
          cards[#cards + 1] = {
            id = fresh (rk.id),
            title = as_text (rk.title, ''),
            notes = as_text (rk.notes, ''),
            labels = M.sort_labels (rk.labels),
            due = M.valid_date (rk.due) and rk.due or nil,
            created = type (rk.created) == 'number' and rk.created or 0,
          }
        end
      end
      local limit = tonumber (rc.limit)
      columns[#columns + 1] = {
        id = fresh (rc.id),
        title = as_text (rc.title, 'Untitled'),
        limit = limit and limit >= 1 and math.floor (limit) or nil,
        cards = cards,
      }
    end
  end

  local title = trim (as_text (src.title, ''))
  return {
    version = M.VERSION,
    title = title ~= '' and title or 'Untitled board',
    labels = labels,
    columns = columns,
  }
end

---@param board Kanban.Board
---@param title string
---@return Kanban.Board
function M.set_title (board, title)
  local name = trim (title or '')
  if name == '' or name == board.title then
    return board
  end
  return {
    version = board.version,
    title = name,
    labels = board.labels,
    columns = board.columns,
  }
end

-- Columns ------------------------------------------------------------------------------------

---@param board Kanban.Board
---@param column_id string
---@return Kanban.Column?
---@return integer?
function M.find_column (board, column_id)
  for i, c in ipairs (board.columns) do
    if c.id == column_id then
      return c, i
    end
  end
  return nil, nil
end

---Adds an empty column at the end. Returns the board and the new column's id.
---@param board Kanban.Board
---@param title string
---@param new_id Kanban.NewId
---@return Kanban.Board
---@return string?
function M.add_column (board, title, new_id)
  local name = trim (title or '')
  if name == '' then
    return board, nil
  end
  local id = new_id ()
  local columns = copy_list (board.columns) --[[@as Kanban.Column[] ]]
  columns[#columns + 1] = { id = id, title = name, cards = {} }
  return with_columns (board, columns), id
end

---@param board Kanban.Board
---@param column_id string
---@param title string
---@return Kanban.Board
function M.rename_column (board, column_id, title)
  local column, index = M.find_column (board, column_id)
  local name = trim (title or '')
  if not column or not index or name == '' or name == column.title then
    return board
  end
  return set_column (
    board,
    index,
    { id = column.id, title = name, limit = column.limit, cards = column.cards }
  )
end

---Sets how many cards a column should hold. Nil, zero or less clears the limit.
---@param board Kanban.Board
---@param column_id string
---@param limit number?
---@return Kanban.Board
function M.set_limit (board, column_id, limit)
  local column, index = M.find_column (board, column_id)
  if not column or not index then
    return board
  end
  local value = (limit and limit >= 1) and math.floor (limit) or nil
  if value == column.limit then
    return board
  end
  return set_column (board, index, {
    id = column.id,
    title = column.title,
    limit = value,
    cards = column.cards,
  })
end

---Moves a column so it ends up at `to_index`.
---@param board Kanban.Board
---@param column_id string
---@param to_index integer
---@return Kanban.Board
function M.move_column (board, column_id, to_index)
  local column, index = M.find_column (board, column_id)
  if not column or not index then
    return board
  end
  local columns = copy_list (board.columns) --[[@as Kanban.Column[] ]]
  table.remove (columns, index)
  local at = math.max (1, math.min (math.floor (to_index), #columns + 1))
  if at == index then
    return board
  end
  table.insert (columns, at, column)
  return with_columns (board, columns)
end

---Removes a column and every card in it.
---@param board Kanban.Board
---@param column_id string
---@return Kanban.Board
function M.remove_column (board, column_id)
  local _, index = M.find_column (board, column_id)
  if not index then
    return board
  end
  local columns = copy_list (board.columns) --[[@as Kanban.Column[] ]]
  table.remove (columns, index)
  return with_columns (board, columns)
end

---True when a column holds more cards than its limit.
---@param column Kanban.Column
---@return boolean
function M.over_limit (column)
  return column.limit ~= nil and #column.cards > column.limit
end

-- Cards --------------------------------------------------------------------------------------

---@param board Kanban.Board
---@param card_id string
---@return Kanban.Found?
function M.find_card (board, card_id)
  for ci, column in ipairs (board.columns) do
    for i, card in ipairs (column.cards) do
      if card.id == card_id then
        return { card = card, column = column, index = i, column_index = ci }
      end
    end
  end
  return nil
end

---Adds a card to a column, at the end unless `index` says where. Returns the board and the
---new card's id, or no id when the title is empty or the column is gone.
---@param board Kanban.Board
---@param column_id string
---@param title string
---@param new_id Kanban.NewId
---@param now number
---@param index? integer
---@return Kanban.Board
---@return string?
function M.add_card (board, column_id, title, new_id, now, index)
  local column, ci = M.find_column (board, column_id)
  local name = trim (title or '')
  if not column or not ci or name == '' then
    return board, nil
  end
  local id = new_id ()
  local cards = copy_list (column.cards) --[[@as Kanban.Card[] ]]
  local at =
    math.max (1, math.min (math.floor (index or #cards + 1), #cards + 1))
  table.insert (
    cards,
    at,
    { id = id, title = name, notes = '', labels = {}, created = now }
  )
  return set_column (board, ci, with_cards (column, cards)), id
end

---Changes some fields of a card. An empty title leaves the title as it was.
---@param board Kanban.Board
---@param card_id string
---@param fields Kanban.CardFields
---@return Kanban.Board
function M.update_card (board, card_id, fields)
  local found = M.find_card (board, card_id)
  if not found then
    return board
  end
  local card = copy_card (found.card)
  local changed = false
  if fields.title ~= nil then
    local name = trim (fields.title)
    if name ~= '' and name ~= card.title then
      card.title, changed = name, true
    end
  end
  if fields.notes ~= nil and fields.notes ~= card.notes then
    card.notes, changed = fields.notes, true
  end
  if fields.labels ~= nil then
    local labels = M.sort_labels (fields.labels)
    if table.concat (labels, ',') ~= table.concat (card.labels, ',') then
      card.labels, changed = labels, true
    end
  end
  if fields.due ~= nil then
    local due = M.valid_date (fields.due) and fields.due or nil
    if due ~= card.due then
      card.due, changed = due, true
    end
  end
  if not changed then
    return board
  end
  local cards = copy_list (found.column.cards) --[[@as Kanban.Card[] ]]
  cards[found.index] = card
  return set_column (board, found.column_index, with_cards (found.column, cards))
end

---Puts a label on a card, or takes it off when the card has it.
---@param board Kanban.Board
---@param card_id string
---@param label_id string
---@return Kanban.Board
function M.toggle_label (board, card_id, label_id)
  local found = M.find_card (board, card_id)
  if not found then
    return board
  end
  local labels = {} ---@type string[]
  local had = false
  for _, id in ipairs (found.card.labels) do
    if id == label_id then
      had = true
    else
      labels[#labels + 1] = id
    end
  end
  if not had then
    labels[#labels + 1] = label_id
  end
  return M.update_card (board, card_id, { labels = labels })
end

---Moves a card so it ends up at `to_index` in the column `to_column_id`. The index counts
---the column's cards without the moving card, which is where a drag shows the gap.
---@param board Kanban.Board
---@param card_id string
---@param to_column_id string
---@param to_index integer
---@return Kanban.Board
function M.move_card (board, card_id, to_column_id, to_index)
  local found = M.find_card (board, card_id)
  local target, ti = M.find_column (board, to_column_id)
  if not found or not target or not ti then
    return board
  end
  local same = ti == found.column_index
  local source = copy_list (found.column.cards) --[[@as Kanban.Card[] ]]
  table.remove (source, found.index)
  local dest = same and source or copy_list (target.cards) --[[@as Kanban.Card[] ]]
  local at = math.max (1, math.min (math.floor (to_index), #dest + 1))
  if same and at == found.index then
    return board
  end
  table.insert (dest, at, found.card)
  local columns = copy_list (board.columns) --[[@as Kanban.Column[] ]]
  columns[found.column_index] = with_cards (found.column, source)
  if not same then
    columns[ti] = with_cards (target, dest)
  end
  return with_columns (board, columns)
end

---Moves a card one step: up or down in its column, or to the column on the left or right,
---keeping its place in the list where it can.
---@param board Kanban.Board
---@param card_id string
---@param direction Kanban.Direction
---@return Kanban.Board
function M.nudge (board, card_id, direction)
  local found = M.find_card (board, card_id)
  if not found then
    return board
  end
  if direction == 'up' or direction == 'down' then
    local at = found.index + (direction == 'up' and -1 or 1)
    if at < 1 or at > #found.column.cards then
      return board
    end
    return M.move_card (board, card_id, found.column.id, at)
  end
  local step = direction == 'left' and -1 or 1
  local target = board.columns[found.column_index + step]
  if not target then
    return board
  end
  return M.move_card (
    board,
    card_id,
    target.id,
    math.min (found.index, #target.cards + 1)
  )
end

---@param board Kanban.Board
---@param card_id string
---@return Kanban.Board
function M.remove_card (board, card_id)
  local found = M.find_card (board, card_id)
  if not found then
    return board
  end
  local cards = copy_list (found.column.cards) --[[@as Kanban.Card[] ]]
  table.remove (cards, found.index)
  return set_column (board, found.column_index, with_cards (found.column, cards))
end

---Puts a copy of a card right below it. Returns the board and the copy's id.
---@param board Kanban.Board
---@param card_id string
---@param new_id Kanban.NewId
---@param now number
---@return Kanban.Board
---@return string?
function M.duplicate_card (board, card_id, new_id, now)
  local found = M.find_card (board, card_id)
  if not found then
    return board, nil
  end
  local card = copy_card (found.card)
  card.id = new_id ()
  card.created = now
  card.labels = copy_list (found.card.labels) --[[@as string[] ]]
  local cards = copy_list (found.column.cards) --[[@as Kanban.Card[] ]]
  table.insert (cards, found.index + 1, card)
  return set_column (board, found.column_index, with_cards (found.column, cards)),
    card.id
end

-- Labels -------------------------------------------------------------------------------------

---A label's name, or its colour when the user has not named it.
---@param labels Kanban.Label[]
---@param label_id string
---@return string
function M.label_name (labels, label_id)
  for _, label in ipairs (labels) do
    if label.id == label_id and label.name ~= '' then
      return label.name
    end
  end
  return M.LABEL_COLOURS[label_id] or label_id
end

---@param board Kanban.Board
---@param label_id string
---@param name string
---@return Kanban.Board
function M.rename_label (board, label_id, name)
  local text = trim (name or '')
  local labels = {} ---@type Kanban.Label[]
  local changed = false
  for i, label in ipairs (board.labels) do
    if label.id == label_id and label.name ~= text then
      labels[i] = { id = label.id, name = text }
      changed = true
    else
      labels[i] = label
    end
  end
  if not changed then
    return board
  end
  return {
    version = board.version,
    title = board.title,
    labels = labels,
    columns = board.columns,
  }
end

-- Search and counts --------------------------------------------------------------------------

---True when a card matches the search. Every word of `query` must appear in the title, the
---notes or a label's name. With `only`, the card must also carry that label.
---@param card Kanban.Card
---@param query string?
---@param labels Kanban.Label[]
---@param only? string A label id.
---@return boolean
function M.matches (card, query, labels, only)
  if only and only ~= '' and not has (card.labels, only) then
    return false
  end
  local q = trim ((query or ''):lower ())
  if q == '' then
    return true
  end
  local parts = { card.title, card.notes } ---@type string[]
  for _, id in ipairs (card.labels) do
    parts[#parts + 1] = M.label_name (labels, id)
    parts[#parts + 1] = M.LABEL_COLOURS[id] or id
  end
  local hay = table.concat (parts, '\n'):lower ()
  for word in q:gmatch ('%S+') do
    if not hay:find (word, 1, true) then
      return false
    end
  end
  return true
end

---How many cards the board holds, and how many are overdue or due soon.
---@param board Kanban.Board
---@param today string
---@return Kanban.Counts
function M.counts (board, today)
  local out = { cards = 0, overdue = 0, soon = 0 } ---@type Kanban.Counts
  for _, column in ipairs (board.columns) do
    for _, card in ipairs (column.cards) do
      out.cards = out.cards + 1
      local state = M.due_state (card, today)
      if state == 'overdue' then
        out.overdue = out.overdue + 1
      elseif state == 'soon' then
        out.soon = out.soon + 1
      end
    end
  end
  return out
end

-- Dragging -----------------------------------------------------------------------------------

---Where a dropped item lands among the others: before the first one whose middle is past
---the pointer. `spans` hold the other items only, top to bottom or left to right, so the
---answer is the index `move_card` and `move_column` take.
---@param spans Kanban.Span[]
---@param pos number
---@return integer
function M.drop_index (spans, pos)
  for i, s in ipairs (spans) do
    if pos < s.top + s.h / 2 then
      return i
    end
  end
  return #spans + 1
end

---The span under the pointer, or the nearest one, or nil when there are none.
---@param spans Kanban.Span[]
---@param pos number
---@return integer?
function M.span_at (spans, pos)
  local best, best_gap = nil, math.huge ---@type integer?, number
  for i, s in ipairs (spans) do
    if pos >= s.top and pos < s.top + s.h then
      return i
    end
    local gap = pos < s.top and s.top - pos or pos - (s.top + s.h)
    if gap < best_gap then
      best, best_gap = i, gap
    end
  end
  return best
end

---How fast to scroll while dragging near an edge: negative near `lo`, positive near `hi`,
---growing to `max` at the edge itself, and zero elsewhere.
---@param pos number
---@param lo number
---@param hi number
---@param zone number
---@param max number
---@return number
function M.edge_speed (pos, lo, hi, zone, max)
  if hi - lo < zone * 2 then
    return 0
  end
  if pos < lo + zone then
    local f = math.min (1, (lo + zone - pos) / zone)
    return -math.ceil (max * f)
  end
  if pos > hi - zone then
    local f = math.min (1, (pos - (hi - zone)) / zone)
    return math.ceil (max * f)
  end
  return 0
end

-- Files --------------------------------------------------------------------------------------

---@type table<string, boolean>
local RESERVED = { con = true, prn = true, aux = true, nul = true }

---A file name for a board title, without the `.json`. Characters Windows refuses go.
---@param title string
---@return string
function M.file_name (title)
  local name = (title or ''):gsub ('[%c\\/:%*%?"<>|]', ' ')
  name = trim ((name:gsub ('%s+', ' ')))
  name = name:gsub ('[%.%s]+$', ''):gsub ('^%.+', '')
  if #name > 60 then
    name = trim (name:sub (1, 60))
  end
  local low = name:lower ()
  if RESERVED[low] or low:match ('^com%d$') or low:match ('^lpt%d$') then
    name = name .. ' board'
  end
  return name ~= '' and name or 'Board'
end

---`name`, or `name 2`, `name 3` and so on when that is taken. Case does not count.
---@param name string
---@param taken table<string, boolean> Names in lower case.
---@return string
function M.unique_name (name, taken)
  if not taken[name:lower ()] then
    return name
  end
  local n = 2
  while taken[(name .. ' ' .. n):lower ()] do
    n = n + 1
  end
  return name .. ' ' .. n
end

---@type table<string, string>
local ESCAPES = {
  ['"'] = '\\"',
  ['\\'] = '\\\\',
  ['\n'] = '\\n',
  ['\r'] = '\\r',
  ['\t'] = '\\t',
  ['\b'] = '\\b',
  ['\f'] = '\\f',
}

---@param s string
---@return string
local function quote (s)
  local body = s:gsub ('[%c"\\]', function (c)
    return ESCAPES[c] or string.format ('\\u%04x', c:byte ())
  end)
  return '"' .. body .. '"'
end

---@param n number
---@return string
local function number_text (n)
  if n == math.floor (n) and math.abs (n) < 2 ^ 53 then
    return string.format ('%d', n)
  end
  return string.format ('%.17g', n)
end

---@param ids string[]
---@return string
local function quote_list (ids)
  local parts = {} ---@type string[]
  for i, id in ipairs (ids) do
    parts[i] = quote (id)
  end
  return '[' .. table.concat (parts, ', ') .. ']'
end

---The text of a board file. Keys keep a fixed order and an empty list saves as `[]`, so the
---file reads well and changes little from one save to the next.
---@param board Kanban.Board
---@return string
function M.encode (board)
  local out = {} ---@type string[]
  ---@param line string
  local function put (line)
    out[#out + 1] = line
  end
  put ('{')
  put ('  "version": ' .. number_text (board.version) .. ',')
  put ('  "title": ' .. quote (board.title) .. ',')
  put ('  "labels": [')
  for i, label in ipairs (board.labels) do
    put (
      '    { "id": '
        .. quote (label.id)
        .. ', "name": '
        .. quote (label.name)
        .. ' }'
        .. (i < #board.labels and ',' or '')
    )
  end
  put ('  ],')
  if #board.columns == 0 then
    put ('  "columns": []')
  else
    put ('  "columns": [')
    for ci, column in ipairs (board.columns) do
      put ('    {')
      put ('      "id": ' .. quote (column.id) .. ',')
      put ('      "title": ' .. quote (column.title) .. ',')
      if column.limit then
        put ('      "limit": ' .. number_text (column.limit) .. ',')
      end
      if #column.cards == 0 then
        put ('      "cards": []')
      else
        put ('      "cards": [')
        for i, card in ipairs (column.cards) do
          put ('        {')
          put ('          "id": ' .. quote (card.id) .. ',')
          put ('          "title": ' .. quote (card.title) .. ',')
          put ('          "notes": ' .. quote (card.notes) .. ',')
          put ('          "labels": ' .. quote_list (card.labels) .. ',')
          if card.due then
            put ('          "due": ' .. quote (card.due) .. ',')
          end
          put ('          "created": ' .. number_text (card.created))
          put ('        }' .. (i < #column.cards and ',' or ''))
        end
        put ('      ]')
      end
      put ('    }' .. (ci < #board.columns and ',' or ''))
    end
    put ('  ]')
  end
  put ('}')
  return table.concat (out, '\n') .. '\n'
end

---The board written on first start, which shows labels, a limit, due dates and notes.
---@param new_id Kanban.NewId
---@param now number
---@param today string
---@return Kanban.Board
function M.example (new_id, now, today)
  ---@param title string
  ---@param labels string[]
  ---@param due string?
  ---@param notes string?
  ---@return Kanban.Card
  local function card (title, labels, due, notes)
    return {
      id = new_id (),
      title = title,
      notes = notes or '',
      labels = labels,
      due = due,
      created = now,
    }
  end
  ---@type table<string, string>
  local names = {
    red = 'Bug',
    orange = 'Urgent',
    yellow = 'Idea',
    green = 'Ready',
    blue = 'Design',
    purple = 'Research',
  }
  local labels = start_labels ()
  for _, label in ipairs (labels) do
    label.name = names[label.id] or ''
  end
  return {
    version = M.VERSION,
    title = 'Getting started',
    labels = labels,
    columns = {
      {
        id = new_id (),
        title = 'To do',
        cards = {
          card (
            'Drag a card to another column',
            {},
            nil,
            'Hold the mouse button down on a card and move it. A gap shows '
              .. 'where it will land.\n\nAlt and the arrow keys move the '
              .. 'selected card too.'
          ),
          card (
            'Plan the launch',
            { 'orange' },
            M.add_days (today, 1),
            '- Pick a date\n- Book the room\n- Tell the team'
          ),
          card ('Try a dark theme', { 'yellow' }, M.add_days (today, 9)),
        },
      },
      {
        id = new_id (),
        title = 'Doing',
        limit = 3,
        cards = {
          card (
            'Click a card to open it',
            { 'green' },
            nil,
            'The panel on the right changes the title, the labels, the due '
              .. 'date and these notes.\n\nNotes use **Markdown**. Press '
              .. 'Preview to see them formatted.'
          ),
          card (
            'Fix the sign-in bug',
            { 'red', 'orange' },
            M.add_days (today, -1),
            'The due date has passed, so the badge shows red.'
          ),
        },
      },
      {
        id = new_id (),
        title = 'Done',
        cards = {
          card ('Make a board', { 'green' }),
        },
      },
    },
  }
end

-- Undo history -------------------------------------------------------------------------------

---@param board Kanban.Board
---@param limit? integer
---@return Kanban.History
function M.history_new (board, limit)
  return {
    past = {},
    present = board,
    future = {},
    limit = limit or M.HISTORY_LIMIT,
  }
end

---Makes `board` the present board. A change with the same `merge` key as the one before
---replaces it instead of adding a step, so typing a title makes one step. Returns false
---when `board` is the present board already.
---@param h Kanban.History
---@param board Kanban.Board
---@param merge? string
---@return boolean
function M.history_push (h, board, merge)
  if board == h.present then
    return false
  end
  h.future = {}
  if merge and merge == h.merge and #h.past > 0 then
    h.present = board
    return true
  end
  h.past[#h.past + 1] = h.present
  while #h.past > h.limit do
    table.remove (h.past, 1)
  end
  h.present = board
  h.merge = merge
  return true
end

---Ends a burst of merged changes, so the next change makes a step of its own.
---@param h Kanban.History
function M.history_seal (h)
  h.merge = nil
end

---Steps back. Returns the board now present, or nil when there is nothing to undo.
---@param h Kanban.History
---@return Kanban.Board?
function M.history_undo (h)
  local board = h.past[#h.past]
  if not board then
    return nil
  end
  h.past[#h.past] = nil
  h.future[#h.future + 1] = h.present
  h.present = board
  h.merge = nil
  return board
end

---Steps forward again. Returns the board now present, or nil when there is nothing to redo.
---@param h Kanban.History
---@return Kanban.Board?
function M.history_redo (h)
  local board = h.future[#h.future]
  if not board then
    return nil
  end
  h.future[#h.future] = nil
  h.past[#h.past + 1] = h.present
  h.present = board
  h.merge = nil
  return board
end

return M
