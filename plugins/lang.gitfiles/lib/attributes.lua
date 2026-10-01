-- attributes: help for .gitattributes files. A line is a pattern, then attributes, such as
-- `*.sh text eol=lf`. It completes attribute names and their values, and its hover text says
-- what an attribute does. Nothing here calls the host, so the tests reach it.

---One attribute, and the values it takes.
---@class LangGitfiles.Attribute
---@field name string
---@field doc string
---@field values? { [1]: string, [2]: string }[] Each value and what it means.

---Where the cursor is on a line, for completion.
---@class LangGitfiles.AttributeContext
---@field where 'pattern'|'name'|'value'
---@field word string What completion replaces.
---@field from integer Where `word` starts, counted from 0.
---@field name? string The attribute a value is for.

---@class LangGitfiles.AttributesModule
local M = {}

-- The diff drivers Git knows without any setup, each for finding functions in one language.
local DRIVERS = {
  'ada',
  'bash',
  'bibtex',
  'cpp',
  'csharp',
  'css',
  'dts',
  'elixir',
  'fortran',
  'fountain',
  'golang',
  'html',
  'java',
  'kotlin',
  'markdown',
  'matlab',
  'objc',
  'pascal',
  'perl',
  'php',
  'python',
  'ruby',
  'rust',
  'scheme',
  'tex',
}

-- Languages often named in `linguist-language`, as GitHub spells them.
local LANGUAGES = {
  'C',
  'C++',
  'C#',
  'Go',
  'Java',
  'JavaScript',
  'JSON',
  'Lua',
  'Markdown',
  'Python',
  'Ruby',
  'Rust',
  'Shell',
  'Text',
  'TOML',
  'TypeScript',
  'YAML',
}

local driver_values = {} ---@type { [1]: string, [2]: string }[]
for _, d in ipairs (DRIVERS) do
  driver_values[#driver_values + 1] =
    { d, 'Shows the function or section each change is in, for ' .. d .. '.' }
end

local language_values = {} ---@type { [1]: string, [2]: string }[]
for _, l in ipairs (LANGUAGES) do
  language_values[#language_values + 1] =
    { l, 'GitHub shows and counts the files as ' .. l .. '.' }
end

---@type LangGitfiles.Attribute[]
M.list = {
  {
    name = 'text',
    doc = 'Marks the files as text. Git stores them with LF line endings and writes them out with the line endings `eol` or `core.eol` asks for. `-text` leaves line endings as they are.',
    values = {
      {
        'auto',
        'Git looks at each file and treats it as text unless it holds binary data. `* text=auto` suits most repositories.',
      },
    },
  },
  {
    name = 'eol',
    doc = 'The line endings Git writes the files out with. It also marks them as text.',
    values = {
      {
        'lf',
        'Writes LF line endings, on every system. Shell scripts need them.',
      },
      {
        'crlf',
        'Writes CRLF line endings, on every system. Windows batch files need them.',
      },
    },
  },
  {
    name = 'binary',
    doc = 'Marks the files as binary. It is short for `-diff -merge -text`: no changes to line endings, no line by line diff and no merging.',
  },
  {
    name = 'diff',
    doc = 'How `git diff` shows changes. `-diff` shows them as binary. `diff=<driver>` names a driver, which finds the function each change is in.',
    values = driver_values,
  },
  {
    name = 'merge',
    doc = "How Git merges the files. `-merge` keeps the current branch's copy and marks a conflict.",
    values = {
      { 'text', 'Merges line by line. This is what Git does for text.' },
      {
        'binary',
        "Keeps the current branch's copy and marks a conflict.",
      },
      {
        'union',
        'Keeps the lines from both sides, with no conflict. It suits lists, such as a changelog.',
      },
      {
        'ours',
        "Keeps the current branch's copy with no conflict. It needs a driver of that name: `git config merge.ours.driver true`.",
      },
    },
  },
  {
    name = 'filter',
    doc = 'A filter that changes the files on their way into the repository and back out.',
    values = {
      {
        'lfs',
        'Stores the files with Git LFS: the repository keeps a small pointer, and the file itself lives on the LFS server.',
      },
    },
  },
  {
    name = 'whitespace',
    doc = 'Which whitespace mistakes `git diff` shows and `git apply` warns about, such as `whitespace=trailing-space,tab-in-indent`.',
  },
  {
    name = 'ident',
    doc = "Replaces `$Id$` in the files with the name of the file's contents when Git writes them out.",
  },
  {
    name = 'delta',
    doc = '`-delta` stops Git from storing the files as differences from each other. It helps with large files that are already compressed.',
  },
  {
    name = 'export-ignore',
    doc = 'Leaves the files out of archives that `git archive` makes, such as the source downloads of a GitHub release.',
  },
  {
    name = 'export-subst',
    doc = 'Fills in `$Format:...$` placeholders in the files when `git archive` makes an archive.',
  },
  {
    name = 'working-tree-encoding',
    doc = 'The encoding of the files on disk. Git stores them as UTF-8 and writes them out in this encoding.',
    values = {
      {
        'UTF-16LE-BOM',
        'UTF-16, little-endian, with a byte order mark. Windows tools expect it.',
      },
      { 'UTF-16', 'UTF-16, with a byte order mark.' },
      { 'UTF-16BE', 'UTF-16, big-endian, without a byte order mark.' },
      { 'UTF-32', 'UTF-32, with a byte order mark.' },
      { 'ISO-8859-1', 'Latin-1, one byte per character.' },
      { 'SHIFT-JIS', 'Shift JIS, for Japanese text.' },
    },
  },
  {
    name = 'lockable',
    doc = 'Git LFS makes the files read only until someone locks them with `git lfs lock`.',
  },
  {
    name = 'linguist-generated',
    doc = "GitHub folds the files away in diffs, and leaves them out of the repository's language statistics.",
  },
  {
    name = 'linguist-vendored',
    doc = "GitHub counts the files as code from elsewhere, and leaves them out of the repository's language statistics.",
  },
  {
    name = 'linguist-documentation',
    doc = "GitHub counts the files as documentation, and leaves them out of the repository's language statistics.",
  },
  {
    name = 'linguist-detectable',
    doc = 'GitHub counts the files in the language statistics, even a kind it leaves out by default, such as data or prose.',
  },
  {
    name = 'linguist-language',
    doc = 'The language GitHub shows the files in, and counts them as.',
    values = language_values,
  },
}

-- Whole lines often written, offered while the pattern is typed.
---@type { [1]: string, [2]: string }[]
M.lines = {
  {
    '* text=auto',
    'Lets Git find the text files and store them with LF line endings.',
  },
  {
    '*.sh text eol=lf',
    'Shell scripts keep LF line endings, even on Windows.',
  },
  { '*.bat text eol=crlf', 'Batch files keep CRLF line endings everywhere.' },
  { '*.cmd text eol=crlf', 'Batch files keep CRLF line endings everywhere.' },
  { '*.ps1 text eol=crlf', 'PowerShell scripts keep CRLF line endings.' },
  { '*.png binary', 'Pictures are binary.' },
  { '*.jpg binary', 'Pictures are binary.' },
  { '*.pdf binary', 'PDF files are binary.' },
  { '*.zip binary', 'Archives are binary.' },
  {
    '*.psd filter=lfs diff=lfs merge=lfs -text',
    'Large files go to Git LFS. `git lfs track "*.psd"` writes this line.',
  },
  {
    '*.lock -diff linguist-generated',
    'Lock files show no diff and stay out of the language statistics.',
  },
  {
    'dist/** linguist-generated',
    'Built files fold away in GitHub diffs.',
  },
  {
    'vendor/** linguist-vendored',
    'Code from elsewhere stays out of the language statistics.',
  },
  {
    'docs/** linguist-documentation',
    'Documentation stays out of the language statistics.',
  },
  {
    '.gitattributes export-ignore',
    'Leaves this file out of release archives.',
  },
}

local BY_NAME = {} ---@type table<string, LangGitfiles.Attribute>
for _, a in ipairs (M.list) do
  BY_NAME[a.name] = a
end

---@param name string
---@return LangGitfiles.Attribute?
function M.get (name)
  return BY_NAME[name]
end

---What is being typed at a column, counted from 0.
---@param line string
---@param column integer
---@return LangGitfiles.AttributeContext?
function M.at (line, column)
  local before = line:sub (1, column)
  if before:match ('^%s*#') then
    return nil
  end
  local pattern = before:match ('^%s*(%S*)$')
  if pattern then
    return { where = 'pattern', word = pattern, from = #before - #pattern }
  end
  local token = before:match ('(%S*)$') or ''
  local name, value = token:match ('^[%-!]?([%w_%-%.]+)=(%S*)$')
  if name then
    return {
      where = 'value',
      word = value,
      from = #before - #value,
      name = name,
    }
  end
  local word = token:match ('^[%-!]?([%w_%-%.]*)$')
  if not word then
    return nil
  end
  return { where = 'name', word = word, from = #before - #word }
end

---The completion list for a place on a line.
---@param at LangGitfiles.AttributeContext
---@return Proteus.CompletionItem[]
function M.items (at)
  local items = {} ---@type Proteus.CompletionItem[]
  if at.where == 'pattern' then
    for _, l in ipairs (M.lines) do
      items[#items + 1] =
        { label = l[1], kind = 'snippet', documentation = l[2] }
    end
  elseif at.where == 'name' then
    for _, a in ipairs (M.list) do
      items[#items + 1] =
        { label = a.name, kind = 'property', documentation = a.doc }
    end
  else
    local a = BY_NAME[at.name or '']
    for _, v in ipairs (a and a.values or {}) do
      items[#items + 1] =
        { label = v[1], kind = 'constant', documentation = v[2] }
    end
  end
  return items
end

---The word under a column: the run of characters without spaces around it, and where it
---starts, counted from 1.
---@param line string
---@param column integer Counted from 0.
---@return string?, integer?
local function token_at (line, column)
  local first, last = column + 1, column
  while first > 1 and line:sub (first - 1, first - 1):match ('%S') do
    first = first - 1
  end
  while line:sub (last + 1, last + 1):match ('%S') do
    last = last + 1
  end
  if last < first then
    return nil, nil
  end
  return line:sub (first, last), first
end

---What an attribute on a line means, in Markdown. `-name` turns an attribute off, `!name`
---leaves it as if no line had set it, and `name=value` gives it a value.
---@param token string
---@return string?
function M.describe (token)
  local prefix, name, value = token:match ('^([%-!]?)([%w_%-%.]+)=?(.*)$')
  local a = name and BY_NAME[name]
  if not a then
    return nil
  end
  local out = { '**`' .. token .. '`**', a.doc }
  if prefix == '-' then
    out[#out + 1] = 'The `-` turns it off for these files.'
  elseif prefix == '!' then
    out[#out + 1] =
      'The `!` leaves it unspecified for these files, as if no line had set it.'
  end
  for _, v in ipairs (value ~= '' and a.values or {}) do
    if v[1]:lower () == value:lower () then
      out[#out + 1] = '`' .. v[1] .. '`: ' .. v[2]
    end
  end
  return table.concat (out, '\n\n')
end

---The hover text for a column on a line, counted from 0.
---@param line string
---@param column integer
---@return string?
function M.hover (line, column)
  if line:match ('^%s*#') then
    return nil
  end
  local token, first = token_at (line, column)
  if not token or not first then
    return nil
  end
  if not line:sub (1, first - 1):find ('%S') then
    return '**`'
      .. token
      .. '`**\n\nThe files this line sets attributes for. It matches the way a .gitignore line does, except that it cannot start with `!`.'
  end
  return M.describe (token)
end

return M
