-- icons.badges: an icon pack of small letter badges, such as TS, RS and MD, in the color
-- theme's own syntax colors. It follows the color theme: switch the theme, and the badges
-- change with it.
--
-- It registers the pack with core.icons, then ties every kind of file to its badge as a file
-- association of the kind `icon`, through core.files. Pick it with View > Choose File Icons,
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

---Kinds of files by extension: the extensions, the badge's letters, and its color. A row with
---`icon` shows that Lucide icon instead of letters.
---@type { [1]: string[], [2]: string, [3]: string, icon?: string }[]
local EXTENSIONS = {
  { { 'lua', 'luau' }, 'LU', FUNCTION },
  { { 'rs' }, 'RS', NUMBER },
  { { 'ts', 'mts', 'cts' }, 'TS', FUNCTION },
  { { 'd.ts' }, 'DTS', FAINT },
  { { 'tsx' }, 'TSX', BUILTIN },
  { { 'js', 'mjs', 'cjs' }, 'JS', PROPERTY },
  { { 'jsx' }, 'JSX', BUILTIN },
  { { 'py', 'pyi' }, 'PY', PROPERTY },
  { { 'go' }, 'GO', BUILTIN },
  { { 'c' }, 'C', FUNCTION },
  { { 'h', 'hpp', 'hh' }, 'H', KEYWORD },
  { { 'cpp', 'cc', 'cxx' }, 'C++', CONSTANT },
  { { 'cs' }, 'C#', KEYWORD },
  { { 'java' }, 'JV', NUMBER },
  { { 'kt', 'kts' }, 'KT', KEYWORD },
  { { 'rb' }, 'RB', DANGER },
  { { 'php' }, 'PHP', KEYWORD },
  { { 'swift' }, 'SW', NUMBER },
  { { 'dart' }, 'DT', BUILTIN },
  { { 'zig' }, 'ZIG', PROPERTY },
  { { 'ex', 'exs' }, 'EX', KEYWORD },
  { { 'hs' }, 'HS', KEYWORD },
  { { 'json', 'jsonc', 'json5' }, '{}', PROPERTY },
  { { 'yaml', 'yml' }, 'YML', STRING },
  { { 'toml' }, 'TML', NUMBER },
  { { 'ini', 'cfg', 'conf' }, 'CFG', MUTED },
  { { 'xml', 'plist' }, 'XML', CONSTANT },
  { { 'html', 'htm' }, '<>', CONSTANT },
  { { 'css' }, 'CSS', FUNCTION },
  { { 'scss', 'sass' }, 'SC', KEYWORD },
  { { 'less' }, 'LS', KEYWORD },
  { { 'vue' }, 'VUE', SUCCESS },
  { { 'svelte' }, 'SV', CONSTANT },
  { { 'md', 'markdown' }, 'MD', BUILTIN },
  { { 'mdx' }, 'MDX', BUILTIN },
  { { 'txt', 'rst' }, 'TXT', MUTED },
  { { 'pdf' }, 'PDF', DANGER },
  { { 'csv', 'tsv' }, 'CSV', STRING },
  { { 'xlsx', 'xls', 'ods' }, 'XLS', SUCCESS },
  { { 'sql', 'db', 'sqlite', 'sqlite3' }, 'SQL', OPERATOR },
  { { 'graphql', 'gql' }, 'GQL', CONSTANT },
  { { 'sh', 'bash', 'zsh', 'fish' }, '$', SUCCESS },
  { { 'ps1', 'bat', 'cmd' }, '>', FUNCTION },
  { { 'wgsl' }, 'WG', KEYWORD },
  { { 'glsl', 'frag', 'vert', 'hlsl' }, 'GL', KEYWORD },
  { { 'svg' }, 'SVG', PROPERTY },
  { { 'ttf', 'otf', 'woff', 'woff2' }, 'Aa', MUTED },
  { { 'diff', 'patch' }, '+-', SUCCESS },
  { { 'wasm' }, 'WA', KEYWORD },
  { { 'env' }, 'ENV', PROPERTY },
  { { 'log' }, 'LOG', FAINT },
  {
    { 'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'ico', 'avif' },
    '',
    KEYWORD,
    icon = 'image',
  },
  { { 'mp3', 'wav', 'ogg', 'flac', 'm4a' }, '', CONSTANT, icon = 'music' },
  { { 'mp4', 'mov', 'webm', 'mkv', 'avi' }, '', CONSTANT, icon = 'video' },
  {
    { 'zip', 'tar', 'gz', 'tgz', '7z', 'rar', 'xz' },
    '',
    MUTED,
    icon = 'archive',
  },
  { { 'lock' }, '', FAINT, icon = 'lock' },
  -- Proteus's own files.
  { { 'graph.json' }, '', ACCENT, icon = 'workflow' },
  { { 'block.lua' }, '', ACCENT, icon = 'blocks' },
}

---Files known by their whole name.
---@type { [1]: string[], [2]: string, [3]: string, icon?: string }[]
local NAMES = {
  { { 'package.json' }, 'NPM', DANGER },
  {
    { 'package-lock.json', 'yarn.lock', 'pnpm-lock.yaml' },
    '',
    FAINT,
    icon = 'lock',
  },
  { { 'tsconfig.json', 'jsconfig.json' }, 'TS', MUTED },
  { { 'Cargo.toml' }, 'CRG', NUMBER },
  { { 'go.mod', 'go.sum' }, 'MOD', BUILTIN },
  { { 'Makefile', 'CMakeLists.txt', 'justfile' }, 'MK', CONSTANT },
  { { 'Dockerfile', 'docker-compose.yml', 'compose.yaml' }, 'DK', FUNCTION },
  {
    { '.gitignore', '.gitattributes', '.gitmodules', '.gitkeep' },
    'GIT',
    DANGER,
  },
  { { 'README.md', 'README.txt', 'README' }, '', ACCENT, icon = 'info' },
  { { 'LICENSE', 'LICENSE.md', 'LICENSE.txt', 'COPYING' }, 'LIC', PROPERTY },
  { { 'proteus.json' }, '', ACCENT, icon = 'puzzle' },
  { { '.env', '.env.local', '.env.example' }, 'ENV', PROPERTY },
}

---Folders known by name: the names, the icon while closed, the color.
---@type { [1]: string[], [2]: string, [3]: string }[]
local FOLDERS = {
  { { 'src', 'lib', 'source' }, 'folder-code', ACCENT },
  { { 'test', 'tests', '__tests__', 'spec' }, 'folder-check', SUCCESS },
  { { 'node_modules', 'vendor' }, 'folder-archive', FAINT },
  { { '.git', '.github', '.gitlab' }, 'folder-git', DANGER },
  { { 'dist', 'build', 'out', 'target' }, 'folder-output', FAINT },
  { { '.proteus', 'plugins' }, 'folder-kanban', ACCENT },
}

---@type Proteus.Plugin
return {
  name = 'Letter Badges',
  description = 'A file icon pack of small letter badges, such as TS and MD, drawn in the syntax colors of the color theme.',
  version = '1.0.0',
  requires = { proteus = '>=0.2.0', features = { 'permissions', 'icons' } },
  permissions = {},
  depends = { 'core.icons', 'core.files' },
  activate = function (app)
    local files = app.use ('files')
    app.use ('icons').register ({
      id = PACK,
      name = 'Letter Badges',
      description = 'Letters in the syntax colors of the color theme',
      file = { icon = 'file', color = FAINT },
      folder = { icon = 'folder', open = 'folder-open', color = MUTED },
    })

    ---@param pattern string
    ---@param value Proteus.IconAssociation
    local function associate (pattern, value)
      value.pack = PACK
      files.associate ({ kind = 'icon', pattern = pattern, value = value })
    end

    ---@param row { [1]: string[], [2]: string, [3]: string, icon?: string }
    ---@param pattern fun(name: string): string
    local function add_files (row, pattern)
      for _, name in ipairs (row[1]) do
        if row.icon then
          associate (pattern (name), { icon = row.icon, color = row[3] })
        else
          associate (pattern (name), { text = row[2], color = row[3] })
        end
      end
    end

    for _, row in ipairs (EXTENSIONS) do
      add_files (row, function (ext)
        return '*.' .. ext
      end)
    end
    for _, row in ipairs (NAMES) do
      add_files (row, function (name)
        return name
      end)
    end
    for _, row in ipairs (FOLDERS) do
      for _, name in ipairs (row[1]) do
        associate (
          name,
          { folder = true, icon = row[2], open = 'folder-open', color = row[3] }
        )
      end
    end
  end,
}
