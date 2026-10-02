-- server: when the Tailwind server runs. It starts for the first file that may hold classes,
-- and only when the open folder uses Tailwind. It looks again when a file that may change
-- the answer is saved, such as a new `tailwind.config.js`.

local detect = require ('lib.detect') --[[@as LangTailwind.DetectModule]]
local disk = require ('disk_paths') --[[@as DiskPaths]]
local program_module = require ('lib.program') --[[@as LangTailwind.ProgramModule]]

---@class LangTailwind.Server
---@field start fun(doc: Proteus.DocInfo?)
---@field stop fun()
---@field forget fun() Forgets which folders use Tailwind, so the next start looks again.

---@class LangTailwind.ServerModule
local M = {}

-- The editor languages of the files the server serves. The editor calls `.vue` and `.svelte`
-- files `html`, and `.scss` files `css`.
local SERVED = { 'css', 'html', 'javascript', 'jsx', 'markdown', 'tsx', 'typescript' }

---Calls `cb (true)` when the folder uses Tailwind: a config file first, then a stylesheet
---or a package.json that names it.
---@param app Proteus.App
---@param root string
---@param log fun(text: string)
---@param cb fun(yes: boolean)
local function uses_tailwind (app, root, log, cb)
  local walk_opts =
    { include = detect.CONFIG_GLOBS, skip = detect.SKIP, limit = 1 }
  app.fs.walk_dir (root, walk_opts, function (walked, walk_err)
    if walk_err then
      log ('could not list ' .. root .. ': ' .. tostring (walk_err))
    end
    if walked and #walked.files > 0 then
      cb (true)
      return
    end
    local search_opts =
      { include = detect.SEARCH_GLOBS, skip = detect.SKIP, limit = 200 }
    app.fs.search_dir (root, 'tailwind', search_opts, function (found, err)
      if err then
        log ('could not search ' .. root .. ': ' .. tostring (err))
      end
      cb (found ~= nil and detect.any (found.matches))
    end)
  end)
end

---@param ctx LangTailwind.Context
---@param tool Proteus.ToolHandle
---@param client LangTailwind.Client
---@return LangTailwind.Server
function M.install (ctx, tool, client)
  local app, settings, editor = ctx.app, ctx.settings, ctx.editor
  local starting = false
  local known = {} ---@type table<string, boolean> Whether each folder uses Tailwind.
  local server ---@type LangTailwind.Server

  ---@param text string
  local function log (text)
    tool.log ('info', text)
  end

  ---@return Proteus.DocInfo?
  local function first_doc ()
    for _, doc in ipairs (editor.docs ()) do
      if client.serves (doc) then
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
    return project and project.root () or disk.parent (ctx.to_disk (doc))
  end

  ---Tells the Tools panel the editor languages the server serves. An older app has no
  ---`set_languages`, and then the server shows in the status bar for every file.
  ---@param list string[]
  local function set_languages (list)
    if tool.set_languages then
      tool.set_languages (list)
    end
  end

  ---@param root string
  local function launch (root)
    set_languages (SERVED)
    program_module.find (app, tool, root, function (found, why)
      starting = false
      if not found then
        tool.set_path (nil)
        tool.set_state ('missing', why)
        return
      end
      client.start (found, root)
    end)
  end

  server = {
    start = function (doc)
      if client.running () or starting then
        return
      end
      if settings.get ('tailwind.enabled') ~= true then
        tool.set_state ('stopped', 'switched off in Settings (tailwind.enabled)')
        return
      end
      doc = doc or first_doc ()
      if not doc then
        tool.set_state ('stopped', 'starts when a file with classes opens')
        return
      end
      local root = root_for (doc)
      if known[root] == false then
        set_languages ({})
        tool.set_state ('stopped', 'the open folder does not use Tailwind CSS')
        return
      end
      starting = true
      if known[root] then
        launch (root)
        return
      end
      uses_tailwind (app, root, log, function (yes)
        known[root] = yes
        if not yes then
          starting = false
          set_languages ({})
        tool.set_state ('stopped', 'the open folder does not use Tailwind CSS')
          return
        end
        launch (root)
      end)
    end,
    stop = function ()
      client.stop ()
    end,
    forget = function ()
      known = {}
    end,
  }

  app.on ('editor:opened', function (doc)
    ---@cast doc Proteus.DocInfo
    if client.serves (doc) and not client.running () then
      server.start (doc)
    end
  end)

  -- A folder without Tailwind may get it, such as from a new config file or an install.
  app.on ('editor:saved', function (path)
    if
      type (path) == 'string'
      and not client.running ()
      and detect.matters (path)
    then
      known = {}
      server.start (nil)
    end
  end)

  local first = true
  settings.watch ('tailwind.enabled', function ()
    if first then
      first = false
      return
    end
    server.stop ()
    server.start (nil)
  end)

  return server
end

return M
