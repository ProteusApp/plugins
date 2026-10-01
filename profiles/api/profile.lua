-- An API client. Saved requests live as JSON files in data/proteus.api, so the editor can open
-- them too.
return {
  name = 'API Client',
  description = 'Send HTTP requests, save them, and read the answers.',
  version = '1.0.0',
  requires = { proteus = '>=0.3.0' },
  plugins = {
    'proteus.theme.daylight',
    'proteus.theme.midnight',
    'proteus.theme.retro',
    'proteus.core.keys',
    'proteus.ui.menus',
    'proteus.ui.toolbar',
    'proteus.ui.statusbar',
    'proteus.ui.views',
    'proteus.ui.palette',
    'proteus.ui.notify',
    'proteus.core.profiles',
    'proteus.api',
    'proteus.discord.rpc',
  },
  settings = {
    theme = 'midnight',
  },
}
