-- proteus.kanban is a Nodal graph plugin, run as an app. The app's scripts/build-graphs.mjs writes
-- kanban.ndg from graphs/kanban.ndg, and the init.lua beside it that reads the graph and runs it.
-- Neither file is edited by hand: change the graph in the app, then run
-- `node scripts/build-graphs.mjs --plugins ../plugins/plugins` there. These tests fail when
-- init.lua is no longer the one Nodal writes, or the graph file is not a graph.

local DIR = 'plugins/proteus.kanban/'
local GRAPH_FILE = 'kanban.ndg'

-- init.lua as Nodal writes it.
local EXPECTED = [==[
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
  version = '1.2.0',
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
]==]

local source = read (DIR .. 'init.lua')
local graph = read (DIR .. GRAPH_FILE)

test (
  'init.lua is the one Nodal writes, which reads the graph beside it',
  function ()
    ok (source == EXPECTED, 'init.lua is not what build-graphs.mjs writes')
    ok (
      source:find ("\nlocal GRAPH_FILE = '" .. GRAPH_FILE .. "'\n", 1, true),
      'init.lua reads ' .. GRAPH_FILE
    )
  end
)

test ('the graph file is a Nodal graph', function ()
  ok (
    graph:find ('^{\n  "version": 3,'),
    GRAPH_FILE .. ' is not a version 3 graph'
  )
  ok (graph:find ('"nodes": [', 1, true), GRAPH_FILE .. ' has no nodes')
end)
