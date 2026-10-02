local core = require ('api_core') --[[@as ApiApp.Core]]

---An answer from an older app, which had only these fields.
---@param fields table<string, any>
---@return Proteus.HttpReply
local function reply (fields)
  return fields --[[@as Proteus.HttpReply]]
end

test ('folder_files runs from a folder out to the top', function ()
  eq (core.folder_files ('data/api', 'pets/cats'), {
    'data/api/pets/cats/.folder.json',
    'data/api/pets/.folder.json',
    'data/api/.folder.json',
  })
  eq (core.folder_files ('data/api', ''), { 'data/api/.folder.json' })
  eq (
    core.folder_of_file ('data/api', 'data/api/pets/cats/.folder.json'),
    'pets/cats'
  )
  eq (core.folder_of_file ('data/api', 'data/api/.folder.json'), '')
  ok (core.hidden ('.folder.json'))
  ok (not core.hidden ('Get pets.json'))
end)

test ('a token is good until shortly before it ends', function ()
  local kept = core.keep_token ('abc', 3600, 1000)
  eq (kept, { token = 'abc', ends = 1000 + 3600 * 1000 })
  ok (core.token_fresh (kept, 1000))
  ok (
    not core.token_fresh (kept, kept.ends - 10 * 1000),
    'thirty seconds to go is too close'
  )
  eq (core.keep_token ('abc', nil, 5), { token = 'abc' })
  ok (
    core.token_fresh (core.keep_token ('abc', nil, 5), 1e15),
    'no end said is no end'
  )
  ok (not core.token_fresh (nil, 0))
  ok (not core.token_fresh ({ token = '' }, 0))
end)

test ('send_problem says which file to pick, or what else is wrong', function ()
  eq (core.send_problem ({ unpicked = {}, problems = {} }), nil)
  eq (
    core.send_problem ({ unpicked = { 'the body' }, problems = {} }),
    'Pick the file to send in the Body tab first.'
  )
  eq (
    core.send_problem ({ unpicked = { '"photo"' }, problems = {} }),
    'Pick the file for "photo" in the Body tab first, or switch that row off.'
  )
  eq (
    core.send_problem ({ unpicked = { '"a"', '"b"', '"c"' }, problems = {} }),
    'Pick the file for "a", "b" and "c" in the Body tab first, or switch those rows off.'
  )
  eq (
    core.send_problem ({ unpicked = { '"a"' }, problems = { 'Bad variables.' } }),
    'Bad variables.'
  )
end)

test (
  'parse_timeout reads seconds, and timeout_text writes them back',
  function ()
    eq (core.parse_timeout (''), 0)
    eq (core.parse_timeout (' 90 '), 90)
    eq (core.parse_timeout ('2.5'), 2.5)
    eq (core.parse_timeout ('-1'), nil)
    eq (core.parse_timeout ('4000'), nil)
    eq (core.parse_timeout ('soon'), nil)
    eq (core.timeout_text (0), '')
    eq (core.timeout_text (90), '90')
    eq (core.timeout_text (2.5), '2.5')
  end
)

test ('random_hex gives hex of the length asked', function ()
  local n = 0
  local text = core.random_hex (8, function (_, high)
    n = n + 1
    return n % (high + 1)
  end)
  eq (text, '12345678')
end)

test ('result_of keeps an answer, and copes with an older app', function ()
  local r = core.result_of ({
    status = 200,
    headers = { ['set-cookie'] = 'a=1\nb=2' },
    header_list = {
      { name = 'set-cookie', value = 'a=1' },
      { name = 'set-cookie', value = 'b=2' },
    },
    body = 'AAEC',
    encoding = 'base64',
    size = 3,
    url = 'https://x.io/end',
    redirects = 1,
    ms = 12.5,
  }, 'https://x.io/start', 99, 'careful')
  eq (r.status, 200)
  eq (#r.list, 2)
  eq (r.binary, true)
  eq (r.size, 3)
  eq (r.ms, 12.5)
  eq (r.url, 'https://x.io/end')
  eq (r.redirects, 1)
  eq (r.warning, 'careful')

  local old = core.result_of (
    reply ({ status = 404, headers = { b = '2', a = '1' }, body = 'nope' }),
    'https://x.io',
    40
  )
  eq (old.list, { { name = 'a', value = '1' }, { name = 'b', value = '2' } })
  eq (old.binary, false)
  eq (old.size, 4)
  eq (old.ms, 40)
  eq (old.url, nil)

  local same = core.result_of (
    reply ({ status = 200, headers = {}, body = '', url = 'https://x.io' }),
    'https://x.io',
    1
  )
  eq (same.url, nil, 'an answer from the address sent to says nothing of it')
  eq (core.empty_result ({ error = 'No answer.' }).error, 'No answer.')
end)

test ('a request file gives its name and its folder', function ()
  eq (core.stem ('data/api/pets/Get cats.json'), 'Get cats')
  eq (core.stem ('data/api/notes'), 'data/api/notes')
  eq (core.folder_of ('data/api', 'data/api/pets/cats/List.json'), 'pets/cats')
  eq (core.folder_of ('data/api', 'data/api/List.json'), '')
  eq (core.folder_of ('data/api', 'data/api/pets'), '')
  eq (core.path_for ('data/api', 'pets', 'List'), 'data/api/pets/List.json')
  eq (core.path_for ('data/api', '', 'List'), 'data/api/List.json')
end)

test ('grid_item reads the row and the field of an event', function ()
  eq ({ core.grid_item ('3:value') }, { 3, 'value' })
  eq ({ core.grid_item ('12:del') }, { 12, 'del' })
  eq ({ core.grid_item ('x:value') }, {})
  eq ({ core.grid_item ('3:') }, {})
  eq ({ core.grid_item (nil) }, {})
end)
