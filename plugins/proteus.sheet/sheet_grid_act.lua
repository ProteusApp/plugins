-- sheet_grid_act: the actions on the Sheet app grid's selection. Copy, cut and paste, clearing
-- and filling, inserting, deleting and hiding rows and columns, freezing panes, sizes, and the
-- measuring behind auto-fit. sheet_grid.lua installs it into the grid, and the commands in
-- init.lua call these functions.

local calc = require ('sheet_grid_calc') --[[@as Sheet.GridCalcModule]]
local model = require ('sheet_model') --[[@as Sheet.ModelModule]]
local ops = require ('sheet_ops') --[[@as Sheet.OpsModule]]

---@class Sheet.GridActModule
local M = {}

---@param grid Sheet.GridView
function M.install (grid)
  local G = grid
  local app, env = G.app, G.env

  -- The clipboard --------------------------------------------------------------------------

  function G.drop_clip ()
    if G.clip then
      G.clip, G.clip_rect, G.clip_sheet = nil, nil, nil
      G.place_boxes ()
    end
  end

  ---@param cut boolean
  function G.copy (cut)
    local s = G.sheet ()
    if not s then
      return
    end
    local rect = G.sel_rect ()
    local taken = s:copy (rect)
    taken.cut = cut or nil
    G.clip, G.clip_rect, G.clip_sheet = taken, rect, s
    app.system.clipboard (taken.tsv or '')
    G.place_boxes ()
  end

  ---Pastes text from the clipboard at the selection. When the text is what the last copy put
  ---there, the copied cells paste instead, with their formulas and styles.
  ---@param text string
  ---@param opts? Sheet.PasteOptions
  function G.paste_text (text, opts)
    local rect = G.sel_rect ()
    local taken = G.clip
    local area = G.change ('Paste', function (_, s)
      if taken and (text == nil or model.same_clip (taken, text)) then
        return s:paste (rect.r1, rect.c1, taken, rect, opts)
      end
      return s:paste_text (rect.r1, rect.c1, text, rect, opts)
    end) --[[@as Sheet.Rect?]]
    if taken and taken.cut then
      G.drop_clip ()
    end
    if area then
      G.select (area)
    end
  end

  ---Pastes from the system clipboard, for the menus. Ctrl+V pastes through the waiting editor
  ---instead, which needs no permission.
  ---@param opts? Sheet.PasteOptions
  function G.paste (opts)
    app.system.clipboard_read (function (text, err)
      local ok, problem = pcall (function ()
        if text then
          G.paste_text (text, opts)
        elseif G.clip then
          G.paste_text (G.clip.tsv or '', opts)
        else
          env.say (
            'warn',
            'The clipboard could not be read'
              .. (err and (': ' .. err) or '.')
              .. ' Ctrl+V pastes too.'
          )
        end
        G.focus ()
      end)
      if not ok then
        env.say ('error', 'Paste failed: ' .. tostring (problem))
      end
    end)
  end

  function G.clear ()
    local rect = G.sel_rect ()
    G.change ('Clear', function (_, s)
      s:clear (rect)
    end)
  end

  ---Fill down or fill right, from the top row or the left column of the selection.
  ---@param down boolean
  function G.fill (down)
    local rect = G.sel_rect ()
    G.change (down and 'Fill down' or 'Fill right', function (_, s)
      if down then
        return s:fill_down (rect)
      end
      return s:fill_right (rect)
    end)
  end

  -- Rows and columns -----------------------------------------------------------------------

  ---A menu label with the number of rows or columns selected, such as `Insert 3 rows above`.
  ---@param what string
  ---@param axis 'row'|'col'
  ---@return string
  function G.count_label (what, axis)
    local rect = G.sel_rect ()
    local n = axis == 'row' and (rect.r2 - rect.r1 + 1)
      or (rect.c2 - rect.c1 + 1)
    local noun = axis == 'row' and 'row' or 'column'
    if n == 1 then
      return string.format (what, noun)
    end
    return string.format (what, n .. ' ' .. noun .. 's')
  end

  ---Inserts as many rows or columns as are selected, before the selection or after it.
  ---@param axis 'row'|'col'
  ---@param after boolean
  function G.insert (axis, after)
    local rect = G.sel_rect ()
    local count = axis == 'row' and (rect.r2 - rect.r1 + 1)
      or (rect.c2 - rect.c1 + 1)
    local at = axis == 'row' and (after and rect.r2 + 1 or rect.r1)
      or (after and rect.c2 + 1 or rect.c1)
    G.drop_clip ()
    G.change (
      axis == 'row' and 'Insert rows' or 'Insert columns',
      function (_, s)
        if axis == 'row' then
          s:insert_rows (at, count)
        else
          s:insert_cols (at, count)
        end
      end
    )
    local s = G.sheet ()
    if not s then
      return
    end
    if axis == 'row' then
      G.select ({ r1 = at, c1 = rect.c1, r2 = at + count - 1, c2 = rect.c2 })
    else
      G.select ({ r1 = rect.r1, c1 = at, r2 = rect.r2, c2 = at + count - 1 })
    end
  end

  ---Deletes the selected rows or columns.
  ---@param axis 'row'|'col'
  function G.delete (axis)
    local rect = G.sel_rect ()
    G.drop_clip ()
    G.change (
      axis == 'row' and 'Delete rows' or 'Delete columns',
      function (_, s)
        if axis == 'row' then
          s:delete_rows (rect.r1, rect.r2 - rect.r1 + 1)
        else
          s:delete_cols (rect.c1, rect.c2 - rect.c1 + 1)
        end
      end
    )
    local s = G.sheet ()
    if s then
      G.select_cell (math.min (G.sel.r, s.rows), math.min (G.sel.c, s.cols))
    end
  end

  ---Hides the selected rows or columns, or shows them and the hidden ones beside them.
  ---@param axis 'row'|'col'
  ---@param on boolean
  function G.hide (axis, on)
    local s = G.sheet ()
    if not s then
      return
    end
    local rect = G.sel_rect ()
    local lo, hi = rect.r1, rect.r2
    local count, hidden =
      s.rows, function (i)
        return s:row_hidden (i) and not s:filtered (i)
      end
    if axis == 'col' then
      lo, hi, count = rect.c1, rect.c2, s.cols
      hidden = function (i)
        return s:col_hidden (i)
      end
    end
    if not on then
      lo, hi = calc.unhide_span (lo, hi, count, hidden)
    elseif lo == 1 and hi >= count then
      env.say ('warn', 'Some rows or columns must stay in view.')
      return
    end
    local noun = axis == 'row' and 'rows' or 'columns'
    G.change ((on and 'Hide ' or 'Unhide ') .. noun, function (_, sh)
      sh:set_hidden (axis, lo, hi, on)
    end)
    if on then
      if axis == 'row' then
        G.select_cell (math.min (hi + 1, s.rows), G.sel.c)
      else
        G.select_cell (G.sel.r, math.min (hi + 1, s.cols))
      end
    end
  end

  ---Freezes rows and columns. A nil count keeps what is frozen now.
  ---@param rows? integer
  ---@param cols? integer
  function G.freeze (rows, cols)
    local s = G.sheet ()
    if not s then
      return
    end
    local fr, fc = s:freeze ()
    G.change ('Freeze', function (_, sh)
      sh:set_freeze (rows or fr, cols or fc)
    end)
  end

  ---Asks for a row height or a column width, and sets it on every selected row or column.
  ---@param axis 'row'|'col'
  function G.ask_size (axis)
    local s = G.sheet ()
    local picker = G.picker
    if not s or not picker then
      return
    end
    local rect = G.sel_rect ()
    local now = axis == 'row' and s:height (rect.r1) or s:width (rect.c1)
    local lo, hi = 12, 600
    if axis == 'col' then
      lo, hi = 24, 1200
    end
    picker.input ({
      prompt = axis == 'row' and 'Row height in pixels'
        or 'Column width in pixels',
      value = tostring (math.floor (now + 0.5)),
      validate = function (text)
        local n = tonumber (text)
        if not n or n < lo or n > hi then
          return 'Type a number from ' .. lo .. ' to ' .. hi .. '.'
        end
        return nil
      end,
      on_submit = function (text)
        local n = tonumber (text) --[[@as number]]
        G.change (
          axis == 'row' and 'Row height' or 'Column width',
          function (_, sh)
            if axis == 'row' then
              sh:set_heights (rect.r1, rect.r2, n)
            else
              sh:set_widths (rect.c1, rect.c2, n)
            end
          end
        )
        G.focus ()
      end,
      on_cancel = function ()
        G.focus ()
      end,
    })
  end

  -- Links ----------------------------------------------------------------------------------

  ---Follows the link on a cell. A place in the book, such as `#Sheet2!A1`, shows that sheet
  ---and selects the cells. A web or mail address is copied, since the app opens no pages.
  ---@param row integer
  ---@param col integer
  function G.follow_link (row, col)
    local s, book = G.sheet (), G.cur_book
    local link = s and s:link (row, col)
    if not s or not book or not link then
      return
    end
    if string.sub (link, 1, 1) ~= '#' then
      app.system.clipboard (link)
      env.say (
        'info',
        'Copied ' .. link .. '. Paste it in a browser to open it.'
      )
      return
    end
    local rect, sheet_name = model.parse_ref (string.sub (link, 2))
    if not rect then
      env.say ('warn', 'The link points at ' .. link .. ', which is not a cell.')
      return
    end
    if sheet_name then
      local target = book:find (sheet_name)
      if not target then
        env.say ('warn', 'There is no sheet named "' .. sheet_name .. '".')
        return
      end
      local index = book:index_of (target)
      if index and index ~= book.active then
        G.show_sheet (index)
      end
    end
    G.select (rect)
  end

  -- Measuring ------------------------------------------------------------------------------

  ---The inline CSS for a style's font.
  ---@param style? Sheet.Style
  ---@return string
  local function font_css (style)
    if not style then
      return ''
    end
    local out = {} ---@type string[]
    if style.bold then
      out[#out + 1] = 'font-weight:700'
    end
    if style.italic then
      out[#out + 1] = 'font-style:italic'
    end
    if style.size then
      out[#out + 1] = 'font-size:' .. style.size .. 'px'
    end
    return table.concat (out, ';')
  end

  ---The width of a text in pixels, in a style's font.
  ---@param text string
  ---@param style? Sheet.Style
  ---@return number
  function G.measure (text, style)
    G.measurer:html (
      '<div style="'
        .. font_css (style)
        .. '">'
        .. calc.escape (text)
        .. '</div>'
    )
    return (tonumber (G.measurer:get ('offsetWidth')) or 8) - 8
  end

  -- Wrapped texts already measured, by width, font and text.
  local wrap_cache = {} ---@type table<string, number>
  local wrap_count = 0

  ---The height a text needs when it wraps in a column, measured once for each width, font
  ---and text. Rows grow by this as wrapped text is typed.
  ---@param text string
  ---@param style Sheet.Style
  ---@param width number
  ---@return number
  function G.measure_wrap (text, style, width)
    local css = font_css (style)
    local key = width .. '\0' .. css .. '\0' .. text
    local hit = wrap_cache[key]
    if hit then
      return hit
    end
    G.measurer:html (
      '<div style="width:'
        .. math.max (1, width - 9)
        .. 'px;white-space:pre-wrap;overflow-wrap:anywhere;'
        .. css
        .. '">'
        .. calc.escape (text)
        .. '</div>'
    )
    local h = tonumber (G.measurer:get ('offsetHeight')) or 0
    if wrap_count >= 2000 then
      wrap_cache, wrap_count = {}, 0
    end
    wrap_cache[key] = h
    wrap_count = wrap_count + 1
    return h
  end

  ---The widest of several texts, each in its own font, measured with one element.
  ---@param items Sheet.FitCell[]
  ---@return number
  local function widest (items)
    local seen = {} ---@type table<string, boolean>
    local parts = {} ---@type string[]
    for _, item in ipairs (items) do
      local css = font_css (item.style)
      local key = css .. '\0' .. item.text
      if not seen[key] then
        seen[key] = true
        parts[#parts + 1] = '<div style="'
          .. css
          .. '">'
          .. calc.escape (item.text)
          .. '</div>'
      end
    end
    if #parts == 0 then
      return 0
    end
    G.measurer:html (table.concat (parts))
    return tonumber (G.measurer:get ('offsetWidth')) or 0
  end

  ---Sets the given columns, or the selected ones, as wide as their widest text.
  ---@param cols? integer[]
  function G.autofit (cols)
    local s = G.sheet ()
    if not s then
      return
    end
    if not cols then
      local rect = G.sel_rect ()
      cols = {}
      for c = rect.c1, rect.c2 do
        if not s:col_hidden (c) then
          cols[#cols + 1] = c
        end
      end
    end
    local list = cols
    G.change ('Auto-fit', function (_, sh)
      for _, c in ipairs (list) do
        local w = widest (ops.column_cells (sh, c))
        local f = sh.filter
        if f and c >= f.rect.c1 and c <= f.rect.c2 then
          w = w + calc.BUTTON_W
        end
        if w > 0 then
          sh:set_width (c, math.max (24, math.min (1200, math.ceil (w + 6))))
        else
          sh:set_width (c, model.DEFAULT_WIDTH)
        end
      end
    end)
  end

  ---Sets rows as tall as their tallest cell: wrapped text at its column's width, or a big font.
  ---@param rows integer[]
  function G.autofit_row (rows)
    local s = G.sheet ()
    if not s then
      return
    end
    G.change ('Auto-fit', function (_, sh)
      for _, r in ipairs (rows) do
        local parts = {} ---@type string[]
        for c = 1, sh.cols do
          local text = sh:text (r, c)
          if text ~= '' and not sh:col_hidden (c) then
            local st = sh:style_at (r, c)
            local wrap = st.wrap
                and ('width:' .. (sh:width (c) - 9) .. 'px;white-space:pre-wrap;overflow-wrap:anywhere;')
              or ''
            parts[#parts + 1] = '<div style="'
              .. wrap
              .. font_css (st)
              .. '">'
              .. calc.escape ((sh:display (r, c)))
              .. '</div>'
          end
        end
        local h = model.DEFAULT_HEIGHT
        if #parts > 0 then
          G.measurer:html (
            '<div style="display:flex;align-items:flex-start">'
              .. table.concat (parts)
              .. '</div>'
          )
          h = math.max (
            h,
            math.ceil ((tonumber (G.measurer:get ('offsetHeight')) or 0) + 1)
          )
        end
        sh:set_height (r, math.min (600, h))
      end
    end)
  end

  ---Double-clicking the fill handle fills down as far as the column beside goes.
  function G.fill_to_end ()
    local s = G.sheet ()
    if not s then
      return
    end
    local src = G.sel_rect ()
    local last = calc.fill_down_to (src, s.rows, s.cols, function (r, c)
      return s:text (r, c) ~= ''
    end)
    if not last or last <= src.r2 then
      return
    end
    local target = { r1 = src.r1, c1 = src.c1, r2 = last, c2 = src.c2 }
    local done = G.change ('Fill', function (_, sh)
      return ops.fill (sh, src, target)
    end) --[[@as Sheet.Rect?]]
    G.select (done or target)
  end
end

return M
