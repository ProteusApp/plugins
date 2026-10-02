local re = require ('log_regex') --[[@as { compile: fun(pattern: string, opts?: { fold?: boolean }): LogRegex.Program?, string? }]]

---Where a pattern first matches in a text, as { start, stop }, or false.
---@param pattern string
---@param text string
---@param fold? boolean
---@return table|false
local function where (pattern, text, fold)
  local prog = assert (re.compile (pattern, { fold = fold }))
  local s, e = prog.find (text)
  if not s then
    return false
  end
  return { s, e }
end

test ('compile reads literals, classes, anchors and repeats', function ()
  eq (where ('err', 'an error'), { 4, 6 })
  eq (where ('e.r', 'beer'), { 2, 4 })
  eq (where ('\\d+', 'id=12345;'), { 4, 8 })
  eq (where ('[a-c]+', 'xxabcabd'), { 3, 7 })
  eq (where ('[^ ]+$', 'last word'), { 6, 9 })
  eq (where ('^GET', 'a GET'), false)
  eq (where ('^GET', 'GET /'), { 1, 3 })
  eq (where ('\\bcat\\b', 'concat cat'), { 8, 10 })
  eq (where ('colou?r', 'color'), { 1, 5 })
  eq (where ('a{2,3}', 'caaaat'), { 2, 4 })
  eq (where ('a{2}', 'ca'), false)
  eq (
    where ('x{,}', 'x{,}'),
    { 1, 4 },
    'a brace that is not a count stands for itself'
  )
  eq (where ('\\.json$', 'a.json'), { 2, 6 })
  eq (where ('\\[\\w+\\]', 'at [main] start'), { 4, 9 })
end)

test ('compile reads groups, alternation and lazy repeats', function ()
  eq (where ('time(out|d out)', 'request timed out'), { 9, 17 })
  eq (where ('(?:ab)+c', 'xababc'), { 2, 6 })
  eq (where ('<.+?>', '<a><b>'), { 1, 3 })
  eq (where ('<.+>', '<a><b>'), { 1, 6 })
  eq (where ('(a|ab)c', 'abc'), { 1, 3 }, 'it backtracks into a group')
  eq (
    where ('(x*)*y', 'xxxy'),
    { 1, 4 },
    'a group that matches nothing stops repeating'
  )
  eq (where ('WARN|Error', 'an error', true), { 4, 8 })
end)

test ('fold matches a text in lower case whatever the pattern says', function ()
  eq (where ('[A-Z]+', 'abc', true), { 1, 3 })
  eq (where ('[A-Z]+', 'abc'), false)
  eq (where ('Timeout', 'timeout'), false)
  eq (where ('Timeout', 'timeout', true), { 1, 7 })
end)

test ('a long line does not run out of stack', function ()
  local long = string.rep ('a', 100000) .. 'b'
  eq (where ('a*b', long), { 1, 100001 })
  eq (where ('.*b$', long), { 1, 100001 })
end)

test ('compile says what is wrong with a pattern', function ()
  ---@param pattern string
  ---@return string?
  local function problem (pattern)
    local _, err = re.compile (pattern)
    return err
  end
  eq (problem ('(a'), 'a ( has no )')
  eq (problem ('a)'), 'a ) has no (')
  eq (problem ('[a'), 'a [ has no ]')
  eq (problem ('*a'), 'nothing comes before *')
  eq (problem ('a\\'), 'the pattern ends with a \\')
  eq (problem ('[z-a]'), 'a range in [ ] runs backwards')
  eq (problem ('(?=a)'), '(? is supported only as (?: and (?<name>')
  eq (problem ('^*'), 'an anchor cannot repeat')
end)

test ('match gives what each group took, by number and by name', function ()
  local prog = assert (
    re.compile ('^(?<time>\\S+) \\[(?P<level>\\w+)\\] (\\w+)?(?:x)?(.*)$')
  )
  eq (prog.names, { 'time', 'level' })
  local got = assert (prog.match ('12:00 [WARN] disk almost full'))
  eq (got.time, '12:00')
  eq (got.level, 'WARN')
  eq (got[1], '12:00')
  eq (got[3], 'disk')
  eq (got[4], ' almost full')
  eq (got[0], '12:00 [WARN] disk almost full')
  eq (prog.match ('no match'), nil)
  local back = assert (re.compile ('(a+)(a)b'))
  local taken = assert (back.match ('aaab'))
  eq ({ taken[1], taken[2] }, { 'aa', 'a' }, 'a group gives back on a backtrack')
  local alt = assert (re.compile ('(?<k>x)|(?<v>y)'))
  local y = assert (alt.match ('y'))
  eq ({ y.k, y.v }, { nil, 'y' }, 'a group that took nothing has no entry')
  local _, err = re.compile ('(?<a>x)(?<a>y)')
  eq (err, 'two groups are named a')
  local _, look = re.compile ('(?=x)')
  eq (look, '(? is supported only as (?: and (?<name>')
end)
