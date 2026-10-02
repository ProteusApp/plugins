-- code.minimap: the whole file in front, in miniature, at the side of the code.
--
-- It sits inside the editor, at its right or left edge, either over the text or beside it. It
-- works wherever proteus.editor.core edits files, so in the Code Editor and in the Plugin
-- Editor alike. It redraws a moment after the text changes, and when another tab comes to the
-- front.
--
-- A box shades the lines on screen and follows the editor as it scrolls. A click, or a drag
-- down the picture, scrolls the editor so the line under the pointer sits in the middle of the
-- screen, leaving the cursor where it was. When the picture is taller than the editor, it
-- scrolls along with it, so the box stays in sight. Selected lines, and lines with problems
-- from the diagnostics service, show as full-width bands.
--
-- A Proteus whose editor has no side for plugins shows the minimap in the right dock instead.
-- One whose editor does not say where it is scrolled has no box. There a click moves the
-- cursor to the line, and a band marks the line it moved to.

local render = require ('minimap_render') --[[@as Minimap.RenderModule]]

-- The text waits this long after the last change before the picture redraws.
local PAUSE = 150
-- The height of one line of the picture, in pixels, for each `minimap.size`.
local LINE_HEIGHTS = { small = 2, medium = 3, large = 4 }
-- The narrowest and widest the minimap may be, in pixels.
local MIN_WIDTH, MAX_WIDTH = 40, 400

-- lang=css
local CSS = [[
.minimap { --minimap-line: 3px; position: relative; display: flex; flex-direction: column; height: 100%;
  min-height: 0; background: var(--editor-bg, var(--bg)); pointer-events: auto; transition: opacity .15s; }
.minimap.in-editor.right { box-shadow: -1px 0 0 var(--border); }
.minimap.in-editor.left { box-shadow: 1px 0 0 var(--border); }
.minimap.fades:not(.hovered) { opacity: 0; pointer-events: none; }
.minimap.off { display: none; }
.minimap-scroll { flex: 1; min-height: 0; overflow-x: hidden; overflow-y: auto; cursor: pointer;
  scrollbar-width: none; }
.minimap-page { position: relative; min-height: 100%; }
.minimap-code { margin: 0; padding: 0 6px; overflow: hidden; white-space: pre; tab-size: 4;
  font-family: var(--font-mono); font-size: calc(var(--minimap-line) * 0.85);
  line-height: var(--minimap-line); color: var(--fg-muted); user-select: none; pointer-events: none; }
.minimap-code .k { color: var(--syn-keyword); }
.minimap-code .s { color: var(--syn-string); }
.minimap-code .c { color: var(--syn-comment); }
.minimap-code .n { color: var(--syn-number); }
.minimap-code .t { color: var(--syn-constant); }
.minimap.plain .minimap-code span { color: inherit; }
.minimap-marks { position: absolute; inset: 0; pointer-events: none; }
.minimap-marks i { position: absolute; left: 0; right: 0; min-height: 2px; }
.minimap-marks .sel { background: color-mix(in srgb, var(--accent) 45%, transparent); }
.minimap-marks .e { background: color-mix(in srgb, var(--danger) 75%, transparent); }
.minimap-marks .w { background: color-mix(in srgb, var(--warning) 70%, transparent); }
.minimap-marks .i { background: color-mix(in srgb, var(--accent) 35%, transparent); }
.minimap.no-marks .minimap-marks { display: none; }
.minimap-band, .minimap-hover, .minimap-view { position: absolute; left: 0; right: 0; display: none;
  pointer-events: none; }
.minimap-band { min-height: 2px; border-left: 2px solid var(--accent);
  background: color-mix(in srgb, var(--accent) 35%, transparent); }
.minimap-view { border-top: 1px solid color-mix(in srgb, var(--fg) 22%, transparent);
  border-bottom: 1px solid color-mix(in srgb, var(--fg) 22%, transparent);
  background: color-mix(in srgb, var(--fg) 10%, transparent); }
.minimap.slider-fades:not(.hovered):not(.dragging) .minimap-view { visibility: hidden; }
.minimap-hover { min-height: 2px; background: color-mix(in srgb, var(--fg) 14%, transparent); }
.minimap-scroll:hover .minimap-hover { display: block; }
.minimap-empty { padding: 12px; font-size: 12px; color: var(--fg-faint); }
.minimap-note { flex: none; padding: 4px 8px; border-top: 1px solid var(--border); font-size: 11px;
  color: var(--fg-faint); }
]]

---Reads a list of line ranges from the editor. A list from the editor's own code may count
---from 0 or from 1, so it goes by the order of the keys.
---@param value any
---@return Minimap.Range[]
local function ranges_of (value)
  local out = {}
  if type (value) ~= 'table' then
    return out
  end
  local keys = {}
  for k in pairs (value) do
    if type (k) == 'number' then
      keys[#keys + 1] = k
    end
  end
  table.sort (keys)
  for _, k in ipairs (keys) do
    local r = value[k]
    if type (r) == 'table' and tonumber (r.first) and tonumber (r.last) then
      out[#out + 1] =
        { first = math.floor (r.first), last = math.floor (r.last) }
    end
  end
  return out
end

---@type Proteus.Plugin
return {
  name = 'Minimap',
  description = 'Shows the file in front in miniature at the side of the code, with the part on screen, the selection and problems marked.',
  version = '1.1.0',
  -- `files` for the `editor` service, which hands over the text of the file in front.
  permissions = { 'files' },
  requires = { proteus = '>=0.3.0', features = { 'permissions' } },
  depends = {
    'proteus.lib.ui',
    'proteus.ui.views',
    'proteus.ui.tabs',
    'proteus.editor.core',
  },
  optional = {
    'proteus.core.settings',
    'proteus.core.commands',
    'proteus.tools.diagnostics',
  },
  activate = function (app)
    local ui = app.use ('ui')
    local tabs = app.use ('tabs')
    local editor = app.use ('editor')
    local settings = app.try_use ('settings')
    local commands = app.try_use ('commands')
    ui.css (CSS)

    local painter = render.painter ()
    local line_h = LINE_HEIGHTS.medium

    local code = ui.pre ({ class = 'minimap-code' })
    local marks = ui.div ({ class = 'minimap-marks' })
    local band = ui.div ({ class = 'minimap-band' })
    local box = ui.div ({ class = 'minimap-view' })
    local hover = ui.div ({ class = 'minimap-hover' })
    local scroller = ui.div ({
      class = 'minimap-scroll',
      ui.div ({ class = 'minimap-page', code, marks, box, band, hover }),
    })
    local empty =
      ui.div ({ class = 'minimap-empty', 'Open a file to see its minimap.' })
    local note = ui.div ({ class = 'minimap-note' })
    local root = ui.div ({ class = 'minimap', scroller, empty, note })

    -- The document the picture shows, and how many of its lines it holds.
    local shown = nil ---@type { path: string, lines: integer }?
    -- The line the minimap last moved the editor to, which the band marks.
    local jumped = nil ---@type integer?
    -- The lines on screen in the editor, which the box shades, when the editor tells them.
    local on_screen = nil ---@type Minimap.Range?
    -- The selected lines, which show as bands.
    local selected = {} ---@type Minimap.Range[]
    -- True while a drag down the picture goes on.
    local dragging = false
    -- True when the text changed while the minimap was out of sight.
    local stale = true
    local cancel_pause = nil ---@type fun()?

    ---True while the minimap is on screen. Out of sight, it has no width.
    ---@return boolean
    local function visible ()
      return root:alive () and root:rect ().w > 0
    end

    ---Puts a band at a line, or hides it for nil.
    ---@param el Proteus.El
    ---@param line integer?
    local function place (el, line)
      if not line then
        el:style ('display', nil)
        return
      end
      el:style ({
        display = 'block',
        top = ((line - 1) * line_h) .. 'px',
        height = line_h .. 'px',
      })
    end

    ---Shades the lines on screen, or hides the box for nil.
    ---@param lines Minimap.Range?
    local function place_box (lines)
      on_screen = lines
      if not lines or not shown then
        box:style ('display', nil)
        return
      end
      local last = math.min (lines.last, shown.lines)
      local first = math.min (lines.first, last)
      box:style ({
        display = 'block',
        top = ((first - 1) * line_h) .. 'px',
        height = ((last - first + 1) * line_h) .. 'px',
      })
    end

    ---Draws the bands for the selection and for problems.
    local function draw_marks ()
      if not shown then
        marks:html ('')
        return
      end
      local diagnostics = app.try_use ('diagnostics')
      local problems = diagnostics and diagnostics.get (shown.path) or {}
      marks:html (render.marks (selected, problems, shown.lines, line_h))
    end

    ---Scrolls the picture along with the editor, for a file taller than the minimap. At the
    ---top of the file the picture shows its top, and at the bottom its bottom, so the box
    ---never leaves sight.
    local function follow ()
      if not on_screen or not shown or dragging then
        return
      end
      local spare = shown.lines * line_h - scroller:rect ().h
      if spare <= 0 then
        return
      end
      local count = on_screen.last - on_screen.first + 1
      local share = (on_screen.first - 1) / math.max (1, shown.lines - count)
      scroller:set ('scrollTop', math.floor (math.min (1, share) * spare))
    end

    ---Scrolls the picture so a line sits in view, for a file taller than the minimap.
    ---@param line integer
    local function keep_in_view (line)
      local top = (line - 1) * line_h
      local height = scroller:rect ().h
      local scroll = tonumber (scroller:get ('scrollTop')) or 0
      if top < scroll or top > scroll + height - line_h then
        scroller:set ('scrollTop', math.max (0, top - height / 2))
      end
    end

    local function draw ()
      stale = false
      local doc = editor.current ()
      if not doc then
        shown, jumped, selected = nil, nil, {}
        code:html ('')
        place (band, nil)
        place_box (nil)
        draw_marks ()
        scroller:show (false)
        note:show (false)
        empty:show (true)
        return
      end
      local picture = painter.paint (doc.text (), doc.language)
      if not shown or shown.path ~= doc.path then
        jumped = nil
        scroller:set ('scrollTop', 0)
      end
      shown = { path = doc.path, lines = picture.drawn }
      code:html (picture.html)
      empty:show (false)
      scroller:show (true)
      if picture.drawn < picture.lines then
        note:text (
          ('Drawn up to line %d of %d.'):format (picture.drawn, picture.lines)
        )
        note:show (true)
      else
        note:show (false)
      end
      if jumped and jumped > picture.drawn then
        jumped = nil
      end
      place (band, jumped)
      selected = ranges_of (doc.selections and doc.selections () or nil)
      draw_marks ()
      place_box (doc.viewport and doc.viewport () or nil)
      follow ()
    end

    ---Redraws after a short pause, or once the minimap shows when it is out of sight.
    local function soon ()
      if not visible () then
        stale = true
        return
      end
      if cancel_pause then
        cancel_pause ()
      end
      cancel_pause = app.timer.after (PAUSE, function ()
        cancel_pause = nil
        draw ()
      end)
    end

    ---The line under the pointer, or nil when no file shows.
    ---@param ev Proteus.DomEvent
    ---@return integer?
    local function line_under (ev)
      if not shown or not ev.y then
        return nil
      end
      local scroll = tonumber (scroller:get ('scrollTop')) or 0
      return render.line_at (
        ev.y - scroller:rect ().top + scroll,
        line_h,
        shown.lines
      )
    end

    ---Scrolls the editor so the line under the pointer sits in the middle of the screen. An
    ---editor that cannot say where it is scrolled moves its cursor to the line instead.
    ---@param ev Proteus.DomEvent
    local function jump (ev)
      local line = line_under (ev)
      if not line or not shown or line == jumped then
        return
      end
      jumped = line
      local doc = editor.current ()
      if doc and doc.scroll_to and doc.path == shown.path then
        local count = on_screen and (on_screen.last - on_screen.first + 1) or 1
        doc.scroll_to (math.max (1, line - math.floor (count / 2)))
        return
      end
      place (band, line)
      editor.open (shown.path, { line = line })
    end

    scroller:on ('mousedown', function (ev)
      if ev.button ~= 0 then
        return nil
      end
      dragging = true
      root:class ('dragging', true)
      jump (ev)
      -- Keeps the keyboard in the editor.
      return true
    end)
    scroller:on ('mousemove', function (ev)
      place (hover, line_under (ev))
      if dragging then
        jump (ev)
        if jumped and not on_screen then
          keep_in_view (jumped)
        end
      end
    end)

    ---Marks the minimap as under the pointer, which brings out a minimap that fades and a box
    ---that shows only on hover. It goes by the minimap's place on screen, since a faded
    ---minimap lets the pointer through to the text.
    ---@param ev Proteus.DomEvent
    local function track_pointer (ev)
      if not ev.x or not ev.y or not root:alive () then
        return
      end
      local r = root:rect ()
      local inside = r.w > 0
        and ev.x >= r.left
        and ev.x <= r.right
        and ev.y >= r.top
        and ev.y <= r.bottom
      root:class ('hovered', inside or dragging)
    end
    app.dom.on_global ('mousemove', track_pointer)
    app.dom.on_global ('mouseup', function (ev)
      if not dragging then
        return
      end
      -- The picture holds still under the pointer during a drag, then catches up.
      dragging = false
      root:class ('dragging', false)
      track_pointer (ev)
      if on_screen then
        jumped = nil
        follow ()
      end
    end)

    -- Settings -------------------------------------------------------------------------------

    local config =
      { show = 'always', placement = 'over', side = 'right', width = 120 }
    local side = nil ---@type Proteus.EditorSide?

    ---Puts the minimap where the settings say.
    local function apply_place ()
      root:class ('off', config.show == 'off')
      root:class ('fades', config.show == 'hover')
      root:class ('left', config.side == 'left')
      root:class ('right', config.side ~= 'left')
      if side then
        side.set ({
          side = config.side == 'left' and 'left' or 'right',
          width = config.show == 'off' and 0 or config.width,
          over = config.placement ~= 'beside',
        })
      end
      if config.show ~= 'off' then
        soon ()
      end
    end

    ---Declares a setting and follows it. Without the settings service, the default holds.
    ---@param key string
    ---@param spec Proteus.SettingSpec
    ---@param fn fun(value: any)
    local function setting (key, spec, fn)
      if settings then
        settings.define (key, spec)
        settings.watch (key, fn)
      else
        fn (spec.default)
      end
    end

    setting ('minimap.show', {
      title = 'Show the minimap',
      type = 'select',
      options = { 'always', 'hover', 'off' },
      default = 'always',
      description = 'Always, only while the pointer is over it, or never. While it waits for the pointer, clicks go through to the text.',
    }, function (value)
      config.show = (value == 'hover' or value == 'off') and value or 'always'
      apply_place ()
    end)
    setting ('minimap.placement', {
      title = 'Minimap placement',
      type = 'select',
      options = { 'over', 'beside' },
      default = 'over',
      description = 'Over the edge of the text, or beside the text, taking room from it.',
    }, function (value)
      config.placement = value == 'beside' and 'beside' or 'over'
      apply_place ()
    end)
    setting ('minimap.side', {
      title = 'Minimap side',
      type = 'select',
      options = { 'right', 'left' },
      default = 'right',
      description = 'The edge of the editor the minimap sits at.',
    }, function (value)
      config.side = value == 'left' and 'left' or 'right'
      apply_place ()
    end)
    setting ('minimap.width', {
      title = 'Minimap width',
      type = 'number',
      default = 120,
      description = 'How wide the minimap is, in pixels, from 40 to 400.',
    }, function (value)
      local n = math.floor (tonumber (value) or 120)
      config.width = math.max (MIN_WIDTH, math.min (MAX_WIDTH, n))
      apply_place ()
    end)
    setting ('minimap.size', {
      title = 'Minimap line size',
      type = 'select',
      options = { 'small', 'medium', 'large' },
      default = 'medium',
      description = 'How tall each line of the minimap is: 2, 3 or 4 pixels.',
    }, function (value)
      line_h = LINE_HEIGHTS[value] or LINE_HEIGHTS.medium
      root:style ('--minimap-line', line_h .. 'px')
      place (band, jumped)
      place_box (on_screen)
      draw_marks ()
      follow ()
    end)
    setting ('minimap.slider', {
      title = 'Minimap screen box',
      type = 'select',
      options = { 'always', 'hover' },
      default = 'always',
      description = 'Shades the lines on screen always, or only while the pointer is over the minimap.',
    }, function (value)
      root:class ('slider-fades', value == 'hover')
    end)
    setting ('minimap.colors', {
      title = 'Color the minimap',
      type = 'boolean',
      default = true,
      description = "Colors comments, strings, keywords and numbers with the theme's code colors.",
    }, function (value)
      root:class ('plain', value == false)
    end)
    setting ('minimap.marks', {
      title = 'Mark the selection and problems',
      type = 'boolean',
      default = true,
      description = 'Shows selected lines, and lines with errors, warnings and hints, as full-width bands.',
    }, function (value)
      root:class ('no-marks', value == false)
    end)

    -- Where it shows -------------------------------------------------------------------------

    if editor.add_side then
      root:class ('in-editor', true)
      side = editor.add_side ({
        content = root,
        side = config.side == 'left' and 'left' or 'right',
        width = config.show == 'off' and 0 or config.width,
        over = config.placement ~= 'beside',
      })
    else
      app.use ('views').add ('right', {
        id = 'minimap',
        title = 'Minimap',
        icon = 'map',
        order = 90,
        content = root,
        on_show = function ()
          if stale then
            draw ()
          end
        end,
      })
    end

    if commands and settings then
      local last_shown = config.show ~= 'off' and config.show or 'always'
      commands.register ({
        id = 'minimap.toggle',
        category = 'View',
        title = 'Toggle Minimap',
        icon = 'map',
        run = function ()
          if config.show == 'off' then
            settings.set ('minimap.show', last_shown)
          else
            last_shown = config.show
            settings.set ('minimap.show', 'off')
          end
        end,
      })
    end

    tabs.on_change (soon)
    app.on ('editor:opened', soon)
    app.on ('editor:closed', soon)
    app.on ('editor:changed', function (doc)
      if shown and doc.path == shown.path then
        soon ()
      end
    end)
    app.on ('editor:scrolled', function (path, first, last)
      if shown and path == shown.path and visible () then
        place_box ({ first = first, last = last })
        follow ()
      end
    end)
    app.on ('editor:selected', function (path, ranges)
      if shown and path == shown.path then
        selected = ranges_of (ranges)
        draw_marks ()
      end
    end)
    app.on ('diagnostics:changed', function (path)
      if shown and path == shown.path then
        draw_marks ()
      end
    end)
    -- The minimap may show from the start, when a file was open last time.
    app.timer.after (PAUSE, soon)
  end,
}
