-- format: formats Luau files with StyLua, when `stylua` is on the PATH. StyLua reads Luau's
-- types with `--syntax Luau`. It runs in the file's folder, and uses the first `stylua.toml`
-- or `.stylua.toml` it finds there or above. The app's own StyLua plugin formats `.lua` files.

local disk = require ('disk_paths') --[[@as DiskPaths]]
local launch = require ('lib.launch') --[[@as LangLuau.LaunchModule]]

---@class LangLuau.Formatter
---@field reset fun() Looks for `stylua` again at the next format.

---@class LangLuau.FormatModule
local M = {}

---@param ctx LangLuau.Context
---@param tool Proteus.ToolHandle The luau-lsp tool, whose log StyLua shares.
---@return LangLuau.Formatter
function M.install (ctx, tool)
  local app, settings = ctx.app, ctx.settings
  -- Looked for once, at the first format. A restart looks again.
  local program = nil ---@type string|false|nil

  ---@param cb fun(path: string?)
  local function locate (cb)
    if program ~= nil then
      cb (program or nil)
      return
    end
    app.process.which ('stylua', function (found)
      program = found or false
      if not found then
        tool.log (
          'info',
          'stylua is not on the PATH, so Luau files do not format'
        )
      end
      cb (found)
    end)
  end

  ctx.editor.add_formatter ('luau', function (doc, text, done)
    if settings.get ('luau-lsp.format') ~= true or not ctx.desktop then
      done (nil)
      return
    end
    local path = ctx.to_disk (doc)
    locate (function (exe)
      if not exe then
        done (nil)
        return
      end
      local opts = { cwd = disk.parent (path), stdin = text }
      app.process.run (
        exe,
        launch.stylua_args (path),
        opts,
        function (result, err)
          if err or not result then
            tool.log ('err', 'StyLua did not run: ' .. tostring (err))
            done (nil)
          elseif result.code ~= 0 then
            tool.log ('err', doc.path .. ': ' .. result.stderr:gsub ('%s+$', ''))
            ctx.notify (
              'StyLua could not format '
                .. disk.name (doc.path)
                .. '. The Tools panel has its message.'
            )
            done (nil)
          else
            done (result.stdout)
          end
        end
      )
    end)
  end)

  ---@type LangLuau.Formatter
  return {
    reset = function ()
      program = nil
    end,
  }
end

return M
