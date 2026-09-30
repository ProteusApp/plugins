-- daw.native: the CLAP and VST3 plugins installed on this computer, as DAW devices. It asks the
-- app for the plugins it found, and registers each as an instrument or an effect that names
-- its plugin by reference. The DAW's rack, browser and songs then use it like any device.
--
-- Only the native sound engine plays them: set daw.engine to native. daw.engine opens that
-- engine with the rights this plugin lends it (`app.audio.lend`), so the permission and the
-- user's answers belong to this plugin, and the rest of the DAW needs neither. The app never tells this plugin where a
-- binary is, and asks the user the first time a song loads each one.

---A device id for a plugin reference: letters, digits, dots and dashes.
---@param ref string
---@return string
local function device_id (ref)
  return 'native.' .. ref:gsub ('[^%w.-]', '.')
end

---@type Proteus.Plugin
return {
  name = 'Native plugins',
  description = 'The CLAP and VST3 plugins installed on this computer, as instruments and effects for the DAW.',
  version = '1.0.0',
  requires = {
    proteus = '>=0.2.0',
    features = { 'permissions', 'native-audio' },
  },
  permissions = { 'native-plugins' },
  depends = { 'daw.core', 'daw.devices', 'core.commands' },
  optional = { 'ui.notify' },
  activate = function (app)
    local daw = app.use ('daw') --[[@as Daw.Core]]
    local devices = app.use ('daw.devices') --[[@as Daw.Devices]]
    local commands = app.use ('commands')
    local notify = app.try_use ('notify')

    ---@param list Proteus.NativePlugin[]
    ---@return integer
    local function register (list)
      local count = 0
      for _, p in ipairs (list) do
        local ok, err = pcall (devices.register, {
          id = device_id (p.ref),
          name = p.name,
          role = p.role,
          description = (p.vendor ~= '' and (p.vendor .. ', ') or '')
            .. (p.format == 'vst3' and 'VST3' or 'CLAP')
            .. ' plugin',
          icon = p.role == 'instrument' and 'piano' or 'audio-waveform',
          category = p.format == 'vst3' and 'VST3' or 'CLAP',
          params = daw.device.from_native (p.params),
          patch = {},
          native = { plugin = p.ref },
        })
        if ok then
          count = count + 1
        else
          app.warn (p.name .. ': ' .. tostring (err))
        end
      end
      return count
    end

    app.audio.plugins (register)

    -- daw.engine opens the native engine, and keeps its own files. This plugin lends it the
    -- right to load native plugins, which works for daw.engine alone.
    local token = app.audio.lend ('daw.engine')
    app.provide ('daw.native', {
      lend = function ()
        return token
      end,
    })

    commands.register ({
      id = 'native.rescan',
      category = 'DAW',
      title = 'Look for Native Plugins',
      icon = 'search',
      run = function ()
        if notify then
          notify.info ('Looking for CLAP and VST3 plugins...')
        end
        app.audio.plugins (function (list)
          local count = register (list)
          if notify then
            notify.success (
              string.format (
                'Found %d native plugin%s.',
                count,
                count == 1 and '' or 's'
              )
            )
          end
        end, { rescan = true })
      end,
    })
  end,
}
