local completion = require ('lib.completion') --[[@as LangCss.CompletionModule]]

test ('plain stops where the snippet puts the cursor first', function ()
  eq (completion.plain ('color: $0;'), 'color: ')
  eq (completion.plain ('var($1)'), 'var(')
  eq (completion.plain ('url(${1:path})'), 'url(')
  eq (completion.plain ('${1|a,b|} x'), '')
  eq (completion.plain ('display'), 'display')
end)

test ('plain keeps escaped characters and Sass variables', function ()
  eq (completion.plain ([[red(\$color: ${1:#000000})]]), 'red($color: ')
  eq (completion.plain ([[a \} b \\ c]]), [[a } b \ c]])
  eq (completion.plain ('$name'), '$name')
end)

test ('text turns only snippets into plain text', function ()
  eq (
    completion.text ({
      label = 'color',
      insertTextFormat = 2,
      textEdit = {
        newText = 'color: $0;',
        range = {},
      },
    }),
    'color: '
  )
  eq (completion.text ({ label = '$1 off', insertText = '$1 off' }), '$1 off')
  eq (completion.text ({ label = 'block' }), 'block')
  eq (completion.text ({}), nil)
end)

test ('word_start counts dashes, $ and @ as part of the word', function ()
  eq (completion.word_start ('  background-im', 15), 2)
  eq (completion.word_start ('  color: $mai', 13), 9)
  eq (completion.word_start ('@med', 4), 0)
  eq (completion.word_start ('  color: ', 9), 9)
end)

---A server item that replaces columns `start` to `stop` of line 2 with `text`.
---@param text string
---@param start integer
---@param stop integer
---@return table
local function item (text, start, stop)
  return {
    label = 'x',
    insertTextFormat = 2,
    textEdit = {
      newText = text,
      range = {
        start = { line = 2, character = start },
        ['end'] = { line = 2, character = stop },
      },
    },
  }
end

test ('from is where the server replaces a dashed name', function ()
  -- `.z { background-im }` with the cursor after `im`, as the server answered it.
  local line, pos = '.z { background-im }', { line = 2, character = 18 }
  local raws = { item ('background-image: ', 5, 18) }
  local from = completion.from (raws, line, pos)
  eq (from, 5)
  eq (completion.insert (raws[1], line, pos, from), 'background-image: ')
end)

test ('from falls back to the word before the cursor', function ()
  local line, pos = '  backg', { line = 2, character = 7 }
  eq (completion.from ({ { label = 'background' } }, line, pos), 2)
  -- A range on another line does not count.
  eq (
    completion.from ({ item ('x', 0, 1) }, line, { line = 3, character = 7 }),
    2
  )
end)

test ('insert puts back what lies between from and a later start', function ()
  local line, pos = '  a: $b', { line = 2, character = 7 }
  eq (completion.insert (item ('bc', 6, 7), line, pos, 5), '$bc')
end)

test ('insert leaves out what is typed before from', function ()
  local line, pos = '  color: $ma', { line = 2, character = 12 }
  eq (completion.insert ({ label = '$main' }, line, pos, 10), 'main')
end)

test ('offset counts columns as UTF-16 does', function ()
  eq (completion.offset ('abc', 2), 2)
  eq (completion.offset ('é"x', 1), 2)
  eq (completion.offset ('😀x', 2), 4)
  eq (completion.slice ('"é"x', 1, 3), 'é"')
end)

test ('line gives one line without its break', function ()
  eq (completion.line ('a {\r\n  color: red;\r\n}', 1), '  color: red;')
  eq (completion.line ('one', 3), '')
end)
