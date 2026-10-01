-- shader.canvas: the node editor for shader graphs. Nodes, typed wires, connecting, panning
-- and zooming, frames, reroute points, picking many nodes, copy and paste, and a minimap.
--
-- The document in shader.docs is the source of truth. Each node is one element whose inside
-- is drawn as an HTML string, and draws again only when something it shows changes. Each wire
-- keeps its own SVG paths. While nodes are dragged, their new places live here, and the
-- document records one change when the drag ends.
--
-- Each open shader gets its own canvas, and each part of a canvas lives in a module that adds
-- its functions to the canvas's context:
--
--   style      the CSS
--   node_html  what a node shows, as HTML. Pure, so the tests reach it.
--   view       pan, zoom, where nodes and ports sit, fitting the graph in view
--   wires      wires, reroute points, and the inputs a dragged wire can go into
--   frames     frames behind the nodes
--   edit       picking, and every change: add, paste, delete, move, tidy, frames
--   gestures   pointer gestures
--   commands   the commands and the right-click menu
--
-- The math every node canvas needs is the app's lib/node_canvas.lua, which Nodal's canvas
-- shares. It ships with Proteus 0.3.1.

local CSS = require ('style') --[[@as string]]
local commands_m = require ('commands')
local edit_m = require ('edit')
local frames_m = require ('frames')
local gestures_m = require ('gestures')
local html_m = require ('node_html')
local view_m = require ('view')
local wires_m = require ('wires')

---@type Proteus.Plugin
return {
  name = 'Shader canvas',
  description = 'The node editor for shader graphs: nodes, typed wires, panning and zooming.',
  version = '1.1.0',
  requires = { proteus = '>=0.3.1', features = { 'permissions' } },
  permissions = {},
  depends = {
    'lib.ui',
    'shader.core',
    'shader.docs',
    'core.commands',
  },
  optional = { 'ui.palette', 'ui.menus', 'ui.notify', 'core.keys' },
  activate = function (app)
    -- The shared node canvas is in the app's lib/.
    local nc = require ('node_canvas') --[[@as NodeCanvas]]
    local ui = app.use ('ui')
    local core = app.use ('shader') --[[@as Shader.Core]]
    local docs = app.use ('shader.docs') --[[@as Shader.Docs]]
    local commands = app.use ('commands')
    local menus = app.try_use ('menus')
    local notify = app.try_use ('notify')
    ui.css (CSS)
    ui.css (nc.CSS)
    local html = html_m.new ({
      catalog = core.nodes,
      types = core.types,
      esc = app.util.escape,
    })

    ---@param text string
    local function refuse (text)
      if notify then
        notify.warn (text)
      else
        app.warn (text)
      end
    end

    local snap_grid = app.store.get ('snap', false) == true
    local instances = {} ---@type table<string, ShaderCanvas.Ctx>

    ---Makes the canvas for one open graph.
    ---@param doc Shader.OpenDoc
    ---@return Proteus.El
    local function make_canvas (doc)
      local path = doc.path
      local saved = app.store.get ('view:' .. path, nil)
      local view = { x = 40, y = 40, zoom = 1 } ---@type NodeCanvas.View
      if type (saved) == 'table' then
        view = {
          x = tonumber (saved.x) or 40,
          y = tonumber (saved.y) or 40,
          zoom = tonumber (saved.zoom) or 1,
        }
      end

      local frames_el = ui.div ({ class = 'sg-frames' })
      local world = ui.div ({ class = 'sg-world', frames_el })
      local wires_svg = ui.h ('svg:svg', { class = 'sg-wires' })
      local temp_wire = ui.h ('svg:path', { class = 'sg-wire temp' })
      temp_wire:show (false)
      wires_svg:append (temp_wire)
      world:append (wires_svg)
      local empty = ui.div ({ class = 'sg-empty' })
      local marquee = ui.div ({ class = 'nc-marquee' })
      marquee:show (false)
      local viewport = ui.div ({
        class = 'sg-viewport',
        attrs = { tabindex = '0' },
        world,
        empty,
        marquee,
      })
      local status = ui.span ({ class = 'sg-status' })
      local zoom_label = ui.span ({ class = 'sg-t', text = '100%' })

      local shared = {
        app = app,
        ui = ui,
        nc = nc,
        core = core,
        docs = docs,
        commands = commands,
        catalog = core.nodes,
        html = html,
        html_m = html_m,
        refuse = refuse,
        doc = doc,
        path = path,
        view = view,
        picked = { nodes = {}, frames = {}, points = {} },
        live = {},
        live_frames = {},
        live_points = {},
        routes = {},
        elements = {},
        drawn = {},
        shown = {},
        heights = {},
        snap_grid = function ()
          return snap_grid
        end,
        viewport = viewport,
        world = world,
        frames_el = frames_el,
        wires_svg = wires_svg,
        temp_wire = temp_wire,
        marquee = marquee,
        zoom_label = zoom_label,
      }
      -- The modules fill in the rest.
      local ctx = shared --[[@as ShaderCanvas.Ctx]]
      ctx.minimap = nc.minimap ({
        ui = ui,
        on_jump = function (x, y)
          ctx.set_view (nc.center_on (ctx.view, viewport:rect (), x, y))
        end,
      })
      viewport:append (ctx.minimap.el)

      view_m.attach (ctx)
      wires_m.attach (ctx)
      frames_m.attach (ctx)
      edit_m.attach (ctx)
      gestures_m.attach (ctx)
      if menus then
        commands_m.menu (ctx, menus)
      end

      function ctx.draw_minimap ()
        local boxes = {} ---@type NodeCanvas.Box[]
        for _, n in ipairs (ctx.current ().nodes) do
          local p = ctx.position (n)
          -- The rows give the size here, so drawing the map measures nothing.
          local def = core.nodes.get (n.type)
          local h = view_m.HEAD_H
            + (def and html.rows (def, n) or 1) * view_m.ROW_H
          boxes[#boxes + 1] =
            { id = n.id, x = p.x, y = p.y, w = view_m.NODE_W, h = h }
        end
        local frames = {} ---@type NodeCanvas.Box[]
        for _, f in ipairs (ctx.frames ()) do
          frames[#frames + 1] =
            { id = f.id, x = f.x, y = f.y, w = f.w, h = f.h }
        end
        ctx.minimap.draw (
          boxes,
          frames,
          ctx.picked.nodes,
          ctx.view,
          viewport:rect ()
        )
      end

      ---Moves a node's element to where the node is, when that changed.
      ---@param id string
      function ctx.place (id)
        local el = ctx.elements[id]
        local n = ctx.node (id)
        if el and n then
          local p = ctx.position (n)
          local placed = string.format ('translate(%.1fpx, %.1fpx)', p.x, p.y)
          local shown = ctx.shown[id] or {}
          ctx.shown[id] = shown
          if shown.placed ~= placed then
            shown.placed = placed
            el:style ('transform', placed)
          end
        end
      end

      ---Shows which nodes are picked.
      function ctx.show_picked ()
        for id, el in pairs (ctx.elements) do
          local shown = ctx.shown[id] or {}
          ctx.shown[id] = shown
          local on = ctx.picked.nodes[id] == true
          if shown.picked ~= on then
            shown.picked = on
            el:class ('selected', on)
          end
        end
      end

      function ctx.render ()
        local d = ctx.current ()
        local result = docs.compiled (path)
        ctx.routes = core.graph.routes (d)
        local linked_map = {} ---@type table<string, table<string, boolean>>
        local used_map = {} ---@type table<string, table<string, boolean>>
        for _, e in ipairs (d.edges) do
          linked_map[e.to] = linked_map[e.to] or {}
          linked_map[e.to][e.input] = true
          used_map[e.from] = used_map[e.from] or {}
          used_map[e.from][e.output] = true
        end
        local errors = {} ---@type table<string, string>
        local loose = nil ---@type string?
        local list = result and result.errors or {} ---@type Shader.CompileError[]
        for _, err in ipairs (list) do
          local where = err.node ---@type string?
          if where then
            errors[where] = errors[where] or err.message
          elseif not loose then
            loose = err.message
          end
        end
        local seen = {} ---@type table<string, boolean>
        for _, n in ipairs (d.nodes) do
          seen[n.id] = true
          local def = core.nodes.get (n.type)
          local el = ctx.elements[n.id]
          if not el then
            el = ui.div ({ class = 'sg-node' })
            ctx.elements[n.id] = el
            world:insert_before (el, wires_svg)
          end
          local info = def
            and html.info_of (n, result, linked_map, used_map, errors)
          local sig = html.signature (n, info or nil)
          if ctx.drawn[n.id] ~= sig and ctx.held ~= n.id then
            ctx.drawn[n.id] = sig
            ctx.heights[n.id] = nil
            if def and info then
              local text, color = html.node_html (n, def, info)
              el:html (text)
              el:style ('--cat', color)
            else
              el:html (html.missing_html (n))
            end
          end
          local shown = ctx.shown[n.id] or {}
          ctx.shown[n.id] = shown
          local bad = errors[n.id] ~= nil or not def
          if shown.bad ~= bad then
            shown.bad = bad
            el:class ('error', bad)
          end
          ctx.place (n.id)
        end
        for id, el in pairs (ctx.elements) do
          if not seen[id] then
            el:remove ()
            ctx.elements[id] = nil
            ctx.drawn[id] = nil
            ctx.shown[id] = nil
            ctx.heights[id] = nil
            ctx.picked.nodes[id] = nil
          end
        end
        ctx.show_picked ()
        ctx.draw_frames ()
        ctx.draw_wires ()
        ctx.draw_points ()
        ctx.draw_minimap ()
        empty:show (#d.nodes == 0)
        if #d.nodes == 0 then
          empty:html (
            'Double-click to add a node.<br>Every shader needs an Output node.'
          )
        end
        local count = #list
        if count == 0 then
          status:text (#d.nodes .. ' nodes')
          status:class ('bad', false)
          status:attr ('title', '')
        else
          status:text (count == 1 and '1 problem' or (count .. ' problems'))
          status:class ('bad', true)
          -- A problem of no one node, such as a missing Output, has nowhere else to show.
          status:attr ('title', loose or '')
        end
      end

      -- Fields -------------------------------------------------------------------------------

      ---@param id string
      ---@param key string
      ---@param index integer
      ---@param text string
      local function set_number (id, key, index, text)
        local v = tonumber (text)
        local n = ctx.node (id)
        local def = n and core.nodes.get (n.type)
        local port = def and core.nodes.input (def, key)
        if not n or not port or not v then
          ctx.drawn[id] = nil
          ctx.render ()
          return
        end
        local values = {} ---@type number[]
        local old = n.inputs[key] or port.default
        for i = 1, 4 do
          values[i] = tonumber (old[i] or old[#old]) or 0
        end
        values[index] = v
        ctx.commit (core.graph.set_input (ctx.current (), id, key, values))
      end

      ---@param id string
      ---@param key string
      ---@param index? integer
      ---@param text string
      local function set_setting (id, key, index, text)
        local n = ctx.node (id)
        local def = n and core.nodes.get (n.type)
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
            local old = core.nodes.setting (def, n.settings, key) or {} ---@type number[]
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
          ctx.drawn[id] = nil
          ctx.render ()
          return
        end
        ctx.commit (core.graph.set_setting (ctx.current (), id, key, value))
      end

      viewport:on ('change', function (ev)
        local item = ev.item and html_m.split (ev.item) or {}
        local id, kind, key = item[1], item[2], item[3]
        if not id or not key then
          return nil
        end
        ctx.held = nil
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
          ctx.drawn[id] = nil
          ctx.render ()
        end
        return nil
      end)

      -- A colour follows the picker as it moves, without drawing the node again.
      viewport:on ('input', function (ev)
        local item = ev.item and html_m.split (ev.item) or {}
        local id, kind, key = item[1], item[2], item[3]
        local rgb = html_m.from_hex (ev.value or '')
        if not id or not key or not rgb then
          return nil
        end
        if kind == 'color' then
          ctx.held = id
          ctx.commit (
            core.graph.set_input (ctx.current (), id, key, rgb),
            nil,
            'color:' .. id .. key
          )
        elseif kind == 'setcolor' then
          ctx.held = id
          local n = ctx.node (id)
          local value = rgb
          if n and n.type == 'parameter' then
            value = { rgb[1], rgb[2], rgb[3], 1 }
          end
          ctx.commit (
            core.graph.set_setting (ctx.current (), id, key, value),
            nil,
            'color:' .. id .. key
          )
        end
        return nil
      end)

      local bar = ui.div ({
        class = 'sg-bar',
        ui.button ({
          'Add Node',
          icon = 'plus',
          variant = 'ghost',
          title = 'Add a node (double-click the canvas)',
          onclick = function ()
            ctx.ask_add ()
          end,
        }),
        ui.button ({
          'Tidy Up',
          icon = 'layout-grid',
          variant = 'ghost',
          onclick = ctx.tidy,
        }),
        ui.button ({
          icon = 'scan',
          variant = 'ghost',
          title = 'Zoom to fit',
          onclick = ctx.fit,
        }),
        zoom_label,
        status,
      })
      status:on ('click', function ()
        local result = docs.compiled (path)
        local first = result and result.errors[1]
        if first then
          if first.node then
            ctx.set_picked ({ [first.node] = true })
          end
          refuse (first.message)
        end
      end)
      ctx.root = ui.div ({ class = 'sg-root', bar, viewport })
      instances[path] = ctx

      ctx.apply_view ()
      ctx.render ()
      if type (saved) ~= 'table' then
        app.timer.after (60, ctx.fit)
      end
      return ctx.root
    end

    docs.register_opener ('graph', make_canvas)

    app.on ('shader:changed', function (path)
      local ctx = instances[path]
      if ctx then
        ctx.render ()
      end
    end)
    app.on ('shader:uniform', function (path)
      local ctx = instances[path]
      if ctx then
        ctx.render ()
      end
    end)
    app.on ('shader:closed', function (path)
      instances[path] = nil
    end)

    -- One listener for every canvas: the one with a drag going on hears the pointer.
    app.dom.on_global ('mousemove', function (ev)
      for _, ctx in pairs (instances) do
        if ctx.drag then
          return ctx.on_move (ev)
        end
      end
      return nil
    end)
    app.dom.on_global ('mouseup', function (ev)
      for _, ctx in pairs (instances) do
        if ctx.drag then
          return ctx.on_up (ev)
        end
      end
      return nil
    end)

    ---@return ShaderCanvas.Ctx?
    local function front ()
      local d = docs.active ()
      return d and instances[d.path] or nil
    end

    ---@type Shader.CanvasService
    local service = {
      add = function (type_id)
        local ctx = front ()
        if ctx then
          ctx.add_node (type_id)
          return true
        end
        return false
      end,
      fit = function ()
        local ctx = front ()
        if ctx then
          ctx.fit ()
        end
      end,
      select = function (path, ids)
        local ctx = instances[path]
        if ctx then
          local picked = {} ---@type table<string, boolean>
          for _, id in ipairs (ids) do
            picked[id] = true
          end
          ctx.set_picked (picked)
        end
      end,
    }
    app.provide ('shader.canvas', service)

    commands_m.register (app, commands, front, function ()
      snap_grid = not snap_grid
      app.store.set ('snap', snap_grid)
    end)
  end,
}
