-- wam.basics: two Web Audio Modules for the DAW. PolySynth is an instrument, and Echo is a
-- stereo delay. Each is a module in wam/, built on the Web Audio Modules SDK, which wam/sdk/
-- holds as its authors publish it (see vendor.json). The folder is exported, so the DAW's
-- engine page can load the modules, and this plugin only tells the DAW they are there.

---@type Proteus.Plugin
return {
  name = 'WAM Basics',
  description = 'Two Web Audio Modules for the DAW: PolySynth, a polyphonic synth, and Echo, a stereo delay.',
  version = '1.0.0',
  requires = {
    proteus = '>=0.2.0',
    features = { 'permissions', 'webview-files' },
  },
  permissions = {},
  exports = { 'wam' },
  depends = { 'daw.devices' },
  activate = function (app)
    local devices = app.use ('daw.devices') --[[@as Daw.Devices]]
    devices.register ({
      id = 'wam.polysynth',
      name = 'PolySynth',
      role = 'instrument',
      category = 'Web Audio Modules',
      icon = 'audio-waveform',
      description = 'Two detuned oscillators through a resonant low-pass filter, as a Web Audio Module.',
      wam = { path = 'wam/polysynth/index.js' },
      -- The module brings its sound and its parameters, so there is no patch.
      params = {},
      patch = {},
    })
    devices.register ({
      id = 'wam.echo',
      name = 'Echo',
      role = 'effect',
      category = 'Web Audio Modules',
      icon = 'repeat',
      description = 'A stereo delay whose repeats bounce between the sides, as a Web Audio Module.',
      wam = { path = 'wam/echo/index.js' },
      params = {},
      patch = {},
    })
  end,
}
