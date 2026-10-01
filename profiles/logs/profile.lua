-- A log viewer. It follows a file or a running program and filters the lines as they arrive.
return {
  name = 'Logs',
  description = 'Follow a log file or a program, filter the lines, and spot errors.',
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
    'proteus.logs',
    'proteus.discord.rpc',
  },
  settings = {
    theme = 'midnight',
  },
}
