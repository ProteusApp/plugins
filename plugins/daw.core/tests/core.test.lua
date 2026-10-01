local demo = require ('daw_demo') --[[@as Daw.DemoModule]]
local file = require ('daw_file') --[[@as Daw.FileModule]]
local history = require ('daw_history') --[[@as Daw.HistoryModule]]
local notes = require ('daw_notes') --[[@as Daw.NotesModule]]
local song = require ('daw_song') --[[@as Daw.SongModule]]
local time = require ('daw_time') --[[@as Daw.TimeModule]]

---@param pitch integer
---@param start number
---@param length number
---@return Daw.Note
local function n (pitch, start, length)
  return { pitch = pitch, start = start, length = length, velocity = 0.8 }
end

---A song with one instrument track holding one clip.
---@return Daw.Song, string, string
local function one_clip ()
  local s, track = song.add_track (song.new ('T'), {
    instrument = { id = '', device = 'daw.synth', params = {}, bypass = false },
  })
  local s2, clip = song.add_clip (s, track, {
    start = 4,
    length = 4,
    notes = { n (60, 0, 1), n (64, 1.5, 1), n (67, 3, 2) },
  })
  return s2, track, clip
end

-- time -------------------------------------------------------------------------------------

test ('time formats beats as bars, beats and sixteenths from 1', function ()
  eq (time.format (0, 4), '1.1.1')
  eq (time.format (5.25, 4), '2.2.2')
  eq (time.format (2.9999999, 4), '1.4.1', 'rounding lands on the beat')
  eq (time.format (3, 3), '2.1.1')
  eq (time.format_short (9, 4), '3.2')
end)

test ('time snaps to grids and leaves off alone', function ()
  eq (time.snap (1.2, '1/4'), 1)
  eq (time.snap (1.2, '1/8'), 1)
  eq (time.snap (1.3, '1/8'), 1.5)
  eq (time.snap_down (1.99, '1/4'), 1)
  eq (time.snap (1.37, 'off'), 1.37)
  eq (time.grid_beats ('1/16'), 0.25)
  eq (time.grid_beats ('nonsense'), 0)
end)

test ('time names notes and reads them back', function ()
  eq (time.note_name (60), 'C4')
  eq (time.note_name (61), 'C#4')
  eq (time.note_name (21), 'A0')
  eq (time.parse_note ('C4'), 60)
  eq (time.parse_note ('f#3'), 54)
  eq (time.parse_note ('Bb2'), 46)
  eq (time.parse_note ('64'), 64)
  eq (time.parse_note ('H2'), nil)
  eq (time.parse_note ('200'), nil)
  ok (time.is_black (61))
  ok (not time.is_black (64))
end)

test ('time converts beats to a clock', function ()
  eq (time.seconds (4, 120), 2)
  eq (time.format_clock (65.25), '1:05.250')
end)

-- song -------------------------------------------------------------------------------------

test ('add_track gives ids to the track, its devices and its clips', function ()
  local s, id = song.add_track (song.new (), {
    name = 'Keys',
    instrument = { id = '', device = 'daw.synth', params = {}, bypass = false },
    effects = { { id = '', device = 'daw.delay', params = {}, bypass = false } },
    clips = { { start = 0, length = 4, notes = {} } },
  })
  local t = song.track (s, id)
  ok (t)
  eq (t and t.name, 'Keys')
  eq (t and t.instrument and t.instrument.id, 'd2')
  eq (t and t.effects[1].id, 'd3')
  eq (t and t.clips[1].id, 'c4')
  eq (t and t.clips[1].name, 'Keys')
  eq (s.ids, 4)
end)

test (
  'operations leave the old song untouched and share what did not change',
  function ()
    local s, track, clip = one_clip ()
    local s2 = song.update_clip (s, clip, { start = 8 })
    local old = song.clip (s, clip)
    local new = song.clip (s2, clip)
    eq (old and old.start, 4)
    eq (new and new.start, 8)
    ok (old and new and old.notes == new.notes, 'the notes are shared')
    local s3 = song.update_track (s2, track, { volume = 20, pan = -3 })
    local t = song.track (s3, track)
    eq (t and t.volume, 6)
    eq (t and t.pan, -1)
    eq ((song.track (s2, track) or {}).volume, 0)
  end
)

test ('split_clip cuts notes at the split and moves the rest', function ()
  local s, _, clip = one_clip ()
  local s2, right = song.split_clip (s, clip, 6)
  ok (right)
  local l = song.clip (s2, clip)
  local r = song.clip (s2, right or '')
  eq (l and l.length, 2)
  eq (r and r.start, 6)
  eq (r and r.length, 2)
  eq (l and l.notes, { n (60, 0, 1), n (64, 1.5, 0.5) })
  eq (r and r.notes, { n (67, 1, 2) })
  local same, none = song.split_clip (s, clip, 4)
  ok (same == s and none == nil, 'a split at the edge does nothing')
end)

test ('duplicate_clips places copies right after the selection', function ()
  local s, track, clip = one_clip ()
  local s2, second = song.add_clip (s, track, { start = 10, length = 2 })
  local s3, ids = song.duplicate_clips (s2, { clip, second })
  eq (#ids, 2)
  eq ((song.clip (s3, ids[1]) or {}).start, 12)
  eq ((song.clip (s3, ids[2]) or {}).start, 18)
  eq (song.song_end (s3), 20)
end)

test ('move_clip goes between tracks of the same kind only', function ()
  local s, track, clip = one_clip ()
  local s2, other = song.add_track (s, {})
  local s3, audio = song.add_track (s2, { kind = 'audio' })
  local moved = song.move_clip (s3, clip, other, 0)
  local c, owner = song.clip (moved, clip)
  eq (owner and owner.id, other)
  eq (c and c.start, 0)
  eq (#(song.track (moved, track) or { clips = {} }).clips, 0)
  ok (
    song.move_clip (s3, clip, audio, 0) == s3,
    'an audio track refuses a MIDI clip'
  )
end)

test ('devices can be found, changed, moved and removed anywhere', function ()
  local s, track = one_clip ()
  local s2, a = song.add_effect (
    s,
    track,
    { id = '', device = 'daw.eq', params = {}, bypass = false }
  )
  local s3, b = song.add_effect (
    s2,
    track,
    { id = '', device = 'daw.delay', params = {}, bypass = false }
  )
  local s4, m = song.add_effect (
    s3,
    'master',
    { id = '', device = 'daw.comp', params = {}, bypass = false }
  )
  local s5 = song.set_param (s4, b, 'mix', 0.5)
  eq ((song.device (s5, b) or {}).params, { mix = 0.5 })
  eq ((song.device (s4, b) or {}).params, {})
  local s6 = song.move_effect (s5, b, 1)
  local t = song.track (s6, track)
  eq (t and t.effects[1].id, b)
  eq (t and t.effects[2].id, a)
  local s6b =
    song.set_preset (song.update_device (s6, b, { preset = 'Dub' }), b, nil)
  eq ((song.device (s6b, b) or {}).params, {})
  eq ((song.device (s6b, b) or {}).preset, nil)
  local s7 = song.remove_device (s6, m)
  eq (#s7.master.effects, 0)
  local inst = (song.track (s7, track) or {}).instrument
  ok (inst)
  local s8 = song.remove_device (s7, inst and inst.id or '')
  eq ((song.track (s8, track) or {}).instrument, nil)
end)

test ('remove_clips and remove_track', function ()
  local s, track, clip = one_clip ()
  eq (#song.remove_clips (s, { clip }).tracks[1].clips, 0)
  ok (song.remove_clips (s, { 'nope' }) == s)
  eq (#song.remove_track (s, track).tracks, 0)
end)

test ('set_loop keeps the loop the right way round', function ()
  local s = song.set_loop (song.new (), { start = 8, finish = 4 })
  eq (s.loop.start, 8)
  eq (s.loop.finish, 9)
end)

-- notes ------------------------------------------------------------------------------------

test ('notes move, resize and quantize in place', function ()
  local list = { n (60, 0.1, 1), n (62, 1.9, 0.4) }
  local moved = notes.move (list, { 2 }, 1, 2, 4)
  eq (moved[1], list[1])
  eq (moved[2], n (64, 2.9, 0.4))
  eq (notes.move (list, { 1 }, -5, 200, 4)[1], n (127, 0, 1))
  eq (notes.resize (list, { 1 }, -2, 0.25)[1].length, 0.25)
  local q = notes.quantize (list, {}, '1/4', true)
  eq (q[1], n (60, 0, 1))
  eq (q[2], n (62, 2, 1))
  eq (list[2].start, 1.9, 'the old list is untouched')
end)

test ('notes are found at a point and in a box', function ()
  local list = { n (60, 0, 1), n (60, 0.5, 1), n (64, 2, 1) }
  eq (notes.at (list, 0.75, 60), 2)
  eq (notes.at (list, 0.25, 60), 1)
  eq (notes.at (list, 0.25, 61), nil)
  eq (notes.within (list, 0.9, 2.5, 59, 65), { 1, 2, 3 })
  eq (notes.within (list, 1.6, 3, 63, 70), { 3 })
  local lo, hi = notes.range (list)
  eq ({ lo, hi }, { 60, 64 })
end)

test ('notes add, remove, transpose and set velocity', function ()
  local list, index = notes.add (
    {},
    { pitch = 200, start = -1, length = 1, velocity = 2 }
  )
  eq (index, 1)
  eq (list[1], { pitch = 127, start = 0, length = 1, velocity = 1 })
  eq (#notes.remove ({ n (1, 0, 1), n (2, 0, 1) }, { 1 }), 1)
  eq (notes.transpose ({ n (60, 0, 1) }, {}, -12)[1].pitch, 48)
  eq (notes.set_velocity ({ n (60, 0, 1) }, {}, 0)[1].velocity, 0.01)
end)

-- file -------------------------------------------------------------------------------------

test ('normalize turns anything into a valid song', function ()
  local s = file.normalize (nil)
  eq (s.name, 'Untitled')
  eq (#s.tracks, 0)
  local messy = file.normalize ({
    tempo = 900,
    signature = { 7 },
    loop = { on = true, start = 8, finish = 2 },
    tracks = {
      {
        id = 'x',
        kind = 'instrument',
        instrument = {
          device = 'daw.synth',
          params = { cutoff = 900, bad = {} },
        },
        clips = { { notes = { { pitch = 60 }, { nope = true } } } },
        effects = {},
      },
      {
        id = 'x',
        kind = 'audio',
        clips = { { file = 'C:/a.wav', notes = {} } },
      },
    },
  })
  eq (messy.tempo, 400)
  eq (messy.signature, { 7, 4 })
  eq (messy.loop, { on = true, start = 8, finish = 12 })
  local t1, t2 = messy.tracks[1], messy.tracks[2]
  eq (t1.id, 'x')
  ok (t2.id ~= 'x', 'a repeated id is replaced')
  eq (t1.instrument and t1.instrument.params, { cutoff = 900 })
  eq (#(t1.clips[1].notes or {}), 1)
  eq (t2.clips[1].notes, nil)
  eq (t2.clips[1].file, 'C:/a.wav')
  ok (messy.ids >= 1)
end)

test ('a saved song reads back the same', function ()
  local s = demo.song ()
  local back = file.normalize (file.for_save (s))
  eq (back, s)
end)

test (
  'an empty list that came back as an empty object reads as a list',
  function ()
    local s = file.normalize ({
      tracks = { { clips = { { notes = {} } } } },
      master = { effects = {} },
    })
    eq (s.tracks[1].clips[1].notes, {})
  end
)

test ('a format 1 song reads as format 2, without device states', function ()
  local old = file.normalize ({
    format = 1,
    tracks = {
      {
        id = 't1',
        instrument = { id = 'd1', device = 'daw.synth', params = {} },
        effects = { { id = 'd2', device = 'daw.delay' } },
      },
    },
  })
  eq (old.format, 2)
  eq (old.tracks[1].instrument and old.tracks[1].instrument.state, nil)
  eq (song.states (old), {})
  eq (file.for_save (old).format, 2)
end)

test ('a device keeps its saved state through a save', function ()
  local s = file.normalize ({
    format = 2,
    master = {
      effects = {
        { id = 'd3', device = 'wam.echo', state = '{"feedback":0.4}' },
      },
    },
    tracks = {
      {
        id = 't1',
        instrument = { id = 'd1', device = 'native.clap.x', state = 'AAEC' },
        effects = {
          { id = 'd2', device = 'daw.delay', state = '' },
          { id = 'd4', device = 'daw.delay', state = { 'not text' } },
        },
      },
    },
  })
  eq (song.states (s), { d1 = 'AAEC', d3 = '{"feedback":0.4}' })
  eq (s.tracks[1].effects[1].state, nil, 'an empty state is none')
  eq (s.tracks[1].effects[2].state, nil, 'a state is text')
  local back = file.normalize (file.for_save (s))
  eq (back, s)
end)

test (
  'set_states keeps what devices saved, and only copies what changed',
  function ()
    local s = file.normalize ({
      tracks = {
        {
          id = 't1',
          instrument = { id = 'd1', device = 'native.clap.x' },
          effects = { { id = 'd2', device = 'daw.delay' } },
        },
        { id = 't2', instrument = { id = 'd3', device = 'daw.synth' } },
      },
    })
    local next_song = song.set_states (s, { d1 = 'AAEC', gone = 'xyz' })
    eq (song.states (next_song), { d1 = 'AAEC' })
    eq (song.states (s), {}, 'the old song stays as it was')
    ok (next_song.tracks[2] == s.tracks[2], 'other tracks are shared')
    ok (song.set_states (next_song, { d1 = 'AAEC' }) == next_song, 'nothing new')
    ok (song.set_states (next_song, {}) == next_song)
    eq (song.states (song.set_states (next_song, { d1 = '' })), {})
    -- A copied device keeps its state, and a different device drops it.
    local ref = song.copy (next_song.tracks[1].instrument) --[[@as Daw.DeviceRef]]
    ref.id = ''
    local copied = song.add_track (next_song, { instrument = ref })
    local inst = copied.tracks[3].instrument --[[@as Daw.DeviceRef]]
    eq (inst.state, 'AAEC')
    ok (inst.id ~= 'd1', 'the copy has an id of its own')
    local swapped =
      song.update_device (next_song, 'd1', { device = 'native.vst3.y' })
    eq (song.states (swapped), {})
    local same = song.update_device (next_song, 'd1', { bypass = true })
    eq (song.states (same), { d1 = 'AAEC' })
  end
)

-- history ----------------------------------------------------------------------------------

test (
  'history undoes and redoes, and groups quick changes with the same key',
  function ()
    local clock = 0
    local h = history.new (10, function ()
      return clock
    end)
    local a, b, c, d =
      song.new ('a'), song.new ('b'), song.new ('c'), song.new ('d')
    h.push (a)
    h.push (b, 'knob')
    clock = 500
    h.push (c, 'knob')
    eq (h.undo (d), b)
    eq (h.undo (b), a)
    eq (h.undo (a), nil)
    eq (h.redo (a), b)
    ok (h.can_redo ())
    h.push (b)
    ok (not h.can_redo (), 'a new change clears redo')
    h.seal ()
    clock = 600
    h.push (c, 'knob')
    h.push (d, 'knob')
    eq (h.undo (song.new ('e')), c)
  end
)

-- demo -------------------------------------------------------------------------------------

test ('the demo song loops four bars on four tracks', function ()
  local s = demo.song ()
  eq (#s.tracks, 4)
  eq (s.loop.on, true)
  eq (song.song_end (s), 16)
  for _, t in ipairs (s.tracks) do
    ok (t.instrument, t.name .. ' has an instrument')
    eq (#t.clips, 1)
  end
end)
