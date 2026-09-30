-- daw.windows: the studio desktop, in the manner of FL Studio. The middle of the window is a
-- desktop, and each DAW screen is a window on it that can be dragged, resized, maximized,
-- rolled up to its title bar, or closed. Windows snap to the desktop's edges and to each
-- other. A button on the toolbar and a key, such as F5 for the Playlist, show or hide each
-- one, and the layout comes back the next time.
--
-- A screen adds its window with `daw.windows`. When the screen's plugin stops, its window
-- goes with it. A screen without this plugin falls back to the app's docks.

local SNAP = 8
local HEAD_H = 26
local MIN_W = 220
local MIN_H = 120

-- lang=css
local CSS = [[
.daw-desk {
  --win-bg: color-mix(in srgb, var(--bg) 86%, #7c8a99);
  --win-head: color-mix(in srgb, var(--bg-alt) 70%, #8795a3);
  --win-head-on: color-mix(in srgb, var(--bg-alt) 45%, #9fb0c0);
  --win-edge: color-mix(in srgb, var(--border) 60%, #000);
  --win-accent: #f0a030;
  position: relative;
  flex: 1;
  width: 100%;
  height: 100%;
  min-height: 0;
  overflow: hidden;
  background:
    radial-gradient(circle at 30% 20%, color-mix(in srgb, var(--bg) 88%, #5a6878), transparent 60%),
    color-mix(in srgb, var(--bg) 92%, #000);
  user-select: none;
}
.daw-desk-hint {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--fg-faint);
  font-size: 13px;
  pointer-events: none;
}
.daw-win {
  position: absolute;
  display: flex;
  flex-direction: column;
  min-width: 0;
  background: var(--win-bg);
  border: 1px solid var(--win-edge);
  border-radius: 4px;
  box-shadow: 0 6px 22px rgba(0, 0, 0, 0.45);
  overflow: hidden;
}
.daw-win.max {
  border-radius: 0;
  box-shadow: none;
}
.daw-win.shade {
  height: 26px !important;
}
.daw-win.shade .daw-win-body,
.daw-win.shade .daw-win-grip {
  display: none;
}
.daw-win-head {
  flex: none;
  height: 26px;
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 0 4px 0 8px;
  background: var(--win-head);
  border-bottom: 1px solid var(--win-edge);
  color: var(--fg-muted);
  font-size: 12px;
  font-weight: 600;
  cursor: default;
}
.daw-win.on .daw-win-head {
  background: var(--win-head-on);
  color: var(--fg);
}
.daw-win.on .daw-win-head .daw-win-icon {
  color: var(--win-accent);
}
.daw-win-title {
  flex: 1;
  min-width: 0;
  overflow: hidden;
  white-space: nowrap;
  text-overflow: ellipsis;
}
.daw-win-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 20px;
  height: 18px;
  padding: 0;
  border: none;
  border-radius: 3px;
  background: transparent;
  color: inherit;
  cursor: pointer;
}
.daw-win-btn:hover {
  background: rgba(255, 255, 255, 0.12);
}
.daw-win-btn.close:hover {
  background: #c0392b;
  color: #fff;
}
.daw-win-body {
  flex: 1;
  min-height: 0;
  display: flex;
  flex-direction: column;
  overflow: hidden;
  background: var(--bg);
}
.daw-win-body > * {
  flex: 1;
  min-height: 0;
}
.daw-win-grip {
  position: absolute;
  z-index: 2;
}
.daw-win-grip.r { top: 26px; right: 0; bottom: 8px; width: 5px; cursor: ew-resize; }
.daw-win-grip.l { top: 26px; left: 0; bottom: 8px; width: 5px; cursor: ew-resize; }
.daw-win-grip.b { left: 8px; right: 8px; bottom: 0; height: 5px; cursor: ns-resize; }
.daw-win-grip.rb { right: 0; bottom: 0; width: 12px; height: 12px; cursor: nwse-resize; }
.daw-win-grip.lb { left: 0; bottom: 0; width: 12px; height: 12px; cursor: nesw-resize; }
.daw-win.max .daw-win-grip {
  display: none;
}
.daw-winbar {
  display: flex;
  align-items: center;
  gap: 2px;
  padding: 0 4px;
}
.daw-winbar-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 28px;
  height: 24px;
  padding: 0;
  border: 1px solid transparent;
  border-radius: 4px;
  background: transparent;
  color: var(--fg-muted);
  cursor: pointer;
}
.daw-winbar-btn:hover {
  background: var(--bg-hover, rgba(255, 255, 255, 0.08));
  color: var(--fg);
}
.daw-winbar-btn.on {
  color: #f0a030;
  border-color: color-mix(in srgb, #f0a030 45%, transparent);
  background: color-mix(in srgb, #f0a030 12%, transparent);
}
]]

---Where a window sits, as the store keeps it.
---@class Daw.WindowPlace
---@field x number
---@field y number
---@field w number
---@field h number
---@field open boolean
---@field max boolean
---@field shade boolean
---@field z number Its place in the stack, higher in front.

---@class Daw.WindowRecord
---@field spec Daw.WindowSpec
---@field owner string
---@field el Proteus.El
---@field title_el Proteus.El
---@field button Proteus.El
---@field place Daw.WindowPlace
---@field fresh boolean True until the user moves it, so it follows the spec's layout.

---@param v any
---@param fallback number
---@return number
local function num (v, fallback)
  local n = tonumber (v)
  if n == nil or n ~= n then
    return fallback
  end
  return n
end

---@type Proteus.Plugin
return {
  name = 'DAW windows',
  description = 'The DAW as a desktop of floating windows, in the manner of FL Studio: drag, resize, maximize, and a key for each.',
  version = '1.0.0',
  requires = { proteus = '>=0.2.0', features = { 'permissions' } },
  permissions = {},
  depends = { 'lib.ui', 'core.commands' },
  optional = { 'ui.tabs', 'ui.toolbar', 'core.keys' },
  activate = function (app)
    local ui = app.use ('ui')
    local shell = app.use ('shell')
    local commands = app.use ('commands')
    local tabs = app.try_use ('tabs')
    local toolbar = app.try_use ('toolbar')
    ui.css (CSS)

    local stored = app.store.get ('layout', {})
    local saved = type (stored) == 'table' and stored or {} ---@type table<string, table>
    local wins = {} ---@type table<string, Daw.WindowRecord>
    local focused = nil ---@type string?
    local top = 10
    local settle_soon ---@type fun()

    local hint = ui.div ({
      class = 'daw-desk-hint',
      'Every window is closed. Open one from the toolbar, or with F5 to F9.',
    })
    local desk = ui.div ({ class = 'daw-desk', hint })
    local bar = ui.div ({ class = 'daw-winbar' })

    -- Layout -------------------------------------------------------------------------------

    ---@return number w
    ---@return number h
    local function desk_size ()
      local r = desk:rect ()
      local w = r and r.w or 0
      local h = r and r.h or 0
      if w < 50 or h < 50 then
        return 1200, 700
      end
      return w, h
    end

    local save_pending = false
    local function save_soon ()
      if save_pending then
        return
      end
      save_pending = true
      app.timer.after (300, function ()
        save_pending = false
        local out = {} ---@type table<string, Daw.WindowPlace>
        for id, win in pairs (wins) do
          out[id] = win.place
        end
        -- Windows of plugins that are off now keep their place for later.
        for id, place in pairs (saved) do
          if not out[id] then
            out[id] = place --[[@as Daw.WindowPlace]]
          end
        end
        app.store.set ('layout', out)
      end)
    end

    ---Keeps a window's title bar on the desktop, and its size within reason.
    ---@param p Daw.WindowPlace
    local function clamp (p)
      local dw, dh = desk_size ()
      p.w = math.max (MIN_W, math.min (p.w, dw))
      p.h = math.max (MIN_H, math.min (p.h, dh))
      p.x = math.max (60 - p.w, math.min (p.x, dw - 60))
      p.y = math.max (0, math.min (p.y, dh - HEAD_H))
    end

    ---A spec's number as pixels: a value from 0 to 1 is a share of the desktop.
    ---@param v any
    ---@param size number
    ---@param fallback number
    ---@return number
    local function measure (v, size, fallback)
      local n = num (v, fallback)
      if n > 0 and n <= 1 then
        return math.floor (n * size)
      end
      return n
    end

    ---Where a window first sits, from its spec and the desktop's size now.
    ---@param spec Daw.WindowSpec
    ---@return Daw.WindowPlace
    local function default_place (spec)
      local dw, dh = desk_size ()
      ---@type Daw.WindowPlace
      local p = {
        x = measure (spec.x, dw, 40),
        y = measure (spec.y, dh, 40),
        w = measure (spec.w, dw, 0.6),
        h = measure (spec.h, dh, 0.6),
        open = spec.open == true,
        max = false,
        shade = false,
        z = num (spec.z, 0),
      }
      return p
    end

    ---Moves and shrinks a window so all of it shows, where the desktop is big enough.
    ---@param p Daw.WindowPlace
    local function fit (p)
      local dw, dh = desk_size ()
      p.w = math.min (p.w, dw)
      p.h = math.min (p.h, dh)
      p.x = math.max (0, math.min (p.x, dw - p.w))
      p.y = math.max (0, math.min (p.y, dh - p.h))
    end

    ---@param win Daw.WindowRecord
    local function place (win)
      local p = win.place
      if p.max then
        win.el:style ('left', '0')
        win.el:style ('top', '0')
        win.el:style ('width', '100%')
        win.el:style ('height', '100%')
      else
        win.el:style ('left', p.x .. 'px')
        win.el:style ('top', p.y .. 'px')
        win.el:style ('width', p.w .. 'px')
        win.el:style ('height', p.h .. 'px')
      end
      win.el:class ('max', p.max)
      win.el:class ('shade', p.shade and not p.max)
    end

    local function show_hint ()
      local any = false
      for _, win in pairs (wins) do
        any = any or win.place.open
      end
      hint:show (not any)
    end

    ---@param id string
    local function focus (id)
      local win = wins[id]
      if not win then
        return
      end
      if focused and wins[focused] and focused ~= id then
        wins[focused].el:class ('on', false)
      end
      focused = id
      top = top + 1
      win.place.z = top
      win.el:style ('z-index', tostring (top))
      win.el:class ('on', true)
    end

    ---@param id string
    ---@param open boolean
    local function set_open (id, open)
      local win = wins[id]
      if not win then
        return
      end
      win.place.open = open
      win.el:show (open)
      win.button:class ('on', open)
      if open then
        if win.place.shade then
          win.place.shade = false
          place (win)
        end
        focus (id)
        if win.spec.on_show then
          win.spec.on_show ()
        end
      end
      show_hint ()
      save_soon ()
      app.emit ('daw:window', id, open)
    end

    ---Like FL Studio: a window open behind others comes to the front, and one in front
    ---closes.
    ---@param id string
    local function press (id)
      local win = wins[id]
      if not win then
        return
      end
      if win.place.open and focused ~= id then
        focus (id)
      else
        set_open (id, not win.place.open)
      end
    end

    -- Snapping -----------------------------------------------------------------------------

    ---Edges a moving window snaps to: the desktop's, and every other open window's.
    ---@param self_id string
    ---@return number[] xs
    ---@return number[] ys
    local function edges (self_id)
      local dw, dh = desk_size ()
      local xs, ys = { 0, dw }, { 0, dh }
      for id, win in pairs (wins) do
        local p = win.place
        if id ~= self_id and p.open and not p.max then
          xs[#xs + 1] = p.x
          xs[#xs + 1] = p.x + p.w
          ys[#ys + 1] = p.y
          ys[#ys + 1] = p.y + (p.shade and HEAD_H or p.h)
        end
      end
      return xs, ys
    end

    ---Moves `pos` onto an edge within reach, trying both of the window's sides.
    ---@param pos number
    ---@param size number
    ---@param list number[]
    ---@return number
    local function snap_to (pos, size, list)
      local best = pos ---@type number
      local dist = SNAP + 1 ---@type number
      for _, e in ipairs (list) do
        if math.abs (pos - e) < dist then
          best, dist = e, math.abs (pos - e)
        end
        if math.abs (pos + size - e) < dist then
          best, dist = e - size, math.abs (pos + size - e)
        end
      end
      return best
    end

    ---@param on_move fun(ev: Proteus.DomEvent)
    ---@param on_up fun()
    local function follow (on_move, on_up)
      local off_move, off_up ---@type fun(), fun()
      off_move = app.dom.on_global ('mousemove', function (mv)
        on_move (mv)
        return nil
      end)
      off_up = app.dom.on_global ('mouseup', function ()
        off_move ()
        off_up ()
        on_up ()
        return nil
      end)
    end

    ---@param win Daw.WindowRecord
    ---@param ev Proteus.DomEvent
    local function drag (win, ev)
      local p = win.place
      if p.max then
        return
      end
      local x0, y0, px, py = ev.x or 0, ev.y or 0, p.x, p.y
      local xs, ys = edges (win.spec.id)
      follow (function (mv)
        local x = px + (mv.x or 0) - x0
        local y = py + (mv.y or 0) - y0
        if not mv.alt then
          x = snap_to (x, p.w, xs)
          y = snap_to (y, p.shade and HEAD_H or p.h, ys)
        end
        p.x, p.y = x, y
        win.fresh = false
        clamp (p)
        win.el:style ('left', p.x .. 'px')
        win.el:style ('top', p.y .. 'px')
      end, save_soon)
    end

    ---@param win Daw.WindowRecord
    ---@param ev Proteus.DomEvent
    ---@param side string Some of l, r and b.
    local function resize (win, ev, side)
      local p = win.place
      local x0, y0 = ev.x or 0, ev.y or 0
      local sx, sw, sh = p.x, p.w, p.h
      local xs, ys = edges (win.spec.id)
      local min_w = win.spec.min_w or MIN_W
      local min_h = win.spec.min_h or MIN_H
      follow (function (mv)
        win.fresh = false
        local dx, dy = (mv.x or 0) - x0, (mv.y or 0) - y0
        if side:find ('r') then
          local right = sx + sw + dx
          if not mv.alt then
            right = snap_to (right, 0, xs)
          end
          p.w = math.max (min_w, right - sx)
        elseif side:find ('l') then
          local left = sx + dx
          if not mv.alt then
            left = snap_to (left, 0, xs)
          end
          left = math.min (left, sx + sw - min_w)
          p.x, p.w = left, sx + sw - left
        end
        if side:find ('b') then
          local bottom = p.y + sh + dy
          if not mv.alt then
            bottom = snap_to (bottom, 0, ys)
          end
          p.h = math.max (min_h, bottom - p.y)
        end
        place (win)
      end, save_soon)
    end

    -- Windows ------------------------------------------------------------------------------

    ---@param id string
    local function remove (id)
      local win = wins[id]
      if not win then
        return
      end
      saved[id] = win.place
      win.el:remove ()
      win.button:remove ()
      wins[id] = nil
      commands.unregister (
        'daw.window_' .. id:gsub ('^daw%.', ''):gsub ('[^%w_]', '_')
      )
      if focused == id then
        focused = nil
      end
      show_hint ()
    end

    ---Lays out the windows the user never moved, now that the desktop has its size, fits
    ---every window inside it, and stacks them as they were, the front one focused.
    local function settle ()
      local list = {} ---@type Daw.WindowRecord[]
      for _, win in pairs (wins) do
        if win.fresh then
          -- Only where it sits: whether it is open, maximized or rolled up stays.
          local d = default_place (win.spec)
          local p = win.place
          p.x, p.y, p.w, p.h = d.x, d.y, d.w, d.h
        end
        if not win.place.max then
          fit (win.place)
        end
        place (win)
        list[#list + 1] = win
      end
      table.sort (list, function (a, b)
        return a.place.z < b.place.z
      end)
      for _, win in ipairs (list) do
        if win.place.open then
          focus (win.spec.id)
        end
      end
    end

    local settle_pending = false
    settle_soon = function ()
      if settle_pending then
        return
      end
      settle_pending = true
      app.timer.after (60, function ()
        settle_pending = false
        settle ()
      end)
    end

    ---@param owner string
    ---@param spec Daw.WindowSpec
    local function add (owner, spec)
      if type (spec) ~= 'table' or type (spec.id) ~= 'string' then
        error ('daw.windows: a window needs an id', 3)
      end
      remove (spec.id)
      local id = spec.id
      local old = saved[id]
      local p = default_place (spec)
      if type (old) == 'table' then
        p = {
          x = num (old.x, p.x),
          y = num (old.y, p.y),
          w = num (old.w, p.w),
          h = num (old.h, p.h),
          open = old.open == true,
          max = old.max == true,
          shade = old.shade == true,
          z = num (old.z, p.z),
        }
      end
      clamp (p)

      local title_el = ui.span ({ class = 'daw-win-title', spec.title or id })
      local head = ui.div ({
        class = 'daw-win-head',
        ui.span ({
          class = 'daw-win-icon',
          ui.icon (spec.icon or 'app-window', 13),
        }),
        title_el,
        ui.h ('button', {
          class = 'daw-win-btn',
          title = 'Roll up to the title bar',
          attrs = { ['data-item'] = 'shade' },
          ui.icon ('chevrons-up', 13),
        }),
        ui.h ('button', {
          class = 'daw-win-btn',
          title = 'Maximize (double-click the title)',
          attrs = { ['data-item'] = 'max' },
          ui.icon ('maximize-2', 12),
        }),
        ui.h ('button', {
          class = 'daw-win-btn close',
          title = 'Close',
          attrs = { ['data-item'] = 'close' },
          ui.icon ('x', 13),
        }),
      })
      local body = ui.div ({ class = 'daw-win-body', spec.content })
      local el = ui.div ({
        class = 'daw-win',
        attrs = { ['data-win'] = id },
        head,
        body,
        ui.div ({
          class = 'daw-win-grip r',
          attrs = { ['data-item'] = 'grip:r' },
        }),
        ui.div ({
          class = 'daw-win-grip l',
          attrs = { ['data-item'] = 'grip:l' },
        }),
        ui.div ({
          class = 'daw-win-grip b',
          attrs = { ['data-item'] = 'grip:b' },
        }),
        ui.div ({
          class = 'daw-win-grip rb',
          attrs = { ['data-item'] = 'grip:rb' },
        }),
        ui.div ({
          class = 'daw-win-grip lb',
          attrs = { ['data-item'] = 'grip:lb' },
        }),
      })
      local button = ui.h ('button', {
        class = 'daw-winbar-btn',
        title = (spec.title or id)
          .. (spec.key and (' (' .. spec.key:upper () .. ')') or ''),
        ui.icon (spec.icon or 'app-window', 15),
      })

      ---@type Daw.WindowRecord
      local win = {
        spec = spec,
        owner = owner,
        el = el,
        title_el = title_el,
        button = button,
        place = p,
        fresh = type (old) ~= 'table',
      }
      wins[id] = win

      el:on ('mousedown', function (ev)
        focus (id)
        local item = ev.item or ''
        local side = item:match ('^grip:(%a+)$')
        if side and ev.button == 0 then
          resize (win, ev, side)
          return 'stop'
        end
        return nil
      end)
      head:on ('mousedown', function (ev)
        if ev.button == 0 and (ev.item == nil or ev.item == '') then
          drag (win, ev)
        end
        return nil
      end)
      head:on ('dblclick', function (ev)
        if ev.item == nil or ev.item == '' then
          p.max = not p.max
          win.fresh = false
          place (win)
          focus (id)
          save_soon ()
        end
        return nil
      end)
      head:on ('click', function (ev)
        if ev.item == 'close' then
          set_open (id, false)
        elseif ev.item == 'max' then
          p.max = not p.max
          win.fresh = false
          place (win)
          save_soon ()
        elseif ev.item == 'shade' then
          p.shade = not p.shade
          win.fresh = false
          place (win)
          save_soon ()
        end
        return nil
      end)
      button:on ('click', function ()
        press (id)
        return nil
      end)

      place (win)
      el:style ('z-index', tostring (p.z))
      el:show (p.open)
      button:class ('on', p.open)
      desk:append (el)

      -- The toolbar keeps the windows in the order their screens ask for.
      local after = nil ---@type Daw.WindowRecord?
      for _, other in pairs (wins) do
        if
          other ~= win
          and (other.spec.order or 50) > (spec.order or 50)
          and (
            after == nil
            or (other.spec.order or 50) < (after.spec.order or 50)
          )
        then
          after = other
        end
      end
      if after then
        bar:insert_before (button, after.button)
      else
        bar:append (button)
      end

      commands.register ({
        id = 'daw.window_' .. id:gsub ('^daw%.', ''):gsub ('[^%w_]', '_'),
        category = 'DAW',
        title = 'Show or Hide ' .. (spec.title or id),
        icon = spec.icon,
        key = spec.key,
        menu = 'View',
        group = '0',
        run = function ()
          press (id)
        end,
      })
      if p.open and spec.on_show then
        spec.on_show ()
      end
      show_hint ()
      settle_soon ()
    end

    -- The desktop ------------------------------------------------------------------------------

    if tabs then
      tabs.open ({
        id = 'daw.windows',
        title = 'Studio',
        icon = 'layout-dashboard',
        content = desk,
        closable = false,
      })
    else
      shell.mount ('main', desk)
    end
    if toolbar then
      toolbar.add (bar, { align = 'right', order = 40 })
    end
    app.dom.on_global ('resize', function ()
      settle_soon ()
      return nil
    end)

    commands.register ({
      id = 'daw.windows_reset',
      category = 'DAW',
      title = 'Reset the Window Layout',
      icon = 'layout-dashboard',
      menu = 'View',
      group = '1',
      run = function ()
        for _, win in pairs (wins) do
          win.place = default_place (win.spec)
          win.fresh = true
          fit (win.place)
          place (win)
          win.el:show (win.place.open)
          win.button:class ('on', win.place.open)
        end
        show_hint ()
        settle_soon ()
        save_soon ()
      end,
    })

    app.provide_scoped ('daw.windows', function (consumer)
      ---@type Daw.Windows
      local service = {
        add = function (spec)
          add (consumer.id, spec)
          consumer.dispose (function ()
            local win = wins[spec.id]
            if win and win.owner == consumer.id then
              remove (spec.id)
            end
          end)
        end,
        show = function (id)
          if wins[id] then
            set_open (id, true)
          end
        end,
        hide = function (id)
          set_open (id, false)
        end,
        toggle = function (id)
          local win = wins[id]
          if win then
            set_open (id, not win.place.open)
          end
        end,
        is_open = function (id)
          local win = wins[id]
          return win ~= nil and win.place.open
        end,
        set_title = function (id, title)
          local win = wins[id]
          if win then
            win.title_el:text (title)
          end
        end,
      }
      return service
    end)
  end,
}
