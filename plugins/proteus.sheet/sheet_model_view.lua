-- sheet_model_view: how a sheet of the Sheet app shows and prints, apart from its cells. The
-- zoom, protection, which keeps locked cells from changing, groups of rows and columns that
-- fold away (the outline), and the print area and page setup. sheet_model calls it with its
-- kit, and it adds its methods to every sheet.

---A group of rows or columns in the outline: the rows `from` to `to`, at a depth from 1 to 7.
---@class Sheet.OutlineGroup
---@field from integer
---@field to integer
---@field level integer
---@field collapsed boolean True when every row or column of the group is hidden.

---How a sheet prints.
---@class Sheet.PageSetup
---@field landscape? boolean
---@field gridlines? boolean Print the lines between cells.

---@param K Sheet.ModelKit
return function (K)
  ---@class Sheet.Sheet
  local Sheet = K.Sheet
  ---@class Sheet.ModelModule
  local M = K.M

  M.MIN_ZOOM, M.MAX_ZOOM = 25, 400
  M.MAX_LEVEL = 7
  -- The most cells `any_locked` looks at one by one.
  local LOCK_SCAN = 200000

  -------------------------------------------------------------------------------------------
  -- Zoom
  -------------------------------------------------------------------------------------------

  ---Sets how large the sheet shows, in percent, between 25 and 400. The zoom is a way of
  ---looking, so it is not an undo step, but it is saved with the sheet.
  ---@param percent number
  ---@return integer
  function Sheet:set_zoom (percent)
    local z = math.floor ((tonumber (percent) or 100) + 0.5)
    z = math.max (M.MIN_ZOOM, math.min (M.MAX_ZOOM, z))
    self.zoom = z ~= 100 and z or nil
    self.book:touch ()
    return z
  end

  ---The zoom in percent.
  ---@return integer
  function Sheet:zoom_percent ()
    return self.zoom or 100
  end

  -------------------------------------------------------------------------------------------
  -- Protection
  -------------------------------------------------------------------------------------------

  ---Protects the sheet, or lifts its protection, as one undo step. While it is protected,
  ---only cells styled `unlocked` change.
  ---@param on boolean
  function Sheet:set_protected (on)
    self:begin ({ label = on and 'Protect sheet' or 'Unprotect sheet' })
    self:set_prop ('protected', nil, on or nil)
    self:finish ()
  end

  ---True when the sheet is protected and the cell is locked, as every cell is unless its
  ---style says `unlocked`.
  ---@param row integer
  ---@param col integer
  ---@return boolean
  function Sheet:locked_at (row, col)
    return self.protected == true and not self:style_at (row, col).unlocked
  end

  ---True when the sheet is protected and a block holds a locked cell. A block too big to look
  ---at cell by cell counts as locked.
  ---@param rect Sheet.Rect
  ---@return boolean
  function Sheet:any_locked (rect)
    if not self.protected then
      return false
    end
    local r1, r2 = math.max (1, rect.r1), math.min (self.rows, rect.r2)
    local c1, c2 = math.max (1, rect.c1), math.min (self.cols, rect.c2)
    if (r2 - r1 + 1) * (c2 - c1 + 1) > LOCK_SCAN then
      return true
    end
    for row = r1, r2 do
      for col = c1, c2 do
        if not self:style_at (row, col).unlocked then
          return true
        end
      end
    end
    return false
  end

  -------------------------------------------------------------------------------------------
  -- The outline
  -------------------------------------------------------------------------------------------

  ---@param axis 'row'|'col'
  ---@return table<integer, integer>
  function Sheet:levels (axis)
    return axis == 'row' and self.row_levels or self.col_levels
  end

  ---Groups rows or columns one level deeper with `delta` 1, or takes them a level out with
  ----1. One undo step.
  ---@param axis 'row'|'col'
  ---@param from integer
  ---@param to integer
  ---@param delta integer
  function Sheet:group (axis, from, to, delta)
    local field = axis == 'row' and 'row_levels' or 'col_levels'
    local map = self:levels (axis)
    self:begin ({ label = delta > 0 and 'Group' or 'Ungroup' })
    for i = math.min (from, to), math.max (from, to) do
      local level = math.max (0, math.min (M.MAX_LEVEL, (map[i] or 0) + delta))
      self:set_prop (field, i, level > 0 and level or nil)
    end
    self:finish ()
  end

  ---The groups of the outline along an axis, outer groups before the groups inside them.
  ---@param axis 'row'|'col'
  ---@return Sheet.OutlineGroup[]
  function Sheet:outline (axis)
    local map = self:levels (axis)
    local hidden = axis == 'row' and self.hidden_rows or self.hidden_cols
    local keys = {} ---@type integer[]
    local deepest = 0
    for i, level in pairs (map) do
      keys[#keys + 1] = i
      deepest = math.max (deepest, level)
    end
    table.sort (keys)
    local out = {} ---@type Sheet.OutlineGroup[]
    for level = 1, deepest do
      local start, last = nil, nil ---@type integer?, integer?
      local folded = true
      ---Closes the run that is open.
      local function close ()
        if start and last then
          out[#out + 1] =
            { from = start, to = last, level = level, collapsed = folded }
        end
        start, last, folded = nil, nil, true
      end
      for _, i in ipairs (keys) do
        if map[i] >= level then
          if last and i ~= last + 1 then
            close ()
          end
          start = start or i
          last = i
          folded = folded and hidden[i] == true
        end
      end
      close ()
    end
    table.sort (out, function (a, b)
      if a.from ~= b.from then
        return a.from < b.from
      end
      return a.level < b.level
    end)
    return out
  end

  ---The row or column that shows a group's button: the one after it, or the one before when
  ---the group runs to the end of the sheet.
  ---@param axis 'row'|'col'
  ---@param g Sheet.OutlineGroup
  ---@return integer
  function Sheet:summary_of (axis, g)
    local size = axis == 'row' and self.rows or self.cols
    if g.to >= size then
      return math.max (1, g.from - 1)
    end
    return g.to + 1
  end

  ---The outermost group whose button sits on a row or column, or nil.
  ---@param axis 'row'|'col'
  ---@param index integer
  ---@return Sheet.OutlineGroup?
  function Sheet:group_at_summary (axis, index)
    for _, g in ipairs (self:outline (axis)) do
      if self:summary_of (axis, g) == index then
        return g
      end
    end
    return nil
  end

  ---The innermost group that holds a row or column, or nil.
  ---@param axis 'row'|'col'
  ---@param index integer
  ---@return Sheet.OutlineGroup?
  function Sheet:group_holding (axis, index)
    local found = nil ---@type Sheet.OutlineGroup?
    for _, g in ipairs (self:outline (axis)) do
      if index >= g.from and index <= g.to then
        if not found or g.level > found.level then
          found = g
        end
      end
    end
    return found
  end

  ---Folds a group away, or shows it again. One undo step.
  ---@param axis 'row'|'col'
  ---@param g Sheet.OutlineGroup
  ---@param show boolean
  function Sheet:fold (axis, g, show)
    self:set_hidden (axis, g.from, g.to, not show)
  end

  -------------------------------------------------------------------------------------------
  -- Printing
  -------------------------------------------------------------------------------------------

  ---Sets the block that prints, or none with nil, as one undo step.
  ---@param rect? Sheet.Rect
  function Sheet:set_print_area (rect)
    self:begin ({ label = rect and 'Set print area' or 'Clear print area' })
    self:set_prop ('print_area', nil, rect and M.range_name (rect) or nil)
    self:finish ()
  end

  ---Changes the page setup, as one undo step. A field set to false goes back to the default.
  ---@param patch Sheet.PageSetup
  function Sheet:set_page (patch)
    local page = {} ---@type table<string, any>
    for k, v in pairs (self.page or {}) do
      page[k] = v
    end
    for k, v in
      pairs (patch --[[@as table<string, any>]])
    do
      page[k] = v or nil
    end
    self:begin ({ label = 'Page setup' })
    self:set_prop ('page', nil, next (page) and page or nil)
    self:finish ()
  end

  ---The block that prints: the print area, or else every used cell.
  ---@return Sheet.Rect
  function Sheet:print_rect ()
    local area = self.print_area and M.parse_range (self.print_area)
    if area then
      return area
    end
    local rows, cols = self:used ()
    return { r1 = 1, c1 = 1, r2 = math.max (1, rows), c2 = math.max (1, cols) }
  end

  -------------------------------------------------------------------------------------------
  -- As data
  -------------------------------------------------------------------------------------------

  ---Reads the view fields of a sheet's data. sheet_model_data calls it while it loads.
  ---@param data Sheet.SheetData
  ---@param whole fun(v: any): integer?
  ---@param col_key fun(key: any): integer?
  function Sheet:load_view (data, whole, col_key)
    local zoom = whole (data.zoom)
    if zoom and zoom ~= 100 then
      self.zoom = math.max (M.MIN_ZOOM, math.min (M.MAX_ZOOM, zoom))
    end
    self.protected = data.protected == true or nil
    for field, key_of in pairs ({ row_levels = whole, col_levels = col_key }) do
      local map = (data --[[@as table<string, any>]])[field]
      local into = (self --[[@as table<string, table<integer, integer>>]])[field]
      if type (map) == 'table' then
        for key, level in
          pairs (map --[[@as table<any, any>]])
        do
          local i, n = key_of (key), whole (level)
          if i and i >= 1 and n and n >= 1 then
            into[i] = math.min (M.MAX_LEVEL, n)
          end
        end
      end
    end
    if type (data.print_area) == 'string' and M.parse_range (data.print_area) then
      self.print_area = string.upper (data.print_area)
    end
    if type (data.page) == 'table' then
      local page = {} ---@type Sheet.PageSetup
      page.landscape = data.page.landscape == true or nil
      page.gridlines = data.page.gridlines == true or nil
      self.page = next (page) and page or nil
    end
  end

  ---Writes the view fields into a sheet's data.
  ---@param data Sheet.SheetData
  function Sheet:save_view (data)
    data.zoom = self.zoom
    data.protected = self.protected
    if next (self.row_levels) then
      data.row_levels = {}
      for r, level in pairs (self.row_levels) do
        data.row_levels[string.format ('%d', r)] = level
      end
    end
    if next (self.col_levels) then
      data.col_levels = {}
      for c, level in pairs (self.col_levels) do
        data.col_levels[M.col_name (c)] = level
      end
    end
    data.print_area = self.print_area
    if self.page then
      data.page = { landscape = self.page.landscape, gridlines = self.page.gridlines }
    end
  end

  ---Copies the view fields to a copy of the sheet.
  ---@param copy Sheet.Sheet
  function Sheet:copy_view (copy)
    copy.zoom, copy.protected = self.zoom, self.protected
    for r, level in pairs (self.row_levels) do
      copy.row_levels[r] = level
    end
    for c, level in pairs (self.col_levels) do
      copy.col_levels[c] = level
    end
    copy.print_area, copy.page = self.print_area, self.page
  end
end
