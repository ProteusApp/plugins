-- daw_device: checks the device specs that plugins register, and works with parameter
-- values: defaults, limits, where a value sits along a knob, and how it reads.

local M = {}

local ROLES = { instrument = true, effect = true }
local KINDS = { number = true, choice = true, toggle = true, file = true }
local NODE_TYPES = {
  osc = true,
  noise = true,
  sample = true,
  gain = true,
  filter = true,
  delay = true,
  pan = true,
  compressor = true,
  reverb = true,
  shaper = true,
  lfo = true,
  env = true,
  const = true,
}

---@param value any
---@return any
local function deep (value)
  if type (value) ~= 'table' then
    return value
  end
  local c = {} ---@type table<any, any>
  for k, v in
    pairs (value --[[@as table<any, any>]])
  do
    c[k] = deep (v)
  end
  return c
end

---@param graph any
---@param where string
---@param effect boolean
---@return Daw.Graph?, string?
local function check_graph (graph, where, effect)
  if type (graph) ~= 'table' or type (graph.nodes) ~= 'table' then
    return nil, where .. ' needs a list of nodes'
  end
  local seen = { out = true } ---@type table<string, boolean>
  if effect then
    seen['in'] = true
  end
  local nodes = {} ---@type Daw.PatchNode[]
  for i, node in
    ipairs (graph.nodes --[[@as table<string, any>[] ]])
  do
    if type (node) ~= 'table' then
      return nil, where .. ': node ' .. i .. ' is not a table'
    end
    local id, kind = node.id, node.type
    if type (id) ~= 'string' or not id:match ('^[%a_][%w_]*$') then
      return nil,
        where .. ': node ' .. i .. ' needs an id made of letters, digits and _'
    end
    if id == 'in' or id == 'out' or seen[id] then
      return nil, where .. ': the node id ' .. id .. ' is taken'
    end
    if not NODE_TYPES[kind] then
      return nil,
        where .. ': node ' .. id .. ' has an unknown type ' .. tostring (kind)
    end
    seen[id] = true
    nodes[#nodes + 1] = deep (node)
  end
  local wires = {} ---@type string[]
  for _, wire in
    ipairs (graph.connect or {} --[[@as string[] ]])
  do
    local from, to =
      tostring (wire):match ('^%s*([%w_]+)%s*>%s*([%w_]+)[%w_.]*%s*$')
    if not from then
      return nil,
        where .. ': the wire "' .. tostring (wire) .. '" should read "a > b"'
    end
    if not seen[from] or not seen[to] then
      return nil,
        where .. ': the wire "' .. wire .. '" names a node that is not there'
    end
    wires[#wires + 1] = wire
  end
  return { nodes = nodes, connect = wires }, nil
end

---@param p any
---@param i integer
---@return Daw.ParamSpec?, string?
local function check_param (p, i)
  if type (p) ~= 'table' then
    return nil, 'parameter ' .. i .. ' is not a table'
  end
  if type (p.key) ~= 'string' or not p.key:match ('^[%a_][%w_]*$') then
    return nil,
      'parameter ' .. i .. ' needs a key made of letters, digits and _'
  end
  local kind = p.kind or 'number'
  if not KINDS[kind] then
    return nil,
      'parameter ' .. p.key .. ' has an unknown kind ' .. tostring (kind)
  end
  local out = deep (p) --[[@as Daw.ParamSpec]]
  out.kind = kind
  out.label = type (p.label) == 'string' and p.label or p.key
  if kind == 'number' then
    out.min = tonumber (p.min) or 0
    out.max = tonumber (p.max) or 1
    if out.max <= out.min then
      return nil, 'parameter ' .. p.key .. ' needs max above min'
    end
    if out.curve == 'log' and out.min <= 0 then
      return nil, 'parameter ' .. p.key .. ' needs min above 0 for a log curve'
    end
    out.default = M.clamp (out, p.default == nil and out.min or p.default)
  elseif kind == 'choice' then
    if type (p.options) ~= 'table' or #p.options == 0 then
      return nil, 'parameter ' .. p.key .. ' needs options'
    end
    out.default = M.clamp (out, p.default)
  elseif kind == 'toggle' then
    out.default = p.default == true
  else
    out.default = type (p.default) == 'string' and p.default or ''
  end
  return out, nil
end

---@param spec table<string, any>
---@return Daw.DeviceSpec?, string?
function M.check (spec)
  if type (spec) ~= 'table' then
    return nil, 'a device is a table'
  end
  if type (spec.id) ~= 'string' or not spec.id:match ('^[%w][%w._-]*$') then
    return nil, 'a device needs an id such as "my.synth"'
  end
  if not ROLES[spec.role] then
    return nil, spec.id .. ': role must be "instrument" or "effect"'
  end
  local out = {
    id = spec.id,
    name = type (spec.name) == 'string' and spec.name or spec.id,
    role = spec.role,
    description = spec.description,
    icon = spec.icon,
    category = spec.category,
    params = {},
    presets = {},
    patch = {},
  } --[[@as Daw.DeviceSpec]]
  local keys = {} ---@type table<string, boolean>
  for i, p in
    ipairs (spec.params or {} --[[@as table[] ]])
  do
    local param, err = check_param (p, i)
    if not param then
      return nil, spec.id .. ': ' .. tostring (err)
    end
    if keys[param.key] then
      return nil, spec.id .. ': the parameter ' .. param.key .. ' appears twice'
    end
    keys[param.key] = true
    out.params[#out.params + 1] = param
  end
  local patch = spec.patch --[[@as table<string, any>]]
  if type (patch) ~= 'table' then
    return nil, spec.id .. ': a device needs a patch'
  end
  out.patch.poly = tonumber (patch.poly)
      and math.max (1, math.floor (patch.poly))
    or nil
  if spec.role == 'effect' then
    local graph, err = check_graph (patch, spec.id, true)
    if not graph then
      return nil, err
    end
    out.patch.nodes, out.patch.connect = graph.nodes, graph.connect
  elseif type (patch.pads) == 'table' then
    local pads = {} ---@type Daw.Pad[]
    for i, pad in
      ipairs (patch.pads --[[@as table<string, any>[] ]])
    do
      local pitch = type (pad) == 'table' and tonumber (pad.pitch)
      if not pitch then
        return nil, spec.id .. ': pad ' .. i .. ' needs a pitch'
      end
      local graph, err = check_graph (
        pad.voice,
        spec.id .. ' pad ' .. tostring (pad.name or i),
        false
      )
      if not graph then
        return nil, err
      end
      pads[#pads + 1] = {
        pitch = math.floor (pitch),
        name = type (pad.name) == 'string' and pad.name or ('Pad ' .. i),
        choke = type (pad.choke) == 'string' and pad.choke or nil,
        voice = graph,
      }
    end
    if #pads == 0 then
      return nil, spec.id .. ': a kit needs at least one pad'
    end
    out.patch.pads = pads
  else
    local graph, err = check_graph (patch.voice, spec.id .. ' voice', false)
    if not graph then
      return nil, err
    end
    out.patch.voice = graph
  end
  for _, preset in
    ipairs (spec.presets or {} --[[@as table<string, any>[] ]])
  do
    if type (preset) == 'table' and type (preset.name) == 'string' then
      local params = {} ---@type table<string, Daw.Value>
      local given = type (preset.params) == 'table' and preset.params or {}
      for k, v in
        pairs (given --[[@as table<string, any>]])
      do
        local param = M.param (out, k)
        if param then
          params[k] = M.clamp (param, v)
        end
      end
      out.presets[#out.presets + 1] = { name = preset.name, params = params }
    end
  end
  return out, nil
end

---@param spec Daw.DeviceSpec
---@param key string
---@return Daw.ParamSpec?
function M.param (spec, key)
  for _, p in ipairs (spec.params) do
    if p.key == key then
      return p
    end
  end
  return nil
end

---@param spec Daw.DeviceSpec
---@return table<string, Daw.Value>
function M.defaults (spec)
  local out = {} ---@type table<string, Daw.Value>
  for _, p in ipairs (spec.params) do
    out[p.key] = p.default
  end
  return out
end

---@param param Daw.ParamSpec
---@param value any
---@return Daw.Value
function M.clamp (param, value)
  local kind = param.kind or 'number'
  if kind == 'toggle' then
    return value == true or value == 1
  end
  if kind == 'file' then
    return type (value) == 'string' and value or ''
  end
  if kind == 'choice' then
    local options = param.options or {}
    for _, o in ipairs (options) do
      if o == value then
        return o
      end
    end
    return options[1] or ''
  end
  local n = tonumber (value) or tonumber (param.default) or param.min or 0
  local lo, hi = param.min or 0, param.max or 1
  n = math.max (lo, math.min (hi, n))
  if param.step and param.step > 0 then
    n = lo + math.floor ((n - lo) / param.step + 0.5) * param.step
    n = math.max (lo, math.min (hi, n))
  end
  return n
end

---@param spec Daw.DeviceSpec
---@param name? string
---@return Daw.Preset?
function M.preset (spec, name)
  for _, p in ipairs (spec.presets or {}) do
    if p.name == name then
      return p
    end
  end
  return nil
end

---Every parameter of a device on a track: the device's defaults, then the values of the
---preset it loaded, then the values changed on the track.
---@param spec Daw.DeviceSpec
---@param ref Daw.DeviceRef
---@return table<string, Daw.Value>
function M.values (spec, ref)
  local out = M.defaults (spec)
  local preset = M.preset (spec, ref.preset)
  for _, layer in ipairs ({ preset and preset.params or {}, ref.params or {} }) do
    for k, v in pairs (layer) do
      local param = M.param (spec, k)
      if param then
        out[k] = M.clamp (param, v)
      end
    end
  end
  return out
end

---@param spec Daw.DeviceSpec
---@param ref Daw.DeviceRef
---@param key string
---@return Daw.Value
function M.value (spec, ref, key)
  local v = M.values (spec, ref)[key]
  if v == nil then
    return 0
  end
  return v
end

---@param param Daw.ParamSpec
---@param value number
---@return number
function M.to_unit (param, value)
  local lo, hi = param.min or 0, param.max or 1
  local v = math.max (lo, math.min (hi, value))
  if param.curve == 'log' and lo > 0 then
    return math.log (v / lo) / math.log (hi / lo)
  end
  return (v - lo) / (hi - lo)
end

---@param param Daw.ParamSpec
---@param unit number
---@return number
function M.from_unit (param, unit)
  local lo, hi = param.min or 0, param.max or 1
  local u = math.max (0, math.min (1, unit))
  local v ---@type number
  if param.curve == 'log' and lo > 0 then
    v = lo * (hi / lo) ^ u
  else
    v = lo + (hi - lo) * u
  end
  return M.clamp (param, v) --[[@as number]]
end

---@param n number
---@return string
local function trim_number (n)
  if math.abs (n - math.floor (n + 0.5)) < 1e-9 then
    return string.format ('%d', math.floor (n + 0.5))
  end
  return string.format ('%.2f', n)
end

---@param param Daw.ParamSpec
---@param value Daw.Value
---@return string
function M.format (param, value)
  local kind = param.kind or 'number'
  if kind == 'toggle' then
    return value == true and 'On' or 'Off'
  end
  if kind == 'file' then
    local text = tostring (value or '')
    if text == '' then
      return 'No file'
    end
    return text:match ('([^/\\]+)$') or text
  end
  if kind == 'choice' then
    local text = tostring (value)
    return (text:gsub ('^%l', string.upper))
  end
  local n = tonumber (value) or 0
  local unit = param.unit or ''
  if unit == 'Hz' then
    if n >= 1000 then
      return string.format ('%.2f kHz', n / 1000)
    end
    return string.format (n < 100 and '%.1f Hz' or '%.0f Hz', n)
  elseif unit == 'dB' then
    if n <= -60 then
      return '-inf dB'
    end
    return string.format ('%.1f dB', n)
  elseif unit == 's' then
    if n < 1 then
      return string.format ('%.0f ms', n * 1000)
    end
    return string.format ('%.2f s', n)
  elseif unit == '%' then
    return string.format ('%.0f%%', n * 100)
  elseif unit == 'st' or unit == 'ct' then
    local whole = math.floor (n + 0.5)
    return (whole > 0 and '+' or '') .. whole .. ' ' .. unit
  elseif unit == 'x' then
    return string.format ('%.2fx', n)
  elseif unit == ':1' then
    return string.format ('%.1f:1', n)
  elseif unit == 'b' then
    -- Beats as a note length: 0.5 beats is an eighth note, 1.5 a dotted quarter.
    local top, bottom = math.floor (n * 16 + 0.5), 64
    if top <= 0 then
      return '0'
    end
    while top % 2 == 0 and bottom > 1 do
      top, bottom = math.floor (top / 2), math.floor (bottom / 2)
    end
    return string.format ('%d/%d', top, bottom)
  end
  return trim_number (n)
end

---A new device of this kind, with no id yet. A preset is kept by name: its values sit
---between the defaults and whatever the track changes.
---@param spec Daw.DeviceSpec
---@param preset? string
---@return Daw.DeviceRef
function M.ref (spec, preset)
  local found = M.preset (spec, preset)
  return {
    id = '',
    device = spec.id,
    params = {},
    bypass = false,
    preset = found and found.name or nil,
  }
end

return M
