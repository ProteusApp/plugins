local edits = require ('lib.edits') --[[@as LangDocker.EditsModule]]

---@param sl integer
---@param sc integer
---@param el integer
---@param ec integer
---@param text string
---@return LangDocker.TextEdit
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
  eq (edits.offset ('ab\ncd', 0, 9), 3)
  eq (edits.offset ('ab\ncd', 5, 0), 6)
end)

test ('offset counts columns in UTF-16 units', function ()
  local text = 'é😀x'
  eq (text:sub (edits.offset (text, 0, 3)), 'x')
end)

test ('apply makes the edits docker-langserver sends to format', function ()
  -- docker-langserver 0.15.0 answered textDocument/formatting with these two edits, for
  -- tabSize 4 and spaces.
  local text = 'from alpine:3.20\n'
    .. 'MAINTAINER me\n'
    .. '   RUN echo hi && \\\n'
    .. '      echo there\n'
  local out = edits.apply (text, {
    edit (2, 0, 2, 3, ''),
    edit (3, 0, 3, 6, '    '),
  })
  eq (
    out,
    'from alpine:3.20\nMAINTAINER me\nRUN echo hi && \\\n    echo there\n'
  )
end)

test ('apply keeps the order of inserts at one place', function ()
  eq (
    edits.apply ('xy', { edit (0, 1, 0, 1, 'a'), edit (0, 1, 0, 1, 'b') }),
    'xaby'
  )
  eq (edits.apply ('same', {}), 'same')
end)
