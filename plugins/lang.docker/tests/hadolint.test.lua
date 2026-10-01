local hadolint = require ('lib.hadolint') --[[@as LangDocker.HadolintModule]]

-- What Hadolint 2.15.1 printed for this file with `--format json -`, decoded.
local TEXT = 'FROM ubuntu\n'
  .. 'RUN apt-get update && apt-get install curl\n'
  .. 'MAINTAINER me\n'
  .. 'RUN echo "é😀"\n'
local FINDINGS = {
  {
    code = 'DL3006',
    column = 1,
    file = '-',
    level = 'warning',
    line = 1,
    message = 'Always tag the version of an image explicitly',
  },
  {
    code = 'DL3015',
    column = 1,
    file = '-',
    level = 'info',
    line = 2,
    message = 'Avoid additional packages by specifying `--no-install-recommends`',
  },
  {
    code = 'DL4000',
    column = 1,
    file = '-',
    level = 'error',
    line = 3,
    message = 'MAINTAINER is deprecated',
  },
}

test ('diagnostics turns findings into problems from 0', function ()
  local list = hadolint.diagnostics (FINDINGS, TEXT)
  eq (#list, 3)
  eq (list[1], {
    line = 0,
    character = 0,
    end_line = 0,
    end_character = 11,
    severity = 'warning',
    message = 'Always tag the version of an image explicitly',
    source = 'hadolint',
    code = 'DL3006',
  })
  eq (list[2].severity, 'info')
  eq (list[2].end_character, 42)
  eq (list[3].severity, 'error')
  eq (list[3].line, 2)
end)

test ('diagnostics gives style findings as hints', function ()
  local list = hadolint.diagnostics ({
    { code = 'DL3059', line = 1, column = 1, level = 'style', message = 'm' },
  }, 'RUN a\n')
  eq (list[1].severity, 'hint')
end)

test ('diagnostics counts the line in UTF-16 units', function ()
  local list = hadolint.diagnostics ({
    { code = 'X', line = 4, column = 1, level = 'warning', message = 'm' },
  }, TEXT)
  -- `RUN echo "` is 10, é is 1 and 😀 is 2, then the closing quote.
  eq (list[1].end_character, 14)
end)

test ('diagnostics reads a line past the end, CRLF and odd entries', function ()
  local list = hadolint.diagnostics ({
    { code = 'DL1000', line = 9, column = 5, level = 'error', message = 'm' },
    'not a finding',
    { line = 1 },
  }, 'FROM\r\n')
  eq (#list, 1)
  eq (list[1].line, 8)
  eq (list[1].character, 4)
  eq (list[1].end_character, 4)
  eq (hadolint.diagnostics ({}, 'FROM a\r\n'), {})
  eq (hadolint.diagnostics (nil, ''), {})
end)

test ('diagnostics stops at a carriage return', function ()
  local list = hadolint.diagnostics ({
    { code = 'X', line = 1, column = 1, level = 'warning', message = 'm' },
  }, 'FROM a\r\n')
  eq (list[1].end_character, 6)
end)
