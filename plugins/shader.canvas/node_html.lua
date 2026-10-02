-- What a node shows, as an HTML string, and what it shows it from. All of it is pure: the
-- catalog, the types, the escape function and the number format come in through `new`, so
-- the tests reach it without the app.
--
-- Every element a press or a field needs to tell apart carries a `data-item`, such as
-- `n3|head` or `n3|num|color|2`. Node ids are plain names, so `|` never appears inside one.

---@class ShaderCanvas.HtmlDeps
---@field catalog Shader.NodesModule
---@field types Shader.TypesModule
---@field esc fun(text: string): string
---@field format Shader.FormatModule

---@class ShaderCanvas.Html
---@field node_html fun(n: Shader.Node, def: Shader.NodeDef, info: ShaderCanvas.NodeInfo): string, string
---@field missing_html fun(n: Shader.Node): string
---@field info_of fun(n: Shader.Node, result: Shader.CompileResult?, linked_map: table<string, table<string, boolean>>, used_map: table<string, table<string, boolean>>, errors: table<string, string>, def?: Shader.NodeDef): ShaderCanvas.NodeInfo
---@field signature fun(n: Shader.Node, info: ShaderCanvas.NodeInfo?): string
---@field rows fun(def: Shader.NodeDef, n: Shader.Node): integer

local M = {}

-- What an unwired input with a builtin reads, as its row shows it.
---@type table<string, string>
local BUILTIN_LABELS = { uv = 'uv', suv = 'square uv', frag = 'pixel' }

---@type table<string, string>
M.TYPE_COLORS = {
  float = '#a1a1aa',
  vec2 = '#34d399',
  vec3 = '#fbbf24',
  vec4 = '#f472b6',
}

---The parts of a `data-item`, split at each `|`.
---@param text string
---@return string[]
function M.split (text)
  local out = {} ---@type string[]
  for part in (text .. '|'):gmatch ('([^|]*)|') do
    out[#out + 1] = part
  end
  return out
end

---A short text for a setting or input value, for a signature.
---@param v any
---@return string
local function text_of (v)
  if type (v) ~= 'table' then
    return tostring (v)
  end
  local keys = {} ---@type string[]
  for k in
    pairs (v --[[@as table<any, any>]])
  do
    keys[#keys + 1] = tostring (k)
  end
  table.sort (keys)
  local parts = {} ---@type string[]
  for _, k in ipairs (keys) do
    local item = v[k] or v[tonumber (k)]
    parts[#parts + 1] = k .. '=' .. text_of (item)
  end
  return '{' .. table.concat (parts, ',') .. '}'
end

---@param map table<string, boolean>
---@return string
local function keys_of (map)
  local keys = {} ---@type string[]
  for k, on in pairs (map) do
    if on then
      keys[#keys + 1] = k
    end
  end
  table.sort (keys)
  return table.concat (keys, ',')
end

---@param deps ShaderCanvas.HtmlDeps
---@return ShaderCanvas.Html
function M.new (deps)
  local catalog, types, esc = deps.catalog, deps.types, deps.esc
  local fmt, to_hex = deps.format.fmt, deps.format.to_hex
  -- The part of each signature that comes from the node itself, kept while the node is the
  -- same table. Graph operations share the nodes they did not change.
  local node_parts = setmetatable ({}, { __mode = 'k' }) ---@type table<Shader.Node, string>

  ---The fields that edit the numbers of an unwired input.
  ---@param n Shader.Node
  ---@param port Shader.PortDef
  ---@param t Shader.Type
  ---@return string
  local function input_fields (n, port, t)
    local values = n.inputs[port.key] or port.default
    if port.color and t == 'vec3' then
      return '<input type="color" class="sg-color" data-item="'
        .. n.id
        .. '|color|'
        .. port.key
        .. '" value="'
        .. to_hex (values)
        .. '">'
    end
    local parts = {} ---@type string[]
    for i = 1, types.dim (t) do
      local v = tonumber (values[i] or values[#values]) or 0
      parts[#parts + 1] = '<input class="sg-num" spellcheck="false" data-item="'
        .. n.id
        .. '|num|'
        .. port.key
        .. '|'
        .. i
        .. '" value="'
        .. fmt (v)
        .. '">'
    end
    return table.concat (parts)
  end

  ---@param n Shader.Node
  ---@param def Shader.NodeDef
  ---@param s Shader.SettingDef
  ---@param value any
  ---@return string
  local function setting_field (n, def, s, value)
    local item = n.id .. '|set|' .. s.key
    if s.kind == 'select' then
      local opts = {} ---@type string[]
      for _, o in ipairs (s.options or {}) do
        opts[#opts + 1] = '<option value="'
          .. esc (o)
          .. '"'
          .. (o == value and ' selected' or '')
          .. '>'
          .. esc (o)
          .. '</option>'
      end
      return '<select class="sg-select" data-item="'
        .. item
        .. '">'
        .. table.concat (opts)
        .. '</select>'
    elseif s.kind == 'color' then
      return '<input type="color" class="sg-color" data-item="'
        .. n.id
        .. '|setcolor|'
        .. s.key
        .. '" value="'
        .. to_hex (value or {})
        .. '">'
    elseif s.kind == 'vector' then
      local size = s.size or 4
      if n.type == 'parameter' then
        local kind = catalog.setting (def, n.settings, 'kind')
        if kind == 'color' then
          return '<input type="color" class="sg-color" data-item="'
            .. n.id
            .. '|setcolor|'
            .. s.key
            .. '" value="'
            .. to_hex (value or {})
            .. '">'
        end
        size = types.is_type (kind) and types.dim (kind) or 1
      end
      local parts = {} ---@type string[]
      local list = type (value) == 'table' and value or {}
      for i = 1, size do
        parts[#parts + 1] = '<input class="sg-num" spellcheck="false" data-item="'
          .. item
          .. '|'
          .. i
          .. '" value="'
          .. fmt (tonumber (list[i]) or 0)
          .. '">'
      end
      return table.concat (parts)
    elseif s.kind == 'number' or s.kind == 'int' then
      return '<input class="sg-num" spellcheck="false" data-item="'
        .. item
        .. '" value="'
        .. fmt (tonumber (value) or 0)
        .. '">'
    end
    return '<input class="sg-text" spellcheck="false" data-item="'
      .. item
      .. '" value="'
      .. esc (tostring (value or ''))
      .. '">'
  end

  ---True when a node shows the row for a setting.
  ---@param n Shader.Node
  ---@param s Shader.SettingDef
  ---@param settings table<string, any>
  ---@return boolean
  local function shows (n, s, settings)
    if n.type == 'parameter' and (s.key == 'min' or s.key == 'max') then
      return settings.kind ~= 'color'
    end
    return true
  end

  ---@type ShaderCanvas.Html
  local html = {
    node_html = function (n, def, info)
      local cat = catalog.category (def.category)
      ---@type string[]
      local parts = {
        '<div class="sg-head" data-item="',
        n.id,
        '|head" title="',
        esc (def.description),
        '"><span class="sg-title">',
        esc (def.title),
        '</span>',
      }
      if info.gen then
        parts[#parts + 1] = '<span class="sg-kind">' .. info.gen .. '</span>'
      end
      parts[#parts + 1] = '</div>'
      for _, o in ipairs (catalog.visible_outputs (def)) do
        local t = info.outs[o.key] or 'float'
        parts[#parts + 1] = '<div class="sg-row out" data-item="'
          .. n.id
          .. '|out|'
          .. o.key
          .. '"><span class="sg-t">'
          .. t
          .. '</span><span class="sg-label">'
          .. esc (o.label ~= '' and o.label or 'out')
          .. '</span><span class="sg-port out'
          .. (info.used[o.key] and ' linked' or '')
          .. '" style="background:'
          .. (M.TYPE_COLORS[t] or M.TYPE_COLORS.float)
          .. '" data-item="'
          .. n.id
          .. '|pout|'
          .. o.key
          .. '"></span></div>'
      end
      for _, port in ipairs (def.inputs) do
        local t = info.ins[port.key] or 'float' ---@type string
        local linked = info.linked[port.key]
        local fill ---@type string
        if linked then
          fill = '<span class="sg-t">' .. t .. '</span>'
        elseif port.builtin then
          local label = BUILTIN_LABELS[port.builtin] or 'uv' ---@type string
          fill = '<span class="sg-builtin">' .. label .. '</span>'
        else
          fill = input_fields (n, port, t)
        end
        parts[#parts + 1] = '<div class="sg-row in" data-item="'
          .. n.id
          .. '|in|'
          .. port.key
          .. '"><span class="sg-port in'
          .. (linked and ' linked' or '')
          .. '" style="background:'
          .. (M.TYPE_COLORS[t] or M.TYPE_COLORS.float)
          .. '" data-item="'
          .. n.id
          .. '|pin|'
          .. port.key
          .. '"></span><span class="sg-label">'
          .. esc (port.label)
          .. '</span><span class="sg-fill">'
          .. fill
          .. '</span></div>'
      end
      local settings = catalog.settings_of (def, n.settings)
      for _, s in ipairs (def.settings) do
        if shows (n, s, settings) then
          parts[#parts + 1] = '<div class="sg-row set"><span class="sg-label">'
            .. esc (s.label)
            .. '</span><span class="sg-fill">'
            .. setting_field (n, def, s, settings[s.key])
            .. '</span></div>'
        end
      end
      if info.error then
        parts[#parts + 1] = '<div class="sg-row message">'
          .. esc (info.error)
          .. '</div>'
      end
      return table.concat (parts), cat and cat.color or '#888'
    end,

    missing_html = function (n)
      return '<div class="sg-head" data-item="'
        .. n.id
        .. '|head"><span class="sg-title">'
        .. esc (n.type)
        .. '</span></div><div class="sg-row message">There is no node called '
        .. esc (n.type)
        .. '.</div>'
    end,

    info_of = function (n, result, linked_map, used_map, errors, node_def)
      -- A made node's def comes from its document, so the caller gives it.
      local def = node_def or catalog.get (n.type)
      local ins = result and result.types[n.id] or {} ---@type table<string, Shader.Type>
      local outs = result and result.out_types[n.id] or {} ---@type table<string, Shader.Type>
      ---@type ShaderCanvas.NodeInfo
      local info = {
        ins = {},
        outs = {},
        linked = linked_map[n.id] or {},
        used = used_map[n.id] or {},
        error = errors[n.id],
      }
      if def then
        local gen_seen = false
        for _, port in ipairs (def.inputs) do
          local t = ins[port.key] ---@type Shader.Type?
          if not t then
            if port.type == 'gen' or port.type == 'any' then
              t = 'float'
            else
              t = port.type --[[@as Shader.Type]]
            end
          end
          info.ins[port.key] = t
          if port.type == 'gen' then
            gen_seen = true
            info.gen = t
          end
        end
        for _, o in ipairs (def.outputs) do
          local t = outs[o.key] ---@type Shader.Type?
          if not t then
            local ot = catalog.output_type (def, o, n.settings)
            t = (ot == 'gen' or ot == 'any') and (info.gen or 'float') or ot --[[@as Shader.Type]]
          end
          info.outs[o.key] = t
        end
        if not gen_seen then
          info.gen = nil
        end
      end
      return info
    end,

    ---What a node's element was drawn from. A change draws it again. The node's own part is
    ---worked out once for each node table.
    signature = function (n, info)
      local own = node_parts[n]
      if not own then
        own = n.type .. '|' .. text_of (n.inputs) .. '|' .. text_of (n.settings)
        node_parts[n] = own
      end
      if not info then
        return 'missing:' .. own
      end
      return table.concat ({
        own,
        text_of (info.ins),
        text_of (info.outs),
        keys_of (info.linked),
        keys_of (info.used),
        info.gen or '',
        info.error or '',
      }, '|')
    end,

    ---The rows a node shows before any message: outputs, inputs, then settings.
    rows = function (def, n)
      local count = #catalog.visible_outputs (def) + #def.inputs
      local settings = catalog.settings_of (def, n.settings)
      for _, s in ipairs (def.settings) do
        if shows (n, s, settings) then
          count = count + 1
        end
      end
      return count
    end,
  }
  return html
end

return M
