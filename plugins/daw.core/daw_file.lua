-- daw_file: turns whatever a song file holds into a valid song. A file may come from an
-- older version, from another program, or from a hand edit, so every field is checked and
-- anything missing gets its default. An empty list that went through JSON may come back as
-- an empty object, which reads the same here.
--
-- Format 2 lets each device keep `state`, the text its engine saved for it, such as the
-- samples and presets inside a Web Audio Module or a CLAP or VST3 plugin. A format 1 song
-- has none, so it reads as it is and saves as format 2.

local song_mod = require ('daw_song') --[[@as Daw.SongModule]]

local M = {}

M.FORMAT = 2
M.EXT = '.song.json'

---@param value any
---@return table[]
local function list (value)
  local out = {} ---@type table[]
  if type (value) ~= 'table' then
    return out
  end
  for _, v in
    ipairs (value --[[@as any[] ]])
  do
    if type (v) == 'table' then
      out[#out + 1] = v
    end
  end
  return out
end

---@param value any
---@param default number
---@param lo? number
---@param hi? number
---@return number
local function num (value, default, lo, hi)
  local n = tonumber (value)
  if not n or n ~= n then
    n = default
  end
  if lo then
    n = math.max (lo, n)
  end
  if hi then
    n = math.min (hi, n)
  end
  return n
end

---@param value any
---@param default string
---@return string
local function text (value, default)
  if type (value) == 'string' and value ~= '' then
    return value
  end
  return default
end

---@param ids table<string, boolean>
---@param want any
---@param make fun(): string
---@return string
local function unique (ids, want, make)
  local id = type (want) == 'string' and want ~= '' and want or nil
  while not id or ids[id] do
    id = make ()
  end
  ids[id] = true
  return id
end

---@param value any
---@return Daw.Song
function M.normalize (value)
  local v = type (value) == 'table' and value or {}
  local song = song_mod.new (text (v.name, 'Untitled'))
  song.tempo = num (v.tempo, 120, 20, 400)
  local sig = type (v.signature) == 'table' and v.signature or {}
  song.signature = {
    math.floor (num (sig[1], 4, 1, 16)),
    math.floor (num (sig[2], 4, 1, 32)),
  }
  local loop = type (v.loop) == 'table' and v.loop or {}
  song.loop = {
    on = loop.on == true,
    start = num (loop.start, 0, 0),
    finish = num (loop.finish, 16, 0),
  }
  if song.loop.finish <= song.loop.start then
    song.loop.finish = song.loop.start + 4
  end

  local counter = math.floor (num (v.ids, 0, 0))
  local ids = {} ---@type table<string, boolean>
  ---@param prefix string
  ---@return fun(): string
  local function maker (prefix)
    return function ()
      counter = counter + 1
      return prefix .. counter
    end
  end

  ---@param d table<string, any>
  ---@return Daw.DeviceRef?
  local function device (d)
    if type (d) ~= 'table' or type (d.device) ~= 'string' or d.device == '' then
      return nil
    end
    local params = {} ---@type table<string, Daw.Value>
    if type (d.params) == 'table' then
      for k, p in
        pairs (d.params --[[@as table<any, any>]])
      do
        local kind = type (p)
        if
          type (k) == 'string'
          and (kind == 'number' or kind == 'string' or kind == 'boolean')
        then
          params[k] = p
        end
      end
    end
    return {
      id = unique (ids, d.id, maker ('d')),
      device = d.device --[[@as string]],
      params = params,
      bypass = d.bypass == true,
      preset = type (d.preset) == 'string' and d.preset or nil,
      state = type (d.state) == 'string' and d.state ~= '' and d.state or nil,
    }
  end

  ---@param items any
  ---@return Daw.DeviceRef[]
  local function devices (items)
    local out = {} ---@type Daw.DeviceRef[]
    for _, d in ipairs (list (items)) do
      local ref = device (d)
      if ref then
        out[#out + 1] = ref
      end
    end
    return out
  end

  local master = type (v.master) == 'table' and v.master or {}
  song.master = {
    volume = num (master.volume, 0, -60, 6),
    effects = devices (master.effects),
  }

  for i, t in ipairs (list (v.tracks)) do
    local kind = t.kind == 'audio' and 'audio' or 'instrument'
    ---@type Daw.Track
    local track = {
      id = unique (ids, t.id, maker ('t')),
      name = text (t.name, 'Track ' .. i),
      kind = kind,
      color = text (t.color, song_mod.COLORS[(i - 1) % #song_mod.COLORS + 1]),
      volume = num (t.volume, 0, -60, 6),
      pan = num (t.pan, 0, -1, 1),
      mute = t.mute == true,
      solo = t.solo == true,
      arm = t.arm == true,
      instrument = kind == 'instrument' and device (t.instrument) or nil,
      effects = devices (t.effects),
      clips = {},
    }
    for _, c in ipairs (list (t.clips)) do
      ---@type Daw.Clip
      local clip = {
        id = unique (ids, c.id, maker ('c')),
        name = text (c.name, track.name),
        start = num (c.start, 0, 0),
        length = num (c.length, 4, 1 / 64),
        color = type (c.color) == 'string' and c.color or nil,
      }
      if kind == 'audio' then
        clip.file = type (c.file) == 'string' and c.file or ''
        clip.offset = num (c.offset, 0, 0)
        clip.gain = num (c.gain, 0, -60, 12)
      else
        clip.notes = {}
        for _, n in ipairs (list (c.notes)) do
          local pitch = tonumber (n.pitch)
          if pitch then
            clip.notes[#clip.notes + 1] = {
              pitch = math.floor (math.max (0, math.min (127, pitch))),
              start = num (n.start, 0, 0),
              length = num (n.length, 0.25, 1 / 64),
              velocity = num (n.velocity, 0.8, 0, 1),
            }
          end
        end
      end
      track.clips[#track.clips + 1] = clip
    end
    song.tracks[#song.tracks + 1] = track
  end
  song.ids = counter
  return song
end

---@param song Daw.Song
---@return Daw.Song
function M.for_save (song)
  local out = song_mod.copy (song) --[[@as Daw.Song]]
  out.format = M.FORMAT
  return out
end

return M
