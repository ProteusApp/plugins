-- sheet_grid_draw: builds the Sheet app's grid as one HTML table, and the CSS that places it.
-- It takes no `app` and calls no host function, so the tests reach it.
--
-- Each distinct look a cell can have becomes a short CSS class, written once into a list of
-- rules the grid keeps in one style element. Cells carry only the class, so a sheet of
-- thousands of cells stays a small string.
--
-- Frozen rows and columns stay put with `position: sticky`. Their cells stack above the cells
-- that scroll, and the boxes the grid lays over the cells sit in layers between them, so a box
-- that scrolls slides under the frozen cells as the cells beside it do. From the bottom up:
-- scrolling cells, their boxes (1), their charts (2), frozen columns (3), frozen rows (4),
-- text spilling from them (5), their boxes (6) and charts (7), the frozen corner (8), its text
-- (9), boxes (10) and charts (11), then the headers (12 and 13).

local calc = require ('sheet_grid_calc') --[[@as Sheet.GridCalcModule]]
local model = require ('sheet_model') --[[@as Sheet.ModelModule]]
local ops = require ('sheet_ops') --[[@as Sheet.OpsModule]]

---The CSS classes of cell looks, and their rules.
---@class Sheet.GridStyles
---@field ids table<Sheet.Style, integer>
---@field next_id integer
---@field by_key table<string, string>
---@field count integer How many classes there are.
---@field rules string[]
---@field stamp integer Goes up by one when a rule is added.

---What to draw.
---@class Sheet.GridDrawOptions
---@field first integer The first scrolling row to draw.
---@field last integer The last row to draw.
---@field formulas? boolean Show formulas instead of their values.
---@field styles Sheet.GridStyles

---A merged block as drawn: the part of it inside one pane.
---@class Sheet.GridPiece
---@field rowspan integer
---@field colspan integer
---@field merge Sheet.Rect
---@field text boolean True for the piece that shows the block's text.
---@field height number
---@field width number

---What pass one finds out about a cell.
---@class Sheet.GridCellInfo
---@field style Sheet.Style
---@field look? Sheet.Look
---@field note? boolean

---@class Sheet.GridDrawModule
local M = {}

local KEY = model.KEY
local HEAD_W, HEAD_H = calc.HEAD_W, calc.HEAD_H
-- How many empty cells to the right long text may spill into.
local SPILL = 12
-- The padding and the line at the bottom of each cell, which the text cannot use.
local CELL_PAD = 5
local DEFAULT_H = model.DEFAULT_HEIGHT

---@return Sheet.GridStyles
function M.new_styles ()
  return {
    ids = setmetatable ({}, { __mode = 'k' }),
    next_id = 0,
    by_key = {},
    count = 0,
    rules = {},
    stamp = 0,
  }
end

---The CSS class for a cell look, made the first time the look appears.
---@param styles Sheet.GridStyles
---@param look Sheet.GridCellLook
---@return string
function M.class_for (styles, look)
  local st = look.style
  local id = styles.ids[st] or 0
  if id == 0 then
    styles.next_id = styles.next_id + 1
    id = styles.next_id
    styles.ids[st] = id
  end
  ---@type string
  local key = tostring (id)
    .. '|'
    .. (look.color or '')
    .. '|'
    .. (look.fill or '')
    .. '|'
    .. look.align
    .. '|'
    .. (look.error and 'e' or '')
    .. '|'
    .. (look.bottom or '')
    .. '|'
    .. (look.right or '')
    .. '|'
    .. (look.top or '')
    .. '|'
    .. (look.left or '')
  local cls = styles.by_key[key]
  if cls then
    return cls
  end
  styles.count = styles.count + 1
  cls = 'sheet-grid-s' .. styles.count
  styles.by_key[key] = cls
  local cell, inner = calc.cell_css (look)
  if cell ~= '' then
    styles.rules[#styles.rules + 1] = '.sheet-grid-t td.'
      .. cls
      .. '{'
      .. cell
      .. '}'
  end
  if inner ~= '' then
    styles.rules[#styles.rules + 1] = '.sheet-grid-t td.'
      .. cls
      .. '>div{'
      .. inner
      .. '}'
  end
  styles.stamp = styles.stamp + 1
  return cls
end

---Every rule made so far, as one CSS text.
---@param styles Sheet.GridStyles
---@return string
function M.styles_css (styles)
  return table.concat (styles.rules, '\n')
end

---The CSS that depends on the layout: the canvas size, where each frozen row and column
---sticks, and the clipping of the box layers over the frozen panes.
---@param geo Sheet.GridGeo
---@return string
function M.frame_css (geo)
  local out = {} ---@type string[]
  local w = HEAD_W + geo.lefts[geo.cols + 1]
  local h = HEAD_H + geo.tops[geo.rows + 1]
  out[#out + 1] = '.sheet-grid-canvas{width:' .. w .. 'px;height:' .. h .. 'px}'
  for r = 1, geo.fr do
    out[#out + 1] = '.sheet-grid-t tr.sheet-grid-fr'
      .. r
      .. '>*{top:'
      .. (HEAD_H + geo.tops[r])
      .. 'px}'
  end
  for c = 1, geo.fc do
    out[#out + 1] = '.sheet-grid-t .sheet-grid-fc'
      .. c
      .. '{left:'
      .. (HEAD_W + geo.lefts[c])
      .. 'px}'
  end
  local fy = HEAD_H + geo.fh
  local fx = HEAD_W + geo.fw
  local far = 10000000
  out[#out + 1] = '.sheet-grid-pn-tr{clip-path:polygon(0 0,'
    .. far
    .. 'px 0,'
    .. far
    .. 'px '
    .. fy
    .. 'px,0 '
    .. fy
    .. 'px)}'
  out[#out + 1] = '.sheet-grid-pn-bl{clip-path:polygon(0 0,'
    .. fx
    .. 'px 0,'
    .. fx
    .. 'px '
    .. far
    .. 'px,0 '
    .. far
    .. 'px)}'
  out[#out + 1] = '.sheet-grid-pn-tl{clip-path:polygon(0 0,'
    .. fx
    .. 'px 0,'
    .. fx
    .. 'px '
    .. fy
    .. 'px,0 '
    .. fy
    .. 'px)}'
  return table.concat (out, '\n')
end

---The rows and columns of a range text in rules and validation, read once per text.
---@type table<string, Sheet.Rect|false>
local range_cache = {}

---@param text any
---@return Sheet.Rect?
local function range_of (text)
  if type (text) ~= 'string' then
    return nil
  end
  local hit = range_cache[text]
  if hit == nil then
    hit = model.parse_range (text) or false
    range_cache[text] = hit
  end
  return hit or nil
end

---The blocks on a sheet whose cells need a full look even when empty: conditional formatting,
---validation, and the filter's header row.
---@param sheet Sheet.Sheet
---@return Sheet.Rect[]
local function look_areas (sheet)
  local out = {} ---@type Sheet.Rect[]
  for _, rule in ipairs (sheet.rules) do
    local r = range_of (rule.range)
    if r then
      out[#out + 1] = r
    end
  end
  for _, v in ipairs (sheet.validation) do
    local r = range_of (v.range)
    if r then
      out[#out + 1] = r
    end
  end
  return out
end

---The visible rows or columns from `a` to `b`: those whose span has a size.
---@param edges number[]
---@param a integer
---@param b integer
---@return integer[]
local function visible (edges, a, b)
  local out = {} ---@type integer[]
  for i = a, b do
    if edges[i + 1] > edges[i] then
      out[#out + 1] = i
    end
  end
  return out
end

---The drawn pieces of every merged block. `pieces` maps the key of each piece's first cell to
---the piece, and `skip` holds the keys of the other drawn cells the pieces cover.
---@param sheet Sheet.Sheet
---@param geo Sheet.GridGeo
---@param row_segs integer[][] Lists of drawn rows, one per pane.
---@param col_segs integer[][]
---@return table<integer, Sheet.GridPiece> pieces
---@return table<integer, boolean> skip
function M.merge_pieces (sheet, geo, row_segs, col_segs)
  local pieces = {} ---@type table<integer, Sheet.GridPiece>
  local skip = {} ---@type table<integer, boolean>
  for _, m in ipairs (sheet.merges) do
    local shown = false
    for _, rows in ipairs (row_segs) do
      local rs = {} ---@type integer[]
      for _, r in ipairs (rows) do
        if r >= m.r1 and r <= m.r2 then
          rs[#rs + 1] = r
        end
      end
      for _, cols in ipairs (col_segs) do
        local cs = {} ---@type integer[]
        for _, c in ipairs (cols) do
          if c >= m.c1 and c <= m.c2 then
            cs[#cs + 1] = c
          end
        end
        if #rs > 0 and #cs > 0 then
          local r1, c1 = rs[1], cs[1]
          local r2, c2 = rs[#rs], cs[#cs]
          pieces[r1 * KEY + c1] = {
            rowspan = #rs,
            colspan = #cs,
            merge = m,
            text = not shown,
            height = geo.tops[r2 + 1] - geo.tops[r1],
            width = geo.lefts[c2 + 1] - geo.lefts[c1],
          }
          shown = true
          for _, r in ipairs (rs) do
            for _, c in ipairs (cs) do
              if r ~= r1 or c ~= c1 then
                skip[r * KEY + c] = true
              end
            end
          end
        end
      end
    end
  end
  return pieces, skip
end

---True when a block in the list holds a cell.
---@param list Sheet.Rect[]
---@param r integer
---@param c integer
---@return boolean
local function in_any (list, r, c)
  for _, rect in ipairs (list) do
    if r >= rect.r1 and r <= rect.r2 and c >= rect.c1 and c <= rect.c2 then
      return true
    end
  end
  return false
end

---The rows or columns before which each drawn one sits: the next visible one in the same
---list, or nil at the end.
---@param list integer[]
---@return table<integer, integer>
local function next_of (list)
  local out = {} ---@type table<integer, integer>
  for i = 1, #list - 1 do
    out[list[i]] = list[i + 1]
  end
  return out
end

---The line along one side of a cell, from its own style or the neighbour's facing side.
---@param own? Sheet.Style
---@param own_side string
---@param other? Sheet.Style
---@param other_side string
---@return string?
local function edge (own, own_side, other, other_side)
  local t = own --[[@as table<string, any>?]]
  if t and t[own_side] then
    return calc.border_css (t[own_side], t.border_color)
  end
  local o = other --[[@as table<string, any>?]]
  if o and o[other_side] then
    return calc.border_css (o[other_side], o.border_color)
  end
  return nil
end

---Draws the table: the column letters, the frozen rows, the scrolling rows from
---`opts.first` to `opts.last`, and padding rows that keep the rest of the sheet's height.
---@param sheet Sheet.Sheet
---@param geo Sheet.GridGeo
---@param opts Sheet.GridDrawOptions
---@return string
function M.table_html (sheet, geo, opts)
  local styles = opts.styles
  local tops, lefts = geo.tops, geo.lefts
  local vcols = visible (lefts, 1, geo.cols)
  local frozen_cols, scroll_cols = {}, {} ---@type integer[], integer[]
  for _, c in ipairs (vcols) do
    if c <= geo.fc then
      frozen_cols[#frozen_cols + 1] = c
    else
      scroll_cols[#scroll_cols + 1] = c
    end
  end
  local frozen_rows = visible (tops, 1, geo.fr)
  local first = math.max (opts.first, geo.fr + 1)
  local last = math.min (opts.last, geo.rows)
  local scroll_rows = visible (tops, first, last)
  local pieces, skip = M.merge_pieces (
    sheet,
    geo,
    { frozen_rows, scroll_rows },
    { frozen_cols, scroll_cols }
  )
  local next_col = next_of (vcols)
  local last_frozen = frozen_cols[#frozen_cols] or -1
  -- A frozen column's text spills only into frozen columns, since the rest slide under it.
  local seg_end = {} ---@type table<integer, integer>
  for _, c in ipairs (frozen_cols) do
    seg_end[c] = frozen_cols[#frozen_cols]
  end
  for _, c in ipairs (scroll_cols) do
    seg_end[c] = geo.cols
  end
  sheet.book:ensure ()
  local cells = sheet.cells
  local spills = sheet.watch.spills
  local row_styles, col_styles = sheet.row_styles, sheet.col_styles
  local notes = sheet.notes
  local areas = look_areas (sheet)
  local filter = sheet.filter
  local filter_row = filter and filter.rect.r1 or nil

  ---Pass one: what each drawn cell of a row holds.
  ---@param r integer
  ---@return table<integer, Sheet.GridCellInfo|false>
  local function row_infos (r)
    local out = {} ---@type table<integer, Sheet.GridCellInfo|false>
    local rs = row_styles[r]
    local row_areas = {} ---@type Sheet.Rect[]
    for _, a in ipairs (areas) do
      if r >= a.r1 and r <= a.r2 then
        row_areas[#row_areas + 1] = a
      end
    end
    for _, c in ipairs (vcols) do
      local k = r * KEY + c
      local info = false ---@type Sheet.GridCellInfo|false
      if not skip[k] then
        local piece = pieces[k]
        local cell = cells[k]
        local wide = (#row_areas > 0 and in_any (row_areas, r, c))
          or (
            filter_row == r
            and filter
            and c >= filter.rect.c1
            and c <= filter.rect.c2
          )
        if piece then
          local m = piece.merge
          local look = ops.look (sheet, m.r1, m.c1)
          if not piece.text then
            look.text = ''
          end
          info = { style = look.style, look = look }
        elseif cell or wide or spills[k] then
          local look = ops.look (sheet, r, c)
          info = { style = look.style, look = look }
        elseif rs or col_styles[c] or notes[k] then
          info = { style = sheet:style_at (r, c), note = notes[k] ~= nil }
        end
      end
      out[c] = info
    end
    return out
  end

  local html = {} ---@type string[]
  local width = HEAD_W + lefts[geo.cols + 1]
  html[#html + 1] = '<table class="sheet-grid-t" style="width:'
    .. width
    .. 'px"><colgroup><col style="width:'
    .. HEAD_W
    .. 'px">'
  for _, c in ipairs (vcols) do
    html[#html + 1] = '<col style="width:'
      .. (lefts[c + 1] - lefts[c])
      .. 'px">'
  end
  html[#html + 1] =
    '</colgroup><thead><tr><th class="sheet-grid-corner" data-item="all"></th>'
  for i, c in ipairs (vcols) do
    local cls = c <= geo.fc
        and (' class="sheet-grid-fc sheet-grid-fc' .. c .. (c == last_frozen and ' sheet-grid-fcl' or '') .. '"')
      or ''
    local prev = vcols[i - 1] or 0
    if c - prev > 1 then
      -- Columns hidden just before this one show as a double line.
      cls = cls == '' and ' class="sheet-grid-hid"'
        or (string.sub (cls, 1, -2) .. ' sheet-grid-hid"')
    end
    html[#html + 1] = '<th'
      .. cls
      .. ' data-item="col:'
      .. c
      .. '">'
      .. model.col_name (c)
      .. '<i class="sheet-grid-cs" data-item="csize:'
      .. c
      .. '"></i></th>'
  end
  html[#html + 1] = '</tr></thead><tbody>'

  local ncols = #vcols + 1

  ---@param h number
  local function pad (h)
    if h > 0 then
      html[#html + 1] = '<tr class="sheet-grid-pad" style="height:'
        .. h
        .. 'px"><td colspan="'
        .. ncols
        .. '"></td></tr>'
    end
  end

  ---Draws the rows of one pane, in order. `open_top` is true when no drawn row lies above the
  ---first one, so that row draws the line along its own top.
  ---@param rows integer[]
  ---@param frozen boolean
  ---@param open_top boolean
  local function draw_rows (rows, frozen, open_top)
    local infos = {} ---@type table<integer, table<integer, Sheet.GridCellInfo|false>>
    for i, r in ipairs (rows) do
      infos[i] = row_infos (r)
    end
    for i, r in ipairs (rows) do
      local h = tops[r + 1] - tops[r]
      local tr = '<tr'
      if frozen then
        tr = tr
          .. ' class="sheet-grid-fr sheet-grid-fr'
          .. r
          .. (i == #rows and ' sheet-grid-frl' or '')
          .. '"'
      end
      if h ~= DEFAULT_H then
        tr = tr
          .. ' style="height:'
          .. h
          .. 'px;--h:'
          .. math.max (0, h - CELL_PAD)
          .. 'px"'
      end
      html[#html + 1] = tr
        .. '><th data-item="row:'
        .. r
        .. '">'
        .. r
        .. '<i class="sheet-grid-rs" data-item="rsize:'
        .. r
        .. '"></i></th>'
      local here = infos[i]
      local below = infos[i + 1] ---@type table<integer, Sheet.GridCellInfo|false>?
      local below_row = rows[i + 1]
      if below_row and below_row ~= r + 1 then
        -- Hidden rows lie between, which draw nothing, so the next drawn row is the neighbour.
        local seen = tops[below_row] == tops[r + 1]
        if not seen then
          below = nil
        end
      end
      local model_below = nil ---@type integer?
      if not below then
        local nr = r + 1
        while nr <= geo.rows and tops[nr + 1] == tops[nr] do
          nr = nr + 1
        end
        if nr <= geo.rows then
          model_below = nr
        end
      end
      for _, c in ipairs (vcols) do
        local k = r * KEY + c
        if not skip[k] then
          local info = here[c]
          local piece = pieces[k]
          local nc = next_col[c]
          local right_info = nc and here[nc] or nil
          local below_style = nil ---@type Sheet.Style?
          if below then
            local b = below[c]
            below_style = b and b.style or nil
          elseif model_below then
            below_style = sheet:style_at (model_below, c)
          end
          local own = info and info.style or nil
          local bottom = edge (own, 'border_bottom', below_style, 'border_top')
          local right = edge (
            own,
            'border_right',
            right_info and right_info.style or nil,
            'border_left'
          )
          local top, left = nil, nil ---@type string?, string?
          if own and own.border_top and open_top and i == 1 then
            top = calc.border_css (own.border_top, own.border_color)
          end
          if own and own.border_left and c == vcols[1] then
            left = calc.border_css (own.border_left, own.border_color)
          end
          local classes = {} ---@type string[]
          if c <= geo.fc then
            classes[#classes + 1] = 'sheet-grid-fc sheet-grid-fc' .. c
            if c == last_frozen then
              classes[#classes + 1] = 'sheet-grid-fcl'
            end
          end
          local attrs = ''
          if piece then
            if piece.rowspan > 1 then
              attrs = attrs .. ' rowspan="' .. piece.rowspan .. '"'
            end
            if piece.colspan > 1 then
              attrs = attrs .. ' colspan="' .. piece.colspan .. '"'
            end
          end
          if not info and not bottom and not right then
            if #classes > 0 then
              html[#html + 1] = '<td class="'
                .. table.concat (classes, ' ')
                .. '"'
                .. attrs
                .. '></td>'
            else
              html[#html + 1] = '<td' .. attrs .. '></td>'
            end
          else
            local look = info and info.look or nil
            local style = own or model.EMPTY
            local text = look and look.text or ''
            local align = look and look.align or 'left'
            local kind = look and look.kind or 'empty'
            if opts.formulas and look then
              local cell = cells[k]
              if cell and cell.formula then
                text = cell.text
                align = 'left'
              end
            end
            local fill = look and look.fill or style.fill
            local scale = fill and fill ~= style.fill
            ---@type Sheet.GridCellLook
            local cl = {
              style = style,
              color = look and look.color or style.color,
              fill = not scale and fill or nil,
              align = align,
              error = kind == 'error' or nil,
              bottom = bottom,
              right = right,
              top = top,
              left = left,
            }
            classes[#classes + 1] = M.class_for (styles, cl)
            local inline = {} ---@type string[]
            local images = {} ---@type string[]
            if scale and fill then
              inline[#inline + 1] = 'background-color:' .. fill
              if not cl.color then
                local on = calc.text_on (fill)
                if on then
                  inline[#inline + 1] = 'color:' .. on
                end
              end
            end
            local note = (look and look.note) or (info and info.note)
            if look and look.bar and look.bar > 0 then
              local pct = string.format ('%.1f', math.min (1, look.bar) * 100)
              images[#images + 1] = 'linear-gradient(90deg,color-mix(in srgb,'
                .. (look.bar_color or 'var(--accent)')
                .. ' 55%,transparent) 0 '
                .. pct
                .. '%,transparent '
                .. pct
                .. '%)'
            end
            if note then
              classes[#classes + 1] = 'sheet-grid-nt'
            end
            if look and look.list then
              classes[#classes + 1] = 'sheet-grid-dd'
            end
            if
              filter
              and filter_row == r
              and c >= filter.rect.c1
              and c <= filter.rect.c2
            then
              classes[#classes + 1] = filter.columns[c]
                  and 'sheet-grid-fb sheet-grid-fon'
                or 'sheet-grid-fb'
            end
            if #images > 0 then
              if note then
                images[#images + 1] =
                  'linear-gradient(225deg,var(--warning) 50%,transparent 50%)'
                inline[#inline + 1] =
                  'background-size:8px 8px,100% 100%;background-position:right top,0 0;background-repeat:no-repeat'
                images = { images[2], images[1] }
              end
              inline[#inline + 1] = 'background-image:'
                .. table.concat (images, ',')
            end
            local inner = ''
            if piece then
              inline[#inline + 1] = '--h:'
                .. math.max (0, piece.height - CELL_PAD)
                .. 'px'
            elseif
              text ~= ''
              and kind == 'text'
              and align == 'left'
              and not style.wrap
            then
              -- Text spills into the empty cells to its right, as in spreadsheets.
              local room = 0
              local nxt = next_col[c]
              local stop = seg_end[c] or geo.cols
              local count = 0
              while nxt and nxt <= stop and count < SPILL do
                local nk = r * KEY + nxt
                local other = cells[nk]
                if
                  (other and other.text ~= '')
                  or spills[nk]
                  or skip[nk]
                  or pieces[nk]
                then
                  break
                end
                room = room + (lefts[nxt + 1] - lefts[nxt])
                nxt = next_col[nxt]
                count = count + 1
              end
              if room > 0 then
                classes[#classes + 1] = 'sheet-grid-o'
                inner = ' style="width:'
                  .. (lefts[c + 1] - lefts[c] + room - 9)
                  .. 'px"'
              end
            end
            local body = ''
            local icon = look and look.icon
            if icon then
              -- An icon set's icon sits at the left of the cell, before the text.
              icon = '<span class="sheet-grid-ic" style="color:'
                .. (look and look.icon_color or 'inherit')
                .. '">'
                .. calc.escape (icon)
                .. '</span>'
            end
            if text ~= '' or icon then
              body = '<div'
                .. inner
                .. '>'
                .. (icon or '')
                .. calc.escape (text)
                .. '</div>'
            end
            html[#html + 1] = '<td class="'
              .. table.concat (classes, ' ')
              .. '"'
              .. attrs
              .. (#inline > 0 and (' style="' .. table.concat (inline, ';') .. '"') or '')
              .. '>'
              .. body
              .. '</td>'
          end
        end
      end
      html[#html + 1] = '</tr>'
    end
  end

  draw_rows (frozen_rows, true, true)
  local gap = tops[first] - tops[geo.fr + 1]
  pad (gap)
  draw_rows (scroll_rows, false, #frozen_rows == 0 or gap > 0)
  pad (tops[geo.rows + 1] - tops[last + 1])
  html[#html + 1] = '</tbody></table>'
  return table.concat (html)
end

---Rows of the default height that need more room for a big font or for line breaks, as the
---row and the height they need. Rows given a height of their own keep it, and wrapped text is
---left out. A spreadsheet grows such rows by itself, so the file does not change.
---@param sheet Sheet.Sheet
---@return table<integer, number>
function M.auto_heights (sheet)
  local out = {} ---@type table<integer, number>
  local heights = sheet.heights
  local row_styles, col_styles = sheet.row_styles, sheet.col_styles
  for _, cell in pairs (sheet.cells) do
    local r = cell.row
    if cell.text ~= '' and not heights[r] then
      local own = cell.style
      local size = own and own.size
      local wrap = own and own.wrap
      if not size then
        local rs = row_styles[r]
        size = rs and rs.size
      end
      if not size then
        local cs = col_styles[cell.col]
        size = cs and cs.size
      end
      local lines = 1
      if string.find (cell.text, '\n', 1, true) then
        local _, breaks = string.gsub (cell.text, '\n', '')
        lines = breaks + 1
      end
      if (lines > 1 or (size and size > 15)) and not wrap then
        local need = math.ceil ((size or 13) * 1.25 * lines + CELL_PAD)
        if need > DEFAULT_H and need > (out[r] or 0) then
          out[r] = need
        end
      end
    end
  end
  return out
end

---Row tops with some rows grown, from the model's tops. Hidden rows stay hidden.
---@param tops number[]
---@param grown table<integer, number>
---@return number[]
function M.grow_tops (tops, grown)
  if next (grown) == nil then
    return tops
  end
  local out = { 0 } ---@type number[]
  for r = 1, #tops - 1 do
    local h = tops[r + 1] - tops[r]
    local want = grown[r]
    if h > 0 and want and want > h then
      h = want
    end
    out[r + 1] = out[r] + h
  end
  return out
end

---The pane a point of the sheet belongs to: `tl`, `tr`, `bl` or `br`, by whether it lies in
---the frozen rows and the frozen columns.
---@param geo Sheet.GridGeo
---@param x number
---@param y number
---@return 'tl'|'tr'|'bl'|'br'
function M.pane_at (geo, x, y)
  local top = geo.fr > 0 and y < geo.fh
  local left = geo.fc > 0 and x < geo.fw
  if top and left then
    return 'tl'
  elseif top then
    return 'tr'
  elseif left then
    return 'bl'
  end
  return 'br'
end

-- The eight handles of a selected chart.
M.HANDLES = { 'nw', 'n', 'ne', 'e', 'se', 's', 'sw', 'w' }

---The charts of a sheet as HTML, one string per pane. `svg (spec)` gives a chart's picture.
---@param sheet Sheet.Sheet
---@param geo Sheet.GridGeo
---@param svg fun(spec: Sheet.ChartSpec): string
---@param selected? string The id of the selected chart.
---@param map_y? fun(y: number): number Turns a chart's top in the model's rows into the grid's, when rows grew.
---@return table<string, string>
function M.charts_html (sheet, geo, svg, selected, map_y)
  local parts = { tl = {}, tr = {}, bl = {}, br = {} } ---@type table<string, string[]>
  for _, spec in ipairs (sheet.charts) do
    local y = map_y and map_y (spec.y) or spec.y
    local pane = M.pane_at (geo, spec.x, y)
    local id = calc.escape (spec.id)
    local on = spec.id == selected
    local out = parts[pane]
    out[#out + 1] = '<div class="sheet-grid-chart'
      .. (on and ' sheet-grid-on' or '')
      .. '" data-item="chart:'
      .. id
      .. '" style="left:'
      .. (HEAD_W + spec.x)
      .. 'px;top:'
      .. (HEAD_H + y)
      .. 'px;width:'
      .. spec.w
      .. 'px;height:'
      .. spec.h
      .. 'px">'
      .. svg (spec)
    if on then
      for _, h in ipairs (M.HANDLES) do
        out[#out + 1] = '<i class="sheet-grid-hdl sheet-grid-hdl-'
          .. h
          .. '" data-item="chart:'
          .. id
          .. ':'
          .. h
          .. '"></i>'
      end
    end
    out[#out + 1] = '</div>'
  end
  local result = {} ---@type table<string, string>
  for pane, list in pairs (parts) do
    result[pane] = table.concat (list)
  end
  return result
end

---A chart's box after a handle is dragged by `dx`, `dy`, kept at least `min` pixels across.
---@param box Sheet.GridBox
---@param handle string One of `HANDLES`, or `move`.
---@param dx number
---@param dy number
---@param min number
---@return Sheet.GridBox
function M.drag_box (box, handle, dx, dy, min)
  local x1, y1 = box.x, box.y
  local x2, y2 = box.x + box.w, box.y + box.h
  if handle == 'move' then
    return {
      x = math.max (0, x1 + dx),
      y = math.max (0, y1 + dy),
      w = box.w,
      h = box.h,
    }
  end
  if string.find (handle, 'w', 1, true) then
    x1 = math.min (x1 + dx, x2 - min)
  end
  if string.find (handle, 'e', 1, true) then
    x2 = math.max (x2 + dx, x1 + min)
  end
  if string.find (handle, 'n', 1, true) then
    y1 = math.min (y1 + dy, y2 - min)
  end
  if string.find (handle, 's', 1, true) then
    y2 = math.max (y2 + dy, y1 + min)
  end
  x1, y1 = math.max (0, x1), math.max (0, y1)
  return { x = x1, y = y1, w = x2 - x1, h = y2 - y1 }
end

return M
