-- The node catalog. Each node reads its inputs and writes one line of shader code per
-- output, from a template that fits both languages or from one template for each.
--
-- In a template, `{a}` is the value of input `a`, `{T}` is the node's own type name,
-- `{@key}` is a setting, and `{>key}` is an earlier output of the same node. An input of
-- type `gen` takes the widest type wired into any `gen` input of its node, so one Add node
-- adds floats or colours alike.

local types = require ('shader_types') --[[@as Shader.TypesModule]]

---@type Shader.Category[]
local CATEGORIES = {
  { id = 'input', title = 'Input', color = '#3b82f6' },
  { id = 'value', title = 'Value', color = '#64748b' },
  { id = 'math', title = 'Math', color = '#8b5cf6' },
  { id = 'vector', title = 'Vector', color = '#0ea5e9' },
  { id = 'uv', title = 'Coordinates', color = '#14b8a6' },
  { id = 'pattern', title = 'Pattern', color = '#f59e0b' },
  { id = 'color', title = 'Colour', color = '#ec4899' },
  { id = 'custom', title = 'Custom', color = '#84cc16' },
  { id = 'output', title = 'Output', color = '#ef4444' },
}

---@param key string
---@param label string
---@param t Shader.PortType
---@param default? number[]
---@param extra? { builtin?: Shader.Builtin, color?: boolean }
---@return Shader.PortDef
local function I (key, label, t, default, extra)
  local port =
    { key = key, label = label, type = t, default = default or { 0 } }
  if extra then
    port.builtin = extra.builtin
    port.color = extra.color
  end
  return port
end

---@param key string
---@param label string
---@param t Shader.PortType|fun(settings: table<string, any>): Shader.Type
---@param glsl string|fun(ctx: Shader.EmitContext): string
---@param wgsl? string|fun(ctx: Shader.EmitContext): string
---@return Shader.OutputDef
local function O (key, label, t, glsl, wgsl)
  return { key = key, label = label, type = t, glsl = glsl, wgsl = wgsl }
end

---A hidden output: a value the other outputs share, not shown on the node.
---@param key string
---@param t Shader.PortType
---@param glsl string
---@param wgsl? string
---@return Shader.OutputDef
local function H (key, t, glsl, wgsl)
  local out = O (key, key, t, glsl, wgsl)
  out.hidden = true
  return out
end

local UV = { builtin = 'uv' } ---@type { builtin: Shader.Builtin }
local SUV = { builtin = 'suv' } ---@type { builtin: Shader.Builtin }
local CENTER = { 0.5, 0.5 }

---@type Shader.NodeDef[]
local NODES = {}

---@param spec Shader.NodeSpec
local function add (spec)
  ---@type Shader.NodeDef
  local def = {
    type = spec.type,
    title = spec.title,
    category = spec.category,
    description = spec.description,
    inputs = spec.inputs or {},
    outputs = spec.outputs,
    settings = spec.settings or {},
    helpers = spec.helpers,
    unique = spec.unique,
    texture = spec.texture,
    uniforms = spec.uniforms,
  }
  NODES[#NODES + 1] = def
end

---A node with one `gen` output from a function that both languages spell the same way.
---@param type_id string
---@param title string
---@param description string
---@param inputs Shader.PortDef[]
---@param glsl string
---@param wgsl? string
local function gen (type_id, title, description, inputs, glsl, wgsl)
  add ({
    type = type_id,
    title = title,
    category = 'math',
    description = description,
    inputs = inputs,
    outputs = { O ('out', '', 'gen', glsl, wgsl) },
  })
end

---@param type_id string
---@param title string
---@param fn string
---@param description string
---@param wgsl_fn? string
local function unary (type_id, title, fn, description, wgsl_fn)
  gen (
    type_id,
    title,
    description,
    { I ('x', 'X', 'gen') },
    fn .. '({x})',
    wgsl_fn and (wgsl_fn .. '({x})') or nil
  )
end

-- Input -------------------------------------------------------------------------------------

add ({
  type = 'uv',
  title = 'UV',
  category = 'input',
  description = 'Where the pixel sits, from 0 at the bottom left to 1 at the top right.',
  outputs = {
    O ('uv', 'uv', 'vec2', 'uv'),
    O ('x', 'x', 'float', 'uv.x'),
    O ('y', 'y', 'float', 'uv.y'),
  },
})
add ({
  type = 'square_uv',
  title = 'Square UV',
  category = 'input',
  description = 'UV with square pixels: 0 to 1 up the height, centred across the width, so circles stay round.',
  outputs = { O ('uv', 'uv', 'vec2', 'suv') },
})
add ({
  type = 'centered_uv',
  title = 'Centred UV',
  category = 'input',
  description = 'Square pixels with 0 in the middle, from -0.5 to 0.5 up the height.',
  outputs = { O ('uv', 'uv', 'vec2', 'suv - 0.5') },
})
add ({
  type = 'frag_coord',
  title = 'Pixel Position',
  category = 'input',
  description = 'The pixel position in pixels, from the bottom left.',
  outputs = { O ('xy', 'xy', 'vec2', 'fragCoord') },
})
add ({
  type = 'resolution',
  title = 'Resolution',
  category = 'input',
  description = 'The size of the picture in pixels, and its width divided by its height.',
  outputs = {
    O ('size', 'size', 'vec2', 'u_resolution', 'u.resolution'),
    O (
      'aspect',
      'aspect',
      'float',
      'u_resolution.x / u_resolution.y',
      'u.resolution.x / u.resolution.y'
    ),
  },
})
add ({
  type = 'time',
  title = 'Time',
  category = 'input',
  description = 'Seconds since the preview started, and waves that follow it.',
  outputs = {
    O ('time', 'seconds', 'float', 'u_time', 'u.time'),
    O ('sine', 'sine', 'float', 'sin(u_time)', 'sin(u.time)'),
    O ('cosine', 'cosine', 'float', 'cos(u_time)', 'cos(u.time)'),
  },
})
add ({
  type = 'frame',
  title = 'Frame',
  category = 'input',
  description = 'How many frames the preview has drawn.',
  outputs = { O ('frame', 'frame', 'float', 'u_frame', 'u.frame') },
})
add ({
  type = 'mouse',
  title = 'Mouse',
  category = 'input',
  description = 'Where the mouse was last pressed over the preview, and whether it is down now.',
  outputs = {
    O (
      'position',
      'uv',
      'vec2',
      'u_mouse.xy / u_resolution',
      'u.mouse.xy / u.resolution'
    ),
    O ('pixels', 'pixels', 'vec2', 'u_mouse.xy', 'u.mouse.xy'),
    O ('down', 'down', 'float', 'u_mouse.z', 'u.mouse.z'),
  },
})
add ({
  type = 'date',
  title = 'Date',
  category = 'input',
  description = 'The date and the time of day on this computer: the year, the month from 0, the day of the month, and the seconds since midnight.',
  uniforms = { 'date' },
  outputs = {
    O ('seconds', 'seconds', 'float', 'u_date.w', 'u.date.w'),
    O ('hours', 'hours', 'float', 'u_date.w / 3600.0', 'u.date.w / 3600.0'),
    O ('date', 'date', 'vec4', 'u_date', 'u.date'),
  },
})
add ({
  type = 'texture',
  title = 'Texture',
  category = 'input',
  description = 'Reads a channel at a UV. Under Channels, the Preview panel picks what each channel shows: noise, a checker, an image, or a buffer, which is another pass of this shader.',
  texture = true,
  inputs = { I ('uv', 'uv', 'vec2', { 0, 0 }, UV) },
  settings = {
    {
      key = 'channel',
      label = 'channel',
      kind = 'select',
      options = { 'iChannel0', 'iChannel1', 'iChannel2', 'iChannel3' },
      default = 'iChannel0',
    },
  },
  outputs = {
    -- WGSL counts a texture's rows from its top, so the y of the UV turns over.
    H (
      'sample',
      'vec4',
      'texture({@channel}, {uv})',
      'textureSampleLevel({@channel}, {@channel}_sampler, vec2f(({uv}).x, 1.0 - ({uv}).y), 0.0)'
    ),
    O ('rgb', 'rgb', 'vec3', '{>sample}.rgb'),
    O ('alpha', 'alpha', 'float', '{>sample}.a'),
    O ('rgba', 'rgba', 'vec4', '{>sample}'),
    O (
      'size',
      'size',
      'vec2',
      'vec2(textureSize({@channel}, 0))',
      'vec2f(textureDimensions({@channel}))'
    ),
  },
})

-- Value -------------------------------------------------------------------------------------

add ({
  type = 'float',
  title = 'Number',
  category = 'value',
  description = 'A fixed number.',
  settings = {
    { key = 'value', label = 'value', kind = 'number', default = 1 },
  },
  outputs = { O ('out', '', 'float', '{@value}') },
})
for n = 2, 4 do
  local t = types.of_dim (n)
  add ({
    type = t,
    title = 'Vector ' .. n,
    category = 'value',
    description = 'A fixed vector of ' .. n .. ' numbers.',
    settings = {
      {
        key = 'value',
        label = 'value',
        kind = 'vector',
        size = n,
        default = { 0, 0, 0, 1 },
      },
    },
    outputs = { O ('out', '', t, '{@value}') },
  })
end
add ({
  type = 'color',
  title = 'Colour',
  category = 'value',
  description = 'A fixed colour.',
  settings = {
    {
      key = 'value',
      label = 'colour',
      kind = 'color',
      default = { 1, 0.5, 0.2 },
    },
  },
  outputs = { O ('rgb', 'rgb', 'vec3', '{@value}') },
})
add ({
  type = 'parameter',
  title = 'Parameter',
  category = 'value',
  description = 'A value the Preview panel changes while the shader runs. It becomes a uniform.',
  settings = {
    { key = 'name', label = 'name', kind = 'name', default = 'amount' },
    {
      key = 'kind',
      label = 'type',
      kind = 'select',
      options = { 'float', 'vec2', 'vec3', 'vec4', 'color' },
      default = 'float',
    },
    {
      key = 'value',
      label = 'value',
      kind = 'vector',
      size = 4,
      default = { 0.5, 0.5, 0.5, 1 },
    },
    { key = 'min', label = 'min', kind = 'number', default = 0 },
    { key = 'max', label = 'max', kind = 'number', default = 1 },
  },
  outputs = {
    O ('out', '', function (settings)
      local kind = settings.kind
      if kind == 'color' then
        return 'vec3'
      end
      return types.is_type (kind) and kind or 'float'
    end, 'u_{@name}', 'u.{@name}'),
  },
})

-- Math --------------------------------------------------------------------------------------

gen (
  'add',
  'Add',
  'A + B.',
  { I ('a', 'A', 'gen'), I ('b', 'B', 'gen') },
  '{a} + {b}'
)
gen (
  'subtract',
  'Subtract',
  'A - B.',
  { I ('a', 'A', 'gen'), I ('b', 'B', 'gen') },
  '{a} - {b}'
)
gen (
  'multiply',
  'Multiply',
  'A × B, one component at a time.',
  { I ('a', 'A', 'gen', { 1 }), I ('b', 'B', 'gen', { 1 }) },
  '{a} * {b}'
)
gen (
  'divide',
  'Divide',
  'A ÷ B, one component at a time.',
  { I ('a', 'A', 'gen', { 1 }), I ('b', 'B', 'gen', { 1 }) },
  '{a} / {b}'
)
gen (
  'power',
  'Power',
  'Base raised to the exponent.',
  { I ('a', 'base', 'gen', { 1 }), I ('b', 'exponent', 'gen', { 2 }) },
  'pow({a}, {b})'
)
gen (
  'mod',
  'Modulo',
  'What is left after dividing A by B. It repeats from 0 up to B.',
  { I ('a', 'A', 'gen'), I ('b', 'B', 'gen', { 1 }) },
  '{a} - {b} * floor({a} / {b})'
)
gen (
  'min',
  'Minimum',
  'The smaller of A and B.',
  { I ('a', 'A', 'gen'), I ('b', 'B', 'gen') },
  'min({a}, {b})'
)
gen (
  'max',
  'Maximum',
  'The larger of A and B.',
  { I ('a', 'A', 'gen'), I ('b', 'B', 'gen') },
  'max({a}, {b})'
)
gen ('clamp', 'Clamp', 'Keeps X between min and max.', {
  I ('x', 'X', 'gen'),
  I ('lo', 'min', 'gen', { 0 }),
  I ('hi', 'max', 'gen', { 1 }),
}, 'clamp({x}, {lo}, {hi})')
gen (
  'saturate',
  'Saturate',
  'Keeps X between 0 and 1.',
  { I ('x', 'X', 'gen') },
  'clamp({x}, 0.0, 1.0)',
  'saturate({x})'
)
gen ('mix', 'Mix', 'Blends from A to B as T goes from 0 to 1.', {
  I ('a', 'A', 'gen'),
  I ('b', 'B', 'gen', { 1 }),
  I ('t', 'T', 'gen', { 0.5 }),
}, 'mix({a}, {b}, {t})')
gen (
  'step',
  'Step',
  '0 below the edge, 1 from the edge up.',
  { I ('edge', 'edge', 'gen', { 0.5 }), I ('x', 'X', 'gen') },
  'step({edge}, {x})'
)
gen (
  'smoothstep',
  'Smooth Step',
  'A smooth rise from 0 to 1 between two edges.',
  {
    I ('e0', 'from', 'gen', { 0 }),
    I ('e1', 'to', 'gen', { 1 }),
    I ('x', 'X', 'gen'),
  },
  'smoothstep({e0}, {e1}, {x})'
)
gen ('remap', 'Remap', 'Moves X from one range to another.', {
  I ('x', 'X', 'gen'),
  I ('in_lo', 'from min', 'gen', { 0 }),
  I ('in_hi', 'from max', 'gen', { 1 }),
  I ('out_lo', 'to min', 'gen', { 0 }),
  I ('out_hi', 'to max', 'gen', { 1 }),
}, '{out_lo} + ({x} - {in_lo}) * ({out_hi} - {out_lo}) / ({in_hi} - {in_lo})')
gen (
  'one_minus',
  'One Minus',
  '1 - X, which turns a mask inside out.',
  { I ('x', 'X', 'gen') },
  '1.0 - {x}'
)
gen ('negate', 'Negate', '-X.', { I ('x', 'X', 'gen') }, '-({x})')
unary ('abs', 'Absolute', 'abs', 'X without its sign.')
unary ('floor', 'Floor', 'floor', 'X rounded down.')
unary ('ceil', 'Ceiling', 'ceil', 'X rounded up.')
unary ('round', 'Round', 'round', 'X rounded to the nearest whole number.')
unary ('fract', 'Fraction', 'fract', 'The part of X after the point.')
unary ('sign', 'Sign', 'sign', '-1, 0 or 1, following the sign of X.')
unary ('sqrt', 'Square Root', 'sqrt', 'The square root of X.')
unary ('exp', 'Exponent', 'exp', 'e raised to X.')
gen (
  'log',
  'Logarithm',
  'The natural logarithm of X.',
  { I ('x', 'X', 'gen', { 1 }) },
  'log({x})'
)
unary ('sin', 'Sine', 'sin', 'The sine of X, in radians.')
unary ('cos', 'Cosine', 'cos', 'The cosine of X, in radians.')
unary ('tan', 'Tangent', 'tan', 'The tangent of X, in radians.')
gen (
  'atan2',
  'Angle of',
  'The angle of the point (X, Y), in radians.',
  { I ('y', 'Y', 'gen'), I ('x', 'X', 'gen', { 1 }) },
  'atan({y}, {x})',
  'atan2({y}, {x})'
)
gen (
  'ddx',
  'Change Across',
  'How much X changes from this pixel to the next one across: the derivative in x.',
  { I ('x', 'X', 'gen') },
  'dFdx({x})',
  'dpdx({x})'
)
gen (
  'ddy',
  'Change Up',
  'How much X changes from this pixel to the next one up: the derivative in y.',
  { I ('x', 'X', 'gen') },
  'dFdy({x})',
  'dpdy({x})'
)
gen (
  'fwidth',
  'Change Width',
  'How much X changes between neighbouring pixels, across and up together. Smooth Step over it gives edges one pixel wide.',
  { I ('x', 'X', 'gen') },
  'fwidth({x})'
)

-- What Compare offers, and how each language writes it for vectors.
---@type table<string, { glsl: string }>
local COMPARE = {
  ['<'] = { glsl = 'lessThan' },
  ['<='] = { glsl = 'lessThanEqual' },
  ['>'] = { glsl = 'greaterThan' },
  ['>='] = { glsl = 'greaterThanEqual' },
  ['=='] = { glsl = 'equal' },
  ['!='] = { glsl = 'notEqual' },
}

add ({
  type = 'compare',
  title = 'Compare',
  category = 'math',
  description = '1 where A compares to B as the setting says, and 0 elsewhere, one component at a time. Its result is a predicate for Branch.',
  inputs = { I ('a', 'A', 'gen'), I ('b', 'B', 'gen', { 0.5 }) },
  settings = {
    {
      key = 'op',
      label = 'A is',
      kind = 'select',
      options = { '<', '<=', '>', '>=', '==', '!=' },
      default = '<',
    },
  },
  outputs = {
    O ('out', '', 'gen', function (ctx)
      local op = COMPARE[ctx.settings.op] and ctx.settings.op or '<'
      local a, b = ctx.inputs.a, ctx.inputs.b
      local name = types.name (ctx.T, ctx.lang)
      if ctx.lang == 'wgsl' then
        return 'select('
          .. name
          .. '(0.0), '
          .. name
          .. '(1.0), '
          .. a
          .. ' '
          .. op
          .. ' '
          .. b
          .. ')'
      end
      if ctx.T == 'float' then
        return 'float(' .. a .. ' ' .. op .. ' ' .. b .. ')'
      end
      return name .. '(' .. COMPARE[op].glsl .. '(' .. a .. ', ' .. b .. '))'
    end),
  },
})
add ({
  type = 'branch',
  title = 'Branch',
  category = 'math',
  description = 'True where the predicate is above 0.5, and False elsewhere, one component at a time. Compare makes a predicate.',
  inputs = {
    I ('p', 'predicate', 'gen'),
    I ('yes', 'true', 'gen', { 1 }),
    I ('no', 'false', 'gen', { 0 }),
  },
  outputs = {
    O ('out', '', 'gen', function (ctx)
      local p, yes, no = ctx.inputs.p, ctx.inputs.yes, ctx.inputs.no
      local half = types.literal ({ 0.5 }, ctx.T, ctx.lang)
      if ctx.lang == 'wgsl' then
        return 'select('
          .. no
          .. ', '
          .. yes
          .. ', '
          .. p
          .. ' > '
          .. half
          .. ')'
      end
      if ctx.T == 'float' then
        return '(' .. p .. ' > 0.5 ? ' .. yes .. ' : ' .. no .. ')'
      end
      return 'mix('
        .. no
        .. ', '
        .. yes
        .. ', greaterThan('
        .. p
        .. ', '
        .. half
        .. '))'
    end),
  },
})

-- Vector ------------------------------------------------------------------------------------

---@param ctx Shader.EmitContext
---@param fn string
---@param ... string
---@return string
local function vector_only (ctx, fn, ...)
  local args = { ... }
  if ctx.T == 'float' and fn == 'dot' then
    return args[1] .. ' * ' .. args[2]
  end
  if ctx.T == 'float' and fn == 'normalize' then
    return 'sign(' .. args[1] .. ')'
  end
  return fn .. '(' .. table.concat (args, ', ') .. ')'
end

add ({
  type = 'length',
  title = 'Length',
  category = 'vector',
  description = 'How long the vector is.',
  inputs = { I ('v', 'V', 'gen') },
  outputs = { O ('out', '', 'float', 'length({v})') },
})
add ({
  type = 'distance',
  title = 'Distance',
  category = 'vector',
  description = 'How far apart A and B are.',
  inputs = { I ('a', 'A', 'gen'), I ('b', 'B', 'gen') },
  outputs = { O ('out', '', 'float', 'distance({a}, {b})') },
})
add ({
  type = 'dot',
  title = 'Dot Product',
  category = 'vector',
  description = 'A · B: how much A points along B.',
  inputs = { I ('a', 'A', 'gen'), I ('b', 'B', 'gen') },
  outputs = {
    O ('out', '', 'float', function (ctx)
      return vector_only (ctx, 'dot', ctx.inputs.a, ctx.inputs.b)
    end),
  },
})
add ({
  type = 'cross',
  title = 'Cross Product',
  category = 'vector',
  description = 'A × B: the vector at right angles to both.',
  inputs = {
    I ('a', 'A', 'vec3', { 1, 0, 0 }),
    I ('b', 'B', 'vec3', { 0, 1, 0 }),
  },
  outputs = { O ('out', '', 'vec3', 'cross({a}, {b})') },
})
add ({
  type = 'normalize',
  title = 'Normalize',
  category = 'vector',
  description = 'The vector made 1 long, pointing the same way.',
  inputs = { I ('v', 'V', 'gen', { 1 }) },
  outputs = {
    O ('out', '', 'gen', function (ctx)
      return vector_only (ctx, 'normalize', ctx.inputs.v)
    end),
  },
})
add ({
  type = 'reflect',
  title = 'Reflect',
  category = 'vector',
  description = 'The direction I bounces off a surface facing N.',
  inputs = {
    I ('i', 'I', 'vec3', { 1, -1, 0 }),
    I ('n', 'N', 'vec3', { 0, 1, 0 }),
  },
  outputs = { O ('out', '', 'vec3', 'reflect({i}, normalize({n}))') },
})

---@param ctx Shader.EmitContext
---@param index integer
---@return string
local function component (ctx, index)
  local n = types.dim (ctx.types.v)
  if n == 1 then
    return index == 1 and ctx.inputs.v or '0.0'
  end
  if index > n then
    return index == 4 and '1.0' or '0.0'
  end
  return ctx.inputs.v .. '.' .. ({ 'x', 'y', 'z', 'w' })[index]
end

add ({
  type = 'split',
  title = 'Split',
  category = 'vector',
  description = 'The components of a vector, one per output.',
  inputs = { I ('v', 'V', 'any') },
  outputs = {
    O ('x', 'x / r', 'float', function (ctx)
      return component (ctx, 1)
    end),
    O ('y', 'y / g', 'float', function (ctx)
      return component (ctx, 2)
    end),
    O ('z', 'z / b', 'float', function (ctx)
      return component (ctx, 3)
    end),
    O ('w', 'w / a', 'float', function (ctx)
      return component (ctx, 4)
    end),
  },
})
add ({
  type = 'combine',
  title = 'Combine',
  category = 'vector',
  description = 'Builds vectors from single numbers.',
  inputs = {
    I ('x', 'x / r', 'float'),
    I ('y', 'y / g', 'float'),
    I ('z', 'z / b', 'float'),
    I ('w', 'w / a', 'float', { 1 }),
  },
  outputs = {
    O ('xyz', 'vec3', 'vec3', 'vec3({x}, {y}, {z})', 'vec3f({x}, {y}, {z})'),
    O ('xy', 'vec2', 'vec2', 'vec2({x}, {y})', 'vec2f({x}, {y})'),
    O (
      'xyzw',
      'vec4',
      'vec4',
      'vec4({x}, {y}, {z}, {w})',
      'vec4f({x}, {y}, {z}, {w})'
    ),
  },
})
add ({
  type = 'swizzle',
  title = 'Swizzle',
  category = 'vector',
  description = 'Picks and reorders components by letters, such as xy, zyx or rgb.',
  inputs = { I ('v', 'V', 'vec4') },
  settings = {
    { key = 'mask', label = 'letters', kind = 'text', default = 'xyz' },
  },
  outputs = {
    O ('out', '', function (settings)
      return types.of_dim (#tostring (settings.mask or 'x'))
    end, '{v}.{@mask}'),
  },
})

-- Coordinates -------------------------------------------------------------------------------

add ({
  type = 'rotate',
  title = 'Rotate',
  category = 'uv',
  description = 'Turns coordinates around a centre by an angle in radians.',
  helpers = { 'rotate' },
  inputs = {
    I ('uv', 'uv', 'vec2', { 0, 0 }, SUV),
    I ('angle', 'angle', 'float'),
    I ('center', 'centre', 'vec2', CENTER),
  },
  outputs = {
    O ('out', 'uv', 'vec2', 'sb_rotate({uv} - {center}, {angle}) + {center}'),
  },
})
add ({
  type = 'zoom',
  title = 'Scale',
  category = 'uv',
  description = 'Scales coordinates around a centre. More than 1 zooms out.',
  inputs = {
    I ('uv', 'uv', 'vec2', { 0, 0 }, SUV),
    I ('scale', 'scale', 'vec2', { 2 }),
    I ('center', 'centre', 'vec2', CENTER),
  },
  outputs = {
    O ('out', 'uv', 'vec2', '({uv} - {center}) * {scale} + {center}'),
  },
})
add ({
  type = 'tile',
  title = 'Tile',
  category = 'uv',
  description = 'Repeats coordinates in a grid. Cell numbers each tile.',
  inputs = {
    I ('uv', 'uv', 'vec2', { 0, 0 }, UV),
    I ('count', 'count', 'vec2', { 4 }),
  },
  outputs = {
    O ('uv', 'uv', 'vec2', 'fract({uv} * {count})'),
    O ('cell', 'cell', 'vec2', 'floor({uv} * {count})'),
  },
})
add ({
  type = 'polar',
  title = 'Polar',
  category = 'uv',
  description = 'Distance and angle from a centre.',
  inputs = {
    I ('uv', 'uv', 'vec2', { 0, 0 }, SUV),
    I ('center', 'centre', 'vec2', CENTER),
  },
  outputs = {
    H ('d', 'vec2', '{uv} - {center}'),
    O ('radius', 'radius', 'float', 'length({>d})'),
    O (
      'angle',
      'angle',
      'float',
      'atan({>d}.y, {>d}.x)',
      'atan2({>d}.y, {>d}.x)'
    ),
    O ('turn', '0 to 1', 'float', '{>angle} / 6.2831853 + 0.5'),
  },
})

-- Pattern -----------------------------------------------------------------------------------

---@param type_id string
---@param title string
---@param description string
---@param fn string
---@param helper string
---@param scale number
local function noise (type_id, title, description, fn, helper, scale)
  add ({
    type = type_id,
    title = title,
    category = 'pattern',
    description = description,
    helpers = { helper },
    inputs = {
      I ('uv', 'uv', 'vec2', { 0, 0 }, UV),
      I ('scale', 'scale', 'float', { scale }),
      I ('offset', 'offset', 'vec2', { 0 }),
    },
    outputs = { O ('out', '', 'float', fn .. '({uv} * {scale} + {offset})') },
  })
end

noise (
  'value_noise',
  'Value Noise',
  'Soft random blobs from 0 to 1.',
  'sb_value_noise',
  'value_noise',
  8
)
noise (
  'gradient_noise',
  'Gradient Noise',
  'Smooth Perlin-style noise from 0 to 1.',
  'sb_gradient_noise',
  'gradient_noise',
  6
)
add ({
  type = 'fbm',
  title = 'Fractal Noise',
  category = 'pattern',
  description = 'Layers of noise, each finer than the last, for clouds, smoke and terrain.',
  helpers = { 'fbm' },
  inputs = {
    I ('uv', 'uv', 'vec2', { 0, 0 }, UV),
    I ('scale', 'scale', 'float', { 4 }),
    I ('offset', 'offset', 'vec2', { 0 }),
    I ('lacunarity', 'detail step', 'float', { 2 }),
    I ('gain', 'roughness', 'float', { 0.5 }),
  },
  settings = {
    {
      key = 'octaves',
      label = 'layers',
      kind = 'int',
      default = 5,
      min = 1,
      max = 12,
    },
  },
  outputs = {
    O (
      'out',
      '',
      'float',
      'sb_fbm({uv} * {scale} + {offset}, {@octaves}, {lacunarity}, {gain})'
    ),
  },
})
add ({
  type = 'voronoi',
  title = 'Voronoi',
  category = 'pattern',
  description = 'Cells around random points: the distance to the nearest point, and a random number for each cell.',
  helpers = { 'voronoi' },
  inputs = {
    I ('uv', 'uv', 'vec2', { 0, 0 }, UV),
    I ('scale', 'scale', 'float', { 6 }),
    I ('offset', 'offset', 'vec2', { 0 }),
  },
  outputs = {
    H ('pair', 'vec2', 'sb_voronoi({uv} * {scale} + {offset})'),
    O ('distance', 'distance', 'float', '{>pair}.x'),
    O ('cell', 'cell', 'float', '{>pair}.y'),
  },
})
add ({
  type = 'random',
  title = 'Random',
  category = 'pattern',
  description = 'A random number from 0 to 1 that stays the same for the same seed.',
  helpers = { 'hash' },
  inputs = { I ('seed', 'seed', 'vec2', { 0, 0 }, { builtin = 'frag' }) },
  outputs = { O ('out', '', 'float', 'sb_hash({seed})') },
})
add ({
  type = 'checker',
  title = 'Checker',
  category = 'pattern',
  description = 'A checkerboard of 0 and 1.',
  inputs = {
    I ('uv', 'uv', 'vec2', { 0, 0 }, SUV),
    I ('scale', 'squares', 'float', { 8 }),
  },
  outputs = {
    O (
      'out',
      '',
      'float',
      'step(0.5, fract((floor({uv}.x * {scale}) + floor({uv}.y * {scale})) * 0.5))'
    ),
  },
})
add ({
  type = 'stripes',
  title = 'Stripes',
  category = 'pattern',
  description = 'Soft stripes from 0 to 1, turned by an angle in radians.',
  inputs = {
    I ('uv', 'uv', 'vec2', { 0, 0 }, SUV),
    I ('count', 'count', 'float', { 10 }),
    I ('angle', 'angle', 'float'),
  },
  outputs = {
    O (
      'out',
      '',
      'float',
      '0.5 + 0.5 * sin(({uv}.x * cos({angle}) + {uv}.y * sin({angle})) * {count} * 6.2831853)'
    ),
  },
})
add ({
  type = 'circle',
  title = 'Circle',
  category = 'pattern',
  description = 'A disc: 1 inside, 0 outside, with a soft edge.',
  inputs = {
    I ('uv', 'uv', 'vec2', { 0, 0 }, SUV),
    I ('center', 'centre', 'vec2', CENTER),
    I ('radius', 'radius', 'float', { 0.3 }),
    I ('soft', 'softness', 'float', { 0.005 }),
  },
  outputs = {
    O ('distance', 'distance', 'float', 'length({uv} - {center}) - {radius}'),
    O (
      'mask',
      'mask',
      'float',
      '1.0 - smoothstep(-max({soft}, 0.0001), max({soft}, 0.0001), {>distance})'
    ),
  },
})
add ({
  type = 'ring',
  title = 'Ring',
  category = 'pattern',
  description = 'A ring: 1 on the line, 0 elsewhere.',
  inputs = {
    I ('uv', 'uv', 'vec2', { 0, 0 }, SUV),
    I ('center', 'centre', 'vec2', CENTER),
    I ('radius', 'radius', 'float', { 0.3 }),
    I ('width', 'width', 'float', { 0.02 }),
    I ('soft', 'softness', 'float', { 0.005 }),
  },
  outputs = {
    O (
      'distance',
      'distance',
      'float',
      'abs(length({uv} - {center}) - {radius}) - {width}'
    ),
    O (
      'mask',
      'mask',
      'float',
      '1.0 - smoothstep(-max({soft}, 0.0001), max({soft}, 0.0001), {>distance})'
    ),
  },
})
add ({
  type = 'box',
  title = 'Rectangle',
  category = 'pattern',
  description = 'A rectangle: 1 inside, 0 outside. Size is half the width and height.',
  inputs = {
    I ('uv', 'uv', 'vec2', { 0, 0 }, SUV),
    I ('center', 'centre', 'vec2', CENTER),
    I ('size', 'half size', 'vec2', { 0.25, 0.15 }),
    I ('soft', 'softness', 'float', { 0.005 }),
  },
  outputs = {
    H ('q', 'vec2', 'abs({uv} - {center}) - {size}'),
    O (
      'distance',
      'distance',
      'float',
      'length(max({>q}, vec2(0.0))) + min(max({>q}.x, {>q}.y), 0.0)',
      'length(max({>q}, vec2f(0.0))) + min(max({>q}.x, {>q}.y), 0.0)'
    ),
    O (
      'mask',
      'mask',
      'float',
      '1.0 - smoothstep(-max({soft}, 0.0001), max({soft}, 0.0001), {>distance})'
    ),
  },
})

-- Colour ------------------------------------------------------------------------------------

add ({
  type = 'hsv_to_rgb',
  title = 'HSV to RGB',
  category = 'color',
  description = 'A colour from hue, saturation and value, each from 0 to 1.',
  helpers = { 'hsv2rgb' },
  inputs = { I ('hsv', 'hsv', 'vec3', { 0, 1, 1 }) },
  outputs = { O ('rgb', 'rgb', 'vec3', 'sb_hsv2rgb({hsv})') },
})
add ({
  type = 'rgb_to_hsv',
  title = 'RGB to HSV',
  category = 'color',
  description = 'The hue, saturation and value of a colour.',
  helpers = { 'rgb2hsv' },
  inputs = { I ('rgb', 'rgb', 'vec3', { 1, 0.5, 0.2 }, { color = true }) },
  outputs = { O ('hsv', 'hsv', 'vec3', 'sb_rgb2hsv({rgb})') },
})
add ({
  type = 'palette',
  title = 'Cosine Palette',
  category = 'color',
  description = 'A smooth band of colours as T goes from 0 to 1, from four colours that shape it.',
  inputs = {
    I ('t', 'T', 'float'),
    I ('a', 'base', 'vec3', { 0.5, 0.5, 0.5 }, { color = true }),
    I ('b', 'contrast', 'vec3', { 0.5, 0.5, 0.5 }, { color = true }),
    I ('c', 'frequency', 'vec3', { 1, 1, 1 }),
    I ('d', 'phase', 'vec3', { 0, 0.33, 0.67 }),
  },
  outputs = {
    O ('rgb', 'rgb', 'vec3', '{a} + {b} * cos(6.2831853 * ({c} * {t} + {d}))'),
  },
})
add ({
  type = 'luminance',
  title = 'Brightness',
  category = 'color',
  description = 'How bright a colour looks, from 0 to 1.',
  inputs = { I ('rgb', 'rgb', 'vec3', { 1, 1, 1 }, { color = true }) },
  outputs = {
    O (
      'out',
      '',
      'float',
      'dot({rgb}, vec3(0.2126, 0.7152, 0.0722))',
      'dot({rgb}, vec3f(0.2126, 0.7152, 0.0722))'
    ),
  },
})
add ({
  type = 'contrast',
  title = 'Contrast',
  category = 'color',
  description = 'Pushes a colour away from grey, or towards it below 1.',
  inputs = {
    I ('rgb', 'colour', 'gen', { 0.5 }),
    I ('amount', 'amount', 'float', { 1.5 }),
  },
  outputs = { O ('out', '', 'gen', '({rgb} - 0.5) * {amount} + 0.5') },
})
add ({
  type = 'gamma',
  title = 'Gamma',
  category = 'color',
  description = 'Raises a colour to 1 / gamma, which lightens the darks above 1.',
  inputs = {
    I ('rgb', 'colour', 'gen', { 0.5 }),
    I ('gamma', 'gamma', 'float', { 2.2 }),
  },
  outputs = {
    O ('out', '', 'gen', 'pow(max({rgb}, {T}(0.0)), {T}(1.0 / {gamma}))'),
  },
})

-- Custom ------------------------------------------------------------------------------------

---`atan` with two arguments is `atan2` in WGSL.
---@param args string
---@return string
local function atan_call (args)
  return (args:find (',', 1, true) and 'atan2' or 'atan') .. args
end

---GLSL has no `saturate`.
---@param args string
---@return string
local function saturate_call (args)
  return 'clamp(' .. args:sub (2, -2) .. ', 0.0, 1.0)'
end

---Turns an expression written with either language's names into one language.
---@param text string
---@param lang Shader.Lang
---@return string
local function dialect (text, lang)
  local out = text ---@type string
  if lang == 'wgsl' then
    out = string.gsub (out, '%f[%w_]vec([234])%f[^%w_]%s*%(', 'vec%1f(') --[[@as string]]
    out = string.gsub (out, '%f[%w_]float%s*%(', 'f32(') --[[@as string]]
    out = string.gsub (out, '%f[%w_]int%s*%(', 'i32(') --[[@as string]]
    out = string.gsub (out, '%f[%w_]atan%s*(%b())', atan_call) --[[@as string]]
  else
    out = string.gsub (out, '%f[%w_]vec([234])f%s*%(', 'vec%1(') --[[@as string]]
    out = string.gsub (out, '%f[%w_]f32%s*%(', 'float(') --[[@as string]]
    out = string.gsub (out, '%f[%w_]i32%s*%(', 'int(') --[[@as string]]
    out = string.gsub (out, '%f[%w_]atan2%s*%(', 'atan(') --[[@as string]]
    out = string.gsub (out, '%f[%w_]saturate%s*(%b())', saturate_call) --[[@as string]]
  end
  return out
end

add ({
  type = 'expression',
  title = 'Expression',
  category = 'custom',
  description = 'Any expression over a, b, c and d, such as sin(a * 3.0) + b. Functions both languages share work in each, and vec3( and vec3f( both read right. The result is as wide as the widest input unless its type is set.',
  inputs = {
    I ('a', 'a', 'any'),
    I ('b', 'b', 'any'),
    I ('c', 'c', 'any'),
    I ('d', 'd', 'any'),
  },
  settings = {
    { key = 'expr', label = 'expression', kind = 'code', default = 'a' },
    {
      key = 'type',
      label = 'result',
      kind = 'select',
      options = { 'auto', 'float', 'vec2', 'vec3', 'vec4' },
      default = 'auto',
    },
  },
  outputs = {
    O ('out', '', function (settings)
      -- Auto takes the widest type wired in.
      return types.is_type (settings.type) and settings.type or 'gen'
    end, function (ctx)
      local text = tostring (ctx.settings.expr or '')
      -- Stand-in names so a, b, c and d swap for their values in one pass.
      text = text:gsub ('%f[%w_]([abcd])%f[^%w_]', function (name)
        return '\1' .. name .. '\2'
      end)
      text = dialect (text, ctx.lang)
      return (
        text:gsub ('\1(%a)\2', function (name)
          return ctx.inputs[name]
        end)
      )
    end),
  },
})

-- Output ------------------------------------------------------------------------------------

add ({
  type = 'output',
  title = 'Output',
  category = 'output',
  description = 'The colour of each pixel. Every shader has one.',
  unique = true,
  inputs = {
    I ('color', 'colour', 'vec3', { 0, 0, 0 }, { color = true }),
    I ('alpha', 'alpha', 'float', { 1 }),
  },
  outputs = {},
})

local BY_TYPE = {} ---@type table<string, Shader.NodeDef>
for _, def in ipairs (NODES) do
  BY_TYPE[def.type] = def
end

local M = {}

M.categories = CATEGORIES
M.list = NODES
M.dialect = dialect

---@param type_id string
---@return Shader.NodeDef?
function M.get (type_id)
  return BY_TYPE[type_id]
end

---@param id string
---@return Shader.Category?
function M.category (id)
  for _, c in ipairs (CATEGORIES) do
    if c.id == id then
      return c
    end
  end
  return nil
end

---The setting's value on a node, or its default.
---@param def Shader.NodeDef
---@param settings table<string, any>?
---@param key string
---@return any
function M.setting (def, settings, key)
  local value = settings and settings[key]
  if value ~= nil then
    return value
  end
  for _, s in ipairs (def.settings) do
    if s.key == key then
      return s.default
    end
  end
  return nil
end

---Every setting of a node, defaults filled in.
---@param def Shader.NodeDef
---@param settings table<string, any>?
---@return table<string, any>
function M.settings_of (def, settings)
  local out = {} ---@type table<string, any>
  for _, s in ipairs (def.settings) do
    out[s.key] = M.setting (def, settings, s.key)
  end
  return out
end

---The type of an output, before `gen` is worked out.
---@param def Shader.NodeDef
---@param out Shader.OutputDef
---@param settings table<string, any>?
---@return Shader.PortType
function M.output_type (def, out, settings)
  local t = out.type
  if type (t) == 'function' then
    return t (M.settings_of (def, settings))
  end
  return t --[[@as Shader.PortType]]
end

---The outputs a node shows, leaving out the hidden ones.
---@param def Shader.NodeDef
---@return Shader.OutputDef[]
function M.visible_outputs (def)
  local out = {} ---@type Shader.OutputDef[]
  for _, o in ipairs (def.outputs) do
    if not o.hidden then
      out[#out + 1] = o
    end
  end
  return out
end

---@param def Shader.NodeDef
---@param key string
---@return Shader.PortDef?
function M.input (def, key)
  for _, p in ipairs (def.inputs) do
    if p.key == key then
      return p
    end
  end
  return nil
end

---@param def Shader.NodeDef
---@param key string
---@return Shader.OutputDef?
function M.output (def, key)
  for _, o in ipairs (def.outputs) do
    if o.key == key and not o.hidden then
      return o
    end
  end
  return nil
end

return M
