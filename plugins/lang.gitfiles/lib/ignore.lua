-- ignore: help for .gitignore files. It completes common patterns, and its hover text says
-- what a line matches. Nothing here calls the host, so the tests reach it.

---A pattern many projects ignore, and why.
---@class LangGitfiles.Pattern
---@field pattern string
---@field doc string

---@class LangGitfiles.IgnoreModule
local M = {}

---@type LangGitfiles.Pattern[]
M.common = {
  {
    pattern = 'node_modules/',
    doc = 'Packages that npm, Yarn or pnpm installed. `npm install` brings them back.',
  },
  {
    pattern = 'dist/',
    doc = 'Files a build wrote. The build makes them again.',
  },
  {
    pattern = 'build/',
    doc = 'Files a build wrote. The build makes them again.',
  },
  { pattern = 'out/', doc = 'Files a compiler or a build wrote.' },
  {
    pattern = 'target/',
    doc = 'What Cargo or Maven built. It grows large, and the build makes it again.',
  },
  { pattern = 'bin/', doc = 'Programs a build wrote, as in Go and .NET.' },
  { pattern = 'obj/', doc = "The files .NET's compiler keeps between builds." },
  { pattern = 'coverage/', doc = 'Reports from a test coverage tool.' },
  {
    pattern = '.cache/',
    doc = 'Files tools keep to work faster next time.',
  },
  {
    pattern = '*.log',
    doc = 'Log files, such as `npm-debug.log`. Programs write them as they run.',
  },
  {
    pattern = '*.tmp',
    doc = 'Temporary files that programs leave behind.',
  },
  {
    pattern = '.env',
    doc = 'Settings for one computer, which often hold passwords and keys. Keep them out of the repository.',
  },
  {
    pattern = '.env.*',
    doc = 'More `.env` files, such as `.env.local`. Add `!.env.example` after this line to keep the example.',
  },
  {
    pattern = '.DS_Store',
    doc = 'The file macOS writes in each folder to remember how Finder shows it.',
  },
  {
    pattern = 'Thumbs.db',
    doc = 'The picture previews Windows Explorer keeps in a folder.',
  },
  { pattern = 'desktop.ini', doc = 'How Windows Explorer shows a folder.' },
  {
    pattern = '.vscode/',
    doc = "VS Code's settings for this folder. Some projects keep `.vscode/extensions.json` with `!.vscode/extensions.json`.",
  },
  {
    pattern = '.idea/',
    doc = 'The settings JetBrains editors, such as IntelliJ IDEA, keep for a project.',
  },
  { pattern = '*.swp', doc = "Vim's swap files, for a file that is open." },
  { pattern = '*~', doc = 'Backup copies that editors such as Emacs leave.' },
  {
    pattern = '__pycache__/',
    doc = 'The compiled Python files Python writes next to the code.',
  },
  { pattern = '*.pyc', doc = 'Compiled Python files.' },
  {
    pattern = '.venv/',
    doc = 'A Python virtual environment, with the packages pip installed into it.',
  },
  {
    pattern = '*.class',
    doc = 'Compiled Java classes. The build makes them again.',
  },
  { pattern = '*.o', doc = 'Object files a C or C++ compiler wrote.' },
  { pattern = '*.exe', doc = 'Windows programs a build wrote.' },
  {
    pattern = '*.local',
    doc = 'Files for one computer, such as `.env.local`.',
  },
  {
    pattern = '.terraform/',
    doc = 'The providers and modules `terraform init` downloaded.',
  },
}

-- The common patterns by their text, without a `/` at either end.
local BY_NAME = {} ---@type table<string, string>
for _, p in ipairs (M.common) do
  BY_NAME[(p.pattern:gsub ('^/', ''):gsub ('/$', ''))] = p.doc
end

---The pattern a line holds: without the spaces Git ignores at its end, unless a backslash
---keeps one. Nil for a blank line or a comment.
---@param line string
---@return string?
function M.pattern (line)
  local text = line:gsub ('\r$', '')
  if text:match ('^%s*$') or text:sub (1, 1) == '#' then
    return nil
  end
  local kept = text:match ('^(.-\\ )%s*$')
  return kept or (text:gsub ('%s+$', ''))
end

---What a line of a .gitignore file matches, in Markdown. Nil for a blank line.
---@param line string
---@return string?
function M.explain (line)
  local text = line:gsub ('\r$', '')
  if text:match ('^%s*$') then
    return nil
  end
  if text:sub (1, 1) == '#' then
    return 'A comment. Git skips this line.'
  end
  local pattern = M.pattern (text) or ''
  local out = {} ---@type string[]
  local body = pattern
  local negate = body:sub (1, 1) == '!'
  -- A backslash lets a pattern start with `#` or `!` as plain characters.
  if negate or body:match ('^\\[#!]') then
    body = body:sub (2)
  end
  local known = BY_NAME[(body:gsub ('^/', ''):gsub ('/$', ''))]
  out[#out + 1] = '**`' .. pattern .. '`**'
  if known then
    out[#out + 1] = known
  end
  local sentences = {} ---@type string[]
  if negate then
    sentences[#sentences + 1] =
      'The `!` brings back files that an earlier line ignored. It cannot bring back a file inside an ignored folder, since Git never looks in that folder.'
  end
  local folders_only = body:sub (-1) == '/'
  local trimmed = folders_only and body:sub (1, -2) or body
  if folders_only then
    sentences[#sentences + 1] =
      'The `/` at the end matches folders only, with everything inside them.'
  end
  if trimmed:sub (1, 3) == '**/' then
    sentences[#sentences + 1] =
      'The `**/` at the start matches it in any folder.'
  elseif trimmed:find ('/', 1, true) then
    sentences[#sentences + 1] =
      'It holds a `/`, so it matches from the folder that holds this file, not anywhere below.'
  else
    sentences[#sentences + 1] =
      'It matches in this folder and in every folder below it.'
  end
  if trimmed:sub (-3) == '/**' then
    sentences[#sentences + 1] =
      'The `/**` at the end matches everything inside.'
  end
  if trimmed:find ('/**/', 1, true) then
    sentences[#sentences + 1] = 'A `/**/` matches any number of folders.'
  end
  local plain = trimmed:gsub ('%*%*', '')
  if plain:find ('*', 1, true) then
    sentences[#sentences + 1] = 'A `*` matches any characters except `/`.'
  end
  if plain:find ('?', 1, true) then
    sentences[#sentences + 1] = 'A `?` matches one character except `/`.'
  end
  if plain:find ('%[.-%]') then
    sentences[#sentences + 1] =
      'A `[...]` matches one character of the ones listed.'
  end
  out[#out + 1] = table.concat (sentences, ' ')
  return table.concat (out, '\n\n')
end

---What completion replaces: the pattern typed so far on the line, after any `!`. Nil after a
---space, or in a comment.
---@param line string
---@param column integer Counted from 0.
---@return { word: string, from: integer }?
function M.at (line, column)
  local before = line:sub (1, column)
  local lead, word = before:match ('^(%s*!?)(%S*)$')
  if not lead or before:match ('^%s*#') then
    return nil
  end
  return { word = word, from = #lead }
end

---The line that ignores one file, from its path below the folder of the .gitignore. The `/`
---at the start ties it to that place, and a backslash keeps each wildcard character plain.
---@param path string Such as `src/notes.txt`.
---@return string
function M.entry (path)
  local line = '/' .. path:gsub ('\\', '/'):gsub ('^/+', '')
  line = line:gsub ('[%*%?%[]', '\\%0')
  -- Git drops spaces at the end of a line, unless a backslash keeps them.
  return (line:gsub (' $', '\\ '))
end

---The completion list.
---@return Proteus.CompletionItem[]
function M.items ()
  local items = {} ---@type Proteus.CompletionItem[]
  for _, p in ipairs (M.common) do
    items[#items + 1] = {
      label = p.pattern,
      kind = 'constant',
      documentation = p.doc,
    }
  end
  return items
end

return M
