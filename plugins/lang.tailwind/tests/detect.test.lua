local detect = require ('lib.detect') --[[@as LangTailwind.DetectModule]]

test ('is_config knows Tailwind 3 config files', function ()
  eq (detect.is_config ('tailwind.config.js'), true)
  eq (detect.is_config ('C:/code/app/tailwind.config.ts'), true)
  eq (detect.is_config ([[apps\web\tailwind.config.cjs]]), true)
  eq (detect.is_config ('tailwind.config.mjs'), true)
  eq (detect.is_config ('tailwind.config.json'), false)
  eq (detect.is_config ('my-tailwind.config.js'), false)
end)

test ('line_says finds Tailwind in stylesheets', function ()
  eq (detect.line_says ('src/app.css', '@import "tailwindcss";'), true)
  eq (
    detect.line_says ('src/app.css', "@import 'tailwindcss' source(none);"),
    true
  )
  eq (detect.line_says ('src/app.css', '@import url("tailwindcss");'), true)
  eq (detect.line_says ('src/app.css', '@reference "tailwindcss";'), true)
  eq (detect.line_says ('styles/main.scss', '@tailwind base;'), true)
  eq (detect.line_says ('src/app.css', '/* tailwind would be nice */'), false)
  eq (detect.line_says ('src/app.css', '@import "./tailwind-reset.css";'), false)
end)

test ('line_says finds Tailwind among package.json dependencies', function ()
  eq (detect.line_says ('package.json', '    "tailwindcss": "^4.1.0",'), true)
  eq (
    detect.line_says ('apps/web/package.json', '"@tailwindcss/vite": "4.1.0"'),
    true
  )
  eq (
    detect.line_says ('package.json', '"prettier-plugin-tailwindcss": "^0.6"'),
    false
  )
  eq (
    detect.line_says ('package.json', '"description": "uses tailwindcss"'),
    false
  )
end)

test ('any looks through a search', function ()
  eq (
    detect.any ({
      {
        path = 'package.json',
        before = '"name": "',
        hit = 'tailwind',
        after = '-demo"',
      },
      {
        path = 'src/app.css',
        before = '@import "',
        hit = 'tailwind',
        after = 'css";',
      },
    }),
    true
  )
  eq (detect.any ({ { path = 'README.css', hit = 'tailwind' } }), false)
  eq (detect.any ({}), false)
end)

test ('matters knows the files that can change the answer', function ()
  eq (detect.matters ('tailwind.config.ts'), true)
  eq (detect.matters ('C:/code/app/package.json'), true)
  eq (detect.matters ('src/app.css'), true)
  eq (detect.matters ('src/theme.scss'), true)
  eq (detect.matters ('src/App.tsx'), false)
  eq (detect.matters ('index.html'), false)
end)
