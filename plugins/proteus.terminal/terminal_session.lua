-- terminal_session: what each terminal keeps through a reload of the window, and the tabs
-- built again from it. The app keeps a terminal's program running while the window reloads,
-- with a short text the plugin gave it. That text says where the terminal sat: its tab, its
-- place in the tab, and whether it had the focus. Nothing here touches the app, so the tests
-- load it as it is.

---What a terminal keeps through a reload.
---@class Terminal.Saved
---@field group integer Its tab's place, from 1.
---@field pane integer Its place in its tab, from 1.
---@field front boolean Its tab was in front.
---@field focus boolean It had the focus in its tab.
---@field name? string The name the user gave it.
---@field title string
---@field cwd string
---@field profile string
---@field task? string The label of the task it runs.

---A terminal that waits after the reload, with what it kept.
---@class Terminal.Waiting
---@field id integer
---@field saved? Terminal.Saved Nil when what it kept cannot be read.
---@field meta? string The text it kept.
---@field ended boolean

---One tab to build again.
---@class Terminal.SavedGroup
---@field items Terminal.Waiting[] From left to right.
---@field focus integer The place of the one with the focus.

---@class Terminal.Session
local M = {}

---Where a terminal sits now, for its saved text.
---@param state Terminal.GroupState
---@param term integer
---@return { group: integer, pane: integer, front: boolean, focus: boolean }?
function M.place (state, term)
  for gi, g in ipairs (state.list) do
    for pi, t in ipairs (g.panes) do
      if t == term then
        return {
          group = gi,
          pane = pi,
          front = g.id == state.active,
          focus = g.focus == term,
        }
      end
    end
  end
  return nil
end

---@param value any
---@return string?
local function text (value)
  return type (value) == 'string' and value or nil
end

---@param value any
---@return integer
local function place (value)
  local n = tonumber (value)
  if not n or n < 1 then
    return 1
  end
  return math.floor (n)
end

---What a terminal kept, from the decoded text, or nil when it is not a table.
---@param value any
---@return Terminal.Saved?
function M.read (value)
  if type (value) ~= 'table' then
    return nil
  end
  local name = text (value.name)
  local task = text (value.task)
  return {
    group = place (value.group),
    pane = place (value.pane),
    front = value.front == true,
    focus = value.focus == true,
    name = name ~= '' and name or nil,
    title = text (value.title) or 'Terminal',
    cwd = text (value.cwd) or '',
    profile = text (value.profile) or '',
    task = task ~= '' and task or nil,
  }
end

---The tabs to build again, in order, and the place of the one in front. Terminals that kept
---the same tab share it, in the order of their places. A terminal whose text cannot be read
---gets a tab of its own at the end.
---@param waiting Terminal.Waiting[]
---@return Terminal.SavedGroup[] groups
---@return integer? front
function M.layout (waiting)
  local keyed = {} ---@type table<integer, Terminal.Waiting[]>
  local order = {} ---@type integer[]
  local loose = {} ---@type Terminal.Waiting[]
  for _, w in ipairs (waiting) do
    if w.saved then
      local g = w.saved.group
      if not keyed[g] then
        keyed[g] = {}
        order[#order + 1] = g
      end
      local list = keyed[g]
      list[#list + 1] = w
    else
      loose[#loose + 1] = w
    end
  end
  table.sort (order)
  local groups = {} ---@type Terminal.SavedGroup[]
  local front = nil ---@type integer?
  for _, g in ipairs (order) do
    local items = keyed[g]
    -- A stable sort by place: ties keep the order the terminals were opened in.
    ---@param w Terminal.Waiting
    ---@return Terminal.Saved
    local function saved_of (w)
      return w.saved --[[@as Terminal.Saved]]
    end
    for i = 2, #items do
      local item = items[i]
      local j = i - 1
      while j >= 1 and saved_of (items[j]).pane > saved_of (item).pane do
        items[j + 1] = items[j]
        j = j - 1
      end
      items[j + 1] = item
    end
    local focus = 1
    for i, w in ipairs (items) do
      if saved_of (w).focus then
        focus = i
      end
      if saved_of (w).front then
        front = #groups + 1
      end
    end
    groups[#groups + 1] = { items = items, focus = focus }
  end
  for _, w in ipairs (loose) do
    groups[#groups + 1] = { items = { w }, focus = 1 }
  end
  if not front and #groups > 0 then
    front = 1
  end
  return groups, front
end

return M
