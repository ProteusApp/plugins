-- format: formats TOML files with `taplo fmt`. It runs in the file's folder, so Taplo finds a
-- `.taplo.toml` or `taplo.toml` there or above. The tools registry runs it, logs a failure
-- and leaves the text as it was.

---@class LangToml.FormatModule
local M = {}

---@param ctx LangToml.Context
---@param tool Proteus.ToolHandle The Taplo tool, which also runs the language server.
function M.install (ctx, tool)
  ctx.editor.add_formatter (
    'toml',
    ctx.app.use ('tools').formatter ({
      tool = tool,
      name = 'Taplo',
      enabled = 'toml.format',
      in_folder = true,
      args = function (_, path, cb)
        cb ({ 'fmt', '--stdin-filepath', path, '-' })
      end,
    })
  )
end

return M
