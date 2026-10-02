-- languages: which files the Tailwind server hears about, and what it calls each one. The
-- editor's own language for a file does not say enough. It calls `.vue` and `.svelte` files
-- `html`, and `.scss` files `css`. So the extension decides. Nothing here calls the app, so
-- the tests reach it.

---@class LangTailwind.LanguagesModule
local M = {}

-- What the server calls each kind of file, by its extension.
local IDS = {
  html = 'html',
  htm = 'html',
  vue = 'vue',
  svelte = 'svelte',
  css = 'css',
  scss = 'scss',
  js = 'javascript',
  mjs = 'javascript',
  cjs = 'javascript',
  ts = 'typescript',
  mts = 'typescript',
  cts = 'typescript',
  jsx = 'javascriptreact',
  tsx = 'typescriptreact',
  md = 'markdown',
  mdx = 'mdx',
}

-- The files that get class completion, as file association patterns. Each one is served by
-- another plugin, which shows these items before its own.
M.PATTERNS = {
  '*.html',
  '*.htm',
  '*.vue',
  '*.svelte',
  '*.css',
  '*.scss',
  '*.js',
  '*.mjs',
  '*.cjs',
  '*.ts',
  '*.mts',
  '*.cts',
  '*.jsx',
  '*.tsx',
  '*.md',
  '*.mdx',
}

---A file's extension in lower case, or nil when it has none.
---@param path string
---@return string?
function M.extension (path)
  local name = path:match ('[^/\\]*$') or path
  local ext = name:match ('^.+%.([^.]+)$')
  return ext and ext:lower () or nil
end

---What the server calls a file, or nil when the server leaves it alone.
---@param path string
---@return string?
function M.language_id (path)
  return IDS[M.extension (path) or '']
end

return M
