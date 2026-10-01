-- launch: where to look for the language server's own script, so `node` can run it. On
-- Windows npm installs a program as a `.cmd` file and a shell script with no extension, and a
-- search on the PATH finds the shell script first, which Windows cannot run. Running `node`
-- on the package's script works everywhere. Nothing here calls the host, so the tests reach
-- it.

---@class LangCss.LaunchModule
local M = {}

-- The npm package, and the program it installs for CSS.
M.PACKAGE = 'vscode-langservers-extracted'
M.PROGRAM = 'vscode-css-language-server'

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

---The folders the package may be in, best first: the project's own `node_modules`, then the
---ones next to the program that `which` found. npm puts a global package in `node_modules`
---beside the program on Windows, and in `lib/node_modules` above its `bin` folder elsewhere.
---@param root string? The project folder.
---@param program string? The program found on the PATH.
---@return string[]
function M.package_dirs (root, program)
  local out = {} ---@type string[]
  local seen = {} ---@type table<string, true>
  ---@param dir string
  local function add (dir)
    if not seen[dir] then
      seen[dir] = true
      out[#out + 1] = dir
    end
  end
  if root and root ~= '' then
    add (slashed (root) .. '/node_modules/' .. M.PACKAGE)
  end
  if program and program ~= '' then
    local bin = parent (slashed (program))
    add (bin .. '/node_modules/' .. M.PACKAGE)
    add (parent (bin) .. '/lib/node_modules/' .. M.PACKAGE)
  end
  return out
end

---The script a package's `package.json` runs for a program, relative to the package folder.
---@param manifest any The decoded `package.json`.
---@param name string The program, such as `vscode-css-language-server`.
---@return string?
function M.bin (manifest, name)
  if type (manifest) ~= 'table' then
    return nil
  end
  local bin = manifest.bin
  if type (bin) == 'table' then
    bin = bin[name]
  end
  if type (bin) ~= 'string' or bin == '' then
    return nil
  end
  return (bin:gsub ('\\', '/'):gsub ('^%./', ''))
end

---True for a program that the system can start as it is. On Windows only a `.exe` or a
---`.com` file can be, and npm's `.cmd` file and extensionless shell script cannot.
---@param program string
---@param os string Such as `'windows'`.
---@return boolean
function M.runs_directly (program, os)
  if os ~= 'windows' then
    return true
  end
  local ext = program:lower ():match ('%.(%w+)$')
  return ext == 'exe' or ext == 'com'
end

return M
