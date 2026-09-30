-- The DAW: songs of instrument tracks, a piano roll, a mixer and a rack of devices. Every
-- instrument and effect is a plugin that registers a patch with daw.devices, and daw.engine
-- plays those patches through Web Audio in a web view. Songs are JSON files in songs/.
-- The marketplace can add device packs, such as chiptune.
return {
  name = 'DAW',
  description = 'Make music: tracks, clips, a piano roll, a mixer, instruments and effects.',
  version = '1.0.0',
  plugins = {
    'theme.midnight',
    'theme.daylight',
    'theme.retro',
    'core.keys',
    'ui.menus',
    'ui.menubar',
    'ui.toolbar',
    'ui.statusbar',
    'ui.views',
    'ui.tabs',
    'ui.palette',
    'ui.notify',
    'ui.settings',
    'core.profiles',
    'marketplace',
    -- The model, the sound, and the devices.
    'daw.core',
    'daw.devices',
    'daw.session',
    'daw.engine',
    'daw.instruments',
    'daw.effects',
    -- The screens.
    'daw.transport',
    'daw.arrange',
    'daw.pianoroll',
    'daw.mixer',
    'daw.rack',
    'daw.browser',
    'daw.keyboard',
    'discord.rpc',
  },
  settings = {
    theme = 'midnight',
  },
}
