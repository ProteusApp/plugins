-- Pure operations on a shader graph document. Each returns a new document, or nil and a
-- refusal, and never changes the one it was given.

local nodes = require ('shader_nodes') --[[@as Shader.NodesModule]]

local FORMAT = 1

local M = {}

M.FORMAT = FORMAT

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
  local out = copy (doc)
  local id = M.next_id (doc)
  out.nodes[#out.nodes + 1] = {
    id = id,
    type = type_id,
    x = math.floor (x + 0.5),
    y = math.floor (y + 0.5),
    inputs = {},
    settings = {},
  }
  return out, id
end

---@param doc Shader.Doc
---@param ids string[]
---@return Shader.Doc?, string? refusal
function M.remove_nodes (doc, ids)
  local gone = {} ---@type table<string, boolean>
  for _, id in ipairs (ids) do
    gone[id] = true
  end
  local out = copy (doc)
  local kept, edges = {}, {} ---@type Shader.Node[], Shader.Edge[]
  for _, n in ipairs (out.nodes) do
    if not gone[n.id] then
      kept[#kept + 1] = n
    end
  end
  if #kept == #out.nodes then
    return nil, 'Nothing to remove.'
  end
  for _, e in ipairs (out.edges) do
    if not gone[e.from] and not gone[e.to] then
      edges[#edges + 1] = e
    end
  end
  out.nodes, out.edges = kept, edges
  return out
end

---@param doc Shader.Doc
---@param moves table<string, { x: number, y: number }>
---@return Shader.Doc
function M.move (doc, moves)
  local out = copy (doc)
  for _, n in ipairs (out.nodes) do
    local p = moves[n.id]
    if p then
      n.x, n.y = math.floor (p.x + 0.5), math.floor (p.y + 0.5)
    end
  end
  return out
end

---True when `from` can be reached by following wires upstream from `start`.
---@param doc Shader.Doc
---@param start string
---@param target string
---@return boolean
local function upstream (doc, start, target)
  local seen = {} ---@type table<string, boolean>
  local stack = { start }
  while #stack > 0 do
    local id = table.remove (stack)
    if id == target then
      return true
    end
    if not seen[id] then
      seen[id] = true
      for _, e in ipairs (doc.edges) do
        if e.to == id then
          stack[#stack + 1] = e.from
        end
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
  local out = copy (doc)
  local _, i = M.edge_into (out, to, input)
  local edge = { from = from, output = output, to = to, input = input }
  if i then
    out.edges[i] = edge
  else
    out.edges[#out.edges + 1] = edge
  end
  return out
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
  local out = copy (doc)
  table.remove (out.edges, i)
  return out
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
  local out = copy (doc)
  local target = M.node (out, id) --[[@as Shader.Node]]
  target.inputs[key] = values and copy (values) or nil
  return out
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
  local out = copy (doc)
  local target = M.node (out, id) --[[@as Shader.Node]]
  target.settings[key] = copy (value)
  return out
end

---Copies nodes, with the wires between them, a little down and to the right.
---@param doc Shader.Doc
---@param ids string[]
---@return Shader.Doc?, string[] new_ids_or_refusal
function M.duplicate (doc, ids)
  local out = copy (doc)
  local map = {} ---@type table<string, string>
  local fresh = {} ---@type string[]
  for _, id in ipairs (ids) do
    local n = M.node (doc, id)
    local def = n and nodes.get (n.type)
    if n and def and not def.unique then
      local nid = M.next_id (out)
      local c = copy (n)
      c.id, c.x, c.y = nid, n.x + 40, n.y + 40
      out.nodes[#out.nodes + 1] = c
      map[id] = nid
      fresh[#fresh + 1] = nid
    end
  end
  if #fresh == 0 then
    return nil, { 'Nothing to duplicate.' }
  end
  for _, e in ipairs (doc.edges) do
    if map[e.from] and map[e.to] then
      out.edges[#out.edges + 1] = {
        from = map[e.from],
        output = e.output,
        to = map[e.to],
        input = e.input,
      }
    end
  end
  return out, fresh
end

---@param doc Shader.Doc
---@param name string
---@return Shader.Doc
function M.rename (doc, name)
  local out = copy (doc)
  out.name = name
  return out
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

return M
