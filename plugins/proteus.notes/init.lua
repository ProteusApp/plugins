-- Built by Nodal from graphs/notes.ndg. Nodal writes this file, so change the graph instead.
-- It runs the graph beside it with the Nodal runtime, as the Nodal preview does.
-- Placement: app

-- Plugin id: proteus.notes
local NAME = 'Notes'
local GRAPH_FILE = 'notes.ndg'

---@type Proteus.Plugin
return {
  name = NAME,
  description = 'Markdown notes in data/notes. Built with Nodal from graphs/notes.ndg.',
  version = '1.2.1',
  depends = { 'proteus.lib.ui', 'proteus.nodal.app' },
  permissions = { 'workspace' },
  requires = { proteus = '>=0.3.0', features = { 'permissions' } },
  optional = {
    'proteus.ui.notify',
    'proteus.ui.statusbar',
    'proteus.ui.shell',
    'proteus.core.commands',
    'proteus.core.settings',
    'proteus.core.themes',
    'proteus.ui.menus',
  },
  activate = function (app)
    local graph = app.plugin.read (GRAPH_FILE)
    if not graph then
      error ('the graph ' .. GRAPH_FILE .. ' is missing')
    end
    local handle, refusal =
      app.use ('nodal.app').mount_text (graph, { status_bar = true })
    if not handle then
      error ('the graph did not load: ' .. tostring (refusal and refusal.code))
    end
    app.dispose (handle.stop)
    local shell = app.try_use ('shell')
    if shell then
      shell.mount ('main', handle.el)
    else
      app.use ('ui').mount (handle.el)
    end
  end,
}
