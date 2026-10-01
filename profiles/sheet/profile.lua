-- A spreadsheet. Workbooks are saved as files in data/proteus.sheet. It has a menu bar and a
-- formatting toolbar of its own, so it leaves out the shared toolbar.
return {
  name = 'Sheet',
  description = 'A spreadsheet with formulas, charts and Excel files.',
  version = '1.0.0',
  requires = { proteus = '>=0.3.0' },
  plugins = {
    'proteus.theme.daylight',
    'proteus.theme.midnight',
    'proteus.theme.retro',
    'proteus.core.keys',
    'proteus.ui.menus',
    'proteus.ui.menubar',
    'proteus.ui.statusbar',
    'proteus.ui.views',
    'proteus.ui.palette',
    'proteus.ui.notify',
    'proteus.core.profiles',
    'proteus.sheet',
    'proteus.discord.rpc',
  },
  settings = {
    theme = 'daylight',
  },
}
