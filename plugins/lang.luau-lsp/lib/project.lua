-- project: what a folder's file names say about it. A Rojo project file, such as
-- `default.project.json`, or a `.luaurc` marks a Roblox project, which turns Roblox mode on
-- while `luau-lsp.roblox` is `auto`. Nothing here calls the app, so the tests reach it.

-- The project file `rojo sourcemap` reads.
local ROJO_PROJECT = 'default.project.json'

---@class LangLuau.ProjectModule
local M = {}

M.ROJO_PROJECT = ROJO_PROJECT

---True for the names of a folder that holds a Rojo project file or a `.luaurc`.
---@param names string[] As app.fs.list_dir gives them, with a `/` after each folder.
---@return boolean
function M.is_roblox (names)
  for _, name in ipairs (names) do
    if name == '.luaurc' or name:match ('^[^/]+%.project%.json$') then
      return true
    end
  end
  return false
end

---Whether Roblox mode is on. The setting wins when it is `on` or `off`. With `auto`, or any
---other value, the folder decides.
---@param setting any The value of `luau-lsp.roblox`.
---@param names string[]
---@return boolean
function M.roblox (setting, names)
  if setting == 'on' then
    return true
  elseif setting == 'off' then
    return false
  end
  return M.is_roblox (names)
end

---True when the folder holds the project file that `rojo sourcemap` reads.
---@param names string[]
---@return boolean
function M.has_rojo_project (names)
  for _, name in ipairs (names) do
    if name == ROJO_PROJECT then
      return true
    end
  end
  return false
end

return M
