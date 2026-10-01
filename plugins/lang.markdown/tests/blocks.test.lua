local blocks = require ('lib.blocks')

---The line, level and anchor of each part.
---@param split LangMarkdown.Split
---@return table[]
local function outline (split)
  local out = {}
  for _, part in ipairs (split.parts) do
    out[#out + 1] = { part.line, part.level or 0, part.anchor or '' }
  end
  return out
end

test ('split cuts the file at each heading', function ()
  local split = blocks.split (table.concat ({
    'Intro text.',
    '',
    '# Title',
    'Body.',
    '## Second part',
    'More.',
  }, '\n'))
  eq (outline (split), {
    { 1, 0, '' },
    { 3, 1, 'title' },
    { 5, 2, 'second-part' },
  })
  eq (split.parts[2].text, '# Title\nBody.')
  eq (split.lines, 6)
end)

test ('a heading inside a fenced code block is not one', function ()
  local split = blocks.split (table.concat ({
    '# Top',
    '```sh',
    '# a comment',
    '```',
    '~~~',
    '## also code',
    '~~~',
    '## Real',
  }, '\n'))
  eq (outline (split), { { 1, 1, 'top' }, { 8, 2, 'real' } })
end)

test ('a fence closes only with as many of the same character', function ()
  local split = blocks.split (table.concat ({
    '````',
    '```',
    '# still code',
    '````',
    '# Out',
  }, '\n'))
  eq (outline (split), { { 1, 0, '' }, { 5, 1, 'out' } })
end)

test ('a line of = or - under a paragraph makes a heading', function ()
  local split = blocks.split (table.concat ({
    'Big title',
    '=========',
    'text',
    '',
    'Small title',
    '---',
    '',
    '- a list item',
    '---',
  }, '\n'))
  eq (outline (split), { { 1, 1, 'big-title' }, { 5, 2, 'small-title' } })
end)

test ('front matter at the top is left out', function ()
  local split = blocks.split ('---\ntitle: x\n---\n# Hello\n')
  eq (outline (split), { { 4, 1, 'hello' } })
end)

test ('#tag with no space is no heading, and closing hashes go', function ()
  local split = blocks.split ('#tag\n# Done ##\n')
  eq (outline (split), { { 1, 0, '' }, { 2, 1, 'done' } })
  eq (split.parts[2].title, 'Done')
end)

test ('anchors follow GitHub and count repeats', function ()
  eq (blocks.slug ('Hello, World!'), 'hello-world')
  eq (blocks.slug ('The `code` and [a link](x.md)'), 'the-code-and-a-link')
  eq (blocks.slug ('snake_case and _italic_'), 'snake_case-and-italic')
  eq (blocks.slug ('Café menu'), 'café-menu')
  local split = blocks.split ('# Notes\n# Notes\n# Notes\n')
  eq (outline (split), {
    { 1, 1, 'notes' },
    { 2, 1, 'notes-1' },
    { 3, 1, 'notes-2' },
  })
end)

test ('reference definitions are collected', function ()
  local split = blocks.split ('See [home].\n\n[home]: ./README.md\n')
  eq (split.refs, { '[home]: ./README.md' })
end)

test ('each_line changes lines outside code only', function ()
  local split = blocks.split ('a\n```\nb\n```\nc', function (line)
    return line:upper ()
  end)
  eq (split.parts[1].text, 'A\n```\nb\n```\nC')
end)

test ('locate finds the part a line is in, and how far down', function ()
  local parts = { { line = 1 }, { line = 11 }, { line = 21 } }
  local index, fraction = blocks.locate (parts, 16, 30)
  eq (index, 2)
  eq (fraction, 0.5)
  index, fraction = blocks.locate (parts, 21, 30)
  eq ({ index, fraction }, { 3, 0 })
  index = blocks.locate ({ { line = 5 } }, 2, 30)
  eq (index, 1)
  eq (blocks.locate ({}, 3, 10), nil)
end)
