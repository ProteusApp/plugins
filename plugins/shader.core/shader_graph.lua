-- Pure operations on a shader graph document. Each returns a new document, or nil and a
-- refusal, and never changes the one it was given. A new document shares every node and
-- list that did not change with the old one, so undo keeps many documents cheaply.

local nodes = require ('shader_nodes') --[[@as Shader.NodesModule]]
local passes = require ('shader_passes') --[[@as Shader.PassesModule]]

-- The newest file format this reads. A graph with made nodes saves as format 2, so an older
-- shader builder refuses it instead of losing its made nodes.
local FORMAT = 2

-- A made node's type is this, then the id of its subgraph in the document.
local SUBGRAPH = 'subgraph:'

-- A wire passes through at most this many reroute points.
local MAX_POINTS = 32

local M = {}

M.FORMAT = FORMAT
M.SUBGRAPH = SUBGRAPH

---A deep copy, for a caller that wants to change a document of its own.
---@generic T
---@param value T
---@return T
local function copy (value)
  if type (value) ~= 'table' then
    return value
  end
  local out = {} ---@type table<any, any>
  for k, v in
    pairs (value --[[@as table<any, any>]])
  do
    out[k] = copy (v)
  end
  return out
end

M.copy = copy

---The document with new top-level fields. Lists it does not name stay shared.
---@param doc Shader.Doc
---@param fields { nodes?: Shader.Node[], edges?: Shader.Edge[], name?: string, canvas?: Shader.CanvasData|false, channels?: table<string, Shader.ChannelSource>|false, subgraphs?: table<string, Shader.Subgraph>|false }
---@return Shader.Doc
local function with (doc, fields)
  local canvas = doc.canvas ---@type Shader.CanvasData?
  if fields.canvas ~= nil then
    canvas = fields.canvas or nil
  end
  local channels = doc.channels ---@type table<string, Shader.ChannelSource>?
  if fields.channels ~= nil then
    channels = fields.channels or nil
  end
  local subgraphs = doc.subgraphs ---@type table<string, Shader.Subgraph>?
  if fields.subgraphs ~= nil then
    subgraphs = fields.subgraphs or nil
  end
  ---@type Shader.Doc
  return {
    format = doc.format,
    name = fields.name or doc.name,
    preview = doc.preview,
    nodes = fields.nodes or doc.nodes,
    edges = fields.edges or doc.edges,
    canvas = canvas,
    channels = channels,
    subgraphs = subgraphs,
  }
end

M.with = with

-- Made nodes ----------------------------------------------------------------------------------

---The subgraph id in a made node's type, or nil for any other type.
---@param type_id string
---@return string?
function M.subgraph_id (type_id)
  if type (type_id) ~= 'string' or type_id:sub (1, #SUBGRAPH) ~= SUBGRAPH then
    return nil
  end
  return type_id:sub (#SUBGRAPH + 1)
end

-- The node each subgraph reads as, made once for each subgraph table. Subgraphs never change
-- in place, so a table always reads the same.
local made_defs = setmetatable ({}, { __mode = 'k' }) ---@type table<Shader.Subgraph, Shader.NodeDef>

---What a made node shows and takes, from its subgraph.
---@param type_id string
---@param sg Shader.Subgraph
---@return Shader.NodeDef
local function made_def (type_id, sg)
  local hit = made_defs[sg]
  if hit and hit.type == type_id then
    return hit
  end
  local inputs = {} ---@type Shader.PortDef[]
  for i, p in ipairs (sg.inputs) do
    inputs[i] = {
      key = p.key,
      label = p.label,
      type = p.type,
      default = p.default or { 0 },
      builtin = p.builtin,
      color = p.color,
    }
  end
  local outputs = {} ---@type Shader.OutputDef[]
  for i, p in ipairs (sg.outputs) do
    outputs[i] = { key = p.key, label = p.label, type = p.type, glsl = '' }
  end
  ---@type Shader.NodeDef
  local def = {
    type = type_id,
    title = sg.name,
    category = 'custom',
    description = 'Made from '
      .. #sg.nodes
      .. (#sg.nodes == 1 and ' node' or ' nodes')
      .. '. Unpack it to change what is inside.',
    inputs = inputs,
    outputs = outputs,
    settings = {},
  }
  made_defs[sg] = def
  return def
end

---A node type as this document reads it: a node of the catalog, or a node made from a group
---of nodes in this document.
---@param doc Shader.Doc
---@param type_id string
---@return Shader.NodeDef?
function M.def (doc, type_id)
  local found = nodes.get (type_id)
  if found then
    return found
  end
  local sid = M.subgraph_id (type_id)
  local sg = sid and doc.subgraphs and doc.subgraphs[sid]
  if not sg then
    return nil
  end
  return made_def (type_id, sg)
end

---The subgraphs nodes of these lists use, and the ones those use in turn.
---@param doc Shader.Doc
---@param list Shader.Node[]
---@return table<string, boolean>
function M.used_subgraphs (doc, list)
  local used = {} ---@type table<string, boolean>
  local subs = doc.subgraphs or {}
  ---@param ns Shader.Node[]
  local function visit (ns)
    for _, n in ipairs (ns) do
      local sid = M.subgraph_id (n.type)
      if sid and not used[sid] and subs[sid] then
        used[sid] = true
        visit (subs[sid].nodes)
      end
    end
  end
  visit (list)
  return used
end

---The document's subgraphs without the ones no node uses any more, or false when none are
---left.
---@param doc Shader.Doc
---@param list Shader.Node[] The document's nodes.
---@return table<string, Shader.Subgraph>|false
local function kept_subgraphs (doc, list)
  if not doc.subgraphs then
    return false
  end
  local used = M.used_subgraphs (doc, list)
  local out = {} ---@type table<string, Shader.Subgraph>
  local same = true
  for sid, sg in pairs (doc.subgraphs) do
    if used[sid] then
      out[sid] = sg
    else
      same = false
    end
  end
  if same then
    return doc.subgraphs
  end
  return next (out) and out or false
end

M.kept_subgraphs = kept_subgraphs

---A node with its own maps of inputs and settings, ready to change.
---@param n Shader.Node
---@return Shader.Node
local function copy_node (n)
  local inputs, settings = {}, {} ---@type table<string, number[]>, table<string, any>
  for k, v in pairs (n.inputs) do
    inputs[k] = v
  end
  for k, v in pairs (n.settings) do
    settings[k] = v
  end
  return {
    id = n.id,
    type = n.type,
    x = n.x,
    y = n.y,
    inputs = inputs,
    settings = settings,
  }
end

---@param doc Shader.Doc
---@param id string
---@return Shader.Node?, integer?
function M.node (doc, id)
  for i, n in ipairs (doc.nodes) do
    if n.id == id then
      return n, i
    end
  end
  return nil
end

---The edge wired into an input, if any.
---@param doc Shader.Doc
---@param to string
---@param input string
---@return Shader.Edge?, integer?
function M.edge_into (doc, to, input)
  for i, e in ipairs (doc.edges) do
    if e.to == to and e.input == input then
      return e, i
    end
  end
  return nil
end

---The id of the wire into an input, as the canvas and the canvas data name it.
---@param to string
---@param input string
---@return string
function M.wire_id (to, input)
  return to .. '|' .. input
end

---A fresh node id for the document.
---@param doc Shader.Doc
---@return string
function M.next_id (doc)
  local top = 0
  for _, n in ipairs (doc.nodes) do
    local k = tonumber (n.id:match ('^n(%d+)$'))
    if k and k > top then
      top = k
    end
  end
  return 'n' .. (top + 1)
end

---An empty document with an Output node, wired to show the UV coordinates.
---@param name? string
---@return Shader.Doc
function M.new (name)
  ---@type Shader.Doc
  local doc = {
    format = FORMAT,
    name = name or 'Untitled',
    nodes = {
      { id = 'n1', type = 'uv', x = 40, y = 80, inputs = {}, settings = {} },
      {
        id = 'n2',
        type = 'output',
        x = 380,
        y = 80,
        inputs = {},
        settings = {},
      },
    },
    edges = { { from = 'n1', output = 'uv', to = 'n2', input = 'color' } },
  }
  return doc
end

---@param doc Shader.Doc
---@param type_id string
---@param x number
---@param y number
---@return Shader.Doc?, string id_or_refusal
function M.add_node (doc, type_id, x, y)
  local def = M.def (doc, type_id)
  if not def then
    return nil, 'There is no node called ' .. tostring (type_id) .. '.'
  end
  if def.unique then
    for _, n in ipairs (doc.nodes) do
      if n.type == type_id then
        return nil, 'A shader has only one ' .. def.title .. ' node.'
      end
    end
  end
  local id = M.next_id (doc)
  local list = {} ---@type Shader.Node[]
  for i, n in ipairs (doc.nodes) do
    list[i] = n
  end
  list[#list + 1] = {
    id = id,
    type = type_id,
    x = math.floor (x + 0.5),
    y = math.floor (y + 0.5),
    inputs = {},
    settings = {},
  }
  return with (doc, { nodes = list }), id
end

---@param doc Shader.Doc
---@param ids string[]
---@return Shader.Doc?, string? refusal
function M.remove_nodes (doc, ids)
  local gone = {} ---@type table<string, boolean>
  for _, id in ipairs (ids) do
    gone[id] = true
  end
  local kept, edges = {}, {} ---@type Shader.Node[], Shader.Edge[]
  for _, n in ipairs (doc.nodes) do
    if not gone[n.id] then
      kept[#kept + 1] = n
    end
  end
  if #kept == #doc.nodes then
    return nil, 'Nothing to remove.'
  end
  for _, e in ipairs (doc.edges) do
    if not gone[e.from] and not gone[e.to] then
      edges[#edges + 1] = e
    end
  end
  return with (doc, {
    nodes = kept,
    edges = edges,
    subgraphs = kept_subgraphs (doc, kept),
  })
end

---@param doc Shader.Doc
---@param moves table<string, { x: number, y: number }>
---@return Shader.Doc
function M.move (doc, moves)
  local list = {} ---@type Shader.Node[]
  for i, n in ipairs (doc.nodes) do
    local p = moves[n.id]
    if p then
      local moved = copy_node (n)
      moved.x, moved.y = math.floor (p.x + 0.5), math.floor (p.y + 0.5)
      list[i] = moved
    else
      list[i] = n
    end
  end
  return with (doc, { nodes = list })
end

---True when `target` can be reached by following wires upstream from `start`.
---@param doc Shader.Doc
---@param start string
---@param target string
---@return boolean
local function upstream (doc, start, target)
  local into = {} ---@type table<string, string[]>
  for _, e in ipairs (doc.edges) do
    local list = into[e.to] or {}
    list[#list + 1] = e.from
    into[e.to] = list
  end
  local seen = {} ---@type table<string, boolean>
  local stack = { start }
  while #stack > 0 do
    local id = table.remove (stack)
    if id == target then
      return true
    end
    if not seen[id] then
      seen[id] = true
      for _, from in ipairs (into[id] or {}) do
        stack[#stack + 1] = from
      end
    end
  end
  return false
end

---Why a wire from an output to an input cannot go, or nil when it can.
---@param doc Shader.Doc
---@param from string
---@param output string
---@param to string
---@param input string
---@return string? refusal
function M.why_not (doc, from, output, to, input)
  local a, b = M.node (doc, from), M.node (doc, to)
  if not a or not b then
    return 'That node is gone.'
  end
  if from == to then
    return 'A node cannot feed itself.'
  end
  local da, db = M.def (doc, a.type), M.def (doc, b.type)
  if not da or not db or not nodes.output (da, output) then
    return 'That output does not exist.'
  end
  if not nodes.input (db, input) then
    return 'That input does not exist.'
  end
  if upstream (doc, from, to) then
    return 'That wire would make a loop.'
  end
  return nil
end

---Wires an output into an input. A wire already in that input is replaced.
---@param doc Shader.Doc
---@param from string
---@param output string
---@param to string
---@param input string
---@return Shader.Doc?, string? refusal
function M.connect (doc, from, output, to, input)
  local refusal = M.why_not (doc, from, output, to, input)
  if refusal then
    return nil, refusal
  end
  local edges = {} ---@type Shader.Edge[]
  local edge = { from = from, output = output, to = to, input = input }
  local placed = false
  for i, e in ipairs (doc.edges) do
    if e.to == to and e.input == input then
      edges[i] = edge
      placed = true
    else
      edges[i] = e
    end
  end
  if not placed then
    edges[#edges + 1] = edge
  end
  return with (doc, { edges = edges })
end

---@param doc Shader.Doc
---@param to string
---@param input string
---@return Shader.Doc?, string? refusal
function M.disconnect (doc, to, input)
  local _, i = M.edge_into (doc, to, input)
  if not i then
    return nil, 'Nothing is wired there.'
  end
  local edges = {} ---@type Shader.Edge[]
  for k, e in ipairs (doc.edges) do
    if k ~= i then
      edges[#edges + 1] = e
    end
  end
  return with (doc, { edges = edges })
end

---The document with one node changed by `change`, which gets a copy to change.
---@param doc Shader.Doc
---@param id string
---@param change fun(n: Shader.Node)
---@return Shader.Doc
local function change_node (doc, id, change)
  local list = {} ---@type Shader.Node[]
  for i, n in ipairs (doc.nodes) do
    if n.id == id then
      local changed = copy_node (n)
      change (changed)
      list[i] = changed
    else
      list[i] = n
    end
  end
  return with (doc, { nodes = list })
end

---Sets the numbers an unwired input uses.
---@param doc Shader.Doc
---@param id string
---@param key string
---@param values number[]?
---@return Shader.Doc?, string? refusal
function M.set_input (doc, id, key, values)
  local n = M.node (doc, id)
  local def = n and M.def (doc, n.type)
  if not n or not def or not nodes.input (def, key) then
    return nil, 'That input does not exist.'
  end
  return change_node (doc, id, function (changed)
    changed.inputs[key] = values and copy (values) or nil
  end)
end

---@param doc Shader.Doc
---@param id string
---@param key string
---@param value any
---@return Shader.Doc?, string? refusal
function M.set_setting (doc, id, key, value)
  local n = M.node (doc, id)
  local def = n and M.def (doc, n.type)
  if not n or not def then
    return nil, 'That node is gone.'
  end
  local known = false
  for _, s in ipairs (def.settings) do
    known = known or s.key == key
  end
  if not known then
    return nil, 'That setting does not exist.'
  end
  return change_node (doc, id, function (changed)
    changed.settings[key] = copy (value)
  end)
end

---@param doc Shader.Doc
---@param name string
---@return Shader.Doc
function M.rename (doc, name)
  return with (doc, { name = name })
end

---Finds the Parameter node whose uniform has this name.
---@param doc Shader.Doc
---@param name string
---@return Shader.Node?
function M.parameter (doc, name)
  for _, n in ipairs (doc.nodes) do
    if n.type == 'parameter' then
      local def = nodes.get ('parameter') --[[@as Shader.NodeDef]]
      if nodes.setting (def, n.settings, 'name') == name then
        return n
      end
    end
  end
  return nil
end

-- The canvas's own data ----------------------------------------------------------------------

---@param value any
---@return boolean
local function finite (value)
  return type (value) == 'number'
    and value == value
    and value > -math.huge
    and value < math.huge
end

---@param f any
---@return boolean
local function frame_shaped (f)
  if type (f) ~= 'table' then
    return false
  end
  local color = f.color ---@type any
  return type (f.id) == 'string'
    and f.id ~= ''
    and finite (f.x)
    and finite (f.y)
    and finite (f.w)
    and finite (f.h)
    and f.w > 0
    and f.h > 0
    and type (f.title) == 'string'
    and (
      color == nil
      or (type (color) == 'string' and color:match ('^#%x%x%x%x%x%x$') ~= nil)
    )
end

---The canvas's frames and reroute points as the document keeps them: shapes checked, and the
---points of wires that are gone left out. Nil when there is nothing to keep.
---@param doc Shader.Doc
---@param data any
---@return Shader.CanvasData?
---@return string? refusal
local function clean_canvas (doc, data)
  if data == nil then
    return nil
  end
  local bad = 'The canvas data is not right.'
  if type (data) ~= 'table' then
    return nil, bad
  end
  local frames = {} ---@type Shader.Frame[]
  local seen = {} ---@type table<string, boolean>
  local frame_list = type (data.frames) == 'table' and data.frames or {} ---@type any[]
  for _, f in ipairs (frame_list) do
    if not frame_shaped (f) or seen[f.id] then
      return nil, bad
    end
    seen[f.id] = true
    frames[#frames + 1] = {
      id = f.id,
      x = f.x,
      y = f.y,
      w = f.w,
      h = f.h,
      title = f.title,
      color = f.color,
    }
  end
  local wired = {} ---@type table<string, boolean>
  for _, e in ipairs (doc.edges) do
    wired[M.wire_id (e.to, e.input)] = true
  end
  local routes = {} ---@type Shader.Route[]
  local routed = {} ---@type table<string, boolean>
  local route_list = type (data.routes) == 'table' and data.routes or {} ---@type any[]
  for _, r in ipairs (route_list) do
    if
      type (r) ~= 'table'
      or type (r.to) ~= 'string'
      or type (r.input) ~= 'string'
      or type (r.points) ~= 'table'
      or #r.points == 0
      or #r.points > MAX_POINTS
    then
      return nil, bad
    end
    local id = M.wire_id (r.to, r.input)
    local points = {} ---@type { x: number, y: number }[]
    for i, p in
      ipairs (r.points --[[@as any[] ]])
    do
      if type (p) ~= 'table' or not finite (p.x) or not finite (p.y) then
        return nil, bad
      end
      points[i] = { x = p.x, y = p.y }
    end
    if wired[id] and not routed[id] then
      routed[id] = true
      routes[#routes + 1] = { to = r.to, input = r.input, points = points }
    end
  end
  if #frames == 0 and #routes == 0 then
    return nil
  end
  return { frames = frames, routes = routes }
end

---Puts the canvas's frames and reroute points in place.
---@param doc Shader.Doc
---@param data Shader.CanvasData?
---@return Shader.Doc?, string? refusal
function M.set_canvas (doc, data)
  local clean, refusal = clean_canvas (doc, data)
  if refusal then
    return nil, refusal
  end
  return with (doc, { canvas = clean or false })
end

---Sets what a channel shows, 0 to 3. Nil leaves the channel to the Preview's default.
---@param doc Shader.Doc
---@param index integer
---@param source Shader.ChannelSource?
---@return Shader.Doc
function M.set_channel (doc, index, source)
  local out = {} ---@type table<string, Shader.ChannelSource>
  for k, v in pairs (doc.channels or {}) do
    out[k] = v
  end
  if index >= 0 and index < passes.COUNT then
    out[tostring (index)] = passes.clean_source (source)
  end
  return with (doc, { channels = next (out) and out or false })
end

---@param doc Shader.Doc
---@return Shader.Frame[]
function M.frames (doc)
  return doc.canvas and doc.canvas.frames or {}
end

---Each wire's reroute points, by wire id.
---@param doc Shader.Doc
---@return table<string, { x: number, y: number }[]>
function M.routes (doc)
  local out = {} ---@type table<string, { x: number, y: number }[]>
  for _, r in ipairs (doc.canvas and doc.canvas.routes or {}) do
    out[M.wire_id (r.to, r.input)] = r.points
  end
  return out
end

---Puts frames and each wire's reroute points, by wire id, into the document.
---@param doc Shader.Doc
---@param frames Shader.Frame[]
---@param routes table<string, { x: number, y: number }[]>
---@return Shader.Doc
function M.with_canvas (doc, frames, routes)
  local list = {} ---@type Shader.Route[]
  -- Routes follow the order of the edges, so the same drawing always saves the same.
  for _, e in ipairs (doc.edges) do
    local points = routes[M.wire_id (e.to, e.input)]
    if points and #points > 0 then
      list[#list + 1] = { to = e.to, input = e.input, points = points }
    end
  end
  return M.set_canvas (doc, { frames = frames, routes = list }) or doc
end

---A frame id no frame has yet, such as `'f3'`.
---@param frames Shader.Frame[]
---@return string
function M.next_frame_id (frames)
  local top = 0
  for _, f in ipairs (frames) do
    local k = tonumber (f.id:match ('^f(%d+)$'))
    if k and k > top then
      top = k
    end
  end
  return 'f' .. (top + 1)
end

-- Copy and paste -----------------------------------------------------------------------------

---Copies nodes, with the wires between them, their reroute points, and frames, so they can
---be pasted into this graph or another.
---@param doc Shader.Doc
---@param ids string[]
---@param frame_ids? string[]
---@return Shader.Fragment
function M.copy_nodes (doc, ids, frame_ids)
  local wanted = {} ---@type table<string, boolean>
  for _, id in ipairs (ids) do
    wanted[id] = true
  end
  ---@type Shader.Fragment
  local fragment = { nodes = {}, edges = {}, frames = {}, routes = {} }
  for _, n in ipairs (doc.nodes) do
    if wanted[n.id] then
      fragment.nodes[#fragment.nodes + 1] = n
    end
  end
  local routes = M.routes (doc)
  for _, e in ipairs (doc.edges) do
    if wanted[e.from] and wanted[e.to] then
      local id = M.wire_id (e.to, e.input)
      fragment.edges[#fragment.edges + 1] = e
      fragment.routes[id] = routes[id]
    end
  end
  local frames = {} ---@type table<string, boolean>
  for _, id in ipairs (frame_ids or {}) do
    frames[id] = true
  end
  for _, f in ipairs (M.frames (doc)) do
    if frames[f.id] then
      fragment.frames[#fragment.frames + 1] = f
    end
  end
  -- Made nodes carry their subgraphs, so they paste into another graph.
  for sid in pairs (M.used_subgraphs (doc, fragment.nodes)) do
    fragment.subgraphs = fragment.subgraphs or {}
    fragment.subgraphs[sid] = (doc.subgraphs or {})[sid]
  end
  return fragment
end

---True when two values hold the same, all the way down.
---@param a any
---@param b any
---@return boolean
local function same (a, b)
  if a == b then
    return true
  end
  if type (a) ~= 'table' or type (b) ~= 'table' then
    return false
  end
  for k, v in
    pairs (a --[[@as table<any, any>]])
  do
    if not same (v, b[k]) then
      return false
    end
  end
  for k in
    pairs (b --[[@as table<any, any>]])
  do
    if a[k] == nil then
      return false
    end
  end
  return true
end

---A subgraph id no subgraph has yet, such as `'s3'`.
---@param subs table<string, Shader.Subgraph>
---@return string
function M.next_subgraph_id (subs)
  local top = 0
  for sid in pairs (subs) do
    local k = tonumber (sid:match ('^s(%d+)$'))
    if k and k > top then
      top = k
    end
  end
  return 's' .. (top + 1)
end

---The nodes with the made nodes among them pointed at new subgraph ids.
---@param list Shader.Node[]
---@param map table<string, string> New subgraph ids by old.
---@return Shader.Node[]
function M.retype (list, map)
  local out = {} ---@type Shader.Node[]
  for i, n in ipairs (list) do
    local sid = M.subgraph_id (n.type)
    if sid and map[sid] and map[sid] ~= sid then
      local c = copy_node (n)
      c.type = SUBGRAPH .. map[sid]
      out[i] = c
    else
      out[i] = n
    end
  end
  return out
end

---The document's subgraphs with ones from another graph added. One this graph holds the same
---is shared. One whose id this graph uses for another gets a new id.
---@param doc Shader.Doc
---@param incoming table<string, Shader.Subgraph>?
---@return table<string, Shader.Subgraph>? subgraphs
---@return table<string, string> map The id each incoming subgraph has now.
local function merge_subgraphs (doc, incoming)
  local map = {} ---@type table<string, string>
  if not incoming or next (incoming) == nil then
    return doc.subgraphs, map
  end
  local subs = {} ---@type table<string, Shader.Subgraph>
  for sid, sg in pairs (doc.subgraphs or {}) do
    subs[sid] = sg
  end
  local order = {} ---@type string[]
  for sid in pairs (incoming) do
    order[#order + 1] = sid
  end
  table.sort (order)
  local shared = {} ---@type table<string, boolean>
  for _, sid in ipairs (order) do
    if subs[sid] and same (subs[sid], incoming[sid]) then
      shared[sid] = true
    end
  end
  -- A subgraph is shared only when every subgraph inside it is shared too.
  local changed = true
  while changed do
    changed = false
    for _, sid in ipairs (order) do
      if shared[sid] then
        for _, n in ipairs (incoming[sid].nodes) do
          local inner = M.subgraph_id (n.type)
          if inner and incoming[inner] and not shared[inner] then
            shared[sid] = nil
            changed = true
          end
        end
      end
    end
  end
  for _, sid in ipairs (order) do
    if shared[sid] then
      map[sid] = sid
    elseif not subs[sid] then
      map[sid] = sid
      subs[sid] = incoming[sid]
    else
      map[sid] = M.next_subgraph_id (subs)
      subs[map[sid]] = incoming[sid]
    end
  end
  for _, sid in ipairs (order) do
    local sg = incoming[sid]
    if not shared[sid] then
      subs[map[sid]] = {
        name = sg.name,
        nodes = M.retype (sg.nodes, map),
        edges = sg.edges,
        inputs = sg.inputs,
        outputs = sg.outputs,
      }
    end
  end
  return subs, map
end

---@param v number
---@return number
local function round (v)
  return math.floor (v + 0.5)
end

---Adds a copy of a fragment, moved by `dx` and `dy`. A node there can be only one of, such
---as the Output, is left out when the graph has one already.
---@param doc Shader.Doc
---@param fragment Shader.Fragment
---@param dx number
---@param dy number
---@return Shader.Doc? doc
---@return string[] nodes The new nodes' ids.
---@return string[] frames The new frames' ids.
function M.paste (doc, fragment, dx, dy)
  local list = {} ---@type Shader.Node[]
  local has = {} ---@type table<string, boolean>
  for i, n in ipairs (doc.nodes) do
    list[i] = n
    has[n.type] = true
  end
  local subgraphs, sub_map = merge_subgraphs (doc, fragment.subgraphs)
  local grown = with (doc, { nodes = list, subgraphs = subgraphs or false })
  local map = {} ---@type table<string, string>
  local fresh = {} ---@type string[]
  for _, n in ipairs (M.retype (fragment.nodes, sub_map)) do
    local def = M.def (grown, n.type)
    if def and not (def.unique and has[n.type]) then
      local id = M.next_id (grown)
      local c = copy (n)
      c.id, c.x, c.y = id, round (n.x + dx), round (n.y + dy)
      list[#list + 1] = c
      map[n.id] = id
      fresh[#fresh + 1] = id
      has[n.type] = true
    end
  end
  if #fresh == 0 and #fragment.frames == 0 then
    return nil, {}, {}
  end
  local edges = {} ---@type Shader.Edge[]
  for i, e in ipairs (doc.edges) do
    edges[i] = e
  end
  local routes = M.routes (doc)
  for _, e in ipairs (fragment.edges) do
    if map[e.from] and map[e.to] then
      edges[#edges + 1] = {
        from = map[e.from],
        output = e.output,
        to = map[e.to],
        input = e.input,
      }
      local points = fragment.routes[M.wire_id (e.to, e.input)]
      if points then
        local moved = {} ---@type { x: number, y: number }[]
        for i, p in ipairs (points) do
          moved[i] = { x = round (p.x + dx), y = round (p.y + dy) }
        end
        routes[M.wire_id (map[e.to], e.input)] = moved
      end
    end
  end
  local frames = {} ---@type Shader.Frame[]
  for i, f in ipairs (M.frames (doc)) do
    frames[i] = f
  end
  local new_frames = {} ---@type string[]
  for _, f in ipairs (fragment.frames) do
    local id = M.next_frame_id (frames)
    frames[#frames + 1] = {
      id = id,
      x = round (f.x + dx),
      y = round (f.y + dy),
      w = f.w,
      h = f.h,
      title = f.title,
      color = f.color,
    }
    new_frames[#new_frames + 1] = id
  end
  local out = with (grown, { nodes = list, edges = edges })
  out = with (out, { subgraphs = kept_subgraphs (out, list) })
  return M.with_canvas (out, frames, routes), fresh, new_frames
end

---Copies nodes, with the wires between them, a little down and to the right.
---@param doc Shader.Doc
---@param ids string[]
---@return Shader.Doc?, string[]|string new_ids_or_refusal
function M.duplicate (doc, ids)
  local out, fresh = M.paste (doc, M.copy_nodes (doc, ids), 40, 40)
  if not out or #fresh == 0 then
    return nil, 'Nothing to duplicate.'
  end
  return out, fresh
end

---Puts a node into the wire `wire`, which is `<to>|<input>`: the wire's source feeds the
---node's first free input, and the node's first output feeds where the wire went. Nil when
---the node cannot go there.
---@param doc Shader.Doc
---@param id string
---@param wire string
---@return Shader.Doc?
function M.insert (doc, id, wire)
  local to, input = wire:match ('^(.-)|(.*)$')
  local e = to and M.edge_into (doc, to, input)
  local n = M.node (doc, id)
  local def = n and M.def (doc, n.type)
  if not e or not def or e.from == id or e.to == id then
    return nil
  end
  local cut = M.disconnect (doc, e.to, e.input)
  if not cut then
    return nil
  end
  for _, port in ipairs (def.inputs) do
    if not M.edge_into (cut, id, port.key) then
      local into = M.connect (cut, e.from, e.output, id, port.key)
      if into then
        for _, o in ipairs (nodes.visible_outputs (def)) do
          local done = M.connect (into, id, o.key, e.to, e.input)
          if done then
            return done
          end
        end
      end
    end
  end
  return nil
end

return M
