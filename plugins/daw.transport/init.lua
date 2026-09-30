-- daw.transport: the controls along the toolbar. Play, stop, record, loop and the
-- metronome, the position as bars and as a clock, the tempo and the time signature. Every
-- control is also a command, so it has a key and a place in the palette.

-- lang=css
local CSS = [[
.daw-transport {
  display: flex;
  align-items: center;
  gap: 4px;
  padding: 0 6px;
}
.daw-tbtn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 28px;
  height: 26px;
  border: 1px solid transparent;
  border-radius: var(--radius);
  background: transparent;
  color: var(--fg);
  cursor: pointer;
}
.daw-tbtn:hover {
  background: var(--bg-hover);
}
.daw-tbtn.on {
  color: var(--accent);
  border-color: var(--accent);
}
.daw-tbtn.rec.on {
  color: var(--danger);
  border-color: var(--danger);
}
.daw-tbtn.play.on {
  color: var(--success);
  border-color: var(--success);
}
.daw-pos {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  min-width: 92px;
  padding: 1px 8px;
  border-radius: var(--radius);
  background: var(--bg-alt);
  font-family: var(--font-mono);
  font-variant-numeric: tabular-nums;
  line-height: 1.1;
  cursor: pointer;
}
.daw-pos-bars {
  font-size: 14px;
}
.daw-pos-clock {
  font-size: 10px;
  color: var(--fg-muted);
}
.daw-field {
  display: flex;
  align-items: center;
  gap: 4px;
  font-size: 11px;
  color: var(--fg-muted);
}
.daw-field input,
.daw-field select {
  width: 56px;
  padding: 2px 4px;
  font-family: var(--font-mono);
}
.daw-field select {
  width: auto;
}
.daw-sep {
  width: 1px;
  height: 20px;
  margin: 0 4px;
  background: var(--border);
}
]]

---@type Proteus.Plugin
return {
  name = 'DAW transport',
  description = 'Play, stop, record, loop, the metronome, the position and the tempo.',
  version = '1.0.0',
  requires = { proteus = '>=0.2.0', features = { 'permissions' } },
  permissions = {},
  depends = {
    'lib.ui',
    'daw.core',
    'daw.session',
    'daw.engine',
    'core.commands',
  },
  optional = { 'ui.toolbar', 'ui.statusbar', 'core.keys', 'ui.palette' },
  activate = function (app)
    local ui = app.use ('ui')
    local daw = app.use ('daw') --[[@as Daw.Core]]
    local session = app.use ('daw.session') --[[@as Daw.Session]]
    local engine = app.use ('daw.engine') --[[@as Daw.Engine]]
    local commands = app.use ('commands')
    local toolbar = app.try_use ('toolbar')
    local picker = app.try_use ('picker')
    ui.css (CSS)

    ---@return boolean
    local function free ()
      return not app.dom.focus_info ().editable
    end

    local function toggle_loop ()
      local song = session.song ()
      session.apply (
        daw.song.set_loop (song, { on = not song.loop.on }),
        { kind = 'edit', label = 'Loop' }
      )
    end

    local function record ()
      if engine.recording () then
        engine.set_recording (false)
        return
      end
      engine.set_recording (true)
      if not engine.playing () then
        -- Recording starts a bar early, so there is time to come in.
        local bar = daw.song.beats_per_bar (session.song ())
        local from = math.max (0, engine.position () - bar)
        engine.play (from)
      end
    end

    commands.register ({
      id = 'daw.play',
      category = 'DAW',
      title = 'Play or Stop',
      key = 'space',
      icon = 'play',
      menu = 'Transport',
      when = free,
      run = function ()
        engine.toggle ()
      end,
    })
    commands.register ({
      id = 'daw.pause',
      category = 'DAW',
      title = 'Pause Here',
      key = 'shift+space',
      icon = 'pause',
      menu = 'Transport',
      when = free,
      run = function ()
        if engine.playing () then
          engine.pause ()
        else
          engine.play ()
        end
      end,
    })
    commands.register ({
      id = 'daw.home',
      category = 'DAW',
      title = 'Go to Start',
      key = 'home',
      icon = 'skip-back',
      menu = 'Transport',
      when = free,
      run = function ()
        local song = session.song ()
        engine.seek (song.loop.on and song.loop.start or 0)
      end,
    })
    commands.register ({
      id = 'daw.record',
      category = 'DAW',
      title = 'Record',
      key = 'ctrl+r',
      icon = 'circle',
      menu = 'Transport',
      run = record,
    })
    commands.register ({
      id = 'daw.loop',
      category = 'DAW',
      title = 'Loop On or Off',
      -- The loop bar on the arrangement's ruler runs it too.
      shared = true,
      key = 'ctrl+l',
      icon = 'repeat',
      menu = 'Transport',
      run = toggle_loop,
    })
    commands.register ({
      id = 'daw.metronome',
      category = 'DAW',
      title = 'Metronome On or Off',
      key = 'ctrl+m',
      icon = 'timer',
      menu = 'Transport',
      run = function ()
        engine.set_metronome (not engine.metronome ())
      end,
    })
    commands.register ({
      id = 'daw.tempo',
      category = 'DAW',
      title = 'Set Tempo',
      icon = 'gauge',
      run = function ()
        if not picker then
          return
        end
        picker.input ({
          prompt = 'Beats per minute',
          value = tostring (session.song ().tempo),
          validate = function (text)
            local n = tonumber (text)
            if not n or n < 20 or n > 400 then
              return 'A number from 20 to 400'
            end
            return nil
          end,
          on_submit = function (text)
            session.apply (
              daw.song.set (session.song (), { tempo = tonumber (text) }),
              { kind = 'edit', label = 'Tempo' }
            )
          end,
        })
      end,
    })

    if not toolbar then
      return
    end

    -- The toolbar controls -----------------------------------------------------------------------

    ---@param icon string
    ---@param title string
    ---@param command string
    ---@param extra? string
    ---@return Proteus.El
    local function button (icon, title, command, extra)
      return ui.button ({
        class = 'daw-tbtn ' .. (extra or ''),
        title = title,
        icon = icon,
        onclick = function ()
          commands.run (command)
        end,
      })
    end

    local play_btn = button ('play', 'Play or stop (Space)', 'daw.play', 'play')
    local stop_btn = ui.button ({
      class = 'daw-tbtn',
      title = 'Stop and go back',
      icon = 'square',
      onclick = function ()
        if engine.playing () then
          engine.stop ()
        else
          commands.run ('daw.home')
        end
      end,
    })
    local rec_btn = button ('circle', 'Record (Ctrl+R)', 'daw.record', 'rec')
    local loop_btn = button ('repeat', 'Loop (Ctrl+L)', 'daw.loop')
    local click_btn = button ('timer', 'Metronome (Ctrl+M)', 'daw.metronome')

    local bars = ui.div ({ class = 'daw-pos-bars', text = '1.1.1' })
    local clock = ui.div ({ class = 'daw-pos-clock', text = '0:00.000' })
    local pos = ui.div ({
      class = 'daw-pos',
      title = 'Click to go to the start',
      bars,
      clock,
      onclick = function ()
        commands.run ('daw.home')
      end,
    })

    local tempo = ui.input ({
      type = 'number',
      title = 'Tempo in beats per minute',
      attrs = { min = 20, max = 400, step = 1 },
      onchange = function (ev)
        local n = tonumber (ev.value)
        if n then
          session.apply (
            daw.song.set (session.song (), { tempo = n }),
            { kind = 'edit', label = 'Tempo' }
          )
        end
      end,
    })
    tempo:on ('keydown', function (ev)
      if ev.key == 'Enter' or ev.key == 'Escape' then
        tempo:blur ()
      end
      return nil
    end)

    local sig = ui.h ('select', {
      title = 'Beats per bar',
      class = 'ui-input',
      onchange = function (ev)
        local n = tonumber (ev.value)
        if n then
          local song = session.song ()
          session.apply (
            daw.song.set (song, { signature = { n, song.signature[2] or 4 } }),
            { kind = 'edit', label = 'Time signature' }
          )
        end
      end,
    })
    for _, n in ipairs ({ 2, 3, 4, 5, 6, 7 }) do
      sig:append (ui.option ({ text = n .. '/4', value = n }))
    end

    local root = ui.div ({
      class = 'daw-transport',
      stop_btn,
      play_btn,
      rec_btn,
      ui.div ({ class = 'daw-sep' }),
      loop_btn,
      click_btn,
      ui.div ({ class = 'daw-sep' }),
      pos,
      ui.div ({ class = 'daw-sep' }),
      ui.label ({ class = 'daw-field', text = 'BPM', tempo }),
      ui.label ({ class = 'daw-field', sig }),
    })
    toolbar.add (root, { align = 'left', order = 1 })

    ---@param beat number
    local function show_position (beat)
      local song = session.song ()
      bars:text (daw.time.format (beat, daw.song.beats_per_bar (song)))
      clock:text (daw.time.format_clock (daw.time.seconds (beat, song.tempo)))
    end

    local function show_song ()
      local song = session.song ()
      loop_btn:class ('on', song.loop.on)
      if app.dom.focus_info ().handle ~= tempo.id then
        tempo:value (tostring (song.tempo))
      end
      sig:value (tostring (daw.song.beats_per_bar (song)))
    end

    app.on ('daw:changed', show_song)
    app.on ('daw:tick', show_position)
    app.on ('daw:transport', function (playing)
      play_btn:class ('on', playing == true)
    end)
    app.on ('daw:recording', function (on)
      rec_btn:class ('on', on == true)
    end)
    app.on ('daw:metronome', function (on)
      click_btn:class ('on', on == true)
    end)
    click_btn:class ('on', engine.metronome ())
    show_song ()
    show_position (engine.position ())
  end,
}
