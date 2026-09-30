-- daw_demo: songs built from code. `song` is a four-bar loop in A minor that shows off the
-- builtin devices, and `empty` is where a new song starts. Both name devices by id only, so
-- each device's defaults fill in everything a song leaves out.

local song_mod = require ('daw_song') --[[@as Daw.SongModule]]

local M = {}

---@param device string
---@param preset? string
---@param params? table<string, Daw.Value>
---@return Daw.DeviceRef
local function ref (device, preset, params)
  return {
    id = '',
    device = device,
    params = params or {},
    bypass = false,
    preset = preset,
  }
end

---@param list Daw.Note[]
---@param pitch integer
---@param start number
---@param length number
---@param velocity? number
local function note (list, pitch, start, length, velocity)
  list[#list + 1] = {
    pitch = pitch,
    start = start,
    length = length,
    velocity = velocity or 0.8,
  }
end

---@return Daw.Note[]
local function beat ()
  local out = {} ---@type Daw.Note[]
  for bar = 0, 3 do
    local b = bar * 4
    for i = 0, 3 do
      note (out, 36, b + i, 0.25, 0.95)
      note (out, 42, b + i + 0.5, 0.125, i % 2 == 0 and 0.55 or 0.7)
    end
    note (out, 39, b + 1, 0.25, 0.8)
    note (out, 38, b + 3, 0.25, 0.9)
    if bar == 3 then
      note (out, 38, b + 3.5, 0.25, 0.6)
      note (out, 38, b + 3.75, 0.25, 0.75)
    else
      note (out, 46, b + 3.5, 0.25, 0.5)
    end
  end
  note (out, 49, 0, 1, 0.6)
  return out
end

-- Am, F, C, G: the root of each bar, and its chord from the bottom up.
local ROOTS = { 33, 29, 36, 31 }
local CHORDS =
  { { 57, 60, 64 }, { 57, 60, 65 }, { 55, 60, 64 }, { 55, 59, 62 } }

---@return Daw.Note[]
local function bass ()
  local out = {} ---@type Daw.Note[]
  for bar, root in ipairs (ROOTS) do
    local b = (bar - 1) * 4
    note (out, root, b, 0.75, 0.9)
    note (out, root, b + 1, 0.5, 0.7)
    note (out, root + 12, b + 1.5, 0.5, 0.75)
    note (out, root, b + 2.5, 0.5, 0.7)
    note (out, root + 7, b + 3, 0.5, 0.65)
    note (out, root + 12, b + 3.5, 0.5, 0.7)
  end
  return out
end

---@return Daw.Note[]
local function chords ()
  local out = {} ---@type Daw.Note[]
  for bar, chord in ipairs (CHORDS) do
    for _, pitch in ipairs (chord) do
      note (out, pitch, (bar - 1) * 4, 3.75, 0.6)
    end
  end
  return out
end

---@return Daw.Note[]
local function lead ()
  local out = {} ---@type Daw.Note[]
  local line = {
    { 76, 0, 0.5 },
    { 72, 0.75, 0.25 },
    { 74, 1, 0.5 },
    { 76, 1.5, 1 },
    { 77, 4, 0.5 },
    { 76, 4.75, 0.25 },
    { 72, 5, 1.5 },
    { 79, 8, 0.5 },
    { 76, 8.75, 0.25 },
    { 72, 9, 0.5 },
    { 76, 9.5, 1 },
    { 74, 12, 0.5 },
    { 71, 12.75, 0.25 },
    { 67, 13, 0.5 },
    { 71, 13.5, 1.5 },
  }
  for _, n in ipairs (line) do
    note (out, n[1], n[2], n[3], 0.75)
  end
  return out
end

---@return Daw.Song
function M.song ()
  local s = song_mod.new ('Demo')
  s = song_mod.set (s, { tempo = 112 })
  -- Room above the loudest peaks, so the master never clips.
  s.master = { volume = -3, effects = {} }
  s = song_mod.set_loop (s, { on = true, start = 0, finish = 16 })
  s = song_mod.add_track (s, {
    name = 'Drums',
    instrument = ref ('daw.drums'),
    effects = { ref ('daw.comp', 'Glue') },
    clips = { { name = 'Beat', start = 0, length = 16, notes = beat () } },
  })
  s = song_mod.add_track (s, {
    name = 'Bass',
    volume = -3,
    instrument = ref ('daw.synth', 'Sub Bass'),
    clips = { { name = 'Bass', start = 0, length = 16, notes = bass () } },
  })
  s = song_mod.add_track (s, {
    name = 'Chords',
    volume = -9,
    instrument = ref ('daw.synth', 'Warm Pad'),
    effects = { ref ('daw.chorus'), ref ('daw.reverb', 'Hall') },
    clips = { { name = 'Chords', start = 0, length = 16, notes = chords () } },
  })
  s = song_mod.add_track (s, {
    name = 'Lead',
    volume = -8,
    pan = 0.15,
    instrument = ref ('daw.fm', 'Electric Piano'),
    effects = { ref ('daw.delay', 'Dotted Eighth') },
    clips = { { name = 'Melody', start = 0, length = 16, notes = lead () } },
  })
  return s
end

---@return Daw.Song
function M.empty ()
  local s = song_mod.new ('Untitled')
  s = song_mod.add_track (s, { name = 'Drums', instrument = ref ('daw.drums') })
  s = song_mod.add_track (s, {
    name = 'Synth',
    instrument = ref ('daw.synth'),
    effects = { ref ('daw.reverb') },
  })
  return s
end

return M
