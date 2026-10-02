-- Exports a compiled graph to other engines: HLSL for Direct3D, a Godot shader, a three.js
-- ShaderMaterial, and a Unity shader. Each starts from the compiled program (`result.ir`):
-- the values in order, each one GLSL expression, the helpers they call, the uniforms and the
-- channels. GLSL expressions go into the other languages through a small rewriter that
-- renames types and functions and turns calls that differ, such as `mix` into `lerp`.
--
-- Every export reads its place from the UV the vertex stage gives it, the way the compiled
-- GLSL does, so it colours the surface of any mesh, and `fragCoord` is the UV times
-- `u_resolution`.

local helpers = require ('shader_helpers') --[[@as Shader.HelpersModule]]
local types = require ('shader_types') --[[@as Shader.TypesModule]]

local M = {}

---@type Shader.ExportTarget[]
M.TARGETS = {
  {
    id = 'hlsl',
    title = 'HLSL',
    ending = '.hlsl',
    about = 'A vertex and a pixel shader in HLSL for Direct3D 11 and later',
  },
  {
    id = 'godot',
    title = 'Godot',
    ending = '.gdshader',
    about = 'A canvas item shader for Godot 4',
  },
  {
    id = 'three',
    title = 'three.js',
    ending = '.three.js',
    about = 'A JavaScript module that makes a three.js ShaderMaterial',
  },
  {
    id = 'unity',
    title = 'Unity',
    ending = '.shader',
    about = 'An unlit Unity shader in ShaderLab, for the built-in render pipeline',
  },
}

-- The size a shader thinks it draws at when the engine does not say, in pixels.
local DEFAULT_SIZE = 512

-- Rewriting GLSL ------------------------------------------------------------------------------

---@class Shader.Token
---@field kind 'name'|'number'|'space'|'other'
---@field text string

---Splits GLSL into names, numbers, spaces and single characters. A comment is one space.
---@param text string
---@return Shader.Token[]
local function tokens (text)
  local out = {} ---@type Shader.Token[]
  local i = 1
  local n = #text
  while i <= n do
    local c = text:sub (i, i)
    local name = text:match ('^[%a_][%w_]*', i)
    if name then
      out[#out + 1] = { kind = 'name', text = name }
      i = i + #name
    elseif
      c:match ('%d') or (c == '.' and text:sub (i + 1, i + 1):match ('%d'))
    then
      local num = text:match ('^%d*%.?%d*', i) --[[@as string]]
      local exp = text:match ('^[eE][-+]?%d+', i + #num) or ''
      local suffix = text:match ('^[uUfF]', i + #num + #exp) or ''
      local whole = num .. exp .. suffix
      out[#out + 1] = { kind = 'number', text = whole }
      i = i + #whole
    elseif text:sub (i, i + 1) == '//' then
      local stop = text:find ('\n', i, true) or (n + 1)
      out[#out + 1] = { kind = 'space', text = text:sub (i, stop - 1) }
      i = stop
    elseif c:match ('%s') then
      local space = text:match ('^%s+', i) --[[@as string]]
      out[#out + 1] = { kind = 'space', text = space }
      i = i + #space
    else
      out[#out + 1] = { kind = 'other', text = c }
      i = i + 1
    end
  end
  return out
end

---@param s string
---@return string
local function trim (s)
  return (s:match ('^%s*(.-)%s*$'))
end

-- GLSL's vector and matrix types, and their HLSL names.
---@type table<string, string>
local HLSL_TYPES = {
  vec2 = 'float2',
  vec3 = 'float3',
  vec4 = 'float4',
  ivec2 = 'int2',
  ivec3 = 'int3',
  ivec4 = 'int4',
  uvec2 = 'uint2',
  uvec3 = 'uint3',
  uvec4 = 'uint4',
  bvec2 = 'bool2',
  bvec3 = 'bool3',
  bvec4 = 'bool4',
  mat2 = 'float2x2',
  mat3 = 'float3x3',
  mat4 = 'float4x4',
}

-- GLSL functions HLSL spells another way.
---@type table<string, string>
local HLSL_CALLS = {
  mix = 'lerp',
  fract = 'frac',
  inversesqrt = 'rsqrt',
  dFdx = 'ddx',
  dFdy = 'ddy',
  mod = 'sb_mod',
}

-- GLSL's comparisons of vectors, as operators.
---@type table<string, string>
local COMPARE = {
  lessThan = '<',
  lessThanEqual = '<=',
  greaterThan = '>',
  greaterThanEqual = '>=',
  equal = '==',
  notEqual = '!=',
}

---How one language writes what GLSL writes.
---@class Shader.Dialect
---@field hlsl boolean Types, casts, functions and comparisons as HLSL has them.
---@field names table<string, string> Names to write another way, such as `u_time`.
---@field texture? fun(channel: string, uv: string): string How a texture read is written.
---@field texture_size? fun(channel: string): string How a texture's size is written.

---Rewrites GLSL in another language.
---@param text string
---@param dialect Shader.Dialect
---@param used table<string, boolean> Gets the helpers the result needs: `mod` and `texture_size`.
---@return string
local function rewrite (text, dialect, used)
  local list = tokens (text)
  local pos = 1

  ---@param name string
  ---@return string
  local function rename (name)
    local out = dialect.names[name]
    if out then
      return out
    end
    if dialect.hlsl and HLSL_TYPES[name] then
      return HLSL_TYPES[name]
    end
    return name
  end

  ---@param name string
  ---@param args string[]
  ---@param gap string The space between the name and its bracket.
  ---@return string
  local function call (name, args, gap)
    local clean = {} ---@type string[]
    for i, a in ipairs (args) do
      clean[i] = trim (a)
    end
    if name == 'texture' and #clean >= 2 and dialect.texture then
      return dialect.texture (clean[1], clean[2])
    end
    if name == 'textureSize' and #clean >= 1 and dialect.texture_size then
      used.texture_size = true
      return dialect.texture_size (clean[1])
    end
    if dialect.hlsl then
      local t = HLSL_TYPES[name]
        or (
          (name == 'float' or name == 'int' or name == 'uint' or name == 'bool')
          and name
        )
      if t and #clean == 1 then
        -- HLSL makes a vector from one number only by a cast.
        return '((' .. t .. ')(' .. clean[1] .. '))'
      end
      if t then
        return t .. '(' .. table.concat (clean, ', ') .. ')'
      end
      if COMPARE[name] and #clean == 2 then
        return '(('
          .. clean[1]
          .. ') '
          .. COMPARE[name]
          .. ' ('
          .. clean[2]
          .. '))'
      end
      if name == 'not' and #clean == 1 then
        return '(!(' .. clean[1] .. '))'
      end
      if name == 'atan' and #clean == 2 then
        return 'atan2(' .. table.concat (clean, ', ') .. ')'
      end
      if
        name == 'mix'
        and #clean == 3
        and clean[3]:match ('^%(%(.*%) [<>=!]=? %(.*%)%)$')
      then
        -- A blend by a comparison picks one side or the other.
        return 'lerp('
          .. clean[1]
          .. ', '
          .. clean[2]
          .. ', ('
          .. clean[3]
          .. ' ? 1.0 : 0.0))'
      end
      if name == 'mod' then
        used.mod = true
      end
      if HLSL_CALLS[name] then
        return HLSL_CALLS[name] .. '(' .. table.concat (clean, ', ') .. ')'
      end
    end
    return rename (name) .. gap .. '(' .. table.concat (args, ',') .. ')'
  end

  ---The text up to a token in `stop` at this depth, which is left for the caller.
  ---@param stop table<string, boolean>
  ---@return string
  local function run (stop)
    local out = {} ---@type string[]
    while pos <= #list do
      local t = list[pos]
      if t.kind == 'other' and stop[t.text] then
        break
      end
      if t.kind == 'name' then
        local j = pos + 1
        local gap = ''
        while list[j] and list[j].kind == 'space' do
          gap = gap .. list[j].text
          j = j + 1
        end
        if list[j] and list[j].text == '(' then
          pos = j + 1
          local args = {} ---@type string[]
          local k = pos
          while list[k] and list[k].kind == 'space' do
            k = k + 1
          end
          if list[k] and list[k].text == ')' then
            pos = k + 1
          else
            while pos <= #list do
              args[#args + 1] = run ({ [','] = true, [')'] = true })
              local sep = list[pos]
              pos = pos + 1
              if not sep or sep.text == ')' then
                break
              end
            end
          end
          out[#out + 1] = call (t.text, args, gap)
        else
          out[#out + 1] = rename (t.text)
          pos = pos + 1
        end
      elseif t.text == '(' then
        pos = pos + 1
        local inner = run ({ [')'] = true })
        pos = pos + 1
        out[#out + 1] = '(' .. inner .. ')'
      else
        out[#out + 1] = t.text
        pos = pos + 1
      end
    end
    return table.concat (out)
  end

  local result = {} ---@type string[]
  while pos <= #list do
    result[#result + 1] = run ({})
    -- A bracket that closes nothing stays as it is.
    if pos <= #list then
      result[#result + 1] = list[pos].text
      pos = pos + 1
    end
  end
  return table.concat (result)
end

M.rewrite = rewrite

-- Pieces every export shares -------------------------------------------------------------------

---A name for a comment or a string: one line, with no quotes or backslashes.
---@param text string
---@return string
local function plain (text)
  local out = tostring (text or ''):gsub ('[%c"\\`]', ' '):gsub ('%*/', '* /')
  out = trim (out)
  return out ~= '' and out or 'Untitled'
end

---@param n number
---@return string
local function num (n)
  return types.number (n)
end

---A number as JavaScript and ShaderLab write it, such as `1` or `0.5`.
---@param n number
---@return string
local function short (n)
  return (types.number (n):gsub ('%.0$', ''))
end

---The numbers of a uniform's starting value, as many as its type has.
---@param u Shader.Uniform
---@return number[]
local function values_of (u)
  local out = {} ---@type number[]
  for i = 1, types.dim (u.type --[[@as Shader.Type]]) do
    out[i] = tonumber (u.value[i]) or 0
  end
  return out
end

---The builtin uniforms an export declares, with their types: the four every shader has,
---then the ones its nodes ask for.
---@param ir Shader.Ir
---@return { name: string, type: Shader.Type, about: string }[]
local function builtins (ir)
  local out = {
    {
      name = 'u_resolution',
      type = 'vec2',
      about = 'the size it draws at, in pixels',
    },
    { name = 'u_time', type = 'float', about = 'seconds' },
    { name = 'u_frame', type = 'float', about = 'frames drawn' },
    {
      name = 'u_mouse',
      type = 'vec4',
      about = 'x and y in pixels from the bottom left, z is 1 while pressed',
    },
  } ---@type { name: string, type: Shader.Type, about: string }[]
  for _, name in ipairs (ir.extra) do
    if name == 'date' then
      out[#out + 1] = {
        name = 'u_date',
        type = 'vec4',
        about = 'year, month from 0, day, seconds since midnight',
      }
    end
  end
  return out
end

---The body of the fragment stage in one language: each value, then nothing more. The colour
---and alpha come back for the caller to write out.
---@param ir Shader.Ir
---@param dialect Shader.Dialect
---@param used table<string, boolean>
---@param type_name fun(t: Shader.Type): string
---@param indent string
---@return string[] lines
---@return string color
---@return string alpha
local function body (ir, dialect, used, type_name, indent)
  local lines = {} ---@type string[]
  for _, s in ipairs (ir.steps) do
    lines[#lines + 1] = indent
      .. type_name (s.type)
      .. ' '
      .. s.var
      .. ' = '
      .. rewrite (s.glsl, dialect, used)
      .. ';'
  end
  return lines,
    rewrite (ir.color, dialect, used),
    rewrite (ir.alpha, dialect, used)
end

---The helpers the values call, in one dialect.
---@param ir Shader.Ir
---@param dialect? Shader.Dialect Nil keeps them as GLSL.
---@param used table<string, boolean>
---@return string[]
local function helper_sources (ir, dialect, used)
  local out = {} ---@type string[]
  for _, src in ipairs (helpers.sources (ir.helpers, 'glsl')) do
    out[#out + 1] = dialect and rewrite (src, dialect, used) or src
  end
  return out
end

---True when the shader sets an alpha of its own, so the engine should blend it.
---@param ir Shader.Ir
---@return boolean
local function blends (ir)
  return trim (ir.alpha) ~= '1.0'
end

---Lines with each one moved right, leaving empty lines empty.
---@param text string
---@param indent string
---@return string[]
local function indented (text, indent)
  local out = {} ---@type string[]
  for line in (text .. '\n'):gmatch ('([^\n]*)\n') do
    out[#out + 1] = line == '' and '' or (indent .. line)
  end
  return out
end

---@param t Shader.Type
---@return string
local function hlsl_type (t)
  return t == 'float' and 'float' or HLSL_TYPES[t]
end

---@param t Shader.Type
---@return string
local function glsl_type (t)
  return types.name (t, 'glsl')
end

---Where each field of an HLSL constant buffer sits: packed in order, and none crosses a
---16-byte boundary.
---@param fields { type: Shader.Type }[]
---@return integer[]
local function hlsl_offsets (fields)
  local out = {} ---@type integer[]
  local at = 0
  for i, f in ipairs (fields) do
    local size = types.dim (f.type) * 4
    if at % 16 + size > 16 then
      at = at + (16 - at % 16)
    end
    out[i] = at
    at = at + size
  end
  return out
end

-- HLSL ------------------------------------------------------------------------------------

local HLSL_MOD = '#define sb_mod(x, y) ((x) - (y) * floor((x) / (y)))'
local HLSL_SIZE = [[
float2 sb_texture_size(Texture2D t)
{
  uint w, h;
  t.GetDimensions(w, h);
  return float2(w, h);
}]]

---HLSL for Direct3D 11 and later: a constant buffer, the channels as textures, a vertex
---shader that covers the target with one triangle, and the pixel shader.
---@param ir Shader.Ir
---@return string
function M.hlsl (ir)
  local used = {} ---@type table<string, boolean>
  ---@type Shader.Dialect
  local dialect = {
    hlsl = true,
    names = {},
    -- Direct3D counts a texture's rows from its top, so the y of the UV turns over.
    texture = function (channel, uv)
      return channel
        .. '.Sample('
        .. channel
        .. '_sampler, float2(('
        .. uv
        .. ').x, 1.0 - ('
        .. uv
        .. ').y))'
    end,
    texture_size = function (channel)
      return 'sb_texture_size(' .. channel .. ')'
    end,
  }
  local lines, color, alpha = body (ir, dialect, used, hlsl_type, '  ')
  local helper_list = helper_sources (ir, dialect, used)
  local fields = {} ---@type { name: string, type: Shader.Type, about: string }[]
  for _, b in ipairs (builtins (ir)) do
    fields[#fields + 1] = b
  end
  for _, u in ipairs (ir.uniforms) do
    local about = u.color and 'a colour'
      or ('from ' .. short (u.min) .. ' to ' .. short (u.max))
    fields[#fields + 1] = {
      name = u.glsl or ('u_' .. u.key),
      type = u.type --[[@as Shader.Type]],
      about = about,
    }
  end
  local offsets = hlsl_offsets (fields)
  ---@type string[]
  local out = {
    '// ' .. plain (ir.name) .. ', built with the Proteus shader builder.',
    '// HLSL for Direct3D 11 and later. VSMain draws one triangle over the whole target from',
    '// SV_VertexID alone, so draw 3 vertices with no vertex buffer. On a mesh, pass its UV in',
    '// TEXCOORD0 instead. PSMain colours each pixel. Fill Uniforms each frame at the offsets',
    "// below, which follow HLSL's packing rules.",
    '',
    'cbuffer Uniforms : register(b0)',
    '{',
  }
  for i, f in ipairs (fields) do
    out[#out + 1] = '  '
      .. hlsl_type (f.type)
      .. ' '
      .. f.name
      .. '; // offset '
      .. offsets[i]
      .. ': '
      .. f.about
  end
  out[#out + 1] = '};'
  for _, c in ipairs (ir.channels) do
    out[#out + 1] = ''
    out[#out + 1] = 'Texture2D iChannel'
      .. c.index
      .. ' : register(t'
      .. c.index
      .. ');'
    out[#out + 1] = 'SamplerState iChannel'
      .. c.index
      .. '_sampler : register(s'
      .. c.index
      .. ');'
  end
  if used.mod then
    out[#out + 1] = ''
    out[#out + 1] = HLSL_MOD
  end
  if used.texture_size then
    out[#out + 1] = ''
    out[#out + 1] = HLSL_SIZE
  end
  for _, src in ipairs (helper_list) do
    out[#out + 1] = ''
    out[#out + 1] = src
  end
  local tail = {
    '',
    'struct VSOut',
    '{',
    '  float4 position : SV_Position;',
    '  float2 uv : TEXCOORD0;',
    '};',
    '',
    'VSOut VSMain(uint id : SV_VertexID)',
    '{',
    '  float2 p = float2((id << 1) & 2, id & 2);',
    '  VSOut o;',
    '  o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);',
    '  o.uv = p;',
    '  return o;',
    '}',
    '',
    'float4 PSMain(VSOut frag_in) : SV_Target',
    '{',
    '  float2 uv = frag_in.uv;',
    '  float2 fragCoord = uv * u_resolution;',
    '  float2 suv = (fragCoord - 0.5 * u_resolution) / u_resolution.y + 0.5;',
  }
  for _, line in ipairs (tail) do
    out[#out + 1] = line
  end
  for _, line in ipairs (lines) do
    out[#out + 1] = line
  end
  out[#out + 1] = '  return float4(' .. color .. ', ' .. alpha .. ');'
  out[#out + 1] = '}'
  out[#out + 1] = ''
  return table.concat (out, '\n')
end

-- Godot -----------------------------------------------------------------------------------

---A Godot 4 canvas item shader. Godot keeps the time itself, and the rest are uniforms.
---@param ir Shader.Ir
---@return string
function M.godot (ir)
  local used = {} ---@type table<string, boolean>
  ---@type Shader.Dialect
  local dialect = {
    hlsl = false,
    names = { u_time = 'TIME' },
    -- Godot counts a texture's rows from its top, so the y of the UV turns over.
    texture = function (channel, uv)
      return 'texture('
        .. channel
        .. ', vec2(('
        .. uv
        .. ').x, 1.0 - ('
        .. uv
        .. ').y))'
    end,
  }
  local lines, color, alpha = body (ir, dialect, used, glsl_type, '  ')
  ---@type string[]
  local out = {
    '// ' .. plain (ir.name) .. ', built with the Proteus shader builder.',
    '// A canvas item shader for Godot 4. Put it in a ShaderMaterial on a ColorRect or a',
    '// Sprite2D. u_resolution is the size it draws at, in pixels, and Godot keeps the time.',
    'shader_type canvas_item;',
    '',
    'uniform vec2 u_resolution = vec2(' .. num (DEFAULT_SIZE) .. ', ' .. num (
      DEFAULT_SIZE
    ) .. ');',
  }
  for _, b in ipairs (builtins (ir)) do
    if b.name ~= 'u_resolution' and b.name ~= 'u_time' then
      out[#out + 1] = 'uniform '
        .. glsl_type (b.type)
        .. ' '
        .. b.name
        .. '; // '
        .. b.about
    end
  end
  for _, u in ipairs (ir.uniforms) do
    local t = u.type --[[@as Shader.Type]]
    local hint = ''
    if u.color then
      hint = ' : source_color'
    elseif t == 'float' and u.max > u.min then
      hint = ' : hint_range(' .. num (u.min) .. ', ' .. num (u.max) .. ')'
    end
    out[#out + 1] = 'uniform '
      .. glsl_type (t)
      .. ' '
      .. (u.glsl or ('u_' .. u.key))
      .. hint
      .. ' = '
      .. types.literal (values_of (u), t, 'glsl')
      .. ';'
  end
  for _, c in ipairs (ir.channels) do
    out[#out + 1] = 'uniform sampler2D iChannel'
      .. c.index
      .. ' : repeat_enable, filter_linear;'
  end
  for _, src in ipairs (helper_sources (ir, dialect, used)) do
    out[#out + 1] = ''
    out[#out + 1] = src
  end
  out[#out + 1] = ''
  out[#out + 1] = 'void fragment() {'
  out[#out + 1] =
    '  // Godot counts UV from the top left. These shaders count from the bottom left.'
  out[#out + 1] = '  vec2 uv = vec2(UV.x, 1.0 - UV.y);'
  out[#out + 1] = '  vec2 fragCoord = uv * u_resolution;'
  out[#out + 1] =
    '  vec2 suv = (fragCoord - 0.5 * u_resolution) / u_resolution.y + 0.5;'
  for _, line in ipairs (lines) do
    out[#out + 1] = line
  end
  out[#out + 1] = '  COLOR = vec4(' .. color .. ', ' .. alpha .. ');'
  out[#out + 1] = '}'
  out[#out + 1] = ''
  return table.concat (out, '\n')
end

-- three.js --------------------------------------------------------------------------------

---Code for a JavaScript template string: backslashes, backticks and `${` kept as text.
---@param text string
---@return string
local function template (text)
  return (text:gsub ('\\', '\\\\'):gsub ('`', '\\`'):gsub ('%${', '\\${'))
end

---A JavaScript module that makes a three.js ShaderMaterial. The material colours any mesh
---from its UV.
---@param ir Shader.Ir
---@return string
function M.three (ir)
  local used = {} ---@type table<string, boolean>
  ---@type Shader.Dialect
  local dialect = { hlsl = false, names = {} }
  local lines, color, alpha = body (ir, dialect, used, glsl_type, '  ')
  local frag = {} ---@type string[]
  for _, b in ipairs (builtins (ir)) do
    frag[#frag + 1] = 'uniform ' .. glsl_type (b.type) .. ' ' .. b.name .. ';'
  end
  for _, u in ipairs (ir.uniforms) do
    frag[#frag + 1] = 'uniform '
      .. glsl_type (u.type --[[@as Shader.Type]])
      .. ' '
      .. (u.glsl or ('u_' .. u.key))
      .. ';'
  end
  for _, c in ipairs (ir.channels) do
    frag[#frag + 1] = 'uniform sampler2D iChannel' .. c.index .. ';'
  end
  frag[#frag + 1] = ''
  frag[#frag + 1] = 'in vec2 v_uv;'
  for _, src in ipairs (helper_sources (ir, nil, used)) do
    frag[#frag + 1] = ''
    frag[#frag + 1] = src
  end
  frag[#frag + 1] = ''
  frag[#frag + 1] = 'void main() {'
  frag[#frag + 1] = '  vec2 uv = v_uv;'
  frag[#frag + 1] = '  vec2 fragCoord = uv * u_resolution;'
  frag[#frag + 1] =
    '  vec2 suv = (fragCoord - 0.5 * u_resolution) / u_resolution.y + 0.5;'
  for _, line in ipairs (lines) do
    frag[#frag + 1] = line
  end
  frag[#frag + 1] = '  gl_FragColor = vec4(' .. color .. ', ' .. alpha .. ');'
  frag[#frag + 1] = '}'

  -- What the module takes from three.js.
  ---@type table<string, boolean>
  local needs =
    { GLSL3 = true, ShaderMaterial = true, Vector2 = true, Vector4 = true }
  local VECTORS = { vec2 = 'Vector2', vec3 = 'Vector3', vec4 = 'Vector4' }
  ---@param t Shader.Type
  ---@param values number[]
  ---@return string
  local function js_value (t, values)
    if t == 'float' then
      return short (values[1] or 0)
    end
    local parts = {} ---@type string[]
    for i = 1, types.dim (t) do
      parts[i] = short (values[i] or 0)
    end
    needs[VECTORS[t]] = true
    return 'new ' .. VECTORS[t] .. '(' .. table.concat (parts, ', ') .. ')'
  end
  local uniform_lines = {
    '      u_resolution: { value: new Vector2('
      .. DEFAULT_SIZE
      .. ', '
      .. DEFAULT_SIZE
      .. ') },',
    '      u_time: { value: 0 },',
    '      u_frame: { value: 0 },',
    '      u_mouse: { value: new Vector4(0, 0, 0, 0) },',
  }
  for _, name in ipairs (ir.extra) do
    if name == 'date' then
      uniform_lines[#uniform_lines + 1] =
        '      u_date: { value: new Vector4(0, 0, 0, 0) },'
    end
  end
  for _, u in ipairs (ir.uniforms) do
    uniform_lines[#uniform_lines + 1] = '      '
      .. (u.glsl or ('u_' .. u.key))
      .. ': { value: '
      .. js_value (u.type --[[@as Shader.Type]], values_of (u))
      .. ' },'
  end
  for _, c in ipairs (ir.channels) do
    uniform_lines[#uniform_lines + 1] = '      iChannel'
      .. c.index
      .. ': { value: null },'
  end
  local imports = {} ---@type string[]
  for name in pairs (needs) do
    imports[#imports + 1] = name
  end
  table.sort (imports)

  ---@type string[]
  local out = {
    '// ' .. plain (ir.name) .. ', built with the Proteus shader builder.',
    '// A three.js ShaderMaterial. Put createMaterial() on any mesh: the shader colours its',
    '// surface from its UV. Set u_time each frame, and a texture on each iChannel.',
    'import { ' .. table.concat (imports, ', ') .. " } from 'three';",
    '',
    'export const vertexShader = /* glsl */ `',
    'out vec2 v_uv;',
    '',
    'void main() {',
    '  v_uv = uv;',
    '  gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);',
    '}',
    '`;',
    '',
    'export const fragmentShader = /* glsl */ `',
    template (table.concat (frag, '\n')),
    '`;',
    '',
    'export function createMaterial() {',
    '  return new ShaderMaterial({',
    '    glslVersion: GLSL3,',
    '    uniforms: {',
  }
  for _, line in ipairs (uniform_lines) do
    out[#out + 1] = line
  end
  out[#out + 1] = '    },'
  out[#out + 1] = '    vertexShader,'
  out[#out + 1] = '    fragmentShader,'
  if blends (ir) then
    out[#out + 1] = '    transparent: true,'
  end
  out[#out + 1] = '  });'
  out[#out + 1] = '}'
  out[#out + 1] = ''
  return table.concat (out, '\n')
end

-- Unity -----------------------------------------------------------------------------------

---An unlit Unity shader in ShaderLab, with a Cg/HLSL pass for the built-in render pipeline.
---@param ir Shader.Ir
---@return string
function M.unity (ir)
  local used = {} ---@type table<string, boolean>
  local names = { u_time = '_Time.y' } ---@type table<string, string>
  for _, c in ipairs (ir.channels) do
    names['iChannel' .. c.index] = '_Channel' .. c.index
  end
  ---@type Shader.Dialect
  local dialect = {
    hlsl = true,
    names = names,
    -- Unity turns textures over itself where it needs to, so the UV stays as it is.
    texture = function (channel, uv)
      return 'tex2D(' .. channel .. ', ' .. uv .. ')'
    end,
    texture_size = function (channel)
      return channel .. '_TexelSize.zw'
    end,
  }
  local lines, color, alpha = body (ir, dialect, used, hlsl_type, '  ')
  local helper_list = helper_sources (ir, dialect, used)
  -- The Cg/HLSL code of the pass, before it moves right.
  local code = {
    '#pragma vertex vert',
    '#pragma fragment frag',
    '#include "UnityCG.cginc"',
    '',
  } ---@type string[]
  for _, b in ipairs (builtins (ir)) do
    if b.name ~= 'u_time' then
      code[#code + 1] = hlsl_type (b.type)
        .. ' '
        .. b.name
        .. '; // '
        .. b.about
    end
  end
  for _, u in ipairs (ir.uniforms) do
    code[#code + 1] = hlsl_type (u.type --[[@as Shader.Type]])
      .. ' '
      .. (u.glsl or ('u_' .. u.key))
      .. ';'
  end
  for _, c in ipairs (ir.channels) do
    code[#code + 1] = 'sampler2D _Channel' .. c.index .. ';'
    code[#code + 1] = 'float4 _Channel' .. c.index .. '_TexelSize;'
  end
  if used.mod then
    code[#code + 1] = ''
    code[#code + 1] = HLSL_MOD
  end
  for _, src in ipairs (helper_list) do
    code[#code + 1] = ''
    code[#code + 1] = src
  end
  local tail = {
    '',
    'struct appdata',
    '{',
    '  float4 vertex : POSITION;',
    '  float2 uv : TEXCOORD0;',
    '};',
    '',
    'struct v2f',
    '{',
    '  float4 pos : SV_POSITION;',
    '  float2 uv : TEXCOORD0;',
    '};',
    '',
    'v2f vert(appdata v)',
    '{',
    '  v2f o;',
    '  o.pos = UnityObjectToClipPos(v.vertex);',
    '  o.uv = v.uv;',
    '  return o;',
    '}',
    '',
    'float4 frag(v2f frag_in) : SV_Target',
    '{',
    '  float2 uv = frag_in.uv;',
    '  float2 fragCoord = uv * u_resolution;',
    '  float2 suv = (fragCoord - 0.5 * u_resolution) / u_resolution.y + 0.5;',
  }
  for _, line in ipairs (tail) do
    code[#code + 1] = line
  end
  for _, line in ipairs (lines) do
    code[#code + 1] = line
  end
  code[#code + 1] = '  return float4(' .. color .. ', ' .. alpha .. ');'
  code[#code + 1] = '}'

  local name = plain (ir.name)
  ---@type string[]
  local out = {
    '// ' .. name .. ', built with the Proteus shader builder.',
    '// An unlit Unity shader for the built-in render pipeline. Make a material from it and put',
    '// it on any mesh: the shader colours the surface from its UV. Unity keeps the time.',
    'Shader "Proteus/' .. name .. '"',
    '{',
    '  Properties',
    '  {',
    '    u_resolution ("Resolution", Vector) = ('
      .. DEFAULT_SIZE
      .. ', '
      .. DEFAULT_SIZE
      .. ', 0, 0)',
  }
  for _, u in ipairs (ir.uniforms) do
    local values = values_of (u)
    local prop ---@type string
    if u.color then
      prop = 'Color) = ('
        .. short (values[1] or 0)
        .. ', '
        .. short (values[2] or 0)
        .. ', '
        .. short (values[3] or 0)
        .. ', 1)'
    elseif u.type == 'float' then
      if u.max > u.min then
        prop = 'Range('
          .. short (u.min)
          .. ', '
          .. short (u.max)
          .. ')) = '
          .. short (values[1])
      else
        prop = 'Float) = ' .. short (values[1])
      end
    else
      local parts = {} ---@type string[]
      for i = 1, 4 do
        parts[i] = short (values[i] or 0)
      end
      prop = 'Vector) = (' .. table.concat (parts, ', ') .. ')'
    end
    out[#out + 1] = '    '
      .. (u.glsl or ('u_' .. u.key))
      .. ' ("'
      .. plain (u.key)
      .. '", '
      .. prop
  end
  for _, c in ipairs (ir.channels) do
    out[#out + 1] = '    _Channel'
      .. c.index
      .. ' ("iChannel'
      .. c.index
      .. '", 2D) = "white" {}'
  end
  out[#out + 1] = '  }'
  out[#out + 1] = '  SubShader'
  out[#out + 1] = '  {'
  if blends (ir) then
    out[#out + 1] =
      '    Tags { "RenderType" = "Transparent" "Queue" = "Transparent" }'
  else
    out[#out + 1] = '    Tags { "RenderType" = "Opaque" }'
  end
  out[#out + 1] = '    Pass'
  out[#out + 1] = '    {'
  if blends (ir) then
    out[#out + 1] = '      Blend SrcAlpha OneMinusSrcAlpha'
    out[#out + 1] = '      ZWrite Off'
  end
  out[#out + 1] = '      CGPROGRAM'
  for _, line in ipairs (indented (table.concat (code, '\n'), '      ')) do
    out[#out + 1] = line
  end
  out[#out + 1] = '      ENDCG'
  out[#out + 1] = '    }'
  out[#out + 1] = '  }'
  out[#out + 1] = '}'
  out[#out + 1] = ''
  return table.concat (out, '\n')
end

---The export for one target, by its id in `TARGETS`.
---@param id string
---@param ir Shader.Ir
---@return string?
function M.export (id, ir)
  local fn = ({
    hlsl = M.hlsl,
    godot = M.godot,
    three = M.three,
    unity = M.unity,
  })[id]
  return fn and fn (ir) or nil
end

---The target with this id.
---@param id string
---@return Shader.ExportTarget?
function M.target (id)
  for _, t in ipairs (M.TARGETS) do
    if t.id == id then
      return t
    end
  end
  return nil
end

return M
