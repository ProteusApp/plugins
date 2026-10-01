-- sheet_xlsx: Excel files for the Sheet app. `read` turns the XML files inside an `.xlsx` zip
-- into workbook data, and `write` turns workbook data back into those files. The host does the
-- zipping. The module draws nothing and calls no host function.
--
-- An Excel file can hold more than a workbook file keeps. Whatever does not come across, such
-- as charts or conditional formats, is named in a list of warnings.

local format = require ('sheet_format') --[[@as Sheet.FormatModule]]
local formula = require ('sheet_formula') --[[@as Sheet.FormulaModule]]

-- The workbook shapes it reads and writes, Sheet.BookData and the types inside it, are
-- declared in sheet_book.lua.

---An element of an XML document.
---@class Sheet.XmlNode
---@field name string The tag as written, prefix included, such as `x:c`.
---@field attrs table<string, string>
---@field children Sheet.XmlNode[]
---@field text string The text directly inside the element, with entities decoded.

---A relationship from one part of the file to another.
---@class Sheet.XlsxRel
---@field type string The last word of the relationship type, such as `worksheet`.
---@field target string The path of the part inside the zip.

---The zip's files, with a lower-case index, since part names ignore case.
---@class Sheet.XlsxSource
---@field files table<string, string>
---@field lower table<string, string>

---What every sheet of a workbook shares while it is read.
---@class Sheet.XlsxBook
---@field strings string[]
---@field rich table<integer, boolean> Shared strings with mixed formatting.
---@field xf_styles table<integer, Sheet.Style> Styles by `s` number, relative to style 0.
---@field xf_dates table<integer, boolean> Styles with a date format.
---@field date1904 boolean
---@field typed table<string, Sheet.XlsxTyped>

---A column range from a `<col>` element.
---@class Sheet.XlsxCol
---@field min integer
---@field max integer
---@field width? number Pixels, when it differs from the sheet's default.
---@field hidden boolean
---@field style? Sheet.Style

---A shared formula cell that waits for its master cell.
---@class Sheet.XlsxShared
---@field addr string
---@field row integer
---@field col integer
---@field si string
---@field value? string The cached value, used when the master is missing.

---The parts of a style that Excel keeps in separate lists, while a file is written.
---@class Sheet.XlsxStyleSheet
---@field fonts string[]
---@field font_ids table<string, integer>
---@field fills string[]
---@field fill_ids table<string, integer>
---@field borders string[]
---@field border_ids table<string, integer>
---@field formats string[]
---@field format_ids table<string, integer>
---@field xfs string[]
---@field xf_ids table<string, integer>
---@field by_style table<string, integer> Style keys to `s` numbers.

---@class Sheet.XlsxStrings
---@field list string[]
---@field ids table<string, integer>
---@field uses integer How many cells use a shared string.

---What every sheet shares while a workbook is written.
---@class Sheet.XlsxWriter
---@field styles Sheet.XlsxStyleSheet
---@field strings Sheet.XlsxStrings
---@field values? Sheet.XlsxValues
---@field warnings string[]
---@field typed table<string, Sheet.XlsxTyped>

---What typing a text stores, kept so that text which repeats is parsed once.
---@class Sheet.XlsxTyped
---@field value Sheet.Value
---@field code? string

---@alias Sheet.XlsxValues fun(sheet_index: integer, row: integer, col: integer): Sheet.Value

---@class Sheet.XlsxModule
local M = {}

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
-- A `<col>` range that reaches this far means the rest of the sheet.
local REST_OF_SHEET = 1000
-- Excel counts dates in a 1904 workbook from 1904-01-01, 1462 days after this app's day 0.
local DAYS_1904 = 1462

local NS_MAIN = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'
local NS_REL =
  'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
local NS_PACKAGE =
  'http://schemas.openxmlformats.org/package/2006/relationships'
local XML_HEAD = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
local SHEET_TYPE =
  'application/vnd.openxmlformats-officedocument.spreadsheetml.'

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
---@type table<string, boolean>
local BORDERS = {
  thin = true,
  medium = true,
  thick = true,
  dashed = true,
  dotted = true,
  double = true,
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

---------------------------------------------------------------------------------------------
-- Reading XML
---------------------------------------------------------------------------------------------

---@type table<string, string>
local ENTITIES = { lt = '<', gt = '>', amp = '&', quot = '"', apos = "'" }

---@param name string
---@return string?
local function entity (name)
  if string.sub (name, 1, 1) ~= '#' then
    return ENTITIES[name]
  end
  local code ---@type integer?
  if string.sub (name, 2, 2) == 'x' then
    code = math.tointeger (tonumber (string.sub (name, 3), 16))
  else
    code = math.tointeger (tonumber (string.sub (name, 2), 10))
  end
  -- Surrogates are not characters, so they stay as written.
  if
    not code
    or code < 0
    or code > 0x10FFFF
    or (code >= 0xD800 and code <= 0xDFFF)
  then
    return nil
  end
  return utf8.char (code)
end

---@param s string
---@return string
local function unescape (s)
  if not string.find (s, '&', 1, true) then
    return s
  end
  return (string.gsub (s, '&(#?%w+);', entity))
end

---Reads an XML document into a tree of elements. Returns the root element, or nil and a
---message when the text is not well formed. Names keep their prefixes as written.
---@param src string
---@return Sheet.XmlNode?
---@return string?
function M.parse_xml (src)
  if string.sub (src, 1, 3) == '\239\187\191' then
    src = string.sub (src, 4)
  end
  if string.find (src, '\r', 1, true) then
    src = string.gsub (src, '\r\n?', '\n')
  end
  local root = nil ---@type Sheet.XmlNode?
  local stack = {} ---@type Sheet.XmlNode[]
  -- The text of each open element, as a list of pieces joined when it closes.
  local pieces = {} ---@type string[][]
  local pos = 1
  local n = #src
  while pos <= n do
    local lt = string.find (src, '<', pos, true)
    local depth = #stack
    if not lt then
      lt = n + 1
    end
    if lt > pos and depth > 0 then
      local list = pieces[depth]
      list[#list + 1] = unescape (string.sub (src, pos, lt - 1))
    end
    if lt > n then
      break
    end
    local c = string.sub (src, lt + 1, lt + 1)
    if c == '/' then
      local close = string.find (src, '>', lt + 2, true)
      if not close then
        return nil, 'An end tag is not closed.'
      end
      local name =
        string.match (string.sub (src, lt + 2, close - 1), '^(.-)%s*$')
      local top = stack[depth]
      if not top or top.name ~= name then
        return nil, 'The end tag </' .. name .. '> does not match its start.'
      end
      top.text = table.concat (pieces[depth])
      stack[depth] = nil
      pieces[depth] = nil
      pos = close + 1
    elseif c == '?' then
      local _, close = string.find (src, '?>', lt + 2, true)
      if not close then
        return nil, 'An instruction is not closed.'
      end
      pos = close + 1
    elseif string.sub (src, lt, lt + 3) == '<!--' then
      local _, close = string.find (src, '-->', lt + 4, true)
      if not close then
        return nil, 'A comment is not closed.'
      end
      pos = close + 1
    elseif string.sub (src, lt, lt + 8) == '<![CDATA[' then
      local close = string.find (src, ']]>', lt + 9, true)
      if not close then
        return nil, 'A CDATA section is not closed.'
      end
      if depth > 0 then
        local list = pieces[depth]
        list[#list + 1] = string.sub (src, lt + 9, close - 1)
      end
      pos = close + 3
    elseif c == '!' then
      -- A document type, which may hold declarations in brackets.
      local close = string.find (src, '[%[>]', lt + 2)
      if close and string.sub (src, close, close) == '[' then
        local bracket = string.find (src, ']', close + 1, true)
        close = bracket and string.find (src, '>', bracket + 1, true)
      end
      if not close then
        return nil, 'A document type is not closed.'
      end
      pos = close + 1
    else
      local _, name_end, name = string.find (src, '^([^%s/>]+)', lt + 1)
      if not name_end then
        return nil, 'A tag has no name.'
      end
      ---@type Sheet.XmlNode
      local node = { name = name, attrs = {}, children = {}, text = '' }
      local i = name_end + 1
      local closed = false
      while true do
        local _, eq_end, key, quote =
          string.find (src, '^%s*([^%s=/>]+)%s*=%s*(["\'])', i)
        if eq_end then
          local value_end = string.find (src, quote, eq_end + 1, true)
          if not value_end then
            return nil, 'An attribute of <' .. name .. '> is not closed.'
          end
          ---@cast key string
          local value = string.sub (src, eq_end + 1, value_end - 1)
          node.attrs[key] = unescape ((string.gsub (value, '[\t\n]', ' ')))
          i = value_end + 1
        else
          local _, tag_end, slash = string.find (src, '^%s*(/?)>', i)
          if not tag_end then
            return nil, 'The tag <' .. name .. '> is not well formed.'
          end
          closed = slash == '/'
          i = tag_end + 1
          break
        end
      end
      local parent = stack[depth]
      if parent then
        parent.children[#parent.children + 1] = node
      elseif root then
        return nil, 'The XML has more than one root element.'
      else
        root = node
      end
      if not closed then
        stack[depth + 1] = node
        pieces[depth + 1] = {}
      end
      pos = i
    end
  end
  if #stack > 0 then
    return nil, 'The element <' .. stack[#stack].name .. '> has no end tag.'
  end
  if not root then
    return nil, 'The XML has no root element.'
  end
  return root
end

---@type table<string, string>
local bare_names = {}

---A name without its namespace prefix: `x:c` is `c`.
---@param name string
---@return string
local function bare (name)
  local out = bare_names[name]
  if not out then
    out = string.match (name, ':([^:]*)$') or name
    bare_names[name] = out
  end
  return out
end

---The first child with this name, ignoring prefixes.
---@param node Sheet.XmlNode?
---@param name string
---@return Sheet.XmlNode?
local function child (node, name)
  if node then
    for _, c in ipairs (node.children) do
      if bare (c.name) == name then
        return c
      end
    end
  end
  return nil
end

---Every child with this name, ignoring prefixes.
---@param node Sheet.XmlNode?
---@param name string
---@return Sheet.XmlNode[]
local function children (node, name)
  local out = {} ---@type Sheet.XmlNode[]
  if node then
    for _, c in ipairs (node.children) do
      if bare (c.name) == name then
        out[#out + 1] = c
      end
    end
  end
  return out
end

---An attribute such as `r:id`, whatever prefix the file gave it.
---@param node Sheet.XmlNode
---@param name string
---@return string?
local function prefixed (node, name)
  for key, value in pairs (node.attrs) do
    if bare (key) == name and key ~= name then
      return value
    end
  end
  return nil
end

---A true or false attribute. A missing `val` means true, as in `<b/>`.
---@param value string?
---@return boolean
local function flag (value)
  return value == nil or value == '1' or value == 'true' or value == 'on'
end

---@param value string?
---@return integer?
local function int (value)
  return value and math.tointeger (tonumber (value))
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
  return (string.gsub (string.gsub (part, '_xlfn%.', ''), '_xlws%.', ''))
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
  return outside_quotes (text, drop_prefixes)
end

---Turns formula text as this app writes it into formula text as Excel stores it.
---@param text string
---@return string
local function to_excel (text)
  return outside_quotes (text, add_prefixes)
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
  local root, err = M.parse_xml (text)
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
  { 'charts', 'Charts in %s were left out.' },
  { 'pictures', 'Pictures in %s were left out.' },
  { 'shapes', 'Shapes in %s were left out.' },
  { 'comments', 'Comments in %s were left out.' },
  { 'conditional', 'Conditional formats in %s were left out.' },
  { 'validation', 'Data validation in %s was left out.' },
  { 'filter', 'The filter in %s was left out.' },
  { 'links', 'Links in %s were left out.' },
  { 'tables', 'Table styles in %s were left out.' },
  {
    'pivots',
    'Pivot tables in %s were left out. Their last values are kept.',
  },
  { 'sparklines', 'Sparklines in %s were left out.' },
  { 'protection', 'Protection in %s was left out.' },
  { 'rich', 'Mixed text formatting inside cells in %s was left out.' },
}

-- Worksheet elements that mean a feature is there.
---@type table<string, string>
local FEATURE_TAGS = {
  conditionalFormatting = 'conditional',
  conditionalFormattings = 'conditional',
  dataValidations = 'validation',
  autoFilter = 'filter',
  hyperlinks = 'links',
  tableParts = 'tables',
  sheetProtection = 'protection',
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
      local kind = FEATURE_TAGS[name]
      if kind then
        found[kind] = true
      elseif name == 'extLst' or name == 'ext' then
        stack[#stack + 1] = c
      end
    end
  end
  local _, rels = rels_of (src, path)
  for _, rel in ipairs (rels) do
    if rel.type == 'comments' or rel.type == 'threadedComment' then
      found.comments = true
    elseif rel.type == 'pivotTable' then
      found.pivots = true
    elseif rel.type == 'table' then
      found.tables = true
    elseif rel.type == 'drawing' then
      local _, drawing_rels = rels_of (src, rel.target)
      for _, d in ipairs (drawing_rels) do
        if d.type == 'chart' or d.type == 'chartEx' then
          found.charts = true
        elseif d.type == 'image' then
          found.pictures = true
        end
      end
      local drawing = part_text (src, rel.target) or ''
      if string.find (drawing, '<[%w]*:?sp[%s>]') then
        found.shapes = true
      end
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
  local last_row = 0 ---@type integer
  for _, row in ipairs (children (child (root, 'sheetData'), 'row')) do
    local a = row.attrs
    local r = int (a.r) or last_row + 1 ---@type integer
    last_row = r
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
      max_row = math.max (max_row, r)
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
        if f and kind == 'shared' and f.attrs.si then
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
        end
        if text then
          cells[addr] = text
        end
        local style =
          own_style (book.xf_styles[s], overlay (col_style (cc), row_style))
        if style then
          styles[addr] = style
        end
        if text or style or f then
          max_row = math.max (max_row, cr)
          max_col = math.max (max_col, cc)
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
    if r1 and c1 and r2 and c2 and (r1 ~= r2 or c1 ~= c2) then
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
  }

  local view = child (child (wb, 'bookViews'), 'workbookView')
  local active_tab = view and int (view.attrs.activeTab) or 0
  ---@type Sheet.BookData
  local book = { version = 2, active = 1, sheets = {} }
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
  for _, node in ipairs (children (child (wb, 'definedNames'), 'definedName')) do
    local name = node.attrs.name or ''
    if string.sub (name, 1, 6) ~= '_xlnm.' then
      warn_once (warnings, seen, 'names', 'Named ranges were left out.')
    end
  end
  return book, warnings
end

---------------------------------------------------------------------------------------------
-- Writing
---------------------------------------------------------------------------------------------

---@type table<string, string>
local TEXT_ESCAPES = { ['&'] = '&amp;', ['<'] = '&lt;', ['>'] = '&gt;' }
---@type table<string, string>
local ATTR_ESCAPES = {
  ['&'] = '&amp;',
  ['<'] = '&lt;',
  ['>'] = '&gt;',
  ['"'] = '&quot;',
  ['\t'] = '&#9;',
  ['\n'] = '&#10;',
  ['\r'] = '&#13;',
}

---Replaces bytes that are not UTF-8 with U+FFFD, since Excel refuses such a file.
---@param s string
---@return string
local function utf8_only (s)
  if utf8.len (s) then
    return s
  end
  local out = {} ---@type string[]
  local i = 1
  while i <= #s do
    local len, bad = utf8.len (s, i)
    if len then
      out[#out + 1] = string.sub (s, i)
      break
    end
    ---@cast bad integer
    out[#out + 1] = string.sub (s, i, bad - 1) .. '\239\191\189'
    i = bad + 1
  end
  return table.concat (out)
end

---Text for an attribute value. Control characters other than tab and line breaks cannot
---appear in XML at all, so they are dropped.
---@param s string
---@return string
local function attr (s)
  s = string.gsub (utf8_only (s), '[%z\1-\8\11\12\14-\31]', '')
  return (string.gsub (s, '[&<>"\t\n\r]', ATTR_ESCAPES))
end

---Text for a cell string. Excel writes the control characters XML cannot hold as `_x000D_`,
---and marks a literal `_x0041_` with `_x005F_` so it stays as typed.
---@param s string
---@return string
local function cell_string (s)
  s = utf8_only (s)
  if string.find (s, '_x', 1, true) then
    s = string.gsub (s, '_(x%x%x%x%x_)', '_x005F_%1')
  end
  s = string.gsub (s, '[%z\1-\8\11-\31]', function (ch)
    return string.format ('_x%04X_', string.byte (ch))
  end)
  return (string.gsub (s, '[&<>]', TEXT_ESCAPES))
end

---Text for a formula element.
---@param s string
---@return string
local function formula_text (s)
  s = string.gsub (utf8_only (s), '[%z\1-\8\11\12\14-\31]', '')
  s = string.gsub (s, '\r', '&#13;')
  return (string.gsub (s, '[&<>]', TEXT_ESCAPES))
end

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
    format_id = BUILTIN_IDS[code] or sheet.format_ids[code]
    if not format_id then
      format_id = 164 + #sheet.formats
      sheet.format_ids[code] = format_id
      sheet.formats[#sheet.formats + 1] = '<numFmt numFmtId="'
        .. format_id
        .. '" formatCode="'
        .. attr (code)
        .. '"/>'
    end
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
  if #align > 0 then
    xf[#xf + 1] = ' applyAlignment="1"><alignment'
      .. table.concat (align)
      .. '/></xf>'
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

---@param map any
---@return boolean
local function has_entries (map)
  return type (map) == 'table' and next (map) ~= nil
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
    local value = cached ()
    if type (value) == 'number' then
      if value == value and value ~= math.huge and value ~= -math.huge then
        return nil, number_text (value), f
      end
      return 'e', '#NUM!', f
    elseif type (value) == 'string' then
      return 'str', value, f
    elseif type (value) == 'boolean' then
      return 'b', value and '1' or '0', f
    elseif type (value) == 'table' and EXCEL_ERRORS[value.code] then
      return 'e', value.code, f
    end
    return nil, nil, f
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

---@class Sheet.XlsxRow
---@field height? number
---@field hidden? boolean
---@field style? Sheet.Style

---Writes one worksheet.
---@param w Sheet.XlsxWriter
---@param data Sheet.SheetData
---@param index integer
---@param name string The name the file gives the sheet.
---@param active boolean
---@return string
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
        if f then
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
  out[#out + 1] =
    '<pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" header="0.3" footer="0.3"/>'
  out[#out + 1] = '</worksheet>'
  return table.concat (out)
end

-- What a workbook file may hold that an Excel file from this app leaves out for now.
local NOT_WRITTEN = {
  { 'rules', 'Conditional formats were left out of the Excel file.' },
  { 'validation', 'Validation rules were left out of the Excel file.' },
  { 'notes', 'Notes were left out of the Excel file.' },
  { 'charts', 'Charts were left out of the Excel file.' },
  { 'filter', 'Filters were left out of the Excel file.' },
}

---Makes the files of an `.xlsx` file from workbook data, as a map of path to text. `values`,
---when given, supplies the value of each formula cell, so other programs can show values
---without working them out. Returns the files and a list of warnings.
---@param book Sheet.BookData
---@param values? Sheet.XlsxValues
---@return table<string, string>
---@return string[]
function M.write (book, values)
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
  }
  xf_of (w.styles, nil)
  local files = {} ---@type table<string, string>

  local sheet_entries = {} ---@type string[]
  local rel_entries = {} ---@type string[]
  local type_entries = {} ---@type string[]
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
    files[path] = sheet_xml (w, data, i, names[i], i == active)
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

  files['[Content_Types].xml'] = table.concat ({
    XML_HEAD,
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">',
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>',
    '<Default Extension="xml" ContentType="application/xml"/>',
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
  files['xl/workbook.xml'] = table.concat ({
    XML_HEAD,
    '<workbook xmlns="' .. NS_MAIN .. '" xmlns:r="' .. NS_REL .. '">',
    '<bookViews><workbookView activeTab="' .. (active - 1) .. '"/></bookViews>',
    '<sheets>',
    table.concat (sheet_entries),
    '</sheets>',
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

  for _, item in ipairs (NOT_WRITTEN) do
    for _, data in ipairs (sheets) do
      if
        has_entries ((data --[[@as table<string, any>]])[item[1]])
      then
        warnings[#warnings + 1] = item[2]
        break
      end
    end
  end
  return files, warnings
end

return M
