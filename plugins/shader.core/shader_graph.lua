-- Pure operations on a shader graph document. Each returns a new document, or nil and a
-- refusal, and never changes the one it was given. A new document shares every node and
-- list that did not change with the old one, so undo keeps many documents cheaply.

local nodes = require ('shader_nodes') --[[@as Shader.NodesModule]]

local FORMAT = 1

-- A wire passes through at most this many reroute points.
local MAX_POINTS = 32

local M = {}

M.FORMAT = FORMAT

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
---@param fields { nodes?: Shader.Node[], edges?: Shader.Edge[], name?: string, canvas?: Shader.CanvasData|false }
---@return Shader.Doc
local function with (doc, fields)
  local canvas = doc.canvas ---@type Shader.CanvasData?
  if fields.canvas ~= nil then
    canvas = fields.canvas or nil
  end
  ---@type Shader.Doc
  return {
    format = doc.format,
    name = fields.name or doc.name,
    preview = doc.preview,
    nodes = fields.nodes or doc.nodes,
    edges = fields.edges or doc.edges,
    canvas = canvas,
  }
end

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
  local def = nodes.get (type_id)
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
  return with (doc, { nodes = kept, edges = edges })
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
  local da, db = nodes.get (a.type), nodes.get (b.type)
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
  local def = n and nodes.get (n.type)
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
  local def = n and nodes.get (n.type)
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
  return fragment
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
  local grown = with (doc, { nodes = list })
  local map = {} ---@type table<string, string>
  local fresh = {} ---@type string[]
  for _, n in ipairs (fragment.nodes) do
    local def = nodes.get (n.type)
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
  local out = with (doc, { nodes = list, edges = edges })
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
  local def = n and nodes.get (n.type)
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
