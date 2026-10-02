-- theme.bevel: A desktop from the mid 1990s. Silver panels with raised buttons and sunken
-- fields, each bevel drawn from four one-pixel lines, panel headings as navy title bars, a
-- navy highlight on whatever is selected, and chunky scroll bars on a dithered track.
--
-- It lists one theme as data, which core.themes registers: its colors as CSS variables, and a
-- little CSS of its own for what colors alone cannot do. Pick it with View > Choose Color
-- Theme, or set `theme` to `bevel`.

---@type Proteus.Plugin
return {
  name = 'Bevel theme',
  description = 'A 1990s desktop: silver panels with raised and sunken bevels, and navy title bars.',
  version = '1.1.0',
  requires = { proteus = '>=0.2.0', features = { 'permissions', 'theme-data' } },
  permissions = {},
  depends = { 'core.themes' },
  themes = {
    {
      id = 'bevel',
      name = 'Bevel',
      dark = false,
      vars = {
        ['bg'] = '#c0c0c0',
        ['bg-alt'] = '#c0c0c0',
        ['bg-elev'] = '#c0c0c0',
        ['bg-hover'] = '#d4d0c8',
        ['bg-active'] = '#b4bdd6',
        ['fg'] = '#000000',
        ['fg-muted'] = '#303030',
        ['fg-faint'] = '#686868',
        ['border'] = '#808080',
        ['accent'] = '#000080',
        ['accent-fg'] = '#ffffff',
        ['danger'] = '#a00000',
        ['warning'] = '#806000',
        ['success'] = '#006000',
        ['selection'] = 'rgba(0,0,128,.25)',
        ['scrollbar'] = '#c0c0c0',
        ['shadow'] = '1px 1px 0 #000000',
        ['editor-bg'] = '#ffffff',
        ['editor-line'] = 'rgba(0,0,128,.05)',
        ['syn-keyword'] = '#000080',
        ['syn-string'] = '#800000',
        ['syn-number'] = '#008080',
        ['syn-constant'] = '#800080',
        ['syn-comment'] = '#008000',
        ['syn-function'] = '#0000ff',
        ['syn-operator'] = '#000000',
        ['syn-property'] = '#804000',
        ['syn-builtin'] = '#008080',
        ['radius'] = '0px',
        ['font-ui'] = 'Tahoma, "MS Sans Serif", "Segoe UI", Verdana, sans-serif',
        ['font-size'] = '12px',
        ['info'] = '#2962d1',
        ['hint'] = '#0d746d',
        ['diff-add'] = '#1c7549',
        ['diff-remove'] = '#b83b3b',
        ['diff-change'] = '#8f5e18',
        ['ansi-red'] = '#c0333c',
        ['ansi-green'] = '#287730',
        ['ansi-yellow'] = '#826300',
        ['ansi-blue'] = '#2d67bc',
        ['ansi-cyan'] = '#127474',
        ['ansi-bright-red'] = '#b83b3b',
        ['ansi-bright-green'] = '#1c7549',
        ['ansi-bright-yellow'] = '#905c00',
        ['ansi-bright-blue'] = '#2962d1',
        ['ansi-bright-magenta'] = '#9942ae',
        ['ansi-bright-cyan'] = '#0d746d',
      },
      -- lang=css
      css = [[
/* Raised: light above and left, dark below and right, one pixel at a time. */
body .ui-button:not(.menubar-item):not(.views-bar-item):not(.views-tab):not(.status-item):not(.tab-close),
body .views-tab.active,
body .popup,
body .palette,
body .overlay-modal,
body .toast,
body .shell-menubar,
body .shell-toolbar,
body .tab.active {
  border: none;
  box-shadow: inset -1px -1px #0a0a0a, inset 1px 1px #ffffff, inset -2px -2px #808080, inset 2px 2px #dfdfdf;
}
body .ui-button:not(.menubar-item):not(.views-bar-item):not(.views-tab):not(.status-item):not(.tab-close):active { box-shadow: inset -1px -1px #ffffff, inset 1px 1px #0a0a0a, inset -2px -2px #dfdfdf, inset 2px 2px #808080; }
/* Sunken: the reverse, for fields and the page being edited. */
body .ui-input,
body .palette-input,
body .cm-editor,
body .shell-status .status-item {
  border: none;
  background-color: #ffffff;
  box-shadow: inset -1px -1px #ffffff, inset 1px 1px #808080, inset -2px -2px #dfdfdf, inset 2px 2px #0a0a0a;
}
body .shell-status .status-item { background-color: transparent; margin: 1px 2px; }
/* Title bars on the panels. */
body .views-head {
  background: linear-gradient(90deg, #000080, #1084d0);
  color: #ffffff;
  font-weight: 700;
  text-transform: none;
  letter-spacing: 0;
}
/* The selection highlight: navy with white text. */
body .tree-row.selected,
body .palette-item.active,
body .popup-item.active {
  background: #000080;
  color: #ffffff;
}
body .tree-row.selected .ui-icon,
body .palette-item.active .ui-icon,
body .popup-item.active .ui-icon,
body .palette-item.active .palette-detail,
body .popup-item.active .popup-key { color: #ffffff; }
body .tab { border-right: 1px solid #808080; }
body .tab.active::before { display: none; }
/* Chunky scroll bars on a dithered track. */
body ::-webkit-scrollbar { width: 16px; height: 16px; }
body ::-webkit-scrollbar-track {
  background: repeating-conic-gradient(#c0c0c0 0 25%, #ffffff 0 50%) 0 0 / 2px 2px;
}
body ::-webkit-scrollbar-thumb {
  border: none;
  border-radius: 0;
  background: #c0c0c0;
  box-shadow: inset -1px -1px #0a0a0a, inset 1px 1px #ffffff, inset -2px -2px #808080, inset 2px 2px #dfdfdf;
}
/* Menus are flat until pointed at. */
body .menubar-item { border: none; box-shadow: none; }
body .menubar-item:hover,
body .menubar-item.open { background: #000080; color: #ffffff; }
      ]],
    },
  },
}
