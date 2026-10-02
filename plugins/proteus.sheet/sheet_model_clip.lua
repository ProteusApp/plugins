-- sheet_model_clip: filling, copying and pasting cells in a sheet of the Sheet app, and the
-- text forms of a block of cells: CSV, and the tab-separated text other spreadsheets put on
-- the clipboard. sheet_model calls it with its kit, and it adds its methods to every sheet and
-- its functions to the module.

local format = require ('sheet_format') --[[@as Sheet.FormatModule]]
local formula = require ('sheet_formula') --[[@as Sheet.FormulaModule]]

---@param K Sheet.ModelKit
return function (K)
  ---@class Sheet.Sheet
  local Sheet = K.Sheet
  ---@class Sheet.ModelModule
  local M = K.M
  local KEY, tidy, with_bold = K.KEY, K.tidy, K.with_bold
  local cell_patch, full_patch = K.cell_patch, K.full_patch

  -------------------------------------------------------------------------------------------
  -- Fill, copy and paste
  -------------------------------------------------------------------------------------------

  ---Copies the top row of a block into the rows below it, moving references as a paste does,
  ---with the styles. A block of one row copies the row above it instead. Returns false when
  ---there is no row to copy from.
  ---@param rect Sheet.Rect
  ---@return boolean
  function Sheet:fill_down (rect)
    local r = tidy (rect)
    local src, first = r.r1, r.r1 + 1
    if r.r1 == r.r2 then
      if r.r1 == 1 then
        return false
      end
      src, first = r.r1 - 1, r.r1
    end
    self:begin ({ select = r, label = 'Fill down' })
    for col = r.c1, r.c2 do
      local text = self:text (src, col)
      local full = full_patch (self:style_at (src, col))
      for row = first, r.r2 do
        self:record (row, col, {
          text = formula.shift (text, row - src, 0),
          style = cell_patch (nil, full, self:inherited (row, col)),
        })
      end
    end
    self:finish ()
    return true
  end

  ---Copies the left column of a block into the columns right of it. A block of one column
  ---copies the column to its left instead.
  ---@param rect Sheet.Rect
  ---@return boolean
  function Sheet:fill_right (rect)
    local r = tidy (rect)
    local src, first = r.c1, r.c1 + 1
    if r.c1 == r.c2 then
      if r.c1 == 1 then
        return false
      end
      src, first = r.c1 - 1, r.c1
    end
    self:begin ({ select = r, label = 'Fill right' })
    for row = r.r1, r.r2 do
      local text = self:text (row, src)
      local full = full_patch (self:style_at (row, src))
      for col = first, r.c2 do
        self:record (row, col, {
          text = formula.shift (text, 0, col - src),
          style = cell_patch (nil, full, self:inherited (row, col)),
        })
      end
    end
    self:finish ()
    return true
  end

  ---A value as text that types back to the same value.
  ---@param v Sheet.Value
  ---@return string
  local function literal_text (v)
    if v == nil then
      return ''
    end
    local t = type (v)
    if t == 'number' then
      return M.number_text (v --[[@as number]])
    elseif t == 'boolean' then
      return v and 'TRUE' or 'FALSE'
    elseif t == 'table' then
      return (v --[[@as Sheet.Error]]).code
    end
    local s = v --[[@as string]]
    if s == '' then
      return ''
    end
    local first = string.sub (s, 1, 1)
    if first == '=' or first == "'" then
      return "'" .. s
    end
    local back = format.parse_input (s)
    if back ~= s then
      return "'" .. s
    end
    return s
  end

  ---Takes a block of cells for a copy. The clip keeps each cell's text, full style and value,
  ---the merges and notes inside the block, and the shown values as tab-separated text for the
  ---system clipboard.
  ---@param rect Sheet.Rect
  ---@return Sheet.Clip
  function Sheet:copy (rect)
    local r = tidy (rect)
    self.book:ensure ()
    local texts, bold, styles, literals, shown = {}, {}, {}, {}, {} ---@type string[][], boolean[][], Sheet.Style[][], string[][], string[][]
    for row = r.r1, r.r2 do
      local t, b, st, l, s = {}, {}, {}, {}, {} ---@type string[], boolean[], Sheet.Style[], string[], string[]
      for col = r.c1, r.c2 do
        local cell = self.cells[row * KEY + col]
        local style = self:style_at (row, col)
        local text = cell and cell.text or ''
        local value = cell and cell.value
        if text == '' then
          -- A cell a block spills into copies as its value, unless the formula comes along.
          local spilled, anchor = self:spilled (row, col)
          if
            anchor
            and not (
              anchor.row >= r.r1
              and anchor.row <= r.r2
              and anchor.col >= r.c1
              and anchor.col <= r.c2
            )
          then
            value = spilled
            text = literal_text (spilled)
          end
        end
        t[#t + 1] = text
        b[#b + 1] = style.bold == true
        st[#st + 1] = style
        l[#l + 1] = literal_text (value)
        s[#s + 1] = self:display (row, col)
      end
      texts[#texts + 1], bold[#bold + 1], styles[#styles + 1] = t, b, st
      literals[#literals + 1], shown[#shown + 1] = l, s
    end
    local merges = {} ---@type Sheet.Rect[]
    for _, m in ipairs (self.merges) do
      if M.contains (r, m) then
        merges[#merges + 1] = {
          r1 = m.r1 - r.r1 + 1,
          c1 = m.c1 - r.c1 + 1,
          r2 = m.r2 - r.r1 + 1,
          c2 = m.c2 - r.c1 + 1,
        }
      end
    end
    ---@param map table<integer, string>
    ---@return table<integer, string>
    local function in_clip (map)
      local out = {} ---@type table<integer, string>
      for key, text in pairs (map) do
        local row = math.floor (key / KEY)
        local col = key - row * KEY
        if row >= r.r1 and row <= r.r2 and col >= r.c1 and col <= r.c2 then
          out[(row - r.r1 + 1) * KEY + (col - r.c1 + 1)] = text
        end
      end
      return out
    end
    local notes = in_clip (self.notes)
    local links = in_clip (self.links)
    return {
      texts = texts,
      bold = bold,
      styles = styles,
      literals = literals,
      merges = merges,
      notes = notes,
      links = links,
      row = r.r1,
      col = r.c1,
      sheet = self,
      tsv = M.to_csv (shown, '\t', '\n'),
    }
  end

  ---A block moved by a number of rows and columns.
  ---@param rect Sheet.Rect
  ---@param drow integer
  ---@param dcol integer
  ---@return Sheet.Rect
  local function shifted (rect, drow, dcol)
    return {
      r1 = rect.r1 + drow,
      c1 = rect.c1 + dcol,
      r2 = rect.r2 + drow,
      c2 = rect.c2 + dcol,
    }
  end

  ---A copy of a rule, a validation or a chart with some fields changed.
  ---@param item table
  ---@param fields table<string, any>
  ---@return table
  local function with_fields (item, fields)
    local copy = {} ---@type table<string, any>
    for k, v in
      pairs (item --[[@as table<string, any>]])
    do
      copy[k] = v
    end
    for k, v in pairs (fields) do
      copy[k] = v
    end
    return copy
  end

  ---Follows a block of cells that a cut and paste or a drag moved from `source` to `target` on
  ---this sheet, as part of the open step. Every formula in the book that points into the block
  ---points where it went, and a reference to the cells it landed on turns into #REF!. The rules,
  ---validation, charts and filter that lie wholly inside the block move with it. A chart stays
  ---when the block moves to another sheet, since its range names no sheet. The cells in
  ---`target` are left alone: the paste wrote them already.
  ---@param source Sheet.Sheet
  ---@param src Sheet.Rect
  ---@param target Sheet.Rect
  function Sheet:follow_move (source, src, target)
    local drow, dcol = target.r1 - src.r1, target.c1 - src.c1
    local from, to = source.name, self.name
    ---@param text string
    ---@param own string
    ---@param lands? string
    ---@return string
    local function move (text, own, lands)
      return formula.move (
        text,
        src,
        drow,
        dcol,
        { from = from, to = to, own = own, lands = lands }
      )
    end
    self.book:rewrite_names (function (text)
      return move (text, '')
    end)
    for _, sheet in ipairs (self.book.sheets) do
      local list = {} ---@type Sheet.Cell[]
      for _, cell in pairs (sheet.cells) do
        if
          cell.formula
          and not (
            sheet == self
            and M.contains (
              target,
              { r1 = cell.row, c1 = cell.col, r2 = cell.row, c2 = cell.col }
            )
          )
        then
          list[#list + 1] = cell
        end
      end
      for _, cell in ipairs (list) do
        local text = move (cell.text, sheet.name)
        if text ~= cell.text then
          sheet:record (cell.row, cell.col, { text = text, style = cell.style })
        end
      end
    end

    -- Rules and validation that lie inside the block go with it, to another sheet too.
    local arrived = { rules = {}, validation = {} } ---@type table<string, table[]>
    for _, sheet in ipairs (self.book.sheets) do
      for _, field in ipairs ({ 'rules', 'validation', 'charts' }) do
        local items = (sheet --[[@as table<string, table[]>]])[field]
        local out = {} ---@type table[]
        local changed = false
        for _, item in ipairs (items) do
          local rect = sheet == source and M.parse_range (item.range)
          local goes = rect and M.contains (src, rect)
          if goes and field == 'charts' and source ~= self then
            goes = false
          end
          local fields = {} ---@type table<string, any>
          if type (item.formula) == 'string' then
            local text = move (item.formula, sheet.name, goes and to or nil)
            if text ~= item.formula then
              fields.formula = text
            end
          end
          if goes then
            fields.range =
              M.range_name (shifted (rect --[[@as Sheet.Rect]], drow, dcol))
          end
          local next_item = next (fields) and with_fields (item, fields) or item
          if goes and source ~= self then
            local list = arrived[field]
            list[#list + 1] = next_item
            changed = true
          else
            out[#out + 1] = next_item
            changed = changed or next_item ~= item
          end
        end
        if changed then
          sheet:set_prop (field, nil, out)
        end
      end
    end
    for field, list in pairs (arrived) do
      if #list > 0 then
        local out = {} ---@type table[]
        for _, item in
          ipairs ((self --[[@as table<string, table[]>]])[field])
        do
          out[#out + 1] = item
        end
        for _, item in ipairs (list) do
          out[#out + 1] = item
        end
        self:set_prop (field, nil, out)
      end
    end

    -- The filter goes with the block when the block holds it all, and the rows it hides follow.
    local f = source.filter
    if
      f
      and M.contains (src, f.rect)
      and (source == self or not self.filter)
    then
      local columns = {} ---@type table<integer, Sheet.FilterColumn>
      for col, test in pairs (f.columns) do
        columns[col + dcol] = test
      end
      ---@type Sheet.LiveFilter
      local moved =
        { rect = shifted (f.rect, drow, dcol), columns = columns, hidden = {} }
      moved.hidden = self:hidden_by (moved)
      if source ~= self then
        source:set_prop ('filter', nil, nil)
      end
      self:set_prop ('filter', nil, moved)
    end
  end

  ---Pastes a clip with its top left cell at `row` and `col`, as one undo step, and returns the
  ---block that changed. Formulas from a copy move their relative references by the distance
  ---moved. A cut moves the cells as they are and empties where they came from. When `fill` is a
  ---block whose size is a whole number of clips, the clip repeats to fill it, so a one-cell clip
  ---fills any block. `opts` pastes only values, formulas or formats, and can turn rows into
  ---columns.
  ---@param row integer
  ---@param col integer
  ---@param clip Sheet.Clip
  ---@param fill? Sheet.Rect
  ---@param opts? Sheet.PasteOptions
  ---@return Sheet.Rect?
  function Sheet:paste (row, col, clip, fill, opts)
    local o = opts or {}
    local only, turn = o.only, o.transpose == true
    local texts = clip.texts
    local h, w = #texts, 0
    for _, line in ipairs (texts) do
      if #line > w then
        w = #line
      end
    end
    if h == 0 or w == 0 then
      return nil
    end
    local th, tw = h, w
    if turn then
      th, tw = w, h
    end
    local target = { r1 = row, c1 = col, r2 = row + th - 1, c2 = col + tw - 1 }
    if fill then
      local f = tidy (fill)
      local fh, fw = f.r2 - f.r1 + 1, f.c2 - f.c1 + 1
      if fh % th == 0 and fw % tw == 0 and (fh > th or fw > tw) then
        target = f
      end
    end
    local with_text = only ~= 'formats'
    local with_style = only == nil or only == 'formats'
    local from_row, from_col = clip.row, clip.col
    local source = clip.sheet or self
    -- A cut moves cells within one book. From another book it pastes as a copy.
    local cut = clip.cut == true and source.book == self.book
    self:begin ({ select = target, label = 'Paste' })
    local src = nil ---@type Sheet.Rect?
    if cut and from_row and from_col and only == nil then
      src = {
        r1 = from_row,
        c1 = from_col,
        r2 = from_row + h - 1,
        c2 = from_col + w - 1,
      }
      for i = 1, h do
        for j = 1, w do
          source:record (from_row + i - 1, from_col + j - 1, { text = '' })
        end
      end
      source:unmerge (src)
      for _, field in ipairs ({ 'notes', 'links' }) do
        for key in
          pairs (
            (clip --[[@as table<string, table<integer, string>?>]])[field] or {}
          )
        do
          local i = math.floor (key / KEY)
          local j = key - i * KEY
          source:set_prop (
            field,
            (from_row + i - 1) * KEY + (from_col + j - 1),
            nil
          )
        end
      end
    end
    if with_style and clip.merges then
      self:unmerge (target)
    end
    for r = target.r1, target.r2 do
      for c = target.c1, target.c2 do
        local oi = (r - target.r1) % th
        local oj = (c - target.c1) % tw
        local i, j = oi + 1, oj + 1
        if turn then
          i, j = oj + 1, oi + 1
        end
        local cell = self.cells[r * KEY + c]
        ---@type Sheet.CellState
        local state =
          { text = cell and cell.text or '', style = cell and cell.style }
        if with_text then
          local text = texts[i][j] or ''
          if only == 'values' and clip.literals then
            text = clip.literals[i] and clip.literals[i][j] or ''
          elseif from_row and from_col and not cut then
            text = formula.shift (
              text,
              r - (from_row + i - 1),
              c - (from_col + j - 1)
            )
          elseif src and not turn then
            -- A moved formula keeps pointing where it did, unless it points into the block.
            text =
              formula.move (text, src, target.r1 - src.r1, target.c1 - src.c1, {
                from = source.name,
                to = self.name,
                own = source.name,
                lands = self.name,
              })
          end
          if clip.typed and only == nil then
            state = self:typed (r, c, text)
          else
            state.text = text
          end
        end
        if with_style then
          local full = clip.styles and clip.styles[i] and clip.styles[i][j]
          local patch = clip.patches and clip.patches[i] and clip.patches[i][j]
          if patch then
            state.style = cell_patch (state.style, patch, self:inherited (r, c))
          elseif full then
            state.style =
              cell_patch (nil, full_patch (full), self:inherited (r, c))
          elseif clip.bold and clip.bold[i] and clip.bold[i][j] ~= nil then
            state.style = with_bold (state.style, clip.bold[i][j])
          end
        end
        self:record (r, c, state)
      end
    end
    if with_style and clip.merges and #clip.merges > 0 then
      local list = {} ---@type Sheet.Rect[]
      for _, m in ipairs (self.merges) do
        list[#list + 1] = m
      end
      for tr = target.r1, target.r2, th do
        for tc = target.c1, target.c2, tw do
          for _, m in ipairs (clip.merges) do
            local a, b, c, d = m.r1, m.c1, m.r2, m.c2
            if turn then
              a, b, c, d = m.c1, m.r1, m.c2, m.r2
            end
            list[#list + 1] = {
              r1 = tr + a - 1,
              c1 = tc + b - 1,
              r2 = tr + c - 1,
              c2 = tc + d - 1,
            }
          end
        end
      end
      self:set_prop ('merges', nil, list)
    end
    for _, field in ipairs ({ 'notes', 'links' }) do
      local map = (clip --[[@as table<string, table<integer, string>?>]])[field]
      if only == nil and map then
        for key, text in pairs (map) do
          local i = math.floor (key / KEY)
          local j = key - i * KEY
          local oi, oj = i - 1, j - 1
          if turn then
            oi, oj = j - 1, i - 1
          end
          self:set_prop (field, (target.r1 + oi) * KEY + (target.c1 + oj), text)
        end
      end
    end
    if src and not turn then
      self:follow_move (source, src, target)
    end
    self:finish ()
    return target
  end

  ---Pastes plain text from the clipboard: tab-separated, comma-separated, or one cell per line.
  ---Each cell reads as if typed.
  ---@param row integer
  ---@param col integer
  ---@param text string
  ---@param fill? Sheet.Rect
  ---@param opts? Sheet.PasteOptions
  ---@return Sheet.Rect?
  function Sheet:paste_text (row, col, text, fill, opts)
    return self:paste (
      row,
      col,
      { texts = M.parse_clipboard (text), typed = true },
      fill,
      opts
    )
  end

  -------------------------------------------------------------------------------------------
  -- Ranges, CSV and the clipboard
  -------------------------------------------------------------------------------------------

  ---Splits CSV text into rows of fields. Quoted fields may hold the separator, doubled quotes
  ---and line breaks. Lines may end with \r\n or \n.
  ---@param text string
  ---@param sep? string A comma when nil, or a tab for tab-separated text.
  ---@return string[][]
  function M.parse_csv (text, sep)
    sep = sep or ','
    local rows = {} ---@type string[][]
    if text == '' then
      return rows
    end
    local stop = '[' .. (sep == '\t' and '\t' or '%' .. sep) .. '\r\n]'
    local n = #text
    local row = {} ---@type string[]
    local pos = 1
    while true do
      local field ---@type string
      if string.sub (text, pos, pos) == '"' then
        local parts = {} ---@type string[]
        local p = pos + 1
        while true do
          local q = string.find (text, '"', p, true)
          if not q then
            parts[#parts + 1] = string.sub (text, p)
            pos = n + 1
            break
          end
          parts[#parts + 1] = string.sub (text, p, q - 1)
          if string.sub (text, q + 1, q + 1) == '"' then
            parts[#parts + 1] = '"'
            p = q + 2
          else
            pos = q + 1
            break
          end
        end
        field = table.concat (parts)
        -- Text after the closing quote joins the field, as spreadsheets read it.
        local e = string.find (text, stop, pos) or (n + 1)
        field = field .. string.sub (text, pos, e - 1)
        pos = e
      else
        local e = string.find (text, stop, pos) or (n + 1)
        field = string.sub (text, pos, e - 1)
        pos = e
      end
      row[#row + 1] = field
      local ch = string.sub (text, pos, pos)
      if ch == sep then
        pos = pos + 1
      elseif ch == '\r' or ch == '\n' then
        rows[#rows + 1] = row
        row = {}
        pos = pos
          + (
            (ch == '\r' and string.sub (text, pos + 1, pos + 1) == '\n') and 2
            or 1
          )
        if pos > n then
          break
        end
      else
        rows[#rows + 1] = row
        break
      end
    end
    return rows
  end

  ---Joins rows of fields into CSV text. Fields holding the separator, a quote or a line break
  ---go in quotes, with quotes doubled.
  ---@param rows string[][]
  ---@param sep? string
  ---@param eol? string
  ---@return string
  function M.to_csv (rows, sep, eol)
    sep = sep or ','
    eol = eol or '\r\n'
    local lines = {} ---@type string[]
    for _, row in ipairs (rows) do
      local fields = {} ---@type string[]
      for i, field in ipairs (row) do
        if
          string.find (field, sep, 1, true)
          or string.find (field, '["\r\n]')
        then
          field = '"' .. string.gsub (field, '"', '""') .. '"'
        end
        fields[i] = field
      end
      lines[#lines + 1] = table.concat (fields, sep)
    end
    return table.concat (lines, eol)
  end

  ---Reads pasted text into rows of cells. Text with tabs is tab-separated. Text with commas is
  ---comma-separated when every line splits into the same number of fields. A single line only
  ---splits when no field starts with a space, so a sentence stays in one cell. Anything else
  ---puts one line in each cell.
  ---@param text string
  ---@return string[][]
  function M.parse_clipboard (text)
    local s = string.gsub (text, '\r?\n$', '')
    if s == '' then
      return { { '' } }
    end
    if string.find (s, '\t', 1, true) then
      return M.parse_csv (s, '\t')
    end
    if string.find (s, ',', 1, true) then
      local rows = M.parse_csv (s, ',')
      local width = #rows[1]
      local even = width > 1
      for _, row in ipairs (rows) do
        if #row ~= width then
          even = false
        end
      end
      if even and #rows == 1 then
        for _, field in ipairs (rows[1]) do
          if string.sub (field, 1, 1) == ' ' then
            even = false
          end
        end
      end
      if even then
        return rows
      end
    end
    local rows = {} ---@type string[][]
    for line in string.gmatch (s .. '\n', '([^\n]*)\n') do
      rows[#rows + 1] = { (string.gsub (line, '\r$', '')) }
    end
    return rows
  end

  ---True when clipboard text is what a clip put there, so a paste can use the clip's formulas.
  ---@param clip Sheet.Clip
  ---@param text string
  ---@return boolean
  function M.same_clip (clip, text)
    ---@param s string
    ---@return string
    local function plain (s)
      local out = string.gsub (s, '\r\n', '\n')
      out = string.gsub (out, '\n+$', '')
      return out
    end
    return clip.tsv ~= nil and plain (clip.tsv) == plain (text)
  end

  ---Makes a sheet, alone in a new book, from rows of cell text such as a parsed CSV file. Each
  ---cell reads as if typed.
  ---@param rows string[][]
  ---@param opts? Sheet.Options
  ---@return Sheet.Sheet
  function M.from_grid (rows, opts)
    local sheet = M.new (opts)
    for r, line in ipairs (rows) do
      for c, text in ipairs (line) do
        if text ~= '' then
          sheet:put (r, c, sheet:typed (r, c, text))
        end
      end
    end
    return sheet
  end
end
