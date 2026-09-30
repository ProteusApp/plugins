-- daw_time: beats, bars, grids and note names. A beat is a quarter note, and the song
-- starts at beat 0. Bars and beats read from 1, the way musicians count them.

---@type Daw.Grid[]
local GRIDS =
  { '1/1', '1/2', '1/4', '1/8', '1/16', '1/32', '1/8T', '1/16T', 'off' }

---@type table<string, number>
local GRID_BEATS = {
  ['1/1'] = 4,
  ['1/2'] = 2,
  ['1/4'] = 1,
  ['1/8'] = 0.5,
  ['1/16'] = 0.25,
  ['1/32'] = 0.125,
  ['1/8T'] = 1 / 3,
  ['1/16T'] = 1 / 6,
  off = 0,
}

local NAMES =
  { 'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B' }

---@type table<string, integer>
local LETTERS = { C = 0, D = 2, E = 4, F = 5, G = 7, A = 9, B = 11 }

-- A small amount that absorbs rounding, so 0.9999999 counts as 1.
local EPS = 1e-6

local M = {}

M.GRIDS = GRIDS

---@param grid string
---@return number
function M.grid_beats (grid)
  return GRID_BEATS[grid] or 0
end

---@param beat number
---@param grid string
---@return number
function M.snap (beat, grid)
  local step = GRID_BEATS[grid] or 0
  if step <= 0 then
    return beat
  end
  return math.floor (beat / step + 0.5) * step
end

---@param beat number
---@param grid string
---@return number
function M.snap_down (beat, grid)
  local step = GRID_BEATS[grid] or 0
  if step <= 0 then
    return beat
  end
  return math.floor (beat / step + EPS) * step
end

---@param beat number
---@param beats_per_bar integer
---@return integer bar
---@return integer beat
---@return integer sixteenth
local function split (beat, beats_per_bar)
  local b = math.max (0, beat) + EPS
  local per = math.max (1, beats_per_bar)
  local bar = math.floor (b / per)
  local in_bar = b - bar * per
  local whole = math.floor (in_bar)
  local sixteenth = math.floor ((in_bar - whole) * 4)
  return bar + 1, whole + 1, sixteenth + 1
end

---@param beat number
---@param beats_per_bar integer
---@return string
function M.format (beat, beats_per_bar)
  local bar, b, s = split (beat, beats_per_bar)
  return string.format ('%d.%d.%d', bar, b, s)
end

---@param beat number
---@param beats_per_bar integer
---@return string
function M.format_short (beat, beats_per_bar)
  local bar, b = split (beat, beats_per_bar)
  return string.format ('%d.%d', bar, b)
end

---@param beat number
---@param tempo number
---@return number
function M.seconds (beat, tempo)
  return beat * 60 / math.max (1, tempo)
end

---@param seconds number
---@return string
function M.format_clock (seconds)
  local s = math.max (0, seconds)
  local minutes = math.floor (s / 60)
  return string.format ('%d:%06.3f', minutes, s - minutes * 60)
end

---@param pitch integer
---@return string
function M.note_name (pitch)
  local p = math.floor (pitch)
  return NAMES[p % 12 + 1] .. tostring (math.floor (p / 12) - 1)
end

---@param pitch integer
---@return boolean
function M.is_black (pitch)
  local n = math.floor (pitch) % 12
  return n == 1 or n == 3 or n == 6 or n == 8 or n == 10
end

---@param text string
---@return integer?
function M.parse_note (text)
  local t = (text or ''):gsub ('%s', '')
  local n = tonumber (t)
  if n then
    local whole = math.floor (n)
    if whole >= 0 and whole <= 127 then
      return whole
    end
    return nil
  end
  local letter, accidental, octave = t:match ('^([A-Ga-g])([#b]?)(%-?%d+)$')
  if not letter then
    return nil
  end
  local pitch = LETTERS[letter:upper ()]
    + (accidental == '#' and 1 or accidental == 'b' and -1 or 0)
    + (tonumber (octave) + 1) * 12
  if pitch < 0 or pitch > 127 then
    return nil
  end
  return math.floor (pitch)
end

return M
