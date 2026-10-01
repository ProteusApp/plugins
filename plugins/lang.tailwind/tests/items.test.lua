local items = require ('lib.items') --[[@as LangTailwind.ItemsModule]]

-- Items as @tailwindcss/language-server 0.16 sends them for `class="bg-|"` on line 3, where
-- the class starts at column 16 and the cursor is at column 19.
local LINE = '    <div class="bg-"></div>'
local POS = { line = 3, character = 19 }

---@param new_text string
---@return table
local function edit (new_text)
  return {
    newText = new_text,
    range = {
      start = { line = 3, character = 16 },
      ['end'] = { line = 3, character = 19 },
    },
  }
end

local RED = {
  label = 'bg-red-500',
  kind = 16,
  documentation = '#fb2c36',
  sortText = '02735',
  data = { _projectKey = '0', variants = {} },
  textEdit = edit ('bg-red-500'),
}
local HOVER = {
  label = 'hover:',
  kind = 9,
  detail = '@media (hover: hover) { &:hover }',
  sortText = '-00000170',
  textEdit = edit ('hover:'),
}
local NOT = {
  label = 'not-[]:',
  kind = 9,
  sortText = '-00000002',
  insertTextFormat = 2,
  textEdit = edit ('not-[${1}]:${0}'),
}
local FLEX = {
  label = 'flex',
  kind = 21,
  sortText = '01200',
  textEdit = edit ('flex'),
}
local BLOCK = {
  label = 'border-green-500',
  kind = 21,
  sortText = '00100',
  textEdit = edit ('border-green-500'),
}

test ('from is where the class starts, or else the cursor', function ()
  eq (items.from ({ RED, HOVER }, POS), 16)
  eq (items.from ({ { label = 'x' } }, POS), 19)
  eq (items.slice (LINE, 16, 19), 'bg-')
end)

test (
  'pick keeps what fits the typed text, those that start with it first',
  function ()
    local picked = items.pick ({ FLEX, RED, BLOCK, HOVER }, 'bg-')
    eq (#picked, 2)
    eq (picked[1].label, 'bg-red-500')
    eq (picked[2].label, 'border-green-500')
    eq (#items.pick ({ FLEX, RED, HOVER }, ''), 3)
    eq (items.pick ({ FLEX, RED, HOVER }, '')[1].label, 'hover:')
    eq (items.fits ('bg-red-500', 'BGR'), true)
    eq (items.fits ('flex', 'bg'), false)
  end
)

test ('plain text stops where a snippet puts the cursor', function ()
  eq (items.text (NOT), 'not-[')
  eq (items.plain ('group-[${1}]:${0}'), 'group-[')
  eq (items.plain ([[a\$b]]), 'a$b')
  eq (items.text (RED), 'bg-red-500')
end)

test (
  'item shows a color beside its name, and the CSS once resolved',
  function ()
    eq (items.item (RED, LINE, POS, 16), {
      label = 'bg-red-500',
      kind = 'color',
      detail = '#fb2c36',
      insert = 'bg-red-500',
    })
    local resolved = {}
    for k, v in pairs (RED) do
      resolved[k] = v
    end
    resolved.detail = 'background-color: oklch(63.7% 0.237 25.331);'
    eq (
      items.item (resolved, LINE, POS, 16).documentation,
      '```css\n.bg-red-500 {\n  background-color: oklch(63.7% 0.237 25.331);\n}\n```'
    )
  end
)

test ('item keeps documentation the server wrote', function ()
  local truncate = {
    label = 'truncate',
    kind = 21,
    detail = 'overflow: hidden;',
    documentation = {
      kind = 'markdown',
      value = '```css\n.truncate {\n  overflow: hidden;\n}\n```',
    },
    textEdit = edit ('truncate'),
  }
  eq (items.item (truncate, LINE, POS, 16), {
    label = 'truncate',
    kind = 'constant',
    documentation = '```css\n.truncate {\n  overflow: hidden;\n}\n```',
    insert = 'truncate',
  })
  eq (items.wants_css (truncate), false)
  eq (items.wants_css (RED), true)
  eq (items.wants_css (HOVER), false)
end)

test ('a variant says what it does', function ()
  eq (items.item (HOVER, LINE, POS, 16), {
    label = 'hover:',
    kind = 'module',
    documentation = '```css\n@media (hover: hover) { &:hover }\n```',
    insert = 'hover:',
  })
end)

test ('insert adds the text between an earlier start and the item', function ()
  local later = {
    label = 'red-500',
    textEdit = {
      newText = 'red-500',
      range = {
        start = { line = 3, character = 19 },
        ['end'] = { line = 3, character = 19 },
      },
    },
  }
  eq (items.insert (later, LINE, POS, 16), 'bg-red-500')
end)

test ('rule writes the declarations one per line', function ()
  eq (
    items.rule ('w-1/2', 'width: calc(1 / 2 * 100%); --x: 1;'),
    '.w-1\\/2 {\n  width: calc(1 / 2 * 100%);\n  --x: 1;\n}'
  )
  eq (items.selector ('@container'), '.\\@container')
end)

test ('line and offset count characters as the editor does', function ()
  eq (items.line ('a\r\nb\nc', 1), 'b')
  eq (items.line ('a', 4), '')
  eq (items.offset ('é-x', 2), 3)
  eq (items.slice ('class="é bg-"', 9, 12), 'bg-')
end)
