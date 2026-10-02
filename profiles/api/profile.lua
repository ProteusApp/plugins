-- An API client. Saved requests live as JSON files in data/proteus.api, so the editor can open
-- them too.
return {
  name = 'API Client',
  description = 'Send HTTP requests, save them, and read the answers.',
  version = '1.1.0',
  requires = { proteus = '>=0.3.0', features = { 'profile-extends' } },
  -- The themes, keys, menus, status bar, side panels, palette, messages, Settings and
  -- Profiles come from the app's shell, profiles/base/shell.lua.
  extends = 'shell',
  plugins = {
    'proteus.ui.toolbar',
    'proteus.api',
    'proteus.discord.rpc',
  },
  settings = {
    theme = 'midnight',
  },
}
