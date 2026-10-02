-- A spreadsheet. Workbooks are saved as files in data/proteus.sheet. It has a menu bar and a
-- formatting toolbar of its own, so it leaves out the shared toolbar.
return {
  name = 'Sheet',
  description = 'A spreadsheet with formulas, charts and Excel files.',
  version = '1.1.0',
  requires = { proteus = '>=0.3.0', features = { 'profile-extends' } },
  -- The themes, keys, menus, status bar, side panels, palette, messages, Settings and
  -- Profiles come from the app's shell, profiles/base/shell.lua.
  extends = 'shell',
  plugins = {
    'proteus.ui.menubar',
    'proteus.sheet',
    'proteus.discord.rpc',
  },
  settings = {
    theme = 'daylight',
  },
}
