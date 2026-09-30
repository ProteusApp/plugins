-- theme.nord: An arctic, north-bluish color theme from the Nord palette by Arctic Ice Studio
-- (MIT).
--
-- It registers its theme with core.themes. Pick it with View > Choose Color Theme, or the
-- `theme` setting. Every color is a CSS variable, so the whole app changes at once.

---Every theme this plugin adds.
---@type Proteus.ThemeSpec[]
local THEMES = {
  {
    id = 'nord',
    name = 'Nord',
    dark = true,
    vars = {
      ['bg'] = '#2e3440',
      ['bg-alt'] = '#292e39',
      ['bg-elev'] = '#3b4252',
      ['bg-hover'] = '#373e4c',
      ['bg-active'] = '#434c5e',
      ['fg'] = '#d8dee9',
      ['fg-muted'] = '#aeb7c6',
      ['fg-faint'] = '#6d7a91',
      ['border'] = '#3b4252',
      ['accent'] = '#88c0d0',
      ['accent-fg'] = '#2e3440',
      ['danger'] = '#bf616a',
      ['warning'] = '#ebcb8b',
      ['success'] = '#a3be8c',
      ['selection'] = 'rgba(136,192,208,.25)',
      ['scrollbar'] = 'rgba(129,161,193,.30)',
      ['shadow'] = '0 8px 30px rgba(0,0,0,.45)',
      ['editor-bg'] = '#2e3440',
      ['editor-line'] = 'rgba(236,239,244,.04)',
      ['syn-keyword'] = '#81a1c1',
      ['syn-string'] = '#a3be8c',
      ['syn-number'] = '#b48ead',
      ['syn-constant'] = '#d08770',
      ['syn-comment'] = '#616e88',
      ['syn-function'] = '#88c0d0',
      ['syn-operator'] = '#81a1c1',
      ['syn-property'] = '#8fbcbb',
      ['syn-builtin'] = '#ebcb8b',
    },
  },
}

---@type Proteus.Plugin
return {
  name = 'Nord theme',
  description = 'An arctic, north-bluish dark theme, from the Nord palette.',
  version = '1.0.0',
  requires = { proteus = '>=0.2.0', features = { 'permissions' } },
  permissions = {},
  depends = { 'core.themes' },
  activate = function (app)
    local themes = app.use ('themes')
    for _, theme in ipairs (THEMES) do
      themes.register (theme)
    end
  end,
}
