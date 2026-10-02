-- What a build writes, and that the code the builder makes compiles with real compilers:
-- glslangValidator for GLSL ES 3.00 and naga for WGSL. Where a compiler is not installed, its
-- checks are left out, except in the check workflow, which installs both.

local build = require ('shader_build') --[[@as Shader.BuildModule]]
local compile = require ('shader_compile') --[[@as Shader.CompileModule]]
local examples = require ('shader_examples') --[[@as Shader.ExamplesModule]]
local file = require ('shader_file') --[[@as Shader.FileModule]]
local graph = require ('shader_graph') --[[@as Shader.GraphModule]]
local nodes = require ('shader_nodes') --[[@as Shader.NodesModule]]
local source = require ('shader_source') --[[@as Shader.SourceModule]]

local EXAMPLES = 'plugins/shader.docs/examples/'

---@param text string
---@param piece string
---@return boolean
local function has (text, piece)
  return text:find (piece, 1, true) ~= nil
end

---Fails when a compiler that is installed refuses the code.
---@param what string
---@param lang 'glsl'|'wgsl'
---@param stage 'fragment'|'vertex'
---@param code string
local function compiles (what, lang, stage, code)
  local good, messages = shader_check (lang, stage, code)
  if good == false then
    error (what .. ' does not compile:\n' .. tostring (messages), 2)
  end
end

---Checks every stage of a program.
---@param what string
---@param p Shader.Program
local function program_compiles (what, p)
  if p.language == 'wgsl' then
    compiles (what, 'wgsl', 'fragment', p.source)
  else
    compiles (what, 'glsl', 'fragment', p.source)
    compiles (what .. ' (vertex)', 'glsl', 'vertex', p.vertex or '')
  end
end

---A graph with one node of the type, its first output wired to the colour.
---@param def Shader.NodeDef
---@return Shader.Doc
local function graph_of (def)
  local doc = graph.new (def.title)
  if def.type == 'output' then
    return doc
  end
  local id ---@type string
  doc, id = assert (graph.add_node (doc, def.type, 0, 0))
  local out = nodes.visible_outputs (def)[1]
  if out then
    doc = assert (graph.connect (doc, id, out.key, 'n2', 'color'))
  end
  return doc
end

test ('a file name comes from the shader name', function ()
  eq (build.stem ('My Shader!'), 'my-shader')
  eq (build.stem ('--a__b--'), 'a__b')
  eq (build.stem (''), 'shader')
  eq (build.stem ('???'), 'shader')
end)

test ('a graph builds into GLSL, WGSL, pages, uniforms and a README', function ()
  local doc = examples.build ('plasma') --[[@as Shader.Doc]]
  local r = compile.compile (doc)
  local files = build.files ({ name = 'Plasma', glsl = r.glsl, wgsl = r.wgsl })
  local names = {} ---@type string[]
  for name in pairs (files) do
    names[#names + 1] = name
  end
  table.sort (names)
  eq (names, {
    'README.md',
    'index.html',
    'plasma.frag',
    'plasma.vert',
    'plasma.wgsl',
    'uniforms.json',
    'webgpu.html',
  })
  eq (files['plasma.frag'], r.glsl.source)
  eq (files['plasma.wgsl'], r.wgsl.source)
  ok (has (files['index.html'], 'WebGL 2'))
  ok (has (files['webgpu.html'], 'WebGPU'))
  ok (has (files['README.md'], '| `u_speed` | float | 1 | 0 to 4 |'))
  local data = assert (file.decode (files['uniforms.json']))
  eq (data.name, 'Plasma')
  eq (data.glsl[1].glsl, 'u_speed')
  eq (data.wgsl.uniforms[1].offset, r.wgsl.uniforms[1].offset)
  eq (data.wgsl.buffer_size, r.wgsl.layout.size)
end)

test ('a code shader builds in its own language only', function ()
  local p = source.wgsl_program (source.TEMPLATES.wgsl)
  local files = build.files ({ name = 'tunnel', wgsl = p })
  eq (files['tunnel.frag'], nil)
  ok (files['tunnel.wgsl'])
  ok (has (files['index.html'], 'WebGPU'))
  eq (files['webgpu.html'], nil)
  local data = assert (file.decode (files['uniforms.json']))
  eq (data.glsl, nil)
  eq (data.wgsl.fields[5].name, 'speed')
end)

test ('a page cannot be ended early by what the shader holds', function ()
  local p = source.glsl_program (
    'void main() { fragColor = vec4(1.0); } // </script><b>'
  )
  local files = build.files ({ name = '<b>x</b>', glsl = p })
  local page = files['index.html']
  eq (select (2, page:gsub ('</script>', '')), 1)
  ok (has (page, '<title>bx/b</title>'))
end)

test ('every node compiles in both languages', function ()
  for _, def in ipairs (nodes.list) do
    local r = compile.compile (graph_of (def))
    ok (r.ok, def.type .. ': ' .. (r.errors[1] and r.errors[1].message or ''))
    program_compiles (def.type .. ' as GLSL', r.glsl)
    program_compiles (def.type .. ' as WGSL', r.wgsl)
  end
end)

test ('every example graph compiles in both languages', function ()
  for _, name in ipairs (examples.names) do
    local doc = assert (file.load (read (EXAMPLES .. name .. file.EXTENSION)))
    local r = compile.compile (doc)
    program_compiles (name .. ' as GLSL', r.glsl)
    program_compiles (name .. ' as WGSL', r.wgsl)
  end
end)

test ('every example code shader and template compiles', function ()
  for _, name in ipairs ({
    'waves.frag',
    'raymarch.frag',
    'shadertoy.frag',
    'weather.frag',
    'tunnel.wgsl',
    'ink.frag',
    'ink.buffer-a.frag',
  }) do
    local lang = source.kind_of (name) --[[@as Shader.Lang]]
    program_compiles (name, (source.program (lang, read (EXAMPLES .. name))))
  end
  for key, text in pairs (source.TEMPLATES) do
    if key == 'vertex' then
      program_compiles (
        'the vertex template',
        (source.glsl_program (source.TEMPLATES.glsl, text))
      )
    elseif key == 'wgsl' or key == 'buffer_wgsl' then
      program_compiles ('the WGSL template', (source.wgsl_program (text)))
    else
      program_compiles (
        'the ' .. key .. ' template',
        (source.glsl_program (text))
      )
    end
  end
end)

test ('a broken shader does not compile', function ()
  local good =
    shader_check ('glsl', 'fragment', '#version 300 es\nvoid main() { x; }\n')
  ok (good ~= true)
  good = shader_check ('wgsl', 'fragment', 'fn f() -> f32 { return y; }\n')
  ok (good ~= true)
  good = shader_check (
    'hlsl',
    'fragment',
    'float4 PSMain() : SV_Target { return z; }\n',
    'PSMain'
  )
  ok (good ~= true)
  local fine =
    'float4 PSMain() : SV_Target { return float4(1.0, 0.0, 0.0, 1.0); }\n'
  ok (shader_check ('hlsl', 'fragment', fine, 'PSMain') ~= false)
end)

test (
  'a shader with buffers builds every pass, with what its channels show',
  function ()
    local buffer = source.glsl_program (
      (source.TEMPLATES.buffer:gsub ('{{BUFFER}}', 'buffer-a'))
    )
    local image = source.glsl_program (
      '// @channel 0 buffer-a\nvoid mainImage(out vec4 c, in vec2 f) { c = texture(iChannel0, f / iResolution.xy) + texture(iChannel1, vec2(0.0)); }\n'
    )
    local files = build.files ({
      name = 'Ink',
      glsl = image,
      channels = {
        [0] = { kind = 'buffer', buffer = 'a' },
        [1] = { kind = 'image', grant = 'f3', name = 'wood.png' },
      },
      buffers = {
        {
          id = 'a',
          glsl = buffer,
          channels = { [0] = { kind = 'buffer', buffer = 'a' } },
        },
      },
    })
    eq (files['ink.buffer-a.frag'], buffer.source)
    eq (files['ink.wgsl'], nil, 'the code is GLSL only')
    local page = files['index.html']
    ok (has (page, '"id": "a"'))
    ok (has (page, '"name": "wood.png"'))
    ok (not has (page, 'f3'), 'a grant means nothing beside the page')
    local readme = files['README.md']
    ok (has (readme, '## Passes and channels'))
    ok (has (readme, '| Buffer A | `iChannel0` | `iChannel0` | Buffer A |'))
    ok (
      has (
        readme,
        '| Image | `iChannel1` | `iChannel1` | `wood.png`, which goes beside the page |'
      )
    )
    local data = assert (file.decode (files['uniforms.json']))
    eq (data.buffers[1].id, 'a')
    eq (data.channels[2].source, { kind = 'image', name = 'wood.png' })
    -- A graph image with a GLSL buffer builds GLSL only.
    local graph_image =
      compile.compile (examples.build ('plasma') --[[@as Shader.Doc]])
    local mixed = build.files ({
      name = 'Mixed',
      glsl = graph_image.glsl,
      wgsl = graph_image.wgsl,
      buffers = { { id = 'a', glsl = buffer } },
    })
    ok (mixed['mixed.frag'])
    eq (mixed['mixed.wgsl'], nil)
    eq (mixed['webgpu.html'], nil)
  end
)
