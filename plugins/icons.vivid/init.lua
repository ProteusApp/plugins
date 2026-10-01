-- icons.vivid: an icon pack with a Lucide icon for each kind of file, in the colors each
-- language is known by, and icons for the folders most projects have.
--
-- It registers the pack with core.icons, then ties every kind of file to its icon as a file
-- association of the kind `icon`, through core.files. Pick it with View > Choose File Icons,
-- or set `icon_pack` to `vivid`.

local PACK = 'vivid'

---Kinds of files by extension: the extensions, the Lucide icon, and its color. A longer
---extension, such as `test.ts`, wins over a shorter one.
---@type { [1]: string[], [2]: string, [3]: string }[]
local EXTENSIONS = {
  { { 'lua', 'luau' }, 'moon', '#51a0cf' },
  { { 'rs' }, 'cog', '#dea584' },
  { { 'ts', 'mts', 'cts' }, 'file-type', '#3178c6' },
  { { 'd.ts' }, 'file-type', '#6a9fd8' },
  { { 'js', 'mjs', 'cjs' }, 'file-code', '#f1e05a' },
  { { 'jsx', 'tsx' }, 'atom', '#61dafb' },
  { { 'py', 'pyi' }, 'file-code', '#4b8bbe' },
  { { 'go' }, 'file-code', '#00add8' },
  { { 'c', 'h' }, 'file-code', '#599eff' },
  { { 'cpp', 'cc', 'cxx', 'hpp', 'hh' }, 'file-code', '#f34b7d' },
  { { 'cs' }, 'hash', '#9b4f96' },
  { { 'java' }, 'coffee', '#b07219' },
  { { 'kt', 'kts' }, 'file-code', '#a97bff' },
  { { 'rb' }, 'gem', '#cc342d' },
  { { 'php' }, 'file-code', '#8892bf' },
  { { 'swift' }, 'bird', '#f05138' },
  { { 'dart' }, 'file-code', '#40c4ff' },
  { { 'zig' }, 'zap', '#f7a41d' },
  { { 'ex', 'exs' }, 'droplet', '#a074c4' },
  { { 'hs' }, 'sigma', '#8f4e8b' },
  { { 'json', 'jsonc', 'json5' }, 'braces', '#cbcb41' },
  { { 'yaml', 'yml' }, 'list-tree', '#e56b6f' },
  { { 'toml' }, 'settings', '#b76b3e' },
  { { 'ini', 'cfg', 'conf' }, 'sliders-horizontal', '#9aa1ad' },
  { { 'xml', 'plist' }, 'code-xml', '#f1662a' },
  { { 'html', 'htm' }, 'code-xml', '#e34c26' },
  { { 'css' }, 'palette', '#42a5f5' },
  { { 'scss', 'sass', 'less' }, 'palette', '#cd6799' },
  { { 'vue' }, 'triangle', '#41b883' },
  { { 'svelte' }, 'flame', '#ff3e00' },
  { { 'md', 'markdown', 'mdx' }, 'book-open', '#519aba' },
  { { 'txt', 'rst' }, 'file-text', '#a0a8b8' },
  { { 'pdf' }, 'file-text', '#e53935' },
  { { 'csv', 'tsv', 'xlsx', 'xls', 'ods' }, 'sheet', '#43a047' },
  { { 'sql', 'db', 'sqlite', 'sqlite3' }, 'database', '#e38c00' },
  { { 'graphql', 'gql' }, 'share-2', '#e10098' },
  {
    { 'sh', 'bash', 'zsh', 'fish', 'ps1', 'bat', 'cmd' },
    'terminal',
    '#89e051',
  },
  { { 'wgsl', 'glsl', 'frag', 'vert', 'hlsl' }, 'sparkles', '#b388ff' },
  { { 'svg' }, 'pen-tool', '#ffb13b' },
  {
    { 'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'ico', 'avif' },
    'image',
    '#a074c4',
  },
  { { 'mp3', 'wav', 'ogg', 'flac', 'm4a' }, 'music', '#ef6c00' },
  { { 'mp4', 'mov', 'webm', 'mkv', 'avi' }, 'video', '#fd971f' },
  { { 'ttf', 'otf', 'woff', 'woff2' }, 'type', '#ec5f67' },
  { { 'zip', 'tar', 'gz', 'tgz', '7z', 'rar', 'xz' }, 'archive', '#afb42b' },
  { { 'lock' }, 'lock', '#9aa1ad' },
  { { 'log' }, 'scroll-text', '#8d9ab0' },
  { { 'diff', 'patch' }, 'file-diff', '#41b883' },
  { { 'wasm' }, 'binary', '#654ff0' },
  { { 'env' }, 'key-round', '#ecd53f' },
  -- Proteus's own files.
  { { 'ndg' }, 'workflow', '#7c6cff' },
  { { 'ndb.lua' }, 'blocks', '#7c6cff' },
  -- Tests, whatever the language.
  {
    {
      'test.ts',
      'test.tsx',
      'test.js',
      'test.jsx',
      'test.lua',
      'spec.ts',
      'spec.tsx',
      'spec.js',
      'spec.jsx',
      'spec.lua',
    },
    'flask-conical',
    '#8bc34a',
  },
}

---Files known by their whole name.
---@type { [1]: string[], [2]: string, [3]: string }[]
local NAMES = {
  { { 'package.json' }, 'package', '#e05d44' },
  { { 'package-lock.json', 'yarn.lock', 'pnpm-lock.yaml' }, 'lock', '#e05d44' },
  { { 'tsconfig.json', 'jsconfig.json' }, 'settings', '#3178c6' },
  { { 'Cargo.toml' }, 'package', '#dea584' },
  { { 'Cargo.lock' }, 'lock', '#dea584' },
  { { 'go.mod', 'go.sum' }, 'package', '#00add8' },
  { { 'pyproject.toml', 'requirements.txt', 'Pipfile' }, 'package', '#ffd43b' },
  { { 'Gemfile', 'Gemfile.lock' }, 'gem', '#cc342d' },
  { { 'Makefile', 'CMakeLists.txt', 'justfile' }, 'hammer', '#e37933' },
  {
    { 'Dockerfile', 'docker-compose.yml', 'compose.yaml', '.dockerignore' },
    'container',
    '#2496ed',
  },
  {
    { '.gitignore', '.gitattributes', '.gitmodules', '.gitkeep' },
    'git-branch',
    '#f14e32',
  },
  { { 'README.md', 'README.txt', 'README' }, 'info', '#42a5f5' },
  {
    { 'LICENSE', 'LICENSE.md', 'LICENSE.txt', 'COPYING' },
    'scale',
    '#d4b106',
  },
  { { 'CHANGELOG.md' }, 'history', '#8bc34a' },
  { { '.editorconfig' }, 'sliders-horizontal', '#9aa1ad' },
  {
    { '.prettierrc', '.prettierrc.json', 'prettier.config.js' },
    'paintbrush',
    '#56b3b4',
  },
  { { 'eslint.config.js', '.eslintrc.json' }, 'shield-check', '#8080f2' },
  { { 'vite.config.ts', 'vite.config.js' }, 'zap', '#bd34fe' },
  { { 'stylua.toml', '.stylua.toml' }, 'paintbrush', '#51a0cf' },
  { { 'selene.toml' }, 'shield-check', '#51a0cf' },
  { { '.luarc.json' }, 'settings', '#51a0cf' },
  { { 'proteus.json' }, 'puzzle', '#7c6cff' },
  { { '.env', '.env.local', '.env.example' }, 'key-round', '#ecd53f' },
}

---Folders known by name: the names, the icon while closed, the icon while open, the color.
---@type { [1]: string[], [2]: string, [3]: string, [4]: string }[]
local FOLDERS = {
  { { 'src', 'lib', 'source' }, 'folder-code', 'folder-open', '#4fc3f7' },
  {
    { 'test', 'tests', '__tests__', 'spec' },
    'folder-check',
    'folder-open',
    '#8bc34a',
  },
  { { 'node_modules', 'vendor' }, 'folder-archive', 'folder-open', '#6d8086' },
  { { '.git' }, 'folder-git', 'folder-open', '#f14e32' },
  { { '.github', '.gitlab' }, 'folder-git-2', 'folder-open', '#9aa1ad' },
  { { 'docs', 'doc' }, 'folder-pen', 'folder-open', '#42a5f5' },
  {
    { 'assets', 'images', 'img', 'public', 'static' },
    'folder-heart',
    'folder-open',
    '#ffb13b',
  },
  {
    { 'dist', 'build', 'out', 'target' },
    'folder-output',
    'folder-open',
    '#e57373',
  },
  { { 'scripts', 'bin' }, 'folder-cog', 'folder-open', '#ffb74d' },
  {
    { 'config', '.config', '.vscode', '.cargo' },
    'folder-cog',
    'folder-open',
    '#9aa1ad',
  },
  {
    { '.proteus', 'plugins', 'profiles' },
    'folder-kanban',
    'folder-open',
    '#7c6cff',
  },
  { { 'graphs' }, 'folder-tree', 'folder-open', '#7c6cff' },
  { { 'data' }, 'folder-archive', 'folder-open', '#e38c00' },
  { { 'src-tauri' }, 'folder-code', 'folder-open', '#ffc131' },
}

---@type Proteus.Plugin
return {
  name = 'Vivid Icons',
  description = 'A file icon pack: a Lucide icon for each kind of file, in the colors each language is known by.',
  version = '1.1.0',
  requires = { proteus = '>=0.2.0', features = { 'permissions', 'icons' } },
  permissions = {},
  depends = { 'core.icons', 'core.files' },
  activate = function (app)
    local files = app.use ('files')
    app.use ('icons').register ({
      id = PACK,
      name = 'Vivid',
      description = 'Colored icons for each language',
      file = { icon = 'file' },
      folder = { icon = 'folder', open = 'folder-open', color = '#90a4ae' },
    })

    ---@param pattern string
    ---@param value Proteus.IconAssociation
    local function associate (pattern, value)
      value.pack = PACK
      files.associate ({ kind = 'icon', pattern = pattern, value = value })
    end

    for _, row in ipairs (EXTENSIONS) do
      for _, ext in ipairs (row[1]) do
        associate ('*.' .. ext, { icon = row[2], color = row[3] })
      end
    end
    for _, row in ipairs (NAMES) do
      for _, name in ipairs (row[1]) do
        associate (name, { icon = row[2], color = row[3] })
      end
    end
    for _, row in ipairs (FOLDERS) do
      for _, name in ipairs (row[1]) do
        associate (
          name,
          { folder = true, icon = row[2], open = row[3], color = row[4] }
        )
      end
    end
  end,
}
