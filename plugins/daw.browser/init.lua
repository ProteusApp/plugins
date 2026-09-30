-- daw.browser: the left dock. It lists the songs in songs/, and every instrument and
-- effect the running plugins provide, with their presets. Click a song to open it. Click an
-- instrument to start a new track with it, and an effect to add it to the selected track.

-- lang=css
local CSS = [[
.daw-br {
  height: 100%;
  min-height: 0;
  overflow: auto;
  padding: 6px 0 12px;
  font-size: 12px;
  user-select: none;
}
.daw-br-head {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 10px 12px 4px;
  color: var(--fg-muted);
  font-size: 10px;
  text-transform: uppercase;
  letter-spacing: 0.05em;
}
.daw-br-head span {
  flex: 1;
}
.daw-br-head button {
  padding: 1px 6px;
  font-size: 11px;
}
.daw-br-item {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 5px 12px;
  cursor: pointer;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.daw-br-item:hover {
  background: var(--bg-hover);
}
.daw-br-item.active {
  background: var(--bg-active);
}
.daw-br-item .icon {
  flex: none;
  color: var(--fg-muted);
}
.daw-br-item small {
  margin-left: auto;
  color: var(--fg-faint);
}
.daw-br-preset {
  padding-left: 34px;
  color: var(--fg-muted);
}
.daw-br-cat {
  padding: 6px 12px 2px;
  color: var(--fg-faint);
  font-size: 10px;
}
]]

---@type Proteus.Plugin
return {
  name = 'DAW browser',
  description = 'Songs, instruments, effects and presets, one click away.',
  version = '1.0.0',
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
  optional = { 'ui.menus', 'ui.palette' },
  activate = function (app)
    local ui = app.use ('ui')
    local views = app.use ('views')
    local daw = app.use ('daw') --[[@as Daw.Core]]
    local devices = app.use ('daw.devices') --[[@as Daw.Devices]]
    local session = app.use ('daw.session') --[[@as Daw.Session]]
    local commands = app.use ('commands')
    local menus = app.try_use ('menus')
    local esc = app.util.escape
    ui.css (CSS)

    local open = app.store.get ('open', { presets = false }) --[[@as { presets: boolean }]]
    local root = ui.div ({ class = 'daw-br' })

    ---@param name string
    ---@return string
    local function icon (name)
      return app.util.icon (name, 14) or ''
    end

    ---@param text string
    ---@param button? string
    ---@param item? string
    ---@return string
    local function head (text, button, item)
      return '<div class="daw-br-head"><span>'
        .. esc (text)
        .. '</span>'
        .. (button and ('<button class="ui-button" data-item="' .. item .. '">' .. esc (
          button
        ) .. '</button>') or '')
        .. '</div>'
    end

    ---@param role Daw.Role
    ---@param out string[]
    local function device_list (role, out)
      local by_cat = {} ---@type table<string, Daw.DeviceSpec[]>
      local cats = {} ---@type string[]
      for _, spec in ipairs (devices.list (role)) do
        local cat = spec.category or 'Other'
        if not by_cat[cat] then
          by_cat[cat] = {}
          cats[#cats + 1] = cat
        end
        table.insert (by_cat[cat], spec)
      end
      for _, cat in ipairs (cats) do
        out[#out + 1] = '<div class="daw-br-cat">' .. esc (cat) .. '</div>'
        for _, spec in ipairs (by_cat[cat]) do
          out[#out + 1] = string.format (
            '<div class="daw-br-item" data-item="%s:%s" title="%s">%s%s<small>%s</small></div>',
            role,
            esc (spec.id),
            esc (spec.description or spec.name),
            icon (
              spec.icon
                or (role == 'instrument' and 'music' or 'sliders-horizontal')
            ),
            esc (spec.name),
            spec.owner
                and spec.owner ~= 'daw.instruments'
                and spec.owner ~= 'daw.effects'
                and esc (spec.owner)
              or ''
          )
          if open.presets then
            for i, p in ipairs (spec.presets or {}) do
              out[#out + 1] = string.format (
                '<div class="daw-br-item daw-br-preset" data-item="%s:%s:%d">%s</div>',
                role,
                esc (spec.id),
                i,
                esc (p.name)
              )
            end
          end
        end
      end
    end

    local function render ()
      local out = {} ---@type string[]
      out[#out + 1] = head ('Songs', 'New', 'new')
      local current = session.path ()
      for _, s in ipairs (session.list ()) do
        out[#out + 1] = string.format (
          '<div class="daw-br-item%s" data-item="song:%s">%s%s</div>',
          s.path == current and ' active' or '',
          esc (s.path),
          icon ('music'),
          esc (s.name)
        )
      end
      if not current then
        out[#out + 1] = '<div class="daw-br-item active" data-item="save">'
          .. icon ('save')
          .. esc (session.song ().name)
          .. ' <small>not saved</small></div>'
      end
      out[#out + 1] = head (
        'Instruments',
        open.presets and 'Hide presets' or 'Presets',
        'presets'
      )
      device_list ('instrument', out)
      out[#out + 1] = head ('Effects')
      device_list ('effect', out)
      root:html (table.concat (out))
    end

    ---@param item string
    ---@return Daw.DeviceSpec?, string?
    local function device_of (item)
      local _, id, n = item:match ('^(%a+):([^:]+):?(%d*)$')
      local spec = id and devices.get (id)
      if not spec then
        return nil, nil
      end
      local index = tonumber (n)
      local preset = index and spec.presets and spec.presets[index]
      return spec, preset and preset.name or nil
    end

    ---@param spec Daw.DeviceSpec
    ---@param preset? string
    local function new_track (spec, preset)
      local song = session.song ()
      local _, index = daw.song.track (song, session.selected_track () or '')
      local s, id = daw.song.add_track (song, {
        name = preset or spec.name,
        instrument = daw.device.ref (spec, preset),
      }, index and index + 1 or nil)
      session.apply (s, { kind = 'edit', label = 'Add track' })
      session.select_track (id)
    end

    ---@param spec Daw.DeviceSpec
    ---@param preset? string
    ---@param track_id string A track, or 'master'.
    local function add_effect (spec, preset, track_id)
      local s = daw.song.add_effect (
        session.song (),
        track_id,
        daw.device.ref (spec, preset)
      )
      session.apply (s, { kind = 'edit', label = 'Add effect' })
    end

    root:on ('click', function (ev)
      local item = ev.item or ''
      if item == 'new' then
        commands.run ('daw.new')
      elseif item == 'save' then
        commands.run ('daw.save')
      elseif item == 'presets' then
        open.presets = not open.presets
        app.store.set ('open', open)
        render ()
      elseif item:match ('^song:') then
        local path = item:sub (6)
        if path ~= session.path () then
          session.open (path)
        end
      elseif item:match ('^instrument:') then
        local spec, preset = device_of (item)
        if spec then
          new_track (spec, preset)
        end
      elseif item:match ('^effect:') then
        local spec, preset = device_of (item)
        if spec then
          add_effect (spec, preset, session.selected_track () or 'master')
        end
      end
      return nil
    end)

    if menus then
      menus.attach (root, function (ev)
        local item = ev.item or ''
        local spec, preset = device_of (item)
        if item:match ('^instrument:') and spec then
          local track =
            daw.song.track (session.song (), session.selected_track () or '')
          return {
            {
              label = 'New Track With It',
              icon = 'plus',
              run = function ()
                new_track (spec, preset)
              end,
            },
            {
              label = 'Put It on '
                .. (track and track.name or 'the Selected Track'),
              icon = 'replace',
              disabled = not track or track.kind ~= 'instrument',
              run = function ()
                if track then
                  local s = daw.song.set_instrument (
                    session.song (),
                    track.id,
                    daw.device.ref (spec, preset)
                  )
                  session.apply (
                    s,
                    { kind = 'edit', label = 'Change instrument' }
                  )
                end
              end,
            },
          }
        elseif item:match ('^effect:') and spec then
          return {
            {
              label = 'Add to the Selected Track',
              icon = 'plus',
              disabled = session.selected_track () == nil,
              run = function ()
                add_effect (spec, preset, session.selected_track () or 'master')
              end,
            },
            {
              label = 'Add to the Master',
              icon = 'plus',
              run = function ()
                add_effect (spec, preset, 'master')
              end,
            },
          }
        elseif item:match ('^song:') then
          local path = item:sub (6)
          return {
            {
              label = 'Open',
              icon = 'folder-open',
              run = function ()
                session.open (path)
              end,
            },
          }
        end
        return nil
      end)
    end

    views.add ('left', {
      id = 'daw.browser',
      title = 'Browser',
      icon = 'library',
      order = 1,
      content = root,
      on_show = render,
    })

    app.on ('daw:changed', function (_, change)
      local c = change --[[@as Daw.Change]]
      if c.kind == 'open' or c.kind == 'new' or c.label == 'Rename' then
        render ()
      end
    end)
    app.on ('daw:saved', render)
    app.on ('daw:devices', render)
    render ()
    -- The first time the DAW opens, the browser is the panel in front on the left.
    if not app.store.get ('shown') then
      app.store.set ('shown', true)
      views.show ('daw.browser')
    end
  end,
}
