local formats = require ('formats')
local viewer = require ('viewer')

test (
  'opens every kind of picture, whatever the case of its extension',
  function ()
    for _, path in ipairs ({
      'art/logo.png',
      'C:/code/app/photo.JPG',
      'C:\\code\\app\\scan.jpeg',
      '/home/me/old.jfif',
      'spin.gif',
      'shot.webp',
      'shot.avif',
      'paint.bmp',
      'favicon.ico',
      'icons/arrow.svg',
    }) do
      ok (viewer.opens (formats, path), path)
    end
  end
)

test ('leaves other files to the editor', function ()
  for _, path in ipairs ({
    'notes.md',
    'png',
    'archive.png.zip',
    'Makefile',
    'C:/code/app/.png/readme',
  }) do
    ok (not viewer.opens (formats, path), path)
  end
  ok (not viewer.opens (formats, nil))
end)

test ('each extension gives the page the type of the picture', function ()
  eq (formats.jfif, 'image/jpeg')
  eq (formats.svg, 'image/svg+xml')
  eq (formats.ico, 'image/x-icon')
end)

test ('name and extension come from the end of the path', function ()
  eq (viewer.name ('C:\\art\\Big Logo.PNG'), 'Big Logo.PNG')
  eq (viewer.name ('plugins/mine/a.svg'), 'a.svg')
  eq (viewer.extension ('C:\\art\\Big Logo.PNG'), 'png')
  eq (viewer.extension ('README'), nil)
end)

test ('tells full paths on disk from workspace paths', function ()
  ok (viewer.is_full ('C:/code/a.png'))
  ok (viewer.is_full ('c:\\code\\a.png'))
  ok (viewer.is_full ('/home/me/a.png'))
  ok (viewer.is_full ('\\\\server\\share\\a.png'))
  ok (not viewer.is_full ('plugins/mine/a.png'))
  ok (not viewer.is_full ('a.png'))
end)

test ('the same Windows file matches whatever its slashes and case', function ()
  eq (viewer.key ('C:\\Code\\Logo.png'), viewer.key ('c:/code/logo.PNG'))
  eq (viewer.key ('plugins/Mine/a.png'), 'plugins/Mine/a.png')
  ok (viewer.key ('/home/Me/a.png') ~= viewer.key ('/home/me/a.png'))
end)

test ('a change on disk reloads only the file it names', function ()
  local key = viewer.key ('C:/code/logo.png')
  ok (viewer.touches (key, { { path = 'C:/code/logo.png', kind = 'file' } }))
  ok (viewer.touches (key, { { path = 'c:/Code/LOGO.png', kind = 'file' } }))
  ok (
    not viewer.touches (key, { { path = 'C:/code/other.png', kind = 'file' } })
  )
  ok (
    not viewer.touches (key, { { path = 'C:/code/logo.png', kind = 'remove' } })
  )
  ok (not viewer.touches (key, nil))
end)

test ('sizes read the way people say them', function ()
  eq (viewer.size_text (0), '0 B')
  eq (viewer.size_text (912), '912 B')
  eq (viewer.size_text (1024), '1 KB')
  eq (viewer.size_text (35021), '34.2 KB')
  eq (viewer.size_text (500 * 1024), '500 KB')
  eq (viewer.size_text (1.5 * 1024 * 1024), '1.5 MB')
  eq (viewer.size_text (3 * 1024 * 1024 * 1024), '3 GB')
end)

test ('zoom reads as a percentage', function ()
  eq (viewer.zoom_text (1), '100%')
  eq (viewer.zoom_text (2.5), '250%')
  eq (viewer.zoom_text (0.125), '12.5%')
  eq (viewer.zoom_text (0.05), '5%')
  eq (viewer.zoom_text (1 / 3), '33.3%')
  eq (viewer.zoom_text (1600), '160000%')
end)
