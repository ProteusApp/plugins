local core = require ('search_core') --[[@as CodeSearch.Core]]

---@param path string
---@param line integer
---@param col integer
---@param hit string
---@param with? string
---@return Proteus.SearchMatch
local function match (path, line, col, hit, with)
  return {
    path = path,
    line = line,
    col = col,
    before = '',
    hit = hit,
    after = '',
    with = with,
  }
end

test (
  'globs reads patterns typed with commas, and a folder means what is in it',
  function ()
    eq (
      core.globs (' src , *.ts,, ./docs/ ,a\\b'),
      { 'src/**', '*.ts', 'docs/**', 'a/b/**' }
    )
    eq (core.globs (''), {})
  end
)

test ('by_file groups matches in the order they came', function ()
  local files = core.by_file ({
    match ('a.lua', 1, 1, 'x'),
    match ('a.lua', 2, 1, 'x'),
    match ('b.lua', 1, 1, 'x'),
  })
  eq (#files, 2)
  eq (files[1].path, 'a.lua')
  eq (#files[1].matches, 2)
  eq (files[2].path, 'b.lua')
end)

test ('summary counts results and files', function ()
  eq (core.summary (0, 0, false), 'No results.')
  eq (core.summary (1, 1, false), '1 result in 1 file.')
  eq (
    core.summary (2000, 7, true),
    'The first 2000 results in 7 files. Narrow the search to see the rest.'
  )
end)

test ('remember keeps each search once, newest first', function ()
  eq (core.remember ({ 'b', 'a', 'c' }, 'a', 3), { 'a', 'b', 'c' })
  eq (core.remember ({ 'b', 'c' }, 'a', 2), { 'a', 'b' })
end)

test (
  'exact_glob matches one file from the root, whatever its name holds',
  function ()
    eq (core.exact_glob ('src/main.rs'), '/src/main.rs')
    eq (core.exact_glob ('a/[x]*?.txt'), '/a/\\[x\\]\\*\\?.txt')
    eq (core.exact_glob ('odd '), '/odd\\ ')
  end
)

test ('rows leave out the matches of a file folded shut', function ()
  local files = {
    {
      path = 'a',
      matches = { match ('a', 1, 1, 'x'), match ('a', 2, 1, 'x') },
    },
    { path = 'b', matches = { match ('b', 1, 1, 'x') } },
  }
  local keys = {} ---@type string[]
  for _, r in ipairs (core.rows (files, { a = true })) do
    keys[#keys + 1] = r.key
  end
  eq (keys, { 'f:1', 'f:2', 'm:2:1' })
  eq (#core.rows (files, {}), 5)
end)

test ('next_match goes round the matches of every file', function ()
  local files = {
    {
      path = 'a',
      matches = { match ('a', 1, 1, 'x'), match ('a', 2, 1, 'x') },
    },
    { path = 'b', matches = { match ('b', 1, 1, 'x') } },
  }
  eq ({ core.next_match (files, nil, nil, 1) }, { 1, 1 })
  eq ({ core.next_match (files, nil, nil, -1) }, { 2, 1 })
  eq ({ core.next_match (files, 1, 2, 1) }, { 2, 1 })
  eq ({ core.next_match (files, 2, 1, 1) }, { 1, 1 })
  eq ({ core.next_match (files, 1, 1, -1) }, { 2, 1 })
  -- From a file's row, Next goes to its first match and Previous to the match before it.
  eq ({ core.next_match (files, 2, nil, 1) }, { 2, 1 })
  eq ({ core.next_match (files, 2, nil, -1) }, { 1, 2 })
  eq ({ core.next_match ({}, nil, nil, 1) }, {})
end)

test ('byte_at counts columns in UTF-16 units', function ()
  eq (core.byte_at ('abc', 1), 1)
  eq (core.byte_at ('abc', 4), 4)
  eq (core.byte_at ('abc', 5), nil)
  -- é is two bytes and one unit, and the face is four bytes and two units.
  eq (core.byte_at ('é😀x', 2), 3)
  eq (core.byte_at ('é😀x', 4), 7)
  eq (core.byte_at ('é😀x', 3), nil)
end)

test ('replace_one replaces the match where the search found it', function ()
  local text = 'one foo\r\ntwo foo foo\n'
  eq (
    core.replace_one (text, match ('a', 2, 9, 'foo', 'bar')),
    'one foo\r\ntwo foo bar\n'
  )
  eq (
    core.replace_one (text, match ('a', 1, 5, 'foo', '')),
    'one \r\ntwo foo foo\n'
  )
  eq (core.replace_one ('é foo', match ('a', 1, 3, 'foo', 'x')), 'é x')
end)

test ('replace_one refuses a match that moved or was cut short', function ()
  local text = 'one foo\n'
  local out, problem = core.replace_one (text, match ('a', 1, 2, 'foo', 'bar'))
  eq (out, nil)
  ok (problem and problem:find ('changed'))
  out, problem = core.replace_one (text, match ('a', 3, 1, 'foo', 'bar'))
  eq (out, nil)
  ok (problem and problem:find ('changed'))
  out, problem = core.replace_one (text, match ('a', 1, 5, 'foo'))
  eq (out, nil)
  ok (problem)
  local long = string.rep ('x', core.HIT_CHARS) .. '…'
  out, problem = core.replace_one (text, match ('a', 1, 1, long, 'y'))
  eq (out, nil)
  ok (problem and problem:find ('too long'))
end)
