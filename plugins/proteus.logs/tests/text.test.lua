local lf = require ('log_filter') --[[@as Logs.FilterModule]]
local tx = require ('log_text') --[[@as Logs.TextModule]]

test ('log_filter hands out the text helpers of log_text', function ()
  ok (lf.escape == tx.escape)
  ok (lf.trim == tx.trim)
  ok (lf.sentence == tx.sentence)
  ok (lf.group == tx.group)
  ok (lf.clip == tx.clip)
  ok (lf.split_lines == tx.split_lines)
end)

test ('escape makes text safe inside HTML and its attributes', function ()
  eq (
    tx.escape ([[<a href="x">Tom & 'Jo'</a>]]),
    '&lt;a href=&quot;x&quot;&gt;Tom &amp; &#39;Jo&#39;&lt;/a&gt;'
  )
  eq (tx.escape ('plain'), 'plain')
end)

test ('trim keeps spaces inside the text', function ()
  eq (tx.trim ('\t a  b \n'), 'a  b')
  eq (tx.trim ('   '), '')
end)

test ('sentence leaves a stop or a question as it is', function ()
  eq (tx.sentence ('no such file'), 'No such file.')
  eq (tx.sentence ('Done!'), 'Done!')
  eq (tx.sentence ('why?'), 'Why?')
  eq (tx.sentence ('  '), '')
end)

test ('group writes small, large and negative numbers', function ()
  eq (tx.group (0), '0')
  eq (tx.group (999), '999')
  eq (tx.group (1000), '1,000')
  eq (tx.group (1234567), '1,234,567')
  eq (tx.group (-4500), '-4,500')
  eq (tx.group (12.7), '12')
end)

test ('clip keeps short text and cuts long text at a character', function ()
  eq (tx.clip ('short', 10), 'short')
  eq (tx.clip ('abcdef', 3), 'abc')
  -- é is two bytes, so cutting after its first byte keeps only the a.
  eq (tx.clip ('aé', 2), 'a')
end)

test ('split_lines reads every kind of line ending', function ()
  eq (tx.split_lines (''), {})
  eq (tx.split_lines ('a\r\nb\rc\nd'), { 'a', 'b', 'c', 'd' })
  eq (tx.split_lines ('a\n\nb\n'), { 'a', '', 'b' })
end)
