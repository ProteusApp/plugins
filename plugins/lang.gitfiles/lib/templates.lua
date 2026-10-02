-- templates: .gitignore templates for common languages, editors and systems, and the text a
-- .gitignore gets when one is added. Nothing here calls the host, so the tests reach it.

---@class LangGitfiles.Template
---@field name string
---@field detail string What it covers, shown in the list.
---@field lines string[] The patterns. A line that starts with `#` is a comment.

---@class LangGitfiles.TemplatesModule
local M = {}

---@type LangGitfiles.Template[]
M.list = {
  {
    name = 'Node',
    detail = 'npm, Yarn and pnpm packages, builds and logs',
    lines = {
      'node_modules/',
      'dist/',
      'build/',
      'coverage/',
      '.cache/',
      '.parcel-cache/',
      '.next/',
      '.nuxt/',
      '.vite/',
      '.turbo/',
      '*.tsbuildinfo',
      '.eslintcache',
      '.npm/',
      '.yarn/cache/',
      '.pnp.*',
      'npm-debug.log*',
      'yarn-debug.log*',
      'yarn-error.log*',
      'pnpm-debug.log*',
      '.env',
      '.env.*',
      '!.env.example',
    },
  },
  {
    name = 'Python',
    detail = 'compiled files, virtual environments and tool caches',
    lines = {
      '__pycache__/',
      '*.py[cod]',
      '*.so',
      'build/',
      'dist/',
      '*.egg-info/',
      '.eggs/',
      '.venv/',
      'venv/',
      'env/',
      '.pytest_cache/',
      '.mypy_cache/',
      '.ruff_cache/',
      '.tox/',
      '.nox/',
      '.coverage',
      'htmlcov/',
      '.ipynb_checkpoints/',
      '.env',
    },
  },
  {
    name = 'Rust',
    detail = 'what Cargo builds',
    lines = {
      'target/',
      '# Libraries leave Cargo.lock out. Programs keep it.',
      '# Cargo.lock',
      '**/*.rs.bk',
      '*.pdb',
    },
  },
  {
    name = 'Go',
    detail = 'programs, test files and the work file',
    lines = {
      '*.exe',
      '*.exe~',
      '*.dll',
      '*.so',
      '*.dylib',
      '*.test',
      '*.out',
      'bin/',
      'vendor/',
      'go.work',
      'go.work.sum',
    },
  },
  {
    name = 'Java',
    detail = 'classes, archives, and Maven and Gradle builds',
    lines = {
      '*.class',
      '*.jar',
      '*.war',
      '*.ear',
      '*.log',
      'hs_err_pid*',
      'replay_pid*',
      'target/',
      'build/',
      '.gradle/',
      '!gradle/wrapper/gradle-wrapper.jar',
      'out/',
    },
  },
  {
    name = 'Lua',
    detail = 'compiled chunks, LuaRocks trees and test output',
    lines = {
      'luac.out',
      '*.luac',
      '*.o',
      '*.so',
      '*.dll',
      'lua_modules/',
      '.luarocks/',
      '*.rock',
      '*.src.rock',
      'luacov.*.out',
    },
  },
  {
    name = 'C and C++',
    detail = 'object files, libraries, programs and CMake builds',
    lines = {
      '*.o',
      '*.obj',
      '*.a',
      '*.lib',
      '*.so',
      '*.dylib',
      '*.dll',
      '*.exe',
      '*.out',
      '*.d',
      'build/',
      'cmake-build-*/',
      'CMakeCache.txt',
      'CMakeFiles/',
      'compile_commands.json',
    },
  },
  {
    name = '.NET',
    detail = 'builds, packages and Visual Studio files',
    lines = {
      'bin/',
      'obj/',
      '*.user',
      '*.suo',
      '.vs/',
      'packages/',
      '*.nupkg',
      'TestResults/',
    },
  },
  {
    name = 'macOS',
    detail = 'Finder and system files',
    lines = {
      '.DS_Store',
      '.AppleDouble',
      '.LSOverride',
      '._*',
      '.Spotlight-V100',
      '.Trashes',
      '.fseventsd',
    },
  },
  {
    name = 'Windows',
    detail = 'Explorer files, shortcuts and dumps',
    lines = {
      'Thumbs.db',
      'Thumbs.db:encryptable',
      'ehthumbs.db',
      'desktop.ini',
      '$RECYCLE.BIN/',
      '*.lnk',
      '*.stackdump',
    },
  },
  {
    name = 'Linux',
    detail = 'backups, trash and file manager files',
    lines = {
      '*~',
      '.fuse_hidden*',
      '.directory',
      '.Trash-*',
      '.nfs*',
    },
  },
  {
    name = 'VS Code',
    detail = 'editor settings, keeping the shared ones',
    lines = {
      '.vscode/*',
      '!.vscode/settings.json',
      '!.vscode/tasks.json',
      '!.vscode/launch.json',
      '!.vscode/extensions.json',
      '*.code-workspace',
      '.history/',
    },
  },
  {
    name = 'JetBrains',
    detail = 'IntelliJ IDEA, PyCharm, Rider and the rest',
    lines = {
      '.idea/',
      '*.iml',
      '*.ipr',
      '*.iws',
      'out/',
      '.idea_modules/',
    },
  },
  {
    name = 'Vim and Emacs',
    detail = 'swap files, backups and sessions',
    lines = {
      '[._]*.s[a-v][a-z]',
      '[._]*.sw[a-p]',
      'Session.vim',
      '*~',
      '\\#*\\#',
      '.\\#*',
    },
  },
}

---@param name string
---@return LangGitfiles.Template?
function M.get (name)
  for _, t in ipairs (M.list) do
    if t.name == name then
      return t
    end
  end
  return nil
end

---The lines a file holds, without spaces at either end.
---@param text string
---@return table<string, true>
local function line_set (text)
  local out = {} ---@type table<string, true>
  for line in (text .. '\n'):gmatch ('([^\n]*)\n') do
    out[(line:gsub ('^%s+', ''):gsub ('%s+$', ''))] = true
  end
  return out
end

---Adds lines to a file's text. A line the file already holds is left out. With a heading,
---the lines go under it, after a blank line. Returns nil when every line is there already.
---@param text string The file's text, or `''` for a new file.
---@param heading string? A comment line, such as `# Node`.
---@param lines string[]
---@return string?
function M.append (text, heading, lines)
  local have = line_set (text)
  local new = {} ---@type string[]
  local patterns = 0
  for _, line in ipairs (lines) do
    local key = (line:gsub ('^%s+', ''):gsub ('%s+$', ''))
    local comment = key:sub (1, 1) == '#'
    if comment or not have[key] then
      new[#new + 1] = line
      if not comment then
        patterns = patterns + 1
        have[key] = true
      end
    end
  end
  if patterns == 0 then
    return nil
  end
  local out = text
  if out ~= '' and out:sub (-1) ~= '\n' then
    out = out .. '\n'
  end
  if heading then
    if out:match ('%S') and not out:match ('\n%s*\n$') then
      out = out .. '\n'
    end
    table.insert (new, 1, heading)
  end
  return out .. table.concat (new, '\n') .. '\n'
end

---The text of a .gitignore with a template added.
---@param text string
---@param template LangGitfiles.Template
---@return string?
function M.add (text, template)
  return M.append (text, '# ' .. template.name, template.lines)
end

return M
