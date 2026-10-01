-- viewer: opens files of some kinds in a tab of their own, with a web view page that shows
-- them. The page gets the file's bytes from the app, since Lua cannot read a binary file.
--
-- Each tab holds a bar along the top, made here, and the page under it. The plugin adds its
-- own buttons to the bar and writes the line of facts at its right. A tab reads its file
-- again when the file changes on disk, and when the Reload button is pressed.
--
-- The first half of this file is plain functions on paths and sizes, which the tests check.

local M = {}

-- A file that changes waits this long before it reloads, so a burst of writes reloads once.
local SETTLE = 200

-- lang=css
M.CSS = [[
.vw-root { display: flex; flex-direction: column; height: 100%; min-height: 0; }
.vw-bar { display: flex; align-items: center; gap: 2px; flex: none; padding: 3px 6px;
  border-bottom: 1px solid var(--border); background: var(--bg-alt); font-size: 12px; }
.vw-bar .ui-button { padding: 2px 6px; }
.vw-bar .vw-on { background: var(--bg-active); color: var(--fg); }
.vw-sep { width: 1px; height: 16px; margin: 0 4px; background: var(--border); }
.vw-grow { flex: 1; }
.vw-info { overflow: hidden; color: var(--fg-muted); font-family: var(--font-mono);
  font-size: 11px; white-space: nowrap; text-overflow: ellipsis; }
.vw-info.vw-error { color: var(--danger); }
.vw-page { position: relative; flex: 1; min-height: 0; }
]]

---The extension of a path, in lower case, or nil when it has none.
---@param path string
---@return string?
function M.extension (path)
  local name = M.name (path)
  local ext = name:match ('%.([^.]+)$')
  return ext and ext:lower () or nil
end

---The file name at the end of a path.
---@param path string
---@return string
function M.name (path)
  return path:match ('[^/\\]+$') or path
end

---True for a full path on disk, such as `C:/code/a.png` or `/home/me/a.png`, and false for
---a workspace path, such as `plugins/mine/a.png`.
---@param path string
---@return boolean
function M.is_full (path)
  return path:match ('^%a:[/\\]') ~= nil
    or path:sub (1, 1) == '/'
    or path:sub (1, 2) == '\\\\'
end

---A form of the path for telling whether two paths are the same file. Back slashes turn
---into forward ones. A Windows path is in lower case, since Windows ignores case.
---@param path string
---@return string
function M.key (path)
  local p = path:gsub ('\\', '/')
  if p:match ('^%a:/') or p:sub (1, 2) == '//' then
    p = p:lower ()
  end
  return p
end

---True when a path ends in one of the extensions.
---@param extensions table<string, any> Extensions in lower case, without the dot.
---@param path any
---@return boolean
function M.opens (extensions, path)
  if type (path) ~= 'string' then
    return false
  end
  local ext = M.extension (path)
  return ext ~= nil and extensions[ext] ~= nil
end

---A number of bytes the way people read it, such as `912 B`, `34.2 KB` or `1.5 MB`.
---@param bytes number
---@return string
function M.size_text (bytes)
  if bytes < 1024 then
    return string.format ('%d B', bytes)
  end
  local units = { 'KB', 'MB', 'GB' }
  local value = bytes / 1024
  local unit = 1
  while value >= 1024 and unit < #units do
    value = value / 1024
    unit = unit + 1
  end
  local text = value < 100 and string.format ('%.1f', value)
    or string.format ('%d', math.floor (value + 0.5))
  return (text:gsub ('%.0$', '')) .. ' ' .. units[unit]
end

---A zoom factor as a percentage, such as `100%` or `12.5%`.
---@param zoom number
---@return string
function M.zoom_text (zoom)
  local percent = zoom * 100
  if percent >= 100 then
    return string.format ('%d%%', math.floor (percent + 0.5))
  end
  return (string.format ('%.1f', percent):gsub ('%.0$', '')) .. '%'
end

---True when a list of changes on disk touches the file, other than removing it.
---@param key string The file's path, as `M.key` gives it.
---@param changes any A Proteus.DirChange list.
---@return boolean
function M.touches (key, changes)
  if type (changes) ~= 'table' then
    return false
  end
  for _, change in ipairs (changes) do
    if
      type (change) == 'table'
      and type (change.path) == 'string'
      and change.kind ~= 'remove'
      and M.key (change.path) == key
    then
      return true
    end
  end
  return false
end

---@class Viewer.View
---@field path string The file, as the editor gave it.
---@field key string The path, as `M.key` gives it.
---@field name string The file name.
---@field tab Proteus.Tab
---@field page Proteus.El The web view.
---@field bar Proteus.El The bar along the top, for the plugin's buttons.
---@field post fun(message: table) Sends a message to the page.
---@field reload fun() Sends the file to the page again.
---@field info fun(text: string, error?: boolean) Writes the line of facts in the bar.
---@field state table Anything the plugin keeps for this tab.

---@class Viewer.Spec
---@field prefix string Starts each tab id, such as `images`.
---@field extensions table<string, any> The extensions it opens, in lower case. A string value goes to the page with the file, as `tag.kind`.
---@field icon string The tab's Lucide icon when the icon packs have none for the file.
---@field page string The web view page, such as `page/index.html`.
---@field noun string What the file is called in titles, such as `Image`.
---@field build? fun(view: Viewer.View) Adds the plugin's buttons to a new tab's bar.
---@field on_message? fun(view: Viewer.View, message: table) A message from a tab's page.

---@class Viewer.Service
---@field active fun(): Viewer.View? The tab in front, when it is one of these.
---@field each fun(fn: fun(view: Viewer.View)) Runs `fn` for every open tab.
---@field open fun(path: string) Opens a file in a tab, or brings its tab to the front.

---Opens files of the kinds in `spec.extensions` in tabs of their own. Needs the services
---`ui`, `tabs` and `editor`, and uses `commands`, `themes` and `icons` when they run.
---@param app Proteus.App
---@param spec Viewer.Spec
---@return Viewer.Service
function M.start (app, spec)
  local ui = app.use ('ui')
  local tabs = app.use ('tabs')
  local editor = app.use ('editor')
  local commands = app.try_use ('commands')
  ui.css (M.CSS)

  local views = {} ---@type table<string, Viewer.View>

  ---The colors and fonts of the theme in use, for the pages. A page cannot read the app's
  ---style, so it gets them in a message. Nil when the themes service is not there.
  ---@return table?
  local function theme ()
    local themes = app.try_use ('themes')
    if not themes then
      return nil
    end
    local ok, message = pcall (function ()
      local vars = {} ---@type table<string, string>
      for k, v in pairs (themes.defaults () or {}) do
        vars[tostring (k)] = tostring (v)
      end
      local current = themes.current ()
      local dark = true
      for _, t in ipairs (themes.list () or {}) do
        if t.id == current then
          for k, v in pairs (t.vars or {}) do
            vars[tostring (k)] = tostring (v)
          end
          dark = t.dark ~= false
        end
      end
      return { type = 'theme', vars = vars, dark = dark }
    end)
    return ok and message or nil
  end

  ---The icon a tab shows: the one the icon packs give the file, or the plugin's own.
  ---@param path string
  ---@return string|Proteus.FileIcon
  local function icon_for (path)
    local icons = app.try_use ('icons')
    local found = icons and icons.file (path)
    return found or spec.icon
  end

  ---@param path string
  local function open (path)
    local key = M.key (path)
    local id = spec.prefix .. ':' .. key
    local existing = tabs.get (id)
    if existing then
      existing.focus ()
      return
    end

    local view ---@type Viewer.View
    local info = ui.span ({ class = 'vw-info', '' })
    local bar = ui.div ({ class = 'vw-bar' })
    local page = ui.webview ({
      page = spec.page,
      on_message = function (message)
        if type (message) == 'table' and view and spec.on_message then
          spec.on_message (view, message)
        end
      end,
      on_status = function (status)
        if view and not status.responsive then
          view.info (status.error or 'The page stopped answering.', true)
        end
      end,
    })
    local root = ui.div ({
      class = 'vw-root',
      bar,
      ui.div ({ class = 'vw-page', page }),
    })

    local cancel_reload = nil ---@type fun()?

    view = {
      path = path,
      key = key,
      name = M.name (path),
      page = page,
      bar = bar,
      state = {},
      tab = nil --[[@as Proteus.Tab]],
      post = function (message)
        page:widget ('post', message)
      end,
      info = function (text, error)
        info:text (text)
        info:class ('vw-error', error == true)
      end,
      reload = function ()
        if cancel_reload then
          cancel_reload ()
          cancel_reload = nil
        end
        local kind = spec.extensions[M.extension (path) or '']
        local tag = {
          name = M.name (path),
          kind = type (kind) == 'string' and kind or nil,
        }
        local ok, err = pcall (page.widget, page, 'send_path', path, tag)
        if not ok then
          view.info (tostring (err), true)
          view.post ({ type = 'failed', error = tostring (err) })
        end
      end,
    }

    ---Reloads a moment from now, so a burst of changes reloads once.
    function view.state.reload_soon ()
      if cancel_reload then
        cancel_reload ()
      end
      cancel_reload = app.timer.after (SETTLE, function ()
        cancel_reload = nil
        view.reload ()
      end)
    end

    if spec.build then
      spec.build (view)
    end
    bar:append (ui.span ({ class = 'vw-grow' }))
    bar:append (info)
    bar:append (ui.button ({
      icon = 'refresh-cw',
      variant = 'ghost',
      title = 'Read the file again',
      onclick = function ()
        view.reload ()
      end,
    }))

    views[id] = view
    view.tab = tabs.open ({
      id = id,
      title = view.name,
      tooltip = path,
      icon = icon_for (path),
      content = root,
      data = { path = path },
      on_close = function ()
        views[id] = nil
        if cancel_reload then
          cancel_reload ()
        end
        return true
      end,
    })

    local colors = theme ()
    if colors then
      view.post (colors)
    end
    view.reload ()
  end

  editor.add_opener (function (path)
    if not M.opens (spec.extensions, path) then
      return false
    end
    open (path)
    return true
  end)

  ---@param fn fun(view: Viewer.View)
  local function each (fn)
    for _, view in pairs (views) do
      fn (view)
    end
  end

  ---@return Viewer.View?
  local function active ()
    local tab = tabs.active ()
    return tab and views[tab.id] or nil
  end

  app.on ('themes:applied', function ()
    local colors = theme ()
    if colors then
      each (function (view)
        view.post (colors)
      end)
    end
  end)

  -- A workspace file that changed. The Plugin Editor opens files by workspace path.
  app.on ('fs:changed', function (path)
    if type (path) ~= 'string' then
      return
    end
    local key = M.key (path)
    each (function (view)
      if not M.is_full (view.path) and view.key == key then
        view.state.reload_soon ()
      end
    end)
  end)

  -- Files that changed in the folder open in the Code Editor, by full path.
  app.on ('code:disk_changed', function (changes, ev)
    local all = type (ev) == 'table' and ev.overflow == true
    each (function (view)
      if M.is_full (view.path) and (all or M.touches (view.key, changes)) then
        view.state.reload_soon ()
      end
    end)
  end)

  if commands then
    commands.register ({
      id = spec.prefix .. '.reload',
      category = spec.noun,
      title = 'Reload the ' .. spec.noun,
      icon = 'refresh-cw',
      when = function ()
        return active () ~= nil
      end,
      run = function ()
        local view = active ()
        if view then
          view.reload ()
        end
      end,
    })
  end

  return { active = active, each = each, open = open }
end

return M
