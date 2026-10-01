-- lang.gitfiles: Git's own files and GitHub's, in the code editor.
--
-- .gitignore, .gitattributes and .gitconfig files get languages of their own, so their
-- comments are colored. The first two get completion and hover help that explains each line
-- or attribute. Two commands add a template or the file in front to a .gitignore. GitHub's
-- YAML files get JSON schemas and GitHub Actions completion, which a YAML language server
-- such as lang.yaml uses. Every file here also gets an icon.
--
-- The parts live in lib/:
--   languages        the language specs
--   ignore           completion and hover help for .gitignore
--   attributes       completion and hover help for .gitattributes
--   templates        .gitignore templates
--   commands         the two commands
--   associations     schemas, completion and icons for GitHub's files
--   actions          GitHub Actions completion, with tags from GitHub
--   actions_context  where the cursor is in a workflow
--   actions_data     popular actions, and what expressions can name

local actions = require ('lib.actions') --[[@as LangGitfiles.ActionsModule]]
local associations = require ('lib.associations') --[[@as LangGitfiles.AssociationsModule]]
local attributes = require ('lib.attributes') --[[@as LangGitfiles.AttributesModule]]
local commands_module = require ('lib.commands') --[[@as LangGitfiles.CommandsModule]]
local disk = require ('disk_paths') --[[@as DiskPaths]]
local ignore = require ('lib.ignore') --[[@as LangGitfiles.IgnoreModule]]
local languages = require ('lib.languages') --[[@as LangGitfiles.LanguagesModule]]

---What the parts of the plugin share.
---@class LangGitfiles.Context
---@field app Proteus.App
---@field editor Proteus.Editor
---@field full_path fun(doc: { path: string, external: boolean }): string A document's full path on disk.

---One line of a text, counted from 0. Nil past the end.
---@param text string
---@param index integer
---@return string?
local function line_at (text, index)
  local n = 0
  for line in (text .. '\n'):gmatch ('([^\n]*)\n') do
    if n == index then
      return (line:gsub ('\r$', ''))
    end
    n = n + 1
  end
  return nil
end

---@type Proteus.Plugin
return {
  name = 'Git Files',
  description = 'Colors, completion and hover help for .gitignore, .gitattributes and .gitconfig, .gitignore templates, and schemas and Actions completion for GitHub workflows.',
  version = '1.0.0',
  requires = { proteus = '>=0.3.0', features = { 'permissions', 'languages' } },
  -- `files` for the `editor` service and for the .gitignore on disk that the commands change.
  -- `net` to ask GitHub for the versions of an action.
  permissions = { 'net', 'files' },
  depends = {
    'proteus.lib.ui',
    'proteus.core.commands',
    'proteus.core.files',
    'proteus.editor.core',
  },
  optional = {
    'proteus.code.project',
    'proteus.ui.palette',
    'proteus.ui.notify',
  },
  activate = function (app)
    local ui = app.use ('ui')
    local editor = app.use ('editor')
    local workspace = disk.normalize (app.kernel.launch.workspace or '')

    for _, spec in ipairs (languages.list) do
      ui.language (spec)
    end

    editor.set_provider ('gitignore', function (doc)
      ---@type Proteus.CodeProvider
      return {
        complete = function (pos, respond)
          local at =
            ignore.at (line_at (doc.text (), pos.line) or '', pos.character)
          respond (at and { items = ignore.items (), from = at.from } or nil)
        end,
        hover = function (pos, respond)
          respond (ignore.explain (line_at (doc.text (), pos.line) or ''))
        end,
      }
    end)

    editor.set_provider ('gitattributes', function (doc)
      ---@type Proteus.CodeProvider
      return {
        complete = function (pos, respond)
          local line = line_at (doc.text (), pos.line) or ''
          local at = attributes.at (line, pos.character)
          respond (
            at and { items = attributes.items (at), from = at.from } or nil
          )
        end,
        hover = function (pos, respond)
          local line = line_at (doc.text (), pos.line) or ''
          respond (attributes.hover (line, pos.character))
        end,
      }
    end)

    ---@type LangGitfiles.Context
    local ctx = {
      app = app,
      editor = editor,
      full_path = function (doc)
        return doc.external and disk.normalize (doc.path)
          or disk.join (workspace, doc.path)
      end,
    }
    commands_module.install (ctx)
    associations.install (app.use ('files'), actions.new (app))
  end,
}
