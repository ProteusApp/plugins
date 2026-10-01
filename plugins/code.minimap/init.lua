-- code.minimap: the whole file in front, in miniature, in a panel beside the code.
--
-- The panel sits in the right dock. It works wherever proteus.editor.core edits files, so in
-- the Code Editor and in the Plugin Editor alike. It redraws a moment after the text changes,
-- and when another tab comes to the front.
--
-- A box shades the lines on screen, and follows the editor as it scrolls. A click, or a drag
-- down the picture, scrolls the editor so the line under the pointer sits in the middle of
-- the screen, leaving the cursor where it was. When the picture is taller than the panel, it
-- scrolls along with the editor, so the box stays in sight.
--
-- A Proteus from before the editor told plugins where it is scrolled has no box. There a
-- click moves the cursor to the line instead, and a band marks the line it moved to.

local render = require ('minimap_render') --[[@as Minimap.RenderModule]]

-- The text waits this long after the last change before the picture redraws.
local PAUSE = 150
-- The height of one line of the picture, in pixels, for each `minimap.size`.
local LINE_HEIGHTS = { small = 2, medium = 3, large = 4 }

-- lang=css
local CSS = [[
.minimap { --minimap-line: 3px; display: flex; flex-direction: column; height: 100%; min-height: 0;
  background: var(--editor-bg, var(--bg)); }
.minimap-scroll { flex: 1; min-height: 0; overflow-x: hidden; overflow-y: auto; cursor: pointer;
  scrollbar-width: thin; }
.minimap-page { position: relative; min-height: 100%; }
.minimap-code { margin: 0; padding: 0 6px; overflow: hidden; white-space: pre; tab-size: 4;
  font-family: var(--font-mono); font-size: calc(var(--minimap-line) * 0.85);
  line-height: var(--minimap-line); color: var(--fg-muted); user-select: none; pointer-events: none; }
.minimap-code .k { color: var(--syn-keyword); }
.minimap-code .s { color: var(--syn-string); }
.minimap-code .c { color: var(--syn-comment); }
.minimap-code .n { color: var(--syn-number); }
.minimap-code .t { color: var(--syn-constant); }
.minimap-band, .minimap-hover, .minimap-view { position: absolute; left: 0; right: 0; display: none; pointer-events: none; }
.minimap-band { min-height: 2px; border-left: 2px solid var(--accent);
  background: color-mix(in srgb, var(--accent) 35%, transparent); }
.minimap-view { border-top: 1px solid color-mix(in srgb, var(--fg) 22%, transparent);
  border-bottom: 1px solid color-mix(in srgb, var(--fg) 22%, transparent);
  background: color-mix(in srgb, var(--fg) 10%, transparent); }
.minimap-hover { min-height: 2px; background: color-mix(in srgb, var(--fg) 14%, transparent); }
.minimap-scroll:hover .minimap-hover { display: block; }
.minimap-empty { padding: 12px; font-size: 12px; color: var(--fg-faint); }
.minimap-note { flex: none; padding: 4px 8px; border-top: 1px solid var(--border); font-size: 11px;
  color: var(--fg-faint); }
]]

---@type Proteus.Plugin
return {
  name = 'Minimap',
  description = 'Shows the file in front in miniature beside the code, shades the part on screen, and scrolls there on a click.',
  version = '1.0.0',
  -- `files` for the `editor` service, which hands over the text of the file in front.
  permissions = { 'files' },
  requires = { proteus = '>=0.3.0', features = { 'permissions' } },
  depends = {
    'proteus.lib.ui',
    'proteus.ui.views',
    'proteus.ui.tabs',
    'proteus.editor.core',
  },
  optional = { 'proteus.core.settings' },
  activate = function (app)
    local ui = app.use ('ui')
    local views = app.use ('views')
    local tabs = app.use ('tabs')
    local editor = app.use ('editor')
    local settings = app.try_use ('settings')
    ui.css (CSS)

    local painter = render.painter ()
    local line_h = LINE_HEIGHTS.medium

    local code = ui.pre ({ class = 'minimap-code' })
    local band = ui.div ({ class = 'minimap-band' })
    local box = ui.div ({ class = 'minimap-view' })
    local hover = ui.div ({ class = 'minimap-hover' })
    local scroller = ui.div ({
      class = 'minimap-scroll',
      ui.div ({ class = 'minimap-page', code, box, band, hover }),
    })
    local empty =
      ui.div ({ class = 'minimap-empty', 'Open a file to see its minimap.' })
    local note = ui.div ({ class = 'minimap-note' })
    local root = ui.div ({ class = 'minimap', scroller, empty, note })

    -- The document the picture shows, and how many of its lines it holds.
    local shown = nil ---@type { path: string, lines: integer }?
    -- The line the panel last moved the editor to, which the band marks.
    local jumped = nil ---@type integer?
    -- The lines on screen in the editor, which the box shades, when the editor tells them.
    local on_screen = nil ---@type { first: integer, last: integer }?
    -- True while a drag down the picture goes on.
    local dragging = false
    -- True when the text changed while the panel was out of sight.
    local stale = true
    local cancel_pause = nil ---@type fun()?

    ---True while the panel is on screen. A hidden dock leaves it with no width.
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
    ---@param lines { first: integer, last: integer }?
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

    ---Scrolls the picture along with the editor, for a file taller than the panel. At the
    ---top of the file the picture shows its top, and at the bottom its bottom, so the box
    ---never leaves the panel.
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

    ---Scrolls the picture so a line sits in view, for a file taller than the panel.
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
        shown, jumped = nil, nil
        code:html ('')
        place (band, nil)
        place_box (nil)
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
      place_box (doc.viewport and doc.viewport () or nil)
      follow ()
    end

    ---Redraws after a short pause, or once the panel shows when it is out of sight.
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
      jump (ev)
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
    app.dom.on_global ('mouseup', function ()
      if not dragging then
        return
      end
      -- The picture holds still under the pointer during a drag, then catches up.
      dragging = false
      if on_screen then
        jumped = nil
        follow ()
      end
    end)

    ---@param size any
    local function set_size (size)
      line_h = LINE_HEIGHTS[size] or LINE_HEIGHTS.medium
      root:style ('--minimap-line', line_h .. 'px')
      place (band, jumped)
      place_box (on_screen)
      follow ()
    end

    if settings then
      settings.define ('minimap.size', {
        title = 'Minimap size',
        type = 'select',
        options = { 'small', 'medium', 'large' },
        default = 'medium',
        description = 'How tall each line of the minimap is: 2, 3 or 4 pixels.',
      })
      settings.watch ('minimap.size', set_size)
    else
      set_size ('medium')
    end

    views.add ('right', {
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
    -- The panel may show from the start, when the dock was open last time.
    app.timer.after (PAUSE, soon)
  end,
}
