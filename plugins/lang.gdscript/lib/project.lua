-- project: where a Godot project starts, and the files its `res://` paths name. A Godot
-- project is the folder that holds `project.godot`, and `res://` is that folder. Nothing here
-- calls the host, so the tests reach it.

---@class LangGdscript.ProjectModule
local M = {}

-- A file this many folders below its project is not looked for any higher.
local MAX_DEPTH = 32

---Writes a path with `/`, one between each part and none at the end. A drive root keeps its
---slash, as in `C:/`.
---@param path string
---@return string
local function normalize (path)
  local text = path:gsub ('\\', '/'):gsub ('/+', '/')
  if text:match ('^%a:/?$') then
    return text:sub (1, 2) .. '/'
  end
  if #text > 1 then
    text = text:gsub ('/$', '')
  end
  return text
end

---The folders that hold a file, nearest first, up to the top of the disk.
---@param file string A full path, such as `C:/games/hop/player/player.gd`.
---@return string[]
function M.folders_up (file)
  local list = {} ---@type string[]
  local path = normalize (file)
  while #list < MAX_DEPTH do
    local up = path:match ('^(.*)/[^/]+$')
    if not up then
      break
    end
    if up == '' then
      up = '/'
    elseif up:match ('^%a:$') then
      up = up .. '/'
    end
    list[#list + 1] = up
    if up == '/' or up:match ('^%a:/$') then
      break
    end
    path = up
  end
  return list
end

---The full path a `res://` path names in a project. A path to a part of a file, such as
---`res://level.tscn::3`, names the file. Anything else, such as `user://save.json`, names
---nothing.
---@param res string
---@param root string The folder that holds `project.godot`.
---@return string?
function M.res_to_disk (res, root)
  local rest = res:match ('^res://(.*)$')
  if not rest then
    return nil
  end
  rest = rest:gsub ('::.*$', ''):gsub ('^/+', '')
  local base = normalize (root)
  if rest == '' then
    return base
  end
  if base:sub (-1) == '/' then
    return normalize (base .. rest)
  end
  return normalize (base .. '/' .. rest)
end

---Line `n` of a text, counted from 0, without its line break.
---@param text string
---@param n integer
---@return string?
function M.line_at (text, n)
  local i = 0
  for line in (text .. '\n'):gmatch ('([^\n]*)\n') do
    if i == n then
      return (line:gsub ('\r$', ''))
    end
    i = i + 1
  end
  return nil
end

---The `res://` path in quotes under a column of a line, such as the one in
---`preload ("res://enemy.tscn")` or `path="res://player.gd"`.
---@param line string
---@param character integer The column, counted from 0.
---@return string?
function M.res_path_at (line, character)
  local col = character + 1
  local from = 1
  while true do
    local first, last, _, path = line:find ('(["\'])(res://[^"\']*)%1', from)
    if not first then
      return nil
    end
    if col >= first and col <= last then
      return path
    end
    from = last + 1
  end
end

return M
