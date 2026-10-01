-- sheet_panel_pop: what the Sheet app's toolbar and panels share, and its small pop-ups.
--
-- `env` gives both parts one table for a controller: the services, the pop-up in view, and
-- choices that last while the app runs, such as the border line last picked. A pop-up floats
-- in the app's root element, sits next to a button or a cell, stays inside the window, and
-- closes on Escape or a click outside it. The colour palette and the borders pop-up live here
-- because the toolbar and the Format menu both open them.

local text = require ('sheet_panel_text') --[[@as Sheet.PanelTextModule]]

---Where a pop-up goes next to what opened it.
---@class Sheet.PopOptions
---@field side? 'below'|'right' Below the anchor, the default, or to its right.
---@field owner? Proteus.El Clicks inside this element do not close the pop-up.
---@field on_close? fun()
---@field keep_focus? boolean Leaves the keyboard where it is on close, instead of giving it to the grid.

---The pop-up in view.
---@class Sheet.OpenPop
---@field el Proteus.El
---@field opts Sheet.PopOptions
---@field off fun()[]

---What the toolbar and the panels share for one controller.
---@class Sheet.PanelEnv
---@field app Proteus.App
---@field ctl Sheet.Ctl
---@field ui Proteus.UI
---@field commands Proteus.Commands
---@field keys? Proteus.Keys
---@field menus? Proteus.Menus
---@field picker? Proteus.Picker
---@field pop? Sheet.OpenPop
---@field line string The border line last picked.
---@field border_color? string The border colour last picked. Nil is the default grey.
---@field actions table<string, fun(...: any)> What each command of the panels does, by command id.
---@field panels? Sheet.PanelsApi Set by sheet_panels once it is installed.

---What sheet_panels offers the toolbar.
---@class Sheet.PanelsApi
---@field sum fun(fn: string) Types or fills a quick sum.

---@class Sheet.PanelPopModule
local M = {}

-- lang=css
local CSS = [[
.sheet-pop {
  position: fixed;
  z-index: 2500;
  padding: 8px;
  background: var(--bg-elev);
  color: var(--fg);
  border: 1px solid var(--border);
  border-radius: calc(var(--radius) + 2px);
  box-shadow: var(--shadow);
  font-family: var(--font-ui);
  font-size: var(--font-size);
}
.sheet-pop-reset {
  display: flex;
  align-items: center;
  gap: 8px;
  width: 100%;
  padding: 4px 6px;
  margin-bottom: 6px;
  border: none;
  border-radius: var(--radius);
  background: transparent;
  color: var(--fg);
  cursor: pointer;
  font: inherit;
}
.sheet-pop-reset:hover {
  background: var(--bg-hover);
}
.sheet-pop-swatches {
  display: grid;
  grid-template-columns: repeat(10, 20px);
  gap: 4px;
}
.sheet-pop-swatch {
  width: 20px;
  height: 20px;
  border-radius: 50%;
  border: 1px solid color-mix(in srgb, var(--fg) 18%, transparent);
  cursor: pointer;
  display: grid;
  place-items: center;
}
.sheet-pop-swatch:hover {
  transform: scale(1.18);
  box-shadow: 0 0 0 2px var(--bg-elev), 0 0 0 3px var(--accent);
}
.sheet-pop-swatch.on {
  box-shadow: 0 0 0 2px var(--bg-elev), 0 0 0 4px var(--accent);
}
.sheet-pop-custom {
  display: flex;
  align-items: center;
  gap: 6px;
  margin-top: 8px;
  padding-top: 8px;
  border-top: 1px solid var(--border);
}
.sheet-pop-custom .ui-input {
  width: 96px;
  padding: 3px 7px;
  font-family: var(--font-mono);
}
.sheet-pop-label {
  color: var(--fg-muted);
  font-size: 12px;
}
.sheet-pop-picker {
  width: 28px;
  height: 24px;
  padding: 0;
  border: 1px solid var(--border);
  border-radius: var(--radius);
  background: transparent;
  cursor: pointer;
}
.sheet-pop-grid {
  display: grid;
  grid-template-columns: repeat(5, 1fr);
  gap: 4px;
}
.sheet-pop-cell {
  width: 100%;
  height: 30px;
  display: grid;
  place-items: center;
  border: none;
  border-radius: var(--radius);
  background: transparent;
  color: var(--fg);
  cursor: pointer;
}
.sheet-pop-cell:hover {
  background: var(--bg-hover);
}
.sheet-pop-cell.on {
  background: var(--bg-active);
  color: var(--accent);
}
.sheet-pop-row {
  display: flex;
  align-items: center;
  gap: 4px;
  margin-top: 8px;
}
.sheet-pop-row .sheet-pop-label {
  width: 44px;
  flex: none;
}
.sheet-pop-line {
  width: 30px;
  height: 24px;
  display: grid;
  place-items: center;
  border: none;
  border-radius: var(--radius);
  background: transparent;
  color: var(--fg);
  cursor: pointer;
}
.sheet-pop-line:hover {
  background: var(--bg-hover);
}
.sheet-pop-line.on {
  background: var(--bg-active);
  color: var(--accent);
}
.sheet-pop-dots {
  display: flex;
  gap: 4px;
}
.sheet-pop-dots .sheet-pop-swatch {
  width: 16px;
  height: 16px;
}
.sheet-pop-auto {
  width: 16px;
  height: 16px;
  border-radius: 50%;
  border: 1px dashed var(--fg-muted);
  background: transparent;
  cursor: pointer;
  padding: 0;
}
.sheet-pop-auto.on {
  box-shadow: 0 0 0 2px var(--bg-elev), 0 0 0 4px var(--accent);
}
]]

-- Pop-ups and shared state, one set per controller. A set goes away with its controller, such
-- as after a reload.
---@type table<Sheet.Ctl, Sheet.PanelEnv>
local envs = setmetatable ({}, { __mode = 'k' })

---The table the toolbar and panels share for a controller, made on first use.
---@param app Proteus.App
---@param ctl Sheet.Ctl
---@return Sheet.PanelEnv
function M.env (app, ctl)
  local env = envs[ctl]
  if env then
    return env
  end
  local ui = app.use ('ui')
  ui.css (CSS)
  env = {
    app = app,
    ctl = ctl,
    ui = ui,
    commands = app.use ('commands'),
    keys = app.try_use ('keys'),
    menus = app.try_use ('menus'),
    picker = app.try_use ('picker'),
    line = 'thin',
    actions = {},
  }
  envs[ctl] = env
  return env
end

---True when a workbook is open.
---@param env Sheet.PanelEnv
---@return boolean
function M.has_sheet (env)
  return env.ctl.sheet () ~= nil
end

---True when a shortcut should act on the sheet: a workbook is open, and the keyboard is on
---the grid, in the cell editor or in the formula bar. Other text boxes, such as the name box,
---a sheet tab being renamed, the find bar or a panel, keep their keys.
---@param env Sheet.PanelEnv
---@return boolean
function M.keys_ok (env)
  if not env.ctl.sheet () then
    return false
  end
  local dom = env.app.dom
  local focus = dom.focus_info ()
  if not focus.editable then
    return true
  end
  local handle = focus.handle
  return handle ~= nil
    and (
      dom.has_class (handle, 'sheet-grid-editor')
      or dom.has_class (handle, 'sheet-grid-fbar')
    )
end

---Runs a command for a click on the toolbar or a pop-up. A command of the panels runs at once
---while a workbook is open, wherever the keyboard is. Its `when` only keeps its shortcut out
---of other text boxes. Any other command runs through the command list.
---@param env Sheet.PanelEnv
---@param id string
---@param ... any
function M.act (env, id, ...)
  local action = env.actions[id]
  if not action then
    env.commands.run (id, ...)
    return
  end
  if env.ctl.sheet () then
    action (...)
  end
end

---A tooltip: the name, and the shortcut of a command when it has one.
---@param env Sheet.PanelEnv
---@param name string
---@param id? string
---@return string
function M.tip (env, name, id)
  local key = id and env.keys and env.keys.label (id)
  if key then
    return name .. ' (' .. key .. ')'
  end
  return name
end

---Where the active cell is on screen, or a spot near the top of the app when it is out of
---view, for a pop-up that belongs to the cell.
---@param env Sheet.PanelEnv
---@return Proteus.Rect
function M.cell_anchor (env)
  local _, row, col = env.ctl.selection ()
  local rect = env.ctl.cell_rect (row, col)
  if rect then
    return rect
  end
  local root = env.ctl.root ():rect ()
  local x, y = root.left + 80, root.top + 90
  return {
    x = x,
    y = y,
    w = 0,
    h = 0,
    left = x,
    top = y,
    right = x,
    bottom = y,
  }
end

---Closes the pop-up in view, if any.
---@param env Sheet.PanelEnv
function M.close (env)
  local pop = env.pop
  if not pop then
    return
  end
  env.pop = nil
  for _, off in ipairs (pop.off) do
    off ()
  end
  -- The pop-up's boxes still hold their text while on_close reads them.
  if pop.opts.on_close then
    env.app.try (pop.opts.on_close)
  end
  pop.el:remove ()
  if not pop.opts.keep_focus then
    env.ctl.focus ()
  end
end

---Moves an element next to a rect, inside the window.
---@param env Sheet.PanelEnv
---@param el Proteus.El
---@param anchor Proteus.Rect
---@param side? 'below'|'right'
function M.place (env, el, anchor, side)
  local vp = env.app.dom.viewport ()
  local r = el:rect ()
  local x, y ---@type number, number
  if side == 'right' then
    x, y = anchor.right + 6, anchor.top
    if x + r.w > vp.w - 4 then
      x = anchor.left - r.w - 6
    end
  else
    x, y = anchor.left, anchor.bottom + 4
    if y + r.h > vp.h - 4 and anchor.top - r.h - 4 >= 4 then
      y = anchor.top - r.h - 4
    end
  end
  x = math.max (4, math.min (x, vp.w - r.w - 4))
  y = math.max (4, math.min (y, vp.h - r.h - 4))
  el:style ({ left = math.floor (x) .. 'px', top = math.floor (y) .. 'px' })
end

---Shows an element as the pop-up, next to `anchor`. Any other pop-up closes first.
---@param env Sheet.PanelEnv
---@param el Proteus.El
---@param anchor Proteus.Rect
---@param opts? Sheet.PopOptions
function M.open (env, el, anchor, opts)
  M.close (env)
  local o = opts or {}
  local app = env.app
  el:class ('sheet-pop', true)
  el:style ({ left = '-9999px', top = '0px' })
  env.ctl.root ():append (el)
  M.place (env, el, anchor, o.side)
  local pop = { el = el, opts = o, off = {} } ---@type Sheet.OpenPop
  env.pop = pop
  pop.off[1] = app.dom.on_global ('mousedown', function (ev)
    local target = ev.target
    if target and app.dom.contains (el.id, target) then
      return nil
    end
    if target and o.owner and app.dom.contains (o.owner.id, target) then
      return nil
    end
    -- A click elsewhere puts the keyboard where it lands, so closing leaves the focus alone.
    o.keep_focus = true
    if env.pop == pop then
      M.close (env)
    end
    return nil
  end, { capture = true })
  pop.off[2] = app.dom.on_global ('keydown', function (ev)
    if ev.key == 'Escape' and env.pop == pop then
      M.close (env)
      return 'stop'
    end
    return nil
  end, { capture = true })
end

---@param color string
---@param on boolean
---@param extra? string
---@return string
local function swatch_html (color, on, extra)
  local check = ''
  if on then
    -- A tick that reads on light and dark swatches.
    check = '<svg width="12" height="12" viewBox="0 0 24 24" fill="none" '
      .. 'stroke="'
      .. (text.is_dark (color) and '#ffffff' or '#000000')
      .. '" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">'
      .. '<path d="M20 6 9 17l-5-5"/></svg>'
  end
  return '<div class="sheet-pop-swatch'
    .. (on and ' on' or '')
    .. (extra or '')
    .. '" data-item="'
    .. color
    .. '" title="'
    .. color
    .. '" style="background:'
    .. color
    .. '">'
    .. check
    .. '</div>'
end

---The colour palette: a Reset button, the swatches, and a box for any colour. `on_pick`
---gets the colour, or false for Reset.
---@param env Sheet.PanelEnv
---@param anchor Proteus.Rect
---@param current? string The colour in use now, marked with a tick.
---@param on_pick fun(color: string|false)
---@param opts? Sheet.PopOptions
function M.palette (env, anchor, current, on_pick, opts)
  local ui = env.ui
  local cur = current and string.lower (current) or nil
  local parts = {} ---@type string[]
  for _, color in ipairs (text.COLORS) do
    parts[#parts + 1] = swatch_html (color, color == cur)
  end
  local done = false
  ---@param color string|false
  local function pick (color)
    if done then
      return
    end
    done = true
    M.close (env)
    on_pick (color)
  end
  local grid = ui.div ({
    class = 'sheet-pop-swatches',
    html = table.concat (parts),
  })
  grid:on ('click', function (ev)
    if ev.item then
      pick (ev.item)
    end
    return nil
  end)
  local hex = ui.input ({
    placeholder = '#rrggbb',
    value = cur or '',
    spellcheck = false,
  })
  hex:on ('keydown', function (ev)
    if ev.key == 'Enter' then
      local color = text.parse_color (hex:value ())
      if color then
        pick (color)
      else
        hex:class ('sheet-pop-bad', true)
      end
      return 'stop'
    end
    return nil
  end)
  local native = ui.h ('input', {
    class = 'sheet-pop-picker',
    type = 'color',
    title = 'Pick any colour',
    value = cur or '#000000',
  })
  native:on ('change', function (ev)
    local color = text.parse_color (ev.value or '')
    if color then
      pick (color)
    end
    return nil
  end)
  local el = ui.div ({
    ui.h ('button', {
      class = 'sheet-pop-reset',
      ui.icon ('eraser', 15),
      'Reset',
      onclick = function ()
        pick (false)
        return nil
      end,
    }),
    grid,
    ui.div ({
      class = 'sheet-pop-custom',
      ui.span ({ class = 'sheet-pop-label', 'Custom' }),
      hex,
      native,
    }),
  })
  M.open (env, el, anchor, opts)
end

---A small picture of a border preset: the cell lines, with the ones it draws solid.
---@param preset string
---@return string
function M.border_icon (preset)
  local solid = {
    all = { 'l', 't', 'r', 'b', 'h', 'v' },
    inner = { 'h', 'v' },
    horizontal = { 'h' },
    vertical = { 'v' },
    outer = { 'l', 't', 'r', 'b' },
    left = { 'l' },
    top = { 't' },
    right = { 'r' },
    bottom = { 'b' },
    none = {},
  }
  local lines = {
    l = 'M2 2v14',
    t = 'M2 2h14',
    r = 'M16 2v14',
    b = 'M2 16h14',
    h = 'M2 9h14',
    v = 'M9 2v14',
  }
  local on = {} ---@type table<string, boolean>
  for _, k in ipairs (solid[preset] or {}) do
    on[k] = true
  end
  local faint, strong = {}, {} ---@type string[], string[]
  for _, k in ipairs ({ 'l', 't', 'r', 'b', 'h', 'v' }) do
    if on[k] then
      strong[#strong + 1] = lines[k]
    else
      faint[#faint + 1] = lines[k]
    end
  end
  return '<svg width="18" height="18" viewBox="0 0 18 18" fill="none" '
    .. 'stroke="currentColor" stroke-linecap="square">'
    .. '<path d="'
    .. table.concat (faint, ' ')
    .. '" stroke-width="1" stroke-opacity=".3" stroke-dasharray="1 2"/>'
    .. '<path d="'
    .. table.concat (strong, ' ')
    .. '" stroke-width="2"/></svg>'
end

---A sample of a border line style.
---@param line string
---@return string
local function line_icon (line)
  local body ---@type string
  if line == 'double' then
    body = '<path d="M2 4.5h20M2 7.5h20" stroke-width="1"/>'
  else
    local width = ({ thin = 1, medium = 2, thick = 3 })[line] or 1
    local dash = ''
    if line == 'dashed' then
      dash = ' stroke-dasharray="4 2"'
    elseif line == 'dotted' then
      dash = ' stroke-dasharray="1 2"'
    end
    body = '<path d="M2 6h20" stroke-width="' .. width .. '"' .. dash .. '/>'
  end
  return '<svg width="24" height="12" viewBox="0 0 24 12" fill="none" '
    .. 'stroke="currentColor">'
    .. body
    .. '</svg>'
end

---The borders pop-up: the presets, a line style and a colour. A preset applies at once with
---the line and colour picked, and the pop-up stays open for another.
---@param env Sheet.PanelEnv
---@param anchor Proteus.Rect
---@param apply fun(preset: Sheet.BorderPreset, line: string, color?: string)
---@param opts? Sheet.PopOptions
function M.borders (env, anchor, apply, opts)
  local ui = env.ui
  local grid = ui.div ({ class = 'sheet-pop-grid' })
  for _, b in ipairs (text.BORDERS) do
    grid:append (ui.h ('button', {
      class = 'sheet-pop-cell',
      title = b.label,
      html = M.border_icon (b.id),
      onclick = function ()
        apply (b.id, env.line, env.border_color)
        return nil
      end,
    }))
  end
  local lines = ui.div ({ class = 'sheet-pop-row' })
  lines:append (ui.span ({ class = 'sheet-pop-label', 'Line' }))
  local line_buttons = {} ---@type table<string, Proteus.El>
  for _, l in ipairs (text.LINES) do
    local b = ui.h ('button', {
      class = 'sheet-pop-line' .. (env.line == l.id and ' on' or ''),
      title = l.label,
      html = line_icon (l.id),
    })
    b:on ('click', function ()
      line_buttons[env.line]:class ('on', false)
      env.line = l.id
      b:class ('on', true)
      return nil
    end)
    line_buttons[l.id] = b
    lines:append (b)
  end
  local dots = ui.div ({ class = 'sheet-pop-dots' })
  local auto = ui.h ('button', {
    class = 'sheet-pop-auto' .. (env.border_color and '' or ' on'),
    title = 'Default colour',
  })
  ---@param color? string
  local function draw_dots (color)
    local parts = {} ---@type string[]
    for _, c in ipairs (text.BORDER_COLORS) do
      parts[#parts + 1] = swatch_html (c, c == color)
    end
    dots:html (table.concat (parts))
    auto:class ('on', color == nil)
  end
  draw_dots (env.border_color)
  dots:on ('click', function (ev)
    if ev.item then
      env.border_color = ev.item
      draw_dots (ev.item)
    end
    return nil
  end)
  auto:on ('click', function ()
    env.border_color = nil
    draw_dots (nil)
    return nil
  end)
  local native = ui.h ('input', {
    class = 'sheet-pop-picker',
    type = 'color',
    title = 'Pick any colour',
    value = env.border_color or '#000000',
  })
  native:on ('change', function (ev)
    local color = text.parse_color (ev.value or '')
    if color then
      env.border_color = color
      draw_dots (color)
    end
    return nil
  end)
  local el = ui.div ({
    grid,
    lines,
    ui.div ({
      class = 'sheet-pop-row',
      ui.span ({ class = 'sheet-pop-label', 'Colour' }),
    }),
    ui.div ({
      class = 'sheet-pop-row',
      auto,
      dots,
      native,
    }),
  })
  M.open (env, el, anchor, opts)
end

return M
