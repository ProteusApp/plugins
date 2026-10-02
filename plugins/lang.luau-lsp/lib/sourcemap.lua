-- sourcemap: keeps `sourcemap.json` up to date while the server runs in Roblox mode. luau-lsp
-- reads it to know which instance each script is, such as `game.ReplicatedStorage.Shared`.
-- `rojo sourcemap --watch` writes it again whenever the project changes, and prints a line
-- each time. Each line tells the server to read the file again.

local launch = require ('lib.launch') --[[@as LangLuau.LaunchModule]]
local project = require ('lib.project') --[[@as LangLuau.ProjectModule]]

---@class LangLuau.Sourcemap
---@field start fun(root: string, names: string[], changed: fun()) Runs Rojo in the folder, when it has a project file and Rojo is on the PATH. `changed` runs after each write.
---@field stop fun()

---@class LangLuau.SourcemapModule
local M = {}

---@param ctx LangLuau.Context
---@param tool Proteus.ToolHandle The luau-lsp tool, whose log Rojo shares.
---@return LangLuau.Sourcemap
function M.install (ctx, tool)
  local app = ctx.app
  local rojo = nil ---@type Proteus.ProcessHandle?
  -- Each start and stop counts up, so an answer meant for an earlier start is dropped.
  local run = 0

  local function stop ()
    run = run + 1
    if rojo and rojo.alive () then
      rojo.kill ()
    end
    rojo = nil
  end

  ---@type LangLuau.Sourcemap
  return {
    start = function (root, names, changed)
      stop ()
      local mine = run
      if not project.has_rojo_project (names) then
        tool.log (
          'info',
          'no '
            .. project.ROJO_PROJECT
            .. ' in the folder, so Rojo does not write sourcemap.json'
        )
        return
      end
      app.process.which ('rojo', function (program)
        if mine ~= run then
          return
        end
        if not program then
          tool.log (
            'info',
            'rojo is not on the PATH, so sourcemap.json is not kept up to date'
          )
          return
        end
        tool.log ('info', 'rojo ' .. table.concat (launch.rojo_args (), ' '))
        local errors = {} ---@type string[]
        rojo = app.process.spawn (program, launch.rojo_args (), {
          cwd = root,
          on_message = function (line)
            tool.log ('out', 'rojo: ' .. line)
            changed ()
          end,
          on_stderr = function (line)
            errors[#errors + 1] = line
            tool.log ('err', 'rojo: ' .. line)
          end,
          on_exit = function (code)
            -- A stop kills Rojo, which ends with no code.
            if code ~= nil then
              tool.log ('err', 'rojo ended with code ' .. tostring (code))
              ctx.notify (
                'Rojo stopped writing sourcemap.json. '
                  .. (errors[1] or 'The Tools panel has its messages.')
              )
            end
          end,
          on_error = function (err)
            tool.log ('err', 'rojo did not start: ' .. tostring (err))
          end,
        })
      end)
    end,
    stop = stop,
  }
end

return M
