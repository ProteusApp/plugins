-- theme.catppuccin: Soothing pastel color themes from the Catppuccin palette (MIT): Mocha,
-- which is dark, and Latte, which is light.
--
-- It registers its themes with core.themes. Pick one with View > Choose Color Theme, or the
-- `theme` setting. Every color is a CSS variable, so the whole app changes at once.

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
      ['syn-comment'] = '#7f849c',
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
      ['fg-muted'] = '#6c6f85',
      ['fg-faint'] = '#9ca0b0',
      ['border'] = '#dce0e8',
      ['accent'] = '#8839ef',
      ['accent-fg'] = '#eff1f5',
      ['danger'] = '#d20f39',
      ['warning'] = '#df8e1d',
      ['success'] = '#40a02b',
      ['selection'] = 'rgba(124,127,147,.20)',
      ['scrollbar'] = 'rgba(124,127,147,.30)',
      ['shadow'] = '0 8px 30px rgba(76,79,105,.18)',
      ['editor-bg'] = '#eff1f5',
      ['editor-line'] = 'rgba(76,79,105,.05)',
      ['syn-keyword'] = '#8839ef',
      ['syn-string'] = '#40a02b',
      ['syn-number'] = '#fe640b',
      ['syn-constant'] = '#fe640b',
      ['syn-comment'] = '#8c8fa1',
      ['syn-function'] = '#1e66f5',
      ['syn-operator'] = '#04a5e5',
      ['syn-property'] = '#7287fd',
      ['syn-builtin'] = '#df8e1d',
      ['radius'] = '8px',
    },
  },
}

---@type Proteus.Plugin
return {
  name = 'Catppuccin themes',
  description = 'Soothing pastel themes: Mocha, which is dark, and Latte, which is light.',
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
