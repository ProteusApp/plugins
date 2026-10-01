-- sheet_toolbar: the Sheet app's formatting toolbar.
--
-- A row of small buttons in groups, which wraps on a narrow window. The toggles and the
-- colour bars follow the active cell's style as the selection moves. Buttons run the same
-- actions as the menus and the keys. A button keeps the keyboard where it is when clicked, so
-- the grid keeps its focus. The toolbar greys out with no workbook open, and while a cell is
-- being edited, except the quick sum, which types into the editor.

local pop = require ('sheet_panel_pop') --[[@as Sheet.PanelPopModule]]
local text = require ('sheet_panel_text') --[[@as Sheet.PanelTextModule]]

-- lang=css
local CSS = [[
.sheet-tb {
  flex: none;
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 1px;
  padding: 4px 8px;
  background: var(--bg-alt);
  border-bottom: 1px solid var(--border);
  user-select: none;
}
.sheet-tb-btn {
  height: 28px;
  min-width: 28px;
  padding: 0 5px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 1px;
  border: none;
  border-radius: var(--radius);
  background: transparent;
  color: var(--fg);
  cursor: pointer;
  font: inherit;
}
.sheet-tb-btn .ui-icon {
  opacity: 0.85;
}
.sheet-tb-btn:hover:not(:disabled) {
  background: var(--bg-hover);
}
.sheet-tb-btn.on {
  background: var(--bg-active);
  color: var(--accent);
}
.sheet-tb-btn.on .ui-icon {
  opacity: 1;
}
.sheet-tb-btn:disabled {
  opacity: 0.38;
  cursor: default;
}
.sheet-tb-btn.open {
  background: var(--bg-hover);
}
.sheet-tb-word {
  font-size: 12px;
  font-weight: 600;
  letter-spacing: 0.02em;
  padding-left: 2px;
}
.sheet-tb-more {
  opacity: 0.6;
  margin-left: -1px;
}
.sheet-tb-sep {
  width: 1px;
  height: 20px;
  margin: 0 5px;
  background: var(--border);
}
.sheet-tb-paint {
  display: inline-flex;
  flex-direction: column;
  align-items: center;
  gap: 1px;
}
.sheet-tb-bar {
  width: 16px;
  height: 4px;
  border-radius: 1px;
  box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--fg) 15%, transparent);
}
.sheet-tb-size {
  display: inline-flex;
  align-items: center;
  margin: 0 2px;
}
.sheet-tb-size input {
  width: 38px;
  height: 24px;
  padding: 0 4px;
  border: 1px solid var(--border);
  border-radius: var(--radius) 0 0 var(--radius);
  background: var(--bg);
  color: var(--fg);
  text-align: center;
  font: inherit;
  font-variant-numeric: tabular-nums;
  outline: none;
}
.sheet-tb-size input:focus {
  border-color: var(--accent);
}
.sheet-tb-size input:disabled {
  opacity: 0.38;
}
.sheet-tb-size .sheet-tb-btn {
  height: 24px;
  min-width: 18px;
  padding: 0;
  border: 1px solid var(--border);
  border-left: none;
  border-radius: 0 var(--radius) var(--radius) 0;
}
]]

---A button on the toolbar.
---@class Sheet.ToolButton
---@field el Proteus.El
---@field name string
---@field id? string The command whose shortcut the tooltip shows.
---@field live? boolean Stays on while a cell is being edited.
---@field grid? boolean Runs a command of the grid, whose own `when` decides if it is on.

local ALIGN_ICONS = {
  left = 'align-left',
  center = 'align-center',
  right = 'align-right',
}
local VALIGN_ICONS = {
  top = 'arrow-up-to-line',
  middle = 'fold-vertical',
  bottom = 'arrow-down-to-line',
}

---@type Sheet.ToolbarModule
local M = {
  mount = function (app, ctl, host)
    local env = pop.env (app, ctl)
    local ui = env.ui
    local commands = env.commands
    local menus = env.menus
    ui.css (CSS)

    local bar = ui.div ({ class = 'sheet-tb' })
    host:append (bar)
    local buttons = {} ---@type Sheet.ToolButton[]
    -- The button whose menu is open, so a second click closes it.
    local menu_for = nil ---@type Proteus.El?

    ---@param el Proteus.El
    local function keep_focus (el)
      el:on ('mousedown', function ()
        return true
      end)
    end

    ---@param name string
    ---@param spec { icon?: string, lead?: Proteus.El, word?: string, more?: boolean, id?: string, live?: boolean, grid?: boolean, click?: fun(el: Proteus.El), parent?: Proteus.El }
    ---@return Proteus.El
    local function button (name, spec)
      local el = ui.h ('button', {
        class = 'sheet-tb-btn',
        title = pop.tip (env, name, spec.id),
        spec.lead,
        spec.icon and ui.icon (spec.icon, 16) or nil,
        spec.word and ui.span ({ class = 'sheet-tb-word', spec.word }) or nil,
        spec.more and ui.span ({
          class = 'sheet-tb-more',
          ui.icon ('chevron-down', 12),
        }) or nil,
      })
      keep_focus (el)
      el:on ('click', function ()
        if spec.click then
          spec.click (el)
        elseif spec.id then
          pop.act (env, spec.id)
        end
        return nil
      end)
      buttons[#buttons + 1] = {
        el = el,
        name = name,
        id = spec.id,
        live = spec.live,
        grid = spec.grid,
      }
      (spec.parent or bar):append (el)
      return el
    end

    local function sep ()
      bar:append (ui.div ({ class = 'sheet-tb-sep' }))
    end

    ---Opens a menu under a toolbar button, or closes it when it is open already.
    ---@param el Proteus.El
    ---@param items Proteus.MenuItem[]
    local function menu (el, items)
      if not menus then
        return
      end
      if menu_for == el then
        menus.close ()
        return
      end
      pop.close (env)
      local rect = el:rect ()
      menu_for = el
      el:class ('open', true)
      menus.popup (items, rect.left, rect.bottom + 3, {
        owner = el,
        on_close = function ()
          el:class ('open', false)
          if menu_for == el then
            menu_for = nil
          end
          ctl.focus ()
        end,
      })
    end

    ---A menu item that runs a command and shows its shortcut.
    ---@param label string
    ---@param id string
    ---@param icon? string
    ---@param on? boolean
    ---@return Proteus.MenuItem
    local function item (label, id, icon, on)
      return {
        label = label,
        icon = on and 'check' or icon,
        key = env.keys and env.keys.label (id) or nil,
        run = function ()
          pop.act (env, id)
        end,
      }
    end

    ---Shows a pop-up of this module under a button, or closes it when it is open already.
    ---@param el Proteus.El
    ---@return boolean opened False when the click closed it.
    local function toggle_pop (el)
      if env.pop and env.pop.opts.owner == el then
        pop.close (env)
        return false
      end
      return true
    end

    ---@return Sheet.Style
    local function style_now ()
      local sheet = ctl.sheet ()
      if not sheet then
        return {}
      end
      local _, row, col = ctl.selection ()
      return sheet:style_at (row, col)
    end

    -- Undo and redo --------------------------------------------------------------------

    button ('Undo', { icon = 'undo-2', id = 'sheet.undo', grid = true })
    button ('Redo', { icon = 'redo-2', id = 'sheet.redo', grid = true })
    sep ()

    -- Number formats -------------------------------------------------------------------

    button ('Format as currency', {
      icon = 'dollar-sign',
      id = 'sheet.format_currency',
    })
    button (
      'Format as percent',
      { icon = 'percent', id = 'sheet.format_percent' }
    )
    button ('Fewer decimal places', {
      icon = 'decimals-arrow-left',
      id = 'sheet.decimals_less',
    })
    button ('More decimal places', {
      icon = 'decimals-arrow-right',
      id = 'sheet.decimals_more',
    })
    button ('Number format', {
      word = '123',
      more = true,
      id = 'sheet.number_format',
      click = function (el)
        local current = style_now ().format
        local items = {} ---@type Proteus.MenuItem[]
        for _, choice in ipairs (text.format_choices ()) do
          local on = current == choice.code
            or (current == nil and choice.id == 'general')
          items[#items + 1] = {
            label = choice.label,
            icon = on and 'check' or '',
            key = choice.example,
            run = function ()
              pop.act (env, 'sheet.number_format', choice.code)
            end,
          }
        end
        items[#items + 1] = { separator = true }
        items[#items + 1] = item ('Custom format…', 'sheet.custom_format')
        menu (el, items)
      end,
    })
    sep ()

    -- Font size ------------------------------------------------------------------------

    local size_box = ui.div ({ class = 'sheet-tb-size' })
    local size_input = ui.h ('input', {
      spellcheck = false,
      title = 'Font size',
      value = tostring (text.DEFAULT_SIZE),
    })
    local shown_size = text.DEFAULT_SIZE
    size_box:append (size_input)
    bar:append (size_box)
    size_input:on ('keydown', function (ev)
      if ev.key == 'Enter' then
        local size = text.parse_size (size_input:value ())
        if size then
          pop.act (env, 'sheet.font_size', size)
        else
          size_input:value (tostring (shown_size))
        end
        ctl.focus ()
        return 'stop'
      elseif ev.key == 'Escape' then
        size_input:value (tostring (shown_size))
        ctl.focus ()
        return 'stop'
      end
      return nil
    end)
    size_input:on ('blur', function ()
      size_input:value (tostring (shown_size))
      return nil
    end)
    size_input:on ('focus', function ()
      size_input:select ()
      return nil
    end)
    button ('Font size', {
      icon = 'chevron-down',
      id = 'sheet.font_size',
      parent = size_box,
      click = function (el)
        local current = style_now ().size or text.DEFAULT_SIZE
        local items = {} ---@type Proteus.MenuItem[]
        for _, size in ipairs (text.SIZES) do
          items[#items + 1] = {
            label = tostring (size),
            icon = size == current and 'check' or '',
            run = function ()
              pop.act (env, 'sheet.font_size', size)
            end,
          }
        end
        menu (el, items)
      end,
    })
    sep ()

    -- Text style -----------------------------------------------------------------------

    local bold = button ('Bold', { icon = 'bold', id = 'sheet.bold' })
    local italic = button ('Italic', { icon = 'italic', id = 'sheet.italic' })
    local strike =
      button ('Strikethrough', { icon = 'strikethrough', id = 'sheet.strike' })
    local underline =
      button ('Underline', { icon = 'underline', id = 'sheet.underline' })

    ---A colour button: an icon over a bar of the colour in use.
    ---@param name string
    ---@param icon string
    ---@param id string
    ---@param field 'color'|'fill'
    ---@return Proteus.El bar
    local function paint (name, icon, id, field)
      local swatch = ui.span ({ class = 'sheet-tb-bar' })
      local el = button (name, {
        id = id,
        click = function (self)
          if not toggle_pop (self) then
            return
          end
          local now = style_now ()
          local current = now.fill
          if field == 'color' then
            current = now.color
          end
          pop.palette (env, self:rect (), current, function (color)
            pop.act (env, id, color)
          end, { owner = self })
        end,
      })
      el:append (ui.span ({
        class = 'sheet-tb-paint',
        ui.icon (icon, 15),
        swatch,
      }))
      return swatch
    end
    local color_bar =
      paint ('Text colour', 'baseline', 'sheet.text_color', 'color')
    local fill_bar =
      paint ('Fill colour', 'paint-bucket', 'sheet.fill_color', 'fill')
    sep ()

    -- Borders and merge ----------------------------------------------------------------

    button ('Borders', {
      lead = ui.span ({ class = 'ui-icon', html = pop.border_icon ('all') }),
      id = 'sheet.borders',
      click = function (el)
        if not toggle_pop (el) then
          return
        end
        pop.borders (env, el:rect (), function (preset, line, color)
          pop.act (env, 'sheet.borders', preset, line, color)
        end, { owner = el })
      end,
    })
    local merge = button ('Merge cells', {
      icon = 'table-cells-merge',
      more = true,
      id = 'sheet.merge',
      click = function (el)
        menu (el, {
          item ('Merge all', 'sheet.merge', 'table-cells-merge'),
          item ('Merge across', 'sheet.merge_across', 'rows-3'),
          item ('Unmerge', 'sheet.unmerge', 'table-cells-split'),
        })
      end,
    })
    sep ()

    -- Alignment and wrap ---------------------------------------------------------------

    local align_icon = ui.span ({ ui.icon ('align-left', 16) })
    button ('Horizontal align', {
      lead = align_icon,
      more = true,
      click = function (el)
        local sheet = ctl.sheet ()
        local _, row, col = ctl.selection ()
        local now = sheet and sheet:align (row, col) or 'left'
        menu (el, {
          item ('Left', 'sheet.align_left', 'align-left', now == 'left'),
          item ('Centre', 'sheet.align_center', 'align-center', now == 'center'),
          item ('Right', 'sheet.align_right', 'align-right', now == 'right'),
        })
      end,
    })
    local valign_icon = ui.span ({ ui.icon ('arrow-down-to-line', 16) })
    button ('Vertical align', {
      lead = valign_icon,
      more = true,
      click = function (el)
        local now = style_now ().valign or 'bottom'
        menu (el, {
          item ('Top', 'sheet.valign_top', VALIGN_ICONS.top, now == 'top'),
          item (
            'Middle',
            'sheet.valign_middle',
            VALIGN_ICONS.middle,
            now == 'middle'
          ),
          item (
            'Bottom',
            'sheet.valign_bottom',
            VALIGN_ICONS.bottom,
            now == 'bottom'
          ),
        })
      end,
    })
    local wrap = button ('Wrap text', { icon = 'wrap-text', id = 'sheet.wrap' })
    sep ()

    -- Data -----------------------------------------------------------------------------

    local filter = button ('Filter', { icon = 'filter', id = 'sheet.filter' })
    button ('Insert chart', { icon = 'chart-column', id = 'sheet.chart' })
    button ('Functions', {
      icon = 'sigma',
      more = true,
      live = true,
      click = function (el)
        local items = {} ---@type Proteus.MenuItem[]
        for _, fn in ipairs (text.SUM_FUNCTIONS) do
          items[#items + 1] = {
            label = fn,
            run = function ()
              if env.panels then
                env.panels.sum (fn)
              end
            end,
          }
        end
        items[#items + 1] = { separator = true }
        items[#items + 1] = item ('More functions…', 'sheet.function')
        menu (el, items)
      end,
    })

    -- Keeping the buttons in step ------------------------------------------------------

    local seen = {} ---@type table<string, any>

    ---Changes a class or a property only when it differs from last time, since each change
    ---is a call into the page.
    ---@param key string
    ---@param value any
    ---@param apply fun()
    local function once (key, value, apply)
      if seen[key] ~= value then
        seen[key] = value
        apply ()
      end
    end

    ---@param el Proteus.El
    ---@param key string
    ---@param on boolean
    local function set_on (el, key, on)
      once (key, on, function ()
        el:class ('on', on)
      end)
    end

    local function refresh ()
      local sheet = ctl.sheet ()
      local editing = sheet ~= nil and ctl.editing ()
      for i, b in ipairs (buttons) do
        local off = sheet == nil or (editing and not b.live)
        if not off and b.grid and b.id then
          off = not commands.can_run (b.id)
        end
        once ('off' .. i, off, function ()
          b.el:set ('disabled', off)
        end)
      end
      once ('size_off', sheet == nil or editing, function ()
        size_input:set ('disabled', sheet == nil or editing)
      end)
      local style = style_now ()
      set_on (bold, 'bold', style.bold == true)
      set_on (italic, 'italic', style.italic == true)
      set_on (strike, 'strike', style.strike == true)
      set_on (underline, 'underline', style.underline == true)
      set_on (wrap, 'wrap', style.wrap == true)
      set_on (filter, 'filter', sheet ~= nil and sheet.filter ~= nil)
      local _, row, col = ctl.selection ()
      local merged = sheet ~= nil and sheet:merge_at (row, col) ~= nil
      set_on (merge, 'merge', merged)
      local size = style.size or text.DEFAULT_SIZE
      once ('size', size, function ()
        shown_size = size
        size_input:value (tostring (size))
      end)
      once ('color', style.color or '', function ()
        color_bar:style ('background', style.color or 'var(--fg)')
      end)
      once ('fill', style.fill or '', function ()
        fill_bar:style ('background', style.fill or 'transparent')
      end)
      local how = sheet and sheet:align (row, col) or 'left'
      once ('align', how, function ()
        align_icon:set_children ({
          ui.icon (ALIGN_ICONS[how] or 'align-left', 16),
        })
      end)
      local vhow = style.valign or 'bottom'
      once ('valign', vhow, function ()
        valign_icon:set_children ({ ui.icon (VALIGN_ICONS[vhow], 16) })
      end)
    end

    -- Events come in bursts, such as a change and then a selection, so one refresh follows.
    local queued = false
    local function soon ()
      if queued then
        return
      end
      queued = true
      app.timer.after (0, function ()
        queued = false
        refresh ()
      end)
    end

    ---Shortcut labels exist only once the commands do, which register after the toolbar.
    local function retitle ()
      for _, b in ipairs (buttons) do
        b.el:set ('title', pop.tip (env, b.name, b.id))
      end
    end

    for _, event in ipairs ({
      'book',
      'sheet',
      'selection',
      'changed',
      'editing',
      'view',
    }) do
      ctl.on (event --[[@as Sheet.CtlEvent]], soon)
    end
    commands.on_change (function ()
      retitle ()
      soon ()
    end)
    refresh ()
  end,
}

return M
