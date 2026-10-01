-- Built by Nodal from graphs/terminal.ndg. Nodal writes this file, so change the graph instead.
-- It runs the graph beside it with the Nodal runtime, as the Nodal preview does.
-- Placement: bottom

local ID = 'proteus.nodal.terminal'
local NAME = 'Terminal'
local GRAPH_FILE = 'terminal.ndg'

---@type Proteus.Plugin
return {
  name = NAME,
  description = 'A terminal in the bottom dock, built with Nodal from graphs/terminal.ndg.',
  version = '1.2.0',
  depends = { 'proteus.lib.ui', 'proteus.ui.views', 'proteus.nodal.app' },
  permissions = { 'process' },
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
    app.use ('views').add (
      'bottom',
      { id = ID, title = NAME, icon = 'terminal', content = handle.el }
    )
  end,
}
