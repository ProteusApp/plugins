local context = require ('lib.package_context') --[[@as LangJavascript.PackageContextModule]]

local PACKAGE = [[
{
  "name": "app",
  "scripts": { "build": "vite build" },
  "dependencies": {
    "react": "^18.3",
    "rea
  },
  "devDependencies": {
    "@types/node": "
  }
}]]

local lines = context.lines (PACKAGE)

test ('at finds a name typed in dependencies', function ()
  eq (
    context.at (lines, 5, #lines[6]),
    { where = 'name', word = 'rea', from = 5 }
  )
end)

test ('at finds a version, and keeps the sign of a range', function ()
  eq (context.at (lines, 4, 19), {
    where = 'version',
    name = 'react',
    word = '18.3',
    from = 15,
  })
  eq (context.at (lines, 8, #lines[9]), {
    where = 'version',
    name = '@types/node',
    word = '',
    from = 20,
  })
end)

test ('at ignores other parts of the file', function ()
  eq (context.at (lines, 1, #lines[2]), nil)
  eq (context.at (lines, 2, 22), nil)
  eq (context.at (lines, 40, 0), nil)
end)

test ('at ignores a dependencies key that is not at the top', function ()
  local nested = context.lines ('{\n  "a": {\n    "dependencies": {\n      "re')
  eq (context.at (nested, 3, 9), nil)
end)

test ('open_keys skips braces inside strings', function ()
  eq (context.open_keys ('{ "a": "{", "b": { "c": "\\"}"'), { '', 'b' })
end)
