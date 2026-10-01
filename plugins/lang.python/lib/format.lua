-- format: Format Document for Python, with `ruff format`. The text goes in on standard input.
-- The file's own path goes along as `--stdin-filename`, so Ruff finds the project's settings
-- in ruff.toml or pyproject.toml, and formats a `.pyi` file as a stub.

local disk = require ('disk_paths') --[[@as DiskPaths]]

---@class LangPython.FormatModule
local M = {}

---@param ctx LangPython.Context
---@param ruff LangPython.Ruff
function M.install (ctx, ruff)
  local app, settings, tool = ctx.app, ctx.settings, ruff.tool

  ---@param doc Proteus.DocInfo
  ---@param text string
  ---@param done fun(text: string?)
  local function format (doc, text, done)
    if settings.get ('python.format') ~= true or not ctx.desktop then
      done (nil)
      return
    end
    local path = ctx.full_path (doc)
    ruff.program (ctx.root_for (doc), function (program)
      if not program then
        done (nil)
        return
      end
      local args = { 'format', '--stdin-filename', path, '-' }
      local opts = { cwd = disk.parent (path), stdin = text }
      app.process.run (program, args, opts, function (result, err)
        if err or not result then
          tool.log ('err', tostring (err))
          done (nil)
        elseif result.code ~= 0 then
          tool.log ('err', doc.path .. ': ' .. result.stderr:gsub ('%s+$', ''))
          ctx.notify (
            'warn',
            'Ruff could not format '
              .. disk.name (doc.path)
              .. '. The Tools panel has its message.'
          )
          done (nil)
        else
          done (result.stdout)
        end
      end)
    end)
  end

  ctx.editor.add_formatter ('python', format)
end

return M
