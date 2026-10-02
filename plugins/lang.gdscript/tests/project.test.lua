local project = require ('lib.project')

test (
  'folders_up lists the folders above a file on Windows, nearest first',
  function ()
    eq (project.folders_up ('C:/games/hop/player/player.gd'), {
      'C:/games/hop/player',
      'C:/games/hop',
      'C:/games',
      'C:/',
    })
  end
)

test ('folders_up reads backslashes as slashes', function ()
  eq (project.folders_up ('D:\\hop\\main.gd'), { 'D:/hop', 'D:/' })
end)

test ('folders_up goes up to / on Linux and macOS', function ()
  eq (project.folders_up ('/home/ana/hop/main.gd'), {
    '/home/ana/hop',
    '/home/ana',
    '/home',
    '/',
  })
end)

test ('folders_up stops after 32 folders', function ()
  local path = string.rep ('/a', 40) .. '/x.gd'
  eq (#project.folders_up (path), 32)
end)

test ('res_to_disk puts a res:// path under the project folder', function ()
  eq (
    project.res_to_disk ('res://player/player.tscn', 'C:/games/hop'),
    'C:/games/hop/player/player.tscn'
  )
  eq (
    project.res_to_disk ('res://main.gd', '/home/ana/hop/'),
    '/home/ana/hop/main.gd'
  )
end)

test ('res_to_disk drops the part after :: and an extra slash', function ()
  eq (project.res_to_disk ('res://level.tscn::3', 'C:/hop'), 'C:/hop/level.tscn')
  eq (project.res_to_disk ('res:///icon.svg', 'C:/hop'), 'C:/hop/icon.svg')
end)

test ('res_to_disk gives the project folder for res:// alone', function ()
  eq (project.res_to_disk ('res://', 'C:\\hop'), 'C:/hop')
end)

test ('res_to_disk names nothing for other kinds of path', function ()
  eq (project.res_to_disk ('user://save.json', 'C:/hop'), nil)
  eq (project.res_to_disk ('uid://b2x8k', 'C:/hop'), nil)
  eq (project.res_to_disk ('player.gd', 'C:/hop'), nil)
end)

test ('line_at gives a line counted from 0, without its line break', function ()
  local text = 'extends Node\r\nvar a = 1\n\nfunc _ready():'
  eq (project.line_at (text, 0), 'extends Node')
  eq (project.line_at (text, 1), 'var a = 1')
  eq (project.line_at (text, 2), '')
  eq (project.line_at (text, 3), 'func _ready():')
  eq (project.line_at (text, 4), nil)
end)

test ('res_path_at finds the path in quotes under the column', function ()
  local line = 'const Enemy = preload ("res://enemy/enemy.tscn")'
  local quote = line:find ('"', 1, true) - 1
  eq (project.res_path_at (line, quote), 'res://enemy/enemy.tscn')
  eq (project.res_path_at (line, quote + 10), 'res://enemy/enemy.tscn')
  eq (project.res_path_at (line, #line - 2), 'res://enemy/enemy.tscn')
  eq (project.res_path_at (line, 2), nil)
end)

test (
  'res_path_at takes single quotes and the right one of two paths',
  function ()
    local line = "var a = load('res://a.png'); var b = load('res://b.png')"
    local b = line:find ('res://b', 1, true)
    eq (project.res_path_at (line, b), 'res://b.png')
    eq (project.res_path_at (line, 16), 'res://a.png')
  end
)

test ('res_path_at reads a path in a scene file', function ()
  local line =
    '[ext_resource type="Script" uid="uid://c1" path="res://player.gd" id="1"]'
  local at = line:find ('player', 1, true)
  eq (project.res_path_at (line, at), 'res://player.gd')
  eq (project.res_path_at (line, line:find ('uid://', 1, true)), nil)
end)
