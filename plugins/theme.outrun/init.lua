-- theme.outrun: Synthwave after dark. Hot pink and electric cyan glow on a midnight purple
-- sky, a sunset stripe runs under the menu bar, and a neon grid runs to the horizon under the
-- code.
--
-- It lists one theme as data, which core.themes registers: its colors as CSS variables, and a
-- little CSS of its own for what colors alone cannot do. Pick it with View > Choose Color
-- Theme, or set `theme` to `outrun`.

---@type Proteus.Plugin
return {
  name = 'Outrun theme',
  description = 'Synthwave neon on a midnight purple sky, with a glowing grid running to the horizon under the code.',
  version = '1.1.0',
  requires = { proteus = '>=0.2.0', features = { 'permissions', 'theme-data' } },
  permissions = {},
  depends = { 'core.themes' },
  themes = {
    {
      id = 'outrun',
      name = 'Outrun',
      dark = true,
      vars = {
        ['bg'] = '#1a0b2e',
        ['bg-alt'] = '#13072a',
        ['bg-elev'] = '#261145',
        ['bg-hover'] = '#2f1655',
        ['bg-active'] = '#3e1d6e',
        ['fg'] = '#f6ecff',
        ['fg-muted'] = '#c7aee8',
        ['fg-faint'] = '#8b6cb3',
        ['border'] = '#34195c',
        ['accent'] = '#ff2e97',
        ['accent-fg'] = '#1a0b2e',
        ['danger'] = '#ff5566',
        ['warning'] = '#ffb454',
        ['success'] = '#3cf2c4',
        ['selection'] = 'rgba(54,249,246,.20)',
        ['scrollbar'] = 'rgba(255,46,151,.35)',
        ['shadow'] = '0 0 0 1px rgba(255,46,151,.35), 0 0 24px rgba(255,46,151,.25), 0 12px 32px rgba(0,0,0,.6)',
        ['editor-bg'] = '#1a0b2e',
        ['editor-line'] = 'rgba(54,249,246,.06)',
        ['syn-keyword'] = '#ff2e97',
        ['syn-string'] = '#ffd319',
        ['syn-number'] = '#ff8b39',
        ['syn-constant'] = '#ff8b39',
        ['syn-comment'] = '#8973b1',
        ['syn-function'] = '#36f9f6',
        ['syn-operator'] = '#fe4450',
        ['syn-property'] = '#72f1b8',
        ['syn-builtin'] = '#b893ff',
        ['radius'] = '4px',
      },
      -- lang=css
      css = [[
/* A sunset stripe under the menu bar. */
body .shell-menubar {
  border-bottom: 2px solid transparent;
  border-image: linear-gradient(90deg, #ff2e97, #ff8b39, #ffd319, #36f9f6) 1;
}
/* Neon: the active tab, the side bar and buttons glow. */
body .tab.active::before {
  background: linear-gradient(90deg, #ff2e97, #36f9f6);
  box-shadow: 0 0 10px #ff2e97, 0 0 2px #36f9f6;
}
body .tab.active .tab-title,
body .views-bar-item.active,
body .menubar-brand { text-shadow: 0 0 8px rgba(255, 46, 151, 0.8); }
body .ui-button.primary { box-shadow: 0 0 12px rgba(255, 46, 151, 0.55); }
body .ui-input:focus,
body .palette-input:focus { box-shadow: 0 0 0 1px #36f9f6, 0 0 12px rgba(54, 249, 246, 0.45); }
/* The horizon: a neon grid in perspective, fading as it leaves, under the text. */
body .cm-editor::before {
  content: "";
  position: absolute;
  left: -50%;
  right: -50%;
  bottom: 0;
  height: 55%;
  pointer-events: none;
  background:
    repeating-linear-gradient(90deg, rgba(255, 46, 151, 0.55) 0 1px, transparent 1px 56px),
    repeating-linear-gradient(0deg, rgba(255, 46, 151, 0.55) 0 1px, transparent 1px 28px);
  transform: perspective(260px) rotateX(62deg);
  transform-origin: bottom;
  -webkit-mask-image: linear-gradient(transparent, #000 85%);
  mask-image: linear-gradient(transparent, #000 85%);
  opacity: 0.4;
}
body .cm-editor { overflow: hidden; }
body .cm-editor > .cm-scroller { position: relative; z-index: 1; }
      ]],
    },
  },
}
