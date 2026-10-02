-- languages: which files Some Sass serves, what it hears about each one, and its settings.
-- Nothing here calls the app, so the tests reach it.

---@class LangSass.LanguagesModule
local M = {}

-- The editor's languages for the files Some Sass reads. The editor calls `.scss`, `.css` and
-- `.less` files `css`, and `.sass` files `sass`.
M.EDITOR_LANGUAGES = { 'css', 'sass' }

-- What the server calls each kind of file, by its extension. Less is not here, since Some
-- Sass does not read it.
local IDS = { scss = 'scss', sass = 'sass', css = 'css' }

-- The program npm installs. On Windows npm adds a script with no extension for other shells,
-- next to the `.cmd` file. A search for the bare name finds that script first, and Windows
-- cannot run it, so the plugin asks for the `.cmd` file by its full name.
local PROGRAM = 'some-sass-language-server'

---A file's extension in lower case, or nil when it has none.
---@param path string
---@return string?
function M.extension (path)
  local name = path:match ('[^/\\]*$') or path
  local ext = name:match ('^.+%.([^.]+)$')
  return ext and ext:lower () or nil
end

---What the server calls a file, or nil when the plugin leaves it alone. Plain CSS files count
---only when `with_css` is true.
---@param path string
---@param language string The editor's language for the file.
---@param with_css boolean
---@return string?
function M.language_id (path, language, with_css)
  if language ~= 'css' and language ~= 'sass' then
    return nil
  end
  local id = IDS[M.extension (path) or '']
  if id == 'css' and not with_css then
    return nil
  end
  return id
end

---The program to look for on this system.
---@param system string Such as `'windows'`.
---@return string
function M.program (system)
  return system == 'windows' and (PROGRAM .. '.cmd') or PROGRAM
end

---The `somesass` settings section the server asks for.
---@param load_paths any The `sass.load_paths` setting, a list of folders.
---@param use_only boolean True to suggest only what `@use` and `@forward` bring in.
---@return table
function M.config (load_paths, use_only)
  local section = {
    scss = { completion = { suggestFromUseOnly = use_only } },
    sass = { completion = { suggestFromUseOnly = use_only } },
  }
  local paths = {} ---@type string[]
  if type (load_paths) == 'table' then
    for _, path in ipairs (load_paths) do
      if type (path) == 'string' and path ~= '' then
        paths[#paths + 1] = path
      end
    end
  end
  -- Left out when empty, since an empty table could go out as `[]`.
  if #paths > 0 then
    section.workspace = { loadPaths = paths }
  end
  return section
end

return M
