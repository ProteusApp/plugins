-- daw.engine: the sound. The engine itself is a page, page/engine.html, that runs in a
-- sandboxed web view and plays through Web Audio. This plugin keeps it playing the session's
-- song: on each change it turns the song into patches and parameters with daw_resolve and
-- posts the result. A knob or a fader takes a shorter path, so dragging one does not send
-- the whole song each time.
--
-- The page is also the master meter, and it sits on the toolbar. It asks for autoplay, and
-- where the browser still holds its sound, the meter reads "Click for sound".
--
-- Web Audio Modules come from packs: plugins that register module devices with daw.devices
-- and export the folder that holds them. The page is served with its own files and the
-- packs' folders, loads each module in an AudioWorklet, and reports its parameters, which
-- daw.devices keeps for the rack. A new pack starts the page again with its folder.
--
-- The sound can also play on the app's native engine (`app.audio`), a process of its own that
-- takes the same messages as the page and can host CLAP and VST3 plugins. The setting
-- daw.engine picks it. The page then only draws the master meter, from the engine's levels.
--
-- Audio files come from the user, one pick at a time, through app.grants: the plugin holds
-- an id and a name, never a path. A song keeps the ids, the page asks for a file when it
-- needs one, and the app sends the bytes straight into the page. Export as WAV works the
-- same way: the user picks where to save, and only the page writes there.
--
-- Events it sends:
--   daw:transport (playing, beat)   playing started or stopped
--   daw:tick (beat)                 about 30 times a second while playing, for playheads
--   daw:recording (on)              recording started or stopped
--   daw:metronome (on)              the metronome was switched on or off
--   daw:sound (on)                  the page may make sound now, or not
--   daw:file (id)                   an audio file decoded or failed, see engine.file

local AUDIO = {
  {
    name = 'Audio',
    extensions = { 'wav', 'mp3', 'ogg', 'flac', 'm4a', 'aac', 'aif', 'aiff' },
  },
}

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
  description = "Plays the song through Web Audio in a web view, or on the app's native engine: instruments, effects, the mixer and recording.",
  version = '1.2.0',
  requires = {
    proteus = '>=0.2.0',
    features = {
      'permissions',
      'webview',
      'grants',
      'autoplay',
      'webview-files',
    },
  },
  permissions = {},
  depends = {
    'lib.ui',
    'daw.core',
    'daw.devices',
    'daw.session',
    'core.commands',
  },
  optional = {
    'ui.toolbar',
    'ui.notify',
    'core.keys',
    'ui.windows',
    'core.settings',
    'daw.native',
  },
  activate = function (app)
    local ui = app.use ('ui')
    local daw = app.use ('daw') --[[@as Daw.Core]]
    local devices = app.use ('daw.devices') --[[@as Daw.Devices]]
    local session = app.use ('daw.session') --[[@as Daw.Session]]
    local commands = app.use ('commands')
    local toolbar = app.try_use ('toolbar')
    local windows = app.try_use ('windows') --[[@as Proteus.Windows?]]
    local notify = app.try_use ('notify')
    local settings = app.try_use ('settings')
    ui.css (CSS)

    if settings then
      settings.define ('daw.engine', {
        title = 'Sound engine',
        type = 'select',
        options = { 'web', 'native' },
        default = 'web',
        description = "web plays in a sandboxed web page, and plays Web Audio Modules. native plays in the app's own engine, a process of its own, and plays CLAP and VST3 plugins.",
      })
    end

    -- The native engine while it plays, or nil when the page does.
    local native = nil ---@type Proteus.AudioEngine?

    local playing = false
    local recording = false
    local sound = false
    local position = 0
    local metronome = app.store.get ('metronome', false) == true
    local levels = { tracks = {}, master = { 0, 0 } } ---@type { tracks: table<string, number>, master: number[] }
    local warned = {} ---@type table<string, boolean>
    local push_pending = false
    local view = nil ---@type Proteus.El?
    local files = {} ---@type table<string, Daw.EngineFile>
    -- The name of each file an export is writing, by grant id.
    local exporting = {} ---@type table<string, string>

    ---Whether the setting asks for the native engine, and this Proteus has one.
    ---@return boolean
    local function wants_native ()
      return settings ~= nil
        and settings.get ('daw.engine') == 'native'
        and app.audio ~= nil
    end

    ---A message for the page itself, whichever engine plays.
    ---@param message table
    local function page_post (message)
      if view then
        view:widget ('post', message)
      end
    end

    ---A message for the engine that plays.
    ---@param message table
    local function post (message)
      if native then
        native.send (message)
      else
        page_post (message)
      end
    end

    -- The song, sent to the page -----------------------------------------------------------------

    ---A value as the device takes it. A Web Audio Module takes a choice by its index, from 0.
    ---@param device_id string
    ---@param key string
    ---@param value any
    ---@return any
    local function module_value (device_id, key, value)
      local ref = daw.song.device (session.song (), device_id)
      local spec = ref and devices.get (ref.device)
      local param = spec and spec.wam and daw.device.param (spec, key)
      if param and param.kind == 'choice' then
        for i, o in ipairs (param.options or {}) do
          if o == value then
            return i - 1
          end
        end
        return 0
      end
      return value
    end

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

    -- Audio files ------------------------------------------------------------------------------

    ---What the engine knows of a file, by grant id. Nil for an id this plugin was never given.
    ---@param id string
    ---@return Daw.EngineFile?
    local function file_info (id)
      local known = files[id]
      if known then
        return known
      end
      local g = app.grants.get (id)
      if not g then
        return nil
      end
      files[id] = { name = g.name }
      return files[id]
    end

    ---@param id string
    local function send_file (id)
      if not view then
        return
      end
      local g = app.grants.get (id)
      if g and g.mode == 'read' and native then
        native.send_file (id)
      elseif g and g.mode == 'read' then
        view:widget ('send_file', id)
      else
        post ({
          type = 'missing',
          file = id,
          error = 'the DAW no longer has this file. Pick it again.',
        })
      end
    end

    ---@param id string
    ---@param m table
    local function file_loaded (id, m)
      local info = file_info (id) or { name = id }
      info.failed = nil
      info.seconds = tonumber (m.seconds)
      info.peaks = type (m.peaks) == 'table' and m.peaks or nil
      files[id] = info
      app.emit ('daw:file', id)
    end

    ---@param id string
    ---@param err string
    local function file_failed (id, err)
      local info = file_info (id) or { name = id }
      local first = not info.failed
      info.failed = err
      files[id] = info
      if first and notify then
        notify.warn ('The audio file ' .. info.name .. ' did not load: ' .. err)
      end
      app.emit ('daw:file', id)
    end

    -- Messages from the page ------------------------------------------------------------------

    ---@param m any
    local function on_message (m)
      if type (m) ~= 'table' then
        return
      end
      local kind = m.type --[[@as string?]]
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
        if native then
          page_post ({ type = 'meter', master = levels.master })
        end
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
      elseif kind == 'wam_params' then
        devices.describe (
          tostring (m.device),
          type (m.info) == 'table' and m.info or {}
        )
      elseif kind == 'want' then
        send_file (tostring (m.file))
      elseif kind == 'file' then
        file_loaded (tostring (m.file), m)
      elseif kind == 'file_failed' then
        file_failed (tostring (m.file), tostring (m.error))
      elseif kind == 'rendered' or kind == 'render_failed' then
        local g = app.grants.get (tostring (m.file))
        -- A newer Proteus drops a save grant once the page wrote it, so the export keeps the name.
        local name = exporting[tostring (m.file)]
          or (g and g.name)
          or 'the file'
        exporting[tostring (m.file)] = nil
        -- The page may write to it only once: a new export asks where again.
        app.grants.forget (tostring (m.file))
        if notify then
          if kind == 'rendered' then
            notify.success (
              string.format (
                'Exported %s, %.1f seconds.',
                name,
                tonumber (m.seconds) or 0
              )
            )
          else
            notify.error (
              'Could not export ' .. name .. ': ' .. tostring (m.error)
            )
          end
        end
      end
    end

    ---The plugins whose Web Audio Modules the song may use: the owners of every module
    ---device, in order. The page mounts their exported folders.
    ---@return string[]
    local function packs ()
      local seen = {} ---@type table<string, boolean>
      local out = {} ---@type string[]
      for _, spec in ipairs (devices.list ()) do
        local owner = spec.owner or ''
        if spec.wam and owner ~= '' and not seen[owner] then
          seen[owner] = true
          out[#out + 1] = owner
        end
      end
      table.sort (out)
      return out
    end

    local mounted = '' -- The packs the page has now, joined.

    ---@return Proteus.El
    local function make_view ()
      local list = packs ()
      mounted = table.concat (list, ',')
      return ui.webview ({
        page = 'page/engine.html',
        -- Served with its files, so it loads modules, worklets and the packs' folders.
        files = true,
        mounts = list,
        autoplay = true,
        on_message = function (m)
          -- While the native engine plays, the page is only the meter.
          if not native then
            on_message (m)
          elseif type (m) == 'table' and m.type == 'ready' then
            page_post ({ type = 'native', on = true })
          end
        end,
        on_status = function (status)
          if not status.responsive and notify then
            notify.warn (
              'The sound engine stopped answering'
                .. (status.error and (': ' .. status.error) or '.')
            )
          end
        end,
      })
    end

    view = make_view ()
    local box = ui.div ({
      class = 'daw-meter-box',
      title = 'Master level. Click here once to let the DAW make sound.',
      view,
    })

    -- A pack that arrives or leaves changes what the page may load, so the page starts again
    -- with the new folders. It asks for the song as it starts.
    local function remount ()
      if table.concat (packs (), ',') == mounted or not view then
        return
      end
      view:remove ()
      view = make_view ()
      box:append (view)
    end
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
      native = nil
    end)

    -- The native engine -------------------------------------------------------------------

    ---The engine ended: nothing plays or records, and the meter falls.
    local function stopped ()
      if recording then
        recording = false
        app.emit ('daw:recording', false)
      end
      playing = false
      app.emit ('daw:transport', false, position)
      levels = { tracks = {}, master = { 0, 0 } }
      page_post ({ type = 'meter', master = levels.master })
    end

    local function start_native ()
      -- daw.native, when it runs, lends the engine its right to load native plugins.
      local lender = app.try_use ('daw.native')
      local engine ---@type Proteus.AudioEngine
      engine = app.audio.open (function (m)
        if native ~= engine then
          return
        end
        if
          type (m) == 'table' and (m.type == 'exit' or m.type == 'crashed')
        then
          -- What played stopped with it. A crashed engine starts again on its own and says
          -- ready, and the song goes to it as it does to a new one.
          stopped ()
          if m.type == 'exit' then
            native = nil
            if notify then
              local why = m.error and (': ' .. tostring (m.error)) or ''
              notify.warn (
                'The native sound engine stopped'
                  .. why
                  .. (why:find ('[.!?]$') and ' ' or '. ')
                  .. 'Restart the Sound Engine starts it again.'
              )
            end
          elseif notify and (tonumber (m.attempt) or 1) <= 1 then
            -- Once for crashes in a row: the app gives up after a few, and says so.
            notify.warn (
              'The native sound engine stopped'
                .. (m.reason and (': ' .. tostring (m.reason)) or '')
                .. '. It starts again and loads the song.'
            )
          end
          return
        end
        on_message (m)
      end, { plugins = lender and lender.lend () or nil })
      native = engine
      page_post ({ type = 'native', on = true })
    end

    ---Moves the sound to the engine the setting names. What plays stops, and the other engine
    ---takes the song.
    local function follow_setting ()
      local want = wants_native ()
      if want == (native ~= nil) then
        return
      end
      post ({ type = 'stop' })
      if want then
        start_native ()
      else
        local was = native
        native = nil
        if was then
          was.close ()
        end
        page_post ({ type = 'native', on = false })
        page_post ({ type = 'metronome', on = metronome })
        push ()
      end
    end
    if wants_native () then
      start_native ()
    end
    app.on ('settings:changed', function (key)
      if key == 'daw.engine' then
        follow_setting ()
      end
    end)

    -- Module editors -----------------------------------------------------------------------

    -- The open editor windows of Web Audio Modules, by device id.
    local editors = {} ---@type table<string, { view: Proteus.El, ready: boolean }>

    ---Every value of a module device, as its module takes them.
    ---@param device_id string
    ---@return table<string, any>
    local function module_values (device_id)
      local ref = daw.song.device (session.song (), device_id)
      local spec = ref and devices.get (ref.device)
      local out = {} ---@type table<string, any>
      if not ref or not spec then
        return out
      end
      for _, p in ipairs (spec.params) do
        out[p.key] =
          module_value (device_id, p.key, daw.device.value (spec, ref, p.key))
      end
      return out
    end

    ---Takes values an editor changed into the song, one parameter at a time, so the engine
    ---plays each at once and a drag is one undo step.
    ---@param device_id string
    ---@param values table<string, any>
    local function from_editor (device_id, values)
      local song = session.song ()
      local ref = daw.song.device (song, device_id)
      local spec = ref and devices.get (ref.device)
      if not ref or not spec then
        return
      end
      for key, v in pairs (values) do
        local param = daw.device.param (spec, tostring (key))
        if param then
          local value = v ---@type Daw.Value
          if param.kind == 'choice' then
            value = (param.options or {})[math.floor (tonumber (v) or 0) + 1]
              or param.default
          elseif param.kind == 'toggle' then
            value = (tonumber (v) or 0) ~= 0
          end
          session.apply (
            daw.song.set_param (session.song (), device_id, param.key, value),
            {
              kind = 'param',
              device = device_id,
              key = param.key,
              value = value,
            },
            'param:' .. device_id .. ':' .. param.key
          )
        end
      end
    end

    ---Opens a module device's own editor in a window.
    ---@param device_id string
    local function open_editor (device_id)
      local song = session.song ()
      local ref, track = daw.song.device (song, device_id)
      local spec = ref and devices.get (ref.device)
      if not ref or not spec or not spec.wam or not windows then
        return
      end
      local win_id = 'daw.editor.' .. device_id
      local title = spec.name .. (track and (' - ' .. track.name) or '')
      if editors[device_id] then
        windows.set_title (win_id, title)
        windows.show (win_id)
        return
      end
      local editor = { ready = false } ---@type { view: Proteus.El, ready: boolean }
      editor.view = ui.webview ({
        page = 'page/editor.html',
        files = true,
        mounts = { spec.owner },
        autoplay = true,
        on_message = function (m)
          if type (m) ~= 'table' then
            return
          end
          if m.type == 'ready' then
            editor.ready = true
            local url = '_/' .. tostring (spec.owner) .. '/' .. spec.wam.path
            editor.view:widget ('post', {
              type = 'open',
              url = url,
              values = module_values (device_id),
            })
          elseif m.type == 'values' and type (m.values) == 'table' then
            from_editor (device_id, m.values)
          end
        end,
      })
      editors[device_id] = editor
      windows.add ({
        id = win_id,
        title = title,
        icon = spec.icon or 'sliders-horizontal',
        category = 'DAW',
        content = editor.view,
        open = true,
        x = 0.25,
        y = 0.12,
        w = 520,
        h = 360,
        min_w = 280,
      })
      windows.show (win_id)
    end

    app.on ('daw:changed', function (_, change)
      local c = change --[[@as Daw.Change]]
      local editor = c.device and editors[c.device]
      if editor and editor.ready and c.kind == 'param' and c.key then
        editor.view:widget ('post', {
          type = 'set',
          values = { [c.key] = module_value (c.device, c.key, c.value) },
        })
      end
      if c.kind == 'param' and c.device and c.key then
        post ({
          type = 'param',
          device = c.device,
          key = c.key,
          value = module_value (c.device, c.key, c.value),
        })
      elseif c.kind == 'mix' and c.track and c.key then
        post ({ type = 'mix', track = c.track, key = c.key, value = c.value })
      else
        push_soon ()
      end
      post ({ type = 'live', track = live_track () or '' })
    end)
    app.on ('daw:devices', function ()
      -- A pack registers its devices while it starts, and the app mounts only running plugins,
      -- so the page starts again once the pack is up.
      app.timer.after (0, remount)
      push_soon ()
    end)
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
      pick_audio = function (multiple, cb)
        app.grants.open ({
          title = multiple and 'Choose Audio Files' or 'Choose an Audio File',
          filters = AUDIO,
          multiple = multiple,
        }, function (picked)
          local out = {} ---@type { id: string, name: string }[]
          for _, g in ipairs (picked or {}) do
            local info = files[g.id]
            if info and info.failed then
              -- Picked again after it failed, so the page tries once more.
              info.failed = nil
              post ({ type = 'retry', file = g.id })
            elseif not (info and info.seconds) then
              -- Decoded now, since a new clip's length comes from the file.
              files[g.id] = info or { name = g.name }
              send_file (g.id)
            end
            files[g.id] = info or files[g.id] or { name = g.name }
            out[#out + 1] = { id = g.id, name = g.name }
          end
          cb (out)
        end)
      end,
      file = file_info,
      open_editor = open_editor,
      export_wav = function ()
        local song = session.song ()
        app.grants.save ({
          title = 'Export as WAV',
          name = (song.name ~= '' and song.name or 'Song') .. '.wav',
          filters = { { name = 'WAV audio', extensions = { 'wav' } } },
        }, function (g)
          if not g or not (view or native) then
            return
          end
          -- The web engine's page writes the file itself. The native engine gets the grant,
          -- which the app turns into the path.
          if not native and view then
            view:widget ('allow_save', g.id)
          end
          exporting[g.id] = g.name
          post ({ type = 'render', file = g.id, from = 0, to = 0 })
          if notify then
            notify.info ('Exporting ' .. g.name .. '...')
          end
        end)
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
      id = 'daw.export_wav',
      category = 'DAW',
      title = 'Export as WAV',
      icon = 'file-down',
      shared = true,
      menu = 'File',
      group = '4',
      run = service.export_wav,
    })
    commands.register ({
      id = 'daw.reload_engine',
      category = 'DAW',
      title = 'Restart the Sound Engine',
      icon = 'rotate-cw',
      run = function ()
        if wants_native () then
          local was = native
          native = nil
          if was then
            was.close ()
          end
          start_native ()
        elseif view then
          view:widget ('reload')
        end
      end,
    })
  end,
}
