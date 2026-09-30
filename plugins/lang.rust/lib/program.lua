-- program: finds a rust-analyzer that runs. The one set in Settings wins, then the one on the
-- PATH, then a download. rustup puts a rust-analyzer on the PATH that fails until its
-- component is added, so the PATH copy must run before it counts.

---@class LangRust.ProgramModule
local M = {}

---@param app Proteus.App
---@param settings Proteus.Settings
---@param tool Proteus.ToolHandle
---@param cb fun(program: string?)
function M.find (app, settings, tool, cb)
  local wanted = tostring (settings.get ('rust.analyzer_path') or '')
  if wanted ~= '' then
    cb (wanted)
    return
  end
  tool.locate (function (found)
    if not found then
      cb (nil)
      return
    end
    app.process.run (found, { '--version' }, nil, function (result)
      if result and result.code == 0 then
        cb (found)
        return
      end
      tool.log (
        'info',
        found .. ' does not run, so a downloaded copy is used instead'
      )
      tool.cached (function (path)
        if not path then
          tool.offer ()
        end
        cb (path)
      end)
    end)
  end)
end

return M
