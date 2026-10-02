-- Tests for git_paths: paths, the recent list, and the text to show when git fails.
-- tests/git.test.lua reaches the same functions through git_parse.

local m = require ('git_parse') --[[@as Git.ParseModule]]
local paths = require ('git_paths') --[[@as Git.PathsModule]]

test ('git_parse hands out every function of git_paths', function ()
  for k, v in pairs (paths) do
    eq (m[k], v, k)
  end
  eq (m.split_path, paths.split_path)
end)

test ('split_path and parent take a folder off the end', function ()
  eq ({ paths.split_path ('src/') }, { 'src', '' })
  eq ({ paths.split_path ('a/b/') }, { 'b', 'a' })
  eq (paths.parent ('C:\\r\\a\\b.txt'), 'C:\\r\\a')
  eq (paths.parent ('C:/r/a/'), 'C:/r')
  eq (paths.parent ('a.txt'), 'a.txt')
end)

test ('join drops the separators at the end of the root', function ()
  eq (paths.join ('/r//', 'a.txt'), '/r/a.txt')
  eq (paths.join ('C:\\r\\', 'a.txt'), 'C:\\r/a.txt')
end)

test ('remember keeps no more than max', function ()
  eq (paths.remember ({ 'a', 'b' }, 'c', 1), { 'c' })
  eq (paths.remember ({ 'a', 'b' }, 'a', 2), { 'a', 'b' })
end)

test ('error_text keeps up to eight lines', function ()
  local eight = string.rep ('x\n', 8)
  eq (
    paths.error_text ({ code = 1, stdout = '', stderr = eight }, nil),
    string.rep ('x\n', 7) .. 'x'
  )
  eq (
    paths.error_text ({ code = 1, stdout = '', stderr = eight .. 'y\n' }, nil),
    eight .. '…'
  )
  eq (
    paths.error_text ({ code = 1, stdout = 'out\n', stderr = '  \n' }, nil),
    'out'
  )
end)

test ('summary takes the first line, without a carriage return', function ()
  eq (
    paths.summary ({ code = 0, stdout = 'Done.\r\nmore\r\n', stderr = '' }),
    'Done.'
  )
  eq (paths.summary ({ code = 0, stdout = '  \n', stderr = 'x\n' }), 'x')
  eq (paths.is_binary_error ('invalid UTF-8'), true)
end)
