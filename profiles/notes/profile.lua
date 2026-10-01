-- A notes app built from the same plugins as the editor, plus proteus.notes. That plugin is a Nodal
-- graph, graphs/notes.graph.json, built as an app. Open the graph in the editor to change it.
-- It leaves out the menu bar and all the developer tools.
return {
  name = 'Notes',
  description = 'Markdown notes, saved as files in data/notes.',
  version = '1.0.0',
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
    'proteus.notes',
    'proteus.discord.rpc',
  },
  settings = {
    theme = 'daylight',
  },
}
