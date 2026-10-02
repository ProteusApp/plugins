-- format: formats shell scripts with shfmt. The text goes in on standard input, with the
-- file's full path in `--filename`. shfmt then reads the zsh, bash or POSIX dialect from the
-- file's name or its `#!` line, and finds the project's `.editorconfig` for the file.

local config = require ('lib.config') --[[@as LangShell.ConfigModule]]
local disk = require ('disk_paths') --[[@as DiskPaths]]

---@class LangShell.FormatModule
local M = {}

---@param ctx LangShell.Context
function M.install (ctx)
  local app, settings, shfmt = ctx.app, ctx.settings, ctx.shfmt
  local tool = shfmt.tool

  ctx.editor.add_formatter ('shell', function (doc, text, done)
    if settings.get ('shell.format') ~= true then
      done (nil)
      return
    end
    local path = ctx.to_disk (doc)
    shfmt.find (function (program)
      if not program then
        done (nil)
        return
      end
      local args = config.shfmt_args (path, settings.get ('shell.indent'))
      local opts = { cwd = disk.parent (path), stdin = text }
      app.process.run (program, args, opts, function (result, err)
        if err or not result then
          tool.log ('err', tostring (err))
          done (nil)
        elseif result.code ~= 0 then
          tool.log ('err', (result.stderr:gsub ('%s+$', '')))
          ctx.notify (
            'shfmt could not format '
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
