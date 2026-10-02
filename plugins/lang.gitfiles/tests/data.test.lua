local associations = require ('lib.associations') --[[@as LangGitfiles.AssociationsModule]]
local languages = require ('lib.languages') --[[@as LangGitfiles.LanguagesModule]]

-- The extensions the editor gives a language of its own, which a plugin cannot take.
local EDITOR_KNOWS = {
  yaml = true,
  yml = true,
  toml = true,
  ini = true,
  cfg = true,
  conf = true,
  env = true,
  txt = true,
}

---@param words string|string[]|nil
---@return string[]
local function word_list (words)
  if type (words) == 'string' then
    local out = {}
    for w in words:gmatch ('%S+') do
      out[#out + 1] = w
    end
    return out
  end
  return words or {}
end

test ('each language is a valid spec', function ()
  local names = {}
  for _, spec in ipairs (languages.list) do
    ok (spec.name:match ('^[a-z][a-z0-9_-]*$'), spec.name)
    ok (not names[spec.name], spec.name .. ' once')
    names[spec.name] = true
    eq (spec.directive, '#')
    -- `#` starts a comment in every one of them, which keeps `/*` from opening a C comment.
    local marks = type (spec.comment) == 'table' and spec.comment
      or { spec.comment }
    eq (marks[1], '#', spec.name .. ' comments')
    for _, field in ipairs ({ 'keywords', 'atoms', 'extensions' }) do
      for _, word in ipairs (word_list (spec[field])) do
        ok (
          word:match ('^[%a_$][%w_$]*$'),
          spec.name .. ' ' .. field .. ': ' .. word
        )
      end
    end
  end
  ok (names.gitignore and names.gitattributes and names.gitconfig)
end)

test (
  'the extensions are ones the editor leaves free, each claimed once',
  function ()
    local seen = {}
    for _, spec in ipairs (languages.list) do
      for _, ext in ipairs (word_list (spec.extensions)) do
        ok (not EDITOR_KNOWS[ext], ext)
        ok (not seen[ext], ext .. ' once')
        seen[ext] = true
      end
    end
    for _, ext in ipairs ({
      'gitignore',
      'dockerignore',
      'npmignore',
      'prettierignore',
      'eslintignore',
      'stylelintignore',
      'vscodeignore',
      'gitattributes',
      'gitconfig',
      'gitmodules',
    }) do
      ok (seen[ext], ext)
    end
  end
)

test ('every schema comes from schemastore.org', function ()
  local seen = {}
  for _, s in ipairs (associations.schemas) do
    ok (s[2]:match ('^https://www%.schemastore%.org/[%w%.%-]+%.json$'), s[2])
    ok (not seen[s[1]], s[1] .. ' once')
    seen[s[1]] = true
  end
  ok (seen['.github/workflows/*.yml'] and seen['action.yml'])
  ok (seen['.github/dependabot.yml'] and seen['.github/FUNDING.yml'])
  ok (seen['.github/ISSUE_TEMPLATE/config.yml'])
end)

test ('Actions completion covers workflows and actions', function ()
  eq (associations.actions, {
    '.github/workflows/*.yml',
    '.github/workflows/*.yaml',
    'action.yml',
    'action.yaml',
  })
end)

test ('every icon names a Lucide icon and a color', function ()
  for _, i in ipairs (associations.icons) do
    ok (i.icon:match ('^[a-z0-9%-]+$'), i.pattern)
    ok (i.color ~= '', i.pattern)
  end
end)
