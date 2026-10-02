-- The Code Editor: a general editor for any project folder on disk. It opens a folder, edits
-- its files, searches them, runs a terminal in it, and commits to Git. The proteus.code.*
-- plugins make it work on a folder, and proteus.git becomes its Source Control panel. The
-- `editor` profile, the Plugin Editor that ships with Proteus, edits Proteus itself instead.
return {
  name = 'Code Editor',
  description = 'Open a project folder: edit, search, run a terminal, and commit to Git.',
  version = '1.1.1',
  requires = { proteus = '>=0.3.1', features = { 'profile-extends' } },
  -- The themes, keys, menus, status bar, side panels, palette, messages, Settings and
  -- Profiles come from the app's shell, profiles/base/shell.lua.
  extends = 'shell',
  plugins = {
    'proteus.ui.menubar',
    'proteus.ui.toolbar',
    'proteus.ui.tabs',
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
    -- The Problems panel, for what any language plugin finds.
    'proteus.tools.diagnostics',
    -- Lua, for the folder's own Proteus plugins and any other Lua code: the language server,
    -- StyLua and selene. Each one that is not installed downloads the first time a Lua file
    -- needs it, and each has a setting that switches it off.
    'proteus.lang.luals',
    'proteus.lang.stylua',
    'proteus.lang.selene',
    'proteus.discord.rpc',
  },
  -- Plugins switched on in the plugin manager or installed from the store stay on.
  extensible = true,
  settings = {
    theme = 'midnight',
    -- Both sidebars' panels show as a bar of icons along the window's edge.
    ['views.left_style'] = 'bar',
    ['views.right_style'] = 'bar',
    -- Prettier would reformat every file of a project that does not use it.
    ['editor.format_on_save'] = false,
  },
}
