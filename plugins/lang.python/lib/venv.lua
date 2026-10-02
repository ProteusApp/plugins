-- venv: where a project's Python and its tools may be. A virtual environment keeps its
-- programs in `Scripts` on Windows and in `bin` elsewhere. Nothing here calls the app, so the
-- tests reach it.

---@class LangPython.VenvModule
local M = {}

-- The folders in a project that usually hold its virtual environment, best first.
M.FOLDERS = { '.venv', 'venv' }

-- The names Python goes by on the PATH, best first.
M.PATH_NAMES = { 'python', 'python3' }

-- A line of Python that prints the interpreter's own path.
M.WHERE = 'import sys; print(sys.executable)'

---The path with `/`, and no `/` at the end.
---@param path string
---@return string
local function slashed (path)
  local out = path:gsub ('\\', '/')
  if #out > 1 and out:sub (-1) == '/' and not out:match ('^%a:/$') then
    out = out:sub (1, -2)
  end
  return out
end

---The folder that holds a path.
---@param path string
---@return string
local function parent (path)
  return path:match ('^(.*)/[^/]*$') or path
end

---True while the Code Editor has a folder open that the user does not trust. A folder's own
---programs, such as a `.venv` Python or the basedpyright in its node_modules, run nothing
---until then. Without the `project` service there is no folder to trust.
---@param project? Proteus.Project
---@param layer Proteus.ProjectLayer What `app.kernel.project ()` says.
---@return boolean
function M.untrusted (project, layer)
  if not project or not project.root () then
    return false
  end
  if project.trusted then
    return not project.trusted ()
  end
  return layer.trusted ~= true
end

---A program inside a virtual environment, such as `.venv/Scripts/python.exe`.
---@param env string The environment's folder.
---@param name string Such as `'python'`.
---@param os string Such as `'windows'`.
---@return string
function M.program (env, name, os)
  if os == 'windows' then
    return slashed (env) .. '/Scripts/' .. name .. '.exe'
  end
  return slashed (env) .. '/bin/' .. name
end

---The interpreters a project's virtual environments would hold, best first.
---@param root string? The project folder.
---@param os string
---@return string[]
function M.candidates (root, os)
  local out = {} ---@type string[]
  if not root or root == '' then
    return out
  end
  for _, folder in ipairs (M.FOLDERS) do
    out[#out + 1] = M.program (slashed (root) .. '/' .. folder, 'python', os)
  end
  return out
end

---A program in the same folder as an interpreter. A virtual environment puts the tools
---installed into it, such as Ruff, beside its Python.
---@param python string The interpreter's path.
---@param name string Such as `'ruff'`.
---@param os string
---@return string
function M.beside (python, name, os)
  local dir = parent (slashed (python))
  return dir .. '/' .. name .. (os == 'windows' and '.exe' or '')
end

---The interpreter's own path, from what `python -c WHERE` printed, or nil.
---@param stdout string?
---@return string?
function M.executable (stdout)
  for line in (stdout or ''):gmatch ('[^\r\n]+') do
    local path = line:match ('^%s*(.-)%s*$')
    if path ~= '' then
      return slashed (path)
    end
  end
  return nil
end

return M
