-- Built by Nodal from graphs/kanban.ndg. Nodal writes this file, so change the graph instead.
-- It runs the graph beside it with the Nodal runtime, as the Nodal preview does.
-- Placement: app

-- Plugin id: proteus.kanban
local NAME = 'Kanban'
local GRAPH_FILE = 'kanban.ndg'

---@type Proteus.Plugin
return {
  name = NAME,
  description = 'Boards of cards in columns, saved in data/kanban. Built with Nodal from graphs/kanban.ndg.',
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
