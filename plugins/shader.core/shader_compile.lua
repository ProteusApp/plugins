-- Turns a shader graph into complete shaders: a GLSL ES 3.00 vertex and fragment shader for
-- WebGL 2, and one WGSL module for WebGPU. Both come from the same pass over the graph, so
-- they compute the same picture.
--
-- Only the nodes the Output node reads are written. Each output a later node reads becomes
-- one local, in an order where every value comes before its first use.

local graph = require ('shader_graph') --[[@as Shader.GraphModule]]
local helpers = require ('shader_helpers') --[[@as Shader.HelpersModule]]
local layout = require ('shader_layout') --[[@as Shader.LayoutModule]]
local nodes = require ('shader_nodes') --[[@as Shader.NodesModule]]
local passes = require ('shader_passes') --[[@as Shader.PassesModule]]
local subgraph = require ('shader_subgraph') --[[@as Shader.SubgraphModule]]
local types = require ('shader_types') --[[@as Shader.TypesModule]]

-- The uniforms every shader gets, in their WGSL order.
---@type { name: string, type: Shader.UniformType }[]
local BUILTIN_FIELDS = {
  { name = 'resolution', type = 'vec2' },
  { name = 'time', type = 'float' },
  { name = 'frame', type = 'float' },
  { name = 'mouse', type = 'vec4' },
}

-- Uniforms a shader gets only when a node asks for them, such as the Date node.
---@type table<string, { glsl: string, type: Shader.UniformType }>
local OPTIONAL_FIELDS = { date = { glsl = 'u_date', type = 'vec4' } }

local BUILTIN_NAMES =
  { resolution = true, time = true, frame = true, mouse = true, date = true }

---What an unwired input with a `builtin` reads, and its type.
---@type table<Shader.Builtin, string>
local BUILTINS = { uv = 'uv', suv = 'suv', frag = 'fragCoord' }

local GLSL_VERTEX = [[
#version 300 es
// One triangle that covers the whole picture, made from gl_VertexID alone.
out vec2 v_uv;

void main() {
  vec2 p = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2));
  v_uv = p;
  gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}
]]

local WGSL_VERTEX = [[
struct VertexOut {
  @builtin(position) position: vec4f,
  @location(0) uv: vec2f,
}

// One triangle that covers the whole picture, made from the vertex index alone.
@vertex
fn vs_main(@builtin(vertex_index) index: u32) -> VertexOut {
  let p = vec2f(f32((index << 1u) & 2u), f32(index & 2u));
  var result: VertexOut;
  result.position = vec4f(p * 2.0 - 1.0, 0.0, 1.0);
  result.uv = p;
  return result;
}]]

local M = {}

M.GLSL_VERTEX = GLSL_VERTEX
M.WGSL_VERTEX = WGSL_VERTEX
M.BUILTIN_FIELDS = BUILTIN_FIELDS

---Why a parameter name will not do, or nil when it will.
---@param name any
---@return string?
function M.bad_name (name)
  if type (name) ~= 'string' or not name:match ('^[%a_][%w_]*$') then
    return 'A parameter name is letters, digits and _, and starts with a letter.'
  end
  if name:sub (1, 2) == '__' or name == '_' then
    return 'A parameter name cannot start with __.'
  end
  if BUILTIN_NAMES[name] then
    return 'The shader has a ' .. name .. ' already. Pick another name.'
  end
  if layout.reserved (name) then
    return 'WGSL keeps the word ' .. name .. ' for itself. Pick another name.'
  end
  return nil
end

---A name for a comment: one line, with nothing that could end the comment.
---@param text string
---@return string
local function comment_text (text)
  return (tostring (text or ''):gsub ('[%c]', ' '):gsub ('%*/', '* /'))
end

---@param template string|fun(ctx: Shader.EmitContext): string
---@param ctx Shader.EmitContext
---@param own table<string, string> This node's earlier outputs, by key.
---@param def Shader.NodeDef
---@return string
local function fill (template, ctx, own, def)
  if type (template) == 'function' then
    return template (ctx)
  end
  ---@param key string
  ---@return string
  local function replace (key)
    if key == 'T' then
      return types.name (ctx.T, ctx.lang)
    end
    local first, rest = key:sub (1, 1), key:sub (2)
    if first == '>' then
      return own[rest] or '0.0'
    end
    if first == '@' then
      local value = ctx.settings[rest]
      local spec ---@type Shader.SettingDef?
      for _, s in ipairs (def.settings) do
        if s.key == rest then
          spec = s
        end
      end
      local kind = spec and spec.kind or 'text'
      if kind == 'number' then
        return types.number (tonumber (value) or 0)
      elseif kind == 'int' then
        return tostring (math.floor (tonumber (value) or 0))
      elseif kind == 'color' then
        return types.literal (value, 'vec3', ctx.lang)
      elseif kind == 'vector' then
        return types.literal (
          value,
          types.of_dim (spec and spec.size or 4),
          ctx.lang
        )
      end
      return tostring (value or '')
    end
    return ctx.inputs[key] or '0.0'
  end
  return (template:gsub ('{([^{}]+)}', replace))
end

---The outputs of a node a template refers to with `{>key}`.
---@param out Shader.OutputDef
---@param lang Shader.Lang
---@return string[]
local function refs (out, lang)
  local list = {} ---@type string[]
  local t = out[lang] or out.glsl
  if type (t) == 'string' then
    for key in t:gmatch ('{>([%w_]+)}') do
      list[#list + 1] = key
    end
  end
  return list
end

---Why a node's settings cannot make code, or nil.
---@param n Shader.Node
---@param def Shader.NodeDef
---@param settings table<string, any>
---@return string?
local function check_settings (n, def, settings)
  if def.texture then
    -- The channel's name goes into the code as it is.
    if not passes.channel_of_name (tostring (settings.channel)) then
      return 'Pick a channel, iChannel0 to iChannel3.'
    end
  elseif n.type == 'parameter' then
    return M.bad_name (settings.name)
  elseif n.type == 'swizzle' then
    local mask = tostring (settings.mask or '')
    if
      #mask < 1
      or #mask > 4
      or not (mask:match ('^[xyzw]+$') or mask:match ('^[rgba]+$'))
    then
      return 'Letters are 1 to 4 of x, y, z, w, or of r, g, b, a.'
    end
  elseif n.type == 'expression' then
    local expr = tostring (settings.expr or '')
    if not expr:find ('%S') then
      return 'The expression is empty.'
    end
    if expr:find ('[;{}]') then
      return 'An expression cannot hold ; { or }.'
    end
  end
  return nil
end

---@param n number
---@return string
local function short (n)
  return (types.number (n):gsub ('%.0$', ''))
end

---The note after a uniform that gives it a control when the code is opened as code.
---@param p Shader.Uniform
---@return string
local function notes (p)
  local values = {} ---@type string[]
  for i, v in ipairs (p.value) do
    values[i] = short (v)
  end
  if p.color then
    return ' // @color @default ' .. table.concat (values, ' ')
  end
  return ' // @range '
    .. short (p.min)
    .. ' '
    .. short (p.max)
    .. ' @default '
    .. table.concat (values, ' ')
end

---Orders the nodes the Output node reads, each after the nodes it reads.
---@param doc Shader.Doc
---@param start string
---@param into table<string, table<string, Shader.Edge>>
---@return string[]? order, string? error, string? node
local function order_from (doc, start, into)
  local state = {} ---@type table<string, 'open'|'done'>
  local order = {} ---@type string[]
  local fail, fail_node ---@type string?, string?
  ---@param id string
  local function visit (id)
    if fail then
      return
    end
    if state[id] == 'done' then
      return
    end
    if state[id] == 'open' then
      fail, fail_node = 'These wires make a loop.', id
      return
    end
    state[id] = 'open'
    local n = graph.node (doc, id)
    local def = n and nodes.get (n.type)
    if def then
      for _, port in ipairs (def.inputs) do
        local e = into[id] and into[id][port.key]
        if e then
          visit (e.from)
        end
      end
    end
    state[id] = 'done'
    order[#order + 1] = id
  end
  visit (start)
  if fail then
    return nil, fail, fail_node
  end
  return order
end

---Compiles a graph without made nodes.
---@param doc Shader.Doc
---@return Shader.CompileResult
local function compile_flat (doc)
  local errors = {} ---@type Shader.CompileError[]
  ---@param message string
  ---@param node? string
  local function problem (message, node)
    errors[#errors + 1] = { message = message, node = node }
  end

  -- The wires that still fit their nodes, by the input they end in.
  local into = {} ---@type table<string, table<string, Shader.Edge>>
  for _, e in ipairs (doc.edges or {}) do
    local a, b = graph.node (doc, e.from), graph.node (doc, e.to)
    local da, db = a and nodes.get (a.type), b and nodes.get (b.type)
    if
      da
      and db
      and nodes.output (da, e.output)
      and nodes.input (db, e.input)
    then
      into[e.to] = into[e.to] or {}
      into[e.to][e.input] = e
    end
  end

  local output_id ---@type string?
  for _, n in ipairs (doc.nodes or {}) do
    if not nodes.get (n.type) then
      problem ('There is no node called ' .. tostring (n.type) .. '.', n.id)
    elseif n.type == 'output' then
      if output_id then
        problem ('Only the first Output node counts.', n.id)
      else
        output_id = n.id
      end
    end
  end

  local order = {} ---@type string[]
  if output_id then
    local list, err, where = order_from (doc, output_id, into)
    if list then
      order = list
    else
      problem (err or 'These wires make a loop.', where)
    end
  else
    problem ('Add an Output node. Its colour is the picture.')
  end

  -- Which outputs something reads.
  local used = {} ---@type table<string, table<string, boolean>>
  local reached = {} ---@type table<string, boolean>
  for _, id in ipairs (order) do
    reached[id] = true
  end
  for to, inputs in pairs (into) do
    if reached[to] then
      for _, e in pairs (inputs) do
        used[e.from] = used[e.from] or {}
        used[e.from][e.output] = true
      end
    end
  end

  local out_types = {} ---@type table<string, table<string, Shader.Type>>
  local vars = {} ---@type table<string, table<string, string>>
  local broken = {} ---@type table<string, boolean>
  local stmts = { glsl = {}, wgsl = {} } ---@type table<Shader.Lang, { text: string, node: string }[]>
  local needs = {} ---@type table<string, boolean>
  local params = {} ---@type Shader.Uniform[]
  local param_names = {} ---@type table<string, boolean>
  local final = { glsl = {}, wgsl = {} } ---@type table<Shader.Lang, table<string, string>>
  local node_types = {} ---@type table<string, table<string, Shader.Type>>
  -- The channels Texture nodes read, and the uniforms nodes ask for beyond the four.
  local reads = {} ---@type table<integer, string[]>
  local wants = {} ---@type table<string, boolean>
  -- Each value in GLSL, in order, for the exporters to write in other languages.
  local steps = {} ---@type Shader.Step[]

  for _, id in ipairs (order) do
    local n = graph.node (doc, id) --[[@as Shader.Node]]
    local def = nodes.get (n.type) --[[@as Shader.NodeDef]]
    local settings = nodes.settings_of (def, n.settings)
    local bad = check_settings (n, def, settings)
    if n.type == 'parameter' and not bad then
      if param_names[settings.name] then
        bad = 'Another Parameter is called '
          .. tostring (settings.name)
          .. ' already.'
      end
    end

    -- What each input receives, and the node's own type.
    local src = {} ---@type table<string, Shader.Type>
    local gen_list = {} ---@type Shader.Type[]
    local any_list = {} ---@type Shader.Type[]
    for _, port in ipairs (def.inputs) do
      local e = into[id] and into[id][port.key]
      local t ---@type Shader.Type
      if e and not broken[e.from] and out_types[e.from] then
        t = out_types[e.from][e.output] or 'float'
      elseif port.builtin then
        t = 'vec2'
      elseif port.type == 'gen' or port.type == 'any' then
        t = 'float'
      else
        t = port.type --[[@as Shader.Type]]
      end
      src[port.key] = t
      if port.type == 'gen' then
        gen_list[#gen_list + 1] = t
      elseif port.type == 'any' then
        any_list[#any_list + 1] = t
      end
    end
    -- A node with no gen inputs takes its own type from what is wired into its any inputs.
    local T = types.widest (#gen_list > 0 and gen_list or any_list)
    local declared = {} ---@type table<string, Shader.Type>
    for _, port in ipairs (def.inputs) do
      if port.type == 'gen' then
        declared[port.key] = T
      elseif port.type == 'any' then
        declared[port.key] = src[port.key]
      else
        declared[port.key] = port.type --[[@as Shader.Type]]
      end
    end
    node_types[id] = declared

    if bad then
      problem (bad, id)
      broken[id] = true
    else
      out_types[id], vars[id] = {}, {}
      for _, lang in ipairs ({ 'glsl', 'wgsl' }) do
        ---@cast lang Shader.Lang
        local inputs = {} ---@type table<string, string>
        for _, port in ipairs (def.inputs) do
          local e = into[id] and into[id][port.key]
          local want = declared[port.key]
          if e and not broken[e.from] and vars[e.from] then
            inputs[port.key] = types.convert (
              vars[e.from][e.output] or '0.0',
              src[port.key],
              want,
              lang
            )
          elseif port.builtin then
            inputs[port.key] =
              types.convert (BUILTINS[port.builtin], 'vec2', want, lang)
          else
            inputs[port.key] =
              types.literal (n.inputs[port.key] or port.default, want, lang)
          end
        end
        ---@type Shader.EmitContext
        local ctx = {
          lang = lang,
          T = T,
          inputs = inputs,
          types = declared,
          settings = settings,
        }
        if n.type == 'output' then
          final[lang] = inputs
        end

        -- The outputs something reads, and the ones those refer to.
        local wanted = {} ---@type table<string, boolean>
        ---@param key string
        local function want (key)
          if wanted[key] then
            return
          end
          wanted[key] = true
          for _, o in ipairs (def.outputs) do
            if o.key == key then
              for _, r in ipairs (refs (o, lang)) do
                want (r)
              end
            end
          end
        end
        for key in pairs (used[id] or {}) do
          want (key)
        end

        local own = {} ---@type table<string, string>
        for _, o in ipairs (def.outputs) do
          local t = nodes.output_type (def, o, n.settings)
          local ot = (t == 'gen' or t == 'any') and T or t --[[@as Shader.Type]]
          local var = id .. '_' .. o.key
          own[o.key] = var
          out_types[id][o.key] = ot
          vars[id][o.key] = var
          if wanted[o.key] then
            local expr = fill (o[lang] or o.glsl, ctx, own, def)
            local line = lang == 'glsl'
                and ('  ' .. types.name (ot, 'glsl') .. ' ' .. var .. ' = ' .. expr .. ';')
              or (
                '  let '
                .. var
                .. ': '
                .. types.name (ot, 'wgsl')
                .. ' = '
                .. expr
                .. ';'
              )
            local list = stmts[lang]
            list[#list + 1] = { text = line, node = id }
            if lang == 'glsl' then
              steps[#steps + 1] =
                { var = var, type = ot, glsl = expr, node = id }
            end
          end
        end
      end
      for _, h in ipairs (def.helpers or {}) do
        needs[h] = true
      end
      for _, name in ipairs (def.uniforms or {}) do
        wants[name] = true
      end
      if def.texture then
        local index = passes.channel_of_name (settings.channel) --[[@as integer]]
        reads[index] = reads[index] or {}
        table.insert (reads[index], id)
      end
      if n.type == 'parameter' then
        param_names[settings.name] = true
        local kind = settings.kind
        local t = kind == 'color' and 'vec3'
          or (types.is_type (kind) and kind or 'float')
        local value = {} ---@type number[]
        for i = 1, types.dim (t) do
          value[i] = tonumber ((settings.value or {})[i]) or 0
        end
        params[#params + 1] = {
          key = settings.name,
          glsl = 'u_' .. settings.name,
          type = t,
          value = value,
          min = tonumber (settings.min) or 0,
          max = tonumber (settings.max) or 1,
          color = kind == 'color',
          node = id,
        }
      end
    end
  end

  -- The WGSL struct: the builtin fields, the ones nodes ask for, then the parameters.
  local fields = {} ---@type { name: string, type: Shader.UniformType }[]
  for _, f in ipairs (BUILTIN_FIELDS) do
    fields[#fields + 1] = f
  end
  local optional = {} ---@type string[]
  for name in pairs (wants) do
    if OPTIONAL_FIELDS[name] then
      optional[#optional + 1] = name
    end
  end
  table.sort (optional)
  for _, name in ipairs (optional) do
    fields[#fields + 1] = { name = name, type = OPTIONAL_FIELDS[name].type }
  end
  local builtin_count = #fields
  for _, p in ipairs (params) do
    fields[#fields + 1] = { name = p.key, type = p.type }
  end
  local lay = layout.layout (fields)
  for i, f in ipairs (lay.fields) do
    if BUILTIN_NAMES[f.name] and i <= builtin_count then
      f.builtin = f.name
    end
  end
  for i, p in ipairs (params) do
    p.offset = lay.fields[builtin_count + i].offset
  end

  -- The channels, with the Texture nodes that read each.
  local channels = {} ---@type Shader.Channel[]
  local bindings = { ---@type Shader.Binding[]
    { group = 0, binding = 0, kind = 'uniforms', name = 'u', used = true },
  }
  for i = 0, passes.COUNT - 1 do
    if reads[i] then
      local name = 'iChannel' .. i
      channels[#channels + 1] =
        { index = i, names = { name }, nodes = reads[i] }
      bindings[#bindings + 1] = {
        group = 1,
        binding = i * 2,
        kind = 'texture',
        name = name,
        channel = i,
        used = true,
      }
      bindings[#bindings + 1] = {
        group = 1,
        binding = i * 2 + 1,
        kind = 'sampler',
        name = name .. '_sampler',
        channel = i,
        used = true,
      }
    end
  end

  local helper_names = {} ---@type string[]
  for name in pairs (needs) do
    helper_names[#helper_names + 1] = name
  end
  local title = comment_text (doc.name or 'Untitled')

  -- GLSL -------------------------------------------------------------------------------------
  local g = {} ---@type string[]
  local glsl_lines = {} ---@type table<integer, string>
  g[#g + 1] = '#version 300 es'
  g[#g + 1] = 'precision highp float;'
  g[#g + 1] = ''
  g[#g + 1] = '// ' .. title .. ', built with the Proteus shader builder.'
  g[#g + 1] = ''
  g[#g + 1] = 'uniform vec2 u_resolution;'
  g[#g + 1] = 'uniform float u_time;'
  g[#g + 1] = 'uniform float u_frame;'
  g[#g + 1] = 'uniform vec4 u_mouse;'
  for _, name in ipairs (optional) do
    local f = OPTIONAL_FIELDS[name]
    g[#g + 1] = 'uniform '
      .. types.name (f.type --[[@as Shader.Type]], 'glsl')
      .. ' '
      .. f.glsl
      .. ';'
  end
  for _, c in ipairs (channels) do
    g[#g + 1] = 'uniform highp sampler2D ' .. c.names[1] .. ';'
  end
  for _, p in ipairs (params) do
    g[#g + 1] = 'uniform '
      .. types.name (p.type --[[@as Shader.Type]], 'glsl')
      .. ' '
      .. p.glsl
      .. ';'
      .. notes (p)
    glsl_lines[#g] = p.node
  end
  g[#g + 1] = ''
  g[#g + 1] = 'in vec2 v_uv;'
  g[#g + 1] = 'out vec4 fragColor;'
  for _, src in ipairs (helpers.sources (helper_names, 'glsl')) do
    g[#g + 1] = ''
    g[#g + 1] = src
  end
  g[#g + 1] = ''
  g[#g + 1] = 'void main() {'
  g[#g + 1] = '  vec2 fragCoord = gl_FragCoord.xy;'
  g[#g + 1] = '  vec2 uv = fragCoord / u_resolution;'
  g[#g + 1] =
    '  vec2 suv = (fragCoord - 0.5 * u_resolution) / u_resolution.y + 0.5;'
  for _, s in ipairs (stmts.glsl) do
    g[#g + 1] = s.text
    glsl_lines[#g] = s.node
  end
  local color = final.glsl.color or 'vec3(0.0)'
  local alpha = final.glsl.alpha or '1.0'
  g[#g + 1] = '  fragColor = vec4(' .. color .. ', ' .. alpha .. ');'
  glsl_lines[#g] = output_id
  g[#g + 1] = '}'
  g[#g + 1] = ''

  -- WGSL -------------------------------------------------------------------------------------
  local w = {} ---@type string[]
  local wgsl_lines = {} ---@type table<integer, string>
  w[#w + 1] = '// ' .. title .. ', built with the Proteus shader builder.'
  w[#w + 1] = ''
  w[#w + 1] = 'struct Uniforms {'
  for i, f in ipairs (lay.fields) do
    w[#w + 1] = '  '
      .. f.name
      .. ': '
      .. types.name (f.type --[[@as Shader.Type]], 'wgsl')
      .. ','
    if i > builtin_count then
      local p = params[i - builtin_count]
      w[#w] = w[#w] .. notes (p)
      wgsl_lines[#w] = p.node
    end
  end
  w[#w + 1] = '}'
  w[#w + 1] = ''
  w[#w + 1] = '@group(0) @binding(0) var<uniform> u: Uniforms;'
  for _, b in ipairs (bindings) do
    if b.kind ~= 'uniforms' then
      w[#w + 1] = '@group('
        .. b.group
        .. ') @binding('
        .. b.binding
        .. ') var '
        .. b.name
        .. ': '
        .. (b.kind == 'texture' and 'texture_2d<f32>' or 'sampler')
        .. ';'
    end
  end
  w[#w + 1] = ''
  for line in (WGSL_VERTEX .. '\n'):gmatch ('([^\n]*)\n') do
    w[#w + 1] = line
  end
  for _, src in ipairs (helpers.sources (helper_names, 'wgsl')) do
    w[#w + 1] = ''
    w[#w + 1] = src
  end
  w[#w + 1] = ''
  w[#w + 1] = '@fragment'
  w[#w + 1] =
    'fn fs_main(@builtin(position) position: vec4f) -> @location(0) vec4f {'
  w[#w + 1] =
    '  let fragCoord = vec2f(position.x, u.resolution.y - position.y);'
  w[#w + 1] = '  let uv = fragCoord / u.resolution;'
  w[#w + 1] =
    '  let suv = (fragCoord - 0.5 * u.resolution) / u.resolution.y + 0.5;'
  for _, s in ipairs (stmts.wgsl) do
    w[#w + 1] = s.text
    wgsl_lines[#w] = s.node
  end
  color = final.wgsl.color or 'vec3f(0.0)'
  alpha = final.wgsl.alpha or '1.0'
  w[#w + 1] = '  return vec4f(' .. color .. ', ' .. alpha .. ');'
  wgsl_lines[#w] = output_id
  w[#w + 1] = '}'
  w[#w + 1] = ''

  local glsl_uniforms, wgsl_uniforms = {}, {} ---@type Shader.Uniform[], Shader.Uniform[]
  for _, p in ipairs (params) do
    glsl_uniforms[#glsl_uniforms + 1] = p
    wgsl_uniforms[#wgsl_uniforms + 1] = p
  end

  ---@type Shader.CompileResult
  local result = {
    ok = #errors == 0,
    errors = errors,
    uniforms = params,
    types = node_types,
    out_types = out_types,
    glsl = {
      language = 'glsl',
      source = table.concat (g, '\n'),
      vertex = GLSL_VERTEX,
      uniforms = glsl_uniforms,
      lines = glsl_lines,
      offset = 0,
      channels = channels,
    },
    wgsl = {
      language = 'wgsl',
      source = table.concat (w, '\n'),
      vertex_entry = 'vs_main',
      fragment_entry = 'fs_main',
      uniforms = wgsl_uniforms,
      layout = lay,
      lines = wgsl_lines,
      offset = 0,
      channels = channels,
      bindings = bindings,
    },
    ir = {
      name = doc.name or 'Untitled',
      steps = steps,
      color = final.glsl.color or 'vec3(0.0)',
      alpha = final.glsl.alpha or '1.0',
      helpers = helpers.closure (helper_names),
      uniforms = params,
      extra = optional,
      channels = channels,
    },
  }
  return result
end

---Compiles a graph. The result always holds shaders that compile, even when the graph has
---problems: nodes with problems are left out, and `errors` says why. Made nodes are expanded
---first, and what the result says of their nodes it says of the made node.
---@param doc Shader.Doc
---@return Shader.CompileResult
function M.compile (doc)
  local flat, expansion = subgraph.expand (doc)
  local result = compile_flat (flat)
  if not expansion then
    return result
  end
  local owner = expansion.owner
  ---@param id string?
  ---@return string?
  local function top (id)
    return id and (owner[id] or id)
  end
  for _, e in ipairs (result.errors) do
    e.node = top (e.node)
  end
  for _, p in ipairs ({ result.glsl, result.wgsl }) do
    for line, id in pairs (p.lines or {}) do
      p.lines[line] = top (id) --[[@as string]]
    end
  end
  for _, u in ipairs (result.uniforms) do
    u.node = top (u.node)
  end
  for _, c in ipairs (result.glsl.channels or {}) do
    local seen, list = {}, {} ---@type table<string, boolean>, string[]
    for _, id in ipairs (c.nodes or {}) do
      local t = top (id) --[[@as string]]
      if not seen[t] then
        seen[t] = true
        list[#list + 1] = t
      end
    end
    c.nodes = list
  end
  -- A made node's ports have the types of the inputs and outputs inside it.
  for id, ports in pairs (expansion.ports) do
    local ins, outs = {}, {} ---@type table<string, Shader.Type>, table<string, Shader.Type>
    for key, targets in pairs (ports.ins) do
      local t = targets[1]
      ins[key] = t and (result.types[t.node] or {})[t.input] or nil
    end
    for key, o in pairs (ports.outs) do
      outs[key] = (result.out_types[o.node] or {})[o.output]
    end
    result.types[id] = ins
    result.out_types[id] = outs
  end
  return result
end

return M
