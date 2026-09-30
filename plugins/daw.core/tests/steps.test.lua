local song = require ('daw_song') --[[@as Daw.SongModule]]
local steps = require ('daw_steps') --[[@as Daw.StepsModule]]

---A song with one instrument track and no clips, in 4/4.
---@return Daw.Song, string
local function empty ()
  return song.add_track (song.new ('T'), {
    instrument = { id = '', device = 'daw.drums', params = {}, bypass = false },
  })
end

---@param row boolean[]
---@return string
local function show (row)
  local out = {} ---@type string[]
  for i, on in ipairs (row) do
    out[i] = on and 'x' or '.'
  end
  return table.concat (out)
end

test ('a bar in 4/4 has sixteen steps', function ()
  local s = empty ()
  eq (steps.count (s), 16)
  eq (steps.count (song.set (s, { signature = { 3, 4 } })), 12)
end)

test ('a step on an empty track makes a one-bar clip', function ()
  local s, track = empty ()
  local s2, clip_id = steps.toggle (s, track, 36, 2, 5)
  local clip = song.clip (s2, clip_id or '')
  ok (clip, 'a clip')
  eq (clip and clip.start, 8)
  eq (clip and clip.length, 4)
  eq (clip and clip.notes, {
    { pitch = 36, start = 1, length = 0.25, velocity = 0.8 },
  })
  eq (show (steps.row (s2, track, 36, 2)), '....x...........')
  eq (show (steps.row (s2, track, 38, 2)), '................', 'another pitch')
  eq (show (steps.row (s2, track, 36, 1)), '................', 'another bar')
end)

test (
  'more steps go into the same clip, and a second press takes one off',
  function ()
    local s, track = empty ()
    local clip_id
    for _, i in ipairs ({ 1, 5, 9, 13 }) do
      s, clip_id = steps.toggle (s, track, 36, 0, i)
    end
    local t = song.track (s, track)
    eq (t and #t.clips, 1)
    eq (show (steps.row (s, track, 36, 0)), 'x...x...x...x...')
    s = steps.toggle (s, track, 36, 0, 5)
    eq (show (steps.row (s, track, 36, 0)), 'x.......x...x...')
    local clip = song.clip (s, clip_id or '')
    eq (clip and #clip.notes, 3)
  end
)

test ('steps read notes of clips that start before the bar', function ()
  local s, track = empty ()
  local s2, id = song.add_clip (s, track, {
    start = 2,
    length = 8,
    notes = {
      { pitch = 60, start = 2, length = 1, velocity = 0.8 },
      { pitch = 60, start = 2.6, length = 0.2, velocity = 0.8 },
    },
  })
  ok (id)
  -- Beats 4 and 4.6: steps 1 and 3 of the second bar.
  eq (show (steps.row (s2, track, 60, 1)), 'x.x.............')
  local s3 = steps.toggle (s2, track, 60, 1, 3)
  eq (show (steps.row (s3, track, 60, 1)), 'x...............')
  local s4 = steps.toggle (s3, track, 60, 1, 16)
  local t = song.track (s4, track)
  eq (t and #t.clips, 1, 'the clip that covers the step takes it')
end)

test ('an audio track takes no steps', function ()
  local s, track = song.add_track (song.new ('T'), { kind = 'audio' })
  local s2, id = steps.toggle (s, track, 60, 0, 1)
  eq (s2, s)
  eq (id, nil)
end)

test ('a channel plays the pitch its notes use most', function ()
  local s, track = empty ()
  eq (steps.pitch_of (song.track (s, track) --[[@as Daw.Track]]), 60)
  s = select (1, steps.toggle (s, track, 42, 0, 1))
  s = select (1, steps.toggle (s, track, 42, 0, 3))
  s = select (1, steps.toggle (s, track, 36, 0, 5))
  eq (steps.pitch_of (song.track (s, track) --[[@as Daw.Track]]), 42)
end)
