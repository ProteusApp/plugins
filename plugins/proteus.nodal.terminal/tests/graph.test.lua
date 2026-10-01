-- proteus.nodal.terminal is a Nodal graph built as an app. The app's scripts/build-graphs.mjs writes init.lua
-- from graphs/terminal.graph.json, with the wrapper Nodal's Build as App writes, and puts a copy of the
-- graph beside it. Neither file is edited by hand: change the graph in the app, then run
-- `node scripts/build-graphs.mjs --plugins ../plugins/plugins` there. These tests fail when
-- init.lua no longer matches the graph file, or its wrapper is not the one Nodal writes.

local DIR = 'plugins/proteus.nodal.terminal/'
local GRAPH_FILE = 'terminal.graph.json'

-- init.lua up to the graph.
local HEAD = [==[
-- Built by Nodal from graphs/terminal.graph.json. Building again replaces this file.
-- It runs the graph below with the Nodal runtime, as the Nodal preview does.
-- To change it, change the graph.

local ID = 'proteus.nodal.terminal'
local NAME = 'Terminal'

-- lang=json
local GRAPH = [[
]==]

-- init.lua after the graph.
local TAIL = [==[

]]

---@type Proteus.Plugin
return {
  name = NAME,
  description = 'A terminal in the bottom dock, built with Nodal from graphs/terminal.graph.json.',
  version = '1.0.0',
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
    local handle, refusal =
      app.use ('nodal.app').mount_text (GRAPH, { status_bar = true })
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

test ('init.lua carries the graph file as it is', function ()
  local _, body = source:match ('\nlocal GRAPH = %[(=*)%[\n(.-)\n%]%1%]\n')
  ok (body, 'init.lua holds the graph in GRAPH')
  ok (body .. '\n' == graph, 'GRAPH in init.lua is not ' .. GRAPH_FILE)
end)

test ('init.lua is the wrapper Nodal writes, around the graph', function ()
  ok (source:sub (1, #HEAD) == HEAD, 'the lines before the graph changed')
  ok (source:sub (-#TAIL) == TAIL, 'the lines after the graph changed')
  ok (
    source == HEAD .. graph:gsub ('\n$', '') .. TAIL,
    'init.lua is more than the graph and its wrapper'
  )
end)
