local attributes = require ('lib.attributes') --[[@as LangGitfiles.AttributesModule]]

---The labels of a completion list.
---@param items Proteus.CompletionItem[]
---@return table<string, boolean>
local function labels (items)
  local out = {}
  for _, item in ipairs (items) do
    out[item.label] = true
  end
  return out
end

test ('the pattern is typed first', function ()
  eq (attributes.at ('*.s', 3), { where = 'pattern', word = '*.s', from = 0 })
  ok (
    labels (attributes.items ({ where = 'pattern', word = '', from = 0 }))['* text=auto']
  )
end)

test ('an attribute name after the pattern', function ()
  eq (attributes.at ('*.sh te', 7), { where = 'name', word = 'te', from = 5 })
  eq (attributes.at ('*.png -di', 9), { where = 'name', word = 'di', from = 7 })
  eq (attributes.at ('*.png !di', 9), { where = 'name', word = 'di', from = 7 })
  eq (attributes.at ('*.sh text ', 10), { where = 'name', word = '', from = 10 })
end)

test ('a value after =', function ()
  eq (
    attributes.at ('*.sh text eol=', 14),
    { where = 'value', word = '', from = 14, name = 'eol' }
  )
  eq (
    attributes.at ('*.py diff=py', 12),
    { where = 'value', word = 'py', from = 10, name = 'diff' }
  )
end)

test ('nothing in a comment', function ()
  eq (attributes.at ('# eol=', 6), nil)
end)

test ('names and values come from the list', function ()
  local names =
    labels (attributes.items ({ where = 'name', word = '', from = 0 }))
  for _, name in ipairs ({
    'text',
    'eol',
    'binary',
    'diff',
    'merge',
    'filter',
    'export-ignore',
    'working-tree-encoding',
    'linguist-generated',
    'linguist-vendored',
    'linguist-documentation',
    'linguist-language',
  }) do
    ok (names[name], name)
  end
  local eol = labels (
    attributes.items ({ where = 'value', word = '', from = 0, name = 'eol' })
  )
  eq (eol, { lf = true, crlf = true })
  ok (
    labels (
      attributes.items ({ where = 'value', word = '', from = 0, name = 'merge' })
    ).ours
  )
  ok (
    labels (
      attributes.items ({ where = 'value', word = '', from = 0, name = 'filter' })
    ).lfs
  )
  eq (
    attributes.items ({ where = 'value', word = '', from = 0, name = 'nope' }),
    {}
  )
end)

test ('hover explains an attribute, its prefix and its value', function ()
  local line = '*.sh text eol=lf -diff !merge'
  local eol = attributes.hover (line, 12)
  ok (eol and eol:find ('**`eol=lf`**', 1, true))
  ok (eol and eol:find ('`lf`: Writes LF', 1, true))
  ok (attributes.hover (line, 19):find ('turns it off', 1, true))
  ok (attributes.hover (line, 25):find ('unspecified', 1, true))
  ok (attributes.hover (line, 6):find ('Marks the files as text', 1, true))
end)

test ('hover on the pattern says what it is for', function ()
  ok (attributes.hover ('*.sh text', 1):find ('sets attributes for', 1, true))
end)

test ('hover on an unknown word, a space or a comment gives nothing', function ()
  eq (attributes.hover ('*.sh madeup', 7), nil)
  eq (attributes.hover ('*.sh  text', 5), nil)
  eq (attributes.hover ('# text', 3), nil)
end)

test ('every attribute and value says what it does', function ()
  for _, a in ipairs (attributes.list) do
    ok (a.doc:match ('%.$'), a.name)
    for _, v in ipairs (a.values or {}) do
      ok (v[2]:match ('%.$'), a.name .. '=' .. v[1])
    end
  end
end)
