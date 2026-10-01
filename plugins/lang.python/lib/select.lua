-- select: the Select Interpreter command. It lists the virtual environments in the project
-- and the Pythons on the PATH, and keeps the one picked for this folder. "Find
-- automatically" forgets the pick, and "Enter a path" takes any other Python. The
-- `python.interpreter` setting still wins over a pick, for every folder.

local disk = require ('disk_paths') --[[@as DiskPaths]]

---@class LangPython.SelectModule
local M = {}

-- What each way of finding Python shows in the list.
local DETAIL = {
  venv = 'virtual environment',
  path = 'on the PATH',
}

---@param ctx LangPython.Context
---@param changed fun() Runs after the folder's Python changed.
---@return fun() run Shows the list.
function M.new (ctx, changed)
  local app = ctx.app

  ---@param root string
  ---@param path string?
  local function choose (root, path)
    ctx.python.pick (root, path)
    changed ()
  end

  ---@param picker Proteus.Picker
  ---@param root string
  local function enter_path (picker, root)
    picker.input ({
      prompt = 'The full path of a Python program',
      value = ctx.python.picked (root) or '',
      validate = function (text)
        if text:match ('^%s*$') then
          return 'Enter a path.'
        end
        return nil
      end,
      on_submit = function (text)
        choose (root, (text:gsub ('^%s+', ''):gsub ('%s+$', '')))
      end,
    })
  end

  return function ()
    local picker = app.try_use ('picker')
    local root = ctx.root_for (ctx.current_doc ())
    if not picker or not root then
      ctx.notify ('info', 'Open a Python file or a folder first.')
      return
    end
    if tostring (ctx.settings.get ('python.interpreter') or '') ~= '' then
      ctx.notify (
        'info',
        'The python.interpreter setting picks Python for every folder. Clear it to pick one here.'
      )
      return
    end
    ctx.python.choices (root, function (list)
      local now = ctx.python.picked (root)
      local items = {
        {
          label = 'Find automatically',
          detail = 'a .venv or venv folder, then the PATH',
          icon = 'search',
          hint = not now and 'in use' or nil,
          value = false,
        },
      } ---@type Proteus.PickItem[]
      for _, found in ipairs (list) do
        local rel = disk.relative (root, found.path, app.os)
        items[#items + 1] = {
          label = rel or found.path,
          detail = DETAIL[found.how],
          icon = 'terminal',
          hint = now and disk.same (now, found.path, app.os) and 'in use'
            or nil,
          value = found.path,
        }
      end
      items[#items + 1] = {
        label = 'Enter a path',
        detail = 'any other Python',
        icon = 'folder-open',
        value = true,
      }
      picker.pick ({
        prompt = 'Python for ' .. disk.name (root),
        placeholder = 'Pick a Python',
        items = items,
        on_pick = function (item)
          if item.value == true then
            enter_path (picker, root)
          elseif item.value == false then
            choose (root, nil)
          else
            choose (root, tostring (item.value))
          end
        end,
      })
    end)
  end
end

return M
