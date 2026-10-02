-- languages: the languages this plugin adds to the code editor. Each one is data. `comment`
-- names the marks that start a comment, so `/*` in a pattern such as `**/*.log` stays a
-- pattern. A Proteus from before `comment` colors them with its rules for C, and there
-- `directive` still gives `#` lines a color of their own.
--
-- The editor finds a file's language from the part of its name after the last dot, so
-- `.gitignore` has the extension `gitignore`.

---@class LangGitfiles.LanguagesModule
local M = {}

---@type Proteus.LanguageSpec[]
M.list = {
  {
    name = 'gitignore',
    -- Other programs read ignore files written the same way as Git's.
    extensions = {
      'gitignore',
      'dockerignore',
      'npmignore',
      'prettierignore',
      'eslintignore',
      'stylelintignore',
      'vscodeignore',
    },
    comment = '#',
    directive = '#',
  },
  {
    name = 'gitattributes',
    extensions = { 'gitattributes' },
    keywords = {
      'text',
      'eol',
      'binary',
      'diff',
      'merge',
      'filter',
      'whitespace',
      'ident',
      'delta',
      'encoding',
      'lockable',
    },
    atoms = 'auto lf crlf lfs union ours',
    comment = '#',
    directive = '#',
  },
  {
    name = 'gitconfig',
    extensions = { 'gitconfig', 'gitmodules' },
    atoms = 'true false yes no on off',
    -- Git's config files start a comment with `#` or `;`.
    comment = { '#', ';' },
    directive = '#',
  },
}

return M
