-- daw.channels: the Channel Rack, in the manner of FL Studio. Each instrument track is a
-- channel: a light that mutes it, its name, and a row of sixteen steps for one bar. A kit,
-- such as the Drum Kit, gets a row for each pad, so a beat is a few clicks. Steps write real
-- notes into the track's clips (see daw_steps), so the Playlist and the piano roll show them.
--
-- Clicking a step plays it, and a drag paints across a row. The bar follows the playhead
-- while the song plays, and the arrows pick another. Clicking a channel's name selects the
-- track and opens its settings window, and a double-click opens its notes in the piano roll.

local NAME_W = 140
local LED_W = 22
local STEP_W = 18
local STEP_GAP = 2
local GROUP_GAP = 5
local PAD_LEFT = 8

-- lang=css
local CSS = [[
.daw-cr {
  height: 100%;
  min-height: 0;
  display: flex;
  flex-direction: column;
  background: var(--bg);
  color: var(--fg);
  font-size: 12px;
  user-select: none;
}
.daw-cr-bar {
  flex: none;
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 4px 8px;
  border-bottom: 1px solid var(--border);
  background: var(--bg-alt);
}
.daw-cr-bar .ui-button {
  padding: 2px 8px;
  font-size: 12px;
}
.daw-cr-bar-label {
  min-width: 64px;
  text-align: center;
  font-variant-numeric: tabular-nums;
  color: var(--fg-muted);
}
.daw-cr-grow {
  flex: 1;
}
.daw-cr-follow.on {
  color: #f0a030;
}
.daw-cr-scroll {
  flex: 1;
  min-height: 0;
  overflow: auto;
  position: relative;
}
.daw-cr-list {
  position: relative;
  padding: 6px 0 10px;
}
.daw-cr-row {
  display: flex;
  align-items: center;
  height: 24px;
  padding-left: 8px;
  gap: 0;
}
.daw-cr-row.first {
  margin-top: 4px;
}
.daw-cr-led {
  flex: none;
  width: 12px;
  height: 12px;
  margin: 0 5px;
  border-radius: 50%;
  border: 1px solid rgba(0, 0, 0, 0.5);
  background: #2c3a2c;
  cursor: pointer;
}
.daw-cr-led.on {
  background: #6ee76e;
  box-shadow: 0 0 6px #6ee76e88;
}
.daw-cr-led.none {
  visibility: hidden;
}
.daw-cr-name {
  flex: none;
  width: 132px;
  height: 20px;
  margin-right: 8px;
  display: flex;
  align-items: center;
  gap: 5px;
  padding: 0 7px;
  box-sizing: border-box;
  border-radius: 3px;
  border-left: 4px solid var(--c);
  background: color-mix(in srgb, var(--bg-alt) 70%, #8795a3);
  color: var(--fg);
  overflow: hidden;
  white-space: nowrap;
  text-overflow: ellipsis;
  cursor: pointer;
}
.daw-cr-name.pad {
  background: color-mix(in srgb, var(--bg-alt) 85%, #8795a3);
  color: var(--fg-muted);
}
.daw-cr-row.sel .daw-cr-name {
  background: color-mix(in srgb, var(--bg-alt) 40%, #a9bccc);
  color: var(--fg);
}
.daw-cr-row.muted .daw-cr-name,
.daw-cr-row.muted .daw-cr-step {
  opacity: 0.45;
}
.daw-cr-steps {
  display: flex;
  gap: 2px;
}
.daw-cr-step {
  width: 18px;
  height: 20px;
  border-radius: 3px;
  background: color-mix(in srgb, var(--bg) 70%, #56606b);
  box-shadow: inset 0 -2px 0 rgba(0, 0, 0, 0.25);
  cursor: pointer;
}
.daw-cr-step.alt {
  background: color-mix(in srgb, var(--bg) 55%, #7a4a4a);
}
.daw-cr-step.gap {
  margin-left: 3px;
}
.daw-cr-step.on {
  background: linear-gradient(#ffd08a, #f0a030);
  box-shadow: 0 0 5px #f0a03088;
}
.daw-cr-now {
  position: absolute;
  top: 0;
  bottom: 0;
  width: 18px;
  background: rgba(255, 255, 255, 0.1);
  border-left: 1px solid rgba(255, 255, 255, 0.35);
  pointer-events: none;
  display: none;
}
.daw-cr-empty {
  padding: 18px;
  color: var(--fg-faint);
  text-align: center;
}
.daw-cr-add {
  margin: 8px 8px 0;
}
]]

---One row of steps: a channel, or one pad of a kit.
---@class DawChannels.Row
---@field track Daw.Track
---@field pitch integer
---@field name string
---@field pad boolean
---@field first boolean The track's first row, which carries its light.

---The left edge of a step, in pixels from the list's left.
---@param i integer From 1.
---@return number
local function step_left (i)
  return PAD_LEFT
    + LED_W
    + NAME_W
    + (i - 1) * (STEP_W + STEP_GAP)
    + math.floor ((i - 1) / 4) * (GROUP_GAP - STEP_GAP)
end

---@type Proteus.Plugin
return {
  name = 'DAW channel rack',
  description = 'The Channel Rack: every instrument as a channel, with a step sequencer that writes into the Playlist.',
  version = '1.0.0',
  requires = { proteus = '>=0.2.0', features = { 'permissions' } },
  permissions = {},
  depends = {
    'lib.ui',
    'daw.core',
    'daw.devices',
    'daw.session',
    'daw.engine',
    'daw.windows',
    'core.commands',
  },
  activate = function (app)
    local ui = app.use ('ui')
    local daw = app.use ('daw') --[[@as Daw.Core]]
    local devices = app.use ('daw.devices') --[[@as Daw.Devices]]
    local session = app.use ('daw.session') --[[@as Daw.Session]]
    local engine = app.use ('daw.engine') --[[@as Daw.Engine]]
    local windows = app.use ('daw.windows') --[[@as Daw.Windows]]
    local commands = app.use ('commands')
    local esc = app.util.escape
    ui.css (CSS)

    local bar = 0
    local follow = app.store.get ('follow', true) ~= false
    local rows = {} ---@type DawChannels.Row[]

    local bar_label = ui.span ({ class = 'daw-cr-bar-label' })
    local follow_btn ---@type Proteus.El
    follow_btn = ui.button ({
      class = 'daw-cr-follow' .. (follow and ' on' or ''),
      icon = 'locate-fixed',
      variant = 'ghost',
      title = 'Follow the playhead while playing',
      onclick = function ()
        follow = not follow
        app.store.set ('follow', follow)
        follow_btn:class ('on', follow)
      end,
    })
    local list = ui.div ({ class = 'daw-cr-list' })
    local now = ui.div ({ class = 'daw-cr-now' })
    local scroll = ui.div ({ class = 'daw-cr-scroll', list, now })

    ---@param to integer
    local function set_bar (to)
      bar = math.max (0, to)
      bar_label:text ('Bar ' .. (bar + 1))
    end
    set_bar (0)

    -- Rows ---------------------------------------------------------------------------------

    ---@param song Daw.Song
    ---@return DawChannels.Row[]
    local function rows_of (song)
      local out = {} ---@type DawChannels.Row[]
      for _, t in ipairs (song.tracks) do
        if t.kind == 'instrument' then
          local spec = t.instrument and devices.get (t.instrument.device)
          local pads = spec and spec.patch and spec.patch.pads or {}
          if #pads > 0 then
            for i, pad in ipairs (pads) do
              out[#out + 1] = {
                track = t,
                pitch = pad.pitch,
                name = pad.name,
                pad = true,
                first = i == 1,
              }
            end
          else
            out[#out + 1] = {
              track = t,
              pitch = daw.steps.pitch_of (t),
              name = t.name,
              pad = false,
              first = true,
            }
          end
        end
      end
      return out
    end

    local function render ()
      local song = session.song ()
      rows = rows_of (song)
      local sel = session.selected_track ()
      local count = daw.steps.count (song)
      local out = {} ---@type string[]
      for r, row in ipairs (rows) do
        local t = row.track
        local on = daw.steps.row (song, t.id, row.pitch, bar)
        local cells = {} ---@type string[]
        for i = 1, count do
          cells[#cells + 1] = string.format (
            '<div class="daw-cr-step%s%s%s" data-item="step:%d:%d"></div>',
            math.floor ((i - 1) / 4) % 2 == 1 and ' alt' or '',
            (i > 1 and (i - 1) % 4 == 0) and ' gap' or '',
            on[i] and ' on' or '',
            r,
            i
          )
        end
        local label = row.pad
            and (daw.time.note_name (row.pitch) .. ' ' .. row.name)
          or row.name
        out[#out + 1] = string.format (
          '<div class="daw-cr-row%s%s%s" style="--c:%s">'
            .. '<div class="daw-cr-led%s" data-item="led:%d" title="Mute or unmute %s"></div>'
            .. '<div class="daw-cr-name%s" data-item="name:%d" title="%s">%s</div>'
            .. '<div class="daw-cr-steps">%s</div></div>',
          t.id == sel and ' sel' or '',
          t.mute and ' muted' or '',
          (row.first and r > 1) and ' first' or '',
          esc (t.color),
          row.first and (t.mute and '' or ' on') or ' none',
          r,
          esc (t.name),
          row.pad and ' pad' or '',
          r,
          esc (
            t.name
              .. (row.pad and (' · ' .. row.name) or '')
              .. '. Click for its settings, double-click for its notes.'
          ),
          esc (label),
          table.concat (cells)
        )
      end
      if #rows == 0 then
        out[#out + 1] =
          '<div class="daw-cr-empty">No instrument channels yet.</div>'
      end
      list:html (table.concat (out))
    end

    -- The playhead ----------------------------------------------------------------------------

    ---@param beat number
    local function tick (beat)
      local song = session.song ()
      local bpb = daw.song.beats_per_bar (song)
      local b = math.floor (beat / bpb)
      if follow and engine.playing () and b ~= bar then
        set_bar (b)
        render ()
      end
      local i = math.floor ((beat - bar * bpb) / daw.steps.STEP) + 1
      if engine.playing () and i >= 1 and i <= daw.steps.count (song) then
        now:style ('display', 'block')
        now:style ('left', step_left (i) .. 'px')
      else
        now:style ('display', 'none')
      end
    end

    -- Input ------------------------------------------------------------------------------------

    ---@param item string?
    ---@return string kind
    ---@return integer row
    ---@return integer step
    local function parse (item)
      local kind, r, i = (item or ''):match ('^(%a+):(%d+):?(%d*)$')
      return kind or '',
        math.floor (tonumber (r) or 0),
        math.floor (tonumber (i) or 0)
    end

    ---Sets a step to `want`, and plays it when it turns on.
    ---@param row DawChannels.Row
    ---@param i integer
    ---@param want boolean
    local function set_step (row, i, want)
      local song = session.song ()
      local cur = daw.steps.row (song, row.track.id, row.pitch, bar)
      if cur[i] == want then
        return
      end
      local s = daw.steps.toggle (song, row.track.id, row.pitch, bar, i)
      session.apply (s, { kind = 'edit', label = 'Steps' }, 'steps')
      if want then
        engine.note_on (row.track.id, row.pitch, 0.8)
        local id, pitch = row.track.id, row.pitch
        app.timer.after (140, function ()
          engine.note_off (id, pitch)
        end)
      end
    end

    local painting = nil ---@type { row: integer, want: boolean }?

    list:on ('mousedown', function (ev)
      if ev.button ~= 0 then
        return nil
      end
      local kind, r, i = parse (ev.item)
      local row = rows[r]
      if not row then
        return nil
      end
      if kind == 'step' then
        local on = daw.steps.row (session.song (), row.track.id, row.pitch, bar)
        painting = { row = r, want = not on[i] }
        set_step (row, i, painting.want)
        local off ---@type fun()
        off = app.dom.on_global ('mouseup', function ()
          painting = nil
          session.seal ()
          off ()
          return nil
        end)
        return 'stop'
      elseif kind == 'led' then
        local t = daw.song.track (session.song (), row.track.id)
        if t then
          session.apply (
            daw.song.update_track (session.song (), t.id, { mute = not t.mute }),
            { kind = 'mix', track = t.id, key = 'mute', value = not t.mute }
          )
          session.seal ()
        end
        return 'stop'
      elseif kind == 'name' then
        session.select_track (row.track.id)
        windows.show ('daw.rack')
        return 'stop'
      end
      return nil
    end)
    list:on ('mouseover', function (ev)
      if not painting then
        return nil
      end
      local kind, r, i = parse (ev.item)
      if kind == 'step' and r == painting.row and rows[r] then
        set_step (rows[r], i, painting.want)
      end
      return nil
    end)
    list:on ('dblclick', function (ev)
      local kind, r = parse (ev.item)
      local row = rows[r]
      if kind ~= 'name' or not row then
        return nil
      end
      -- The clip under this bar, so its notes open in the piano roll.
      local song = session.song ()
      local at = bar * daw.song.beats_per_bar (song)
      local t = daw.song.track (song, row.track.id)
      for _, c in ipairs (t and t.clips or {}) do
        if at >= c.start and at < c.start + c.length then
          session.select_clips ({ c.id })
          session.edit_clip (c.id)
          windows.show ('daw.pianoroll')
          return 'stop'
        end
      end
      return 'stop'
    end)

    local root = ui.div ({
      class = 'daw-cr',
      ui.div ({
        class = 'daw-cr-bar',
        ui.button ({
          icon = 'chevron-left',
          variant = 'ghost',
          title = 'The bar before',
          onclick = function ()
            set_bar (bar - 1)
            render ()
          end,
        }),
        bar_label,
        ui.button ({
          icon = 'chevron-right',
          variant = 'ghost',
          title = 'The bar after',
          onclick = function ()
            set_bar (bar + 1)
            render ()
          end,
        }),
        follow_btn,
        ui.div ({ class = 'daw-cr-grow' }),
        ui.button ({
          'Channel',
          icon = 'plus',
          variant = 'ghost',
          title = 'Add an instrument channel',
          onclick = function ()
            commands.run ('daw.add_track')
          end,
        }),
      }),
      scroll,
    })

    windows.add ({
      id = 'daw.channels',
      title = 'Channel rack',
      icon = 'grid3x3',
      key = 'f6',
      order = 2,
      open = true,
      x = 24,
      y = 40,
      w = 540,
      h = 320,
      z = 2,
      min_w = 360,
      content = root,
      on_show = render,
    })

    app.on ('daw:changed', function (_, change)
      local c = change --[[@as Daw.Change]]
      if c.kind == 'param' or (c.kind == 'mix' and c.key ~= 'mute') then
        return
      end
      render ()
    end)
    app.on ('daw:selection', render)
    app.on ('daw:devices', render)
    app.on ('daw:tick', tick)
    app.on ('daw:transport', function (playing, beat)
      if not playing then
        now:style ('display', 'none')
      else
        tick (tonumber (beat) or 0)
      end
    end)
    render ()
  end,
}
