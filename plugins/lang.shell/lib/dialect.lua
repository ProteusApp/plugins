-- dialect: tells a zsh script from the others. ShellCheck does not support zsh. The server
-- leaves a `.zsh` file alone, but it checks `.zshrc` as bash, and a file whose first line
-- runs zsh gets one error that says so. The plugin drops ShellCheck's problems for every
-- zsh file instead. Nothing here calls the app, so the tests reach it.

---@class LangShell.DialectModule
local M = {}

-- The startup files zsh reads, by name.
local ZSH_FILES = {
  ['.zshrc'] = true,
  ['.zshenv'] = true,
  ['.zprofile'] = true,
  ['.zlogin'] = true,
  ['.zlogout'] = true,
}

---The program a `#!` line runs, without its folder. `#!/usr/bin/env zsh` runs zsh, and so
---does `#!/usr/bin/env -S zsh -f`.
---@param line string The first line.
---@return string?
function M.interpreter (line)
  local rest = line:match ('^#!%s*(.-)%s*$')
  if not rest then
    return nil
  end
  local words = {} ---@type string[]
  for word in rest:gmatch ('%S+') do
    words[#words + 1] = word
  end
  local i = 1
  local name = words[i] and words[i]:match ('([^/]+)$')
  if name == 'env' then
    i = i + 1
    while words[i] and words[i]:sub (1, 1) == '-' do
      i = i + 1
    end
    name = words[i] and words[i]:match ('([^/]+)$')
  end
  return name
end

---The shell a `# shellcheck shell=zsh` line names, among the comments at the top.
---@param text string
---@return string?
function M.directive (text)
  for line in (text .. '\n'):gmatch ('([^\n]*)\n') do
    local trimmed = line:match ('^%s*(.-)%s*$')
    if trimmed ~= '' and trimmed:sub (1, 1) ~= '#' then
      return nil
    end
    local shell = trimmed:match ('^#%s*shellcheck%s.-shell=(%w+)')
    if shell then
      return shell
    end
  end
  return nil
end

---True for a zsh script: by its name, by its `#!` line, or by a ShellCheck directive.
---@param path string
---@param text string? The file's text, when it is open.
---@return boolean
function M.is_zsh (path, text)
  local name = (path:match ('([^/\\]+)$') or path):lower ()
  if ZSH_FILES[name] or name:match ('%.zsh$') then
    return true
  end
  if not text then
    return false
  end
  local first = text:match ('^([^\r\n]*)') or ''
  if M.interpreter (first) == 'zsh' then
    return true
  end
  return M.directive (text) == 'zsh'
end

return M
