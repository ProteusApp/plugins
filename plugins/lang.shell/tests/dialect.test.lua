local dialect = require ('lib.dialect') --[[@as LangShell.DialectModule]]

test ('is_zsh knows zsh scripts by name', function ()
  eq (dialect.is_zsh ('/home/me/.zshrc', nil), true)
  eq (dialect.is_zsh ([[C:\Users\me\.zprofile]], nil), true)
  eq (dialect.is_zsh ('/code/prompt.ZSH', nil), true)
  eq (dialect.is_zsh ('/home/me/.bashrc', nil), false)
  eq (dialect.is_zsh ('/code/build.sh', nil), false)
end)

test ('is_zsh reads the #! line', function ()
  eq (dialect.is_zsh ('/code/run', '#!/bin/zsh\necho hi\n'), true)
  eq (dialect.is_zsh ('/code/run.sh', '#!/usr/bin/env zsh\n'), true)
  eq (dialect.is_zsh ('/code/run.sh', '#!/usr/bin/env -S zsh -f\r\n'), true)
  eq (dialect.is_zsh ('/code/run.sh', '#!/bin/bash\n# zsh is nicer\n'), false)
  eq (dialect.is_zsh ('/code/run.sh', 'echo zsh\n'), false)
end)

test ('is_zsh reads a ShellCheck directive at the top', function ()
  eq (dialect.is_zsh ('/code/lib.sh', '# shellcheck shell=zsh\nfoo\n'), true)
  eq (
    dialect.is_zsh (
      '/code/lib.sh',
      '#!/bin/sh\n\n# shellcheck disable=SC1090 shell=zsh\n'
    ),
    true
  )
  eq (dialect.is_zsh ('/code/lib.sh', 'foo\n# shellcheck shell=zsh\n'), false)
  eq (dialect.directive ('# shellcheck shell=bash\n'), 'bash')
end)

test ('interpreter gives the program a #! line runs', function ()
  eq (dialect.interpreter ('#!/bin/bash'), 'bash')
  eq (dialect.interpreter ('#! /usr/bin/env sh'), 'sh')
  eq (dialect.interpreter ('#!/hint/zsh'), 'zsh')
  eq (dialect.interpreter ('# not a #! line'), nil)
end)
