local languages = require ('lib.languages') --[[@as LangSass.LanguagesModule]]

test ('extension reads the last part of the name in lower case', function ()
  eq (languages.extension ('C:/code/app/styles/Main.SCSS'), 'scss')
  eq (languages.extension ('src/theme.module.sass'), 'sass')
  eq (languages.extension ('C:\\code\\app\\reset.css'), 'css')
end)

test ('extension is nil for a name without one', function ()
  eq (languages.extension ('Makefile'), nil)
  eq (languages.extension ('.sassrc'), nil)
  eq (languages.extension ('styles.d/partials'), nil)
end)

test ('scss files go to the server as scss and sass files as sass', function ()
  eq (languages.language_id ('a/main.scss', 'css', false), 'scss')
  eq (languages.language_id ('a/_mixins.sass', 'sass', false), 'sass')
end)

test ('plain css goes to the server only when it is switched on', function ()
  eq (languages.language_id ('a/reset.css', 'css', false), nil)
  eq (languages.language_id ('a/reset.css', 'css', true), 'css')
end)

test ('less files are never served', function ()
  eq (languages.language_id ('a/theme.less', 'css', false), nil)
  eq (languages.language_id ('a/theme.less', 'css', true), nil)
end)

test ('a file in another editor language is left alone', function ()
  eq (languages.language_id ('a/notes.scss', 'markdown', true), nil)
  eq (languages.language_id ('a/main.lua', 'lua', true), nil)
end)

test ('the program is the cmd file on Windows', function ()
  eq (languages.program ('windows'), 'some-sass-language-server.cmd')
  eq (languages.program ('linux'), 'some-sass-language-server')
  eq (languages.program ('macos'), 'some-sass-language-server')
end)

test ('config passes the use-only choice to both syntaxes', function ()
  eq (languages.config ({}, true), {
    scss = { completion = { suggestFromUseOnly = true } },
    sass = { completion = { suggestFromUseOnly = true } },
  })
end)

test ('config leaves out the load paths when there are none', function ()
  local section = languages.config ({}, false)
  eq (section.workspace, nil)
  section = languages.config (nil, false)
  eq (section.workspace, nil)
  section = languages.config ('src', false)
  eq (section.workspace, nil)
end)

test ('config keeps only load paths that are text', function ()
  local section = languages.config ({ 'src/styles', '', 42, 'vendor' }, false)
  eq (section.workspace, { loadPaths = { 'src/styles', 'vendor' } })
end)
