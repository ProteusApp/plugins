-- theme.gruvbox: Warm retro color themes from the Gruvbox palette by Pavel Pertsev (MIT):
-- Gruvbox Dark and Gruvbox Light.
--
-- It registers its themes with core.themes. Pick one with View > Choose Color Theme, or the
-- `theme` setting. Every color is a CSS variable, so the whole app changes at once.

---Every theme this plugin adds.
---@type Proteus.ThemeSpec[]
local THEMES = {
  {
    id = 'gruvbox-dark',
    name = 'Gruvbox Dark',
    dark = true,
    vars = {
      ['bg'] = '#282828',
      ['bg-alt'] = '#1d2021',
      ['bg-elev'] = '#32302f',
      ['bg-hover'] = '#3c3836',
      ['bg-active'] = '#504945',
      ['fg'] = '#ebdbb2',
      ['fg-muted'] = '#bdae93',
      ['fg-faint'] = '#7c6f64',
      ['border'] = '#3c3836',
      ['accent'] = '#fabd2f',
      ['accent-fg'] = '#282828',
      ['danger'] = '#fb4934',
      ['warning'] = '#fe8019',
      ['success'] = '#b8bb26',
      ['selection'] = 'rgba(131,165,152,.30)',
      ['scrollbar'] = 'rgba(168,153,132,.30)',
      ['shadow'] = '0 8px 30px rgba(0,0,0,.45)',
      ['editor-bg'] = '#282828',
      ['editor-line'] = 'rgba(235,219,178,.04)',
      ['syn-keyword'] = '#fb4934',
      ['syn-string'] = '#b8bb26',
      ['syn-number'] = '#d3869b',
      ['syn-constant'] = '#d3869b',
      ['syn-comment'] = '#928374',
      ['syn-function'] = '#fabd2f',
      ['syn-operator'] = '#fe8019',
      ['syn-property'] = '#83a598',
      ['syn-builtin'] = '#8ec07c',
      ['radius'] = '4px',
    },
  },
  {
    id = 'gruvbox-light',
    name = 'Gruvbox Light',
    dark = false,
    vars = {
      ['bg'] = '#fbf1c7',
      ['bg-alt'] = '#f2e5bc',
      ['bg-elev'] = '#f9f5d7',
      ['bg-hover'] = '#ebdbb2',
      ['bg-active'] = '#d5c4a1',
      ['fg'] = '#3c3836',
      ['fg-muted'] = '#665c54',
      ['fg-faint'] = '#a89984',
      ['border'] = '#e2d3ab',
      ['accent'] = '#076678',
      ['accent-fg'] = '#fbf1c7',
      ['danger'] = '#9d0006',
      ['warning'] = '#af3a03',
      ['success'] = '#79740e',
      ['selection'] = 'rgba(7,102,120,.18)',
      ['scrollbar'] = 'rgba(124,111,100,.35)',
      ['shadow'] = '0 8px 30px rgba(60,56,54,.18)',
      ['editor-bg'] = '#fbf1c7',
      ['editor-line'] = 'rgba(60,56,54,.05)',
      ['syn-keyword'] = '#9d0006',
      ['syn-string'] = '#79740e',
      ['syn-number'] = '#8f3f71',
      ['syn-constant'] = '#8f3f71',
      ['syn-comment'] = '#928374',
      ['syn-function'] = '#b57614',
      ['syn-operator'] = '#af3a03',
      ['syn-property'] = '#076678',
      ['syn-builtin'] = '#427b58',
      ['radius'] = '4px',
    },
  },
}

---@type Proteus.Plugin
return {
  name = 'Gruvbox themes',
  description = 'Retro groove colors, warm and easy on the eyes, in a dark and a light theme.',
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
