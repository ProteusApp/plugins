-- sheet_xlsx_read: reading Excel files for the Sheet app. `read` turns the XML files inside an
-- `.xlsx` zip into workbook data: cells and their formulas, styles, sizes, merges and the parts
-- sheet_xlsx_parts reads, with a warning for each thing that does not come across. It also
-- holds what reading and writing share: Excel's built-in formats, colours and borders, and the
-- formula text Excel writes. The module draws nothing and calls no host function.

local format = require ('sheet_format') --[[@as Sheet.FormatModule]]
local formula = require ('sheet_formula') --[[@as Sheet.FormulaModule]]
local sheet_parts = require ('sheet_xlsx_parts') --[[@as Sheet.XlsxPartsModule]]
local xml_mod = require ('sheet_xml') --[[@as Sheet.XmlModule]]

---@class Sheet.XlsxReadModule
local M = {}
local bare, child, children, prefixed =
  xml_mod.bare, xml_mod.child, xml_mod.children, xml_mod.prefixed
local flag, int = xml_mod.flag, xml_mod.int

local DEFAULT_ROWS = 100
local DEFAULT_COLS = 26
-- The app's own column width and font size, in pixels. A column or a font at Excel's default
-- size reads in at the app's default size. Writing does the reverse.
local APP_WIDTH = 100
local APP_SIZE = 13
-- Excel's standard column is 64 pixels. Stored widths count characters of 7 pixels, padding
-- included, so pixels are the width times 7.
local EXCEL_WIDTH = 64
local CHAR_PX = 7
local MAX_ROWS = 1048576
local MAX_COLS = 16384
-- A `<col>` range that reaches this far means the rest of the sheet. A row past this that
-- holds only a height, a hidden flag or a style counts only up to the last row with cells, so
-- one styled row at the bottom of the sheet does not make a sheet of a million rows.
local REST_OF_SHEET = 1000
-- Excel counts dates in a 1904 workbook from 1904-01-01, 1462 days after this app's day 0.
local DAYS_1904 = 1462
-- The helpers sheet_xlsx_parts uses, which sheet_xlsx fills in once the writer has loaded.
---@type Sheet.XlsxKit
---@diagnostic disable-next-line: missing-fields
local KIT = {}

-- Excel's built-in number formats, as US Excel shows them. The ids it leaves out show as
-- General.
---@type table<integer, string>
local BUILTIN_FORMATS = {
  [1] = '0',
  [2] = '0.00',
  [3] = '#,##0',
  [4] = '#,##0.00',
  [5] = '$#,##0_);($#,##0)',
  [6] = '$#,##0_);[Red]($#,##0)',
  [7] = '$#,##0.00_);($#,##0.00)',
  [8] = '$#,##0.00_);[Red]($#,##0.00)',
  [9] = '0%',
  [10] = '0.00%',
  [11] = '0.00E+00',
  [12] = '# ?/?',
  [13] = '# ??/??',
  [14] = 'm/d/yyyy',
  [15] = 'd-mmm-yy',
  [16] = 'd-mmm',
  [17] = 'mmm-yy',
  [18] = 'h:mm AM/PM',
  [19] = 'h:mm:ss AM/PM',
  [20] = 'h:mm',
  [21] = 'h:mm:ss',
  [22] = 'm/d/yyyy h:mm',
  [37] = '#,##0 ;(#,##0)',
  [38] = '#,##0 ;[Red](#,##0)',
  [39] = '#,##0.00;(#,##0.00)',
  [40] = '#,##0.00;[Red](#,##0.00)',
  [41] = '_(* #,##0_);_(* \\(#,##0\\);_(* "-"_);_(@_)',
  [42] = '_("$"* #,##0_);_("$"* \\(#,##0\\);_("$"* "-"_);_(@_)',
  [43] = '_(* #,##0.00_);_(* \\(#,##0.00\\);_(* "-"??_);_(@_)',
  [44] = '_("$"* #,##0.00_);_("$"* \\(#,##0.00\\);_("$"* "-"??_);_(@_)',
  [45] = 'mm:ss',
  [46] = '[h]:mm:ss',
  [47] = 'mmss.0',
  [48] = '##0.0E+0',
  [49] = '@',
}

---@type table<string, integer>
local BUILTIN_IDS = {}
for id, code in pairs (BUILTIN_FORMATS) do
  BUILTIN_IDS[code] = id
end

-- The colours of the standard Office theme, in the order Excel numbers them. That order
-- differs from the theme file's, so 0 is the light background and 1 is the dark text.
local OFFICE_THEME = {
  'FFFFFF',
  '000000',
  'E7E6E6',
  '44546A',
  '4472C4',
  'ED7D31',
  'A5A5A5',
  'FFC000',
  '5B9BD5',
  '70AD47',
  '0563C1',
  '954F72',
}
local THEME_SLOTS = {
  'lt1',
  'dk1',
  'lt2',
  'dk2',
  'accent1',
  'accent2',
  'accent3',
  'accent4',
  'accent5',
  'accent6',
  'hlink',
  'folHlink',
}

-- The legacy palette that `indexed` colours count into. 64 and 65 are the system colours,
-- which read as automatic.
local INDEXED = {} ---@type string[]
for hex in
  string.gmatch (
    '000000 FFFFFF FF0000 00FF00 0000FF FFFF00 FF00FF 00FFFF '
      .. '000000 FFFFFF FF0000 00FF00 0000FF FFFF00 FF00FF 00FFFF '
      .. '800000 008000 000080 808000 800080 008080 C0C0C0 808080 '
      .. '9999FF 993366 FFFFCC CCFFFF 660066 FF8080 0066CC CCCCFF '
      .. '000080 FF00FF FFFF00 00FFFF 800080 800000 008080 0000FF '
      .. '00CCFF CCFFFF CCFFCC FFFF99 99CCFF FF99CC CC99FF FFCC99 '
      .. '3366FF 33CCCC 99CC00 FFCC00 FF9900 FF6600 666699 969696 '
      .. '003366 339966 003300 333300 993300 993366 333399 333333',
    '%x+'
  )
do
  INDEXED[#INDEXED + 1] = hex
end

-- Excel's border styles, and the nearest one this app draws.
---@type table<string, string>
local BORDER_READ = {
  thin = 'thin',
  medium = 'medium',
  thick = 'thick',
  dashed = 'dashed',
  dotted = 'dotted',
  double = 'double',
  hair = 'thin',
  mediumDashed = 'dashed',
  dashDot = 'dashed',
  mediumDashDot = 'dashed',
  dashDotDot = 'dotted',
  mediumDashDotDot = 'dotted',
  slantDashDot = 'dashed',
}
local SIDES = { 'top', 'right', 'bottom', 'left' }

---@type table<string, 'left'|'center'|'right'>
local ALIGN_READ = {
  left = 'left',
  center = 'center',
  right = 'right',
  fill = 'left',
  justify = 'left',
  centerContinuous = 'center',
  distributed = 'center',
}
---@type table<string, 'top'|'middle'>
local VALIGN_READ = {
  top = 'top',
  center = 'middle',
  justify = 'middle',
  distributed = 'middle',
}

-- Functions newer than Excel 2007. A file names them with a `_xlfn.` prefix, or Excel shows
-- #NAME? until the cell is entered again.
---@type table<string, string>
local NEWER_FUNCTIONS = {}
for name in
  string.gmatch (
    'ACOT ACOTH AGGREGATE ARABIC BASE BETA.DIST BETA.INV BINOM.DIST BINOM.DIST.RANGE '
      .. 'BINOM.INV BITAND BITLSHIFT BITOR BITRSHIFT BITXOR CEILING.MATH CEILING.PRECISE '
      .. 'CHISQ.DIST CHISQ.DIST.RT CHISQ.INV CHISQ.INV.RT CHISQ.TEST CHOOSECOLS CHOOSEROWS '
      .. 'COMBINA CONCAT CONFIDENCE.NORM CONFIDENCE.T COT COTH COVARIANCE.P COVARIANCE.S '
      .. 'CSC CSCH DAYS DECIMAL DROP ERF.PRECISE ERFC.PRECISE EXPAND EXPON.DIST F.DIST '
      .. 'F.DIST.RT F.INV F.INV.RT F.TEST FILTERXML FLOOR.MATH FLOOR.PRECISE FORECAST.LINEAR '
      .. 'FORMULATEXT GAMMA GAMMA.DIST GAMMA.INV GAMMALN.PRECISE GAUSS HSTACK HYPGEOM.DIST '
      .. 'IFNA IFS IMCOSH IMCOT IMCSC IMCSCH IMSEC IMSECH IMSINH IMTAN ISFORMULA ISOWEEKNUM '
      .. 'LAMBDA LET LOGNORM.DIST LOGNORM.INV MAXIFS MINIFS MODE.MULT MODE.SNGL '
      .. 'NEGBINOM.DIST NETWORKDAYS.INTL NORM.DIST NORM.INV NORM.S.DIST NORM.S.INV '
      .. 'NUMBERVALUE PDURATION PERCENTILE.EXC PERCENTILE.INC PERCENTRANK.EXC '
      .. 'PERCENTRANK.INC PERMUTATIONA PHI POISSON.DIST QUARTILE.EXC QUARTILE.INC RANDARRAY '
      .. 'RANK.AVG RANK.EQ RRI SEC SECH SEQUENCE SHEET SHEETS SKEW.P SORTBY STDEV.P STDEV.S '
      .. 'SWITCH T.DIST T.DIST.2T T.DIST.RT T.INV T.INV.2T T.TEST TAKE TEXTAFTER TEXTBEFORE '
      .. 'TEXTJOIN TEXTSPLIT TOCOL TOROW UNICHAR UNICODE UNIQUE VALUETOTEXT VAR.P VAR.S '
      .. 'VSTACK WEIBULL.DIST WORKDAY.INTL WRAPCOLS WRAPROWS XLOOKUP XMATCH XOR Z.TEST',
    '%S+'
  )
do
  NEWER_FUNCTIONS[name] = '_xlfn.' .. name
end
NEWER_FUNCTIONS.FILTER = '_xlfn._xlws.FILTER'
NEWER_FUNCTIONS.SORT = '_xlfn._xlws.SORT'
for name in string.gmatch ('MAP REDUCE SCAN BYROW BYCOL MAKEARRAY', '%S+') do
  NEWER_FUNCTIONS[name] = '_xlfn.' .. name
end

---@param x number
---@return integer
local function round (x)
  return math.floor (x + 0.5)
end

---------------------------------------------------------------------------------------------
-- Formula text
---------------------------------------------------------------------------------------------

---Runs `fn` over the parts of a formula outside quotes. Text in double quotes and sheet names
---in single quotes stay as they are. A doubled quote inside quotes stands for one quote.
---@param text string
---@param fn fun(part: string): string
---@return string
local function outside_quotes (text, fn)
  local out = {} ---@type string[]
  local i = 1
  local n = #text
  while i <= n do
    local q = string.find (text, '["\']', i)
    if not q then
      out[#out + 1] = fn (string.sub (text, i))
      break
    end
    out[#out + 1] = fn (string.sub (text, i, q - 1))
    local mark = string.sub (text, q, q)
    local j = q + 1
    local stop = n
    while true do
      local e = string.find (text, mark, j, true)
      if not e then
        break
      end
      if string.sub (text, e + 1, e + 1) ~= mark then
        stop = e
        break
      end
      j = e + 2
    end
    out[#out + 1] = string.sub (text, q, stop)
    i = stop + 1
  end
  return table.concat (out)
end

---@param part string
---@return string
local function drop_prefixes (part)
  if not string.find (part, '_xl', 1, true) then
    return part
  end
  local out = string.gsub (part, '_xlfn%.', '')
  out = string.gsub (out, '_xlws%.', '')
  -- The names LET and LAMBDA give carry `_xlpm.`.
  out = string.gsub (out, '_xlpm%.', '')
  return out
end

---@param part string
---@return string
local function add_prefixes (part)
  return (
    string.gsub (part, '([%a_][%w_%.]*)%(', function (name)
      local full = NEWER_FUNCTIONS[string.upper (name)]
      return full and (full .. '(') or nil
    end)
  )
end

---Turns formula text as Excel stores it into formula text as this app writes it.
---@param text string
---@return string
local function from_excel (text)
  local out = outside_quotes (text, drop_prefixes)
  -- Excel writes the block a formula spills, A1#, as ANCHORARRAY(A1).
  if string.find (out, 'ANCHORARRAY(', 1, true) then
    out = string.gsub (out, 'ANCHORARRAY%(([^()"]-)%)', '%1#')
  end
  return out
end

---The names in a formula that LET and LAMBDA give, which Excel marks with `_xlpm.`, and the
---blocks a formula spills, A1#, which Excel writes as ANCHORARRAY(A1).
---@param text string Formula text without its "=".
---@return string
local function excel_names (text)
  if
    not string.find (text, '#', 1, true)
    and not string.find (string.upper (text), 'L[EA][TM]')
  then
    return text
  end
  local tokens = formula.tokenize ('=' .. text, 2)
  if not tokens then
    return text
  end
  local known = {} ---@type table<string, boolean>
  for _, name in ipairs (formula.functions) do
    known[name] = true
  end
  local parts = {} ---@type string[]
  local pos = 1
  for i, t in ipairs (tokens) do
    local new = nil ---@type string?
    if t.kind == 'name' then
      local up = string.upper (t.text)
      local after = tokens[i + 1]
      local call = after and after.kind == 'open'
      if up ~= 'TRUE' and up ~= 'FALSE' and not (call and known[up]) then
        new = '_xlpm.' .. t.text
      end
    elseif t.kind == 'ref' and t.spill then
      new = '_xlfn.ANCHORARRAY(' .. string.sub (t.text, 1, -2) .. ')'
    end
    if new then
      -- Tokens count bytes of the text with its "=", one more than here.
      parts[#parts + 1] = string.sub (text, pos, t.from - 2)
      parts[#parts + 1] = new
      pos = t.to
    end
  end
  parts[#parts + 1] = string.sub (text, pos)
  return table.concat (parts)
end

---Turns formula text as this app writes it into formula text as Excel stores it.
---@param text string
---@return string
local function to_excel (text)
  return outside_quotes (excel_names (text), add_prefixes)
end

---True when formula text as Excel stores it reads another workbook, as `[1]Sheet1!A1` does.
---@param text string
---@return boolean
local function external (text)
  local found = false
  outside_quotes (string.gsub (text, "'", ''), function (part)
    if string.find (part, '%[%d+%]') then
      found = true
    end
    return part
  end)
  return found
end

---------------------------------------------------------------------------------------------
-- Reading the workbook
---------------------------------------------------------------------------------------------

---Joins a relationship target onto the folder of the part that names it.
---@param base string The part the target is relative to, such as `xl/workbook.xml`.
---@param target string
---@return string
local function resolve (base, target)
  local parts = {} ---@type string[]
  if string.sub (target, 1, 1) ~= '/' then
    for seg in string.gmatch (base, '[^/]+') do
      parts[#parts + 1] = seg
    end
    parts[#parts] = nil
  end
  for seg in string.gmatch (target, '[^/]+') do
    if seg == '..' then
      parts[#parts] = nil
    elseif seg ~= '.' then
      parts[#parts + 1] = seg
    end
  end
  return table.concat (parts, '/')
end

---@param src Sheet.XlsxSource
---@param path string
---@return string?
local function part_text (src, path)
  local text = src.files[path]
  if text == nil then
    local real = src.lower[string.lower (path)]
    text = real and src.files[real]
  end
  return text
end

---Parses a part. Returns nil when it is missing, and nil and a message when it is damaged.
---@param src Sheet.XlsxSource
---@param path string
---@return Sheet.XmlNode?
---@return string?
local function part_xml (src, path)
  local text = part_text (src, path)
  if not text then
    return nil
  end
  local root, err = xml_mod.parse_xml (text)
  if not root then
    return nil, path .. ': ' .. tostring (err)
  end
  return root
end

---The relationships of a part, by id and in order. A missing or damaged list is empty.
---@param src Sheet.XlsxSource
---@param part string
---@return table<string, Sheet.XlsxRel>
---@return Sheet.XlsxRel[]
local function rels_of (src, part)
  local by_id = {} ---@type table<string, Sheet.XlsxRel>
  local list = {} ---@type Sheet.XlsxRel[]
  local dir, file = string.match (part, '^(.-)([^/]*)$')
  local root = part_xml (src, dir .. '_rels/' .. file .. '.rels')
  for _, node in ipairs (children (root, 'Relationship')) do
    local a = node.attrs
    if a.Id and a.Target and a.TargetMode ~= 'External' then
      ---@type Sheet.XlsxRel
      local rel = {
        type = string.match (a.Type or '', '([^/]*)$'),
        target = resolve (part, a.Target),
      }
      by_id[a.Id] = rel
      list[#list + 1] = rel
    end
  end
  return by_id, list
end

---@param rels Sheet.XlsxRel[]
---@param kind string
---@return string?
local function target_of (rels, kind)
  for _, rel in ipairs (rels) do
    if rel.type == kind then
      return rel.target
    end
  end
  return nil
end

---The theme colours of the file, or of the standard Office theme where it has none.
---@param root Sheet.XmlNode?
---@return string[]
local function theme_colors (root)
  local out = {} ---@type string[]
  local scheme = child (child (root, 'themeElements'), 'clrScheme')
  for i, slot in ipairs (THEME_SLOTS) do
    local node = child (scheme, slot)
    local rgb = child (node, 'srgbClr')
    local sys = child (node, 'sysClr')
    local hex = (rgb and rgb.attrs.val) or (sys and sys.attrs.lastClr)
    if hex and string.match (hex, '^%x%x%x%x%x%x$') then
      out[i] = string.upper (hex)
    else
      out[i] = OFFICE_THEME[i]
    end
  end
  return out
end

---@param p number
---@param q number
---@param t number
---@return number
local function hue (p, q, t)
  if t < 0 then
    t = t + 1
  elseif t > 1 then
    t = t - 1
  end
  if t < 1 / 6 then
    return p + (q - p) * 6 * t
  elseif t < 1 / 2 then
    return q
  elseif t < 2 / 3 then
    return p + (q - p) * (2 / 3 - t) * 6
  end
  return p
end

---Lightens a colour for a positive tint and darkens it for a negative one, the way Excel
---shades theme colours such as "Blue, Accent 1, Lighter 80%".
---@param hex string
---@param tint number
---@return string
local function shade (hex, tint)
  local r = (tonumber (string.sub (hex, 1, 2), 16) or 0) / 255
  local g = (tonumber (string.sub (hex, 3, 4), 16) or 0) / 255
  local b = (tonumber (string.sub (hex, 5, 6), 16) or 0) / 255
  local hi = math.max (r, g, b)
  local lo = math.min (r, g, b)
  local l = (hi + lo) / 2 ---@type number
  local h, s = 0, 0 ---@type number, number
  if hi ~= lo then
    local d = hi - lo
    s = l > 0.5 and d / (2 - hi - lo) or d / (hi + lo)
    if hi == r then
      h = (g - b) / d + (g < b and 6 or 0)
    elseif hi == g then
      h = (b - r) / d + 2
    else
      h = (r - g) / d + 4
    end
    h = h / 6
  end
  if tint < 0 then
    l = l * (1 + tint)
  else
    l = l * (1 - tint) + tint
  end
  if s == 0 then
    r, g, b = l, l, l
  else
    local q = l < 0.5 and l * (1 + s) or l + s - l * s
    local p = 2 * l - q
    r, g, b = hue (p, q, h + 1 / 3), hue (p, q, h), hue (p, q, h - 1 / 3)
  end
  return string.format (
    '%02X%02X%02X',
    round (r * 255),
    round (g * 255),
    round (b * 255)
  )
end

---A colour element as `#rrggbb`, or nil for automatic.
---@param node Sheet.XmlNode?
---@param theme string[]
---@return string?
local function color_of (node, theme)
  if not node then
    return nil
  end
  local a = node.attrs
  local hex ---@type string?
  if a.rgb then
    hex = string.match (a.rgb, '(%x%x%x%x%x%x)$')
  elseif a.theme then
    hex = theme[(int (a.theme) or -1) + 1]
  elseif a.indexed then
    hex = INDEXED[(int (a.indexed) or -1) + 1]
  end
  if not hex then
    return nil
  end
  local tint = tonumber (a.tint)
  if tint and tint ~= 0 then
    hex = shade (hex, math.max (-1, math.min (1, tint)))
  end
  return '#' .. string.lower (hex)
end

---Every style field in a fixed order, for comparing and for keys.
local STYLE_FIELDS = {
  'bold',
  'italic',
  'underline',
  'strike',
  'size',
  'color',
  'fill',
  'align',
  'valign',
  'wrap',
  'format',
  'border_top',
  'border_right',
  'border_bottom',
  'border_left',
  'border_color',
}

---@param style table
---@return boolean
local function is_empty (style)
  return next (style) == nil
end

---A cell style as Excel's lists describe it, before it is compared with the default. The
---size stays in points here.
---@param xf Sheet.XmlNode
---@param lists { fonts: Sheet.XmlNode[], fills: Sheet.XmlNode[], borders: Sheet.XmlNode[], formats: table<integer, string> }
---@param theme string[]
---@return table<string, any>
local function raw_style (xf, lists, theme)
  local out = {} ---@type table<string, any>
  local font = lists.fonts[(int (xf.attrs.fontId) or 0) + 1]
  if font then
    for _, key in ipairs ({ 'b', 'i', 'strike' }) do
      local node = child (font, key)
      if node and flag (node.attrs.val) then
        out[key == 'b' and 'bold' or key == 'i' and 'italic' or 'strike'] = true
      end
    end
    local u = child (font, 'u')
    if u and u.attrs.val ~= 'none' then
      out.underline = true
    end
    local sz = child (font, 'sz')
    out.size = sz and tonumber (sz.attrs.val) or nil
    out.color = color_of (child (font, 'color'), theme)
  end
  local fill =
    child (lists.fills[(int (xf.attrs.fillId) or 0) + 1], 'patternFill')
  if fill and fill.attrs.patternType == 'solid' then
    out.fill = color_of (child (fill, 'fgColor'), theme)
      or color_of (child (fill, 'bgColor'), theme)
  end
  local border = lists.borders[(int (xf.attrs.borderId) or 0) + 1]
  if border then
    local line_color = nil ---@type string?
    for _, side in ipairs (SIDES) do
      local node = child (border, side)
      if not node and side == 'left' then
        node = child (border, 'start')
      elseif not node and side == 'right' then
        node = child (border, 'end')
      end
      local kind = node and BORDER_READ[node.attrs.style or '']
      if node and kind then
        out['border_' .. side] = kind
        line_color = line_color or color_of (child (node, 'color'), theme)
      end
    end
    out.border_color = line_color
  end
  local align = child (xf, 'alignment')
  if align then
    out.align = ALIGN_READ[align.attrs.horizontal or '']
    out.valign = VALIGN_READ[align.attrs.vertical or '']
    if align.attrs.wrapText and flag (align.attrs.wrapText) then
      out.wrap = true
    end
  end
  local id = int (xf.attrs.numFmtId) or 0
  local code = lists.formats[id] or BUILTIN_FORMATS[id]
  if code and string.lower (code) ~= 'general' then
    out.format = code
  end
  return out
end

---Reads `styles.xml` into one style per `s` number, keeping only what differs from style 0.
---@param root Sheet.XmlNode?
---@param theme string[]
---@param date1904 boolean
---@return table<integer, Sheet.Style> styles
---@return table<integer, boolean> dates
local function read_styles (root, theme, date1904)
  local formats = {} ---@type table<integer, string>
  for _, node in ipairs (children (child (root, 'numFmts'), 'numFmt')) do
    local id = int (node.attrs.numFmtId)
    if id and node.attrs.formatCode then
      formats[id] = node.attrs.formatCode
    end
  end
  local lists = {
    fonts = children (child (root, 'fonts'), 'font'),
    fills = children (child (root, 'fills'), 'fill'),
    borders = children (child (root, 'borders'), 'border'),
    formats = formats,
  }
  local styles = {} ---@type table<integer, Sheet.Style>
  local dates = {} ---@type table<integer, boolean>
  local xfs = children (child (root, 'cellXfs'), 'xf')
  local base = xfs[1] and raw_style (xfs[1], lists, theme) or {}
  for i, xf in ipairs (xfs) do
    local raw = raw_style (xf, lists, theme)
    local style = {} ---@type table<string, any>
    for _, key in ipairs (STYLE_FIELDS) do
      local v = raw[key]
      if v ~= nil and v ~= base[key] then
        style[key] = v
      end
    end
    if style.size then
      style.size = round (style.size --[[@as number]] * 4 / 3)
    end
    styles[i - 1] = style --[[@as Sheet.Style]]
    local code = raw.format
    if date1904 and type (code) == 'string' then
      local kind = format.kind (code)
      dates[i - 1] = kind == 'date' or kind == 'datetime'
    end
  end
  return styles, dates
end

---The text of a shared or inline string, joining the runs of rich text. Phonetic guides are
---left out. The second value is true when the runs carry their own formatting.
---@param node Sheet.XmlNode
---@return string
---@return boolean
local function string_of (node)
  local parts = {} ---@type string[]
  local rich = false
  for _, c in ipairs (node.children) do
    local name = bare (c.name)
    if name == 't' then
      parts[#parts + 1] = c.text
    elseif name == 'r' then
      local t = child (c, 't')
      parts[#parts + 1] = t and t.text or ''
      rich = rich or child (c, 'rPr') ~= nil
    end
  end
  local text = table.concat (parts)
  -- Excel writes characters XML cannot hold as `_x000D_`, and an underscore that starts such a
  -- sequence as `_x005F_`.
  if string.find (text, '_x', 1, true) then
    text = string.gsub (text, '_x(%x%x%x%x)_', function (h)
      local code = tonumber (h, 16)
      if code >= 0xD800 and code <= 0xDFFF then
        return nil
      end
      if code == 0 then
        return ''
      end
      return utf8.char (code)
    end)
  end
  return text, rich
end

---What typing `text` into a cell stores, as `sheet_format` reads it. Plain decimals skip the
---parser. Other text goes through it once, and the cache keeps the answer.
---@param text string
---@param cache table<string, Sheet.XlsxTyped>
---@return Sheet.Value
---@return string?
local function parse_input (text, cache)
  if
    string.match (text, '^%-?%d+$') or string.match (text, '^%-?%d+%.%d+$')
  then
    return (tonumber (text) or 0) + 0.0
  end
  local hit = cache[text]
  if not hit then
    local value, code = format.parse_input (text)
    hit = { value = value, code = code }
    cache[text] = hit
  end
  return hit.value, hit.code
end

---Cell text as a user would type it to get this text back. A string that would read as a
---number, a date, a formula or anything else but text gets a leading `'`.
---@param s string
---@param cache table<string, Sheet.XlsxTyped>
---@return string
local function typed_text (s, cache)
  local first = string.sub (s, 1, 1)
  if first == '=' or first == "'" then
    return "'" .. s
  end
  local value = parse_input (s, cache)
  if type (value) ~= 'string' or value ~= s then
    return "'" .. s
  end
  return s
end

---A number from a file as cell text, with the 15 significant digits Excel shows, so float
---noise such as 0.30000000000000004 reads as 0.3.
---@param n number
---@return string
local function read_number (n)
  if n ~= n or n == math.huge or n == -math.huge then
    return '#NUM!'
  end
  if n == math.floor (n) and math.abs (n) < 2 ^ 53 then
    return string.format ('%d', n)
  end
  return string.format ('%.15g', n)
end

---A number as file text, as short as it can be without changing the number.
---@param n number
---@return string
local function number_text (n)
  if n ~= n or n == math.huge or n == -math.huge then
    return '#NUM!'
  end
  if n == math.floor (n) and math.abs (n) < 2 ^ 53 then
    return string.format ('%d', n)
  end
  for digits = 15, 16 do
    local s = string.format ('%.' .. digits .. 'g', n)
    if tonumber (s) == n then
      return s
    end
  end
  return string.format ('%.17g', n)
end

---A date written as `2026-09-29T14:30:00` as a serial number.
---@param text string
---@return number?
local function iso_date (text)
  local y, m, d = string.match (text, '^(%d%d%d%d)%-(%d%d)%-(%d%d)')
  if not y then
    return nil
  end
  local h, mi, s = string.match (text, 'T(%d%d):(%d%d):?(%d*)')
  return formula.serial (
    int (y) or 1900,
    int (m) or 1,
    int (d) or 1,
    int (h) or 0,
    int (mi) or 0,
    int (s) or 0
  )
end

---@param a? Sheet.Style
---@param b? Sheet.Style
---@return Sheet.Style?
local function overlay (a, b)
  if not a then
    return b
  end
  if not b then
    return a
  end
  local out = {} ---@type table<string, any>
  for k, v in
    pairs (a --[[@as table<string, any>]])
  do
    out[k] = v
  end
  for k, v in
    pairs (b --[[@as table<string, any>]])
  do
    out[k] = v
  end
  return out --[[@as Sheet.Style]]
end

---A cell's own style, which holds the fields where its full style differs from its row and
---column. When the row or column is bold and the cell is not, the cell gets `bold = false`,
---and a number format resets to General. Returns a fresh table, or nil when nothing differs.
---@param full? Sheet.Style
---@param base? Sheet.Style
---@return Sheet.Style?
local function own_style (full, base)
  if not base and (not full or is_empty (full)) then
    return nil
  end
  local out = {} ---@type table<string, any>
  local f = (full or {}) --[[@as table<string, any>]]
  local b = (base or {}) --[[@as table<string, any>]]
  for _, key in ipairs (STYLE_FIELDS) do
    local v = f[key]
    if v ~= nil and v ~= b[key] then
      out[key] = v
    elseif v == nil and b[key] == true then
      out[key] = false
    elseif v == nil and key == 'format' and b[key] ~= nil then
      out[key] = 'General'
    end
  end
  if is_empty (out) then
    return nil
  end
  return out --[[@as Sheet.Style]]
end

---@param warnings string[]
---@param seen table<string, boolean>
---@param kind string
---@param text string
local function warn_once (warnings, seen, kind, text)
  if not seen[kind] then
    seen[kind] = true
    warnings[#warnings + 1] = text
  end
end

-- What a sheet may hold that this app leaves out, in the order the warnings list them.
local LEFT_OUT = {
  { 'charts', 'Charts in %s that this app cannot show were left out.' },
  { 'pictures', 'Pictures in %s were left out.' },
  { 'shapes', 'Shapes in %s were left out.' },
  {
    'conditional',
    'Conditional formats in %s that this app cannot show were left out.',
  },
  {
    'validation',
    'Data validation in %s that this app cannot check was left out.',
  },
  { 'filter', 'Filter tests in %s that this app cannot apply were left out.' },
  { 'tables', 'Table styles in %s were left out.' },
  {
    'pivots',
    'Pivot tables in %s were left out. Their last values are kept.',
  },
  { 'sparklines', 'Sparklines in %s were left out.' },
  { 'protection', 'Protection in %s was left out.' },
  { 'rich', 'Mixed text formatting inside cells in %s was left out.' },
  {
    'external',
    'Formulas in %s that read other workbooks were left out. Their last values are kept.',
  },
  {
    'outside',
    'Cells in %s past row 1048576 or column XFD were left out.',
  },
}

-- Worksheet elements that mean a feature is there, at the top of the sheet and inside its
-- extension lists. Newer conditional formats and validation sit in the extension lists,
-- where the app does not read them.
---@type table<string, string>
local FEATURE_TAGS = {
  tableParts = 'tables',
  sheetProtection = 'protection',
}
---@type table<string, string>
local EXT_TAGS = {
  conditionalFormattings = 'conditional',
  dataValidations = 'validation',
  sparklineGroups = 'sparklines',
}

---Finds the features a sheet holds that this app leaves out.
---@param src Sheet.XlsxSource
---@param root Sheet.XmlNode
---@param path string
---@param found table<string, boolean>
local function find_features (src, root, path, found)
  -- Newer features sit inside extension lists, so the search looks inside those too.
  local stack = { root } ---@type Sheet.XmlNode[]
  while #stack > 0 do
    local node = stack[#stack]
    stack[#stack] = nil
    for _, c in ipairs (node.children) do
      local name = bare (c.name)
      local kind = EXT_TAGS[name]
      if node == root then
        kind = FEATURE_TAGS[name]
      end
      if kind then
        found[kind] = true
      elseif name == 'extLst' or name == 'ext' then
        stack[#stack + 1] = c
      end
    end
  end
  local _, rels = rels_of (src, path)
  for _, rel in ipairs (rels) do
    if rel.type == 'pivotTable' then
      found.pivots = true
    elseif rel.type == 'table' then
      found.tables = true
    end
  end
end

---Reads one worksheet into sheet data.
---@param src Sheet.XlsxSource
---@param path string
---@param name string
---@param book Sheet.XlsxBook
---@param warnings string[]
---@return Sheet.SheetData?
local function read_sheet (src, path, name, book, warnings)
  local root = part_xml (src, path)
  if not root then
    return nil
  end
  local found = {} ---@type table<string, boolean>
  local cells = {} ---@type table<string, string>
  local styles = {} ---@type table<string, Sheet.Style>
  local row_styles = {} ---@type table<string, Sheet.Style>
  local heights = {} ---@type table<string, number>
  local hidden_rows = {} ---@type integer[]
  local max_row, max_col = 0, 0

  local format_pr = child (root, 'sheetFormatPr')
  local default_width = EXCEL_WIDTH
  local base_width = format_pr and tonumber (format_pr.attrs.defaultColWidth)
  if base_width then
    default_width = round (base_width * CHAR_PX)
  end

  local cols = {} ---@type Sheet.XlsxCol[]
  for _, node in ipairs (children (child (root, 'cols'), 'col')) do
    local a = node.attrs
    local lo, hi = int (a.min), int (a.max)
    if lo and hi and lo >= 1 and hi >= lo then
      local width = tonumber (a.width)
      local px = width and round (width * CHAR_PX)
      local style = book.xf_styles[int (a.style) or 0]
      cols[#cols + 1] = {
        min = lo,
        max = math.min (hi, MAX_COLS),
        width = px ~= default_width and px or nil,
        hidden = a.hidden ~= nil and flag (a.hidden),
        style = style and not is_empty (style) and style or nil,
      }
    end
  end

  ---@param col integer
  ---@return Sheet.Style?
  local function col_style (col)
    for _, def in ipairs (cols) do
      if def.style and col >= def.min and col <= def.max then
        return def.style
      end
    end
    return nil
  end

  local shared = {} ---@type table<string, { row: integer, col: integer, text: string }>
  local waiting = {} ---@type Sheet.XlsxShared[]
  -- Array formulas and the blocks they cover, whose other cells hold the last values.
  local arrays = {} ---@type { row: integer, col: integer, ref: string }[]
  local last_row = 0 ---@type integer
  local styled_rows = {} ---@type integer[]
  for _, row in ipairs (children (child (root, 'sheetData'), 'row')) do
    local a = row.attrs
    local r = int (a.r) or last_row + 1 ---@type integer
    last_row = r
    -- A row past the last row of a sheet is left out.
    if r >= 1 and r <= MAX_ROWS then
      local key = string.format ('%d', r)
      local ht = tonumber (a.ht)
      local touched = false
      if ht and a.customHeight and flag (a.customHeight) then
        heights[key] = round (ht * 4 / 3)
        touched = true
      end
      if a.hidden and flag (a.hidden) then
        hidden_rows[#hidden_rows + 1] = r
        touched = true
      end
      local row_style = nil ---@type Sheet.Style?
      local rs = int (a.s)
      if rs and a.customFormat and flag (a.customFormat) then
        row_style = book.xf_styles[rs]
        if row_style and not is_empty (row_style) then
          row_styles[key] = own_style (row_style, nil)
          touched = true
        else
          row_style = nil
        end
      end
      if touched then
        styled_rows[#styled_rows + 1] = r
      end
      local last_col = 0 ---@type integer
      for _, c in ipairs (row.children) do
        if bare (c.name) == 'c' then
          local cr, cc = nil, nil ---@type integer?, integer?
          if c.attrs.r then
            cr, cc = formula.parse_address (c.attrs.r)
          end
          if not cr or not cc then
            cr, cc = r, last_col + 1
          end
          ---@cast cc integer
          last_col = cc
          -- A cell past the last row or column of a sheet is left out.
          local outside = cr > MAX_ROWS or cc > MAX_COLS
          local addr = formula.address (cr, cc)
          local t = c.attrs.t or 'n'
          local v = child (c, 'v')
          local f = child (c, 'f')
          local s = int (c.attrs.s) or 0
          local value = nil ---@type string?
          if t == 's' and v then
            local i = int (v.text)
            local text = i and book.strings[i + 1]
            if text and text ~= '' then
              value = typed_text (text, book.typed)
              found.rich = found.rich or book.rich[i + 1] == true
            end
          elseif t == 'inlineStr' then
            local is = child (c, 'is')
            if is then
              local text, rich = string_of (is)
              if text ~= '' then
                value = typed_text (text, book.typed)
                found.rich = found.rich or rich
              end
            end
          elseif t == 'b' and v then
            value = v.text == '1' and 'TRUE' or 'FALSE'
          elseif t == 'e' and v and v.text ~= '' then
            value = v.text
          elseif t == 'str' and v and v.text ~= '' then
            value = typed_text (v.text, book.typed)
          elseif t == 'd' and v then
            local n = iso_date (v.text)
            value = n and read_number (n)
          elseif v and v.text ~= '' then
            local n = tonumber (v.text)
            if n and book.date1904 and book.xf_dates[s] then
              n = n + DAYS_1904
            end
            value = n and read_number (n)
          end
          local text = value
          local kind = f and f.attrs.t
          if f and external (f.text) then
            -- This app cannot read another workbook, so the last value stays.
            found.external = true
            f = nil
          elseif f and kind == 'shared' and f.attrs.si then
            local body = f.text
            if string.find (body, '%S') then
              body = from_excel (body)
              shared[f.attrs.si] = { row = cr, col = cc, text = body }
              text = '=' .. body
            else
              waiting[#waiting + 1] = {
                addr = addr,
                row = cr,
                col = cc,
                si = f.attrs.si,
                value = value,
              }
            end
          elseif f and kind ~= 'dataTable' and string.find (f.text, '%S') then
            text = '=' .. from_excel (f.text)
            if kind == 'array' and f.attrs.ref and not outside then
              arrays[#arrays + 1] = { row = cr, col = cc, ref = f.attrs.ref }
            end
          end
          local style =
            own_style (book.xf_styles[s], overlay (col_style (cc), row_style))
          if outside then
            found.outside = true
          elseif text or style or f then
            cells[addr] = text
            styles[addr] = style
            max_row = math.max (max_row, cr)
            max_col = math.max (max_col, cc)
          end
        end
      end
    end
  end
  -- Rows that hold only a height, a hidden flag or a style count only up to the last row with
  -- cells, or up to REST_OF_SHEET.
  local last_styled = math.max (max_row, REST_OF_SHEET)
  for _, r in ipairs (styled_rows) do
    if r <= last_styled then
      max_row = math.max (max_row, r)
    else
      local key = string.format ('%d', r)
      heights[key], row_styles[key] = nil, nil
    end
  end
  for i = #hidden_rows, 1, -1 do
    if hidden_rows[i] > last_styled then
      table.remove (hidden_rows, i)
    end
  end
  -- The formula spills its block again, so the values Excel kept for the block's other cells
  -- are left out.
  for _, array in ipairs (arrays) do
    local from, to = string.match (array.ref, '^([^:]+):([^:]+)$')
    local r1, c1 = formula.parse_address (from or '')
    local r2, c2 = formula.parse_address (to or '')
    if r1 and c1 and r2 and c2 then
      for r = math.min (r1, r2), math.min (math.max (r1, r2), MAX_ROWS) do
        for c = math.min (c1, c2), math.min (math.max (c1, c2), MAX_COLS) do
          if r ~= array.row or c ~= array.col then
            local addr = formula.address (r, c)
            local text = cells[addr]
            if text and not formula.is_formula (text) then
              cells[addr] = nil
            end
          end
        end
      end
    end
  end
  for _, cell in ipairs (waiting) do
    local master = shared[cell.si]
    if master then
      cells[cell.addr] = formula.shift (
        '=' .. master.text,
        cell.row - master.row,
        cell.col - master.col
      )
    elseif cell.value then
      cells[cell.addr] = cell.value
    end
  end

  local merges = {} ---@type string[]
  for _, node in ipairs (children (child (root, 'mergeCells'), 'mergeCell')) do
    local ref = node.attrs.ref or ''
    local from, to = string.match (ref, '^([^:]+):([^:]+)$')
    local r1, c1 = formula.parse_address (from or '')
    local r2, c2 = formula.parse_address (to or '')
    if
      r1
      and c1
      and r2
      and c2
      and (r1 ~= r2 or c1 ~= c2)
      and math.max (r1, r2) <= MAX_ROWS
      and math.max (c1, c2) <= MAX_COLS
    then
      merges[#merges + 1] = string.upper (ref)
      max_row = math.max (max_row, r1, r2)
      max_col = math.max (max_col, c1, c2)
    end
  end

  local widths = {} ---@type table<string, number>
  local hidden_cols = {} ---@type string[]
  local col_styles = {} ---@type table<string, Sheet.Style>
  local used_cols = math.max (max_col, DEFAULT_COLS)
  for _, def in ipairs (cols) do
    local last = def.max
    if last >= REST_OF_SHEET then
      last = math.max (def.min, math.min (last, used_cols))
    end
    if def.width or def.hidden or def.style then
      for c = def.min, last do
        local letters = formula.col_name (c)
        widths[letters] = def.width
        if def.hidden then
          hidden_cols[#hidden_cols + 1] = letters
        end
        col_styles[letters] = def.style and own_style (def.style, nil)
      end
      max_col = math.max (max_col, last)
    end
  end
  table.sort (hidden_cols, function (x, y)
    return (formula.col_number (x) or 0) < (formula.col_number (y) or 0)
  end)
  table.sort (hidden_rows)

  ---@type Sheet.SheetData
  local data = {
    name = name,
    rows = math.max (DEFAULT_ROWS, max_row),
    cols = math.max (DEFAULT_COLS, max_col),
    cells = cells,
  }
  if next (widths) then
    data.widths = widths
  end
  if next (heights) then
    data.heights = heights
  end
  if #hidden_rows > 0 then
    data.hidden_rows = hidden_rows
  end
  if #hidden_cols > 0 then
    data.hidden_cols = hidden_cols
  end
  if next (styles) then
    data.styles = styles
  end
  if next (col_styles) then
    data.col_styles = col_styles
  end
  if next (row_styles) then
    data.row_styles = row_styles
  end
  if #merges > 0 then
    data.merges = merges
  end

  local view = child (child (root, 'sheetViews'), 'sheetView')
  local pane = child (view, 'pane')
  local state = pane and pane.attrs.state
  if pane and (state == 'frozen' or state == 'frozenSplit') then
    local frozen_rows = math.floor (tonumber (pane.attrs.ySplit) or 0)
    local frozen_cols = math.floor (tonumber (pane.attrs.xSplit) or 0)
    if frozen_rows > 0 or frozen_cols > 0 then
      data.freeze = {
        rows = frozen_rows > 0 and frozen_rows or nil,
        cols = frozen_cols > 0 and frozen_cols or nil,
      }
    end
  end

  sheet_parts.read (KIT, {
    src = src,
    path = path,
    root = root,
    data = data,
    dxfs = book.dxfs,
    theme = book.theme,
    found = found,
  })
  find_features (src, root, path, found)
  for _, item in ipairs (LEFT_OUT) do
    if found[item[1]] then
      warnings[#warnings + 1] = string.format (item[2], name)
    end
  end
  return data
end

---Reads the files of an `.xlsx` file, each path inside the zip mapped to its text. Returns
---workbook data and a list of warnings about what was left out, or nil and a message.
---@param files table<string, string>
---@return Sheet.BookData?
---@return string[]|string
function M.read (files)
  ---@type Sheet.XlsxSource
  local src = { files = files, lower = {} }
  for path in pairs (files) do
    src.lower[string.lower (path)] = path
  end
  local warnings = {} ---@type string[]
  local seen = {} ---@type table<string, boolean>

  local _, root_rels = rels_of (src, '')
  local wb_path = target_of (root_rels, 'officeDocument') or 'xl/workbook.xml'
  local wb, err = part_xml (src, wb_path)
  if not wb then
    if err then
      return nil, 'The workbook is damaged. ' .. err
    end
    return nil, 'This file is not an Excel workbook.'
  end
  local wb_ids, wb_rels = rels_of (src, wb_path)
  local base = string.match (wb_path, '^(.-)[^/]*$')

  local props = child (wb, 'workbookPr')
  local date1904 = props ~= nil
    and props.attrs.date1904 ~= nil
    and flag (props.attrs.date1904)

  local theme = theme_colors (
    (
      part_xml (
        src,
        target_of (wb_rels, 'theme') or (base .. 'theme/theme1.xml')
      )
    )
  )
  local styles_root, styles_err =
    part_xml (src, target_of (wb_rels, 'styles') or (base .. 'styles.xml'))
  if styles_err then
    return nil, 'The workbook is damaged. ' .. styles_err
  end
  local xf_styles, xf_dates = read_styles (styles_root, theme, date1904)

  local strings = {} ---@type string[]
  local rich = {} ---@type table<integer, boolean>
  local sst, sst_err = part_xml (
    src,
    target_of (wb_rels, 'sharedStrings') or (base .. 'sharedStrings.xml')
  )
  if sst_err then
    return nil, 'The workbook is damaged. ' .. sst_err
  end
  for i, si in ipairs (children (sst, 'si')) do
    local text, is_rich = string_of (si)
    strings[i] = text
    rich[i] = is_rich or nil
  end

  ---@type Sheet.XlsxBook
  local shared = {
    strings = strings,
    rich = rich,
    xf_styles = xf_styles,
    xf_dates = xf_dates,
    date1904 = date1904,
    typed = {},
    dxfs = sheet_parts.read_dxfs (KIT, styles_root, theme),
    theme = theme,
  }

  local view = child (child (wb, 'bookViews'), 'workbookView')
  local active_tab = view and int (view.attrs.activeTab) or 0
  ---@type Sheet.BookData
  local book = { version = 3, active = 1, sheets = {} }
  for i, node in ipairs (children (child (wb, 'sheets'), 'sheet')) do
    local name = node.attrs.name or ('Sheet' .. i)
    local id = prefixed (node, 'id')
    local rel = id and wb_ids[id]
    if rel and rel.type == 'worksheet' then
      local own = {} ---@type string[]
      local data = read_sheet (src, rel.target, name, shared, own)
      if data then
        local state = node.attrs.state
        if state == 'hidden' or state == 'veryHidden' then
          warnings[#warnings + 1] = 'The hidden sheet '
            .. name
            .. ' shows here.'
        end
        for _, text in ipairs (own) do
          warnings[#warnings + 1] = text
        end
        book.sheets[#book.sheets + 1] = data
        if i - 1 == active_tab then
          book.active = #book.sheets
        end
      else
        warnings[#warnings + 1] = 'The sheet '
          .. name
          .. ' could not be read, so it was left out.'
      end
    elseif rel and rel.type == 'chartsheet' then
      warnings[#warnings + 1] = 'The chart sheet ' .. name .. ' was left out.'
    else
      warnings[#warnings + 1] = 'The sheet ' .. name .. ' was left out.'
    end
  end
  if #book.sheets == 0 then
    return nil, 'The workbook has no sheets that can be opened.'
  end
  -- Names for the whole workbook come over. Excel's own, such as the print area, and names
  -- that belong to one sheet or read another workbook are left out.
  local names, taken = {}, {} ---@type Sheet.DefinedName[], table<string, boolean>
  for _, node in ipairs (children (child (wb, 'definedNames'), 'definedName')) do
    local name = node.attrs.name or ''
    local text = node.text or ''
    if string.sub (name, 1, 6) ~= '_xlnm.' then
      local up = string.upper (name)
      if
        node.attrs.localSheetId
        or formula.name_problem (name)
        or taken[up]
        or external (text)
        or not formula.parse ('=' .. from_excel (text))
      then
        warn_once (
          warnings,
          seen,
          'names',
          'Names that belong to one sheet, or that this app cannot read, were left out.'
        )
      else
        taken[up] = true
        names[#names + 1] = { name = name, formula = '=' .. from_excel (text) }
      end
    end
  end
  if #names > 0 then
    book.names = names
  end
  return book, warnings
end

M.APP_SIZE = APP_SIZE
M.APP_WIDTH = APP_WIDTH
M.BUILTIN_IDS = BUILTIN_IDS
M.BORDER_READ = BORDER_READ
M.CHAR_PX = CHAR_PX
M.KIT = KIT
M.MAX_COLS = MAX_COLS
M.MAX_ROWS = MAX_ROWS
M.SIDES = SIDES
M.STYLE_FIELDS = STYLE_FIELDS
M.color_of = color_of
M.from_excel = from_excel
M.is_empty = is_empty
M.number_text = number_text
M.overlay = overlay
M.parse_input = parse_input
M.part_xml = part_xml
M.read_number = read_number
M.resolve = resolve
M.string_of = string_of
M.to_excel = to_excel

return M
