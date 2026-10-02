-- A log viewer. It follows a file or a running program and filters the lines as they arrive.
return {
  name = 'Logs',
  description = 'Follow a log file or a program, filter the lines, and spot errors.',
  version = '1.2.0',
  requires = { proteus = '>=0.3.1', features = { 'profile-extends' } },
  -- The themes, keys, menus, status bar, side panels, palette, messages, Settings and
  -- Profiles come from the app's shell, profiles/base/shell.lua.
  extends = 'shell',
  plugins = {
    'proteus.ui.toolbar',
    -- The marketplace, to install plugins from inside the app.
    'proteus.marketplace',
    'proteus.logs',
    'proteus.discord.rpc',
  },
  settings = {
    theme = 'midnight',
  },
}
