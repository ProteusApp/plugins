-- theme.parchment: A scholar's manuscript. Iron-gall ink on warm, faintly mottled paper,
-- headings in book type and small capitals, rubric red for keywords, and a red margin rule
-- beside the line numbers, as in a ruled notebook.
--
-- It registers one theme with core.themes, with its colors as CSS variables and a little CSS
-- of its own for what colors alone cannot do. Pick it with View > Choose Color Theme, or set
-- `theme` to `parchment`.

---@type Proteus.Plugin
return {
  name = 'Parchment theme',
  description = 'Iron-gall ink on warm paper, with book type, rubric red and a ruled margin beside the code.',
  version = '1.0.0',
  requires = { proteus = '>=0.2.0', features = { 'permissions' } },
  permissions = {},
  depends = { 'core.themes' },
  activate = function (app)
    app.use ('themes').register ({
      id = 'parchment',
      name = 'Parchment',
      dark = false,
      vars = {
        ['bg'] = '#f3ead3',
        ['bg-alt'] = '#ebe0c4',
        ['bg-elev'] = '#f8f1de',
        ['bg-hover'] = '#e4d7b6',
        ['bg-active'] = '#dccba1',
        ['fg'] = '#3a2d20',
        ['fg-muted'] = '#6b5a45',
        ['fg-faint'] = '#a08c6c',
        ['border'] = '#d9c9a3',
        ['accent'] = '#8b2e1f',
        ['accent-fg'] = '#fbf6ea',
        ['danger'] = '#a3261b',
        ['warning'] = '#94600d',
        ['success'] = '#4a6b2f',
        ['selection'] = 'rgba(139,46,31,.16)',
        ['scrollbar'] = 'rgba(107,90,69,.35)',
        ['shadow'] = '0 2px 4px rgba(58,45,32,.12), 0 12px 28px rgba(58,45,32,.20)',
        ['editor-bg'] = '#f7f0dc',
        ['editor-line'] = 'rgba(139,46,31,.05)',
        ['syn-keyword'] = '#8b2e1f',
        ['syn-string'] = '#4a6b2f',
        ['syn-number'] = '#9a5b13',
        ['syn-constant'] = '#9a5b13',
        ['syn-comment'] = '#9a8466',
        ['syn-function'] = '#2f4d6b',
        ['syn-operator'] = '#6b5a45',
        ['syn-property'] = '#6d3f63',
        ['syn-builtin'] = '#2f6b5f',
        ['radius'] = '3px',
        ['font-ui'] = '"Iowan Old Style", "Palatino Linotype", Palatino, "Book Antiqua", Georgia, serif',
        ['font-size'] = '14px',
      },
      -- lang=css
      css = [[
/* Paper: warm blotches of age, laid over the page. */
body .shell {
  background-image:
    radial-gradient(ellipse at 12% 18%, rgba(160, 120, 60, 0.08), transparent 45%),
    radial-gradient(ellipse at 88% 76%, rgba(160, 120, 60, 0.10), transparent 50%),
    radial-gradient(ellipse at 60% 8%, rgba(120, 90, 40, 0.05), transparent 35%);
}
/* The ruled margin of a notebook: a red rule after the line numbers. */
body .cm-gutters {
  border-right: 1px solid rgba(139, 46, 31, 0.5) !important;
  box-shadow: 3px 0 0 -2px rgba(139, 46, 31, 0.25);
  font-style: italic;
}
/* Book headings: small capitals, not shouting capitals. */
body .views-head {
  text-transform: none;
  font-variant: small-caps;
  font-size: 14px;
  letter-spacing: 0.06em;
  color: var(--accent);
}
body .tab.active .tab-title { font-style: italic; }
body .tab.active::before { height: 1px; }
body .menubar-item { font-variant: small-caps; letter-spacing: 0.03em; }
      ]],
    })
  end,
}
