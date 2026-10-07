# C# for Godot

C# for Godot 4 .NET projects in the Code Editor: completion of your scripts and of Godot's own API, build errors in the Problems panel, running the game, and opening scripts from Godot at the line you clicked.

## What it does

- **Completion** of your scripts and Godot's API (`Node`, `GD`, `Input` and the rest), with hover help, go to definition (F12) and problems as you type, from [csharp-ls](https://github.com/razzmatazz/csharp-language-server). It runs `dotnet restore` first, which fetches the GodotSharp package that holds Godot's API.
- **Godot: Build C#** runs `dotnet build` and puts its errors in the Problems panel.
- **Godot: Run the Game** builds, then starts the game. **Godot: Stop the Game** stops it.
- **Godot: Open in the Godot Editor** starts the Godot editor on the project.
- **Godot: Use Proteus as Godot's Editor…** shows what to type into Godot, so that a double-click on a C# script in Godot opens it here, at the line.

The commands are in the Run menu and the palette. The output of each shows in the Tools panel, under csharp-ls and Godot (C#).

## What you need

- The .NET SDK, 8 or newer. Godot 4 C# needs it anyway.
- The .NET build of Godot 4, on the PATH as `godot-mono`, `godot4-mono`, `godot` or `godot4`, or set in Settings (`csharp.godot_path`).
- A project with a `.sln` or `.csproj` beside `project.godot`. Godot makes them when you add the first C# script, or with Project > Tools > C# > Create C# solution.

csharp-ls installs itself: when it is missing, a message offers **Install csharp-ls**, which runs `dotnet tool install` into the app's cache folder. The version suits the newest .NET installed: 0.16.0 for .NET 8, 0.20.0 for .NET 9 and 0.28.0 for .NET 10. One on the PATH, or one set in `csharp.server_path`, wins.

## Opening scripts from Godot

In Godot, open Editor > Editor Settings, turn on **Advanced Settings**, and go to Dotnet > Editor. Set **External Editor** to **Custom**, and fill in:

| Setting | Value |
|---------|-------|
| Exec Path | The Proteus program, such as `C:\Program Files\Proteus\proteus.exe` |
| Exec Path Args | `--profile code --folder "{project}" --goto "{file}:{line}:{col}"` |

Each script Godot opens starts a Proteus window on the project at that line.

## Settings

| Setting | What it does |
|---------|--------------|
| `csharp.server_enabled` | Runs csharp-ls. On by default. |
| `csharp.server_path` | A csharp-ls to use instead of the one on the PATH or the installed copy. |
| `csharp.dotnet_path` | A dotnet to use instead of the one on the PATH. |
| `csharp.godot_path` | The Godot program. |
| `csharp.godot_args` | Extra arguments for the game and the Godot editor, such as `--rendering-driver opengl3` on a computer without Vulkan. |
