local lf = require ('log_filter') --[[@as Logs.FilterModule]]
local lq = require ('log_query') --[[@as Logs.QueryModule]]
local lr = require ('log_ring') --[[@as Logs.RingModule]]

---@param n integer
---@param time? number
---@param id? integer
---@return Logs.Line
local function at (n, time, id)
  local line = lr.make_line (n, 'line ' .. n)
  line.time = time
  line.id = id
  return line
end

test ('log_filter hands out the lines and the ring of log_ring', function ()
  ok (lf.make_line == lr.make_line)
  ok (lf.ring == lr.ring)
  ok (lf.find_line == lr.find_line)
  ok (lf.index_of == lr.index_of)
  ok (lf.classify == lr.classify)
  ok (lf.scan == lr.scan)
  ok (lf.newest == lr.newest)
  ok (lf.merge == lr.merge)
end)

test ('a ring of one keeps only the newest line', function ()
  local r = lr.ring (1)
  eq (r:push (at (1)), nil)
  local dropped = r:push (at (2))
  eq (dropped and dropped.n, 1)
  eq (r:count (), 1)
  eq ((r:get (1) or {}).n, 2)
end)

test ('newest skips the lines that have no time', function ()
  local r = lr.ring (5)
  eq (lr.newest (r), nil)
  r:push (at (1, 100))
  r:push (at (2, 200))
  r:push (at (3))
  eq (lr.newest (r), 200)
end)

test ('classify counts a line a chip hides but does not show it', function ()
  local line = lr.make_line (1, 'WARN disk low')
  local counted, visible = lr.classify (line, lq.parse_query ('disk'), {})
  ok (counted and visible)
  counted, visible =
    lr.classify (line, lq.parse_query ('disk'), { warn = true })
  ok (counted and not visible)
  counted, visible = lr.classify (line, lq.parse_query ('cpu'), {})
  ok (not counted and not visible)
end)

test ('scan with a limit of 0 keeps every line but shows none', function ()
  local r = lr.ring (5)
  for i = 1, 3 do
    r:push (at (i))
  end
  local result = lr.scan (r, lq.parse_query (''), {}, 0)
  eq (#result.all, 3)
  eq (result.shown, {})
  eq (result.levels.other, 3)
end)

test (
  'merge keeps arrival order for lines with the same time or none',
  function ()
    local a = { at (1, 10, 1), at (2, nil, 3), at (3, 30, 5) }
    local b = { at (1, 10, 2), at (2, 20, 4) }
    local order = {} ---@type integer[]
    for _, line in ipairs (lr.merge ({ a, b })) do
      order[#order + 1] = line.id or 0
    end
    eq (order, { 1, 2, 3, 4, 5 })
    eq (lr.merge ({}), {})
  end
)
