-- The shader canvas's commands, which act on the shader in front, and each canvas's
-- right-click menu. A shortcut never fires while the user types in a field.

local html_m = require ('node_html')

local M = {}

---@type { id: string, title: string, edge: NodeCanvas.Edge }[]
local ALIGN = {
  { id = 'shader.align_left', title = 'Align Left Edges', edge = 'left' },
  { id = 'shader.align_center', title = 'Align Centres', edge = 'center' },
  { id = 'shader.align_right', title = 'Align Right Edges', edge = 'right' },
  { id = 'shader.align_top', title = 'Align Tops', edge = 'top' },
  { id = 'shader.align_middle', title = 'Align Middles', edge = 'middle' },
  { id = 'shader.align_bottom', title = 'Align Bottoms', edge = 'bottom' },
}

---@param ctx ShaderCanvas.Ctx
---@return integer
local function picked_nodes (ctx)
  local n = 0
  for _ in pairs (ctx.picked.nodes) do
    n = n + 1
  end
  return n
end

---The made node picked, when it is the only node picked.
---@param ctx ShaderCanvas.Ctx
---@return string?
local function made_picked (ctx)
  local ids = ctx.picked_nodes ()
  local n = #ids == 1 and ctx.node (ids[1])
  if n and ctx.core.graph.subgraph_id (n.type) then
    return n.id
  end
  return nil
end

---Finds a node or a frame by name, then picks it and brings it into view.
---@param ctx ShaderCanvas.Ctx
local function find (ctx)
  local picker = ctx.app.try_use ('picker')
  if not picker then
    return
  end
  local items = {} ---@type Proteus.PickItem[]
  for _, n in ipairs (ctx.current ().nodes) do
    local def = ctx.catalog.get (n.type)
    local title = def and def.title or n.type
    local name = ''
    if n.type == 'parameter' and def then
      name = tostring (ctx.catalog.setting (def, n.settings, 'name') or '')
    end
    items[#items + 1] = {
      label = name ~= '' and name or title,
      detail = title .. '  ·  ' .. n.id,
      value = 'node:' .. n.id,
      search = name .. ' ' .. title .. ' ' .. n.type .. ' ' .. n.id,
    }
  end
  for _, f in ipairs (ctx.frames ()) do
    items[#items + 1] = {
      label = f.title ~= '' and f.title or 'Frame',
      detail = 'Frame',
      value = 'frame:' .. f.id,
    }
  end
  picker.pick ({
    placeholder = 'Go to a node. Type to search.',
    items = items,
    on_pick = function (item)
      local kind, id = tostring (item.value):match ('^(%a+):(.+)$')
      if kind == 'node' and id then
        ctx.set_picked ({ [id] = true })
        ctx.center_on (id)
      elseif kind == 'frame' and id then
        ctx.set_picked ({}, { [id] = true })
        local box = ctx.frame_box (id)
        if box then
          ctx.set_view (
            ctx.nc.center_on (
              ctx.view,
              ctx.viewport:rect (),
              box.x + box.w / 2,
              box.y + box.h / 2
            )
          )
        end
      end
    end,
  })
end

---Registers the commands, which act on the shader in front.
---@param app Proteus.App
---@param commands Proteus.Commands
---@param front fun(): ShaderCanvas.Ctx?
---@param toggle_snap fun()
function M.register (app, commands, front, toggle_snap)
  ---@return boolean
  local function in_front ()
    return front () ~= nil
  end

  ---True when a shader is in front and nobody types in a field.
  ---@return boolean
  local function canvas_keys ()
    return front () ~= nil and not app.dom.focus_info ().editable
  end

  ---A command that runs `fn` with the canvas in front.
  ---@param spec { id: string, title: string, icon: string, key?: string|string[], when?: fun(ctx: ShaderCanvas.Ctx): boolean, menu?: boolean }
  ---@param fn fun(ctx: ShaderCanvas.Ctx)
  local function command (spec, fn)
    commands.register ({
      id = spec.id,
      category = 'Shader',
      title = spec.title,
      menu = spec.menu ~= false and 'Graph' or nil,
      icon = spec.icon,
      key = spec.key,
      when = function ()
        local ctx = front ()
        if not ctx or app.dom.focus_info ().editable then
          return false
        end
        return not spec.when or spec.when (ctx)
      end,
      run = function ()
        local ctx = front ()
        if ctx then
          fn (ctx)
        end
      end,
    })
  end

  commands.register ({
    id = 'shader.add_node',
    category = 'Shader',
    title = 'Add Node...',
    menu = 'Graph',
    icon = 'plus',
    key = 'ctrl+k',
    when = canvas_keys,
    run = function ()
      local ctx = front ()
      if ctx then
        ctx.ask_add ()
      end
    end,
  })
  command ({
    id = 'shader.delete_selection',
    title = 'Delete Selected Nodes',
    icon = 'trash-2',
    key = { 'delete', 'backspace' },
  }, function (ctx)
    ctx.delete_picked ()
  end)
  command ({
    id = 'shader.duplicate',
    title = 'Duplicate Selected Nodes',
    icon = 'copy',
    key = 'ctrl+d',
  }, function (ctx)
    ctx.duplicate ()
  end)
  command ({
    id = 'shader.copy',
    title = 'Copy Nodes',
    icon = 'copy',
    key = 'ctrl+c',
    when = function (ctx)
      return not ctx.nothing_picked ()
    end,
  }, function (ctx)
    ctx.copy ()
  end)
  command ({
    id = 'shader.cut',
    title = 'Cut Nodes',
    icon = 'scissors',
    key = 'ctrl+x',
    when = function (ctx)
      return not ctx.nothing_picked ()
    end,
  }, function (ctx)
    ctx.cut ()
  end)
  command ({
    id = 'shader.paste',
    title = 'Paste Nodes',
    icon = 'clipboard-paste',
    key = 'ctrl+v',
    when = function (ctx)
      return ctx.can_paste ()
    end,
  }, function (ctx)
    ctx.paste ()
  end)
  command ({
    id = 'shader.select_all',
    title = 'Select All Nodes',
    icon = 'box-select',
    key = 'ctrl+a',
  }, function (ctx)
    ctx.select_all ()
  end)
  command ({
    id = 'shader.find',
    title = 'Go to Node...',
    icon = 'search',
    key = 'ctrl+f',
  }, find)
  command ({
    id = 'shader.make_node',
    title = 'Make a Node from the Selected Nodes...',
    icon = 'boxes',
    when = function (ctx)
      return picked_nodes (ctx) > 0
    end,
  }, function (ctx)
    ctx.ask_make_node ()
  end)
  command ({
    id = 'shader.unpack_node',
    title = 'Unpack the Selected Made Node',
    icon = 'ungroup',
    when = function (ctx)
      return made_picked (ctx) ~= nil
    end,
  }, function (ctx)
    local id = made_picked (ctx)
    if id then
      ctx.unpack_node (id)
    end
  end)
  command ({
    id = 'shader.frame',
    title = 'Frame the Selected Nodes',
    icon = 'square-dashed',
    when = function (ctx)
      return picked_nodes (ctx) > 0
    end,
  }, function (ctx)
    ctx.frame_picked ()
  end)
  for _, a in ipairs (ALIGN) do
    command ({
      id = a.id,
      title = a.title,
      icon = 'align-left',
      menu = false,
      when = function (ctx)
        return picked_nodes (ctx) > 1
      end,
    }, function (ctx)
      ctx.align (a.edge)
    end)
  end
  command ({
    id = 'shader.distribute_x',
    title = 'Space Evenly Across',
    icon = 'align-horizontal-space-around',
    menu = false,
    when = function (ctx)
      return picked_nodes (ctx) > 2
    end,
  }, function (ctx)
    ctx.distribute ('x')
  end)
  command ({
    id = 'shader.distribute_y',
    title = 'Space Evenly Down',
    icon = 'align-vertical-space-around',
    menu = false,
    when = function (ctx)
      return picked_nodes (ctx) > 2
    end,
  }, function (ctx)
    ctx.distribute ('y')
  end)
  commands.register ({
    id = 'shader.tidy',
    category = 'Shader',
    title = 'Tidy Up',
    menu = 'Graph',
    icon = 'layout-grid',
    when = in_front,
    run = function ()
      local ctx = front ()
      if ctx then
        ctx.tidy ()
      end
    end,
  })
  command ({
    id = 'shader.fit',
    title = 'Zoom to Fit',
    icon = 'scan',
    key = 'shift+1',
  }, function (ctx)
    ctx.fit ()
  end)
  commands.register ({
    id = 'shader.snap',
    category = 'Shader',
    title = 'Snap to Grid',
    menu = 'Graph',
    icon = 'grid-3x3',
    run = toggle_snap,
  })
end

---Adds the right-click menu to one canvas.
---@param ctx ShaderCanvas.Ctx
---@param menus Proteus.Menus
function M.menu (ctx, menus)
  local split = html_m.split
  menus.attach (ctx.viewport, function (ev)
    local item = ev.item and split (ev.item) or {}
    local id = item[1]
    local wx, wy = ctx.to_world (ev.x or 0, ev.y or 0)
    if id == '#w' then
      local wire = item[2] .. '|' .. (item[3] or '')
      local to, input = item[2], item[3] or ''
      return {
        {
          label = 'Add Reroute Point',
          icon = 'git-commit-horizontal',
          run = function ()
            ctx.add_point (wire, wx, wy)
          end,
        },
        {
          label = 'Remove Wire',
          icon = 'unlink',
          danger = true,
          run = function ()
            ctx.commit (ctx.core.graph.disconnect (ctx.current (), to, input))
          end,
        },
      }
    end
    if id == '#p' then
      local index = tonumber (item[2]) --[[@as integer?]]
      local wire = (item[3] or '') .. '|' .. (item[4] or '')
      return {
        {
          label = 'Remove Reroute Point',
          icon = 'x',
          danger = true,
          run = function ()
            if index then
              ctx.remove_point (wire, index)
            end
          end,
        },
      }
    end
    if id == '#f' and item[3] ~= 'frame-body' then
      local frame = item[2]
      if not ctx.picked.frames[frame] then
        ctx.set_picked ({}, { [frame] = true })
      end
      return {
        {
          label = 'Rename Frame',
          icon = 'pencil',
          run = function ()
            local title = ctx.frame_layer.title_el (frame)
            if title then
              title:focus ():select ()
            end
          end,
        },
        { separator = true },
        {
          label = 'Delete Frame',
          icon = 'trash-2',
          danger = true,
          run = ctx.delete_picked,
        },
      }
    end
    if id and id ~= '#f' and ctx.node (id) then
      if not ctx.picked.nodes[id] then
        ctx.set_picked ({ [id] = true })
      end
      local items = {
        {
          label = 'Duplicate',
          icon = 'copy',
          key = 'Ctrl+D',
          run = ctx.duplicate,
        },
        {
          label = 'Copy',
          icon = 'copy',
          key = 'Ctrl+C',
          run = function ()
            ctx.copy ()
          end,
        },
        {
          label = 'Put in a Frame',
          icon = 'square-dashed',
          run = ctx.frame_picked,
        },
        {
          label = 'Make a Node from These...',
          icon = 'boxes',
          run = ctx.ask_make_node,
        },
        {
          label = 'Show Its Code',
          icon = 'code',
          run = function ()
            ctx.commands.run ('shader.show_code')
          end,
        },
      } ---@type Proteus.MenuItem[]
      if made_picked (ctx) then
        items[#items + 1] = {
          label = 'Unpack',
          icon = 'ungroup',
          run = function ()
            ctx.unpack_node (id)
          end,
        }
        items[#items + 1] = {
          label = 'Rename Made Node...',
          icon = 'pencil',
          run = function ()
            ctx.ask_rename_node (id)
          end,
        }
      end
      if picked_nodes (ctx) > 1 then
        items[#items + 1] = { separator = true }
        for _, a in ipairs (ALIGN) do
          items[#items + 1] = {
            label = a.title,
            run = function ()
              ctx.align (a.edge)
            end,
          }
        end
      end
      items[#items + 1] = { separator = true }
      items[#items + 1] = {
        label = 'Delete',
        icon = 'trash-2',
        danger = true,
        key = 'Delete',
        run = ctx.delete_picked,
      }
      return items
    end
    return {
      {
        label = 'Add Node...',
        icon = 'plus',
        run = function ()
          ctx.ask_add ({ x = wx - 116, y = wy - 20 })
        end,
      },
      {
        label = 'Add a Frame Here',
        icon = 'square-dashed',
        run = function ()
          ctx.add_frame ({ x = wx, y = wy, w = 320, h = 200 })
        end,
      },
      {
        label = 'Paste',
        icon = 'clipboard-paste',
        key = 'Ctrl+V',
        disabled = not ctx.can_paste (),
        run = ctx.paste,
      },
      { separator = true },
      { label = 'Select All', icon = 'box-select', run = ctx.select_all },
      {
        label = 'Go to Node...',
        icon = 'search',
        run = function ()
          find (ctx)
        end,
      },
      { label = 'Tidy Up', icon = 'layout-grid', run = ctx.tidy },
      { label = 'Zoom to Fit', icon = 'scan', run = ctx.fit },
    }
  end)
end

return M
