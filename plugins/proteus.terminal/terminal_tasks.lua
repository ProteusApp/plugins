-- terminal_tasks: tasks, the commands a folder or the user names to run in a terminal, such as
-- a build or the tests. They come from the open folder's `.proteus/tasks.json` and from the
-- `terminal.tasks` setting:
--
--   { "tasks": [
--     { "label": "Build", "command": "npm run build", "group": "build", "problems": "tsc" },
--     { "label": "Test", "program": "cargo", "args": ["test"], "problems": "rustc" } ] }
--
-- `.proteus/tasks.json` reaches the plugin only through the folder's `.proteus` layer, which
-- the app mounts only for a folder the user trusts, so an untrusted folder's tasks never run.
-- A problem matcher reads a task's output line by line and finds the problems in it, which
-- go to the Problems panel. Nothing here touches the app, so the tests load it as it is.

---A task a terminal runs.
---@class Terminal.Task
---@field label string
---@field command? string A command line the shell runs.
---@field program? string A program run as it is, with `args`.
---@field args string[]
---@field cwd? string The folder it runs in: a full path, or one inside the open folder.
---@field env table<string, string>
---@field group? 'build'|'test'
---@field default boolean The task Run Build Task or Run Test Task runs.
---@field problems string[] The names of its problem matchers.
---@field detail? string
---@field source 'folder'|'settings'

---A problem a matcher found in a task's output.
---@class Terminal.Problem
---@field file string As the tool printed it.
---@field line integer From 1.
---@field col integer From 1.
---@field severity 'error'|'warning'|'info'
---@field message string
---@field code? string

---Reads a task's output one line at a time.
---@class Terminal.Matcher
---@field feed fun(line: string): Terminal.Problem?

---@class Terminal.Tasks
local M = {}

---@param text string
---@return string
local function trim (text)
  return (text:match ('^%s*(.-)%s*$') or '')
end

---A list of text, from a list of text or numbers. Anything else gives nil.
---@param value any
---@return string[]?
local function text_list (value)
  if value == nil then
    return {}
  end
  if type (value) ~= 'table' then
    return nil
  end
  local out = {} ---@type string[]
  for i = 1, #value do
    local v = value[i]
    if type (v) ~= 'string' and type (v) ~= 'number' then
      return nil
    end
    out[i] = tostring (v)
  end
  return out
end

---Variable names and their values. A name that cannot be set gives nil.
---@param value any
---@return table<string, string>?
local function variables (value)
  if value == nil then
    return {}
  end
  if type (value) ~= 'table' then
    return nil
  end
  local out = {} ---@type table<string, string>
  for k, v in pairs (value) do
    if
      type (k) ~= 'string'
      or k == ''
      or k:find ('=', 1, true)
      or k:find ('\0', 1, true)
      or (
        type (v) ~= 'string'
        and type (v) ~= 'number'
        and type (v) ~= 'boolean'
      )
    then
      return nil
    end
    out[k] = tostring (v)
  end
  return out
end

---Severity words as tools print them.
local SEVERITY = { ---@type table<string, 'error'|'warning'|'info'>
  error = 'error',
  fatal = 'error',
  ['fatal error'] = 'error',
  err = 'error',
  warning = 'warning',
  warn = 'warning',
  note = 'info',
  info = 'info',
  help = 'info',
}

---@param word string?
---@param default 'error'|'warning'|'info'
---@return 'error'|'warning'|'info'
local function severity_of (word, default)
  return word and SEVERITY[trim (word):lower ()] or default
end

---@param file string
---@param line string|integer
---@param col string|integer|nil
---@param severity 'error'|'warning'|'info'
---@param message string
---@param code? string
---@return Terminal.Problem
local function problem (file, line, col, severity, message, code)
  return {
    file = trim (file),
    line = math.max (1, tonumber (line) or 1),
    col = math.max (1, tonumber (col) or 1),
    severity = severity,
    message = trim (message),
    code = code,
  }
end

---`file:line:col: severity: message`, as gcc, clang, Go and many linters print.
---@return Terminal.Matcher
local function gcc ()
  return {
    feed = function (line)
      local file, l, c, rest = line:match ('^(%S[^:]*):(%d+):(%d+):%s*(.*)$')
      if not file then
        -- A Windows path starts with a drive letter, such as C:/code/main.c:3:5: error: ...
        file, l, c, rest = line:match ('^(%a:[/\\][^:]*):(%d+):(%d+):%s*(.*)$')
      end
      if not file or not rest then
        return nil
      end
      local word, message = rest:match ('^(%a[%a ]-)%s*:%s*(.*)$')
      if word and SEVERITY[word:lower ()] then
        return problem (file, l, c, severity_of (word, 'error'), message)
      end
      return problem (file, l, c, 'error', rest)
    end,
  }
end

---`file(line,col): error TS2322: message`, as the TypeScript compiler prints.
---@return Terminal.Matcher
local function tsc ()
  return {
    feed = function (line)
      local file, l, c, word, code, message =
        line:match ('^(%S.-)%((%d+),(%d+)%)%s*:%s*(%a+)%s+(TS%d+)%s*:%s*(.*)$')
      if not file then
        -- tsc --pretty prints `file:line:col - error TS2322: message`.
        file, l, c, word, code, message =
          line:match ('^(%S.-):(%d+):(%d+)%s+%-%s+(%a+)%s+(TS%d+)%s*:%s*(.*)$')
      end
      if not file then
        return nil
      end
      return problem (file, l, c, severity_of (word, 'error'), message, code)
    end,
  }
end

---`error[E0308]: message`, then `  --> file:line:col` a line or two later, as rustc and Cargo
---print.
---@return Terminal.Matcher
local function rustc ()
  local pending = nil ---@type { severity: 'error'|'warning'|'info', message: string, code: string? }?
  return {
    feed = function (line)
      local word, code, message = line:match ('^(%a+)%[(%w+)%]:%s*(.*)$')
      if not word then
        word, message = line:match ('^(%a+):%s*(.*)$')
      end
      if word and SEVERITY[word:lower ()] then
        -- "warning: 3 warnings emitted" and "error: could not compile" name no place.
        pending = {
          severity = severity_of (word, 'error'),
          message = message or '',
          code = code,
        }
        return nil
      end
      local file, l, c = line:match ('^%s*%-%->%s*(.-):(%d+):(%d+)%s*$')
      if file and pending then
        local found =
          problem (file, l, c, pending.severity, pending.message, pending.code)
        pending = nil
        return found
      end
      return nil
    end,
  }
end

---ESLint's stylish output: a file's path on a line of its own, then `  3:5  error  message
---rule` for each problem in it.
---@return Terminal.Matcher
local function eslint ()
  local file = nil ---@type string?
  return {
    feed = function (line)
      local l, c, word, rest = line:match ('^%s+(%d+):(%d+)%s+(%a+)%s+(.*)$')
      if l and file then
        local message, rule = rest:match ('^(.-)%s%s+(%S+)%s*$')
        return problem (
          file,
          l,
          c,
          severity_of (word, 'error'),
          message or rest,
          rule
        )
      end
      if line:match ('^%S') and not line:match ('^✖') then
        file = trim (line)
      elseif trim (line) == '' then
        file = nil
      end
      return nil
    end,
  }
end

---`file:line:col: (W211) message` from luacheck, and selene's and StyLua's own forms are
---gcc's. A `lua` matcher also reads Lua's own `lua: file:line: message`.
---@return Terminal.Matcher
local function lua ()
  local plain = gcc ()
  return {
    feed = function (line)
      local file, l, message =
        line:match ('^[%w%.]*lua[%w%.]*:%s+(%S-):(%d+):%s*(.*)$')
      if file then
        return problem (file, l, 1, 'error', message)
      end
      local found = plain.feed (line)
      if found then
        local code, rest = found.message:match ('^%((%a%d+)%)%s*(.*)$')
        if code then
          found.code = code
          found.message = rest
          found.severity = code:sub (1, 1) == 'E' and 'error' or 'warning'
        end
      end
      return found
    end,
  }
end

---The problem matchers by name.
---@type table<string, fun(): Terminal.Matcher>
M.MATCHERS = {
  gcc = gcc,
  tsc = tsc,
  rustc = rustc,
  eslint = eslint,
  lua = lua,
}
M.MATCHERS.go = gcc
M.MATCHERS.clang = gcc
M.MATCHERS.cargo = rustc

---Every task in a list, as `tasks.json` holds it (`{ "tasks": [...] }`) or as the setting does
---(the list alone). A task without a label, with a label already taken, with neither or both
---of `command` and `program`, or with a field of the wrong kind is left out, and `problems`
---says why. `taken` holds the labels other lists took, in lower case, and grows.
---@param value any
---@param source 'folder'|'settings'
---@param taken? table<string, true>
---@return Terminal.Task[] tasks
---@return string[] problems
function M.read (value, source, taken)
  local where_from = source == 'folder' and '.proteus/tasks.json'
    or 'terminal.tasks'
  local list = value
  if type (value) == 'table' and value.tasks ~= nil then
    list = value.tasks
  end
  local out = {} ---@type Terminal.Task[]
  local problems = {} ---@type string[]
  if list == nil or list == '' then
    return out, problems
  end
  if type (list) ~= 'table' then
    problems[#problems + 1] = where_from .. ' has no list of tasks'
    return out, problems
  end
  local labels = taken or {}
  for i = 1, #list do
    local entry = list[i]
    local where = where_from .. ' task ' .. i
    if type (entry) ~= 'table' then
      problems[#problems + 1] = where .. ' is not a table'
    else
      local label = type (entry.label) == 'string' and trim (entry.label) or ''
      local args = text_list (entry.args)
      local env = variables (entry.env)
      local matchers = entry.problems
      if type (matchers) == 'string' then
        matchers = { matchers }
      end
      local matcher_names = text_list (matchers)
      local unknown = nil ---@type string?
      for _, name in ipairs (matcher_names or {}) do
        if not M.MATCHERS[name] then
          unknown = name
        end
      end
      local command = entry.command
      local program = entry.program
      if label == '' then
        problems[#problems + 1] = where .. ' has no label'
      elseif labels[label:lower ()] then
        problems[#problems + 1] = label .. ': the label is taken'
      elseif command ~= nil and type (command) ~= 'string' then
        problems[#problems + 1] = label .. ': command is not text'
      elseif program ~= nil and type (program) ~= 'string' then
        problems[#problems + 1] = label .. ': program is not text'
      elseif (command or '') == '' and (program or '') == '' then
        problems[#problems + 1] = label .. ': it needs a command or a program'
      elseif (command or '') ~= '' and (program or '') ~= '' then
        problems[#problems + 1] = label
          .. ': it has both a command and a program'
      elseif not args then
        problems[#problems + 1] = label .. ': args is not a list of text'
      elseif not env then
        problems[#problems + 1] = label
          .. ': env is not a table of names and values'
      elseif entry.cwd ~= nil and type (entry.cwd) ~= 'string' then
        problems[#problems + 1] = label .. ': cwd is not text'
      elseif
        entry.group ~= nil
        and entry.group ~= 'build'
        and entry.group ~= 'test'
      then
        problems[#problems + 1] = label .. ': group is build or test'
      elseif not matcher_names then
        problems[#problems + 1] = label .. ': problems is not a list of names'
      elseif unknown then
        problems[#problems + 1] = label
          .. ': there is no problem matcher called '
          .. unknown
      else
        labels[label:lower ()] = true
        local cwd = entry.cwd --[[@as string?]]
        out[#out + 1] = {
          label = label,
          command = (command or '') ~= '' and command or nil,
          program = (program or '') ~= '' and program or nil,
          args = args,
          cwd = cwd ~= '' and cwd or nil,
          env = env,
          group = entry.group,
          default = entry.default == true,
          problems = matcher_names,
          detail = type (entry.detail) == 'string' and entry.detail or nil,
          source = source,
        }
      end
    end
  end
  return out, problems
end

---The task called `label`, ignoring case, or nil.
---@param tasks Terminal.Task[]
---@param label string?
---@return Terminal.Task?
function M.find (tasks, label)
  if not label then
    return nil
  end
  local want = trim (label):lower ()
  for _, t in ipairs (tasks) do
    if t.label:lower () == want then
      return t
    end
  end
  return nil
end

---The task of a group that Run Build Task or Run Test Task runs: the one marked `default`,
---or the only one in the group. Nil when there is none, and the list of the group's tasks to
---choose from when there are several.
---@param tasks Terminal.Task[]
---@param group 'build'|'test'
---@return Terminal.Task?
---@return Terminal.Task[]
function M.of_group (tasks, group)
  local in_group = {} ---@type Terminal.Task[]
  for _, t in ipairs (tasks) do
    if t.group == group then
      if t.default then
        return t, { t }
      end
      in_group[#in_group + 1] = t
    end
  end
  if #in_group == 1 then
    return in_group[1], in_group
  end
  return nil, in_group
end

---The program and arguments a task runs. A command line goes to the shell: `cmd` on Windows
---and `sh` elsewhere.
---@param task Terminal.Task
---@param os string Such as `'windows'`.
---@return string program
---@return string[] args
function M.command_line (task, os)
  if task.program then
    return task.program, task.args
  end
  local line = task.command or ''
  if #task.args > 0 then
    line = line .. ' ' .. table.concat (task.args, ' ')
  end
  if os == 'windows' then
    return 'cmd.exe', { '/d', '/c', line }
  end
  return '/bin/sh', { '-c', line }
end

---@param path string
---@return boolean
local function is_absolute (path)
  return path:match ('^%a:[/\\]') ~= nil or path:match ('^[/\\]') ~= nil
end

---The folder a task runs in: its `cwd`, inside the open folder when it is not a full path,
---or else the open folder, or else the workspace folder.
---@param task Terminal.Task
---@param root string?
---@param workspace string?
---@return string
function M.cwd (task, root, workspace)
  local base = (root and root ~= '') and root or (workspace or '')
  local dir = task.cwd
  if not dir or dir == '' then
    return base
  end
  if is_absolute (dir) or base == '' then
    return dir
  end
  local rel = dir:gsub ('^%./', '')
  return (base:gsub ('[/\\]+$', '')) .. '/' .. rel
end

---Reads output with the matchers named, and gives what the first one finds in each line.
---@param names string[]
---@return Terminal.Matcher?
function M.matcher (names)
  local list = {} ---@type Terminal.Matcher[]
  for _, name in ipairs (names) do
    local make = M.MATCHERS[name]
    if make then
      list[#list + 1] = make ()
    end
  end
  if #list == 0 then
    return nil
  end
  return {
    feed = function (line)
      local found = nil ---@type Terminal.Problem?
      -- Every matcher sees every line, so one that waits for a second line keeps its place.
      for _, m in ipairs (list) do
        local p = m.feed (line)
        found = found or p
      end
      return found
    end,
  }
end

---The full path of a file a tool named, as it printed it, from the folder the task ran in.
---@param file string
---@param cwd string
---@return string
function M.full_path (file, cwd)
  local path = file:gsub ('\\', '/')
  if is_absolute (path) or cwd == '' then
    return path
  end
  path = path:gsub ('^%./', '')
  local base = cwd:gsub ('\\', '/'):gsub ('/+$', '')
  return base .. '/' .. path
end

---A problem as the diagnostics service takes it, with lines and columns from 0.
---@param p Terminal.Problem
---@param source string
---@return Proteus.Diagnostic
function M.diagnostic (p, source)
  return {
    line = p.line - 1,
    character = p.col - 1,
    severity = p.severity,
    message = p.message,
    source = source,
    code = p.code,
  }
end

return M
