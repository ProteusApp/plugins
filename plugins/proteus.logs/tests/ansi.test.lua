local ansi = require ('log_ansi') --[[@as Logs.AnsiModule]]
local lf = require ('log_filter') --[[@as Logs.FilterModule]]

local ESC = '\27'

test ('log_filter hands out the colour code functions of log_ansi', function ()
  ok (lf.parse_ansi == ansi.parse_ansi)
  ok (lf.strip_ansi == ansi.strip_ansi)
end)

test ('parse_ansi gives text with no codes back as one run', function ()
  eq (ansi.parse_ansi (''), {})
  eq (
    ansi.parse_ansi ('plain\ttext'),
    { { text = 'plain\ttext', bold = false } }
  )
end)

test ('parse_ansi reads bright colours and resets them', function ()
  eq (ansi.parse_ansi (ESC .. '[92mok' .. ESC .. '[39m done'), {
    { text = 'ok', fg = 10, bold = false },
    { text = ' done', bold = false },
  })
end)

test (
  'parse_ansi takes the first 16 of 256 colours and skips true colour',
  function ()
    eq (
      ansi.parse_ansi (ESC .. '[38;5;3mx'),
      { { text = 'x', fg = 3, bold = false } }
    )
    eq (ansi.parse_ansi (ESC .. '[38;5;200mx'), { { text = 'x', bold = false } })
    -- The numbers of a true colour are not read as codes, so 1 does not turn bold on.
    eq (
      ansi.parse_ansi (ESC .. '[38;2;1;1;1mx'),
      { { text = 'x', bold = false } }
    )
  end
)

test (
  'parse_ansi drops title sequences and stray control characters',
  function ()
    eq (
      ansi.parse_ansi (ESC .. ']0;title\7a\1b'),
      { { text = 'ab', bold = false } }
    )
    eq (ansi.parse_ansi ('a' .. ESC .. ']8;;http://x' .. ESC .. '\\b'), {
      { text = 'ab', bold = false },
    })
  end
)

test ('strip_ansi keeps text with no codes as it is', function ()
  local text = 'no codes here'
  ok (ansi.strip_ansi (text) == text)
  eq (ansi.strip_ansi (ESC .. '[1;31merror' .. ESC .. '[0m: x'), 'error: x')
end)
