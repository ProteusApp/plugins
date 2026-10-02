-- associations: the file associations for GitHub's files and Git's own. Each is data, so a
-- YAML language server, an icon pack or any other plugin can use it without knowing this
-- plugin exists.

local STORE = 'https://www.schemastore.org/'

-- Git's orange, for the files Git itself reads.
local GIT = '#f05033'

---@class LangGitfiles.AssociationsModule
local M = {}

-- JSON schemas from schemastore.org. A YAML language server, such as lang.yaml's, checks the
-- files against them and completes their keys.
---@type { [1]: string, [2]: string }[]
M.schemas = {
  { '.github/workflows/*.yml', STORE .. 'github-workflow.json' },
  { '.github/workflows/*.yaml', STORE .. 'github-workflow.json' },
  { 'action.yml', STORE .. 'github-action.json' },
  { 'action.yaml', STORE .. 'github-action.json' },
  { '.github/dependabot.yml', STORE .. 'dependabot-2.0.json' },
  { '.github/dependabot.yaml', STORE .. 'dependabot-2.0.json' },
  { '.github/ISSUE_TEMPLATE/*.yml', STORE .. 'github-issue-forms.json' },
  { '.github/ISSUE_TEMPLATE/*.yaml', STORE .. 'github-issue-forms.json' },
  { '.github/ISSUE_TEMPLATE/config.yml', STORE .. 'github-issue-config.json' },
  {
    '.github/ISSUE_TEMPLATE/config.yaml',
    STORE .. 'github-issue-config.json',
  },
  { '.github/DISCUSSION_TEMPLATE/*.yml', STORE .. 'github-discussion.json' },
  { '.github/DISCUSSION_TEMPLATE/*.yaml', STORE .. 'github-discussion.json' },
  { '.github/FUNDING.yml', STORE .. 'github-funding.json' },
  { '.github/FUNDING.yaml', STORE .. 'github-funding.json' },
  { '.github/release.yml', STORE .. 'github-release-config.json' },
  {
    '.github/secret_scanning.yml',
    STORE .. 'github-secret-scanning.json',
  },
  {
    '.github/workflow-templates/*.properties.json',
    STORE .. 'github-workflow-template-properties.json',
  },
}

-- The files that get GitHub Actions completion: workflows and actions.
M.actions = {
  '.github/workflows/*.yml',
  '.github/workflows/*.yaml',
  'action.yml',
  'action.yaml',
}

-- Icons for every icon pack. A pack's own icon for the same files wins.
---@type { pattern: string, icon: string, color: string, open?: string, folder?: boolean }[]
M.icons = {
  { pattern = '.gitignore', icon = 'git-branch', color = GIT },
  { pattern = '.gitattributes', icon = 'git-branch', color = GIT },
  { pattern = '.gitmodules', icon = 'git-branch', color = GIT },
  { pattern = '.gitconfig', icon = 'git-branch', color = GIT },
  { pattern = '.dockerignore', icon = 'eye-off', color = 'var(--fg-muted)' },
  { pattern = '.npmignore', icon = 'eye-off', color = 'var(--fg-muted)' },
  { pattern = '.prettierignore', icon = 'eye-off', color = 'var(--fg-muted)' },
  { pattern = '.eslintignore', icon = 'eye-off', color = 'var(--fg-muted)' },
  {
    pattern = '.stylelintignore',
    icon = 'eye-off',
    color = 'var(--fg-muted)',
  },
  { pattern = '.vscodeignore', icon = 'eye-off', color = 'var(--fg-muted)' },
  {
    pattern = '.github',
    icon = 'folder-git-2',
    open = 'folder-open',
    color = 'var(--fg-muted)',
    folder = true,
  },
  {
    pattern = '.github/workflows/*.yml',
    icon = 'workflow',
    color = 'var(--syn-keyword)',
  },
  {
    pattern = '.github/workflows/*.yaml',
    icon = 'workflow',
    color = 'var(--syn-keyword)',
  },
  { pattern = 'action.yml', icon = 'zap', color = 'var(--syn-keyword)' },
  { pattern = 'action.yaml', icon = 'zap', color = 'var(--syn-keyword)' },
  {
    pattern = 'dependabot.yml',
    icon = 'package-check',
    color = 'var(--syn-function)',
  },
  { pattern = 'FUNDING.yml', icon = 'heart', color = 'var(--syn-string)' },
  { pattern = 'CODEOWNERS', icon = 'users', color = 'var(--syn-constant)' },
  {
    pattern = '.github/ISSUE_TEMPLATE/*',
    icon = 'circle-dot',
    color = 'var(--syn-string)',
  },
  {
    pattern = 'pull_request_template.md',
    icon = 'git-pull-request',
    color = 'var(--syn-string)',
  },
}

---Adds every association.
---@param files Proteus.Files
---@param complete fun(doc: Proteus.DocInfo, pos: Proteus.CodePosition, respond: fun(result: Proteus.CompletionResult?))
function M.install (files, complete)
  for _, s in ipairs (M.schemas) do
    files.associate ({ kind = 'schema', pattern = s[1], value = s[2] })
  end
  for _, pattern in ipairs (M.actions) do
    files.associate ({ kind = 'completion', pattern = pattern, value = complete })
  end
  for _, i in ipairs (M.icons) do
    files.associate ({
      kind = 'icon',
      pattern = i.pattern,
      value = {
        icon = i.icon,
        color = i.color,
        open = i.open,
        folder = i.folder,
      },
    })
  end
end

return M
