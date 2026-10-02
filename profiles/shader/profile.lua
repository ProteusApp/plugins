-- The Shader Builder: GLSL and WGSL shaders, built from a node graph or written as code, with
-- a live preview on WebGL 2 and WebGPU. Shaders live in shaders/, and a build writes complete
-- shader files and a page that runs them.
return {
  name = 'Shader Builder',
  description = 'Build GLSL and WGSL shaders from nodes or code, with a live preview.',
  version = '1.1.0',
  plugins = {
    'theme.midnight',
    'theme.daylight',
    'theme.retro',
    'core.keys',
    'ui.menus',
    'ui.menubar',
    'ui.toolbar',
    'ui.statusbar',
    'ui.views',
    'ui.tabs',
    'ui.palette',
    'ui.notify',
    'ui.settings',
    'core.profiles',
    -- The marketplace, for more plugins and profiles.
    'marketplace',
    'shader.core',
    'shader.docs',
    'shader.canvas',
    'shader.code',
    'shader.preview',
    'shader.library',
    'shader.build',
  },
  -- Plugins installed from the marketplace stay on.
  extensible = true,
  settings = {
    theme = 'midnight',
  },
}
