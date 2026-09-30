-- daw.instruments: the builtin instruments. The patches live in daw_instruments.lua as
-- data, where the tests check them, and this plugin only registers them. A plugin that adds
-- instruments of its own works the same way.

local list = require ('daw_instruments') --[[@as Daw.DeviceSpec[] ]]

---@type Proteus.Plugin
return {
  name = 'DAW instruments',
  description = 'Synth, FM Keys and Drum Kit for the DAW.',
  version = '1.0.0',
  requires = { proteus = '>=0.2.0', features = { 'permissions' } },
  permissions = {},
  depends = { 'daw.devices' },
  activate = function (app)
    local devices = app.use ('daw.devices') --[[@as Daw.Devices]]
    for _, spec in ipairs (list) do
      devices.register (spec)
    end
  end,
}
