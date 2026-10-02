-- Pointer gestures on one shader canvas. What a press landed on comes from the `data-item`
-- of the element under it, and the press starts a node_canvas gesture: a pan, a move, a
-- marquee, a frame being sized, or a wire being dragged. Nothing reaches the document until
-- the button comes up.
--
-- A plain drag on empty canvas pans, and so does the middle button anywhere. Shift or Ctrl
-- with a drag on empty canvas draws a marquee that picks the nodes it touches.

local frames_m = require ('frames')
local html_m = require ('node_html')
local view_m = require ('view')

local M = {}

local split = html_m.split

---@param ctx ShaderCanvas.Ctx
function M.attach (ctx)
  local nc, core = ctx.nc, ctx.core
  local viewport = ctx.viewport

  ---@return number?
  local function grid ()
    return ctx.snap_grid () and view_m.GRID_PX or nil
  end

  ---Starts moving the picked nodes, frames and reroute points, and the nodes inside each
  ---picked frame. `lead` is the one pressed, which snaps to the grid.
  ---@param x number
  ---@param y number
  ---@param lead NodeCanvas.Point
  ---@param only? string A click without a drag picks this alone.
  local function start_move (x, y, lead, only)
    local origins = {} ---@type table<string, NodeCanvas.Point>
    for id in pairs (ctx.picked.nodes) do
      local n = ctx.node (id)
      if n then
        origins[id] = ctx.position (n)
      end
    end
    local frames = {} ---@type table<string, NodeCanvas.Box>
    local boxes = ctx.boxes ()
    for id in pairs (ctx.picked.frames) do
      local box = ctx.frame_box (id)
      if box then
        frames[id] = box
        for _, inside in ipairs (nc.inside (box, boxes)) do
          local n = ctx.node (inside)
          if n and not origins[inside] then
            origins[inside] = ctx.position (n)
          end
        end
      end
    end
    local points = {} ---@type table<string, NodeCanvas.Point>
    for key in pairs (ctx.picked.points) do
      local wire, index = key:match ('^(.*)#(%d+)$')
      local route = wire and ctx.routes[wire]
      local p = route and route[tonumber (index)]
      if p then
        points[key] = { x = p.x, y = p.y }
      end
    end
    -- A node on its own, with no wires, can be dropped onto a wire to go into it.
    local single = nil ---@type string?
    local count = 0
    for id in pairs (origins) do
      count = count + 1
      single = id
    end
    if count ~= 1 or next (frames) or next (points) then
      single = nil
    end
    if single and #ctx.edges_of (single) > 0 then
      single = nil
    end
    ctx.drag = nc.press ('move', x, y, {
      origins = origins,
      data = {
        frames = frames,
        points = points,
        lead = lead,
        single = single,
        only = only,
      },
    })
  end

  ---Picks what a press landed on: Shift or Ctrl adds or takes away, and a plain press on
  ---something not picked picks it alone.
  ---@param kind 'nodes'|'frames'|'points'
  ---@param id string
  ---@param ev Proteus.DomEvent
  ---@return string? only Set when a plain press landed on one of several picked things.
  local function pick (kind, id, ev)
    local p = ctx.picked
    local plain = not (ev.shift or ev.ctrl or ev.meta)
    if plain and p[kind][id] then
      local count = 0
      for _, set in ipairs ({ p.nodes, p.frames, p.points }) do
        for _ in pairs (set) do
          count = count + 1
        end
      end
      return count > 1 and id or nil
    end
    if plain then
      local only = { nodes = {}, frames = {}, points = {} } ---@type ShaderCanvas.Picked
      only[kind][id] = true
      ctx.set_picked (only.nodes, only.frames, only.points)
      return nil
    end
    local next_set = nc.pick (
      p[kind],
      id,
      { shift = ev.shift, ctrl = ev.ctrl, meta = ev.meta }
    )
    local nodes, frames, points = p.nodes, p.frames, p.points
    if kind == 'nodes' then
      nodes = next_set
    elseif kind == 'frames' then
      frames = next_set
    else
      points = next_set
    end
    ctx.set_picked (nodes, frames, points)
    return nil
  end

  ---@param g NodeCanvas.Gesture
  local function move_step (g)
    local data = g.data or {}
    local dx, dy = nc.delta (g, ctx.view.zoom, grid (), data.lead)
    local moved = {} ---@type table<string, boolean>
    for id, p in pairs (g.origins or {}) do
      ctx.live[id] = { x = p.x + dx, y = p.y + dy }
      ctx.place (id)
      moved[id] = true
    end
    local framed = {} ---@type table<string, boolean>
    for id, box in
      pairs (data.frames --[[@as table<string, NodeCanvas.Box>]])
    do
      ctx.live_frames[id] =
        { x = box.x + dx, y = box.y + dy, w = box.w, h = box.h }
      framed[id] = true
    end
    if next (framed) then
      ctx.place_frames (framed)
    end
    local wires = {} ---@type table<string, boolean>
    for key, p in
      pairs (data.points --[[@as table<string, NodeCanvas.Point>]])
    do
      ctx.live_points[key] = { x = p.x + dx, y = p.y + dy }
      local wire = key:match ('^(.*)#%d+$')
      if wire then
        wires[wire] = true
      end
    end
    if next (wires) then
      ctx.draw_points ()
    end
    ctx.draw_wires (moved, wires)
    local single = data.single --[[@as string?]]
    local n = single and ctx.node (single)
    if single and n then
      ctx.show_insert (ctx.wire_at (ctx.box (n), single))
    end
  end

  ---@param g NodeCanvas.Gesture
  local function move_end (g)
    local data = g.data or {}
    local nodes = {} ---@type table<string, NodeCanvas.Point>
    for id in pairs (g.origins or {}) do
      nodes[id] = ctx.live[id]
    end
    local frames = {} ---@type table<string, NodeCanvas.Box>
    for id in
      pairs (data.frames --[[@as table<string, NodeCanvas.Box>]])
    do
      frames[id] = ctx.live_frames[id]
    end
    local points = {} ---@type table<string, NodeCanvas.Point>
    for key in
      pairs (data.points --[[@as table<string, NodeCanvas.Point>]])
    do
      points[key] = ctx.live_points[key]
    end
    ctx.live, ctx.live_frames, ctx.live_points = {}, {}, {}
    local insert = ctx.insert_wire
    ctx.show_insert (nil)
    if g.moved then
      ctx.finish_move (nodes, frames, points, insert)
    elseif data.only then
      ctx.set_picked ({ [data.only] = true })
    end
  end

  ---@param g NodeCanvas.Gesture
  ---@return table<string, boolean>
  local function marquee_pick (g)
    local r = viewport:rect ()
    local area = nc.marquee (g)
    ctx.marquee:style ('left', string.format ('%.0fpx', area.x - r.left))
    ctx.marquee:style ('top', string.format ('%.0fpx', area.y - r.top))
    ctx.marquee:style ('width', string.format ('%.0fpx', area.w))
    ctx.marquee:style ('height', string.format ('%.0fpx', area.h))
    ctx.marquee:show (true)
    local data = g.data or {}
    local picked = {} ---@type table<string, boolean>
    for id in
      pairs (data.base --[[@as table<string, boolean>]])
    do
      picked[id] = true
    end
    local boxes = data.boxes --[[@as NodeCanvas.Box[] ]]
    for _, id in
      ipairs (nc.touching (boxes, nc.box_to_world (ctx.view, r, area)))
    do
      picked[id] = true
    end
    return picked
  end

  viewport:on ('mousedown', function (ev)
    local x, y = ev.x or 0, ev.y or 0
    if ev.button == 1 then
      ctx.drag = nc.press ('pan', x, y, { view = ctx.view })
      viewport:class ('panning', true)
      return true
    end
    if ev.button ~= 0 then
      return nil
    end
    local item = ev.item and split (ev.item) or {}
    local kind = item[2]
    if item[1] == '#w' then
      ctx.selected_wire = item[2] .. '|' .. (item[3] or '')
      ctx.set_picked ({})
      ctx.draw_wires ()
      viewport:focus ()
      return true
    end
    if ctx.selected_wire then
      ctx.selected_wire = nil
      ctx.draw_wires ()
    end
    if item[1] == '#f' and item[3] == 'frame-title' then
      return nil
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
    if item[1] == '#p' then
      local index = tonumber (item[2])
      local wire = (item[3] or '') .. '|' .. (item[4] or '')
      local route = ctx.routes[wire]
      local p = route and index and route[index]
      if p and index then
        local key = nc.point_key (wire, index --[[@as integer]])
        local only = pick ('points', key, ev)
        if ctx.picked.points[key] then
          start_move (x, y, p, only)
        end
      end
      return true
    end
    if item[1] == '#f' and item[3] == 'frame-head' then
      local id = item[2]
      local only = pick ('frames', id, ev)
      local box = ctx.frame_box (id)
      if ctx.picked.frames[id] and box then
        start_move (x, y, box, only)
      end
      return true
    end
    if item[1] == '#f' and item[3] == 'frame-size' then
      local box = ctx.frame_box (item[2])
      if box then
        ctx.drag = nc.press ('size', x, y, {
          data = { frame = item[2], box = box },
        })
      end
      return true
    end
    if not ev.item or #item < 2 or item[1] == '#f' then
      if ev.shift or ev.ctrl or ev.meta then
        local base = {} ---@type table<string, boolean>
        for id in pairs (ctx.picked.nodes) do
          base[id] = true
        end
        ctx.drag = nc.press ('marquee', x, y, {
          data = { base = base, boxes = ctx.boxes () },
        })
        return true
      end
      if not ctx.nothing_picked () then
        ctx.set_picked ({})
      end
      ctx.drag = nc.press ('pan', x, y, { view = ctx.view })
      viewport:class ('panning', true)
      return true
    end
    local id = item[1]
    local n = ctx.node (id)
    if not n then
      return true
    end
    if (kind == 'out' or kind == 'pout') and item[3] then
      ctx.drag = nc.press ('wire', x, y, {
        data = {
          node = id,
          output = item[3],
          type = ctx.out_type (id, item[3]),
        },
      })
      ctx.find_targets (id, item[3])
      return true
    end
    if kind == 'pin' and item[3] then
      -- Pulling a wired input picks the wire up from its source.
      local e = core.graph.edge_into (ctx.current (), id, item[3])
      if e then
        local t = ctx.out_type (e.from, e.output)
        ctx.commit (core.graph.disconnect (ctx.current (), id, item[3]))
        local g = nc.press ('wire', x, y, {
          data = { node = e.from, output = e.output, type = t },
        })
        g.moved = true
        ctx.drag = g
        ctx.find_targets (e.from, e.output)
      end
      return true
    end
    -- The head moves the node, and the rest of what is picked with it.
    local only = pick ('nodes', id, ev)
    if (kind == 'head' or kind == 'in') and ctx.picked.nodes[id] then
      start_move (x, y, ctx.position (n), only)
      return true
    end
    return nil
  end)

  ---@param ev Proteus.DomEvent
  ---@return Proteus.EventResult
  function ctx.on_move (ev)
    local g = ctx.drag
    if not g or not nc.drag (g, ev.x or 0, ev.y or 0) then
      return nil
    end
    local data = g.data or {}
    if g.kind == 'pan' then
      ctx.view = nc.panned (g)
      ctx.apply_view ()
    elseif g.kind == 'move' then
      move_step (g)
    elseif g.kind == 'size' then
      local box = data.box --[[@as NodeCanvas.Box]]
      local dx, dy = nc.delta (g, ctx.view.zoom, grid (), {
        x = box.x + box.w,
        y = box.y + box.h,
      })
      ctx.live_frames[data.frame] = {
        x = box.x,
        y = box.y,
        w = math.max (frames_m.MIN_W, box.w + dx),
        h = math.max (frames_m.MIN_H, box.h + dy),
      }
      ctx.place_frames ({ [data.frame] = true })
    elseif g.kind == 'marquee' then
      ctx.picked.nodes = marquee_pick (g)
      ctx.show_picked ()
    elseif g.kind == 'wire' then
      local n = ctx.node (data.node)
      if n then
        local x1, y1 = ctx.port_point (n, 'out', data.output or 'out')
        local wx, wy = ctx.to_world (ev.x or 0, ev.y or 0)
        local target = ctx.snap_target (ev.x or 0, ev.y or 0)
        if target then
          wx, wy = target.x, target.y
        end
        ctx.temp_wire:attr ('d', nc.curve (x1, y1, wx, wy))
        ctx.temp_wire:attr (
          'stroke',
          html_m.TYPE_COLORS[data.type or 'float'] or html_m.TYPE_COLORS.float
        )
        ctx.temp_wire:show (true)
      end
    end
    return nil
  end

  ---@param ev Proteus.DomEvent
  ---@return Proteus.EventResult
  function ctx.on_up (ev)
    local g = ctx.drag
    if not g then
      return nil
    end
    ctx.drag = nil
    viewport:class ('panning', false)
    ctx.temp_wire:show (false)
    ctx.marquee:show (false)
    local data = g.data or {}
    if g.kind == 'pan' then
      if g.moved then
        ctx.save_view ()
      end
    elseif g.kind == 'move' then
      move_end (g)
    elseif g.kind == 'size' then
      local id = data.frame --[[@as string]]
      local box = ctx.live_frames[id]
      ctx.live_frames[id] = nil
      if g.moved and box then
        ctx.finish_move ({}, { [id] = box }, {})
      end
    elseif g.kind == 'marquee' then
      if g.moved then
        ctx.set_picked (marquee_pick (g), ctx.picked.frames, ctx.picked.points)
        ctx.marquee:show (false)
      end
    elseif g.kind == 'wire' then
      local item = ev.item and split (ev.item) or {}
      local target, input = item[1], item[3]
      local kind = item[2]
      local output = data.output or 'out'
      local snapped = ctx.snap_target (ev.x or 0, ev.y or 0)
      if
        target
        and input
        and (kind == 'in' or kind == 'pin' or kind == 'num' or kind == 'color')
      then
        ctx.commit (
          core.graph.connect (ctx.current (), data.node, output, target, input)
        )
      elseif snapped then
        ctx.commit (
          core.graph.connect (
            ctx.current (),
            data.node,
            output,
            snapped.data.node,
            snapped.data.input
          )
        )
      elseif not ev.item and g.moved then
        local wx, wy = ctx.to_world (ev.x or 0, ev.y or 0)
        ctx.ask_add ({ x = wx + 20, y = wy - 20 }, {
          node = data.node,
          output = output,
          type = data.type or 'float',
        })
      end
    end
    return nil
  end

  viewport:on ('wheel', function (ev)
    ctx.set_view (nc.wheel (ctx.view, ev, viewport:rect (), view_m.LIMITS))
    return true
  end)

  viewport:on ('dblclick', function (ev)
    local item = ev.item and split (ev.item) or {}
    local wx, wy = ctx.to_world (ev.x or 0, ev.y or 0)
    if item[1] == '#w' then
      ctx.add_point (item[2] .. '|' .. (item[3] or ''), wx, wy)
      return true
    end
    if item[1] == '#p' then
      local index = tonumber (item[2])
      if index then
        ctx.remove_point (
          (item[3] or '') .. '|' .. (item[4] or ''),
          index --[[@as integer]]
        )
      end
      return true
    end
    if item[1] == '#f' and item[3] == 'frame-head' then
      local title = ctx.frame_layer.title_el (item[2])
      if title then
        title:focus ():select ()
      end
      return true
    end
    if ev.item and item[1] ~= '#f' then
      return nil
    end
    ctx.ask_add ({ x = wx - view_m.NODE_W / 2, y = wy - 20 })
    return true
  end)

  viewport:on ('keydown', function (ev)
    -- Enter commits a field, the same as leaving it.
    if ev.key == 'Enter' and ev.item then
      viewport:focus ()
      return true
    end
    if ev.key == 'Escape' and ctx.drag then
      ctx.drag = nil
      ctx.live, ctx.live_frames, ctx.live_points = {}, {}, {}
      ctx.temp_wire:show (false)
      ctx.marquee:show (false)
      viewport:class ('panning', false)
      ctx.show_insert (nil)
      ctx.render ()
      return true
    end
    return nil
  end)
end

return M
