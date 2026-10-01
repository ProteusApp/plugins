-- router: shares the editor's `css` language between plugins. The editor gives `.css`, `.scss`
-- and `.less` files the same language, and keeps one provider for each language, so a second
-- plugin that set its own would take the help away from the first. This plugin sets the only
-- one, and it hands each file to a plugin by its extension. A plugin such as lang.sass asks
-- for `.scss` files through the `css` service. Every other file goes to this plugin's own
-- server.
--
-- Nothing here needs anything but the editor, so the tests reach it with a stand-in.

---A plugin's claim on files of some kinds.
---@class LangCss.Route
---@field extensions string[] In lower case, without the dot, such as `{ 'scss' }`.
---@field factory Proteus.ProviderFactory

---@class LangCss.Router
---@field own fun(factory: Proteus.ProviderFactory) Sets the help for files no plugin claimed.
---@field route fun(route: LangCss.Route): fun() Claims files. Returns a function that gives them back.
---@field routed fun(ext: string): boolean True when a plugin claimed files of this kind.
---@field apply fun() Sets the provider again, so the editor asks about every open file anew.
---@field on_change fun(fn: fun()) Runs `fn` after a claim comes or goes.
---@field stop fun() Takes the provider away for good.

---The part of the editor the router uses.
---@class LangCss.RouterEditor
---@field set_provider fun(language: string, factory: Proteus.ProviderFactory): fun()

---@class LangCss.RouterModule
local M = {}

---A file's extension in lower case, or nil when it has none.
---@param path string
---@return string?
local function extension (path)
  local name = path:match ('[^/\\]*$') or path
  local ext = name:match ('^.+%.([^.]+)$')
  return ext and ext:lower () or nil
end

---@param editor LangCss.RouterEditor
---@param language string The editor's language, `'css'`.
---@return LangCss.Router
function M.new (editor, language)
  local routes = {} ---@type LangCss.Route[] The latest claim comes last and wins.
  local own = nil ---@type Proteus.ProviderFactory?
  local remove = nil ---@type fun()?
  local listeners = {} ---@type fun()[]
  local stopped = false

  ---The latest claim on files of this kind, or nil.
  ---@param ext string?
  ---@return LangCss.Route?
  local function route_for (ext)
    if not ext then
      return nil
    end
    for i = #routes, 1, -1 do
      for _, claimed in ipairs (routes[i].extensions) do
        if claimed == ext then
          return routes[i]
        end
      end
    end
    return nil
  end

  ---The one provider the editor keeps for the language.
  ---@type Proteus.ProviderFactory
  local function factory (doc)
    if doc.language ~= language then
      return nil
    end
    local route = route_for (extension (doc.path))
    if route then
      return route.factory (doc)
    end
    return own and own (doc) or nil
  end

  local function apply ()
    if stopped then
      return
    end
    if remove then
      remove ()
    end
    remove = editor.set_provider (language, factory)
  end

  local function changed ()
    if stopped then
      return
    end
    apply ()
    for _, fn in ipairs (listeners) do
      fn ()
    end
  end

  ---@type LangCss.Router
  return {
    own = function (fn)
      own = fn
    end,
    route = function (route)
      local entry = { extensions = {}, factory = route.factory } ---@type LangCss.Route
      for _, ext in ipairs (route.extensions) do
        entry.extensions[#entry.extensions + 1] = (
          tostring (ext):lower ():gsub ('^%.', '')
        )
      end
      routes[#routes + 1] = entry
      changed ()
      local gone = false
      return function ()
        if gone then
          return
        end
        gone = true
        for i, r in ipairs (routes) do
          if r == entry then
            table.remove (routes, i)
            break
          end
        end
        changed ()
      end
    end,
    routed = function (ext)
      return route_for (ext) ~= nil
    end,
    apply = apply,
    on_change = function (fn)
      listeners[#listeners + 1] = fn
    end,
    stop = function ()
      stopped = true
      if remove then
        remove ()
        remove = nil
      end
    end,
  }
end

return M
