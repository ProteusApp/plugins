-- icons.vivid: an icon pack with a Lucide icon for each kind of file, in the colors each
-- language is known by, and icons for the folders most projects have.
--
-- It registers the pack with core.icons, with a look for every kind of file and folder in the
-- app's lib/file_kinds.lua. Each color is a pair, one for light themes and one for dark ones,
-- so the icons read on both. Pick it with View > Choose File Icons, or set `icon_pack` to
-- `vivid`.

local PACK = 'vivid'

---An icon in two colors: the first while a light theme shows, the second while a dark one does.
---@param icon string A Lucide icon name.
---@param light string
---@param dark string
---@return Proteus.FileIcon
local function look (icon, light, dark)
  return { icon = icon, color = 'light-dark(' .. light .. ', ' .. dark .. ')' }
end

---A folder's icon, which shows `folder-open` while the folder is open.
---@param icon string
---@param light string
---@param dark string
---@return Proteus.FileIcon
local function folder (icon, light, dark)
  local out = look (icon, light, dark)
  out.open = 'folder-open'
  return out
end

---How each kind of file and folder looks, by its id in lib/file_kinds.lua.
---@type table<string, Proteus.FileIcon>
local KINDS = {
  lua = look ('moon', '#2a536c', '#51a0cf'),
  rust = look ('cog', '#644a3b', '#dea584'),
  typescript = look ('file-type', '#215287', '#4e8bce'),
  ['typescript-types'] = look ('file-type', '#36516e', '#6a9fd8'),
  tsx = look ('atom', '#265562', '#61dafb'),
  javascript = look ('file-code', '#575120', '#f1e05a'),
  jsx = look ('atom', '#265562', '#61dafb'),
  python = look ('file-code', '#2d5372', '#4f8dbf'),
  go = look ('file-code', '#00586e', '#00add8'),
  c = look ('file-code', '#2d5182', '#599eff'),
  header = look ('file-code', '#5e4474', '#a277c5'),
  cpp = look ('file-code', '#8d2b48', '#f34b7d'),
  csharp = look ('hash', '#743b71', '#b074ac'),
  fsharp = look ('hash', '#225571', '#3f90bd'),
  java = look ('coffee', '#6f4810', '#b67c29'),
  kotlin = look ('file-code', '#5b428a', '#a97bff'),
  scala = look ('file-code', '#982220', '#e35b59'),
  groovy = look ('file-code', '#255567', '#4298b8'),
  clojure = look ('file-code', '#325a19', '#63b132'),
  ruby = look ('gem', '#972621', '#d8655f'),
  php = look ('file-code', '#494f67', '#8892bf'),
  perl = look ('file-code', '#39457e', '#7e86ab'),
  swift = look ('bird', '#8e3021', '#f05138'),
  dart = look ('file-code', '#1c5670', '#40c4ff'),
  zig = look ('zap', '#6d480d', '#f7a41d'),
  nim = look ('crown', '#574f1c', '#ffe953'),
  elixir = look ('droplet', '#5e4474', '#a277c5'),
  erlang = look ('file-code', '#882a70', '#c865af'),
  haskell = look ('sigma', '#713e6e', '#aa78a7'),
  elm = look ('tangent', '#2d5560', '#60b5cc'),
  ocaml = look ('file-code', '#7c3f04', '#ef7a08'),
  r = look ('chart-line', '#1c508e', '#528acf'),
  julia = look ('circle-dot', '#634471', '#a676bd'),
  nix = look ('snowflake', '#484891', '#7e7eff'),
  terraform = look ('layers', '#67379e', '#9f75ce'),
  protobuf = look ('file-code', '#2d5372', '#4f8dbf'),
  notebook = look ('notebook-pen', '#7e3d14', '#f37626'),
  tex = look ('sigma', '#385915', '#77905d'),
  json = look ('braces', '#53531b', '#cbcb41'),
  ['json-lines'] = look ('braces', '#53531b', '#cbcb41'),
  yaml = look ('list-tree', '#7e3b3d', '#e56b6f'),
  toml = look ('settings', '#754428', '#bd774d'),
  config = look ('sliders-horizontal', '#4d5056', '#9aa1ad'),
  xml = look ('code-xml', '#853817', '#f1662a'),
  env = look ('key-round', '#574f17', '#ecd53f'),
  html = look ('code-xml', '#8f3018', '#e65c3a'),
  css = look ('palette', '#21527a', '#42a5f5'),
  sass = look ('palette', '#773c59', '#cd6799'),
  less = look ('palette', '#1d365d', '#7c8aa1'),
  vue = look ('triangle', '#205a40', '#41b883'),
  svelte = look ('flame', '#992500', '#ff3e00'),
  astro = look ('rocket', '#8c3301', '#ff5d01'),
  graphql = look ('share-2', '#9b0069', '#e942b3'),
  wasm = look ('binary', '#4c3bb4', '#8776f3'),
  markdown = look ('book-open', '#2d5566', '#519aba'),
  mdx = look ('book-open', '#674912', '#fcb32c'),
  text = look ('file-text', '#4b4f56', '#a0a8b8'),
  pdf = look ('file-text', '#972623', '#e95551'),
  table = look ('sheet', '#265b28', '#43a047'),
  spreadsheet = look ('sheet', '#265b28', '#43a047'),
  database = look ('database', '#714600', '#e38c00'),
  log = look ('scroll-text', '#49505c', '#8d9ab0'),
  diff = look ('file-diff', '#205a40', '#41b883'),
  shell = look ('terminal', '#355720', '#89e051'),
  ['windows-shell'] = look ('terminal', '#2d4e89', '#5391fe'),
  wgsl = look ('sparkles', '#5b4582', '#b388ff'),
  glsl = look ('sparkles', '#5b4582', '#b388ff'),
  svg = look ('pen-tool', '#6b4a19', '#ffb13b'),
  image = look ('image', '#5e4474', '#a277c5'),
  audio = look ('music', '#833b00', '#ef6c00'),
  midi = look ('piano', '#833b00', '#ef6c00'),
  ['audio-plugin'] = look ('audio-waveform', '#833b00', '#ef6c00'),
  video = look ('video', '#74450e', '#fd971f'),
  font = look ('type', '#87363b', '#ec5f67'),
  archive = look ('archive', '#505314', '#afb42b'),
  binary = look ('cpu', '#4d5056', '#9aa1ad'),
  key = look ('key-round', '#5f4e1a', '#e2b93d'),
  lock = look ('lock', '#4d5056', '#9aa1ad'),
  graph = look ('workflow', '#4d439e', '#8475ff'),
  ['code-block'] = look ('blocks', '#4d439e', '#8475ff'),
  ['proteus-manifest'] = look ('puzzle', '#4d439e', '#8475ff'),
  test = look ('flask-conical', '#3d5621', '#8bc34a'),
  npm = look ('package', '#863829', '#e05f46'),
  ['npm-lock'] = look ('lock', '#863829', '#e05f46'),
  npmrc = look ('settings', '#863829', '#e05f46'),
  tsconfig = look ('settings', '#215287', '#4e8bce'),
  cargo = look ('package', '#644a3b', '#dea584'),
  ['cargo-lock'] = look ('lock', '#644a3b', '#dea584'),
  ['go-module'] = look ('package', '#00586e', '#00add8'),
  ['python-project'] = look ('package', '#5e4e16', '#ffd43b'),
  gem = look ('gem', '#972621', '#d8655f'),
  build = look ('hammer', '#7b411c', '#e37933'),
  docker = look ('container', '#145282', '#2496ed'),
  git = look ('git-branch', '#8e2e1d', '#f15034'),
  ci = look ('git-branch', '#833914', '#fc6d26'),
  readme = look ('info', '#21527a', '#42a5f5'),
  license = look ('scale', '#5d4e03', '#d4b106'),
  changelog = look ('history', '#3d5621', '#8bc34a'),
  editorconfig = look ('sliders-horizontal', '#4d5056', '#9aa1ad'),
  prettier = look ('paintbrush', '#295656', '#56b3b4'),
  eslint = look ('shield-check', '#49498a', '#8080f2'),
  vite = look ('zap', '#7b22a5', '#c64efe'),
  stylua = look ('paintbrush', '#2a536c', '#51a0cf'),
  selene = look ('shield-check', '#2a536c', '#51a0cf'),
  luarc = look ('settings', '#2a536c', '#51a0cf'),
  source = folder ('folder-code', '#23566d', '#4fc3f7'),
  tests = folder ('folder-check', '#3d5621', '#8bc34a'),
  dependencies = folder ('folder-archive', '#465256', '#7a8b91'),
  ['git-folder'] = folder ('folder-git', '#8e2e1d', '#f15034'),
  ['ci-folder'] = folder ('folder-git-2', '#4d5056', '#9aa1ad'),
  docs = folder ('folder-pen', '#21527a', '#42a5f5'),
  assets = folder ('folder-heart', '#6b4a19', '#ffb13b'),
  output = folder ('folder-output', '#7c3e3e', '#e57373'),
  scripts = folder ('folder-cog', '#66491f', '#ffb74d'),
  ['config-folder'] = folder ('folder-cog', '#4d5056', '#9aa1ad'),
  proteus = folder ('folder-kanban', '#4d439e', '#8475ff'),
  graphs = folder ('folder-tree', '#4d439e', '#8475ff'),
  data = folder ('folder-archive', '#714600', '#e38c00'),
  tauri = folder ('folder-code', '#634b13', '#ffc131'),
}

---@type Proteus.Plugin
return {
  name = 'Vivid Icons',
  description = 'A file icon pack: a Lucide icon for each kind of file, in the colors each language is known by.',
  version = '2.0.0',
  requires = {
    proteus = '>=0.2.0',
    features = { 'permissions', 'icons', 'file-kinds' },
  },
  permissions = {},
  depends = { 'core.icons' },
  activate = function (app)
    app.use ('icons').register ({
      id = PACK,
      name = 'Vivid',
      description = 'Colored icons for each language',
      file = { icon = 'file' },
      folder = folder ('folder', '#485257', '#90a4ae'),
      kinds = KINDS,
    })
  end,
}
