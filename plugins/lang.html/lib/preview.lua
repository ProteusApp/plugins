-- preview: shows the HTML file in front, rendered, in a panel in the right dock, beside the
-- code. It shows the file again a moment after typing stops, and when another HTML file
-- comes to the front. While a file of another kind is in front, it keeps the last page.
--
-- The page runs in a web view, under the app's strict policy. Inline `<style>` and
-- `<script>` work. Anything the page loads by address does not: linked stylesheets,
-- scripts, images and fonts. A note above the page says so. Unless `html.preview_scripts`
-- is on, the page's scripts are taken out before it shows.

local markup = require ('lib.markup') --[[@as LangHtml.Markup]]

-- The text waits this long after the last change before the page shows it.
local PAUSE = 400
-- The panel's id in the dock.
local VIEW = 'html.preview'

-- lang=css
local CSS = [[
.html-preview { display: flex; flex-direction: column; height: 100%; min-height: 0; }
.html-preview-head { flex: none; padding: 6px 10px; border-bottom: 1px solid var(--border); }
.html-preview-name { font-size: 12px; font-weight: 600; color: var(--fg); overflow: hidden;
  text-overflow: ellipsis; white-space: nowrap; }
.html-preview-note { font-size: 11px; color: var(--fg-faint); }
.html-preview-frame { flex: 1; min-height: 0; background: #fff; }
.html-preview-empty { padding: 12px; font-size: 12px; color: var(--fg-faint); }
]]

---A document as the preview reads it, from `editor.current` or `editor.docs`.
---@class LangHtml.Page
---@field path string
---@field text fun(): string

---@class LangHtml.Preview
---@field open fun() Shows the panel with the HTML file in front.

---@class LangHtml.PreviewModule
local M = {}

---@param ctx LangHtml.Context
---@return LangHtml.Preview
function M.install (ctx)
  local app, settings, editor = ctx.app, ctx.settings, ctx.editor
  local ui = app.use ('ui')
  local views = app.use ('views')
  local tabs = app.use ('tabs')
  ui.css (CSS)

  local name = ui.div ({ class = 'html-preview-name' })
  local note = ui.div ({ class = 'html-preview-note' })
  local head = ui.div ({ class = 'html-preview-head', name, note })
  local frame = ui.div ({ class = 'html-preview-frame' })
  local empty = ui.div ({
    class = 'html-preview-empty',
    'Open an HTML file to see it here.',
  })
  local root = ui.div ({ class = 'html-preview', head, frame, empty })

  -- True once the panel is in the dock. It joins the dock the first time it opens.
  local added = false
  -- The path of the file the page shows.
  local shown = nil ---@type string?
  -- The web view that shows it.
  local page = nil ---@type Proteus.El?
  -- How far each file's page was scrolled, so a new version opens at the same place.
  local scrolled = {} ---@type table<string, number>
  -- True when the shown file changed since the page showed it.
  local dirty = false
  -- True when something changed while the panel was out of sight.
  local stale = false
  local cancel = nil ---@type fun()?

  ---@return boolean
  local function visible ()
    return added and root:alive () and root:rect ().w > 0
  end

  ---@return boolean
  local function scripts_on ()
    return settings.get ('html.preview_scripts') == true
  end

  ---The file to show: the HTML file in front, or else the one shown last while it is open.
  ---@return LangHtml.Page?
  local function target ()
    local doc = editor.current ()
    if doc and markup.is_page (doc.path) then
      return doc
    end
    if shown then
      for _, d in ipairs (editor.docs ()) do
        if d.path == shown then
          return d
        end
      end
    end
    return nil
  end

  local function draw ()
    dirty = false
    local doc = target ()
    if page then
      page:remove ()
      page = nil
    end
    if not doc then
      shown = nil
      head:show (false)
      frame:show (false)
      empty:show (true)
      return
    end
    local path = doc.path
    shown = path
    name:text (path:match ('[^/\\]+$') or path)
    note:text (
      'Linked stylesheets, scripts and images do not load here.'
        .. (scripts_on () and '' or ' Scripts are off.')
    )
    page = ui.webview ({
      html = markup.page (doc.text (), scripts_on ()),
      on_message = function (message)
        if type (message) == 'table' and type (message.y) == 'number' then
          scrolled[path] = message.y
        end
      end,
    })
    frame:append (page)
    if scrolled[path] then
      page:widget ('post', { type = 'scroll', y = scrolled[path] })
    end
    empty:show (false)
    head:show (true)
    frame:show (true)
  end

  ---Shows the page again when its file changed, or when another file is to show.
  local function update ()
    local doc = target ()
    if dirty or not page or not doc or doc.path ~= shown then
      draw ()
    end
  end

  ---Updates after a short pause, or once the panel shows when it is out of sight.
  local function soon ()
    if not visible () then
      stale = true
      return
    end
    if cancel then
      cancel ()
    end
    cancel = app.timer.after (PAUSE, function ()
      cancel = nil
      update ()
    end)
  end

  tabs.on_change (soon)
  app.on ('editor:changed', function (doc)
    ---@cast doc Proteus.DocInfo
    if doc.path == shown then
      dirty = true
      soon ()
    end
  end)
  app.on ('editor:closed', function (path)
    if path == shown then
      soon ()
    end
  end)
  settings.watch ('html.preview_scripts', function ()
    dirty = true
    soon ()
  end)

  ---@type LangHtml.Preview
  return {
    open = function ()
      if not added then
        added = true
        views.add ('right', {
          id = VIEW,
          title = 'HTML Preview',
          icon = 'eye',
          content = root,
          on_show = function ()
            if stale then
              stale = false
              update ()
            end
          end,
        })
      end
      views.show (VIEW)
      dirty = true
      update ()
    end,
  }
end

return M
