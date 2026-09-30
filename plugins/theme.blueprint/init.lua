-- theme.blueprint: An architect's blueprint: chalk-white lines on Prussian blue paper. The
-- editor and the panels carry a drafting grid, a fine one every 8 pixels and a heavy one every
-- 40, headings are lettered in capitals like a title block, and the accent is a yellow
-- highlighter.
--
-- It registers one theme with core.themes, with its colors as CSS variables and a little CSS
-- of its own for what colors alone cannot do. Pick it with View > Choose Color Theme, or set
-- `theme` to `blueprint`.

---@type Proteus.Plugin
return {
  name = 'Blueprint theme',
  description = 'White lines on Prussian blue drafting paper, with a measured grid behind the code.',
  version = '1.0.0',
  requires = { proteus = '>=0.2.0', features = { 'permissions' } },
  permissions = {},
  depends = { 'core.themes' },
  activate = function (app)
    app.use ('themes').register ({
      id = 'blueprint',
      name = 'Blueprint',
      dark = true,
      vars = {
        ['bg'] = '#123e6b',
        ['bg-alt'] = '#0f355c',
        ['bg-elev'] = '#17497c',
        ['bg-hover'] = '#1b5288',
        ['bg-active'] = '#235f99',
        ['fg'] = '#e9f2fb',
        ['fg-muted'] = '#b3cbe4',
        ['fg-faint'] = '#7fa3c8',
        ['border'] = '#3b6a98',
        ['accent'] = '#ffe066',
        ['accent-fg'] = '#0f355c',
        ['danger'] = '#ff9e8f',
        ['warning'] = '#ffd08a',
        ['success'] = '#b6f0c0',
        ['selection'] = 'rgba(255,224,102,.22)',
        ['scrollbar'] = 'rgba(233,242,251,.28)',
        ['shadow'] = '0 0 0 1px rgba(233,242,251,.35), 0 10px 30px rgba(5,20,40,.5)',
        ['editor-bg'] = '#123e6b',
        ['editor-line'] = 'rgba(233,242,251,.06)',
        ['syn-keyword'] = '#9fd3ff',
        ['syn-string'] = '#ffe8a3',
        ['syn-number'] = '#ffb4a2',
        ['syn-constant'] = '#ffb4a2',
        ['syn-comment'] = '#86abd1',
        ['syn-function'] = '#ffffff',
        ['syn-operator'] = '#b9dcff',
        ['syn-property'] = '#c3f0ca',
        ['syn-builtin'] = '#a0e7e5',
        ['radius'] = '2px',
        ['font-mono'] = '"Cascadia Code", "JetBrains Mono", Consolas, monospace',
      },
      -- lang=css
      css = [[
/* The drafting grid: a fine line every 8px and a heavy one every 40px. */
body .cm-editor,
body .shell-left,
body .shell-right,
body .shell-bottom {
  background-image:
    linear-gradient(rgba(233, 242, 251, 0.11) 1px, transparent 1px),
    linear-gradient(90deg, rgba(233, 242, 251, 0.11) 1px, transparent 1px),
    linear-gradient(rgba(233, 242, 251, 0.045) 1px, transparent 1px),
    linear-gradient(90deg, rgba(233, 242, 251, 0.045) 1px, transparent 1px);
  background-size: 40px 40px, 40px 40px, 8px 8px, 8px 8px;
}
/* Everything drawn in ink is a line: panels, tabs and pop-ups get thin white rules. */
body .tab { border-right: 1px dashed var(--border); }
body .tab.active::before { height: 1px; background: var(--accent); box-shadow: 0 1px 0 var(--accent); }
body .ui-button { background: transparent; border-color: var(--fg-faint); }
body .ui-button.primary { background: var(--accent); color: var(--accent-fg); }
body .cm-gutters { border-right: 1px dashed var(--fg-faint) !important; }
/* Title-block lettering. */
body .views-head,
body .menubar-item,
body .status-item {
  text-transform: uppercase;
  letter-spacing: 0.08em;
  font-size: 11px;
}
body .views-head { color: var(--fg); }
      ]],
    })
  end,
}
