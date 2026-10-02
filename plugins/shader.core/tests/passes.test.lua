-- Channels and passes: what reads a channel, what the notes give it, which file is which pass,
-- and what graphs and code make of them.

local compile = require ('shader_compile') --[[@as Shader.CompileModule]]
local examples = require ('shader_examples') --[[@as Shader.ExamplesModule]]
local file = require ('shader_file') --[[@as Shader.FileModule]]
local graph = require ('shader_graph') --[[@as Shader.GraphModule]]
local passes = require ('shader_passes') --[[@as Shader.PassesModule]]
local source = require ('shader_source') --[[@as Shader.SourceModule]]

---@param text string
---@param piece string
---@return boolean
local function has (text, piece)
  return text:find (piece, 1, true) ~= nil
end

---Fails when a compiler that is installed refuses the code.
---@param what string
---@param p Shader.Program
local function compiles (what, p)
  local good, messages ---@type boolean?, string?
  if p.language == 'wgsl' then
    good, messages = shader_check ('wgsl', 'fragment', p.source)
  else
    good, messages = shader_check ('glsl', 'fragment', p.source)
  end
  if good == false then
    error (what .. ' does not compile:\n' .. tostring (messages), 2)
  end
end

test ('a note names a source', function ()
  eq (passes.parse_source (' buffer-a'), { kind = 'buffer', buffer = 'a' })
  eq (
    passes.parse_source ('noise nearest clamp'),
    { kind = 'noise', filter = 'nearest', wrap = 'clamp' }
  )
  eq (passes.parse_source ('none'), { kind = 'none' })
  eq (passes.parse_source ('nearest'), nil)
  eq (passes.parse_source ('buffer-e'), nil)
  eq (passes.clean_source ({ kind = 'buffer', buffer = 'B' }), {
    kind = 'buffer',
    buffer = 'b',
  })
  eq (passes.clean_source ({ kind = 'buffer' }), nil)
  eq (passes.clean_source ({ kind = 'lava' }), nil)
  eq (
    passes.clean_source ({ kind = 'image', grant = 'f3', name = 'a.png', x = 1 }),
    { kind = 'image', grant = 'f3', name = 'a.png' }
  )
  eq (passes.label ({ kind = 'buffer', buffer = 'c' }), 'Buffer C')
  eq (passes.label ({ kind = 'noise' }), 'Noise')
  eq (passes.label (nil), 'Nothing')
end)

test ('a file is a pass of the shader of its name', function ()
  eq ({ passes.pass_of ('shaders/ink.frag') }, { 'shaders/ink', 'image' })
  eq ({ passes.pass_of ('shaders/ink.buffer-b.frag') }, { 'shaders/ink', 'b' })
  eq (
    { passes.pass_of ('shaders/ink.Buffer-A.shader.json') },
    { 'shaders/ink', 'a' }
  )
  eq ({ passes.pass_of ('x.buffer-e.wgsl') }, { 'x.buffer-e', 'image' })
  eq (passes.pass_paths ('s/ink', 'c'), {
    's/ink.buffer-c.shader.json',
    's/ink.buffer-c.frag',
    's/ink.buffer-c.glsl',
    's/ink.buffer-c.wgsl',
  })
  eq (passes.buffer_path ('s/ink.wgsl', 'a'), 's/ink.buffer-a.wgsl')
  eq (passes.buffer_path ('s/ink.vert', 'b'), 's/ink.buffer-b.frag')
  eq (
    passes.buffer_path ('s/ink.buffer-a.shader.json', 'd'),
    's/ink.buffer-d.shader.json'
  )
end)

test ('glsl samplers read channels by name or by note', function ()
  local channels, errors = passes.glsl_channels ([[
uniform sampler2D iChannel2; // @channel 2 noise
uniform highp sampler2D u_tex; // @channel 1
uniform sampler2D u_lost;
uniform samplerCube u_sky;
// @channel 1 buffer-b nearest
// @channel 3 checker
/* uniform sampler2D iChannel3; */
// @channel 7 noise
]])
  eq (#channels, 2)
  eq (channels[1].index, 1)
  eq (channels[1].names, { 'u_tex' })
  eq (channels[1].source, { kind = 'buffer', buffer = 'b', filter = 'nearest' })
  eq (channels[2].index, 2)
  eq (channels[2].source, { kind = 'noise' })
  eq (#errors, 3)
  eq (errors[1].line, 3)
  ok (has (errors[1].message, 'Nothing is bound to u_lost'))
  eq (errors[2].line, 4)
  ok (has (errors[2].message, 'only sampler2D'))
  eq (errors[3].line, 8)
end)

test (
  'a short shader gets the channels, the date and the sizes it reads',
  function ()
    local p, errors = source.glsl_program ([[
// @channel 0 buffer-a
void mainImage(out vec4 c, in vec2 f) {
  c = texture(iChannel0, f / iChannelResolution[0].xy) + iDate.w * 0.0;
}
]])
    eq (errors, {})
    ok (has (p.source, 'uniform vec4 iDate;'))
    ok (has (p.source, 'uniform vec3 iChannelResolution[4];'))
    ok (has (p.source, 'uniform highp sampler2D iChannel0;'))
    eq (p.channels, {
      {
        index = 0,
        names = { 'iChannel0' },
        source = { kind = 'buffer', buffer = 'a' },
      },
    })
    eq (#p.uniforms, 0)
    compiles ('the short shader', p)
  end
)

test ('an array uniform gets no control', function ()
  local list, _, errors = source.glsl_uniforms (
    'uniform float u_weights[3];\nuniform vec3 iChannelResolution[4];\n'
  )
  eq (#list, 0)
  eq (#errors, 1)
  ok (has (errors[1].message, 'u_weights'))
end)

test ('wgsl textures and samplers are bound by group and binding', function ()
  local text = source.TEMPLATES.buffer_wgsl:gsub ('{{BUFFER}}', 'buffer-a')
  local p, errors = source.wgsl_program (text)
  eq (errors, {})
  eq (p.channels, {
    {
      index = 0,
      names = { 'iChannel0' },
      source = { kind = 'buffer', buffer = 'a' },
      line = 13,
    },
  })
  eq (p.bindings, {
    {
      group = 0,
      binding = 0,
      kind = 'uniforms',
      name = 'u',
      used = true,
    },
    {
      group = 1,
      binding = 0,
      kind = 'texture',
      name = 'iChannel0',
      channel = 0,
      used = true,
    },
    {
      group = 1,
      binding = 1,
      kind = 'sampler',
      name = 'iChannel0_sampler',
      channel = 0,
      used = true,
    },
  })
  compiles ('the WGSL buffer template', p)
end)

test ('a wgsl texture that reads no channel is named', function ()
  local _, errors = source.wgsl_program ([[
@group(1) @binding(0) var tex: texture_2d<f32>;
@group(1) @binding(1) var cube: texture_cube<f32>;
var lost: texture_2d<f32>;
@fragment fn fs_main() -> @location(0) vec4f { return vec4f(1.0); }
]])
  eq (#errors, 3)
  ok (has (errors[1].message, 'Nothing is bound to tex'))
  ok (has (errors[2].message, 'cube reads nothing'))
  ok (has (errors[3].message, '@group and @binding'))
end)

test ('a Texture node reads its channel in both languages', function ()
  local doc = graph.new ('Read')
  local id ---@type string
  doc, id = assert (graph.add_node (doc, 'texture', 0, 0))
  doc = assert (graph.set_setting (doc, id, 'channel', 'iChannel2'))
  doc = assert (graph.connect (doc, id, 'rgb', 'n2', 'color'))
  local r = compile.compile (doc)
  ok (r.ok)
  eq (
    r.glsl.channels,
    { { index = 2, names = { 'iChannel2' }, nodes = { id } } }
  )
  ok (has (r.glsl.source, 'uniform highp sampler2D iChannel2;'))
  ok (has (r.glsl.source, 'texture(iChannel2, uv)'))
  ok (
    has (r.wgsl.source, '@group(1) @binding(4) var iChannel2: texture_2d<f32>;')
  )
  ok (
    has (r.wgsl.source, '@group(1) @binding(5) var iChannel2_sampler: sampler;')
  )
  eq (#r.wgsl.bindings, 3)
  compiles ('a Texture node as GLSL', r.glsl)
  compiles ('a Texture node as WGSL', r.wgsl)
  -- A channel's name goes into the code, so only the four do.
  doc = assert (graph.set_setting (doc, id, 'channel', 'x); evil('))
  r = compile.compile (doc)
  ok (not r.ok)
  eq (r.errors[1].node, id)
  ok (not has (r.glsl.source, 'evil'))
end)

test ('a Date node adds the date to the uniforms', function ()
  local doc = graph.new ('Clock')
  local id, param ---@type string, string
  doc, id = assert (graph.add_node (doc, 'date', 0, 0))
  doc = assert (graph.connect (doc, id, 'seconds', 'n2', 'color'))
  doc, param = assert (graph.add_node (doc, 'parameter', 0, 0))
  doc = assert (graph.connect (doc, param, 'out', 'n2', 'alpha'))
  local r = compile.compile (doc)
  ok (r.ok)
  ok (has (r.glsl.source, 'uniform vec4 u_date;'))
  ok (has (r.wgsl.source, '  date: vec4f,'))
  local lay = r.wgsl.layout --[[@as Shader.Layout]]
  eq (
    lay.fields[5],
    { name = 'date', type = 'vec4', offset = 32, builtin = 'date' }
  )
  eq (r.uniforms[1].offset, 48)
  eq (
    compile.bad_name ('date'),
    'The shader has a date already. Pick another name.'
  )
  compiles ('a Date node as GLSL', r.glsl)
  compiles ('a Date node as WGSL', r.wgsl)
end)

test ('a graph keeps what its channels show in its file', function ()
  local doc = graph.set_channel (graph.new ('A'), 1, { kind = 'noise' })
  doc = graph.set_channel (doc, 3, { kind = 'buffer', buffer = 'a' })
  doc = graph.set_channel (doc, 9, { kind = 'noise' })
  local text = file.save (doc)
  ok (has (text, '"channels": { "1": { "kind": "noise" }, "3": {'))
  local back = assert (file.load (text))
  eq (back.channels, doc.channels)
  -- Other changes keep them.
  local moved = graph.rename (back, 'B')
  eq (moved.channels, doc.channels)
  local cleared = graph.set_channel (graph.set_channel (back, 1, nil), 3, nil)
  eq (cleared.channels, nil)
  ok (not has (file.save (cleared), 'channels'))
  -- A source that does not read is dropped, not the graph.
  local odd = assert (
    file.load (
      '{ "nodes": [], "channels": { "0": { "kind": "lava" }, "2": { "kind": "checker" } } }'
    )
  )
  eq (odd.channels, { ['2'] = { kind = 'checker' } })
end)

test ('a new graph buffer reads its own last frame', function ()
  local doc = examples.buffer ('b')
  eq (doc.channels, { ['0'] = { kind = 'buffer', buffer = 'b' } })
  local r = compile.compile (doc)
  ok (r.ok, r.errors[1] and r.errors[1].message)
  eq (r.glsl.channels[1].index, 0)
  compiles ('the graph buffer as GLSL', r.glsl)
  compiles ('the graph buffer as WGSL', r.wgsl)
end)
