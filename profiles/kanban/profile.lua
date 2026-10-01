-- A kanban board, from proteus.kanban. That plugin is a Nodal graph, graphs/kanban.ndg,
-- built as an app. Open the graph in the editor or the nodal profile to see how it works.
-- Boards are saved as JSON files in data/kanban.
return {
  name = 'Kanban',
  description = 'Cards in columns. Drag them along as work moves.',
  version = '1.0.1',
  -- It runs plugins by the ids they took in Proteus 0.3.0.
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
    'proteus.kanban',
    'proteus.discord.rpc',
  },
  settings = {
    theme = 'daylight',
  },
}
