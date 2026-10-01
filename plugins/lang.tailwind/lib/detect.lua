-- detect: whether a folder uses Tailwind CSS. A folder does when it has a `tailwind.config`
-- file, as Tailwind 3 needs, or a stylesheet that imports `tailwindcss`, as Tailwind 4 does,
-- or `tailwindcss` in a package.json. The server looks for its projects itself once it runs.
-- This only keeps it from starting in a folder with none. Nothing here calls the app, so the
-- tests reach it.

---@class LangTailwind.DetectModule
local M = {}

-- The names of Tailwind 3's config file.
M.CONFIG_GLOBS = {
  'tailwind.config.js',
  'tailwind.config.cjs',
  'tailwind.config.mjs',
  'tailwind.config.ts',
  'tailwind.config.cts',
  'tailwind.config.mts',
}

-- The files a search for `tailwind` reads.
M.SEARCH_GLOBS = {
  '*.css',
  '*.scss',
  '*.sass',
  '*.less',
  '*.pcss',
  '*.postcss',
  'package.json',
}

-- Folders a search leaves out. Every package installs its own package.json there.
M.SKIP = { 'node_modules', '.git' }

---The last part of a path.
---@param path string
---@return string
local function name_of (path)
  return path:match ('[^/\\]*$') or path
end

---True for a Tailwind 3 config file, such as `tailwind.config.ts`.
---@param path string
---@return boolean
function M.is_config (path)
  local name = name_of (path):lower ()
  for _, glob in ipairs (M.CONFIG_GLOBS) do
    if name == glob then
      return true
    end
  end
  return false
end

---True when a line of a file shows the folder uses Tailwind. In a package.json that is a
---`tailwindcss` or `@tailwindcss/...` dependency. In a stylesheet it is an `@import` or
---`@reference` of `tailwindcss`, or a Tailwind 3 `@tailwind` rule.
---@param path string
---@param line string
---@return boolean
function M.line_says (path, line)
  if name_of (path):lower () == 'package.json' then
    return line:find ('"tailwindcss"%s*:') ~= nil
      or line:find ('"@tailwindcss/[%w%-]+"%s*:') ~= nil
  end
  return line:find ('@import%s+["\']tailwindcss') ~= nil
    or line:find ('@import%s+url%(%s*["\']?tailwindcss') ~= nil
    or line:find ('@reference%s+["\']tailwindcss') ~= nil
    or line:find ('@tailwind%s+%a') ~= nil
end

---True when one of a search's matches shows the folder uses Tailwind.
---@param matches { path: string, before?: string, hit?: string, after?: string }[]
---@return boolean
function M.any (matches)
  for _, m in ipairs (matches) do
    local line = (m.before or '') .. (m.hit or '') .. (m.after or '')
    if M.line_says (m.path, line) then
      return true
    end
  end
  return false
end

---True for a file whose saving may change the answer, such as a new config file.
---@param path string
---@return boolean
function M.matters (path)
  if M.is_config (path) then
    return true
  end
  local name = name_of (path):lower ()
  if name == 'package.json' then
    return true
  end
  for _, glob in ipairs (M.SEARCH_GLOBS) do
    local ext = glob:match ('^%*(%..+)$')
    if ext and name:sub (-#ext) == ext then
      return true
    end
  end
  return false
end

return M
