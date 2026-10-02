-- preview: one rendered view of a Markdown file. The plugin makes one for the preview tab and
-- one for the preview at the side of the editor.
--
-- It renders a moment after the text stops changing, and only while it is on screen. A file
-- that changed while it was out of sight renders when it shows again. Each heading and the
-- text under it is a part of its own, so a link to a heading scrolls to that part, and the
-- line on top of the editor scrolls the preview to the same place.

local blocks = require ('lib.blocks') --[[@as LangMarkdown.BlocksModule]]
local links = require ('lib.links') --[[@as LangMarkdown.LinksModule]]
local render = require ('lib.render') --[[@as LangMarkdown.RenderModule]]

-- The text waits this long after the last change before the preview renders it again.
local PAUSE = 250
-- The room left above a heading that a link scrolls to, in pixels.
local MARGIN = 8

---A part on screen.
---@class LangMarkdown.Shown
---@field el Proteus.El
---@field html string
---@field line integer
---@field anchor? string

---@class LangMarkdown.PreviewOptions
---@field header? boolean Shows a bar on top with the file's name and a close button.
---@field on_close? fun() Runs when the close button is clicked.
---@field on_source? fun(path: string?) Runs when the preview starts to show another file.

---@class LangMarkdown.Preview
---@field root Proteus.El
---@field path fun(): string? The file it shows.
---@field show fun(path: string?) Shows a file, or the empty message for nil.
---@field wake fun() Renders soon, for a preview that just came on screen.
---@field changed fun(path: string) The text of a file changed.
---@field scrolled fun(path: string, first: integer) The editor scrolled a file.

---@class LangMarkdown.PreviewModule
local M = {}

-- The style sheet for every preview, and for the frame of the one at the side. The theme's
-- variables color it, so it matches any theme.
-- lang=css
M.CSS = [[
.md-preview { display: flex; flex-direction: column; height: 100%; min-height: 0;
  background: var(--editor-bg, var(--bg)); color: var(--fg); }
.md-head { flex: none; display: flex; align-items: center; gap: 6px; padding: 3px 4px 3px 12px;
  border-bottom: 1px solid var(--border); font-size: 12px; color: var(--fg-muted); }
.md-head-title { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis;
  white-space: nowrap; }
.md-scroll { position: relative; flex: 1; min-height: 0; overflow: auto; }
.md-empty { padding: 24px; font-size: 13px; color: var(--fg-faint); text-align: center; }
.md-body { max-width: 900px; margin: 0 auto; padding: 16px 28px 64px; font-size: 14px;
  line-height: 1.6; overflow-wrap: break-word; }
.md-body h1, .md-body h2, .md-body h3, .md-body h4, .md-body h5, .md-body h6 {
  margin: 1.4em 0 .6em; line-height: 1.25; font-weight: 600; }
.md-body h1 { font-size: 1.9em; padding-bottom: .25em; border-bottom: 1px solid var(--border); }
.md-body h2 { font-size: 1.45em; padding-bottom: .25em; border-bottom: 1px solid var(--border); }
.md-body h3 { font-size: 1.2em; }
.md-body h4 { font-size: 1em; }
.md-body h5 { font-size: .9em; }
.md-body h6 { font-size: .85em; color: var(--fg-muted); }
.md-part:first-child > :first-child { margin-top: 0; }
.md-body p, .md-body ul, .md-body ol, .md-body blockquote, .md-body pre, .md-body table {
  margin: 0 0 1em; }
.md-body ul, .md-body ol { padding-left: 2em; }
.md-body li + li { margin-top: .25em; }
.md-body li > ul, .md-body li > ol { margin: .25em 0 0; }
.md-body a { color: var(--accent); text-decoration: none; cursor: pointer; }
.md-body a:hover { text-decoration: underline; }
.md-body code { font-family: var(--font-mono); font-size: .88em; padding: .15em .4em;
  border-radius: 4px; background: var(--bg-alt); }
.md-body pre { padding: 12px 14px; overflow: auto; border-radius: var(--radius);
  background: var(--bg-alt); line-height: 1.45; }
.md-body pre code { padding: 0; font-size: 12.5px; background: none; }
.md-body blockquote { padding: 0 1em; color: var(--fg-muted); border-left: 3px solid var(--border); }
.md-body hr { height: 0; margin: 1.5em 0; border: 0; border-top: 1px solid var(--border); }
.md-body table { display: block; max-width: 100%; overflow: auto; border-collapse: collapse; }
.md-body th, .md-body td { padding: 5px 12px; border: 1px solid var(--border); }
.md-body th { font-weight: 600; background: var(--bg-alt); }
.md-body tr:nth-child(2n) td { background: color-mix(in srgb, var(--bg-alt) 50%, transparent); }
.md-body kbd { padding: .1em .4em; font-family: var(--font-mono); font-size: .85em;
  border: 1px solid var(--border); border-bottom-width: 2px; border-radius: 4px; }
.md-body img.md-img { max-width: 100%; }
.md-body li.md-task { list-style: none; }
.md-check { display: inline-block; box-sizing: border-box; width: 14px; height: 14px;
  margin: 0 6px 0 -20px; vertical-align: -2px; border: 1px solid var(--fg-muted);
  border-radius: 3px; }
.md-check.done { border-color: var(--accent); background: var(--accent); }
.md-check.done::after { content: ''; display: block; width: 4px; height: 8px; margin: 1px 0 0 4px;
  border: solid var(--accent-fg); border-width: 0 2px 2px 0; transform: rotate(45deg); }
.md-image { display: inline-block; padding: 2px 8px; font-size: .9em; color: var(--fg-muted);
  border: 1px dashed var(--border); border-radius: 4px; background: var(--bg-alt); }
.md-image::before { content: 'Image: '; color: var(--fg-faint); }
.md-side { position: relative; height: 100%; min-height: 0; border-left: 1px solid var(--border);
  pointer-events: auto; }
.md-side.off { display: none; }
.md-grip { position: absolute; top: 0; bottom: 0; left: -3px; z-index: 1; width: 6px;
  cursor: col-resize; }
.md-grip:hover { background: color-mix(in srgb, var(--accent) 40%, transparent); }
]]

---The last part of a path: the file's name.
---@param path string
---@return string
local function name_of (path)
  return path:match ('[^/\\]+$') or path
end

---@param ctx LangMarkdown.Context
---@param opts? LangMarkdown.PreviewOptions
---@return LangMarkdown.Preview
function M.new (ctx, opts)
  opts = opts or {}
  local app, ui, editor, settings = ctx.app, ctx.ui, ctx.editor, ctx.settings

  local body = ui.div ({ class = 'md-body' })
  local empty = ui.div ({
    class = 'md-empty',
    'Open a Markdown file to see its preview.',
  })
  local scroller = ui.div ({ class = 'md-scroll', empty, body })
  local title = ui.span ({ class = 'md-head-title' })
  local root = ui.div ({ class = 'md-preview' })
  if opts.header then
    root:append (ui.div ({
      class = 'md-head',
      title,
      ui.button ({
        icon = 'x',
        variant = 'ghost',
        title = 'Close the preview',
        onclick = function ()
          if opts.on_close then
            opts.on_close ()
          end
          return 'stop'
        end,
      }),
    }))
  end
  root:append (scroller)

  local source = nil ---@type string?
  local shown = {} ---@type LangMarkdown.Shown[]
  local lines = 0
  local cache = {} ---@type table<string, string>
  local stale = false
  local cancel = nil ---@type fun()?
  -- True once the file now in `source` has been drawn.
  local drawn = false

  ---@return boolean
  local function visible ()
    return root:alive () and root:rect ().w > 0
  end

  ---The open document at a path.
  ---@param path string
  ---@return Proteus.DocInfo?
  local function doc_at (path)
    for _, doc in ipairs (editor.docs ()) do
      if doc.path == path then
        return doc
      end
    end
    return nil
  end

  ---The document in front, when it is the file this preview shows.
  ---@return Proteus.CurrentDoc?
  local function current_source ()
    local doc = editor.current ()
    if doc and doc.path == source then
      return doc
    end
    return nil
  end

  ---How far down the page an element starts, in pixels.
  ---@param el Proteus.El
  ---@return number
  local function top_of (el)
    local scroll = tonumber (scroller:get ('scrollTop')) or 0
    return el:rect ().top - scroller:rect ().top + scroll
  end

  ---Scrolls the preview so a line of the file sits on top.
  ---@param first integer
  local function follow_line (first)
    if first <= 1 then
      scroller:set ('scrollTop', 0)
      return
    end
    local index, fraction = blocks.locate (shown, first, lines)
    local part = index and shown[index]
    if not part then
      return
    end
    local top = top_of (part.el) + fraction * part.el:rect ().h
    scroller:set ('scrollTop', math.max (0, math.floor (top)))
  end

  ---@return boolean
  local function syncing ()
    return settings.get ('markdown.preview_sync_scroll') ~= false
  end

  ---Scrolls to the heading a `#link` names. While the preview scrolls with the editor, the
  ---editor moves to the heading too, so the two agree. Returns false when there is no such
  ---heading.
  ---@param anchor string
  ---@return boolean
  local function reveal (anchor)
    local want = anchor:lower ()
    for _, part in ipairs (shown) do
      if part.anchor and part.anchor:lower () == want then
        local doc = syncing () and current_source () or nil
        if doc and doc.scroll_to then
          doc.scroll_to (part.line)
        end
        scroller:set ('scrollTop', math.max (0, top_of (part.el) - MARGIN))
        return true
      end
    end
    return false
  end

  ---Puts the page's parts on screen, changing only those whose HTML changed.
  ---@param page LangMarkdown.Page
  local function place (page)
    for i, part in ipairs (page.parts) do
      local old = shown[i]
      if old then
        if old.html ~= part.html then
          old.el:html (part.html)
          old.html = part.html
        end
        old.line, old.anchor = part.line, part.anchor
      else
        local el = ui.div ({ class = 'md-part', html = part.html })
        body:append (el)
        shown[i] =
          { el = el, html = part.html, line = part.line, anchor = part.anchor }
      end
    end
    for i = #shown, #page.parts + 1, -1 do
      shown[i].el:remove ()
      shown[i] = nil
    end
    lines = page.lines
  end

  local function draw ()
    if not visible () then
      stale = true
      return
    end
    stale = false
    if not source then
      return
    end
    local doc = doc_at (source)
    if not doc then
      -- The file closed. What shows stays until another file comes.
      return
    end
    local page
    page, cache = render.page (doc.text (), app.util.safe_markdown, cache)
    place (page)
    empty:show (#page.parts == 0)
    if #page.parts == 0 then
      empty:text ('This file is empty.')
    end
    local first_time = not drawn
    drawn = true
    local anchor = ctx.pending[source]
    if anchor then
      ctx.pending[source] = nil
      reveal (anchor)
    elseif first_time and syncing () then
      local front = current_source ()
      local on_screen = front and front.viewport and front.viewport ()
      if on_screen then
        follow_line (on_screen.first)
      end
    end
  end

  ---Renders after a short pause.
  local function soon ()
    if cancel then
      cancel ()
    end
    cancel = app.timer.after (PAUSE, function ()
      cancel = nil
      draw ()
    end)
  end

  ---Follows a click on a link.
  ---@param target LangMarkdown.Target
  local function go (target)
    if target.kind == 'anchor' then
      reveal (target.anchor or '')
    elseif target.kind == 'web' and target.url then
      app.system.open_url (target.url)
    elseif target.kind == 'file' and target.path and source then
      local path = links.resolve (source, target.path, ctx.root_for (source))
      if not path or path:sub (-1) == '/' then
        ctx.notify ('The link does not lead to a file: ' .. target.path)
        return
      end
      if path == source then
        if target.anchor then
          reveal (target.anchor)
        end
        return
      end
      ctx.pending[path] = target.anchor
      editor.open_file (path)
    else
      ctx.notify ('The preview cannot open this link: ' .. (target.url or ''))
    end
  end

  body:on ('click', function (ev)
    local item = ev.item
    if not item or ev.button == 2 then
      return nil
    end
    local target = nil ---@type LangMarkdown.Target?
    local address = item:match ('^go:(.*)$')
    if address then
      target = links.classify (address)
    else
      local url = item:match ('^link:(.+)$')
      target = url and { kind = 'web', url = url } or nil
    end
    if not target then
      return nil
    end
    go (target)
    return 'stop'
  end)

  ---@type LangMarkdown.Preview
  return {
    root = root,
    path = function ()
      return source
    end,
    show = function (path)
      if path == source then
        if stale or not drawn then
          soon ()
        end
        return
      end
      source, drawn, cache = path, false, {}
      for _, part in ipairs (shown) do
        part.el:remove ()
      end
      shown = {}
      scroller:set ('scrollTop', 0)
      title:text (path and name_of (path) or '')
      empty:text ('Open a Markdown file to see its preview.')
      empty:show (path == nil)
      if opts.on_source then
        opts.on_source (path)
      end
      if path then
        soon ()
      end
    end,
    wake = function ()
      if stale or not drawn then
        soon ()
      end
    end,
    changed = function (path)
      if path == source then
        soon ()
      end
    end,
    scrolled = function (path, first)
      if path == source and drawn and syncing () and visible () then
        follow_line (first)
      end
    end,
  }
end

return M
