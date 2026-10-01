-- server: runs Some Sass for Sass files. It starts for the first `.scss` or `.sass` file that
-- opens, and hears again whenever one of its settings changes. When lang.css starts later,
-- the help for `.scss` files moves to lang.css's `css` service, and plain `.css` files go
-- to lang.css.

local attach_module = require ('lib.attach') --[[@as LangSass.AttachModule]]
local client_module = require ('lib.client') --[[@as LangSass.ClientModule]]
local disk = require ('disk_paths') --[[@as DiskPaths]]
local languages = require ('lib.languages') --[[@as LangSass.LanguagesModule]]

-- Some Sass asks for its settings under this name.
local SECTION = 'somesass'

---@class LangSass.Server
---@field start fun(doc: Proteus.DocInfo?)
---@field stop fun()

---@class LangSass.ServerModule
local M = {}

---@param ctx LangSass.Context
---@param tool Proteus.ToolHandle
---@return LangSass.Server
function M.install (ctx, tool)
  local app, settings, editor = ctx.app, ctx.settings, ctx.editor
  local starting = false
  local server ---@type LangSass.Server

  ---@return table
  local function config ()
    return languages.config (
      settings.get ('sass.load_paths'),
      settings.get ('sass.use_only') == true
    )
  end

  ---lang.css's `css` service, while it runs.
  ---@return LangSass.CssService?
  local function css ()
    return attach_module.find_css (app.try_use)
  end

  ---True when Some Sass serves plain `.css` files: `sass.css` is on, and lang.css, which
  ---serves them otherwise, is not running.
  ---@return boolean
  local function with_css ()
    return settings.get ('sass.css') == true and css () == nil
  end

  ---What the server calls a file, or nil when it leaves the file alone.
  ---@param doc Proteus.DocInfo
  ---@return string?
  local function language_id (doc)
    return languages.language_id (doc.path, doc.language, with_css ())
  end

  local client = client_module.new (app, {
    name = 'Some Sass',
    languages = languages.EDITOR_LANGUAGES,
    language_id = language_id,
    source = 'sass',
    tool = tool,
    config = function (section)
      return section == SECTION and config () or nil
    end,
    css = css,
  })

  ---@return Proteus.DocInfo?
  local function first_sass_doc ()
    for _, doc in ipairs (editor.docs ()) do
      if language_id (doc) then
        return doc
      end
    end
    return nil
  end

  ---The folder the server works on: the open folder, or else the file's own folder.
  ---@param doc Proteus.DocInfo
  ---@return string
  local function root_for (doc)
    local project = app.try_use ('project')
    return project and project.root () or disk.parent (client.to_disk (doc))
  end

  server = {
    start = function (doc)
      if client.running () or starting then
        return
      end
      if settings.get ('sass.enabled') ~= true then
        tool.set_state ('stopped', 'switched off in Settings (sass.enabled)')
        return
      end
      doc = doc or first_sass_doc ()
      local root = doc and root_for (doc)
      if not root then
        tool.set_state ('stopped', 'starts when a Sass file opens')
        return
      end
      starting = true
      tool.locate (function (program)
        starting = false
        if not program then
          tool.set_state (
            'missing',
            'some-sass-language-server is not on the PATH'
          )
          return
        end
        tool.set_path (program)
        client.start (program, { '--stdio' }, root)
      end)
    end,
    stop = function ()
      client.stop ()
    end,
  }

  app.on ('editor:opened', function (doc)
    ---@cast doc Proteus.DocInfo
    if language_id (doc) and not client.running () then
      server.start (doc)
    end
  end)

  ---Calls `fn` when a setting changes, but not for the first call `watch` makes at once.
  ---@param key string
  ---@param fn fun()
  local function on_change (key, fn)
    local first = true
    settings.watch (key, function ()
      if first then
        first = false
        return
      end
      fn ()
    end)
  end

  -- lang.css started after this plugin. It owns `css` now, so the help for `.scss` files goes
  -- through its service. Plain `.css` files go to it too, so a server that holds them starts
  -- over without them.
  app.on ('kernel:service', function (name)
    if name ~= 'css' or not client.running () then
      return
    end
    if settings.get ('sass.css') == true then
      server.stop ()
      server.start (nil)
    else
      client.reattach ()
    end
  end)

  -- Plain CSS changes which files the server holds, so it starts over.
  for _, key in ipairs ({ 'sass.enabled', 'sass.css' }) do
    on_change (key, function ()
      server.stop ()
      server.start (nil)
    end)
  end

  for _, key in ipairs ({ 'sass.load_paths', 'sass.use_only' }) do
    on_change (key, function ()
      if client.ready () then
        client.notify ('workspace/didChangeConfiguration', {
          settings = { [SECTION] = config () },
        })
      end
    end)
  end

  return server
end

return M
