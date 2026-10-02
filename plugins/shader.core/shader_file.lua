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

---The file's text.
---@param doc Shader.Doc
---@return string
function M.save (doc)
  ---@type string[]
  local lines = {
    '{',
    '  "format": ' .. graph.FORMAT .. ',',
    '  "kind": "' .. KIND .. '",',
    '  "name": ' .. quote (doc.name or 'Untitled') .. ',',
  }
  if doc.preview then
    lines[#lines + 1] = '  "preview": ' .. quote (doc.preview) .. ','
  end
  if doc.channels and next (doc.channels) then
    lines[#lines + 1] = '  "channels": ' .. encode (doc.channels) .. ','
  end
  lines[#lines + 1] = '  "nodes": ['
  for i, n in ipairs (doc.nodes) do
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
    lines[#lines + 1] = '    { '
      .. table.concat (parts, ', ')
      .. ' }'
      .. (i < #doc.nodes and ',' or '')
  end
  lines[#lines + 1] = '  ],'
  lines[#lines + 1] = '  "edges": ['
  for i, e in ipairs (doc.edges) do
    lines[#lines + 1] = '    { "from": '
      .. quote (e.from)
      .. ', "output": '
      .. quote (e.output)
      .. ', "to": '
      .. quote (e.to)
      .. ', "input": '
      .. quote (e.input)
      .. ' }'
      .. (i < #doc.edges and ',' or '')
  end
  -- The canvas's frames and reroute points, one to a line, only when there are some.
  local canvas = (graph.set_canvas (doc, doc.canvas) or doc).canvas
  if canvas then
    lines[#lines + 1] = '  ],'
    lines[#lines + 1] = '  "canvas": {'
    lines[#lines + 1] = '    "frames": ['
    for i, f in ipairs (canvas.frames) do
      lines[#lines + 1] = '      '
        .. encode ({
          id = f.id,
          title = f.title,
          x = f.x,
          y = f.y,
          w = f.w,
          h = f.h,
          color = f.color,
        })
        .. (i < #canvas.frames and ',' or '')
    end
    lines[#lines + 1] = '    ],'
    lines[#lines + 1] = '    "routes": ['
    for i, r in ipairs (canvas.routes) do
      lines[#lines + 1] = '      '
        .. encode ({ to = r.to, input = r.input, points = r.points })
        .. (i < #canvas.routes and ',' or '')
    end
    lines[#lines + 1] = '    ]'
    lines[#lines + 1] = '  }'
  else
    lines[#lines + 1] = '  ]'
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
  if type (data.nodes) ~= 'table' then
    return nil, 'The file has no list of nodes.'
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
  local seen = {} ---@type table<string, boolean>
  local node_list = data.nodes ---@type table<string, any>[]
  for i, n in ipairs (node_list) do
    if
      type (n) ~= 'table'
      or type (n.id) ~= 'string'
      or not n.id:match ('^[%a_][%w_]*$')
      or type (n.type) ~= 'string'
    then
      return nil, 'Node ' .. i .. ' needs an id and a type.'
    end
    if seen[n.id] then
      return nil, 'Two nodes are called ' .. n.id .. '.'
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
    doc.nodes[#doc.nodes + 1] = {
      id = n.id,
      type = n.type,
      x = tonumber (n.x) or 0,
      y = tonumber (n.y) or 0,
      inputs = inputs,
      settings = settings,
    }
  end
  local taken = {} ---@type table<string, boolean>
  local edge_list = type (data.edges) == 'table' and data.edges or {} ---@type table<string, any>[]
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
        doc.edges[#doc.edges + 1] =
          { from = e.from, output = e.output, to = e.to, input = e.input }
      end
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
