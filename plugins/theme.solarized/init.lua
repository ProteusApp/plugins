-- theme.solarized: Color themes from Ethan Schoonover's Solarized palette (MIT): Solarized
-- Dark and Solarized Light share the same accents. The accent is Solarized blue made a little
-- deeper, so white text on buttons stays readable.
--
-- It lists its themes as data, and core.themes registers them. Pick one with View > Choose
-- Color Theme, or the `theme` setting. Every color is a CSS variable, so the whole app changes
-- at once.

---Every theme this plugin adds.
---@type Proteus.ThemeSpec[]
local THEMES = {
  {
    id = 'solarized-dark',
    name = 'Solarized Dark',
    dark = true,
    vars = {
      ['bg'] = '#002b36',
      ['bg-alt'] = '#00252f',
      ['bg-elev'] = '#073642',
      ['bg-hover'] = '#0a3d4a',
      ['bg-active'] = '#0f4654',
      ['fg'] = '#a4b0b0',
      ['fg-muted'] = '#839496',
      ['fg-faint'] = '#5f747b',
      ['border'] = '#073642',
      ['accent'] = '#2075b0',
      ['accent-fg'] = '#fdf6e3',
      ['danger'] = '#dc322f',
      ['warning'] = '#b58900',
      ['success'] = '#859900',
      ['selection'] = 'rgba(38,139,210,.28)',
      ['scrollbar'] = 'rgba(88,110,117,.50)',
      ['shadow'] = '0 8px 30px rgba(0,0,0,.45)',
      ['editor-bg'] = '#002b36',
      ['editor-line'] = 'rgba(147,161,161,.05)',
      ['syn-keyword'] = '#859900',
      ['syn-string'] = '#2aa198',
      ['syn-number'] = '#dd649f',
      ['syn-constant'] = '#d67349',
      ['syn-comment'] = '#809196',
      ['syn-function'] = '#3794d6',
      ['syn-operator'] = '#93a1a1',
      ['syn-property'] = '#b58900',
      ['syn-builtin'] = '#8488cd',
    },
  },
  {
    id = 'solarized-light',
    name = 'Solarized Light',
    dark = false,
    vars = {
      ['bg'] = '#fdf6e3',
      ['bg-alt'] = '#f5efdc',
      ['bg-elev'] = '#fffbef',
      ['bg-hover'] = '#eee8d5',
      ['bg-active'] = '#e4ddc8',
      ['fg'] = '#50646a',
      ['fg-muted'] = '#5f747b',
      ['fg-faint'] = '#838f8f',
      ['border'] = '#e6dfca',
      ['accent'] = '#2075b0',
      ['accent-fg'] = '#fdf6e3',
      ['danger'] = '#dc322f',
      ['warning'] = '#b18600',
      ['success'] = '#829600',
      ['selection'] = 'rgba(38,139,210,.18)',
      ['scrollbar'] = 'rgba(88,110,117,.30)',
      ['shadow'] = '0 8px 30px rgba(0,43,54,.15)',
      ['editor-bg'] = '#fdf6e3',
      ['editor-line'] = 'rgba(7,54,66,.04)',
      ['syn-keyword'] = '#687700',
      ['syn-string'] = '#207c75',
      ['syn-number'] = '#c8337c',
      ['syn-constant'] = '#c34815',
      ['syn-comment'] = '#687272',
      ['syn-function'] = '#2075b0',
      ['syn-operator'] = '#5f747b',
      ['syn-property'] = '#8d6b00',
      ['syn-builtin'] = '#6469b6',
    },
  },
}

---@type Proteus.Plugin
return {
  name = 'Solarized themes',
  description = 'The precise, low-contrast Solarized colors, in a dark and a light theme.',
  version = '1.1.0',
  requires = { proteus = '>=0.2.0', features = { 'permissions', 'theme-data' } },
  permissions = {},
  depends = { 'core.themes' },
  themes = THEMES,
}
