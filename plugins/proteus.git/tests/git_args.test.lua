-- Tests for git_args, the command lines the Git client runs. tests/git.test.lua reaches the
-- same functions through git_parse.

local A = require ('git_args') --[[@as Git.ArgsModule]]
local m = require ('git_parse') --[[@as Git.ParseModule]]

test ('git_parse hands out every function and format of git_args', function ()
  for k, v in pairs (A) do
    eq (m[k], v, k)
  end
  eq (m.LOG_FORMAT, A.LOG_FORMAT)
end)

test ('base_args gives a new list each time', function ()
  -- The client adds each command's own arguments to the list it gets.
  local first = A.base_args ()
  first[#first + 1] = 'status'
  eq (A.base_args (), { '--literal-pathspecs', '-c', 'core.quotepath=false' })
end)

test ('status_args reads only the modes Git knows', function ()
  eq (A.status_args ('no\n')[5], '--untracked-files=no')
  eq (A.status_args (' normal ')[5], '--untracked-files=normal')
  eq (A.status_args ('false')[5], '--untracked-files=all')
  eq (A.status_args ('')[5], '--untracked-files=all')
end)

test ('log_args leaves out a skip of zero', function ()
  eq (A.log_args (50, { skip = 0 }), A.log_args (50))
  eq (A.log_args (50, { skip = 50 })[7], '--skip=50')
  -- Search text reaches Git as it is, never as a pattern.
  eq (
    A.search_args ('fix [x]*'),
    { '--regexp-ignore-case', '--fixed-strings', '--grep=fix [x]*' }
  )
end)

test ('show_args and stash_show_args keep the a/ and b/ prefixes', function ()
  eq (A.show_args ('abc'), {
    'show',
    '--no-color',
    '--no-ext-diff',
    '--src-prefix=a/',
    '--dst-prefix=b/',
    '-m',
    '--first-parent',
    '--date=format-local:%Y-%m-%d %H:%M',
    A.SHOW_FORMAT,
    '--patch',
    'abc',
  })
  eq (A.stash_show_args ('stash@{0}'), {
    'stash',
    'show',
    '--patch',
    '--no-color',
    '--no-ext-diff',
    '--src-prefix=a/',
    '--dst-prefix=b/',
    'stash@{0}',
  })
end)

test ('switch_args gives nothing for the Create item', function ()
  local create = { label = 'Create', icon = 'plus', action = 'create' }
  eq (A.switch_args (create, {}), nil)
  local track = { label = 'x', icon = 'cloud', action = 'track', name = 'up/x' }
  eq (A.switch_args (track, {}), { 'switch', '--track', 'up/x' })
end)
