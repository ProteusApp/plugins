-- A to-do list with no window layout at all. proteus.todo draws the whole window itself.
return {
  name = 'Todo',
  description = 'A one-screen to-do list with no menus or toolbar.',
  version = '1.0.0',
  requires = { proteus = '>=0.3.0' },
  plugins = {
    'proteus.theme.retro',
    'proteus.theme.midnight',
    'proteus.theme.daylight',
    'proteus.ui.menus',
    'proteus.todo',
    'proteus.discord.rpc',
  },
  settings = {
    theme = 'retro',
  },
}
