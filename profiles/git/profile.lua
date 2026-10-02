-- A Git client: changes, diffs, commits, branches and history for any folder with a repository.
return {
  name = 'Git',
  description = 'Stage, commit, branch and browse the history of a Git repository.',
  version = '1.2.0',
  requires = { proteus = '>=0.3.1', features = { 'profile-extends' } },
  -- The themes, keys, menus, status bar, side panels, palette, messages, Settings and
  -- Profiles come from the app's shell, profiles/base/shell.lua.
  extends = 'shell',
  plugins = {
    'proteus.ui.toolbar',
    -- The marketplace, to install plugins from inside the app.
    'proteus.marketplace',
    'proteus.git',
    'proteus.discord.rpc',
  },
  settings = {
    theme = 'midnight',
  },
}
