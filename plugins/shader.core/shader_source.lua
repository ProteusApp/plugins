-- Shaders written as code. A GLSL file is a fragment shader, and a WGSL file is a module with
-- a fragment entry point. This module finds their uniforms, fills in what a short shader
-- leaves out, and turns each into the program the preview runs.
--
-- A uniform's line can carry notes in a comment that shape its control in the Preview panel:
--
--   uniform float u_speed; // @range 0 4 @default 1
--   uniform vec3 u_tint;   // @color @default 1 0.6 0.2
--   speed: f32,            // @range 0 4 @step 0.5
--
-- shader_passes.lua reads the notes that shape channels, such as `// @channel 0 buffer-a`.

local compile = require ('shader_compile') --[[@as Shader.CompileModule]]
local layout = require ('shader_layout') --[[@as Shader.LayoutModule]]
local passes = require ('shader_passes') --[[@as Shader.PassesModule]]

-- Uniforms the preview sets by itself, by name, with their GLSL types.
---@type table<string, string>
local GLSL_BUILTINS = {
  u_resolution = 'vec2',
  u_time = 'float',
  u_frame = 'float',
  u_mouse = 'vec4',
  u_date = 'vec4',
  iResolution = 'vec3',
  iTime = 'float',
  iTimeDelta = 'float',
  iFrame = 'int',
  iMouse = 'vec4',
  iDate = 'vec4',
  iChannelResolution = 'vec3',
}
-- The order they are declared in when a short shader leaves them out.
local GLSL_BUILTIN_ORDER = {
  'u_resolution',
  'u_time',
  'u_frame',
  'u_mouse',
  'u_date',
  'iResolution',
  'iTime',
  'iTimeDelta',
  'iFrame',
  'iMouse',
  'iDate',
  'iChannelResolution',
}
-- Builtins that are arrays, with their length.
local GLSL_ARRAYS = { iChannelResolution = passes.COUNT }

---@type table<string, Shader.UniformType>
local GLSL_TYPES = {
  float = 'float',
  vec2 = 'vec2',
  vec3 = 'vec3',
  vec4 = 'vec4',
  int = 'int',
  bool = 'bool',
}

---@type table<string, Shader.UniformType>
local WGSL_TYPES = {
  f32 = 'float',
  i32 = 'int',
  u32 = 'uint',
  vec2f = 'vec2',
  vec3f = 'vec3',
  vec4f = 'vec4',
  ['vec2<f32>'] = 'vec2',
  ['vec3<f32>'] = 'vec3',
  ['vec4<f32>'] = 'vec4',
}

---@type table<string, Shader.UniformType>
local WGSL_BUILTINS = {
  resolution = 'vec2',
  time = 'float',
  frame = 'float',
  mouse = 'vec4',
  date = 'vec4',
}

local DIMS =
  { float = 1, int = 1, uint = 1, bool = 1, vec2 = 2, vec3 = 3, vec4 = 4 }

local EXTENSIONS = {
  frag = { 'glsl', 'fragment' },
  fs = { 'glsl', 'fragment' },
  glsl = { 'glsl', 'fragment' },
  vert = { 'glsl', 'vertex' },
  vs = { 'glsl', 'vertex' },
  wgsl = { 'wgsl', 'fragment' },
}

local M = {}

M.GLSL_BUILTINS = GLSL_BUILTINS

---The language and stage of a shader file, from its name.
---@param path string
---@return Shader.Lang?, ('fragment'|'vertex')?
function M.kind_of (path)
  local ext = tostring (path or ''):lower ():match ('%.([%w]+)$')
  local e = ext and EXTENSIONS[ext]
  if e then
    return e[1], e[2]
  end
  return nil
end

---The notes in a uniform's comment.
---@param comment string
---@param t Shader.UniformType
---@return Shader.Notes
function M.notes (comment, t)
  local n = DIMS[t] or 1
  ---@type Shader.Notes
  local notes = { min = 0, max = 1, color = false, value = {} }
  local given ---@type number[]?
  for chunk in (comment or ''):gmatch ('@[^@]*') do
    local word, rest = chunk:match ('^@(%a*)(.*)$')
    local nums = {} ---@type number[]
    for num in tostring (rest):gmatch ('[-+]?%d*%.?%d+[eE]?[-+]?%d*') do
      nums[#nums + 1] = tonumber (num)
    end
    word = tostring (word):lower ()
    if word == 'range' and #nums >= 2 then
      notes.min, notes.max = nums[1], nums[2]
    elseif word == 'min' and nums[1] then
      notes.min = nums[1]
    elseif word == 'max' and nums[1] then
      notes.max = nums[1]
    elseif word == 'step' and nums[1] then
      notes.step = nums[1]
    elseif (word == 'default' or word == 'value') and #nums > 0 then
      given = nums
    elseif word == 'color' or word == 'colour' then
      notes.color = n >= 3
    end
  end
  if t == 'int' or t == 'uint' then
    notes.step = notes.step or 1
    if not comment:find ('@range') and not comment:find ('@max') then
      notes.max = 10
    end
  elseif t == 'bool' then
    notes.min, notes.max, notes.step = 0, 1, 1
  end
  local value = {} ---@type number[]
  for i = 1, n do
    local v = given and (given[i] or given[#given]) ---@type number?
    if v == nil then
      if notes.color then
        v = 1
      elseif t == 'bool' then
        v = 0
      else
        v = (notes.min + notes.max) / 2
        if notes.step then
          v = notes.min
            + math.floor ((v - notes.min) / notes.step + 0.5) * notes.step
        end
      end
    end
    value[i] = v
  end
  notes.value = value
  return notes
end

---The code with comments blanked out, keeping every line where it was.
---@param text string
---@return string
local function strip_comments (text)
  local out = text:gsub ('/%*.-%*/', function (block)
    return (block:gsub ('[^\n]', ' '))
  end)
  out = out:gsub ('//[^\n]*', '')
  return out
end

---@param text string
---@param word string
---@return boolean
local function uses (text, word)
  return text:find ('%f[%w_]' .. word .. '%f[^%w_]') ~= nil
end

---The uniforms a GLSL shader declares, apart from the ones the preview sets itself.
---@param text string
---@return Shader.Uniform[] uniforms, table<string, boolean> declared, Shader.CompileError[] errors
function M.glsl_uniforms (text)
  local list = {} ---@type Shader.Uniform[]
  local declared = {} ---@type table<string, boolean>
  local errors = {} ---@type Shader.CompileError[]
  local line_no = 0
  for line in (text .. '\n'):gmatch ('([^\n]*)\n') do
    line_no = line_no + 1
    local code, comment = line, ''
    local at = line:find ('//', 1, true)
    if at then
      code, comment = line:sub (1, at - 1), line:sub (at + 2)
    end
    for _, q in ipairs ({ 'highp', 'mediump', 'lowp' }) do
      code = code:gsub ('%f[%w_]' .. q .. '%f[^%w_]', '')
    end
    local ty, names = code:match ('^%s*uniform%s+([%w_]+)%s+([%w_%s,%[%]]+);')
    if ty and names then
      for name, size in tostring (names):gmatch ('([%w_]+)%s*(%[?[^,]*)') do
        declared[name] = true
        local t = GLSL_TYPES[ty]
        if ty:match ('sampler') then
          -- shader_passes.lua reads samplers: each one reads a channel.
        elseif size:find ('[', 1, true) and not GLSL_BUILTINS[name] then
          errors[#errors + 1] = {
            message = 'The preview has no control for an array, so '
              .. name
              .. ' stays at 0.',
            line = line_no,
            severity = 'warning',
          }
        elseif not GLSL_BUILTINS[name] and t then
          local notes = M.notes (comment, t)
          list[#list + 1] = {
            key = name,
            glsl = name,
            type = t,
            value = notes.value,
            min = notes.min,
            max = notes.max,
            step = notes.step,
            color = notes.color,
          }
        elseif
          not GLSL_BUILTINS[name]
          and not t
          and not ty:match ('sampler')
        then
          errors[#errors + 1] = {
            message = 'The preview has no control for a uniform '
              .. ty
              .. ', so '
              .. name
              .. ' stays at 0.',
            line = line_no,
            severity = 'warning',
          }
        end
      end
    end
  end
  return list, declared, errors
end

---@param source string
---@return integer
local function count_lines (source)
  local _, n = source:gsub ('\n', '\n')
  return n
end

---Makes the program the preview runs from a GLSL fragment shader, and an optional vertex
---shader. A shader with its own `#version` line runs as it is. A shorter one gets the
---version, the precision, the uniforms it uses and an output. One with Shadertoy's
---`mainImage` also gets a `main` that calls it.
---@param text string
---@param vertex? string
---@return Shader.Program program, Shader.CompileError[] errors
function M.glsl_program (text, vertex)
  local uniforms, declared, errors = M.glsl_uniforms (text)
  local code = strip_comments (text)
  local source, offset = text, 0
  local shadertoy = false
  local extra = {} ---@type integer[]
  if not code:find ('^%s*#%s*version') then
    shadertoy = uses (code, 'mainImage') and not code:find ('%f[%w_]main%s*%(')
    local head = { '#version 300 es', 'precision highp float;' } ---@type string[]
    for _, name in ipairs (GLSL_BUILTIN_ORDER) do
      if uses (code, name) and not declared[name] then
        head[#head + 1] = 'uniform '
          .. GLSL_BUILTINS[name]
          .. ' '
          .. name
          .. (GLSL_ARRAYS[name] and ('[' .. GLSL_ARRAYS[name] .. ']') or '')
          .. ';'
      end
    end
    for i = 0, passes.COUNT - 1 do
      local name = 'iChannel' .. i
      if uses (code, name) and not declared[name] then
        head[#head + 1] = 'uniform highp sampler2D ' .. name .. ';'
        extra[#extra + 1] = i
      end
    end
    if uses (code, 'v_uv') and not code:find ('in%s+vec2%s+v_uv') then
      head[#head + 1] = 'in vec2 v_uv;'
    end
    if shadertoy then
      head[#head + 1] = 'out vec4 proteus_fragColor;'
    elseif not code:find ('%f[%w_]out%s+[%w%s]-vec4%s+[%w_]+%s*;') then
      head[#head + 1] = 'out vec4 fragColor;'
    end
    offset = #head
    source = table.concat (head, '\n') .. '\n' .. text
    if shadertoy then
      source = source
        .. '\n\nvoid main() {\n'
        .. '  mainImage(proteus_fragColor, gl_FragCoord.xy);\n'
        .. '  proteus_fragColor.a = 1.0;\n'
        .. '}\n'
    end
  end
  local channels, channel_errors = passes.glsl_channels (text, extra)
  for _, e in ipairs (channel_errors) do
    errors[#errors + 1] = e
  end
  local vert = compile.GLSL_VERTEX
  local vert_offset = 0
  if vertex and vertex:find ('%S') then
    vert = vertex
    if not strip_comments (vertex):find ('^%s*#%s*version') then
      vert = '#version 300 es\n' .. vertex
      vert_offset = 1
    end
  end
  ---@type Shader.Program
  local program = {
    language = 'glsl',
    source = source,
    vertex = vert,
    uniforms = uniforms,
    offset = offset,
    vertex_offset = vert_offset,
    shadertoy = shadertoy,
    user_lines = count_lines (text) + 1,
    channels = channels,
  }
  return program, errors
end

---The fields of a WGSL module's `struct Uniforms`, with their buffer offsets.
---@param text string
---@return Shader.Layout? layout, Shader.Uniform[] uniforms, Shader.CompileError[] errors
function M.wgsl_uniforms (text)
  local errors = {} ---@type Shader.CompileError[]
  local start = text:find ('struct%s+Uniforms%s*{')
  if not start then
    return nil, {}, errors
  end
  local _, before = text:sub (1, start):gsub ('\n', '\n')
  local body_from = text:find ('{', start, true) --[[@as integer]]
  local body_to = text:find ('}', body_from, true) or #text
  local body = text:sub (body_from + 1, body_to - 1)
  local fields = {} ---@type { name: string, type: Shader.UniformType }[]
  local notes_of = {} ---@type table<string, string>
  local line_no = before + 1
  local first = true
  for line in (body .. '\n'):gmatch ('([^\n]*)\n') do
    if not first then
      line_no = line_no + 1
    end
    first = false
    local code, comment = line, ''
    local at = line:find ('//', 1, true)
    if at then
      code, comment = line:sub (1, at - 1), line:sub (at + 2)
    end
    for member in code:gmatch ('[%w_]+%s*:%s*[%w_<>]+') do
      local name, ty = member:match ('^([%w_]+)%s*:%s*(.+)$')
      local t = WGSL_TYPES[ty]
      if t then
        fields[#fields + 1] = { name = name, type = t }
        notes_of[name] = comment
      else
        errors[#errors + 1] = {
          message = 'The Uniforms struct can hold f32, i32, u32 and vec2f to vec4f, not '
            .. ty
            .. '.',
          line = line_no,
        }
      end
    end
  end
  local lay = layout.layout (fields)
  local uniforms = {} ---@type Shader.Uniform[]
  for _, f in ipairs (lay.fields) do
    if WGSL_BUILTINS[f.name] == f.type then
      f.builtin = f.name
    else
      local notes = M.notes (notes_of[f.name] or '', f.type)
      uniforms[#uniforms + 1] = {
        key = f.name,
        type = f.type,
        value = notes.value,
        min = notes.min,
        max = notes.max,
        step = notes.step,
        color = notes.color,
        offset = f.offset,
      }
    end
  end
  return lay, uniforms, errors
end

---Makes the program the preview runs from a WGSL module. A module with no vertex entry point
---gets one at its end that covers the picture, so line numbers stay the same.
---@param text string
---@return Shader.Program program, Shader.CompileError[] errors
function M.wgsl_program (text)
  local code = strip_comments (text)
  local lay, uniforms, errors = M.wgsl_uniforms (text)
  local fragment = code:match ('@fragment%s+fn%s+([%w_]+)')
  local vertex = code:match ('@vertex%s+fn%s+([%w_]+)')
  if not fragment then
    errors[#errors + 1] = {
      message = 'Add a fragment entry point, such as @fragment fn fs_main(...) -> @location(0) vec4f.',
    }
  end
  local bindings, channels, resource_errors = passes.wgsl_resources (text, code)
  for _, e in ipairs (resource_errors) do
    errors[#errors + 1] = e
  end
  local source = text
  if not vertex then
    local stage = compile.WGSL_VERTEX
      :gsub ('VertexOut', 'ProteusVertexOut')
      :gsub ('vs_main', 'proteus_vs')
    source = text .. '\n\n' .. stage .. '\n'
    vertex = 'proteus_vs'
  end
  ---@type Shader.Program
  local program = {
    language = 'wgsl',
    source = source,
    vertex_entry = vertex,
    fragment_entry = fragment or 'fs_main',
    uniforms = uniforms,
    layout = lay,
    offset = 0,
    user_lines = count_lines (text) + 1,
    channels = channels,
    bindings = bindings,
  }
  return program, errors
end

---The program for a code shader in either language.
---@param lang Shader.Lang
---@param text string
---@param vertex? string
---@return Shader.Program, Shader.CompileError[]
function M.program (lang, text, vertex)
  if lang == 'wgsl' then
    return M.wgsl_program (text)
  end
  return M.glsl_program (text, vertex)
end

-- Starting points for new files ------------------------------------------------------------

M.TEMPLATES = {
  glsl = [[
#version 300 es
precision highp float;

uniform vec2 u_resolution; // The picture's size in pixels.
uniform float u_time; // Seconds since the preview started.
uniform vec4 u_mouse; // xy: where the mouse was pressed, in pixels. z: 1 while it is down.
uniform float u_speed; // @range 0 4 @default 1
uniform vec3 u_tint; // @color @default 0.3 0.6 1.0

in vec2 v_uv; // 0 at the bottom left, 1 at the top right.
out vec4 fragColor;

void main() {
  vec2 p = (gl_FragCoord.xy - 0.5 * u_resolution) / u_resolution.y;
  float wave = 0.5 + 0.5 * sin(length(p) * 18.0 - u_time * u_speed * 3.0);
  vec3 color = mix(vec3(0.05), u_tint, wave);
  fragColor = vec4(color, 1.0);
}
]],
  wgsl = [[
// The preview fills this struct. resolution, time, frame and mouse are set every frame, and
// every other field gets a control in the Preview panel.
struct Uniforms {
  resolution: vec2f,
  time: f32,
  frame: f32,
  mouse: vec4f,
  speed: f32, // @range 0 4 @default 1
  tint: vec3f, // @color @default 0.3 0.6 1.0
}

@group(0) @binding(0) var<uniform> u: Uniforms;

struct VertexOut {
  @builtin(position) position: vec4f,
  @location(0) uv: vec2f,
}

// One triangle that covers the picture.
@vertex
fn vs_main(@builtin(vertex_index) index: u32) -> VertexOut {
  let p = vec2f(f32((index << 1u) & 2u), f32(index & 2u));
  var result: VertexOut;
  result.position = vec4f(p * 2.0 - 1.0, 0.0, 1.0);
  result.uv = p;
  return result;
}

@fragment
fn fs_main(input: VertexOut) -> @location(0) vec4f {
  let frag = vec2f(input.position.x, u.resolution.y - input.position.y);
  let p = (frag - 0.5 * u.resolution) / u.resolution.y;
  let wave = 0.5 + 0.5 * sin(length(p) * 18.0 - u.time * u.speed * 3.0);
  let color = mix(vec3f(0.05), u.tint, wave);
  return vec4f(color, 1.0);
}
]],
  shadertoy = [[
// A Shadertoy-style shader: mainImage gets the pixel position and writes its colour. The
// preview fills in iResolution, iTime, iTimeDelta, iFrame and iMouse.
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
  vec2 uv = fragCoord / iResolution.xy;
  vec3 col = 0.5 + 0.5 * cos(iTime + uv.xyx + vec3(0.0, 2.0, 4.0));
  fragColor = vec4(col, 1.0);
}
]],
  buffer = [[
// A buffer: a pass of this shader that draws into a picture of its own before the image
// each frame. The image, and every pass, can read that picture through a channel. This one
// reads its own last frame on iChannel0, so what it drew fades instead of vanishing: a
// trail behind the mouse. Set a channel of the image to this buffer to show it.
// @channel 0 {{BUFFER}}
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
  vec2 uv = fragCoord / iResolution.xy;
  vec3 last = texture(iChannel0, uv).rgb;
  vec2 mouse = iResolution.xy * (0.5 + 0.3 * vec2(cos(iTime), sin(iTime * 1.3)));
  if (iMouse.z > 0.0) {
    mouse = iMouse.xy;
  }
  float spot = 1.0 - smoothstep(0.0, 18.0, length(fragCoord - mouse));
  fragColor = vec4(max(last * 0.97, vec3(spot)), 1.0);
}
]],
  buffer_wgsl = [[
// A buffer: a pass of this shader that draws into a picture of its own before the image
// each frame. The image, and every pass, can read that picture through a channel. This one
// reads its own last frame on iChannel0, so what it drew fades instead of vanishing: a
// trail behind the mouse. Set a channel of the image to this buffer to show it.
struct Uniforms {
  resolution: vec2f,
  time: f32,
  frame: f32,
  mouse: vec4f,
}

@group(0) @binding(0) var<uniform> u: Uniforms;
@group(1) @binding(0) var iChannel0: texture_2d<f32>; // @channel 0 {{BUFFER}}
@group(1) @binding(1) var iChannel0_sampler: sampler;

@fragment
fn fs_main(@builtin(position) position: vec4f) -> @location(0) vec4f {
  // A texture's rows count from its top, as the position's y does.
  let last = textureSample(iChannel0, iChannel0_sampler, position.xy / u.resolution).rgb;
  let frag = vec2f(position.x, u.resolution.y - position.y);
  var mouse = u.resolution * (0.5 + 0.3 * vec2f(cos(u.time), sin(u.time * 1.3)));
  if (u.mouse.z > 0.0) {
    mouse = u.mouse.xy;
  }
  let spot = 1.0 - smoothstep(0.0, 18.0, length(frag - mouse));
  return vec4f(max(last * 0.97, vec3f(spot)), 1.0);
}
]],
  vertex = [[
#version 300 es
// A vertex shader for the fragment shader of the same name. It draws one triangle that
// covers the picture. The preview draws three vertices and sets no attributes.
out vec2 v_uv;

void main() {
  vec2 p = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2));
  v_uv = p;
  gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}
]],
}

return M
