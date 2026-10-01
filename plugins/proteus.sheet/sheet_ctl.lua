-- sheet_ctl: the controller that joins the Sheet app's screen parts. init.lua and sheet_grid.lua
-- make it and own the grid, files and sheets. sheet_toolbar.lua and sheet_panels.lua use it for
-- the toolbar, the side panels and the pop-ups. The parts also reach each other's commands by
-- id with `commands.run`.

---What the grid shows besides the cells.
---@class Sheet.ViewOptions
---@field gridlines boolean
---@field formulas boolean True while formulas show instead of their values.

---@alias Sheet.CtlEvent
---| 'book' # A workbook opened or closed. No arguments.
---| 'sheet' # Another sheet shows. No arguments.
---| 'selection' # The selection or the active cell moved. Gets the active row and column.
---| 'changed' # The book changed, by any means, including undo and typing. No arguments.
---| 'editing' # Editing a cell started or stopped. Gets true or false.
---| 'chart' # A chart was selected, or none. Gets the chart's id or nil.
---| 'filter_menu' # A filter button in a header was clicked. Gets the column and the button's rect.
---| 'view' # A view option changed. Gets the new `Sheet.ViewOptions`.
---| 'scroll' # The grid scrolled. No arguments.

---@class Sheet.Ctl
---@field book fun(): Sheet.Book? The open workbook.
---@field sheet fun(): Sheet.Sheet? The sheet that shows.
---@field file fun(): string? The open workbook's name, without the folder or `.sheet.json`.
---@field selection fun(): Sheet.Rect, integer, integer The selected block, then the active cell's row and column.
---@field select fun(rect: Sheet.Rect, row?: integer, col?: integer) Selects a block, grown to whole merges, and scrolls to it. The active cell is the top left one unless given.
---@field show_sheet fun(index: integer) Shows another sheet of the book, as clicking its tab does.
---@field grid_rect fun(): Proteus.Rect? The grid's visible area on screen, in window pixels, without the headers.
---@field change fun(label: string, fn: fun(book: Sheet.Book, sheet: Sheet.Sheet): any?): any Runs model calls as one undo step named `label`, then draws, emits `changed` and schedules a save. Returns what `fn` returns. Shows the error when `fn` raises. Does nothing without an open sheet.
---@field redraw fun() Draws the grid again, charts included.
---@field editing fun(): boolean True while a cell is being edited.
---@field type_text fun(text: string) Types into the open cell editor at its cursor, or starts editing the active cell with `text`.
---@field cell_rect fun(row: integer, col: integer): Proteus.Rect? Where a cell is on screen, in window pixels, or nil when it is out of view.
---@field measure fun(text: string, style?: Sheet.Style): number The width of a text in pixels, in a style's font.
---@field root fun(): Proteus.El The app's root element. Pop-ups go inside it with `position: fixed`.
---@field focus fun() Gives the keyboard back to the grid.
---@field chart fun(): string? The selected chart's id.
---@field select_chart fun(id: string?) Selects a chart, or none.
---@field view fun(): Sheet.ViewOptions
---@field on fun(event: Sheet.CtlEvent, fn: fun(...: any)): fun() Listens for an event. Returns a function that stops listening.
---@field emit fun(event: Sheet.CtlEvent, ...: any)
---@field say fun(kind: 'info'|'success'|'warn'|'error', text: string) Shows a message.

---The formatting toolbar, from sheet_toolbar.lua.
---@class Sheet.ToolbarModule
---@field mount fun(app: Proteus.App, ctl: Sheet.Ctl, host: Proteus.El) Builds the toolbar inside `host`, and keeps it in step with the selection.

---The side panels, pop-ups, and the Format, Data and Insert commands, from sheet_panels.lua.
---@class Sheet.PanelsModule
---@field install fun(app: Proteus.App, ctl: Sheet.Ctl) Registers the panels and their commands.

---@class Sheet.CtlModule
local M = {}

---A small event hub for the controller's `on` and `emit`.
---@return fun(event: Sheet.CtlEvent, fn: fun(...: any)): fun() on
---@return fun(event: Sheet.CtlEvent, ...: any) emit
function M.events ()
  local listeners = {} ---@type table<string, (fun(...: any))[]>
  ---@param event Sheet.CtlEvent
  ---@param fn fun(...: any)
  ---@return fun()
  local function on (event, fn)
    local list = listeners[event] or {}
    listeners[event] = list
    list[#list + 1] = fn
    return function ()
      for i, f in ipairs (list) do
        if f == fn then
          table.remove (list, i)
          return
        end
      end
    end
  end
  ---@param event Sheet.CtlEvent
  ---@param ... any
  local function emit (event, ...)
    -- A copy, so a listener that stops listening does not skip the next one.
    local list = {} ---@type (fun(...: any))[]
    for i, f in ipairs (listeners[event] or {}) do
      list[i] = f
    end
    for _, f in ipairs (list) do
      f (...)
    end
  end
  return on, emit
end

return M
