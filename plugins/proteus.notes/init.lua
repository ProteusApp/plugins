-- Built by Nodal from graphs/notes.ndg. Building again replaces this file.
-- It runs the graph below with the Nodal runtime, as the Nodal preview does.
-- To change it, change the graph.

-- Plugin id: proteus.notes
local NAME = 'Notes'

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
      "block": "app.setting",
      "name": "Notes folder",
      "position": {
        "x": 0,
        "y": 0
      },
      "config": {
        "key": "notes.folder",
        "title": "Notes folder",
        "description": "The folder the notes are kept in.",
        "type": "text",
        "default": "data/notes"
      },
      "literals": {}
    },
    {
      "id": "n2",
      "block": "event.start",
      "name": "Start",
      "position": {
        "x": 0,
        "y": 522
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n3",
      "block": "file.list",
      "name": "Look in the folder",
      "position": {
        "x": 330,
        "y": 458
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n4",
      "block": "list.matching",
      "name": "Notes found at start",
      "position": {
        "x": 660,
        "y": 284
      },
      "config": {},
      "literals": {
        "text": ".md"
      }
    },
    {
      "id": "n5",
      "block": "list.length",
      "name": "Count at start",
      "position": {
        "x": 990,
        "y": 348
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n6",
      "block": "logic.compare",
      "name": "No notes yet",
      "position": {
        "x": 1320,
        "y": 490
      },
      "config": {
        "operator": "==="
      },
      "literals": {
        "b": 0
      }
    },
    {
      "id": "n7",
      "block": "flow.when",
      "name": "Only when there are no notes",
      "position": {
        "x": 1650,
        "y": 490
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n8",
      "block": "value.text",
      "name": "Welcome text",
      "position": {
        "x": 0,
        "y": 1622
      },
      "config": {
        "value": "# Welcome to Notes\n\nThis app is a Nodal graph. Every list, button and command in it is a block you can open\nand change.\n\n- **Ctrl+N** makes a new note\n- **Ctrl+E** shows or hides the Markdown preview\n- Right-click a note to open it in the editor or delete it\n\nNotes are saved as you type, as Markdown files in the notes folder. The folder is a\nsetting.\n"
      },
      "literals": {}
    },
    {
      "id": "n9",
      "block": "text.join",
      "name": "Welcome path",
      "position": {
        "x": 330,
        "y": 0
      },
      "config": {},
      "literals": {
        "b": "Welcome.md",
        "between": "/"
      }
    },
    {
      "id": "n10",
      "block": "file.write",
      "name": "Write the welcome note",
      "position": {
        "x": 1980,
        "y": 682
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n11",
      "block": "flow.any",
      "name": "After a change",
      "position": {
        "x": 2970,
        "y": 380
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n12",
      "block": "flow.any",
      "name": "List the notes",
      "position": {
        "x": 3300,
        "y": 0
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n13",
      "block": "file.list",
      "name": "List the folder",
      "position": {
        "x": 3630,
        "y": 0
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n14",
      "block": "list.matching",
      "name": "Markdown files",
      "position": {
        "x": 3960,
        "y": 0
      },
      "config": {},
      "literals": {
        "text": ".md"
      }
    },
    {
      "id": "n15",
      "block": "list.sort",
      "name": "Sorted",
      "position": {
        "x": 4290,
        "y": 0
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n16",
      "block": "state.list",
      "name": "Files",
      "position": {
        "x": 0,
        "y": 142
      },
      "config": {
        "value": []
      },
      "literals": {}
    },
    {
      "id": "n17",
      "block": "state.set",
      "name": "Set the files",
      "position": {
        "x": 4620,
        "y": 0
      },
      "config": {
        "limit": 0,
        "mode": "replace",
        "variable": "n16"
      },
      "literals": {}
    },
    {
      "id": "n18",
      "block": "ui.textbox",
      "name": "Search",
      "position": {
        "x": 0,
        "y": 220
      },
      "config": {
        "label": "",
        "clear_on_submit": false,
        "mono": false,
        "multiline": false
      },
      "literals": {
        "placeholder": "Search notes"
      }
    },
    {
      "id": "n19",
      "block": "list.matching",
      "name": "Shown files",
      "position": {
        "x": 330,
        "y": 284
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n20",
      "block": "list.join",
      "name": "Shown files as text",
      "position": {
        "x": 660,
        "y": 142
      },
      "config": {},
      "literals": {
        "between": "\n"
      }
    },
    {
      "id": "n21",
      "block": "text.join",
      "name": "With a line break at the end",
      "position": {
        "x": 990,
        "y": 174
      },
      "config": {},
      "literals": {
        "b": "",
        "between": "\n"
      }
    },
    {
      "id": "n22",
      "block": "text.split",
      "name": "Split at .md",
      "position": {
        "x": 1320,
        "y": 348
      },
      "config": {},
      "literals": {
        "separator": ".md\n"
      }
    },
    {
      "id": "n23",
      "block": "list.slice",
      "name": "Note names",
      "position": {
        "x": 1650,
        "y": 316
      },
      "config": {},
      "literals": {
        "from": 1,
        "to": -1
      }
    },
    {
      "id": "n24",
      "block": "ui.list",
      "name": "Notes",
      "position": {
        "x": 1980,
        "y": 0
      },
      "config": {
        "label": ""
      },
      "literals": {}
    },
    {
      "id": "n25",
      "block": "ui.button",
      "name": "New note",
      "position": {
        "x": 0,
        "y": 600
      },
      "config": {
        "label": "",
        "icon": "square-pen",
        "style": "primary"
      },
      "literals": {
        "label": "New note"
      }
    },
    {
      "id": "n26",
      "block": "ui.button",
      "name": "Toggle preview",
      "position": {
        "x": 0,
        "y": 774
      },
      "config": {
        "label": "",
        "icon": "eye",
        "style": "plain"
      },
      "literals": {
        "label": "Preview"
      }
    },
    {
      "id": "n27",
      "block": "state.text",
      "name": "Current",
      "position": {
        "x": 0,
        "y": 948
      },
      "config": {
        "value": ""
      },
      "literals": {}
    },
    {
      "id": "n28",
      "block": "flow.order",
      "name": "Open the picked note",
      "position": {
        "x": 2310,
        "y": 0
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n29",
      "block": "list.get",
      "name": "Picked file",
      "position": {
        "x": 2310,
        "y": 206
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n30",
      "block": "text.join",
      "name": "Picked path",
      "position": {
        "x": 2640,
        "y": 0
      },
      "config": {},
      "literals": {
        "between": "/"
      }
    },
    {
      "id": "n31",
      "block": "state.set",
      "name": "Set the current note",
      "position": {
        "x": 2970,
        "y": 0
      },
      "config": {
        "limit": 0,
        "mode": "replace",
        "variable": "n27"
      },
      "literals": {}
    },
    {
      "id": "n32",
      "block": "flow.any",
      "name": "Open the current note",
      "position": {
        "x": 2970,
        "y": 174
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n33",
      "block": "file.read",
      "name": "Read the note",
      "position": {
        "x": 3300,
        "y": 380
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n34",
      "block": "logic.compare",
      "name": "A note is open",
      "position": {
        "x": 330,
        "y": 696
      },
      "config": {
        "operator": "!=="
      },
      "literals": {
        "b": ""
      }
    },
    {
      "id": "n35",
      "block": "logic.if",
      "name": "Editor text",
      "position": {
        "x": 3630,
        "y": 444
      },
      "config": {},
      "literals": {
        "otherwise": ""
      }
    },
    {
      "id": "n36",
      "block": "flow.any",
      "name": "Show the note",
      "position": {
        "x": 3630,
        "y": 238
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n37",
      "block": "ui.code",
      "name": "Editor",
      "position": {
        "x": 3960,
        "y": 174
      },
      "config": {
        "label": ""
      },
      "literals": {}
    },
    {
      "id": "n38",
      "block": "ui.markdown",
      "name": "Preview",
      "position": {
        "x": 4290,
        "y": 458
      },
      "config": {
        "label": ""
      },
      "literals": {}
    },
    {
      "id": "n39",
      "block": "flow.wait",
      "name": "Wait for a pause",
      "position": {
        "x": 4290,
        "y": 110
      },
      "config": {},
      "literals": {
        "ms": 400
      }
    },
    {
      "id": "n40",
      "block": "flow.when",
      "name": "Only when a note is open",
      "position": {
        "x": 4620,
        "y": 284
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n41",
      "block": "file.write",
      "name": "Save the note",
      "position": {
        "x": 4950,
        "y": 316
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n42",
      "block": "text.replace",
      "name": "One line",
      "position": {
        "x": 4290,
        "y": 284
      },
      "config": {},
      "literals": {
        "find": "\n",
        "with": " "
      }
    },
    {
      "id": "n43",
      "block": "text.trim",
      "name": "Trimmed",
      "position": {
        "x": 4620,
        "y": 174
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n44",
      "block": "text.split",
      "name": "Words",
      "position": {
        "x": 4950,
        "y": 0
      },
      "config": {},
      "literals": {
        "separator": " "
      }
    },
    {
      "id": "n45",
      "block": "list.length",
      "name": "Word count",
      "position": {
        "x": 5280,
        "y": 0
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n46",
      "block": "logic.compare",
      "name": "Blank",
      "position": {
        "x": 4950,
        "y": 142
      },
      "config": {
        "operator": "==="
      },
      "literals": {
        "b": ""
      }
    },
    {
      "id": "n47",
      "block": "logic.if",
      "name": "Words counted",
      "position": {
        "x": 5610,
        "y": 0
      },
      "config": {},
      "literals": {
        "then": 0
      }
    },
    {
      "id": "n48",
      "block": "text.join",
      "name": "Saved line",
      "position": {
        "x": 5940,
        "y": 0
      },
      "config": {},
      "literals": {
        "b": "words · saved"
      }
    },
    {
      "id": "n49",
      "block": "state.text",
      "name": "Status",
      "position": {
        "x": 0,
        "y": 1026
      },
      "config": {
        "value": ""
      },
      "literals": {}
    },
    {
      "id": "n50",
      "block": "state.set",
      "name": "Show that it saved",
      "position": {
        "x": 6270,
        "y": 0
      },
      "config": {
        "limit": 0,
        "mode": "replace",
        "variable": "n49"
      },
      "literals": {}
    },
    {
      "id": "n51",
      "block": "app.status",
      "name": "Status bar",
      "position": {
        "x": 330,
        "y": 1076
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n52",
      "block": "app.command",
      "name": "New Note",
      "position": {
        "x": 0,
        "y": 1104
      },
      "config": {
        "key": "ctrl+n",
        "title": "New Note",
        "icon": "square-pen",
        "menu": "File"
      },
      "literals": {}
    },
    {
      "id": "n53",
      "block": "flow.any",
      "name": "Make a new note",
      "position": {
        "x": 330,
        "y": 870
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n54",
      "block": "list.length",
      "name": "Note count",
      "position": {
        "x": 330,
        "y": 174
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n55",
      "block": "math.add",
      "name": "Next number",
      "position": {
        "x": 660,
        "y": 0
      },
      "config": {},
      "literals": {
        "b": 1
      }
    },
    {
      "id": "n56",
      "block": "text.join",
      "name": "New note title",
      "position": {
        "x": 990,
        "y": 0
      },
      "config": {},
      "literals": {
        "a": "Note"
      }
    },
    {
      "id": "n57",
      "block": "text.join",
      "name": "New note file",
      "position": {
        "x": 1320,
        "y": 0
      },
      "config": {},
      "literals": {
        "b": ".md",
        "between": ""
      }
    },
    {
      "id": "n58",
      "block": "text.join",
      "name": "New note path",
      "position": {
        "x": 1650,
        "y": 0
      },
      "config": {},
      "literals": {
        "between": "/"
      }
    },
    {
      "id": "n59",
      "block": "text.join",
      "name": "New note text",
      "position": {
        "x": 1320,
        "y": 174
      },
      "config": {},
      "literals": {
        "a": "#"
      }
    },
    {
      "id": "n60",
      "block": "list.contains",
      "name": "Name taken",
      "position": {
        "x": 1650,
        "y": 174
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n61",
      "block": "flow.when",
      "name": "Is the name taken",
      "position": {
        "x": 1980,
        "y": 270
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n62",
      "block": "app.notify",
      "name": "Say the name is taken",
      "position": {
        "x": 2310,
        "y": 348
      },
      "config": {
        "kind": "warn"
      },
      "literals": {
        "message": "There is already a note with that name"
      }
    },
    {
      "id": "n63",
      "block": "flow.order",
      "name": "Make it",
      "position": {
        "x": 2310,
        "y": 522
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n64",
      "block": "state.set",
      "name": "Make it the current note",
      "position": {
        "x": 2640,
        "y": 174
      },
      "config": {
        "limit": 0,
        "mode": "replace",
        "variable": "n27"
      },
      "literals": {}
    },
    {
      "id": "n65",
      "block": "file.write",
      "name": "Write the new note",
      "position": {
        "x": 2640,
        "y": 348
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n66",
      "block": "app.command",
      "name": "Toggle Preview",
      "position": {
        "x": 0,
        "y": 1214
      },
      "config": {
        "key": "ctrl+e",
        "title": "Toggle Preview",
        "icon": "eye",
        "menu": "View"
      },
      "literals": {}
    },
    {
      "id": "n67",
      "block": "flow.any",
      "name": "Toggle the preview",
      "position": {
        "x": 330,
        "y": 1186
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n68",
      "block": "state.boolean",
      "name": "Preview",
      "position": {
        "x": 0,
        "y": 1324
      },
      "config": {
        "value": false
      },
      "literals": {}
    },
    {
      "id": "n69",
      "block": "logic.not",
      "name": "Not preview",
      "position": {
        "x": 330,
        "y": 1392
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n70",
      "block": "state.set",
      "name": "Flip the preview",
      "position": {
        "x": 660,
        "y": 458
      },
      "config": {
        "limit": 0,
        "mode": "replace",
        "variable": "n68"
      },
      "literals": {}
    },
    {
      "id": "n71",
      "block": "app.command",
      "name": "Delete Note",
      "position": {
        "x": 0,
        "y": 1402
      },
      "config": {
        "key": "",
        "title": "Delete Note",
        "icon": "trash-2",
        "menu": "File"
      },
      "literals": {}
    },
    {
      "id": "n72",
      "block": "flow.when",
      "name": "Only when a note is open to delete",
      "position": {
        "x": 660,
        "y": 632
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n73",
      "block": "file.delete",
      "name": "Delete the current note",
      "position": {
        "x": 990,
        "y": 632
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n74",
      "block": "flow.any",
      "name": "Close the note",
      "position": {
        "x": 2640,
        "y": 586
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n75",
      "block": "flow.order",
      "name": "Close it",
      "position": {
        "x": 2970,
        "y": 586
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n76",
      "block": "state.set",
      "name": "Clear the current note",
      "position": {
        "x": 3300,
        "y": 206
      },
      "config": {
        "limit": 0,
        "mode": "replace",
        "variable": "n27"
      },
      "literals": {
        "to": ""
      }
    },
    {
      "id": "n77",
      "block": "flow.any",
      "name": "After a delete",
      "position": {
        "x": 2310,
        "y": 728
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n78",
      "block": "value.list",
      "name": "Menu items",
      "position": {
        "x": 0,
        "y": 1512
      },
      "config": {
        "items": "Open in the editor\nDelete"
      },
      "literals": {}
    },
    {
      "id": "n79",
      "block": "ui.menu",
      "name": "Note menu",
      "position": {
        "x": 330,
        "y": 1502
      },
      "config": {
        "target": "n24"
      },
      "literals": {}
    },
    {
      "id": "n80",
      "block": "logic.compare",
      "name": "On a note",
      "position": {
        "x": 660,
        "y": 838
      },
      "config": {
        "operator": "!=="
      },
      "literals": {
        "b": ""
      }
    },
    {
      "id": "n81",
      "block": "flow.when",
      "name": "Only on a note",
      "position": {
        "x": 990,
        "y": 838
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n82",
      "block": "logic.compare",
      "name": "Chose open",
      "position": {
        "x": 660,
        "y": 1012
      },
      "config": {
        "operator": "==="
      },
      "literals": {
        "b": "Open in the editor"
      }
    },
    {
      "id": "n83",
      "block": "flow.when",
      "name": "Only when open was chosen",
      "position": {
        "x": 1320,
        "y": 838
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n84",
      "block": "text.join",
      "name": "Menu note file",
      "position": {
        "x": 660,
        "y": 1186
      },
      "config": {},
      "literals": {
        "b": ".md",
        "between": ""
      }
    },
    {
      "id": "n85",
      "block": "text.join",
      "name": "Menu note path",
      "position": {
        "x": 990,
        "y": 458
      },
      "config": {},
      "literals": {
        "between": "/"
      }
    },
    {
      "id": "n86",
      "block": "app.open",
      "name": "Open in the editor",
      "position": {
        "x": 1650,
        "y": 696
      },
      "config": {
        "what": "file"
      },
      "literals": {}
    },
    {
      "id": "n87",
      "block": "logic.compare",
      "name": "Chose delete",
      "position": {
        "x": 660,
        "y": 1360
      },
      "config": {
        "operator": "==="
      },
      "literals": {
        "b": "Delete"
      }
    },
    {
      "id": "n88",
      "block": "flow.when",
      "name": "Only when delete was chosen",
      "position": {
        "x": 1650,
        "y": 870
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n89",
      "block": "file.delete",
      "name": "Delete the note",
      "position": {
        "x": 1980,
        "y": 476
      },
      "config": {},
      "literals": {}
    },
    {
      "id": "n90",
      "block": "logic.compare",
      "name": "It was open",
      "position": {
        "x": 1320,
        "y": 664
      },
      "config": {
        "operator": "==="
      },
      "literals": {}
    },
    {
      "id": "n91",
      "block": "flow.when",
      "name": "Only when it was open",
      "position": {
        "x": 2310,
        "y": 934
      },
      "config": {},
      "literals": {}
    }
  ],
  "edges": [
    {
      "id": "e92",
      "from": "n2",
      "to": "n3",
      "input": "when"
    },
    {
      "id": "e93",
      "from": "n1",
      "to": "n3",
      "input": "path"
    },
    {
      "id": "e94",
      "from": "n3",
      "output": "names",
      "to": "n4",
      "input": "list"
    },
    {
      "id": "e95",
      "from": "n4",
      "to": "n5",
      "input": "list"
    },
    {
      "id": "e96",
      "from": "n5",
      "to": "n6",
      "input": "a"
    },
    {
      "id": "e97",
      "from": "n3",
      "output": "done",
      "to": "n7",
      "input": "when"
    },
    {
      "id": "e98",
      "from": "n6",
      "to": "n7",
      "input": "test"
    },
    {
      "id": "e99",
      "from": "n7",
      "output": "yes",
      "to": "n10",
      "input": "when"
    },
    {
      "id": "e100",
      "from": "n1",
      "to": "n9",
      "input": "a"
    },
    {
      "id": "e101",
      "from": "n9",
      "to": "n10",
      "input": "path"
    },
    {
      "id": "e102",
      "from": "n8",
      "to": "n10",
      "input": "text"
    },
    {
      "id": "e103",
      "from": "n10",
      "output": "done",
      "to": "n11",
      "input": "a"
    },
    {
      "id": "e104",
      "from": "n7",
      "output": "no",
      "to": "n12",
      "input": "a"
    },
    {
      "id": "e105",
      "from": "n11",
      "output": "then",
      "to": "n12",
      "input": "b"
    },
    {
      "id": "e106",
      "from": "n12",
      "output": "then",
      "to": "n13",
      "input": "when"
    },
    {
      "id": "e107",
      "from": "n1",
      "to": "n13",
      "input": "path"
    },
    {
      "id": "e108",
      "from": "n13",
      "output": "names",
      "to": "n14",
      "input": "list"
    },
    {
      "id": "e109",
      "from": "n14",
      "to": "n15",
      "input": "list"
    },
    {
      "id": "e110",
      "from": "n13",
      "output": "done",
      "to": "n17",
      "input": "when"
    },
    {
      "id": "e111",
      "from": "n15",
      "to": "n17",
      "input": "to"
    },
    {
      "id": "e112",
      "from": "n16",
      "to": "n19",
      "input": "list"
    },
    {
      "id": "e113",
      "from": "n18",
      "to": "n19",
      "input": "text"
    },
    {
      "id": "e114",
      "from": "n19",
      "to": "n20",
      "input": "list"
    },
    {
      "id": "e115",
      "from": "n20",
      "to": "n21",
      "input": "a"
    },
    {
      "id": "e116",
      "from": "n21",
      "to": "n22",
      "input": "text"
    },
    {
      "id": "e117",
      "from": "n22",
      "to": "n23",
      "input": "list"
    },
    {
      "id": "e118",
      "from": "n23",
      "to": "n24",
      "input": "items"
    },
    {
      "id": "e119",
      "from": "n24",
      "output": "picked",
      "to": "n28",
      "input": "when"
    },
    {
      "id": "e120",
      "from": "n19",
      "to": "n29",
      "input": "list"
    },
    {
      "id": "e121",
      "from": "n24",
      "output": "position",
      "to": "n29",
      "input": "position"
    },
    {
      "id": "e122",
      "from": "n1",
      "to": "n30",
      "input": "a"
    },
    {
      "id": "e123",
      "from": "n29",
      "to": "n30",
      "input": "b"
    },
    {
      "id": "e124",
      "from": "n28",
      "output": "first",
      "to": "n31",
      "input": "when"
    },
    {
      "id": "e125",
      "from": "n30",
      "to": "n31",
      "input": "to"
    },
    {
      "id": "e126",
      "from": "n28",
      "output": "second",
      "to": "n32",
      "input": "a"
    },
    {
      "id": "e127",
      "from": "n65",
      "output": "done",
      "to": "n32",
      "input": "b"
    },
    {
      "id": "e128",
      "from": "n32",
      "output": "then",
      "to": "n33",
      "input": "when"
    },
    {
      "id": "e129",
      "from": "n27",
      "to": "n33",
      "input": "path"
    },
    {
      "id": "e130",
      "from": "n27",
      "to": "n34",
      "input": "a"
    },
    {
      "id": "e131",
      "from": "n34",
      "to": "n35",
      "input": "when"
    },
    {
      "id": "e132",
      "from": "n33",
      "output": "text",
      "to": "n35",
      "input": "then"
    },
    {
      "id": "e133",
      "from": "n33",
      "output": "done",
      "to": "n36",
      "input": "a"
    },
    {
      "id": "e134",
      "from": "n75",
      "output": "second",
      "to": "n36",
      "input": "b"
    },
    {
      "id": "e135",
      "from": "n36",
      "output": "then",
      "to": "n37",
      "input": "set"
    },
    {
      "id": "e136",
      "from": "n35",
      "to": "n37",
      "input": "to"
    },
    {
      "id": "e137",
      "from": "n37",
      "to": "n38",
      "input": "text"
    },
    {
      "id": "e138",
      "from": "n68",
      "to": "n38",
      "input": "visible"
    },
    {
      "id": "e139",
      "from": "n37",
      "output": "changed",
      "to": "n39",
      "input": "when"
    },
    {
      "id": "e140",
      "from": "n39",
      "output": "then",
      "to": "n40",
      "input": "when"
    },
    {
      "id": "e141",
      "from": "n34",
      "to": "n40",
      "input": "test"
    },
    {
      "id": "e142",
      "from": "n40",
      "output": "yes",
      "to": "n41",
      "input": "when"
    },
    {
      "id": "e143",
      "from": "n27",
      "to": "n41",
      "input": "path"
    },
    {
      "id": "e144",
      "from": "n37",
      "to": "n41",
      "input": "text"
    },
    {
      "id": "e145",
      "from": "n37",
      "to": "n42",
      "input": "text"
    },
    {
      "id": "e146",
      "from": "n42",
      "to": "n43",
      "input": "text"
    },
    {
      "id": "e147",
      "from": "n43",
      "to": "n44",
      "input": "text"
    },
    {
      "id": "e148",
      "from": "n44",
      "to": "n45",
      "input": "list"
    },
    {
      "id": "e149",
      "from": "n43",
      "to": "n46",
      "input": "a"
    },
    {
      "id": "e150",
      "from": "n46",
      "to": "n47",
      "input": "when"
    },
    {
      "id": "e151",
      "from": "n45",
      "to": "n47",
      "input": "otherwise"
    },
    {
      "id": "e152",
      "from": "n47",
      "to": "n48",
      "input": "a"
    },
    {
      "id": "e153",
      "from": "n41",
      "output": "done",
      "to": "n50",
      "input": "when"
    },
    {
      "id": "e154",
      "from": "n48",
      "to": "n50",
      "input": "to"
    },
    {
      "id": "e155",
      "from": "n49",
      "to": "n51",
      "input": "text"
    },
    {
      "id": "e156",
      "from": "n25",
      "to": "n53",
      "input": "a"
    },
    {
      "id": "e157",
      "from": "n52",
      "to": "n53",
      "input": "b"
    },
    {
      "id": "e158",
      "from": "n16",
      "to": "n54",
      "input": "list"
    },
    {
      "id": "e159",
      "from": "n54",
      "to": "n55",
      "input": "a"
    },
    {
      "id": "e160",
      "from": "n55",
      "to": "n56",
      "input": "b"
    },
    {
      "id": "e161",
      "from": "n56",
      "to": "n57",
      "input": "a"
    },
    {
      "id": "e162",
      "from": "n1",
      "to": "n58",
      "input": "a"
    },
    {
      "id": "e163",
      "from": "n57",
      "to": "n58",
      "input": "b"
    },
    {
      "id": "e164",
      "from": "n56",
      "to": "n59",
      "input": "b"
    },
    {
      "id": "e165",
      "from": "n16",
      "to": "n60",
      "input": "list"
    },
    {
      "id": "e166",
      "from": "n57",
      "to": "n60",
      "input": "item"
    },
    {
      "id": "e167",
      "from": "n53",
      "output": "then",
      "to": "n61",
      "input": "when"
    },
    {
      "id": "e168",
      "from": "n60",
      "to": "n61",
      "input": "test"
    },
    {
      "id": "e169",
      "from": "n61",
      "output": "yes",
      "to": "n62",
      "input": "when"
    },
    {
      "id": "e170",
      "from": "n61",
      "output": "no",
      "to": "n63",
      "input": "when"
    },
    {
      "id": "e171",
      "from": "n63",
      "output": "first",
      "to": "n64",
      "input": "when"
    },
    {
      "id": "e172",
      "from": "n58",
      "to": "n64",
      "input": "to"
    },
    {
      "id": "e173",
      "from": "n63",
      "output": "second",
      "to": "n65",
      "input": "when"
    },
    {
      "id": "e174",
      "from": "n27",
      "to": "n65",
      "input": "path"
    },
    {
      "id": "e175",
      "from": "n59",
      "to": "n65",
      "input": "text"
    },
    {
      "id": "e176",
      "from": "n65",
      "output": "done",
      "to": "n11",
      "input": "b"
    },
    {
      "id": "e177",
      "from": "n66",
      "to": "n67",
      "input": "a"
    },
    {
      "id": "e178",
      "from": "n26",
      "to": "n67",
      "input": "b"
    },
    {
      "id": "e179",
      "from": "n68",
      "to": "n69",
      "input": "value"
    },
    {
      "id": "e180",
      "from": "n67",
      "output": "then",
      "to": "n70",
      "input": "when"
    },
    {
      "id": "e181",
      "from": "n69",
      "to": "n70",
      "input": "to"
    },
    {
      "id": "e182",
      "from": "n71",
      "to": "n72",
      "input": "when"
    },
    {
      "id": "e183",
      "from": "n34",
      "to": "n72",
      "input": "test"
    },
    {
      "id": "e184",
      "from": "n72",
      "output": "yes",
      "to": "n73",
      "input": "when"
    },
    {
      "id": "e185",
      "from": "n27",
      "to": "n73",
      "input": "path"
    },
    {
      "id": "e186",
      "from": "n73",
      "output": "done",
      "to": "n74",
      "input": "a"
    },
    {
      "id": "e187",
      "from": "n91",
      "output": "yes",
      "to": "n74",
      "input": "b"
    },
    {
      "id": "e188",
      "from": "n74",
      "output": "then",
      "to": "n75",
      "input": "when"
    },
    {
      "id": "e189",
      "from": "n75",
      "output": "first",
      "to": "n76",
      "input": "when"
    },
    {
      "id": "e190",
      "from": "n73",
      "output": "done",
      "to": "n77",
      "input": "a"
    },
    {
      "id": "e191",
      "from": "n89",
      "output": "done",
      "to": "n77",
      "input": "b"
    },
    {
      "id": "e192",
      "from": "n77",
      "output": "then",
      "to": "n11",
      "input": "c"
    },
    {
      "id": "e193",
      "from": "n78",
      "to": "n79",
      "input": "items"
    },
    {
      "id": "e194",
      "from": "n79",
      "output": "item",
      "to": "n80",
      "input": "a"
    },
    {
      "id": "e195",
      "from": "n79",
      "output": "picked",
      "to": "n81",
      "input": "when"
    },
    {
      "id": "e196",
      "from": "n80",
      "to": "n81",
      "input": "test"
    },
    {
      "id": "e197",
      "from": "n79",
      "output": "choice",
      "to": "n82",
      "input": "a"
    },
    {
      "id": "e198",
      "from": "n81",
      "output": "yes",
      "to": "n83",
      "input": "when"
    },
    {
      "id": "e199",
      "from": "n82",
      "to": "n83",
      "input": "test"
    },
    {
      "id": "e200",
      "from": "n79",
      "output": "item",
      "to": "n84",
      "input": "a"
    },
    {
      "id": "e201",
      "from": "n1",
      "to": "n85",
      "input": "a"
    },
    {
      "id": "e202",
      "from": "n84",
      "to": "n85",
      "input": "b"
    },
    {
      "id": "e203",
      "from": "n83",
      "output": "yes",
      "to": "n86",
      "input": "when"
    },
    {
      "id": "e204",
      "from": "n85",
      "to": "n86",
      "input": "target"
    },
    {
      "id": "e205",
      "from": "n79",
      "output": "choice",
      "to": "n87",
      "input": "a"
    },
    {
      "id": "e206",
      "from": "n83",
      "output": "no",
      "to": "n88",
      "input": "when"
    },
    {
      "id": "e207",
      "from": "n87",
      "to": "n88",
      "input": "test"
    },
    {
      "id": "e208",
      "from": "n88",
      "output": "yes",
      "to": "n89",
      "input": "when"
    },
    {
      "id": "e209",
      "from": "n85",
      "to": "n89",
      "input": "path"
    },
    {
      "id": "e210",
      "from": "n85",
      "to": "n90",
      "input": "a"
    },
    {
      "id": "e211",
      "from": "n27",
      "to": "n90",
      "input": "b"
    },
    {
      "id": "e212",
      "from": "n89",
      "output": "done",
      "to": "n91",
      "input": "when"
    },
    {
      "id": "e213",
      "from": "n90",
      "to": "n91",
      "input": "test"
    }
  ],
  "next_id": 214,
  "layout": {
    "id": "root",
    "kind": "column",
    "children": [
      {
        "id": "box1",
        "kind": "row",
        "grow": true,
        "children": [
          {
            "id": "box2",
            "kind": "column",
            "width": 260,
            "children": [
              {
                "node": "n18"
              },
              {
                "node": "n24",
                "grow": true
              },
              {
                "id": "box3",
                "kind": "row",
                "children": [
                  {
                    "node": "n25",
                    "grow": true
                  },
                  {
                    "node": "n26"
                  }
                ]
              }
            ]
          },
          {
            "id": "box4",
            "kind": "column",
            "grow": true,
            "children": [
              {
                "node": "n37",
                "grow": true
              },
              {
                "node": "n38",
                "grow": true
              }
            ]
          }
        ]
      },
      {
        "node": "n51"
      }
    ]
  }
}
]]

---@type Proteus.Plugin
return {
  name = NAME,
  description = 'Markdown notes in data/notes. Built with Nodal from graphs/notes.ndg.',
  version = '1.1.0',
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
