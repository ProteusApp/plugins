local config = require ('lib.config') --[[@as LangDocker.ConfigModule]]

test ('the checks section names every check as a warning', function ()
  local checks = config.section ('docker.languageserver.diagnostics')
  ok (checks ~= nil)
  local count = 0
  for name, level in pairs (checks or {}) do
    count = count + 1
    eq (level, 'warning', name)
  end
  eq (count, 9)
  eq ((checks or {}).instructionCasing, 'warning')
end)

test ('the formatter section indents continued lines', function ()
  eq (
    config.section ('docker.languageserver.formatter'),
    { ignoreMultilineInstructions = false }
  )
end)

test ('other sections get nothing', function ()
  eq (config.section ('docker'), nil)
  eq (config.section (''), nil)
end)
