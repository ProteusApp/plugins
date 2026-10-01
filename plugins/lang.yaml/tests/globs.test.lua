local globs = require ('lib.globs') --[[@as LangYaml.GlobsModule]]

test ('a name without a folder matches in any folder', function ()
  eq (globs.to_glob ('action.yml'), '**/action.yml')
  eq (globs.to_glob ('*.yaml'), '**/*.yaml')
end)

test ('a pattern with folders matches the end of a path', function ()
  eq (globs.to_glob ('.github/workflows/*.yml'), '**/.github/workflows/*.yml')
  eq (globs.to_glob ('**/k8s/*.yaml'), '**/k8s/*.yaml')
  eq (globs.to_glob ('src/**/*.yml'), '**/src/**/*.yml')
end)

test ('a full path loses its drive and its first slash', function ()
  eq (globs.to_glob ('/home/me/app/*.yml'), '**/home/me/app/*.yml')
  eq (globs.to_glob ('C:\\code\\app\\x.yml'), '**/code/app/x.yml')
end)

test (
  'characters the server reads as glob syntax stand for themselves',
  function ()
    eq (globs.to_glob ('a{b}.yml'), '**/a[{]b[}].yml')
    eq (globs.to_glob ('(x).yml'), '**/[(]x[)].yml')
  end
)

test ('fits matches a plain path against a wildcard pattern', function ()
  ok (
    globs.fits (
      '.github/ISSUE_TEMPLATE/*.yml',
      '.github/ISSUE_TEMPLATE/config.yml'
    )
  )
  ok (globs.fits ('*.yml', 'action.yml'))
  ok (not globs.fits ('.github/workflows/*.yml', 'action.yml'))
  ok (not globs.fits ('*.yaml', 'action.yml'))
  ok (globs.fits ('**/*.yml', 'a/b/c.yml'))
end)

test ('schemas groups the globs of each schema', function ()
  eq (
    globs.schemas ({
      { pattern = '.github/workflows/*.yml', value = 'https://w.json' },
      { pattern = '.github/workflows/*.yaml', value = 'https://w.json' },
      { pattern = 'action.yml', value = 'https://a.json' },
      { pattern = 'action.yml', value = 'https://a.json' },
    }),
    {
      ['https://w.json'] = {
        '**/.github/workflows/*.yml',
        '**/.github/workflows/*.yaml',
      },
      ['https://a.json'] = { '**/action.yml' },
    }
  )
end)

test (
  'a file named in full is left out of another schema that fits it',
  function ()
    eq (
      globs.schemas ({
        { pattern = '.github/ISSUE_TEMPLATE/*.yml', value = 'forms' },
        { pattern = '.github/ISSUE_TEMPLATE/config.yml', value = 'config' },
      }),
      {
        forms = {
          '**/.github/ISSUE_TEMPLATE/*.yml',
          '!**/.github/ISSUE_TEMPLATE/config.yml',
        },
        config = { '**/.github/ISSUE_TEMPLATE/config.yml' },
      }
    )
  end
)

test ('the same schema named twice leaves nothing out', function ()
  eq (
    globs.schemas ({
      { pattern = '*.yml', value = 'one' },
      { pattern = 'x.yml', value = 'one' },
    }),
    { one = { '**/*.yml', '**/x.yml' } }
  )
end)

test ('no associations give an empty table', function ()
  eq (globs.schemas ({}), {})
end)

test ('schemas leaves out a schema given as a table or a function', function ()
  local out = globs.schemas ({
    { pattern = 'a.yml', value = { type = 'object' } },
    {
      pattern = 'b.yml',
      value = function ()
        return {}
      end,
    },
    { pattern = 'c.yml', value = 'https://example.com/c.json' },
  })
  eq (out, { ['https://example.com/c.json'] = { '**/c.yml' } })
end)
