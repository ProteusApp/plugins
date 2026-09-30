-- daw.engine: the sound. The engine itself is a page, page/engine.html, that runs in a
-- sandboxed web view and plays through Web Audio. This plugin keeps it playing the session's
-- song: on each change it turns the song into patches and parameters with daw_resolve and
-- posts the result. A knob or a fader takes a shorter path, so dragging one does not send
-- the whole song each time.
--
-- The page is also the master meter, and it sits on the toolbar. The browser holds a
-- sandboxed page's sound until someone clicks inside it, so until then the meter reads
-- "Click for sound".
--
-- Events it sends:
--   daw:transport (playing, beat)   playing started or stopped
--   daw:tick (beat)                 about 30 times a second while playing, for playheads
--   daw:recording (on)              recording started or stopped
--   daw:metronome (on)              the metronome was switched on or off
--   daw:sound (on)                  the page may make sound now, or not

-- lang=css
local CSS = [[
.daw-meter-box {
  display: flex;
  align-items: center;
  width: 128px;
  height: 22px;
  padding: 0 6px;
}
.daw-meter-box .ea-webview {
  min-height: 0 !important;
}
]]

---@type Proteus.Plugin
return {
  name = 'DAW engine',
  description = 'Plays the song through Web Audio in a web view: instruments, effects, the mixer and recording.',
  version = '1.0.0',
  requires = { proteus = '>=0.2.0', features = { 'permissions', 'webview' } },
  permissions = {},
  depends = {
    'lib.ui',
    'daw.core',
    'daw.devices',
    'daw.session',
    'core.commands',
  },
  optional = { 'ui.toolbar', 'ui.notify', 'core.keys' },
  activate = function (app)
    local ui = app.use ('ui')
    local daw = app.use ('daw') --[[@as Daw.Core]]
    local devices = app.use ('daw.devices') --[[@as Daw.Devices]]
    local session = app.use ('daw.session') --[[@as Daw.Session]]
    local commands = app.use ('commands')
    local toolbar = app.try_use ('toolbar')
    local notify = app.try_use ('notify')
    ui.css (CSS)

    local playing = false
    local recording = false
    local sound = false
    local position = 0
    local metronome = app.store.get ('metronome', false) == true
    local levels = { tracks = {}, master = { 0, 0 } } ---@type { tracks: table<string, number>, master: number[] }
    local warned = {} ---@type table<string, boolean>
    local push_pending = false
    local view = nil ---@type Proteus.El?

    ---@param message table
    local function post (message)
      if view then
        view:widget ('post', message)
      end
    end

    -- The song, sent to the page -----------------------------------------------------------------

    local function push ()
      push_pending = false
      local resolved, missing = daw.resolve.song (session.song (), devices.get)
      -- As JSON text, so an empty list stays a list on the way.
      post ({ type = 'load', song = app.json.encode (resolved) })
      for _, id in ipairs (missing) do
        if not warned[id] then
          warned[id] = true
          if notify then
            notify.warn (
              'This song uses the device '
                .. id
                .. ', which no running plugin provides. Its track plays without it.'
            )
          end
        end
      end
    end

    local function push_soon ()
      if push_pending then
        return
      end
      push_pending = true
      app.timer.after (0, push)
    end

    ---The track that live notes and recording go to: the armed track, or the selected one.
    ---@return string?
    local function live_track ()
      for _, t in ipairs (session.song ().tracks) do
        if t.arm and t.kind == 'instrument' then
          return t.id
        end
      end
      return session.selected_track ()
    end

    -- Recording ---------------------------------------------------------------------------------

    ---Puts what was just recorded into a new clip on the live track, in whole bars.
    ---@param taken Daw.Note[]
    local function keep_recording (taken)
      local track_id = live_track ()
      if #taken == 0 or not track_id then
        return
      end
      local song = session.song ()
      local bar = daw.song.beats_per_bar (song)
      local first = math.huge ---@type number
      local last = 0 ---@type number
      for _, n in ipairs (taken) do
        if n.start < first then
          first = n.start
        end
        if n.start + n.length > last then
          last = n.start + n.length
        end
      end
      local start = math.floor (first / bar) * bar
      local finish = math.max (start + bar, math.ceil (last / bar) * bar)
      local notes = {} ---@type Daw.Note[]
      for _, n in ipairs (taken) do
        notes[#notes + 1] = {
          pitch = math.floor (tonumber (n.pitch) or 60),
          start = n.start - start,
          length = math.max (1 / 32, n.length),
          velocity = tonumber (n.velocity) or 0.8,
        }
      end
      local next_song, clip = daw.song.add_clip (song, track_id, {
        name = 'Take',
        start = start,
        length = finish - start,
        notes = notes,
      })
      session.apply (next_song, { kind = 'edit', label = 'Record' })
      session.select_clips ({ clip })
      session.edit_clip (clip)
    end

    -- Messages from the page ------------------------------------------------------------------

    ---@param m any
    local function on_message (m)
      if type (m) ~= 'table' then
        return
      end
      local kind = m.type
      if kind == 'ready' then
        post ({ type = 'metronome', on = metronome })
        post ({ type = 'live', track = live_track () or '' })
        push ()
      elseif kind == 'tick' then
        position = tonumber (m.beat) or position
        app.emit ('daw:tick', position)
      elseif kind == 'levels' then
        levels = {
          tracks = type (m.tracks) == 'table' and m.tracks or {},
          master = type (m.master) == 'table' and m.master or { 0, 0 },
        }
      elseif kind == 'transport' then
        playing = m.playing == true
        position = tonumber (m.beat) or 0
        -- Stopping ends a recording too. The page has sent what it recorded already.
        if not playing and recording then
          recording = false
          post ({ type = 'record', on = false })
          app.emit ('daw:recording', false)
        end
        app.emit ('daw:transport', playing, position)
        app.emit ('daw:tick', position)
      elseif kind == 'recorded' then
        keep_recording (type (m.notes) == 'table' and m.notes or {})
      elseif kind == 'sound' then
        sound = m.on == true
        app.emit ('daw:sound', sound)
      elseif kind == 'warning' then
        app.warn (tostring (m.message))
      end
    end

    view = ui.webview ({
      page = 'page/engine.html',
      on_message = on_message,
      on_status = function (status)
        if not status.responsive and notify then
          notify.warn (
            'The sound engine stopped answering'
              .. (status.error and (': ' .. status.error) or '.')
          )
        end
      end,
    })
    local box = ui.div ({
      class = 'daw-meter-box',
      title = 'Master level. Click here once to let the DAW make sound.',
      view,
    })
    if toolbar then
      toolbar.add (box, { align = 'right', order = 50 })
    else
      -- The page must be on screen to be clicked, so it stays in a corner.
      box:style ('position', 'fixed')
      box:style ('right', '8px')
      box:style ('bottom', '8px')
      ui.mount (box)
    end
    app.dispose (function ()
      view = nil
    end)

    app.on ('daw:changed', function (_, change)
      local c = change --[[@as Daw.Change]]
      if c.kind == 'param' and c.device and c.key then
        post ({ type = 'param', device = c.device, key = c.key, value = c.value })
      elseif c.kind == 'mix' and c.track and c.key then
        post ({ type = 'mix', track = c.track, key = c.key, value = c.value })
      else
        push_soon ()
      end
      post ({ type = 'live', track = live_track () or '' })
    end)
    app.on ('daw:devices', push_soon)
    app.on ('daw:selection', function ()
      post ({ type = 'live', track = live_track () or '' })
    end)

    -- The service -----------------------------------------------------------------------------

    ---@type Daw.Engine
    local service = {
      play = function (from)
        post ({ type = 'play', from = from })
      end,
      stop = function ()
        post ({ type = 'stop' })
      end,
      pause = function ()
        post ({ type = 'pause' })
      end,
      toggle = function ()
        post ({ type = playing and 'stop' or 'play' })
      end,
      seek = function (beat)
        position = beat
        post ({ type = 'seek', beat = beat })
      end,
      position = function ()
        return position
      end,
      playing = function ()
        return playing
      end,
      sound = function ()
        return sound
      end,
      note_on = function (track_id, pitch, velocity)
        post ({
          type = 'note_on',
          track = track_id,
          pitch = pitch,
          velocity = velocity or 0.8,
        })
      end,
      note_off = function (track_id, pitch)
        post ({ type = 'note_off', track = track_id, pitch = pitch })
      end,
      all_notes_off = function ()
        post ({ type = 'all_off' })
      end,
      set_metronome = function (on)
        metronome = on
        app.store.set ('metronome', on)
        post ({ type = 'metronome', on = on })
        app.emit ('daw:metronome', on)
      end,
      metronome = function ()
        return metronome
      end,
      set_recording = function (on)
        recording = on
        post ({ type = 'record', on = on })
        app.emit ('daw:recording', recording)
      end,
      recording = function ()
        return recording
      end,
      levels = function ()
        return levels
      end,
    }
    app.provide ('daw.engine', service)

    commands.register ({
      id = 'daw.panic',
      category = 'DAW',
      title = 'Stop All Notes',
      icon = 'octagon-x',
      run = function ()
        post ({ type = 'stop' })
        post ({ type = 'all_off' })
      end,
    })
    commands.register ({
      id = 'daw.reload_engine',
      category = 'DAW',
      title = 'Restart the Sound Engine',
      icon = 'rotate-cw',
      run = function ()
        if view then
          view:widget ('reload')
        end
      end,
    })
  end,
}
