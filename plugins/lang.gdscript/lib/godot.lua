-- godot: the Godot program, for when the plugin starts Godot itself. Which names to look for,
-- which versions can run the language server without a window, and the command line. Nothing
-- here calls the host, so the tests reach it.

---@class LangGdscript.GodotModule
local M = {}

-- The port the Godot editor listens on unless its settings say otherwise.
M.DEFAULT_PORT = 6005

---The port from the `gdscript.port` setting. A value that is not a port gives the default.
---@param value any
---@return integer
function M.port (value)
  local n = tonumber (value)
  if not n or n ~= math.floor (n) or n < 1 or n > 65535 then
    return M.DEFAULT_PORT
  end
  return math.floor (n)
end

---The programs to look for, in order: the `gdscript.godot_path` setting when it is set,
---and otherwise `godot` and `godot4` on the PATH.
---@param setting any
---@return string[]
function M.programs (setting)
  local path = type (setting) == 'string' and setting:match ('^%s*(.-)%s*$')
    or ''
  if path ~= '' then
    return { path }
  end
  return { 'godot', 'godot4' }
end

---The version `godot --version` prints, such as `4.3.stable.official.77dcf97d8`.
---@param text string
---@return integer? major
---@return integer? minor
function M.version (text)
  local major, minor = text:match ('(%d+)%.(%d+)')
  if not major then
    return nil, nil
  end
  return math.floor (tonumber (major) or 0), math.floor (tonumber (minor) or 0)
end

---True for a Godot that runs its language server without a window. That came in Godot 4.2.
---@param major integer
---@param minor integer
---@return boolean
function M.serves_headless (major, minor)
  return major > 4 or (major == 4 and minor >= 2)
end

---The arguments that open a project in the Godot editor, with no window, and its language
---server on a port.
---@param root string The folder that holds `project.godot`.
---@param port integer
---@return string[]
function M.args (root, port)
  return {
    '--path',
    root,
    '--editor',
    '--headless',
    '--lsp-port',
    tostring (port),
  }
end

return M
