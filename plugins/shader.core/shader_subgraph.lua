-- Made nodes: a group of nodes turned into one node, and back. The group is a subgraph the
-- document keeps in `subgraphs`, by an id such as `s1`, and a made node's type is
-- `subgraph:s1`. A wire from outside the group into it becomes an input of the made node, and
-- a wire from the group to a node outside becomes an output.
--
-- The compiler never sees a made node. `expand` puts each one's nodes back in its place
-- first, with ids that start with the made node's, so `n5` holds `n5_n1` and `n5_n2`.

local graph = require ('shader_graph') --[[@as Shader.GraphModule]]
local nodes = require ('shader_nodes') --[[@as Shader.NodesModule]]

-- How deep made nodes may sit inside each other.
local MAX_DEPTH = 8

local M = {}

---@param list string[]
---@return table<string, boolean>
local function set_of (list)
  local out = {} ---@type table<string, boolean>
  for _, v in ipairs (list) do
    out[v] = true
  end
  return out
end

---A label not taken yet: the label, or the label and a number.
---@param label string
---@param taken table<string, boolean>
---@return string
local function fresh_label (label, taken)
  local text = label ~= '' and label or 'value'
  local out, n = text, 1
  while taken[out] do
    n = n + 1
    out = text .. ' ' .. n
  end
  taken[out] = true
  return out
end

---Makes one node from a group of nodes. Wires from outside into the group become its
---inputs, and wires out of it its outputs. When nothing outside reads the group, each output
---of a node nothing inside reads becomes one.
---@param doc Shader.Doc
---@param ids string[]
---@param name? string
---@return Shader.Doc? doc
---@return string id_or_refusal The made node's id.
function M.make (doc, ids, name)
  local picked = set_of (ids)
  local inside = {} ---@type Shader.Node[]
  local left, top = math.huge, math.huge
  for _, n in ipairs (doc.nodes) do
    if picked[n.id] then
      local def = graph.def (doc, n.type)
      if not def then
        return nil, 'There is no node called ' .. n.type .. '.'
      end
      if def.unique then
        return nil, 'The ' .. def.title .. ' node cannot go inside a made node.'
      end
      inside[#inside + 1] = n
      left, top = math.min (left, n.x), math.min (top, n.y)
    end
  end
  if #inside == 0 then
    return nil, 'Pick the nodes to make a node from.'
  end

  local inner_nodes = {} ---@type Shader.Node[]
  for i, n in ipairs (inside) do
    local c = graph.copy (n) --[[@as Shader.Node]]
    c.x, c.y = n.x - left, n.y - top
    inner_nodes[i] = c
  end

  local inner_edges = {} ---@type Shader.Edge[]
  local inputs = {} ---@type Shader.SubgraphInput[]
  local input_of = {} ---@type table<string, Shader.SubgraphInput>
  local outputs = {} ---@type Shader.SubgraphOutput[]
  local output_of = {} ---@type table<string, Shader.SubgraphOutput>
  local in_labels, out_labels = {}, {} ---@type table<string, boolean>, table<string, boolean>
  -- The wires outside the group, kept, and the ones that cross into or out of it.
  local outer_edges = {} ---@type Shader.Edge[]
  local crossing_in = {} ---@type { from: string, output: string, key: string }[]
  local crossing_out = {} ---@type { key: string, to: string, input: string }[]

  ---@param n_id string
  ---@param output string
  ---@return Shader.SubgraphOutput
  local function output_port (n_id, output)
    local key = n_id .. '.' .. output
    local port = output_of[key]
    if port then
      return port
    end
    local n = graph.node (doc, n_id) --[[@as Shader.Node]]
    local def = graph.def (doc, n.type) --[[@as Shader.NodeDef]]
    local o = nodes.output (def, output)
    local label = o and o.label ~= '' and o.label or def.title
    port = {
      key = 'o' .. (#outputs + 1),
      label = fresh_label (label, out_labels),
      type = o and nodes.output_type (def, o, n.settings) or 'float',
      node = n_id,
      output = output,
    }
    if type (port.type) ~= 'string' then
      port.type = 'float'
    end
    outputs[#outputs + 1] = port
    output_of[key] = port
    return port
  end

  for _, e in ipairs (doc.edges) do
    local from_in, to_in = picked[e.from], picked[e.to]
    if from_in and to_in then
      inner_edges[#inner_edges + 1] = e
    elseif to_in then
      local key = e.from .. '.' .. e.output
      local port = input_of[key]
      local target = graph.node (doc, e.to) --[[@as Shader.Node]]
      if not port then
        local def = graph.def (doc, target.type) --[[@as Shader.NodeDef]]
        local p = nodes.input (def, e.input)
        port = {
          key = 'i' .. (#inputs + 1),
          label = fresh_label (p and p.label or e.input, in_labels),
          type = p and p.type or 'gen',
          default = graph.copy (
            target.inputs[e.input] or (p and p.default) or { 0 }
          ),
          builtin = p and p.builtin,
          color = p and p.color,
          targets = {},
        }
        inputs[#inputs + 1] = port
        input_of[key] = port
        crossing_in[#crossing_in + 1] =
          { from = e.from, output = e.output, key = port.key }
      end
      port.targets[#port.targets + 1] = { node = e.to, input = e.input }
    elseif from_in then
      local port = output_port (e.from, e.output)
      crossing_out[#crossing_out + 1] =
        { key = port.key, to = e.to, input = e.input }
    else
      outer_edges[#outer_edges + 1] = e
    end
  end

  if #outputs == 0 then
    local read = {} ---@type table<string, boolean>
    for _, e in ipairs (inner_edges) do
      read[e.from] = true
    end
    for _, n in ipairs (inside) do
      if not read[n.id] then
        local def = graph.def (doc, n.type) --[[@as Shader.NodeDef]]
        for _, o in ipairs (nodes.visible_outputs (def)) do
          output_port (n.id, o.key)
        end
      end
    end
  end

  local subs = {} ---@type table<string, Shader.Subgraph>
  for sid, sg in pairs (doc.subgraphs or {}) do
    subs[sid] = sg
  end
  local sid = graph.next_subgraph_id (subs)
  local title = tostring (name or ''):gsub ('%c', ' '):match ('^%s*(.-)%s*$')
  ---@type Shader.Subgraph
  local sg = {
    name = title ~= '' and title or 'Made node',
    nodes = inner_nodes,
    edges = inner_edges,
    inputs = inputs,
    outputs = outputs,
  }
  subs[sid] = sg

  local kept = {} ---@type Shader.Node[]
  for _, n in ipairs (doc.nodes) do
    if not picked[n.id] then
      kept[#kept + 1] = n
    end
  end
  local id = graph.next_id (doc)
  kept[#kept + 1] = {
    id = id,
    type = graph.SUBGRAPH .. sid,
    x = math.floor (left + 0.5),
    y = math.floor (top + 0.5),
    inputs = {},
    settings = {},
  }
  for _, c in ipairs (crossing_in) do
    outer_edges[#outer_edges + 1] =
      { from = c.from, output = c.output, to = id, input = c.key }
  end
  for _, c in ipairs (crossing_out) do
    outer_edges[#outer_edges + 1] =
      { from = id, output = c.key, to = c.to, input = c.input }
  end
  local out =
    graph.with (doc, { nodes = kept, edges = outer_edges, subgraphs = subs })
  -- Reroute points of wires that are gone go with them.
  return graph.with_canvas (out, graph.frames (out), graph.routes (out)), id
end

---Puts a made node's nodes back in its place, wired as the made node was.
---@param doc Shader.Doc
---@param id string
---@return Shader.Doc? doc
---@return string[]|string ids_or_refusal The ids of the nodes put back.
function M.unpack (doc, id)
  local use = graph.node (doc, id)
  local sid = use and graph.subgraph_id (use.type)
  local sg = sid and doc.subgraphs and doc.subgraphs[sid]
  if not use or not sg then
    return nil, 'Only a made node can be unpacked.'
  end
  local list = {} ---@type Shader.Node[]
  for _, n in ipairs (doc.nodes) do
    if n.id ~= id then
      list[#list + 1] = n
    end
  end
  local grown = graph.with (doc, { nodes = list })
  local map = {} ---@type table<string, string>
  local fresh = {} ---@type string[]
  for _, n in ipairs (sg.nodes) do
    local c = graph.copy (n) --[[@as Shader.Node]]
    c.id = graph.next_id (grown)
    c.x, c.y = math.floor (use.x + n.x + 0.5), math.floor (use.y + n.y + 0.5)
    list[#list + 1] = c
    map[n.id] = c.id
    fresh[#fresh + 1] = c.id
  end
  -- The numbers the made node held for its unwired inputs go into the nodes they fed.
  local by_id = {} ---@type table<string, Shader.Node>
  for _, n in ipairs (list) do
    by_id[n.id] = n
  end
  local wired = {} ---@type table<string, boolean>
  for _, e in ipairs (doc.edges) do
    if e.to == id then
      wired[e.input] = true
    end
  end
  for _, p in ipairs (sg.inputs) do
    local value = use.inputs[p.key]
    if value and not wired[p.key] then
      for _, t in ipairs (p.targets) do
        local n = by_id[map[t.node] or '']
        if n then
          n.inputs[t.input] = graph.copy (value)
        end
      end
    end
  end
  local edges = {} ---@type Shader.Edge[]
  local input_of = {} ---@type table<string, Shader.SubgraphInput>
  for _, p in ipairs (sg.inputs) do
    input_of[p.key] = p
  end
  local output_of = {} ---@type table<string, Shader.SubgraphOutput>
  for _, p in ipairs (sg.outputs) do
    output_of[p.key] = p
  end
  for _, e in ipairs (doc.edges) do
    if e.to == id then
      local p = input_of[e.input]
      for _, t in ipairs (p and p.targets or {}) do
        if map[t.node] then
          edges[#edges + 1] = {
            from = e.from,
            output = e.output,
            to = map[t.node],
            input = t.input,
          }
        end
      end
    elseif e.from == id then
      local p = output_of[e.output]
      if p and map[p.node] then
        edges[#edges + 1] =
          { from = map[p.node], output = p.output, to = e.to, input = e.input }
      end
    else
      edges[#edges + 1] = e
    end
  end
  for _, e in ipairs (sg.edges) do
    if map[e.from] and map[e.to] then
      edges[#edges + 1] = {
        from = map[e.from],
        output = e.output,
        to = map[e.to],
        input = e.input,
      }
    end
  end
  local out = graph.with (grown, { nodes = list, edges = edges })
  out = graph.with (out, { subgraphs = graph.kept_subgraphs (out, list) })
  return graph.with_canvas (out, graph.frames (out), graph.routes (out)), fresh
end

---Renames the subgraph a made node shows. Every node made from it shows the new name.
---@param doc Shader.Doc
---@param sid string
---@param name string
---@return Shader.Doc? doc
---@return string? refusal
function M.rename (doc, sid, name)
  local sg = doc.subgraphs and doc.subgraphs[sid]
  local title = tostring (name or ''):gsub ('%c', ' '):match ('^%s*(.-)%s*$')
  if not sg then
    return nil, 'That made node is gone.'
  end
  if title == '' then
    return nil, 'A made node needs a name.'
  end
  local subs = {} ---@type table<string, Shader.Subgraph>
  for k, v in pairs (doc.subgraphs) do
    subs[k] = v
  end
  subs[sid] = {
    name = title,
    nodes = sg.nodes,
    edges = sg.edges,
    inputs = sg.inputs,
    outputs = sg.outputs,
  }
  return graph.with (doc, { subgraphs = subs })
end

---The subgraphs a document holds, in id order, with the type of a node made from each.
---@param doc Shader.Doc
---@return { id: string, type: string, subgraph: Shader.Subgraph }[]
function M.list (doc)
  local out = {} ---@type { id: string, type: string, subgraph: Shader.Subgraph }[]
  for sid, sg in pairs (doc.subgraphs or {}) do
    out[#out + 1] = { id = sid, type = graph.SUBGRAPH .. sid, subgraph = sg }
  end
  table.sort (out, function (a, b)
    local x, y =
      tonumber (a.id:match ('%d+')) or 0, tonumber (b.id:match ('%d+')) or 0
    if x ~= y then
      return x < y
    end
    return a.id < b.id
  end)
  return out
end

---The graph with every made node replaced by its nodes, and where each node came from. The
---compiler runs on the result. A made node whose subgraph is missing stays as it is, and the
---compiler says so.
---@param doc Shader.Doc
---@return Shader.Doc flat
---@return Shader.Expansion? expansion Nil when the graph has no made nodes.
function M.expand (doc)
  local any = false
  for _, n in ipairs (doc.nodes) do
    any = any or graph.subgraph_id (n.type) ~= nil
  end
  if not any then
    return doc, nil
  end
  local subs = doc.subgraphs or {}
  local out_nodes = {} ---@type Shader.Node[]
  local out_edges = {} ---@type Shader.Edge[]
  ---@type Shader.Expansion
  local expansion = { owner = {}, ports = {} }
  -- Every node placed so far, by its new id. Each one is a copy, so its inputs can change.
  local copies = {} ---@type table<string, Shader.Node>

  ---Places a list of nodes and wires, and returns where each node went.
  ---@param list Shader.Node[]
  ---@param edges Shader.Edge[]
  ---@param prefix string
  ---@param top? string The top-level made node they sit in.
  ---@param depth integer
  ---@return table<string, Shader.Placed>
  local function place (list, edges, prefix, top, depth)
    local placed = {} ---@type table<string, Shader.Placed>
    for _, n in ipairs (list) do
      local sid = graph.subgraph_id (n.type)
      local sg = sid and subs[sid]
      local new_id = prefix .. n.id
      if sg and depth < MAX_DEPTH then
        local inner =
          place (sg.nodes, sg.edges, new_id .. '_', top or new_id, depth + 1)
        local ins = {} ---@type table<string, { node: string, input: string }[]>
        for _, p in ipairs (sg.inputs) do
          local targets = {} ---@type { node: string, input: string }[]
          for _, t in ipairs (p.targets) do
            local where = inner[t.node]
            if where and where.id then
              targets[#targets + 1] = { node = where.id, input = t.input }
            elseif where and where.ins then
              for _, deeper in ipairs (where.ins[t.input] or {}) do
                targets[#targets + 1] = deeper
              end
            end
          end
          ins[p.key] = targets
        end
        local outs = {} ---@type table<string, { node: string, output: string }>
        for _, p in ipairs (sg.outputs) do
          local where = inner[p.node]
          if where and where.id then
            outs[p.key] = { node = where.id, output = p.output }
          elseif where and where.outs then
            outs[p.key] = where.outs[p.output]
          end
        end
        placed[n.id] = { ins = ins, outs = outs }
        -- The numbers a made node holds go into the inputs they feed, unless wired.
        local wired = {} ---@type table<string, boolean>
        for _, e in ipairs (edges) do
          if e.to == n.id then
            wired[e.input] = true
          end
        end
        for key, targets in pairs (ins) do
          local value = n.inputs[key]
          if value and not wired[key] then
            for _, t in ipairs (targets) do
              local c = copies[t.node]
              if c then
                c.inputs[t.input] = value
              end
            end
          end
        end
        if not top then
          expansion.ports[n.id] = { ins = ins, outs = outs }
        end
      else
        local c = {
          id = new_id,
          type = n.type,
          x = n.x,
          y = n.y,
          inputs = {},
          settings = n.settings,
        } ---@type Shader.Node
        for k, v in pairs (n.inputs) do
          c.inputs[k] = v
        end
        out_nodes[#out_nodes + 1] = c
        copies[new_id] = c
        expansion.owner[new_id] = top or new_id
        placed[n.id] = { id = new_id }
      end
    end
    for _, e in ipairs (edges) do
      local from, to = placed[e.from], placed[e.to]
      local source ---@type { node: string, output: string }?
      if from and from.id then
        source = { node = from.id, output = e.output }
      elseif from and from.outs then
        source = from.outs[e.output]
      end
      local targets = {} ---@type { node: string, input: string }[]
      if to and to.id then
        targets = { { node = to.id, input = e.input } }
      elseif to and to.ins then
        targets = to.ins[e.input] or {}
      end
      if source then
        for _, t in ipairs (targets) do
          out_edges[#out_edges + 1] = {
            from = source.node,
            output = source.output,
            to = t.node,
            input = t.input,
          }
        end
      end
    end
    return placed
  end

  place (doc.nodes, doc.edges, '', nil, 0)
  local flat = graph.with (doc, {
    nodes = out_nodes,
    edges = out_edges,
    canvas = false,
    subgraphs = false,
  })
  return flat, expansion
end

return M
