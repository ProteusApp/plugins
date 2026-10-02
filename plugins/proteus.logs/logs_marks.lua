-- logs_marks: the log viewer's bookmarks. A line can be bookmarked and unbookmarked, the
-- selection jumps to the next or the previous bookmark in the list, and a picker lists them
-- all. `is:marked` in the filter keeps only the bookmarked lines. The log viewer's init.lua
-- attaches it to the context its modules share.
--
-- Rows are HTML strings with no element of their own, so one CSS rule marks every
-- bookmarked row by its id, the way the selected row is marked.

local lf = require ('log_filter') --[[@as Logs.FilterModule]]
local list_m = require ('logs_list') --[[@as Logs.ListModule]]

---@class Logs.MarksModule
local M = {}

---Adds the bookmarks to `ctx`.
---@param ctx Logs.Ctx
function M.attach (ctx)
  local ui, picker = ctx.ui, ctx.picker
  local say = ctx.say
  local id_of, tag_of = ctx.id_of, ctx.tag_of
  local show_window, select_line = ctx.show_window, ctx.select_line

  local marks_css = ui.css ('')

  local function render_marks ()
    local selectors = {} ---@type string[]
    for id in pairs (ctx.marks) do
      selectors[#selectors + 1] = '.logs-list .logs-row[data-item="'
        .. id
        .. '"] .logs-n'
    end
    table.sort (selectors)
    if #selectors == 0 then
      marks_css:set ('')
      return
    end
    marks_css:set (
      table.concat (selectors, ',\n')
        .. ' { color: var(--accent); box-shadow: inset 3px 0 var(--accent); font-weight: 700; }'
    )
  end

  ---The filter shows or hides bookmarked lines, so a change of bookmark changes the list.
  local function refilter ()
    if ctx.query.marked or ctx.query.unmarked then
      ctx.redraw_list ()
    end
  end

  ---Bookmarks a line, or takes its bookmark away.
  ---@param line Logs.Line
  local function toggle_mark (line)
    local id = id_of (line)
    if line.marked then
      line.marked = nil
      ctx.marks[id] = nil
    else
      line.marked = true
      ctx.marks[id] = line
    end
    render_marks ()
    refilter ()
  end

  ---Takes the bookmarks away from lines that are gone: those `gone` says yes to.
  ---@param gone fun(line: Logs.Line): boolean
  local function forget_marks (gone)
    local changed = false
    for id, line in pairs (ctx.marks) do
      if gone (line) then
        line.marked = nil
        ctx.marks[id] = nil
        changed = true
      end
    end
    if changed then
      render_marks ()
    end
  end

  ---Where a line is in the view, or nil when the filter hides it.
  ---@param line Logs.Line
  ---@return integer?
  local function view_index (line)
    for k = ctx.view_first, #ctx.view_all do
      if ctx.view_all[k] == line then
        return k
      end
    end
    return nil
  end

  ---Moves the window to a line in the view, and selects it.
  ---@param line Logs.Line
  ---@return boolean shown False when the filter hides the line.
  local function go_to_line (line)
    local k = view_index (line)
    if not k then
      return false
    end
    local id = id_of (line)
    if not ctx.by_id[id] then
      show_window (k - math.floor (list_m.MAX_SHOWN / 2))
    end
    select_line (id)
    return true
  end

  ---Selects the next bookmark in the view, or the previous one when `step` is below 0. It
  ---goes round from the end to the start.
  ---@param step integer
  local function next_mark (step)
    local count = #ctx.view_all - ctx.view_first + 1
    if count <= 0 or next (ctx.marks) == nil then
      say ('No lines are bookmarked.')
      return
    end
    local at = ctx.selected and view_index (ctx.selected)
    if not at then
      at = step > 0 and ctx.win_from - 1 or ctx.win_from + ctx.drawn
    end
    for i = 1, count do
      local k = (at - ctx.view_first + i * step) % count + ctx.view_first
      local line = ctx.view_all[k]
      if line and line.marked then
        go_to_line (line)
        return
      end
    end
    say ('The filter hides every bookmarked line.')
  end

  ---Lists the bookmarked lines of the view's sources in a picker.
  local function list_marks ()
    local p = picker
    if not p then
      return
    end
    local lines = {} ---@type Logs.Line[]
    for _, src in ipairs (ctx.view_sources ()) do
      for i = 1, src.lines:count () do
        local line = src.lines:get (i)
        if line and line.marked then
          lines[#lines + 1] = line
        end
      end
    end
    if #ctx.view_sources () > 1 then
      table.sort (lines, function (a, b)
        if a.time and b.time and a.time ~= b.time then
          return a.time < b.time
        end
        return id_of (a) < id_of (b)
      end)
    end
    local items = {} ---@type Proteus.PickItem[]
    for _, line in ipairs (lines) do
      local tag = tag_of (line)
      items[#items + 1] = {
        label = lf.clip (lf.trim (line.plain), 200),
        detail = (tag and (tag.name .. ', ') or '') .. 'line ' .. line.n,
        icon = 'bookmark',
        value = line,
      }
    end
    p.pick ({
      items = items,
      placeholder = 'Go to a bookmarked line',
      empty = 'No lines are bookmarked. Ctrl+F2 bookmarks the selected line.',
      on_pick = function (item)
        if not go_to_line (item.value) then
          say ('The filter hides that line. Show All Lines shows it again.')
        end
      end,
    })
  end

  ctx.toggle_mark = toggle_mark
  ctx.forget_marks = forget_marks
  ctx.next_mark = next_mark
  ctx.list_marks = list_marks
  ctx.go_to_line = go_to_line
end

return M
