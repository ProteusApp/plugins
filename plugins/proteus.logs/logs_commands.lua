-- logs_commands: the log viewer's right-click menus and its commands, which the toolbar, the
-- palette and the keys run. The log viewer's init.lua attaches it to the context its modules
-- share, once the rest is in place.

local list_m = require ('logs_list') --[[@as Logs.ListModule]]

local PAGE_STEP = 2500 -- how far the window moves

---@class Logs.CommandsModule
local M = {}

---Adds the menus and the commands.
---@param ctx Logs.Ctx
function M.attach (ctx)
  local app, commands, menus = ctx.app, ctx.commands, ctx.menus
  local list, src_list = ctx.list, ctx.src_list
  local LEVEL_PLURALS = ctx.level_plurals
  local here, set_follow, reset_filter =
    ctx.here, ctx.set_follow, ctx.reset_filter
  local show_window, page, id_of = ctx.show_window, ctx.page, ctx.id_of
  local select_line = ctx.select_line
  local find_source, show_source, show_merged =
    ctx.find_source, ctx.show_source, ctx.show_merged
  local stop, restart, close_source = ctx.stop, ctx.restart, ctx.close_source
  local open_file, run_command = ctx.open_file, ctx.run_command
  local open_rotated = ctx.open_rotated
  local paste_log, open_recent = ctx.paste_log, ctx.open_recent
  local clear_lines, copy_matching = ctx.clear_lines, ctx.copy_matching
  local copy_selected, toggle_level = ctx.copy_selected, ctx.toggle_level
  local toggle_wrap, focus_filter = ctx.toggle_wrap, ctx.focus_filter

  -- Right-click menus -------------------------------------------------------------------------

  if menus then
    menus.attach (list, function (ev)
      local items = {} ---@type Proteus.MenuItem[]
      local picked = nil ---@type Logs.Line?
      local n = tonumber (ev.item or '')
      if n then
        picked = ctx.by_id[math.floor (n)]
      end
      local selection = ev.selection or ''
      if selection ~= '' then
        items[#items + 1] = {
          label = 'Copy',
          icon = 'copy',
          key = 'Ctrl+C',
          run = function ()
            app.system.clipboard (selection)
          end,
        }
      end
      if picked then
        local line = picked
        items[#items + 1] = {
          label = 'Copy Line',
          icon = 'copy',
          run = function ()
            app.system.clipboard (line.plain)
          end,
        }
        items[#items + 1] = {
          label = 'Show Details',
          icon = 'panel-bottom',
          run = function ()
            select_line (id_of (line))
          end,
        }
        items[#items + 1] = {
          label = 'Hide ' .. LEVEL_PLURALS[line.level],
          icon = 'eye-off',
          run = function ()
            toggle_level (line.level)
          end,
        }
        items[#items + 1] = { separator = true }
      end
      items[#items + 1] = {
        label = 'Copy Matching Lines',
        icon = 'clipboard-list',
        disabled = ctx.matched == 0,
        run = copy_matching,
      }
      items[#items + 1] = {
        label = 'Clear',
        icon = 'eraser',
        key = 'Ctrl+K',
        disabled = ctx.shown == nil and not ctx.merged,
        run = clear_lines,
      }
      return items
    end)

    menus.attach (src_list, function (ev)
      local id = tonumber ((ev.item or ''):match ('(%d+)$') or '')
      local src = find_source (id)
      if not src then
        return {
          {
            label = 'Open Log File',
            icon = 'file-text',
            run = function ()
              open_file (false)
            end,
          },
          {
            label = 'Open Whole Log File',
            icon = 'file-search',
            run = function ()
              open_file (true)
            end,
          },
          {
            label = 'Open Rotated Log File',
            icon = 'files',
            run = open_rotated,
          },
          {
            label = 'All Sources, by Time',
            icon = 'git-merge',
            disabled = #ctx.sources < 2,
            run = show_merged,
          },
          {
            label = 'Run Command',
            icon = 'square-terminal',
            run = run_command,
          },
          {
            label = 'Paste Log',
            icon = 'clipboard-paste',
            run = paste_log,
          },
        }
      end
      local s = src
      local items = {} ---@type Proteus.MenuItem[]
      items[#items + 1] = {
        label = 'Show',
        icon = 'eye',
        run = function ()
          show_source (s)
        end,
      }
      if s.state == 'running' then
        items[#items + 1] = {
          label = 'Stop',
          icon = 'square',
          run = function ()
            stop (s)
          end,
        }
      end
      if s.spec.kind ~= 'paste' then
        items[#items + 1] = {
          label = 'Restart',
          icon = 'rotate-cw',
          run = function ()
            restart (s)
          end,
        }
      end
      local path, command = s.spec.path, s.spec.command
      if path then
        items[#items + 1] = {
          label = 'Copy Path',
          icon = 'copy',
          run = function ()
            app.system.clipboard (path)
          end,
        }
      end
      if command then
        items[#items + 1] = {
          label = 'Copy Command',
          icon = 'copy',
          run = function ()
            app.system.clipboard (command)
          end,
        }
      end
      items[#items + 1] = { separator = true }
      items[#items + 1] = {
        label = 'Close',
        icon = 'x',
        danger = true,
        run = function ()
          close_source (s)
        end,
      }
      return items
    end)
  end

  -- Commands --------------------------------------------------------------------------------

  ---@return boolean
  local function has_source ()
    return here () and (ctx.shown ~= nil or ctx.merged)
  end

  ---@return boolean
  local function is_running ()
    local src = ctx.shown
    return here () and src ~= nil and src.state == 'running'
  end

  ---@return boolean
  local function can_restart ()
    local src = ctx.shown
    return here () and src ~= nil and src.spec.kind ~= 'paste'
  end

  commands.register ({
    id = 'logs.open_file',
    category = 'Logs',
    title = 'Open Log File',
    key = 'ctrl+o',
    icon = 'file-text',
    toolbar = 1,
    when = here,
    run = function ()
      open_file (false)
    end,
  })
  commands.register ({
    id = 'logs.open_whole',
    category = 'Logs',
    title = 'Open Whole Log File',
    key = 'ctrl+shift+o',
    icon = 'file-search',
    when = here,
    run = function ()
      open_file (true)
    end,
  })
  commands.register ({
    id = 'logs.open_rotated',
    category = 'Logs',
    title = 'Open Rotated Log File',
    icon = 'files',
    when = here,
    run = open_rotated,
  })
  commands.register ({
    id = 'logs.merged',
    category = 'Logs',
    title = 'Show All Sources by Time',
    icon = 'git-merge',
    when = function ()
      return here () and #ctx.sources >= 2
    end,
    run = show_merged,
  })
  commands.register ({
    id = 'logs.earlier',
    category = 'Logs',
    title = 'Show Earlier Lines',
    key = 'ctrl+pageup',
    icon = 'chevrons-up',
    when = function ()
      return has_source () and ctx.win_from > ctx.view_first
    end,
    run = function ()
      page (-PAGE_STEP)
    end,
  })
  commands.register ({
    id = 'logs.later',
    category = 'Logs',
    title = 'Show Later Lines',
    key = 'ctrl+pagedown',
    icon = 'chevrons-down',
    when = function ()
      return has_source () and ctx.win_from + ctx.drawn - 1 < #ctx.view_all
    end,
    run = function ()
      page (PAGE_STEP)
    end,
  })
  commands.register ({
    id = 'logs.follow_newest',
    category = 'Logs',
    title = 'Go to the Newest Line',
    key = 'ctrl+end',
    icon = 'arrow-down-to-line',
    when = has_source,
    run = function ()
      show_window (#ctx.view_all - list_m.MAX_SHOWN + 1)
      set_follow (true)
    end,
  })
  commands.register ({
    id = 'logs.run',
    category = 'Logs',
    title = 'Run Command',
    key = 'ctrl+shift+r',
    icon = 'square-terminal',
    toolbar = 2,
    when = here,
    run = run_command,
  })
  commands.register ({
    id = 'logs.paste',
    category = 'Logs',
    title = 'Paste Log',
    icon = 'clipboard-paste',
    toolbar = 3,
    when = here,
    run = paste_log,
  })
  commands.register ({
    id = 'logs.recent',
    category = 'Logs',
    title = 'Open Recent',
    icon = 'history',
    toolbar = 4,
    when = function ()
      return here () and #ctx.recent > 0
    end,
    run = open_recent,
  })
  commands.register ({
    id = 'logs.stop',
    category = 'Logs',
    title = 'Stop',
    icon = 'square',
    toolbar = 5,
    when = is_running,
    run = function ()
      if ctx.shown then
        stop (ctx.shown)
      end
    end,
  })
  commands.register ({
    id = 'logs.restart',
    category = 'Logs',
    title = 'Restart',
    icon = 'rotate-cw',
    toolbar = 6,
    when = can_restart,
    run = function ()
      if ctx.shown and ctx.shown.spec.kind ~= 'paste' then
        restart (ctx.shown)
      end
    end,
  })
  commands.register ({
    id = 'logs.close',
    category = 'Logs',
    title = 'Close Source',
    icon = 'x',
    when = has_source,
    run = function ()
      if ctx.shown then
        close_source (ctx.shown)
      end
    end,
  })
  commands.register ({
    id = 'logs.filter',
    category = 'Logs',
    title = 'Filter Lines',
    key = 'ctrl+f',
    icon = 'search',
    when = here,
    run = focus_filter,
  })
  commands.register ({
    id = 'logs.clear',
    category = 'Logs',
    title = 'Clear Lines',
    key = 'ctrl+k',
    icon = 'eraser',
    when = has_source,
    run = clear_lines,
  })
  commands.register ({
    id = 'logs.wrap',
    category = 'Logs',
    title = 'Toggle Wrap',
    key = 'alt+z',
    icon = 'text-wrap',
    when = here,
    run = toggle_wrap,
  })
  commands.register ({
    id = 'logs.follow',
    category = 'Logs',
    title = 'Toggle Follow',
    icon = 'arrow-down-to-line',
    when = here,
    run = function ()
      set_follow (not ctx.follow)
    end,
  })
  commands.register ({
    id = 'logs.copy_line',
    category = 'Logs',
    title = 'Copy Selected Line',
    icon = 'copy',
    when = function ()
      return here () and ctx.selected ~= nil
    end,
    run = copy_selected,
  })
  commands.register ({
    id = 'logs.copy_matching',
    category = 'Logs',
    title = 'Copy Matching Lines',
    icon = 'clipboard-list',
    when = has_source,
    run = copy_matching,
  })
  commands.register ({
    id = 'logs.show_all',
    category = 'Logs',
    title = 'Show All Lines',
    icon = 'eye',
    when = here,
    run = reset_filter,
  })
  commands.register ({
    id = 'logs.theme',
    category = 'Logs',
    title = 'Change Theme',
    icon = 'palette',
    toolbar = 90,
    toolbar_align = 'right',
    run = function ()
      commands.run ('theme.choose')
    end,
  })
  commands.register ({
    id = 'logs.switch_app',
    category = 'Logs',
    title = 'Switch App',
    icon = 'layers',
    toolbar = 91,
    toolbar_align = 'right',
    run = function ()
      commands.run ('profile.switch')
    end,
  })
end

return M
