-- theme.catppuccin: Soothing pastel color themes from the Catppuccin palette (MIT): Mocha,
-- which is dark, and Latte, which is light.
--
-- It lists its themes as data, and core.themes registers them. Pick one with View > Choose
-- Color Theme, or the `theme` setting. Every color is a CSS variable, so the whole app changes
-- at once.

---Every theme this plugin adds.
---@type Proteus.ThemeSpec[]
local THEMES = {
  {
    id = 'catppuccin-mocha',
    name = 'Catppuccin Mocha',
    dark = true,
    vars = {
      ['bg'] = '#1e1e2e',
      ['bg-alt'] = '#181825',
      ['bg-elev'] = '#313244',
      ['bg-hover'] = '#2a2b3c',
      ['bg-active'] = '#45475a',
      ['fg'] = '#cdd6f4',
      ['fg-muted'] = '#a6adc8',
      ['fg-faint'] = '#6c7086',
      ['border'] = '#313244',
      ['accent'] = '#cba6f7',
      ['accent-fg'] = '#11111b',
      ['danger'] = '#f38ba8',
      ['warning'] = '#fab387',
      ['success'] = '#a6e3a1',
      ['selection'] = 'rgba(147,153,178,.25)',
      ['scrollbar'] = 'rgba(108,112,134,.40)',
      ['shadow'] = '0 8px 30px rgba(0,0,0,.45)',
      ['editor-bg'] = '#1e1e2e',
      ['editor-line'] = 'rgba(205,214,244,.04)',
      ['syn-keyword'] = '#cba6f7',
      ['syn-string'] = '#a6e3a1',
      ['syn-number'] = '#fab387',
      ['syn-constant'] = '#fab387',
      ['syn-comment'] = '#82869e',
      ['syn-function'] = '#89b4fa',
      ['syn-operator'] = '#89dceb',
      ['syn-property'] = '#b4befe',
      ['syn-builtin'] = '#f9e2af',
      ['radius'] = '8px',
    },
  },
  {
    id = 'catppuccin-latte',
    name = 'Catppuccin Latte',
    dark = false,
    vars = {
      ['bg'] = '#eff1f5',
      ['bg-alt'] = '#e6e9ef',
      ['bg-elev'] = '#f7f8fa',
      ['bg-hover'] = '#dce0e8',
      ['bg-active'] = '#ccd0da',
      ['fg'] = '#4c4f69',
      ['fg-muted'] = '#696c81',
      ['fg-faint'] = '#858896',
      ['border'] = '#dce0e8',
      ['accent'] = '#8839ef',
      ['accent-fg'] = '#eff1f5',
      ['danger'] = '#d20f39',
      ['warning'] = '#c07a19',
      ['success'] = '#3f9d2a',
      ['selection'] = 'rgba(124,127,147,.20)',
      ['scrollbar'] = 'rgba(124,127,147,.30)',
      ['shadow'] = '0 8px 30px rgba(76,79,105,.18)',
      ['editor-bg'] = '#eff1f5',
      ['editor-line'] = 'rgba(76,79,105,.05)',
      ['syn-keyword'] = '#8839ef',
      ['syn-string'] = '#317b21',
      ['syn-number'] = '#b94908',
      ['syn-constant'] = '#b94908',
      ['syn-comment'] = '#6a6d7a',
      ['syn-function'] = '#1d63ee',
      ['syn-operator'] = '#0375a3',
      ['syn-property'] = '#5665be',
      ['syn-builtin'] = '#986114',
      ['radius'] = '8px',
    },
  },
}

---@type Proteus.Plugin
return {
  name = 'Catppuccin themes',
  description = 'Soothing pastel themes: Mocha, which is dark, and Latte, which is light.',
  version = '1.1.0',
  requires = { proteus = '>=0.2.0', features = { 'permissions', 'theme-data' } },
  permissions = {},
  depends = { 'core.themes' },
  themes = THEMES,
}
