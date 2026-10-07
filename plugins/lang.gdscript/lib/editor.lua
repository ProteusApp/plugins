-- editor: Open in the Godot Editor, from a scene's right-click menu in the Code Editor's file
-- tree. Godot opens a scene only when it starts, and has no lock file and no way to hand a
-- running editor a file. So with the project already open in a Godot window, it says so
-- rather than start a second editor on the same files.

local disk = require ('disk_paths')
local godot = require ('lib.godot') --[[@as LangGdscript.GodotModule]]

---@class LangGdscript.EditorModule
local M = {}

---Returns the function the menu item runs, which takes a scene's full path.
---@param app Proteus.App
---@param settings Proteus.Settings
---@param notify fun(text: string)
---@return fun(path: string)
function M.opener (app, settings, notify)
  ---Tells whether a Godot window already has the project open. Windows has no pgrep, so
  ---there the answer is always no.
  ---@param root string
  ---@param cb fun(open: boolean)
  local function editor_open (root, cb)
    if app.os == 'windows' then
      cb (false)
      return
    end
    app.process.run ('pgrep', { '-af', 'godot' }, nil, function (result)
      cb (result ~= nil and godot.editor_running (result.stdout or '', root))
    end)
  end

  ---@param cb fun(program: string?)
  local function find_godot (cb)
    local names = godot.programs (settings.get ('gdscript.godot_path'))
    local i = 0
    local function look ()
      i = i + 1
      local name = names[i]
      if not name then
        cb (nil)
        return
      end
      app.process.which (name, function (path)
        if path then
          cb (path)
        else
          look ()
        end
      end)
    end
    look ()
  end

  return function (path)
    path = disk.normalize (path)
    disk.find_up (
      app.fs.stat_path,
      disk.parent (path),
      { 'project.godot' },
      function (found)
        local root = found and disk.parent (found)
        local scene = root and godot.res_path (root, path)
        if not root or not scene then
          notify ('No project.godot is above this scene.')
          return
        end
        editor_open (root, function (open)
          if open then
            notify (
              'Godot already has this project open. Open ' .. scene .. ' there.'
            )
            return
          end
          find_godot (function (program)
            if not program then
              notify (
                'Godot is not on the PATH. Set gdscript.godot_path to the Godot program.'
              )
              return
            end
            app.process.spawn (
              program,
              { '--path', root, '--editor', '--scene', scene },
              {
                cwd = root,
                on_error = function (why)
                  notify ('Godot did not start: ' .. why)
                end,
              }
            )
          end)
        end)
      end
    )
  end
end

return M
