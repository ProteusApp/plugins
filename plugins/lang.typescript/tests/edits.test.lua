local edits = require ('lib.edits') --[[@as LangTypescript.EditsModule]]

---@param sl integer
---@param sc integer
---@param el integer
---@param ec integer
---@param text string
---@return LangTypescript.TextEdit
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
  local text = "import { b } from 'b'\nimport { a } from 'a'\n"
  local out = edits.apply (text, {
    edit (0, 0, 1, 21, "import { a } from 'a'\nimport { b } from 'b'"),
  })
  eq (out, "import { a } from 'a'\nimport { b } from 'b'\n")
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
        { textDocument = { uri = 'file:///a.ts', version = 3 }, edits = list },
        { kind = 'create', uri = 'file:///b.ts' },
      },
    }),
    { { uri = 'file:///a.ts', edits = list } }
  )
  eq (
    edits.files ({ changes = { ['file:///c.ts'] = list } }),
    { { uri = 'file:///c.ts', edits = list } }
  )
  eq (edits.files (nil), {})
end)

test ('apply makes the edits Organize Imports sends', function ()
  local text = "import { z } from './z';\n"
    .. "import { b, a } from './lib';\n"
    .. 'export const x: number = a + b;\n'
  local uri = 'file:///c%3A/code/app/a.ts'
  local files = edits.files ({
    changes = {
      [uri] = {
        edit (0, 0, 1, 0, "import { a, b } from './lib';\n"),
        edit (1, 0, 2, 0, ''),
      },
    },
  })
  eq (#files, 1)
  eq (
    edits.apply (text, files[1].edits),
    "import { a, b } from './lib';\nexport const x: number = a + b;\n"
  )
end)
