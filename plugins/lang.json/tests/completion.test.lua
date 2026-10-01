local completion = require ('lib.completion') --[[@as LangJson.CompletionModule]]

test ('plain takes the snippet marks out', function ()
  eq (completion.plain ('"version": "$1"'), '"version": ""')
  eq (completion.plain ('"keywords": [$1]'), '"keywords": []')
  eq (completion.plain ('{\n\t"a": ${1:false}$0\n}'), '{\n\t"a": false\n}')
  eq (completion.plain ('${1|one,two|}'), 'one')
  eq (completion.plain ('${1}x'), 'x')
  eq (completion.plain ('\\$1 costs \\}'), '$1 costs }')
  eq (completion.plain ('${1:a ${2:b}}'), 'a b')
  eq (completion.plain ('$name and ${x}'), '$name and ${x}')
end)

test ('line gives one line without its break', function ()
  eq (completion.line ('{\r\n  "a": 1\r\n}', 1), '  "a": 1')
  eq (completion.line ('one', 0), 'one')
  eq (completion.line ('one', 3), '')
end)

test ('offset counts columns as UTF-16 does', function ()
  eq (completion.offset ('abc', 2), 2)
  eq (completion.offset ('é"x', 1), 2)
  eq (completion.offset ('😀x', 2), 4)
  eq (completion.slice ('"é"x', 1, 3), 'é"')
end)

test ('word_start finds letters, digits and _ before the cursor', function ()
  eq (completion.word_start ('  "na', 5), 3)
  eq (completion.word_start ('  "', 3), 3)
  eq (completion.word_start ('a_b1', 4), 0)
end)

---A server item that replaces `line` from `start` to `stop` with `text`.
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

test ('insert leaves out the quote typed before the word', function ()
  -- `  "na` with the cursor at the end.
  local line, pos = '  "na', { line = 2, character = 5 }
  eq (
    completion.insert (item ('"version": "$1"', 2, 5), line, pos, 3),
    'version": ""'
  )
end)

test ('insert leaves out the closing quote after the cursor', function ()
  -- `  "na"` with the cursor before the closing quote.
  local line, pos = '  "na"', { line = 2, character = 5 }
  eq (
    completion.insert (item ('"version": "$1"', 2, 6), line, pos, 3),
    'version": "'
  )
  eq (
    completion.insert (item ('"keywords": [$1]', 2, 6), line, pos, 3),
    'keywords'
  )
  -- `  "type": ""` with the cursor between the quotes.
  local value = '  "type": ""'
  eq (
    completion.insert (
      item ('"module"', 10, 12),
      value,
      { line = 2, character = 11 },
      11
    ),
    'module'
  )
end)

test (
  'insert puts back what lies between an earlier start and the range',
  function ()
    -- npm completion starts at `@`, and the server's range at the `t`.
    local line, pos = '    "@ty', { line = 2, character = 8 }
    eq (completion.insert (item ('types', 6, 8), line, pos, 5), '@types')
  end
)

test ('insert falls back to the text without a range on this line', function ()
  local pos = { line = 2, character = 1 }
  eq (
    completion.insert (
      { label = 'a', insertText = '"a": $1', insertTextFormat = 2 },
      'x',
      pos,
      1
    ),
    '"a": '
  )
  eq (completion.insert ({ label = 'true' }, 'x', pos, 1), 'true')
  eq (completion.insert ({}, 'x', pos, 1), nil)
end)
