-- daw.arrange: the arrangement, in the Playlist window (F5), or in the middle of the window
-- without daw.windows. Each track is a row: its header
-- on the left, and its clips along a timeline of bars. The ruler on top moves the playhead,
-- and a drag along it sets the loop.
--
-- The rows are drawn as one HTML string on each change, and one listener on the whole view
-- reads the `data-item` of whatever was pressed, as the plugin guide suggests for long lists.
-- A drag moves a light outline, and the song changes once, when the button comes up.

local HEAD_W = 200
local ROW_H = 58
local RULER_H = 26
local MIN_PPB = 6
local MAX_PPB = 200

-- lang=css
local CSS = [[
.daw-arr {
  flex: 1;
  height: 100%;
  min-height: 0;
  min-width: 0;
  display: flex;
  flex-direction: column;
  background: var(--bg);
  color: var(--fg);
  font-size: 12px;
  user-select: none;
}
.daw-arr-bar {
  flex: none;
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 5px 8px;
  border-bottom: 1px solid var(--border);
  background: var(--bg-alt);
}
.daw-arr-bar .ui-button {
  padding: 3px 9px;
  font-size: 12px;
}
.daw-arr-bar select {
  padding: 2px 4px;
}
.daw-arr-grow {
  flex: 1;
}
.daw-scroll {
  flex: 1;
  min-height: 0;
  overflow: auto;
  position: relative;
}
.daw-wrap {
  position: relative;
  min-height: 100%;
}
.daw-grid {
  display: grid;
  grid-template-columns: var(--head-w) auto;
  grid-template-rows: var(--ruler-h);
  grid-auto-rows: var(--row-h);
}
.daw-corner {
  position: sticky;
  top: 0;
  left: 0;
  z-index: 4;
  height: var(--ruler-h);
  display: flex;
  align-items: center;
  padding: 0 10px;
  background: var(--bg-alt);
  border-bottom: 1px solid var(--border);
  border-right: 1px solid var(--border);
  color: var(--fg-muted);
}
.daw-ruler {
  position: sticky;
  top: 0;
  z-index: 3;
  height: var(--ruler-h);
  background: var(--bg-alt);
  border-bottom: 1px solid var(--border);
  cursor: pointer;
}
.daw-bar-no {
  position: absolute;
  top: 0;
  bottom: 0;
  padding: 5px 4px 0;
  border-left: 1px solid var(--border);
  color: var(--fg-muted);
  font-family: var(--font-mono);
  font-size: 10px;
  pointer-events: none;
}
.daw-loop {
  position: absolute;
  top: 14px;
  height: 10px;
  border-radius: 3px;
  background: color-mix(in srgb, var(--fg-muted) 35%, transparent);
  cursor: grab;
}
.daw-loop.on {
  background: color-mix(in srgb, var(--accent) 70%, transparent);
}
.daw-loop-edge {
  position: absolute;
  top: 0;
  bottom: 0;
  width: 7px;
  cursor: ew-resize;
}
.daw-head {
  position: sticky;
  left: 0;
  z-index: 2;
  display: flex;
  align-items: stretch;
  gap: 8px;
  padding-right: 6px;
  background: var(--bg-alt);
  border-right: 1px solid var(--border);
  border-bottom: 1px solid var(--border);
  cursor: pointer;
}
.daw-head.sel {
  background: var(--bg-active);
}
.daw-head-color {
  flex: none;
  width: 5px;
  background: var(--c);
}
.daw-head-main {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  justify-content: center;
  gap: 2px;
}
.daw-head-name {
  font-weight: 600;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.daw-head-dev {
  color: var(--fg-muted);
  font-size: 11px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.daw-head-dev.missing {
  color: var(--danger);
}
.daw-head-btns {
  flex: none;
  display: flex;
  align-items: center;
  gap: 3px;
}
.daw-hb {
  width: 22px;
  height: 20px;
  padding: 0;
  border: 1px solid var(--border);
  border-radius: 4px;
  background: var(--bg-elev);
  color: var(--fg-muted);
  font: 700 10px var(--font-ui);
  cursor: pointer;
}
.daw-hb.on.m {
  background: var(--warning);
  color: #000;
}
.daw-hb.on.s {
  background: var(--accent);
  color: var(--accent-fg);
}
.daw-hb.on.r {
  background: var(--danger);
  color: #fff;
}
.daw-lane {
  position: relative;
  border-bottom: 1px solid var(--border);
  background-image: linear-gradient(to right, var(--border) 1px, transparent 1px),
    linear-gradient(to right, color-mix(in srgb, var(--border) 45%, transparent) 1px, transparent 1px);
  background-size: var(--bar-w) 100%, var(--beat-w) 100%;
}
.daw-lane.sel {
  background-color: color-mix(in srgb, var(--accent) 5%, transparent);
}
.daw-clip {
  position: absolute;
  top: 3px;
  bottom: 3px;
  overflow: hidden;
  border-radius: 4px;
  border: 1px solid color-mix(in srgb, var(--c) 80%, #000);
  background: color-mix(in srgb, var(--c) 30%, var(--bg-alt));
  cursor: grab;
}
.daw-clip.sel {
  border-color: var(--fg);
  box-shadow: 0 0 0 1px var(--fg);
}
.daw-clip-name {
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  padding: 1px 5px;
  background: color-mix(in srgb, var(--c) 70%, var(--bg-alt));
  color: var(--fg);
  font-size: 10px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  pointer-events: none;
}
.daw-clip svg {
  position: absolute;
  left: 0;
  top: 16px;
  width: 100%;
  height: calc(100% - 18px);
  pointer-events: none;
}
.daw-clip svg rect {
  fill: var(--c);
}
.daw-clip svg polyline {
  fill: none;
  stroke: var(--c);
  stroke-width: 1;
  vector-effect: non-scaling-stroke;
}
.daw-edge {
  position: absolute;
  top: 0;
  bottom: 0;
  right: 0;
  width: 7px;
  cursor: ew-resize;
}
.daw-playhead {
  position: absolute;
  top: 0;
  bottom: 0;
  width: 1px;
  background: var(--danger);
  pointer-events: none;
  z-index: 3;
}
.daw-ghost {
  position: absolute;
  border: 1px dashed var(--fg);
  border-radius: 4px;
  background: color-mix(in srgb, var(--fg) 12%, transparent);
  pointer-events: none;
  z-index: 5;
  display: none;
}
.daw-empty-row {
  grid-column: 1 / -1;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  color: var(--fg-muted);
}
]]

---@param n number
---@return string
local function px (n)
  return string.format ('%.1fpx', n)
end

---@type Proteus.Plugin
return {
  name = 'DAW arrangement',
  description = 'Tracks and clips along a timeline, with the ruler and the loop.',
  version = '1.1.0',
  requires = { proteus = '>=0.2.0', features = { 'permissions' } },
  permissions = {},
  depends = {
    'lib.ui',
    'ui.shell',
    'daw.core',
    'daw.devices',
    'daw.session',
    'daw.engine',
    'core.commands',
  },
  optional = {
    'ui.menus',
    'ui.palette',
    'ui.views',
    'ui.notify',
    'ui.tabs',
    'core.keys',
    'daw.windows',
  },
  activate = function (app)
    local ui = app.use ('ui')
    local shell = app.use ('shell')
    local daw = app.use ('daw') --[[@as Daw.Core]]
    local devices = app.use ('daw.devices') --[[@as Daw.Devices]]
    local session = app.use ('daw.session') --[[@as Daw.Session]]
    local engine = app.use ('daw.engine') --[[@as Daw.Engine]]
    local commands = app.use ('commands')
    local menus = app.try_use ('menus')
    local picker = app.try_use ('picker')
    local views = app.try_use ('views')
    local windows = app.try_use ('daw.windows') --[[@as Daw.Windows?]]

    ---Opens the piano roll, in its window or its dock.
    local function show_pianoroll ()
      if windows then
        windows.show ('daw.pianoroll')
      elseif views then
        views.show ('daw.pianoroll')
      end
    end
    local notify = app.try_use ('notify')
    local esc = app.util.escape
    ui.css (CSS)

    local ppb = tonumber (app.store.get ('zoom', 28)) or 28
    local grid = tostring (app.store.get ('grid', '1/4'))
    local focused = true

    ---@return boolean
    local function free ()
      return focused and not app.dom.focus_info ().editable
    end

    ---@param song Daw.Song
    ---@return number
    local function total_beats (song)
      local bar = daw.song.beats_per_bar (song)
      local finish = math.max (daw.song.song_end (song), song.loop.finish)
      return (math.ceil (finish / bar) + 16) * bar
    end

    -- Elements ---------------------------------------------------------------------------------

    local grid_select = ui.h ('select', {
      class = 'ui-input',
      title = 'Snap clips to',
      onchange = function (ev)
        grid = ev.value or '1/4'
        app.store.set ('grid', grid)
      end,
    })
    for _, g in ipairs ({ '1/1', '1/2', '1/4', '1/8', '1/16', 'off' }) do
      grid_select:append (ui.option ({
        text = g == 'off' and 'No snap' or ('Snap ' .. g),
        value = g,
      }))
    end
    grid_select:value (grid)

    local content = ui.div ({ class = 'daw-grid' })
    local playhead = ui.div ({ class = 'daw-playhead' })
    local ghost = ui.div ({ class = 'daw-ghost' })
    local wrap = ui.div ({ class = 'daw-wrap', content, playhead, ghost })
    local scroll = ui.div ({ class = 'daw-scroll', wrap })
    local root = ui.div ({
      class = 'daw-arr',
      ui.div ({
        class = 'daw-arr-bar',
        ui.button ({
          'Instrument track',
          icon = 'plus',
          variant = 'ghost',
          title = 'Add a track that plays notes (Ctrl+T)',
          onclick = function ()
            commands.run ('daw.add_track')
          end,
        }),
        ui.button ({
          'Audio track',
          icon = 'audio-lines',
          variant = 'ghost',
          title = 'Add a track that plays audio files',
          onclick = function ()
            commands.run ('daw.add_audio_track')
          end,
        }),
        ui.button ({
          'Import audio',
          icon = 'file-audio',
          variant = 'ghost',
          title = 'Put audio files on the timeline at the playhead',
          onclick = function ()
            commands.run ('daw.import_audio')
          end,
        }),
        ui.div ({ class = 'daw-arr-grow' }),
        grid_select,
        ui.button ({
          icon = 'zoom-out',
          variant = 'ghost',
          title = 'Zoom out (Ctrl+-)',
          onclick = function ()
            commands.run ('daw.zoom_out')
          end,
        }),
        ui.button ({
          icon = 'zoom-in',
          variant = 'ghost',
          title = 'Zoom in (Ctrl+=)',
          onclick = function ()
            commands.run ('daw.zoom_in')
          end,
        }),
      }),
      scroll,
    })

    -- Drawing ----------------------------------------------------------------------------------

    ---@param clip Daw.Clip
    ---@return string
    local function midi_preview (clip)
      local list = clip.notes or {}
      if #list == 0 then
        return ''
      end
      local lo, hi = daw.notes.range (list)
      lo, hi = (lo or 60) - 1, (hi or 60) + 1
      local parts = {
        string.format (
          '<svg viewBox="0 0 %.4f %d" preserveAspectRatio="none">',
          clip.length,
          hi - lo + 1
        ),
      }
      for _, n in ipairs (list) do
        if n.start < clip.length then
          parts[#parts + 1] = string.format (
            '<rect x="%.4f" y="%d" width="%.4f" height="1"/>',
            n.start,
            hi - n.pitch,
            math.max (0.05, math.min (n.length, clip.length - n.start))
          )
        end
      end
      parts[#parts + 1] = '</svg>'
      return table.concat (parts)
    end

    ---A waveform of the stretch of the file an audio clip plays, from the peaks the engine
    ---sent when the file decoded.
    ---@param clip Daw.Clip
    ---@param tempo number
    ---@return string
    local function audio_preview (clip, tempo)
      local info = engine.file (clip.file or '')
      local p = info and info.peaks
      if not info or not p or #p == 0 or not info.seconds then
        return ''
      end
      local per = #p / math.max (0.001, info.seconds)
      local from = (clip.offset or 0) * per
      local count = clip.length * 60 / tempo * per
      local pts = {} ---@type string[]
      local steps = math.min (300, math.max (2, math.floor (count)))
      for i = 0, steps do
        local v = p[math.floor (from + count * i / steps) + 1] or 0
        pts[#pts + 1] = string.format ('%d,%.3f', i, 1 - v)
        pts[#pts + 1] = string.format ('%d,%.3f', i, 1 + v)
      end
      return string.format (
        '<svg viewBox="0 0 %d 2" preserveAspectRatio="none"><polyline points="%s"/></svg>',
        steps,
        table.concat (pts, ' ')
      )
    end

    ---What a clip's tooltip says: its name, and for an audio clip whose file is not here,
    ---why it is silent.
    ---@param t Daw.Track
    ---@param c Daw.Clip
    ---@return string
    local function clip_title (t, c)
      if t.kind ~= 'audio' then
        return c.name
      end
      local info = engine.file (c.file or '')
      if not info then
        return c.name .. ' (the file is not on this computer: import it again)'
      end
      if info.failed then
        return c.name .. ' (' .. info.failed .. ')'
      end
      return c.name .. ' · ' .. info.name
    end

    local function render ()
      local song = session.song ()
      local bar = daw.song.beats_per_bar (song)
      local beats = total_beats (song)
      local width = beats * ppb
      local sel_track = session.selected_track ()
      local sel = {} ---@type table<string, boolean>
      for _, id in ipairs (session.selected_clips ()) do
        sel[id] = true
      end
      content:style ('--head-w', px (HEAD_W))
      content:style ('--row-h', px (ROW_H))
      content:style ('--ruler-h', px (RULER_H))
      content:style ('--bar-w', px (bar * ppb))
      content:style ('--beat-w', px (ppb))
      content:style ('width', px (HEAD_W + width))

      local out = {} ---@type string[]
      out[#out + 1] = '<div class="daw-corner">'
        .. #song.tracks
        .. (#song.tracks == 1 and ' track' or ' tracks')
        .. '</div>'
      out[#out + 1] = '<div class="daw-ruler" data-item="ruler" style="width:'
        .. px (width)
        .. '">'
      local every = ppb * bar < 40 and 4 or 1
      for b = 0, math.floor (beats / bar) - 1, every do
        out[#out + 1] = '<div class="daw-bar-no" style="left:'
          .. px (b * bar * ppb)
          .. '">'
          .. (b + 1)
          .. '</div>'
      end
      local loop = song.loop
      out[#out + 1] = string.format (
        '<div class="daw-loop%s" data-item="loop" style="left:%s;width:%s" title="Drag to move the loop. Click to turn it on or off.">'
          .. '<div class="daw-loop-edge" data-item="loopstart" style="left:0"></div>'
          .. '<div class="daw-loop-edge" data-item="loopend" style="right:0"></div></div>',
        loop.on and ' on' or '',
        px (loop.start * ppb),
        px ((loop.finish - loop.start) * ppb)
      )
      out[#out + 1] = '</div>'

      for _, t in ipairs (song.tracks) do
        local dev_name, missing = 'Audio', false
        if t.kind == 'instrument' then
          local spec = t.instrument and devices.get (t.instrument.device)
          if t.instrument and not spec then
            dev_name, missing = t.instrument.device .. ' (missing)', true
          elseif spec then
            dev_name = spec.name
              .. (
                (t.instrument and t.instrument.preset)
                  and (' · ' .. t.instrument.preset)
                or ''
              )
          else
            dev_name = 'No instrument'
          end
        end
        local is_sel = t.id == sel_track
        out[#out + 1] = string.format (
          '<div class="daw-head%s" data-item="head:%s" style="--c:%s">'
            .. '<div class="daw-head-color"></div>'
            .. '<div class="daw-head-main"><div class="daw-head-name">%s</div>'
            .. '<div class="daw-head-dev%s">%s</div></div>'
            .. '<div class="daw-head-btns">'
            .. '<button class="daw-hb m%s" data-item="mute:%s" title="Mute">M</button>'
            .. '<button class="daw-hb s%s" data-item="solo:%s" title="Solo">S</button>'
            .. '%s</div></div>',
          is_sel and ' sel' or '',
          t.id,
          esc (t.color),
          esc (t.name),
          missing and ' missing' or '',
          esc (dev_name),
          t.mute and ' on' or '',
          t.id,
          t.solo and ' on' or '',
          t.id,
          t.kind == 'instrument'
              and string.format (
                '<button class="daw-hb r%s" data-item="arm:%s" title="Record into this track">●</button>',
                t.arm and ' on' or '',
                t.id
              )
            or ''
        )
        local clips = {} ---@type string[]
        for _, c in ipairs (t.clips) do
          clips[#clips + 1] = string.format (
            '<div class="daw-clip%s" data-item="clip:%s" style="left:%s;width:%s;--c:%s" title="%s">'
              .. '<div class="daw-clip-name">%s</div>%s'
              .. '<div class="daw-edge" data-item="edge:%s"></div></div>',
            sel[c.id] and ' sel' or '',
            c.id,
            px (c.start * ppb),
            px (math.max (3, c.length * ppb - 1)),
            esc (c.color or t.color),
            esc (clip_title (t, c)),
            esc (c.name),
            t.kind == 'audio' and audio_preview (c, song.tempo)
              or midi_preview (c),
            c.id
          )
        end
        out[#out + 1] = string.format (
          '<div class="daw-lane%s" data-item="lane:%s" style="width:%s">%s</div>',
          is_sel and ' sel' or '',
          t.id,
          px (width),
          table.concat (clips)
        )
      end
      if #song.tracks == 0 then
        out[#out + 1] =
          '<div class="daw-empty-row">No tracks yet. Add an instrument or audio track to start.</div>'
      end
      content:html (table.concat (out))
      playhead:style ('left', px (HEAD_W + engine.position () * ppb))
    end

    ---@param beat number
    local function move_playhead (beat)
      local x = HEAD_W + beat * ppb
      playhead:style ('left', px (x))
      if engine.playing () then
        local left = tonumber (scroll:get ('scrollLeft')) or 0
        local w = tonumber (scroll:get ('clientWidth')) or 0
        if x > left + w - 40 or x < left + HEAD_W then
          scroll:set ('scrollLeft', math.max (0, x - HEAD_W - 40))
        end
      end
    end

    -- Pointer helpers --------------------------------------------------------------------------

    ---@param x number A pointer position in the window.
    ---@return number beat
    local function beat_at (x)
      local r = wrap:rect ()
      return math.max (0, (x - r.left - HEAD_W) / ppb)
    end

    ---@param y number
    ---@return integer row From 1, clamped to the tracks.
    local function row_at (y)
      local r = wrap:rect ()
      local n = #session.song ().tracks
      local row = math.floor ((y - r.top - RULER_H) / ROW_H) + 1
      return math.max (1, math.min (n, row))
    end

    ---@param beat number
    ---@return number
    local function snap (beat)
      return daw.time.snap (beat, grid)
    end

    ---@param left number beats
    ---@param row integer
    ---@param length number beats
    ---@param rows? integer
    local function show_ghost (left, row, length, rows)
      ghost:style ('display', 'block')
      ghost:style ('left', px (HEAD_W + left * ppb))
      ghost:style ('top', px (RULER_H + (row - 1) * ROW_H + 3))
      ghost:style ('width', px (math.max (3, length * ppb)))
      ghost:style ('height', px ((rows or 1) * ROW_H - 6))
    end

    local function hide_ghost ()
      ghost:style ('display', 'none')
    end

    ---@param on_move fun(ev: Proteus.DomEvent)
    ---@param on_up fun(ev: Proteus.DomEvent)
    local function follow (on_move, on_up)
      local off_move, off_up ---@type fun(), fun()
      off_move = app.dom.on_global ('mousemove', function (mv)
        on_move (mv)
        return nil
      end)
      off_up = app.dom.on_global ('mouseup', function (up)
        off_move ()
        off_up ()
        on_up (up)
        return nil
      end)
    end

    ---@param song Daw.Song
    ---@param id string
    ---@return integer
    local function row_of (song, id)
      local _, index = daw.song.track (song, id)
      return index or 1
    end

    -- Clips ------------------------------------------------------------------------------------

    ---@param ev Proteus.DomEvent
    ---@param id string
    ---@param resize boolean
    local function press_clip (ev, id, resize)
      local song = session.song ()
      local clip, owner = daw.song.clip (song, id)
      if not clip or not owner then
        return
      end
      local picked = session.selected_clips ()
      local in_sel = false
      for _, other in ipairs (picked) do
        in_sel = in_sel or other == id
      end
      if ev.ctrl or ev.shift then
        local next_sel = {} ---@type string[]
        for _, other in ipairs (picked) do
          if other ~= id then
            next_sel[#next_sel + 1] = other
          end
        end
        if not in_sel then
          next_sel[#next_sel + 1] = id
        end
        session.select_clips (next_sel)
        return
      end
      if not in_sel then
        picked = { id }
        session.select_clips (picked)
      end
      local x0, y0 = ev.x or 0, ev.y or 0
      local row0 = row_of (song, owner.id)
      local moved = false
      local d_beats, d_rows, new_len = 0, 0, clip.length
      follow (function (mv)
        local dx, dy = (mv.x or 0) - x0, (mv.y or 0) - y0
        if not moved and dx * dx + dy * dy < 16 then
          return
        end
        moved = true
        if resize then
          local finish = snap (clip.start + clip.length + dx / ppb)
          new_len = math.max (
            daw.time.grid_beats (grid) > 0 and daw.time.grid_beats (grid)
              or 0.25,
            finish - clip.start
          )
          show_ghost (clip.start, row0, new_len)
        else
          local start = mv.alt and (clip.start + dx / ppb)
            or snap (clip.start + dx / ppb)
          d_beats = math.max (-clip.start, start - clip.start)
          d_rows = row_at (mv.y or 0) - row0
          show_ghost (clip.start + d_beats, row0 + d_rows, clip.length)
        end
      end, function ()
        hide_ghost ()
        if not moved then
          return
        end
        local s = session.song ()
        if resize then
          s = daw.song.update_clip (s, id, { length = new_len })
          session.apply (s, { kind = 'edit', label = 'Resize clip' })
          return
        end
        for _, cid in ipairs (picked) do
          local c, t = daw.song.clip (s, cid)
          if c and t then
            local target = s.tracks[row_of (s, t.id) + d_rows]
            if not target or target.kind ~= t.kind then
              target = t
            end
            s = daw.song.move_clip (s, cid, target.id, c.start + d_beats)
          end
        end
        session.apply (s, { kind = 'edit', label = 'Move clips' })
      end)
    end

    ---@param track_id string
    ---@param beat number
    local function new_clip (track_id, beat)
      local song = session.song ()
      local t = daw.song.track (song, track_id)
      if not t or t.kind ~= 'instrument' then
        return
      end
      local bar = daw.song.beats_per_bar (song)
      local start = math.floor (beat / bar) * bar
      local s, id =
        daw.song.add_clip (song, track_id, { start = start, length = bar })
      session.apply (s, { kind = 'edit', label = 'New clip' })
      session.select_clips ({ id })
      session.edit_clip (id)
      show_pianoroll ()
    end

    -- The ruler and the loop -------------------------------------------------------------------

    ---@param ev Proteus.DomEvent
    ---@param part string
    local function press_ruler (ev, part)
      local song = session.song ()
      local loop = song.loop
      local b0 = beat_at (ev.x or 0)
      local moved = false
      local range = { start = loop.start, finish = loop.finish }
      follow (function (mv)
        local b = beat_at (mv.x or 0)
        if not moved and math.abs (b - b0) * ppb < 4 then
          return
        end
        moved = true
        local step = daw.time.grid_beats (grid) > 0 and grid or '1/4'
        if part == 'loopstart' then
          range.start = math.min (daw.time.snap (b, step), loop.finish - 0.25)
        elseif part == 'loopend' then
          range.finish = math.max (daw.time.snap (b, step), loop.start + 0.25)
        elseif part == 'loop' then
          local d = daw.time.snap (b - b0, step)
          d = math.max (-loop.start, d)
          range.start, range.finish = loop.start + d, loop.finish + d
        else
          local a, z = daw.time.snap (b0, step), daw.time.snap (b, step)
          range.start, range.finish = math.min (a, z), math.max (a, z)
        end
        ghost:style ('display', 'block')
        ghost:style ('left', px (HEAD_W + range.start * ppb))
        ghost:style ('top', '14px')
        ghost:style ('width', px ((range.finish - range.start) * ppb))
        ghost:style ('height', '10px')
      end, function ()
        hide_ghost ()
        if not moved then
          if part == 'loop' then
            commands.run ('daw.loop')
          else
            engine.seek (math.max (0, daw.time.snap (b0, grid)))
          end
          return
        end
        if range.finish - range.start < 0.25 then
          return
        end
        session.apply (
          daw.song.set_loop (session.song (), {
            on = true,
            start = range.start,
            finish = range.finish,
          }),
          { kind = 'edit', label = 'Set loop' }
        )
      end)
    end

    -- Tracks -----------------------------------------------------------------------------------

    ---@param id string
    ---@param key 'mute'|'solo'|'arm'
    local function toggle (id, key)
      local song = session.song ()
      local t = daw.song.track (song, id)
      if not t then
        return
      end
      local value = not t[key]
      local s = daw.song.update_track (song, id, { [key] = value })
      if key == 'arm' and value then
        -- One armed track at a time: recording goes to it.
        for _, other in ipairs (s.tracks) do
          if other.id ~= id and other.arm then
            s = daw.song.update_track (s, other.id, { arm = false })
          end
        end
        session.apply (s, { kind = 'edit', label = 'Arm' })
        return
      end
      if key == 'arm' then
        session.apply (s, { kind = 'edit', label = 'Arm' })
        return
      end
      session.apply (
        s,
        { kind = 'mix', track = id, key = key, value = value },
        'mix:' .. id .. key
      )
      session.seal ()
    end

    ---@param id string
    local function rename_track (id)
      local t = daw.song.track (session.song (), id)
      if not t or not picker then
        return
      end
      picker.input ({
        prompt = 'Track name',
        value = t.name,
        on_submit = function (text)
          if text ~= '' then
            session.apply (
              daw.song.update_track (session.song (), id, { name = text }),
              { kind = 'edit', label = 'Rename track' }
            )
          end
        end,
      })
    end

    ---@param id string
    local function recolor_track (id)
      if not picker then
        return
      end
      local items = {} ---@type Proteus.PickItem[]
      for i, c in ipairs (daw.song.COLORS) do
        items[#items + 1] =
          { label = 'Colour ' .. i, detail = c, icon = 'palette', value = c }
      end
      picker.pick ({
        placeholder = 'Pick a colour',
        items = items,
        on_pick = function (it)
          session.apply (
            daw.song.update_track (session.song (), id, { color = it.value }),
            { kind = 'edit', label = 'Colour' }
          )
        end,
      })
    end

    ---Asks for an instrument and one of its presets.
    ---@param done fun(ref: Daw.DeviceRef, spec: Daw.DeviceSpec)
    local function choose_instrument (done)
      local list = devices.list ('instrument')
      if not picker then
        if list[1] then
          done (daw.device.ref (list[1]), list[1])
        end
        return
      end
      local items = {} ---@type Proteus.PickItem[]
      for _, spec in ipairs (list) do
        items[#items + 1] = {
          label = spec.name,
          detail = spec.category,
          icon = spec.icon or 'music',
          value = { spec = spec },
        }
        for _, p in ipairs (spec.presets or {}) do
          items[#items + 1] = {
            label = spec.name .. ': ' .. p.name,
            detail = spec.category,
            icon = spec.icon or 'music',
            value = { spec = spec, preset = p.name },
          }
        end
      end
      picker.pick ({
        placeholder = 'Pick an instrument',
        items = items,
        on_pick = function (it)
          local v = it.value --[[@as { spec: Daw.DeviceSpec, preset?: string }]]
          done (daw.device.ref (v.spec, v.preset), v.spec)
        end,
      })
    end

    local function add_track ()
      choose_instrument (function (ref, spec)
        local song = session.song ()
        local _, index = daw.song.track (song, session.selected_track () or '')
        local s, id = daw.song.add_track (song, {
          name = ref.preset or spec.name,
          instrument = ref,
        }, index and index + 1 or nil)
        session.apply (s, { kind = 'edit', label = 'Add track' })
        session.select_track (id)
      end)
    end

    ---Adds an audio track after the selected one and selects it.
    ---@param name? string
    ---@return string id
    local function add_audio_track (name)
      local song = session.song ()
      local _, index = daw.song.track (song, session.selected_track () or '')
      local s, id = daw.song.add_track (
        song,
        { kind = 'audio', name = name },
        index and index + 1 or nil
      )
      session.apply (s, { kind = 'edit', label = 'Add track' })
      session.select_track (id)
      return id
    end

    -- Imports waiting for their file to decode, since a clip's length comes from the file's.
    local waiting = {} ---@type table<string, { track: string, start: number, name: string }>

    ---@param track_id string
    ---@param start number
    ---@param file { id: string, name: string }
    local function place_clip (track_id, start, file)
      local info = engine.file (file.id)
      local seconds = info and info.seconds
      if not seconds then
        waiting[file.id] = { track = track_id, start = start, name = file.name }
        return
      end
      local song = session.song ()
      local s, id = daw.song.add_clip (song, track_id, {
        name = file.name:match ('^(.+)%.%w+$') or file.name,
        start = start,
        length = math.max (0.25, seconds * song.tempo / 60),
        file = file.id,
        offset = 0,
        gain = 0,
      })
      session.apply (s, { kind = 'edit', label = 'Import audio' })
      session.select_clips ({ id })
    end

    ---Asks for audio files and puts them on the timeline at `beat`: on the selected audio
    ---track when there is one file and one is selected, or else each on a new track.
    ---@param beat number
    ---@param track_id? string
    local function import_audio (beat, track_id)
      engine.pick_audio (true, function (picked)
        local target = track_id or session.selected_track ()
        local t = daw.song.track (session.song (), target or '')
        for i, file in ipairs (picked) do
          local into = (i == 1 and t and t.kind == 'audio') and t.id
            or add_audio_track (file.name:match ('^(.+)%.%w+$') or file.name)
          place_clip (into, beat, file)
        end
      end)
    end

    app.on ('daw:file', function (id)
      local file = tostring (id)
      local wait = waiting[file]
      if wait then
        waiting[file] = nil
        local info = engine.file (file)
        if info and info.seconds then
          place_clip (wait.track, wait.start, { id = file, name = wait.name })
          return
        end
      end
      render ()
    end)

    ---@param id string
    local function delete_track (id)
      local t = daw.song.track (session.song (), id)
      if not t then
        return
      end
      local function go ()
        session.apply (
          daw.song.remove_track (session.song (), id),
          { kind = 'edit', label = 'Delete track' }
        )
      end
      if #t.clips > 0 and picker then
        picker.confirm ({
          message = 'Delete ' .. t.name .. ' and its clips?',
          yes = 'Delete',
          on_yes = go,
        })
      else
        go ()
      end
    end

    ---@param id string
    local function duplicate_track (id)
      local song = session.song ()
      local t, index = daw.song.track (song, id)
      if not t or not index then
        return
      end
      local copy = daw.song.copy (t) --[[@as table<string, any>]]
      copy.name = t.name .. ' copy'
      if copy.instrument then
        copy.instrument.id = ''
      end
      for _, e in
        ipairs (copy.effects --[[@as Daw.DeviceRef[] ]])
      do
        e.id = ''
      end
      local s, new_id = daw.song.add_track (song, copy, index + 1)
      session.apply (s, { kind = 'edit', label = 'Duplicate track' })
      session.select_track (new_id)
    end

    -- Selection commands -----------------------------------------------------------------------

    local function delete_clips ()
      local picked = session.selected_clips ()
      if #picked == 0 then
        return
      end
      session.apply (
        daw.song.remove_clips (session.song (), picked),
        { kind = 'edit', label = 'Delete clips' }
      )
      session.select_clips ({})
    end

    local function duplicate_clips ()
      local picked = session.selected_clips ()
      if #picked == 0 then
        return
      end
      local s, ids = daw.song.duplicate_clips (session.song (), picked)
      session.apply (s, { kind = 'edit', label = 'Duplicate clips' })
      session.select_clips (ids)
    end

    local function split ()
      local beat = engine.position ()
      local song = session.song ()
      local picked = session.selected_clips ()
      if #picked == 0 then
        local track = daw.song.track (song, session.selected_track () or '')
        for _, c in ipairs (track and track.clips or {}) do
          if c.start < beat and beat < c.start + c.length then
            picked = { c.id }
          end
        end
      end
      local s = song
      for _, id in ipairs (picked) do
        s = daw.song.split_clip (s, id, beat)
      end
      if s ~= song then
        session.apply (s, { kind = 'edit', label = 'Split' })
      elseif notify then
        notify.info ('Put the playhead inside a clip to split it.')
      end
    end

    local function select_all ()
      local ids = {} ---@type string[]
      for _, t in ipairs (session.song ().tracks) do
        for _, c in ipairs (t.clips) do
          ids[#ids + 1] = c.id
        end
      end
      session.select_clips (ids)
    end

    ---@param factor number
    local function zoom (factor)
      local centre = beat_at ((scroll:rect ().left + scroll:rect ().right) / 2)
      ppb = math.max (MIN_PPB, math.min (MAX_PPB, ppb * factor))
      app.store.set ('zoom', ppb)
      render ()
      local w = tonumber (scroll:get ('clientWidth')) or 0
      scroll:set ('scrollLeft', math.max (0, centre * ppb - (w - HEAD_W) / 2))
    end

    ---@param id string
    local function rename_clip (id)
      local c = daw.song.clip (session.song (), id)
      if not c or not picker then
        return
      end
      picker.input ({
        prompt = 'Clip name',
        value = c.name,
        on_submit = function (text)
          if text ~= '' then
            session.apply (
              daw.song.update_clip (session.song (), id, { name = text }),
              { kind = 'edit', label = 'Rename clip' }
            )
          end
        end,
      })
    end

    ---@param id string
    local function open_clip (id)
      local c, t = daw.song.clip (session.song (), id)
      if not c or not t or t.kind ~= 'instrument' then
        return
      end
      session.select_clips ({ id })
      session.edit_clip (id)
      show_pianoroll ()
    end

    -- Input ------------------------------------------------------------------------------------

    ---@param item string?
    ---@return string kind
    ---@return string id
    local function split_item (item)
      local kind, id = (item or ''):match ('^(%w+):(.+)$')
      return kind or (item or ''), id or ''
    end

    root:on ('mousedown', function ()
      if not focused then
        app.emit ('daw:focus', 'arrange')
      end
      return nil
    end, { capture = true })
    app.on ('daw:focus', function (who)
      focused = who == 'arrange'
    end)

    content:on ('mousedown', function (ev)
      if ev.button ~= 0 then
        return nil
      end
      local kind, id = split_item (ev.item)
      if kind == 'mute' or kind == 'solo' or kind == 'arm' then
        toggle (id, kind --[[@as 'mute'|'solo'|'arm']])
        return 'stop'
      elseif kind == 'head' then
        session.select_track (id)
      elseif kind == 'clip' or kind == 'edge' then
        press_clip (ev, id, kind == 'edge')
        return true
      elseif kind == 'lane' then
        session.select_track (id)
        if #session.selected_clips () > 0 then
          session.select_clips ({})
        end
      elseif
        kind == 'ruler'
        or kind == 'loop'
        or kind == 'loopstart'
        or kind == 'loopend'
      then
        press_ruler (ev, kind)
        return true
      end
      return nil
    end)

    content:on ('dblclick', function (ev)
      local kind, id = split_item (ev.item)
      if kind == 'clip' or kind == 'edge' then
        open_clip (id)
      elseif kind == 'lane' then
        new_clip (id, beat_at (ev.x or 0))
      elseif kind == 'head' then
        rename_track (id)
      end
      return nil
    end)

    scroll:on ('wheel', function (ev)
      if ev.ctrl then
        zoom ((ev.dy or 0) < 0 and 1.15 or 1 / 1.15)
        return true
      end
      return nil
    end)

    if menus then
      menus.attach (content, function (ev)
        local kind, id = split_item (ev.item)
        if kind == 'clip' or kind == 'edge' then
          local c, t = daw.song.clip (session.song (), id)
          if not c or not t then
            return nil
          end
          local in_sel = false
          for _, other in ipairs (session.selected_clips ()) do
            in_sel = in_sel or other == id
          end
          if not in_sel then
            session.select_clips ({ id })
          end
          ---@type Proteus.MenuItem[]
          local items = {}
          if t.kind == 'instrument' then
            items[#items + 1] = {
              label = 'Open in Piano Roll',
              icon = 'piano',
              run = function ()
                open_clip (id)
              end,
            }
          end
          items[#items + 1] = {
            label = 'Rename',
            icon = 'pencil',
            run = function ()
              rename_clip (id)
            end,
          }
          items[#items + 1] = {
            label = 'Duplicate',
            icon = 'copy',
            key = 'Ctrl+D',
            run = duplicate_clips,
          }
          items[#items + 1] = {
            label = 'Split at Playhead',
            icon = 'scissors',
            key = 'Ctrl+E',
            run = split,
          }
          items[#items + 1] = {
            label = 'Loop This Clip',
            icon = 'repeat',
            run = function ()
              session.apply (
                daw.song.set_loop (
                  session.song (),
                  { on = true, start = c.start, finish = c.start + c.length }
                ),
                { kind = 'edit', label = 'Set loop' }
              )
            end,
          }
          items[#items + 1] = { separator = true }
          items[#items + 1] = {
            label = 'Delete',
            icon = 'trash-2',
            key = 'Delete',
            danger = true,
            run = delete_clips,
          }
          return items
        elseif
          kind == 'head'
          or kind == 'mute'
          or kind == 'solo'
          or kind == 'arm'
        then
          session.select_track (id)
          local t = daw.song.track (session.song (), id)
          if not t then
            return nil
          end
          ---@type Proteus.MenuItem[]
          local items = {
            {
              label = 'Rename',
              icon = 'pencil',
              run = function ()
                rename_track (id)
              end,
            },
            {
              label = 'Colour',
              icon = 'palette',
              run = function ()
                recolor_track (id)
              end,
            },
          }
          if t.kind == 'instrument' then
            items[#items + 1] = {
              label = 'Change Instrument',
              icon = 'piano',
              run = function ()
                choose_instrument (function (ref)
                  session.apply (
                    (daw.song.set_instrument (session.song (), id, ref)),
                    { kind = 'edit', label = 'Change instrument' }
                  )
                end)
              end,
            }
          end
          local _, index = daw.song.track (session.song (), id)
          items[#items + 1] = {
            label = 'Move Up',
            icon = 'chevron-up',
            disabled = index == 1,
            run = function ()
              session.apply (
                daw.song.move_track (session.song (), id, (index or 1) - 1),
                { kind = 'edit', label = 'Move track' }
              )
            end,
          }
          items[#items + 1] = {
            label = 'Move Down',
            icon = 'chevron-down',
            disabled = index == #session.song ().tracks,
            run = function ()
              session.apply (
                daw.song.move_track (session.song (), id, (index or 1) + 1),
                { kind = 'edit', label = 'Move track' }
              )
            end,
          }
          items[#items + 1] = {
            label = 'Duplicate Track',
            icon = 'copy',
            run = function ()
              duplicate_track (id)
            end,
          }
          items[#items + 1] = { separator = true }
          items[#items + 1] = {
            label = 'Delete Track',
            icon = 'trash-2',
            danger = true,
            run = function ()
              delete_track (id)
            end,
          }
          return items
        elseif kind == 'lane' then
          session.select_track (id)
          local t = daw.song.track (session.song (), id)
          local beat = beat_at (ev.x or 0)
          if t and t.kind == 'audio' then
            return {
              {
                label = 'Import Audio Here',
                icon = 'file-audio',
                run = function ()
                  import_audio (snap (beat), id)
                end,
              },
              {
                label = 'Move the Playhead Here',
                icon = 'map-pin',
                run = function ()
                  engine.seek (snap (beat))
                end,
              },
            }
          end
          if t and t.kind == 'instrument' then
            return {
              {
                label = 'New Clip Here',
                icon = 'plus',
                run = function ()
                  new_clip (id, beat)
                end,
              },
              {
                label = 'Move the Playhead Here',
                icon = 'map-pin',
                run = function ()
                  engine.seek (snap (beat))
                end,
              },
            }
          end
        end
        return nil
      end)
    end

    -- Commands ---------------------------------------------------------------------------------

    commands.register ({
      id = 'daw.add_audio_track',
      category = 'DAW',
      title = 'Add Audio Track',
      icon = 'audio-lines',
      menu = 'Track',
      run = function ()
        add_audio_track ()
      end,
    })
    commands.register ({
      id = 'daw.import_audio',
      category = 'DAW',
      title = 'Import Audio File',
      icon = 'file-audio',
      menu = 'Track',
      run = function ()
        import_audio (engine.position ())
      end,
    })
    commands.register ({
      id = 'daw.add_track',
      category = 'DAW',
      title = 'Add Instrument Track',
      key = 'ctrl+t',
      icon = 'plus',
      menu = 'Track',
      run = add_track,
    })
    commands.register ({
      id = 'daw.delete_track',
      category = 'DAW',
      title = 'Delete Track',
      icon = 'trash-2',
      menu = 'Track',
      when = function ()
        return session.selected_track () ~= nil
      end,
      run = function ()
        delete_track (session.selected_track () or '')
      end,
    })
    commands.register ({
      id = 'daw.duplicate_track',
      category = 'DAW',
      title = 'Duplicate Track',
      icon = 'copy',
      menu = 'Track',
      when = function ()
        return session.selected_track () ~= nil
      end,
      run = function ()
        duplicate_track (session.selected_track () or '')
      end,
    })
    commands.register ({
      id = 'daw.duplicate',
      category = 'DAW',
      title = 'Duplicate Clips',
      key = 'ctrl+d',
      icon = 'copy',
      menu = 'Edit',
      group = '2',
      when = function ()
        return free () and #session.selected_clips () > 0
      end,
      run = duplicate_clips,
    })
    commands.register ({
      id = 'daw.split',
      category = 'DAW',
      title = 'Split Clip at Playhead',
      key = 'ctrl+e',
      icon = 'scissors',
      menu = 'Edit',
      group = '2',
      when = free,
      run = split,
    })
    commands.register ({
      id = 'daw.delete_clips',
      category = 'DAW',
      title = 'Delete Clips',
      key = { 'delete', 'backspace' },
      icon = 'trash-2',
      menu = 'Edit',
      group = '2',
      when = function ()
        return free () and #session.selected_clips () > 0
      end,
      run = delete_clips,
    })
    commands.register ({
      id = 'daw.select_all_clips',
      category = 'DAW',
      title = 'Select All Clips',
      key = 'ctrl+a',
      icon = 'box-select',
      menu = 'Edit',
      group = '2',
      when = free,
      run = select_all,
    })
    commands.register ({
      id = 'daw.loop_selection',
      category = 'DAW',
      title = 'Loop the Selected Clips',
      key = 'ctrl+shift+l',
      icon = 'repeat',
      menu = 'Transport',
      when = function ()
        return #session.selected_clips () > 0
      end,
      run = function ()
        local song = session.song ()
        local a = math.huge ---@type number
        local z = 0 ---@type number
        for _, id in ipairs (session.selected_clips ()) do
          local c = daw.song.clip (song, id)
          if c and c.start < a then
            a = c.start
          end
          if c and c.start + c.length > z then
            z = c.start + c.length
          end
        end
        if z > a then
          session.apply (
            daw.song.set_loop (song, { on = true, start = a, finish = z }),
            { kind = 'edit', label = 'Set loop' }
          )
        end
      end,
    })
    commands.register ({
      id = 'daw.zoom_in',
      category = 'DAW',
      title = 'Zoom In',
      key = 'ctrl+=',
      icon = 'zoom-in',
      menu = 'View',
      run = function ()
        zoom (1.4)
      end,
    })
    commands.register ({
      id = 'daw.zoom_out',
      category = 'DAW',
      title = 'Zoom Out',
      key = 'ctrl+-',
      icon = 'zoom-out',
      menu = 'View',
      run = function ()
        zoom (1 / 1.4)
      end,
    })

    -- Start ------------------------------------------------------------------------------------

    -- Profiles with tabs, such as one with the settings screen, get the arrangement as a tab
    -- that stays open. Without tabs it fills the middle of the window.
    local tabs = app.try_use ('tabs')
    if windows then
      -- FL Studio's Playlist: the song, as clips on tracks.
      windows.add ({
        id = 'daw.arrange',
        title = 'Playlist',
        icon = 'audio-lines',
        key = 'f5',
        order = 1,
        open = true,
        x = 0,
        y = 0,
        w = 1,
        h = 0.68,
        z = 1,
        content = root,
        on_show = render,
      })
    elseif tabs then
      tabs.open ({
        id = 'daw.arrange',
        title = 'Arrangement',
        icon = 'audio-lines',
        content = root,
        closable = false,
      })
    else
      shell.mount ('main', root)
    end
    app.on ('daw:changed', function (_, change)
      local c = change --[[@as Daw.Change]]
      -- A knob, a fader or a pan changes nothing the arrangement shows.
      if
        c.kind == 'param'
        or (c.kind == 'mix' and (c.key == 'volume' or c.key == 'pan'))
      then
        return
      end
      render ()
    end)
    app.on ('daw:selection', render)
    app.on ('daw:devices', render)
    app.on ('daw:tick', move_playhead)
    render ()
  end,
}
