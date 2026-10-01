-- config: the settings bash-language-server gets, the arguments shfmt runs with, and the
-- version a program prints. Nothing here calls the app, so the tests reach it.

---@class LangShell.ConfigModule
local M = {}

-- The server asks for its settings under this name, which comes from its VS Code extension.
M.SECTION = 'bashIde'

---The server's settings. An empty `shellcheckPath` turns ShellCheck off, and an empty shfmt
---path keeps the server from formatting, since the plugin runs shfmt itself. explainshell
---stays off, so hover help never asks a web site.
---@param shellcheck string? The ShellCheck program, or nil to run none.
---@return table
function M.server (shellcheck)
  return {
    shellcheckPath = shellcheck or '',
    explainshellEndpoint = '',
    shfmt = { path = '' },
  }
end

---shfmt's arguments for formatting text from standard input. shfmt reads the project's
---`.editorconfig` for the file named by `--filename`, but only when no indent is given, so
---an indent below 0 leaves `-i` out. 0 indents with tabs, and more indents with that many
---spaces.
---@param path string The file's full path.
---@param indent any The `shell.indent` setting.
---@return string[]
function M.shfmt_args (path, indent)
  local args = { '--filename', path }
  local n = tonumber (indent)
  if n and n >= 0 then
    args[#args + 1] = '-i'
    args[#args + 1] = tostring (math.floor (n))
  end
  args[#args + 1] = '-'
  return args
end

---The version a program prints, such as `0.11.0` from ShellCheck's `version: 0.11.0` line,
---or `v3.14.1` from shfmt.
---@param text string What `--version` printed.
---@return string?
function M.version (text)
  local named = text:match ('[Vv]ersion:%s*(%S+)')
  if named then
    return named
  end
  local first = text:match ('^%s*([^\r\n]-)%s*[\r\n]')
    or text:match ('^%s*(.-)%s*$')
  return first ~= '' and first or nil
end

return M
