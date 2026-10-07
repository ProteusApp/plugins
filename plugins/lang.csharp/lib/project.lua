-- project: finds the Godot project a C# file belongs to, by walking up to project.godot,
-- and the solution and project files in it. Each folder is looked up once, until a
-- project.godot, .sln or .csproj changes on disk.

local disk = require ('disk_paths') --[[@as DiskPaths]]
local godot = require ('lib.godot') --[[@as LangCsharp.GodotModule]]

---A Godot project on disk.
---@class LangCsharp.GodotProject
---@field root string The folder that holds project.godot, with `/`.
---@field info LangCsharp.Project
---@field solution? string The .sln or .csproj the language server loads, as a full path.
---@field csproj? string The .csproj that builds the game, as a full path.

---@class LangCsharp.Projects
---@field of fun(dir: string, cb: fun(project: LangCsharp.GodotProject?)) The Godot project at or above `dir`.
---@field forget fun()

---@class LangCsharp.ProjectModule
local M = {}

---@param name string
---@return boolean
local function matters (name)
  return name == 'project.godot'
    or name:sub (-4) == '.sln'
    or name:sub (-7) == '.csproj'
end

---@param app Proteus.App
---@return LangCsharp.Projects
function M.new (app)
  -- Folder to its project, or false when no project.godot is at or above it.
  local known = {} ---@type table<string, LangCsharp.GodotProject|false>

  ---@param changes any
  local function changed (changes)
    for _, change in
      ipairs (changes or {} --[[@as Proteus.DirChange[] ]])
    do
      if matters (disk.name (change.path)) then
        known = {}
        return
      end
    end
  end
  app.on ('code:disk_changed', changed)
  app.on ('disk:changed', changed)

  ---Reads the project in `root`, whose file names are `names`.
  ---@param root string
  ---@param names string[]
  ---@param cb fun(project: LangCsharp.GodotProject?)
  local function load (root, names, cb)
    app.fs.read_file (root .. '/project.godot', function (text)
      local info = godot.parse_project (text or '')
      local solution = godot.pick_solution (names, info.assembly)
      local projects = {} ---@type string[]
      for _, name in ipairs (names) do
        if name:sub (-7) == '.csproj' then
          projects[#projects + 1] = name
        end
      end
      local csproj = godot.pick_solution (projects, info.assembly)
      cb ({
        root = root,
        info = info,
        solution = solution and disk.join (root, solution) or nil,
        csproj = csproj and disk.join (root, csproj) or nil,
      })
    end)
  end

  ---@param dir string
  ---@param seen string[] Folders passed on the way up, which get the same answer.
  ---@param cb fun(project: LangCsharp.GodotProject?)
  local function up (dir, seen, cb)
    ---@param project LangCsharp.GodotProject?
    local function answer (project)
      for _, d in ipairs (seen) do
        known[d] = project or false
      end
      cb (project)
    end
    local have = known[dir]
    if have ~= nil then
      answer (have or nil)
      return
    end
    seen[#seen + 1] = dir
    app.fs.list_dir (dir, function (names)
      local found = false
      for _, name in ipairs (names or {}) do
        found = found or name == 'project.godot'
      end
      if found then
        load (dir, names or {}, answer)
        return
      end
      local parent = disk.parent (dir)
      if parent == dir then
        answer (nil)
        return
      end
      up (parent, seen, answer)
    end)
  end

  return {
    of = function (dir, cb)
      up (disk.normalize (dir), {}, cb)
    end,
    forget = function ()
      known = {}
    end,
  }
end

return M
