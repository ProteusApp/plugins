-- A kanban board, from proteus.kanban. That plugin is a Nodal graph, graphs/kanban.ndg,
-- built as an app. Open the graph in the editor or the nodal profile to see how it works.
-- Boards are saved as JSON files in data/kanban.
return {
  name = 'Kanban',
  description = 'Cards in columns. Drag them along as work moves.',
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
    'proteus.kanban',
    'proteus.discord.rpc',
  },
  settings = {
    -- The app has no panels of its own, so the left edge shows the marketplace's icon
    -- instead of an empty sidebar.
    ['views.left_style'] = 'bar',
    theme = 'daylight',
  },
}
