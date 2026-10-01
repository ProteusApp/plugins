-- Built by Nodal from graphs/terminal.graph.json. Building again replaces this file.
-- It runs the graph below with the Nodal runtime, as the Nodal preview does.
-- To change it, change the graph.

local ID = 'proteus.nodal.terminal'
local NAME = 'Terminal'

-- lang=json
local GRAPH = [[
{
  "version": 3,
  "settings": {
    "locale": "en-US",
    "currency": "USD"
  },
  "blocks": [],
  "nodes": [
    {
      "id": "n1",
      "block": "event.start",
      "name": "Start",
      "position": {
        "x": 0,
        "y": 0
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n2",
      "block": "value.list",
      "name": "Shells",
      "position": {
        "x": 0,
        "y": 78
      },
      "config": {
        "items": "powershell\ncmd\nbash"
      },
      "literals": {}
    },
    {
      "id": "n3",
      "block": "ui.dropdown",
      "name": "Shell",
      "position": {
        "x": 330,
        "y": 0
      },
      "config": {
        "label": "Shell"
      },
      "literals": {
        "to": "powershell"
      }
    },
    {
      "id": "n4",
      "block": "ui.button",
      "name": "Restart",
      "position": {
        "x": 0,
        "y": 188
      },
      "config": {
        "label": "",
        "icon": "rotate-ccw",
        "style": "primary"
      },
      "literals": {
        "label": "Restart"
      }
    },
    {
      "id": "n5",
      "block": "flow.any",
      "name": "Start again",
      "position": {
        "x": 660,
        "y": 0
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n6",
      "block": "ui.terminal",
      "name": "Terminal",
      "position": {
        "x": 990,
        "y": 0
      },
      "config": {
        "label": "",
        "autostart": true,
        "font_size": 13
      },
      "literals": {}
    }
  ],
  "edges": [
    {
      "id": "e7",
      "from": "n1",
      "to": "n3",
      "input": "set"
    },
    {
      "id": "e8",
      "from": "n2",
      "to": "n3",
      "input": "options"
    },
    {
      "id": "e9",
      "from": "n3",
      "to": "n6",
      "input": "program"
    },
    {
      "id": "e10",
      "from": "n4",
      "to": "n5",
      "input": "a"
    },
    {
      "id": "e11",
      "from": "n3",
      "output": "changed",
      "to": "n5",
      "input": "b"
    },
    {
      "id": "e12",
      "from": "n5",
      "output": "then",
      "to": "n6",
      "input": "restart"
    }
  ],
  "next_id": 13,
  "layout": {
    "id": "root",
    "kind": "column",
    "children": [
      {
        "id": "box1",
        "kind": "row",
        "children": [
          {
            "node": "n3"
          },
          {
            "node": "n4"
          }
        ]
      },
      {
        "node": "n6",
        "grow": true
      }
    ]
  }
}
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
