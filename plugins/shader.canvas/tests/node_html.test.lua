-- What a node on the shader canvas shows, drawn as HTML from the node and the last compile.

local html_m = require ('node_html')

---Loads a module of shader.core the way its own `require` does, since a test here reaches
---only this plugin's folder through `require`.
---@type table<string, any>
local loaded = {}
---@param name string
---@return any
local function core_require (name)
  if loaded[name] == nil then
    -- selene: allow(global_usage)
    local env = setmetatable ({ require = core_require }, { __index = _G })
    local chunk = assert (
      load (
        read ('plugins/shader.core/' .. name .. '.lua'),
        '@' .. name,
        't',
        env
      )
    )
    loaded[name] = chunk ()
  end
  return loaded[name]
end

local format = core_require ('shader_format') --[[@as Shader.FormatModule]]
local nodes = core_require ('shader_nodes') --[[@as Shader.NodesModule]]
local types = core_require ('shader_types') --[[@as Shader.TypesModule]]

---@param text string
---@return string
local function esc (text)
  return (
    text
      :gsub ('&', '&amp;')
      :gsub ('<', '&lt;')
      :gsub ('>', '&gt;')
      :gsub ('"', '&quot;')
  )
end

local html = html_m.new ({
  catalog = nodes,
  types = types,
  esc = esc,
  format = format,
})

---@param text string
---@param piece string
---@return boolean
local function has (text, piece)
  return text:find (piece, 1, true) ~= nil
end

---@param id string
---@param type_id string
---@return Shader.Node
local function node (id, type_id)
  return { id = id, type = type_id, x = 0, y = 0, inputs = {}, settings = {} }
end

test ('a data-item splits into its parts', function ()
  eq (html_m.split ('n3|num|color|2'), { 'n3', 'num', 'color', '2' })
end)

test ('a field shows its number the way shader.core writes it', function ()
  local n = node ('n5', 'sin')
  n.inputs.x = { 0.25 }
  local def = assert (nodes.get ('sin'))
  local text = html.node_html (n, def, html.info_of (n, nil, {}, {}, {}))
  ok (has (text, 'data-item="n5|num|x|1" value="0.25"'))
end)

test ('a node shows a row for each output, input and setting', function ()
  local n = node ('n4', 'sin')
  local def = assert (nodes.get ('sin'))
  local info = html.info_of (n, nil, {}, {}, {})
  local text, color = html.node_html (n, def, info)
  ok (has (text, 'data-item="n4|head"'))
  ok (has (text, 'data-item="n4|pout|out"'), 'the output port')
  ok (has (text, 'data-item="n4|pin|x"'), 'the input port')
  ok (
    has (text, 'data-item="n4|num|x|1"'),
    'an unwired input has a number field'
  )
  ok (color:match ('^#'))
  -- Wired, the input shows its type instead of a field.
  local linked = html.info_of (n, nil, { n4 = { x = true } }, {}, {})
  ok (not has (html.node_html (n, def, linked), 'n4|num|x'))
  local broken = html.info_of (n, nil, {}, {}, { n4 = 'Bad <thing>' })
  ok (has (html.node_html (n, def, broken), 'Bad &lt;thing&gt;'))
  ok (
    has (
      html.missing_html (node ('n9', 'nope')),
      'There is no node called nope.'
    )
  )
end)

test ('a signature changes only when what the node shows changes', function ()
  local n = node ('n4', 'sin')
  local info = html.info_of (n, nil, {}, {}, {})
  local first = html.signature (n, info)
  eq (html.signature (n, html.info_of (n, nil, {}, {}, {})), first)
  local set = node ('n4', 'sin')
  set.inputs.x = { 2 }
  ok (html.signature (set, info) ~= first, 'a typed number')
  local wired = html.info_of (n, nil, { n4 = { x = true } }, {}, {})
  ok (html.signature (n, wired) ~= first, 'a wire in')
  ok (html.signature (n, nil):match ('^missing:'))
end)

test ('a colour parameter hides its range', function ()
  local p = node ('n1', 'parameter')
  local def = assert (nodes.get ('parameter'))
  local rows = html.rows (def, p)
  p.settings.kind = 'color'
  eq (html.rows (def, p), rows - 2)
  local text = html.node_html (p, def, html.info_of (p, nil, {}, {}, {}))
  ok (has (text, 'type="color"'))
end)

test (
  'a made node shows the ports of its group, with the types inside it',
  function ()
    local graph = core_require ('shader_graph') --[[@as Shader.GraphModule]]
    local subgraph = core_require ('shader_subgraph') --[[@as Shader.SubgraphModule]]
    local compile = core_require ('shader_compile') --[[@as Shader.CompileModule]]
    local doc, circle =
      assert (graph.add_node (graph.new ('Rings'), 'circle', 0, 0))
    doc = assert (graph.connect (doc, 'n1', 'uv', circle, 'uv'))
    doc = assert (graph.connect (doc, circle, 'mask', 'n2', 'color'))
    local made, id = subgraph.make (doc, { circle }, 'Disc <1>')
    assert (made, id)
    local n = assert (graph.node (made, id))
    -- The plain catalog does not know the made node. The graph does.
    eq (nodes.get (n.type), nil)
    local def = assert (graph.def (made, n.type))
    local result = compile.compile (made)
    local info = html.info_of (
      n,
      result,
      { [id] = { i1 = true } },
      { [id] = { o1 = true } },
      {},
      def
    )
    eq (info.ins, { i1 = 'vec2' })
    eq (info.outs, { o1 = 'float' })
    local text = html.node_html (n, def, info)
    ok (has (text, 'Disc &lt;1&gt;'))
    ok (has (text, 'data-item="' .. id .. '|pin|i1"'))
    ok (has (text, 'data-item="' .. id .. '|pout|o1"'))
    eq (html.rows (def, n), 2)
  end
)
