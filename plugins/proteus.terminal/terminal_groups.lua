-- terminal_groups: which terminals share a tab. Each tab of the Terminal panel is a group of
-- terminals split side by side, and one of them has the focus. Terminals are named by their
-- ids here, and init.lua draws what this says. Nothing here touches the app, so the tests load
-- it as it is.

---One tab: its terminals from left to right, and the one with the focus.
---@class Terminal.Group
---@field id integer
---@field panes integer[]
---@field focus integer

---@class Terminal.GroupState
---@field list Terminal.Group[]
---@field active integer? The id of the group in front.
---@field next_id integer

---@class Terminal.Groups
local M = {}

---@return Terminal.GroupState
function M.new ()
  return { list = {}, active = nil, next_id = 1 }
end

---The group that holds a terminal, and the terminal's place in it.
---@param state Terminal.GroupState
---@param term integer
---@return Terminal.Group?
---@return integer?
function M.of (state, term)
  for _, g in ipairs (state.list) do
    for i, t in ipairs (g.panes) do
      if t == term then
        return g, i
      end
    end
  end
  return nil, nil
end

---The group in front, and its terminal with the focus.
---@param state Terminal.GroupState
---@return Terminal.Group?
---@return integer?
function M.current (state)
  for _, g in ipairs (state.list) do
    if g.id == state.active then
      return g, g.focus
    end
  end
  return nil, nil
end

---Puts a terminal in a new group of its own, at the end, and brings it to the front.
---@param state Terminal.GroupState
---@param term integer
---@return Terminal.Group
function M.add (state, term)
  local g = { id = state.next_id, panes = { term }, focus = term }
  state.next_id = state.next_id + 1
  state.list[#state.list + 1] = g
  state.active = g.id
  return g
end

---Puts a terminal beside another, to its right, in the same group. With no terminal to go
---beside, it goes beside the one with the focus in the group in front, or into a new group.
---@param state Terminal.GroupState
---@param term integer
---@param beside? integer
---@return Terminal.Group
function M.split (state, term, beside)
  local g, i = nil, nil ---@type Terminal.Group?, integer?
  if beside then
    g, i = M.of (state, beside)
  end
  if not g then
    local cur, focus = M.current (state)
    if cur and focus then
      g, i = M.of (state, focus)
    end
  end
  if not g or not i then
    return M.add (state, term)
  end
  table.insert (g.panes, i + 1, term)
  g.focus = term
  state.active = g.id
  return g
end

---Gives a terminal the focus in its group, and brings the group to the front.
---@param state Terminal.GroupState
---@param term integer
---@return boolean found
function M.focus (state, term)
  local g = M.of (state, term)
  if not g then
    return false
  end
  g.focus = term
  state.active = g.id
  return true
end

---Takes a terminal away. Its group keeps the terminal to its left, or else the one to its
---right. A group left empty goes too, and the group before it comes to the front, or else
---the one after. Returns the terminal that has the focus now, or nil when none is left.
---@param state Terminal.GroupState
---@param term integer
---@return integer?
function M.remove (state, term)
  local g, i = M.of (state, term)
  if not g or not i then
    local _, focus = M.current (state)
    return focus
  end
  table.remove (g.panes, i)
  if #g.panes > 0 then
    if g.focus == term then
      g.focus = g.panes[math.max (1, i - 1)]
    end
    local _, focus = M.current (state)
    return focus
  end
  local at = 1
  for k, other in ipairs (state.list) do
    if other == g then
      at = k
      break
    end
  end
  table.remove (state.list, at)
  if state.active == g.id then
    local next_group = state.list[at - 1] or state.list[at]
    state.active = next_group and next_group.id or nil
  end
  local _, focus = M.current (state)
  return focus
end

---Every terminal, group by group, from left to right.
---@param state Terminal.GroupState
---@return integer[]
function M.all (state)
  local out = {} ---@type integer[]
  for _, g in ipairs (state.list) do
    for _, t in ipairs (g.panes) do
      out[#out + 1] = t
    end
  end
  return out
end

---The terminal `step` places away from the one with the focus, across every group and round
---the ends, or nil when there is none.
---@param state Terminal.GroupState
---@param step integer 1 for the next, -1 for the one before.
---@return integer?
function M.step (state, step)
  local all = M.all (state)
  if #all == 0 then
    return nil
  end
  local _, focus = M.current (state)
  local at = 0
  for i, t in ipairs (all) do
    if t == focus then
      at = i
      break
    end
  end
  if at == 0 then
    return all[1]
  end
  return all[(at - 1 + step) % #all + 1]
end

return M
