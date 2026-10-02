local completion = require ('lib.completion') --[[@as LangShell.CompletionModule]]

test ('word_start finds letters, digits and _ before the cursor', function ()
  eq (completion.word_start ('ls --al', 7), 5)
  eq (completion.word_start ('echo $na', 8), 6)
  eq (completion.word_start ('ech', 3), 0)
  eq (completion.word_start ('ls --', 5), 5)
end)

test ('insert gives a plain name as it is', function ()
  local pos = { line = 0, character = 8 }
  eq (
    completion.insert ({ label = 'name', kind = 6 }, 'echo $na', pos, 6),
    'name'
  )
end)

test ('insert puts the typed part of an option back in front', function ()
  -- `ls --al` with the cursor at the end. The server adds `l` at the cursor.
  local raw = {
    label = '--all',
    textEdit = {
      newText = 'l',
      range = {
        start = { line = 3, character = 7 },
        ['end'] = { line = 3, character = 7 },
      },
    },
  }
  eq (completion.insert (raw, 'ls --al', { line = 3, character = 7 }, 5), 'all')
  -- `ls --` with nothing of the option typed yet.
  raw.textEdit.newText = 'all'
  raw.textEdit.range.start.character = 5
  raw.textEdit.range['end'].character = 5
  eq (completion.insert (raw, 'ls --', { line = 3, character = 5 }, 5), 'all')
end)

test ('insert takes the snippet marks out', function ()
  local raw = {
    label = 'if',
    insertText = 'if [ ${1:cond} ]; then\n\t$0\nfi',
    insertTextFormat = 2,
  }
  eq (
    completion.insert (raw, 'if', { line = 0, character = 2 }, 0),
    'if [ cond ]; then\n\t\nfi'
  )
end)
