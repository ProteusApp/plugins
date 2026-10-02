-- icons.badges: an icon pack of small letter badges, such as TS, RS and MD, in the color
-- theme's own syntax colors. It follows the color theme: switch the theme, and the badges
-- change with it.
--
-- It registers the pack with core.icons, with a badge for every kind of file and an icon for
-- every kind of folder in the app's lib/file_kinds.lua. Pick it with View > Choose File Icons,
-- or set `icon_pack` to `badges`.

local PACK = 'badges'

-- The theme variables the badges are drawn in, so each theme colors them its own way.
local KEYWORD = 'var(--syn-keyword)'
local STRING = 'var(--syn-string)'
local NUMBER = 'var(--syn-number)'
local CONSTANT = 'var(--syn-constant)'
local FUNCTION = 'var(--syn-function)'
local OPERATOR = 'var(--syn-operator)'
local PROPERTY = 'var(--syn-property)'
local BUILTIN = 'var(--syn-builtin)'
local ACCENT = 'var(--accent)'
local DANGER = 'var(--danger)'
local SUCCESS = 'var(--success)'
local MUTED = 'var(--fg-muted)'
local FAINT = 'var(--fg-faint)'

---A badge of up to three letters.
---@param text string
---@param color string
---@return Proteus.FileIcon
local function badge (text, color)
  return { text = text, color = color }
end

---A Lucide icon, for kinds that read better as a picture.
---@param icon string
---@param color string
---@return Proteus.FileIcon
local function picture (icon, color)
  return { icon = icon, color = color }
end

---A folder's icon, which shows `folder-open` while the folder is open.
---@param icon string
---@param color string
---@return Proteus.FileIcon
local function folder (icon, color)
  return { icon = icon, open = 'folder-open', color = color }
end

---How each kind of file and folder looks, by its id in lib/file_kinds.lua.
---@type table<string, Proteus.FileIcon>
local KINDS = {
  lua = badge ('LU', FUNCTION),
  rust = badge ('RS', NUMBER),
  typescript = badge ('TS', FUNCTION),
  ['typescript-types'] = badge ('DTS', FAINT),
  tsx = badge ('TSX', BUILTIN),
  javascript = badge ('JS', PROPERTY),
  jsx = badge ('JSX', BUILTIN),
  python = badge ('PY', PROPERTY),
  go = badge ('GO', BUILTIN),
  c = badge ('C', FUNCTION),
  header = badge ('H', KEYWORD),
  cpp = badge ('C++', CONSTANT),
  csharp = badge ('C#', KEYWORD),
  fsharp = badge ('F#', FUNCTION),
  java = badge ('JV', NUMBER),
  kotlin = badge ('KT', KEYWORD),
  scala = badge ('SC', DANGER),
  groovy = badge ('GR', FUNCTION),
  clojure = badge ('CLJ', SUCCESS),
  ruby = badge ('RB', DANGER),
  php = badge ('PHP', KEYWORD),
  perl = badge ('PL', FUNCTION),
  swift = badge ('SW', NUMBER),
  dart = badge ('DT', BUILTIN),
  zig = badge ('ZIG', PROPERTY),
  nim = badge ('NIM', PROPERTY),
  elixir = badge ('EX', KEYWORD),
  erlang = badge ('ERL', CONSTANT),
  haskell = badge ('HS', KEYWORD),
  elm = badge ('ELM', BUILTIN),
  ocaml = badge ('ML', NUMBER),
  r = badge ('R', FUNCTION),
  julia = badge ('JL', KEYWORD),
  nix = badge ('NIX', FUNCTION),
  terraform = badge ('TF', KEYWORD),
  protobuf = badge ('PB', FUNCTION),
  notebook = badge ('NB', NUMBER),
  tex = badge ('TEX', SUCCESS),
  json = badge ('{}', PROPERTY),
  ['json-lines'] = badge ('{}L', PROPERTY),
  yaml = badge ('YML', STRING),
  toml = badge ('TML', NUMBER),
  config = badge ('CFG', MUTED),
  xml = badge ('XML', CONSTANT),
  env = badge ('ENV', PROPERTY),
  html = badge ('<>', CONSTANT),
  css = badge ('CSS', FUNCTION),
  sass = badge ('SC', KEYWORD),
  less = badge ('LS', KEYWORD),
  vue = badge ('VUE', SUCCESS),
  svelte = badge ('SV', CONSTANT),
  astro = badge ('AST', NUMBER),
  graphql = badge ('GQL', CONSTANT),
  wasm = badge ('WA', KEYWORD),
  markdown = badge ('MD', BUILTIN),
  mdx = badge ('MDX', BUILTIN),
  text = badge ('TXT', MUTED),
  pdf = badge ('PDF', DANGER),
  table = badge ('CSV', STRING),
  spreadsheet = badge ('XLS', SUCCESS),
  database = badge ('SQL', OPERATOR),
  log = badge ('LOG', FAINT),
  diff = badge ('+-', SUCCESS),
  shell = badge ('$', SUCCESS),
  ['windows-shell'] = badge ('>', FUNCTION),
  wgsl = badge ('WG', KEYWORD),
  glsl = badge ('GL', KEYWORD),
  svg = badge ('SVG', PROPERTY),
  image = picture ('image', KEYWORD),
  audio = picture ('music', CONSTANT),
  midi = badge ('MID', CONSTANT),
  ['audio-plugin'] = badge ('PLG', CONSTANT),
  video = picture ('video', CONSTANT),
  font = badge ('Aa', MUTED),
  archive = picture ('archive', MUTED),
  binary = badge ('BIN', MUTED),
  key = picture ('key-round', PROPERTY),
  lock = picture ('lock', FAINT),
  graph = picture ('workflow', ACCENT),
  ['code-block'] = picture ('blocks', ACCENT),
  ['proteus-manifest'] = picture ('puzzle', ACCENT),
  test = badge ('T', SUCCESS),
  npm = badge ('NPM', DANGER),
  ['npm-lock'] = picture ('lock', FAINT),
  npmrc = badge ('NPM', MUTED),
  tsconfig = badge ('TS', MUTED),
  cargo = badge ('CRG', NUMBER),
  ['cargo-lock'] = picture ('lock', FAINT),
  ['go-module'] = badge ('MOD', BUILTIN),
  ['python-project'] = badge ('PY', MUTED),
  gem = badge ('GEM', DANGER),
  build = badge ('MK', CONSTANT),
  docker = badge ('DK', FUNCTION),
  git = badge ('GIT', DANGER),
  ci = badge ('CI', DANGER),
  readme = picture ('info', ACCENT),
  license = badge ('LIC', PROPERTY),
  changelog = badge ('LOG', SUCCESS),
  editorconfig = badge ('EC', MUTED),
  prettier = badge ('PR', BUILTIN),
  eslint = badge ('ES', KEYWORD),
  vite = badge ('VT', KEYWORD),
  stylua = badge ('STY', FUNCTION),
  selene = badge ('SEL', FUNCTION),
  luarc = badge ('LRC', FUNCTION),
  source = folder ('folder-code', ACCENT),
  tests = folder ('folder-check', SUCCESS),
  dependencies = folder ('folder-archive', FAINT),
  ['git-folder'] = folder ('folder-git', DANGER),
  ['ci-folder'] = folder ('folder-git', DANGER),
  docs = folder ('folder-pen', BUILTIN),
  assets = folder ('folder-heart', PROPERTY),
  output = folder ('folder-output', FAINT),
  scripts = folder ('folder-cog', FUNCTION),
  ['config-folder'] = folder ('folder-cog', MUTED),
  proteus = folder ('folder-kanban', ACCENT),
  graphs = folder ('folder-tree', ACCENT),
  data = folder ('folder-archive', NUMBER),
  tauri = folder ('folder-code', NUMBER),
}

---@type Proteus.Plugin
return {
  name = 'Letter Badges',
  description = 'A file icon pack of small letter badges, such as TS and MD, drawn in the syntax colors of the color theme.',
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
      name = 'Letter Badges',
      description = 'Letters in the syntax colors of the color theme',
      file = { icon = 'file', color = FAINT },
      folder = folder ('folder', MUTED),
      kinds = KINDS,
    })
  end,
}
