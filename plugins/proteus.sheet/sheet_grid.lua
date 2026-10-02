-- sheet_grid: the Sheet app's grid. It draws the active sheet, keeps the selection, and handles
-- the mouse and the keys. sheet_grid_act.lua adds the actions on the selection, such as copy,
-- paste and inserting rows, sheet_grid_edit.lua adds editing and the formula bar, and
-- sheet_grid_tabs.lua the sheet tabs along the bottom. init.lua builds the controller from the
-- functions here.
--
-- The grid is one HTML table, drawn from sheet_grid_draw.lua. Only rows near the view are
-- drawn in a long sheet. The boxes over the cells, such as the selection and the active cell,
-- are placed by arithmetic from the running sums of the row heights and column widths. Every
-- box sits in four layers, one per pane of the frozen rows and columns, and each layer sticks
-- or scrolls with its pane. So moving the selection rewrites one small style element, and
-- scrolling moves nothing at all.
--
-- The cell editor is a text box that keeps the focus while it waits, unseen, over the active
-- cell. Typing goes straight into it, and a paste lands in it with its line breaks intact.

local calc = require ('sheet_grid_calc') --[[@as Sheet.GridCalcModule]]
local draw = require ('sheet_grid_draw') --[[@as Sheet.GridDrawModule]]
local model = require ('sheet_model') --[[@as Sheet.ModelModule]]
local ops = require ('sheet_ops') --[[@as Sheet.OpsModule]]

---The selection: the active cell, and a block from the anchor to the corner Shift moves.
---@class Sheet.GridSelection
---@field r integer
---@field c integer
---@field ar integer
---@field ac integer
---@field er integer
---@field ec integer

---A reference being put into a formula by pointing at cells.
---@class Sheet.GridPoint
---@field from integer The first byte of the reference in the text.
---@field to integer The byte after it.
---@field ar integer
---@field ac integer
---@field er integer
---@field ec integer

---The cell being edited.
---@class Sheet.GridEdit
---@field sheet Sheet.Sheet The sheet the cell is on, which may differ from the one showing.
---@field row integer
---@field col integer
---@field source 'cell'|'bar' The box the user types in.
---@field original string
---@field typed boolean True when typing started the edit, so arrow keys finish it.
---@field point? Sheet.GridPoint
---@field choices Sheet.CatalogEntry[] The functions the list under the editor offers.
---@field choice integer The highlighted one.

---A mouse drag in the grid.
---@class Sheet.GridDrag
---@field kind 'cells'|'rows'|'cols'|'point'|'fill'|'move'|'csize'|'rsize'|'chart'
---@field index? integer The row or column being resized.
---@field start number Where the pointer started, across for columns and down for rows.
---@field size? number The size when the drag started.
---@field x number The pointer's last place in the window.
---@field y number
---@field row? integer The cell the drag started on.
---@field col? integer
---@field target? Sheet.Rect Where a fill or a move goes.
---@field chart? string
---@field handle? string
---@field box? Sheet.GridBox A chart's box when the drag started.
---@field now? Sheet.GridBox A chart's box now.
---@field last? string The cell the pointer was last over, as `row,col`.

---What init.lua gives the grid.
---@class Sheet.GridEnv
---@field emit fun(event: Sheet.CtlEvent, ...: any)
---@field say fun(kind: 'info'|'success'|'warn'|'error', text: string)
---@field dirty fun() The book changed, so save it soon.

---The grid. The fields past the elements are functions, some added by sheet_grid_act.lua,
---sheet_grid_edit.lua and sheet_grid_tabs.lua.
---@class Sheet.GridView
---@field app Proteus.App
---@field ui Proteus.UI
---@field env Sheet.GridEnv
---@field commands Proteus.Commands
---@field menus? Proteus.Menus
---@field picker? Proteus.Picker
---@field status? Proteus.Status
---@field cur_book? Sheet.Book
---@field sel Sheet.GridSelection
---@field edit? Sheet.GridEdit
---@field clip? Sheet.Clip
---@field clip_rect? Sheet.Rect
---@field clip_sheet? Sheet.Sheet
---@field geo? Sheet.GridGeo
---@field sx number
---@field sy number
---@field vw number
---@field vh number
---@field srect? Proteus.Rect Where the scrolling box sits in the window.
---@field drawn_first integer
---@field drawn_last integer
---@field view_opts Sheet.ViewOptions
---@field chart_id? string
---@field drag? Sheet.GridDrag
---@field styles Sheet.GridStyles
---@field ref_css string The boxes around the references of the formula being typed.
---@field paste_mode? Sheet.PasteOptions How the next paste from the keyboard pastes.
---@field saved_sel table<Sheet.Sheet, { sel: Sheet.GridSelection, sx: number, sy: number }>
---@field area Proteus.El The grid and the boxes over it.
---@field scroll Proteus.El
---@field canvas Proteus.El
---@field host Proteus.El Holds the table.
---@field holder Proteus.El Holds the cell editor.
---@field edbox Proteus.El
---@field editor Proteus.El The cell editor.
---@field mirror Proteus.El The coloured copy of the editor's text.
---@field pop Proteus.El The list or hint under the cell editor.
---@field bar Proteus.El The formula bar.
---@field fbar Proteus.El The formula bar's text box.
---@field fmirror Proteus.El
---@field fpop Proteus.El
---@field namebox Proteus.El
---@field tabs_bar Proteus.El
---@field measurer Proteus.El
---@field tip Proteus.El The note shown beside a cell.
---@field guide Proteus.El The line that shows a new row or column size.
---@field chart_layers table<string, Proteus.El>
---@field sheet fun(): Sheet.Sheet?
---@field sel_rect fun(): Sheet.Rect
---@field cur_rect fun(): Sheet.Rect
---@field draw fun()
---@field place fun()
---@field place_boxes fun()
---@field reveal fun(row: integer, col: integer)
---@field select fun(rect: Sheet.Rect, row?: integer, col?: integer)
---@field select_cell fun(row: integer, col: integer, extend?: boolean)
---@field move fun(dr: integer, dc: integer, extend?: boolean, jump?: boolean)
---@field change fun(label: string, fn: fun(book: Sheet.Book, sheet: Sheet.Sheet): any?): any
---@field after_change fun()
---@field set_book fun(book: Sheet.Book?)
---@field show_sheet fun(index: integer)
---@field sheet_shown fun()
---@field hit_at fun(x: number, y: number): Sheet.GridHit?
---@field cell_rect fun(row: integer, col: integer): Proteus.Rect?
---@field grid_rect fun(): Proteus.Rect?
---@field measure fun(text: string, style?: Sheet.Style): number
---@field focus fun()
---@field typing fun(): boolean
---@field select_chart fun(id: string?)
---@field delete_chart fun()
---@field set_box fun(name: 'target'|'point', rect?: Sheet.Rect)
---@field refs_css fun(spans: Sheet.GridSpan[], colors: integer[], own: Sheet.Sheet): string
---@field edit_moved fun()
---@field drop_clip fun()
---@field charts_later fun()
---@field redraw_charts fun()
---@field grid_key fun(ev: Proteus.DomEvent): Proteus.EventResult
---@field set_view fun(key: 'gridlines'|'formulas', on: boolean)
---@field undo fun(back: boolean)
---@field copy fun(cut: boolean)
---@field paste_text fun(text: string, opts?: Sheet.PasteOptions)
---@field paste fun(opts?: Sheet.PasteOptions)
---@field clear fun()
---@field select_all fun()
---@field fill fun(down: boolean)
---@field insert fun(axis: 'row'|'col', after: boolean)
---@field delete fun(axis: 'row'|'col')
---@field hide fun(axis: 'row'|'col', on: boolean)
---@field freeze fun(rows?: integer, cols?: integer)
---@field ask_size fun(axis: 'row'|'col')
---@field autofit fun(cols?: integer[])
---@field autofit_row fun(rows: integer[])
---@field fill_to_end fun()
---@field count_label fun(what: string, axis: 'row'|'col'): string
---@field stats_later fun()
---@field begin_edit fun(source: 'cell'|'bar', text: string, typed: boolean)
---@field finish_edit fun(dr: integer, dc: integer, refocus?: boolean): boolean
---@field cancel_edit fun()
---@field type_text fun(text: string)
---@field point_at fun(row: integer, col: integer, extend: boolean): boolean
---@field show_edit_text fun()
---@field open_dropdown fun(row: integer, col: integer)
---@field tabs_draw fun()
---@field show_stats fun(text: string?, size: string?)
---@field add_sheet fun()
---@field rename_sheet fun(index: integer)
---@field duplicate_sheet fun(index: integer)
---@field delete_sheet fun(index: integer)
---@field move_sheet fun(index: integer, delta: integer)
---@field step_sheet fun(delta: integer)
---@field pick_sheet fun()

---@class Sheet.GridModule
local M = {}

-- A sheet with more rows than this draws only the rows near the view, plus a margin.
local DRAW_ALL = 300
local MARGIN = 60
-- How close the view may come to the edge of the drawn rows before they are drawn again.
local SLACK = 20
-- How many reference outlines can show at once.
local REF_BOXES = 12
local HEAD_W, HEAD_H = calc.HEAD_W, calc.HEAD_H

-- lang=css
local CSS = [[
.sheet-grid-area { flex: 1; min-height: 0; position: relative; background: var(--bg); }
.sheet-grid-scroll { position: absolute; inset: 0; overflow: auto; z-index: 0; outline: none; }
.sheet-grid-canvas { position: relative; }
.sheet-grid-host { position: static; }
.sheet-grid-pn, .sheet-grid-ly { display: block; width: 0; height: 0; pointer-events: none; }
.sheet-grid-pn-br { position: absolute; left: 0; top: 0; z-index: 1; }
.sheet-grid-ly-br { position: absolute; left: 0; top: 0; z-index: 2; }
.sheet-grid-pn-bl { position: sticky; left: 0; z-index: 6; }
.sheet-grid-pn-tr { position: sticky; top: 0; z-index: 6; }
.sheet-grid-ly-bl { position: sticky; left: 0; z-index: 7; }
.sheet-grid-ly-tr { position: sticky; top: 0; z-index: 7; }
.sheet-grid-pn-tl { position: sticky; left: 0; top: 0; z-index: 10; }
.sheet-grid-ly-tl { position: sticky; left: 0; top: 0; z-index: 11; }
.sheet-grid-hold { display: block; width: 0; height: 0; position: sticky; z-index: 15; }

.sheet-grid-t { table-layout: fixed; border-collapse: separate; border-spacing: 0;
  font-variant-numeric: tabular-nums; color: var(--fg); }
.sheet-grid-t tbody tr { height: 24px; }
.sheet-grid-t thead tr { height: 24px; }
.sheet-grid-t td { box-sizing: border-box; padding: 2px 4px; border: 0; overflow: hidden;
  border-right: 1px solid var(--border); border-bottom: 1px solid var(--border);
  background-color: var(--bg); vertical-align: bottom; white-space: nowrap; line-height: 1.25; }
.sheet-grid-t td > div { max-height: var(--h, 19px); overflow: hidden; white-space: pre; }
.sheet-grid-t td.sheet-grid-o { overflow: visible; }
.sheet-grid-t .sheet-grid-ic { float: left; margin-right: 4px; }
.sheet-grid-t td.sheet-grid-fc { position: sticky; z-index: 3; }
.sheet-grid-t tr.sheet-grid-fr > td { position: sticky; z-index: 4; }
.sheet-grid-t tr.sheet-grid-fr > td.sheet-grid-fc { z-index: 8; }
.sheet-grid-t td.sheet-grid-fc.sheet-grid-o { z-index: 4; }
.sheet-grid-t tr.sheet-grid-fr > td.sheet-grid-o { z-index: 5; }
.sheet-grid-t tr.sheet-grid-fr > td.sheet-grid-fc.sheet-grid-o { z-index: 9; }
.sheet-grid-t tr.sheet-grid-frl > td, .sheet-grid-t tr.sheet-grid-frl > th { box-shadow: inset 0 -2px 0 var(--fg-faint); }
.sheet-grid-t .sheet-grid-fcl { box-shadow: inset -2px 0 0 var(--fg-faint); }
.sheet-grid-t tr.sheet-grid-frl > .sheet-grid-fcl { box-shadow: inset 0 -2px 0 var(--fg-faint), inset -2px 0 0 var(--fg-faint); }
.sheet-grid-t th { box-sizing: border-box; padding: 0 2px; border: 0; background: var(--bg-alt);
  color: var(--fg-muted); font-size: 11px; font-weight: 500; text-align: center; user-select: none;
  border-right: 1px solid var(--border); border-bottom: 1px solid var(--border); white-space: nowrap;
  overflow: hidden; }
.sheet-grid-t thead th { position: sticky; top: 0; z-index: 12; }
.sheet-grid-t tbody th { position: sticky; left: 0; z-index: 12; }
.sheet-grid-t thead th.sheet-grid-fc, .sheet-grid-t tr.sheet-grid-fr > th { z-index: 13; }
.sheet-grid-t thead th.sheet-grid-corner { left: 0; z-index: 14; }
.sheet-grid-t thead th.sheet-grid-hid { box-shadow: inset 3px 0 0 -1px var(--fg-faint); }
.sheet-grid-t tr.sheet-grid-pad td { padding: 0; border: 0; background: none; }
.sheet-grid-nogrid .sheet-grid-t td { border-right-color: transparent; border-bottom-color: transparent; }
.sheet-grid-cs { position: absolute; top: 0; right: -1px; width: 5px; height: 100%; cursor: col-resize; }
.sheet-grid-rs { position: absolute; left: 0; bottom: -1px; height: 5px; width: 100%; cursor: row-resize; }
.sheet-grid-cs:hover, .sheet-grid-rs:hover { background: var(--accent); }
.sheet-grid-t td.sheet-grid-nt { background-image: linear-gradient(225deg, var(--warning) 50%, transparent 50%);
  background-size: 8px 8px; background-position: right top; background-repeat: no-repeat; }
.sheet-grid-t td.sheet-grid-dd, .sheet-grid-t td.sheet-grid-fb { padding-right: 18px; background-repeat: no-repeat;
  background-image: linear-gradient(45deg, transparent 50%, var(--fg-muted) 50%),
    linear-gradient(135deg, var(--fg-muted) 50%, transparent 50%);
  background-size: 4px 4px, 4px 4px; background-position: right 9px center, right 5px center; }
.sheet-grid-t td.sheet-grid-fb { background-image: linear-gradient(45deg, transparent 50%, var(--fg-muted) 50%),
    linear-gradient(135deg, var(--fg-muted) 50%, transparent 50%),
    linear-gradient(var(--bg-hover), var(--bg-hover));
  background-size: 4px 4px, 4px 4px, 14px 14px;
  background-position: right 8px center, right 4px center, right 1px center; }
.sheet-grid-t td.sheet-grid-fon { background-image: linear-gradient(45deg, transparent 50%, var(--accent-fg) 50%),
    linear-gradient(135deg, var(--accent-fg) 50%, transparent 50%),
    linear-gradient(var(--accent), var(--accent)); }

.sheet-grid-b { position: absolute; display: none; box-sizing: border-box; pointer-events: none; }
.sheet-grid-b-sel { border: 1px solid var(--accent); background: color-mix(in srgb, var(--accent) 10%, transparent); }
.sheet-grid-b-cur { border: 2px solid var(--accent); }
.sheet-grid-b-copy { border: 2px dashed var(--accent); }
.sheet-grid-b-point { border: 2px dashed var(--fg); }
.sheet-grid-b-target { border: 2px dashed var(--fg-muted); background: color-mix(in srgb, var(--fg-muted) 8%, transparent); }
.sheet-grid-b-find { border: 2px solid var(--warning); }
.sheet-grid-b-ref { border: 2px solid; }
.sheet-grid-edge { position: absolute; pointer-events: auto; cursor: move; }
.sheet-grid-edge-t { left: 0; right: 0; top: -3px; height: 5px; }
.sheet-grid-edge-b { left: 0; right: 0; bottom: -3px; height: 5px; }
.sheet-grid-edge-l { top: 0; bottom: 0; left: -3px; width: 5px; }
.sheet-grid-edge-r { top: 0; bottom: 0; right: -3px; width: 5px; }
.sheet-grid-fill { position: absolute; right: -4px; bottom: -4px; width: 7px; height: 7px; pointer-events: auto;
  cursor: crosshair; background: var(--accent); border: 1px solid var(--bg); box-sizing: border-box; }
.sheet-grid-busy .sheet-grid-edge, .sheet-grid-busy .sheet-grid-fill { display: none; }

.sheet-grid-chart { position: absolute; pointer-events: auto; background: var(--bg-elev);
  border: 1px solid var(--border); border-radius: 4px; box-sizing: border-box; overflow: visible; cursor: default; }
.sheet-grid-chart > svg { display: block; width: 100%; height: 100%; border-radius: 4px; }
.sheet-grid-chart.sheet-grid-on { outline: 2px solid var(--accent); outline-offset: 1px; cursor: move; }
.sheet-grid-hdl { position: absolute; width: 8px; height: 8px; background: var(--bg); border: 2px solid var(--accent);
  border-radius: 2px; box-sizing: border-box; }
.sheet-grid-hdl-nw { left: -6px; top: -6px; cursor: nwse-resize; }
.sheet-grid-hdl-n { left: calc(50% - 4px); top: -6px; cursor: ns-resize; }
.sheet-grid-hdl-ne { right: -6px; top: -6px; cursor: nesw-resize; }
.sheet-grid-hdl-e { right: -6px; top: calc(50% - 4px); cursor: ew-resize; }
.sheet-grid-hdl-se { right: -6px; bottom: -6px; cursor: nwse-resize; }
.sheet-grid-hdl-s { left: calc(50% - 4px); bottom: -6px; cursor: ns-resize; }
.sheet-grid-hdl-sw { left: -6px; bottom: -6px; cursor: nesw-resize; }
.sheet-grid-hdl-w { left: -6px; top: calc(50% - 4px); cursor: ew-resize; }

.sheet-grid-guide { position: absolute; display: none; z-index: 30; pointer-events: none; background: var(--accent); }
.sheet-grid-measure { position: fixed; left: -20000px; top: 0; visibility: hidden; width: max-content;
  white-space: pre; font-family: var(--font-ui); font-size: 13px; line-height: 1.25; }
.sheet-grid-measure > div { padding: 2px 4px; }
.sheet-grid-tip { position: fixed; z-index: 1000; display: none; max-width: 280px; padding: 8px 10px;
  background: var(--bg-elev); color: var(--fg); border: 1px solid var(--border); border-left: 3px solid var(--warning);
  border-radius: var(--radius); box-shadow: var(--shadow); white-space: pre-wrap; font-size: 12px;
  pointer-events: none; }
.sheet-grid-rc1 { color: var(--syn-function); } .sheet-grid-rc2 { color: var(--syn-constant); }
.sheet-grid-rc3 { color: var(--syn-string); } .sheet-grid-rc4 { color: var(--syn-keyword); }
.sheet-grid-rc5 { color: var(--syn-number); } .sheet-grid-rc6 { color: var(--syn-builtin); }
.sheet-grid-rc7 { color: var(--syn-property); } .sheet-grid-rc8 { color: var(--danger); }
]]

-- The theme colours the reference outlines cycle through, in the order of `.sheet-grid-rc*`.
local REF_COLORS = {
  'var(--syn-function)',
  'var(--syn-constant)',
  'var(--syn-string)',
  'var(--syn-keyword)',
  'var(--syn-number)',
  'var(--syn-builtin)',
  'var(--syn-property)',
  'var(--danger)',
}

---@type table<string, { [1]: integer, [2]: integer }>
local ARROWS = {
  ArrowUp = { -1, 0 },
  ArrowDown = { 1, 0 },
  ArrowLeft = { 0, -1 },
  ArrowRight = { 0, 1 },
}

---The box names every pane layer holds.
local BOXES = { 'sel', 'copy', 'target', 'point', 'cur', 'frame' }

---@param rect Sheet.Rect
---@param r integer
---@param c integer
---@return boolean
local function inside (rect, r, c)
  return r >= rect.r1 and r <= rect.r2 and c >= rect.c1 and c <= rect.c2
end

---@param app Proteus.App
---@param env Sheet.GridEnv
---@return Sheet.GridView
function M.new (app, env)
  local ui = app.use ('ui')
  ui.css (CSS)
  local frame_style = ui.css ('')
  local cell_style = ui.css ('')
  local box_style = ui.css ('')
  local drag_style = ui.css ('')
  local written = { frame = '', cells = -1, boxes = '' }

  ---@type Sheet.GridView
  ---@diagnostic disable-next-line: missing-fields
  local G = {
    app = app,
    ui = ui,
    env = env,
    commands = app.use ('commands'),
    menus = app.try_use ('menus'),
    picker = app.try_use ('picker'),
    status = app.try_use ('status'),
    sel = { r = 1, c = 1, ar = 1, ac = 1, er = 1, ec = 1 },
    sx = 0,
    sy = 0,
    vw = 800,
    vh = 600,
    drawn_first = 1,
    drawn_last = 0,
    view_opts = { gridlines = true, formulas = false },
    styles = draw.new_styles (),
    ref_css = '',
    saved_sel = setmetatable ({}, { __mode = 'k' }),
  }
  local saved_view = app.store.get ('view')
  if type (saved_view) == 'table' then
    G.view_opts.gridlines = saved_view.gridlines ~= false
    G.view_opts.formulas = saved_view.formulas == true
  end

  -- Screen parts ---------------------------------------------------------------------------

  ---The same boxes in one pane layer, as HTML.
  ---@return string
  local function pane_boxes ()
    local parts = {} ---@type string[]
    for _, name in ipairs (BOXES) do
      if name == 'frame' then
        parts[#parts + 1] = '<div class="sheet-grid-b sheet-grid-b-frame">'
          .. '<i class="sheet-grid-edge sheet-grid-edge-t" data-item="move"></i>'
          .. '<i class="sheet-grid-edge sheet-grid-edge-b" data-item="move"></i>'
          .. '<i class="sheet-grid-edge sheet-grid-edge-l" data-item="move"></i>'
          .. '<i class="sheet-grid-edge sheet-grid-edge-r" data-item="move"></i>'
          .. '<i class="sheet-grid-fill" data-item="fill"></i></div>'
      else
        parts[#parts + 1] = '<div class="sheet-grid-b sheet-grid-b-'
          .. name
          .. '"></div>'
      end
    end
    for i = 1, REF_BOXES do
      parts[#parts + 1] = '<div class="sheet-grid-b sheet-grid-b-ref sheet-grid-b-rf'
        .. i
        .. '"></div>'
    end
    return table.concat (parts)
  end

  local panes = {} ---@type Proteus.El[]
  G.chart_layers = {}
  for _, name in ipairs ({ 'br', 'bl', 'tr', 'tl' }) do
    panes[#panes + 1] = ui.div ({
      class = 'sheet-grid-pn sheet-grid-pn-' .. name,
      html = pane_boxes (),
    })
    local layer = ui.div ({ class = 'sheet-grid-ly sheet-grid-ly-' .. name })
    G.chart_layers[name] = layer
    panes[#panes + 1] = layer
  end
  G.editor = ui.h ('textarea', {
    class = 'sheet-grid-editor',
    spellcheck = false,
    rows = 1,
    attrs = { autocomplete = 'off', ['aria-label'] = 'Cell' },
  })
  G.mirror = ui.div ({ class = 'sheet-grid-mirror' })
  G.pop = ui.div ({ class = 'sheet-grid-pop' })
  G.edbox = ui.div ({
    class = 'sheet-grid-edbox',
    ui.div ({ class = 'sheet-grid-edwrap', G.mirror, G.editor }),
    G.pop,
  })
  G.holder = ui.div ({ class = 'sheet-grid-hold', G.edbox })
  G.host = ui.div ({ class = 'sheet-grid-host' })
  G.canvas = ui.div ({ class = 'sheet-grid-canvas', panes, G.holder, G.host })
  G.scroll = ui.div ({ class = 'sheet-grid-scroll', G.canvas })
  G.guide = ui.div ({ class = 'sheet-grid-guide' })
  G.area = ui.div ({ class = 'sheet-grid-area', G.scroll, G.guide })
  G.measurer = ui.div ({ class = 'sheet-grid-measure' })
  G.tip = ui.div ({ class = 'sheet-grid-tip' })

  -- Basics ---------------------------------------------------------------------------------

  ---@return Sheet.Sheet?
  function G.sheet ()
    local book = G.cur_book
    return book and book:active_sheet () or nil
  end

  ---The selected block, grown to take in whole merged blocks.
  ---@return Sheet.Rect
  function G.sel_rect ()
    local sel = G.sel
    local rect = {
      r1 = math.min (sel.ar, sel.er),
      c1 = math.min (sel.ac, sel.ec),
      r2 = math.max (sel.ar, sel.er),
      c2 = math.max (sel.ac, sel.ec),
    }
    local s = G.sheet ()
    -- Whole rows and columns stay as they are, as in other spreadsheets.
    if
      s
      and #s.merges > 0
      and not (rect.r1 == 1 and rect.r2 >= s.rows)
      and not (rect.c1 == 1 and rect.c2 >= s.cols)
    then
      return s:expand_to_merges (rect)
    end
    return rect
  end

  ---The active cell, or the merged block it starts.
  ---@return Sheet.Rect
  function G.cur_rect ()
    local sel = G.sel
    local s = G.sheet ()
    local m = s and s:merge_at (sel.r, sel.c)
    if m then
      return { r1 = m.r1, c1 = m.c1, r2 = m.r2, c2 = m.c2 }
    end
    return { r1 = sel.r, c1 = sel.c, r2 = sel.r, c2 = sel.c }
  end

  local function read_view ()
    G.vw = tonumber (G.scroll:get ('clientWidth')) or G.vw
    G.vh = tonumber (G.scroll:get ('clientHeight')) or G.vh
  end

  local function read_scroll ()
    G.sx = tonumber (G.scroll:get ('scrollLeft')) or 0
    G.sy = tonumber (G.scroll:get ('scrollTop')) or 0
  end

  -- The row tops with rows grown for big fonts, kept until the book changes.
  local grown = { sheet = nil, stamp = -1, tops = {}, model = {} } ---@type { sheet: Sheet.Sheet?, stamp: integer, tops: number[], model: number[] }

  ---A top in the model's rows, as the grid draws it with rows grown for big fonts.
  ---@param y number
  ---@return number
  local function map_y (y)
    return calc.map_pos (grown.model, grown.tops, y)
  end

  ---@return Sheet.GridGeo?
  local function make_geo ()
    local s = G.sheet ()
    if not s then
      return nil
    end
    local lay = s:layout ()
    local fr, fc = s:freeze ()
    if
      grown.sheet ~= s
      or grown.stamp ~= s.book.stamp
      or #grown.tops ~= #lay.tops
    then
      grown.sheet, grown.stamp, grown.model = s, s.book.stamp, lay.tops
      grown.tops = draw.grow_tops (lay.tops, draw.auto_heights (s))
    end
    G.geo = calc.geometry (grown.tops, lay.lefts, fr, fc)
    return G.geo
  end

  -- Charts ---------------------------------------------------------------------------------

  -- Each chart's picture, kept until the book changes and a pause passes.
  ---@type table<string, { svg: string, w: number, h: number, sheet: Sheet.Sheet }>
  local svgs = {}
  local charts_stale = false
  local cancel_charts = nil ---@type fun()?

  ---@param spec Sheet.ChartSpec
  ---@return string
  local function chart_svg (spec)
    local s = G.sheet ()
    local hit = svgs[spec.id]
    if hit and hit.w == spec.w and hit.h == spec.h and hit.sheet == s then
      return hit.svg
    end
    local ok, svg = pcall (ops.chart_svg, s --[[@as Sheet.Sheet]], spec)
    if not ok then
      svg = '<svg xmlns="http://www.w3.org/2000/svg"></svg>'
    end
    svgs[spec.id] = {
      svg = svg,
      w = spec.w,
      h = spec.h,
      sheet = s --[[@as Sheet.Sheet]],
    }
    return svg
  end

  local drawn_charts = {} ---@type table<string, string>

  local function draw_charts ()
    local s, geo = G.sheet (), G.geo
    local html = { tl = '', tr = '', bl = '', br = '' } ---@type table<string, string>
    if s and geo then
      html = draw.charts_html (s, geo, chart_svg, G.chart_id, map_y)
    end
    for name, layer in pairs (G.chart_layers) do
      local text = html[name] or ''
      if drawn_charts[name] ~= text then
        drawn_charts[name] = text
        layer:html (text)
      end
    end
  end

  ---Draws the charts again after a pause, since a big chart takes a moment.
  function G.charts_later ()
    charts_stale = true
    if cancel_charts then
      cancel_charts ()
    end
    cancel_charts = app.timer.after (350, function ()
      cancel_charts = nil
      if charts_stale then
        charts_stale = false
        svgs = {}
        draw_charts ()
      end
    end)
  end

  ---Draws every chart again now.
  function G.redraw_charts ()
    svgs = {}
    draw_charts ()
  end

  -- Drawing --------------------------------------------------------------------------------

  ---Draws the table again: the rows near the view, the classes of new looks, and the CSS that
  ---places the frozen panes.
  function G.draw ()
    local s = G.sheet ()
    if not s then
      return
    end
    read_view ()
    local geo = make_geo () --[[@as Sheet.GridGeo]]
    local first, last = calc.draw_rows (geo, G.sy, G.vh, MARGIN, DRAW_ALL)
    G.drawn_first, G.drawn_last = first, last
    local ok, html = pcall (draw.table_html, s, geo, {
      first = first,
      last = last,
      formulas = G.view_opts.formulas,
      styles = G.styles,
    })
    if not ok then
      env.say ('error', 'The sheet could not be drawn: ' .. tostring (html))
      return
    end
    if G.styles.stamp ~= written.cells then
      written.cells = G.styles.stamp
      cell_style:set (draw.styles_css (G.styles))
    end
    local frame = draw.frame_css (geo)
    if frame ~= written.frame then
      written.frame = frame
      frame_style:set (frame)
    end
    G.host:html (html)
    G.area:class ('sheet-grid-nogrid', not G.view_opts.gridlines)
    draw_charts ()
    G.place ()
  end

  ---The CSS rule that shows a box over a block of cells.
  ---@param name string
  ---@param rect Sheet.Rect
  ---@param extra? string
  ---@return string
  local function box_rule (name, rect, extra)
    local geo = G.geo --[[@as Sheet.GridGeo]]
    local b = calc.canvas_box (geo, rect)
    return '.sheet-grid-b-'
      .. name
      .. '{display:block;left:'
      .. (b.x - 1)
      .. 'px;top:'
      .. (b.y - 1)
      .. 'px;width:'
      .. (b.w + 1)
      .. 'px;height:'
      .. (b.h + 1)
      .. 'px'
      .. (extra or '')
      .. '}'
  end

  ---The CSS of the reference outlines for a formula's references on the sheet that shows.
  ---@param spans Sheet.GridSpan[]
  ---@param colors integer[]
  ---@param own Sheet.Sheet The sheet the formula lives on.
  ---@return string
  function G.refs_css (spans, colors, own)
    local s, geo = G.sheet (), G.geo
    if not s or not geo then
      return ''
    end
    local out = {} ---@type string[]
    local seen = {} ---@type table<string, boolean>
    local n = 0
    for i, span in ipairs (spans) do
      local area = span.area
      local on_sheet = area.sheet == nil and own == s
        or (
          area.sheet ~= nil
          and string.lower (area.sheet) == string.lower (s.name)
        )
      local key = calc.area_key (area)
      if on_sheet and not seen[key] and n < REF_BOXES then
        seen[key] = true
        local rect = calc.area_rect (area, s.rows, s.cols)
        if rect then
          n = n + 1
          local color = REF_COLORS[colors[i]] or REF_COLORS[1]
          out[#out + 1] = box_rule (
            'rf' .. n,
            rect,
            ';border-color:'
              .. color
              .. ';background:color-mix(in srgb,'
              .. color
              .. ' 8%,transparent)'
          )
        end
      end
    end
    return table.concat (out)
  end

  -- Extra boxes other parts ask for, such as a drag's target.
  local extra_boxes = {} ---@type table<string, Sheet.Rect>

  ---@param name 'target'|'point'
  ---@param rect? Sheet.Rect
  function G.set_box (name, rect)
    extra_boxes[name] = rect
    G.place_boxes ()
  end

  ---Writes the CSS that places every box, the idle editor and the lit headers.
  function G.place_boxes ()
    local s, geo = G.sheet (), G.geo
    if not s or not geo then
      return
    end
    local rect = G.sel_rect ()
    local cur = G.cur_rect ()
    local rules = {} ---@type string[]
    if rect.r1 ~= rect.r2 or rect.c1 ~= rect.c2 then
      -- The active cell stays clear of the selection's tint, so its own border shows.
      local sb = calc.canvas_box (geo, rect)
      local cb = calc.canvas_box (geo, cur)
      local x1, y1 = cb.x - sb.x, cb.y - sb.y
      local x2, y2 = x1 + cb.w + 1, y1 + cb.h + 1
      rules[#rules + 1] = box_rule (
        'sel',
        rect,
        string.format (
          ';clip-path:polygon(evenodd,0 0,100%% 0,100%% 100%%,0 100%%,0 0,'
            .. '%gpx %gpx,%gpx %gpx,%gpx %gpx,%gpx %gpx,%gpx %gpx)',
          x1,
          y1,
          x2,
          y1,
          x2,
          y2,
          x1,
          y2,
          x1,
          y1
        )
      )
    end
    local edit = G.edit
    local here = not edit or edit.sheet == s
    if here then
      rules[#rules + 1] = box_rule ('cur', cur)
    end
    rules[#rules + 1] = box_rule ('frame', rect)
    if G.clip and G.clip_rect and G.clip_sheet == s then
      rules[#rules + 1] = box_rule ('copy', G.clip_rect)
    end
    for name, r in pairs (extra_boxes) do
      rules[#rules + 1] = box_rule (name, r)
    end
    rules[#rules + 1] = G.ref_css
    -- The cell editor waits over the active cell, sticking with its pane.
    local ed = edit
        and { r1 = edit.row, c1 = edit.col, r2 = edit.row, c2 = edit.col }
      or cur
    if edit then
      local m = edit.sheet:merge_at (edit.row, edit.col)
      if m then
        ed = m
      end
    end
    local b = calc.canvas_box (geo, ed)
    rules[#rules + 1] = '.sheet-grid-canvas .sheet-grid-edbox{left:'
      .. (b.x - 1)
      .. 'px;top:'
      .. (b.y - 1)
      .. 'px;--w:'
      .. (b.w + 1)
      .. 'px;--h:'
      .. (b.h + 1)
      .. 'px}.sheet-grid-canvas .sheet-grid-hold{top:'
      .. (ed.r1 <= geo.fr and '0' or 'auto')
      .. ';left:'
      .. (ed.c1 <= geo.fc and '0' or 'auto')
      .. '}'
    -- The column letters and row numbers of the selection light up.
    local lit = {} ---@type string[]
    for c = rect.c1, math.min (rect.c2, rect.c1 + 200) do
      lit[#lit + 1] = '.sheet-grid-t th[data-item="col:' .. c .. '"]'
    end
    local r1 = math.max (rect.r1, 1)
    local r2 = math.min (rect.r2, r1 + 400)
    for r = r1, r2 do
      if r <= geo.fr or (r >= G.drawn_first and r <= G.drawn_last) then
        lit[#lit + 1] = '.sheet-grid-t th[data-item="row:' .. r .. '"]'
      end
    end
    if #lit > 0 then
      rules[#rules + 1] = table.concat (lit, ',')
        .. '{background:var(--bg-active);color:var(--fg)}'
    end
    if G.chart_id or (G.drag and G.drag.kind ~= 'fill') or edit then
      rules[#rules + 1] = '.sheet-grid-fill,.sheet-grid-edge{display:none}'
    end
    local text = table.concat (rules, '\n')
    if text ~= written.boxes then
      written.boxes = text
      box_style:set (text)
    end
  end

  ---Places the boxes and updates the formula bar, the name box and the status numbers.
  function G.place ()
    local s = G.sheet ()
    if not s then
      return
    end
    G.place_boxes ()
    if not G.edit then
      G.show_edit_text ()
    end
    local rect = G.sel_rect ()
    if app.dom.active () ~= G.namebox.id then
      G.namebox:value (model.range_name (rect))
    end
    G.stats_later ()
    env.emit ('selection', G.sel.r, G.sel.c)
  end

  ---Scrolls so a cell shows, and draws more rows when it lies past the ones drawn.
  ---@param row integer
  ---@param col integer
  function G.reveal (row, col)
    local s, geo = G.sheet (), G.geo
    if not s or not geo then
      return
    end
    local rect = { r1 = row, c1 = col, r2 = row, c2 = col }
    local m = s:merge_at (row, col)
    if m then
      rect = { r1 = m.r1, c1 = m.c1, r2 = m.r2, c2 = m.c2 }
    end
    local nx, ny = calc.reveal (geo, rect, G.sx, G.sy, G.vw, G.vh)
    if nx ~= G.sx then
      G.scroll:set ('scrollLeft', nx)
      G.sx = nx
    end
    if ny ~= G.sy then
      G.scroll:set ('scrollTop', ny)
      G.sy = ny
      if
        calc.needs_rows (geo, G.sy, G.vh, G.drawn_first, G.drawn_last, SLACK)
      then
        G.draw ()
      end
    end
  end

  G.scroll:on ('scroll', function ()
    read_scroll ()
    local geo = G.geo
    if
      geo
      and calc.needs_rows (geo, G.sy, G.vh, G.drawn_first, G.drawn_last, SLACK)
    then
      G.draw ()
    end
    G.tip:style ('display', 'none')
    env.emit ('scroll')
    return nil
  end)

  app.dom.on_global ('resize', function ()
    if G.sheet () then
      G.srect = nil
      G.draw ()
    end
    return nil
  end)

  -- Selecting ------------------------------------------------------------------------------

  ---Selects a block, grown to whole merges, with the active cell at `row`, `col` or its top
  ---left, and scrolls to it.
  ---@param rect Sheet.Rect
  ---@param row? integer
  ---@param col? integer
  function G.select (rect, row, col)
    local s = G.sheet ()
    if not s then
      return
    end
    local r = model.tidy (rect)
    s:grow (r.r2, r.c2)
    r = s:expand_to_merges (r)
    local ar, ac = row or r.r1, col or r.c1
    G.sel = { r = ar, c = ac, ar = r.r1, ac = r.c1, er = r.r2, ec = r.c2 }
    G.select_chart (nil)
    if not G.geo or #G.geo.tops - 1 ~= s.rows or #G.geo.lefts - 1 ~= s.cols then
      G.draw ()
    else
      G.place ()
    end
    G.reveal (ar, ac)
  end

  ---Selects a cell, or stretches the selection to it. Moving past the edge adds a row or a
  ---column.
  ---@param row integer
  ---@param col integer
  ---@param extend? boolean
  function G.select_cell (row, col, extend)
    local s = G.sheet ()
    if not s then
      return
    end
    row, col = math.max (1, row), math.max (1, col)
    if row > s.rows or col > s.cols then
      s:grow (row, col)
      env.dirty ()
      G.draw ()
    end
    if extend then
      G.sel.er, G.sel.ec = row, col
    else
      -- A cell under a merged block stands for the block, whose text is in its first cell.
      local m = s:merge_at (row, col)
      if m then
        row, col = m.r1, m.c1
      end
      G.sel = { r = row, c = col, ar = row, ac = col, er = row, ec = col }
    end
    G.select_chart (nil)
    G.place ()
    G.reveal (row, col)
  end

  ---Moves the active cell, or the far corner with `extend`, one cell or to the edge of the
  ---data with `jump`. Hidden rows and columns and the cells under a merge are passed over.
  ---@param dr integer
  ---@param dc integer
  ---@param extend? boolean
  ---@param jump? boolean
  function G.move (dr, dc, extend, jump)
    local s = G.sheet ()
    if not s then
      return
    end
    local sel = G.sel
    local r, c = sel.r, sel.c
    if extend then
      r, c = sel.er, sel.ec
    end
    local nr, nc ---@type integer, integer
    if jump then
      nr, nc = s:jump (r, c, dr, dc)
    else
      nr, nc = s:next_visible (r, c, dr, dc)
      if nr == r and nc == c then
        local m = s:merge_at (r, c)
        local er = m and m.r2 or r
        local ec = m and m.c2 or c
        if dr > 0 and er >= s.rows then
          nr = er + 1
        elseif dc > 0 and ec >= s.cols then
          nc = ec + 1
        end
      end
    end
    G.select_cell (nr, nc, extend)
  end

  ---Ctrl+A: the data around the active cell, then the whole sheet.
  function G.select_all ()
    local s = G.sheet ()
    if not s then
      return
    end
    local rect = G.sel_rect ()
    local region = s:region (G.sel.r, G.sel.c)
    local whole = { r1 = 1, c1 = 1, r2 = s.rows, c2 = s.cols }
    local same = region.r1 == rect.r1
      and region.c1 == rect.c1
      and region.r2 == rect.r2
      and region.c2 == rect.c2
    if not same and (region.r1 ~= region.r2 or region.c1 ~= region.c2) then
      G.select (region, G.sel.r, G.sel.c)
    else
      G.select (whole, G.sel.r, G.sel.c)
    end
  end

  ---Selects whole columns, or stretches the selection across to one. With `keep`, the
  ---active cell stays where it is, as Ctrl+Space leaves it.
  ---@param col integer
  ---@param extend? boolean
  ---@param keep? boolean
  local function select_cols (col, extend, keep)
    local s = G.sheet ()
    if not s then
      return
    end
    if extend then
      G.sel.ar, G.sel.er, G.sel.ec = 1, s.rows, col
    else
      local r = keep and G.sel.r or 1
      G.sel = { r = r, c = col, ar = 1, ac = col, er = s.rows, ec = col }
    end
    G.select_chart (nil)
    G.place ()
  end

  ---@param row integer
  ---@param extend? boolean
  ---@param keep? boolean
  local function select_rows (row, extend, keep)
    local s = G.sheet ()
    if not s then
      return
    end
    if extend then
      G.sel.ac, G.sel.ec, G.sel.er = 1, s.cols, row
    else
      local c = keep and G.sel.c or 1
      G.sel = { r = row, c = c, ar = row, ac = 1, er = row, ec = s.cols }
    end
    G.select_chart (nil)
    G.place ()
  end

  -- Opening books and showing sheets ------------------------------------------------------------

  ---True when the text being edited is a formula.
  ---@param edit Sheet.GridEdit
  ---@return boolean
  local function formula_text (edit)
    local box = edit.source == 'bar' and G.fbar or G.editor
    return string.sub (box:value () or '', 1, 1) == '='
  end

  ---Remembers where the showing sheet was, so coming back to it finds the same place.
  local function remember ()
    local s = G.sheet ()
    if s then
      local sel = G.sel
      G.saved_sel[s] = {
        sel = {
          r = sel.r,
          c = sel.c,
          ar = sel.ar,
          ac = sel.ac,
          er = sel.er,
          ec = sel.ec,
        },
        sx = G.sx,
        sy = G.sy,
      }
    end
  end

  ---Takes up the selection and scroll of the sheet that now shows.
  function G.sheet_shown ()
    local s = G.sheet ()
    if not s then
      return
    end
    local saved = G.saved_sel[s]
    if saved then
      local sel = saved.sel
      G.sel = {
        r = sel.r,
        c = sel.c,
        ar = sel.ar,
        ac = sel.ac,
        er = sel.er,
        ec = sel.ec,
      }
    else
      G.sel = { r = 1, c = 1, ar = 1, ac = 1, er = 1, ec = 1 }
    end
    G.chart_id = nil
    G.sx, G.sy = saved and saved.sx or 0, saved and saved.sy or 0
    if G.sx ~= 0 or G.sy ~= 0 then
      -- The canvas takes the sheet's size first, or the browser cuts the scroll short.
      G.draw ()
    end
    G.scroll:set ('scrollLeft', G.sx)
    G.scroll:set ('scrollTop', G.sy)
    read_scroll ()
    G.draw ()
    G.tabs_draw ()
    env.emit ('sheet')
    env.emit ('chart', nil)
  end

  ---Shows another sheet of the book. While a formula is being typed, the edit stays open, so
  ---a click on a cell there puts in a reference to the other sheet.
  ---@param index integer
  function G.show_sheet (index)
    local book = G.cur_book
    if not book or not book.sheets[index] or index == book.active then
      return
    end
    local edit = G.edit
    if edit and not formula_text (edit) then
      if not G.finish_edit (0, 0, false) then
        return
      end
      edit = nil
    end
    remember ()
    book:set_active (index)
    env.dirty ()
    G.sheet_shown ()
    if edit then
      G.edit_moved ()
    else
      G.focus ()
    end
  end

  ---Opens a book, or shows nothing with nil.
  ---@param book? Sheet.Book
  function G.set_book (book)
    if G.edit then
      G.cancel_edit ()
    end
    G.cur_book = book
    G.saved_sel = setmetatable ({}, { __mode = 'k' })
    G.clip, G.clip_rect, G.clip_sheet = nil, nil, nil
    svgs = {}
    G.chart_id = nil
    if book then
      G.sx, G.sy = 0, 0
      G.scroll:set ('scrollLeft', 0)
      G.scroll:set ('scrollTop', 0)
      G.sheet_shown ()
    else
      G.geo = nil
      G.host:html ('')
      G.tabs_draw ()
    end
  end

  -- Changes --------------------------------------------------------------------------------

  ---Keeps the selection on the sheet after rows or columns went.
  local function clamp ()
    local s = G.sheet ()
    if not s then
      return
    end
    local sel = G.sel
    sel.r, sel.c = math.min (sel.r, s.rows), math.min (sel.c, s.cols)
    sel.ar, sel.er = math.min (sel.ar, s.rows), math.min (sel.er, s.rows)
    sel.ac, sel.ec = math.min (sel.ac, s.cols), math.min (sel.ec, s.cols)
  end

  ---Draws everything again after the book changed, and saves soon.
  function G.after_change ()
    clamp ()
    G.draw ()
    G.tabs_draw ()
    env.emit ('changed')
    env.dirty ()
    G.charts_later ()
  end

  ---Runs model calls as one undo step, then draws, tells the other parts and saves soon.
  ---@param label string
  ---@param fn fun(book: Sheet.Book, sheet: Sheet.Sheet): any?
  ---@return any
  function G.change (label, fn)
    local book = G.cur_book
    local s = book and book:active_sheet ()
    if not book or not s then
      return nil
    end
    local before = book.active
    local count = #book.sheets
    remember ()
    book:begin ({ label = label, sheet = s, select = G.sel_rect () })
    local ok, result = pcall (fn, book, s)
    book:finish ()
    -- A model call that raised in the middle of its own batch leaves it open.
    while book.depth > 0 do
      book:finish ()
    end
    if not ok then
      env.say ('error', label .. ' failed: ' .. tostring (result))
    end
    if book.active ~= before or #book.sheets ~= count then
      G.sheet_shown ()
    end
    G.after_change ()
    if ok then
      return result
    end
    return nil
  end

  ---Undo, or redo when `back` is false.
  ---@param back boolean
  function G.undo (back)
    local book = G.cur_book
    if not book then
      return
    end
    if G.edit then
      G.cancel_edit ()
    end
    local before = book.active
    remember ()
    local info = nil ---@type Sheet.StepInfo?
    if back then
      info = book:undo ()
    else
      info = book:redo ()
    end
    if not info then
      return
    end
    G.drop_clip ()
    if book.active ~= before then
      G.sheet_shown ()
    end
    local s = G.sheet ()
    if info.rect and s then
      local r = info.rect --[[@as Sheet.Rect]]
      s:grow (r.r2, r.c2)
      G.sel = { r = r.r1, c = r.c1, ar = r.r1, ac = r.c1, er = r.r2, ec = r.c2 }
    end
    G.after_change ()
    if info.rect then
      G.reveal (info.rect.r1, info.rect.c1)
    end
    G.focus ()
  end

  -- Screen positions -----------------------------------------------------------------------

  ---@return Proteus.Rect
  local function scroll_rect ()
    local r = G.srect
    if not r then
      r = G.scroll:rect ()
      G.srect = r
    end
    return r
  end

  ---What a point in the window lands on in the grid.
  ---@param x number
  ---@param y number
  ---@return Sheet.GridHit?
  function G.hit_at (x, y)
    local geo = G.geo
    if not geo then
      return nil
    end
    local r = scroll_rect ()
    return calc.hit (geo, x - r.left, y - r.top, G.sx, G.sy)
  end

  ---Where a cell is on screen, in window pixels, or nil when it is out of view.
  ---@param row integer
  ---@param col integer
  ---@return Proteus.Rect?
  function G.cell_rect (row, col)
    local s, geo = G.sheet (), G.geo
    if
      not s
      or not geo
      or row < 1
      or col < 1
      or row > s.rows
      or col > s.cols
    then
      return nil
    end
    local rect = { r1 = row, c1 = col, r2 = row, c2 = col }
    local m = s:merge_at (row, col)
    if m then
      rect = { r1 = m.r1, c1 = m.c1, r2 = m.r2, c2 = m.c2 }
    end
    G.srect = nil
    read_view ()
    local sr = scroll_rect ()
    local b = calc.view_box (geo, rect, G.sx, G.sy, G.vw, G.vh)
    if not b then
      return nil
    end
    local x, y = sr.left + b.x, sr.top + b.y
    return {
      x = x,
      y = y,
      w = b.w,
      h = b.h,
      left = x,
      top = y,
      right = x + b.w,
      bottom = y + b.h,
    }
  end

  ---The grid's visible area on screen, in window pixels, without the headers and the scroll
  ---bars, or nil when no sheet shows.
  ---@return Proteus.Rect?
  function G.grid_rect ()
    if not G.sheet () then
      return nil
    end
    read_view ()
    G.srect = nil
    local sr = scroll_rect ()
    local x, y = sr.left + HEAD_W, sr.top + HEAD_H
    local w, h = math.max (0, G.vw - HEAD_W), math.max (0, G.vh - HEAD_H)
    return {
      x = x,
      y = y,
      w = w,
      h = h,
      left = x,
      top = y,
      right = x + w,
      bottom = y + h,
    }
  end

  ---Gives the keyboard back to the grid.
  function G.focus ()
    if G.edit then
      if G.edit.source == 'bar' then
        G.fbar:focus ()
      else
        G.editor:focus ()
      end
    else
      G.editor:focus ()
    end
  end

  ---True when a text box has the keys: a cell being edited, the formula bar, or any other box.
  ---@return boolean
  function G.typing ()
    local info = app.dom.focus_info ()
    if not info.editable then
      return false
    end
    return G.edit ~= nil or info.handle ~= G.editor.id
  end

  -- View options ---------------------------------------------------------------------------

  ---@param key 'gridlines'|'formulas'
  ---@param on boolean
  function G.set_view (key, on)
    if key == 'gridlines' then
      G.view_opts.gridlines = on
    else
      G.view_opts.formulas = on
    end
    app.store.set (
      'view',
      { gridlines = G.view_opts.gridlines, formulas = G.view_opts.formulas }
    )
    G.draw ()
    env.emit (
      'view',
      { gridlines = G.view_opts.gridlines, formulas = G.view_opts.formulas }
    )
  end

  -- Charts on the grid ---------------------------------------------------------------------

  ---Selects a chart, or none.
  ---@param id? string
  function G.select_chart (id)
    if G.chart_id == id then
      return
    end
    G.chart_id = id
    draw_charts ()
    G.place_boxes ()
    env.emit ('chart', id)
  end

  ---Deletes the selected chart.
  local function delete_chart ()
    local id = G.chart_id
    if not id then
      return
    end
    G.chart_id = nil
    G.change ('Delete chart', function (_, s)
      ops.delete_chart (s, id)
    end)
    env.emit ('chart', nil)
  end
  G.delete_chart = delete_chart

  ---Opens the Chart panel on a chart.
  ---@param id string
  local function open_chart (id)
    G.select_chart (id)
    local cmds = G.commands
    for _, cid in ipairs ({ 'sheet.edit_chart' }) do
      if cmds.get (cid) then
        cmds.run (cid, id)
        return
      end
    end
    env.emit ('chart', id)
  end

  -- The mouse ------------------------------------------------------------------------------

  local stop_scroller = nil ---@type fun()?

  ---@param x number
  ---@param y number
  local function drag_to (x, y)
    local d = G.drag
    local s, geo = G.sheet (), G.geo
    if not d or not s or not geo then
      return
    end
    d.x, d.y = x, y
    local sr = scroll_rect ()
    if d.kind == 'csize' or d.kind == 'rsize' then
      local col = d.kind == 'csize'
      local delta = (col and x or y) - d.start
      local lo = col and 24 or 12
      local size = math.max (lo, (d.size or 0) + delta)
      local i = d.index or 1
      local edges = col and geo.lefts or geo.tops
      local frozen = col and geo.fc or geo.fr
      local head = col and HEAD_W or HEAD_H
      local scroll = col and G.sx or G.sy
      local at = head + edges[i] + size - (i > frozen and scroll or 0)
      if col then
        G.guide:style ({
          display = 'block',
          left = at .. 'px',
          top = '0',
          width = '2px',
          height = '100%',
        })
      else
        G.guide:style ({
          display = 'block',
          top = at .. 'px',
          left = '0',
          height = '2px',
          width = '100%',
        })
      end
      return
    end
    if d.kind == 'chart' then
      local box = d.box
      if not box or not d.chart then
        return
      end
      local now = draw.drag_box (
        box,
        d.handle or 'move',
        x - (d.row or 0),
        y - (d.col or 0),
        60
      )
      d.now = now
      drag_style:set (
        '.sheet-grid-chart[data-item="chart:'
          .. calc.escape (d.chart)
          .. '"]{left:'
          .. (HEAD_W + now.x)
          .. 'px!important;top:'
          .. (HEAD_H + map_y (now.y))
          .. 'px!important;width:'
          .. now.w
          .. 'px!important;height:'
          .. now.h
          .. 'px!important}'
      )
      return
    end
    local hit = calc.hit (geo, x - sr.left, y - sr.top, G.sx, G.sy)
    local key = hit.row .. ',' .. hit.col
    if key == d.last then
      return
    end
    d.last = key
    if d.kind == 'cells' then
      G.sel.er, G.sel.ec = hit.row, hit.col
      G.place ()
    elseif d.kind == 'rows' then
      select_rows (hit.row, true)
    elseif d.kind == 'cols' then
      select_cols (hit.col, true)
    elseif d.kind == 'point' then
      G.point_at (hit.row, hit.col, true)
    elseif d.kind == 'fill' then
      d.target = calc.fill_target (G.sel_rect (), hit.row, hit.col)
      G.set_box ('target', d.target)
    elseif d.kind == 'move' then
      d.target = calc.move_target (
        G.sel_rect (),
        d.row or 1,
        d.col or 1,
        hit.row,
        hit.col,
        s.rows,
        s.cols
      )
      G.set_box ('target', d.target)
    end
  end

  ---Scrolls while a drag holds the pointer past the edge of the view.
  local function auto_scroll ()
    local d = G.drag
    local geo = G.geo
    if not d or not geo then
      return
    end
    local kinds = {
      cells = true,
      rows = true,
      cols = true,
      point = true,
      fill = true,
      move = true,
    }
    if not kinds[d.kind] then
      return
    end
    local sr = scroll_rect ()
    local x, y = d.x - sr.left, d.y - sr.top
    local dx, dy = 0, 0
    if x > G.vw - 4 then
      dx = 30
    elseif x < HEAD_W + geo.fw and G.sx > 0 and d.kind ~= 'rows' then
      dx = -30
    end
    if y > G.vh - 4 then
      dy = 24
    elseif y < HEAD_H + geo.fh and G.sy > 0 and d.kind ~= 'cols' then
      dy = -24
    end
    if dx == 0 and dy == 0 then
      if stop_scroller then
        stop_scroller ()
        stop_scroller = nil
      end
      return
    end
    if stop_scroller then
      return
    end
    stop_scroller = app.timer.every (40, function ()
      local dd = G.drag
      if not dd then
        if stop_scroller then
          stop_scroller ()
          stop_scroller = nil
        end
        return
      end
      if dx ~= 0 then
        G.scroll:set ('scrollLeft', math.max (0, G.sx + dx))
      end
      if dy ~= 0 then
        G.scroll:set ('scrollTop', math.max (0, G.sy + dy))
      end
      read_scroll ()
      if
        calc.needs_rows (geo, G.sy, G.vh, G.drawn_first, G.drawn_last, SLACK)
      then
        G.draw ()
      end
      dd.last = nil
      drag_to (dd.x, dd.y)
    end)
  end

  ---@param kind 'cells'|'rows'|'cols'|'point'|'fill'|'move'|'csize'|'rsize'|'chart'
  ---@param ev Proteus.DomEvent
  ---@return Sheet.GridDrag
  local function start_drag (kind, ev)
    local d = { kind = kind, start = 0, x = ev.x or 0, y = ev.y or 0 } ---@type Sheet.GridDrag
    G.drag = d
    if kind ~= 'fill' then
      G.area:class ('sheet-grid-busy', true)
    end
    return d
  end

  local function end_drag ()
    local d = G.drag
    G.drag = nil
    G.area:class ('sheet-grid-busy', false)
    if stop_scroller then
      stop_scroller ()
      stop_scroller = nil
    end
    return d
  end

  app.dom.on_global ('mousemove', function (ev)
    if G.drag then
      drag_to (ev.x or 0, ev.y or 0)
      auto_scroll ()
    end
    return nil
  end)

  app.dom.on_global ('mouseup', function ()
    local d = end_drag ()
    if not d then
      return nil
    end
    local s = G.sheet ()
    if not s then
      return nil
    end
    if d.kind == 'csize' or d.kind == 'rsize' then
      G.guide:style ('display', 'none')
      local col = d.kind == 'csize'
      local delta = (col and d.x or d.y) - d.start
      local size = math.max (col and 24 or 12, (d.size or 0) + delta)
      if math.abs (delta) >= 1 and d.index then
        local rect = G.sel_rect ()
        local idx = d.index --[[@as integer]]
        local lo, hi = idx, idx
        -- A size set on one of several whole rows or columns goes on all of them.
        if
          col
          and rect.r1 == 1
          and rect.r2 >= s.rows
          and d.index >= rect.c1
          and d.index <= rect.c2
        then
          lo, hi = rect.c1, rect.c2
        elseif
          not col
          and rect.c1 == 1
          and rect.c2 >= s.cols
          and d.index >= rect.r1
          and d.index <= rect.r2
        then
          lo, hi = rect.r1, rect.r2
        end
        G.change (col and 'Column width' or 'Row height', function (_, sh)
          if col then
            sh:set_widths (lo, hi, size)
          else
            sh:set_heights (lo, hi, size)
          end
        end)
      end
    elseif d.kind == 'fill' then
      G.set_box ('target', nil)
      local target = d.target
      if target then
        local src = G.sel_rect ()
        local done = G.change ('Fill', function (_, sh)
          return ops.fill (sh, src, target)
        end) --[[@as Sheet.Rect?]]
        G.select (done or target)
      end
    elseif d.kind == 'move' then
      G.set_box ('target', nil)
      local target = d.target
      local src = G.sel_rect ()
      if target and (target.r1 ~= src.r1 or target.c1 ~= src.c1) then
        G.change ('Move', function (_, sh)
          local taken = sh:copy (src)
          taken.cut = true
          sh:paste (target.r1, target.c1, taken)
        end)
        G.drop_clip ()
        G.select (target)
      end
    elseif d.kind == 'chart' then
      local now, id = d.now, d.chart
      drag_style:set ('')
      if now and id and d.box then
        local b = d.box --[[@as Sheet.GridBox]]
        local box = now --[[@as Sheet.GridBox]]
        if box.x ~= b.x or box.y ~= b.y or box.w ~= b.w or box.h ~= b.h then
          G.change ('Move chart', function (_, sh)
            ops.update_chart (sh, id, {
              x = math.floor (box.x + 0.5),
              y = math.floor (box.y + 0.5),
              w = math.floor (box.w + 0.5),
              h = math.floor (box.h + 0.5),
            })
          end)
        end
      end
    end
    G.place_boxes ()
    return nil
  end)

  ---True when a point lies in the button area at the right of a cell.
  ---@param x number
  ---@param row integer
  ---@param col integer
  ---@return boolean
  local function on_button (x, row, col)
    local rect = G.cell_rect (row, col)
    return rect ~= nil and x >= rect.right - calc.BUTTON_W and x <= rect.right
  end

  ---Opens the filter menu of a column, or the dropdown of a list cell, when a click lands on
  ---its button. Returns true when it did.
  ---@param x number
  ---@param row integer
  ---@param col integer
  ---@return boolean
  local function press_button (x, row, col)
    local s = G.sheet ()
    if not s then
      return false
    end
    local f = s.filter
    if
      f
      and row == f.rect.r1
      and col >= f.rect.c1
      and col <= f.rect.c2
      and on_button (x, row, col)
    then
      local rect = G.cell_rect (row, col) --[[@as Proteus.Rect]]
      local bx = rect.right - calc.BUTTON_W
      env.emit ('filter_menu', col, {
        x = bx,
        y = rect.top,
        w = calc.BUTTON_W,
        h = rect.h,
        left = bx,
        top = rect.top,
        right = rect.right,
        bottom = rect.bottom,
      })
      return true
    end
    if ops.dropdown (s, row, col) and on_button (x, row, col) then
      G.open_dropdown (row, col)
      return true
    end
    return false
  end

  local last_fill = 0
  -- When a double press on the fill handle last filled, so the browser's double-click that
  -- follows, now over another cell, does not start an edit there.
  local filled_at = 0

  G.scroll:on ('mouseenter', function ()
    G.srect = nil
    return nil
  end)

  G.scroll:on ('mousedown', function (ev)
    local s = G.sheet ()
    if not s or not G.geo then
      return nil
    end
    G.srect = nil
    local item = ev.item or ''
    local x, y = ev.x or 0, ev.y or 0
    G.tip:style ('display', 'none')
    -- Charts.
    local chart_id, handle = string.match (item, '^chart:(.-):(%a+)$')
    if not chart_id then
      chart_id = string.match (item, '^chart:(.+)$')
    end
    if chart_id then
      if G.edit then
        G.finish_edit (0, 0)
      end
      local spec = ops.chart_by_id (s, chart_id)
      if spec and ev.button == 0 then
        G.select_chart (chart_id)
        local d = start_drag ('chart', ev)
        d.chart = chart_id
        d.handle = handle or 'move'
        d.box = { x = spec.x, y = spec.y, w = spec.w, h = spec.h }
        d.row, d.col = math.floor (x), math.floor (y)
      elseif spec then
        G.select_chart (chart_id)
      end
      G.focus ()
      return 'prevent'
    end
    local hit = G.hit_at (x, y) --[[@as Sheet.GridHit]]
    if ev.button == 2 then
      -- A right-click outside the selection selects what is under it first.
      if G.edit then
        return nil
      end
      local rect = G.sel_rect ()
      if hit.zone == 'cell' and not inside (rect, hit.row, hit.col) then
        G.select_cell (hit.row, hit.col)
      elseif
        hit.zone == 'col'
        and not (
          hit.col >= rect.c1
          and hit.col <= rect.c2
          and rect.r1 == 1
          and rect.r2 >= s.rows
        )
      then
        select_cols (hit.col)
      elseif
        hit.zone == 'row'
        and not (
          hit.row >= rect.r1
          and hit.row <= rect.r2
          and rect.c1 == 1
          and rect.c2 >= s.cols
        )
      then
        select_rows (hit.row)
      end
      G.focus ()
      return 'prevent'
    end
    if ev.button ~= 0 then
      return nil
    end
    local csize = tonumber (string.match (item, '^csize:(%d+)$'))
    local rsize = tonumber (string.match (item, '^rsize:(%d+)$'))
    if csize or rsize then
      if G.edit then
        G.finish_edit (0, 0)
      end
      local d = start_drag (csize and 'csize' or 'rsize', ev)
      d.index = math.floor (csize or rsize --[[@as number]])
      d.start = csize and x or y
      d.size = csize and s:width (d.index) or s:height (d.index)
      drag_to (x, y)
      return 'prevent'
    end
    if item == 'fill' and not G.edit then
      -- The handle hides while it is dragged, so a double-click never reaches it. A second
      -- press soon after the first counts as one instead.
      local now = app.util.now ()
      if now - last_fill < 400 then
        last_fill = 0
        filled_at = now
        G.fill_to_end ()
        return 'prevent'
      end
      last_fill = now
      start_drag ('fill', ev)
      return 'prevent'
    end
    if item == 'move' and not G.edit then
      local d = start_drag ('move', ev)
      d.row, d.col = hit.row, hit.col
      d.last = hit.row .. ',' .. hit.col
      return 'prevent'
    end
    if G.edit then
      if
        hit.zone == 'cell'
        and G.point_at (
          hit.row,
          hit.col,
          ev.shift == true and G.edit.point ~= nil
        )
      then
        local d = start_drag ('point', ev)
        d.last = hit.row .. ',' .. hit.col
        return 'prevent'
      end
      if not G.finish_edit (0, 0) then
        return 'prevent'
      end
    end
    if hit.zone == 'corner' then
      G.select ({ r1 = 1, c1 = 1, r2 = s.rows, c2 = s.cols })
    elseif hit.zone == 'col' then
      select_cols (hit.col, ev.shift)
      local d = start_drag ('cols', ev)
      d.last = hit.row .. ',' .. hit.col
    elseif hit.zone == 'row' then
      select_rows (hit.row, ev.shift)
      local d = start_drag ('rows', ev)
      d.last = hit.row .. ',' .. hit.col
    elseif not ev.shift and press_button (x, hit.row, hit.col) then
      G.select_cell (hit.row, hit.col)
    else
      G.select_cell (hit.row, hit.col, ev.shift)
      local d = start_drag ('cells', ev)
      d.last = hit.row .. ',' .. hit.col
    end
    G.focus ()
    return 'prevent'
  end)

  G.scroll:on ('dblclick', function (ev)
    local s = G.sheet ()
    if not s then
      return nil
    end
    local item = ev.item or ''
    local chart_id = string.match (item, '^chart:([^:]+)')
    if chart_id then
      open_chart (chart_id)
      return 'prevent'
    end
    if item == 'fill' or app.util.now () - filled_at < 600 then
      return 'prevent'
    end
    local csize = tonumber (string.match (item, '^csize:(%d+)$'))
    if csize then
      local rect = G.sel_rect ()
      local cols = { math.floor (csize) } ---@type integer[]
      if
        rect.r1 == 1
        and rect.r2 >= s.rows
        and csize >= rect.c1
        and csize <= rect.c2
      then
        cols = {}
        for c = rect.c1, rect.c2 do
          cols[#cols + 1] = c
        end
      end
      G.autofit (cols)
      return 'prevent'
    end
    local rsize = tonumber (string.match (item, '^rsize:(%d+)$'))
    if rsize then
      G.autofit_row ({ math.floor (rsize) })
      return 'prevent'
    end
    local hit = G.hit_at (ev.x or 0, ev.y or 0)
    if hit and hit.zone == 'cell' and not G.edit then
      if press_button (ev.x or 0, hit.row, hit.col) then
        return 'prevent'
      end
      G.select_cell (hit.row, hit.col)
      G.begin_edit ('cell', s:edit_text (G.sel.r, G.sel.c), false)
      return 'prevent'
    end
    return nil
  end)

  -- Notes show beside their cell while the pointer rests on it.
  local tip_cell = ''
  local cancel_tip = nil ---@type fun()?
  G.scroll:on ('mousemove', function (ev)
    if G.drag then
      return nil
    end
    local s = G.sheet ()
    local hit = s and G.hit_at (ev.x or 0, ev.y or 0)
    local key = ''
    local note = nil ---@type string?
    if
      s
      and hit
      and hit.zone == 'cell'
      and hit.past_x == 0
      and hit.past_y == 0
    then
      local m = s:merge_at (hit.row, hit.col)
      local r, c = hit.row, hit.col
      if m then
        r, c = m.r1, m.c1
      end
      note = s:note (r, c)
      if note then
        key = r .. ',' .. c
      end
    end
    if key == tip_cell then
      return nil
    end
    tip_cell = key
    if cancel_tip then
      cancel_tip ()
      cancel_tip = nil
    end
    G.tip:style ('display', 'none')
    if note and hit then
      local text = note
      local row, col = hit.row, hit.col
      cancel_tip = app.timer.after (250, function ()
        cancel_tip = nil
        local rect = G.cell_rect (row, col)
        if not rect or G.drag or G.edit then
          return
        end
        G.tip:text (text)
        G.tip:style ({
          display = 'block',
          left = (rect.right + 6) .. 'px',
          top = rect.top .. 'px',
        })
      end)
    end
    return nil
  end)

  G.scroll:on ('mouseleave', function ()
    tip_cell = ''
    if cancel_tip then
      cancel_tip ()
      cancel_tip = nil
    end
    G.tip:style ('display', 'none')
    return nil
  end)

  -- Keys -----------------------------------------------------------------------------------

  ---Keys on the grid while no cell is being edited. Shortcuts that belong to commands reach
  ---core.keys first.
  ---@param ev Proteus.DomEvent
  ---@return Proteus.EventResult
  function G.grid_key (ev)
    local s = G.sheet ()
    if not s or ev.composing then
      return nil
    end
    local key = ev.key or ''
    local mod = ev.ctrl == true or ev.meta == true
    if G.chart_id then
      if key == 'Delete' or key == 'Backspace' then
        delete_chart ()
        return 'prevent'
      end
      if key == 'Escape' then
        G.select_chart (nil)
        return 'prevent'
      end
      if not mod and #key == 1 then
        G.select_chart (nil)
      end
    end
    local dir = ARROWS[key]
    if dir then
      if
        key == 'ArrowDown'
        and ev.alt
        and ops.dropdown (s, G.sel.r, G.sel.c)
      then
        G.open_dropdown (G.sel.r, G.sel.c)
        return 'prevent'
      end
      G.move (dir[1], dir[2], ev.shift == true, mod)
      return 'prevent'
    end
    if key == 'Enter' then
      if mod then
        return 'prevent'
      end
      local text = s:edit_text (G.sel.r, G.sel.c)
      if
        not ev.shift
        and text ~= ''
        and G.sel_rect ().r1 == G.sel_rect ().r2
      then
        G.begin_edit ('cell', text, false)
      else
        G.move (ev.shift and -1 or 1, 0)
      end
      return 'prevent'
    end
    if key == 'Tab' then
      G.move (0, ev.shift and -1 or 1)
      return 'prevent'
    end
    if key == 'Home' then
      if mod then
        -- A1 may sit in a frozen pane, where it shows at any scroll, so scroll back too.
        G.scroll:set ('scrollLeft', 0)
        G.scroll:set ('scrollTop', 0)
        read_scroll ()
        G.select_cell (1, 1, ev.shift)
        G.draw ()
      else
        G.select_cell (G.sel.r, 1, ev.shift)
      end
      return 'prevent'
    end
    if key == 'End' and mod then
      local rows, cols = s:used ()
      G.select_cell (math.max (1, rows), math.max (1, cols), ev.shift)
      return 'prevent'
    end
    if (key == 'PageDown' or key == 'PageUp') and not mod then
      local geo = G.geo
      local page = 20
      if geo then
        local first, last = calc.seen_rows (geo, G.sy, G.vh)
        page = math.max (1, last - first - 1)
      end
      local sign = key == 'PageDown' and 1 or -1
      local target = math.max (
        1,
        math.min (s.rows, (ev.shift and G.sel.er or G.sel.r) + sign * page)
      )
      if not ev.shift then
        G.scroll:set (
          'scrollTop',
          math.max (0, G.sy + sign * (G.vh - HEAD_H - (geo and geo.fh or 0)))
        )
        read_scroll ()
      end
      G.select_cell (target, ev.shift and G.sel.ec or G.sel.c, ev.shift)
      return 'prevent'
    end
    if key == 'F2' then
      G.begin_edit ('cell', s:edit_text (G.sel.r, G.sel.c), false)
      return 'prevent'
    end
    if key == 'Delete' or key == 'Backspace' then
      G.clear ()
      return 'prevent'
    end
    if key == 'Escape' then
      G.drop_clip ()
      return 'prevent'
    end
    if key == ' ' and (ev.shift or mod) and not ev.alt then
      if mod then
        select_cols (G.sel.c, false, true)
      else
        select_rows (G.sel.r, false, true)
      end
      return 'prevent'
    end
    if mod and string.lower (key) == 'v' and ev.shift then
      G.paste_mode = { only = 'values' }
    end
    -- Anything else types into the waiting editor box. Ctrl+V pastes into it.
    return nil
  end

  -- The other parts ------------------------------------------------------------------------

  local act_mod = require ('sheet_grid_act') --[[@as Sheet.GridActModule]]
  local edit_mod = require ('sheet_grid_edit') --[[@as Sheet.GridEditModule]]
  local tabs_mod = require ('sheet_grid_tabs') --[[@as Sheet.GridTabsModule]]
  act_mod.install (G)
  edit_mod.install (G)
  tabs_mod.install (G)
  ui.mount (G.measurer)
  ui.mount (G.tip)
  G.stats_later ()
  return G
end

return M
