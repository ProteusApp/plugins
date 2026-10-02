-- sheet_model_data: a sheet of the Sheet app as plain data and back. It copies a sheet, loads
-- one from the decoded data of a `.sheet.json` file, checking every field, and writes one as
-- data, with the filter, sorting and the hidden rows it keeps. sheet_model calls it with its
-- kit, and it adds its methods to every sheet.

local formula = require ('sheet_formula') --[[@as Sheet.FormulaModule]]

---@param K Sheet.ModelKit
return function (K)
  ---@class Sheet.Sheet
  local Sheet = K.Sheet
  ---@class Sheet.ModelModule
  local M = K.M
  local KEY, intern, make_cell = K.KEY, K.intern, K.make_cell
  local MIN_WIDTH, MAX_WIDTH = K.MIN_WIDTH, K.MAX_WIDTH
  local MIN_HEIGHT, MAX_HEIGHT = K.MIN_HEIGHT, K.MAX_HEIGHT

  -------------------------------------------------------------------------------------------
  -- The sheet as data
  -------------------------------------------------------------------------------------------

  ---A copy of this sheet under another name, in the same book, with every cell, style and
  ---setting. The book adds it to its list.
  ---@param name string
  ---@return Sheet.Sheet
  function Sheet:clone (name)
    local copy = M.blank (self.book, name, self.rows, self.cols)
    local clock = self.book.clock
    for key, cell in pairs (self.cells) do
      copy.cells[key] =
        make_cell (cell.row, cell.col, cell.text, cell.style, clock)
    end
    for _, field in ipairs ({
      'row_styles',
      'col_styles',
      'widths',
      'heights',
      'hidden_rows',
      'hidden_cols',
      'notes',
      'links',
    }) do
      local src = (self --[[@as table<string, any>]])[field] --[[@as table<any, any>]]
      local dst = (copy --[[@as table<string, any>]])[field] --[[@as table<any, any>]]
      for k, v in pairs (src) do
        dst[k] = v
      end
    end
    copy.merges = self.merges
    copy.rules = self.rules
    copy.validation = self.validation
    copy.charts = self.charts
    copy.freeze_rows, copy.freeze_cols = self.freeze_rows, self.freeze_cols
    self:copy_view (copy)
    local f = self.filter
    if f then
      local hidden = {} ---@type table<integer, boolean>
      for k, v in pairs (f.hidden) do
        hidden[k] = v
      end
      copy.filter = { rect = f.rect, columns = f.columns, hidden = hidden }
    end
    return copy
  end

  ---@param v any
  ---@return integer?
  local function whole (v)
    local n = tonumber (v)
    if not n or n ~= n or n == math.huge or n == -math.huge then
      return nil
    end
    return math.tointeger (math.floor (n))
  end

  ---A column from a key such as `C`, `3` or 3.
  ---@param key any
  ---@return integer?
  local function col_key (key)
    if type (key) == 'number' then
      return whole (key)
    elseif type (key) == 'string' then
      return M.col_number (key) or whole (key)
    end
    return nil
  end

  ---@param t any
  ---@return table?
  local function copy_table (t)
    if type (t) ~= 'table' then
      return nil
    end
    local out = {} ---@type table<any, any>
    for k, v in
      pairs (t --[[@as table<any, any>]])
    do
      if type (v) == 'table' then
        out[k] = copy_table (v)
      else
        out[k] = v
      end
    end
    return out
  end

  ---@param v any
  ---@return string?
  local function text_of (v)
    if type (v) == 'string' then
      return v
    elseif type (v) == 'number' then
      return formula.format_number (v, 15)
    elseif type (v) == 'boolean' then
      return v and 'TRUE' or 'FALSE'
    end
    return nil
  end

  ---A filter column test from file data, or nil.
  ---@param t any
  ---@return Sheet.FilterColumn?
  local function filter_column (t)
    if type (t) ~= 'table' then
      return nil
    end
    local out = {} ---@type Sheet.FilterColumn
    if type (t.values) == 'table' then
      local values = {} ---@type string[]
      for _, v in
        ipairs (t.values --[[@as any[] ]])
      do
        local s = text_of (v)
        if s then
          values[#values + 1] = s
        end
      end
      out.values = values
    end
    if type (t.op) == 'string' then
      out.op = t.op
      out.value = text_of (t.value)
      out.value2 = text_of (t.value2)
    end
    if not out.values and not out.op then
      return nil
    end
    return out
  end

  ---True when a cell lies within the last row and column a sheet can have.
  ---@param row integer
  ---@param col integer
  ---@return boolean
  local function on_sheet (row, col)
    return row <= formula.LAST_ROW and col <= formula.LAST_COL
  end

  ---Fills an empty sheet from file data, without undo. Fields of the wrong type are skipped.
  ---Cells past the last row or column a sheet can have are left out.
  ---@param data any
  function Sheet:load (data)
    if type (data) ~= 'table' then
      return
    end
    local rows, cols = whole (data.rows), whole (data.cols)
    if rows and rows >= 1 then
      self.rows = math.min (rows, formula.LAST_ROW)
    end
    if cols and cols >= 1 then
      self.cols = math.min (cols, formula.LAST_COL)
    end
    if type (data.cells) == 'table' then
      for addr, v in
        pairs (data.cells --[[@as table<any, any>]])
      do
        local row, col = nil, nil ---@type integer?, integer?
        if type (addr) == 'string' then
          row, col = M.parse_address (addr)
        end
        local text = text_of (v)
        if row and col and text and text ~= '' and on_sheet (row, col) then
          self:put (row, col, { text = text })
        end
      end
    end
    if type (data.styles) == 'table' then
      for addr, style in
        pairs (data.styles --[[@as table<any, any>]])
      do
        local row, col = nil, nil ---@type integer?, integer?
        if type (addr) == 'string' then
          row, col = M.parse_address (addr)
        end
        local s = intern (style)
        if row and col and s and on_sheet (row, col) then
          self:put (row, col, { text = self:text (row, col), style = s })
        end
      end
    end
    if type (data.widths) == 'table' then
      for key, w in
        pairs (data.widths --[[@as table<any, any>]])
      do
        local col = col_key (key)
        if col and col >= 1 and type (w) == 'number' and w > 0 then
          local px =
            math.floor (math.max (MIN_WIDTH, math.min (MAX_WIDTH, w)) + 0.5)
          self.widths[col] = px ~= M.DEFAULT_WIDTH and px or nil
        end
      end
    end
    if type (data.heights) == 'table' then
      for key, h in
        pairs (data.heights --[[@as table<any, any>]])
      do
        local row = whole (key)
        if row and row >= 1 and type (h) == 'number' and h > 0 then
          local px =
            math.floor (math.max (MIN_HEIGHT, math.min (MAX_HEIGHT, h)) + 0.5)
          self.heights[row] = px ~= M.DEFAULT_HEIGHT and px or nil
        end
      end
    end
    if type (data.hidden_rows) == 'table' then
      for _, v in
        pairs (data.hidden_rows --[[@as table<any, any>]])
      do
        local row = whole (v)
        if row and row >= 1 then
          self.hidden_rows[row] = true
        end
      end
    end
    if type (data.hidden_cols) == 'table' then
      for _, v in
        pairs (data.hidden_cols --[[@as table<any, any>]])
      do
        local col = col_key (v)
        if col and col >= 1 then
          self.hidden_cols[col] = true
        end
      end
    end
    if type (data.freeze) == 'table' then
      self.freeze_rows = math.max (0, whole (data.freeze.rows) or 0)
      self.freeze_cols = math.max (0, whole (data.freeze.cols) or 0)
    end
    self:load_view (data, whole, col_key)
    if type (data.col_styles) == 'table' then
      for key, style in
        pairs (data.col_styles --[[@as table<any, any>]])
      do
        local col = col_key (key)
        if col and col >= 1 then
          self.col_styles[col] = intern (style)
        end
      end
    end
    if type (data.row_styles) == 'table' then
      for key, style in
        pairs (data.row_styles --[[@as table<any, any>]])
      do
        local row = whole (key)
        if row and row >= 1 then
          self.row_styles[row] = intern (style)
        end
      end
    end
    if type (data.merges) == 'table' then
      local list = {} ---@type Sheet.Rect[]
      for _, text in
        ipairs (data.merges --[[@as any[] ]])
      do
        local m = M.parse_range (text)
        if m and (m.r1 < m.r2 or m.c1 < m.c2) then
          local clash = false
          for _, other in ipairs (list) do
            if M.overlaps (m, other) then
              clash = true
            end
          end
          if not clash then
            list[#list + 1] = m
          end
        end
      end
      self.merges = list
    end
    for _, field in ipairs ({ 'notes', 'links' }) do
      local map = (data --[[@as table<string, any>]])[field]
      if type (map) == 'table' then
        local into = (self --[[@as table<string, table<integer, string>>]])[field]
        for addr, text in
          pairs (map --[[@as table<any, any>]])
        do
          local row, col = nil, nil ---@type integer?, integer?
          if type (addr) == 'string' then
            row, col = M.parse_address (addr)
          end
          if row and col and type (text) == 'string' and text ~= '' then
            into[row * KEY + col] = text
          end
        end
      end
    end
    local f = data.filter ---@type any
    local rect = type (f) == 'table' and M.parse_range (f.range)
    if type (f) == 'table' and rect then
      local columns = {} ---@type table<integer, Sheet.FilterColumn>
      if type (f.columns) == 'table' then
        for key, t in
          pairs (f.columns --[[@as table<any, any>]])
        do
          local col = col_key (key)
          local test = filter_column (t)
          if col and test then
            columns[col] = test
          end
        end
      end
      self.filter = { rect = rect, columns = columns, hidden = {} }
    end
    for _, field in ipairs ({ 'rules', 'validation', 'charts' }) do
      local list = {} ---@type table[]
      if type (data[field]) == 'table' then
        for _, item in
          ipairs (data[field] --[[@as any[] ]])
        do
          if type (item) == 'table' and M.parse_range (item.range) then
            list[#list + 1] = copy_table (item) --[[@as table]]
          end
        end
      end
      (self --[[@as table<string, any>]])[field] = list
    end
    for i, chart in ipairs (self.charts) do
      if type (chart.id) ~= 'string' then
        chart.id = 'c' .. i
      end
      chart.type = chart.type or 'column'
      chart.x = tonumber (chart.x) or 0
      chart.y = tonumber (chart.y) or 0
      chart.w = tonumber (chart.w) or 480
      chart.h = tonumber (chart.h) or 300
    end
    self.touched = true
  end

  ---@param map table<integer, any>
  ---@return integer[]
  local function sorted (map)
    local keys = {} ---@type integer[]
    for k in pairs (map) do
      keys[#keys + 1] = k
    end
    table.sort (keys)
    return keys
  end

  ---The sheet as plain data, the shape of one sheet in a `.sheet.json` file. Empty fields are
  ---left out, except `cells`.
  ---@return Sheet.SheetData
  function Sheet:to_data ()
    ---@type Sheet.SheetData
    local data = {
      name = self.name,
      rows = self.rows,
      cols = self.cols,
      cells = {},
    }
    if next (self.widths) then
      data.widths = {}
      for c, w in pairs (self.widths) do
        data.widths[M.col_name (c)] = w
      end
    end
    if next (self.heights) then
      data.heights = {}
      for r, h in pairs (self.heights) do
        data.heights[string.format ('%d', r)] = h
      end
    end
    if next (self.hidden_rows) then
      data.hidden_rows = sorted (self.hidden_rows)
    end
    if next (self.hidden_cols) then
      local list = {} ---@type string[]
      for _, c in ipairs (sorted (self.hidden_cols)) do
        list[#list + 1] = M.col_name (c)
      end
      data.hidden_cols = list
    end
    if self.freeze_rows > 0 or self.freeze_cols > 0 then
      data.freeze = {
        rows = self.freeze_rows > 0 and self.freeze_rows or nil,
        cols = self.freeze_cols > 0 and self.freeze_cols or nil,
      }
    end
    local cells = data.cells --[[@as table<string, string>]]
    local styles = {} ---@type table<string, Sheet.Style>
    for _, cell in pairs (self.cells) do
      local addr = M.address (cell.row, cell.col)
      if cell.text ~= '' then
        cells[addr] = cell.text
      end
      if cell.style then
        styles[addr] = M.copy_style (cell.style) --[[@as Sheet.Style]]
      end
    end
    if next (styles) then
      data.styles = styles
    end
    if next (self.col_styles) then
      data.col_styles = {}
      for c, style in pairs (self.col_styles) do
        data.col_styles[M.col_name (c)] = M.copy_style (style) --[[@as Sheet.Style]]
      end
    end
    if next (self.row_styles) then
      data.row_styles = {}
      for r, style in pairs (self.row_styles) do
        data.row_styles[string.format ('%d', r)] = M.copy_style (style) --[[@as Sheet.Style]]
      end
    end
    if #self.merges > 0 then
      local list = {} ---@type string[]
      for i, m in ipairs (self.merges) do
        list[i] = M.range_name (m)
      end
      data.merges = list
    end
    if next (self.notes) then
      data.notes = {}
      for key, text in pairs (self.notes) do
        local row = math.floor (key / KEY)
        data.notes[M.address (row, key - row * KEY)] = text
      end
    end
    if next (self.links) then
      data.links = {}
      for key, text in pairs (self.links) do
        local row = math.floor (key / KEY)
        data.links[M.address (row, key - row * KEY)] = text
      end
    end
    local f = self.filter
    if f then
      local columns = {} ---@type table<string, Sheet.FilterColumn>
      for c, test in pairs (f.columns) do
        columns[M.col_name (c)] = copy_table (test) --[[@as Sheet.FilterColumn]]
      end
      data.filter = {
        range = M.range_name (f.rect),
        columns = next (columns) and columns or nil,
      }
    end
    if #self.rules > 0 then
      data.rules = copy_table (self.rules) --[[@as Sheet.Rule[] ]]
    end
    if #self.validation > 0 then
      data.validation = copy_table (self.validation) --[[@as Sheet.Validation[] ]]
    end
    if #self.charts > 0 then
      data.charts = copy_table (self.charts) --[[@as Sheet.ChartSpec[] ]]
    end
    self:save_view (data)
    return data
  end
end
