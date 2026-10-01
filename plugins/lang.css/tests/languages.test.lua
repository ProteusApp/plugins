local languages = require ('lib.languages') --[[@as LangCss.LanguagesModule]]

---@param ext string
---@return boolean
local function nothing_routed (ext)
  return ext == nil
end

---@param ext string
---@return boolean
local function scss_routed (ext)
  return ext == 'scss'
end

test ('extension reads the last part of the name in lower case', function ()
  eq (languages.extension ('C:/code/app/styles/Site.CSS'), 'css')
  eq (languages.extension ('src/theme.module.less'), 'less')
  eq (languages.extension ([[C:\code\app\main.scss]]), 'scss')
  eq (languages.extension ('Makefile'), nil)
  eq (languages.extension ('.stylelintrc'), nil)
end)

test ('each kind of file goes to the server under its own name', function ()
  eq (languages.language_id ('a/site.css', 'css', nothing_routed), 'css')
  eq (languages.language_id ('a/theme.less', 'css', nothing_routed), 'less')
  eq (languages.language_id ('a/main.scss', 'css', nothing_routed), 'scss')
end)

test ('a kind another plugin claimed is left alone', function ()
  eq (languages.language_id ('a/main.scss', 'css', scss_routed), nil)
  eq (languages.language_id ('a/site.css', 'css', scss_routed), 'css')
end)

test ('a file in another editor language is left alone', function ()
  eq (languages.language_id ('a/main.sass', 'sass', nothing_routed), nil)
  eq (languages.language_id ('a/notes.css', 'markdown', nothing_routed), nil)
  eq (languages.language_id ('a/style.styl', 'css', nothing_routed), nil)
end)

test ('section passes the lint levels by the server names', function ()
  eq (
    languages.section (true, {
      unknownProperties = 'error',
      important = 'warning',
    }),
    {
      validate = true,
      lint = { unknownProperties = 'error', important = 'warning' },
    }
  )
end)

test ('section leaves out the lint table when no level is set', function ()
  eq (languages.section (false, {}), { validate = false })
end)

test ('section drops levels the server does not know', function ()
  eq (
    languages.section (true, { unknownProperties = 'loud', emptyRules = 42 }),
    { validate = true }
  )
end)

test ('section ignores rules the plugin does not offer', function ()
  eq (languages.section (true, { zeroUnits = 'warning' }), { validate = true })
end)

test ('every lint rule has a default the server knows', function ()
  local known = {}
  for _, level in ipairs (languages.LEVELS) do
    known[level] = true
  end
  for _, spec in ipairs (languages.LINT_RULES) do
    ok (known[spec.default], spec.key .. ' has an unknown default')
  end
end)
