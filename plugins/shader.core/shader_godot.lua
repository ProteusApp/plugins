-- Godot shaders in the preview. A .gdshader file is written in Godot's shading language, which
-- reads like GLSL. This module turns one into a GLSL fragment shader that the preview runs,
-- with every line where it was, so the compiler's problems point at the user's own lines.
--
-- The `shader_type` line becomes the declarations of Godot's built-ins, such as UV and COLOR.
-- `render_mode` lines become comments, a uniform loses its hints and default and gets notes
-- that shape its control instead, and a varying becomes a plain variable. A `main` at the end
-- fills the built-ins, runs `vertex` for each pixel, then `fragment`, and writes the colour.
--
-- canvas_item, spatial and sky shaders run. A spatial shader draws flat, lit by one light, and
-- a sky shader draws its whole sky as a flat picture. Godot's `TEXTURE` reads channel 0, and
-- each sampler uniform reads the next free channel.

local source = require ('shader_source') --[[@as Shader.SourceModule]]

local M = {}

-- Constants and the time, which every shader type has.
local COMMON = {
  'const float PI = 3.14159265359;',
  'const float TAU = 6.28318530718;',
  'const float E = 2.71828182846;',
  'float TIME;',
  'bool OUTPUT_IS_SRGB;',
}

---The built-ins of each shader type that runs, as GLSL types.
---@type table<string, string[]>
local BUILTINS = {
  canvas_item = {
    'vec2 UV',
    'vec4 COLOR',
    'vec4 FRAGCOORD',
    'vec2 SCREEN_UV',
    'vec2 SCREEN_PIXEL_SIZE',
    'vec2 TEXTURE_PIXEL_SIZE',
    'vec2 VERTEX',
    'vec2 POINT_COORD',
    'float POINT_SIZE',
    'vec3 NORMAL',
    'vec3 NORMAL_MAP',
    'float NORMAL_MAP_DEPTH',
    'vec4 SPECULAR_SHININESS',
    'vec3 LIGHT_VERTEX',
    'vec2 SHADOW_VERTEX',
    'vec4 REGION_RECT',
    'bool AT_LIGHT_PASS',
    'mat4 MODEL_MATRIX',
    'mat4 CANVAS_MATRIX',
    'mat4 SCREEN_MATRIX',
    'int INSTANCE_ID',
    'vec4 INSTANCE_CUSTOM',
    'int VERTEX_ID',
    'vec4 CUSTOM0',
    'vec4 CUSTOM1',
    'vec4 LIGHT',
    'vec4 LIGHT_COLOR',
    'float LIGHT_ENERGY',
    'vec3 LIGHT_POSITION',
    'vec3 LIGHT_DIRECTION',
    'bool LIGHT_IS_DIRECTIONAL',
    'vec4 SHADOW_MODULATE',
  },
  spatial = {
    'vec2 VIEWPORT_SIZE',
    'vec4 FRAGCOORD',
    'bool FRONT_FACING',
    'vec3 VIEW',
    'vec2 UV',
    'vec2 UV2',
    'vec4 COLOR',
    'vec2 POINT_COORD',
    'float POINT_SIZE',
    'mat4 MODEL_MATRIX',
    'mat3 MODEL_NORMAL_MATRIX',
    'mat4 VIEW_MATRIX',
    'mat4 INV_VIEW_MATRIX',
    'mat4 MAIN_CAM_INV_VIEW_MATRIX',
    'mat4 PROJECTION_MATRIX',
    'mat4 INV_PROJECTION_MATRIX',
    'mat4 MODELVIEW_MATRIX',
    'mat3 MODELVIEW_NORMAL_MATRIX',
    'vec3 NODE_POSITION_WORLD',
    'vec3 NODE_POSITION_VIEW',
    'vec3 CAMERA_POSITION_WORLD',
    'vec3 CAMERA_DIRECTION_WORLD',
    'vec3 EYE_OFFSET',
    'int VIEW_INDEX',
    'int VIEW_MONO_LEFT',
    'int VIEW_RIGHT',
    'int INSTANCE_ID',
    'vec4 INSTANCE_CUSTOM',
    'int VERTEX_ID',
    'vec4 POSITION',
    'vec3 VERTEX',
    'vec3 LIGHT_VERTEX',
    'vec2 SCREEN_UV',
    'float DEPTH',
    'vec3 NORMAL',
    'vec3 TANGENT',
    'vec3 BINORMAL',
    'vec3 NORMAL_MAP',
    'float NORMAL_MAP_DEPTH',
    'vec3 ALBEDO',
    'float ALPHA',
    'float ALPHA_SCISSOR_THRESHOLD',
    'float ALPHA_HASH_SCALE',
    'float ALPHA_ANTIALIASING_EDGE',
    'vec2 ALPHA_TEXTURE_COORDINATE',
    'float PREMUL_ALPHA_FACTOR',
    'float METALLIC',
    'float SPECULAR',
    'float ROUGHNESS',
    'float RIM',
    'float RIM_TINT',
    'float CLEARCOAT',
    'float CLEARCOAT_ROUGHNESS',
    'float ANISOTROPY',
    'vec2 ANISOTROPY_FLOW',
    'float SSS_STRENGTH',
    'vec4 SSS_TRANSMITTANCE_COLOR',
    'float SSS_TRANSMITTANCE_DEPTH',
    'float SSS_TRANSMITTANCE_BOOST',
    'vec3 BACKLIGHT',
    'float AO',
    'float AO_LIGHT_AFFECT',
    'vec3 EMISSION',
    'vec4 FOG',
    'vec4 RADIANCE',
    'vec4 IRRADIANCE',
    'vec4 CUSTOM0',
    'vec4 CUSTOM1',
    'vec4 CUSTOM2',
    'vec4 CUSTOM3',
    'vec4 BONE_WEIGHTS',
    'float Z_CLIP_SCALE',
    'float CLIP_SPACE_FAR',
    'vec3 LIGHT',
    'vec3 LIGHT_COLOR',
    'float SPECULAR_AMOUNT',
    'bool LIGHT_IS_DIRECTIONAL',
    'float ATTENUATION',
    'vec3 DIFFUSE_LIGHT',
    'vec3 SPECULAR_LIGHT',
  },
  sky = {
    'vec3 POSITION',
    'vec3 EYEDIR',
    'vec2 SCREEN_UV',
    'vec2 SKY_COORDS',
    'bool AT_HALF_RES_PASS',
    'bool AT_QUARTER_RES_PASS',
    'bool AT_CUBEMAP_PASS',
    'vec3 COLOR',
    'float ALPHA',
    'vec4 FOG',
  },
}
for i = 0, 3 do
  local n = 'LIGHT' .. i
  local sky = BUILTINS.sky
  sky[#sky + 1] = 'bool ' .. n .. '_ENABLED'
  sky[#sky + 1] = 'float ' .. n .. '_ENERGY'
  sky[#sky + 1] = 'vec3 ' .. n .. '_DIRECTION'
  sky[#sky + 1] = 'vec3 ' .. n .. '_COLOR'
  sky[#sky + 1] = 'float ' .. n .. '_SIZE'
end

-- What runs before the user's functions, for each shader type.
local SETUP = {
  canvas_item = {
    '  UV = vec2(v_uv.x, 1.0 - v_uv.y);',
    '  FRAGCOORD = vec4(gl_FragCoord.x, u_resolution.y - gl_FragCoord.y, gl_FragCoord.z, 1.0);',
    '  SCREEN_PIXEL_SIZE = 1.0 / u_resolution;',
    '  SCREEN_UV = FRAGCOORD.xy * SCREEN_PIXEL_SIZE;',
    '  TEXTURE_PIXEL_SIZE = SCREEN_PIXEL_SIZE;',
    '  VERTEX = FRAGCOORD.xy;',
    '  NORMAL = vec3(0.0, 0.0, 1.0);',
    '  NORMAL_MAP = vec3(0.5, 0.5, 1.0);',
    '  NORMAL_MAP_DEPTH = 1.0;',
    '  MODEL_MATRIX = mat4(1.0);',
    '  CANVAS_MATRIX = mat4(1.0);',
    '  SCREEN_MATRIX = mat4(1.0);',
    '  REGION_RECT = vec4(0.0, 0.0, 1.0, 1.0);',
    '  COLOR = vec4(1.0);',
  },
  spatial = {
    '  VIEWPORT_SIZE = u_resolution;',
    '  UV = vec2(v_uv.x, 1.0 - v_uv.y);',
    '  UV2 = UV;',
    '  FRAGCOORD = vec4(v_uv * u_resolution, 0.0, 1.0);',
    '  SCREEN_UV = v_uv;',
    '  FRONT_FACING = true;',
    '  VERTEX = vec3(v_uv * 2.0 - 1.0, 0.0);',
    '  NORMAL = vec3(0.0, 0.0, 1.0);',
    '  TANGENT = vec3(1.0, 0.0, 0.0);',
    '  BINORMAL = vec3(0.0, 1.0, 0.0);',
    '  VIEW = vec3(0.0, 0.0, 1.0);',
    '  MODEL_MATRIX = mat4(1.0);',
    '  MODEL_NORMAL_MATRIX = mat3(1.0);',
    '  VIEW_MATRIX = mat4(1.0);',
    '  INV_VIEW_MATRIX = mat4(1.0);',
    '  MAIN_CAM_INV_VIEW_MATRIX = mat4(1.0);',
    '  PROJECTION_MATRIX = mat4(1.0);',
    '  INV_PROJECTION_MATRIX = mat4(1.0);',
    '  MODELVIEW_MATRIX = mat4(1.0);',
    '  MODELVIEW_NORMAL_MATRIX = mat3(1.0);',
    '  COLOR = vec4(1.0);',
    '  ALBEDO = vec3(1.0);',
    '  ALPHA = 1.0;',
    '  ROUGHNESS = 1.0;',
    '  SPECULAR = 0.5;',
    '  AO = 1.0;',
    '  NORMAL_MAP = vec3(0.5, 0.5, 1.0);',
    '  NORMAL_MAP_DEPTH = 1.0;',
  },
  sky = {
    '  SCREEN_UV = v_uv;',
    '  SKY_COORDS = vec2(v_uv.x, 1.0 - v_uv.y);',
    '  float proteus_phi = (SKY_COORDS.x - 0.5) * TAU;',
    '  float proteus_theta = (0.5 - SKY_COORDS.y) * PI;',
    '  EYEDIR = vec3(cos(proteus_theta) * sin(proteus_phi), sin(proteus_theta), -cos(proteus_theta) * cos(proteus_phi));',
    '  POSITION = vec3(0.0);',
    '  LIGHT0_ENABLED = true;',
    '  LIGHT0_ENERGY = 1.0;',
    '  LIGHT0_DIRECTION = normalize(vec3(0.3, 0.5, -0.8));',
    '  LIGHT0_COLOR = vec3(1.0);',
    '  LIGHT0_SIZE = 0.05;',
    '  COLOR = vec3(0.0);',
    '  ALPHA = 1.0;',
  },
}

-- Each type's processor functions, in the order `main` runs them.
local RUNS = {
  canvas_item = { 'vertex', 'fragment' },
  spatial = { 'vertex', 'fragment' },
  sky = { 'sky' },
}

-- Shader types Godot has that the preview cannot run.
local OTHER_TYPES = { particles = true, fog = true }

M.TYPES = { 'canvas_item', 'spatial', 'sky' }

---The code with comments blanked out, keeping every character where it was.
---@param text string
---@return string
local function blank_comments (text)
  local out = text:gsub ('/%*.-%*/', function (block)
    return (block:gsub ('[^\n]', ' '))
  end)
  out = out:gsub ('//[^\n]*', function (line)
    return string.rep (' ', #line)
  end)
  return out
end

---@param text string
---@return string[]
local function lines_of (text)
  local out = {} ---@type string[]
  for line in (text .. '\n'):gmatch ('([^\n]*)\n') do
    out[#out + 1] = line
  end
  return out
end

---@param text string
---@param word string
---@return boolean
local function uses (text, word)
  return text:find ('%f[%w_]' .. word .. '%f[^%w_]') ~= nil
end

---@param s string
---@return string
local function trim (s)
  return (s:gsub ('^%s+', ''):gsub ('%s+$', ''))
end

---The text of a line's `//` comment, or ''. A `//` inside a block comment does not count.
---@param raw string The line as written.
---@param code string The same line with comments blanked out.
---@return string
local function line_comment (raw, code)
  local from = 1
  while true do
    local at = raw:find ('//', from, true)
    if not at then
      return ''
    end
    if code:sub (at, at + 1) == '  ' then
      return trim (raw:sub (at + 2))
    end
    from = at + 2
  end
end

---The notes for a uniform's hints and default, such as `@range 0 4 @default 1`.
---@param hints string What follows the `:`, or ''.
---@param default string What follows the `=`, or ''.
---@return string
local function notes_of (hints, default)
  local out = {} ---@type string[]
  local lo, hi, rest =
    hints:match ('hint_range%s*%(%s*([^,%)]+),%s*([^,%)]+)(.-)%)')
  if lo and hi then
    out[#out + 1] = '@range ' .. trim (lo) .. ' ' .. trim (hi)
    local step = rest and rest:match (',%s*([^,%)]+)')
    if step then
      out[#out + 1] = '@step ' .. trim (step)
    end
  end
  if uses (hints, 'source_color') then
    out[#out + 1] = '@color'
  end
  local values = {} ---@type string[]
  local d = default
    :gsub ('%f[%w_]true%f[^%w_]', '1')
    :gsub ('%f[%w_]false%f[^%w_]', '0')
    :gsub ('^%s*[%w_]+%s*%(', '')
  for n in d:gmatch ('%-?%d*%.?%d+[eE]?[-+]?%d*') do
    values[#values + 1] = tostring (tonumber (n) or 0)
  end
  if #values > 0 then
    out[#out + 1] = '@default ' .. table.concat (values, ' ')
  end
  return table.concat (out, ' ')
end

---Turns one uniform declaration into GLSL. Gives nil when the line holds none.
---@param code string The line with comments blanked out.
---@param comment string The line's own comment, kept after the notes.
---@param next_channel fun(): integer? The next free channel, for a sampler.
---@return string? line, string? problem
local function uniform_line (code, comment, next_channel)
  local indent, rest =
    code:match ('^(%s*)[%w_%s]-%f[%w_]uniform%f[^%w_]%s+(.-);%s*$')
  if not rest then
    return nil
  end
  local decl, hints, default = rest, '', ''
  local eq_at = decl:find ('=', 1, true)
  if eq_at then
    default = decl:sub (eq_at + 1)
    decl = decl:sub (1, eq_at - 1)
  end
  local colon = decl:find (':', 1, true)
  if colon then
    hints = decl:sub (colon + 1)
    decl = decl:sub (1, colon - 1)
  end
  decl = trim (decl)
  local is_sampler = decl:match ('^[%w_%s]-sampler') ~= nil
  local notes = ''
  local problem = nil ---@type string?
  if is_sampler then
    local i = next_channel ()
    if i then
      notes = '@channel ' .. i
    else
      problem = 'The preview has four channels, so this sampler reads nothing.'
    end
  else
    notes = notes_of (hints, default)
  end
  local tail = notes
  if comment ~= '' then
    tail = (tail ~= '' and (tail .. ' ') or '') .. comment
  end
  local line = indent
    .. 'uniform '
    .. decl
    .. ';'
    .. (tail ~= '' and (' // ' .. tail) or '')
  return line, problem
end

---The Godot shader as GLSL for the preview, and what went wrong on the way. The text is nil
---when the shader cannot run in the preview.
---@param text string
---@return string? glsl, Shader.CompileError[] errors, string? kind
function M.translate (text)
  local errors = {} ---@type Shader.CompileError[]
  local code_lines = lines_of (blank_comments (text))
  local raw_lines = lines_of (text)
  local kind = nil ---@type string?
  local modes = {} ---@type table<string, boolean>
  local out = {} ---@type string[]
  local code = blank_comments (text)
  local channel = uses (code, 'TEXTURE') and 1 or 0
  local function next_channel ()
    if channel > 3 then
      return nil
    end
    channel = channel + 1
    return channel - 1
  end
  for i, c in ipairs (code_lines) do
    local raw = raw_lines[i] or ''
    local comment = line_comment (raw, c)
    local t = c:match ('^%s*shader_type%s+([%w_]+)%s*;')
    local line = raw
    if t then
      kind = t
      if BUILTINS[t] then
        local decl = {} ---@type string[]
        for _, d in ipairs (COMMON) do
          decl[#decl + 1] = d
        end
        for _, b in ipairs (BUILTINS[t]) do
          decl[#decl + 1] = b .. ';'
        end
        line = table.concat (decl, ' ')
      else
        line = '// ' .. raw
      end
    elseif c:match ('^%s*render_mode%f[^%w_]') then
      for m in (c:match ('render_mode(.-);') or ''):gmatch ('[%w_]+') do
        modes[m] = true
      end
      line = '// ' .. raw
    elseif c:match ('^%s*group_uniforms%f[^%w_]') then
      line = '// ' .. raw
    elseif c:match ('^%s*#%s*include%f[^%w_]') then
      line = '// ' .. raw
      errors[#errors + 1] = {
        message = 'The preview does not read #include files, so what this one holds is missing.',
        line = i,
        severity = 'warning',
      }
    elseif c:match ('^%s*varying%f[^%w_]') then
      line = c:gsub ('varying%s+', '', 1)
        :gsub ('%f[%w_]flat%s+', '')
        :gsub ('%f[%w_]smooth%s+', '')
    elseif c:find ('%f[%w_]uniform%f[^%w_]') then
      local u, problem = uniform_line (c, comment, next_channel)
      if u then
        line = u
      end
      if problem then
        errors[#errors + 1] =
          { message = problem, line = i, severity = 'warning' }
      end
    end
    if kind == 'canvas_item' and not t then
      line = line:gsub ('%f[%w_]TEXTURE%f[^%w_]', 'iChannel0')
    end
    out[#out + 1] = line
  end
  if not kind then
    errors[#errors + 1] = {
      message = 'A Godot shader starts with its type, such as shader_type canvas_item;',
      line = 1,
    }
    return nil, errors, nil
  end
  if OTHER_TYPES[kind] then
    errors[#errors + 1] = {
      message = 'The preview runs canvas_item, spatial and sky shaders, not '
        .. kind
        .. ' ones.',
      line = 1,
      severity = 'warning',
    }
    return nil, errors, kind
  end
  if not BUILTINS[kind] then
    errors[#errors + 1] = {
      message = kind
        .. ' is not a shader type. Godot has canvas_item, spatial, particles, sky and fog.',
      line = 1,
    }
    return nil, errors, kind
  end
  local main = { '', 'void main() {', '  TIME = u_time;' } ---@type string[]
  for _, s in ipairs (SETUP[kind]) do
    main[#main + 1] = s
  end
  for _, fn in ipairs (RUNS[kind]) do
    if code:find ('%f[%w_]void%s+' .. fn .. '%s*%(%s*%)') then
      if
        kind == 'canvas_item'
        and fn == 'fragment'
        and uses (code, 'TEXTURE')
      then
        -- Godot's COLOR starts as the texture's colour. A channel that shows nothing leaves white.
        main[#main + 1] =
          '  if (iChannelResolution[0].x > 0.0) { TEXTURE_PIXEL_SIZE = 1.0 / iChannelResolution[0].xy; COLOR *= texture(iChannel0, UV); }'
      end
      main[#main + 1] = '  ' .. fn .. '();'
    end
  end
  if kind == 'canvas_item' then
    main[#main + 1] = '  fragColor = COLOR;'
  elseif kind == 'sky' then
    main[#main + 1] = '  fragColor = vec4(COLOR, 1.0);'
  elseif modes.unshaded then
    main[#main + 1] = '  fragColor = vec4(ALBEDO + EMISSION, ALPHA);'
  else
    main[#main + 1] =
      '  float proteus_light = max(dot(normalize(NORMAL), normalize(vec3(0.4, 0.6, 0.7))), 0.0);'
    main[#main + 1] =
      '  fragColor = vec4(ALBEDO * (0.3 + 0.7 * proteus_light) * AO + EMISSION, ALPHA);'
  end
  main[#main + 1] = '}'
  return table.concat (out, '\n') .. '\n' .. table.concat (main, '\n') .. '\n',
    errors,
    kind
end

---The program the preview runs for a Godot shader. Nil, with the reason, when it cannot run.
---@param text string
---@return Shader.Program? program, Shader.CompileError[] errors
function M.program (text)
  local glsl, errors = M.translate (text)
  if not glsl then
    return nil, errors
  end
  local program, more = source.glsl_program (glsl)
  for _, e in ipairs (more) do
    errors[#errors + 1] = e
  end
  program.user_lines = #lines_of (text)
  return program, errors
end

return M
