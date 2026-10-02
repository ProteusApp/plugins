-- proteus.nodal.terminal is a Nodal graph plugin, run as a bottom panel. The app's scripts/build-graphs.mjs writes
-- terminal.ndg from graphs/terminal.ndg, and the init.lua beside it that reads the graph and runs it.
-- Neither file is edited by hand: change the graph in the app, then run
-- `node scripts/build-graphs.mjs --plugins ../plugins/plugins` there. These tests fail when
-- init.lua is no longer the one Nodal writes, or the graph file is not a graph.

local DIR = 'plugins/proteus.nodal.terminal/'
local GRAPH_FILE = 'terminal.ndg'

-- init.lua as Nodal writes it.
local EXPECTED = [==[
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
  version = '1.2.1',
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
