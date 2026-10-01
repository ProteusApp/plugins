-- A Git client: changes, diffs, commits, branches and history for any folder with a repository.
return {
  name = 'Git',
  description = 'Stage, commit, branch and browse the history of a Git repository.',
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
    'proteus.git',
    'proteus.discord.rpc',
  },
  settings = {
    theme = 'midnight',
  },
}
