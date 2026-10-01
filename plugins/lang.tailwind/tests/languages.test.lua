local languages = require ('lib.languages') --[[@as LangTailwind.LanguagesModule]]

test ('language_id names each kind of file by its extension', function ()
  eq (languages.language_id ('C:/code/app/index.html'), 'html')
  eq (languages.language_id ('page.HTM'), 'html')
  eq (languages.language_id ('src/App.vue'), 'vue')
  eq (languages.language_id ('src/routes/+page.svelte'), 'svelte')
  eq (languages.language_id ('app.css'), 'css')
  eq (languages.language_id ('theme.scss'), 'scss')
  eq (languages.language_id ('main.js'), 'javascript')
  eq (languages.language_id ('tailwind.config.mjs'), 'javascript')
  eq (languages.language_id ('main.ts'), 'typescript')
  eq (languages.language_id ([[C:\code\app\App.jsx]]), 'javascriptreact')
  eq (languages.language_id ('App.tsx'), 'typescriptreact')
  eq (languages.language_id ('README.md'), 'markdown')
end)

test ('language_id leaves other files alone', function ()
  eq (languages.language_id ('main.rs'), nil)
  eq (languages.language_id ('package.json'), nil)
  eq (languages.language_id ('Makefile'), nil)
  eq (languages.language_id ('.html'), nil)
end)

test ('every pattern names a file the server hears about', function ()
  for _, pattern in ipairs (languages.PATTERNS) do
    ok (
      languages.language_id ('file' .. pattern:sub (2)),
      pattern .. ' has a language'
    )
  end
end)
