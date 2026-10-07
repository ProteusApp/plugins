-- godot: what the plugin reads from a Godot C# project, and the command lines it builds.
-- Nothing here calls the host, so the tests reach it.

---@class LangCsharp.Project
---@field name? string `config/name` in project.godot.
---@field assembly? string `project/assembly_name` in project.godot's [dotnet] section.
---@field version? string The Godot version the project was saved with, such as `'4.3'`.
---@field csharp boolean True when the project uses C#.

---@class LangCsharp.Goto
---@field path string
---@field line? integer From 1.
---@field col? integer From 1.

---@class LangCsharp.Problem
---@field path string The file as MSBuild printed it.
---@field line integer From 1.
---@field col integer From 1.
---@field severity 'error'|'warning'
---@field code string Such as `'CS0103'`.
---@field message string

---@class LangCsharp.GodotModule
local M = {}

-- The newest csharp-ls for each .NET it runs on. csharp-ls moved to .NET 9 at 0.17.0 and to
-- .NET 10 at 0.21.0, and Godot 4 projects need only .NET 8.
local SERVER_VERSIONS = { [8] = '0.16.0', [9] = '0.20.0', [10] = '0.28.0' }

---The newest .NET runtime `dotnet --list-runtimes` lists, as its major version, such as 8.
---@param text string
---@return integer?
function M.runtime_major (text)
  local best = nil ---@type integer?
  for major in text:gmatch ('Microsoft%.NETCore%.App%s+(%d+)%.') do
    local n = math.floor (tonumber (major) or 0)
    if not best or n > best then
      best = n
    end
  end
  return best
end

---The csharp-ls version to install for a .NET runtime major version, or nil for one older
---than .NET 8.
---@param major integer?
---@return string?
function M.server_version (major)
  if not major or major < 8 then
    return nil
  end
  return SERVER_VERSIONS[math.min (major, 10)]
end

---A value from an INI-style line, such as `"My Game"` or `PackedStringArray("4.3", "C#")`.
---@param raw string
---@return string
local function unquote (raw)
  local s = raw:match ('^%s*"(.*)"%s*$')
  return s or (raw:match ('^%s*(.-)%s*$'))
end

---Reads project.godot.
---@param text string
---@return LangCsharp.Project
function M.parse_project (text)
  local out = { csharp = false } ---@type LangCsharp.Project
  local section = ''
  for line in (text .. '\n'):gmatch ('([^\n]*)\n') do
    line = line:gsub ('\r$', '')
    local head = line:match ('^%[([^%]]+)%]')
    if head then
      section = head
      if head == 'dotnet' then
        out.csharp = true
      end
    else
      local key, value = line:match ('^([%w_/]+)%s*=%s*(.*)$')
      if key and section == 'application' and key == 'config/name' then
        out.name = unquote (value)
      elseif key and section == 'application' and key == 'config/features' then
        local features = value --[[@as string]]
        for feature in features:gmatch ('"([^"]*)"') do
          if feature == 'C#' then
            out.csharp = true
          elseif not out.version and feature:match ('^%d+%.%d+$') then
            out.version = feature
          end
        end
      elseif key and section == 'dotnet' and key == 'project/assembly_name' then
        out.assembly = unquote (value)
      end
    end
  end
  return out
end

---The Godot.NET.Sdk version a .csproj names, such as `'4.3.0'`, or nil for another project.
---@param text string
---@return string?
function M.sdk_version (text)
  return text:match ('Sdk%s*=%s*"Godot%.NET%.Sdk/([^"]+)"')
end

---The `--goto` flag among the app's arguments: `--goto <file>:<line>:<col>` or
---`--goto=<file>:<line>:<col>`, as Godot's custom external editor fills it in. Godot counts
---lines and columns from 0, and gives -1 for a script opened with no place in it, so the
---result counts from 1, or leaves them out.
---@param args string[]
---@return LangCsharp.Goto?
function M.goto_arg (args)
  local value = nil ---@type string?
  for i, arg in ipairs (args) do
    if arg == '--goto' then
      value = args[i + 1]
    elseif arg:sub (1, 7) == '--goto=' then
      value = arg:sub (8)
    end
  end
  if not value or value == '' then
    return nil
  end
  local path, line, col = value:match ('^(.-):(%-?%d+):(%-?%d+)$')
  if not path then
    path, line = value:match ('^(.-):(%-?%d+)$')
  end
  if not path or path == '' then
    return { path = value }
  end
  local l, c = tonumber (line), tonumber (col)
  ---@type LangCsharp.Goto
  local out = { path = path }
  if l and l >= 0 then
    out.line = math.floor (l) + 1
    if c and c >= 0 then
      out.col = math.floor (c) + 1
    end
  end
  return out
end

---What to type into Godot's Editor Settings, under Dotnet > Editor, for Proteus to open
---scripts: the program, and its arguments with Godot's placeholders.
---@param profile string The profile to open, such as `'code'`.
---@return string
function M.exec_args (profile)
  return '--profile '
    .. profile
    .. ' --folder "{project}" --goto "{file}:{line}:{col}"'
end

---The Godot programs to try, in order: the setting when it is set, and otherwise the names
---Godot's .NET builds and package managers use.
---@param setting any
---@return string[]
function M.programs (setting)
  local path = type (setting) == 'string' and setting:match ('^%s*(.-)%s*$')
    or ''
  if path ~= '' then
    return { path }
  end
  return { 'godot-mono', 'godot4-mono', 'godot', 'godot4' }
end

---Splits the `csharp.godot_args` setting into arguments, at spaces outside double quotes.
---@param setting any
---@return string[]
function M.split_args (setting)
  local out = {} ---@type string[]
  local text = type (setting) == 'string' and setting or ''
  local current = {} ---@type string[]
  local quoted = false
  local started = false
  for i = 1, #text do
    local ch = text:sub (i, i)
    if ch == '"' then
      quoted = not quoted
      started = true
    elseif ch:match ('%s') and not quoted then
      if started then
        out[#out + 1] = table.concat (current)
        current, started = {}, false
      end
    else
      current[#current + 1] = ch
      started = true
    end
  end
  if started then
    out[#out + 1] = table.concat (current)
  end
  return out
end

---The problems in `dotnet build` output, each once. MSBuild prints each one as
---`path(line,col): error CS0103: message [project]`, and often twice.
---@param text string
---@return LangCsharp.Problem[]
function M.build_problems (text)
  local out = {} ---@type LangCsharp.Problem[]
  local seen = {} ---@type table<string, true>
  for line in (text .. '\n'):gmatch ('([^\n]*)\n') do
    line = line:gsub ('\r$', '')
    local path, l, c, severity, code, message = line:match (
      '^%s*(.-)%((%d+),(%d+)%)%s*:%s*(%a+)%s+([%w]+)%s*:%s*(.-)%s*$'
    )
    if path and (severity == 'error' or severity == 'warning') then
      message = (message:gsub ('%s*%[[^%]]*%]$', '')) --[[@as string]]
      local key = table.concat ({ path, l, c, code, message }, '|')
      if not seen[key] then
        seen[key] = true
        out[#out + 1] = {
          path = path,
          line = math.floor (tonumber (l) or 1),
          col = math.floor (tonumber (c) or 1),
          severity = severity --[[@as 'error'|'warning']],
          code = code,
          message = message,
        }
      end
    end
  end
  return out
end

---The solution or project file the language server should load, from a folder's file names:
---the one .sln, or else the one .csproj. Nil when there is none, or more than one of a kind
---and none named after the project.
---@param names string[] File names in the folder.
---@param assembly? string The project's assembly name.
---@return string?
function M.pick_solution (names, assembly)
  for _, ext in ipairs ({ '.sln', '.csproj' }) do
    local found = {} ---@type string[]
    for _, name in ipairs (names) do
      if name:sub (-#ext) == ext then
        found[#found + 1] = name
      end
    end
    if #found == 1 then
      return found[1]
    end
    for _, name in ipairs (found) do
      if assembly and name == assembly .. ext then
        return name
      end
    end
  end
  return nil
end

return M
