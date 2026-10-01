local config = require ('lib.config') --[[@as LangShell.ConfigModule]]

test ('server gives the ShellCheck path, or an empty one', function ()
  eq (config.server ('C:/tools/shellcheck.exe'), {
    shellcheckPath = 'C:/tools/shellcheck.exe',
    explainshellEndpoint = '',
    shfmt = { path = '' },
  })
  eq (config.server (nil).shellcheckPath, '')
end)

test ('shfmt_args leaves the indent to .editorconfig below 0', function ()
  eq (
    config.shfmt_args ('/code/run.sh', -1),
    { '--filename', '/code/run.sh', '-' }
  )
  eq (
    config.shfmt_args ('/code/run.sh', nil),
    { '--filename', '/code/run.sh', '-' }
  )
end)

test ('shfmt_args passes tabs or spaces', function ()
  eq (
    config.shfmt_args ('/code/run.sh', 0),
    { '--filename', '/code/run.sh', '-i', '0', '-' }
  )
  eq (
    config.shfmt_args ('/code/run.sh', 2.0),
    { '--filename', '/code/run.sh', '-i', '2', '-' }
  )
end)

test ('version reads what the programs print', function ()
  eq (
    config.version (
      'ShellCheck - shell script analysis tool\nversion: 0.11.0\nlicense: GNU\n'
    ),
    '0.11.0'
  )
  eq (config.version ('v3.14.1\n'), 'v3.14.1')
  eq (config.version ('v3.14.1'), 'v3.14.1')
  eq (config.version (''), nil)
end)
