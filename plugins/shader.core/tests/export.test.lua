-- Exports to other engines: HLSL, Godot, three.js and Unity. Each export of every node, and of
-- every example graph, goes through a real compiler where one is installed: glslangValidator
-- reads HLSL, and the GLSL inside the Godot, three.js and Unity files with what each engine
-- adds around it.

local build = require ('shader_build') --[[@as Shader.BuildModule]]
local compile = require ('shader_compile') --[[@as Shader.CompileModule]]
local examples = require ('shader_examples') --[[@as Shader.ExamplesModule]]
local export = require ('shader_export') --[[@as Shader.ExportModule]]
local graph = require ('shader_graph') --[[@as Shader.GraphModule]]
local nodes = require ('shader_nodes') --[[@as Shader.NodesModule]]
local subgraph = require ('shader_subgraph') --[[@as Shader.SubgraphModule]]

---@param text string
---@param piece string
---@return boolean
local function has (text, piece)
  return text:find (piece, 1, true) ~= nil
end

---Fails when a compiler that is installed refuses the code.
---@param what string
---@param lang 'glsl'|'hlsl'
---@param stage 'fragment'|'vertex'
---@param code string
---@param entry? string
local function compiles (what, lang, stage, code, entry)
  local good, messages = shader_check (lang, stage, code, entry)
  if good == false then
    error (
      what .. ' does not compile:\n' .. tostring (messages) .. '\n' .. code,
      2
    )
  end
end

-- What three.js puts above a ShaderMaterial's shaders with glslVersion GLSL3.
local THREE_VERTEX = [[
#version 300 es
precision highp float;
precision highp int;
uniform mat4 modelMatrix;
uniform mat4 modelViewMatrix;
uniform mat4 projectionMatrix;
uniform mat4 viewMatrix;
uniform mat3 normalMatrix;
uniform vec3 cameraPosition;
in vec3 position;
in vec3 normal;
in vec2 uv;
]]
local THREE_FRAGMENT = [[
#version 300 es
precision highp float;
precision highp int;
uniform mat4 viewMatrix;
uniform vec3 cameraPosition;
#define varying in
layout(location = 0) out highp vec4 pc_fragColor;
#define gl_FragColor pc_fragColor
]]

-- What UnityCG.cginc gives the shaders this test compiles.
local UNITY_CG = [[
float4 _Time;
float4 UnityObjectToClipPos(float4 v) { return v; }
]]

---Checks each export of a graph with the compilers.
---@param what string
---@param doc Shader.Doc
local function exports_compile (what, doc)
  local result = compile.compile (doc)
  assert (
    result.ok,
    what .. ': ' .. (result.errors[1] and result.errors[1].message or '')
  )
  local ir = result.ir

  local hlsl = export.hlsl (ir)
  compiles (what .. ' as HLSL', 'hlsl', 'fragment', hlsl, 'PSMain')
  compiles (what .. ' as HLSL (vertex)', 'hlsl', 'vertex', hlsl, 'VSMain')

  -- Godot's shading language is GLSL ES 3.00 with its own words around it.
  local gd = export.godot (ir)
  local body = gd:gsub ('shader_type canvas_item;', '')
    :gsub ('(uniform [%w_]+ [%w_]+)[^;\n]*;', '%1;')
    :gsub ('uniform sampler2D', 'uniform highp sampler2D')
    :gsub ('void fragment%(%)', 'in vec2 UV;\nvoid main()')
    :gsub ('COLOR = ', 'proteus_color = ')
  compiles (
    what .. ' as Godot',
    'glsl',
    'fragment',
    '#version 300 es\nprecision highp float;\nuniform float TIME;\nout vec4 proteus_color;\n'
      .. body
  )

  local js = export.three (ir)
  local vertex =
    assert (js:match ('export const vertexShader = /%* glsl %*/ `\n(.-)\n`;'))
  local fragment =
    assert (js:match ('export const fragmentShader = /%* glsl %*/ `\n(.-)\n`;'))
  compiles (
    what .. ' as three.js (vertex)',
    'glsl',
    'vertex',
    THREE_VERTEX .. vertex
  )
  compiles (
    what .. ' as three.js',
    'glsl',
    'fragment',
    THREE_FRAGMENT .. fragment
  )

  local unity = export.unity (ir)
  local program = assert (unity:match ('CGPROGRAM\n(.-)ENDCG'))
  program = program
    :gsub ('#include "UnityCG.cginc"', UNITY_CG)
    :gsub ('\n%s*#pragma[^\n]*', '')
  compiles (what .. ' as Unity', 'hlsl', 'fragment', program, 'frag')
  compiles (what .. ' as Unity (vertex)', 'hlsl', 'vertex', program, 'vert')
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

test ('GLSL turns into HLSL', function ()
  local dialect = { hlsl = true, names = {} } ---@type Shader.Dialect
  local used = {} ---@type table<string, boolean>
  ---@param text string
  ---@return string
  local function hlsl (text)
    return export.rewrite (text, dialect, used)
  end
  eq (hlsl ('mix(a, b, 0.5)'), 'lerp(a, b, 0.5)')
  eq (hlsl ('vec3(1.0)'), '((float3)(1.0))')
  eq (hlsl ('vec3(a, b, 1.0) * fract(x)'), 'float3(a, b, 1.0) * frac(x)')
  eq (hlsl ('atan(y, x) + atan(z)'), 'atan2(y, x) + atan(z)')
  eq (hlsl ('vec3(lessThan(a, b))'), '((float3)(((a) < (b))))')
  eq (
    hlsl ('mix(no, yes, greaterThan(p, vec2(0.5)))'),
    'lerp(no, yes, (((p) > (((float2)(0.5)))) ? 1.0 : 0.0))'
  )
  eq (hlsl ('float(a > b)'), '((float)(a > b))')
  eq (hlsl ('dFdx(v) + inversesqrt(w)'), 'ddx(v) + rsqrt(w)')
  eq (used.mod, nil)
  eq (hlsl ('mod(a, 2.0)'), 'sb_mod(a, 2.0)')
  eq (used.mod, true)
  eq (hlsl ('vec2 p = vec2(1.0, 2.0);'), 'float2 p = float2(1.0, 2.0);')
  eq (hlsl ('1.0e-10 + .5 + p.xyz'), '1.0e-10 + .5 + p.xyz')
  -- Text that does not close keeps what is there.
  eq (hlsl ('sin(a'), 'sin(a)')
  eq (hlsl ('a)'), 'a)')
end)

test ('every node exports and compiles in each engine', function ()
  for _, def in ipairs (nodes.list) do
    exports_compile (def.title, graph_of (def))
  end
end)

test ('every example graph exports and compiles in each engine', function ()
  for _, name in ipairs (examples.names) do
    exports_compile (name, assert (examples.build (name)))
  end
end)

test ('a graph with a made node exports the nodes inside it', function ()
  local doc = assert (examples.build (examples.names[1]))
  local ids = {} ---@type string[]
  for _, n in ipairs (doc.nodes) do
    if n.type ~= 'output' then
      ids[#ids + 1] = n.id
    end
  end
  local made = assert (subgraph.make (doc, ids, 'Everything'))
  exports_compile ('a made node', made)
end)

test ('each export says what its engine needs', function ()
  local doc = graph.new ('Pulse "one"')
  local id ---@type string
  doc, id = assert (graph.add_node (doc, 'parameter', 0, 0))
  doc = assert (graph.set_setting (doc, id, 'kind', 'color'))
  doc = assert (graph.set_setting (doc, id, 'name', 'tint'))
  local tex ---@type string
  doc, tex = assert (graph.add_node (doc, 'texture', 0, 0))
  local mul ---@type string
  doc, mul = assert (graph.add_node (doc, 'multiply', 0, 0))
  doc = assert (graph.connect (doc, id, 'out', mul, 'a'))
  doc = assert (graph.connect (doc, tex, 'rgb', mul, 'b'))
  doc = assert (graph.connect (doc, mul, 'out', 'n2', 'color'))
  local time ---@type string
  doc, time = assert (graph.add_node (doc, 'time', 0, 0))
  doc = assert (graph.connect (doc, time, 'sine', 'n2', 'alpha'))
  local ir = compile.compile (doc).ir
  eq (#ir.uniforms, 1)
  eq (#ir.channels, 1)

  local hlsl = export.hlsl (ir)
  ok (has (hlsl, 'cbuffer Uniforms : register(b0)'))
  ok (has (hlsl, 'float2 u_resolution; // offset 0'))
  ok (has (hlsl, 'float4 u_mouse; // offset 16'))
  ok (has (hlsl, 'float3 u_tint; // offset 32'))
  ok (has (hlsl, 'Texture2D iChannel0 : register(t0);'))
  ok (
    has (
      hlsl,
      'iChannel0.Sample(iChannel0_sampler, float2((uv).x, 1.0 - (uv).y))'
    )
  )
  ok (has (hlsl, '// Pulse  one, built with'))

  local gd = export.godot (ir)
  ok (has (gd, 'shader_type canvas_item;'))
  ok (has (gd, 'uniform vec3 u_tint : source_color = vec3(0.5);'))
  ok (has (gd, 'uniform sampler2D iChannel0'))
  ok (has (gd, 'sin(TIME)'))
  ok (not has (gd, 'u_time'))
  ok (has (gd, 'COLOR = vec4('))

  local js = export.three (ir)
  ok (
    has (
      js,
      "import { GLSL3, ShaderMaterial, Vector2, Vector3, Vector4 } from 'three';"
    )
  )
  ok (has (js, 'u_tint: { value: new Vector3(0.5, 0.5, 0.5) },'))
  ok (has (js, 'iChannel0: { value: null },'))
  ok (has (js, 'transparent: true,'))
  ok (has (js, 'glslVersion: GLSL3,'))

  local unity = export.unity (ir)
  ok (has (unity, 'Shader "Proteus/Pulse  one"'))
  ok (has (unity, 'u_tint ("tint", Color) = (0.5, 0.5, 0.5, 1)'))
  ok (has (unity, '_Channel0 ("iChannel0", 2D) = "white" {}'))
  ok (has (unity, 'tex2D(_Channel0, uv)'))
  ok (has (unity, 'sin(_Time.y)'))
  ok (has (unity, 'Blend SrcAlpha OneMinusSrcAlpha'))

  eq (export.target ('godot').ending, '.gdshader')
  eq (export.export ('nothing', ir), nil)
end)

test ('a graph builds for other engines, and a code shader does not', function ()
  local doc = assert (examples.build ('plasma'))
  local r = compile.compile (doc)
  local files =
    build.files ({ name = 'Plasma', glsl = r.glsl, wgsl = r.wgsl, ir = r.ir })
  for _, t in ipairs (export.TARGETS) do
    eq (files['plasma' .. t.ending], export.export (t.id, r.ir))
  end
  ok (has (files['README.md'], '## Other engines'))
  local code = build.files ({ name = 'Plasma', glsl = r.glsl })
  eq (code['plasma.hlsl'], nil)
end)
