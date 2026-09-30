-- The DAW, laid out like FL Studio: a desktop of floating windows for the Channel Rack, the
-- Playlist, the piano roll, the mixer and each channel's settings. Every instrument and effect
-- is a plugin that registers a patch with daw.devices, and daw.engine plays those patches
-- through Web Audio in a web view. Songs are JSON files in songs/. The marketplace can add
-- device packs, such as chiptune.
return {
  name = 'DAW',
  description = 'Make music in floating windows, like FL Studio: a channel rack with steps, a playlist, a piano roll, a mixer, instruments and effects.',
  version = '1.2.0',
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
    'ui.windows',
    'daw.instruments',
    'daw.effects',
    -- The screens, each a window on the desktop, as in FL Studio.
    'daw.transport',
    'daw.channels',
    'daw.arrange',
    'daw.pianoroll',
    'daw.mixer',
    'daw.rack',
    'daw.browser',
    'daw.keyboard',
    'daw.midi',
    'discord.rpc',
  },
  settings = {
    theme = 'midnight',
    ['windows.title'] = 'Studio',
  },
}
