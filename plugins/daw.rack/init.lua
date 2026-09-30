-- daw.rack: the devices of the selected track, or of the master, in the Channel settings
-- window, or in the right dock without floating windows. Each device is a card with its presets,
-- a bypass switch, and a control for every parameter the device declares. Nothing here knows
-- any device by name: the cards are built from the parameter lists that plugins register
-- with daw.devices.
--
-- Moving a control sends a `param` change, which the engine applies at once. The cards are
-- built again only when the devices themselves change.

-- lang=css
local CSS = [[
.daw-rack {
  height: 100%;
  min-height: 0;
  display: flex;
  flex-direction: column;
  background: var(--bg);
  font-size: 12px;
}
.daw-rack-head {
  flex: none;
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 6px 8px;
  border-bottom: 1px solid var(--border);
  background: var(--bg-alt);
}
.daw-rack-head .ui-button {
  padding: 2px 8px;
  font-size: 12px;
}
.daw-rack-head .on {
  color: var(--accent);
  border-color: var(--accent);
}
.daw-rack-title {
  flex: 1;
  font-weight: 600;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.daw-rack-list {
  flex: 1;
  min-height: 0;
  overflow: auto;
  padding: 8px;
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.daw-card {
  border: 1px solid var(--border);
  border-radius: var(--radius);
  background: var(--bg-alt);
}
.daw-card.off .daw-card-body {
  opacity: 0.45;
}
.daw-card.missing {
  border-color: var(--danger);
}
.daw-card-head {
  display: flex;
  align-items: center;
  gap: 4px;
  padding: 5px 6px;
  border-bottom: 1px solid var(--border);
}
.daw-card-name {
  flex: 1;
  min-width: 0;
  font-weight: 600;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.daw-card-head select {
  max-width: 120px;
  padding: 1px 4px;
  font-size: 11px;
}
.daw-icon-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 22px;
  height: 22px;
  padding: 0;
  border: 1px solid transparent;
  border-radius: 4px;
  background: transparent;
  color: var(--fg-muted);
  cursor: pointer;
}
.daw-icon-btn:hover {
  background: var(--bg-hover);
  color: var(--fg);
}
.daw-icon-btn.on {
  color: var(--success);
}
.daw-card-body {
  padding: 6px 8px 8px;
}
.daw-group {
  margin: 6px 0 2px;
  color: var(--fg-muted);
  font-size: 10px;
  text-transform: uppercase;
  letter-spacing: 0.05em;
}
.daw-param {
  display: grid;
  grid-template-columns: 78px 1fr 64px;
  align-items: center;
  gap: 6px;
  min-height: 22px;
}
.daw-param label {
  color: var(--fg-muted);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.daw-param input[type="range"] {
  width: 100%;
  margin: 0;
  accent-color: var(--accent);
}
.daw-param select {
  padding: 1px 4px;
  font-size: 11px;
}
.daw-param-value {
  text-align: right;
  font: 11px var(--font-mono);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.daw-rack-empty {
  padding: 16px;
  color: var(--fg-muted);
  text-align: center;
}
.daw-card-desc {
  color: var(--fg-muted);
  font-size: 11px;
  margin-bottom: 4px;
}
]]

local STEPS = 1000

---@type Proteus.Plugin
return {
  name = 'DAW device rack',
  description = 'The instrument and effects of the selected track, with every parameter.',
  version = '1.2.0',
  requires = { proteus = '>=0.2.0', features = { 'permissions' } },
  permissions = {},
  depends = {
    'lib.ui',
    'ui.views',
    'daw.core',
    'daw.devices',
    'daw.session',
    'core.commands',
  },
  optional = { 'ui.palette', 'ui.menus', 'daw.engine', 'ui.windows' },
  activate = function (app)
    local ui = app.use ('ui')
    local views = app.use ('views')
    local windows = app.try_use ('windows') --[[@as Proteus.Windows?]]
    local daw = app.use ('daw') --[[@as Daw.Core]]
    local devices = app.use ('daw.devices') --[[@as Daw.Devices]]
    local session = app.use ('daw.session') --[[@as Daw.Session]]
    local commands = app.use ('commands')
    local picker = app.try_use ('picker')
    local engine = app.try_use ('daw.engine') --[[@as Daw.Engine?]]
    ui.css (CSS)

    local show_master = false
    local built_key = nil ---@type string?
    ---Each control that shows a value, by device id and parameter key, so undo can set it.
    ---@type table<string, table<string, fun(v: Daw.Value)>>
    local setters = {}

    local title = ui.div ({ class = 'daw-rack-title' })
    local master_btn = ui.button ({
      'Master',
      icon = 'sliders-horizontal',
      variant = 'ghost',
      title = 'Show the effects on the master output',
      onclick = function ()
        show_master = not show_master
        built_key = nil
        app.emit ('daw:rack_redraw')
      end,
    })
    local list = ui.div ({ class = 'daw-rack-list' })
    local root = ui.div ({
      class = 'daw-rack',
      ui.div ({
        class = 'daw-rack-head',
        title,
        master_btn,
        ui.button ({
          'Effect',
          icon = 'plus',
          variant = 'ghost',
          title = 'Add an effect to the end of the chain',
          onclick = function ()
            commands.run ('daw.add_effect')
          end,
        }),
      }),
      list,
    })

    ---@return string owner A track id, or 'master'.
    ---@return Daw.Track?
    local function owner ()
      local song = session.song ()
      if show_master then
        return 'master', nil
      end
      local t = daw.song.track (song, session.selected_track () or '')
      if t then
        return t.id, t
      end
      return 'master', nil
    end

    -- Changing devices -------------------------------------------------------------------------

    ---@param ref Daw.DeviceRef
    ---@param key string
    ---@param value Daw.Value
    local function set_param (ref, key, value)
      local s = daw.song.set_param (session.song (), ref.id, key, value)
      session.apply (
        s,
        { kind = 'param', device = ref.id, key = key, value = value },
        'param:' .. ref.id .. ':' .. key
      )
    end

    ---@param ref Daw.DeviceRef
    ---@param spec Daw.DeviceSpec
    ---@param name string
    local function load_preset (ref, spec, name)
      local found = daw.device.preset (spec, name)
      session.apply (
        daw.song.set_preset (session.song (), ref.id, found and found.name),
        { kind = 'edit', label = 'Preset' }
      )
    end

    ---@param done fun(ref: Daw.DeviceRef)
    local function choose_effect (done)
      local fx = devices.list ('effect')
      if not picker then
        if fx[1] then
          done (daw.device.ref (fx[1]))
        end
        return
      end
      local items = {} ---@type Proteus.PickItem[]
      for _, spec in ipairs (fx) do
        items[#items + 1] = {
          label = spec.name,
          detail = spec.category,
          icon = spec.icon or 'sliders-horizontal',
          value = { spec = spec },
        }
        for _, p in ipairs (spec.presets or {}) do
          items[#items + 1] = {
            label = spec.name .. ': ' .. p.name,
            detail = spec.category,
            icon = spec.icon or 'sliders-horizontal',
            value = { spec = spec, preset = p.name },
          }
        end
      end
      picker.pick ({
        placeholder = 'Add an effect',
        items = items,
        on_pick = function (it)
          local v = it.value --[[@as { spec: Daw.DeviceSpec, preset?: string }]]
          done (daw.device.ref (v.spec, v.preset))
        end,
      })
    end

    local function add_effect ()
      local id = owner ()
      choose_effect (function (ref)
        local s = daw.song.add_effect (session.song (), id, ref)
        session.apply (s, { kind = 'edit', label = 'Add effect' })
      end)
    end

    -- Building the cards -----------------------------------------------------------------------

    ---@param ref Daw.DeviceRef
    ---@param spec Daw.DeviceSpec
    ---@param param Daw.ParamSpec
    ---@return Proteus.El
    local function control (ref, spec, param)
      local value_el = ui.div ({ class = 'daw-param-value' })
      local kind = param.kind or 'number'
      local input ---@type Proteus.El
      local set ---@type fun(v: Daw.Value)
      if kind == 'choice' then
        input = ui.h ('select', { class = 'ui-input' })
        for _, o in ipairs (param.options or {}) do
          input:append (
            ui.option ({ text = daw.device.format (param, o), value = o })
          )
        end
        input:on ('change', function (ev)
          set_param (ref, param.key, daw.device.clamp (param, ev.value))
          session.seal ()
          return nil
        end)
        set = function (v)
          input:value (tostring (v))
        end
      elseif kind == 'toggle' then
        input = ui.input ({ type = 'checkbox' })
        input:on ('change', function (ev)
          set_param (ref, param.key, ev.checked == true)
          value_el:text (daw.device.format (param, ev.checked == true))
          session.seal ()
          return nil
        end)
        set = function (v)
          input:checked (v == true)
          value_el:text (daw.device.format (param, v))
        end
      elseif kind == 'file' then
        -- The user picks the file in the system's dialog, and the engine keeps it. The song
        -- holds its id, and the card shows its name.
        input = ui.button ({
          'Choose...',
          variant = 'ghost',
          disabled = engine == nil,
          title = engine and 'Pick an audio file' or 'Needs daw.engine',
          onclick = function ()
            if not engine then
              return
            end
            engine.pick_audio (false, function (picked)
              if picked[1] then
                set_param (ref, param.key, picked[1].id)
                session.seal ()
                value_el:text (picked[1].name)
              end
            end)
          end,
        })
        set = function (v)
          local id = tostring (v or '')
          local info = engine and id ~= '' and engine.file (id)
          if info then
            value_el:text (info.name)
            value_el:attr ('title', info.failed or info.name)
          else
            value_el:text (id == '' and 'No file' or 'Missing file')
            value_el:attr (
              'title',
              id == '' and 'No file yet'
                or 'Pick the file again on this computer'
            )
          end
        end
      else
        input = ui.input ({
          type = 'range',
          attrs = { min = 0, max = STEPS, step = 1 },
        })
        input:on ('input', function (ev)
          local v =
            daw.device.from_unit (param, (tonumber (ev.value) or 0) / STEPS)
          value_el:text (daw.device.format (param, v))
          set_param (ref, param.key, v)
          return nil
        end)
        input:on ('change', function ()
          session.seal ()
          return nil
        end)
        input:on ('dblclick', function ()
          local v = param.default
          set_param (ref, param.key, v)
          session.seal ()
          input:value (
            tostring (
              math.floor (
                daw.device.to_unit (param, tonumber (v) or 0) * STEPS + 0.5
              )
            )
          )
          value_el:text (daw.device.format (param, v))
          return nil
        end)
        set = function (v)
          if app.dom.focus_info ().handle ~= input.id then
            input:value (
              tostring (
                math.floor (
                  daw.device.to_unit (param, tonumber (v) or 0) * STEPS + 0.5
                )
              )
            )
          end
          value_el:text (daw.device.format (param, v))
        end
      end
      setters[ref.id] = setters[ref.id] or {}
      setters[ref.id][param.key] = set
      set (daw.device.value (spec, ref, param.key))
      return ui.div ({
        class = 'daw-param',
        title = param.label
          .. (kind == 'number' and '. Double-click to reset.' or ''),
        ui.label ({ text = param.label }),
        input,
        value_el,
      })
    end

    ---@param ref Daw.DeviceRef
    ---@param role Daw.Role
    ---@param index integer
    ---@return Proteus.El
    local function card (ref, role, index)
      local spec = devices.get (ref.device)
      ---@param icon string
      ---@param tip string
      ---@param run fun()
      ---@param extra? string
      ---@return Proteus.El
      local function icon_btn (icon, tip, run, extra)
        return ui.button ({
          class = 'daw-icon-btn ' .. (extra or ''),
          icon = icon,
          title = tip,
          onclick = function ()
            run ()
            return 'stop'
          end,
        })
      end
      local head = ui.div ({ class = 'daw-card-head' })
      if spec and spec.icon then
        head:append (ui.icon (spec.icon, 14))
      end
      head:append (ui.div ({
        class = 'daw-card-name',
        text = spec and spec.name or (ref.device .. ' (missing)'),
      }))
      if spec and spec.presets and #spec.presets > 0 then
        local presets =
          ui.h ('select', { class = 'ui-input', title = 'Presets' })
        presets:append (ui.option ({ text = 'Default', value = '' }))
        for _, p in ipairs (spec.presets) do
          presets:append (ui.option ({ text = p.name, value = p.name }))
        end
        presets:value (ref.preset or '')
        presets:on ('change', function (ev)
          load_preset (ref, spec, ev.value or '')
          return nil
        end)
        head:append (presets)
      end
      if role == 'effect' then
        head:append (
          icon_btn ('power', ref.bypass and 'Turn on' or 'Turn off', function ()
            session.apply (
              daw.song.update_device (
                session.song (),
                ref.id,
                { bypass = not ref.bypass }
              ),
              { kind = 'edit', label = 'Bypass' }
            )
          end, ref.bypass and '' or 'on')
        )
        head:append (icon_btn ('chevron-up', 'Move up', function ()
          session.apply (
            daw.song.move_effect (session.song (), ref.id, index - 1),
            { kind = 'edit', label = 'Move effect' }
          )
        end))
        head:append (icon_btn ('chevron-down', 'Move down', function ()
          session.apply (
            daw.song.move_effect (session.song (), ref.id, index + 1),
            { kind = 'edit', label = 'Move effect' }
          )
        end))
        head:append (icon_btn ('x', 'Remove', function ()
          session.apply (
            daw.song.remove_device (session.song (), ref.id),
            { kind = 'edit', label = 'Remove effect' }
          )
        end))
      else
        head:append (icon_btn ('replace', 'Change the instrument', function ()
          commands.run ('daw.change_instrument')
        end))
      end
      local body = ui.div ({ class = 'daw-card-body' })
      if not spec then
        body:append (ui.div ({
          class = 'daw-card-desc',
          text = 'No running plugin provides this device. Its settings stay in the song.',
        }))
      else
        if spec.description then
          body:append (
            ui.div ({ class = 'daw-card-desc', text = spec.description })
          )
        end
        local group = nil ---@type string?
        for _, param in ipairs (spec.params) do
          if param.group and param.group ~= group then
            group = param.group
            body:append (ui.div ({ class = 'daw-group', text = group }))
          end
          body:append (control (ref, spec, param))
        end
      end
      local classes = { 'daw-card' }
      if ref.bypass then
        classes[#classes + 1] = 'off'
      end
      if not spec then
        classes[#classes + 1] = 'missing'
      end
      return ui.div ({ class = classes, head, body })
    end

    ---@param refs Daw.DeviceRef[]
    ---@return string
    local function refs_key (refs)
      local parts = {} ---@type string[]
      for _, r in ipairs (refs) do
        parts[#parts + 1] = table.concat (
          { r.id, r.device, tostring (r.bypass), r.preset or '' },
          ','
        )
      end
      return table.concat (parts, ';')
    end

    local function render ()
      local id, track = owner ()
      local song = session.song ()
      if windows then
        windows.set_title (
          'daw.rack',
          (track and track.name or 'Master') .. ' - Channel settings'
        )
      end
      master_btn:class ('on', id == 'master')
      local chain = track and track.effects or song.master.effects
      local key = id
        .. '|'
        .. (track and track.instrument and refs_key ({ track.instrument }) or '')
        .. '|'
        .. refs_key (chain)
      if key == built_key then
        -- The same devices: only set each control to the song's value.
        local all = { track and track.instrument }
        for _, r in ipairs (chain) do
          all[#all + 1] = r
        end
        for _, r in ipairs (all) do
          local spec = r and devices.get (r.device)
          if r and spec and setters[r.id] then
            for k, set in pairs (setters[r.id]) do
              set (daw.device.value (spec, r, k))
            end
          end
        end
        return
      end
      built_key = key
      setters = {}
      list:clear ()
      title:text (track and track.name or 'Master')
      if track and track.kind == 'instrument' then
        if track.instrument then
          list:append (card (track.instrument, 'instrument', 0))
        else
          list:append (ui.button ({
            'Choose an instrument',
            icon = 'piano',
            onclick = function ()
              commands.run ('daw.change_instrument')
            end,
          }))
        end
      end
      for i, ref in ipairs (chain) do
        list:append (card (ref, 'effect', i))
      end
      if #chain == 0 then
        list:append (ui.div ({
          class = 'daw-rack-empty',
          text = 'No effects yet. Add one with + Effect.',
        }))
      end
    end

    commands.register ({
      id = 'daw.add_effect',
      category = 'DAW',
      title = 'Add Effect',
      icon = 'plus',
      menu = 'Track',
      run = add_effect,
    })
    commands.register ({
      id = 'daw.change_instrument',
      category = 'DAW',
      title = 'Change Instrument',
      icon = 'piano',
      menu = 'Track',
      when = function ()
        local _, t = owner ()
        return t ~= nil and t.kind == 'instrument'
      end,
      run = function ()
        local id, t = owner ()
        if not t or not picker then
          return
        end
        local items = {} ---@type Proteus.PickItem[]
        for _, spec in ipairs (devices.list ('instrument')) do
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
          placeholder = 'Pick an instrument for ' .. t.name,
          items = items,
          on_pick = function (it)
            local v = it.value --[[@as { spec: Daw.DeviceSpec, preset?: string }]]
            local s = daw.song.set_instrument (
              session.song (),
              id,
              daw.device.ref (v.spec, v.preset)
            )
            session.apply (s, { kind = 'edit', label = 'Change instrument' })
          end,
        })
      end,
    })

    if windows then
      -- FL Studio calls the window of one channel's instrument and effects its settings.
      windows.add ({
        category = 'DAW',
        id = 'daw.rack',
        title = 'Channel settings',
        icon = 'sliders-horizontal',
        order = 5,
        x = 0.6,
        y = 0.03,
        w = 380,
        h = 0.85,
        min_w = 300,
        content = root,
        on_show = render,
      })
    else
      views.add ('right', {
        id = 'daw.rack',
        title = 'Devices',
        icon = 'sliders-horizontal',
        order = 1,
        content = root,
      })
    end

    app.on ('daw:changed', function (_, change)
      local c = change --[[@as Daw.Change]]
      if c.kind ~= 'param' and c.kind ~= 'mix' then
        render ()
      end
    end)
    app.on ('daw:selection', function ()
      show_master = false
      render ()
    end)
    app.on ('daw:devices', function ()
      built_key = nil
      render ()
    end)
    app.on ('daw:rack_redraw', render)
    render ()
  end,
}
