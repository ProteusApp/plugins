-- sheet_fn_lookup: the lookup and reference functions of the Sheet app's formulas: VLOOKUP,
-- XLOOKUP, MATCH and INDEX, the size and place of a reference, and the references made from
-- text and numbers with INDIRECT, OFFSET and ADDRESS. sheet_formula loads the module.

---@param K Sheet.FormulaKit
return function (K)
  local define, raise, ERRORS = K.define, K.raise, K.ERRORS
  local dims, grid_at, new_array = K.dims, K.grid_at, K.new_array
  local eval, given, value_of, text_of, bool_of, int_of =
    K.eval, K.given, K.value_of, K.text_of, K.bool_of, K.int_of
  local grid_or_value, need_grid, need_reference =
    K.grid_or_value, K.need_grid, K.need_reference
  local resolve, cell_range, on_sheet = K.resolve, K.cell_range, K.on_sheet
  local opt_int, opt_bool = K.opt_int, K.opt_bool
  local compare, equals = K.compare, K.equals
  local to_number, to_text, trunc = K.to_number, K.to_text, K.trunc
  local tokenize, sheet_prefix = K.tokenize, K.sheet_prefix
  local col_name, quote_sheet = K.col_name, K.quote_sheet

  -------------------------------------------------------------------------------------------
  -- Lookup
  -------------------------------------------------------------------------------------------

  ---Finds a value in sorted data without an exact match. `dir` 1 finds the last value up to
  ---`want` in ascending data, and -1 the last value from `want` up in descending data. Only
  ---values of the same type as `want` count, and the search stops at the first value on the far
  ---side. Returns the position or nil.
  ---@param get fun(k: integer): Sheet.Value
  ---@param count integer
  ---@param want Sheet.Value
  ---@param dir integer
  ---@return integer?
  local function find_sorted (get, count, want, dir)
    if want == nil then
      return nil
    end
    local kind = type (want)
    local best = nil ---@type integer?
    for k = 1, count do
      local v = get (k)
      if type (v) == kind then
        local c = compare (v, want)
        if c == 0 or (dir > 0 and c < 0) or (dir < 0 and c > 0) then
          best = k
        else
          break
        end
      end
    end
    return best
  end

  ---Finds a value by exact match, first to last.
  ---@param get fun(k: integer): Sheet.Value
  ---@param count integer
  ---@param want Sheet.Value
  ---@param wild boolean
  ---@return integer?
  local function find_exact (get, count, want, wild)
    local same = equals (want, wild)
    for k = 1, count do
      if same (get (k)) then
        return k
      end
    end
    return nil
  end

  ---Finds a value for XLOOKUP and XMATCH. Mode 0 is an exact match, 2 an exact match with
  ---wildcards, -1 the exact value or the next smaller one, and 1 the exact value or the next
  ---larger one. The data need no order.
  ---@param get fun(k: integer): Sheet.Value
  ---@param count integer
  ---@param want Sheet.Value
  ---@param mode integer
  ---@param reverse boolean True to search from the last value back.
  ---@return integer?
  local function find_near (get, count, want, mode, reverse)
    local same = equals (want, mode == 2)
    local from, to, step = 1, count, 1
    if reverse then
      from, to, step = count, 1, -1
    end
    local best, best_v = nil, nil ---@type integer?, Sheet.Value
    for k = from, to, step do
      local v = get (k)
      if same (v) then
        return k
      end
      if (mode == 1 or mode == -1) and v ~= nil and type (v) == type (want) then
        local c = compare (v, want)
        if c * mode > 0 and (best == nil or compare (v, best_v) * mode < 0) then
          best, best_v = k, v
        end
      end
    end
    return best
  end

  ---A getter for the values along a one-row or one-column block.
  ---@param g Sheet.Grid
  ---@param ctx Sheet.Context
  ---@return fun(k: integer): Sheet.Value
  ---@return integer count
  local function along (g, ctx)
    local h, w = dims (g)
    if h == 1 then
      return function (k)
        return grid_at (g, 1, k, ctx)
      end, w
    end
    return function (k)
      return grid_at (g, k, 1, ctx)
    end, h
  end

  ---Part of a block: rows `r1` to `r2` and columns `c1` to `c2`, counting from 1.
  ---@param g Sheet.Grid
  ---@param r1 integer
  ---@param c1 integer
  ---@param r2 integer
  ---@param c2 integer
  ---@param ctx Sheet.Context
  ---@return Sheet.Grid
  local function sub_grid (g, r1, c1, r2, c2, ctx)
    if g.is_range then
      local r = g --[[@as Sheet.RangeValue]]
      return {
        is_range = true,
        r1 = r.r1 + r1 - 1,
        c1 = r.c1 + c1 - 1,
        r2 = r.r1 + r2 - 1,
        c2 = r.c1 + c2 - 1,
        sheet = r.sheet,
      }
    end
    local out = {} ---@type Sheet.Values
    local k = 0
    for i = r1, r2 do
      for j = c1, c2 do
        k = k + 1
        out[k] = grid_at (g, i, j, ctx)
      end
    end
    return new_array (r2 - r1 + 1, c2 - c1 + 1, out)
  end

  ---VLOOKUP and HLOOKUP.
  ---@param across boolean True for HLOOKUP, which looks along the first row.
  ---@return Sheet.Function
  local function table_lookup (across)
    return {
      min = 3,
      max = 4,
      run = function (args, ctx)
        local want = value_of (args[1], ctx)
        local g = need_grid (args[2], ctx)
        local index = int_of (args[3], ctx)
        local approx = true
        if args[4] then
          approx = bool_of (args[4], ctx)
        end
        local h, w = dims (g)
        local count, size = h, w
        if across then
          count, size = w, h
        end
        if index < 1 then
          return raise ('#VALUE!')
        end
        if index > size then
          return raise ('#REF!')
        end
        ---@param k integer
        ---@return Sheet.Value
        local function get (k)
          if across then
            return grid_at (g, 1, k, ctx)
          end
          return grid_at (g, k, 1, ctx)
        end
        local k ---@type integer?
        if approx then
          k = find_sorted (get, count, want, 1)
        else
          k = find_exact (get, count, want, true)
        end
        if not k then
          return raise ('#N/A')
        end
        if across then
          return grid_at (g, index, k, ctx)
        end
        return grid_at (g, k, index, ctx)
      end,
    }
  end

  define (
    'VLOOKUP',
    'Lookup',
    'VLOOKUP(value, table, column, [approximate])',
    'Finds a value in the first column of a table and gives the value in another column of its row.',
    table_lookup (false)
  )
  define (
    'HLOOKUP',
    'Lookup',
    'HLOOKUP(value, table, row, [approximate])',
    'Finds a value in the first row of a table and gives the value in another row of its column.',
    table_lookup (true)
  )

  ---Reads the match mode and search mode of XLOOKUP and XMATCH.
  ---@param args Sheet.Node[]
  ---@param at integer Where the match mode sits.
  ---@param ctx Sheet.Context
  ---@return integer mode
  ---@return boolean reverse
  local function x_modes (args, at, ctx)
    local mode, dir = 0, 1
    if given (args[at]) then
      mode = int_of (args[at], ctx)
    end
    if given (args[at + 1]) then
      dir = int_of (args[at + 1], ctx)
    end
    if
      mode < -1
      or mode > 2
      or (dir ~= 1 and dir ~= -1 and dir ~= 2 and dir ~= -2)
    then
      error (ERRORS['#VALUE!'], 0)
    end
    return mode, dir < 0
  end

  define (
    'XLOOKUP',
    'Lookup',
    'XLOOKUP(value, lookup_range, return_range, [if_not_found], [match_mode], [search_mode])',
    'Finds a value in one range and gives what sits at the same place in another.',
    {
      min = 3,
      max = 6,
      run = function (args, ctx)
        local want = value_of (args[1], ctx)
        local look = need_grid (args[2], ctx)
        local back = need_grid (args[3], ctx)
        local lh, lw = dims (look)
        local bh, bw = dims (back)
        if lh ~= 1 and lw ~= 1 then
          return raise ('#VALUE!')
        end
        local across = lh == 1 and lw > 1
        if (across and bw ~= lw) or (not across and bh ~= lh) then
          return raise ('#VALUE!')
        end
        local mode, reverse = x_modes (args, 5, ctx)
        local get, count = along (look, ctx)
        local k = find_near (get, count, want, mode, reverse)
        if not k then
          if given (args[4]) then
            return eval (args[4], ctx)
          end
          return raise ('#N/A')
        end
        if across then
          return sub_grid (back, 1, k, bh, k, ctx)
        end
        return sub_grid (back, k, 1, k, bw, ctx)
      end,
    }
  )

  define (
    'LOOKUP',
    'Lookup',
    'LOOKUP(value, lookup_range, [result_range])',
    'Finds the largest value up to a value in sorted data and gives what sits at the same place.',
    {
      min = 2,
      max = 3,
      run = function (args, ctx)
        local want = value_of (args[1], ctx)
        local g = need_grid (args[2], ctx)
        local h, w = dims (g)
        local get, count = along (g, ctx)
        local result ---@type fun(k: integer): Sheet.Value
        if given (args[3]) then
          result = along (need_grid (args[3] --[[@as Sheet.Node]], ctx), ctx)
        elseif w > h then
          -- A wide block is searched along its first row, and gives from its last row.
          count = w
          get = function (k)
            return grid_at (g, 1, k, ctx)
          end
          result = function (k)
            return grid_at (g, h, k, ctx)
          end
        else
          count = h
          get = function (k)
            return grid_at (g, k, 1, ctx)
          end
          result = function (k)
            return grid_at (g, k, w, ctx)
          end
        end
        local k = find_sorted (get, count, want, 1)
        if not k then
          return raise ('#N/A')
        end
        return result (k)
      end,
    }
  )

  define (
    'MATCH',
    'Lookup',
    'MATCH(value, range, [match_type])',
    'Gives the position of a value in a row or column: 0 for an exact match, 1 or -1 for sorted data.',
    {
      min = 2,
      max = 3,
      run = function (args, ctx)
        local want = value_of (args[1], ctx)
        local g = need_grid (args[2], ctx)
        local h, w = dims (g)
        if h ~= 1 and w ~= 1 then
          return raise ('#N/A')
        end
        local kind = 1
        if args[3] then
          kind = int_of (args[3], ctx)
        end
        local get, count = along (g, ctx)
        local k ---@type integer?
        if kind == 0 then
          k = find_exact (get, count, want, true)
        else
          k = find_sorted (get, count, want, kind > 0 and 1 or -1)
        end
        if not k then
          return raise ('#N/A')
        end
        return k
      end,
    }
  )

  define (
    'XMATCH',
    'Lookup',
    'XMATCH(value, range, [match_mode], [search_mode])',
    'Gives the position of a value in a row or column, in any order.',
    {
      min = 2,
      max = 4,
      run = function (args, ctx)
        local want = value_of (args[1], ctx)
        local g = need_grid (args[2], ctx)
        local h, w = dims (g)
        if h ~= 1 and w ~= 1 then
          return raise ('#VALUE!')
        end
        local mode, reverse = x_modes (args, 3, ctx)
        local get, count = along (g, ctx)
        local k = find_near (get, count, want, mode, reverse)
        if not k then
          return raise ('#N/A')
        end
        return k
      end,
    }
  )

  define (
    'INDEX',
    'Lookup',
    'INDEX(range, row, [column])',
    'Gives the cell at a row and column of a range, or a whole row or column for 0.',
    {
      min = 2,
      max = 3,
      run = function (args, ctx)
        local g = need_grid (args[1], ctx)
        local h, w = dims (g)
        local row = int_of (args[2], ctx)
        local col ---@type integer
        if args[3] then
          col = int_of (args[3], ctx)
        elseif w == 1 then
          col = 1
        elseif h == 1 then
          row, col = 1, row
        else
          col = 0
        end
        if row < 0 or row > h or col < 0 or col > w then
          return raise ('#REF!')
        end
        local r1, r2, c1, c2 = row, row, col, col
        if row == 0 then
          r1, r2 = 1, h
        end
        if col == 0 then
          c1, c2 = 1, w
        end
        return sub_grid (g, r1, c1, r2, c2, ctx)
      end,
    }
  )

  ---ROW and COLUMN.
  ---@param want_row boolean
  ---@return Sheet.Function
  local function position (want_row)
    return {
      min = 0,
      max = 1,
      ---@param args Sheet.Node[]
      ---@param ctx Sheet.Context
      ---@return Sheet.Result
      run = function (args, ctx)
        if not given (args[1]) then
          local here = ctx.col ---@type integer?
          if want_row then
            here = ctx.row
          end
          return here or raise ('#VALUE!')
        end
        local rng = need_reference (args[1], ctx)
        return want_row and rng.r1 or rng.c1
      end,
    }
  end

  define (
    'ROW',
    'Lookup',
    'ROW([reference])',
    'Gives the row number of a reference, or of the cell the formula is in.',
    position (true)
  )
  define (
    'COLUMN',
    'Lookup',
    'COLUMN([reference])',
    'Gives the column number of a reference, or of the cell the formula is in.',
    position (false)
  )

  define (
    'ROWS',
    'Lookup',
    'ROWS(range)',
    'Counts the rows of a range or an array.',
    {
      min = 1,
      max = 1,
      run = function (args, ctx)
        local h = dims (grid_or_value (args[1], ctx))
        return h
      end,
    }
  )

  define (
    'COLUMNS',
    'Lookup',
    'COLUMNS(range)',
    'Counts the columns of a range or an array.',
    {
      min = 1,
      max = 1,
      run = function (args, ctx)
        local _, w = dims (grid_or_value (args[1], ctx))
        return w
      end,
    }
  )

  ---Reads a reference written as text, such as `B3`, `Data!A1:C9` or, when `a1` is false,
  ---`R3C2`. Returns nil when the text is not a reference.
  ---@param text string
  ---@param a1 boolean
  ---@param ctx Sheet.Context
  ---@return Sheet.RangeValue?
  local function read_reference (text, a1, ctx)
    local s = string.match (text, '^%s*(.-)%s*$')
    if a1 then
      local tokens = tokenize (s)
      if not tokens or #tokens ~= 1 then
        return nil
      end
      local t = tokens[1]
      if t.kind == 'ref' then
        return cell_range (t.a --[[@as Sheet.Ref]], ctx)
      end
      if t.kind == 'range' then
        return resolve (t.a --[[@as Sheet.Ref]], t.b --[[@as Sheet.Ref]], ctx)
      end
      return nil
    end
    local sheet, after = sheet_prefix (s, 1)
    local body = string.upper (string.sub (s, after))
    local r1, c1, r2, c2 = string.match (body, '^R(%d+)C(%d+):R(%d+)C(%d+)$')
    if not r1 then
      r1, c1 = string.match (body, '^R(%d+)C(%d+)$')
      r2, c2 = r1, c1
    end
    if not r1 then
      return nil
    end
    ---@type Sheet.Ref, Sheet.Ref
    local a, b =
      {
        row = math.tointeger (tonumber (r1)),
        col = math.tointeger (tonumber (c1)),
        row_abs = true,
        col_abs = true,
        sheet = sheet,
      }, {
        row = math.tointeger (tonumber (r2)),
        col = math.tointeger (tonumber (c2)),
        row_abs = true,
        col_abs = true,
        sheet = sheet,
      }
    if
      (a.row or 0) < 1
      or (a.col or 0) < 1
      or (b.row or 0) < 1
      or (b.col or 0) < 1
    then
      return nil
    end
    return resolve (a, b, ctx)
  end

  define (
    'INDIRECT',
    'Lookup',
    'INDIRECT(reference_text, [a1_style])',
    'Gives the cells a reference written as text names, such as "B3" or "Data!A1:C9".',
    {
      min = 1,
      max = 2,
      run = function (args, ctx)
        local text = text_of (args[1], ctx)
        local a1 = true
        if args[2] then
          a1 = bool_of (args[2], ctx)
        end
        return read_reference (text, a1, ctx) or raise ('#REF!')
      end,
    }
  )

  define (
    'OFFSET',
    'Lookup',
    'OFFSET(reference, rows, columns, [height], [width])',
    'Gives the cells a number of rows and columns away from a reference, in a block of a given size.',
    {
      min = 3,
      max = 5,
      run = function (args, ctx)
        local base = need_reference (args[1], ctx)
        local dr, dc = int_of (args[2], ctx), int_of (args[3], ctx)
        local h, w = dims (base)
        if given (args[4]) then
          h = int_of (args[4], ctx)
        end
        if given (args[5]) then
          w = int_of (args[5], ctx)
        end
        local r1, c1 = base.r1 + dr, base.c1 + dc
        if h < 1 or w < 1 or r1 < 1 or c1 < 1 then
          return raise ('#REF!')
        end
        on_sheet (r1 + h - 1, c1 + w - 1)
        return {
          is_range = true,
          r1 = r1,
          c1 = c1,
          r2 = r1 + h - 1,
          c2 = c1 + w - 1,
          sheet = base.sheet,
        }
      end,
    }
  )

  define (
    'ADDRESS',
    'Lookup',
    'ADDRESS(row, column, [absolute], [a1_style], [sheet])',
    'Writes the address of a cell as text, such as $C$2.',
    {
      min = 2,
      max = 5,
      map = function (v, n)
        local row, col = trunc (to_number (v[1])), trunc (to_number (v[2]))
        local kind = opt_int (v, n, 3, 1)
        if row < 1 or col < 1 or kind < 1 or kind > 4 then
          return raise ('#VALUE!')
        end
        local row_abs = kind == 1 or kind == 2
        local col_abs = kind == 1 or kind == 3
        local out ---@type string
        if opt_bool (v, n, 4, true) then
          out = (col_abs and '$' or '')
            .. col_name (col)
            .. (row_abs and '$' or '')
            .. string.format ('%d', row)
        else
          out = (row_abs and 'R%d' or 'R[%d]'):format (row)
            .. (col_abs and 'C%d' or 'C[%d]'):format (col)
        end
        if n >= 5 and v[5] ~= nil then
          local sheet = to_text (v[5])
          if sheet ~= '' then
            out = quote_sheet (sheet) .. '!' .. out
          end
        end
        return out
      end,
    }
  )
end
