-- daw_song: pure operations on a song. Each one returns a new song and leaves the one it
-- was given untouched, so the old song can sit in the undo history as it is. Only the tables
-- on the path to a change are copied. The rest is shared between the two songs.

local M = {}

M.COLORS = {
  '#e06c75',
  '#e5a04b',
  '#d8c95a',
  '#7fc47a',
  '#4fb8b0',
  '#5fa0e8',
  '#9a86e8',
  '#d77ac8',
}

---@param t table
---@return table
local function shallow (t)
  local c = {} ---@type table<any, any>
  for k, v in
    pairs (t --[[@as table<any, any>]])
  do
    c[k] = v
  end
  return c
end

---@param value any
---@return any
function M.copy (value)
  if type (value) ~= 'table' then
    return value
  end
  local c = {} ---@type table<any, any>
  for k, v in
    pairs (value --[[@as table<any, any>]])
  do
    c[k] = M.copy (v)
  end
  return c
end

---@param name? string
---@return Daw.Song
function M.new (name)
  ---@type Daw.Song
  return {
    format = 2,
    name = name or 'Untitled',
    tempo = 120,
    signature = { 4, 4 },
    loop = { on = false, start = 0, finish = 16 },
    master = { volume = 0, effects = {} },
    tracks = {},
    ids = 0,
  }
end

---@param song Daw.Song
---@return integer
function M.beats_per_bar (song)
  local sig = song.signature or {}
  return math.max (1, math.floor (tonumber (sig[1]) or 4))
end

---@param song Daw.Song
---@param prefix string
---@return Daw.Song, string
function M.new_id (song, prefix)
  local s = shallow (song) --[[@as Daw.Song]]
  s.ids = (song.ids or 0) + 1
  return s, prefix .. tostring (s.ids)
end

---@param song Daw.Song
---@param id string
---@return Daw.Track?, integer?
function M.track (song, id)
  for i, t in ipairs (song.tracks) do
    if t.id == id then
      return t, i
    end
  end
  return nil, nil
end

---@param song Daw.Song
---@param id string
---@return Daw.Clip?, Daw.Track?, integer?
function M.clip (song, id)
  for _, t in ipairs (song.tracks) do
    for i, c in ipairs (t.clips) do
      if c.id == id then
        return c, t, i
      end
    end
  end
  return nil, nil, nil
end

---@param song Daw.Song
---@param id string
---@return Daw.DeviceRef?, Daw.Track?
function M.device (song, id)
  for _, d in ipairs (song.master.effects) do
    if d.id == id then
      return d, nil
    end
  end
  for _, t in ipairs (song.tracks) do
    if t.instrument and t.instrument.id == id then
      return t.instrument, t
    end
    for _, d in ipairs (t.effects) do
      if d.id == id then
        return d, t
      end
    end
  end
  return nil, nil
end

---Replaces one track with what `fn` makes of a copy of it.
---@param song Daw.Song
---@param id string
---@param fn fun(t: Daw.Track): Daw.Track?
---@return Daw.Song
local function with_track (song, id, fn)
  local _, index = M.track (song, id)
  if not index then
    return song
  end
  local changed = fn (shallow (song.tracks[index]) --[[@as Daw.Track]])
  if not changed then
    return song
  end
  local s = shallow (song) --[[@as Daw.Song]]
  s.tracks = shallow (song.tracks) --[[@as Daw.Track[] ]]
  s.tracks[index] = changed
  return s
end

---@param song Daw.Song
---@param fields table<string, any>
---@return Daw.Song
function M.set (song, fields)
  local s = shallow (song) --[[@as Daw.Song]]
  for k, v in pairs (fields) do
    if k ~= 'tracks' and k ~= 'master' and k ~= 'ids' then
      (s --[[@as table<string, any>]])[k] = v
    end
  end
  if s.tempo then
    s.tempo = math.max (20, math.min (400, tonumber (s.tempo) or 120))
  end
  return s
end

---@param song Daw.Song
---@param fields { on?: boolean, start?: number, finish?: number }
---@return Daw.Song
function M.set_loop (song, fields)
  local loop = shallow (song.loop) --[[@as Daw.Loop]]
  if fields.on ~= nil then
    loop.on = fields.on
  end
  loop.start = fields.start or loop.start
  loop.finish = fields.finish or loop.finish
  loop.start = math.max (0, loop.start)
  if loop.finish <= loop.start then
    loop.finish = loop.start + 1
  end
  local s = shallow (song) --[[@as Daw.Song]]
  s.loop = loop
  return s
end

---Gives a device an id when it has none.
---@param song Daw.Song
---@param ref Daw.DeviceRef
---@return Daw.Song, Daw.DeviceRef
local function place_device (song, ref)
  local d = shallow (ref) --[[@as Daw.DeviceRef]]
  d.params = shallow (ref.params or {})
  d.bypass = ref.bypass == true
  if not d.id or d.id == '' then
    local s, id = M.new_id (song, 'd')
    d.id = id
    return s, d
  end
  return song, d
end

---@param song Daw.Song
---@param fields table<string, any>
---@param index? integer
---@return Daw.Song, string
function M.add_track (song, fields, index)
  local s, id = M.new_id (song, 't')
  local n = #song.tracks + 1
  local kind = fields.kind == 'audio' and 'audio' or 'instrument'
  ---@type Daw.Track
  local t = {
    id = id,
    name = fields.name or ((kind == 'audio' and 'Audio ' or 'Track ') .. n),
    kind = kind,
    color = fields.color or M.COLORS[(n - 1) % #M.COLORS + 1],
    volume = fields.volume or 0,
    pan = fields.pan or 0,
    mute = fields.mute == true,
    solo = fields.solo == true,
    arm = fields.arm == true,
    effects = {},
    clips = {},
  }
  if kind == 'instrument' and fields.instrument then
    local inst ---@type Daw.DeviceRef
    s, inst = place_device (s, fields.instrument)
    t.instrument = inst
  end
  for _, ref in
    ipairs (fields.effects or {} --[[@as Daw.DeviceRef[] ]])
  do
    local d ---@type Daw.DeviceRef
    s, d = place_device (s, ref)
    t.effects[#t.effects + 1] = d
  end
  for _, c in
    ipairs (fields.clips or {} --[[@as table[] ]])
  do
    local cid ---@type string
    s, cid = M.new_id (s, 'c')
    local clip = M.copy (c) --[[@as Daw.Clip]]
    clip.id = cid
    clip.name = clip.name or t.name
    t.clips[#t.clips + 1] = clip
  end
  s.tracks = shallow (song.tracks) --[[@as Daw.Track[] ]]
  local at = math.max (1, math.min (index or n, n))
  table.insert (s.tracks, at, t)
  return s, id
end

---@param song Daw.Song
---@param id string
---@return Daw.Song
function M.remove_track (song, id)
  local _, index = M.track (song, id)
  if not index then
    return song
  end
  local s = shallow (song) --[[@as Daw.Song]]
  s.tracks = shallow (song.tracks) --[[@as Daw.Track[] ]]
  table.remove (s.tracks, index)
  return s
end

---@param song Daw.Song
---@param id string
---@param index integer
---@return Daw.Song
function M.move_track (song, id, index)
  local t, from = M.track (song, id)
  if not t or not from then
    return song
  end
  local to = math.max (1, math.min (index, #song.tracks))
  if to == from then
    return song
  end
  local s = shallow (song) --[[@as Daw.Song]]
  s.tracks = shallow (song.tracks) --[[@as Daw.Track[] ]]
  table.remove (s.tracks, from)
  table.insert (s.tracks, to, t)
  return s
end

---@param song Daw.Song
---@param id string
---@param fields table<string, any>
---@return Daw.Song
function M.update_track (song, id, fields)
  return with_track (song, id, function (t)
    for k, v in pairs (fields) do
      if k ~= 'id' and k ~= 'clips' and k ~= 'effects' and k ~= 'kind' then
        (t --[[@as table<string, any>]])[k] = v
      end
    end
    t.volume = math.max (-60, math.min (6, tonumber (t.volume) or 0))
    t.pan = math.max (-1, math.min (1, tonumber (t.pan) or 0))
    return t
  end)
end

---@param song Daw.Song
---@param track_id string
---@param ref Daw.DeviceRef?
---@return Daw.Song, string?
function M.set_instrument (song, track_id, ref)
  local t = M.track (song, track_id)
  if not t or t.kind ~= 'instrument' then
    return song, nil
  end
  local s, d = song, nil ---@type Daw.Song, Daw.DeviceRef?
  if ref then
    s, d = place_device (song, ref)
  end
  s = with_track (s, track_id, function (copy)
    copy.instrument = d
    return copy
  end)
  return s, d and d.id
end

---@param song Daw.Song
---@param track_id string A track's id, or `'master'`.
---@param ref Daw.DeviceRef
---@param index? integer
---@return Daw.Song, string
function M.add_effect (song, track_id, ref, index)
  local s, d = place_device (song, ref)
  ---@param list Daw.DeviceRef[]
  ---@return Daw.DeviceRef[]
  local function insert (list)
    local out = shallow (list) --[[@as Daw.DeviceRef[] ]]
    local at = math.max (1, math.min (index or (#out + 1), #out + 1))
    table.insert (out, at, d)
    return out
  end
  if track_id == 'master' then
    s = shallow (s) --[[@as Daw.Song]]
    s.master = shallow (s.master) --[[@as Daw.Master]]
    s.master.effects = insert (s.master.effects)
    return s, d.id
  end
  if not M.track (s, track_id) then
    return song, d.id
  end
  s = with_track (s, track_id, function (t)
    t.effects = insert (t.effects)
    return t
  end)
  return s, d.id
end

---Changes the device with this id wherever it is: `fn` gets a copy and returns the new
---device, or false to take it away.
---@param song Daw.Song
---@param id string
---@param fn fun(d: Daw.DeviceRef): Daw.DeviceRef|false
---@return Daw.Song
local function with_device (song, id, fn)
  ---@param list Daw.DeviceRef[]
  ---@return Daw.DeviceRef[]?
  local function in_list (list)
    for i, d in ipairs (list) do
      if d.id == id then
        local out = shallow (list) --[[@as Daw.DeviceRef[] ]]
        local changed = fn (shallow (d) --[[@as Daw.DeviceRef]])
        if changed then
          out[i] = changed
        else
          table.remove (out, i)
        end
        return out
      end
    end
    return nil
  end
  local master = in_list (song.master.effects)
  if master then
    local s = shallow (song) --[[@as Daw.Song]]
    s.master = shallow (song.master) --[[@as Daw.Master]]
    s.master.effects = master
    return s
  end
  local _, owner = M.device (song, id)
  if not owner then
    return song
  end
  return with_track (song, owner.id, function (t)
    if t.instrument and t.instrument.id == id then
      local changed = fn (shallow (t.instrument) --[[@as Daw.DeviceRef]])
      t.instrument = changed or nil
      return t
    end
    local list = in_list (t.effects)
    if not list then
      return nil
    end
    t.effects = list
    return t
  end)
end

---@param song Daw.Song
---@param id string
---@return Daw.Song
function M.remove_device (song, id)
  return with_device (song, id, function ()
    return false
  end)
end

---@param song Daw.Song
---@param id string
---@param fields table<string, any>
---@return Daw.Song
function M.update_device (song, id, fields)
  return with_device (song, id, function (d)
    local was = d.device
    for k, v in pairs (fields) do
      if k ~= 'id' then
        (d --[[@as table<string, any>]])[k] = v
      end
    end
    -- What one device saved means nothing to another.
    if d.device ~= was and fields.state == nil then
      d.state = nil
    end
    return d
  end)
end

---Every device in the song, the master's effects first.
---@param song Daw.Song
---@return Daw.DeviceRef[]
local function all_devices (song)
  local out = {} ---@type Daw.DeviceRef[]
  for _, d in ipairs (song.master.effects) do
    out[#out + 1] = d
  end
  for _, t in ipairs (song.tracks) do
    if t.instrument then
      out[#out + 1] = t.instrument
    end
    for _, d in ipairs (t.effects) do
      out[#out + 1] = d
    end
  end
  return out
end

---The state each device saved, by device id, for the devices that have one.
---@param song Daw.Song
---@return table<string, string>
function M.states (song)
  local out = {} ---@type table<string, string>
  for _, d in ipairs (all_devices (song)) do
    if d.state then
      out[d.id] = d.state
    end
  end
  return out
end

---Keeps what devices saved: `states` holds the text by device id, and an empty text takes a
---state away. A device the song does not have is left out, and the song comes back as it was
---when nothing changes.
---@param song Daw.Song
---@param states table<string, string>
---@return Daw.Song
function M.set_states (song, states)
  local s = song
  for _, d in ipairs (all_devices (song)) do
    local given = states[d.id]
    if type (given) == 'string' then
      local want = given ~= '' and given or nil
      if d.state ~= want then
        s = with_device (s, d.id, function (copy)
          copy.state = want
          return copy
        end)
      end
    end
  end
  return s
end

---@param song Daw.Song
---@param id string
---@param key string
---@param value Daw.Value
---@return Daw.Song
function M.set_param (song, id, key, value)
  return with_device (song, id, function (d)
    d.params = shallow (d.params or {})
    d.params[key] = value
    return d
  end)
end

---Loads a preset by name, or the defaults for nil, and drops the values changed by hand.
---@param song Daw.Song
---@param id string
---@param name? string
---@return Daw.Song
function M.set_preset (song, id, name)
  return with_device (song, id, function (d)
    d.params = {}
    d.preset = name
    return d
  end)
end

---@param song Daw.Song
---@param id string
---@param index integer
---@return Daw.Song
function M.move_effect (song, id, index)
  ---@param list Daw.DeviceRef[]
  ---@return Daw.DeviceRef[]?
  local function moved (list)
    for i, d in ipairs (list) do
      if d.id == id then
        local out = shallow (list) --[[@as Daw.DeviceRef[] ]]
        table.remove (out, i)
        table.insert (out, math.max (1, math.min (index, #out + 1)), d)
        return out
      end
    end
    return nil
  end
  local master = moved (song.master.effects)
  if master then
    local s = shallow (song) --[[@as Daw.Song]]
    s.master = shallow (song.master) --[[@as Daw.Master]]
    s.master.effects = master
    return s
  end
  local _, owner = M.device (song, id)
  if not owner then
    return song
  end
  return with_track (song, owner.id, function (t)
    local list = moved (t.effects)
    if not list then
      return nil
    end
    t.effects = list
    return t
  end)
end

---@param song Daw.Song
---@param track_id string
---@param fields table<string, any>
---@return Daw.Song, string
function M.add_clip (song, track_id, fields)
  local t = M.track (song, track_id)
  local s, id = M.new_id (song, 'c')
  if not t then
    return song, id
  end
  local clip = M.copy (fields) --[[@as Daw.Clip]]
  clip.id = id
  clip.name = clip.name or t.name
  clip.start = math.max (0, tonumber (clip.start) or 0)
  clip.length = math.max (1 / 16, tonumber (clip.length) or 4)
  if t.kind == 'instrument' then
    clip.notes = clip.notes or {}
    clip.file = nil
  end
  s = with_track (s, track_id, function (copy)
    copy.clips = shallow (copy.clips) --[[@as Daw.Clip[] ]]
    copy.clips[#copy.clips + 1] = clip
    return copy
  end)
  return s, id
end

---@param song Daw.Song
---@param id string
---@param fn fun(c: Daw.Clip): Daw.Clip
---@return Daw.Song
local function with_clip (song, id, fn)
  local _, owner, index = M.clip (song, id)
  if not owner or not index then
    return song
  end
  return with_track (song, owner.id, function (t)
    t.clips = shallow (t.clips) --[[@as Daw.Clip[] ]]
    t.clips[index] = fn (shallow (t.clips[index]) --[[@as Daw.Clip]])
    return t
  end)
end

---@param song Daw.Song
---@param id string
---@param fields table<string, any>
---@return Daw.Song
function M.update_clip (song, id, fields)
  return with_clip (song, id, function (c)
    for k, v in pairs (fields) do
      if k ~= 'id' then
        (c --[[@as table<string, any>]])[k] = v
      end
    end
    c.start = math.max (0, tonumber (c.start) or 0)
    c.length = math.max (1 / 16, tonumber (c.length) or 1)
    return c
  end)
end

---@param song Daw.Song
---@param id string
---@param notes Daw.Note[]
---@return Daw.Song
function M.set_notes (song, id, notes)
  return with_clip (song, id, function (c)
    c.notes = notes
    return c
  end)
end

---@param song Daw.Song
---@param id string
---@param track_id string
---@param start number
---@return Daw.Song
function M.move_clip (song, id, track_id, start)
  local clip, from = M.clip (song, id)
  local to = M.track (song, track_id)
  if not clip or not from or not to or to.kind ~= from.kind then
    return song
  end
  local moved = shallow (clip) --[[@as Daw.Clip]]
  moved.start = math.max (0, start)
  if from.id == to.id then
    return with_clip (song, id, function ()
      return moved
    end)
  end
  local s = M.remove_clips (song, { id })
  return with_track (s, track_id, function (t)
    t.clips = shallow (t.clips) --[[@as Daw.Clip[] ]]
    t.clips[#t.clips + 1] = moved
    return t
  end)
end

---@param song Daw.Song
---@param ids string[]
---@return Daw.Song
function M.remove_clips (song, ids)
  local gone = {} ---@type table<string, boolean>
  for _, id in ipairs (ids) do
    gone[id] = true
  end
  local s = shallow (song) --[[@as Daw.Song]]
  s.tracks = {}
  local changed = false
  for i, t in ipairs (song.tracks) do
    local keep = {} ---@type Daw.Clip[]
    for _, c in ipairs (t.clips) do
      if not gone[c.id] then
        keep[#keep + 1] = c
      end
    end
    if #keep ~= #t.clips then
      local copy = shallow (t) --[[@as Daw.Track]]
      copy.clips = keep
      s.tracks[i] = copy
      changed = true
    else
      s.tracks[i] = t
    end
  end
  return changed and s or song
end

---Cuts a clip in two at a beat. Notes that start before the cut stay in the first part,
---shortened to fit, and the rest move to the second part.
---@param song Daw.Song
---@param id string
---@param beat number
---@return Daw.Song, string?
function M.split_clip (song, id, beat)
  local clip, owner, index = M.clip (song, id)
  if not clip or not owner or not index then
    return song, nil
  end
  local at = beat - clip.start
  if at <= 1e-6 or at >= clip.length - 1e-6 then
    return song, nil
  end
  local s, new_id = M.new_id (song, 'c')
  local left = shallow (clip) --[[@as Daw.Clip]]
  local right = shallow (clip) --[[@as Daw.Clip]]
  left.length = at
  right.id = new_id
  right.start = clip.start + at
  right.length = clip.length - at
  if clip.notes then
    local l, r = {}, {} ---@type Daw.Note[], Daw.Note[]
    for _, n in ipairs (clip.notes) do
      if n.start < at then
        local copy = shallow (n) --[[@as Daw.Note]]
        copy.length = math.min (n.length, at - n.start)
        l[#l + 1] = copy
      else
        local copy = shallow (n) --[[@as Daw.Note]]
        copy.start = n.start - at
        r[#r + 1] = copy
      end
    end
    left.notes, right.notes = l, r
  end
  if clip.file then
    right.offset = (clip.offset or 0) + at * 60 / math.max (1, song.tempo)
  end
  s = with_track (s, owner.id, function (t)
    t.clips = shallow (t.clips) --[[@as Daw.Clip[] ]]
    t.clips[index] = left
    table.insert (t.clips, index + 1, right)
    return t
  end)
  return s, new_id
end

---Copies clips to just after the stretch they cover together, each on its own track.
---@param song Daw.Song
---@param ids string[]
---@return Daw.Song, string[]
function M.duplicate_clips (song, ids)
  local first = math.huge ---@type number
  local last = -math.huge ---@type number
  local found = {} ---@type { clip: Daw.Clip, track: Daw.Track }[]
  for _, id in ipairs (ids) do
    local c, t = M.clip (song, id)
    if c and t then
      found[#found + 1] = { clip = c, track = t }
      if c.start < first then
        first = c.start
      end
      if c.start + c.length > last then
        last = c.start + c.length
      end
    end
  end
  local s = song
  local out = {} ---@type string[]
  for _, f in ipairs (found) do
    local copy = M.copy (f.clip) --[[@as table<string, any>]]
    copy.id = nil
    copy.start = f.clip.start + (last - first)
    local new_id ---@type string
    s, new_id = M.add_clip (s, f.track.id, copy)
    out[#out + 1] = new_id
  end
  return s, out
end

---@param song Daw.Song
---@return number
function M.song_end (song)
  local finish = 0
  for _, t in ipairs (song.tracks) do
    for _, c in ipairs (t.clips) do
      finish = math.max (finish, c.start + c.length)
    end
  end
  return finish
end

return M
