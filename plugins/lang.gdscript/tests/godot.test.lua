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

test (
  'may_start needs a trusted folder that holds the project, in the Code Editor',
  function ()
    eq (godot.may_start ('/home/me/game', nil, false), true, 'no folder open')
    eq (godot.may_start ('/home/me/game', '/home/me/game', false), false)
    eq (godot.may_start ('/home/me/game', '/home/me/game', true), true)
    eq (godot.may_start ('/home/me/game/sub', '/home/me/game/', true), true)
    eq (
      godot.may_start ('/home/me/other', '/home/me/game', true),
      false,
      'a project outside the folder'
    )
    eq (godot.may_start ('/home/me/gamex', '/home/me/game', true), false)
    eq (
      godot.may_start ([[C:\Code\Game]], 'c:/code/game', true, 'windows'),
      true
    )
    eq (godot.may_start ('/Home/me/game', '/home/me/game', true, 'linux'), false)
  end
)

test ('is_scene knows the scene files Godot opens', function ()
  eq (godot.is_scene ('/p/Scenes/Main.tscn'), true)
  eq (godot.is_scene ('/p/Scenes/Main.SCN'), true)
  eq (godot.is_scene ('/p/Scripts/Main.cs'), false)
  eq (godot.is_scene ('/p/Scripts/Main.cs.uid'), false)
end)

test ('res_path names a file inside the project', function ()
  eq (
    godot.res_path ('/p/game', '/p/game/Scenes/Main.tscn'),
    'res://Scenes/Main.tscn'
  )
  eq (godot.res_path ('/p/game/', '/p/game/Main.tscn'), 'res://Main.tscn')
  eq (godot.res_path ('/p/game', '/p/gamer/Main.tscn'), nil)
end)

test ('editor_running finds a Godot editor on the project alone', function ()
  local ps = table.concat ({
    '84094 /usr/lib/godot-mono/godot.mono --path /p/game --editor',
    '84100 /usr/bin/godot-mono --path /p/other -e',
  }, '\n')
  eq (godot.editor_running (ps, '/p/game'), true)
  eq (godot.editor_running (ps, '/p/other/'), true)
  eq (godot.editor_running (ps, '/p/third'), false)
  -- The game runs with --path too, but without --editor.
  eq (
    godot.editor_running ('90 /usr/bin/godot-mono --path /p/game', '/p/game'),
    false
  )
  eq (godot.editor_running ('91 godot --editor --path=/p/game', '/p/game'), true)
  -- A language server with no window is not an editor to open scenes in.
  eq (
    godot.editor_running (
      '92 godot --path /p/game --editor --headless --lsp-port 6005',
      '/p/game'
    ),
    false
  )
end)
