-- Picking and changing a shader graph: which nodes, frames and reroute points are picked, and
-- every change made to them together. Each change goes to shader.docs as one whole document,
-- so it is one undo step however many nodes it touches.

local view_m = require ('view')

local M = {}

-- Pasted nodes land this far below and to the right of the nodes they copy.
local STEP = 40
local TIDY_MS = 280
local COLUMN_GAP = 58
local ROW_GAP = 28

-- One clipboard for every open shader, so nodes copied in one graph paste into another.
local clipboard = nil ---@type Shader.Fragment?
local clip_bounds = nil ---@type NodeCanvas.Box?
local clip_path = nil ---@type string?
local pasted = 0

---@param set table<string, boolean>
---@return string[]
local function sorted (set)
  local out = {} ---@type string[]
  for k in pairs (set) do
    out[#out + 1] = k
  end
  table.sort (out)
  return out
end

---@param ctx ShaderCanvas.Ctx
function M.attach (ctx)
  local nc, core, docs, app = ctx.nc, ctx.core, ctx.docs, ctx.app
  local catalog = ctx.catalog

  ---@param blocks table<string, boolean>
  ---@param frames? table<string, boolean>
  ---@param points? table<string, boolean>
  function ctx.set_picked (blocks, frames, points)
    ctx.picked =
      { nodes = blocks, frames = frames or {}, points = points or {} }
    docs.select (ctx.path, sorted (blocks))
    ctx.show_picked ()
    ctx.draw_frames ()
    ctx.draw_points ()
    ctx.draw_minimap ()
  end

  ---@return boolean
  function ctx.nothing_picked ()
    local p = ctx.picked
    return next (p.nodes) == nil
      and next (p.frames) == nil
      and next (p.points) == nil
  end

  ---The picked nodes, in document order.
  ---@return string[]
  function ctx.picked_nodes ()
    local out = {} ---@type string[]
    for _, n in ipairs (ctx.current ().nodes) do
      if ctx.picked.nodes[n.id] then
        out[#out + 1] = n.id
      end
    end
    return out
  end

  ---Records a new document from a graph operation, or says why it could not.
  ---@param doc_after Shader.Doc?
  ---@param refusal any
  ---@param key? string
  ---@return boolean
  function ctx.commit (doc_after, refusal, key)
    if not doc_after then
      if type (refusal) == 'string' then
        ctx.refuse (refusal)
      end
      return false
    end
    docs.change (ctx.path, doc_after, key)
    return true
  end

  -- Adding ------------------------------------------------------------------------------------

  ---Adds a node at a point, and wires it to the output a wire was dropped from.
  ---@param type_id string
  ---@param at? NodeCanvas.Point
  ---@param from? { node: string, output: string, type: Shader.Type }
  ---@return string?
  function ctx.add_node (type_id, at, from)
    local x, y ---@type number, number
    if at then
      x, y = at.x, at.y
    else
      x, y = ctx.view_center ()
      x, y = x - view_m.NODE_W / 2, y - 40
    end
    local d, id = core.graph.add_node (ctx.current (), type_id, x, y)
    if not d then
      ctx.refuse (id)
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
    docs.change (ctx.path, d)
    ctx.set_picked ({ [id] = true })
    return id
  end

  ---Asks which node to add, then adds it.
  ---@param at? NodeCanvas.Point
  ---@param from? { node: string, output: string, type: Shader.Type }
  function ctx.ask_add (at, from)
    local picker = app.try_use ('picker')
    if not picker then
      return
    end
    local has_output = false
    for _, n in ipairs (ctx.current ().nodes) do
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
      placeholder = from and 'Add a node that takes this wire' or 'Add a node',
      on_pick = function (item)
        ctx.add_node (item.value, at, from)
      end,
    })
  end

  -- Copy and paste ----------------------------------------------------------------------------

  ---@return NodeCanvas.Box?
  local function picked_bounds ()
    local boxes = ctx.boxes (true)
    for _, f in ipairs (ctx.frames ()) do
      if ctx.picked.frames[f.id] then
        boxes[#boxes + 1] = { x = f.x, y = f.y, w = f.w, h = f.h }
      end
    end
    return nc.bounds (boxes)
  end

  ---@param fragment Shader.Fragment
  ---@param dx number
  ---@param dy number
  local function paste_at (fragment, dx, dy)
    local d, ids, frames = core.graph.paste (ctx.current (), fragment, dx, dy)
    if not d then
      ctx.refuse ('Nothing to paste.')
      return
    end
    docs.change (ctx.path, d)
    local nodes, picked_frames = {}, {} ---@type table<string, boolean>, table<string, boolean>
    for _, id in ipairs (ids) do
      nodes[id] = true
    end
    for _, id in ipairs (frames) do
      picked_frames[id] = true
    end
    ctx.set_picked (nodes, picked_frames)
  end

  ---Copies the picked nodes and frames. False when nothing is picked.
  ---@return boolean
  function ctx.copy ()
    local ids = ctx.picked_nodes ()
    local frames = sorted (ctx.picked.frames)
    if #ids == 0 and #frames == 0 then
      return false
    end
    clipboard = core.graph.copy_nodes (ctx.current (), ids, frames)
    clip_bounds = picked_bounds ()
    clip_path = ctx.path
    pasted = 0
    return true
  end

  ---@return boolean
  function ctx.can_paste ()
    return clipboard ~= nil
  end

  ---Pastes the copied nodes: just below and to the right of the nodes they copy while those
  ---are in view, and in the middle of the view otherwise.
  function ctx.paste ()
    local fragment, bounds = clipboard, clip_bounds
    if not fragment or not bounds then
      return
    end
    pasted = pasted + 1
    local seen = nc.seen (ctx.view, ctx.viewport:rect ())
    local dx = STEP * pasted ---@type number
    local dy = STEP * pasted ---@type number
    if clip_path ~= ctx.path or not nc.overlaps (seen, bounds) then
      dx = seen.x + seen.w / 2 - (bounds.x + bounds.w / 2)
      dy = seen.y + seen.h / 2 - (bounds.y + bounds.h / 2)
    end
    paste_at (fragment, dx, dy)
  end

  function ctx.cut ()
    if ctx.copy () then
      ctx.delete_picked ()
    end
  end

  ---Copies the picked nodes a little down and to the right, with the wires between them.
  function ctx.duplicate ()
    local ids = ctx.picked_nodes ()
    local frames = sorted (ctx.picked.frames)
    if #ids == 0 and #frames == 0 then
      return
    end
    paste_at (core.graph.copy_nodes (ctx.current (), ids, frames), STEP, STEP)
  end

  ---Removes the picked wire, or the picked nodes, frames and reroute points.
  function ctx.delete_picked ()
    local wire = ctx.selected_wire
    if wire then
      ctx.selected_wire = nil
      local to, input = wire:match ('^(.-)|(.*)$')
      if to then
        ctx.commit (core.graph.disconnect (ctx.current (), to, input))
      end
      return
    end
    if ctx.nothing_picked () then
      return
    end
    local d = ctx.current ()
    local ids = ctx.picked_nodes ()
    if #ids > 0 then
      d = core.graph.remove_nodes (d, ids) or d
    end
    local frames = {} ---@type Shader.Frame[]
    for _, f in ipairs (core.graph.frames (d)) do
      if not ctx.picked.frames[f.id] then
        frames[#frames + 1] = f
      end
    end
    local routes = core.graph.routes (d)
    local gone = {} ---@type table<string, table<integer, boolean>>
    for key in pairs (ctx.picked.points) do
      local wire_id, index = key:match ('^(.*)#(%d+)$')
      if wire_id then
        gone[wire_id] = gone[wire_id] or {}
        gone[wire_id][
          tonumber (index) --[[@as integer]]
        ] =
          true
      end
    end
    for wire_id, drop in pairs (gone) do
      local kept = {} ---@type { x: number, y: number }[]
      for i, p in ipairs (routes[wire_id] or {}) do
        if not drop[i] then
          kept[#kept + 1] = p
        end
      end
      routes[wire_id] = kept
    end
    docs.change (ctx.path, core.graph.with_canvas (d, frames, routes))
    ctx.set_picked ({})
  end

  function ctx.select_all ()
    local nodes, frames = {}, {} ---@type table<string, boolean>, table<string, boolean>
    for _, n in ipairs (ctx.current ().nodes) do
      nodes[n.id] = true
    end
    for _, f in ipairs (core.graph.frames (ctx.current ())) do
      frames[f.id] = true
    end
    ctx.set_picked (nodes, frames)
  end

  -- Moving ------------------------------------------------------------------------------------

  ---Puts nodes, frames and reroute points where a drag left them, as one change. With
  ---`insert`, the one node moved goes into that wire too.
  ---@param nodes table<string, NodeCanvas.Point>
  ---@param frames table<string, NodeCanvas.Box>
  ---@param points table<string, NodeCanvas.Point>
  ---@param insert? string
  function ctx.finish_move (nodes, frames, points, insert)
    local d = core.graph.move (ctx.current (), nodes)
    if next (frames) or next (points) then
      local list = {} ---@type Shader.Frame[]
      for i, f in ipairs (core.graph.frames (d)) do
        local box = frames[f.id]
        list[i] = box
            and {
              id = f.id,
              x = math.floor (box.x + 0.5),
              y = math.floor (box.y + 0.5),
              w = math.floor (box.w + 0.5),
              h = math.floor (box.h + 0.5),
              title = f.title,
              color = f.color,
            }
          or f
      end
      local routes = core.graph.routes (d)
      for key, p in pairs (points) do
        local wire_id, index = key:match ('^(.*)#(%d+)$')
        local route = wire_id and routes[wire_id]
        local i = tonumber (index)
        if route and i and route[i] then
          local copy = {} ---@type { x: number, y: number }[]
          for k, q in ipairs (route) do
            copy[k] = q
          end
          copy[i] = { x = math.floor (p.x + 0.5), y = math.floor (p.y + 0.5) }
          routes[wire_id] = copy
        end
      end
      d = core.graph.with_canvas (d, list, routes)
    end
    local id = next (nodes)
    if insert and id then
      d = core.graph.insert (d, id, insert) or d
    end
    docs.change (ctx.path, d)
  end

  ---Lines the picked nodes up on one edge.
  ---@param edge NodeCanvas.Edge
  function ctx.align (edge)
    docs.change (
      ctx.path,
      core.graph.move (ctx.current (), nc.align (ctx.boxes (true), edge))
    )
  end

  ---Spaces the picked nodes evenly.
  ---@param axis 'x'|'y'
  function ctx.distribute (axis)
    docs.change (
      ctx.path,
      core.graph.move (ctx.current (), nc.distribute (ctx.boxes (true), axis))
    )
  end

  local stop = nil ---@type fun()?

  ---Lines nodes up in columns, each right of the nodes it reads from, gliding them there.
  function ctx.tidy ()
    if stop then
      stop ()
      stop = nil
    end
    local d = ctx.current ()
    local ids = {} ---@type string[]
    for _, n in ipairs (d.nodes) do
      ids[#ids + 1] = n.id
    end
    local target = nc.layered_columns ({
      ids = ids,
      edges = d.edges,
      height = function (id)
        local n = ctx.node (id)
        return n and ctx.height (n) or view_m.HEAD_H
      end,
      width = view_m.NODE_W,
      column_gap = COLUMN_GAP,
      row_gap = ROW_GAP,
      origin = { x = 40, y = 40 },
      -- Within a column, nodes keep their order from top to bottom.
      before = function (a, b)
        local na, nb = ctx.node (a), ctx.node (b)
        if na and nb and na.y ~= nb.y then
          return na.y < nb.y
        end
        return a < b
      end,
    })
    local start = {} ---@type table<string, NodeCanvas.Point>
    local moving = {} ---@type table<string, boolean>
    for id in pairs (target) do
      local n = ctx.node (id)
      start[id] = n and ctx.position (n) or target[id]
      moving[id] = true
    end
    local began = app.util.now ()
    stop = app.timer.every (16, function ()
      local t = math.min (1, (app.util.now () - began) / TIDY_MS)
      for id, p in pairs (nc.between (start, target, nc.ease (t))) do
        ctx.live[id] = p
        ctx.place (id)
      end
      ctx.draw_wires (moving)
      if t >= 1 then
        if stop then
          stop ()
          stop = nil
        end
        ctx.live = {}
        docs.change (ctx.path, core.graph.move (ctx.current (), target))
        app.timer.after (30, ctx.fit)
      end
    end)
  end

  -- Frames and reroute points -----------------------------------------------------------------

  ---Adds a frame, picks it, and puts the cursor in its title.
  ---@param box NodeCanvas.Box
  function ctx.add_frame (box)
    local d = ctx.current ()
    local frames = {} ---@type Shader.Frame[]
    for i, f in ipairs (core.graph.frames (d)) do
      frames[i] = f
    end
    local id = core.graph.next_frame_id (frames)
    frames[#frames + 1] = {
      id = id,
      x = math.floor (box.x + 0.5),
      y = math.floor (box.y + 0.5),
      w = math.max (1, math.floor (box.w + 0.5)),
      h = math.max (1, math.floor (box.h + 0.5)),
      title = '',
    }
    docs.change (
      ctx.path,
      core.graph.with_canvas (d, frames, core.graph.routes (d))
    )
    ctx.set_picked ({}, { [id] = true })
    local title = ctx.frame_layer.title_el (id)
    if title then
      title:focus ()
    end
  end

  ---Puts a frame around the picked nodes.
  function ctx.frame_picked ()
    local box = nc.frame_around (ctx.boxes (true))
    if box then
      ctx.add_frame (box)
    end
  end

  ---@param id string
  ---@param title string
  function ctx.set_frame_title (id, title)
    local d = ctx.current ()
    local frames = {} ---@type Shader.Frame[]
    for i, f in ipairs (core.graph.frames (d)) do
      frames[i] = f
      if f.id == id then
        frames[i] = {
          id = f.id,
          x = f.x,
          y = f.y,
          w = f.w,
          h = f.h,
          title = title,
          color = f.color,
        }
      end
    end
    docs.change (
      ctx.path,
      core.graph.with_canvas (d, frames, core.graph.routes (d)),
      'frame-title:' .. id
    )
  end

  ---Adds a reroute point where a wire was double-clicked, and picks it.
  ---@param wire_id string
  ---@param x number World units.
  ---@param y number
  function ctx.add_point (wire_id, x, y)
    local e = ctx.wire (wire_id)
    if not e then
      return
    end
    local d = ctx.current ()
    local index = ctx.point_index (e, x, y)
    local routes = core.graph.routes (d)
    local list = {} ---@type { x: number, y: number }[]
    for i, p in ipairs (routes[wire_id] or {}) do
      list[i] = p
    end
    table.insert (
      list,
      index,
      { x = math.floor (x + 0.5), y = math.floor (y + 0.5) }
    )
    routes[wire_id] = list
    docs.change (
      ctx.path,
      core.graph.with_canvas (d, core.graph.frames (d), routes)
    )
    ctx.selected_wire = nil
    ctx.set_picked ({}, {}, { [nc.point_key (wire_id, index)] = true })
  end

  ---@param wire_id string
  ---@param index integer
  function ctx.remove_point (wire_id, index)
    local d = ctx.current ()
    local routes = core.graph.routes (d)
    local list = {} ---@type { x: number, y: number }[]
    for i, p in ipairs (routes[wire_id] or {}) do
      if i ~= index then
        list[#list + 1] = p
      end
    end
    routes[wire_id] = list
    docs.change (
      ctx.path,
      core.graph.with_canvas (d, core.graph.frames (d), routes)
    )
  end
end

return M
