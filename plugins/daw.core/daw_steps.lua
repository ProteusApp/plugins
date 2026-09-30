-- daw_steps: the Channel Rack's step sequencer, as operations on a song. A row of steps is
-- one pitch on one track over one bar, a step to each sixteenth note. A step is on when a
-- note of that pitch starts inside it, in any clip of the track. Turning a step on adds a
-- sixteenth note to the clip that covers it, or to a new clip one bar long. Turning it off
-- removes every note of that pitch that starts inside it.

local notes_mod = require ('daw_notes') --[[@as Daw.NotesModule]]
local song_mod = require ('daw_song') --[[@as Daw.SongModule]]

local M = {}

---A step's length in beats: a sixteenth note.
M.STEP = 0.25

local EPS = 1e-6

---How many steps one bar holds.
---@param song Daw.Song
---@return integer
function M.count (song)
  return song_mod.beats_per_bar (song) * 4
end

---Which steps of a bar are on, for one pitch on one track. `bar` counts from 0.
---@param song Daw.Song
---@param track_id string
---@param pitch integer
---@param bar integer
---@return boolean[]
function M.row (song, track_id, pitch, bar)
  local count = M.count (song)
  local out = {} ---@type boolean[]
  for i = 1, count do
    out[i] = false
  end
  local t = song_mod.track (song, track_id)
  if not t then
    return out
  end
  local from = bar * song_mod.beats_per_bar (song)
  for _, c in ipairs (t.clips) do
    for _, n in ipairs (c.notes or {}) do
      if n.pitch == pitch and n.start < c.length then
        local at = c.start + n.start - from
        if at > -EPS then
          local i = math.floor (at / M.STEP + EPS) + 1
          if i >= 1 and i <= count then
            out[i] = true
          end
        end
      end
    end
  end
  return out
end

---Turns a step on or off. Returns the new song and the clip it changed or made, or the same
---song when the track cannot take notes. `step` counts from 1.
---@param song Daw.Song
---@param track_id string
---@param pitch integer
---@param bar integer
---@param step integer
---@param velocity? number
---@return Daw.Song
---@return string?
function M.toggle (song, track_id, pitch, bar, step, velocity)
  local t = song_mod.track (song, track_id)
  if not t or t.kind ~= 'instrument' then
    return song
  end
  local bpb = song_mod.beats_per_bar (song)
  local at = bar * bpb + (step - 1) * M.STEP
  local s = song
  local changed = nil ---@type string?
  for _, c in ipairs (t.clips) do
    local picked = {} ---@type integer[]
    for i, n in ipairs (c.notes or {}) do
      local start = c.start + n.start
      if
        n.pitch == pitch
        and n.start < c.length
        and start > at - EPS
        and start < at + M.STEP - EPS
      then
        picked[#picked + 1] = i
      end
    end
    if #picked > 0 then
      s = song_mod.set_notes (s, c.id, notes_mod.remove (c.notes or {}, picked))
      changed = c.id
    end
  end
  if changed then
    return s, changed
  end
  local target = nil ---@type Daw.Clip?
  for _, c in ipairs (t.clips) do
    if c.notes and at > c.start - EPS and at < c.start + c.length - EPS then
      target = c
    end
  end
  local id ---@type string
  if target then
    id = target.id
  else
    s, id = song_mod.add_clip (s, track_id, {
      name = t.name,
      start = bar * bpb,
      length = bpb,
    })
    target = song_mod.clip (s, id)
  end
  local list = notes_mod.add (target and target.notes or {}, {
    pitch = pitch,
    start = at - (target and target.start or 0),
    length = M.STEP,
    velocity = velocity or 0.8,
  })
  return song_mod.set_notes (s, id, list), id
end

---The pitch a channel's single row of steps plays: the one its notes use most, or middle C.
---@param track Daw.Track
---@return integer
function M.pitch_of (track)
  local counts = {} ---@type table<integer, integer>
  local best, most = 60, 0
  for _, c in ipairs (track.clips) do
    for _, n in ipairs (c.notes or {}) do
      counts[n.pitch] = (counts[n.pitch] or 0) + 1
      if counts[n.pitch] > most then
        best, most = n.pitch, counts[n.pitch]
      end
    end
  end
  return best
end

return M
