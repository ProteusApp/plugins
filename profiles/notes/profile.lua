-- A notes app built from the same plugins as the editor, plus proteus.notes. That plugin is a Nodal
-- graph, graphs/notes.ndg, built as an app. Open the graph in the editor to change it.
-- It leaves out the menu bar and all the developer tools.
return {
  name = 'Notes',
  description = 'Markdown notes, saved as files in data/notes.',
  version = '1.2.0',
  -- It runs plugins by the ids they took in Proteus 0.3.0.
  requires = { proteus = '>=0.3.1', features = { 'profile-extends' } },
  -- The themes, keys, menus, status bar, side panels, palette, messages, Settings and
  -- Profiles come from the app's shell, profiles/base/shell.lua.
  extends = 'shell',
  plugins = {
    'proteus.ui.toolbar',
    -- The marketplace, to install plugins from inside the app.
    'proteus.marketplace',
    'proteus.notes',
    'proteus.discord.rpc',
  },
  settings = {
    -- The app has no panels of its own, so the left edge shows the marketplace's icon
    -- instead of an empty sidebar.
    ['views.left_style'] = 'bar',
    theme = 'daylight',
  },
}
