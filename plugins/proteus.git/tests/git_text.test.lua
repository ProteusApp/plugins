-- Tests for git_text, the text helpers the other git modules share.

local T = require ('git_text') --[[@as Git.TextModule]]

test ('split keeps empty fields', function ()
  eq (T.split ('a,b', ','), { 'a', 'b' })
  eq (T.split ('a,,b,', ','), { 'a', '', 'b', '' })
  eq (T.split ('', ','), { '' })
  -- The separator is plain text, not a pattern.
  eq (T.split ('a.b', '.'), { 'a', 'b' })
  eq (T.split ('a\0b\0', '\0'), { 'a', 'b', '' })
end)

test ('lines_of leaves out the newline at the very end', function ()
  eq (T.lines_of ('one\ntwo\n'), { 'one', 'two' })
  eq (T.lines_of ('one\ntwo'), { 'one', 'two' })
  eq (T.lines_of ('one\n\n'), { 'one', '' })
  eq (T.lines_of (''), {})
end)

test ('trim, strip_cr and int', function ()
  eq (T.trim ('  a b \n'), 'a b')
  eq (T.trim (''), '')
  eq (T.strip_cr ('line\r'), 'line')
  eq (T.strip_cr ('line\r\r'), 'line\r')
  eq (T.strip_cr ('line'), 'line')
  eq (T.int ('12'), 12)
  eq (T.int (nil), 0)
  eq (T.int ('x'), 0)
end)
