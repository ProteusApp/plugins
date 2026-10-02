-- Made nodes: a group of nodes made into one node, unpacked again, kept in the file, and
-- expanded before the compiler sees the graph.

local compile = require ('shader_compile') --[[@as Shader.CompileModule]]
local file = require ('shader_file') --[[@as Shader.FileModule]]
local graph = require ('shader_graph') --[[@as Shader.GraphModule]]
local subgraph = require ('shader_subgraph') --[[@as Shader.SubgraphModule]]

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

---The code with every node's name numbered by where it first shows, so two graphs that
---compute the same in the same order read the same.
---@param code string
---@return string
local function shape (code)
  local seen, count = {}, 0 ---@type table<string, string>, integer
  return (
    code:gsub ('%f[%w_]n%d+[%w_]*', function (name)
      local base = name:match ('^(n[%d_n]*%d)') or name
      local rest = name:sub (#base + 1)
      if not seen[base] then
        count = count + 1
        seen[base] = 'v' .. count
      end
      return seen[base] .. rest
    end)
  )
end

---UV into a circle into a palette into the output: n1 UV, n2 Output, n3 Circle, n4 Palette.
---@return Shader.Doc
local function sample ()
  local doc = graph.new ('Rings')
  local circle, palette ---@type string, string
  doc, circle = add (doc, 'circle')
  doc, palette = add (doc, 'palette')
  doc = wire (doc, 'n1', 'uv', circle, 'uv')
  doc = wire (doc, circle, 'distance', palette, 't')
  doc = wire (doc, palette, 'rgb', 'n2', 'color')
  doc = assert (graph.set_input (doc, circle, 'radius', { 0.4 }))
  return doc
end

test (
  'a group of nodes becomes one node with an input and an output',
  function ()
    local doc = sample ()
    local made, id = subgraph.make (doc, { 'n3', 'n4' }, 'Glow')
    assert (made, id)
    eq (#made.nodes, 3)
    local n = assert (graph.node (made, id))
    local sid = assert (graph.subgraph_id (n.type))
    local sg = made.subgraphs[sid]
    eq (sg.name, 'Glow')
    eq (#sg.nodes, 2)
    eq (#sg.edges, 1)
    eq (#sg.inputs, 1)
    eq (sg.inputs[1].targets, { { node = 'n3', input = 'uv' } })
    eq (#sg.outputs, 1)
    eq ({ sg.outputs[1].node, sg.outputs[1].output }, { 'n4', 'rgb' })
    ok (graph.edge_into (made, id, sg.inputs[1].key))
    local into = assert (graph.edge_into (made, 'n2', 'color'))
    eq ({ into.from, into.output }, { id, sg.outputs[1].key })
    local def = assert (graph.def (made, n.type))
    eq (def.title, 'Glow')
    eq (def.inputs[1].builtin, 'suv')
    eq (def.outputs[1].type, 'vec3')
  end
)

test ('a made node compiles to the same code as its nodes', function ()
  local doc = sample ()
  local made, id = subgraph.make (doc, { 'n3', 'n4' }, 'Glow')
  assert (made, id)
  local before, after = compile.compile (doc), compile.compile (made)
  ok (after.ok, after.errors[1] and after.errors[1].message)
  eq (shape (after.glsl.source), shape (before.glsl.source))
  eq (shape (after.wgsl.source), shape (before.wgsl.source))
  -- The canvas shows the made node's ports with the types inside it.
  eq (after.types[id], { i1 = 'vec2' })
  eq (after.out_types[id], { o1 = 'vec3' })
  -- Lines of the code point at the made node, not at the nodes inside it.
  local named = {} ---@type table<string, boolean>
  for _, node in pairs (after.glsl.lines) do
    named[node] = true
  end
  ok (named[id])
  ok (not named[id .. '_n3'])
end)

test ('unpacking puts the nodes back, wired as before', function ()
  local doc = sample ()
  local made, id = subgraph.make (doc, { 'n3', 'n4' }, 'Glow')
  assert (made, id)
  local back, ids = subgraph.unpack (made, id)
  assert (back, ids)
  eq (#back.nodes, 4)
  eq (back.subgraphs, nil)
  eq (#ids --[[@as string[] ]], 2)
  eq (
    shape (compile.compile (back).glsl.source),
    shape (compile.compile (doc).glsl.source)
  )
  local nothing, why = subgraph.unpack (back, 'n1')
  eq (nothing, nil)
  eq (why, 'Only a made node can be unpacked.')
end)

test (
  'numbers set on a made node reach the nodes inside, and stay when unpacked',
  function ()
    local doc = graph.new ('Shift')
    local add_id ---@type string
    doc, add_id = add (doc, 'add')
    local num ---@type string
    doc, num = add (doc, 'float')
    doc = wire (doc, num, 'out', add_id, 'b')
    doc = wire (doc, add_id, 'out', 'n2', 'color')
    local made, id = subgraph.make (doc, { add_id }, 'Plus')
    assert (made, id)
    -- The wire into b became the made node's input. Take it away and set a number instead.
    made = assert (graph.disconnect (made, id, 'i1'))
    made = assert (graph.set_input (made, id, 'i1', { 0.25 }))
    local flat = subgraph.expand (made)
    local inner = assert (graph.node (flat, id .. '_' .. add_id))
    eq (inner.inputs.b, { 0.25 })
    local back = assert (subgraph.unpack (made, id))
    local found ---@type Shader.Node?
    for _, n in ipairs (back.nodes) do
      if n.type == 'add' then
        found = n
      end
    end
    eq (assert (found).inputs.b, { 0.25 })
  end
)

test ('a made node can hold another', function ()
  local doc = sample ()
  local inner, inner_id = subgraph.make (doc, { 'n3' }, 'Disc')
  assert (inner, inner_id)
  local outer, outer_id = subgraph.make (inner, { inner_id, 'n4' }, 'Glow')
  assert (outer, outer_id)
  local count = 0
  for _ in pairs (outer.subgraphs) do
    count = count + 1
  end
  eq (count, 2)
  local flat = subgraph.expand (outer)
  ok (graph.node (flat, outer_id .. '_' .. inner_id .. '_n3'))
  local result = compile.compile (outer)
  ok (result.ok, result.errors[1] and result.errors[1].message)
  eq (shape (result.glsl.source), shape (compile.compile (doc).glsl.source))
  local back = assert (subgraph.unpack (outer, outer_id))
  -- The made node inside comes back, with its own group still kept.
  count = 0
  for _ in pairs (back.subgraphs) do
    count = count + 1
  end
  eq (count, 1)
end)

test ('some groups cannot become a node', function ()
  local doc = sample ()
  local none, why = subgraph.make (doc, {}, 'x')
  eq (none, nil)
  eq (why, 'Pick the nodes to make a node from.')
  none, why = subgraph.make (doc, { 'n3', 'n2' }, 'x')
  eq (none, nil)
  eq (why, 'The Output node cannot go inside a made node.')
end)

test ('a group nothing outside reads gives each loose output a port', function ()
  local doc = graph.new ('Loose')
  local id ---@type string
  doc, id = add (doc, 'time')
  local made, made_id = subgraph.make (doc, { id }, 'Clock')
  assert (made, made_id)
  local sid = graph.subgraph_id (assert (graph.node (made, made_id)).type)
  eq (#made.subgraphs[sid].outputs, 3)
  eq (made.subgraphs[sid].outputs[1].label, 'seconds')
end)

test ('a problem inside a made node shows on the made node', function ()
  local doc = graph.new ('Bad')
  local sw ---@type string
  doc, sw = add (doc, 'swizzle')
  doc = assert (graph.set_setting (doc, sw, 'mask', 'xq'))
  doc = wire (doc, sw, 'out', 'n2', 'color')
  local made, id = subgraph.make (doc, { sw }, 'Pick')
  assert (made, id)
  local result = compile.compile (made)
  ok (not result.ok)
  eq (result.errors[1].node, id)
end)

test ('a graph with made nodes saves as format 2 and loads the same', function ()
  local doc = sample ()
  eq (file.save (doc):match ('"format": (%d)'), '1')
  local made, id = subgraph.make (doc, { 'n3', 'n4' }, 'Glow "quoted"')
  assert (made, id)
  local text = file.save (made)
  eq (text:match ('"format": (%d)'), '2')
  local loaded = assert (file.load (text))
  eq (loaded.subgraphs, made.subgraphs)
  eq (file.save (loaded), text)
  eq (compile.compile (loaded).glsl.source, compile.compile (made).glsl.source)
end)

test (
  'a group that does not read is dropped, and its made nodes show as missing',
  function ()
    local doc = sample ()
    local made, id = subgraph.make (doc, { 'n3', 'n4' }, 'Glow')
    assert (made, id)
    local text = file.save (made):gsub ('"targets": %[[^%]]*%]', '"targets": 5')
    local loaded = assert (file.load (text))
    eq (loaded.subgraphs, nil)
    local result = compile.compile (loaded)
    ok (not result.ok)
    eq (result.errors[1].node, id)
  end
)

test ('removing the last made node of a group drops the group', function ()
  local doc = sample ()
  local made, id = subgraph.make (doc, { 'n3', 'n4' }, 'Glow')
  assert (made, id)
  local copy = assert (graph.duplicate (made, { id }))
  local one = assert (graph.remove_nodes (copy, { id }))
  ok (one.subgraphs)
  local none = assert (graph.remove_nodes (made, { id }))
  eq (none.subgraphs, nil)
end)

test ('made nodes paste into another graph with their groups', function ()
  local doc = sample ()
  local made, id = subgraph.make (doc, { 'n3', 'n4' }, 'Glow')
  assert (made, id)
  local fragment = graph.copy_nodes (made, { id })
  ok (fragment.subgraphs and fragment.subgraphs.s1)
  -- The other graph has a group of its own called s1, so the pasted one gets s2.
  local other = sample ()
  local other_made = assert (subgraph.make (other, { 'n3' }, 'Disc'))
  local pasted, ids = graph.paste (other_made, fragment, 40, 40)
  assert (pasted, 'the paste failed')
  eq (#ids, 1)
  local n = assert (graph.node (pasted, ids[1]))
  eq (n.type, 'subgraph:s2')
  eq (pasted.subgraphs.s2.name, 'Glow')
  eq (pasted.subgraphs.s1.name, 'Disc')
  -- Pasting into the same graph shares the group.
  local again, again_ids = graph.paste (made, fragment, 40, 40)
  assert (again, 'the paste failed')
  eq (assert (graph.node (again, again_ids[1])).type, 'subgraph:s1')
  eq (again.subgraphs.s2, nil)
end)

test ('a made node can be renamed, and listed', function ()
  local doc = sample ()
  local made = assert (subgraph.make (doc, { 'n3', 'n4' }, 'Glow'))
  local renamed = assert (subgraph.rename (made, 's1', 'Halo'))
  eq (renamed.subgraphs.s1.name, 'Halo')
  eq (made.subgraphs.s1.name, 'Glow')
  local list = subgraph.list (renamed)
  eq (#list, 1)
  eq (list[1].type, 'subgraph:s1')
  local none, why = subgraph.rename (made, 's1', '  ')
  eq (none, nil)
  eq (why, 'A made node needs a name.')
end)
