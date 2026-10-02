-- theme.dracula: A dark color theme from the Dracula palette by Zeno Rocha (MIT).
--
-- It lists its theme as data, and core.themes registers it. Pick it with View > Choose Color
-- Theme, or the `theme` setting. Every color is a CSS variable, so the whole app changes at
-- once.

---Every theme this plugin adds.
---@type Proteus.ThemeSpec[]
local THEMES = {
  {
    id = 'dracula',
    name = 'Dracula',
    dark = true,
    vars = {
      ['bg'] = '#282a36',
      ['bg-alt'] = '#21222c',
      ['bg-elev'] = '#343746',
      ['bg-hover'] = '#3a3c4e',
      ['bg-active'] = '#44475a',
      ['fg'] = '#f8f8f2',
      ['fg-muted'] = '#bcbdcc',
      ['fg-faint'] = '#6272a4',
      ['border'] = '#191a21',
      ['accent'] = '#bd93f9',
      ['accent-fg'] = '#21222c',
      ['danger'] = '#ff5555',
      ['warning'] = '#ffb86c',
      ['success'] = '#50fa7b',
      ['selection'] = 'rgba(189,147,249,.28)',
      ['scrollbar'] = 'rgba(98,114,164,.45)',
      ['shadow'] = '0 8px 30px rgba(0,0,0,.45)',
      ['editor-bg'] = '#282a36',
      ['editor-line'] = 'rgba(68,71,90,.45)',
      ['syn-keyword'] = '#ff79c6',
      ['syn-string'] = '#f1fa8c',
      ['syn-number'] = '#bd93f9',
      ['syn-constant'] = '#bd93f9',
      ['syn-comment'] = '#8591b8',
      ['syn-function'] = '#50fa7b',
      ['syn-operator'] = '#ff79c6',
      ['syn-property'] = '#ffb86c',
      ['syn-builtin'] = '#8be9fd',
      ['radius'] = '8px',
    },
  },
}

---@type Proteus.Plugin
return {
  name = 'Dracula theme',
  description = 'A dark theme with vivid pink, purple and green, from the Dracula palette.',
  version = '1.1.0',
  requires = { proteus = '>=0.2.0', features = { 'permissions', 'theme-data' } },
  permissions = {},
  depends = { 'core.themes' },
  themes = THEMES,
}
