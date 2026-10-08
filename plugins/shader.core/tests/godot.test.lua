-- Godot shaders in the preview: what the translation keeps, adds and turns into notes.

local godot = require ('shader_godot') --[[@as Shader.GodotModule]]
local source = require ('shader_source') --[[@as Shader.SourceModule]]

---@param text string
---@param piece string
---@return boolean
local function has (text, piece)
  return text:find (piece, 1, true) ~= nil
end

---@param text string
---@return string[]
local function lines (text)
  local out = {} ---@type string[]
  for line in (text .. '\n'):gmatch ('([^\n]*)\n') do
    out[#out + 1] = line
  end
  return out
end

local CANVAS = table.concat ({
  'shader_type canvas_item;',
  'render_mode blend_add, unshaded;',
  'uniform float speed : hint_range(0.0, 4.0, 0.5) = 1.5; // How fast',
  'uniform vec4 tint : source_color = vec4(1.0, 0.5, 0.25, 1.0);',
  'uniform sampler2D noise : repeat_enable;',
  'varying flat vec2 world;',
  'void vertex() {',
  '  world = VERTEX;',
  '}',
  'void fragment() {',
  '  COLOR = texture(TEXTURE, UV) * tint * TIME * speed;',
  '}',
}, '\n')

test ('.gdshader files are Godot shaders', function ()
  eq ({ source.kind_of ('a/water.gdshader') }, { 'gdshader', 'fragment' })
end)

test ('a translation keeps every line where it was', function ()
  local glsl = godot.translate (CANVAS) --[[@as string]]
  local out = lines (glsl)
  local given = lines (CANVAS)
  ok (has (out[1], 'vec2 UV;') and has (out[1], 'float TIME;'))
  ok (has (out[2], '// render_mode'))
  eq (out[11], '  COLOR = texture(iChannel0, UV) * tint * TIME * speed;')
  eq (out[#given], '}')
end)

test ('uniform hints and defaults become notes', function ()
  local out = lines (godot.translate (CANVAS) --[[@as string]])
  eq (
    out[3],
    'uniform float speed; // @range 0.0 4.0 @step 0.5 @default 1.5 How fast'
  )
  eq (out[4], 'uniform vec4 tint; // @color @default 1.0 0.5 0.25 1.0')
  -- TEXTURE holds channel 0, so the sampler takes the next one.
  eq (out[5], 'uniform sampler2D noise; // @channel 1')
  eq (out[6], 'vec2 world;')
end)

test ('main runs vertex, then fragment, and writes COLOR', function ()
  local glsl = godot.translate (CANVAS) --[[@as string]]
  local v = glsl:find ('  vertex();', 1, true) --[[@as integer]]
  local f = glsl:find ('  fragment();', 1, true) --[[@as integer]]
  ok (v and f and v < f)
  ok (has (glsl, 'fragColor = COLOR;'))
end)

test ('the program has controls and the channels it reads', function ()
  local program, errors = godot.program (CANVAS)
  ok (program)
  eq (#errors, 0)
  local p = program --[[@as Shader.Program]]
  eq (p.language, 'glsl')
  eq (p.uniforms[1].key, 'speed')
  eq (p.uniforms[1].max, 4)
  eq (p.uniforms[2].color, true)
  ok (has (p.source, 'uniform highp sampler2D iChannel0;'))
  ok (has (p.source, 'in vec2 v_uv;'))
  -- Lines added above the user's first line are counted, so problems land on the right line.
  eq (
    lines (p.source)[p.offset + 11],
    lines (godot.translate (CANVAS) --[[@as string]])[11]
  )
  local indexes = {} ---@type integer[]
  for _, c in ipairs (p.channels or {}) do
    indexes[#indexes + 1] = c.index
  end
  eq (indexes, { 0, 1 })
end)

test ('a spatial shader lights ALBEDO, unless it is unshaded', function ()
  local lit = godot.translate (
    'shader_type spatial;\nvoid fragment() { ALBEDO = vec3(1.0); }'
  ) --[[@as string]]
  ok (has (lit, 'proteus_light'))
  local flat = godot.translate (
    'shader_type spatial;\nrender_mode unshaded;\nvoid fragment() { ALBEDO = vec3(1.0); }'
  ) --[[@as string]]
  ok (has (flat, 'fragColor = vec4(ALBEDO + EMISSION, ALPHA);'))
  local program = godot.program (
    'shader_type spatial;\nvoid fragment() { ALBEDO = vec3(UV, 0.0); }'
  ) --[[@as Shader.Program]]
  -- It finds its place from the UV, so the preview can put it on a mesh.
  eq (program.surface, true)
end)

test ('a sky shader runs sky()', function ()
  local glsl = godot.translate (
    'shader_type sky;\nvoid sky() { COLOR = EYEDIR * 0.5 + 0.5; }'
  ) --[[@as string]]
  ok (has (glsl, '  sky();'))
  ok (has (glsl, 'fragColor = vec4(COLOR, 1.0);'))
end)

test ('what cannot run says why', function ()
  local glsl, errors = godot.translate ('void fragment() {}')
  eq (glsl, nil)
  ok (has (errors[1].message, 'shader_type'))
  glsl, errors = godot.translate ('shader_type particles;\nvoid process() {}')
  eq (glsl, nil)
  ok (has (errors[1].message, 'particles'))
  glsl, errors = godot.translate ('shader_type canvas;')
  eq (glsl, nil)
  ok (has (errors[1].message, 'not a shader type'))
  local program, problems = source.program ('gdshader', 'void fragment() {}')
  ok (program)
  eq (#problems, 1)
end)

test ('an #include becomes a comment, with a warning', function ()
  local glsl, errors = godot.translate (
    'shader_type canvas_item;\n#include "res://lib.gdshaderinc"\n'
  )
  ok (has (glsl --[[@as string]], '// #include'))
  eq (errors[1].line, 2)
end)

test ('the template runs', function ()
  local program, errors = godot.program (source.TEMPLATES.gdshader)
  ok (program)
  eq (#errors, 0)
end)

test ('each shader type compiles as GLSL ES 3.00', function ()
  for _, text in ipairs ({
    CANVAS,
    source.TEMPLATES.gdshader,
    table.concat ({
      'shader_type spatial;',
      'uniform float height : hint_range(0, 2) = 0.5;',
      'varying vec3 pos;',
      'void vertex() { pos = VERTEX; VERTEX.y += height; }',
      'void fragment() {',
      '  ALBEDO = vec3(UV, 0.5) * pos.z;',
      '  ROUGHNESS = 0.4; EMISSION = vec3(0.1) * sin(TIME);',
      '}',
      'void light() { DIFFUSE_LIGHT += ATTENUATION * LIGHT_COLOR; }',
    }, '\n'),
    'shader_type sky;\nvoid sky() { COLOR = mix(vec3(0.2, 0.4, 0.8), LIGHT0_COLOR, max(dot(EYEDIR, LIGHT0_DIRECTION), 0.0)); }',
  }) do
    local program = godot.program (text) --[[@as Shader.Program]]
    local good, messages = shader_check ('glsl', 'fragment', program.source)
    if good == false then
      error (
        text:match ('[^\n]*') .. ' does not compile:\n' .. tostring (messages)
      )
    end
  end
end)
