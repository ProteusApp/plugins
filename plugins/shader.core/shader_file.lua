-- The *.shader.json file. It is written the same way every time, one node and one wire per
-- line, so a change reads well in a diff. Loading checks the shape of everything, since the
-- file may have been edited by hand.

local graph = require ('shader_graph') --[[@as Shader.GraphModule]]
local passes = require ('shader_passes') --[[@as Shader.PassesModule]]

local KIND = 'proteus-shader'

local M = {}

M.KIND = KIND
M.EXTENSION = '.shader.json'

-- Writing --------------------------------------------------------------------------------

---@param s string
---@return string
local function quote (s)
  return '"'
    .. s:gsub ('[%c"\\]', function (c)
      if c == '"' then
        return '\\"'
      elseif c == '\\' then
        return '\\\\'
      elseif c == '\n' then
        return '\\n'
      elseif c == '\t' then
        return '\\t'
      elseif c == '\r' then
        return '\\r'
      end
      return string.format ('\\u%04x', c:byte ())
    end)
    .. '"'
end

---@param n number
---@return string
local function number (n)
  if n ~= n or n == math.huge or n == -math.huge then
    return '0'
  end
  if n == math.floor (n) and math.abs (n) < 1e15 then
    return string.format ('%d', n)
  end
  for digits = 6, 17 do
    local text = string.format ('%.' .. digits .. 'g', n)
    if tonumber (text) == n then
      return text
    end
  end
  return string.format ('%.17g', n)
end

local ARRAY = { __jsontype = 'array' }

---Marks a table to be written as a JSON array even when it is empty.
---@generic T: table
---@param t T
---@return T
function M.array (t)
  return setmetatable (t, ARRAY)
end

---@param t table<any, any>
---@return boolean
local function is_list (t)
  if getmetatable (t) == ARRAY then
    return true
  end
  local count = 0
  for _ in pairs (t) do
    count = count + 1
  end
  return count > 0 and count == #t
end

---@param value any
---@return string
local function encode (value)
  local kind = type (value)
  if kind == 'string' then
    return quote (value)
  elseif kind == 'number' then
    return number (value)
  elseif kind == 'boolean' then
    return value and 'true' or 'false'
  elseif kind == 'table' then
    ---@cast value table<any, any>
    if is_list (value) then
      local parts = {} ---@type string[]
      for i, v in ipairs (value) do
        parts[i] = encode (v)
      end
      if #parts == 0 then
        return '[]'
      end
      return '[' .. table.concat (parts, ', ') .. ']'
    end
    local keys = {} ---@type string[]
    for k in pairs (value) do
      keys[#keys + 1] = tostring (k)
    end
    table.sort (keys)
    local parts = {} ---@type string[]
    for _, k in ipairs (keys) do
      parts[#parts + 1] = quote (k) .. ': ' .. encode (value[k])
    end
    if #parts == 0 then
      return '{}'
    end
    return '{ ' .. table.concat (parts, ', ') .. ' }'
  end
  return 'null'
end

M.encode = encode

---One node as a line of the file.
---@param n Shader.Node
---@return string
local function node_line (n)
  local parts = {
    '"id": ' .. quote (n.id),
    '"type": ' .. quote (n.type),
    '"x": ' .. number (n.x or 0),
    '"y": ' .. number (n.y or 0),
  }
  if next (n.inputs or {}) then
    parts[#parts + 1] = '"inputs": ' .. encode (n.inputs)
  end
  if next (n.settings or {}) then
    parts[#parts + 1] = '"settings": ' .. encode (n.settings)
  end
  return '{ ' .. table.concat (parts, ', ') .. ' }'
end

---One wire as a line of the file.
---@param e Shader.Edge
---@return string
local function edge_line (e)
  return '{ "from": '
    .. quote (e.from)
    .. ', "output": '
    .. quote (e.output)
    .. ', "to": '
    .. quote (e.to)
    .. ', "input": '
    .. quote (e.input)
    .. ' }'
end

---Lines for a list, one item to a line, with commas between.
---@param into string[]
---@param indent string
---@param items string[]
local function list_lines (into, indent, items)
  for i, item in ipairs (items) do
    into[#into + 1] = indent .. item .. (i < #items and ',' or '')
  end
end

---The file's text.
---@param doc Shader.Doc
---@return string
function M.save (doc)
  local subgraphs = doc.subgraphs and next (doc.subgraphs) and doc.subgraphs
  ---@type string[]
  local lines = {
    '{',
    -- Format 2 only when a newer builder is needed to read the file.
    '  "format": ' .. (subgraphs and 2 or 1) .. ',',
    '  "kind": "' .. KIND .. '",',
    '  "name": ' .. quote (doc.name or 'Untitled') .. ',',
  }
  if doc.preview then
    lines[#lines + 1] = '  "preview": ' .. quote (doc.preview) .. ','
  end
  if doc.channels and next (doc.channels) then
    lines[#lines + 1] = '  "channels": ' .. encode (doc.channels) .. ','
  end
  -- Each part after the nodes is a list of lines. Commas go between the parts.
  local parts = {} ---@type string[][]
  local node_part = { '  "nodes": [' } ---@type string[]
  local node_items = {} ---@type string[]
  for i, n in ipairs (doc.nodes) do
    node_items[i] = node_line (n)
  end
  list_lines (node_part, '    ', node_items)
  node_part[#node_part + 1] = '  ]'
  parts[#parts + 1] = node_part
  local edge_part = { '  "edges": [' } ---@type string[]
  local edge_items = {} ---@type string[]
  for i, e in ipairs (doc.edges) do
    edge_items[i] = edge_line (e)
  end
  list_lines (edge_part, '    ', edge_items)
  edge_part[#edge_part + 1] = '  ]'
  parts[#parts + 1] = edge_part
  -- The canvas's frames and reroute points, one to a line, only when there are some.
  local canvas = (graph.set_canvas (doc, doc.canvas) or doc).canvas
  if canvas then
    local canvas_part = { '  "canvas": {', '    "frames": [' } ---@type string[]
    local frame_items = {} ---@type string[]
    for i, f in ipairs (canvas.frames) do
      frame_items[i] = encode ({
        id = f.id,
        title = f.title,
        x = f.x,
        y = f.y,
        w = f.w,
        h = f.h,
        color = f.color,
      })
    end
    list_lines (canvas_part, '      ', frame_items)
    canvas_part[#canvas_part + 1] = '    ],'
    canvas_part[#canvas_part + 1] = '    "routes": ['
    local route_items = {} ---@type string[]
    for i, r in ipairs (canvas.routes) do
      route_items[i] =
        encode ({ to = r.to, input = r.input, points = r.points })
    end
    list_lines (canvas_part, '      ', route_items)
    canvas_part[#canvas_part + 1] = '    ]'
    canvas_part[#canvas_part + 1] = '  }'
    parts[#parts + 1] = canvas_part
  end
  -- The groups made nodes come from, each with its own nodes and wires, one to a line.
  if subgraphs then
    local sub_part = { '  "subgraphs": {' } ---@type string[]
    local ids = {} ---@type string[]
    for sid in pairs (subgraphs) do
      ids[#ids + 1] = sid
    end
    table.sort (ids)
    for k, sid in ipairs (ids) do
      local sg = subgraphs[sid]
      sub_part[#sub_part + 1] = '    ' .. quote (sid) .. ': {'
      sub_part[#sub_part + 1] = '      "name": ' .. quote (sg.name) .. ','
      sub_part[#sub_part + 1] = '      "inputs": ['
      local in_items = {} ---@type string[]
      for i, p in ipairs (sg.inputs) do
        local targets = M.array ({}) ---@type table[]
        for j, t in ipairs (p.targets) do
          targets[j] = { node = t.node, input = t.input }
        end
        in_items[i] = encode ({
          key = p.key,
          label = p.label,
          type = p.type,
          default = p.default,
          builtin = p.builtin,
          color = p.color or nil,
          targets = targets,
        })
      end
      list_lines (sub_part, '        ', in_items)
      sub_part[#sub_part + 1] = '      ],'
      sub_part[#sub_part + 1] = '      "outputs": ['
      local out_items = {} ---@type string[]
      for i, p in ipairs (sg.outputs) do
        out_items[i] = encode ({
          key = p.key,
          label = p.label,
          type = p.type,
          node = p.node,
          output = p.output,
        })
      end
      list_lines (sub_part, '        ', out_items)
      sub_part[#sub_part + 1] = '      ],'
      sub_part[#sub_part + 1] = '      "nodes": ['
      local inner_nodes = {} ---@type string[]
      for i, n in ipairs (sg.nodes) do
        inner_nodes[i] = node_line (n)
      end
      list_lines (sub_part, '        ', inner_nodes)
      sub_part[#sub_part + 1] = '      ],'
      sub_part[#sub_part + 1] = '      "edges": ['
      local inner_edges = {} ---@type string[]
      for i, e in ipairs (sg.edges) do
        inner_edges[i] = edge_line (e)
      end
      list_lines (sub_part, '        ', inner_edges)
      sub_part[#sub_part + 1] = '      ]'
      sub_part[#sub_part + 1] = '    }' .. (k < #ids and ',' or '')
    end
    sub_part[#sub_part + 1] = '  }'
    parts[#parts + 1] = sub_part
  end
  for i, part in ipairs (parts) do
    for j, line in ipairs (part) do
      local last = j == #part and i < #parts
      lines[#lines + 1] = line .. (last and ',' or '')
    end
  end
  lines[#lines + 1] = '}'
  return table.concat (lines, '\n') .. '\n'
end

-- Reading --------------------------------------------------------------------------------

---@class Shader.JsonReader
---@field text string
---@field pos integer

---@param r Shader.JsonReader
local function skip (r)
  r.pos = r.text:find ('[^ \t\r\n]', r.pos) or (#r.text + 1)
end

---@param r Shader.JsonReader
---@param message string
local function fail (r, message)
  error (message .. ' at character ' .. r.pos, 0)
end

local read_value ---@type fun(r: Shader.JsonReader, depth: integer): any

---@param r Shader.JsonReader
---@return string
local function read_string (r)
  local out = {} ---@type string[]
  local i = r.pos + 1
  while true do
    local c = r.text:sub (i, i)
    if c == '' then
      fail (r, 'A string never ends')
    elseif c == '"' then
      r.pos = i + 1
      return table.concat (out)
    elseif c == '\\' then
      local e = r.text:sub (i + 1, i + 1)
      local simple = { n = '\n', t = '\t', r = '\r', b = '\b', f = '\f' }
      if simple[e] then
        out[#out + 1] = simple[e]
        i = i + 2
      elseif e == 'u' then
        local code = tonumber (r.text:sub (i + 2, i + 5), 16)
        if not code then
          fail (r, 'A \\u escape is broken')
        end
        out[#out + 1] = utf8.char (code --[[@as integer]])
        i = i + 6
      else
        out[#out + 1] = e
        i = i + 2
      end
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
end

---@param r Shader.JsonReader
---@param depth integer
---@return any
read_value = function (r, depth)
  if depth > 64 then
    fail (r, 'The file nests too deep')
  end
  skip (r)
  local c = r.text:sub (r.pos, r.pos)
  if c == '{' then
    local out = {} ---@type table<string, any>
    r.pos = r.pos + 1
    skip (r)
    if r.text:sub (r.pos, r.pos) == '}' then
      r.pos = r.pos + 1
      return out
    end
    while true do
      skip (r)
      if r.text:sub (r.pos, r.pos) ~= '"' then
        fail (r, 'Expected a name in quotes')
      end
      local key = read_string (r)
      skip (r)
      if r.text:sub (r.pos, r.pos) ~= ':' then
        fail (r, 'Expected :')
      end
      r.pos = r.pos + 1
      out[key] = read_value (r, depth + 1)
      skip (r)
      local d = r.text:sub (r.pos, r.pos)
      r.pos = r.pos + 1
      if d == '}' then
        return out
      elseif d ~= ',' then
        fail (r, 'Expected , or }')
      end
    end
  elseif c == '[' then
    local out = {} ---@type any[]
    r.pos = r.pos + 1
    skip (r)
    if r.text:sub (r.pos, r.pos) == ']' then
      r.pos = r.pos + 1
      return out
    end
    while true do
      out[#out + 1] = read_value (r, depth + 1)
      skip (r)
      local d = r.text:sub (r.pos, r.pos)
      r.pos = r.pos + 1
      if d == ']' then
        return out
      elseif d ~= ',' then
        fail (r, 'Expected , or ]')
      end
    end
  elseif c == '"' then
    return read_string (r)
  elseif r.text:sub (r.pos, r.pos + 3) == 'true' then
    r.pos = r.pos + 4
    return true
  elseif r.text:sub (r.pos, r.pos + 4) == 'false' then
    r.pos = r.pos + 5
    return false
  elseif r.text:sub (r.pos, r.pos + 3) == 'null' then
    r.pos = r.pos + 4
    return nil
  end
  local num = r.text:match ('^-?%d+%.?%d*[eE]?[-+]?%d*', r.pos)
  if num and num ~= '' and tonumber (num) then
    r.pos = r.pos + #num
    return tonumber (num)
  end
  fail (r, 'Unexpected text')
end

---Reads JSON text.
---@param text string
---@return any value, string? error
function M.decode (text)
  local r = { text = text, pos = 1 } ---@type Shader.JsonReader
  local ok, value = pcall (read_value, r, 0)
  if not ok then
    return nil, tostring (value)
  end
  skip (r)
  if r.pos <= #text then
    return nil, 'There is more after the end at character ' .. r.pos
  end
  return value
end

---@param list any
---@return number[]?
local function numbers (list)
  if type (list) ~= 'table' then
    return nil
  end
  local out = {} ---@type number[]
  for i = 1, math.min (#list, 4) do
    if type (list[i]) ~= 'number' then
      return nil
    end
    out[i] = list[i]
  end
  return #out > 0 and out or nil
end

---@param value any
---@return any
local function clean_setting (value)
  local kind = type (value)
  if kind == 'string' or kind == 'number' or kind == 'boolean' then
    return value
  end
  return numbers (value)
end

---Reads a list of nodes. Nil and why when one does not read.
---@param raw any
---@return Shader.Node[]? nodes
---@return string? error
---@return table<string, boolean> ids
local function read_nodes (raw)
  local seen = {} ---@type table<string, boolean>
  local out = {} ---@type Shader.Node[]
  if type (raw) ~= 'table' then
    return nil, 'The file has no list of nodes.', seen
  end
  local node_list = raw ---@type table<string, any>[]
  for i, n in ipairs (node_list) do
    if
      type (n) ~= 'table'
      or type (n.id) ~= 'string'
      or not n.id:match ('^[%a_][%w_]*$')
      or type (n.type) ~= 'string'
    then
      return nil, 'Node ' .. i .. ' needs an id and a type.', seen
    end
    if seen[n.id] then
      return nil, 'Two nodes are called ' .. n.id .. '.', seen
    end
    seen[n.id] = true
    local inputs, settings = {}, {} ---@type table<string, number[]>, table<string, any>
    if type (n.inputs) == 'table' then
      for k, v in
        pairs (n.inputs --[[@as table<string, any>]])
      do
        inputs[tostring (k)] = numbers (v)
      end
    end
    if type (n.settings) == 'table' then
      for k, v in
        pairs (n.settings --[[@as table<string, any>]])
      do
        settings[tostring (k)] = clean_setting (v)
      end
    end
    out[#out + 1] = {
      id = n.id,
      type = n.type,
      x = tonumber (n.x) or 0,
      y = tonumber (n.y) or 0,
      inputs = inputs,
      settings = settings,
    }
  end
  return out, nil, seen
end

---Reads a list of wires between the nodes `seen` names, one at most into each input.
---@param raw any
---@param seen table<string, boolean>
---@return Shader.Edge[]
local function read_edges (raw, seen)
  local out = {} ---@type Shader.Edge[]
  local taken = {} ---@type table<string, boolean>
  local edge_list = type (raw) == 'table' and raw or {} ---@type table<string, any>[]
  for _, e in ipairs (edge_list) do
    if
      type (e) == 'table'
      and seen[e.from]
      and seen[e.to]
      and type (e.output) == 'string'
      and type (e.input) == 'string'
    then
      local key = tostring (e.to) .. '.' .. tostring (e.input)
      if not taken[key] then
        taken[key] = true
        out[#out + 1] =
          { from = e.from, output = e.output, to = e.to, input = e.input }
      end
    end
  end
  return out
end

local PORT_TYPES = {
  float = true,
  vec2 = true,
  vec3 = true,
  vec4 = true,
  gen = true,
  any = true,
}
local BUILTINS = { uv = true, suv = true, frag = true }

---Reads the group a made node comes from, or nil when it does not read.
---@param raw any
---@return Shader.Subgraph?
local function read_subgraph (raw)
  if type (raw) ~= 'table' then
    return nil
  end
  local inner, _, seen = read_nodes (raw.nodes)
  if not inner then
    return nil
  end
  ---@type Shader.Subgraph
  local sg = {
    name = type (raw.name) == 'string' and raw.name or 'Made node',
    nodes = inner,
    edges = read_edges (raw.edges, seen),
    inputs = {},
    outputs = {},
  }
  local keys = {} ---@type table<string, boolean>
  ---@param p any
  ---@return boolean
  local function port_ok (p)
    return type (p) == 'table'
      and type (p.key) == 'string'
      and p.key:match ('^[%w_]+$') ~= nil
      and not keys[p.key]
      and PORT_TYPES[p.type] == true
  end
  local in_list = type (raw.inputs) == 'table' and raw.inputs or {} ---@type any[]
  for _, p in ipairs (in_list) do
    if not port_ok (p) or type (p.targets) ~= 'table' then
      return nil
    end
    keys[p.key] = true
    local targets = {} ---@type { node: string, input: string }[]
    for _, t in
      ipairs (p.targets --[[@as any[] ]])
    do
      if
        type (t) ~= 'table'
        or not seen[t.node]
        or type (t.input) ~= 'string'
      then
        return nil
      end
      targets[#targets + 1] = { node = t.node, input = t.input }
    end
    sg.inputs[#sg.inputs + 1] = {
      key = p.key,
      label = type (p.label) == 'string' and p.label or p.key,
      type = p.type,
      default = numbers (p.default),
      builtin = BUILTINS[p.builtin] and p.builtin or nil,
      color = p.color == true or nil,
      targets = targets,
    }
  end
  local out_list = type (raw.outputs) == 'table' and raw.outputs or {} ---@type any[]
  for _, p in ipairs (out_list) do
    if not port_ok (p) or not seen[p.node] or type (p.output) ~= 'string' then
      return nil
    end
    keys[p.key] = true
    sg.outputs[#sg.outputs + 1] = {
      key = p.key,
      label = type (p.label) == 'string' and p.label or p.key,
      type = p.type,
      node = p.node,
      output = p.output,
    }
  end
  return sg
end

---Reads a file's text into a document.
---@param text string
---@return Shader.Doc? doc, string? error
function M.load (text)
  local decoded, err = M.decode (text)
  local data = decoded ---@type table<string, any>
  if not data then
    return nil, 'The file is not valid JSON: ' .. tostring (err)
  end
  if type (data) ~= 'table' then
    return nil, 'The file does not hold a shader graph.'
  end
  if data.kind ~= nil and data.kind ~= KIND then
    return nil, 'The file does not hold a shader graph.'
  end
  local format = tonumber (data.format) or 1
  if format > graph.FORMAT then
    return nil, 'The file comes from a newer version of the shader builder.'
  end
  ---@type Shader.Doc
  local doc = {
    format = graph.FORMAT,
    name = type (data.name) == 'string' and data.name or 'Untitled',
    nodes = {},
    edges = {},
  }
  if data.preview == 'glsl' or data.preview == 'wgsl' then
    doc.preview = data.preview
  end
  -- What each channel shows. One that does not read is left to the Preview's default.
  if type (data.channels) == 'table' then
    for i = 0, passes.COUNT - 1 do
      local src = passes.clean_source (data.channels[tostring (i)])
      if src then
        doc.channels = doc.channels or {}
        doc.channels[tostring (i)] = src
      end
    end
  end
  local list, why, seen = read_nodes (data.nodes)
  if not list then
    return nil, why
  end
  doc.nodes = list
  doc.edges = read_edges (data.edges, seen)
  -- Groups that do not read are left out, and the made nodes that use one show as missing.
  if type (data.subgraphs) == 'table' then
    local subs = {} ---@type table<string, Shader.Subgraph>
    for sid, raw in
      pairs (data.subgraphs --[[@as table<string, any>]])
    do
      local sg = nil ---@type Shader.Subgraph?
      if type (sid) == 'string' and sid:match ('^[%w_]+$') then
        sg = read_subgraph (raw)
      end
      if sg then
        subs[sid] = sg
      end
    end
    if next (subs) then
      doc.subgraphs = subs
      doc.subgraphs = graph.kept_subgraphs (doc, doc.nodes) or nil
    end
  end
  -- Frames and reroute points that do not read leave the canvas bare, rather than losing the
  -- graph.
  if type (data.canvas) == 'table' then
    doc = graph.set_canvas (doc, data.canvas) or doc
  end
  return doc
end

return M
