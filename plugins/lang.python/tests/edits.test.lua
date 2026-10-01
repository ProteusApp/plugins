local edits = require ('lib.edits') --[[@as LangPython.EditsModule]]

---@param sl integer
---@param sc integer
---@param el integer
---@param ec integer
---@param text string
---@return LangPython.TextEdit
local function edit (sl, sc, el, ec, text)
  return {
    range = {
      start = { line = sl, character = sc },
      ['end'] = { line = el, character = ec },
    },
    newText = text,
  }
end

test ('offset finds a line and a column', function ()
  local text = 'ab\ncd\nef'
  eq (edits.offset (text, 0, 0), 1)
  eq (edits.offset (text, 1, 1), 5)
  eq (edits.offset (text, 2, 2), 9)
end)

test ('offset stops at the end of a short line and of the text', function ()
  local text = 'ab\ncd'
  eq (edits.offset (text, 0, 9), 3)
  eq (edits.offset (text, 5, 0), 6)
end)

test ('offset counts columns in UTF-16 units', function ()
  -- é is two bytes and one unit, and 😀 is four bytes and two units.
  local text = 'é😀x'
  eq (edits.offset (text, 0, 1), 3)
  eq (edits.offset (text, 0, 3), 7)
  eq (text:sub (edits.offset (text, 0, 3)), 'x')
end)

test ('apply makes every edit against the text as it was', function ()
  local text = 'import b\nimport a\n'
  local out = edits.apply (text, { edit (0, 0, 1, 8, 'import a\nimport b') })
  eq (out, 'import a\nimport b\n')
  eq (
    edits.apply ('one two three', {
      edit (0, 0, 0, 3, '1'),
      edit (0, 8, 0, 13, '3'),
    }),
    '1 two 3'
  )
end)

test ('apply keeps the order of inserts at one place', function ()
  eq (
    edits.apply ('xy', { edit (0, 1, 0, 1, 'a'), edit (0, 1, 0, 1, 'b') }),
    'xaby'
  )
end)

test ('files reads documentChanges and changes', function ()
  local list = { edit (0, 0, 0, 0, 'a') }
  eq (
    edits.files ({
      documentChanges = {
        { textDocument = { uri = 'file:///a.py', version = 3 }, edits = list },
        { kind = 'create', uri = 'file:///b.py' },
      },
    }),
    { { uri = 'file:///a.py', edits = list } }
  )
  eq (
    edits.files ({ changes = { ['file:///c.py'] = list } }),
    { { uri = 'file:///c.py', edits = list } }
  )
  eq (edits.files (nil), {})
end)

test ('apply makes the edits Ruff sends for Organize Imports', function ()
  -- The answer Ruff 0.16.10 gave for this file.
  local text = 'import sys\nimport os\nimport json\n\n\nprint(os, json)\n'
  local uri = 'file:///c%3A/code/app/main.py'
  local files = edits.files ({
    changes = {
      [uri] = { edit (0, 0, 3, 0, 'import json\nimport os\nimport sys\n') },
    },
  })
  eq (#files, 1)
  eq (files[1].uri, uri)
  eq (
    edits.apply (text, files[1].edits),
    'import json\nimport os\nimport sys\n\n\nprint(os, json)\n'
  )
end)
