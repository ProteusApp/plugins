-- Nodal: a visual builder. Place blocks and wire them together to get a live preview,
-- typed TypeScript or Lua, and a Proteus plugin built from the same graph.
return {
  name = 'Nodal',
  description = 'Wire blocks together to build an app, then get TypeScript, Lua or a plugin.',
  version = '1.1.0',
  -- It runs plugins by the ids they took in Proteus 0.3.0.
  requires = { proteus = '>=0.3.0', features = { 'profile-extends' } },
  -- The themes, keys, menus, status bar, side panels, palette, messages, Settings and
  -- Profiles come from the app's shell, profiles/base/shell.lua.
  extends = 'shell',
  plugins = {
    'proteus.ui.toolbar',
    -- The editor, so blocks written as Lua files open with types, completion and checks.
    'proteus.ui.tabs',
    'proteus.ui.menubar',
    'proteus.editor.core',
    'proteus.tools.registry',
    'proteus.tools.diagnostics',
    'proteus.lang.luals',
    'proteus.lang.stylua',
    'proteus.lang.selene',
    'proteus.nodal.core',
    'proteus.nodal.state',
    'proteus.nodal.app',
    'proteus.nodal.canvas',
    'proteus.nodal.inspect',
    'proteus.nodal.preview',
    'proteus.nodal.output',
    'proteus.nodal.palette',
    'proteus.discord.rpc',
  },
  settings = {
    theme = 'daylight',
  },
}
