local godot = require ('lib.godot')

local PROJECT = table.concat ({
  '; Engine configuration file.',
  'config_version=5',
  '',
  '[application]',
  '',
  'config/name="Space Rocks"',
  'run/main_scene="res://main.tscn"',
  'config/features=PackedStringArray("4.3", "C#", "Forward Plus")',
  '',
  '[dotnet]',
  '',
  'project/assembly_name="SpaceRocks"',
}, '\r\n')

test ('parse_project reads the name, assembly and version', function ()
  eq (godot.parse_project (PROJECT), {
    name = 'Space Rocks',
    assembly = 'SpaceRocks',
    version = '4.3',
    csharp = true,
  })
end)

test ('a GDScript project is not C#', function ()
  local info = godot.parse_project (
    '[application]\nconfig/name="Plain"\nconfig/features=PackedStringArray("4.2", "Mobile")\n'
  )
  eq (info.csharp, false)
  eq (info.version, '4.2')
  eq (info.assembly, nil)
end)

test ('sdk_version reads the Godot.NET.Sdk version', function ()
  eq (godot.sdk_version ('<Project Sdk="Godot.NET.Sdk/4.3.0">'), '4.3.0')
  eq (
    godot.sdk_version ('<Project Sdk = "Godot.NET.Sdk/4.4.0-dev.2">'),
    '4.4.0-dev.2'
  )
  eq (godot.sdk_version ('<Project Sdk="Microsoft.NET.Sdk">'), nil)
end)

test ('goto_arg counts from 1, as Godot counts from 0', function ()
  eq (godot.goto_arg ({ 'proteus', '--goto', '/g/Player.cs:11:4' }), {
    path = '/g/Player.cs',
    line = 12,
    col = 5,
  })
  eq (godot.goto_arg ({ '--goto=C:/g/Player.cs:0:0' }), {
    path = 'C:/g/Player.cs',
    line = 1,
    col = 1,
  })
  eq (godot.goto_arg ({ '--goto', 'C:/g/Player.cs:7' }), {
    path = 'C:/g/Player.cs',
    line = 8,
  })
end)

test ('goto_arg leaves out a place Godot does not give', function ()
  eq (
    godot.goto_arg ({ '--goto', '/g/Player.cs:-1:-1' }),
    { path = '/g/Player.cs' }
  )
  eq (godot.goto_arg ({ '--goto', '/g/Player.cs' }), { path = '/g/Player.cs' })
  eq (godot.goto_arg ({ '--folder', '/g' }), nil)
  eq (godot.goto_arg ({ '--goto' }), nil)
end)

test ('exec_args names the profile, the folder and the place', function ()
  eq (
    godot.exec_args ('code'),
    '--profile code --folder "{project}" --goto "{file}:{line}:{col}"'
  )
end)

test ('programs prefers the setting, then the .NET builds', function ()
  eq (godot.programs (' /opt/godot/Godot_v4.3-stable_mono '), {
    '/opt/godot/Godot_v4.3-stable_mono',
  })
  eq (godot.programs (''), { 'godot-mono', 'godot4-mono', 'godot', 'godot4' })
  eq (godot.programs (nil), { 'godot-mono', 'godot4-mono', 'godot', 'godot4' })
end)

test ('runtime_major and server_version pick a csharp-ls that runs', function ()
  local runtimes = table.concat ({
    'Microsoft.AspNetCore.App 8.0.31 [/usr/lib/dotnet/shared/Microsoft.AspNetCore.App]',
    'Microsoft.NETCore.App 8.0.31 [/usr/lib/dotnet/shared/Microsoft.NETCore.App]',
    'Microsoft.NETCore.App 9.0.10 [/usr/lib/dotnet/shared/Microsoft.NETCore.App]',
  }, '\n')
  eq (godot.runtime_major (runtimes), 9)
  eq (godot.runtime_major ('nothing'), nil)
  eq (godot.server_version (8), '0.16.0')
  eq (godot.server_version (9), '0.20.0')
  eq (godot.server_version (10), '0.28.0')
  eq (godot.server_version (11), '0.28.0')
  eq (godot.server_version (6), nil)
  eq (godot.server_version (nil), nil)
end)

test ('build_problems reads MSBuild errors once each', function ()
  local out = table.concat ({
    "/g/Player.cs(12,9): error CS0103: The name 'speed' does not exist in the current context [/g/SpaceRocks.csproj]",
    "/g/Player.cs(12,9): error CS0103: The name 'speed' does not exist in the current context [/g/SpaceRocks.csproj]",
    "C:\\g\\Enemy.cs(3,1): warning CS0168: The variable 'x' is declared but never used [C:\\g\\SpaceRocks.csproj]",
    'Build FAILED.',
  }, '\r\n')
  eq (godot.build_problems (out), {
    {
      path = '/g/Player.cs',
      line = 12,
      col = 9,
      severity = 'error',
      code = 'CS0103',
      message = "The name 'speed' does not exist in the current context",
    },
    {
      path = 'C:\\g\\Enemy.cs',
      line = 3,
      col = 1,
      severity = 'warning',
      code = 'CS0168',
      message = "The variable 'x' is declared but never used",
    },
  })
end)

test (
  'pick_solution prefers the one .sln, then the one named for the project',
  function ()
    eq (
      godot.pick_solution ({ 'a.csproj', 'Game.sln', 'project.godot' }),
      'Game.sln'
    )
    eq (godot.pick_solution ({ 'Game.csproj', 'project.godot' }), 'Game.csproj')
    eq (godot.pick_solution ({ 'Tools.sln', 'Game.sln' }, 'Game'), 'Game.sln')
    eq (godot.pick_solution ({ 'Tools.sln', 'Game.sln' }, nil), nil)
    eq (godot.pick_solution ({ 'project.godot' }), nil)
  end
)

test ('split_args splits at spaces outside double quotes', function ()
  eq (
    godot.split_args ('--rendering-driver opengl3  --verbose'),
    { '--rendering-driver', 'opengl3', '--verbose' }
  )
  eq (
    godot.split_args ('--log-file "/tmp/my game.log"'),
    { '--log-file', '/tmp/my game.log' }
  )
  eq (godot.split_args (''), {})
  eq (godot.split_args (nil), {})
end)
