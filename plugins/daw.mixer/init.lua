-- daw.mixer: a channel strip for each track and one for the master, in the Mixer window
-- (F9), or in the bottom dock without daw.windows.
-- Each strip has a level meter, a fader, a pan and mute and solo. Moving a fader sends a
-- `mix` change, which the engine applies at once, without the whole song.
--
-- The strips are built again when tracks come, go or move. Other changes, such as undo,
-- only set the controls to the song's values.

-- lang=css
local CSS = [[
.daw-mix {
  height: 100%;
  min-height: 0;
  box-sizing: border-box;
  display: flex;
  gap: 6px;
  padding: 8px;
  overflow: auto;
  background: var(--bg);
  user-select: none;
}
.daw-strip {
  flex: none;
  width: 84px;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 6px;
  padding: 6px 4px;
  border: 1px solid var(--border);
  border-top: 4px solid var(--c);
  border-radius: var(--radius);
  background: var(--bg-alt);
  cursor: pointer;
}
.daw-strip > * {
  flex: none;
}
.daw-strip > .daw-strip-mid {
  flex: 1;
}
.daw-strip.sel {
  background: var(--bg-active);
}
.daw-strip.master {
  margin-left: auto;
  border-top-color: var(--fg);
}
.daw-strip-name {
  width: 100%;
  text-align: center;
  font-weight: 600;
  font-size: 11px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.daw-strip-dev {
  width: 100%;
  text-align: center;
  font-size: 10px;
  color: var(--fg-muted);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.daw-strip-mid {
  min-height: 40px;
  display: flex;
  gap: 6px;
  align-items: stretch;
}
.daw-fader {
  writing-mode: vertical-lr;
  direction: rtl;
  width: 22px;
  height: 100%;
  margin: 0;
  accent-color: var(--accent);
  cursor: ns-resize;
}
.daw-meter-v {
  position: relative;
  width: 8px;
  border-radius: 3px;
  background: var(--bg);
  overflow: hidden;
}
.daw-meter-v div {
  position: absolute;
  left: 0;
  right: 0;
  bottom: 0;
  height: 0;
  background: var(--success);
}
.daw-meter-v div.warm {
  background: var(--warning);
}
.daw-meter-v div.hot {
  background: var(--danger);
}
.daw-db {
  font: 10px var(--font-mono);
  color: var(--fg-muted);
}
.daw-pan {
  width: 70px;
  margin: 0;
  accent-color: var(--accent);
}
.daw-strip-btns {
  display: flex;
  gap: 4px;
}
]]

---@param db number
---@return string
local function db_text (db)
  if db <= -60 then
    return '-inf'
  end
  return string.format ('%+.1f', db)
end

---Maps a peak from 0 to 1 onto a meter height from 0 to 1, in decibels from -48 to 0.
---@param peak number
---@return number
local function meter_height (peak)
  if peak <= 0 then
    return 0
  end
  local db = 20 * math.log (peak) / math.log (10)
  return math.max (0, math.min (1, (db + 48) / 48))
end

---@type Proteus.Plugin
return {
  name = 'DAW mixer',
  description = 'Faders, pans, meters, mute and solo for every track.',
  version = '1.1.0',
  requires = { proteus = '>=0.2.0', features = { 'permissions' } },
  permissions = {},
  depends = {
    'lib.ui',
    'ui.views',
    'daw.core',
    'daw.devices',
    'daw.session',
    'daw.engine',
  },
  optional = { 'daw.windows' },
  activate = function (app)
    local ui = app.use ('ui')
    local views = app.use ('views')
    local windows = app.try_use ('daw.windows') --[[@as Daw.Windows?]]
    local daw = app.use ('daw') --[[@as Daw.Core]]
    local devices = app.use ('daw.devices') --[[@as Daw.Devices]]
    local session = app.use ('daw.session') --[[@as Daw.Session]]
    local engine = app.use ('daw.engine') --[[@as Daw.Engine]]
    ui.css (CSS)

    ---@class DawMixer.Strip
    ---@field root Proteus.El
    ---@field fader Proteus.El
    ---@field db Proteus.El
    ---@field pan? Proteus.El
    ---@field mute? Proteus.El
    ---@field solo? Proteus.El
    ---@field fills Proteus.El[] The coloured part of each meter.

    local root = ui.div ({ class = 'daw-mix' })
    local strips = {} ---@type table<string, DawMixer.Strip>
    local built_key = nil ---@type string?

    ---@param id string
    ---@param key string
    ---@param value Daw.Value
    local function mix (id, key, value)
      local song = session.song ()
      local s ---@type Daw.Song
      if id == 'master' then
        s = daw.song.set (song, {})
        s.master =
          { volume = tonumber (value) or 0, effects = song.master.effects }
      else
        s = daw.song.update_track (song, id, { [key] = value })
      end
      session.apply (
        s,
        { kind = 'mix', track = id, key = key, value = value },
        'mix:' .. id .. ':' .. key
      )
    end

    ---@param track Daw.Track?
    ---@return DawMixer.Strip
    local function strip (track)
      local id = track and track.id or 'master'
      local db = ui.div ({ class = 'daw-db' })
      local fader = ui.input ({
        type = 'range',
        class = 'daw-fader',
        title = 'Volume',
        attrs = { min = -60, max = 6, step = 0.1 },
      })
      fader:on ('input', function (ev)
        local v = tonumber (ev.value) or 0
        db:text (db_text (v))
        mix (id, 'volume', v)
        return nil
      end)
      fader:on ('change', function ()
        session.seal ()
        return nil
      end)
      fader:on ('dblclick', function ()
        fader:value ('0')
        db:text (db_text (0))
        mix (id, 'volume', 0)
        session.seal ()
        return nil
      end)
      local fills = { ui.div () } ---@type Proteus.El[]
      if not track then
        fills[2] = ui.div ()
      end
      local mid = ui.div ({ class = 'daw-strip-mid', fader })
      for _, fill in
        ipairs (fills --[[@as Proteus.El[] ]])
      do
        mid:append (ui.div ({ class = 'daw-meter-v', fill }))
      end
      ---@type DawMixer.Strip
      local s = { root = ui.div (), fader = fader, db = db, fills = fills }
      if track then
        local dev = 'Audio'
        if track.kind == 'instrument' then
          local spec = track.instrument
            and devices.get (track.instrument.device)
          dev = spec and spec.name or 'No instrument'
        end
        if #track.effects > 0 then
          dev = dev .. ' +' .. #track.effects
        end
        local pan = ui.input ({
          type = 'range',
          class = 'daw-pan',
          title = 'Pan. Double-click to centre.',
          attrs = { min = -1, max = 1, step = 0.01 },
        })
        s.pan = pan
        pan:on ('input', function (ev)
          mix (id, 'pan', tonumber (ev.value) or 0)
          return nil
        end)
        pan:on ('change', function ()
          session.seal ()
          return nil
        end)
        pan:on ('dblclick', function ()
          pan:value ('0')
          mix (id, 'pan', 0)
          session.seal ()
          return nil
        end)
        ---@param key 'mute'|'solo'
        ---@param label string
        ---@return Proteus.El
        local function toggle (key, label)
          return ui.button ({
            class = 'daw-hb ' .. (key == 'mute' and 'm' or 's'),
            text = label,
            title = key == 'mute' and 'Mute' or 'Solo',
            onclick = function ()
              local t = daw.song.track (session.song (), id)
              if t then
                mix (id, key, not t[key])
                session.seal ()
              end
              return 'stop'
            end,
          })
        end
        s.mute = toggle ('mute', 'M')
        s.solo = toggle ('solo', 'S')
        s.root = ui.div ({
          class = 'daw-strip',
          style = { ['--c'] = track.color },
          ui.div ({
            class = 'daw-strip-name',
            text = track.name,
            title = track.name,
          }),
          ui.div ({ class = 'daw-strip-dev', text = dev, title = dev }),
          pan,
          mid,
          db,
          ui.div ({ class = 'daw-strip-btns', s.mute, s.solo }),
          onmousedown = function ()
            session.select_track (id)
            return nil
          end,
        })
      else
        s.root = ui.div ({
          class = 'daw-strip master',
          ui.div ({ class = 'daw-strip-name', text = 'Master' }),
          ui.div ({
            class = 'daw-strip-dev',
            text = #session.song ().master.effects .. ' effects',
          }),
          mid,
          db,
        })
      end
      return s
    end

    ---@param song Daw.Song
    ---@return string
    local function structure (song)
      local parts = {} ---@type string[]
      for _, t in ipairs (song.tracks) do
        parts[#parts + 1] = table.concat ({
          t.id,
          t.name,
          t.color,
          t.instrument and t.instrument.device or '',
          #t.effects,
        }, ',')
      end
      parts[#parts + 1] = tostring (#song.master.effects)
      return table.concat (parts, ';')
    end

    local function sync ()
      local song = session.song ()
      local sel = session.selected_track ()
      for _, t in ipairs (song.tracks) do
        local s = strips[t.id]
        if s then
          if app.dom.focus_info ().handle ~= s.fader.id then
            s.fader:value (tostring (t.volume))
          end
          s.db:text (db_text (t.volume))
          if s.pan then
            s.pan:value (tostring (t.pan))
          end
          if s.mute then
            s.mute:class ('on', t.mute)
          end
          if s.solo then
            s.solo:class ('on', t.solo)
          end
          s.root:class ('sel', t.id == sel)
        end
      end
      local m = strips.master
      if m then
        m.fader:value (tostring (song.master.volume))
        m.db:text (db_text (song.master.volume))
      end
    end

    local function render ()
      local song = session.song ()
      local key = structure (song)
      if key ~= built_key then
        built_key = key
        root:clear ()
        strips = {}
        for _, t in ipairs (song.tracks) do
          local s = strip (t)
          strips[t.id] = s
          root:append (s.root)
        end
        local m = strip (nil)
        strips.master = m
        root:append (m.root)
      end
      sync ()
    end

    -- Meters: read about 15 times a second, only while the mixer shows.
    local function meter ()
      if root:rect ().h <= 0 then
        return
      end
      local levels = engine.levels ()
      for id, s in pairs (strips) do
        local values = id == 'master' and levels.master
          or { levels.tracks[id] or 0 }
        for i, fill in ipairs (s.fills) do
          local h = meter_height (tonumber (values[i]) or 0)
          fill:style ('height', string.format ('%.1f%%', h * 100))
          fill:class ('hot', h > 0.94)
          fill:class ('warm', h > 0.75 and h <= 0.94)
        end
      end
    end
    app.timer.every (66, meter)

    if windows then
      windows.add ({
        id = 'daw.mixer',
        title = 'Mixer',
        icon = 'sliders-vertical',
        key = 'f9',
        order = 4,
        x = 0,
        y = 0.5,
        w = 0.92,
        h = 0.5,
        content = root,
        on_show = render,
      })
    else
      views.add ('bottom', {
        id = 'daw.mixer',
        title = 'Mixer',
        icon = 'sliders-vertical',
        order = 2,
        content = root,
        on_show = render,
      })
    end

    app.on ('daw:changed', function (_, change)
      local c = change --[[@as Daw.Change]]
      if c.kind == 'mix' then
        sync ()
      else
        render ()
      end
    end)
    app.on ('daw:selection', sync)
    app.on ('daw:devices', function ()
      built_key = nil
      render ()
    end)
    render ()
  end,
}
