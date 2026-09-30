-- shader.canvas: the node editor for shader graphs. Nodes, typed wires, connecting, panning
-- and zooming.
--
-- The document in shader.docs is the source of truth. Each node is one element whose inside
-- is drawn as an HTML string, and the wires are one SVG drawn the same way. A node draws again
-- only when something it shows changes. While nodes are dragged, their new places live here,
-- and the document records one move when the drag ends.

local NODE_W = 232
local HEAD_H = 34
local ROW_H = 26
local DRAG_START_PX = 4
local ZOOM_MIN = 0.25
local ZOOM_MAX = 2
local COLUMN_W = 290
local ROW_GAP = 28

-- What an unwired input with a builtin reads, as its row shows it.
---@type table<string, string>
local BUILTIN_LABELS = { uv = 'uv', suv = 'square uv', frag = 'pixel' }

---@type table<string, string>
local TYPE_COLORS = {
  float = '#a1a1aa',
  vec2 = '#34d399',
  vec3 = '#fbbf24',
  vec4 = '#f472b6',
}

-- lang=css
local CSS = [[
.sg-root { display: flex; flex-direction: column; height: 100%; min-height: 0; }
.sg-bar {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 4px 8px;
  border-bottom: 0.5px solid var(--border);
  background: var(--bg-alt);
  font-size: 12px;
}
.sg-bar .sg-status { margin-left: auto; color: var(--fg-muted); }
.sg-bar .sg-status.bad { color: var(--danger); cursor: pointer; }
.sg-viewport {
  position: relative;
  flex: 1;
  min-height: 0;
  overflow: hidden;
  background-color: var(--bg);
  background-image: radial-gradient(circle, var(--border) 1.1px, transparent 1.2px);
  background-size: 22px 22px;
  user-select: none;
  outline: none;
}
.sg-viewport.panning { cursor: grabbing; }
.sg-world { position: absolute; left: 0; top: 0; transform-origin: 0 0; }
.sg-wires { position: absolute; left: 0; top: 0; width: 1px; height: 1px; overflow: visible; }
.sg-wire { fill: none; stroke-width: 2.4; pointer-events: none; }
.sg-wire.selected { stroke-width: 4.5; }
.sg-wire.temp { stroke-dasharray: 6 5; }
.sg-hit { fill: none; stroke: transparent; stroke-width: 12; pointer-events: stroke; cursor: pointer; }
.sg-node {
  position: absolute;
  left: 0;
  top: 0;
  width: 232px;
  background: var(--bg-elev);
  border: 0.5px solid var(--border);
  border-radius: 9px;
  font-size: 12px;
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.18), 0 8px 22px rgba(0, 0, 0, 0.1);
}
.sg-node.selected { outline: 2px solid var(--accent); outline-offset: 1px; }
.sg-node.error { border-color: var(--danger); }
.sg-node.unused { opacity: 0.62; }
.sg-head {
  height: 34px;
  box-sizing: border-box;
  display: flex;
  align-items: center;
  gap: 7px;
  padding: 0 10px;
  border-radius: 9px 9px 0 0;
  border-top: 3px solid var(--cat, var(--border));
  cursor: grab;
}
.sg-head .sg-title { flex: 1; min-width: 0; font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.sg-head .sg-kind { color: var(--fg-muted); font-family: var(--font-mono); font-size: 10.5px; }
.sg-row {
  position: relative;
  height: 26px;
  box-sizing: border-box;
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 0 12px 0 14px;
  border-top: 0.5px solid var(--border);
}
.sg-row.out { justify-content: flex-end; padding: 0 14px 0 12px; }
.sg-row .sg-label { flex: none; max-width: 92px; color: var(--fg-muted); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.sg-row.out .sg-label { color: var(--fg); }
.sg-row .sg-fill { flex: 1; min-width: 0; display: flex; gap: 3px; justify-content: flex-end; }
.sg-row .sg-t { color: var(--fg-muted); font-family: var(--font-mono); font-size: 10.5px; }
.sg-row .sg-builtin { color: var(--fg-muted); font-style: italic; font-size: 11px; }
.sg-row.message { color: var(--danger); height: auto; min-height: 26px; padding: 4px 10px; white-space: normal; line-height: 1.3; }
.sg-port {
  position: absolute;
  top: 7px;
  width: 12px;
  height: 12px;
  border-radius: 50%;
  box-sizing: border-box;
  border: 2px solid var(--bg-elev);
  box-shadow: 0 0 0 1px var(--border);
  cursor: crosshair;
  z-index: 2;
}
/* A wider target than the dot, so a port is easy to hit when zoomed out. */
.sg-port::before { content: ''; position: absolute; inset: -7px; border-radius: 50%; }
.sg-port.in { left: -6px; }
.sg-port.out { right: -6px; }
.sg-port.linked { box-shadow: 0 0 0 1.5px var(--fg-muted); }
.sg-num, .sg-text, .sg-select {
  min-width: 0;
  height: 19px;
  padding: 0 4px;
  border: 0.5px solid var(--border);
  border-radius: 4px;
  background: var(--bg);
  color: var(--fg);
  font: inherit;
  font-family: var(--font-mono);
  font-size: 11px;
  outline: none;
}
.sg-num { width: 100%; max-width: 54px; text-align: right; }
.sg-text { flex: 1; width: 100%; }
.sg-select { flex: 1; font-family: inherit; }
.sg-num:focus, .sg-text:focus, .sg-select:focus { border-color: var(--accent); }
.sg-color { width: 34px; height: 19px; padding: 0; border: 0.5px solid var(--border); border-radius: 4px; background: none; cursor: pointer; }
.sg-empty {
  position: absolute;
  inset: 0;
  display: grid;
  place-items: center;
  color: var(--fg-muted);
  pointer-events: none;
  text-align: center;
  line-height: 1.6;
}
]]

---@param v number
---@return string
local function fmt (v)
  if v == math.floor (v) and math.abs (v) < 1e9 then
    return string.format ('%d', v)
  end
  return (string.format ('%.4f', v):gsub ('0+$', ''):gsub ('%.$', ''))
end

---A colour as #rrggbb from numbers from 0 to 1.
---@param rgb number[]
---@return string
local function to_hex (rgb)
  local parts = {} ---@type string[]
  for i = 1, 3 do
    local v = math.max (0, math.min (1, tonumber (rgb[i]) or 0))
    parts[i] = string.format ('%02x', math.floor (v * 255 + 0.5))
  end
  return '#' .. table.concat (parts)
end

---Numbers from 0 to 1 from #rrggbb.
---@param hex string
---@return number[]?
local function from_hex (hex)
  local r, g, b = tostring (hex):match ('^#(%x%x)(%x%x)(%x%x)$')
  if not r then
    return nil
  end
  local function part (h)
    return math.floor (tonumber (h, 16) / 255 * 1000 + 0.5) / 1000
  end
  return { part (r), part (g), part (b) }
end

---@param text string
---@return string[]
local function split (text)
  local out = {} ---@type string[]
  for part in (text .. '|'):gmatch ('([^|]*)|') do
    out[#out + 1] = part
  end
  return out
end

---@type Proteus.Plugin
return {
  name = 'Shader canvas',
  description = 'The node editor for shader graphs: nodes, typed wires, panning and zooming.',
  version = '1.0.0',
  requires = { proteus = '>=0.2.0', features = { 'permissions' } },
  permissions = {},
  depends = {
    'lib.ui',
    'shader.core',
    'shader.docs',
    'core.commands',
  },
  optional = { 'ui.palette', 'ui.menus', 'ui.notify', 'core.keys' },
  activate = function (app)
    local ui = app.use ('ui')
    local core = app.use ('shader') --[[@as Shader.Core]]
    local docs = app.use ('shader.docs') --[[@as Shader.Docs]]
    local commands = app.use ('commands')
    local picker = app.try_use ('picker')
    local menus = app.try_use ('menus')
    local notify = app.try_use ('notify')
    ui.css (CSS)
    local esc = app.util.escape
    local catalog = core.nodes

    ---@param text string
    local function refuse (text)
      if notify then
        notify.warn (text)
      else
        app.warn (text)
      end
    end

    local instances = {} ---@type table<string, ShaderCanvas.Instance>

    ---Makes the canvas for one open graph.
    ---@param doc Shader.OpenDoc
    ---@return Proteus.El
    local function make_canvas (doc)
      local path = doc.path
      local view = app.store.get ('view:' .. path, nil)
      local pan = { x = 40, y = 40 } ---@type { x: number, y: number }
      local zoom = 1
      if type (view) == 'table' then
        pan = { x = tonumber (view.x) or 40, y = tonumber (view.y) or 40 }
        zoom = tonumber (view.zoom) or 1
      end
      local selected = {} ---@type table<string, boolean>
      local selected_wire = nil ---@type string?
      local drag = nil ---@type ShaderCanvas.Drag?
      local live = {} ---@type table<string, { x: number, y: number }>
      local elements = {} ---@type table<string, Proteus.El>
      local signatures = {} ---@type table<string, string>
      local held = nil ---@type string?

      local world = ui.div ({ class = 'sg-world' })
      local wires = ui.h ('svg:svg', { class = 'sg-wires' })
      local empty = ui.div ({ class = 'sg-empty' })
      local viewport = ui.div ({
        class = 'sg-viewport',
        attrs = { tabindex = '0' },
        world,
        empty,
      })
      world:append (wires)
      local status = ui.span ({ class = 'sg-status' })
      local zoom_label = ui.span ({ class = 'sg-t', text = '100%' })

      ---@return Shader.Doc
      local function current ()
        return doc.history.doc
      end

      local function save_view ()
        app.store.set ('view:' .. path, { x = pan.x, y = pan.y, zoom = zoom })
      end

      local function apply_view ()
        world:style (
          'transform',
          string.format (
            'translate(%.1fpx, %.1fpx) scale(%.3f)',
            pan.x,
            pan.y,
            zoom
          )
        )
        viewport:style (
          'background-size',
          string.format ('%.1fpx %.1fpx', 22 * zoom, 22 * zoom)
        )
        viewport:style (
          'background-position',
          string.format ('%.1fpx %.1fpx', pan.x, pan.y)
        )
        zoom_label:text (math.floor (zoom * 100 + 0.5) .. '%')
      end

      ---@param x number
      ---@param y number
      ---@return number, number
      local function to_world (x, y)
        local r = viewport:rect ()
        return (x - r.left - pan.x) / zoom, (y - r.top - pan.y) / zoom
      end

      ---@param n Shader.Node
      ---@return { x: number, y: number }
      local function position (n)
        return live[n.id] or { x = n.x, y = n.y }
      end

      ---The rows a node shows, in order: outputs, inputs, then settings.
      ---@param def Shader.NodeDef
      ---@return Shader.OutputDef[] outs
      local function outs_of (def)
        return catalog.visible_outputs (def)
      end

      ---Where a port sits, in world units.
      ---@param n Shader.Node
      ---@param side 'in'|'out'
      ---@param key string
      ---@return number, number
      local function port_point (n, side, key)
        local def = catalog.get (n.type)
        local p = position (n)
        if not def then
          return p.x, p.y
        end
        local outs = outs_of (def)
        if side == 'out' then
          for i, o in ipairs (outs) do
            if o.key == key then
              return p.x + NODE_W, p.y + HEAD_H + (i - 0.5) * ROW_H
            end
          end
        else
          for i, port in ipairs (def.inputs) do
            if port.key == key then
              return p.x, p.y + HEAD_H + (#outs + i - 0.5) * ROW_H
            end
          end
        end
        return p.x, p.y + HEAD_H / 2
      end

      ---@param x1 number
      ---@param y1 number
      ---@param x2 number
      ---@param y2 number
      ---@return string
      local function curve (x1, y1, x2, y2)
        local dx = math.max (40, math.abs (x2 - x1) * 0.5)
        return string.format (
          'M %.1f %.1f C %.1f %.1f, %.1f %.1f, %.1f %.1f',
          x1,
          y1,
          x1 + dx,
          y1,
          x2 - dx,
          y2,
          x2,
          y2
        )
      end

      local temp = nil ---@type { x1: number, y1: number, x2: number, y2: number, color: string }?

      local function draw_wires ()
        local d = current ()
        local result = docs.compiled (path)
        local parts = {} ---@type string[]
        for _, e in ipairs (d.edges) do
          local a, b = core.graph.node (d, e.from), core.graph.node (d, e.to)
          if a and b then
            local x1, y1 = port_point (a, 'out', e.output)
            local x2, y2 = port_point (b, 'in', e.input)
            local t = result
                and result.out_types[e.from]
                and result.out_types[e.from][e.output]
              or 'float'
            local id = e.to .. '|' .. e.input
            local path_d = curve (x1, y1, x2, y2)
            parts[#parts + 1] = '<path class="sg-wire'
              .. (selected_wire == id and ' selected' or '')
              .. '" stroke="'
              .. (TYPE_COLORS[t] or TYPE_COLORS.float)
              .. '" d="'
              .. path_d
              .. '"></path><path class="sg-hit" data-item="w|'
              .. esc (id)
              .. '" d="'
              .. path_d
              .. '"></path>'
          end
        end
        if temp then
          parts[#parts + 1] = '<path class="sg-wire temp" stroke="'
            .. temp.color
            .. '" d="'
            .. curve (temp.x1, temp.y1, temp.x2, temp.y2)
            .. '"></path>'
        end
        wires:html (table.concat (parts))
      end

      ---@param n Shader.Node
      local function place (n)
        local el = elements[n.id]
        if el then
          local p = position (n)
          el:style (
            'transform',
            string.format ('translate(%.1fpx, %.1fpx)', p.x, p.y)
          )
        end
      end

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
        for i = 1, core.types.dim (t) do
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
            size = core.types.is_type (kind) and core.types.dim (kind) or 1
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

      ---@param n Shader.Node
      ---@param def Shader.NodeDef
      ---@param info ShaderCanvas.NodeInfo
      ---@return string html, string color
      local function node_html (n, def, info)
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
        for _, o in ipairs (outs_of (def)) do
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
            .. (TYPE_COLORS[t] or TYPE_COLORS.float)
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
            .. (TYPE_COLORS[t] or TYPE_COLORS.float)
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
          local show = true
          if n.type == 'parameter' and (s.key == 'min' or s.key == 'max') then
            show = settings.kind ~= 'color'
          end
          if show then
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
      end

      ---What a node shows, from the document and the compile result.
      ---@param n Shader.Node
      ---@param result Shader.CompileResult?
      ---@param linked_map table<string, table<string, boolean>>
      ---@param used_map table<string, table<string, boolean>>
      ---@param errors table<string, string>
      ---@return ShaderCanvas.NodeInfo
      local function info_of (n, result, linked_map, used_map, errors)
        local def = catalog.get (n.type)
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
      end

      local function render ()
        local d = current ()
        local result = docs.compiled (path)
        local linked_map = {} ---@type table<string, table<string, boolean>>
        local used_map = {} ---@type table<string, table<string, boolean>>
        for _, e in ipairs (d.edges) do
          linked_map[e.to] = linked_map[e.to] or {}
          linked_map[e.to][e.input] = true
          used_map[e.from] = used_map[e.from] or {}
          used_map[e.from][e.output] = true
        end
        local errors = {} ---@type table<string, string>
        local loose = 0
        local list = result and result.errors or {} ---@type Shader.CompileError[]
        for _, err in ipairs (list) do
          local where = err.node ---@type string?
          if where then
            errors[where] = err.message
          else
            loose = loose + 1
          end
        end
        local seen = {} ---@type table<string, boolean>
        for _, n in ipairs (d.nodes) do
          seen[n.id] = true
          local def = catalog.get (n.type)
          local el = elements[n.id]
          if not el then
            el = ui.div ({ class = 'sg-node' })
            elements[n.id] = el
            world:insert_before (el, wires)
          end
          local info = def and info_of (n, result, linked_map, used_map, errors)
          local sig = def
              and (core.file.encode ({
                n.type,
                n.inputs,
                n.settings,
                info and info.ins,
                info and info.outs,
                info and info.linked,
                info and info.used,
                info and info.error or '',
              }))
            or ('missing:' .. n.type)
          if signatures[n.id] ~= sig and held ~= n.id then
            signatures[n.id] = sig
            if def and info then
              local html, color = node_html (n, def, info)
              el:html (html)
              el:style ('--cat', color)
            else
              el:html (
                '<div class="sg-head" data-item="'
                  .. n.id
                  .. '|head"><span class="sg-title">'
                  .. esc (n.type)
                  .. '</span></div><div class="sg-row message">There is no node called '
                  .. esc (n.type)
                  .. '.</div>'
              )
            end
          end
          el:class ('selected', selected[n.id] == true)
          el:class ('error', errors[n.id] ~= nil or not def)
          place (n)
        end
        for id, el in pairs (elements) do
          if not seen[id] then
            el:remove ()
            elements[id] = nil
            signatures[id] = nil
            selected[id] = nil
          end
        end
        draw_wires ()
        empty:show (#d.nodes == 0)
        if #d.nodes == 0 then
          empty:html (
            'Double-click to add a node.<br>Every shader needs an Output node.'
          )
        end
        local count = #(result and result.errors or {})
        if count == 0 then
          status:text (#d.nodes .. ' nodes')
          status:class ('bad', false)
        else
          status:text (count == 1 and '1 problem' or (count .. ' problems'))
          status:class ('bad', true)
          status:attr (
            'title',
            loose > 0 and (result and result.errors[1].message) or ''
          )
        end
      end

      ---@param ids string[]
      local function select_only (ids)
        selected = {}
        for _, id in ipairs (ids) do
          selected[id] = true
        end
        docs.select (path, ids)
        render ()
      end

      ---@return string[]
      local function selection ()
        local out = {} ---@type string[]
        for _, n in ipairs (current ().nodes) do
          if selected[n.id] then
            out[#out + 1] = n.id
          end
        end
        return out
      end

      ---Applies a new document from a graph operation, or says why it could not.
      ---@param doc_after Shader.Doc?
      ---@param refusal any
      ---@param key? string
      ---@return boolean
      local function commit (doc_after, refusal, key)
        if not doc_after then
          if type (refusal) == 'string' then
            refuse (refusal)
          end
          return false
        end
        docs.change (path, doc_after, key)
        return true
      end

      ---The middle of the view, in world units.
      ---@return number, number
      local function view_center ()
        local r = viewport:rect ()
        return (r.w / 2 - pan.x) / zoom, (r.h / 2 - pan.y) / zoom
      end

      ---Adds a node at a point, and wires it to the output a wire was dropped from.
      ---@param type_id string
      ---@param at? { x: number, y: number }
      ---@param from? { node: string, output: string, type: Shader.Type }
      ---@return string?
      local function add_node (type_id, at, from)
        local x, y ---@type number, number
        if at then
          x, y = at.x, at.y
        else
          x, y = view_center ()
          x, y = x - NODE_W / 2, y - 40
        end
        local d, id = core.graph.add_node (current (), type_id, x, y)
        if not d then
          refuse (id)
          return nil
        end
        if from then
          local def = catalog.get (type_id)
          for _, port in ipairs (def and def.inputs or {}) do
            local wired =
              core.graph.connect (d, from.node, from.output, id, port.key)
            if wired then
              d = wired
              break
            end
          end
        end
        docs.change (path, d)
        select_only ({ id })
        return id
      end

      ---Asks which node to add, then adds it.
      ---@param at? { x: number, y: number }
      ---@param from? { node: string, output: string, type: Shader.Type }
      local function ask_add (at, from)
        if not picker then
          return
        end
        local has_output = false
        for _, n in ipairs (current ().nodes) do
          has_output = has_output or n.type == 'output'
        end
        local items = {} ---@type Proteus.PickItem[]
        for _, def in ipairs (catalog.list) do
          local ok_here = not (def.unique and has_output)
          if from and #def.inputs == 0 then
            ok_here = false
          end
          if ok_here then
            local cat = catalog.category (def.category)
            items[#items + 1] = {
              label = def.title,
              detail = (cat and cat.title or def.category)
                .. ' · '
                .. def.description,
              value = def.type,
              search = def.title .. ' ' .. def.type .. ' ' .. def.category,
            }
          end
        end
        picker.pick ({
          items = items,
          placeholder = from and 'Add a node that takes this wire'
            or 'Add a node',
          on_pick = function (item)
            add_node (item.value, at, from)
          end,
        })
      end

      local function fit ()
        local d = current ()
        if #d.nodes == 0 then
          return
        end
        local x1 = math.huge ---@type number
        local y1 = math.huge ---@type number
        local x2 = -math.huge ---@type number
        local y2 = -math.huge ---@type number
        for _, n in ipairs (d.nodes) do
          x1, y1 = math.min (x1, n.x), math.min (y1, n.y)
          x2, y2 = math.max (x2, n.x + NODE_W), math.max (y2, n.y + 200)
        end
        local r = viewport:rect ()
        if r.w < 10 or r.h < 10 then
          return
        end
        zoom = math.max (
          ZOOM_MIN,
          math.min (
            1.2,
            math.min ((r.w - 60) / (x2 - x1), (r.h - 60) / (y2 - y1))
          )
        )
        pan = {
          x = (r.w - (x2 - x1) * zoom) / 2 - x1 * zoom,
          y = (r.h - (y2 - y1) * zoom) / 2 - y1 * zoom,
        }
        apply_view ()
        save_view ()
      end

      ---Lines nodes up in columns, each right of the nodes it reads from.
      local function tidy ()
        local d = current ()
        local depth = {} ---@type table<string, integer>
        ---@param id string
        ---@param guard integer
        ---@return integer
        local function depth_of (id, guard)
          if depth[id] then
            return depth[id]
          end
          if guard > #d.nodes then
            return 0
          end
          local best = 0
          for _, e in ipairs (d.edges) do
            if e.to == id then
              best = math.max (best, depth_of (e.from, guard + 1) + 1)
            end
          end
          depth[id] = best
          return best
        end
        local columns = {} ---@type table<integer, Shader.Node[]>
        local top = 0
        for _, n in ipairs (d.nodes) do
          local k = depth_of (n.id, 0)
          columns[k] = columns[k] or {}
          table.insert (columns[k], n)
          top = math.max (top, k)
        end
        local moves = {} ---@type table<string, { x: number, y: number }>
        for k = 0, top do
          local y = 40
          local list = columns[k] or {}
          table.sort (list, function (a, b)
            return a.y < b.y
          end)
          for _, n in ipairs (list) do
            moves[n.id] = { x = 40 + k * COLUMN_W, y = y }
            local def = catalog.get (n.type)
            local rows = def and (#outs_of (def) + #def.inputs + #def.settings)
              or 1
            y = y + HEAD_H + rows * ROW_H + ROW_GAP
          end
        end
        docs.change (path, core.graph.move (d, moves))
        app.timer.after (30, fit)
      end

      local function delete_selection ()
        if selected_wire then
          local to, input = selected_wire:match ('^(.-)|(.*)$')
          selected_wire = nil
          if to then
            commit (core.graph.disconnect (current (), to, input))
          end
          return
        end
        local ids = selection ()
        if #ids > 0 then
          commit (core.graph.remove_nodes (current (), ids))
          select_only ({})
        end
      end

      local function duplicate ()
        local ids = selection ()
        if #ids == 0 then
          return
        end
        local d, fresh = core.graph.duplicate (current (), ids)
        if d then
          docs.change (path, d)
          select_only (fresh)
        else
          refuse (fresh[1])
        end
      end

      -- Pointer gestures -----------------------------------------------------------------------

      viewport:on ('mousedown', function (ev)
        if ev.button ~= 0 then
          return nil
        end
        local item = ev.item and split (ev.item) or {}
        local x, y = ev.x or 0, ev.y or 0
        local kind = item[2]
        if item[1] == 'w' then
          selected_wire = item[2] .. '|' .. (item[3] or '')
          select_only ({})
          viewport:focus ()
          return true
        end
        if selected_wire then
          selected_wire = nil
          draw_wires ()
        end
        -- Fields take the press themselves.
        if
          kind == 'num'
          or kind == 'set'
          or kind == 'color'
          or kind == 'setcolor'
        then
          return nil
        end
        viewport:focus ()
        if not ev.item or #item < 2 then
          if not ev.shift then
            select_only ({})
          end
          drag = {
            kind = 'pan',
            x = x,
            y = y,
            moved = false,
            pan = { x = pan.x, y = pan.y },
          }
          viewport:class ('panning', true)
          return true
        end
        local id = item[1]
        local n = core.graph.node (current (), id)
        if not n then
          return true
        end
        if (kind == 'out' or kind == 'pout') and item[3] then
          local result = docs.compiled (path)
          local t = result
              and result.out_types[id]
              and result.out_types[id][item[3]]
            or 'float'
          drag = {
            kind = 'wire',
            x = x,
            y = y,
            moved = false,
            node = id,
            output = item[3],
            type = t,
          }
          return true
        end
        if kind == 'pin' and item[3] then
          -- Pulling a wired input picks the wire up from its source.
          local e = core.graph.edge_into (current (), id, item[3])
          if e then
            local result = docs.compiled (path)
            local t = result
                and result.out_types[e.from]
                and result.out_types[e.from][e.output]
              or 'float'
            commit (core.graph.disconnect (current (), id, item[3]))
            drag = {
              kind = 'wire',
              x = x,
              y = y,
              moved = true,
              node = e.from,
              output = e.output,
              type = t,
            }
            return true
          end
          return true
        end
        -- The head moves the node, and the selection with it.
        if ev.shift or ev.ctrl then
          selected[id] = not selected[id] or nil
          select_only (selection ())
        elseif not selected[id] then
          select_only ({ id })
        end
        if kind == 'head' or kind == 'in' or kind == 'set' then
          local origins = {} ---@type table<string, { x: number, y: number }>
          for _, sid in ipairs (selection ()) do
            local sn = core.graph.node (current (), sid)
            if sn then
              origins[sid] = { x = sn.x, y = sn.y }
            end
          end
          drag =
            { kind = 'move', x = x, y = y, moved = false, origins = origins }
          return true
        end
        return nil
      end)

      app.dom.on_global ('mousemove', function (ev)
        local d = drag
        if not d then
          return nil
        end
        local x, y = ev.x or 0, ev.y or 0
        if
          not d.moved
          and math.abs (x - d.x) + math.abs (y - d.y) > DRAG_START_PX
        then
          d.moved = true
        end
        if not d.moved then
          return nil
        end
        if d.kind == 'pan' and d.pan then
          pan = { x = d.pan.x + (x - d.x), y = d.pan.y + (y - d.y) }
          apply_view ()
        elseif d.kind == 'move' and d.origins then
          local doc_now = current ()
          for id, o in pairs (d.origins) do
            live[id] =
              { x = o.x + (x - d.x) / zoom, y = o.y + (y - d.y) / zoom }
            local n = core.graph.node (doc_now, id)
            if n then
              place (n)
            end
          end
          draw_wires ()
        elseif d.kind == 'wire' and d.node then
          local n = core.graph.node (current (), d.node)
          if n then
            local x1, y1 = port_point (n, 'out', d.output or 'out')
            local wx, wy = to_world (x, y)
            temp = {
              x1 = x1,
              y1 = y1,
              x2 = wx,
              y2 = wy,
              color = TYPE_COLORS[d.type or 'float'] or TYPE_COLORS.float,
            }
            draw_wires ()
          end
        end
        return nil
      end)

      app.dom.on_global ('mouseup', function (ev)
        local d = drag
        if not d then
          return nil
        end
        drag = nil
        viewport:class ('panning', false)
        if d.kind == 'pan' then
          if d.moved then
            save_view ()
          end
        elseif d.kind == 'move' and d.origins then
          if d.moved then
            local moves = {} ---@type table<string, { x: number, y: number }>
            for id in pairs (d.origins) do
              moves[id] = live[id]
            end
            live = {}
            docs.change (path, core.graph.move (current (), moves))
          end
          live = {}
        elseif d.kind == 'wire' and d.node then
          temp = nil
          local item = ev.item and split (ev.item) or {}
          local target, input = item[1], item[3]
          local kind = item[2]
          if
            target
            and input
            and (
              kind == 'in'
              or kind == 'pin'
              or kind == 'num'
              or kind == 'color'
            )
          then
            commit (
              core.graph.connect (
                current (),
                d.node,
                d.output or 'out',
                target,
                input
              )
            )
          elseif not ev.item and d.moved then
            local wx, wy = to_world (ev.x or 0, ev.y or 0)
            ask_add ({ x = wx + 20, y = wy - 20 }, {
              node = d.node,
              output = d.output or 'out',
              type = d.type or 'float',
            })
          end
          draw_wires ()
        end
        return nil
      end)

      viewport:on ('wheel', function (ev)
        local dx, dy = ev.dx or 0, ev.dy or 0
        -- A mouse wheel moves in big steps and zooms. A touchpad scrolls and pans.
        if
          ev.ctrl
          or ev.meta
          or (math.abs (dx) < 0.5 and math.abs (dy) >= 50)
        then
          local r = viewport:rect ()
          local px, py = (ev.x or 0) - r.left, (ev.y or 0) - r.top
          local nz = math.max (
            ZOOM_MIN,
            math.min (ZOOM_MAX, zoom * math.exp (-dy * 0.0015))
          )
          pan = {
            x = px - (px - pan.x) * nz / zoom,
            y = py - (py - pan.y) * nz / zoom,
          }
          zoom = nz
        else
          pan = { x = pan.x - dx, y = pan.y - dy }
        end
        apply_view ()
        save_view ()
        return true
      end)

      viewport:on ('dblclick', function (ev)
        if ev.item then
          return nil
        end
        local wx, wy = to_world (ev.x or 0, ev.y or 0)
        ask_add ({ x = wx - NODE_W / 2, y = wy - 20 })
        return true
      end)

      -- Fields -------------------------------------------------------------------------------

      ---@param id string
      ---@param key string
      ---@param index integer
      ---@param text string
      local function set_number (id, key, index, text)
        local v = tonumber (text)
        local n = core.graph.node (current (), id)
        local def = n and catalog.get (n.type)
        local port = def and catalog.input (def, key)
        if not n or not port or not v then
          signatures[id] = nil
          render ()
          return
        end
        local values = {} ---@type number[]
        local old = n.inputs[key] or port.default
        for i = 1, 4 do
          values[i] = tonumber (old[i] or old[#old]) or 0
        end
        values[index] = v
        commit (core.graph.set_input (current (), id, key, values))
      end

      ---@param id string
      ---@param key string
      ---@param index? integer
      ---@param text string
      local function set_setting (id, key, index, text)
        local n = core.graph.node (current (), id)
        local def = n and catalog.get (n.type)
        if not n or not def then
          return
        end
        local spec ---@type Shader.SettingDef?
        for _, s in ipairs (def.settings) do
          if s.key == key then
            spec = s
          end
        end
        if not spec then
          return
        end
        local value ---@type any
        if spec.kind == 'number' or spec.kind == 'int' then
          value = tonumber (text)
          if value and spec.kind == 'int' then
            value = math.floor (value)
            if spec.min then
              value = math.max (spec.min, value)
            end
            if spec.max then
              value = math.min (spec.max, value)
            end
          end
        elseif spec.kind == 'vector' then
          local v = tonumber (text)
          if v then
            local old = catalog.setting (def, n.settings, key) or {} ---@type number[]
            local vec = {} ---@type number[]
            for i = 1, spec.size or 4 do
              vec[i] = tonumber (old[i]) or 0
            end
            vec[index or 1] = v
            value = vec
          end
        else
          value = text
        end
        if value == nil then
          signatures[id] = nil
          render ()
          return
        end
        commit (core.graph.set_setting (current (), id, key, value))
      end

      viewport:on ('change', function (ev)
        local item = ev.item and split (ev.item) or {}
        local id, kind, key = item[1], item[2], item[3]
        if not id or not key then
          return nil
        end
        held = nil
        if kind == 'num' then
          set_number (
            id,
            key,
            math.floor (tonumber (item[4]) or 1),
            ev.value or ''
          )
        elseif kind == 'set' then
          local index = tonumber (item[4])
          set_setting (id, key, index and math.floor (index), ev.value or '')
        elseif kind == 'color' or kind == 'setcolor' then
          signatures[id] = nil
          render ()
        end
        return nil
      end)

      -- A colour follows the picker as it moves, without drawing the node again.
      viewport:on ('input', function (ev)
        local item = ev.item and split (ev.item) or {}
        local id, kind, key = item[1], item[2], item[3]
        local rgb = from_hex (ev.value or '')
        if not id or not key or not rgb then
          return nil
        end
        if kind == 'color' then
          held = id
          commit (
            core.graph.set_input (current (), id, key, rgb),
            nil,
            'color:' .. id .. key
          )
        elseif kind == 'setcolor' then
          held = id
          local n = core.graph.node (current (), id)
          local value = rgb
          if n and n.type == 'parameter' then
            value = { rgb[1], rgb[2], rgb[3], 1 }
          end
          commit (
            core.graph.set_setting (current (), id, key, value),
            nil,
            'color:' .. id .. key
          )
        end
        return nil
      end)

      viewport:on ('keydown', function (ev)
        -- Enter commits a field, the same as leaving it.
        if ev.key == 'Enter' and ev.item then
          viewport:focus ()
          return true
        end
        return nil
      end)

      if menus then
        menus.attach (viewport, function (ev)
          local item = ev.item and split (ev.item) or {}
          local id = item[1]
          local wx, wy = to_world (ev.x or 0, ev.y or 0)
          if id == 'w' then
            local to, input = item[2], item[3]
            return {
              {
                label = 'Remove Wire',
                icon = 'unlink',
                danger = true,
                run = function ()
                  commit (core.graph.disconnect (current (), to, input or ''))
                end,
              },
            }
          end
          if id and core.graph.node (current (), id) then
            if not selected[id] then
              select_only ({ id })
            end
            return {
              {
                label = 'Duplicate',
                icon = 'copy',
                key = 'Ctrl+D',
                run = duplicate,
              },
              {
                label = 'Show Its Code',
                icon = 'code',
                run = function ()
                  commands.run ('shader.show_code')
                end,
              },
              { separator = true },
              {
                label = 'Delete',
                icon = 'trash-2',
                danger = true,
                key = 'Delete',
                run = delete_selection,
              },
            }
          end
          return {
            {
              label = 'Add Node...',
              icon = 'plus',
              run = function ()
                ask_add ({ x = wx - NODE_W / 2, y = wy - 20 })
              end,
            },
            { label = 'Tidy Up', icon = 'layout-grid', run = tidy },
            { label = 'Zoom to Fit', icon = 'scan', run = fit },
          }
        end)
      end

      local bar = ui.div ({
        class = 'sg-bar',
        ui.button ({
          'Add Node',
          icon = 'plus',
          variant = 'ghost',
          title = 'Add a node (double-click the canvas)',
          onclick = function ()
            ask_add ()
          end,
        }),
        ui.button ({
          'Tidy Up',
          icon = 'layout-grid',
          variant = 'ghost',
          onclick = tidy,
        }),
        ui.button ({
          icon = 'scan',
          variant = 'ghost',
          title = 'Zoom to fit',
          onclick = fit,
        }),
        zoom_label,
        status,
      })
      status:on ('click', function ()
        local result = docs.compiled (path)
        local first = result and result.errors[1]
        if first then
          if first.node then
            select_only ({ first.node })
          end
          refuse (first.message)
        end
      end)
      local root = ui.div ({ class = 'sg-root', bar, viewport })

      instances[path] = {
        root = root,
        add = function (type_id)
          add_node (type_id)
        end,
        fit = fit,
        tidy = tidy,
        delete = delete_selection,
        duplicate = duplicate,
        select_all = function ()
          local ids = {} ---@type string[]
          for _, n in ipairs (current ().nodes) do
            ids[#ids + 1] = n.id
          end
          select_only (ids)
        end,
        select = select_only,
        render = render,
      }

      apply_view ()
      render ()
      if type (view) ~= 'table' then
        app.timer.after (60, fit)
      end
      return root
    end

    docs.register_opener ('graph', make_canvas)

    app.on ('shader:changed', function (path)
      local inst = instances[path]
      if inst then
        inst.render ()
      end
    end)
    app.on ('shader:uniform', function (path)
      local inst = instances[path]
      if inst then
        inst.render ()
      end
    end)
    app.on ('shader:closed', function (path)
      instances[path] = nil
    end)

    ---@return ShaderCanvas.Instance?
    local function front ()
      local d = docs.active ()
      return d and instances[d.path] or nil
    end

    ---@return boolean
    local function canvas_keys ()
      return front () ~= nil and not app.dom.focus_info ().editable
    end

    ---@type Shader.CanvasService
    local service = {
      add = function (type_id)
        local inst = front ()
        if inst then
          inst.add (type_id)
          return true
        end
        return false
      end,
      fit = function ()
        local inst = front ()
        if inst then
          inst.fit ()
        end
      end,
      select = function (path, ids)
        local inst = instances[path]
        if inst then
          inst.select (ids)
        end
      end,
    }
    app.provide ('shader.canvas', service)

    commands.register ({
      id = 'shader.add_node',
      category = 'Shader',
      title = 'Add Node...',
      menu = 'Graph',
      icon = 'plus',
      key = 'ctrl+k',
      when = function ()
        return front () ~= nil
      end,
      run = function ()
        local inst = front ()
        if inst and picker then
          local items = {} ---@type Proteus.PickItem[]
          for _, def in ipairs (catalog.list) do
            items[#items + 1] = {
              label = def.title,
              detail = def.description,
              value = def.type,
            }
          end
          picker.pick ({
            items = items,
            placeholder = 'Add a node',
            on_pick = function (item)
              inst.add (item.value)
            end,
          })
        end
      end,
    })
    commands.register ({
      id = 'shader.delete_selection',
      category = 'Shader',
      title = 'Delete Selected Nodes',
      menu = 'Graph',
      icon = 'trash-2',
      key = { 'delete', 'backspace' },
      when = canvas_keys,
      run = function ()
        local inst = front ()
        if inst then
          inst.delete ()
        end
      end,
    })
    commands.register ({
      id = 'shader.duplicate',
      category = 'Shader',
      title = 'Duplicate Selected Nodes',
      menu = 'Graph',
      icon = 'copy',
      key = 'ctrl+d',
      when = canvas_keys,
      run = function ()
        local inst = front ()
        if inst then
          inst.duplicate ()
        end
      end,
    })
    commands.register ({
      id = 'shader.select_all',
      category = 'Shader',
      title = 'Select All Nodes',
      menu = 'Graph',
      icon = 'box-select',
      key = 'ctrl+a',
      when = canvas_keys,
      run = function ()
        local inst = front ()
        if inst then
          inst.select_all ()
        end
      end,
    })
    commands.register ({
      id = 'shader.tidy',
      category = 'Shader',
      title = 'Tidy Up',
      menu = 'Graph',
      icon = 'layout-grid',
      when = function ()
        return front () ~= nil
      end,
      run = function ()
        local inst = front ()
        if inst then
          inst.tidy ()
        end
      end,
    })
    commands.register ({
      id = 'shader.fit',
      category = 'Shader',
      title = 'Zoom to Fit',
      menu = 'Graph',
      icon = 'scan',
      key = 'shift+1',
      when = canvas_keys,
      run = function ()
        local inst = front ()
        if inst then
          inst.fit ()
        end
      end,
    })
  end,
}
