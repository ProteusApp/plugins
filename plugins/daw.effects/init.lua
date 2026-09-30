-- daw.effects: the builtin effects. The patches live in daw_effects.lua as data, where the
-- tests check them, and this plugin only registers them.

local list = require ('daw_effects') --[[@as Daw.DeviceSpec[] ]]

---@type Proteus.Plugin
return {
  name = 'DAW effects',
  description = 'EQ, filter, delay, reverb, compressor, drive, chorus and utility for the DAW.',
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
