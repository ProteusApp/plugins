-- exclude: the patterns of the `project.exclude` setting, which the file tree, search and Go to
-- File all leave out. It calls no host function, and it gets `lib/file_glob.lua` from the
-- caller, so the tests reach it without the app.
--
-- A pattern is a glob, as `lib/file_glob.lua` reads it: a name alone, such as `node_modules`,
-- matches a file or folder of that name anywhere, `*.min.js` any name that fits, and a pattern
-- with folders, such as `docs/build`, the end of a path. A pattern that ends in `/` matches
-- folders only. Whatever sits inside a folder that matches is left out with it.

---@class CodeProject.Exclude
local M = {}

-- What the setting holds until the user changes it: folders nobody reads or searches, and
-- the files a system leaves beside the user's own.
M.DEFAULT = {
  '.git',
  '.DS_Store',
  'Thumbs.db',
  'desktop.ini',
  'node_modules',
  '.venv',
  'venv',
  '__pycache__',
  'dist-newstyle',
  '.stack-work',
  '.next',
  '.cache',
}

-- Before 1.1.0, `project.exclude` held folder names for search alone, and the file tree hid
-- the names in `code.explorer.hide`. These were their defaults.
M.OLD_EXCLUDE = {
  'node_modules',
  'target',
  'dist',
  'build',
  'out',
  '.venv',
  'venv',
  '__pycache__',
  'dist-newstyle',
  '.stack-work',
  '.next',
  '.cache',
  'coverage',
}
M.OLD_HIDE = { '.git', '.DS_Store', 'Thumbs.db', 'desktop.ini' }

---The patterns in a setting's value: the strings that are not empty, trimmed.
---@param value any
---@return string[]
function M.clean (value)
  local out = {} ---@type string[]
  if type (value) ~= 'table' then
    return out
  end
  for _, v in
    ipairs (value --[[@as any[] ]])
  do
    if type (v) == 'string' then
      local p = v:match ('^%s*(.-)%s*$') --[[@as string]]
      p = p:gsub ('\\', '/')
      if p ~= '' and p ~= '/' then
        out[#out + 1] = p
      end
    end
  end
  return out
end

---Every pattern of the lists, each once, in the order they come.
---@param ... string[]
---@return string[]
function M.merge (...)
  local out, seen = {}, {} ---@type string[], table<string, boolean>
  local lists = { ... } ---@type string[][]
  for _, list in ipairs (lists) do
    for _, p in ipairs (list) do
      if not seen[p] then
        seen[p] = true
        out[#out + 1] = p
      end
    end
  end
  return out
end

---True when `pattern` matches the path itself.
---@param file_glob FileGlob
---@param pattern string
---@param rel string
---@param dir boolean
---@param fold boolean
---@return boolean
local function fits (file_glob, pattern, rel, dir, fold)
  -- With a `/` in front the path reads from the root, as a pattern that starts with one does.
  local body = pattern:match ('^(.-)/$')
  if body then
    return dir and body ~= '' and file_glob.matches (body, '/' .. rel, fold)
  end
  return file_glob.matches (pattern, '/' .. rel, fold)
end

---True when the path, from the folder's root, or a folder above it fits one of the patterns.
---@param file_glob FileGlob The app's `lib/file_glob.lua`.
---@param patterns string[]
---@param rel string Such as `src/app/main.rs`.
---@param dir? boolean True when the path is a folder.
---@param fold? boolean Case does not matter, as on Windows.
---@return boolean
function M.matches (file_glob, patterns, rel, dir, fold)
  if #patterns == 0 or rel == '' then
    return false
  end
  local at = 0
  while true do
    local slash = rel:find ('/', at + 1, true)
    local part = slash and rel:sub (1, slash - 1) or rel
    local is_dir = slash ~= nil or dir == true
    for _, p in ipairs (patterns) do
      if fits (file_glob, p, part, is_dir, fold == true) then
        return true
      end
    end
    if not slash then
      return false
    end
    at = slash
  end
end

---The patterns written for a walk or a search on disk, which reads them as `.gitignore` does.
---There a pattern with a `/` inside it starts at the root, so one that does not start with
---`/` gets `**/` in front, to match the end of a path here too.
---@param patterns string[]
---@return string[]
function M.for_walk (patterns)
  local out = {} ---@type string[]
  for i, p in ipairs (patterns) do
    local inner = p:gsub ('/$', '')
    if
      inner:find ('/', 1, true)
      and not p:find ('^/')
      and not p:find ('^%*%*/')
    then
      p = '**/' .. p
    end
    out[i] = p
  end
  return out
end

---What `project.exclude` holds after the update that merged it with `code.explorer.hide`.
---Nil when the user changed neither, so the new default applies.
---@param exclude any The user's `project.exclude`, or nil when it was never set.
---@param hide any The user's `code.explorer.hide`, or nil when it was never set.
---@return string[]?
function M.migrate (exclude, hide)
  if exclude == nil and hide == nil then
    return nil
  end
  local search = exclude ~= nil and M.clean (exclude) or M.DEFAULT
  local tree = hide ~= nil and M.clean (hide) or M.OLD_HIDE
  return M.merge (search, tree)
end

return M
