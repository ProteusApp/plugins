local groups = require ('terminal_groups') --[[@as Terminal.Groups]]

---The panes of each group, in order.
---@param state Terminal.GroupState
---@return integer[][]
local function shape (state)
  local out = {} ---@type integer[][]
  for i, g in ipairs (state.list) do
    out[i] = g.panes
  end
  return out
end

test (
  'add gives each terminal a tab of its own and brings it to the front',
  function ()
    local s = groups.new ()
    groups.add (s, 1)
    groups.add (s, 2)
    eq (shape (s), { { 1 }, { 2 } })
    local g, focus = groups.current (s)
    eq ({ g and g.id, focus }, { 2, 2 })
  end
)

test ('split puts a terminal to the right of the one with the focus', function ()
  local s = groups.new ()
  groups.split (s, 1)
  eq (shape (s), { { 1 } }, 'with no tab, a split opens one')
  groups.split (s, 2)
  groups.focus (s, 1)
  groups.split (s, 3)
  eq (shape (s), { { 1, 3, 2 } })
  groups.add (s, 4)
  groups.split (s, 5, 2)
  eq (shape (s), { { 1, 3, 2, 5 }, { 4 } })
  local _, focus = groups.current (s)
  eq (focus, 5)
end)

test (
  'remove passes the focus to the left, then to the right, then to another tab',
  function ()
    local s = groups.new ()
    groups.add (s, 1)
    groups.add (s, 2)
    groups.split (s, 3)
    groups.split (s, 4)
    eq (shape (s), { { 1 }, { 2, 3, 4 } })
    groups.focus (s, 3)
    eq (groups.remove (s, 3), 2)
    groups.focus (s, 2)
    eq (groups.remove (s, 2), 4)
    eq (groups.remove (s, 4), 1, 'the tab before comes to the front')
    eq (shape (s), { { 1 } })
    eq (groups.remove (s, 1), nil)
    eq (s.active, nil)
    eq (groups.remove (s, 9), nil, 'an unknown terminal changes nothing')
  end
)

test (
  'removing a terminal that is not in front leaves the front alone',
  function ()
    local s = groups.new ()
    groups.add (s, 1)
    groups.add (s, 2)
    groups.add (s, 3)
    groups.focus (s, 3)
    eq (groups.remove (s, 1), 3)
    eq (shape (s), { { 2 }, { 3 } })
    eq (groups.remove (s, 3), 2, 'the tab after comes when there is none before')
  end
)

test ('step walks every terminal round the ends', function ()
  local s = groups.new ()
  eq (groups.step (s, 1), nil)
  groups.add (s, 1)
  groups.split (s, 2)
  groups.add (s, 3)
  eq (groups.all (s), { 1, 2, 3 })
  eq (groups.step (s, 1), 1)
  eq (groups.step (s, -1), 2)
  groups.focus (s, 1)
  eq (groups.step (s, -1), 3)
end)
