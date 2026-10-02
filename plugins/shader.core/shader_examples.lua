-- The example graphs in shaders/, built from the same operations the canvas uses, so they
-- always fit the catalog. tests/lua/shader/examples.test.lua checks the files match.

local graph = require ('shader_graph') --[[@as Shader.GraphModule]]

---Builds a graph from a short description: nodes by name, then wires.
---@param name string
---@param spec { nodes: { [1]: string, [2]: string, [3]: number, [4]: number, inputs?: table<string, number[]>, settings?: table<string, any> }[], wires: string[][] }
---@return Shader.Doc
local function build (name, spec)
  local doc = graph.new (name)
  doc = assert (graph.remove_nodes (doc, { 'n1', 'n2' }))
  local ids = {} ---@type table<string, string>
  for _, n in ipairs (spec.nodes) do
    local id ---@type string
    doc, id = assert (graph.add_node (doc, n[2], n[3], n[4]))
    ids[n[1]] = id
    for key, values in pairs (n.inputs or {}) do
      doc = assert (graph.set_input (doc, id, key, values))
    end
    for key, value in pairs (n.settings or {}) do
      doc = assert (graph.set_setting (doc, id, key, value))
    end
  end
  for _, w in ipairs (spec.wires) do
    local from, output = w[1]:match ('^([%w_]+)%.([%w_]+)$')
    local to, input = w[2]:match ('^([%w_]+)%.([%w_]+)$')
    doc = assert (graph.connect (doc, ids[from], output, ids[to], input))
  end
  return doc
end

local EXAMPLES = {} ---@type table<string, fun(): Shader.Doc>

EXAMPLES.plasma = function ()
  return build ('Plasma', {
    nodes = {
      { 'uv', 'square_uv', 40, 60 },
      { 'time', 'time', 40, 220 },
      {
        'speed',
        'parameter',
        40,
        380,
        settings = { name = 'speed', value = { 1, 0, 0, 1 }, min = 0, max = 4 },
      },
      { 'fast', 'multiply', 320, 260 },
      {
        'waves',
        'expression',
        600,
        100,
        settings = {
          expr = 'sin(a.x * 10.0 + b) + sin(a.y * 10.0 + b * 1.3) + sin(length(a - 0.5) * 18.0 - b * 2.0)',
          type = 'float',
        },
      },
      {
        'fit',
        'remap',
        880,
        100,
        inputs = { in_lo = { -3 }, in_hi = { 3 } },
      },
      { 'colors', 'palette', 1160, 100 },
      { 'out', 'output', 1440, 100 },
    },
    wires = {
      { 'time.time', 'fast.a' },
      { 'speed.out', 'fast.b' },
      { 'uv.uv', 'waves.a' },
      { 'fast.out', 'waves.b' },
      { 'waves.out', 'fit.x' },
      { 'fit.out', 'colors.t' },
      { 'colors.rgb', 'out.color' },
    },
  })
end

EXAMPLES.clouds = function ()
  return build ('Clouds', {
    nodes = {
      { 'uv', 'square_uv', 40, 60 },
      { 'time', 'time', 40, 220 },
      { 'drift', 'vec2', 40, 400, settings = { value = { 0.12, 0.03, 0, 1 } } },
      { 'move', 'multiply', 320, 260 },
      {
        'noise',
        'fbm',
        600,
        60,
        inputs = { scale = { 3 } },
        settings = { octaves = 6 },
      },
      {
        'soft',
        'smoothstep',
        880,
        60,
        inputs = { e0 = { 0.35 }, e1 = { 0.85 } },
      },
      { 'sky', 'color', 880, 300, settings = { value = { 0.18, 0.42, 0.85 } } },
      { 'cloud', 'color', 880, 420, settings = { value = { 1, 1, 1 } } },
      { 'blend', 'mix', 1160, 200 },
      { 'out', 'output', 1440, 200 },
    },
    wires = {
      { 'time.time', 'move.a' },
      { 'drift.out', 'move.b' },
      { 'uv.uv', 'noise.uv' },
      { 'move.out', 'noise.offset' },
      { 'noise.out', 'soft.x' },
      { 'sky.rgb', 'blend.a' },
      { 'cloud.rgb', 'blend.b' },
      { 'soft.out', 'blend.t' },
      { 'blend.out', 'out.color' },
    },
  })
end

EXAMPLES.cells = function ()
  return build ('Cells', {
    nodes = {
      { 'time', 'time', 40, 60 },
      { 'slow', 'multiply', 320, 60, inputs = { b = { 0.4 } } },
      {
        'size',
        'parameter',
        40,
        240,
        settings = { name = 'cells', value = { 6, 0, 0, 1 }, min = 2, max = 20 },
      },
      { 'cells', 'voronoi', 600, 60 },
      { 'hsv', 'combine', 880, 60, inputs = { y = { 0.55 }, z = { 1 } } },
      { 'rgb', 'hsv_to_rgb', 1160, 60 },
      { 'edge', 'one_minus', 880, 300 },
      { 'shade', 'multiply', 1440, 160 },
      { 'out', 'output', 1720, 160 },
    },
    wires = {
      { 'time.time', 'slow.a' },
      { 'slow.out', 'cells.offset' },
      { 'size.out', 'cells.scale' },
      { 'cells.cell', 'hsv.x' },
      { 'hsv.xyz', 'rgb.hsv' },
      { 'cells.distance', 'edge.x' },
      { 'rgb.rgb', 'shade.a' },
      { 'edge.out', 'shade.b' },
      { 'shade.out', 'out.color' },
    },
  })
end

EXAMPLES.shapes = function ()
  return build ('Shapes', {
    nodes = {
      { 'time', 'time', 40, 60 },
      { 'spin', 'rotate', 320, 60 },
      { 'box', 'box', 600, 60 },
      { 'ring', 'ring', 600, 320, inputs = { radius = { 0.38 } } },
      { 'bg', 'color', 880, 40, settings = { value = { 0.08, 0.08, 0.12 } } },
      { 'fill', 'color', 880, 160, settings = { value = { 1, 0.55, 0.2 } } },
      {
        'tint',
        'parameter',
        880,
        300,
        settings = {
          name = 'ring_color',
          kind = 'color',
          value = { 0.3, 0.7, 1, 1 },
        },
      },
      { 'with_box', 'mix', 1160, 60 },
      { 'with_ring', 'mix', 1440, 160 },
      { 'out', 'output', 1720, 160 },
    },
    wires = {
      { 'time.time', 'spin.angle' },
      { 'spin.out', 'box.uv' },
      { 'bg.rgb', 'with_box.a' },
      { 'fill.rgb', 'with_box.b' },
      { 'box.mask', 'with_box.t' },
      { 'with_box.out', 'with_ring.a' },
      { 'tint.out', 'with_ring.b' },
      { 'ring.mask', 'with_ring.t' },
      { 'with_ring.out', 'out.color' },
    },
  })
end

local M = {}

M.names = { 'plasma', 'clouds', 'cells', 'shapes' }

---@param name string
---@return Shader.Doc?
function M.build (name)
  local make = EXAMPLES[name]
  return make and make () or nil
end

---A new graph buffer. It reads its own last frame on iChannel0 and fades it, with a spot that
---circles, or follows the mouse while it is down, so it draws a trail.
---@param pass Shader.PassId
---@return Shader.Doc
function M.buffer (pass)
  local doc = build ('Buffer ' .. pass:upper (), {
    nodes = {
      { 'last', 'texture', 40, 60 },
      { 'uv', 'uv', 40, 260 },
      { 'time', 'time', 40, 400 },
      { 'mouse', 'mouse', 40, 540 },
      {
        'spot',
        'expression',
        340,
        360,
        settings = {
          expr = 'mix(vec2(0.5 + 0.3 * cos(b), 0.5 + 0.3 * sin(b * 1.3)), c, step(0.5, d))',
          type = 'vec2',
        },
      },
      {
        'draw',
        'expression',
        640,
        160,
        settings = {
          expr = 'max(a * 0.97, vec3(1.0 - smoothstep(0.0, 0.03, distance(b, c))))',
          type = 'vec3',
        },
      },
      { 'out', 'output', 940, 160 },
    },
    wires = {
      { 'time.time', 'spot.b' },
      { 'mouse.position', 'spot.c' },
      { 'mouse.down', 'spot.d' },
      { 'last.rgb', 'draw.a' },
      { 'uv.uv', 'draw.b' },
      { 'spot.out', 'draw.c' },
      { 'draw.out', 'out.color' },
    },
  })
  return graph.set_channel (doc, 0, { kind = 'buffer', buffer = pass })
end

return M
