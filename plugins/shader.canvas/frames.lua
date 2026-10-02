-- Frames on one shader canvas: titled boxes behind the nodes, which group them and move them
-- together. The document keeps them beside its nodes, and the compiler never reads them.

local M = {}

-- The smallest a frame gets when it is sized by hand.
M.MIN_W = 120
M.MIN_H = 70

---@param ctx ShaderCanvas.Ctx
function M.attach (ctx)
  local core = ctx.core

  ctx.frame_layer = ctx.nc.frame_layer ({
    ui = ctx.ui,
    layer = ctx.frames_el,
    mark = function (el, part, id)
      el:attr ('data-item', '#f|' .. id .. '|' .. part)
    end,
    on_title = function (id, title)
      ctx.set_frame_title (id, title)
    end,
  })

  ---The frames, each where it is during a drag.
  ---@return Shader.Frame[]
  function ctx.frames ()
    local out = {} ---@type Shader.Frame[]
    for _, f in ipairs (core.graph.frames (ctx.current ())) do
      local live = ctx.live_frames[f.id]
      if live then
        out[#out + 1] = {
          id = f.id,
          x = live.x,
          y = live.y,
          w = live.w,
          h = live.h,
          title = f.title,
          color = f.color,
        }
      else
        out[#out + 1] = f
      end
    end
    return out
  end

  ---@param id string
  ---@return NodeCanvas.Box?
  function ctx.frame_box (id)
    for _, f in ipairs (ctx.frames ()) do
      if f.id == id then
        return { id = f.id, x = f.x, y = f.y, w = f.w, h = f.h }
      end
    end
    return nil
  end

  function ctx.draw_frames ()
    ctx.frame_layer.draw (
      ctx.frames (),
      ctx.picked.frames,
      ctx.app.dom.active ()
    )
  end

  ---Moves only the frames being dragged.
  ---@param ids table<string, boolean>
  function ctx.place_frames (ids)
    for _, f in ipairs (ctx.frames ()) do
      if ids[f.id] then
        ctx.frame_layer.place (f)
      end
    end
  end
end

return M
