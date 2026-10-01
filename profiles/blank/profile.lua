-- The smallest possible app: the UI library and one plugin. A new app can start from here.
return {
  name = 'Blank',
  description = 'One plugin on an empty window. Copy it to start a new app.',
  version = '1.0.0',
  requires = { proteus = '>=0.3.0' },
  plugins = { 'proteus.hello' },
}
