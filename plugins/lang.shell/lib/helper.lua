-- helper: a program the plugin runs beside the server, ShellCheck or shfmt. It has its own
-- row in the Tools panel, with its version and its download. It looks for the program the
-- first time a shell script needs it, and again on the panel's Look again and after a
-- download.

local config = require ('lib.config') --[[@as LangShell.ConfigModule]]

---@class LangShell.HelperOptions
---@field setting string The setting that switches it off, such as `'shell.format'`.
---@field spec Proteus.ToolSpec The tool, without `kind` and `check`, which this sets.

---@class LangShell.Helper
---@field tool Proteus.ToolHandle
---@field path fun(): string? The program the last look found.
---@field check fun() Looks for the program again.
---@field wake fun() Looks for the program the first time a shell script opens, while it is on.
---@field find fun(cb: fun(path: string?)) The program, after a first look when there was none.
---@field on_change fun(fn: fun()) Runs `fn` when the program found changes.

---@class LangShell.HelperModule
local M = {}

---@param app Proteus.App
---@param settings Proteus.Settings
---@param opts LangShell.HelperOptions
---@return LangShell.Helper
function M.new (app, settings, opts)
  local spec = opts.spec
  local found = nil ---@type string?
  local looked = false
  local waiting = {} ---@type fun(path: string?)[]
  local listeners = {} ---@type fun()[]
  local looking = false
  local check ---@type fun()

  spec.kind = 'command'
  spec.check = function ()
    check ()
  end
  local tool = app.use ('tools').register (spec)

  ---Sets the state for a program that was found, by the setting that switches it off.
  local function show_state ()
    if not found then
      return
    end
    if settings.get (opts.setting) == true then
      tool.set_state ('ready')
    else
      tool.set_state (
        'stopped',
        'switched off in Settings (' .. opts.setting .. ')'
      )
    end
  end

  ---Keeps the program found, and tells whoever waits for it.
  ---@param path string?
  local function settle (path)
    local changed = path ~= found
    found = path
    looked = true
    looking = false
    tool.set_path (path)
    local cbs = waiting
    waiting = {}
    for _, cb in ipairs (cbs) do
      cb (path)
    end
    if changed then
      for _, fn in ipairs (listeners) do
        fn ()
      end
    end
  end

  check = function ()
    if looking then
      return
    end
    looking = true
    tool.locate (function (path)
      if not path then
        tool.set_version (nil)
        tool.set_state ('missing', spec.program .. ' is not on the PATH')
        settle (nil)
        return
      end
      app.process.run (path, { '--version' }, nil, function (result)
        if not result or result.code ~= 0 then
          local why = result and result.stderr:match ('[^\r\n]+')
          tool.set_version (nil)
          tool.set_state (
            'error',
            path .. ' does not run' .. (why and (': ' .. why) or '')
          )
          settle (nil)
          return
        end
        tool.set_version (config.version (result.stdout))
        settle (path)
        show_state ()
      end)
    end)
  end

  ---True while the setting leaves the program on.
  ---@return boolean
  local function wanted ()
    return settings.get (opts.setting) == true
  end

  local woken = false
  local first = true
  settings.watch (opts.setting, function ()
    if first then
      first = false
      return
    end
    if woken and wanted () and not looked then
      check ()
    elseif found then
      show_state ()
    elseif not looked then
      tool.set_state (
        'stopped',
        wanted () and 'looks for it when a shell script opens'
          or ('switched off in Settings (' .. opts.setting .. ')')
      )
    end
  end)

  tool.set_state ('stopped', 'looks for it when a shell script opens')

  ---@type LangShell.Helper
  return {
    tool = tool,
    path = function ()
      return found
    end,
    check = check,
    wake = function ()
      if woken then
        return
      end
      woken = true
      if wanted () then
        check ()
      else
        tool.set_state (
          'stopped',
          'switched off in Settings (' .. opts.setting .. ')'
        )
      end
    end,
    find = function (cb)
      if looked and not looking then
        cb (found)
        return
      end
      waiting[#waiting + 1] = cb
      check ()
    end,
    on_change = function (fn)
      listeners[#listeners + 1] = fn
    end,
  }
end

return M
