-- git_paths: joins and reads paths, keeps the list of recent repositories, and picks the
-- text to show when a git command fails. It calls no host function, so the tests reach all
-- of it.

local T = require ('git_text') --[[@as Git.TextModule]]

local lines_of, strip_cr, trim = T.lines_of, T.strip_cr, T.trim

---@class Git.PathsModule
local M = {}

---------------------------------------------------------------------------------------------
-- Paths, lists and messages
---------------------------------------------------------------------------------------------

---Splits a path into its file name and its folder.
---@param path string
---@return string name
---@return string folder Empty for a file at the top.
function M.split_path (path)
  local clean = path:gsub ('/$', '')
  local dir, name = clean:match ('^(.*)/([^/]*)$')
  if not dir then
    return clean, ''
  end
  return name, dir
end

---The folder name `git clone` gives a repository: the last part of its address, without
---`.git`. Empty when the address has no name at its end.
---@param url string
---@return string
function M.clone_name (url)
  local trimmed = url:match ('^%s*(.-)%s*$') or '' ---@type string
  local text = trimmed:gsub ('[/\\]+$', '')
  local last = text:match ('([^/\\:]+)$') or '' ---@type string
  local name = last:gsub ('%.git$', '')
  return name
end

---Joins the repository folder and a path inside it.
---@param root string
---@param rel string
---@return string
function M.join (root, rel)
  local base = root:gsub ('[/\\]+$', '')
  return base .. '/' .. rel
end

---A full path as a path from the repository root, or nil when it is outside. Windows ignores
---the case of letters in paths, so the comparison there does too.
---@param root string
---@param full string
---@param os? string
---@return string?
function M.relative (root, full, os)
  local base = root:gsub ('\\', '/'):gsub ('/+$', '')
  local path = full:gsub ('\\', '/')
  local head = path:sub (1, #base + 1)
  local want = base .. '/'
  if os == 'windows' then
    head, want = head:lower (), want:lower ()
  end
  if head ~= want or #path <= #want then
    return nil
  end
  return path:sub (#want + 1)
end

---The folder that holds a path.
---@param path string
---@return string
function M.parent (path)
  local clean = path:gsub ('[/\\]+$', '')
  return clean:match ('^(.*)[/\\][^/\\]*$') or clean
end

---A path with the separators the system's file manager expects.
---@param path string
---@param os string Such as `'windows'`.
---@return string
function M.native (path, os)
  if os == 'windows' then
    local out = path:gsub ('/', '\\')
    return out
  end
  return path
end

---Puts a repository at the front of the recent list, without repeats, and keeps `max`.
---@param list string[]
---@param path string
---@param max integer
---@return string[]
function M.remember (list, path, max)
  local out = { path } ---@type string[]
  for _, p in ipairs (list) do
    if p ~= path and #out < max then
      out[#out + 1] = p
    end
  end
  return out
end

---The text to show when a git command fails: what Git printed on stderr, or on stdout when
---stderr is empty, or the reason it could not start. Long output keeps its first lines.
---@param res Proteus.RunResult?
---@param err string?
---@return string
function M.error_text (res, err)
  local text = err or ''
  if res then
    text = trim (res.stderr or '')
    if text == '' then
      text = trim (res.stdout or '')
    end
  end
  if text == '' then
    return 'Git failed with no message.'
  end
  local lines = lines_of (text)
  if #lines > 8 then
    text = table.concat (lines, '\n', 1, 8) .. '\n…'
  end
  return text
end

---The first line Git printed, for a short report such as `'Already up to date.'`.
---@param res Proteus.RunResult
---@return string
function M.summary (res)
  for _, s in ipairs ({ res.stdout or '', res.stderr or '' }) do
    local first = trim (s):match ('^[^\n]*') or ''
    if first ~= '' then
      return strip_cr (first)
    end
  end
  return ''
end

---True when a file could not be read because it is not text.
---@param err string?
---@return boolean
function M.is_binary_error (err)
  return err ~= nil and err:lower ():find ('utf%-8') ~= nil
end

return M
