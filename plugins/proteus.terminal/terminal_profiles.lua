-- terminal_profiles: the programs a new terminal can run. The default profile comes from the
-- `terminal.shell` setting, and the `terminal.profiles` setting adds named ones:
--
--   { { name = 'Git Bash', program = 'C:/Program Files/Git/bin/bash.exe', args = { '-l' } },
--     { name = 'Node', program = 'node', env = { NODE_ENV = 'development' }, cwd = 'C:/code' } }
--
-- Nothing here touches the app, so the tests load it as it is.

local shell_words = require ('shell_words') --[[@as Terminal.ShellWords]]

---A program a terminal runs, with what it starts with.
---@class Terminal.Profile
---@field name string `''` for the default profile.
---@field label string What menus show.
---@field program string The system shell when empty.
---@field args string[]
---@field env table<string, string>
---@field cwd? string The folder it starts in, a full path.

---@class Terminal.Profiles
local M = {}

---The program and arguments of the `terminal.shell` setting, split by `shell_words`, so
---`pwsh -NoLogo` runs pwsh with one argument and quotes keep a path with spaces together.
---@param shell string
---@return string program
---@return string[] args
function M.from_shell (shell)
  return shell_words.split (shell)
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

---Every profile: the default one from `shell`, then each usable entry of `list`. An entry
---without a name, with a name already taken, or with a field of the wrong kind is left out,
---and `problems` says why.
---@param list any The `terminal.profiles` setting.
---@param shell string The `terminal.shell` setting.
---@return Terminal.Profile[] profiles
---@return string[] problems
function M.read (list, shell)
  local program, args = M.from_shell (shell or '')
  ---@type Terminal.Profile[]
  local out = {
    {
      name = '',
      label = program ~= '' and program or 'Default shell',
      program = program,
      args = args,
      env = {},
    },
  }
  local problems = {} ---@type string[]
  if type (list) ~= 'table' then
    if list ~= nil and list ~= '' then
      problems[#problems + 1] = 'terminal.profiles is not a list'
    end
    return out, problems
  end
  local taken = {} ---@type table<string, true>
  for i = 1, #list do
    local entry = list[i]
    local where = 'terminal.profiles entry ' .. i
    if type (entry) ~= 'table' then
      problems[#problems + 1] = where .. ' is not a table'
    else
      local name = type (entry.name) == 'string'
          and entry.name:match ('^%s*(.-)%s*$')
        or ''
      local entry_args = text_list (entry.args)
      local env = variables (entry.env)
      if name == '' then
        problems[#problems + 1] = where .. ' has no name'
      elseif taken[name:lower ()] then
        problems[#problems + 1] = where .. ': the name ' .. name .. ' is taken'
      elseif entry.program ~= nil and type (entry.program) ~= 'string' then
        problems[#problems + 1] = name .. ': program is not text'
      elseif not entry_args then
        problems[#problems + 1] = name .. ': args is not a list of text'
      elseif not env then
        problems[#problems + 1] = name
          .. ': env is not a table of names and values'
      elseif entry.cwd ~= nil and type (entry.cwd) ~= 'string' then
        problems[#problems + 1] = name .. ': cwd is not text'
      else
        taken[name:lower ()] = true
        local cwd = entry.cwd --[[@as string?]]
        out[#out + 1] = {
          name = name,
          label = name,
          program = entry.program or '',
          args = entry_args,
          env = env,
          cwd = cwd ~= '' and cwd or nil,
        }
      end
    end
  end
  return out, problems
end

---The profile called `name`, ignoring case, or nil. `''` is the default profile.
---@param profiles Terminal.Profile[]
---@param name string?
---@return Terminal.Profile?
function M.find (profiles, name)
  if name == nil then
    return nil
  end
  local want = name:match ('^%s*(.-)%s*$'):lower ()
  for _, p in ipairs (profiles) do
    if p.name:lower () == want then
      return p
    end
  end
  return nil
end

---The profile a new terminal runs: `wanted` when there is one by that name, then the one the
---`terminal.default_profile` setting names, then the default profile.
---@param profiles Terminal.Profile[]
---@param wanted string?
---@param default_name string?
---@return Terminal.Profile
function M.pick (profiles, wanted, default_name)
  return M.find (profiles, wanted)
    or M.find (profiles, default_name)
    or profiles[1]
end

---The folder a terminal starts in: the one asked for, then the profile's, then the open
---folder, then the workspace folder. `''` lets the app start it in the home folder.
---@param asked string?
---@param profile Terminal.Profile
---@param root string?
---@param workspace string?
---@return string
function M.cwd (asked, profile, root, workspace)
  for _, dir in ipairs ({
    asked or '',
    profile.cwd or '',
    root or '',
    workspace or '',
  }) do
    if dir ~= '' then
      return dir
    end
  end
  return ''
end

---Text from the editor as the shell should get it: each line ends with Enter, and the last
---one runs too.
---@param text string
---@return string
function M.as_input (text)
  local lines = text:gsub ('\r\n', '\n'):gsub ('\r', '\n')
  if lines:sub (-1) ~= '\n' then
    lines = lines .. '\n'
  end
  return (lines:gsub ('\n', '\r'))
end

return M
