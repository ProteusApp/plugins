local formats = require ('formats')
local viewer = require ('viewer')

test (
  'opens every kind of font file, whatever the case of its extension',
  function ()
    for _, path in ipairs ({
      'fonts/Inter.ttf',
      'C:/Windows/Fonts/ACaslonPro-Regular.OTF',
      'C:\\Windows\\Fonts\\cambria.ttc',
      'shared/Source.otc',
      '/home/me/site/rubik-400.woff',
      '/home/me/site/rubik-400.woff2',
    }) do
      ok (viewer.opens (formats, path), path)
    end
  end
)

test ('leaves other files to the editor', function ()
  for _, path in ipairs ({
    'fonts/README.md',
    'fonts/Inter.ttf.bak',
    'font.css',
    'woff2',
    'C:/site/fonts.woff/index.html',
  }) do
    ok (not viewer.opens (formats, path), path)
  end
end)

test ('each extension tells the page what kind of font file it is', function ()
  eq (formats.ttf, 'truetype')
  eq (formats.otf, 'opentype')
  eq (formats.ttc, 'collection')
  eq (formats.woff2, 'woff2')
end)

test ('a workspace font reloads only when its own file changes', function ()
  local key = viewer.key ('plugins/mine/my.theme/fonts/Inter.ttf')
  eq (key, 'plugins/mine/my.theme/fonts/Inter.ttf')
  ok (not viewer.is_full ('plugins/mine/my.theme/fonts/Inter.ttf'))
  ok (viewer.key ('plugins/mine/my.theme/fonts/inter.ttf') ~= key)
end)
