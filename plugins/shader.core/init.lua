-- shader.core: the pure logic of the shader builder, shared with the other shader plugins as
-- the `shader` service. It has no UI and does no I/O: the node catalog, graph operations,
-- the GLSL and WGSL compiler, code shaders, channels and passes, the file format, builds, undo,
-- and how numbers and colours show in fields.

local build = require ('shader_build') --[[@as Shader.BuildModule]]
local compile = require ('shader_compile') --[[@as Shader.CompileModule]]
local examples = require ('shader_examples') --[[@as Shader.ExamplesModule]]
local file = require ('shader_file') --[[@as Shader.FileModule]]
local format = require ('shader_format') --[[@as Shader.FormatModule]]
local graph = require ('shader_graph') --[[@as Shader.GraphModule]]
local helpers = require ('shader_helpers') --[[@as Shader.HelpersModule]]
local history = require ('shader_history') --[[@as Shader.HistoryModule]]
local layout = require ('shader_layout') --[[@as Shader.LayoutModule]]
local nodes = require ('shader_nodes') --[[@as Shader.NodesModule]]
local passes = require ('shader_passes') --[[@as Shader.PassesModule]]
local source = require ('shader_source') --[[@as Shader.SourceModule]]
local types = require ('shader_types') --[[@as Shader.TypesModule]]

---@type Proteus.Plugin
return {
  name = 'Shader core',
  description = 'The logic behind the shader builder: nodes, graphs, the GLSL and WGSL compiler, code shaders and files.',
  version = '1.3.0',
  requires = { proteus = '>=0.2.0', features = { 'permissions' } },
  permissions = {},
  activate = function (app)
    ---@type Shader.Core
    local core = {
      types = types,
      nodes = nodes,
      helpers = helpers,
      graph = graph,
      compile = compile,
      layout = layout,
      source = source,
      passes = passes,
      file = file,
      format = format,
      history = history,
      examples = examples,
      build = build,
    }
    app.provide ('shader', core)
  end,
}
