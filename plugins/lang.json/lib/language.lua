-- language: what the server calls each JSON file. The editor calls `.json`, `.jsonc`, `.json5`
-- and `.ndg` files all `json`. The server reports a comment or a trailing comma as an error in
-- `json`, and lets them pass in `jsonc`. So files that allow comments go out as `jsonc`: the
-- `.jsonc` and `.json5` files, and well-known settings files such as `tsconfig.json`.
-- Nothing here calls the app, so the tests reach it.

---@class LangJson.LanguageModule
local M = {}

-- Files by name that allow comments, in lower case.
local COMMENTED = {
  ['.babelrc.json'] = true,
  ['.devcontainer.json'] = true,
  ['.eslintrc.json'] = true,
  ['devcontainer.json'] = true,
  ['deno.json'] = true,
  ['language-configuration.json'] = true,
}

-- The same, by the start of the name, for files such as `tsconfig.app.json`.
local COMMENTED_STARTS = { 'tsconfig', 'jsconfig' }

---The file's name and the folder that holds it, both in lower case.
---@param path string
---@return string name
---@return string folder
local function name_and_folder (path)
  local parts = {} ---@type string[]
  for part in path:lower ():gsub ('\\', '/'):gmatch ('[^/]+') do
    parts[#parts + 1] = part
  end
  return parts[#parts] or '', parts[#parts - 1] or ''
end

---What the server calls a file: `jsonc` when it may hold comments, and `json` otherwise.
---@param path string
---@return 'json'|'jsonc'
function M.language_id (path)
  local name, folder = name_and_folder (path)
  local ext = name:match ('%.([^.]+)$')
  if ext == 'jsonc' or ext == 'json5' then
    return 'jsonc'
  end
  if ext ~= 'json' then
    return 'json'
  end
  if COMMENTED[name] or folder == '.vscode' then
    return 'jsonc'
  end
  for _, start in ipairs (COMMENTED_STARTS) do
    if name:sub (1, #start) == start then
      return 'jsonc'
    end
  end
  return 'json'
end

---False for a file whose problems the plugin hides. JSON5 allows more than the server
---reads, such as keys without quotes, so its problems would be wrong.
---@param path string
---@return boolean
function M.checked (path)
  local name = name_and_folder (path)
  return name:match ('%.json5$') == nil
end

return M
