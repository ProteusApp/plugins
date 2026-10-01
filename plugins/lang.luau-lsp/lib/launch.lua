-- launch: the command lines this plugin runs, and the settings luau-lsp asks for. Nothing here
-- calls the app, so the tests reach it.

-- The file Rojo writes and luau-lsp reads, in the root of the folder.
local SOURCEMAP = 'sourcemap.json'

-- The files on disk whose changes luau-lsp hears about, by the end of their names.
local WATCHED = { '%.luau$', '%.lua$', '/%.luaurc$', '/' .. SOURCEMAP .. '$' }

-- The protocol's numbers for a changed file and a deleted one.
local CHANGED, DELETED = 2, 3

---The files luau-lsp loads at start, as full paths. A path left out is not passed.
---@class LangLuau.LaunchFiles
---@field definitions? string Roblox's type definitions.
---@field docs? string The documentation for the definitions, or for Luau's own library.

---@class LangLuau.LaunchModule
local M = {}

M.SOURCEMAP = SOURCEMAP

---The arguments for `luau-lsp`. The server talks over its standard input and output. Like
---VS Code's extension, it runs without Luau's experimental flags, and loads Roblox's
---definitions under the name `@roblox`.
---@param files LangLuau.LaunchFiles
---@return string[]
function M.server_args (files)
  local args = { 'lsp', '--no-flags-enabled' }
  if files.definitions then
    args[#args + 1] = '--definitions:@roblox=' .. files.definitions
  end
  if files.docs then
    args[#args + 1] = '--docs=' .. files.docs
  end
  args[#args + 1] = '--stdio'
  return args
end

---The `luau-lsp` section of the settings, as the server asks for it. The server takes every
---file for Roblox code unless it hears otherwise, so plain Luau says `standard`.
---@param roblox boolean
---@param sourcemap boolean True to read the sourcemap that Rojo writes.
---@return table
function M.settings (roblox, sourcemap)
  return {
    platform = { type = roblox and 'roblox' or 'standard' },
    sourcemap = {
      enabled = roblox and sourcemap,
      -- This plugin runs Rojo itself, so the server does not.
      autogenerate = false,
      sourcemapFile = SOURCEMAP,
    },
    completion = {
      -- The editor puts the cursor after inserted text, so `print()` would leave it past the
      -- closing parenthesis. The name alone leaves the `(` to type.
      addParentheses = false,
      -- An import item adds a line at the top of the file, which the editor does not apply.
      imports = { enabled = false },
    },
  }
end

---The arguments for `rojo`, which writes the sourcemap again whenever the project changes.
---@return string[]
function M.rojo_args ()
  return {
    'sourcemap',
    'default.project.json',
    '--output',
    SOURCEMAP,
    '--watch',
    '--include-non-scripts',
  }
end

---The arguments for `stylua`, which formats the text on its standard input. The file's path
---lets it find a `stylua.toml` in the file's folder or a folder above.
---@param path string The file's full path.
---@return string[]
function M.stylua_args (path)
  return {
    '--syntax',
    'Luau',
    '--search-parent-directories',
    '--stdin-filepath',
    path,
    '-',
  }
end

---True for a file whose change luau-lsp should hear about.
---@param path string A full path with `/`.
---@return boolean
function M.watched (path)
  for _, ending in ipairs (WATCHED) do
    if path:find (ending) then
      return true
    end
  end
  return false
end

---The changes on disk under `root` that luau-lsp should hear about, as the protocol's file
---events. A folder that changed is left out.
---@param changes Proteus.DirChange[]
---@param root string The server's folder, a full path with `/`.
---@param uri fun(path: string): string The server's address for a full path.
---@return { uri: string, type: integer }[]
function M.file_events (changes, root, uri)
  local prefix = root:gsub ('/$', '') .. '/'
  local events = {} ---@type { uri: string, type: integer }[]
  for _, change in ipairs (changes) do
    local path = change.path
    if
      change.kind ~= 'dir'
      and path:sub (1, #prefix) == prefix
      and M.watched (path)
    then
      events[#events + 1] = {
        uri = uri (path),
        type = change.kind == 'remove' and DELETED or CHANGED,
      }
    end
  end
  return events
end

return M
