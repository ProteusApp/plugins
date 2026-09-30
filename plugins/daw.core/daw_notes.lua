-- daw_notes: pure operations on a clip's notes, for the piano roll. Each returns a new list
-- and keeps every note where it was in the list, so a selection held as positions in the
-- list stays good across a move or a resize.

local time = require ('daw_time') --[[@as Daw.TimeModule]]

local M = {}

---@param n Daw.Note
---@return Daw.Note
local function copy (n)
  return {
    pitch = n.pitch,
    start = n.start,
    length = n.length,
    velocity = n.velocity,
  }
end

---@param picked integer[]
---@return table<integer, boolean>
local function set_of (picked)
  local out = {} ---@type table<integer, boolean>
  for _, i in ipairs (picked) do
    out[i] = true
  end
  return out
end

---Applies `fn` to the picked notes, or to every note when none are picked.
---@param notes Daw.Note[]
---@param picked integer[]
---@param fn fun(n: Daw.Note)
---@return Daw.Note[]
local function each (notes, picked, fn)
  local chosen = set_of (picked)
  local all = #picked == 0
  local out = {} ---@type Daw.Note[]
  for i, n in ipairs (notes) do
    if all or chosen[i] then
      local c = copy (n)
      fn (c)
      out[i] = c
    else
      out[i] = n
    end
  end
  return out
end

---@param pitch number
---@return integer
local function clamp_pitch (pitch)
  return math.floor (math.max (0, math.min (127, pitch)))
end

---@param notes Daw.Note[]
---@return Daw.Note[]
function M.sort (notes)
  local out = {} ---@type Daw.Note[]
  for i, n in ipairs (notes) do
    out[i] = n
  end
  table.sort (out, function (a, b)
    if a.start ~= b.start then
      return a.start < b.start
    end
    return a.pitch < b.pitch
  end)
  return out
end

---@param notes Daw.Note[]
---@param note Daw.Note
---@return Daw.Note[], integer
function M.add (notes, note)
  local out = {} ---@type Daw.Note[]
  for i, n in ipairs (notes) do
    out[i] = n
  end
  local n = copy (note)
  n.pitch = clamp_pitch (n.pitch)
  n.start = math.max (0, n.start)
  n.velocity = math.max (0, math.min (1, n.velocity or 0.8))
  out[#out + 1] = n
  return out, #out
end

---@param notes Daw.Note[]
---@param picked integer[]
---@return Daw.Note[]
function M.remove (notes, picked)
  local chosen = set_of (picked)
  local out = {} ---@type Daw.Note[]
  for i, n in ipairs (notes) do
    if not chosen[i] then
      out[#out + 1] = n
    end
  end
  return out
end

---Moves notes in time and pitch. None starts before 0 or at `limit` or later.
---@param notes Daw.Note[]
---@param picked integer[]
---@param beats number
---@param semitones integer
---@param limit number
---@return Daw.Note[]
function M.move (notes, picked, beats, semitones, limit)
  return each (notes, picked, function (n)
    n.start = math.max (0, math.min (limit - 1 / 64, n.start + beats))
    n.pitch = clamp_pitch (n.pitch + semitones)
  end)
end

---@param notes Daw.Note[]
---@param picked integer[]
---@param beats number
---@param min_length number
---@return Daw.Note[]
function M.resize (notes, picked, beats, min_length)
  return each (notes, picked, function (n)
    n.length = math.max (min_length, n.length + beats)
  end)
end

---Moves note starts to the grid, and their lengths too when `ends` is set.
---@param notes Daw.Note[]
---@param picked integer[]
---@param grid string
---@param ends? boolean
---@return Daw.Note[]
function M.quantize (notes, picked, grid, ends)
  local step = time.grid_beats (grid)
  if step <= 0 then
    return notes
  end
  return each (notes, picked, function (n)
    n.start = time.snap (n.start, grid)
    if ends then
      n.length = math.max (step, time.snap (n.length, grid))
    end
  end)
end

---@param notes Daw.Note[]
---@param picked integer[]
---@param velocity number
---@return Daw.Note[]
function M.set_velocity (notes, picked, velocity)
  local v = math.max (0.01, math.min (1, velocity))
  return each (notes, picked, function (n)
    n.velocity = v
  end)
end

---@param notes Daw.Note[]
---@param picked integer[]
---@param semitones integer
---@return Daw.Note[]
function M.transpose (notes, picked, semitones)
  return each (notes, picked, function (n)
    n.pitch = clamp_pitch (n.pitch + semitones)
  end)
end

---@param notes Daw.Note[]
---@param beat number
---@param pitch integer
---@return integer?
function M.at (notes, beat, pitch)
  for i = #notes, 1, -1 do
    local n = notes[i]
    if n.pitch == pitch and beat >= n.start and beat < n.start + n.length then
      return i
    end
  end
  return nil
end

---The notes that overlap a stretch of time and fall in a range of pitches.
---@param notes Daw.Note[]
---@param from number
---@param to number
---@param low integer
---@param high integer
---@return integer[]
function M.within (notes, from, to, low, high)
  local a, b = math.min (from, to), math.max (from, to)
  local lo, hi = math.min (low, high), math.max (low, high)
  local out = {} ---@type integer[]
  for i, n in ipairs (notes) do
    if
      n.pitch >= lo
      and n.pitch <= hi
      and n.start < b
      and n.start + n.length > a
    then
      out[#out + 1] = i
    end
  end
  return out
end

---@param notes Daw.Note[]
---@return integer?, integer?
function M.range (notes)
  local lo, hi = nil, nil ---@type integer?, integer?
  for _, n in ipairs (notes) do
    lo = lo and math.min (lo, n.pitch) or n.pitch
    hi = hi and math.max (hi, n.pitch) or n.pitch
  end
  return lo, hi
end

return M
