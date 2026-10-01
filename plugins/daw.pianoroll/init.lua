-- daw.pianoroll: the notes of one clip, in the Piano roll window (F7), or in the bottom dock
-- without floating windows. Keys run down the left side, time runs across, and the velocity of
-- each note stands along the bottom.
--
-- Click an empty spot to add a note, and drag to set its length. Drag a note to move it, or
-- its right edge to resize it. Shift and drag on empty space to select a box of notes. The
-- keys on the left play the track's instrument.
--
-- The rows and keys draw once for each clip. The notes draw into a layer of their own as one
-- HTML string, again on each step of a drag, and the song changes when the button comes up.

local KEYS_W = 64
local ROW = 12
local RULER_H = 20
local VEL_H = 64
local MIN_PPB = 16
local MAX_PPB = 400

-- lang=css
local CSS = [[
.daw-pr {
  height: 100%;
  min-height: 0;
  display: flex;
  flex-direction: column;
  background: var(--bg);
  color: var(--fg);
  font-size: 12px;
  user-select: none;
}
.daw-pr-bar {
  flex: none;
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 4px 8px;
  border-bottom: 1px solid var(--border);
  background: var(--bg-alt);
}
.daw-pr-bar .ui-button {
  padding: 2px 8px;
  font-size: 12px;
}
.daw-pr-title {
  font-weight: 600;
  margin-right: 6px;
}
.daw-pr-bar select,
.daw-pr-bar input {
  padding: 2px 4px;
  width: auto;
}
.daw-pr-grow {
  flex: 1;
}
.daw-pr-scroll {
  flex: 1;
  min-height: 0;
  overflow: auto;
  position: relative;
}
.daw-pr-wrap {
  position: relative;
}
.daw-pr-ruler {
  position: sticky;
  top: 0;
  z-index: 4;
  height: var(--ruler-h);
  margin-left: var(--keys-w);
  background: var(--bg-alt);
  border-bottom: 1px solid var(--border);
}
.daw-pr-corner {
  position: sticky;
  left: 0;
  top: 0;
  z-index: 5;
  float: left;
  width: var(--keys-w);
  height: var(--ruler-h);
  margin-left: calc(-1 * var(--keys-w));
  background: var(--bg-alt);
  border-bottom: 1px solid var(--border);
  border-right: 1px solid var(--border);
}
.daw-pr-beat {
  position: absolute;
  top: 0;
  bottom: 0;
  padding: 3px 4px;
  border-left: 1px solid var(--border);
  color: var(--fg-muted);
  font: 10px var(--font-mono);
}
.daw-pr-body {
  display: flex;
}
.daw-pr-keys {
  position: sticky;
  left: 0;
  z-index: 3;
  flex: none;
  width: var(--keys-w);
  border-right: 1px solid var(--border);
  background: var(--bg-alt);
  cursor: pointer;
}
.daw-pr-key {
  height: var(--row);
  box-sizing: border-box;
  padding-right: 4px;
  text-align: right;
  font-size: 9px;
  line-height: var(--row);
  color: var(--fg-muted);
  background: #f4f4f4;
  border-bottom: 1px solid #ccc;
  white-space: nowrap;
  overflow: hidden;
}
.daw-pr-key.black {
  background: #2a2a2a;
  color: #aaa;
}
.daw-pr-key.pad {
  color: var(--accent);
  font-weight: 600;
}
.daw-pr-key.down {
  background: var(--accent);
  color: var(--accent-fg);
}
.daw-pr-rows {
  flex: none;
  position: relative;
}
.daw-pr-row {
  height: var(--row);
  box-sizing: border-box;
  border-bottom: 1px solid color-mix(in srgb, var(--border) 50%, transparent);
}
.daw-pr-row.black {
  background: color-mix(in srgb, var(--fg) 5%, transparent);
}
.daw-pr-row.c {
  border-bottom-color: var(--border);
}
.daw-pr-lines {
  position: absolute;
  inset: 0;
  pointer-events: none;
  background-image: linear-gradient(to right, var(--border) 1px, transparent 1px),
    linear-gradient(to right, color-mix(in srgb, var(--border) 50%, transparent) 1px, transparent 1px);
  background-size: var(--bar-w) 100%, var(--beat-w) 100%;
}
.daw-pr-after {
  position: absolute;
  top: 0;
  bottom: 0;
  right: 0;
  background: color-mix(in srgb, var(--bg) 60%, #000 40%);
  opacity: 0.35;
  pointer-events: none;
}
.daw-pr-notes {
  position: absolute;
  z-index: 2;
  pointer-events: none;
}
.daw-note {
  position: absolute;
  pointer-events: auto;
  height: calc(var(--row) - 1px);
  box-sizing: border-box;
  border-radius: 3px;
  border: 1px solid color-mix(in srgb, var(--c) 70%, #000);
  background: var(--c);
  cursor: grab;
}
.daw-note.sel {
  border-color: var(--fg);
  box-shadow: 0 0 0 1px var(--fg);
}
.daw-nedge {
  position: absolute;
  top: 0;
  bottom: 0;
  right: 0;
  width: 6px;
  cursor: ew-resize;
}
.daw-pr-playhead {
  position: absolute;
  top: 0;
  bottom: 0;
  width: 1px;
  background: var(--danger);
  pointer-events: none;
  z-index: 3;
}
.daw-pr-box {
  position: absolute;
  z-index: 4;
  border: 1px dashed var(--fg);
  background: color-mix(in srgb, var(--accent) 15%, transparent);
  pointer-events: none;
  display: none;
}
.daw-pr-vel {
  position: sticky;
  bottom: 0;
  z-index: 4;
  height: var(--vel-h);
  display: flex;
  border-top: 1px solid var(--border);
  background: var(--bg-alt);
}
.daw-pr-vel-label {
  position: sticky;
  left: 0;
  z-index: 1;
  flex: none;
  width: var(--keys-w);
  padding: 4px;
  box-sizing: border-box;
  border-right: 1px solid var(--border);
  background: var(--bg-alt);
  color: var(--fg-muted);
  font-size: 10px;
}
.daw-pr-vel-bars {
  position: relative;
  flex: none;
  cursor: ns-resize;
}
.daw-vel {
  position: absolute;
  bottom: 0;
  width: 5px;
  border-radius: 2px 2px 0 0;
  background: var(--c);
}
.daw-vel.sel {
  background: var(--fg);
}
.daw-pr-empty {
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: center;
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
  name = 'DAW piano roll',
  description = 'Draw, move and shape the notes of a clip.',
  version = '1.2.1',
  requires = { proteus = '>=0.2.0', features = { 'permissions' } },
  permissions = {},
  depends = {
    'lib.ui',
    'ui.views',
    'daw.core',
    'daw.devices',
    'daw.session',
    'daw.engine',
    'core.commands',
  },
  optional = { 'ui.menus', 'ui.palette', 'core.keys', 'ui.windows' },
  activate = function (app)
    local ui = app.use ('ui')
    local views = app.use ('views')
    local windows = app.try_use ('windows') --[[@as Proteus.Windows?]]
    local daw = app.use ('daw') --[[@as Daw.Core]]
    local devices = app.use ('daw.devices') --[[@as Daw.Devices]]
    local session = app.use ('daw.session') --[[@as Daw.Session]]
    local engine = app.use ('daw.engine') --[[@as Daw.Engine]]
    local commands = app.use ('commands')
    local menus = app.try_use ('menus')
    local picker = app.try_use ('picker')
    local esc = app.util.escape
    ui.css (CSS)

    local ppb = tonumber (app.store.get ('zoom', 80)) or 80
    local grid = tostring (app.store.get ('grid', '1/16'))
    local last_length = daw.time.grid_beats (grid) > 0
        and daw.time.grid_beats (grid) * 2
      or 0.5
    local picked = {} ---@type integer[]
    local focused = false
    local drawn_clip = nil ---@type string?
    local drawn_key = ''
    local preview = nil ---@type Daw.Note[]? Notes shown during a drag, before the song changes.
    local held_key = nil ---@type integer?

    -- Elements ---------------------------------------------------------------------------------

    local title = ui.span ({ class = 'daw-pr-title', text = 'Piano Roll' })
    local grid_select = ui.h ('select', {
      class = 'ui-input',
      title = 'Note grid',
      onchange = function (ev)
        grid = ev.value or '1/16'
        app.store.set ('grid', grid)
        if daw.time.grid_beats (grid) > 0 then
          last_length = daw.time.grid_beats (grid)
        end
        drawn_key = ''
      end,
    })
    for _, g in ipairs (daw.time.GRIDS) do
      grid_select:append (ui.option ({
        text = g == 'off' and 'No grid' or ('Grid ' .. g),
        value = g,
      }))
    end
    grid_select:value (grid)

    local length_input = ui.input ({
      type = 'number',
      title = 'Clip length in bars',
      attrs = { min = 0.25, step = 0.25 },
      style = { width = '64px' },
    })

    local bg = ui.div ()
    local notes_layer = ui.div ({ class = 'daw-pr-notes' })
    local playhead = ui.div ({ class = 'daw-pr-playhead' })
    local box = ui.div ({ class = 'daw-pr-box' })
    local vel_bars = ui.div ({ class = 'daw-pr-vel-bars' })
    local vel = ui.div ({
      class = 'daw-pr-vel',
      ui.div ({ class = 'daw-pr-vel-label', text = 'Velocity' }),
      vel_bars,
    })
    local wrap =
      ui.div ({ class = 'daw-pr-wrap', bg, notes_layer, playhead, box, vel })
    local scroll = ui.div ({ class = 'daw-pr-scroll', wrap })
    local empty = ui.div ({
      class = 'daw-pr-empty',
      text = 'Double-click a clip in the arrangement to edit its notes.',
    })
    local root = ui.div ({
      class = 'daw-pr',
      ui.div ({
        class = 'daw-pr-bar',
        title,
        grid_select,
        ui.label ({ class = 'daw-field', text = 'Bars', length_input }),
        ui.div ({ class = 'daw-pr-grow' }),
        ui.button ({
          'Quantize',
          icon = 'magnet',
          variant = 'ghost',
          title = 'Move the selected notes, or all of them, to the grid (Alt+Q)',
          onclick = function ()
            commands.run ('daw.quantize')
          end,
        }),
        ui.button ({
          icon = 'zoom-out',
          variant = 'ghost',
          title = 'Zoom out',
          onclick = function ()
            ppb = math.max (MIN_PPB, ppb / 1.4)
            app.store.set ('zoom', ppb)
            drawn_key = ''
            app.emit ('daw:pianoroll_redraw')
          end,
        }),
        ui.button ({
          icon = 'zoom-in',
          variant = 'ghost',
          title = 'Zoom in',
          onclick = function ()
            ppb = math.min (MAX_PPB, ppb * 1.4)
            app.store.set ('zoom', ppb)
            drawn_key = ''
            app.emit ('daw:pianoroll_redraw')
          end,
        }),
      }),
      scroll,
      empty,
    })

    -- What is being edited ---------------------------------------------------------------------

    ---@return Daw.Clip?, Daw.Track?
    local function target ()
      local id = session.editing ()
      if not id then
        for _, cid in ipairs (session.selected_clips ()) do
          local c, t = daw.song.clip (session.song (), cid)
          if c and t and t.kind == 'instrument' then
            return c, t
          end
        end
        -- As in FL Studio, the selected channel: its clip under the playhead, or its first.
        local t =
          daw.song.track (session.song (), session.selected_track () or '')
        if t and t.kind == 'instrument' and #t.clips > 0 then
          local beat = engine.position ()
          for _, c in ipairs (t.clips) do
            if beat >= c.start and beat < c.start + c.length then
              return c, t
            end
          end
          return t.clips[1], t
        end
        return nil, nil
      end
      local c, t = daw.song.clip (session.song (), id)
      if c and t and t.kind == 'instrument' then
        return c, t
      end
      return nil, nil
    end

    ---@param track Daw.Track
    ---@return table<integer, string>
    local function pad_names (track)
      local out = {} ---@type table<integer, string>
      local spec = track.instrument and devices.get (track.instrument.device)
      for _, pad in ipairs (spec and spec.patch.pads or {}) do
        out[pad.pitch] = pad.name
      end
      return out
    end

    ---@param notes Daw.Note[]
    ---@return Daw.Note[]
    local function current_notes (notes)
      return preview or notes
    end

    -- Drawing ----------------------------------------------------------------------------------

    ---@param clip Daw.Clip
    ---@param track Daw.Track
    ---@param song Daw.Song
    local function draw_background (clip, track, song)
      local bar = daw.song.beats_per_bar (song)
      local width = math.max (clip.length, 1) * ppb
      local pads = pad_names (track)
      local key = table.concat ({
        clip.id,
        clip.length,
        ppb,
        bar,
        track.id,
        track.instrument and track.instrument.device or '',
      }, ':')
      if key == drawn_key then
        return
      end
      drawn_key = key
      wrap:style ('--keys-w', px (KEYS_W))
      wrap:style ('--row', px (ROW))
      wrap:style ('--ruler-h', px (RULER_H))
      wrap:style ('--vel-h', px (VEL_H))
      wrap:style ('--bar-w', px (bar * ppb))
      wrap:style ('--beat-w', px (ppb))
      wrap:style ('width', px (KEYS_W + width + 40))

      local out = {} ---@type string[]
      out[#out + 1] = '<div class="daw-pr-ruler" style="width:'
        .. px (width + 40)
        .. '">'
      out[#out + 1] = '<div class="daw-pr-corner"></div>'
      local every = ppb < 30 and bar or 1
      for b = 0, math.ceil (clip.length) - 1, every do
        out[#out + 1] = string.format (
          '<div class="daw-pr-beat" style="left:%s">%s</div>',
          px (b * ppb),
          daw.time.format_short (clip.start + b, bar)
        )
      end
      out[#out + 1] = '</div><div class="daw-pr-body"><div class="daw-pr-keys">'
      for p = 127, 0, -1 do
        local black = daw.time.is_black (p)
        local name = pads[p]
        local label = name and esc (name)
          or (p % 12 == 0 and daw.time.note_name (p) or '')
        out[#out + 1] = string.format (
          '<div class="daw-pr-key%s%s" data-item="key:%d">%s</div>',
          black and ' black' or '',
          name and ' pad' or '',
          p,
          label
        )
      end
      out[#out + 1] = '</div><div class="daw-pr-rows" style="width:'
        .. px (width + 40)
        .. '">'
      for p = 127, 0, -1 do
        out[#out + 1] = string.format (
          '<div class="daw-pr-row%s%s" data-item="row:%d"></div>',
          daw.time.is_black (p) and ' black' or '',
          p % 12 == 0 and ' c' or '',
          p
        )
      end
      out[#out + 1] = '<div class="daw-pr-lines"></div>'
      out[#out + 1] = '<div class="daw-pr-after" style="left:'
        .. px (clip.length * ppb)
        .. '"></div>'
      out[#out + 1] = '</div></div>'
      bg:html (table.concat (out))
      notes_layer:style ('left', px (KEYS_W))
      notes_layer:style ('top', px (RULER_H))
      notes_layer:style ('width', px (width))
      notes_layer:style ('height', px (128 * ROW))
      vel_bars:style ('width', px (width + 40))
      vel_bars:style ('height', px (VEL_H))
    end

    ---@param clip Daw.Clip
    ---@param track Daw.Track
    local function draw_notes (clip, track)
      local list = current_notes (clip.notes or {})
      local sel = {} ---@type table<integer, boolean>
      for _, i in ipairs (picked) do
        sel[i] = true
      end
      local color = esc (clip.color or track.color)
      local out = {} ---@type string[]
      local bars = {} ---@type string[]
      for i, n in ipairs (list) do
        out[#out + 1] = string.format (
          '<div class="daw-note%s" data-item="note:%d" style="left:%s;top:%s;width:%s;--c:%s;opacity:%.2f" title="%s">'
            .. '<div class="daw-nedge" data-item="nedge:%d"></div></div>',
          sel[i] and ' sel' or '',
          i,
          px (n.start * ppb),
          px ((127 - n.pitch) * ROW),
          px (math.max (4, n.length * ppb)),
          color,
          0.45 + n.velocity * 0.55,
          daw.time.note_name (n.pitch)
            .. ' · velocity '
            .. math.floor (n.velocity * 127 + 0.5),
          i
        )
        bars[#bars + 1] = string.format (
          '<div class="daw-vel%s" data-item="vel:%d" style="left:%s;height:%s;--c:%s"></div>',
          sel[i] and ' sel' or '',
          i,
          px (n.start * ppb),
          px (math.max (2, n.velocity * (VEL_H - 8))),
          color
        )
      end
      notes_layer:html (table.concat (out))
      vel_bars:html (table.concat (bars))
    end

    local scrolled_for = nil ---@type string?

    local function render ()
      local clip, track = target ()
      scroll:show (clip ~= nil)
      empty:show (clip == nil)
      if windows then
        windows.set_title (
          'daw.pianoroll',
          track and ('Piano roll - ' .. track.name) or 'Piano roll'
        )
      end
      if not clip or not track then
        title:text ('Piano Roll')
        drawn_clip = nil
        return
      end
      if drawn_clip ~= clip.id then
        picked = {}
        preview = nil
      end
      drawn_clip = clip.id
      local song = session.song ()
      title:text (track.name .. ' · ' .. clip.name)
      if app.dom.focus_info ().handle ~= length_input.id then
        length_input:value (
          tostring (clip.length / daw.song.beats_per_bar (song))
        )
      end
      draw_background (clip, track, song)
      draw_notes (clip, track)
      -- The first time a clip shows, scroll to its notes, or to middle C.
      if scrolled_for ~= clip.id then
        scrolled_for = clip.id
        local lo, hi = daw.notes.range (clip.notes or {})
        local centre = lo and math.floor (((lo or 60) + (hi or 60)) / 2) or 60
        local h = tonumber (scroll:get ('clientHeight')) or 200
        scroll:set ('scrollTop', math.max (0, (127 - centre) * ROW - h / 2))
      end
    end

    ---@param beat number
    local function move_playhead (beat)
      local clip = target ()
      if not clip then
        return
      end
      local at = beat - clip.start
      playhead:show (at >= 0 and at <= clip.length)
      playhead:style ('left', px (KEYS_W + at * ppb))
    end

    -- Changing notes ---------------------------------------------------------------------------

    ---@param notes Daw.Note[]
    ---@param label string
    local function commit (notes, label)
      local clip = target ()
      if not clip then
        return
      end
      preview = nil
      session.apply (
        daw.song.set_notes (session.song (), clip.id, notes),
        { kind = 'edit', label = label }
      )
    end

    ---@param pitch integer
    ---@param velocity? number
    local function audition (pitch, velocity)
      local _, track = target ()
      if not track then
        return
      end
      engine.note_on (track.id, pitch, velocity or 0.8)
      app.timer.after (180, function ()
        engine.note_off (track.id, pitch)
      end)
    end

    ---@param x number
    ---@param y number
    ---@return number beat, integer pitch
    local function point (x, y)
      local r = wrap:rect ()
      local beat = (x - r.left - KEYS_W) / ppb
      local pitch = 127 - math.floor ((y - r.top - RULER_H) / ROW)
      return beat, math.max (0, math.min (127, pitch))
    end

    ---@param beat number
    ---@return number
    local function snap_down (beat)
      return daw.time.snap_down (beat, grid)
    end

    ---@return number
    local function step ()
      local s = daw.time.grid_beats (grid)
      return s > 0 and s or 1 / 32
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

    local function redraw ()
      local clip, track = target ()
      if clip and track then
        draw_notes (clip, track)
      end
    end

    ---@param ev Proteus.DomEvent
    ---@param index integer
    ---@param resize boolean
    local function press_note (ev, index, resize)
      local clip = target ()
      if not clip then
        return
      end
      local notes = clip.notes or {}
      local note = notes[index]
      if not note then
        return
      end
      local in_sel = false
      for _, i in ipairs (picked) do
        in_sel = in_sel or i == index
      end
      if ev.ctrl or ev.shift then
        local next_sel = {} ---@type integer[]
        for _, i in ipairs (picked) do
          if i ~= index then
            next_sel[#next_sel + 1] = i
          end
        end
        if not in_sel then
          next_sel[#next_sel + 1] = index
        end
        picked = next_sel
        redraw ()
        return
      end
      if not in_sel then
        picked = { index }
      end
      audition (note.pitch, note.velocity)
      local b0, p0 = point (ev.x or 0, ev.y or 0)
      local moved = false
      local last_pitch = note.pitch
      follow (function (mv)
        local b, p = point (mv.x or 0, mv.y or 0)
        if not moved and math.abs (b - b0) * ppb < 3 and p == p0 then
          return
        end
        moved = true
        if resize then
          local finish = mv.alt and (note.start + note.length + b - b0)
            or daw.time.snap (note.start + note.length + b - b0, grid)
          preview = daw.notes.resize (
            notes,
            picked,
            finish - (note.start + note.length),
            step ()
          )
        else
          local d = mv.alt and (b - b0)
            or (daw.time.snap (note.start + b - b0, grid) - note.start)
          preview = daw.notes.move (notes, picked, d, p - p0, clip.length)
          local now_pitch = math.max (0, math.min (127, note.pitch + p - p0))
          if now_pitch ~= last_pitch then
            last_pitch = now_pitch
            audition (now_pitch, note.velocity)
          end
        end
        redraw ()
      end, function ()
        if moved and preview then
          if resize then
            local changed = preview[index]
            if changed then
              last_length = changed.length
            end
          end
          commit (preview, resize and 'Resize notes' or 'Move notes')
        else
          redraw ()
        end
      end)
    end

    ---@param ev Proteus.DomEvent
    local function press_empty (ev)
      local clip = target ()
      if not clip then
        return
      end
      local notes = clip.notes or {}
      local b0, p0 = point (ev.x or 0, ev.y or 0)
      if b0 < 0 or b0 >= clip.length then
        return
      end
      if ev.shift then
        -- A box selects every note it touches.
        local r = wrap:rect ()
        local x0, y0 = ev.x or 0, ev.y or 0
        follow (function (mv)
          local x1, y1 = mv.x or 0, mv.y or 0
          box:style ('display', 'block')
          box:style ('left', px (math.min (x0, x1) - r.left))
          box:style ('top', px (math.min (y0, y1) - r.top))
          box:style ('width', px (math.abs (x1 - x0)))
          box:style ('height', px (math.abs (y1 - y0)))
        end, function (up)
          box:style ('display', 'none')
          local b1, p1 = point (up.x or 0, up.y or 0)
          picked = daw.notes.within (notes, b0, b1, p0, p1)
          redraw ()
        end)
        return
      end
      local start = snap_down (b0)
      local list, index = daw.notes.add (notes, {
        pitch = p0,
        start = start,
        length = math.min (last_length, clip.length - start),
        velocity = 0.8,
      })
      picked = { index }
      preview = list
      audition (p0)
      redraw ()
      follow (function (mv)
        local b = point (mv.x or 0, mv.y or 0)
        local finish = mv.alt and b or daw.time.snap (b, grid)
        local length = math.max (step (), finish - start)
        local n = list[index]
        preview = daw.notes.resize (list, { index }, length - n.length, step ())
        redraw ()
      end, function ()
        local done = preview or list
        local n = done[index]
        if n then
          last_length = n.length
        end
        commit (done, 'Add note')
      end)
    end

    ---@param ev Proteus.DomEvent
    local function press_velocity (ev)
      local clip = target ()
      if not clip then
        return
      end
      local notes = clip.notes or {}
      local r = vel_bars:rect ()
      ---@param y number
      ---@return number
      local function level (y)
        return math.max (0.01, math.min (1, (r.bottom - y) / (VEL_H - 8)))
      end
      local kind, id = (ev.item or ''):match ('^(%w+):(%d+)$')
      local which = picked
      if kind == 'vel' then
        local index = math.floor (tonumber (id) or 0)
        local in_sel = false
        for _, i in ipairs (picked) do
          in_sel = in_sel or i == index
        end
        which = in_sel and picked or { index }
      end
      if #which == 0 then
        return
      end
      preview = daw.notes.set_velocity (notes, which, level (ev.y or 0))
      redraw ()
      follow (function (mv)
        preview = daw.notes.set_velocity (notes, which, level (mv.y or 0))
        redraw ()
      end, function ()
        if preview then
          commit (preview, 'Velocity')
        end
      end)
    end

    -- The keys play the instrument --------------------------------------------------------------

    ---@param pitch integer?
    local function key_down (pitch)
      local _, track = target ()
      if held_key and track then
        engine.note_off (track.id, held_key)
      end
      held_key = pitch
      if pitch and track then
        engine.note_on (track.id, pitch, 0.8)
      end
    end

    -- Commands on the selection ----------------------------------------------------------------

    ---@param fn fun(notes: Daw.Note[]): Daw.Note[]?, string?
    local function edit (fn)
      local clip = target ()
      if not clip then
        return
      end
      local out, label = fn (clip.notes or {})
      if out then
        commit (out, label or 'Edit notes')
      end
    end

    ---@return boolean
    local function free ()
      return focused and target () ~= nil and not app.dom.focus_info ().editable
    end

    local function delete_notes ()
      edit (function (notes)
        if #picked == 0 then
          return nil
        end
        local out = daw.notes.remove (notes, picked)
        picked = {}
        return out, 'Delete notes'
      end)
    end

    ---@param semitones integer
    local function transpose (semitones)
      edit (function (notes)
        return daw.notes.transpose (notes, picked, semitones), 'Transpose'
      end)
    end

    ---@param beats number
    local function nudge (beats)
      local clip = target ()
      edit (function (notes)
        return daw.notes.move (
          notes,
          picked,
          beats,
          0,
          clip and clip.length or 4
        ),
          'Move notes'
      end)
    end

    -- Input ------------------------------------------------------------------------------------

    root:on ('mousedown', function ()
      if not focused then
        app.emit ('daw:focus', 'pianoroll')
      end
      return nil
    end, { capture = true })
    app.on ('daw:focus', function (who)
      focused = who == 'pianoroll'
    end)

    wrap:on ('mousedown', function (ev)
      if ev.button ~= 0 then
        return nil
      end
      local kind, id = (ev.item or ''):match ('^(%w+):(%d+)$')
      local n = math.floor (tonumber (id) or 0)
      if kind == 'note' or kind == 'nedge' then
        press_note (ev, n, kind == 'nedge')
        return true
      elseif kind == 'row' then
        if not ev.shift and #picked > 0 and not ev.ctrl then
          picked = {}
        end
        press_empty (ev)
        return true
      elseif kind == 'key' then
        key_down (n)
        local off_up ---@type fun()
        off_up = app.dom.on_global ('mouseup', function ()
          off_up ()
          key_down (nil)
          return nil
        end)
        return true
      elseif kind == 'vel' or (ev.item == nil and ev.target == vel_bars.id) then
        press_velocity (ev)
        return true
      end
      return nil
    end)

    wrap:on ('dblclick', function (ev)
      local kind, id = (ev.item or ''):match ('^(%w+):(%d+)$')
      if kind == 'note' then
        picked = { math.floor (tonumber (id) or 0) }
        delete_notes ()
      end
      return nil
    end)

    length_input:on ('change', function (ev)
      local clip = target ()
      local bars = tonumber (ev.value)
      if clip and bars and bars > 0 then
        local bar = daw.song.beats_per_bar (session.song ())
        session.apply (
          daw.song.update_clip (
            session.song (),
            clip.id,
            { length = bars * bar }
          ),
          { kind = 'edit', label = 'Clip length' }
        )
      end
      return nil
    end)

    scroll:on ('wheel', function (ev)
      if ev.ctrl then
        ppb = math.max (
          MIN_PPB,
          math.min (MAX_PPB, ppb * ((ev.dy or 0) < 0 and 1.15 or 1 / 1.15))
        )
        app.store.set ('zoom', ppb)
        drawn_key = ''
        render ()
        return true
      end
      return nil
    end)

    if menus then
      menus.attach (wrap, function (ev)
        local kind, id = (ev.item or ''):match ('^(%w+):(%d+)$')
        if kind == 'note' or kind == 'nedge' then
          local index = math.floor (tonumber (id) or 0)
          local in_sel = false
          for _, i in ipairs (picked) do
            in_sel = in_sel or i == index
          end
          if not in_sel then
            picked = { index }
            redraw ()
          end
        end
        if not target () then
          return nil
        end
        return {
          {
            label = 'Delete',
            icon = 'trash-2',
            key = 'Delete',
            disabled = #picked == 0,
            run = delete_notes,
          },
          {
            label = 'Quantize',
            icon = 'magnet',
            key = 'Alt+Q',
            run = function ()
              commands.run ('daw.quantize')
            end,
          },
          {
            label = 'Up an Octave',
            icon = 'chevrons-up',
            key = 'Shift+Up',
            run = function ()
              transpose (12)
            end,
          },
          {
            label = 'Down an Octave',
            icon = 'chevrons-down',
            key = 'Shift+Down',
            run = function ()
              transpose (-12)
            end,
          },
          {
            label = 'Set Velocity',
            icon = 'bar-chart-3',
            run = function ()
              commands.run ('daw.velocity')
            end,
          },
          { separator = true },
          {
            label = 'Select All',
            icon = 'box-select',
            key = 'Ctrl+A',
            run = function ()
              commands.run ('daw.select_all_notes')
            end,
          },
        }
      end)
    end

    ---@param id string
    ---@param title_text string
    ---@param key string|string[]
    ---@param run fun()
    ---@param icon? string
    local function note_command (id, title_text, key, run, icon)
      commands.register ({
        id = id,
        category = 'Piano Roll',
        title = title_text,
        key = key,
        icon = icon,
        when = free,
        run = run,
      })
    end

    note_command (
      'daw.delete_notes',
      'Delete Notes',
      { 'delete', 'backspace' },
      delete_notes,
      'trash-2'
    )
    note_command (
      'daw.select_all_notes',
      'Select All Notes',
      'ctrl+a',
      function ()
        local clip = target ()
        picked = {}
        for i in ipairs (clip and clip.notes or {}) do
          picked[#picked + 1] = i
        end
        redraw ()
      end,
      'box-select'
    )
    note_command ('daw.quantize', 'Quantize', 'alt+q', function ()
      edit (function (notes)
        local g = daw.time.grid_beats (grid) > 0 and grid or '1/16'
        return daw.notes.quantize (notes, picked, g, false), 'Quantize'
      end)
    end, 'magnet')
    note_command ('daw.transpose_up', 'Up a Semitone', 'arrowup', function ()
      transpose (1)
    end)
    note_command (
      'daw.transpose_down',
      'Down a Semitone',
      'arrowdown',
      function ()
        transpose (-1)
      end
    )
    note_command ('daw.octave_up', 'Up an Octave', 'shift+arrowup', function ()
      transpose (12)
    end)
    note_command (
      'daw.octave_down',
      'Down an Octave',
      'shift+arrowdown',
      function ()
        transpose (-12)
      end
    )
    note_command (
      'daw.nudge_left',
      'Earlier by a Grid Step',
      'arrowleft',
      function ()
        nudge (-step ())
      end
    )
    note_command (
      'daw.nudge_right',
      'Later by a Grid Step',
      'arrowright',
      function ()
        nudge (step ())
      end
    )
    commands.register ({
      id = 'daw.velocity',
      category = 'Piano Roll',
      title = 'Set Velocity',
      icon = 'bar-chart-3',
      when = function ()
        return target () ~= nil
      end,
      run = function ()
        if not picker then
          return
        end
        picker.input ({
          prompt = 'Velocity from 1 to 127, for the selected notes or all of them',
          value = '100',
          validate = function (text)
            local n = tonumber (text)
            if not n or n < 1 or n > 127 then
              return 'A number from 1 to 127'
            end
            return nil
          end,
          on_submit = function (text)
            edit (function (notes)
              return daw.notes.set_velocity (
                notes,
                picked,
                (tonumber (text) or 100) / 127
              ),
                'Velocity'
            end)
          end,
        })
      end,
    })

    -- Start ------------------------------------------------------------------------------------

    local function on_show ()
      drawn_key = ''
      -- A roll drawn while hidden could not scroll to its notes, so it does now.
      scrolled_for = nil
      render ()
    end
    if windows then
      windows.add ({
        category = 'DAW',
        id = 'daw.pianoroll',
        title = 'Piano roll',
        icon = 'piano',
        key = 'f7',
        order = 3,
        x = 0.06,
        y = 0.1,
        w = 0.86,
        h = 0.62,
        content = root,
        on_show = on_show,
        -- The Playlist and the Channel rack open it.
        shared = true,
      })
    else
      views.add ('bottom', {
        id = 'daw.pianoroll',
        title = 'Piano Roll',
        icon = 'piano',
        order = 1,
        content = root,
        on_show = on_show,
        -- The arrangement opens it.
        shared = true,
      })
    end

    app.on ('daw:changed', function (_, change)
      local c = change --[[@as Daw.Change]]
      if c.kind == 'param' or c.kind == 'mix' then
        return
      end
      preview = nil
      render ()
    end)
    app.on ('daw:edit', render)
    app.on ('daw:selection', function ()
      if not session.editing () then
        render ()
      end
    end)
    app.on ('daw:devices', function ()
      drawn_key = ''
      render ()
    end)
    app.on ('daw:pianoroll_redraw', render)
    app.on ('daw:tick', move_playhead)
    render ()
  end,
}
