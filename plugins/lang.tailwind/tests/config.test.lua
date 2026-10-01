local config = require ('lib.config') --[[@as LangTailwind.ConfigModule]]

test ('section sends what the settings say', function ()
  eq (
    config.section (
      { 'class', 'className', '' },
      { 'tw`([^`]*)', { 'cva\\(([^)]*)\\)', '"([^"]*)"' } },
      { cssConflict = 'error', recommendedVariantOrder = 'ignore' }
    ),
    {
      emmetCompletions = false,
      classAttributes = { 'class', 'className' },
      experimental = {
        classRegex = { 'tw`([^`]*)', { 'cva\\(([^)]*)\\)', '"([^"]*)"' } },
      },
      lint = { cssConflict = 'error', recommendedVariantOrder = 'ignore' },
    }
  )
end)

test ('section leaves out what is empty or wrong', function ()
  eq (config.section ({}, {}, {}), { emmetCompletions = false })
  eq (config.section (nil, 'x', { cssConflict = 'loud' }), {
    emmetCompletions = false,
  })
  eq (config.section ({ 1, 'class' }, { { 'only one' } }, nil), {
    emmetCompletions = false,
    classAttributes = { 'class' },
  })
end)
