-- languages: which files the server reads, what it hears about each one, and its settings.
-- Nothing here calls the app, so the tests reach it.

---@class LangCss.LanguagesModule
local M = {}

-- The editor's language for `.css`, `.scss` and `.less` files.
M.LANGUAGE = 'css'

-- What the server calls each kind of file, by its extension.
local IDS = { css = 'css', less = 'less', scss = 'scss' }

-- The settings sections the server asks for. It asks for the one named after each file's kind.
M.SECTIONS = { 'css', 'less', 'scss' }

-- How loudly a lint rule speaks.
M.LEVELS = { 'ignore', 'warning', 'error' }

---One lint rule the plugin offers as a setting.
---@class LangCss.LintRule
---@field key string The setting, after `css.lint.`.
---@field rule string The server's name for the rule.
---@field default string
---@field title string
---@field description string

-- The lint rules worth a setting. The server knows more, and keeps its defaults for them.
---@type LangCss.LintRule[]
M.LINT_RULES = {
  {
    key = 'unknown_properties',
    rule = 'unknownProperties',
    default = 'warning',
    title = 'Unknown properties',
    description = 'A property name CSS does not know, such as a typo.',
  },
  {
    key = 'unknown_at_rules',
    rule = 'unknownAtRules',
    default = 'warning',
    title = 'Unknown at-rules',
    description = 'An at-rule CSS does not know. Set it to ignore for Tailwind rules such as @apply.',
  },
  {
    key = 'empty_rules',
    rule = 'emptyRules',
    default = 'warning',
    title = 'Empty rules',
    description = 'A rule with nothing between its braces.',
  },
  {
    key = 'duplicate_properties',
    rule = 'duplicateProperties',
    default = 'ignore',
    title = 'Duplicate properties',
    description = 'The same property twice in one rule.',
  },
  {
    key = 'important',
    rule = 'important',
    default = 'ignore',
    title = '!important',
    description = 'Any use of !important.',
  },
  {
    key = 'id_selector',
    rule = 'idSelector',
    default = 'ignore',
    title = 'Id selectors',
    description = 'A selector that names an id, such as #main.',
  },
}

---A file's extension in lower case, or nil when it has none.
---@param path string
---@return string?
function M.extension (path)
  local name = path:match ('[^/\\]*$') or path
  local ext = name:match ('^.+%.([^.]+)$')
  return ext and ext:lower () or nil
end

---What the server calls a file, or nil when the plugin leaves it alone. A file whose kind
---another plugin took over is left alone.
---@param path string
---@param language string The editor's language for the file.
---@param routed fun(ext: string): boolean True when another plugin serves files of this kind.
---@return string?
function M.language_id (path, language, routed)
  if language ~= M.LANGUAGE then
    return nil
  end
  local ext = M.extension (path)
  local id = ext and IDS[ext]
  if not id or routed (ext) then
    return nil
  end
  return id
end

---True for one of the levels a lint rule takes.
---@param value any
---@return boolean
local function is_level (value)
  for _, level in ipairs (M.LEVELS) do
    if value == level then
      return true
    end
  end
  return false
end

---What the server gets when it asks for the `css`, `less` or `scss` section.
---@param validate boolean True to check files and show problems.
---@param levels table<string, any> Each lint rule's level, by the server's name for the rule.
---@return table
function M.section (validate, levels)
  local section = { validate = validate } ---@type table<string, any>
  local lint = {} ---@type table<string, string>
  local any = false
  for _, spec in ipairs (M.LINT_RULES) do
    local level = levels[spec.rule]
    if is_level (level) then
      lint[spec.rule] = level
      any = true
    end
  end
  -- Left out when empty, since an empty table could go out as `[]`.
  if any then
    section.lint = lint
  end
  return section
end

return M
