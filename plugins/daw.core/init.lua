-- daw.core: the pure logic of the DAW, shared with the other DAW plugins as the `daw`
-- service. It knows songs, notes, devices and time, and it draws nothing and makes no
-- sound. The tests load these modules straight from this folder.

local demo = require ('daw_demo') --[[@as Daw.DemoModule]]
local device = require ('daw_device') --[[@as Daw.DeviceModule]]
local file = require ('daw_file') --[[@as Daw.FileModule]]
local history = require ('daw_history') --[[@as Daw.HistoryModule]]
local notes = require ('daw_notes') --[[@as Daw.NotesModule]]
local resolve = require ('daw_resolve') --[[@as Daw.ResolveModule]]
local song = require ('daw_song') --[[@as Daw.SongModule]]
local steps = require ('daw_steps') --[[@as Daw.StepsModule]]
local time = require ('daw_time') --[[@as Daw.TimeModule]]

---@type Proteus.Plugin
return {
  name = 'DAW core',
  description = 'The logic behind the DAW: songs, notes, steps, devices, time and undo.',
  version = '1.1.0',
  requires = { proteus = '>=0.2.0', features = { 'permissions' } },
  permissions = {},
  activate = function (app)
    ---@type Daw.Core
    local core = {
      time = time,
      song = song,
      notes = notes,
      steps = steps,
      device = device,
      file = file,
      resolve = resolve,
      history = history,
      demo = demo,
    }
    app.provide ('daw', core)
  end,
}
