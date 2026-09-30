-- Shaders written as code: their uniforms, their notes, and what the preview runs.

local compile = require ('shader_compile') --[[@as Shader.CompileModule]]
local source = require ('shader_source') --[[@as Shader.SourceModule]]

---@param text string
---@param piece string
---@return boolean
local function has (text, piece)
  return text:find (piece, 1, true) ~= nil
end

test ('files are known by their ending', function ()
  eq ({ source.kind_of ('a/b.frag') }, { 'glsl', 'fragment' })
  eq ({ source.kind_of ('B.VERT') }, { 'glsl', 'vertex' })
  eq ({ source.kind_of ('x.wgsl') }, { 'wgsl', 'fragment' })
  eq ({ source.kind_of ('x.shader.json') }, {})
end)

test ('notes shape the controls', function ()
  local n = source.notes (' @range 0 4 @default 1', 'float')
  eq ({ n.min, n.max, n.value }, { 0, 4, { 1 } })
  n = source.notes ('@color @default 1 0.5 0', 'vec3')
  eq ({ n.color, n.value }, { true, { 1, 0.5, 0 } })
  n = source.notes ('@color', 'vec3')
  eq (n.value, { 1, 1, 1 })
  n = source.notes ('@range -2 2', 'vec2')
  eq (n.value, { 0, 0 })
  n = source.notes ('', 'int')
  eq ({ n.min, n.max, n.step, n.value }, { 0, 10, 1, { 5 } })
  n = source.notes ('', 'bool')
  eq (n.value, { 0 })
end)

test ('glsl uniforms leave out the ones the preview sets', function ()
  local list, declared, errors = source.glsl_uniforms ([[
uniform float u_time;
uniform highp float u_speed; // @range 0 10 @default 2
uniform vec3 a, b; // @color
uniform mat4 u_matrix;
uniform sampler2D u_tex;
]])
  eq (#list, 3)
  eq (list[1].key, 'u_speed')
  eq (list[1].value, { 2 })
  eq (list[2].key, 'a')
  eq (list[3].color, true)
  ok (declared.u_time)
  eq (#errors, 1)
  eq (errors[1].line, 4)
end)

test ('a full glsl shader runs as it is', function ()
  local p, errors = source.glsl_program (source.TEMPLATES.glsl)
  eq (#errors, 0)
  eq (p.offset, 0)
  eq (p.source, source.TEMPLATES.glsl)
  eq (p.vertex, compile.GLSL_VERTEX)
  eq (#p.uniforms, 2)
  eq (p.uniforms[2].key, 'u_tint')
  eq (p.uniforms[2].value, { 0.3, 0.6, 1.0 })
end)

test ('a short glsl shader gets what it leaves out', function ()
  local text = 'void main() {\n  fragColor = vec4(v_uv, sin(u_time), 1.0);\n}\n'
  local p = source.glsl_program (text)
  eq (p.offset, 5)
  ok (
    has (
      p.source,
      '#version 300 es\nprecision highp float;\nuniform float u_time;\nin vec2 v_uv;\nout vec4 fragColor;\nvoid main'
    )
  )
end)

test ('a shadertoy shader gets a main', function ()
  local p = source.glsl_program (source.TEMPLATES.shadertoy)
  eq (p.shadertoy, true)
  ok (has (p.source, 'uniform vec3 iResolution;'))
  ok (has (p.source, 'uniform float iTime;'))
  ok (has (p.source, 'mainImage(proteus_fragColor, gl_FragCoord.xy);'))
  ok (not has (p.source, 'out vec4 fragColor;'))
  -- mainImage in a comment is not enough.
  local q =
    source.glsl_program ('// mainImage\nvoid main() { fragColor = vec4(1.0); }')
  eq (q.shadertoy, false)
end)

test ('a vertex shader of its own gets a version line', function ()
  local p = source.glsl_program (
    source.TEMPLATES.glsl,
    'void main() { gl_Position = vec4(0.0); }'
  )
  eq (p.vertex_offset, 1)
  ok (has (p.vertex or '', '#version 300 es\nvoid main()'))
  p = source.glsl_program (source.TEMPLATES.glsl, source.TEMPLATES.vertex)
  eq (p.vertex_offset, 0)
end)

test ('wgsl uniforms are laid out from the struct', function ()
  local p, errors = source.wgsl_program (source.TEMPLATES.wgsl)
  eq (#errors, 0)
  eq (p.vertex_entry, 'vs_main')
  eq (p.fragment_entry, 'fs_main')
  eq (#p.uniforms, 2)
  eq (p.uniforms[1].key, 'speed')
  eq (p.uniforms[1].offset, 32)
  eq (p.uniforms[1].value, { 1 })
  eq (p.uniforms[2].offset, 48)
  eq (p.uniforms[2].color, true)
  local lay = p.layout --[[@as Shader.Layout]]
  eq (lay.size, 64)
  eq (lay.fields[1].builtin, 'resolution')
  eq (lay.fields[4].builtin, 'mouse')
end)

test ('a wgsl module with no vertex stage gets one at its end', function ()
  local text =
    '@fragment\nfn main_fs(@builtin(position) p: vec4f) -> @location(0) vec4f {\n  return vec4f(1.0);\n}\n'
  local p, errors = source.wgsl_program (text)
  eq (#errors, 0)
  eq (p.vertex_entry, 'proteus_vs')
  eq (p.fragment_entry, 'main_fs')
  eq (p.source:sub (1, #text), text)
  ok (has (p.source, 'struct ProteusVertexOut'))
  eq (p.layout, nil)
end)

test ('wgsl problems name their line', function ()
  local _, errors =
    source.wgsl_program ('struct Uniforms {\n  time: f32,\n  m: mat4x4f,\n}\n')
  eq (#errors, 2)
  eq (errors[1].line, 3)
  ok (has (errors[2].message, 'fragment entry point'))
end)
