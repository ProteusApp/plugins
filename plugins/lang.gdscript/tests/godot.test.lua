local godot = require ('lib.godot')

test ('port takes a whole number from 1 to 65535', function ()
  eq (godot.port (6008), 6008)
  eq (godot.port ('6010'), 6010)
  eq (godot.port (65535), 65535)
end)

test ('port falls back to 6005 for anything else', function ()
  eq (godot.port (nil), 6005)
  eq (godot.port (0), 6005)
  eq (godot.port (70000), 6005)
  eq (godot.port (6005.5), 6005)
  eq (godot.port ('six'), 6005)
end)

test ('programs prefers the path from the settings', function ()
  eq (
    godot.programs ('  C:/Godot/Godot_v4.3-stable_win64.exe '),
    { 'C:/Godot/Godot_v4.3-stable_win64.exe' }
  )
end)

test ('programs looks for godot, then godot4, when no path is set', function ()
  eq (godot.programs (''), { 'godot', 'godot4' })
  eq (godot.programs ('   '), { 'godot', 'godot4' })
  eq (godot.programs (nil), { 'godot', 'godot4' })
end)

test ('version reads what godot --version prints', function ()
  local major, minor = godot.version ('4.3.stable.official.77dcf97d8\n')
  eq ({ major, minor }, { 4, 3 })
  major, minor = godot.version ('3.6.stable.official.de2f0f147')
  eq ({ major, minor }, { 3, 6 })
  major, minor = godot.version ('')
  eq ({ major, minor }, {})
end)

test ('serves_headless needs Godot 4.2 or newer', function ()
  ok (godot.serves_headless (4, 2))
  ok (godot.serves_headless (4, 5))
  ok (godot.serves_headless (5, 0))
  ok (not godot.serves_headless (4, 1))
  ok (not godot.serves_headless (3, 6))
end)

test (
  'args opens the project in the editor, with no window, on the port',
  function ()
    eq (godot.args ('C:/games/hop', 6005), {
      '--path',
      'C:/games/hop',
      '--editor',
      '--headless',
      '--lsp-port',
      '6005',
    })
  end
)
