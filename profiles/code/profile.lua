-- The Code Editor: a general editor for any project folder on disk. It opens a folder, edits
-- its files, searches them, runs a terminal in it, and commits to Git. The proteus.code.*
-- plugins make it work on a folder, and proteus.git becomes its Source Control panel. The
-- `editor` profile, the Plugin Editor that ships with Proteus, edits Proteus itself instead.
return {
  name = 'Code Editor',
  description = 'Open a project folder: edit, search, run a terminal, and commit to Git.',
  version = '1.0.0',
  requires = { proteus = '>=0.3.0' },
  plugins = {
    'proteus.theme.midnight',
    'proteus.theme.daylight',
    'proteus.theme.retro',
    'proteus.core.keys',
    'proteus.ui.menus',
    'proteus.ui.menubar',
    'proteus.ui.toolbar',
    'proteus.ui.statusbar',
    'proteus.ui.views',
    'proteus.ui.tabs',
    'proteus.ui.palette',
    'proteus.ui.notify',
    'proteus.ui.settings',
    'proteus.core.profiles',
    -- The marketplace: plugins and profiles, built-in, local, this folder's and community.
    'proteus.marketplace',
    'proteus.core.files',
    -- The folder, and everything that works on it.
    'proteus.code.project',
    'proteus.editor.core',
    'proteus.code.explorer',
    'proteus.code.search',
    'proteus.terminal',
    'proteus.git',
    'proteus.code.welcome',
    -- Proteus plugins that belong to the folder, built in its .proteus/plugins.
    'proteus.code.plugins',
    -- Prettier runs inside the app, so CSS, JSON, Markdown, HTML and JS format anywhere.
    'proteus.tools.registry',
    'proteus.lang.prettier',
    'proteus.discord.rpc',
  },
  -- Plugins switched on in the plugin manager or installed from the store stay on.
  extensible = true,
  settings = {
    theme = 'midnight',
    -- The left sidebar's panels show as a bar of icons along the window's edge.
    ['views.left_style'] = 'bar',
    -- Prettier would reformat every file of a project that does not use it.
    ['editor.format_on_save'] = false,
  },
}
