-- Geometry and the view of one shader canvas: the pan and zoom, where each node and port
-- sits, how tall each node is, and framing the graph. The math is node_canvas's, from the
-- app's lib/.

local M = {}

M.NODE_W = 232
M.HEAD_H = 34
M.ROW_H = 26
M.GRID_PX = 22
M.LIMITS = { min = 0.25, max = 2 }

---@param ctx ShaderCanvas.Ctx
function M.attach (ctx)
  local nc, app, catalog = ctx.nc, ctx.app, ctx.catalog

  function ctx.current ()
    return ctx.doc.history.doc
  end

  -- Each node by id, built again only when the document's list of nodes changed.
  local index_from = nil ---@type Shader.Node[]?
  local by_id = {} ---@type table<string, Shader.Node>

  ---@param id string
  ---@return Shader.Node?
  function ctx.node (id)
    local list = ctx.current ().nodes
    if index_from ~= list then
      index_from = list
      by_id = {}
      for _, n in ipairs (list) do
        by_id[n.id] = n
      end
    end
    return by_id[id]
  end

  function ctx.save_view ()
    local v = ctx.view
    app.store.set ('view:' .. ctx.path, { x = v.x, y = v.y, zoom = v.zoom })
  end

  function ctx.apply_view ()
    local view = ctx.view
    ctx.world:style ('transform', nc.transform (view))
    local size, position = nc.grid (view, M.GRID_PX)
    ctx.viewport:style ('background-size', size)
    ctx.viewport:style ('background-position', position)
    ctx.zoom_label:text (math.floor (view.zoom * 100 + 0.5) .. '%')
    ctx.minimap.show_seen (view, ctx.viewport:rect ())
  end

  ---@param view NodeCanvas.View
  function ctx.set_view (view)
    ctx.view = view
    ctx.apply_view ()
    ctx.save_view ()
  end

  ---@param x number
  ---@param y number
  ---@return number, number
  function ctx.to_world (x, y)
    return nc.to_world (ctx.view, ctx.viewport:rect (), x, y)
  end

  ---Where a node is: its place during a drag or a tidy, else the document's.
  ---@param n Shader.Node
  ---@return NodeCanvas.Point
  function ctx.position (n)
    return ctx.live[n.id] or { x = n.x, y = n.y }
  end

  ---How tall a node is, measured from its element the first time it is asked after the node
  ---was drawn. A node not drawn yet counts its rows.
  ---@param n Shader.Node
  ---@return number
  function ctx.height (n)
    local known = ctx.heights[n.id]
    if known then
      return known
    end
    local el = ctx.elements[n.id]
    local r = el and el:rect ()
    if r and r.h > 0 then
      ctx.heights[n.id] = r.h / ctx.view.zoom
      return ctx.heights[n.id]
    end
    -- Hidden, as in a tab behind another: count the rows, and measure next time.
    local def = catalog.get (n.type)
    return M.HEAD_H + (def and ctx.html.rows (def, n) or 1) * M.ROW_H
  end

  ---@param n Shader.Node
  ---@return NodeCanvas.Box
  function ctx.box (n)
    local p = ctx.position (n)
    return { id = n.id, x = p.x, y = p.y, w = M.NODE_W, h = ctx.height (n) }
  end

  ---The boxes of every node, or of the picked ones.
  ---@param picked_only? boolean
  ---@return NodeCanvas.Box[]
  function ctx.boxes (picked_only)
    local out = {} ---@type NodeCanvas.Box[]
    for _, n in ipairs (ctx.current ().nodes) do
      if not picked_only or ctx.picked.nodes[n.id] then
        out[#out + 1] = ctx.box (n)
      end
    end
    return out
  end

  ---Where a port sits, in world units.
  ---@param n Shader.Node
  ---@param side 'in'|'out'
  ---@param key string
  ---@return number, number
  function ctx.port_point (n, side, key)
    local def = catalog.get (n.type)
    local p = ctx.position (n)
    if not def then
      return p.x, p.y
    end
    local outs = catalog.visible_outputs (def)
    if side == 'out' then
      for i, o in ipairs (outs) do
        if o.key == key then
          return p.x + M.NODE_W, p.y + M.HEAD_H + (i - 0.5) * M.ROW_H
        end
      end
    else
      for i, port in ipairs (def.inputs) do
        if port.key == key then
          return p.x, p.y + M.HEAD_H + (#outs + i - 0.5) * M.ROW_H
        end
      end
    end
    return p.x, p.y + M.HEAD_H / 2
  end

  ---The middle of the view, in world units.
  ---@return number, number
  function ctx.view_center ()
    local r = ctx.viewport:rect ()
    local s = nc.seen (ctx.view, r)
    return s.x + s.w / 2, s.y + s.h / 2
  end

  ---Frames every node and frame, where they are now and as tall as they are drawn.
  function ctx.fit ()
    local boxes = ctx.boxes ()
    for _, f in ipairs (ctx.frames ()) do
      boxes[#boxes + 1] = { x = f.x, y = f.y, w = f.w, h = f.h }
    end
    local view = nc.fit (
      boxes,
      ctx.viewport:rect (),
      { pad = 30, min = M.LIMITS.min, max = 1.2 }
    )
    if view then
      ctx.set_view (view)
    end
  end

  ---Moves the view so a node sits in the middle, at the same zoom.
  ---@param id string
  function ctx.center_on (id)
    local n = ctx.node (id)
    if n then
      local b = ctx.box (n)
      ctx.set_view (
        nc.center_on (
          ctx.view,
          ctx.viewport:rect (),
          b.x + b.w / 2,
          b.y + b.h / 2
        )
      )
    end
  end
end

return M
