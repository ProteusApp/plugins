-- theme.nanoqoi: A near-black theme in amethyst purples, from nanoqoi's Neovim colors. Those
-- are tokyonight's moon style with the Midnight Amethyst palette laid over it.
--
-- It registers its theme with core.themes. Pick it with View > Choose Color Theme, or the
-- `theme` setting. Every color is a CSS variable, so the whole app changes at once.

---Every theme this plugin adds.
---@type Proteus.ThemeSpec[]
local THEMES = {
  {
    id = 'nanoqoi',
    name = 'nanoqoi',
    dark = true,
    vars = {
      ['bg'] = '#04060b',
      ['bg-alt'] = '#020307',
      ['bg-elev'] = '#0b0e16',
      ['bg-hover'] = '#141821',
      ['bg-active'] = '#30264d',
      ['fg'] = '#e4dcf5',
      ['fg-muted'] = '#9384b5',
      ['fg-faint'] = '#74658f',
      ['border'] = '#493665',
      ['accent'] = '#b486f5',
      ['accent-fg'] = '#04060b',
      ['danger'] = '#f080a5',
      ['warning'] = '#dec08a',
      ['success'] = '#9dcbb3',
      ['selection'] = 'rgba(180,134,245,.25)',
      ['scrollbar'] = 'rgba(116,101,143,.50)',
      ['shadow'] = '0 8px 30px rgba(0,0,0,.60)',
      ['editor-bg'] = '#04060b',
      ['editor-line'] = 'rgba(228,220,245,.04)',
      ['syn-keyword'] = '#d5b5ff',
      ['syn-string'] = '#9dcbb3',
      ['syn-number'] = '#ff966c',
      ['syn-constant'] = '#ff966c',
      ['syn-comment'] = '#9384b5',
      ['syn-function'] = '#9985ec',
      ['syn-operator'] = '#d5b5ff',
      ['syn-property'] = '#4fd6be',
      ['syn-builtin'] = '#f080a5',
    },
  },
}

---@type Proteus.Plugin
return {
  name = 'nanoqoi theme',
  description = "A near-black theme in amethyst purples, from nanoqoi's Neovim colors.",
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
