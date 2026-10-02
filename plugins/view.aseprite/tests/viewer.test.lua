local formats = require ('formats')
local viewer = require ('viewer')

test ('opens Aseprite sprites, whatever the case of their extension', function ()
  for _, path in ipairs ({
    'art/hero.aseprite',
    'C:/game/assets/deck.ase',
    'C:\\game\\assets\\Walk Cycle.ASEPRITE',
    '/home/me/tiles.Ase',
  }) do
    ok (viewer.opens (formats, path), path)
  end
end)

test ('leaves other files to the editor', function ()
  for _, path in ipairs ({
    'art/hero.png',
    'deck.ase.bak',
    'notes.asepritex',
    'aseprite',
    'C:/game/assets.ase/readme.md',
  }) do
    ok (not viewer.opens (formats, path), path)
  end
end)

test ('the sprite reloads when its file changes on disk', function ()
  local key = viewer.key ('C:\\game\\assets\\deck.ase')
  ok (
    viewer.touches (key, { { path = 'C:/game/assets/deck.ase', kind = 'file' } })
  )
  ok (
    not viewer.touches (
      key,
      { { path = 'C:/game/assets/hero.ase', kind = 'file' } }
    )
  )
end)

test ('the bar reads sizes and zoom the way people say them', function ()
  eq (viewer.size_text (3480), '3.4 KB')
  eq (viewer.zoom_text (8), '800%')
end)
