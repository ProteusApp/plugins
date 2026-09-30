-- format: formats TOML files with `taplo fmt`. It runs in the file's folder, so Taplo finds a
-- `.taplo.toml` or `taplo.toml` there or above.

local disk = require ('disk_paths') --[[@as DiskPaths]]

---@class LangToml.FormatModule
local M = {}

---@param ctx LangToml.Context
---@param tool Proteus.ToolHandle The Taplo tool, which also runs the language server.
function M.install (ctx, tool)
  local app, settings = ctx.app, ctx.settings

  ctx.editor.add_formatter ('toml', function (doc, text, done)
    if settings.get ('toml.format') ~= true then
      done (nil)
      return
    end
    local path = ctx.to_disk (doc)
    tool.locate (function (program)
      if not program then
        done (nil)
        return
      end
      local args = { 'fmt', '--stdin-filepath', path, '-' }
      local opts = { cwd = disk.parent (path), stdin = text }
      app.process.run (program, args, opts, function (result, err)
        if err or not result then
          tool.log ('err', tostring (err))
          done (nil)
        elseif result.code ~= 0 then
          tool.log ('err', doc.path .. ': ' .. result.stderr:gsub ('%s+$', ''))
          ctx.notify (
            'Taplo could not format '
              .. disk.name (doc.path)
              .. '. The Tools panel has its message.'
          )
          done (nil)
        else
          tool.log ('info', 'formatted ' .. doc.path)
          done (result.stdout)
        end
      end)
    end)
  end)
end

return M
