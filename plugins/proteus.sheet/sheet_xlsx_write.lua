-- sheet_xlsx_write: writing Excel files for the Sheet app. `write` turns workbook data into the
-- XML files of an `.xlsx` zip: the workbook, each sheet with its cells, sizes and merges, the
-- shared strings and the styles, and the parts sheet_xlsx_parts writes. The host does the
-- zipping. The module draws nothing and calls no host function.

local format = require ('sheet_format') --[[@as Sheet.FormatModule]]
local formula = require ('sheet_formula') --[[@as Sheet.FormulaModule]]
local reader = require ('sheet_xlsx_read') --[[@as Sheet.XlsxReadModule]]
local sheet_parts = require ('sheet_xlsx_parts') --[[@as Sheet.XlsxPartsModule]]
local xml_mod = require ('sheet_xml') --[[@as Sheet.XmlModule]]

---@class Sheet.XlsxWriteModule
local M = {}
local utf8_only, attr, cell_string, formula_text =
  xml_mod.utf8_only, xml_mod.attr, xml_mod.cell_string, xml_mod.formula_text
local APP_SIZE, APP_WIDTH, BUILTIN_IDS, CHAR_PX =
  reader.APP_SIZE, reader.APP_WIDTH, reader.BUILTIN_IDS, reader.CHAR_PX
local KIT, MAX_COLS, MAX_ROWS, SIDES =
  reader.KIT, reader.MAX_COLS, reader.MAX_ROWS, reader.SIDES
local STYLE_FIELDS, is_empty, number_text, overlay =
  reader.STYLE_FIELDS, reader.is_empty, reader.number_text, reader.overlay
local parse_input, to_excel = reader.parse_input, reader.to_excel

local NS_MAIN = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'
local NS_REL =
  'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
local NS_PACKAGE =
  'http://schemas.openxmlformats.org/package/2006/relationships'
local XML_HEAD = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
local SHEET_TYPE =
  'application/vnd.openxmlformats-officedocument.spreadsheetml.'

---@type table<string, boolean>
local BORDERS = {
  thin = true,
  medium = true,
  thick = true,
  dashed = true,
  dotted = true,
  double = true,
}

---@type table<string, boolean>
local EXCEL_ERRORS = {
  ['#NULL!'] = true,
  ['#DIV/0!'] = true,
  ['#VALUE!'] = true,
  ['#REF!'] = true,
  ['#NAME?'] = true,
  ['#NUM!'] = true,
  ['#N/A'] = true,
}

-- Excel's part that marks a formula as one that spills, as Excel itself writes it.
local METADATA = '<metadata xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"'
  .. ' xmlns:xda="http://schemas.microsoft.com/office/spreadsheetml/2017/dynamicarray">'
  .. '<metadataTypes count="1"><metadataType name="XLDAPR" minSupportedVersion="120000"'
  .. ' copy="1" pasteAll="1" pasteValues="1" merge="1" splitFirst="1" rowColShift="1"'
  .. ' clearFormats="1" clearComments="1" assign="1" coerce="1" cellMeta="1"/>'
  .. '</metadataTypes><futureMetadata name="XLDAPR" count="1"><bk><extLst>'
  .. '<ext uri="{bdbb8cdc-fa1e-496e-a857-3c3f30c029c3}">'
  .. '<xda:dynamicArrayProperties fDynamic="1" fCollapsed="0"/></ext></extLst></bk>'
  .. '</futureMetadata><cellMetadata count="1"><bk><rc t="1" v="0"/></bk></cellMetadata>'
  .. '</metadata>'

---------------------------------------------------------------------------------------------
-- Writing
---------------------------------------------------------------------------------------------

---A colour as Excel's `AARRGGBB`, or nil when it is not a colour.
---@param value any
---@return string?
local function argb (value)
  if type (value) ~= 'string' then
    return nil
  end
  local hex = string.match (value, '^#?(%x%x%x%x%x%x)$')
  if not hex then
    local r, g, b = string.match (value, '^#?(%x)(%x)(%x)$') ---@type string?, string?, string?
    if not r or not g or not b then
      return nil
    end
    hex = r .. r .. g .. g .. b .. b
  end
  return 'FF' .. string.upper (hex)
end

---A style with every default field dropped and every field checked, or nil when nothing is
---left.
---@param style any
---@return Sheet.Style?
local function tidy (style)
  if type (style) ~= 'table' then
    return nil
  end
  local out = {} ---@type table<string, any>
  for _, key in ipairs ({ 'bold', 'italic', 'underline', 'strike', 'wrap' }) do
    if style[key] == true then
      out[key] = true
    end
  end
  local size = tonumber (style.size)
  if size and size > 0 and size ~= APP_SIZE then
    out.size = size
  end
  for _, key in ipairs ({ 'color', 'fill', 'border_color' }) do
    local hex = argb (style[key])
    if hex then
      out[key] = '#' .. string.lower (string.sub (hex, 3))
    end
  end
  if
    style.align == 'left'
    or style.align == 'center'
    or style.align == 'right'
  then
    out.align = style.align
  end
  if style.valign == 'top' or style.valign == 'middle' then
    out.valign = style.valign
  end
  local code = style.format ---@type any
  if
    type (code) == 'string'
    and code ~= ''
    and string.lower (code) ~= 'general'
  then
    out.format = code
  end
  for _, side in ipairs (SIDES) do
    local key = 'border_' .. side
    if BORDERS[style[key] or ''] then
      out[key] = style[key]
    end
  end
  if is_empty (out) then
    return nil
  end
  return out --[[@as Sheet.Style]]
end

---@param n number
---@return string
local function short_number (n)
  local s = string.format ('%.6f', n)
  s = string.gsub (s, '0+$', '')
  return (string.gsub (s, '%.$', ''))
end

---@return Sheet.XlsxStyleSheet
local function new_style_sheet ()
  ---@type Sheet.XlsxStyleSheet
  local sheet = {
    fonts = {},
    font_ids = {},
    fills = {
      '<fill><patternFill patternType="none"/></fill>',
      '<fill><patternFill patternType="gray125"/></fill>',
    },
    fill_ids = { [''] = 0 },
    borders = { '<border><left/><right/><top/><bottom/><diagonal/></border>' },
    border_ids = { [''] = 0 },
    formats = {},
    format_ids = {},
    xfs = {},
    xf_ids = {},
    by_style = {},
    dxfs = {},
  }
  return sheet
end

---Adds an entry to one of Excel's style lists, once. Returns its number, counting from 0.
---@param list string[]
---@param ids table<string, integer>
---@param key string
---@param xml string
---@return integer
local function add_entry (list, ids, key, xml)
  local id = ids[key]
  if not id then
    list[#list + 1] = xml
    id = #list - 1
    ids[key] = id
  end
  return id
end

---The number of a format code, adding it to the style sheet's own formats when Excel has no
---such format built in.
---@param sheet Sheet.XlsxStyleSheet
---@param code string
---@return integer
local function format_id_of (sheet, code)
  local id = BUILTIN_IDS[code] or sheet.format_ids[code]
  if not id then
    id = 164 + #sheet.formats
    sheet.format_ids[code] = id
    sheet.formats[#sheet.formats + 1] = '<numFmt numFmtId="'
      .. id
      .. '" formatCode="'
      .. attr (code)
      .. '"/>'
  end
  return id
end

---The `s` number of a style, adding it and its parts to the style sheet when it is new.
---@param sheet Sheet.XlsxStyleSheet
---@param style? Sheet.Style
---@return integer
local function xf_of (sheet, style)
  local parts = {} ---@type string[]
  local s = (style or {}) --[[@as table<string, any>]]
  for i, key in ipairs (STYLE_FIELDS) do
    parts[i] = tostring (s[key] or '')
  end
  local key = table.concat (parts, '|')
  local known = sheet.by_style[key]
  if known then
    return known
  end

  local font = {} ---@type string[]
  if s.bold then
    font[#font + 1] = '<b/>'
  end
  if s.italic then
    font[#font + 1] = '<i/>'
  end
  if s.strike then
    font[#font + 1] = '<strike/>'
  end
  if s.underline then
    font[#font + 1] = '<u/>'
  end
  local size = s.size and short_number (s.size * 3 / 4) or '11'
  font[#font + 1] = '<sz val="' .. size .. '"/>'
  local color = argb (s.color)
  font[#font + 1] = color and ('<color rgb="' .. color .. '"/>')
    or '<color theme="1"/>'
  font[#font + 1] =
    '<name val="Calibri"/><family val="2"/><scheme val="minor"/>'
  local font_xml = '<font>' .. table.concat (font) .. '</font>'
  local font_id = add_entry (sheet.fonts, sheet.font_ids, font_xml, font_xml)

  local fill = argb (s.fill)
  local fill_id = add_entry (
    sheet.fills,
    sheet.fill_ids,
    fill or '',
    '<fill><patternFill patternType="solid"><fgColor rgb="'
      .. (fill or '')
      .. '"/><bgColor indexed="64"/></patternFill></fill>'
  )

  local sides = {} ---@type string[]
  local line = argb (s.border_color)
  local line_xml = line and ('<color rgb="' .. line .. '"/>') or ''
  for _, side in ipairs ({ 'left', 'right', 'top', 'bottom' }) do
    local kind = s['border_' .. side]
    if kind then
      sides[#sides + 1] = '<'
        .. side
        .. ' style="'
        .. kind
        .. '">'
        .. line_xml
        .. '</'
        .. side
        .. '>'
    else
      sides[#sides + 1] = '<' .. side .. '/>'
    end
  end
  local border_key = table.concat (sides)
  if not string.find (border_key, 'style', 1, true) then
    border_key = ''
  end
  local border_id = add_entry (
    sheet.borders,
    sheet.border_ids,
    border_key,
    '<border>' .. table.concat (sides) .. '<diagonal/></border>'
  )

  local format_id = 0
  local code = s.format
  if code then
    format_id = format_id_of (sheet, code)
  end

  local xf = {
    '<xf numFmtId="',
    tostring (format_id),
    '" fontId="',
    tostring (font_id),
    '" fillId="',
    tostring (fill_id),
    '" borderId="',
    tostring (border_id),
    '" xfId="0"',
  }
  if format_id ~= 0 then
    xf[#xf + 1] = ' applyNumberFormat="1"'
  end
  if font_id ~= 0 then
    xf[#xf + 1] = ' applyFont="1"'
  end
  if fill_id ~= 0 then
    xf[#xf + 1] = ' applyFill="1"'
  end
  if border_id ~= 0 then
    xf[#xf + 1] = ' applyBorder="1"'
  end
  local align = {} ---@type string[]
  if s.align then
    align[#align + 1] = ' horizontal="' .. s.align .. '"'
  end
  if s.valign then
    align[#align + 1] = ' vertical="'
      .. (s.valign == 'middle' and 'center' or s.valign)
      .. '"'
  end
  if s.wrap then
    align[#align + 1] = ' wrapText="1"'
  end
  local inner = {} ---@type string[]
  if #align > 0 then
    xf[#xf + 1] = ' applyAlignment="1"'
    inner[#inner + 1] = '<alignment' .. table.concat (align) .. '/>'
  end
  if s.unlocked then
    xf[#xf + 1] = ' applyProtection="1"'
    inner[#inner + 1] = '<protection locked="0"/>'
  end
  if #inner > 0 then
    xf[#xf + 1] = '>' .. table.concat (inner) .. '</xf>'
  else
    xf[#xf + 1] = '/>'
  end
  local xf_xml = table.concat (xf)
  local id = add_entry (sheet.xfs, sheet.xf_ids, xf_xml, xf_xml)
  sheet.by_style[key] = id
  return id
end

---@param sheet Sheet.XlsxStyleSheet
---@return string
local function styles_xml (sheet)
  local out = {
    XML_HEAD,
    '<styleSheet xmlns="' .. NS_MAIN .. '">',
  }
  if #sheet.formats > 0 then
    out[#out + 1] = '<numFmts count="' .. #sheet.formats .. '">'
    out[#out + 1] = table.concat (sheet.formats)
    out[#out + 1] = '</numFmts>'
  end
  for _, list in ipairs ({
    { 'fonts', sheet.fonts },
    { 'fills', sheet.fills },
    { 'borders', sheet.borders },
  }) do
    out[#out + 1] = '<' .. list[1] .. ' count="' .. #list[2] .. '">'
    out[#out + 1] = table.concat (list[2])
    out[#out + 1] = '</' .. list[1] .. '>'
  end
  out[#out + 1] =
    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
  out[#out + 1] = '<cellXfs count="' .. #sheet.xfs .. '">'
  out[#out + 1] = table.concat (sheet.xfs)
  out[#out + 1] = '</cellXfs>'
  out[#out + 1] =
    '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
  if #sheet.dxfs > 0 then
    out[#out + 1] = '<dxfs count="'
      .. #sheet.dxfs
      .. '">'
      .. table.concat (sheet.dxfs)
      .. '</dxfs>'
  end
  out[#out + 1] = '</styleSheet>'
  return table.concat (out)
end

---@param strings Sheet.XlsxStrings
---@param s string
---@return integer
local function string_id (strings, s)
  local id = strings.ids[s]
  if not id then
    strings.list[#strings.list + 1] = s
    id = #strings.list - 1
    strings.ids[s] = id
  end
  return id
end

---@param strings Sheet.XlsxStrings
---@return string
local function strings_xml (strings)
  local out = {
    XML_HEAD,
    '<sst xmlns="'
      .. NS_MAIN
      .. '" count="'
      .. strings.uses
      .. '" uniqueCount="'
      .. #strings.list
      .. '">',
  }
  for _, s in ipairs (strings.list) do
    if string.find (s, '^%s') or string.find (s, '%s$') then
      out[#out + 1] = '<si><t xml:space="preserve">'
        .. cell_string (s)
        .. '</t></si>'
    else
      out[#out + 1] = '<si><t>' .. cell_string (s) .. '</t></si>'
    end
  end
  out[#out + 1] = '</sst>'
  return table.concat (out)
end

---@type table<string, boolean>
local RESERVED_NAMES = { history = true }

---Makes a sheet name Excel accepts: at most 31 characters, none of `[]:*?/\`, no quote at
---either end, and different from every other name, ignoring case.
---@param name string
---@param index integer
---@param taken table<string, boolean> Lower-case names already in use.
---@return string
local function excel_name (name, index, taken)
  local fixed = string.gsub (utf8_only (name), '[%[%]:%*%?/\\%c]', '_')
  fixed = string.gsub (string.gsub (fixed, "^'+", ''), "'+$", '')
  if fixed == '' then
    fixed = 'Sheet' .. index
  end
  ---@param s string
  ---@param limit integer
  ---@return string
  local function cut (s, limit)
    local stop = utf8.offset (s, limit + 1)
    return stop and string.sub (s, 1, stop - 1) or s
  end
  fixed = cut (fixed, 31)
  local candidate = fixed
  local n = 1
  while
    taken[string.lower (candidate)] or RESERVED_NAMES[string.lower (candidate)]
  do
    n = n + 1
    local suffix = ' (' .. n .. ')'
    candidate = cut (fixed, 31 - #suffix) .. suffix
  end
  return candidate
end

---The place of a cell, for sorting, rows first.
---@param row integer
---@param col integer
---@return integer
local function place (row, col)
  return row * (MAX_COLS + 1) + col
end

---@param value any
---@return integer?
local function whole (value)
  local n = tonumber (value)
  return n and math.tointeger (math.floor (n))
end

---The format a formula's result shows with when its cell sets none, such as a date for
---`=DATE(2026,9,29)`, so Excel shows it the way this app does.
---@param text string
---@return string?
local function result_code (text)
  -- Only a function such as DATE or NOW makes a date, so a formula with no call skips the
  -- parser.
  if not string.find (text, '(', 1, true) then
    return nil
  end
  local ast = formula.parse (text)
  local kind = ast and formula.result_format (ast)
  if kind then
    for _, preset in ipairs (format.presets) do
      if preset.id == kind then
        return preset.code
      end
    end
  end
  return nil
end

---The type and the text a value writes as a formula's last value.
---@param value Sheet.Value
---@return string? t
---@return string? v
local function value_parts (value)
  if type (value) == 'number' then
    if value == value and value ~= math.huge and value ~= -math.huge then
      return nil, number_text (value)
    end
    return 'e', '#NUM!'
  elseif type (value) == 'string' then
    return 'str', value
  elseif type (value) == 'boolean' then
    return 'b', value and '1' or '0'
  elseif type (value) == 'table' and EXCEL_ERRORS[value.code] then
    return 'e', value.code
  end
  return nil, nil
end

---What a cell writes: its type, its value and its formula. The last value is a format code
---the text implies, such as `$#,##0` for `$1,200`.
---@param text string
---@param cached fun(): Sheet.Value
---@param cache table<string, Sheet.XlsxTyped>
---@return string? t
---@return string? v
---@return string? f
---@return string? implied
local function cell_parts (text, cached, cache)
  if formula.is_formula (text) then
    local f = to_excel (string.sub (text, 2))
    local t, v = value_parts (cached ())
    return t, v, f
  end
  if string.sub (text, 1, 1) == "'" then
    local rest = string.sub (text, 2)
    if rest == '' then
      return nil
    end
    return 's', rest
  end
  local value, implied = parse_input (text, cache)
  if type (value) == 'number' then
    if value == value and value ~= math.huge and value ~= -math.huge then
      return nil, number_text (value), nil, implied
    end
    return 'e', '#NUM!'
  elseif type (value) == 'boolean' then
    return 'b', value and '1' or '0'
  elseif type (value) == 'table' and EXCEL_ERRORS[value.code] then
    return 'e', value.code
  elseif value == nil then
    return nil
  end
  return 's', text
end

---@class Sheet.XlsxCell
---@field row integer
---@field col integer
---@field text? string
---@field style? Sheet.Style
---@field spill? Sheet.Rect The block a formula spills, written as an array formula.
---@field spilled? boolean True for a cell a block spills into, which writes its value only.

---@class Sheet.XlsxRow
---@field height? number
---@field hidden? boolean
---@field style? Sheet.Style

---Writes one worksheet, and the parts beside it.
---@param w Sheet.XlsxWriter
---@param data Sheet.SheetData
---@param index integer
---@param name string The name the file gives the sheet.
---@param active boolean
---@return string
---@return Sheet.XlsxSheetParts
local function sheet_xml (w, data, index, name, active)
  local styles = w.styles
  local values = w.values
  local cells = {} ---@type table<integer, Sheet.XlsxCell>
  local too_far = false
  ---@param addr any
  ---@return Sheet.XlsxCell?
  local function cell_at (addr)
    if type (addr) ~= 'string' then
      return nil
    end
    local row, col = formula.parse_address (addr)
    if not row or not col then
      return nil
    end
    if row > MAX_ROWS or col > MAX_COLS then
      too_far = true
      return nil
    end
    local key = place (row, col)
    local cell = cells[key]
    if not cell then
      cell = { row = row, col = col }
      cells[key] = cell
    end
    return cell
  end
  if type (data.cells) == 'table' then
    for addr, text in pairs (data.cells) do
      if type (text) == 'string' and text ~= '' then
        local cell = cell_at (addr)
        if cell then
          cell.text = text
        end
      end
    end
  end
  if type (data.styles) == 'table' then
    for addr, style in pairs (data.styles) do
      if type (style) == 'table' then
        local cell = cell_at (addr)
        if cell then
          cell.style = style
        end
      end
    end
  end
  -- A formula that spills writes as an array formula over its block, and the block's other
  -- cells write their values, so a program that does not work formulas out still shows them.
  if w.spills then
    local anchors = {} ---@type Sheet.XlsxCell[]
    for _, cell in pairs (cells) do
      if cell.text and formula.is_formula (cell.text) then
        anchors[#anchors + 1] = cell
      end
    end
    for _, cell in ipairs (anchors) do
      local h, wide = w.spills (index, cell.row, cell.col)
      if h and wide and (h > 1 or wide > 1) then
        local area = {
          r1 = cell.row,
          c1 = cell.col,
          r2 = math.min (cell.row + h - 1, MAX_ROWS),
          c2 = math.min (cell.col + wide - 1, MAX_COLS),
        }
        cell.spill = area
        for r = area.r1, area.r2 do
          for c = area.c1, area.c2 do
            if r ~= cell.row or c ~= cell.col then
              local covered = cell_at (formula.address (r, c))
              if covered and not covered.text then
                covered.spilled = true
              end
            end
          end
        end
      end
    end
  end
  if too_far then
    w.warnings[#w.warnings + 1] = 'Cells in '
      .. name
      .. ' past row 1048576 or column XFD were left out.'
  end

  local rows = {} ---@type table<integer, Sheet.XlsxRow>
  ---@param r integer?
  ---@return Sheet.XlsxRow?
  local function row_at (r)
    if not r or r < 1 or r > MAX_ROWS then
      return nil
    end
    local row = rows[r]
    if not row then
      row = {}
      rows[r] = row
    end
    return row
  end
  for key, px in pairs (type (data.heights) == 'table' and data.heights or {}) do
    local row = row_at (whole (key))
    local h = tonumber (px)
    if row and h and h > 0 then
      row.height = h
    end
  end
  for _, r in
    ipairs (type (data.hidden_rows) == 'table' and data.hidden_rows or {})
  do
    local row = row_at (whole (r))
    if row then
      row.hidden = true
    end
  end
  for key, style in
    pairs (type (data.row_styles) == 'table' and data.row_styles or {})
  do
    local row = row_at (whole (key))
    if row and type (style) == 'table' then
      row.style = style
    end
  end

  -- Notes, links, rules, validation, the filter and charts. The rows the filter hides are
  -- hidden in the file too, since Excel does not apply a filter as it opens a file.
  local extra = sheet_parts.write (KIT, {
    data = data,
    index = index,
    name = name,
    styles = styles,
    values = values,
    filtered = w.filtered and w.filtered (index) or nil,
    warn = function (kind, text)
      if not w.seen[kind] then
        w.seen[kind] = true
        w.warnings[#w.warnings + 1] = text
      end
    end,
    charts = w.charts,
  })
  w.charts = w.charts + extra.charts
  for r in pairs (extra.hidden) do
    local row = row_at (r)
    if row then
      row.hidden = true
    end
  end

  local col_info = {} ---@type table<integer, { width?: number, hidden?: boolean, style?: Sheet.Style }>
  ---@param letters any
  ---@return { width?: number, hidden?: boolean, style?: Sheet.Style }?
  local function col_at (letters)
    local c = type (letters) == 'string' and formula.col_number (letters)
      or whole (letters)
    if not c or c < 1 or c > MAX_COLS then
      return nil
    end
    local info = col_info[c]
    if not info then
      info = {}
      col_info[c] = info
    end
    return info
  end
  for letters, px in pairs (type (data.widths) == 'table' and data.widths or {}) do
    local info = col_at (letters)
    local width = tonumber (px)
    if info and width and width > 0 then
      info.width = width
    end
  end
  for _, letters in
    ipairs (type (data.hidden_cols) == 'table' and data.hidden_cols or {})
  do
    local info = col_at (letters)
    if info then
      info.hidden = true
    end
  end
  for letters, style in
    pairs (type (data.col_styles) == 'table' and data.col_styles or {})
  do
    local info = col_at (letters)
    if info and type (style) == 'table' then
      info.style = style
    end
  end

  local out = {
    XML_HEAD,
    '<worksheet xmlns="' .. NS_MAIN .. '" xmlns:r="' .. NS_REL .. '">',
  }

  local keys = {} ---@type integer[]
  local max_row, max_col = 1, 1
  for key, cell in pairs (cells) do
    keys[#keys + 1] = key
    max_row = math.max (max_row, cell.row)
    max_col = math.max (max_col, cell.col)
  end
  table.sort (keys)
  out[#out + 1] = '<dimension ref="A1'
    .. ((max_row > 1 or max_col > 1) and (':' .. formula.address (
      max_row,
      max_col
    )) or '')
    .. '"/>'

  local view = '<sheetView workbookViewId="0"'
    .. (active and ' tabSelected="1"' or '')
  local freeze = type (data.freeze) == 'table' and data.freeze or {}
  local fr = math.max (0, whole (freeze.rows) or 0)
  local fc = math.max (0, whole (freeze.cols) or 0)
  if fr > 0 or fc > 0 then
    local pane = fr > 0 and fc > 0 and 'bottomRight'
      or fr > 0 and 'bottomLeft'
      or 'topRight'
    out[#out + 1] = '<sheetViews>'
      .. view
      .. '><pane'
      .. (fc > 0 and (' xSplit="' .. fc .. '"') or '')
      .. (fr > 0 and (' ySplit="' .. fr .. '"') or '')
      .. ' topLeftCell="'
      .. formula.address (fr + 1, fc + 1)
      .. '" activePane="'
      .. pane
      .. '" state="frozen"/><selection pane="'
      .. pane
      .. '"/></sheetView></sheetViews>'
  else
    out[#out + 1] = '<sheetViews>' .. view .. '/></sheetViews>'
  end
  out[#out + 1] = '<sheetFormatPr defaultColWidth="'
    .. short_number (APP_WIDTH / CHAR_PX)
    .. '" defaultRowHeight="15"/>'

  local col_keys = {} ---@type integer[]
  for c in pairs (col_info) do
    col_keys[#col_keys + 1] = c
  end
  table.sort (col_keys)
  if #col_keys > 0 then
    out[#out + 1] = '<cols>'
    for _, c in ipairs (col_keys) do
      local info = col_info[c]
      local parts = {
        '<col min="',
        tostring (c),
        '" max="',
        tostring (c),
        '" width="',
        short_number ((info.width or APP_WIDTH) / CHAR_PX),
        '"',
      }
      if info.width then
        parts[#parts + 1] = ' customWidth="1"'
      end
      if info.hidden then
        parts[#parts + 1] = ' hidden="1"'
      end
      local style = tidy (info.style)
      if style then
        parts[#parts + 1] = ' style="' .. xf_of (styles, style) .. '"'
      end
      out[#out + 1] = table.concat (parts) .. '/>'
    end
    out[#out + 1] = '</cols>'
  end

  local row_keys = {} ---@type integer[]
  local row_seen = {} ---@type table<integer, boolean>
  for r in pairs (rows) do
    row_keys[#row_keys + 1] = r
    row_seen[r] = true
  end
  for _, key in ipairs (keys) do
    local r = cells[key].row
    if not row_seen[r] then
      row_seen[r] = true
      row_keys[#row_keys + 1] = r
    end
  end
  table.sort (row_keys)

  out[#out + 1] = '<sheetData>'
  local k = 1
  for _, r in ipairs (row_keys) do
    local row = rows[r] or {}
    local head = { '<row r="', tostring (r), '"' }
    if row.height then
      head[#head + 1] = ' ht="'
        .. short_number (row.height * 3 / 4)
        .. '" customHeight="1"'
    end
    if row.hidden then
      head[#head + 1] = ' hidden="1"'
    end
    local row_style = tidy (row.style)
    if row_style then
      head[#head + 1] = ' s="'
        .. xf_of (styles, row_style)
        .. '" customFormat="1"'
    end
    out[#out + 1] = table.concat (head) .. '>'
    while keys[k] and cells[keys[k]].row == r do
      local cell = cells[keys[k]]
      k = k + 1
      local info = col_info[cell.col]
      local style =
        overlay (overlay (info and info.style, row.style), cell.style)
      local t, v, f, implied = nil, nil, nil, nil ---@type string?, string?, string?, string?
      if cell.text then
        t, v, f, implied = cell_parts (cell.text, function ()
          return values and values (index, cell.row, cell.col)
        end, w.typed)
      elseif cell.spilled and values then
        t, v = value_parts (values (index, cell.row, cell.col))
      end
      local full = tidy (style)
      if f and not (full and full.format) then
        implied = result_code (cell.text --[[@as string]])
      end
      if implied and not (full and full.format) then
        full = overlay (full, { format = implied })
      end
      local s = full and xf_of (styles, full) or 0
      local parts = { '<c r="', formula.address (cell.row, cell.col), '"' }
      if s ~= 0 then
        parts[#parts + 1] = ' s="' .. s .. '"'
      end
      local spill = f and cell.spill
      if spill then
        parts[#parts + 1] = ' cm="1"'
        w.dynamic = true
      end
      if t == 's' then
        ---@cast v string
        parts[#parts + 1] = ' t="s"><v>'
          .. string_id (w.strings, v)
          .. '</v></c>'
        w.strings.uses = w.strings.uses + 1
      elseif f or v then
        if t then
          parts[#parts + 1] = ' t="' .. t .. '"'
        end
        parts[#parts + 1] = '>'
        if spill then
          parts[#parts + 1] = '<f t="array" ref="'
            .. formula.address (spill.r1, spill.c1)
            .. ':'
            .. formula.address (spill.r2, spill.c2)
            .. '">'
            .. formula_text (f --[[@as string]])
            .. '</f>'
        elseif f then
          parts[#parts + 1] = '<f>' .. formula_text (f) .. '</f>'
        end
        if v then
          parts[#parts + 1] = '<v>' .. cell_string (v) .. '</v>'
        end
        parts[#parts + 1] = '</c>'
      else
        parts[#parts + 1] = '/>'
      end
      out[#out + 1] = table.concat (parts)
    end
    out[#out + 1] = '</row>'
  end
  out[#out + 1] = '</sheetData>'
  out[#out + 1] = extra.filter

  -- Excel repairs a file whose merges overlap, so a merge that overlaps an earlier one is
  -- left out.
  local merges = {} ---@type string[]
  local merged = {} ---@type Sheet.Rect[]
  local overlap = false
  for _, ref in ipairs (type (data.merges) == 'table' and data.merges or {}) do
    local from, to = string.match (tostring (ref), '^([^:]+):([^:]+)$')
    local r1, c1 = formula.parse_address (from or '')
    local r2, c2 = formula.parse_address (to or '')
    if r1 and c1 and r2 and c2 then
      ---@type Sheet.Rect
      local rect = {
        r1 = math.min (r1, r2),
        c1 = math.min (c1, c2),
        r2 = math.max (r1, r2),
        c2 = math.max (c1, c2),
      }
      local clash = false
      for _, other in ipairs (merged) do
        if
          rect.r1 <= other.r2
          and other.r1 <= rect.r2
          and rect.c1 <= other.c2
          and other.c1 <= rect.c2
        then
          clash = true
          break
        end
      end
      if clash then
        overlap = true
      elseif rect.r2 <= MAX_ROWS and rect.c2 <= MAX_COLS then
        merged[#merged + 1] = rect
        merges[#merges + 1] = '<mergeCell ref="'
          .. formula.address (rect.r1, rect.c1)
          .. ':'
          .. formula.address (rect.r2, rect.c2)
          .. '"/>'
      end
    end
  end
  if overlap then
    w.warnings[#w.warnings + 1] = 'Merged cells in '
      .. name
      .. ' that overlap others were left out.'
  end
  if #merges > 0 then
    out[#out + 1] = '<mergeCells count="'
      .. #merges
      .. '">'
      .. table.concat (merges)
      .. '</mergeCells>'
  end
  out[#out + 1] = extra.after_merges
  out[#out + 1] =
    '<pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" header="0.3" footer="0.3"/>'
  out[#out + 1] = extra.drawings
  out[#out + 1] = '</worksheet>'
  return table.concat (out), extra
end

---The content types of files by extension, such as the drawings that show notes.
---@param map table<string, string>
---@return string
local function defaults_xml (map)
  local keys = {} ---@type string[]
  for ext in pairs (map) do
    keys[#keys + 1] = ext
  end
  table.sort (keys)
  local out = {} ---@type string[]
  for _, ext in ipairs (keys) do
    out[#out + 1] = '<Default Extension="'
      .. ext
      .. '" ContentType="'
      .. map[ext]
      .. '"/>'
  end
  return table.concat (out)
end

---Makes the files of an `.xlsx` file from workbook data, as a map of path to text. `values`,
---when given, supplies the value of each formula cell, so other programs can show values
---without working them out. `spills`, when given, says which formulas spill a block, which
---write as array formulas over their blocks. `filtered`, when given, names the rows each
---sheet's filter hides. Returns the files and a list of warnings.
---@param book Sheet.BookData
---@param values? Sheet.XlsxValues
---@param spills? Sheet.XlsxSpills
---@param filtered? Sheet.XlsxFiltered
---@return table<string, string>
---@return string[]
function M.write (book, values, spills, filtered)
  local warnings = {} ---@type string[]
  local sheets = {} ---@type Sheet.SheetData[]
  for _, data in ipairs (type (book.sheets) == 'table' and book.sheets or {}) do
    if type (data) == 'table' then
      sheets[#sheets + 1] = data
    end
  end
  if #sheets == 0 then
    sheets[1] = { name = 'Sheet1' }
  end
  local active = whole (book.active) or 1
  if active < 1 or active > #sheets then
    active = 1
  end

  -- Names change only where Excel refuses them. A new name never matches any old name, so
  -- when the formulas take each rename in turn, a later rename never catches a reference an
  -- earlier one made.
  local taken = {} ---@type table<string, boolean>
  local count_of = {} ---@type table<string, integer>
  for _, data in ipairs (sheets) do
    local lower = string.lower (tostring (data.name or ''))
    taken[lower] = true
    count_of[lower] = (count_of[lower] or 0) + 1
  end
  local names = {} ---@type string[]
  local renames = {} ---@type { [1]: string, [2]: string }[]
  local used = {} ---@type table<string, boolean>
  for i, data in ipairs (sheets) do
    local old = tostring (data.name or '')
    local lower = string.lower (old)
    local keep = old ~= ''
      and not used[lower]
      and excel_name (old, i, {}) == old
    local name = old
    if not keep then
      local avoid = {} ---@type table<string, boolean>
      for k in pairs (taken) do
        avoid[k] = true
      end
      for k in pairs (used) do
        avoid[k] = true
      end
      name = excel_name (old, i, avoid)
      if old == '' then
        warnings[#warnings + 1] = 'A sheet with no name is called '
          .. name
          .. ' in the Excel file.'
      else
        warnings[#warnings + 1] = "Excel does not allow the sheet name '"
          .. old
          .. "', so the file calls it '"
          .. name
          .. "'."
        if count_of[lower] == 1 then
          renames[#renames + 1] = { old, name }
        end
      end
    end
    used[string.lower (name)] = true
    names[i] = name
  end

  ---@type Sheet.XlsxWriter
  local w = {
    styles = new_style_sheet (),
    strings = { list = {}, ids = {}, uses = 0 },
    values = values,
    warnings = warnings,
    typed = {},
    spills = spills,
    filtered = filtered,
    seen = {},
    charts = 0,
  }
  xf_of (w.styles, nil)
  local files = {} ---@type table<string, string>

  local sheet_entries = {} ---@type string[]
  local rel_entries = {} ---@type string[]
  local type_entries = {} ---@type string[]
  local default_types = {} ---@type table<string, string>
  local filter_names = {} ---@type string[]
  for i, data in ipairs (sheets) do
    if #renames > 0 and type (data.cells) == 'table' then
      local cells = {} ---@type table<string, string>
      for addr, text in pairs (data.cells) do
        if formula.is_formula (text) then
          for _, pair in ipairs (renames) do
            text = formula.rename_sheet (text, pair[1], pair[2])
          end
        end
        cells[addr] = text
      end
      local copy = {} ---@type table<string, any>
      for k, v in
        pairs (data --[[@as table<string, any>]])
      do
        copy[k] = v
      end
      copy.cells = cells
      data = copy --[[@as Sheet.SheetData]]
    end
    local path = 'xl/worksheets/sheet' .. i .. '.xml'
    local xml, extra = sheet_xml (w, data, i, names[i], i == active)
    files[path] = xml
    for part, text in pairs (extra.files) do
      files[part] = text
    end
    for _, entry in ipairs (extra.types) do
      type_entries[#type_entries + 1] = entry
    end
    for ext, kind in pairs (extra.defaults) do
      default_types[ext] = kind
    end
    if extra.defined then
      filter_names[#filter_names + 1] = extra.defined
    end
    if #extra.rels > 0 then
      files['xl/worksheets/_rels/sheet' .. i .. '.xml.rels'] = XML_HEAD
        .. '<Relationships xmlns="'
        .. NS_PACKAGE
        .. '">'
        .. table.concat (extra.rels)
        .. '</Relationships>'
    end
    sheet_entries[#sheet_entries + 1] = '<sheet name="'
      .. attr (names[i])
      .. '" sheetId="'
      .. i
      .. '" r:id="rId'
      .. i
      .. '"/>'
    rel_entries[#rel_entries + 1] = '<Relationship Id="rId'
      .. i
      .. '" Type="'
      .. NS_REL
      .. '/worksheet" Target="worksheets/sheet'
      .. i
      .. '.xml"/>'
    type_entries[#type_entries + 1] = '<Override PartName="/'
      .. path
      .. '" ContentType="'
      .. SHEET_TYPE
      .. 'worksheet+xml"/>'
  end

  local n = #sheets
  rel_entries[#rel_entries + 1] = '<Relationship Id="rId'
    .. (n + 1)
    .. '" Type="'
    .. NS_REL
    .. '/styles" Target="styles.xml"/>'
  rel_entries[#rel_entries + 1] = '<Relationship Id="rId'
    .. (n + 2)
    .. '" Type="'
    .. NS_REL
    .. '/sharedStrings" Target="sharedStrings.xml"/>'

  if w.dynamic then
    rel_entries[#rel_entries + 1] = '<Relationship Id="rId'
      .. (n + 3)
      .. '" Type="'
      .. NS_REL
      .. '/sheetMetadata" Target="metadata.xml"/>'
    type_entries[#type_entries + 1] = '<Override PartName="/xl/metadata.xml" ContentType="'
      .. SHEET_TYPE
      .. 'sheetMetadata+xml"/>'
    files['xl/metadata.xml'] = XML_HEAD .. METADATA
  end

  files['[Content_Types].xml'] = table.concat ({
    XML_HEAD,
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">',
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>',
    '<Default Extension="xml" ContentType="application/xml"/>',
    defaults_xml (default_types),
    '<Override PartName="/xl/workbook.xml" ContentType="'
      .. SHEET_TYPE
      .. 'sheet.main+xml"/>',
    table.concat (type_entries),
    '<Override PartName="/xl/styles.xml" ContentType="'
      .. SHEET_TYPE
      .. 'styles+xml"/>',
    '<Override PartName="/xl/sharedStrings.xml" ContentType="'
      .. SHEET_TYPE
      .. 'sharedStrings+xml"/>',
    '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>',
    '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>',
    '</Types>',
  })
  files['_rels/.rels'] = table.concat ({
    XML_HEAD,
    '<Relationships xmlns="' .. NS_PACKAGE .. '">',
    '<Relationship Id="rId1" Type="'
      .. NS_REL
      .. '/officeDocument" Target="xl/workbook.xml"/>',
    '<Relationship Id="rId2" Type="'
      .. 'http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties'
      .. '" Target="docProps/core.xml"/>',
    '<Relationship Id="rId3" Type="'
      .. NS_REL
      .. '/extended-properties" Target="docProps/app.xml"/>',
    '</Relationships>',
  })
  files['docProps/app.xml'] = XML_HEAD
    .. '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">'
    .. '<Application>Proteus</Application></Properties>'
  files['docProps/core.xml'] = XML_HEAD
    .. '<cp:coreProperties'
    .. ' xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties"'
    .. ' xmlns:dc="http://purl.org/dc/elements/1.1/"'
    .. ' xmlns:dcterms="http://purl.org/dc/terms/"'
    .. ' xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
    .. '<dc:creator>Proteus</dc:creator></cp:coreProperties>'
  -- The file asks Excel to work out every formula again on opening, since the cached values
  -- came from this app.
  local defined = {} ---@type string[]
  for _, entry in ipairs (filter_names) do
    defined[#defined + 1] = entry
  end
  for _, entry in ipairs (type (book.names) == 'table' and book.names or {}) do
    if
      type (entry) == 'table'
      and type (entry.name) == 'string'
      and formula.is_formula (entry.formula)
    then
      local text = entry.formula
      for _, pair in ipairs (renames) do
        text = formula.rename_sheet (text, pair[1], pair[2])
      end
      defined[#defined + 1] = '<definedName name="'
        .. attr (entry.name)
        .. '">'
        .. formula_text (to_excel (string.sub (text, 2)))
        .. '</definedName>'
    end
  end
  files['xl/workbook.xml'] = table.concat ({
    XML_HEAD,
    '<workbook xmlns="' .. NS_MAIN .. '" xmlns:r="' .. NS_REL .. '">',
    '<bookViews><workbookView activeTab="' .. (active - 1) .. '"/></bookViews>',
    '<sheets>',
    table.concat (sheet_entries),
    '</sheets>',
    #defined > 0
        and '<definedNames>' .. table.concat (defined) .. '</definedNames>'
      or '',
    '<calcPr fullCalcOnLoad="1"/>',
    '</workbook>',
  })
  files['xl/_rels/workbook.xml.rels'] = table.concat ({
    XML_HEAD,
    '<Relationships xmlns="' .. NS_PACKAGE .. '">',
    table.concat (rel_entries),
    '</Relationships>',
  })
  files['xl/styles.xml'] = styles_xml (w.styles)
  files['xl/sharedStrings.xml'] = strings_xml (w.strings)
  return files, warnings
end
M.argb = argb
M.format_id_of = format_id_of

return M
