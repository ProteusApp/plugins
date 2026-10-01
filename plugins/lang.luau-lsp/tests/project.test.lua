local project = require ('lib.project') --[[@as LangLuau.ProjectModule]]

test ('a Rojo project file marks a Roblox project', function ()
  eq (project.is_roblox ({ 'src/', 'default.project.json' }), true)
  eq (project.is_roblox ({ 'place.project.json', 'README.md' }), true)
end)

test ('a .luaurc marks a Roblox project', function ()
  eq (project.is_roblox ({ '.luaurc', 'src/' }), true)
end)

test ('a folder without either is plain Luau', function ()
  eq (project.is_roblox ({ 'src/', 'main.luau', 'project.json' }), false)
  eq (project.is_roblox ({}), false)
end)

test ('a folder named like a project file does not count', function ()
  eq (project.is_roblox ({ 'old.project.json/' }), false)
  eq (project.is_roblox ({ '.luaurc/' }), false)
end)

test ('the setting wins when it says on or off', function ()
  eq (project.roblox ('on', {}), true)
  eq (project.roblox ('off', { 'default.project.json' }), false)
end)

test ('auto lets the folder decide', function ()
  eq (project.roblox ('auto', { 'default.project.json' }), true)
  eq (project.roblox ('auto', { 'main.luau' }), false)
  eq (project.roblox (nil, { '.luaurc' }), true)
end)

test ('Rojo runs only with default.project.json', function ()
  eq (project.has_rojo_project ({ 'default.project.json' }), true)
  eq (project.has_rojo_project ({ 'place.project.json', '.luaurc' }), false)
end)
