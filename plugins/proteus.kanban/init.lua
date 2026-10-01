-- Built by Nodal from graphs/kanban.graph.json. Building again replaces this file.
-- It runs the graph below with the Nodal runtime, as the Nodal preview does.
-- To change it, change the graph.

-- Plugin id: proteus.kanban
local NAME = 'Kanban'

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
      "block": "value.text",
      "name": "Boards folder",
      "position": {
        "x": 0,
        "y": 0
      },
      "config": {
        "value": "data/kanban"
      },
      "literals": {}
    },
    {
      "id": "n2",
      "block": "event.start",
      "name": "Start",
      "position": {
        "x": 0,
        "y": 114
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n3",
      "block": "text.format",
      "name": "Last board file",
      "position": {
        "x": 330,
        "y": 0
      },
      "config": {},
      "literals": {
        "template": "{a}/.last"
      }
    },
    {
      "id": "n4",
      "block": "file.read",
      "name": "Read which board was open",
      "position": {
        "x": 330,
        "y": 210
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n5",
      "block": "text.trim",
      "name": "Board open last",
      "position": {
        "x": 660,
        "y": 0
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n6",
      "block": "flow.any",
      "name": "After the files change",
      "position": {
        "x": 660,
        "y": 114
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n7",
      "block": "state.text",
      "name": "Board name",
      "position": {
        "x": 990,
        "y": 0
      },
      "config": {
        "value": ""
      },
      "literals": {}
    },
    {
      "id": "n8",
      "block": "state.set",
      "name": "Want the board open last",
      "position": {
        "x": 990,
        "y": 82
      },
      "config": {
        "limit": 0,
        "mode": "replace",
        "variable": "n7"
      },
      "literals": {}
    },
    {
      "id": "n9",
      "block": "flow.any",
      "name": "List the boards",
      "position": {
        "x": 990,
        "y": 260
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n10",
      "block": "file.list",
      "name": "List the board files",
      "position": {
        "x": 1320,
        "y": 0
      },
      "config": {
        "drop_ending": true,
        "ending": ".json"
      },
      "literals": {}
    },
    {
      "id": "n11",
      "block": "list.sort",
      "name": "Board names",
      "position": {
        "x": 1650,
        "y": 0
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n12",
      "block": "state.set",
      "name": "Keep the board names",
      "position": {
        "x": 1650,
        "y": 114
      },
      "config": {
        "limit": 0,
        "mode": "replace",
        "variable": "n13"
      },
      "literals": {}
    },
    {
      "id": "n13",
      "block": "state.list",
      "name": "Boards",
      "position": {
        "x": 1650,
        "y": 292
      },
      "config": {
        "value": []
      },
      "literals": {}
    },
    {
      "id": "n14",
      "block": "list.length",
      "name": "How many boards",
      "position": {
        "x": 1980,
        "y": 0
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n15",
      "block": "list.contains",
      "name": "That board is there",
      "position": {
        "x": 1980,
        "y": 114
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n16",
      "block": "list.first",
      "name": "First board",
      "position": {
        "x": 1980,
        "y": 260
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n17",
      "block": "logic.compare",
      "name": "No boards yet",
      "position": {
        "x": 2310,
        "y": 0
      },
      "config": {
        "operator": "==="
      },
      "literals": {
        "b": 0
      }
    },
    {
      "id": "n18",
      "block": "logic.if",
      "name": "Board to open",
      "position": {
        "x": 2310,
        "y": 178
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n19",
      "block": "flow.when",
      "name": "Only when there are no boards",
      "position": {
        "x": 2640,
        "y": 0
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n20",
      "block": "state.set",
      "name": "Choose the board to open",
      "position": {
        "x": 2970,
        "y": 0
      },
      "config": {
        "limit": 0,
        "mode": "replace",
        "variable": "n7"
      },
      "literals": {}
    },
    {
      "id": "n21",
      "block": "ui.list",
      "name": "Board list",
      "position": {
        "x": 3300,
        "y": 0
      },
      "config": {
        "label": ""
      },
      "literals": {}
    },
    {
      "id": "n22",
      "block": "state.set",
      "name": "Want the picked board",
      "position": {
        "x": 3630,
        "y": 0
      },
      "config": {
        "limit": 0,
        "mode": "replace",
        "variable": "n7"
      },
      "literals": {}
    },
    {
      "id": "n23",
      "block": "flow.any",
      "name": "Open a board",
      "position": {
        "x": 0,
        "y": 590
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n24",
      "block": "text.format",
      "name": "Board file to open",
      "position": {
        "x": 0,
        "y": 800
      },
      "config": {},
      "literals": {
        "template": "{a}/{b}.json"
      }
    },
    {
      "id": "n25",
      "block": "state.text",
      "name": "Board file",
      "position": {
        "x": 0,
        "y": 1010
      },
      "config": {
        "value": ""
      },
      "literals": {}
    },
    {
      "id": "n26",
      "block": "logic.compare",
      "name": "Not open already",
      "position": {
        "x": 330,
        "y": 590
      },
      "config": {
        "operator": "!=="
      },
      "literals": {}
    },
    {
      "id": "n27",
      "block": "file.write",
      "name": "Write which board is open",
      "position": {
        "x": 330,
        "y": 768
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n28",
      "block": "flow.when",
      "name": "Only when it is not open",
      "position": {
        "x": 660,
        "y": 590
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n29",
      "block": "file.read",
      "name": "Read the board",
      "position": {
        "x": 990,
        "y": 590
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n30",
      "block": "data.parse_json",
      "name": "Board in the file",
      "position": {
        "x": 1320,
        "y": 590
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n31",
      "block": "flow.when",
      "name": "Only when it reads",
      "position": {
        "x": 1650,
        "y": 590
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n32",
      "block": "flow.order",
      "name": "Load the board",
      "position": {
        "x": 1980,
        "y": 590
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n33",
      "block": "app.notify",
      "name": "Say it would not read",
      "position": {
        "x": 1980,
        "y": 800
      },
      "config": {
        "kind": "warn"
      },
      "literals": {
        "message": "That file does not hold a board"
      }
    },
    {
      "id": "n34",
      "block": "state.set",
      "name": "Put the board in place",
      "position": {
        "x": 2310,
        "y": 590
      },
      "config": {
        "limit": 0,
        "mode": "replace",
        "variable": "n37"
      },
      "literals": {}
    },
    {
      "id": "n35",
      "block": "state.set",
      "name": "Remember its file",
      "position": {
        "x": 2310,
        "y": 768
      },
      "config": {
        "limit": 0,
        "mode": "replace",
        "variable": "n25"
      },
      "literals": {}
    },
    {
      "id": "n36",
      "block": "state.set",
      "name": "The loaded board is saved",
      "position": {
        "x": 2310,
        "y": 946
      },
      "config": {
        "limit": 0,
        "mode": "replace",
        "variable": "n43"
      },
      "literals": {}
    },
    {
      "id": "n37",
      "block": "state.record",
      "name": "Board",
      "position": {
        "x": 2640,
        "y": 590
      },
      "config": {
        "value": {}
      },
      "literals": {}
    },
    {
      "id": "n38",
      "block": "flow.any",
      "name": "Close the card",
      "position": {
        "x": 2640,
        "y": 672
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n39",
      "block": "data.to_json",
      "name": "Board as JSON",
      "position": {
        "x": 0,
        "y": 1244
      },
      "config": {},
      "literals": {
        "pretty": true
      }
    },
    {
      "id": "n40",
      "block": "flow.changed",
      "name": "When the board changes",
      "position": {
        "x": 330,
        "y": 1244
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n41",
      "block": "flow.debounce",
      "name": "Save after a pause",
      "position": {
        "x": 660,
        "y": 1244
      },
      "config": {},
      "literals": {
        "ms": 500
      }
    },
    {
      "id": "n42",
      "block": "flow.any",
      "name": "Save now",
      "position": {
        "x": 990,
        "y": 1244
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n43",
      "block": "state.text",
      "name": "Saved JSON",
      "position": {
        "x": 990,
        "y": 1454
      },
      "config": {
        "value": "{}"
      },
      "literals": {}
    },
    {
      "id": "n44",
      "block": "logic.compare",
      "name": "Has changes to save",
      "position": {
        "x": 1320,
        "y": 1244
      },
      "config": {
        "operator": "!=="
      },
      "literals": {}
    },
    {
      "id": "n45",
      "block": "flow.when",
      "name": "Only when there are changes",
      "position": {
        "x": 1650,
        "y": 1244
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n46",
      "block": "file.write",
      "name": "Write the board",
      "position": {
        "x": 1980,
        "y": 1244
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n47",
      "block": "state.set",
      "name": "Remember what was saved",
      "position": {
        "x": 1980,
        "y": 1486
      },
      "config": {
        "limit": 0,
        "mode": "replace",
        "variable": "n43"
      },
      "literals": {}
    },
    {
      "id": "n48",
      "block": "flow.any",
      "name": "Show the board",
      "position": {
        "x": 6810,
        "y": 0
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n49",
      "block": "data.get",
      "name": "Title",
      "position": {
        "x": 6810,
        "y": 210
      },
      "config": {},
      "literals": {
        "path": "title"
      }
    },
    {
      "id": "n50",
      "block": "ui.textbox",
      "name": "Board title",
      "position": {
        "x": 7140,
        "y": 0
      },
      "config": {
        "label": "",
        "clear_on_submit": false,
        "mono": false,
        "multiline": false
      },
      "literals": {
        "placeholder": "Board title"
      }
    },
    {
      "id": "n51",
      "block": "data.set",
      "name": "Board with the new title",
      "position": {
        "x": 7470,
        "y": 0
      },
      "config": {},
      "literals": {
        "key": "title"
      }
    },
    {
      "id": "n52",
      "block": "state.set",
      "name": "Keep the new title",
      "position": {
        "x": 7800,
        "y": 0
      },
      "config": {
        "limit": 0,
        "mode": "replace",
        "variable": "n37"
      },
      "literals": {}
    },
    {
      "id": "n53",
      "block": "app.command",
      "name": "Find",
      "position": {
        "x": 6810,
        "y": 490
      },
      "config": {
        "key": "ctrl+f",
        "title": "Find",
        "icon": "search",
        "menu": "Edit"
      },
      "literals": {}
    },
    {
      "id": "n54",
      "block": "list.where",
      "name": "Labels with names",
      "position": {
        "x": 6810,
        "y": 604
      },
      "config": {
        "test": "is not empty"
      },
      "literals": {
        "field": "name"
      }
    },
    {
      "id": "n55",
      "block": "ui.textbox",
      "name": "Search",
      "position": {
        "x": 7140,
        "y": 490
      },
      "config": {
        "label": "",
        "clear_on_submit": false,
        "mono": false,
        "multiline": false
      },
      "literals": {
        "placeholder": "Search cards"
      }
    },
    {
      "id": "n56",
      "block": "list.field",
      "name": "Label names",
      "position": {
        "x": 7140,
        "y": 860
      },
      "config": {},
      "literals": {
        "field": "name"
      }
    },
    {
      "id": "n57",
      "block": "list.field",
      "name": "Label ids",
      "position": {
        "x": 7140,
        "y": 1006
      },
      "config": {},
      "literals": {
        "field": "id"
      }
    },
    {
      "id": "n58",
      "block": "list.prepend",
      "name": "Filter choices",
      "position": {
        "x": 7470,
        "y": 490
      },
      "config": {},
      "literals": {
        "item": "All labels"
      }
    },
    {
      "id": "n59",
      "block": "ui.dropdown",
      "name": "Label filter",
      "position": {
        "x": 7800,
        "y": 490
      },
      "config": {
        "label": ""
      },
      "literals": {
        "to": "All labels"
      }
    },
    {
      "id": "n60",
      "block": "math.subtract",
      "name": "Place in the labels",
      "position": {
        "x": 8130,
        "y": 490
      },
      "config": {},
      "literals": {
        "minus": 1
      }
    },
    {
      "id": "n61",
      "block": "list.get",
      "name": "Only this label",
      "position": {
        "x": 8460,
        "y": 490
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n62",
      "block": "ui.button",
      "name": "Add column",
      "position": {
        "x": 6810,
        "y": 1272
      },
      "config": {
        "label": "",
        "icon": "columns-3",
        "style": "plain"
      },
      "literals": {
        "label": "Add column"
      }
    },
    {
      "id": "n63",
      "block": "app.ask",
      "name": "Ask for a column name",
      "position": {
        "x": 7140,
        "y": 1272
      },
      "config": {},
      "literals": {
        "prompt": "A name for the new column"
      }
    },
    {
      "id": "n64",
      "block": "system.now",
      "name": "Time for a new id",
      "position": {
        "x": 7470,
        "y": 1272
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n65",
      "block": "text.format",
      "name": "New column id",
      "position": {
        "x": 7800,
        "y": 1272
      },
      "config": {},
      "literals": {
        "template": "col{a}"
      }
    },
    {
      "id": "n66",
      "block": "data.record",
      "name": "New column",
      "position": {
        "x": 7800,
        "y": 1482
      },
      "config": {},
      "literals": {
        "k1": "id",
        "k2": "title",
        "k3": "cards",
        "v3": []
      }
    },
    {
      "id": "n67",
      "block": "list.append",
      "name": "Columns with the new one",
      "position": {
        "x": 8130,
        "y": 1272
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n68",
      "block": "data.set",
      "name": "Board with the new column",
      "position": {
        "x": 8460,
        "y": 1272
      },
      "config": {},
      "literals": {
        "key": "columns"
      }
    },
    {
      "id": "n69",
      "block": "state.set",
      "name": "Add the column",
      "position": {
        "x": 8790,
        "y": 1272
      },
      "config": {
        "limit": 0,
        "mode": "replace",
        "variable": "n37"
      },
      "literals": {}
    },
    {
      "id": "n70",
      "block": "data.get",
      "name": "Columns",
      "position": {
        "x": 4560,
        "y": 0
      },
      "config": {},
      "literals": {
        "path": "columns"
      }
    },
    {
      "id": "n71",
      "block": "data.get",
      "name": "Labels",
      "position": {
        "x": 4560,
        "y": 146
      },
      "config": {},
      "literals": {
        "path": "labels"
      }
    },
    {
      "id": "n72",
      "block": "app.command",
      "name": "New Card",
      "position": {
        "x": 4560,
        "y": 292
      },
      "config": {
        "key": "ctrl+n",
        "title": "New Card",
        "icon": "square-plus",
        "menu": "File"
      },
      "literals": {}
    },
    {
      "id": "n73",
      "block": "math.max",
      "name": "Column for a new card",
      "position": {
        "x": 4890,
        "y": 0
      },
      "config": {},
      "literals": {
        "b": 1
      }
    },
    {
      "id": "n74",
      "block": "ui.board",
      "name": "Board view",
      "position": {
        "x": 5220,
        "y": 0
      },
      "config": {
        "label": "",
        "card_checklist": "checklist",
        "card_due": "due",
        "card_hidden": "archived",
        "card_notes": "notes",
        "card_tags": "labels",
        "card_title": "title",
        "lane_items": "cards",
        "lane_limit": "limit",
        "lane_title": "title",
        "lane_word": "column"
      },
      "literals": {}
    },
    {
      "id": "n75",
      "block": "data.set",
      "name": "Board with the new columns",
      "position": {
        "x": 5550,
        "y": 0
      },
      "config": {},
      "literals": {
        "key": "columns"
      }
    },
    {
      "id": "n76",
      "block": "state.set",
      "name": "Keep the change",
      "position": {
        "x": 5880,
        "y": 0
      },
      "config": {
        "limit": 0,
        "mode": "replace",
        "variable": "n37"
      },
      "literals": {}
    },
    {
      "id": "n77",
      "block": "logic.compare",
      "name": "Just one card",
      "position": {
        "x": 4560,
        "y": 778
      },
      "config": {
        "operator": "==="
      },
      "literals": {
        "b": 1
      }
    },
    {
      "id": "n78",
      "block": "logic.if",
      "name": "Card or cards",
      "position": {
        "x": 4890,
        "y": 778
      },
      "config": {},
      "literals": {
        "otherwise": "cards",
        "then": "card"
      }
    },
    {
      "id": "n79",
      "block": "text.format",
      "name": "Status text",
      "position": {
        "x": 5220,
        "y": 778
      },
      "config": {},
      "literals": {
        "template": "{a} {c} · {b} overdue"
      }
    },
    {
      "id": "n80",
      "block": "app.status",
      "name": "Status bar",
      "position": {
        "x": 5550,
        "y": 778
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n81",
      "block": "data.find",
      "name": "Picked card",
      "position": {
        "x": 0,
        "y": 2806
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n82",
      "block": "flow.changed",
      "name": "When another card is picked",
      "position": {
        "x": 0,
        "y": 3048
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n83",
      "block": "flow.any",
      "name": "Show the card",
      "position": {
        "x": 330,
        "y": 2806
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n84",
      "block": "data.get",
      "name": "Its title",
      "position": {
        "x": 330,
        "y": 3314
      },
      "config": {},
      "literals": {
        "path": "title"
      }
    },
    {
      "id": "n85",
      "block": "ui.textbox",
      "name": "Card title",
      "position": {
        "x": 660,
        "y": 3314
      },
      "config": {
        "label": "Title",
        "clear_on_submit": false,
        "mono": false,
        "multiline": false
      },
      "literals": {}
    },
    {
      "id": "n86",
      "block": "data.update",
      "name": "Board with its new title",
      "position": {
        "x": 990,
        "y": 3314
      },
      "config": {},
      "literals": {
        "key": "title"
      }
    },
    {
      "id": "n87",
      "block": "state.set",
      "name": "Keep its title",
      "position": {
        "x": 1320,
        "y": 3314
      },
      "config": {
        "limit": 0,
        "mode": "replace",
        "variable": "n37"
      },
      "literals": {}
    },
    {
      "id": "n88",
      "block": "list.field",
      "name": "Column titles",
      "position": {
        "x": 0,
        "y": 3804
      },
      "config": {},
      "literals": {
        "field": "title"
      }
    },
    {
      "id": "n89",
      "block": "list.get",
      "name": "Its column",
      "position": {
        "x": 330,
        "y": 3804
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n90",
      "block": "ui.dropdown",
      "name": "Column",
      "position": {
        "x": 660,
        "y": 3804
      },
      "config": {
        "label": "Column"
      },
      "literals": {}
    },
    {
      "id": "n91",
      "block": "data.remove",
      "name": "Board without the card",
      "position": {
        "x": 990,
        "y": 3804
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n92",
      "block": "text.format",
      "name": "Where its cards are",
      "position": {
        "x": 990,
        "y": 3982
      },
      "config": {},
      "literals": {
        "template": "columns.{a}.cards"
      }
    },
    {
      "id": "n93",
      "block": "data.get",
      "name": "Cards in that column",
      "position": {
        "x": 1320,
        "y": 3804
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n94",
      "block": "list.append",
      "name": "With the card at the end",
      "position": {
        "x": 1650,
        "y": 3804
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n95",
      "block": "data.set_path",
      "name": "Board with the card moved",
      "position": {
        "x": 1980,
        "y": 3804
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n96",
      "block": "state.set",
      "name": "Move the card",
      "position": {
        "x": 2310,
        "y": 3804
      },
      "config": {
        "limit": 0,
        "mode": "replace",
        "variable": "n37"
      },
      "literals": {}
    },
    {
      "id": "n97",
      "block": "data.get",
      "name": "Its labels",
      "position": {
        "x": 330,
        "y": 4312
      },
      "config": {},
      "literals": {
        "path": "labels"
      }
    },
    {
      "id": "n98",
      "block": "ui.tags",
      "name": "Label picker",
      "position": {
        "x": 660,
        "y": 4312
      },
      "config": {
        "label": "Labels",
        "editable": true
      },
      "literals": {}
    },
    {
      "id": "n99",
      "block": "data.update",
      "name": "Board with its labels",
      "position": {
        "x": 990,
        "y": 4312
      },
      "config": {},
      "literals": {
        "key": "labels"
      }
    },
    {
      "id": "n100",
      "block": "data.set",
      "name": "Board with the edited labels",
      "position": {
        "x": 990,
        "y": 4554
      },
      "config": {},
      "literals": {
        "key": "labels"
      }
    },
    {
      "id": "n101",
      "block": "state.set",
      "name": "Keep its labels",
      "position": {
        "x": 1320,
        "y": 4312
      },
      "config": {
        "limit": 0,
        "mode": "replace",
        "variable": "n37"
      },
      "literals": {}
    },
    {
      "id": "n102",
      "block": "state.set",
      "name": "Keep the edited labels",
      "position": {
        "x": 1320,
        "y": 4490
      },
      "config": {
        "limit": 0,
        "mode": "replace",
        "variable": "n37"
      },
      "literals": {}
    },
    {
      "id": "n103",
      "block": "data.get",
      "name": "Its due date",
      "position": {
        "x": 330,
        "y": 4852
      },
      "config": {},
      "literals": {
        "path": "due"
      }
    },
    {
      "id": "n104",
      "block": "ui.date",
      "name": "Due date",
      "position": {
        "x": 660,
        "y": 4852
      },
      "config": {
        "label": "Due date"
      },
      "literals": {}
    },
    {
      "id": "n105",
      "block": "data.update",
      "name": "Board with its due date",
      "position": {
        "x": 990,
        "y": 4852
      },
      "config": {},
      "literals": {
        "key": "due"
      }
    },
    {
      "id": "n106",
      "block": "state.set",
      "name": "Keep its due date",
      "position": {
        "x": 1320,
        "y": 4852
      },
      "config": {
        "limit": 0,
        "mode": "replace",
        "variable": "n37"
      },
      "literals": {}
    },
    {
      "id": "n107",
      "block": "value.list",
      "name": "Priorities",
      "position": {
        "x": 0,
        "y": 5214
      },
      "config": {
        "items": "none\nlow\nmedium\nhigh"
      },
      "literals": {}
    },
    {
      "id": "n108",
      "block": "data.get",
      "name": "Its priority",
      "position": {
        "x": 0,
        "y": 5392
      },
      "config": {},
      "literals": {
        "path": "priority"
      }
    },
    {
      "id": "n109",
      "block": "list.contains",
      "name": "It has a priority",
      "position": {
        "x": 330,
        "y": 5214
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n110",
      "block": "logic.if",
      "name": "Priority to show",
      "position": {
        "x": 660,
        "y": 5214
      },
      "config": {},
      "literals": {
        "otherwise": "none"
      }
    },
    {
      "id": "n111",
      "block": "ui.dropdown",
      "name": "Priority",
      "position": {
        "x": 990,
        "y": 5214
      },
      "config": {
        "label": "Priority"
      },
      "literals": {}
    },
    {
      "id": "n112",
      "block": "data.update",
      "name": "Board with its priority",
      "position": {
        "x": 1320,
        "y": 5214
      },
      "config": {},
      "literals": {
        "key": "priority"
      }
    },
    {
      "id": "n113",
      "block": "state.set",
      "name": "Keep its priority",
      "position": {
        "x": 1650,
        "y": 5214
      },
      "config": {
        "limit": 0,
        "mode": "replace",
        "variable": "n37"
      },
      "literals": {}
    },
    {
      "id": "n114",
      "block": "data.get",
      "name": "Its checklist",
      "position": {
        "x": 330,
        "y": 5658
      },
      "config": {},
      "literals": {
        "path": "checklist"
      }
    },
    {
      "id": "n115",
      "block": "ui.checklist",
      "name": "Checklist",
      "position": {
        "x": 660,
        "y": 5658
      },
      "config": {
        "label": "Checklist"
      },
      "literals": {}
    },
    {
      "id": "n116",
      "block": "data.update",
      "name": "Board with its checklist",
      "position": {
        "x": 990,
        "y": 5658
      },
      "config": {},
      "literals": {
        "key": "checklist"
      }
    },
    {
      "id": "n117",
      "block": "state.set",
      "name": "Keep its checklist",
      "position": {
        "x": 1320,
        "y": 5658
      },
      "config": {
        "limit": 0,
        "mode": "replace",
        "variable": "n37"
      },
      "literals": {}
    },
    {
      "id": "n118",
      "block": "data.get",
      "name": "Its notes",
      "position": {
        "x": 330,
        "y": 6052
      },
      "config": {},
      "literals": {
        "path": "notes"
      }
    },
    {
      "id": "n119",
      "block": "ui.textbox",
      "name": "Notes",
      "position": {
        "x": 660,
        "y": 6052
      },
      "config": {
        "label": "Notes",
        "clear_on_submit": false,
        "mono": false,
        "multiline": true
      },
      "literals": {
        "placeholder": "Notes, in Markdown"
      }
    },
    {
      "id": "n120",
      "block": "data.update",
      "name": "Board with its notes",
      "position": {
        "x": 990,
        "y": 6052
      },
      "config": {},
      "literals": {
        "key": "notes"
      }
    },
    {
      "id": "n121",
      "block": "state.set",
      "name": "Keep its notes",
      "position": {
        "x": 1320,
        "y": 6052
      },
      "config": {
        "limit": 0,
        "mode": "replace",
        "variable": "n37"
      },
      "literals": {}
    },
    {
      "id": "n122",
      "block": "ui.button",
      "name": "Archive",
      "position": {
        "x": 0,
        "y": 6542
      },
      "config": {
        "label": "",
        "icon": "archive",
        "style": "plain"
      },
      "literals": {
        "label": "Archive"
      }
    },
    {
      "id": "n123",
      "block": "ui.button",
      "name": "Delete",
      "position": {
        "x": 0,
        "y": 6752
      },
      "config": {
        "label": "",
        "icon": "trash",
        "style": "plain"
      },
      "literals": {
        "label": "Delete"
      }
    },
    {
      "id": "n124",
      "block": "ui.button",
      "name": "Close",
      "position": {
        "x": 0,
        "y": 6962
      },
      "config": {
        "label": "",
        "icon": "x",
        "style": "plain"
      },
      "literals": {
        "label": "Close"
      }
    },
    {
      "id": "n125",
      "block": "data.update",
      "name": "Board with it archived",
      "position": {
        "x": 330,
        "y": 6542
      },
      "config": {},
      "literals": {
        "key": "archived",
        "value": true
      }
    },
    {
      "id": "n126",
      "block": "app.confirm",
      "name": "Ask before deleting it",
      "position": {
        "x": 330,
        "y": 6784
      },
      "config": {
        "danger": true,
        "yes": "Delete"
      },
      "literals": {
        "message": "Delete this card?"
      }
    },
    {
      "id": "n127",
      "block": "state.set",
      "name": "Archive it",
      "position": {
        "x": 660,
        "y": 6542
      },
      "config": {
        "limit": 0,
        "mode": "replace",
        "variable": "n37"
      },
      "literals": {}
    },
    {
      "id": "n128",
      "block": "state.set",
      "name": "Delete it",
      "position": {
        "x": 660,
        "y": 6720
      },
      "config": {
        "limit": 0,
        "mode": "replace",
        "variable": "n37"
      },
      "literals": {}
    },
    {
      "id": "n129",
      "block": "ui.button",
      "name": "Undo",
      "position": {
        "x": 4560,
        "y": 1108
      },
      "config": {
        "label": "",
        "icon": "undo-2",
        "style": "plain"
      },
      "literals": {
        "label": "Undo"
      }
    },
    {
      "id": "n130",
      "block": "app.command",
      "name": "Undo command",
      "position": {
        "x": 4560,
        "y": 1318
      },
      "config": {
        "key": "ctrl+z",
        "title": "Undo",
        "icon": "undo-2",
        "menu": "Edit"
      },
      "literals": {}
    },
    {
      "id": "n131",
      "block": "ui.button",
      "name": "Redo",
      "position": {
        "x": 4560,
        "y": 1432
      },
      "config": {
        "label": "",
        "icon": "redo-2",
        "style": "plain"
      },
      "literals": {
        "label": "Redo"
      }
    },
    {
      "id": "n132",
      "block": "app.command",
      "name": "Redo command",
      "position": {
        "x": 4560,
        "y": 1642
      },
      "config": {
        "key": "ctrl+y",
        "title": "Redo",
        "icon": "redo-2",
        "menu": "Edit"
      },
      "literals": {}
    },
    {
      "id": "n133",
      "block": "flow.any",
      "name": "Undo a change",
      "position": {
        "x": 4890,
        "y": 1108
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n134",
      "block": "flow.any",
      "name": "Redo a change",
      "position": {
        "x": 4890,
        "y": 1318
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n135",
      "block": "state.history",
      "name": "Undo history",
      "position": {
        "x": 5220,
        "y": 1108
      },
      "config": {
        "limit": 100,
        "merge_ms": 800,
        "variable": "n37"
      },
      "literals": {}
    },
    {
      "id": "n136",
      "block": "data.collect",
      "name": "Archived cards",
      "position": {
        "x": 4560,
        "y": 1876
      },
      "config": {},
      "literals": {
        "field": "archived",
        "value": true
      }
    },
    {
      "id": "n137",
      "block": "ui.list",
      "name": "Archived list",
      "position": {
        "x": 4890,
        "y": 1876
      },
      "config": {
        "label": "Archived"
      },
      "literals": {
        "to": "",
        "field": "title"
      }
    },
    {
      "id": "n138",
      "block": "flow.order",
      "name": "Put it back",
      "position": {
        "x": 5220,
        "y": 1876
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n139",
      "block": "data.get",
      "name": "Id to put back",
      "position": {
        "x": 5220,
        "y": 2086
      },
      "config": {},
      "literals": {
        "path": "id"
      }
    },
    {
      "id": "n140",
      "block": "data.update",
      "name": "Board with it back",
      "position": {
        "x": 5550,
        "y": 1876
      },
      "config": {},
      "literals": {
        "key": "archived",
        "value": false
      }
    },
    {
      "id": "n141",
      "block": "state.set",
      "name": "Keep it on the board",
      "position": {
        "x": 5880,
        "y": 1876
      },
      "config": {
        "limit": 0,
        "mode": "replace",
        "variable": "n37"
      },
      "literals": {}
    },
    {
      "id": "n142",
      "block": "ui.button",
      "name": "New board",
      "position": {
        "x": 3240,
        "y": 2806
      },
      "config": {
        "label": "",
        "icon": "folder-plus",
        "style": "plain"
      },
      "literals": {
        "label": "New board"
      }
    },
    {
      "id": "n143",
      "block": "app.command",
      "name": "New Board",
      "position": {
        "x": 3240,
        "y": 3016
      },
      "config": {
        "key": "",
        "title": "New Board",
        "icon": "folder-plus",
        "menu": "File"
      },
      "literals": {}
    },
    {
      "id": "n144",
      "block": "flow.any",
      "name": "Make a new board",
      "position": {
        "x": 3570,
        "y": 2806
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n145",
      "block": "app.ask",
      "name": "Ask for a board name",
      "position": {
        "x": 3900,
        "y": 2806
      },
      "config": {},
      "literals": {
        "prompt": "A name for the new board"
      }
    },
    {
      "id": "n146",
      "block": "text.trim",
      "name": "New board name",
      "position": {
        "x": 4230,
        "y": 2806
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n147",
      "block": "list.prepend",
      "name": "Names in use",
      "position": {
        "x": 4230,
        "y": 2920
      },
      "config": {},
      "literals": {
        "item": ""
      }
    },
    {
      "id": "n148",
      "block": "list.where",
      "name": "Boards with that name",
      "position": {
        "x": 4560,
        "y": 2806
      },
      "config": {
        "test": "equals"
      },
      "literals": {
        "field": ""
      }
    },
    {
      "id": "n149",
      "block": "data.to_json",
      "name": "Name as JSON",
      "position": {
        "x": 4560,
        "y": 3016
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n150",
      "block": "list.length",
      "name": "How many have it",
      "position": {
        "x": 4890,
        "y": 2806
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n151",
      "block": "text.format",
      "name": "New board as JSON",
      "position": {
        "x": 4890,
        "y": 2920
      },
      "config": {},
      "literals": {
        "template": "{\n  \"version\": 1,\n  \"title\": {a},\n  \"labels\": [],\n  \"columns\": [\n    { \"id\": \"col1\", \"title\": \"To do\", \"cards\": [] },\n    { \"id\": \"col2\", \"title\": \"Doing\", \"cards\": [] },\n    { \"id\": \"col3\", \"title\": \"Done\", \"cards\": [] }\n  ]\n}\n"
      }
    },
    {
      "id": "n152",
      "block": "text.format",
      "name": "New board file",
      "position": {
        "x": 4890,
        "y": 3130
      },
      "config": {},
      "literals": {
        "template": "{a}/{b}.json"
      }
    },
    {
      "id": "n153",
      "block": "logic.compare",
      "name": "Name is free",
      "position": {
        "x": 5220,
        "y": 2806
      },
      "config": {
        "operator": "==="
      },
      "literals": {
        "b": 0
      }
    },
    {
      "id": "n154",
      "block": "flow.when",
      "name": "Only when the name is free",
      "position": {
        "x": 5550,
        "y": 2806
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n155",
      "block": "file.write",
      "name": "Write the new board",
      "position": {
        "x": 5880,
        "y": 2806
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n156",
      "block": "state.set",
      "name": "Want the new board",
      "position": {
        "x": 5880,
        "y": 3048
      },
      "config": {
        "limit": 0,
        "mode": "replace",
        "variable": "n7"
      },
      "literals": {}
    },
    {
      "id": "n157",
      "block": "app.notify",
      "name": "Say to pick another name",
      "position": {
        "x": 5880,
        "y": 3226
      },
      "config": {
        "kind": "warn"
      },
      "literals": {
        "message": "Type a name that no other board has"
      }
    },
    {
      "id": "n158",
      "block": "app.command",
      "name": "Rename Board",
      "position": {
        "x": 3240,
        "y": 3524
      },
      "config": {
        "key": "",
        "title": "Rename Board",
        "icon": "pencil",
        "menu": "File"
      },
      "literals": {}
    },
    {
      "id": "n159",
      "block": "app.ask",
      "name": "Ask for its new name",
      "position": {
        "x": 3570,
        "y": 3524
      },
      "config": {},
      "literals": {
        "prompt": "A new name for the board"
      }
    },
    {
      "id": "n160",
      "block": "text.trim",
      "name": "Its new name",
      "position": {
        "x": 3900,
        "y": 3524
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n161",
      "block": "logic.compare",
      "name": "Has a name",
      "position": {
        "x": 4230,
        "y": 3524
      },
      "config": {
        "operator": "!=="
      },
      "literals": {
        "b": ""
      }
    },
    {
      "id": "n162",
      "block": "text.format",
      "name": "Its new file",
      "position": {
        "x": 4230,
        "y": 3702
      },
      "config": {},
      "literals": {
        "template": "{a}/{b}.json"
      }
    },
    {
      "id": "n163",
      "block": "flow.when",
      "name": "Only when it has a name",
      "position": {
        "x": 4560,
        "y": 3524
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n164",
      "block": "file.rename",
      "name": "Rename its file",
      "position": {
        "x": 4890,
        "y": 3524
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n165",
      "block": "flow.when",
      "name": "Only when that worked",
      "position": {
        "x": 5220,
        "y": 3524
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n166",
      "block": "data.set",
      "name": "Board with the new name",
      "position": {
        "x": 5220,
        "y": 3734
      },
      "config": {},
      "literals": {
        "key": "title"
      }
    },
    {
      "id": "n167",
      "block": "state.set",
      "name": "Want it by its new name",
      "position": {
        "x": 5550,
        "y": 3524
      },
      "config": {
        "limit": 0,
        "mode": "replace",
        "variable": "n7"
      },
      "literals": {}
    },
    {
      "id": "n168",
      "block": "state.set",
      "name": "Remember its new file",
      "position": {
        "x": 5550,
        "y": 3702
      },
      "config": {
        "limit": 0,
        "mode": "replace",
        "variable": "n25"
      },
      "literals": {}
    },
    {
      "id": "n169",
      "block": "state.set",
      "name": "Keep the new name",
      "position": {
        "x": 5550,
        "y": 3880
      },
      "config": {
        "limit": 0,
        "mode": "replace",
        "variable": "n37"
      },
      "literals": {}
    },
    {
      "id": "n170",
      "block": "app.notify",
      "name": "Say the name is taken",
      "position": {
        "x": 5550,
        "y": 4058
      },
      "config": {
        "kind": "warn"
      },
      "literals": {
        "message": "Another board has that name"
      }
    },
    {
      "id": "n171",
      "block": "app.command",
      "name": "Delete Board",
      "position": {
        "x": 3240,
        "y": 4356
      },
      "config": {
        "key": "",
        "title": "Delete Board",
        "icon": "trash",
        "menu": "File"
      },
      "literals": {}
    },
    {
      "id": "n172",
      "block": "text.format",
      "name": "Question",
      "position": {
        "x": 3240,
        "y": 4470
      },
      "config": {},
      "literals": {
        "template": "Delete the board {a}? This cannot be undone."
      }
    },
    {
      "id": "n173",
      "block": "app.confirm",
      "name": "Ask before deleting the board",
      "position": {
        "x": 3570,
        "y": 4356
      },
      "config": {
        "danger": true,
        "yes": "Delete"
      },
      "literals": {}
    },
    {
      "id": "n174",
      "block": "file.delete",
      "name": "Delete its file",
      "position": {
        "x": 3900,
        "y": 4356
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n175",
      "block": "state.set",
      "name": "Forget its changes",
      "position": {
        "x": 3900,
        "y": 4566
      },
      "config": {
        "limit": 0,
        "mode": "replace",
        "variable": "n43"
      },
      "literals": {}
    },
    {
      "id": "n176",
      "block": "system.now",
      "name": "Today",
      "position": {
        "x": 3240,
        "y": 4864
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n177",
      "block": "text.add_days",
      "name": "Tomorrow",
      "position": {
        "x": 3570,
        "y": 4864
      },
      "config": {},
      "literals": {
        "days": 1
      }
    },
    {
      "id": "n178",
      "block": "text.add_days",
      "name": "Yesterday",
      "position": {
        "x": 3570,
        "y": 5010
      },
      "config": {},
      "literals": {
        "days": -1
      }
    },
    {
      "id": "n179",
      "block": "text.add_days",
      "name": "Next week",
      "position": {
        "x": 3570,
        "y": 5156
      },
      "config": {},
      "literals": {
        "days": 7
      }
    },
    {
      "id": "n180",
      "block": "text.format",
      "name": "Getting started file",
      "position": {
        "x": 3570,
        "y": 5302
      },
      "config": {},
      "literals": {
        "template": "{a}/Getting started.json"
      }
    },
    {
      "id": "n181",
      "block": "value.text",
      "name": "Getting started labels",
      "position": {
        "x": 3570,
        "y": 5512
      },
      "config": {
        "value": "[\n  { \"id\": \"red\", \"name\": \"Bug\", \"color\": \"red\" },\n  { \"id\": \"orange\", \"name\": \"Urgent\", \"color\": \"orange\" },\n  { \"id\": \"yellow\", \"name\": \"Idea\", \"color\": \"yellow\" },\n  { \"id\": \"green\", \"name\": \"Ready\", \"color\": \"green\" },\n  { \"id\": \"blue\", \"name\": \"Design\", \"color\": \"blue\" },\n  { \"id\": \"purple\", \"name\": \"Research\", \"color\": \"purple\" }\n]\n"
      },
      "literals": {}
    },
    {
      "id": "n182",
      "block": "text.format",
      "name": "Getting started To do",
      "position": {
        "x": 3900,
        "y": 4864
      },
      "config": {},
      "literals": {
        "template": "{\n  \"id\": \"col1\",\n  \"title\": \"To do\",\n  \"cards\": [\n    {\n      \"id\": \"c1\",\n      \"title\": \"Drag a card to another column\",\n      \"notes\": \"Hold the mouse button down on a card and move it. A gap shows where it will land.\\n\\nAlt and the arrow keys move the picked card too.\",\n      \"labels\": []\n    },\n    {\n      \"id\": \"c2\",\n      \"title\": \"Plan the launch\",\n      \"notes\": \"Due tomorrow, so the date shows amber.\",\n      \"labels\": [\"orange\", \"blue\"],\n      \"due\": \"{a}\",\n      \"priority\": \"high\",\n      \"checklist\": [\n        { \"text\": \"Pick a date\", \"done\": true },\n        { \"text\": \"Book the room\", \"done\": false },\n        { \"text\": \"Tell the team\", \"done\": false }\n      ]\n    },\n    { \"id\": \"c3\", \"title\": \"Try a dark theme\", \"notes\": \"\", \"labels\": [\"yellow\"], \"due\": \"{c}\" }\n  ]\n}"
      }
    },
    {
      "id": "n183",
      "block": "text.format",
      "name": "Getting started Doing",
      "position": {
        "x": 3900,
        "y": 5074
      },
      "config": {},
      "literals": {
        "template": "{\n  \"id\": \"col2\",\n  \"title\": \"Doing\",\n  \"limit\": 3,\n  \"cards\": [\n    {\n      \"id\": \"c4\",\n      \"title\": \"Click a card to open it\",\n      \"notes\": \"The panel on the right changes the title, the column, the labels, the due date, the priority, the checklist and these notes.\\n\\nNotes use **Markdown**.\",\n      \"labels\": [\"green\"]\n    },\n    {\n      \"id\": \"c5\",\n      \"title\": \"Fix the sign-in bug\",\n      \"notes\": \"The due date has passed, so it shows red.\",\n      \"labels\": [\"red\", \"orange\"],\n      \"due\": \"{b}\",\n      \"priority\": \"medium\"\n    }\n  ]\n}"
      }
    },
    {
      "id": "n184",
      "block": "text.format",
      "name": "Getting started board",
      "position": {
        "x": 4230,
        "y": 4864
      },
      "config": {},
      "literals": {
        "template": "{\n  \"version\": 1,\n  \"title\": \"Getting started\",\n  \"labels\": {a},\n  \"columns\": [\n    {b},\n    {c},\n    {\n      \"id\": \"col3\",\n      \"title\": \"Done\",\n      \"cards\": [\n        { \"id\": \"c6\", \"title\": \"Make a board\", \"notes\": \"\", \"labels\": [\"green\"] },\n        {\n          \"id\": \"c7\",\n          \"title\": \"Archive a card\",\n          \"notes\": \"Archived cards leave the board. Pick one in the Archived list to put it back.\",\n          \"labels\": [],\n          \"archived\": true\n        }\n      ]\n    }\n  ]\n}\n"
      }
    },
    {
      "id": "n185",
      "block": "file.write",
      "name": "Write the Getting started board",
      "position": {
        "x": 4560,
        "y": 4864
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n186",
      "block": "flow.when",
      "name": "Only when it was written",
      "position": {
        "x": 4890,
        "y": 4864
      },
      "config": {},
      "literals": {}
    }
  ],
  "edges": [
    {
      "id": "e187",
      "from": "n1",
      "to": "n3",
      "input": "a"
    },
    {
      "id": "e188",
      "from": "n2",
      "to": "n4",
      "input": "when"
    },
    {
      "id": "e189",
      "from": "n3",
      "to": "n4",
      "input": "path"
    },
    {
      "id": "e190",
      "from": "n4",
      "output": "text",
      "to": "n5",
      "input": "text"
    },
    {
      "id": "e191",
      "from": "n4",
      "output": "done",
      "to": "n8",
      "input": "when"
    },
    {
      "id": "e192",
      "from": "n5",
      "to": "n8",
      "input": "to"
    },
    {
      "id": "e193",
      "from": "n4",
      "output": "done",
      "to": "n9",
      "input": "a"
    },
    {
      "id": "e194",
      "from": "n6",
      "output": "then",
      "to": "n9",
      "input": "b"
    },
    {
      "id": "e195",
      "from": "n9",
      "output": "then",
      "to": "n10",
      "input": "when"
    },
    {
      "id": "e196",
      "from": "n1",
      "to": "n10",
      "input": "path"
    },
    {
      "id": "e197",
      "from": "n10",
      "output": "names",
      "to": "n11",
      "input": "list"
    },
    {
      "id": "e198",
      "from": "n10",
      "output": "done",
      "to": "n12",
      "input": "when"
    },
    {
      "id": "e199",
      "from": "n11",
      "to": "n12",
      "input": "to"
    },
    {
      "id": "e200",
      "from": "n13",
      "to": "n21",
      "input": "items"
    },
    {
      "id": "e201",
      "from": "n11",
      "to": "n14",
      "input": "list"
    },
    {
      "id": "e202",
      "from": "n14",
      "to": "n17",
      "input": "a"
    },
    {
      "id": "e203",
      "from": "n10",
      "output": "done",
      "to": "n19",
      "input": "when"
    },
    {
      "id": "e204",
      "from": "n17",
      "to": "n19",
      "input": "test"
    },
    {
      "id": "e205",
      "from": "n11",
      "to": "n15",
      "input": "list"
    },
    {
      "id": "e206",
      "from": "n7",
      "to": "n15",
      "input": "item"
    },
    {
      "id": "e207",
      "from": "n11",
      "to": "n16",
      "input": "list"
    },
    {
      "id": "e208",
      "from": "n15",
      "to": "n18",
      "input": "when"
    },
    {
      "id": "e209",
      "from": "n7",
      "to": "n18",
      "input": "then"
    },
    {
      "id": "e210",
      "from": "n16",
      "to": "n18",
      "input": "otherwise"
    },
    {
      "id": "e211",
      "from": "n19",
      "output": "no",
      "to": "n20",
      "input": "when"
    },
    {
      "id": "e212",
      "from": "n18",
      "to": "n20",
      "input": "to"
    },
    {
      "id": "e213",
      "from": "n19",
      "output": "no",
      "to": "n23",
      "input": "a"
    },
    {
      "id": "e214",
      "from": "n21",
      "output": "picked",
      "to": "n22",
      "input": "when"
    },
    {
      "id": "e215",
      "from": "n21",
      "to": "n22",
      "input": "to"
    },
    {
      "id": "e216",
      "from": "n21",
      "output": "picked",
      "to": "n23",
      "input": "b"
    },
    {
      "id": "e217",
      "from": "n23",
      "output": "then",
      "to": "n21",
      "input": "set"
    },
    {
      "id": "e218",
      "from": "n23",
      "output": "then",
      "to": "n27",
      "input": "when"
    },
    {
      "id": "e219",
      "from": "n7",
      "to": "n21",
      "input": "to"
    },
    {
      "id": "e220",
      "from": "n1",
      "to": "n24",
      "input": "a"
    },
    {
      "id": "e221",
      "from": "n7",
      "to": "n24",
      "input": "b"
    },
    {
      "id": "e222",
      "from": "n24",
      "to": "n26",
      "input": "a"
    },
    {
      "id": "e223",
      "from": "n25",
      "to": "n26",
      "input": "b"
    },
    {
      "id": "e224",
      "from": "n23",
      "output": "then",
      "to": "n28",
      "input": "when"
    },
    {
      "id": "e225",
      "from": "n26",
      "to": "n28",
      "input": "test"
    },
    {
      "id": "e226",
      "from": "n28",
      "output": "yes",
      "to": "n29",
      "input": "when"
    },
    {
      "id": "e227",
      "from": "n24",
      "to": "n29",
      "input": "path"
    },
    {
      "id": "e228",
      "from": "n29",
      "output": "text",
      "to": "n30",
      "input": "text"
    },
    {
      "id": "e229",
      "from": "n29",
      "output": "done",
      "to": "n31",
      "input": "when"
    },
    {
      "id": "e230",
      "from": "n30",
      "output": "ok",
      "to": "n31",
      "input": "test"
    },
    {
      "id": "e231",
      "from": "n31",
      "output": "no",
      "to": "n33",
      "input": "when"
    },
    {
      "id": "e232",
      "from": "n31",
      "output": "yes",
      "to": "n32",
      "input": "when"
    },
    {
      "id": "e233",
      "from": "n32",
      "output": "first",
      "to": "n42",
      "input": "b"
    },
    {
      "id": "e234",
      "from": "n32",
      "output": "second",
      "to": "n34",
      "input": "when"
    },
    {
      "id": "e235",
      "from": "n30",
      "to": "n34",
      "input": "to"
    },
    {
      "id": "e236",
      "from": "n32",
      "output": "second",
      "to": "n35",
      "input": "when"
    },
    {
      "id": "e237",
      "from": "n24",
      "to": "n35",
      "input": "to"
    },
    {
      "id": "e238",
      "from": "n3",
      "to": "n27",
      "input": "path"
    },
    {
      "id": "e239",
      "from": "n7",
      "to": "n27",
      "input": "text"
    },
    {
      "id": "e240",
      "from": "n32",
      "output": "third",
      "to": "n36",
      "input": "when"
    },
    {
      "id": "e241",
      "from": "n39",
      "to": "n36",
      "input": "to"
    },
    {
      "id": "e242",
      "from": "n32",
      "output": "third",
      "to": "n135",
      "input": "clear"
    },
    {
      "id": "e243",
      "from": "n32",
      "output": "third",
      "to": "n48",
      "input": "a"
    },
    {
      "id": "e244",
      "from": "n32",
      "output": "third",
      "to": "n38",
      "input": "a"
    },
    {
      "id": "e245",
      "from": "n32",
      "output": "third",
      "to": "n59",
      "input": "set"
    },
    {
      "id": "e246",
      "from": "n37",
      "to": "n39",
      "input": "value"
    },
    {
      "id": "e247",
      "from": "n39",
      "to": "n40",
      "input": "value"
    },
    {
      "id": "e248",
      "from": "n40",
      "output": "changed",
      "to": "n41",
      "input": "when"
    },
    {
      "id": "e249",
      "from": "n41",
      "output": "then",
      "to": "n42",
      "input": "a"
    },
    {
      "id": "e250",
      "from": "n39",
      "to": "n44",
      "input": "a"
    },
    {
      "id": "e251",
      "from": "n43",
      "to": "n44",
      "input": "b"
    },
    {
      "id": "e252",
      "from": "n42",
      "output": "then",
      "to": "n45",
      "input": "when"
    },
    {
      "id": "e253",
      "from": "n44",
      "to": "n45",
      "input": "test"
    },
    {
      "id": "e254",
      "from": "n45",
      "output": "yes",
      "to": "n46",
      "input": "when"
    },
    {
      "id": "e255",
      "from": "n25",
      "to": "n46",
      "input": "path"
    },
    {
      "id": "e256",
      "from": "n39",
      "to": "n46",
      "input": "text"
    },
    {
      "id": "e257",
      "from": "n45",
      "output": "yes",
      "to": "n47",
      "input": "when"
    },
    {
      "id": "e258",
      "from": "n39",
      "to": "n47",
      "input": "to"
    },
    {
      "id": "e259",
      "from": "n37",
      "to": "n49",
      "input": "value"
    },
    {
      "id": "e260",
      "from": "n48",
      "output": "then",
      "to": "n50",
      "input": "set"
    },
    {
      "id": "e261",
      "from": "n49",
      "to": "n50",
      "input": "to"
    },
    {
      "id": "e262",
      "from": "n37",
      "to": "n51",
      "input": "record"
    },
    {
      "id": "e263",
      "from": "n50",
      "to": "n51",
      "input": "value"
    },
    {
      "id": "e264",
      "from": "n50",
      "output": "changed",
      "to": "n52",
      "input": "when"
    },
    {
      "id": "e265",
      "from": "n51",
      "to": "n52",
      "input": "to"
    },
    {
      "id": "e266",
      "from": "n55",
      "to": "n74",
      "input": "filter"
    },
    {
      "id": "e267",
      "from": "n71",
      "to": "n54",
      "input": "list"
    },
    {
      "id": "e268",
      "from": "n54",
      "to": "n56",
      "input": "list"
    },
    {
      "id": "e269",
      "from": "n56",
      "to": "n58",
      "input": "list"
    },
    {
      "id": "e270",
      "from": "n58",
      "to": "n59",
      "input": "options"
    },
    {
      "id": "e271",
      "from": "n54",
      "to": "n57",
      "input": "list"
    },
    {
      "id": "e272",
      "from": "n59",
      "output": "position",
      "to": "n60",
      "input": "a"
    },
    {
      "id": "e273",
      "from": "n57",
      "to": "n61",
      "input": "list"
    },
    {
      "id": "e274",
      "from": "n60",
      "to": "n61",
      "input": "position"
    },
    {
      "id": "e275",
      "from": "n61",
      "to": "n74",
      "input": "only_tag"
    },
    {
      "id": "e276",
      "from": "n62",
      "to": "n63",
      "input": "when"
    },
    {
      "id": "e277",
      "from": "n63",
      "output": "answered",
      "to": "n64",
      "input": "when"
    },
    {
      "id": "e278",
      "from": "n64",
      "output": "ms",
      "to": "n65",
      "input": "a"
    },
    {
      "id": "e279",
      "from": "n65",
      "to": "n66",
      "input": "v1"
    },
    {
      "id": "e280",
      "from": "n63",
      "output": "text",
      "to": "n66",
      "input": "v2"
    },
    {
      "id": "e281",
      "from": "n70",
      "to": "n67",
      "input": "list"
    },
    {
      "id": "e282",
      "from": "n66",
      "to": "n67",
      "input": "item"
    },
    {
      "id": "e283",
      "from": "n37",
      "to": "n68",
      "input": "record"
    },
    {
      "id": "e284",
      "from": "n67",
      "to": "n68",
      "input": "value"
    },
    {
      "id": "e285",
      "from": "n64",
      "output": "then",
      "to": "n69",
      "input": "when"
    },
    {
      "id": "e286",
      "from": "n68",
      "to": "n69",
      "input": "to"
    },
    {
      "id": "e287",
      "from": "n37",
      "to": "n70",
      "input": "value"
    },
    {
      "id": "e288",
      "from": "n37",
      "to": "n71",
      "input": "value"
    },
    {
      "id": "e289",
      "from": "n70",
      "to": "n74",
      "input": "lanes"
    },
    {
      "id": "e290",
      "from": "n71",
      "to": "n74",
      "input": "tags"
    },
    {
      "id": "e291",
      "from": "n37",
      "to": "n75",
      "input": "record"
    },
    {
      "id": "e292",
      "from": "n74",
      "to": "n75",
      "input": "value"
    },
    {
      "id": "e293",
      "from": "n74",
      "output": "changed",
      "to": "n76",
      "input": "when"
    },
    {
      "id": "e294",
      "from": "n75",
      "to": "n76",
      "input": "to"
    },
    {
      "id": "e295",
      "from": "n72",
      "to": "n74",
      "input": "add"
    },
    {
      "id": "e296",
      "from": "n74",
      "output": "lane",
      "to": "n73",
      "input": "a"
    },
    {
      "id": "e297",
      "from": "n73",
      "to": "n74",
      "input": "lane"
    },
    {
      "id": "e298",
      "from": "n74",
      "output": "count",
      "to": "n77",
      "input": "a"
    },
    {
      "id": "e299",
      "from": "n77",
      "to": "n78",
      "input": "when"
    },
    {
      "id": "e300",
      "from": "n74",
      "output": "count",
      "to": "n79",
      "input": "a"
    },
    {
      "id": "e301",
      "from": "n74",
      "output": "overdue",
      "to": "n79",
      "input": "b"
    },
    {
      "id": "e302",
      "from": "n78",
      "to": "n79",
      "input": "c"
    },
    {
      "id": "e303",
      "from": "n79",
      "to": "n80",
      "input": "text"
    },
    {
      "id": "e304",
      "from": "n37",
      "to": "n81",
      "input": "data"
    },
    {
      "id": "e305",
      "from": "n74",
      "output": "item_id",
      "to": "n81",
      "input": "value"
    },
    {
      "id": "e306",
      "from": "n74",
      "output": "item_id",
      "to": "n82",
      "input": "value"
    },
    {
      "id": "e307",
      "from": "n82",
      "output": "changed",
      "to": "n83",
      "input": "a"
    },
    {
      "id": "e308",
      "from": "n48",
      "output": "then",
      "to": "n83",
      "input": "b"
    },
    {
      "id": "e309",
      "from": "n81",
      "to": "n84",
      "input": "value"
    },
    {
      "id": "e310",
      "from": "n83",
      "output": "then",
      "to": "n85",
      "input": "set"
    },
    {
      "id": "e311",
      "from": "n84",
      "to": "n85",
      "input": "to"
    },
    {
      "id": "e312",
      "from": "n81",
      "output": "found",
      "to": "n85",
      "input": "visible"
    },
    {
      "id": "e313",
      "from": "n37",
      "to": "n86",
      "input": "data"
    },
    {
      "id": "e314",
      "from": "n74",
      "output": "item_id",
      "to": "n86",
      "input": "match"
    },
    {
      "id": "e315",
      "from": "n85",
      "to": "n86",
      "input": "value"
    },
    {
      "id": "e316",
      "from": "n85",
      "output": "changed",
      "to": "n87",
      "input": "when"
    },
    {
      "id": "e317",
      "from": "n86",
      "to": "n87",
      "input": "to"
    },
    {
      "id": "e318",
      "from": "n70",
      "to": "n88",
      "input": "list"
    },
    {
      "id": "e319",
      "from": "n88",
      "to": "n89",
      "input": "list"
    },
    {
      "id": "e320",
      "from": "n74",
      "output": "lane",
      "to": "n89",
      "input": "position"
    },
    {
      "id": "e321",
      "from": "n88",
      "to": "n90",
      "input": "options"
    },
    {
      "id": "e322",
      "from": "n83",
      "output": "then",
      "to": "n90",
      "input": "set"
    },
    {
      "id": "e323",
      "from": "n89",
      "to": "n90",
      "input": "to"
    },
    {
      "id": "e324",
      "from": "n81",
      "output": "found",
      "to": "n90",
      "input": "visible"
    },
    {
      "id": "e325",
      "from": "n37",
      "to": "n91",
      "input": "data"
    },
    {
      "id": "e326",
      "from": "n74",
      "output": "item_id",
      "to": "n91",
      "input": "match"
    },
    {
      "id": "e327",
      "from": "n90",
      "output": "position",
      "to": "n92",
      "input": "a"
    },
    {
      "id": "e328",
      "from": "n91",
      "to": "n93",
      "input": "value"
    },
    {
      "id": "e329",
      "from": "n92",
      "to": "n93",
      "input": "path"
    },
    {
      "id": "e330",
      "from": "n93",
      "to": "n94",
      "input": "list"
    },
    {
      "id": "e331",
      "from": "n81",
      "to": "n94",
      "input": "item"
    },
    {
      "id": "e332",
      "from": "n91",
      "to": "n95",
      "input": "data"
    },
    {
      "id": "e333",
      "from": "n92",
      "to": "n95",
      "input": "path"
    },
    {
      "id": "e334",
      "from": "n94",
      "to": "n95",
      "input": "value"
    },
    {
      "id": "e335",
      "from": "n90",
      "output": "changed",
      "to": "n96",
      "input": "when"
    },
    {
      "id": "e336",
      "from": "n95",
      "to": "n96",
      "input": "to"
    },
    {
      "id": "e337",
      "from": "n81",
      "to": "n97",
      "input": "value"
    },
    {
      "id": "e338",
      "from": "n71",
      "to": "n98",
      "input": "options"
    },
    {
      "id": "e339",
      "from": "n97",
      "to": "n98",
      "input": "selected"
    },
    {
      "id": "e340",
      "from": "n81",
      "output": "found",
      "to": "n98",
      "input": "visible"
    },
    {
      "id": "e341",
      "from": "n37",
      "to": "n99",
      "input": "data"
    },
    {
      "id": "e342",
      "from": "n74",
      "output": "item_id",
      "to": "n99",
      "input": "match"
    },
    {
      "id": "e343",
      "from": "n98",
      "to": "n99",
      "input": "value"
    },
    {
      "id": "e344",
      "from": "n98",
      "output": "changed",
      "to": "n101",
      "input": "when"
    },
    {
      "id": "e345",
      "from": "n99",
      "to": "n101",
      "input": "to"
    },
    {
      "id": "e346",
      "from": "n37",
      "to": "n100",
      "input": "record"
    },
    {
      "id": "e347",
      "from": "n98",
      "output": "options_value",
      "to": "n100",
      "input": "value"
    },
    {
      "id": "e348",
      "from": "n98",
      "output": "options_changed",
      "to": "n102",
      "input": "when"
    },
    {
      "id": "e349",
      "from": "n100",
      "to": "n102",
      "input": "to"
    },
    {
      "id": "e350",
      "from": "n81",
      "to": "n103",
      "input": "value"
    },
    {
      "id": "e351",
      "from": "n83",
      "output": "then",
      "to": "n104",
      "input": "set"
    },
    {
      "id": "e352",
      "from": "n103",
      "to": "n104",
      "input": "to"
    },
    {
      "id": "e353",
      "from": "n81",
      "output": "found",
      "to": "n104",
      "input": "visible"
    },
    {
      "id": "e354",
      "from": "n37",
      "to": "n105",
      "input": "data"
    },
    {
      "id": "e355",
      "from": "n74",
      "output": "item_id",
      "to": "n105",
      "input": "match"
    },
    {
      "id": "e356",
      "from": "n104",
      "to": "n105",
      "input": "value"
    },
    {
      "id": "e357",
      "from": "n104",
      "output": "changed",
      "to": "n106",
      "input": "when"
    },
    {
      "id": "e358",
      "from": "n105",
      "to": "n106",
      "input": "to"
    },
    {
      "id": "e359",
      "from": "n81",
      "to": "n108",
      "input": "value"
    },
    {
      "id": "e360",
      "from": "n107",
      "to": "n109",
      "input": "list"
    },
    {
      "id": "e361",
      "from": "n108",
      "to": "n109",
      "input": "item"
    },
    {
      "id": "e362",
      "from": "n109",
      "to": "n110",
      "input": "when"
    },
    {
      "id": "e363",
      "from": "n108",
      "to": "n110",
      "input": "then"
    },
    {
      "id": "e364",
      "from": "n107",
      "to": "n111",
      "input": "options"
    },
    {
      "id": "e365",
      "from": "n83",
      "output": "then",
      "to": "n111",
      "input": "set"
    },
    {
      "id": "e366",
      "from": "n110",
      "to": "n111",
      "input": "to"
    },
    {
      "id": "e367",
      "from": "n81",
      "output": "found",
      "to": "n111",
      "input": "visible"
    },
    {
      "id": "e368",
      "from": "n37",
      "to": "n112",
      "input": "data"
    },
    {
      "id": "e369",
      "from": "n74",
      "output": "item_id",
      "to": "n112",
      "input": "match"
    },
    {
      "id": "e370",
      "from": "n111",
      "to": "n112",
      "input": "value"
    },
    {
      "id": "e371",
      "from": "n111",
      "output": "changed",
      "to": "n113",
      "input": "when"
    },
    {
      "id": "e372",
      "from": "n112",
      "to": "n113",
      "input": "to"
    },
    {
      "id": "e373",
      "from": "n81",
      "to": "n114",
      "input": "value"
    },
    {
      "id": "e374",
      "from": "n114",
      "to": "n115",
      "input": "items"
    },
    {
      "id": "e375",
      "from": "n81",
      "output": "found",
      "to": "n115",
      "input": "visible"
    },
    {
      "id": "e376",
      "from": "n37",
      "to": "n116",
      "input": "data"
    },
    {
      "id": "e377",
      "from": "n74",
      "output": "item_id",
      "to": "n116",
      "input": "match"
    },
    {
      "id": "e378",
      "from": "n115",
      "to": "n116",
      "input": "value"
    },
    {
      "id": "e379",
      "from": "n115",
      "output": "changed",
      "to": "n117",
      "input": "when"
    },
    {
      "id": "e380",
      "from": "n116",
      "to": "n117",
      "input": "to"
    },
    {
      "id": "e381",
      "from": "n81",
      "to": "n118",
      "input": "value"
    },
    {
      "id": "e382",
      "from": "n83",
      "output": "then",
      "to": "n119",
      "input": "set"
    },
    {
      "id": "e383",
      "from": "n118",
      "to": "n119",
      "input": "to"
    },
    {
      "id": "e384",
      "from": "n81",
      "output": "found",
      "to": "n119",
      "input": "visible"
    },
    {
      "id": "e385",
      "from": "n37",
      "to": "n120",
      "input": "data"
    },
    {
      "id": "e386",
      "from": "n74",
      "output": "item_id",
      "to": "n120",
      "input": "match"
    },
    {
      "id": "e387",
      "from": "n119",
      "to": "n120",
      "input": "value"
    },
    {
      "id": "e388",
      "from": "n119",
      "output": "changed",
      "to": "n121",
      "input": "when"
    },
    {
      "id": "e389",
      "from": "n120",
      "to": "n121",
      "input": "to"
    },
    {
      "id": "e390",
      "from": "n81",
      "output": "found",
      "to": "n122",
      "input": "visible"
    },
    {
      "id": "e391",
      "from": "n37",
      "to": "n125",
      "input": "data"
    },
    {
      "id": "e392",
      "from": "n74",
      "output": "item_id",
      "to": "n125",
      "input": "match"
    },
    {
      "id": "e393",
      "from": "n122",
      "to": "n127",
      "input": "when"
    },
    {
      "id": "e394",
      "from": "n125",
      "to": "n127",
      "input": "to"
    },
    {
      "id": "e395",
      "from": "n81",
      "output": "found",
      "to": "n123",
      "input": "visible"
    },
    {
      "id": "e396",
      "from": "n123",
      "to": "n126",
      "input": "when"
    },
    {
      "id": "e397",
      "from": "n126",
      "output": "yes",
      "to": "n128",
      "input": "when"
    },
    {
      "id": "e398",
      "from": "n91",
      "to": "n128",
      "input": "to"
    },
    {
      "id": "e399",
      "from": "n81",
      "output": "found",
      "to": "n124",
      "input": "visible"
    },
    {
      "id": "e400",
      "from": "n124",
      "to": "n38",
      "input": "b"
    },
    {
      "id": "e401",
      "from": "n38",
      "output": "then",
      "to": "n74",
      "input": "select"
    },
    {
      "id": "e402",
      "from": "n129",
      "to": "n133",
      "input": "a"
    },
    {
      "id": "e403",
      "from": "n130",
      "to": "n133",
      "input": "b"
    },
    {
      "id": "e404",
      "from": "n131",
      "to": "n134",
      "input": "a"
    },
    {
      "id": "e405",
      "from": "n132",
      "to": "n134",
      "input": "b"
    },
    {
      "id": "e406",
      "from": "n133",
      "output": "then",
      "to": "n135",
      "input": "undo"
    },
    {
      "id": "e407",
      "from": "n134",
      "output": "then",
      "to": "n135",
      "input": "redo"
    },
    {
      "id": "e408",
      "from": "n135",
      "output": "can_undo",
      "to": "n129",
      "input": "enabled"
    },
    {
      "id": "e409",
      "from": "n135",
      "output": "can_redo",
      "to": "n131",
      "input": "enabled"
    },
    {
      "id": "e410",
      "from": "n135",
      "output": "changed",
      "to": "n48",
      "input": "b"
    },
    {
      "id": "e411",
      "from": "n37",
      "to": "n136",
      "input": "data"
    },
    {
      "id": "e412",
      "from": "n136",
      "to": "n137",
      "input": "items"
    },
    {
      "id": "e413",
      "from": "n137",
      "to": "n139",
      "input": "value"
    },
    {
      "id": "e414",
      "from": "n37",
      "to": "n140",
      "input": "data"
    },
    {
      "id": "e415",
      "from": "n139",
      "to": "n140",
      "input": "match"
    },
    {
      "id": "e416",
      "from": "n137",
      "output": "picked",
      "to": "n138",
      "input": "when"
    },
    {
      "id": "e417",
      "from": "n138",
      "output": "first",
      "to": "n141",
      "input": "when"
    },
    {
      "id": "e418",
      "from": "n140",
      "to": "n141",
      "input": "to"
    },
    {
      "id": "e419",
      "from": "n138",
      "output": "second",
      "to": "n137",
      "input": "set"
    },
    {
      "id": "e420",
      "from": "n53",
      "to": "n55",
      "input": "focus"
    },
    {
      "id": "e421",
      "from": "n142",
      "to": "n144",
      "input": "a"
    },
    {
      "id": "e422",
      "from": "n143",
      "to": "n144",
      "input": "b"
    },
    {
      "id": "e423",
      "from": "n144",
      "output": "then",
      "to": "n145",
      "input": "when"
    },
    {
      "id": "e424",
      "from": "n145",
      "output": "text",
      "to": "n146",
      "input": "text"
    },
    {
      "id": "e425",
      "from": "n13",
      "to": "n147",
      "input": "list"
    },
    {
      "id": "e426",
      "from": "n147",
      "to": "n148",
      "input": "list"
    },
    {
      "id": "e427",
      "from": "n146",
      "to": "n148",
      "input": "value"
    },
    {
      "id": "e428",
      "from": "n148",
      "to": "n150",
      "input": "list"
    },
    {
      "id": "e429",
      "from": "n150",
      "to": "n153",
      "input": "a"
    },
    {
      "id": "e430",
      "from": "n145",
      "output": "answered",
      "to": "n154",
      "input": "when"
    },
    {
      "id": "e431",
      "from": "n153",
      "to": "n154",
      "input": "test"
    },
    {
      "id": "e432",
      "from": "n154",
      "output": "no",
      "to": "n157",
      "input": "when"
    },
    {
      "id": "e433",
      "from": "n146",
      "to": "n149",
      "input": "value"
    },
    {
      "id": "e434",
      "from": "n149",
      "to": "n151",
      "input": "a"
    },
    {
      "id": "e435",
      "from": "n1",
      "to": "n152",
      "input": "a"
    },
    {
      "id": "e436",
      "from": "n146",
      "to": "n152",
      "input": "b"
    },
    {
      "id": "e437",
      "from": "n154",
      "output": "yes",
      "to": "n155",
      "input": "when"
    },
    {
      "id": "e438",
      "from": "n152",
      "to": "n155",
      "input": "path"
    },
    {
      "id": "e439",
      "from": "n151",
      "to": "n155",
      "input": "text"
    },
    {
      "id": "e440",
      "from": "n154",
      "output": "yes",
      "to": "n156",
      "input": "when"
    },
    {
      "id": "e441",
      "from": "n146",
      "to": "n156",
      "input": "to"
    },
    {
      "id": "e442",
      "from": "n155",
      "output": "done",
      "to": "n6",
      "input": "a"
    },
    {
      "id": "e443",
      "from": "n158",
      "to": "n159",
      "input": "when"
    },
    {
      "id": "e444",
      "from": "n7",
      "to": "n159",
      "input": "value"
    },
    {
      "id": "e445",
      "from": "n159",
      "output": "text",
      "to": "n160",
      "input": "text"
    },
    {
      "id": "e446",
      "from": "n160",
      "to": "n161",
      "input": "a"
    },
    {
      "id": "e447",
      "from": "n159",
      "output": "answered",
      "to": "n163",
      "input": "when"
    },
    {
      "id": "e448",
      "from": "n161",
      "to": "n163",
      "input": "test"
    },
    {
      "id": "e449",
      "from": "n1",
      "to": "n162",
      "input": "a"
    },
    {
      "id": "e450",
      "from": "n160",
      "to": "n162",
      "input": "b"
    },
    {
      "id": "e451",
      "from": "n163",
      "output": "yes",
      "to": "n164",
      "input": "when"
    },
    {
      "id": "e452",
      "from": "n25",
      "to": "n164",
      "input": "from"
    },
    {
      "id": "e453",
      "from": "n162",
      "to": "n164",
      "input": "to"
    },
    {
      "id": "e454",
      "from": "n164",
      "output": "done",
      "to": "n165",
      "input": "when"
    },
    {
      "id": "e455",
      "from": "n164",
      "output": "ok",
      "to": "n165",
      "input": "test"
    },
    {
      "id": "e456",
      "from": "n165",
      "output": "no",
      "to": "n170",
      "input": "when"
    },
    {
      "id": "e457",
      "from": "n165",
      "output": "yes",
      "to": "n167",
      "input": "when"
    },
    {
      "id": "e458",
      "from": "n160",
      "to": "n167",
      "input": "to"
    },
    {
      "id": "e459",
      "from": "n165",
      "output": "yes",
      "to": "n168",
      "input": "when"
    },
    {
      "id": "e460",
      "from": "n162",
      "to": "n168",
      "input": "to"
    },
    {
      "id": "e461",
      "from": "n37",
      "to": "n166",
      "input": "record"
    },
    {
      "id": "e462",
      "from": "n160",
      "to": "n166",
      "input": "value"
    },
    {
      "id": "e463",
      "from": "n165",
      "output": "yes",
      "to": "n169",
      "input": "when"
    },
    {
      "id": "e464",
      "from": "n166",
      "to": "n169",
      "input": "to"
    },
    {
      "id": "e465",
      "from": "n165",
      "output": "yes",
      "to": "n6",
      "input": "b"
    },
    {
      "id": "e466",
      "from": "n165",
      "output": "yes",
      "to": "n48",
      "input": "c"
    },
    {
      "id": "e467",
      "from": "n7",
      "to": "n172",
      "input": "a"
    },
    {
      "id": "e468",
      "from": "n171",
      "to": "n173",
      "input": "when"
    },
    {
      "id": "e469",
      "from": "n172",
      "to": "n173",
      "input": "message"
    },
    {
      "id": "e470",
      "from": "n173",
      "output": "yes",
      "to": "n174",
      "input": "when"
    },
    {
      "id": "e471",
      "from": "n25",
      "to": "n174",
      "input": "path"
    },
    {
      "id": "e472",
      "from": "n173",
      "output": "yes",
      "to": "n175",
      "input": "when"
    },
    {
      "id": "e473",
      "from": "n39",
      "to": "n175",
      "input": "to"
    },
    {
      "id": "e474",
      "from": "n174",
      "output": "done",
      "to": "n9",
      "input": "c"
    },
    {
      "id": "e475",
      "from": "n19",
      "output": "yes",
      "to": "n176",
      "input": "when"
    },
    {
      "id": "e476",
      "from": "n176",
      "output": "date",
      "to": "n177",
      "input": "date"
    },
    {
      "id": "e477",
      "from": "n176",
      "output": "date",
      "to": "n178",
      "input": "date"
    },
    {
      "id": "e478",
      "from": "n176",
      "output": "date",
      "to": "n179",
      "input": "date"
    },
    {
      "id": "e479",
      "from": "n177",
      "to": "n182",
      "input": "a"
    },
    {
      "id": "e480",
      "from": "n179",
      "to": "n182",
      "input": "c"
    },
    {
      "id": "e481",
      "from": "n178",
      "to": "n183",
      "input": "b"
    },
    {
      "id": "e482",
      "from": "n181",
      "to": "n184",
      "input": "a"
    },
    {
      "id": "e483",
      "from": "n182",
      "to": "n184",
      "input": "b"
    },
    {
      "id": "e484",
      "from": "n183",
      "to": "n184",
      "input": "c"
    },
    {
      "id": "e485",
      "from": "n1",
      "to": "n180",
      "input": "a"
    },
    {
      "id": "e486",
      "from": "n176",
      "output": "then",
      "to": "n185",
      "input": "when"
    },
    {
      "id": "e487",
      "from": "n180",
      "to": "n185",
      "input": "path"
    },
    {
      "id": "e488",
      "from": "n184",
      "to": "n185",
      "input": "text"
    },
    {
      "id": "e489",
      "from": "n185",
      "output": "done",
      "to": "n186",
      "input": "when"
    },
    {
      "id": "e490",
      "from": "n185",
      "output": "ok",
      "to": "n186",
      "input": "test"
    },
    {
      "id": "e491",
      "from": "n186",
      "output": "yes",
      "to": "n6",
      "input": "c"
    }
  ],
  "next_id": 492,
  "layout": {
    "id": "root",
    "kind": "column",
    "children": [
      {
        "id": "main",
        "kind": "row",
        "grow": true,
        "children": [
          {
            "id": "side",
            "kind": "column",
            "width": 220,
            "children": [
              {
                "node": "n21",
                "grow": true
              },
              {
                "node": "n142"
              },
              {
                "node": "n137",
                "height": 200
              }
            ]
          },
          {
            "id": "middle",
            "kind": "column",
            "grow": true,
            "children": [
              {
                "node": "n50"
              },
              {
                "id": "header",
                "kind": "row",
                "children": [
                  {
                    "node": "n55",
                    "grow": true
                  },
                  {
                    "node": "n59",
                    "width": 160
                  },
                  {
                    "node": "n129"
                  },
                  {
                    "node": "n131"
                  },
                  {
                    "node": "n62"
                  }
                ]
              },
              {
                "node": "n74",
                "grow": true
              }
            ]
          },
          {
            "id": "panel",
            "kind": "column",
            "children": [
              {
                "node": "n85",
                "width": 320
              },
              {
                "node": "n90",
                "width": 320
              },
              {
                "node": "n98",
                "width": 320
              },
              {
                "id": "dates",
                "kind": "row",
                "children": [
                  {
                    "node": "n104",
                    "grow": true
                  },
                  {
                    "node": "n111",
                    "grow": true
                  }
                ]
              },
              {
                "node": "n115",
                "width": 320
              },
              {
                "node": "n119",
                "grow": true,
                "width": 320
              },
              {
                "id": "card_buttons",
                "kind": "row",
                "children": [
                  {
                    "node": "n122"
                  },
                  {
                    "node": "n123"
                  },
                  {
                    "node": "n124"
                  }
                ]
              }
            ]
          }
        ]
      },
      {
        "node": "n80"
      }
    ]
  }
}
]]

---@type Proteus.Plugin
return {
  name = NAME,
  description = 'Boards of cards in columns, saved in data/kanban. Built with Nodal from graphs/kanban.graph.json.',
  version = '1.0.0',
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
    local handle, refusal =
      app.use ('nodal.app').mount_text (GRAPH, { status_bar = true })
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
