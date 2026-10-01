-- config: the settings basedpyright asks for. It asks for the `python` section, which holds
-- the interpreter, and the `basedpyright` section, which holds how strictly it checks types.
-- A project's pyrightconfig.json, or `[tool.basedpyright]` in its pyproject.toml, wins over
-- both, and the server reads those by itself. Nothing here calls the app, so the tests reach
-- it.

---@class LangPython.ConfigModule
local M = {}

-- basedpyright's type checking modes, from the least strict to the most.
M.MODES = { 'off', 'basic', 'standard', 'strict', 'recommended', 'all' }

-- The mode used when the setting holds something else.
M.DEFAULT_MODE = 'standard'

---What the server is told.
---@class LangPython.ConfigState
---@field python? string The interpreter's path, when one was found.
---@field mode string A type checking mode.

---A mode that basedpyright knows, or the default.
---@param value any
---@return string
function M.mode (value)
  for _, mode in ipairs (M.MODES) do
    if value == mode then
      return mode
    end
  end
  return M.DEFAULT_MODE
end

---The answer to a request for one settings section, or nil for a section it does not fill.
---An empty table could go out as `[]`, so a section with nothing in it is nil.
---@param section string Such as `'python'` or `'basedpyright.analysis'`.
---@param state LangPython.ConfigState
---@return table?
function M.section (section, state)
  local analysis = { typeCheckingMode = M.mode (state.mode) }
  if section == 'python' then
    return state.python and { pythonPath = state.python } or nil
  elseif section == 'basedpyright' then
    return { analysis = analysis }
  elseif section == 'basedpyright.analysis' then
    return analysis
  end
  return nil
end

---Every section at once, for `workspace/didChangeConfiguration`.
---@param state LangPython.ConfigState
---@return table
function M.all (state)
  return {
    python = M.section ('python', state),
    basedpyright = M.section ('basedpyright', state),
  }
end

return M
