local m = require ('kanban_board') --[[@as Kanban.BoardModule]]

---Ids that count up from one, so every test sees the same ones.
---@return Kanban.NewId
local function counter ()
  local n = 0
  return function ()
    n = n + 1
    return 'id' .. n
  end
end

---@param column Kanban.Column
---@return string[]
local function titles (column)
  local out = {} ---@type string[]
  for i, card in ipairs (column.cards) do
    out[i] = card.title
  end
  return out
end

---@param board Kanban.Board
---@return string[]
local function column_titles (board)
  local out = {} ---@type string[]
  for i, column in ipairs (board.columns) do
    out[i] = column.title
  end
  return out
end

---A board with cards A to D in To do and E in Doing.
---@return Kanban.Board
---@return Kanban.NewId
local function sample ()
  local new_id = counter ()
  local board = m.new_board ('Launch', new_id)
  for _, t in ipairs ({ 'A', 'B', 'C', 'D' }) do
    board = m.add_card (board, board.columns[1].id, t, new_id, 100)
  end
  board = m.add_card (board, board.columns[2].id, 'E', new_id, 100)
  return board, new_id
end

---@param board Kanban.Board
---@param title string
---@return string
local function id_of (board, title)
  for _, column in ipairs (board.columns) do
    for _, card in ipairs (column.cards) do
      if card.title == title then
        return card.id
      end
    end
  end
  error ('no card called ' .. title)
end

test ('new_board starts with three columns and six unnamed labels', function ()
  local board = m.new_board ('  Launch  ', counter ())
  eq (board.title, 'Launch')
  eq (board.version, m.VERSION)
  eq (column_titles (board), { 'To do', 'Doing', 'Done' })
  eq (board.columns[1].id, 'id1')
  eq (#board.labels, 6)
  eq (board.labels[1], { id = 'red', name = '' })
  eq (m.new_board ('', counter ()).title, 'Untitled board')
end)

test (
  'normalize fills in missing fields and reads {} as an empty list',
  function ()
    local board = m.normalize ({
      title = 'Old',
      labels = { red = 'Bug', pink = 'Nope' },
      columns = {
        { title = 'To do', cards = {} },
        {
          id = 'c2',
          cards = {
            {
              id = 'x',
              title = 'One',
              labels = { 'green', 'red', 'green', 'pink' },
            },
            { id = 'x', title = 5, due = '2026-02-30', notes = false },
            'not a card',
          },
          limit = 2.7,
        },
        { id = 'c3', cards = 'broken', limit = -1 },
      },
    }, counter ())
    eq (board.title, 'Old')
    eq (board.version, m.VERSION)
    eq (board.labels[1], { id = 'red', name = 'Bug' })
    eq (board.labels[2], { id = 'orange', name = '' })
    eq (#board.labels, 6)
    eq (#board.columns, 3)
    eq (board.columns[1].id, 'id1')
    eq (board.columns[1].cards, {})
    local second = board.columns[2]
    eq (second.title, 'Untitled')
    eq (second.limit, 2)
    eq (#second.cards, 2)
    eq (second.cards[1].labels, { 'red', 'green' })
    eq (second.cards[1].notes, '')
    eq (second.cards[1].created, 0)
    eq (second.cards[2].id, 'id2', 'a taken id gets a new one')
    eq (second.cards[2].title, '5')
    eq (second.cards[2].due, nil, 'February has no 30th')
    eq (board.columns[3].cards, {})
    eq (board.columns[3].limit, nil)
  end
)

test ('normalize takes labels as a list and survives anything', function ()
  local board = m.normalize ({
    labels = { { id = 'blue', name = 'Design' } },
    columns = {},
  }, counter ())
  eq (board.labels[5], { id = 'blue', name = 'Design' })
  eq (board.title, 'Untitled board')
  eq (board.columns, {})
  eq (#m.normalize (nil, counter ()).labels, 6)
  eq (m.normalize ('text', counter ()).columns, {})
end)

test ('normalize keeps a sound board as it is', function ()
  local new_id = counter ()
  local board = m.example (new_id, 5, '2026-09-29')
  eq (m.normalize (board, new_id), board)
end)

test ('column changes return new boards and leave the old one alone', function ()
  local new_id = counter ()
  local board = m.new_board ('B', new_id)
  local added, id = m.add_column (board, ' Review ', new_id)
  eq (column_titles (board), { 'To do', 'Doing', 'Done' })
  eq (column_titles (added), { 'To do', 'Doing', 'Done', 'Review' })
  eq (id, 'id4')
  ok (added.columns[1] == board.columns[1], 'unchanged columns are shared')
  local same, none = m.add_column (board, '   ', new_id)
  ok (same == board and none == nil, 'an empty title adds nothing')

  local renamed = m.rename_column (added, 'id4', 'Check')
  eq (renamed.columns[4].title, 'Check')
  eq (added.columns[4].title, 'Review')
  ok (m.rename_column (added, 'id4', 'Review') == added)
  ok (m.rename_column (added, 'id4', '') == added)
  ok (m.rename_column (added, 'nope', 'X') == added)

  local limited = m.set_limit (added, 'id4', 3.9)
  eq (limited.columns[4].limit, 3)
  eq (m.set_limit (limited, 'id4', 0).columns[4].limit, nil)
  eq (m.set_limit (limited, 'id4', nil).columns[4].limit, nil)
  ok (m.set_limit (limited, 'id4', 3) == limited)

  local moved = m.move_column (added, 'id4', 1)
  eq (column_titles (moved), { 'Review', 'To do', 'Doing', 'Done' })
  eq (
    column_titles (m.move_column (moved, 'id4', 99)),
    { 'To do', 'Doing', 'Done', 'Review' }
  )
  ok (m.move_column (added, 'id4', 4) == added)

  local removed = m.remove_column (added, added.columns[2].id)
  eq (column_titles (removed), { 'To do', 'Done', 'Review' })
  ok (m.remove_column (added, 'nope') == added)
end)

test ('over_limit is true only past the limit', function ()
  local board = sample ()
  local column = board.columns[1]
  ok (not m.over_limit (column), 'no limit')
  ok (not m.over_limit (m.set_limit (board, column.id, 4).columns[1]))
  ok (m.over_limit (m.set_limit (board, column.id, 3).columns[1]))
end)

test ('add_card puts a card at the end or at a given place', function ()
  local new_id = counter ()
  local board = m.new_board ('B', new_id)
  local todo = board.columns[1].id
  local one, id = m.add_card (board, todo, ' First ', new_id, 42)
  eq (id, 'id4')
  eq (
    one.columns[1].cards[1],
    { id = 'id4', title = 'First', notes = '', labels = {}, created = 42 }
  )
  eq (#board.columns[1].cards, 0, 'the old board is untouched')
  ok (one.columns[2] == board.columns[2], 'other columns are shared')
  local two = m.add_card (one, todo, 'Top', new_id, 43, 1)
  eq (titles (two.columns[1]), { 'Top', 'First' })
  local same, none = m.add_card (two, todo, '  ', new_id, 44)
  ok (same == two and none == nil)
  ok ((m.add_card (two, 'nope', 'X', new_id, 44)) == two)
end)

test ('update_card changes only what it is given', function ()
  local board = sample ()
  local a = id_of (board, 'A')
  local changed = m.update_card (
    board,
    a,
    { title = ' Alpha ', notes = 'Some *notes*', due = '2026-10-01' }
  )
  local card = changed.columns[1].cards[1]
  eq (card.title, 'Alpha')
  eq (card.notes, 'Some *notes*')
  eq (card.due, '2026-10-01')
  eq (board.columns[1].cards[1].title, 'A')
  ok (changed.columns[1].cards[2] == board.columns[1].cards[2])
  ok (changed.columns[2] == board.columns[2])

  eq (m.update_card (changed, a, { due = '' }).columns[1].cards[1].due, nil)
  eq (m.update_card (changed, a, { due = 'soon' }).columns[1].cards[1].due, nil)
  eq (
    m.update_card (changed, a, { title = '  ' }).columns[1].cards[1].title,
    'Alpha'
  )
  ok (
    m.update_card (changed, a, { title = 'Alpha', due = '2026-10-01' })
      == changed
  )
  ok (m.update_card (changed, 'nope', { title = 'X' }) == changed)

  local labelled =
    m.update_card (board, a, { labels = { 'blue', 'red', 'odd' } })
  eq (labelled.columns[1].cards[1].labels, { 'red', 'blue' })
  ok (m.update_card (labelled, a, { labels = { 'red', 'blue' } }) == labelled)
end)

test ('toggle_label puts a label on and takes it off', function ()
  local board = sample ()
  local a = id_of (board, 'A')
  local on = m.toggle_label (board, a, 'green')
  on = m.toggle_label (on, a, 'red')
  eq (on.columns[1].cards[1].labels, { 'red', 'green' })
  local off = m.toggle_label (on, a, 'red')
  eq (off.columns[1].cards[1].labels, { 'green' })
  eq (on.columns[1].cards[1].labels, { 'red', 'green' })
end)

test ('moving down in the same column lands where the gap showed', function ()
  local board = sample ()
  local todo = board.columns[1]
  -- Cards A to D stand 50 pixels apart. A is picked up, so the others are B, C and D.
  local others = {
    { top = 50, h = 40 },
    { top = 100, h = 40 },
    { top = 150, h = 40 },
  }
  -- The pointer sits below the middle of C and above the middle of D.
  local at = m.drop_index (others, 160)
  eq (at, 3)
  local moved = m.move_card (board, id_of (board, 'A'), todo.id, at)
  eq (titles (moved.columns[1]), { 'B', 'C', 'A', 'D' })
  eq (titles (board.columns[1]), { 'A', 'B', 'C', 'D' })
  ok (moved.columns[2] == board.columns[2])

  local last = m.move_card (board, id_of (board, 'A'), todo.id, 4)
  eq (titles (last.columns[1]), { 'B', 'C', 'D', 'A' })
  local up = m.move_card (board, id_of (board, 'D'), todo.id, 2)
  eq (titles (up.columns[1]), { 'A', 'D', 'B', 'C' })
  ok (m.move_card (board, id_of (board, 'B'), todo.id, 2) == board, 'no move')
end)

test ('move_card moves across columns and clamps the place', function ()
  local board = sample ()
  local doing = board.columns[2].id
  local moved = m.move_card (board, id_of (board, 'B'), doing, 1)
  eq (titles (moved.columns[1]), { 'A', 'C', 'D' })
  eq (titles (moved.columns[2]), { 'B', 'E' })
  local far = m.move_card (board, id_of (board, 'B'), doing, 50)
  eq (titles (far.columns[2]), { 'E', 'B' })
  local done = m.move_card (board, id_of (board, 'E'), board.columns[3].id, 0)
  eq (titles (done.columns[3]), { 'E' })
  eq (titles (done.columns[2]), {})
  ok (moved.columns[3] == board.columns[3])
  ok (m.move_card (board, 'nope', doing, 1) == board)
  ok (m.move_card (board, id_of (board, 'A'), 'nope', 1) == board)
end)

test ('nudge moves the card one step and stops at the edges', function ()
  local board = sample ()
  local b = id_of (board, 'B')
  eq (titles (m.nudge (board, b, 'up').columns[1]), { 'B', 'A', 'C', 'D' })
  eq (titles (m.nudge (board, b, 'down').columns[1]), { 'A', 'C', 'B', 'D' })
  local right = m.nudge (board, b, 'right')
  eq (titles (right.columns[2]), { 'E', 'B' }, 'keeps its place where it can')
  local d = id_of (board, 'D')
  local over = m.nudge (m.nudge (board, d, 'right'), d, 'right')
  eq (titles (over.columns[3]), { 'D' })
  ok (m.nudge (board, id_of (board, 'A'), 'up') == board)
  ok (m.nudge (board, d, 'down') == board)
  ok (m.nudge (board, d, 'left') == board)
  ok (m.nudge (over, d, 'right') == over)
end)

test ('remove_card, duplicate_card and find_card', function ()
  local board, new_id = sample ()
  local c = id_of (board, 'C')
  local found = assert (m.find_card (board, c))
  eq (found.index, 3)
  eq (found.column_index, 1)
  eq (found.card.title, 'C')
  eq (m.find_card (board, 'nope'), nil)

  local removed = m.remove_card (board, c)
  eq (titles (removed.columns[1]), { 'A', 'B', 'D' })
  ok (m.remove_card (board, 'nope') == board)

  local tagged = m.toggle_label (board, c, 'blue')
  local copied, copy_id = m.duplicate_card (tagged, c, new_id, 999)
  eq (titles (copied.columns[1]), { 'A', 'B', 'C', 'C', 'D' })
  local copy = copied.columns[1].cards[4]
  eq (copy.id, copy_id)
  ok (copy.id ~= c)
  eq (copy.created, 999)
  eq (copy.labels, { 'blue' })
  ok (
    copy.labels ~= copied.columns[1].cards[3].labels,
    'the copy has its own list'
  )
  local same, none = m.duplicate_card (board, 'nope', new_id, 1)
  ok (same == board and none == nil)
end)

test ('labels can be renamed per board', function ()
  local board = sample ()
  eq (m.label_name (board.labels, 'red'), 'Red')
  local renamed = m.rename_label (board, 'red', ' Bug ')
  eq (m.label_name (renamed.labels, 'red'), 'Bug')
  eq (m.label_name (board.labels, 'red'), 'Red')
  ok (renamed.columns == board.columns, 'the cards are shared')
  ok (m.rename_label (renamed, 'red', 'Bug') == renamed)
  eq (m.label_name (m.rename_label (renamed, 'red', '').labels, 'red'), 'Red')
  eq (m.set_title (board, ' New ').title, 'New')
  ok (m.set_title (board, '  ') == board)
end)

test ('matches looks at the title, the notes and the labels', function ()
  local board = m.rename_label (sample (), 'red', 'Bug')
  ---@type Kanban.Card
  local card = {
    id = 'x',
    title = 'Fix the Login page',
    notes = 'Crashes on **Safari**',
    labels = { 'red', 'green' },
    created = 0,
  }
  ok (m.matches (card, '', board.labels))
  ok (m.matches (card, nil, board.labels))
  ok (m.matches (card, 'login', board.labels))
  ok (m.matches (card, 'SAFARI', board.labels))
  ok (m.matches (card, 'bug', board.labels), 'a label name')
  ok (m.matches (card, 'green', board.labels), 'a colour')
  ok (m.matches (card, '  fix   safari ', board.labels), 'every word')
  ok (not m.matches (card, 'fix chrome', board.labels))
  ok (m.matches (card, '', board.labels, 'red'), 'the label filter')
  ok (not m.matches (card, '', board.labels, 'blue'))
  ok (not m.matches (card, 'login', board.labels, 'blue'))
  ok (m.matches (card, 'login', board.labels, ''))
end)

test ('due dates: states, labels and day sums', function ()
  ---@param due string?
  ---@return Kanban.Card
  local function card (due)
    return {
      id = 'x',
      title = 'x',
      notes = '',
      labels = {},
      due = due,
      created = 0,
    }
  end
  local today = '2026-09-29'
  eq (m.due_state (card (nil), today), nil)
  eq (m.due_state (card ('2026-09-28'), today), 'overdue')
  eq (m.due_state (card ('2025-12-31'), today), 'overdue')
  eq (m.due_state (card ('2026-09-29'), today), 'soon')
  eq (m.due_state (card ('2026-09-30'), today), 'soon')
  eq (m.due_state (card ('2026-10-01'), today), 'later')
  eq (m.due_state (card ('2026-12-31'), '2026-12-30'), 'soon')
  eq (m.due_state (card ('2027-01-01'), '2026-12-31'), 'soon')

  eq (m.add_days ('2026-09-29', 1), '2026-09-30')
  eq (m.add_days ('2026-09-30', 1), '2026-10-01')
  eq (m.add_days ('2026-12-31', 1), '2027-01-01')
  eq (m.add_days ('2028-02-28', 1), '2028-02-29')
  eq (m.add_days ('2027-02-28', 1), '2027-03-01')
  eq (m.add_days ('2026-01-01', -1), '2025-12-31')
  eq (m.add_days ('2026-03-01', 365), '2027-03-01')
  eq (m.add_days ('nonsense', 3), 'nonsense')

  ok (m.valid_date ('2028-02-29'))
  ok (not m.valid_date ('2027-02-29'))
  ok (not m.valid_date ('2026-13-01'))
  ok (not m.valid_date ('2026-4-01'))
  ok (not m.valid_date (20260401))

  eq (m.due_label ('2026-09-29', today), 'Today')
  eq (m.due_label ('2026-09-30', today), 'Tomorrow')
  eq (m.due_label ('2026-09-28', today), 'Yesterday')
  eq (m.due_label ('2026-10-05', today), 'Oct 5')
  eq (m.due_label ('2027-01-15', today), 'Jan 15, 2027')
end)

test ('counts adds up cards, overdue cards and cards due soon', function ()
  local board = sample ()
  board = m.update_card (board, id_of (board, 'A'), { due = '2026-09-01' })
  board = m.update_card (board, id_of (board, 'B'), { due = '2026-09-29' })
  board = m.update_card (board, id_of (board, 'E'), { due = '2026-09-20' })
  eq (m.counts (board, '2026-09-29'), { cards = 5, overdue = 2, soon = 1 })
  eq (
    m.counts (m.new_board ('x', counter ()), '2026-09-29'),
    { cards = 0, overdue = 0, soon = 0 }
  )
end)

test ('drop_index, span_at and edge_speed work out a drag', function ()
  local spans =
    { { top = 0, h = 40 }, { top = 50, h = 60 }, { top = 120, h = 20 } }
  eq (m.drop_index (spans, -10), 1)
  eq (m.drop_index (spans, 19), 1)
  eq (m.drop_index (spans, 21), 2)
  eq (m.drop_index (spans, 79), 2)
  eq (m.drop_index (spans, 81), 3)
  eq (m.drop_index (spans, 131), 4)
  eq (m.drop_index ({}, 50), 1, 'an empty column takes the card first')

  local columns = { { top = 10, h = 100 }, { top = 120, h = 100 } }
  eq (m.span_at (columns, 50), 1)
  eq (m.span_at (columns, 150), 2)
  eq (m.span_at (columns, 114), 1, 'the gap goes to the nearest')
  eq (m.span_at (columns, 116), 2)
  eq (m.span_at (columns, 900), 2)
  eq (m.span_at (columns, -50), 1)
  eq (m.span_at ({}, 5), nil)

  eq (m.edge_speed (500, 0, 1000, 60, 20), 0)
  eq (m.edge_speed (0, 0, 1000, 60, 20), -20)
  eq (m.edge_speed (30, 0, 1000, 60, 20), -10)
  eq (m.edge_speed (-40, 0, 1000, 60, 20), -20)
  eq (m.edge_speed (1000, 0, 1000, 60, 20), 20)
  eq (m.edge_speed (970, 0, 1000, 60, 20), 10)
  eq (m.edge_speed (10, 0, 100, 60, 20), 0, 'too narrow to scroll')
end)

test ('the history undoes and redoes, and keeps 100 steps', function ()
  local new_id = counter ()
  local first = m.new_board ('B', new_id)
  local h = m.history_new (first)
  eq (h.limit, 100)
  eq (m.history_undo (h), nil)
  local second = m.add_column (first, 'Two', new_id)
  ok (m.history_push (h, second))
  ok (not m.history_push (h, second), 'the same board is no change')
  ok (m.history_undo (h) == first)
  ok (h.present == first)
  ok (m.history_redo (h) == second)
  eq (m.history_redo (h), nil)
  m.history_undo (h)
  local third = m.add_column (first, 'Three', new_id)
  m.history_push (h, third)
  eq (m.history_redo (h), nil, 'a new change drops the redo steps')

  local long = m.history_new (first)
  local board = first
  for i = 1, 105 do
    board = m.set_title (board, 'Title ' .. i)
    m.history_push (long, board)
  end
  eq (#long.past, 100)
  local steps = 0
  while m.history_undo (long) do
    steps = steps + 1
  end
  eq (steps, 100)
  eq (long.present.title, 'Title 5')
end)

test ('changes with the same merge key make one undo step', function ()
  local board = sample ()
  local a = id_of (board, 'A')
  local h = m.history_new (board)
  local typed = board
  for _, text in ipairs ({ 'Al', 'Alp', 'Alpha' }) do
    typed = m.update_card (typed, a, { title = text })
    m.history_push (h, typed, 'title:' .. a)
  end
  eq (#h.past, 1)
  eq (h.present.columns[1].cards[1].title, 'Alpha')
  m.history_seal (h)
  m.history_push (
    h,
    m.update_card (typed, a, { title = 'Alpha!' }),
    'title:' .. a
  )
  eq (#h.past, 2, 'a sealed burst ends the step')
  m.history_push (h, m.nudge (h.present, a, 'down'))
  m.history_push (
    h,
    m.update_card (h.present, a, { notes = 'x' }),
    'notes:' .. a
  )
  eq (#h.past, 4)
  ok (m.history_undo (h))
  ok (m.history_undo (h))
  ok (m.history_undo (h))
  ok (m.history_undo (h) == board)
end)

test (
  'file_name makes a safe file name and unique_name avoids clashes',
  function ()
    eq (m.file_name ('Launch'), 'Launch')
    eq (m.file_name ('  Q3: plans / ideas?  '), 'Q3 plans ideas')
    eq (m.file_name ('ends with dots...'), 'ends with dots')
    eq (m.file_name ('...'), 'Board')
    eq (m.file_name (''), 'Board')
    eq (m.file_name ('con'), 'con board')
    eq (#m.file_name (string.rep ('x', 90)), 60)

    local taken = { launch = true, ['launch 2'] = true }
    eq (m.unique_name ('Launch', taken), 'Launch 3')
    eq (m.unique_name ('Other', taken), 'Other')
  end
)

test ('the example board shows labels, a limit, due dates and notes', function ()
  local board = m.example (counter (), 1000, '2026-09-29')
  eq (column_titles (board), { 'To do', 'Doing', 'Done' })
  eq (m.label_name (board.labels, 'red'), 'Bug')
  eq (board.columns[2].limit, 3)
  local counts = m.counts (board, '2026-09-29')
  eq (counts.overdue, 1)
  eq (counts.soon, 1)
  local notes = 0
  for _, column in ipairs (board.columns) do
    for _, card in ipairs (column.cards) do
      if card.notes ~= '' then
        notes = notes + 1
      end
    end
  end
  ok (notes >= 2, 'some cards have notes')
end)

test ('encode writes keys in a fixed order and empty lists as []', function ()
  local new_id = counter ()
  local board = m.new_board ('Launch', new_id)
  board = m.rename_label (board, 'red', 'Bug')
  board = m.set_limit (board, board.columns[2].id, 3)
  local todo = board.columns[1].id
  board = m.add_card (board, todo, 'Say "hi"', new_id, 1727600000000)
  local card = board.columns[1].cards[1].id
  board = m.update_card (board, card, {
    notes = 'Line one\nTab\there \\ done',
    labels = { 'red' },
    due = '2026-10-01',
  })
  board = m.remove_column (board, board.columns[3].id)
  local text = m.encode (board)
  local expected = table.concat ({
    '{',
    '  "version": 1,',
    '  "title": "Launch",',
    '  "labels": [',
    '    { "id": "red", "name": "Bug" },',
    '    { "id": "orange", "name": "" },',
    '    { "id": "yellow", "name": "" },',
    '    { "id": "green", "name": "" },',
    '    { "id": "blue", "name": "" },',
    '    { "id": "purple", "name": "" }',
    '  ],',
    '  "columns": [',
    '    {',
    '      "id": "id1",',
    '      "title": "To do",',
    '      "cards": [',
    '        {',
    '          "id": "id4",',
    '          "title": "Say \\"hi\\"",',
    '          "notes": "Line one\\nTab\\there \\\\ done",',
    '          "labels": ["red"],',
    '          "due": "2026-10-01",',
    '          "created": 1727600000000',
    '        }',
    '      ]',
    '    },',
    '    {',
    '      "id": "id2",',
    '      "title": "Doing",',
    '      "limit": 3,',
    '      "cards": []',
    '    }',
    '  ]',
    '}',
    '',
  }, '\n')
  eq (text, expected)
  ok (
    m.encode (m.remove_column (m.remove_column (board, 'id1'), 'id2'))
      :find ('"columns": []', 1, true)
  )
  local control = '"A' .. string.char (92) .. 'u0001B"'
  ok (m.encode (m.set_title (board, 'A\1B')):find (control, 1, true))
end)
