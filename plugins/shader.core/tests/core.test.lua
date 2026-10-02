-- The shader builder's core: types, graph operations, the compiler, the file and undo.

local compile = require ('shader_compile') --[[@as Shader.CompileModule]]
local file = require ('shader_file') --[[@as Shader.FileModule]]
local graph = require ('shader_graph') --[[@as Shader.GraphModule]]
local helpers = require ('shader_helpers') --[[@as Shader.HelpersModule]]
local history = require ('shader_history') --[[@as Shader.HistoryModule]]
local layout = require ('shader_layout') --[[@as Shader.LayoutModule]]
local nodes = require ('shader_nodes') --[[@as Shader.NodesModule]]
local types = require ('shader_types') --[[@as Shader.TypesModule]]

---Adds a node and returns the new document and its id.
---@param doc Shader.Doc
---@param type_id string
---@return Shader.Doc, string
local function add (doc, type_id)
  local out, id = graph.add_node (doc, type_id, 0, 0)
  assert (out, id)
  return out, id
end

---@param doc Shader.Doc
---@param from string
---@param output string
---@param to string
---@param input string
---@return Shader.Doc
local function wire (doc, from, output, to, input)
  local out, err = graph.connect (doc, from, output, to, input)
  assert (out, err)
  return out
end

---@param text string
---@param piece string
---@return boolean
local function has (text, piece)
  return text:find (piece, 1, true) ~= nil
end

test ('numbers read as floats in both languages', function ()
  eq (types.number (1), '1.0')
  eq (types.number (0.25), '0.25')
  eq (types.number (-2), '-2.0')
  eq (types.number (1e-7), '1e-07')
  eq (types.number (0 / 0), '0.0')
  eq (types.literal ({ 0.5 }, 'float', 'glsl'), '0.5')
  eq (types.literal ({ 0.5 }, 'float', 'wgsl'), '0.5f')
  eq (types.literal ({ 1, 2 }, 'vec2', 'glsl'), 'vec2(1.0, 2.0)')
  eq (types.literal ({ 1 }, 'vec3', 'wgsl'), 'vec3f(1.0)')
  eq (types.literal ({ 1, 0 }, 'vec3', 'glsl'), 'vec3(1.0, 0.0, 0.0)')
end)

test ('any wire fits any input', function ()
  eq (types.convert ('a', 'float', 'vec3', 'glsl'), 'vec3(a)')
  eq (types.convert ('a', 'vec4', 'vec2', 'wgsl'), 'a.xy')
  eq (types.convert ('a', 'vec2', 'vec4', 'glsl'), 'vec4(a, 0.0, 1.0)')
  eq (types.convert ('a', 'vec3', 'vec4', 'wgsl'), 'vec4f(a, 1.0)')
  eq (types.convert ('a', 'vec3', 'float', 'glsl'), 'a.x')
  eq (types.convert ('a - b', 'vec3', 'vec2', 'glsl'), '(a - b).xy')
  eq (types.widest ({ 'float', 'vec3', 'vec2' }), 'vec3')
  eq (types.widest ({}), 'float')
end)

test ('every node in the catalog is complete', function ()
  local seen = {} ---@type table<string, boolean>
  for _, def in ipairs (nodes.list) do
    ok (not seen[def.type], 'two nodes are called ' .. def.type)
    seen[def.type] = true
    ok (nodes.category (def.category), def.type .. ' has no category')
    ok (def.description:find ('%.$'), def.type .. ' needs a sentence')
    for _, h in ipairs (def.helpers or {}) do
      ok (helpers.all[h], def.type .. ' needs a helper called ' .. h)
    end
  end
  ok (#nodes.list >= 70, 'the catalog has ' .. #nodes.list .. ' nodes')
end)

test ('a new graph shows the UV coordinates', function ()
  local r = compile.compile (graph.new ('Start'))
  ok (r.ok)
  ok (has (r.glsl.source, '#version 300 es'))
  ok (has (r.glsl.source, '  vec2 n1_uv = uv;'))
  ok (has (r.glsl.source, 'fragColor = vec4(vec3(n1_uv, 0.0), 1.0);'))
  ok (has (r.wgsl.source, '  let n1_uv: vec2f = uv;'))
  ok (has (r.wgsl.source, 'return vec4f(vec3f(n1_uv, 0.0), 1.0f);'))
  ok (has (r.wgsl.source, '@vertex'))
  ok (has (r.wgsl.source, '// Start, built with the Proteus shader builder.'))
end)

test ('gen nodes take the widest type wired in', function ()
  local doc = graph.new ()
  local id, color
  doc, id = add (doc, 'add')
  doc, color = add (doc, 'color')
  doc = wire (doc, color, 'rgb', id, 'a')
  doc = wire (doc, id, 'out', 'n2', 'color')
  local r = compile.compile (doc)
  ok (r.ok)
  eq (r.types[id], { a = 'vec3', b = 'vec3' })
  ok (
    has (
      r.glsl.source,
      'vec3 ' .. id .. '_out = ' .. color .. '_rgb + vec3(0.0);'
    )
  )
  ok (
    has (
      r.wgsl.source,
      'let ' .. id .. '_out: vec3f = ' .. color .. '_rgb + vec3f(0.0);'
    )
  )
end)

test ('only what the output reads is written', function ()
  local doc = graph.new ()
  local lone
  doc, lone = add (doc, 'value_noise')
  local r = compile.compile (doc)
  ok (not has (r.glsl.source, lone .. '_'))
  ok (not has (r.glsl.source, 'sb_value_noise'))
end)

test ('helpers come with the functions they call', function ()
  eq (helpers.closure ({ 'fbm' }), { 'hash', 'value_noise', 'fbm' })
  eq (helpers.closure ({ 'voronoi', 'hash' }), { 'hash', 'hash2', 'voronoi' })
  local doc = graph.new ()
  local id
  doc, id = add (doc, 'fbm')
  doc = wire (doc, id, 'out', 'n2', 'color')
  local r = compile.compile (doc)
  local glsl = r.glsl.source
  ok (glsl:find ('float sb_hash') < glsl:find ('float sb_value_noise'))
  ok (glsl:find ('float sb_value_noise') < glsl:find ('float sb_fbm'))
  ok (has (glsl, 'sb_fbm(uv * 4.0 + vec2(0.0), 5, 2.0, 0.5)'))
end)

test ('wires refuse loops and replace the wire already in an input', function ()
  local doc = graph.new ()
  local a, b
  doc, a = add (doc, 'add')
  doc, b = add (doc, 'add')
  doc = wire (doc, a, 'out', b, 'a')
  local out, err = graph.connect (doc, b, 'out', a, 'a')
  eq (out, nil)
  eq (err, 'That wire would make a loop.')
  eq (graph.connect (doc, a, 'out', a, 'b'), nil)
  doc = wire (doc, 'n1', 'x', b, 'a')
  local e = graph.edge_into (doc, b, 'a')
  eq (e and e.from, 'n1')
  eq (#doc.edges, 2)
end)

test ('graph operations leave the old document alone', function ()
  local doc = graph.new ()
  local after = graph.move (doc, { n1 = { x = 5.4, y = 9.6 } })
  eq (doc.nodes[1].x, 40)
  eq (after.nodes[1].x, 5)
  eq (after.nodes[1].y, 10)
  local removed = assert (graph.remove_nodes (doc, { 'n1' }))
  eq (#removed.nodes, 1)
  eq (#removed.edges, 0)
  eq (#doc.edges, 1)
  eq (
    select (2, graph.add_node (doc, 'output', 0, 0)),
    'A shader has only one Output node.'
  )
end)

test ('duplicate copies nodes and the wires between them', function ()
  local doc = graph.new ()
  local a, b
  doc, a = add (doc, 'time')
  doc, b = add (doc, 'sin')
  doc = wire (doc, a, 'time', b, 'x')
  local out, ids = graph.duplicate (doc, { a, b, 'n2' })
  ok (out)
  eq (#ids, 2)
  eq (#(out --[[@as Shader.Doc]]).nodes, 6)
  local e = graph.edge_into (out --[[@as Shader.Doc]], ids[2], 'x')
  eq (e and e.from, ids[1])
end)

test (
  'parameters become uniforms in both languages, with notes for their controls',
  function ()
    local doc = graph.new ()
    local p, q
    doc, p = add (doc, 'parameter')
    doc = assert (graph.set_setting (doc, p, 'name', 'speed'))
    doc, q = add (doc, 'parameter')
    doc = assert (graph.set_setting (doc, q, 'name', 'tint'))
    doc = assert (graph.set_setting (doc, q, 'kind', 'color'))
    local m
    doc, m = add (doc, 'multiply')
    doc = wire (doc, p, 'out', m, 'a')
    doc = wire (doc, q, 'out', m, 'b')
    doc = wire (doc, m, 'out', 'n2', 'color')
    local r = compile.compile (doc)
    ok (r.ok)
    ok (has (r.glsl.source, 'uniform float u_speed;'))
    ok (has (r.glsl.source, 'uniform vec3 u_tint;'))
    ok (
      has (r.glsl.source, 'uniform float u_speed; // @range 0 1 @default 0.5\n')
    )
    ok (
      has (
        r.glsl.source,
        'uniform vec3 u_tint; // @color @default 0.5 0.5 0.5\n'
      )
    )
    ok (
      has (
        r.wgsl.source,
        '  speed: f32, // @range 0 1 @default 0.5\n  tint: vec3f,'
      )
    )
    eq (#r.uniforms, 2)
    eq (r.uniforms[1].offset, 32)
    eq (r.uniforms[2].offset, 48)
    eq (r.uniforms[2].color, true)
    eq (r.uniforms[2].value, { 0.5, 0.5, 0.5 })
    eq (r.wgsl.layout and r.wgsl.layout.size, 64)
    eq (r.wgsl.layout and r.wgsl.layout.fields[2].builtin, 'time')
  end
)

test ('problems are reported and leave a shader that still compiles', function ()
  local doc = graph.new ()
  local p, q, s
  doc, p = add (doc, 'parameter')
  doc = assert (graph.set_setting (doc, p, 'name', 'time'))
  doc, q = add (doc, 'parameter')
  doc = assert (graph.set_setting (doc, q, 'name', 'filter'))
  doc, s = add (doc, 'swizzle')
  doc = assert (graph.set_setting (doc, s, 'mask', 'xq'))
  local m
  doc, m = add (doc, 'add')
  doc = wire (doc, p, 'out', m, 'a')
  doc = wire (doc, q, 'out', m, 'b')
  local m2
  doc, m2 = add (doc, 'add')
  doc = wire (doc, m, 'out', m2, 'a')
  doc = wire (doc, s, 'out', m2, 'b')
  doc = wire (doc, m2, 'out', 'n2', 'color')
  local r = compile.compile (doc)
  eq (r.ok, false)
  eq (#r.errors, 3)
  eq (r.errors[1].node, p)
  ok (has (r.errors[2].message, 'WGSL keeps the word filter'))
  eq (r.errors[3].node, s)
  -- The broken nodes read as unwired inputs.
  ok (has (r.glsl.source, m .. '_out = 0.0 + 0.0;'))
  eq (#r.uniforms, 0)
end)

test ('a graph with no output says so', function ()
  local doc = assert (graph.remove_nodes (graph.new (), { 'n2' }))
  local r = compile.compile (doc)
  eq (r.ok, false)
  ok (has (r.errors[1].message, 'Add an Output node'))
  ok (has (r.glsl.source, 'fragColor = vec4(vec3(0.0), 1.0);'))
end)

test ('each line of code knows its node', function ()
  local doc = graph.new ()
  local r = compile.compile (doc)
  local found = 0 ---@type integer
  local n = 0 ---@type integer
  for line in (r.glsl.source .. '\n'):gmatch ('([^\n]*)\n') do
    n = n + 1
    if line:find ('n1_uv = uv', 1, true) then
      found = math.floor (n)
    end
  end
  eq (r.glsl.lines and r.glsl.lines[found], 'n1')
end)

test ('expressions read either language', function ()
  eq (nodes.dialect ('vec3(a) + atan(b, c)', 'wgsl'), 'vec3f(a) + atan2(b, c)')
  eq (nodes.dialect ('vec3f(a) + atan2(b, c)', 'glsl'), 'vec3(a) + atan(b, c)')
  eq (nodes.dialect ('saturate(a * 2.0)', 'glsl'), 'clamp(a * 2.0, 0.0, 1.0)')
  local doc = graph.new ()
  local e
  doc, e = add (doc, 'expression')
  doc = assert (graph.set_setting (doc, e, 'expr', 'vec3(a, b, 1.0)'))
  doc = assert (graph.set_setting (doc, e, 'type', 'vec3'))
  doc = wire (doc, 'n1', 'x', e, 'a')
  doc = wire (doc, 'n1', 'y', e, 'b')
  doc = wire (doc, e, 'out', 'n2', 'color')
  local r = compile.compile (doc)
  ok (has (r.glsl.source, 'vec3 ' .. e .. '_out = vec3(n1_x, n1_y, 1.0);'))
  ok (
    has (r.wgsl.source, 'let ' .. e .. '_out: vec3f = vec3f(n1_x, n1_y, 1.0);')
  )
  -- auto takes the widest input
  doc = assert (graph.set_setting (doc, e, 'type', 'auto'))
  doc = assert (graph.set_setting (doc, e, 'expr', 'a * 2.0'))
  doc = wire (doc, 'n1', 'uv', e, 'a')
  r = compile.compile (doc)
  ok (has (r.glsl.source, 'vec2 ' .. e .. '_out = n1_uv * 2.0;'))
end)

test ('wgsl struct fields follow the alignment rules', function ()
  local lay = layout.layout ({
    { name = 'a', type = 'float' },
    { name = 'b', type = 'vec3' },
    { name = 'c', type = 'vec2' },
    { name = 'd', type = 'float' },
  })
  eq (lay.fields[1].offset, 0)
  eq (lay.fields[2].offset, 16)
  eq (lay.fields[3].offset, 32)
  eq (lay.fields[4].offset, 40)
  eq (lay.size, 48)
end)

test ('the file keeps a graph as it was', function ()
  local doc = graph.new ('Round "trip"')
  local id
  doc, id = add (doc, 'parameter')
  doc = assert (graph.set_setting (doc, id, 'name', 'size'))
  doc = assert (
    graph.set_input (
      graph.remove_nodes (doc, { 'n1' }) --[[@as Shader.Doc]],
      'n2',
      'color',
      { 1, 0.25, 0 }
    )
  )
  doc.preview = 'wgsl'
  local text = file.save (doc)
  local back = assert (file.load (text))
  eq (back, doc)
  eq (file.save (back), text)
  ok (has (text, '"edges": [\n  ]'))
end)

test ('loading checks the shape of the file', function ()
  eq (
    select (2, file.load ('{')),
    'The file is not valid JSON: Expected a name in quotes at character 2'
  )
  eq (select (2, file.load ('{"nodes": 3}')), 'The file has no list of nodes.')
  eq (
    select (2, file.load ('{"format": 9, "nodes": []}')),
    'The file comes from a newer version of the shader builder.'
  )
  eq (
    select (2, file.load ('{"nodes": [{"id": "a b", "type": "uv"}]}')),
    'Node 1 needs an id and a type.'
  )
  local doc = assert (
    file.load (
      [[{"nodes": [{"id": "a", "type": "uv"}, {"id": "b", "type": "output"}],
    "edges": [{"from": "a", "output": "uv", "to": "b", "input": "color"},
              {"from": "a", "output": "x", "to": "b", "input": "color"},
              {"from": "zz", "output": "x", "to": "b", "input": "alpha"}]}]]
    )
  )
  eq (#doc.edges, 1)
  eq (doc.name, 'Untitled')
end)

test ('the json reader reads what the writer writes', function ()
  local value =
    { a = { 1, 2.5, -3 }, b = 'line\n"quoted"', c = true, d = { e = {} } }
  eq (file.decode (file.encode (value)), value)
  eq (file.decode ('"\\u00e9"'), 'é')
end)

test ('undo and redo walk the history, and quick changes merge', function ()
  local a = graph.new ('a')
  local h = history.new (a)
  local b, c = graph.rename (a, 'b'), graph.rename (a, 'c')
  history.push (h, b, 'drag', 1000)
  history.push (h, c, 'drag', 1200)
  eq (#h.past, 1)
  ok (history.undo (h))
  eq (h.doc.name, 'a')
  ok (not history.undo (h))
  ok (history.redo (h))
  eq (h.doc.name, 'c')
  history.push (h, b, 'drag', 5000)
  eq (#h.past, 2)
  eq (#h.future, 0)
end)

test ('generated code opened as code keeps its controls', function ()
  local source = require ('shader_source') --[[@as Shader.SourceModule]]
  local doc = graph.new ()
  local p
  doc, p = add (doc, 'parameter')
  doc = assert (graph.set_setting (doc, p, 'name', 'speed'))
  doc = assert (graph.set_setting (doc, p, 'value', { 2, 0, 0, 1 }))
  doc = assert (graph.set_setting (doc, p, 'max', 4))
  doc = wire (doc, p, 'out', 'n2', 'alpha')
  local r = compile.compile (doc)
  local glsl = source.glsl_program (r.glsl.source)
  eq (glsl.uniforms[1].key, 'u_speed')
  eq (
    { glsl.uniforms[1].min, glsl.uniforms[1].max, glsl.uniforms[1].value },
    { 0, 4, { 2 } }
  )
  local wgsl = source.wgsl_program (r.wgsl.source)
  eq (wgsl.uniforms[1].key, 'speed')
  eq (wgsl.uniforms[1].offset, 32)
  eq (wgsl.uniforms[1].value, { 2 })
end)

test ('a change shares every node it did not touch', function ()
  local doc = graph.new ()
  local moved = graph.move (doc, { n1 = { x = 1, y = 2 } })
  ok (moved.nodes[2] == doc.nodes[2], 'the output node is the same table')
  ok (moved.nodes[1] ~= doc.nodes[1])
  ok (moved.edges == doc.edges, 'a move keeps the list of wires')
  local set = assert (graph.set_input (doc, 'n2', 'color', { 1, 0, 0 }))
  ok (set.nodes[1] == doc.nodes[1])
  eq (doc.nodes[2].inputs, {}, 'the old node keeps its inputs')
  eq (select (2, graph.duplicate (doc, { 'n2' })), 'Nothing to duplicate.')
end)

test ('copy and paste brings nodes, wires and frames into any graph', function ()
  local doc = graph.new ()
  local t, s
  doc, t = add (doc, 'time')
  doc, s = add (doc, 'sin')
  doc = wire (doc, t, 'time', s, 'x')
  doc = graph.with_canvas (doc, {
    { id = 'f1', x = -10, y = -40, w = 300, h = 200, title = 'Wave' },
  }, { [graph.wire_id (s, 'x')] = { { x = 100, y = 20 } } })
  local fragment = graph.copy_nodes (doc, { t, s, 'n2' }, { 'f1' })
  eq (#fragment.nodes, 3)
  eq (#fragment.edges, 1)
  -- A new graph has its own Output, so the copied one stays behind.
  local pasted, ids, frames = graph.paste (graph.new (), fragment, 50, 0)
  pasted = assert (pasted, 'the fragment pastes')
  eq (#ids, 2)
  eq (#pasted.nodes, 4)
  local e = graph.edge_into (pasted, ids[2], 'x')
  eq (e and e.from, ids[1])
  eq (frames, { 'f1' })
  eq (graph.frames (pasted)[1].x, 40)
  eq (
    graph.routes (pasted)[graph.wire_id (ids[2], 'x')],
    { { x = 150, y = 20 } }
  )
  eq (compile.compile (pasted).ok, true)
end)

test (
  'the file keeps frames and reroute points, and drops those of gone wires',
  function ()
    local doc = graph.new ()
    doc = graph.with_canvas (doc, {
      {
        id = 'f1',
        x = 0,
        y = 0,
        w = 300,
        h = 200,
        title = 'All',
        color = '#4f8ef7',
      },
    }, { [graph.wire_id ('n2', 'color')] = { { x = 200, y = 90 } } })
    local text = file.save (doc)
    ok (has (text, '"canvas": {'))
    local back = assert (file.load (text))
    eq (back.canvas, doc.canvas)
    eq (file.save (back), text)
    local cut = assert (graph.disconnect (doc, 'n2', 'color'))
    eq (assert (file.load (file.save (cut))).canvas.routes, {})
    ok (not has (file.save (graph.new ()), 'canvas'), 'no canvas data, no key')
    eq (
      select (2, graph.set_canvas (doc, { frames = { { id = 'f1' } } })),
      'The canvas data is not right.'
    )
  end
)

test ('a node dropped onto a wire goes into it', function ()
  local doc = graph.new ()
  local s
  doc, s = add (doc, 'sin')
  local into = assert (graph.insert (doc, s, graph.wire_id ('n2', 'color')))
  local a = graph.edge_into (into, s, 'x')
  local b = graph.edge_into (into, 'n2', 'color')
  eq (a and a.from, 'n1')
  eq (b and b.from, s)
  eq (
    graph.insert (doc, 'n1', graph.wire_id ('n2', 'color')),
    nil,
    'not into its own wire'
  )
end)
