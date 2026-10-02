-- Wires on one shader canvas: each one two SVG paths, kept for as long as the wire lives, and
-- drawn through its reroute points. A drag redraws only the wires of what moves.
--
-- A wire's id is `<to>|<input>`, since an input takes one wire.

local M = {}

-- How close, in pixels, a dropped wire snaps to an input.
M.SNAP_PX = 30

---@param ctx ShaderCanvas.Ctx
function M.attach (ctx)
  local nc, core, html = ctx.nc, ctx.core, ctx.html_m

  ctx.wire_layer = nc.wire_layer ({
    ui = ctx.ui,
    layer = ctx.wires_svg,
    before = ctx.temp_wire,
    class = 'sg-wire',
    hit_class = 'sg-hit',
    on_hit = function (el, id)
      el:attr ('data-item', '#w|' .. id)
    end,
  })
  ctx.point_layer = nc.point_layer ({
    ui = ctx.ui,
    layer = ctx.wires_svg,
    mark = function (el, wire, index)
      el:attr ('data-item', '#p|' .. index .. '|' .. wire)
    end,
  })

  -- The wires of each node, built again only when the document's list of edges changed.
  local edges_from = nil ---@type Shader.Edge[]?
  local edges_of = {} ---@type table<string, Shader.Edge[]>
  local by_id = {} ---@type table<string, Shader.Edge>

  local function index_edges ()
    local edges = ctx.current ().edges
    if edges_from == edges then
      return
    end
    edges_from = edges
    edges_of, by_id = {}, {}
    for _, e in ipairs (edges) do
      by_id[core.graph.wire_id (e.to, e.input)] = e
      for _, id in ipairs ({ e.from, e.to }) do
        local list = edges_of[id] or {}
        list[#list + 1] = e
        edges_of[id] = list
      end
    end
  end

  ---@param id string
  ---@return Shader.Edge[]
  function ctx.edges_of (id)
    index_edges ()
    return edges_of[id] or {}
  end

  ---@param id string
  ---@return Shader.Edge?
  function ctx.wire (id)
    index_edges ()
    return by_id[id]
  end

  ---The points a wire passes through: its output, any reroute points, then its input.
  ---@param e Shader.Edge
  ---@return NodeCanvas.Point[]?
  function ctx.route_of (e)
    local a, b = ctx.node (e.from), ctx.node (e.to)
    if not a or not b then
      return nil
    end
    local x1, y1 = ctx.port_point (a, 'out', e.output)
    local x2, y2 = ctx.port_point (b, 'in', e.input)
    local id = core.graph.wire_id (e.to, e.input)
    local points = { { x = x1, y = y1 } } ---@type NodeCanvas.Point[]
    for i, p in ipairs (ctx.routes[id] or {}) do
      local at = ctx.live_points[nc.point_key (id, i)] or p
      points[#points + 1] = { x = at.x, y = at.y }
    end
    points[#points + 1] = { x = x2, y = y2 }
    return points
  end

  ---The type a node's output carries, from the last compile.
  ---@param from string
  ---@param output string
  ---@return Shader.Type
  function ctx.out_type (from, output)
    local result = ctx.docs.compiled (ctx.path)
    return result and result.out_types[from] and result.out_types[from][output]
      or 'float'
  end

  ---@param e Shader.Edge
  local function draw_edge (e)
    local route = ctx.route_of (e)
    if not route then
      return
    end
    local id = core.graph.wire_id (e.to, e.input)
    local t = ctx.out_type (e.from, e.output)
    ctx.wire_layer.set (id, {
      d = nc.route (route),
      color = html.TYPE_COLORS[t] or html.TYPE_COLORS.float,
      classes = {
        selected = ctx.selected_wire == id,
        insert = ctx.insert_wire == id,
      },
    })
  end

  ---Draws every wire, or only the wires of the nodes in `nodes` and the wires in `wires`.
  ---@param nodes? table<string, boolean>
  ---@param wires? table<string, boolean>
  function ctx.draw_wires (nodes, wires)
    index_edges ()
    if nodes or wires then
      local done = {} ---@type table<string, boolean>
      for id in pairs (nodes or {}) do
        for _, e in ipairs (edges_of[id] or {}) do
          local wid = core.graph.wire_id (e.to, e.input)
          if not done[wid] then
            done[wid] = true
            draw_edge (e)
          end
        end
      end
      for id in pairs (wires or {}) do
        local e = by_id[id]
        if e and not done[id] then
          done[id] = true
          draw_edge (e)
        end
      end
      return
    end
    local seen = {} ---@type table<string, boolean>
    for _, e in ipairs (ctx.current ().edges) do
      seen[core.graph.wire_id (e.to, e.input)] = true
      draw_edge (e)
    end
    ctx.wire_layer.keep (seen)
    if ctx.selected_wire and not seen[ctx.selected_wire] then
      ctx.selected_wire = nil
    end
  end

  function ctx.draw_points ()
    local list = {} ---@type NodeCanvas.RoutePoint[]
    for _, e in ipairs (ctx.current ().edges) do
      local id = core.graph.wire_id (e.to, e.input)
      for i, p in ipairs (ctx.routes[id] or {}) do
        local at = ctx.live_points[nc.point_key (id, i)] or p
        list[#list + 1] = { wire = id, index = i, x = at.x, y = at.y }
      end
    end
    ctx.point_layer.draw (list, ctx.picked.points)
  end

  ---Marks the wire a dragged node would go into, or none.
  ---@param wire? string
  function ctx.show_insert (wire)
    local old = ctx.insert_wire
    if old == wire then
      return
    end
    ctx.insert_wire = wire
    local redo = {} ---@type table<string, boolean>
    if old then
      redo[old] = true
    end
    if wire then
      redo[wire] = true
    end
    ctx.draw_wires (nil, redo)
  end

  ---The wire a node's box lies across, leaving out the node's own wires.
  ---@param box NodeCanvas.Box
  ---@param skip string
  ---@return string?
  function ctx.wire_at (box, skip)
    local lines = {} ---@type NodeCanvas.WireLine[]
    for _, e in ipairs (ctx.current ().edges) do
      if e.from ~= skip and e.to ~= skip then
        local route = ctx.route_of (e)
        if route then
          lines[#lines + 1] =
            { id = core.graph.wire_id (e.to, e.input), points = route }
        end
      end
    end
    return nc.wire_through (lines, box)
  end

  ---Where a reroute point added at `x`, `y` goes among a wire's points: after the stretch
  ---of the wire nearest to it.
  ---@param e Shader.Edge
  ---@param x number
  ---@param y number
  ---@return integer
  function ctx.point_index (e, x, y)
    local route = ctx.route_of (e) or {}
    local best, index = math.huge, 1 ---@type number, integer
    for i = 1, #route - 1 do
      local a, b = route[i], route[i + 1]
      local d = nc.distance_to (nc.curve_points (a.x, a.y, b.x, b.y), x, y)
      if d < best then
        best, index = d, i
      end
    end
    return index
  end

  -- Connecting -------------------------------------------------------------------------------

  -- The inputs the wire being dragged can go into, with where each sits.
  local targets = {} ---@type NodeCanvas.Target[]

  ---Works out, once when a wire drag starts, which inputs it can go into.
  ---@param from string
  ---@param output string
  function ctx.find_targets (from, output)
    targets = {}
    local d = ctx.current ()
    for _, n in ipairs (d.nodes) do
      local def = ctx.catalog.get (n.type)
      for _, port in ipairs (def and def.inputs or {}) do
        if not core.graph.why_not (d, from, output, n.id, port.key) then
          local x, y = ctx.port_point (n, 'in', port.key)
          targets[#targets + 1] = {
            x = x,
            y = y,
            data = { node = n.id, input = port.key },
          }
        end
      end
    end
  end

  ---The input a wire dropped at a window point snaps to.
  ---@param x number
  ---@param y number
  ---@return NodeCanvas.Target?
  function ctx.snap_target (x, y)
    local wx, wy = ctx.to_world (x, y)
    return nc.nearest (targets, wx, wy, M.SNAP_PX / ctx.view.zoom)
  end
end

return M
