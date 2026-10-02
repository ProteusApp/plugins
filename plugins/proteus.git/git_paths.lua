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

---The key a folder is trusted under: `/` for every slash, none at the end, and lower case on
---Windows, which ignores case in paths.
---@param path string
---@param os? string
---@return string
function M.folder_key (path, os)
  local key = path:gsub ('\\', '/'):gsub ('(.)/+$', '%1')
  if os == 'windows' then
    key = key:lower ()
  end
  return key
end

---True when `path` is in the list of trusted folders. A folder inside a trusted one is not
---trusted by that, since it may be a repository of its own that arrived later.
---@param trusted string[] Folder keys.
---@param path string
---@param os? string
---@return boolean
function M.is_trusted (trusted, path, os)
  local key = M.folder_key (path, os)
  for _, t in ipairs (trusted) do
    if key == t then
      return true
    end
  end
  return false
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

-- The language `app.util.highlight` colors a file in, by its extension in lower case.
---@type table<string, string>
local LANGUAGES = {
  lua = 'lua',
  js = 'javascript',
  mjs = 'javascript',
  cjs = 'javascript',
  jsx = 'javascript',
  ts = 'typescript',
  mts = 'typescript',
  cts = 'typescript',
  tsx = 'typescript',
  json = 'json',
  jsonc = 'json',
  css = 'css',
  scss = 'scss',
  less = 'less',
  sass = 'sass',
  html = 'html',
  htm = 'html',
  vue = 'html',
  svelte = 'html',
  xml = 'xml',
  svg = 'xml',
  xaml = 'xml',
  csproj = 'xml',
  plist = 'xml',
  md = 'markdown',
  markdown = 'markdown',
  yaml = 'yaml',
  yml = 'yaml',
  toml = 'toml',
  ini = 'ini',
  cfg = 'ini',
  conf = 'ini',
  properties = 'ini',
  sh = 'shell',
  bash = 'shell',
  zsh = 'shell',
  ps1 = 'powershell',
  psm1 = 'powershell',
  py = 'python',
  pyi = 'python',
  rs = 'rust',
  go = 'go',
  hs = 'haskell',
  c = 'c',
  h = 'c',
  cc = 'cpp',
  cpp = 'cpp',
  cxx = 'cpp',
  hpp = 'cpp',
  hh = 'cpp',
  cs = 'csharp',
  java = 'java',
  kt = 'kotlin',
  kts = 'kotlin',
  scala = 'scala',
  dart = 'dart',
  sql = 'sql',
  rb = 'ruby',
  swift = 'swift',
  erl = 'erlang',
  elm = 'elm',
  clj = 'clojure',
  cljs = 'clojure',
  pl = 'perl',
  pm = 'perl',
  r = 'r',
  jl = 'julia',
  cmake = 'cmake',
  proto = 'protobuf',
  groovy = 'groovy',
  gradle = 'groovy',
  scm = 'scheme',
  lisp = 'commonlisp',
  ml = 'ocaml',
  fs = 'fsharp',
  vb = 'vb',
}

-- Files known by their whole name, in lower case, since they have no extension to go by.
---@type table<string, string>
local FILE_LANGUAGES = {
  dockerfile = 'dockerfile',
  containerfile = 'dockerfile',
  ['cmakelists.txt'] = 'cmake',
  gemfile = 'ruby',
  rakefile = 'ruby',
  ['.bashrc'] = 'shell',
  ['.zshrc'] = 'shell',
  ['nginx.conf'] = 'nginx',
  ['cargo.lock'] = 'toml',
}

---The language `app.util.highlight` colors a file in, by its name or extension, or nil for a
---file it has no colors for.
---@param path string
---@return string?
function M.code_language (path)
  local name = (path:match ('([^/\\]*)$') or ''):lower ()
  if FILE_LANGUAGES[name] then
    return FILE_LANGUAGES[name]
  end
  local ext = name:match ('%.([%w]+)$')
  return ext and LANGUAGES[ext] or nil
end

---True when a file could not be read because it is not text.
---@param err string?
---@return boolean
function M.is_binary_error (err)
  return err ~= nil and err:lower ():find ('utf%-8') ~= nil
end

return M
