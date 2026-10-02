-- lang.markdown: Markdown in the code editor, with Marksman and a live preview.
--
-- Marksman's language server gives completion for links and headings, go to definition,
-- hover help and problems, such as a link to a heading that is not there. When Marksman is
-- not on the PATH, the Tools panel offers its official release, checked against a pinned
-- checksum. Prettier ships inside the app and formats Markdown already, so this plugin adds
-- no formatter.
--
-- The preview shows the file rendered, a moment after the typing stops. It comes in two
-- places:
--   Open Preview              a tab of its own, in place of the code, as a document to read.
--   Open Preview to the Side  a panel inside the editor, beside the text. The tabs service
--                             has no split view, so the editor's side is the one place the
--                             preview and the code show together. The side moves into each
--                             document that comes to the front, so it follows the tab in
--                             front by itself. It hides for files that are not Markdown.
-- A Proteus whose editor has no side for plugins shows the side preview in the right dock.
--
-- The parts live in lib/:
--   release   the Marksman download for each platform
--   server    starts and stops the language server
--   blocks    cuts a file into parts at its headings, for links and scrolling
--   links     links and images before and after rendering
--   render    the HTML of each part
--   preview   one rendered view, with its clicks and scrolling

local preview_module = require ('lib.preview') --[[@as LangMarkdown.PreviewModule]]
local release = require ('lib.release') --[[@as Proteus.ToolRelease]]
local server_module = require ('lib.server') --[[@as LangMarkdown.ServerModule]]

-- The narrowest and widest the side preview may be, in pixels.
local MIN_WIDTH, MAX_WIDTH = 240, 1600

---What the parts of the plugin share.
---@class LangMarkdown.Context
---@field app Proteus.App
---@field ui Proteus.UI
---@field settings Proteus.Settings
---@field editor Proteus.Editor
---@field pending table<string, string> A heading to scroll to once a file shows, by its path.
---@field root_for fun(path: string): string? Where a link that starts with `/` starts.
---@field notify fun(text: string) A warning, when ui.notify runs.

---The name of the file at a path.
---@param path string
---@return string
local function name_of (path)
  return path:match ('[^/\\]+$') or path
end

---@type Proteus.Plugin
return {
  name = 'Markdown',
  description = 'Markdown with Marksman: completion for links and headings, go to definition and problems, and a live preview beside the code.',
  version = '1.0.2',
  requires = { proteus = '>=0.3.0', features = { 'permissions' } },
  -- Marksman is a program it runs and downloads, on files anywhere on disk. `files` also
  -- lets it use the `editor` service, which hands over the text the preview shows. `net`
  -- opens a web link from the preview in the browser.
  permissions = { 'files', 'process', 'net' },
  depends = {
    'proteus.lib.ui',
    'proteus.core.settings',
    'proteus.core.commands',
    'proteus.editor.core',
    'proteus.tools.registry',
    'proteus.tools.diagnostics',
    'proteus.ui.tabs',
    'proteus.ui.views',
  },
  optional = { 'proteus.code.project', 'proteus.ui.notify' },
  activate = function (app)
    local ui = app.use ('ui')
    local settings = app.use ('settings')
    local editor = app.use ('editor')
    local tabs = app.use ('tabs')
    ui.css (preview_module.CSS)

    settings.define ('markdown.enabled', {
      title = 'Run the Markdown language server',
      type = 'boolean',
      default = true,
      description = 'Completion, go to definition and problems in Markdown files, from Marksman.',
    })
    settings.define ('markdown.preview_follow', {
      title = 'Preview tab follows the file in front',
      type = 'boolean',
      default = true,
      description = 'The preview tab switches to each Markdown file that comes to the front. Off, it keeps the file it opened with.',
    })
    settings.define ('markdown.preview_sync_scroll', {
      title = 'Scroll the preview with the editor',
      type = 'boolean',
      default = true,
      description = 'The preview keeps the part of the file on top of the editor on top of the preview too.',
    })
    settings.define ('markdown.preview_width', {
      title = 'Width of the preview at the side',
      type = 'number',
      default = 520,
      description = 'In pixels, from 240 to 1600. Dragging the preview by its left edge changes it too.',
    })

    ---@type LangMarkdown.Context
    local ctx = {
      app = app,
      ui = ui,
      settings = settings,
      editor = editor,
      pending = {},
      root_for = function (path)
        -- A full path is a file on disk, whose top is the open folder. A workspace path's
        -- top is the workspace.
        if path:match ('^%a:[/\\]') or path:sub (1, 1) == '/' then
          local project = app.try_use ('project')
          return project and project.root () or nil
        end
        return ''
      end,
      notify = function (text)
        local n = app.try_use ('notify')
        if n then
          n.warn (text)
        end
      end,
    }

    -- The language server ------------------------------------------------------------------

    local server ---@type LangMarkdown.Server
    local tool = app.use ('tools').register ({
      id = 'marksman',
      name = 'Marksman',
      description = 'Completion, go to definition and problems for Markdown.',
      program = 'marksman',
      kind = 'server',
      install = 'brew install marksman',
      languages = { 'markdown' },
      homepage = 'https://github.com/artempyanykh/marksman',
      settings = { 'markdown.enabled' },
      release = release,
      start = function ()
        server.start (nil)
      end,
      stop = function ()
        server.stop ()
      end,
      check = function ()
        server.stop ()
        server.start (nil)
      end,
    })
    server = server_module.install (ctx, tool)

    -- The preview tab ----------------------------------------------------------------------

    local TAB = 'markdown.preview'
    local tab_preview = nil ---@type LangMarkdown.Preview?

    ---The Markdown document in front, if any.
    ---@return Proteus.CurrentDoc?
    local function front_markdown ()
      local doc = editor.current ()
      if doc and doc.language == 'markdown' then
        return doc
      end
      return nil
    end

    ---@param path string
    local function open_tab (path)
      -- Closing the tab may take its content away for good, so the next one starts afresh.
      if not tab_preview or not tab_preview.root:alive () then
        tab_preview = preview_module.new (ctx, {
          on_source = function (shown)
            local tab = tabs.get (TAB)
            if tab and shown then
              tab.set_title ('Preview ' .. name_of (shown))
              tab.set_tooltip (shown)
            end
          end,
        })
      end
      local own = tab_preview
      tabs.open ({
        id = TAB,
        title = 'Preview ' .. name_of (path),
        tooltip = path,
        icon = 'book-open',
        content = own.root,
        on_focus = function ()
          own.wake ()
        end,
        on_close = function ()
          tab_preview = nil
          return true
        end,
      })
      own.show (path)
      own.wake ()
    end

    -- The preview at the side --------------------------------------------------------------

    local side_open = app.store.get ('side_open', false) == true
    local width = 520
    local side = nil ---@type Proteus.EditorSide?
    local side_preview = nil ---@type LangMarkdown.Preview?
    local side_root = nil ---@type Proteus.El?
    -- True when the side preview lives in the right dock, on an editor with no side.
    local docked = false
    local dragging = nil ---@type { x: number, width: integer }?

    ---Puts the side preview on screen for a Markdown file in front, and off it otherwise.
    local function place_side ()
      if not side_preview or not side_root then
        return
      end
      local doc = front_markdown ()
      if docked then
        if side_open and doc then
          side_preview.show (doc.path)
          side_preview.wake ()
        end
        return
      end
      local on = side_open and doc ~= nil
      side_root:class ('off', not on)
      if side then
        side.set ({ width = on and width or 0 })
      end
      if on and doc then
        side_preview.show (doc.path)
        side_preview.wake ()
      end
    end

    local function close_side ()
      side_open = false
      app.store.set ('side_open', false)
      if docked then
        app.use ('views').toggle ('preview')
      end
      place_side ()
    end

    local function make_side ()
      if side_preview then
        return
      end
      side_preview =
        preview_module.new (ctx, { header = true, on_close = close_side })
      -- A strip along the left edge, which drags the preview wider or narrower.
      local grip = ui.div ({ class = 'md-grip', title = 'Drag to resize' })
      grip:on ('mousedown', function (ev)
        if ev.button ~= 0 or not ev.x then
          return nil
        end
        dragging = { x = ev.x, width = width }
        return true
      end)
      side_root = ui.div ({ class = 'md-side', grip, side_preview.root })
      if editor.add_side then
        side = editor.add_side ({
          content = side_root,
          side = 'right',
          width = 0,
          over = false,
        })
      else
        docked = true
        grip:show (false)
        app.use ('views').add ('right', {
          id = 'preview',
          title = 'Markdown Preview',
          icon = 'book-open',
          order = 80,
          content = side_root,
          on_show = function ()
            place_side ()
          end,
        })
      end
    end

    local function open_side ()
      side_open = true
      app.store.set ('side_open', true)
      make_side ()
      if docked then
        app.use ('views').show ('preview')
      end
      place_side ()
    end

    app.dom.on_global ('mousemove', function (ev)
      if not dragging or not ev.x or not side then
        return nil
      end
      local wanted = dragging.width + (dragging.x - ev.x)
      width = math.floor (math.max (MIN_WIDTH, math.min (MAX_WIDTH, wanted)))
      side.set ({ width = width })
      return nil
    end)
    app.dom.on_global ('mouseup', function ()
      if not dragging then
        return nil
      end
      dragging = nil
      settings.set ('markdown.preview_width', width)
      return nil
    end)

    settings.watch ('markdown.preview_width', function (value)
      local n = math.floor (tonumber (value) or 520)
      width = math.max (MIN_WIDTH, math.min (MAX_WIDTH, n))
      if not dragging then
        place_side ()
      end
    end)

    -- Commands -----------------------------------------------------------------------------

    local commands = app.use ('commands')
    commands.register ({
      id = 'markdown.preview',
      category = 'Markdown',
      title = 'Open Preview',
      icon = 'book-open',
      key = 'ctrl+shift+v',
      menu = 'View',
      group = 'markdown',
      when = function ()
        return front_markdown () ~= nil
      end,
      run = function ()
        local doc = front_markdown ()
        if doc then
          open_tab (doc.path)
        end
      end,
    })
    commands.register ({
      id = 'markdown.preview_side',
      category = 'Markdown',
      title = 'Open Preview to the Side',
      icon = 'columns-2',
      -- The keys service has no two-key chords, so VS Code's Ctrl+K V becomes Ctrl+Alt+V.
      key = 'ctrl+alt+v',
      menu = 'View',
      group = 'markdown',
      when = function ()
        return front_markdown () ~= nil
      end,
      run = open_side,
    })
    commands.register ({
      id = 'markdown.close_preview_side',
      category = 'Markdown',
      title = 'Close Preview to the Side',
      icon = 'x',
      when = function ()
        return side_open
      end,
      run = close_side,
    })
    commands.register ({
      id = 'markdown.restart',
      category = 'Markdown',
      title = 'Restart Marksman',
      icon = 'rotate-cw',
      run = function ()
        server.stop ()
        server.start (nil)
      end,
    })

    -- Following the editor -----------------------------------------------------------------

    ---The preview in the tab, while the tab is open.
    ---@return LangMarkdown.Preview?
    local function open_tab_preview ()
      if tab_preview and not tabs.get (TAB) then
        tab_preview = nil
      end
      return tab_preview
    end

    ---@return LangMarkdown.Preview[]
    local function previews ()
      local list = {} ---@type LangMarkdown.Preview[]
      local in_tab = open_tab_preview ()
      if in_tab then
        list[#list + 1] = in_tab
      end
      if side_preview then
        list[#list + 1] = side_preview
      end
      return list
    end

    local function front_changed ()
      local doc = front_markdown ()
      local in_tab = open_tab_preview ()
      if
        doc
        and in_tab
        and settings.get ('markdown.preview_follow') ~= false
      then
        in_tab.show (doc.path)
      end
      place_side ()
    end

    tabs.on_change (front_changed)
    app.on ('editor:opened', front_changed)
    app.on ('editor:changed', function (doc)
      ---@cast doc Proteus.DocInfo
      for _, p in ipairs (previews ()) do
        p.changed (doc.path)
      end
    end)
    app.on ('editor:scrolled', function (path, first)
      for _, p in ipairs (previews ()) do
        p.scrolled (path, first)
      end
    end)

    if side_open then
      make_side ()
      place_side ()
    end
    server.start (nil)
  end,
}
