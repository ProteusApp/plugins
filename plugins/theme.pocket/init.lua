-- theme.pocket: The screen of an early handheld game: four greens and nothing else, from the
-- darkest ink to the lightest glass. Corners are square, shadows are hard pixel steps, icons
-- snap to the pixel grid, and a faint dot matrix lies over everything like the LCD.
--
-- It lists one theme as data, which core.themes registers: its colors as CSS variables, and a
-- little CSS of its own for what colors alone cannot do. Pick it with View > Choose Color
-- Theme, or set `theme` to `pocket`.

---@type Proteus.Plugin
return {
  name = 'Pocket theme',
  description = 'The four greens of an early handheld game screen, with square corners, pixel shadows and an LCD dot grid.',
  version = '1.1.0',
  requires = { proteus = '>=0.2.0', features = { 'permissions', 'theme-data' } },
  permissions = {},
  depends = { 'core.themes' },
  themes = {
    {
      id = 'pocket',
      name = 'Pocket',
      dark = false,
      vars = {
        ['bg'] = '#9bbc0f',
        ['bg-alt'] = '#8bac0f',
        ['bg-elev'] = '#a7c61c',
        ['bg-hover'] = '#93b40f',
        ['bg-active'] = '#7fa00f',
        ['fg'] = '#0e330e',
        ['fg-muted'] = '#234b23',
        ['fg-faint'] = '#3a671b',
        ['border'] = '#306230',
        ['accent'] = '#0f380f',
        ['accent-fg'] = '#9bbc0f',
        ['danger'] = '#0f380f',
        ['warning'] = '#306230',
        ['success'] = '#306230',
        ['selection'] = 'rgba(15,56,15,.22)',
        ['scrollbar'] = 'rgba(15,56,15,.45)',
        ['shadow'] = '4px 4px 0 #306230',
        ['editor-bg'] = '#9bbc0f',
        ['editor-line'] = 'rgba(15,56,15,.08)',
        ['syn-keyword'] = '#0f380f',
        ['syn-string'] = '#244a24',
        ['syn-number'] = '#244a24',
        ['syn-constant'] = '#0f380f',
        ['syn-comment'] = '#2f4a0c',
        ['syn-function'] = '#0f380f',
        ['syn-operator'] = '#244a24',
        ['syn-property'] = '#1f4a1f',
        ['syn-builtin'] = '#1f4a1f',
        ['radius'] = '0px',
        ['font-ui'] = '"Cascadia Code", "JetBrains Mono", Consolas, monospace',
        ['font-size'] = '12.5px',
        ['info'] = '#2557b9',
        ['hint'] = '#0b6660',
        ['diff-add'] = '#196841',
        ['diff-remove'] = '#a33434',
        ['diff-change'] = '#7e5315',
        ['ansi-red'] = '#a92d34',
        ['ansi-green'] = '#23692a',
        ['ansi-yellow'] = '#745800',
        ['ansi-blue'] = '#285ba7',
        ['ansi-magenta'] = '#88379f',
        ['ansi-cyan'] = '#106666',
        ['ansi-bright-red'] = '#a33434',
        ['ansi-bright-green'] = '#196841',
        ['ansi-bright-yellow'] = '#815200',
        ['ansi-bright-blue'] = '#2557b9',
        ['ansi-bright-magenta'] = '#883b9a',
        ['ansi-bright-cyan'] = '#0b6660',
      },
      -- lang=css
      css = [[
/* The LCD: a faint dot matrix over the whole screen. */
body::after {
  content: "";
  position: fixed;
  inset: 0;
  pointer-events: none;
  z-index: 9999;
  background:
    repeating-linear-gradient(0deg, rgba(15, 56, 15, 0.06) 0 1px, transparent 1px 3px),
    repeating-linear-gradient(90deg, rgba(15, 56, 15, 0.06) 0 1px, transparent 1px 3px);
}
/* Pixels: square everything, snap the icons, and draw frames two pixels thick. */
body .ui-icon svg { shape-rendering: crispEdges; }
body .popup,
body .palette,
body .overlay-modal,
body .toast { border: 2px solid #0f380f; }
body .ui-button:not(.ghost):not(.menubar-item):not(.toolbar-button):not(.icon-button):not(.views-bar-item):not(.views-tab):not(.status-item):not(.tab-close) {
  border: 2px solid #0f380f;
  box-shadow: 2px 2px 0 #306230;
}
body .ui-button:not(.ghost):not(.menubar-item):not(.toolbar-button):not(.icon-button):not(.views-bar-item):not(.views-tab):not(.status-item):not(.tab-close):active {
  transform: translate(2px, 2px);
  box-shadow: none;
}
body .views-tab.active { box-shadow: inset 0 -3px 0 #0f380f; }
/* Selected things turn dark, as sprites do. */
body .tree-row.selected,
body .palette-item.active,
body .popup-item.active {
  background: #0f380f;
  color: #9bbc0f;
}
/* Four greens and nothing else: file icons from any icon pack take the screen's green. */
body .tree-row .ui-icon,
body .tab .ui-icon { color: #306230 !important; }
body .tree-row.selected .ui-icon,
body .palette-item.active .ui-icon,
body .popup-item.active .ui-icon { color: #9bbc0f !important; }
body .tab.active::before { height: 3px; }
body .cm-cursor { border-left-width: 8px !important; opacity: 0.6; }
      ]],
    },
  },
}
