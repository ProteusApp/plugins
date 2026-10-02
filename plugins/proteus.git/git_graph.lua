-- git_graph: lays out the lines of the history graph beside the History view's rows. Each
-- commit sits in a lane, and lines run from it down to its parents. It calls no host function
-- and draws nothing but SVG text, so the tests reach all of it.
--
-- The commits come in the order `git log --date-order` prints, where every commit comes after
-- all its children. A lane waits for the commit it points at, and the commit takes the first
-- lane waiting for it. Its first parent takes over that lane, and each other parent gets the
-- lane already waiting for it or the first free one.

---One line in a row. `x1` and `x2` are lanes, counted from 0. `y1` and `y2` are 0 for the
---top of the row, 1 for the middle, where the commit's dot is, and 2 for the bottom.
---@class Git.GraphLine
---@field x1 integer
---@field y1 integer
---@field x2 integer
---@field y2 integer
---@field lane integer The lane whose colour it takes.

---@class Git.GraphRow
---@field col integer The commit's lane, counted from 0.
---@field merge boolean True for a commit with more than one parent.
---@field width integer How many lanes the row uses.
---@field lines Git.GraphLine[]

---@class Git.GraphModule
local M = {}

-- How many lane colours the CSS defines, as `.git-lane-0` to `.git-lane-7`.
M.COLORS = 8
-- Pixels across a lane, and down a row.
M.LANE = 12
M.HEIGHT = 46
-- Rows wider than this many lanes are cut at the edge.
M.MAX_LANES = 12

---@param lanes (string|false)[]
---@param hash string
---@return integer?
local function find (lanes, hash)
  for i, h in ipairs (lanes) do
    if h == hash then
      return i
    end
  end
  return nil
end

---@param lanes (string|false)[]
---@return integer
local function free (lanes)
  for i, h in ipairs (lanes) do
    if not h then
      return i
    end
  end
  return #lanes + 1
end

---@param lanes (string|false)[]
local function trim (lanes)
  while #lanes > 0 and not lanes[#lanes] do
    lanes[#lanes] = nil
  end
end

---Lays out the graph for a list of commits, one row each.
---@param commits { hash: string, parents?: string[] }[]
---@return Git.GraphRow[]
function M.layout (commits)
  local lanes = {} ---@type (string|false)[]
  local rows = {} ---@type Git.GraphRow[]
  for _, c in ipairs (commits) do
    local lines = {} ---@type Git.GraphLine[]
    local col = find (lanes, c.hash)
    -- The lanes from the row above: the ones waiting for this commit join its dot, and the
    -- others pass by.
    for i, h in ipairs (lanes) do
      if h == c.hash then
        lines[#lines + 1] =
          { x1 = i - 1, y1 = 0, x2 = (col or i) - 1, y2 = 1, lane = i - 1 }
        lanes[i] = false
      elseif h then
        lines[#lines + 1] =
          { x1 = i - 1, y1 = 0, x2 = i - 1, y2 = 2, lane = i - 1 }
      end
    end
    -- A commit nothing waits for, such as a branch's newest, starts a lane of its own.
    col = col or free (lanes)
    local parents = c.parents or {}
    if parents[1] then
      lanes[col] = parents[1]
      lines[#lines + 1] =
        { x1 = col - 1, y1 = 1, x2 = col - 1, y2 = 2, lane = col - 1 }
    else
      lanes[col] = false
    end
    for k = 2, #parents do
      local j = find (lanes, parents[k])
      if not j then
        j = free (lanes)
        lanes[j] = parents[k]
      end
      lines[#lines + 1] =
        { x1 = col - 1, y1 = 1, x2 = j - 1, y2 = 2, lane = j - 1 }
    end
    local width = math.max (#lanes, col)
    trim (lanes)
    for _, l in ipairs (lines) do
      width = math.max (width, l.x1 + 1, l.x2 + 1)
    end
    rows[#rows + 1] =
      { col = col - 1, merge = #parents > 1, width = width, lines = lines }
  end
  return rows
end

---@param lane integer
---@return number
local function x_of (lane)
  return lane * M.LANE + M.LANE / 2
end

---@param y integer
---@return number
local function y_of (y)
  return y * M.HEIGHT / 2
end

---One row's graph as an SVG element. A line that changes lane bends with a curve.
---@param row Git.GraphRow
---@param lanes? integer How many lanes wide to draw it, so every row lines up. `row.width` when nil.
---@return string
function M.svg (row, lanes)
  local n = math.min (lanes or row.width, M.MAX_LANES)
  local w = math.max (n, 1) * M.LANE
  local out = {
    '<svg class="git-graph" width="'
      .. w
      .. '" height="'
      .. M.HEIGHT
      .. '" viewBox="0 0 '
      .. w
      .. ' '
      .. M.HEIGHT
      .. '" aria-hidden="true">',
  }
  for _, l in ipairs (row.lines) do
    local x1, y1, x2, y2 = x_of (l.x1), y_of (l.y1), x_of (l.x2), y_of (l.y2)
    local d ---@type string
    if x1 == x2 then
      d = string.format ('M%g %gL%g %g', x1, y1, x2, y2)
    else
      local mid = (y1 + y2) / 2
      d = string.format (
        'M%g %gC%g %g %g %g %g %g',
        x1,
        y1,
        x1,
        mid,
        x2,
        mid,
        x2,
        y2
      )
    end
    out[#out + 1] = '<path class="git-lane-'
      .. (l.lane % M.COLORS)
      .. '" d="'
      .. d
      .. '"/>'
  end
  out[#out + 1] = string.format (
    '<circle class="git-dot git-lane-%d%s" cx="%g" cy="%g" r="4"/>',
    row.col % M.COLORS,
    row.merge and ' git-dot-merge' or '',
    x_of (row.col),
    y_of (1)
  )
  out[#out + 1] = '</svg>'
  return table.concat (out)
end

---Every row's SVG, all as wide as the widest row, for `log_html`.
---@param commits { hash: string, parents?: string[] }[]
---@return string[]
function M.rows_svg (commits)
  local rows = M.layout (commits)
  local widest = 1
  for _, r in ipairs (rows) do
    widest = math.max (widest, r.width)
  end
  local out = {} ---@type string[]
  for i, r in ipairs (rows) do
    out[i] = M.svg (r, widest)
  end
  return out
end

return M
