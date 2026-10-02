local completion = require ('lib.completion') --[[@as LangDocker.CompletionModule]]

---A server item that replaces line 0 from `start` to `stop` with `text`, as
---docker-langserver 0.15.0 sends it with snippets off.
---@param text string
---@param start integer
---@param stop integer
---@return table
local function item (text, start, stop)
  return {
    label = text,
    insertTextFormat = 1,
    textEdit = {
      newText = text,
      range = {
        start = { line = 0, character = start },
        ['end'] = { line = 0, character = stop },
      },
    },
  }
end

---@param col integer
---@return Proteus.CodePosition
local function at (col)
  return { line = 0, character = col }
end

test ('line gives one line without its break', function ()
  eq (completion.line ('FROM a\r\nRUN b\r\n', 1), 'RUN b')
  eq (completion.line ('FROM a', 3), '')
end)

test ('word_start finds letters, digits and _ before the cursor', function ()
  eq (completion.word_start ('COPY --ch', 9), 7)
  eq (completion.word_start ('FR', 2), 0)
  eq (completion.word_start ('RUN echo $', 10), 10)
end)

test ('from is where the server replaces from', function ()
  local line = 'COPY --ch'
  eq (completion.from ({ item ('--chown=', 5, 9) }, line, at (9)), 5)
  eq (
    completion.from ({ item ('${VERSION}', 9, 12) }, 'RUN echo ${V', at (12)),
    9
  )
  -- Without a range on this line, the word before the cursor.
  eq (completion.from ({ { label = 'FROM' } }, 'FR', at (2)), 0)
  eq (completion.from ({}, 'COPY --ch', at (9)), 7)
end)

test ('insert keeps the server text when it starts at from', function ()
  local line = 'COPY --ch'
  eq (completion.insert (item ('--chown=', 5, 9), line, at (9), 5), '--chown=')
  eq (completion.insert (item ('FROM', 0, 2), 'FR', at (2), 0), 'FROM')
end)

test ('insert fits an item that starts elsewhere', function ()
  local line = 'COPY --ch'
  -- The editor replaces from the word, so the typed `--` stays.
  eq (completion.insert (item ('--chown=', 5, 9), line, at (9), 7), 'chown=')
  -- The editor replaces from before the item, so that part comes back.
  eq (completion.insert (item ('chown=', 7, 9), line, at (9), 5), '--chown=')
end)

test ('insert leaves text after the cursor in place', function ()
  local line = 'RUN echo ${V}'
  eq (
    completion.insert (item ('${VERSION}', 9, 13), line, at (12), 9),
    '${VERSION'
  )
end)

test ('insert falls back to insertText and the label', function ()
  eq (
    completion.insert ({ label = 'RUN', insertText = 'RUN ' }, '', at (0), 0),
    'RUN '
  )
  eq (completion.insert ({ label = 'CMD' }, '', at (0), 0), 'CMD')
end)
