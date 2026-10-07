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

---A path with `/`, no `/` at the end, and lower case on Windows, which ignores case.
---@param path string
---@param os? string
---@return string
local function folder_key (path, os)
  local out = path:gsub ('\\', '/'):gsub ('(.)/+$', '%1')
  if os == 'windows' then
    out = out:lower ()
  end
  return out
end

---True when the plugin may start Godot on the project at `root`. Godot runs a project's tool
---scripts when it opens it, so in the Code Editor the project must be inside the open folder,
---and the user must trust that folder. Without a folder open there is nothing to trust, and
---the user turned `gdscript.start_godot` on.
---@param root string The folder that holds `project.godot`.
---@param folder? string The folder open in the Code Editor.
---@param trusted boolean True when the user trusts it.
---@param os? string
---@return boolean
function M.may_start (root, folder, trusted, os)
  if not folder then
    return true
  end
  if not trusted then
    return false
  end
  local f = folder_key (folder, os)
  local r = folder_key (root, os)
  return r == f or r:sub (1, #f + 1) == f .. '/'
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

---True for a scene file, which the Godot editor can open from the command line.
---@param path string
---@return boolean
function M.is_scene (path)
  local lower = path:lower ()
  return lower:sub (-5) == '.tscn' or lower:sub (-4) == '.scn'
end

---The `res://` path of a file inside a project, or nil for one outside it.
---@param root string The project's folder, with `/`.
---@param path string The file's full path, with `/`.
---@return string?
function M.res_path (root, path)
  local base = root:gsub ('/+$', '') .. '/'
  if path:sub (1, #base) ~= base then
    return nil
  end
  return 'res://' .. path:sub (#base + 1)
end

---True when `pgrep -af godot` output shows a Godot editor window on the project in `root`.
---Godot starts its editor with `--path <folder> --editor`, from the project manager too. One
---with `--headless` has no window, such as the language server the GDScript plugin starts,
---so it does not count.
---@param text string One process a line: its id, then its command line.
---@param root string The project's folder, with `/`.
---@return boolean
function M.editor_running (text, root)
  local want = root:gsub ('/+$', '')
  for line in (text .. '\n'):gmatch ('([^\n]*)\n') do
    local editor, headless, path = false, false, nil ---@type boolean, boolean, string?
    local words = {} ---@type string[]
    for word in line:gmatch ('%S+') do
      words[#words + 1] = word
    end
    for i, word in ipairs (words) do
      if word == '-e' or word == '--editor' then
        editor = true
      elseif word == '--headless' then
        headless = true
      elseif word == '--path' then
        path = words[i + 1]
      elseif word:sub (1, 7) == '--path=' then
        path = word:sub (8)
      end
    end
    if editor and not headless and path and path:gsub ('/+$', '') == want then
      return true
    end
  end
  return false
end

return M
