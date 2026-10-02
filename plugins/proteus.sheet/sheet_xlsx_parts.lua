-- sheet_xlsx_parts: the parts of an Excel sheet that lie beside its cells, for sheet_xlsx.
-- Notes, links, conditional formats, validation, the filter and charts each have a reader and
-- a writer here. sheet_xlsx hands over its XML helpers as a kit, so this module shares them
-- without loading the reader twice. The module draws nothing and calls no host function.
--
-- Each writer gives back pieces of the worksheet's XML, in the places Excel's schema wants
-- them, and any further parts of the zip: comments with the drawing that shows them, and a
-- drawing with one chart part per chart.

local chart_mod = require ('sheet_chart') --[[@as Sheet.ChartModule]]
local format = require ('sheet_format') --[[@as Sheet.FormatModule]]
local formula = require ('sheet_formula') --[[@as Sheet.FormulaModule]]

---The helpers sheet_xlsx shares with this module.
---@class Sheet.XlsxKit
---@field child fun(node: Sheet.XmlNode?, name: string): Sheet.XmlNode?
---@field children fun(node: Sheet.XmlNode?, name: string): Sheet.XmlNode[]
---@field bare fun(name: string): string
---@field prefixed fun(node: Sheet.XmlNode, name: string): string?
---@field flag fun(value: string?): boolean
---@field int fun(value: string?): integer?
---@field attr fun(s: string): string Text for an attribute value.
---@field text fun(s: string): string Text for an element.
---@field formula_text fun(s: string): string Text for a formula element.
---@field from_excel fun(text: string): string
---@field to_excel fun(text: string): string
---@field color_of fun(node: Sheet.XmlNode?, theme: string[]): string?
---@field argb fun(value: any): string?
---@field part_xml fun(src: Sheet.XlsxSource, path: string): Sheet.XmlNode?, string?
---@field resolve fun(base: string, target: string): string
---@field string_of fun(node: Sheet.XmlNode): string, boolean
---@field number_text fun(n: number): string
---@field read_number fun(n: number): string
---@field format_id fun(styles: Sheet.XlsxStyleSheet, code: string): integer
---@field border_read table<string, string>

---What reading one worksheet's parts needs.
---@class Sheet.XlsxReadCtx
---@field src Sheet.XlsxSource
---@field path string The worksheet's part, such as `xl/worksheets/sheet1.xml`.
---@field root Sheet.XmlNode
---@field data Sheet.SheetData The sheet read so far, which gets the parts.
---@field dxfs Sheet.Style[] The styles conditional formats use, by `dxfId + 1`.
---@field theme string[]
---@field found table<string, boolean> Kinds of things left out, for the warnings.

---What writing one worksheet's parts needs.
---@class Sheet.XlsxWriteCtx
---@field data Sheet.SheetData
---@field index integer
---@field name string The sheet's name in the file.
---@field styles Sheet.XlsxStyleSheet
---@field values? Sheet.XlsxValues
---@field filtered? integer[] The rows the filter hides.
---@field warn fun(kind: string, text: string) Adds a warning once for each kind.
---@field charts integer How many charts the book's earlier sheets wrote.

---The pieces of a worksheet's XML, and the parts beside it, that one sheet's extras make.
---@class Sheet.XlsxSheetParts
---@field filter string The `autoFilter`, which goes after the cells.
---@field after_merges string Conditional formats, validation and links, after the merges.
---@field drawings string The `drawing` and `legacyDrawing`, after the page margins.
---@field rels string[] The worksheet's relationships.
---@field files table<string, string> More parts of the zip.
---@field types string[] Content type overrides for them.
---@field defaults table<string, string> Content types by file extension.
---@field defined? string The hidden name Excel gives the filter's block.
---@field hidden table<integer, boolean> Rows the filter hides, which the file marks hidden.
---@field charts integer How many charts this sheet wrote.

---@class Sheet.XlsxPartsModule
local M = {}

local NS_MAIN = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'
local NS_REL =
  'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
local NS_C = 'http://schemas.openxmlformats.org/drawingml/2006/chart'
local NS_A = 'http://schemas.openxmlformats.org/drawingml/2006/main'
local NS_XDR =
  'http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing'
local XML_HEAD = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
local DOC_TYPE = 'application/vnd.openxmlformats-officedocument.'
-- One pixel in the English Metric Units of drawings.
local EMU = 9525
-- The app's own column width and row height, in pixels.
local APP_WIDTH = 100
local APP_HEIGHT = 24
-- How many cells of a link's block get the link.
local LINK_CELLS = 1000

-- The compare ops of rules and validation, and Excel's names for them.
---@type table<string, string>
local OPS = {
  ['='] = 'equal',
  ['<>'] = 'notEqual',
  ['>'] = 'greaterThan',
  ['<'] = 'lessThan',
  ['>='] = 'greaterThanOrEqual',
  ['<='] = 'lessThanOrEqual',
  between = 'between',
  not_between = 'notBetween',
}
---@type table<string, string>
local OPS_READ = {}
for k, v in pairs (OPS) do
  OPS_READ[v] = k
end

-- The text tests of rules, and Excel's rule types for them.
---@type table<string, string>
local TEXT_RULES = {
  contains = 'containsText',
  not_contains = 'notContainsText',
  starts = 'beginsWith',
  ends = 'endsWith',
}
---@type table<string, string>
local TEXT_READ = {}
for k, v in pairs (TEXT_RULES) do
  TEXT_READ[v] = k
end

-- The icon sets the app draws, as Excel names them.
---@type table<string, string>
local ICONS =
  { arrows = '3Arrows', lights = '3TrafficLights1', flags = '3Flags' }

---@type table<string, string>
local VALIDATION_TYPES = {
  number = 'decimal',
  date = 'date',
  length = 'textLength',
  formula = 'custom',
  list = 'list',
}

---@type table<string, Sheet.ChartKind>
local CHART_READ = {
  barChart = 'column',
  bar3DChart = 'column',
  lineChart = 'line',
  line3DChart = 'line',
  areaChart = 'area',
  area3DChart = 'area',
  pieChart = 'pie',
  pie3DChart = 'pie',
  ofPieChart = 'pie',
  doughnutChart = 'doughnut',
  scatterChart = 'scatter',
}

---@type table<string, 'top'|'bottom'|'right'>
local LEGEND_READ =
  { t = 'top', b = 'bottom', r = 'right', l = 'right', tr = 'right' }

---------------------------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------------------------

---A block from text such as `B2:D9` or `B2`, or nil.
---@param text any
---@return Sheet.Rect?
local function rect_of (text)
  if type (text) ~= 'string' then
    return nil
  end
  local plain = string.gsub (text, '%$', '')
  local from, to = string.match (plain, '^%s*([^:%s]+):([^:%s]+)%s*$')
  if not from then
    from = string.match (plain, '^%s*([^:%s]+)%s*$')
    to = from
  end
  local r1, c1 = formula.parse_address (from or '')
  local r2, c2 = formula.parse_address (to or '')
  if not r1 or not c1 or not r2 or not c2 then
    return nil
  end
  return {
    r1 = math.min (r1, r2),
    c1 = math.min (c1, c2),
    r2 = math.max (r1, r2),
    c2 = math.max (c1, c2),
  }
end

---A block as `B2:D9`, or `B2` for one cell.
---@param r Sheet.Rect
---@return string
local function rect_text (r)
  local a = formula.address (r.r1, r.c1)
  if r.r1 == r.r2 and r.c1 == r.c2 then
    return a
  end
  return a .. ':' .. formula.address (r.r2, r.c2)
end

---A cell as `$B$2`.
---@param row integer
---@param col integer
---@return string
local function absolute (row, col)
  return '$' .. formula.col_name (col) .. '$' .. row
end

---A shallow copy of a table.
---@param t table
---@return table
local function copy (t)
  local out = {}
  for k, v in pairs (t) do
    out[k] = v
  end
  return out
end

---A rule or validation value, as text typed into a cell, as Excel formula text: a number,
---a date or TRUE stays a value, a formula loses its "=", and other text goes in quotes.
---@param kit Sheet.XlsxKit
---@param text string
---@return string
local function value_formula (kit, text)
  if formula.is_formula (text) then
    return kit.to_excel (string.sub (text, 2))
  end
  local value = format.parse_input (text)
  if type (value) == 'number' then
    return kit.number_text (value)
  elseif type (value) == 'boolean' then
    return value and 'TRUE' or 'FALSE'
  end
  return '"' .. string.gsub (text, '"', '""') .. '"'
end

---A rule or validation value from Excel formula text: a quoted text loses its quotes, a
---number stays, and anything else is a formula.
---@param kit Sheet.XlsxKit
---@param text string
---@return string
local function value_read (kit, text)
  local inner = string.match (text, '^"(.*)"$')
  if
    inner and not string.find (string.gsub (inner, '""', ''), '"', 1, true)
  then
    return (string.gsub (inner, '""', '"'))
  end
  local n = tonumber (text)
  if n then
    return kit.read_number (n)
  end
  local up = string.upper (text)
  if up == 'TRUE' or up == 'FALSE' then
    return up
  end
  return '=' .. kit.from_excel (text)
end

---A serial date as `2026-09-29`.
---@param serial number
---@return string
local function iso_date (serial)
  local y, m, d = formula.date_parts (serial)
  return string.format ('%04d-%02d-%02d', y, m, d)
end

---The relationships of a part, external ones included, by id.
---@param kit Sheet.XlsxKit
---@param src Sheet.XlsxSource
---@param part string
---@return table<string, { type: string, target: string, external: boolean }>
local function all_rels (kit, src, part)
  local out = {} ---@type table<string, { type: string, target: string, external: boolean }>
  local dir, file = string.match (part, '^(.-)([^/]*)$')
  local root = kit.part_xml (src, dir .. '_rels/' .. file .. '.rels')
  for _, node in ipairs (kit.children (root, 'Relationship')) do
    local a = node.attrs
    if a.Id and a.Target then
      local external = a.TargetMode == 'External'
      out[a.Id] = {
        type = string.match (a.Type or '', '([^/]*)$'),
        target = external and a.Target or kit.resolve (part, a.Target),
        external = external,
      }
    end
  end
  return out
end

---The first relationship of a part of one type, by id.
---@param rels table<string, { type: string, target: string, external: boolean }>
---@param kind string
---@return string?
local function rel_target (rels, kind)
  local ids = {} ---@type string[]
  for id, rel in pairs (rels) do
    if rel.type == kind then
      ids[#ids + 1] = id
    end
  end
  table.sort (ids)
  return ids[1] and rels[ids[1]].target or nil
end

---------------------------------------------------------------------------------------------
-- Styles of conditional formats
---------------------------------------------------------------------------------------------

---Reads the styles conditional formats use, the `dxfs` of `styles.xml`, in order.
---@param kit Sheet.XlsxKit
---@param root Sheet.XmlNode?
---@param theme string[]
---@return Sheet.Style[]
function M.read_dxfs (kit, root, theme)
  local formats = {} ---@type table<integer, string>
  for _, node in ipairs (kit.children (kit.child (root, 'numFmts'), 'numFmt')) do
    local id = kit.int (node.attrs.numFmtId)
    if id and node.attrs.formatCode then
      formats[id] = node.attrs.formatCode
    end
  end
  local out = {} ---@type Sheet.Style[]
  for i, dxf in ipairs (kit.children (kit.child (root, 'dxfs'), 'dxf')) do
    local style = {} ---@type table<string, any>
    local font = kit.child (dxf, 'font')
    if font then
      for _, pair in ipairs ({
        { 'b', 'bold' },
        { 'i', 'italic' },
        { 'strike', 'strike' },
      }) do
        local node = kit.child (font, pair[1])
        if node and kit.flag (node.attrs.val) then
          style[pair[2]] = true
        end
      end
      local u = kit.child (font, 'u')
      if u and u.attrs.val ~= 'none' then
        style.underline = true
      end
      style.color = kit.color_of (kit.child (font, 'color'), theme)
    end
    local fill = kit.child (kit.child (dxf, 'fill'), 'patternFill')
    if fill then
      -- A format's solid fill keeps its colour in bgColor, unlike a cell's.
      style.fill = kit.color_of (kit.child (fill, 'bgColor'), theme)
        or kit.color_of (kit.child (fill, 'fgColor'), theme)
    end
    local num = kit.child (dxf, 'numFmt')
    if num then
      local code = num.attrs.formatCode
        or formats[kit.int (num.attrs.numFmtId) or -1]
      if code and string.lower (code) ~= 'general' then
        style.format = code
      end
    end
    local border = kit.child (dxf, 'border')
    if border then
      for _, side in ipairs ({ 'top', 'right', 'bottom', 'left' }) do
        local node = kit.child (border, side)
        local kind = node and kit.border_read[node.attrs.style or '']
        if node and kind then
          style['border_' .. side] = kind
          style.border_color = style.border_color
            or kit.color_of (kit.child (node, 'color'), theme)
        end
      end
    end
    out[i] = style --[[@as Sheet.Style]]
  end
  return out
end

---The number of a conditional format's style, adding it to the style sheet's `dxfs`.
---@param kit Sheet.XlsxKit
---@param styles Sheet.XlsxStyleSheet
---@param style Sheet.Style
---@return integer?
local function dxf_of (kit, styles, style)
  local s = style --[[@as table<string, any>]]
  local parts = {} ---@type string[]
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
  local color = kit.argb (s.color)
  if color then
    font[#font + 1] = '<color rgb="' .. color .. '"/>'
  end
  if #font > 0 then
    parts[#parts + 1] = '<font>' .. table.concat (font) .. '</font>'
  end
  if type (s.format) == 'string' and string.lower (s.format) ~= 'general' then
    parts[#parts + 1] = '<numFmt numFmtId="'
      .. kit.format_id (styles, s.format)
      .. '" formatCode="'
      .. kit.attr (s.format)
      .. '"/>'
  end
  local fill = kit.argb (s.fill)
  if fill then
    parts[#parts + 1] = '<fill><patternFill patternType="solid"><bgColor rgb="'
      .. fill
      .. '"/></patternFill></fill>'
  end
  local sides = {} ---@type string[]
  local line = kit.argb (s.border_color)
  for _, side in ipairs ({ 'left', 'right', 'top', 'bottom' }) do
    local kind = s['border_' .. side]
    if type (kind) == 'string' and kit.border_read[kind] then
      sides[#sides + 1] = '<'
        .. side
        .. ' style="'
        .. kind
        .. '">'
        .. (line and ('<color rgb="' .. line .. '"/>') or '')
        .. '</'
        .. side
        .. '>'
    end
  end
  if #sides > 0 then
    parts[#parts + 1] = '<border>' .. table.concat (sides) .. '</border>'
  end
  if #parts == 0 then
    return nil
  end
  local xml = '<dxf>' .. table.concat (parts) .. '</dxf>'
  local dxfs = styles.dxfs
  for i, other in ipairs (dxfs) do
    if other == xml then
      return i - 1
    end
  end
  dxfs[#dxfs + 1] = xml
  return #dxfs - 1
end

---------------------------------------------------------------------------------------------
-- Notes
---------------------------------------------------------------------------------------------

---@param kit Sheet.XlsxKit
---@param ctx Sheet.XlsxReadCtx
---@param rels table<string, { type: string, target: string, external: boolean }>
local function read_notes (kit, ctx, rels)
  local path = rel_target (rels, 'comments')
  local root = path and kit.part_xml (ctx.src, path)
  if not root then
    return
  end
  local authors = {} ---@type string[]
  for i, node in ipairs (kit.children (kit.child (root, 'authors'), 'author')) do
    authors[i] = node.text
  end
  local notes = {} ---@type table<string, string>
  for _, node in
    ipairs (kit.children (kit.child (root, 'commentList'), 'comment'))
  do
    local addr = string.upper (node.attrs.ref or '')
    local body = kit.child (node, 'text')
    if formula.parse_address (addr) and body then
      local text = kit.string_of (body)
      -- Excel starts a note with its author's name in bold.
      local author = authors[(kit.int (node.attrs.authorId) or 0) + 1]
      if author and author ~= '' then
        local head = author .. ':'
        if string.sub (text, 1, #head) == head then
          text = string.gsub (string.sub (text, #head + 1), '^\r?\n', '')
        end
      end
      text = string.gsub (text, '\r\n', '\n')
      if text ~= '' then
        notes[addr] = text
      end
    end
  end
  if next (notes) then
    ctx.data.notes = notes
  end
end

---The comments part and the drawing that shows the notes, for a sheet with notes.
---@param kit Sheet.XlsxKit
---@param ctx Sheet.XlsxWriteCtx
---@param out Sheet.XlsxSheetParts
local function write_notes (kit, ctx, out)
  local notes = ctx.data.notes
  if type (notes) ~= 'table' then
    return
  end
  local list = {} ---@type { row: integer, col: integer, text: string }[]
  for addr, text in pairs (notes) do
    local row, col = formula.parse_address (tostring (addr))
    if row and col and type (text) == 'string' and text ~= '' then
      list[#list + 1] = { row = row, col = col, text = text }
    end
  end
  if #list == 0 then
    return
  end
  table.sort (list, function (a, b)
    if a.row ~= b.row then
      return a.row < b.row
    end
    return a.col < b.col
  end)
  local i = ctx.index
  local comments = {
    XML_HEAD,
    '<comments xmlns="'
      .. NS_MAIN
      .. '"><authors><author></author></authors><commentList>',
  }
  local shapes = {
    '<xml xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office"',
    ' xmlns:x="urn:schemas-microsoft-com:office:excel">',
    '<o:shapelayout v:ext="edit"><o:idmap v:ext="edit" data="'
      .. i
      .. '"/></o:shapelayout>',
    '<v:shapetype id="_x0000_t202" coordsize="21600,21600" o:spt="202" path="m,l,21600r21600,l21600,xe">',
    '<v:stroke joinstyle="miter"/><v:path gradientshapeok="t" o:connecttype="rect"/></v:shapetype>',
  }
  for n, note in ipairs (list) do
    comments[#comments + 1] = '<comment ref="'
      .. formula.address (note.row, note.col)
      .. '" authorId="0"><text><t xml:space="preserve">'
      .. kit.text (note.text)
      .. '</t></text></comment>'
    local r, c = note.row - 1, note.col - 1
    shapes[#shapes + 1] = '<v:shape id="_x0000_s'
      .. (i * 1024 + n)
      .. '" type="#_x0000_t202" style="position:absolute;margin-left:59.25pt;margin-top:1.5pt;'
      .. 'width:108pt;height:59.25pt;z-index:'
      .. n
      .. ';visibility:hidden" fillcolor="#ffffe1" o:insetmode="auto">'
      .. '<v:fill color2="#ffffe1"/><v:shadow on="t" color="black" obscured="t"/>'
      .. '<v:path o:connecttype="none"/><v:textbox style="mso-direction-alt:auto">'
      .. '<div style="text-align:left"></div></v:textbox><x:ClientData ObjectType="Note">'
      .. '<x:MoveWithCells/><x:SizeWithCells/><x:Anchor>'
      .. (c + 1)
      .. ', 15, '
      .. r
      .. ', 2, '
      .. (c + 3)
      .. ', 15, '
      .. (r + 4)
      .. ', 16</x:Anchor><x:AutoFill>False</x:AutoFill><x:Row>'
      .. r
      .. '</x:Row><x:Column>'
      .. c
      .. '</x:Column></x:ClientData></v:shape>'
  end
  comments[#comments + 1] = '</commentList></comments>'
  shapes[#shapes + 1] = '</xml>'
  out.files['xl/comments' .. i .. '.xml'] = table.concat (comments)
  out.files['xl/drawings/vmlDrawing' .. i .. '.vml'] = table.concat (shapes)
  out.types[#out.types + 1] = '<Override PartName="/xl/comments'
    .. i
    .. '.xml" ContentType="'
    .. DOC_TYPE
    .. 'spreadsheetml.comments+xml"/>'
  out.defaults.vml = DOC_TYPE .. 'vmlDrawing'
  local id = 'rId' .. (#out.rels + 1)
  out.rels[#out.rels + 1] = '<Relationship Id="'
    .. id
    .. '" Type="'
    .. NS_REL
    .. '/vmlDrawing" Target="../drawings/vmlDrawing'
    .. i
    .. '.vml"/>'
  out.rels[#out.rels + 1] = '<Relationship Id="rId'
    .. (#out.rels + 1)
    .. '" Type="'
    .. NS_REL
    .. '/comments" Target="../comments'
    .. i
    .. '.xml"/>'
  out.drawings = out.drawings .. '<legacyDrawing r:id="' .. id .. '"/>'
end

---------------------------------------------------------------------------------------------
-- Links
---------------------------------------------------------------------------------------------

---@param kit Sheet.XlsxKit
---@param ctx Sheet.XlsxReadCtx
---@param rels table<string, { type: string, target: string, external: boolean }>
local function read_links (kit, ctx, rels)
  local links = {} ---@type table<string, string>
  for _, node in
    ipairs (kit.children (kit.child (ctx.root, 'hyperlinks'), 'hyperlink'))
  do
    local r = rect_of (node.attrs.ref)
    local id = kit.prefixed (node, 'id')
    local rel = id and rels[id]
    local target = nil ---@type string?
    if rel and rel.type == 'hyperlink' then
      target = rel.target
      if node.attrs.location and node.attrs.location ~= '' then
        target = target .. '#' .. node.attrs.location
      end
    elseif node.attrs.location and node.attrs.location ~= '' then
      target = '#' .. node.attrs.location
    end
    if r and target then
      local count = 0
      for row = r.r1, r.r2 do
        for col = r.c1, r.c2 do
          count = count + 1
          if count <= LINK_CELLS then
            links[formula.address (row, col)] = target
          end
        end
      end
    end
  end
  if next (links) then
    ctx.data.links = links
  end
end

---@param kit Sheet.XlsxKit
---@param ctx Sheet.XlsxWriteCtx
---@param out Sheet.XlsxSheetParts
---@return string
local function write_links (kit, ctx, out)
  local links = ctx.data.links
  if type (links) ~= 'table' then
    return ''
  end
  local list = {} ---@type { row: integer, col: integer, target: string }[]
  for addr, target in pairs (links) do
    local row, col = formula.parse_address (tostring (addr))
    if row and col and type (target) == 'string' and target ~= '' then
      list[#list + 1] = { row = row, col = col, target = target }
    end
  end
  table.sort (list, function (a, b)
    if a.row ~= b.row then
      return a.row < b.row
    end
    return a.col < b.col
  end)
  if #list == 0 then
    return ''
  end
  local parts = { '<hyperlinks>' }
  for _, link in ipairs (list) do
    local ref = formula.address (link.row, link.col)
    if string.sub (link.target, 1, 1) == '#' then
      parts[#parts + 1] = '<hyperlink ref="'
        .. ref
        .. '" location="'
        .. kit.attr (string.sub (link.target, 2))
        .. '"/>'
    else
      local id = 'rId' .. (#out.rels + 1)
      out.rels[#out.rels + 1] = '<Relationship Id="'
        .. id
        .. '" Type="'
        .. NS_REL
        .. '/hyperlink" Target="'
        .. kit.attr (link.target)
        .. '" TargetMode="External"/>'
      parts[#parts + 1] = '<hyperlink ref="' .. ref .. '" r:id="' .. id .. '"/>'
    end
  end
  parts[#parts + 1] = '</hyperlinks>'
  return table.concat (parts)
end

---------------------------------------------------------------------------------------------
-- Conditional formats
---------------------------------------------------------------------------------------------

---The colours of a colour scale's points, lower case.
---@param kit Sheet.XlsxKit
---@param node Sheet.XmlNode
---@param theme string[]
---@return string[]
local function scale_colors (kit, node, theme)
  local out = {} ---@type string[]
  for _, c in ipairs (kit.children (node, 'color')) do
    out[#out + 1] = kit.color_of (c, theme) or '#000000'
  end
  return out
end

---One Excel rule as the app's rule, without its range, or nil when the app has no such rule.
---@param kit Sheet.XlsxKit
---@param ctx Sheet.XlsxReadCtx
---@param node Sheet.XmlNode
---@return Sheet.Rule?
local function rule_read (kit, ctx, node)
  local a = node.attrs
  local kind = a.type or ''
  local rule = {} ---@type table<string, any>
  local formulas = {} ---@type string[]
  for _, f in ipairs (kit.children (node, 'formula')) do
    formulas[#formulas + 1] = f.text
  end
  if kind == 'cellIs' then
    local op = OPS_READ[a.operator or '']
    if not op or not formulas[1] then
      return nil
    end
    rule.type, rule.op = 'compare', op
    rule.value = value_read (kit, formulas[1])
    if op == 'between' or op == 'not_between' then
      if not formulas[2] then
        return nil
      end
      rule.value2 = value_read (kit, formulas[2])
    end
  elseif TEXT_READ[kind] then
    rule.type, rule.op, rule.value = 'text', TEXT_READ[kind], a.text or ''
  elseif kind == 'containsBlanks' then
    rule.type = 'blank'
  elseif kind == 'notContainsBlanks' then
    rule.type = 'not_blank'
  elseif kind == 'containsErrors' then
    rule.type = 'error'
  elseif kind == 'duplicateValues' then
    rule.type = 'duplicate'
  elseif kind == 'uniqueValues' then
    rule.type = 'unique'
  elseif kind == 'top10' then
    rule.type = a.bottom and kit.flag (a.bottom) and 'bottom' or 'top'
    rule.count = kit.int (a.rank) or 10
    if a.percent and kit.flag (a.percent) then
      rule.percent = true
    end
  elseif kind == 'aboveAverage' then
    local above = a.aboveAverage == nil or kit.flag (a.aboveAverage)
    rule.type = above and 'above_average' or 'below_average'
  elseif kind == 'expression' then
    if not formulas[1] then
      return nil
    end
    rule.type, rule.formula = 'formula', '=' .. kit.from_excel (formulas[1])
  elseif kind == 'colorScale' then
    local colors = scale_colors (kit, kit.child (node, 'colorScale'), ctx.theme)
    if #colors < 2 then
      return nil
    end
    rule.type = 'scale'
    rule.min_color = colors[1]
    rule.max_color = colors[#colors]
    if #colors >= 3 then
      rule.mid_color = colors[2]
    end
  elseif kind == 'dataBar' then
    local bar = kit.child (node, 'dataBar')
    rule.type = 'bar'
    rule.color = kit.color_of (kit.child (bar, 'color'), ctx.theme)
  elseif kind == 'iconSet' then
    local set = kit.child (node, 'iconSet')
    local name = set and set.attrs.iconSet or '3TrafficLights1'
    rule.type = 'icons'
    if string.find (name, 'Flag', 1, true) then
      rule.icons = 'flags'
    elseif string.find (name, 'Arrow', 1, true) then
      rule.icons = 'arrows'
    else
      rule.icons = 'lights'
    end
    if set and set.attrs.reverse and kit.flag (set.attrs.reverse) then
      rule.reverse = true
    end
  else
    return nil
  end
  local dxf = kit.int (a.dxfId)
  local style = dxf and ctx.dxfs[dxf + 1]
  if style and next (style) then
    rule.style = copy (style)
  end
  if a.stopIfTrue and kit.flag (a.stopIfTrue) then
    rule.stop = true
  end
  return rule --[[@as Sheet.Rule]]
end

---@param kit Sheet.XlsxKit
---@param ctx Sheet.XlsxReadCtx
local function read_rules (kit, ctx)
  ---@type { priority: number, order: integer, rule: Sheet.Rule }[]
  local found = {}
  for _, block in ipairs (kit.children (ctx.root, 'conditionalFormatting')) do
    local ranges = {} ---@type Sheet.Rect[]
    for part in string.gmatch (block.attrs.sqref or '', '%S+') do
      local r = rect_of (part)
      if r then
        ranges[#ranges + 1] = r
      end
    end
    for _, node in ipairs (kit.children (block, 'cfRule')) do
      local rule = #ranges > 0 and rule_read (kit, ctx, node)
      if rule then
        for k, r in ipairs (ranges) do
          local one = copy (rule) --[[@as Sheet.Rule]]
          one.range = rect_text (r)
          -- A formula is written for the first block's top left cell.
          if one.formula and k > 1 then
            one.formula = formula.shift (
              one.formula,
              r.r1 - ranges[1].r1,
              r.c1 - ranges[1].c1
            )
          end
          found[#found + 1] = {
            priority = tonumber (node.attrs.priority) or math.huge,
            order = #found + 1,
            rule = one,
          }
        end
      else
        ctx.found.conditional = true
      end
    end
  end
  if #found == 0 then
    return
  end
  table.sort (found, function (x, y)
    if x.priority ~= y.priority then
      return x.priority < y.priority
    end
    return x.order < y.order
  end)
  local rules = {} ---@type Sheet.Rule[]
  for i, item in ipairs (found) do
    rules[i] = item.rule
  end
  ctx.data.rules = rules
end

---The test a text rule makes of the top left cell of its block, as Excel writes it.
---@param op string
---@param quoted string The text in quotes.
---@param cell string
---@return string
local function text_test (op, quoted, cell)
  if op == 'contains' then
    return 'NOT(ISERROR(SEARCH(' .. quoted .. ',' .. cell .. ')))'
  elseif op == 'not_contains' then
    return 'ISERROR(SEARCH(' .. quoted .. ',' .. cell .. '))'
  elseif op == 'starts' then
    return 'LEFT(' .. cell .. ',LEN(' .. quoted .. '))=' .. quoted
  end
  return 'RIGHT(' .. cell .. ',LEN(' .. quoted .. '))=' .. quoted
end

---One rule as Excel's `cfRule`, or nil when Excel has no such rule.
---@param kit Sheet.XlsxKit
---@param ctx Sheet.XlsxWriteCtx
---@param rule Sheet.Rule
---@param r Sheet.Rect
---@param priority integer
---@return string?
local function rule_xml (kit, ctx, rule, r, priority)
  local kind = rule.type
  local cell = formula.address (r.r1, r.c1)
  local head = {} ---@type string[]
  local body = {} ---@type string[]
  ---@param text string
  local function add_formula (text)
    body[#body + 1] = '<formula>' .. kit.formula_text (text) .. '</formula>'
  end
  if kind == 'compare' or (kind == 'text' and rule.op == 'equals') then
    local op = kind == 'text' and 'equal' or OPS[rule.op or '=']
    if not op then
      return nil
    end
    head[#head + 1] = 'type="cellIs" operator="' .. op .. '"'
    add_formula (value_formula (kit, rule.value or ''))
    if op == 'between' or op == 'notBetween' then
      add_formula (value_formula (kit, rule.value2 or ''))
    end
  elseif kind == 'text' then
    local excel = TEXT_RULES[rule.op or '']
    if not excel then
      return nil
    end
    local text = rule.value or ''
    local quoted = '"' .. string.gsub (text, '"', '""') .. '"'
    head[#head + 1] = 'type="'
      .. excel
      .. '" operator="'
      .. (excel == 'notContainsText' and 'notContains' or excel)
      .. '" text="'
      .. kit.attr (text)
      .. '"'
    add_formula (text_test (rule.op --[[@as string]], quoted, cell))
  elseif kind == 'blank' then
    head[#head + 1] = 'type="containsBlanks"'
    add_formula ('LEN(TRIM(' .. cell .. '))=0')
  elseif kind == 'not_blank' then
    head[#head + 1] = 'type="notContainsBlanks"'
    add_formula ('LEN(TRIM(' .. cell .. '))>0')
  elseif kind == 'error' then
    head[#head + 1] = 'type="containsErrors"'
    add_formula ('ISERROR(' .. cell .. ')')
  elseif kind == 'duplicate' then
    head[#head + 1] = 'type="duplicateValues"'
  elseif kind == 'unique' then
    head[#head + 1] = 'type="uniqueValues"'
  elseif kind == 'top' or kind == 'bottom' then
    head[#head + 1] = 'type="top10" rank="'
      .. math.floor (tonumber (rule.count) or 10)
      .. '"'
      .. (rule.percent and ' percent="1"' or '')
      .. (kind == 'bottom' and ' bottom="1"' or '')
  elseif kind == 'above_average' then
    head[#head + 1] = 'type="aboveAverage"'
  elseif kind == 'below_average' then
    head[#head + 1] = 'type="aboveAverage" aboveAverage="0"'
  elseif kind == 'formula' then
    if not formula.is_formula (rule.formula) then
      return nil
    end
    head[#head + 1] = 'type="expression"'
    add_formula (kit.to_excel (string.sub (rule.formula --[[@as string]], 2)))
  elseif kind == 'scale' then
    head[#head + 1] = 'type="colorScale"'
    local low = kit.argb (rule.min_color or '#f8696b') or 'FFF8696B'
    local high = kit.argb (rule.max_color or '#63be7b') or 'FF63BE7B'
    local mid = rule.mid_color and kit.argb (rule.mid_color)
    if mid then
      body[#body + 1] = '<colorScale><cfvo type="min"/><cfvo type="percentile" val="50"/>'
        .. '<cfvo type="max"/><color rgb="'
        .. low
        .. '"/><color rgb="'
        .. mid
        .. '"/><color rgb="'
        .. high
        .. '"/></colorScale>'
    else
      body[#body + 1] = '<colorScale><cfvo type="min"/><cfvo type="max"/><color rgb="'
        .. low
        .. '"/><color rgb="'
        .. high
        .. '"/></colorScale>'
    end
  elseif kind == 'bar' then
    head[#head + 1] = 'type="dataBar"'
    body[#body + 1] = '<dataBar><cfvo type="min"/><cfvo type="max"/><color rgb="'
      .. (kit.argb (rule.color or '#638ec6') or 'FF638EC6')
      .. '"/></dataBar>'
  elseif kind == 'icons' then
    head[#head + 1] = 'type="iconSet"'
    body[#body + 1] = '<iconSet iconSet="'
      .. (ICONS[rule.icons or 'arrows'] or '3Arrows')
      .. '"'
      .. (rule.reverse and ' reverse="1"' or '')
      .. '><cfvo type="percent" val="0"/><cfvo type="percent" val="33"/>'
      .. '<cfvo type="percent" val="67"/></iconSet>'
  else
    return nil
  end
  if type (rule.style) == 'table' then
    local dxf = dxf_of (kit, ctx.styles, rule.style --[[@as Sheet.Style]])
    if dxf then
      head[#head + 1] = 'dxfId="' .. dxf .. '"'
    end
  end
  head[#head + 1] = 'priority="' .. priority .. '"'
  if rule.stop then
    head[#head + 1] = 'stopIfTrue="1"'
  end
  if #body == 0 then
    return '<cfRule ' .. table.concat (head, ' ') .. '/>'
  end
  return '<cfRule '
    .. table.concat (head, ' ')
    .. '>'
    .. table.concat (body)
    .. '</cfRule>'
end

---@param kit Sheet.XlsxKit
---@param ctx Sheet.XlsxWriteCtx
---@return string
local function write_rules (kit, ctx)
  local rules = ctx.data.rules
  if type (rules) ~= 'table' then
    return ''
  end
  local parts = {} ---@type string[]
  local skipped = false
  for i, rule in ipairs (rules) do
    local r = type (rule) == 'table' and rect_of (rule.range)
    local xml = r and rule_xml (kit, ctx, rule, r, i)
    if r and xml then
      parts[#parts + 1] = '<conditionalFormatting sqref="'
        .. rect_text (r)
        .. '">'
        .. xml
        .. '</conditionalFormatting>'
    else
      skipped = true
    end
  end
  if skipped then
    ctx.warn (
      'rules',
      'Conditional formats Excel cannot hold were left out of the Excel file.'
    )
  end
  return table.concat (parts)
end

---------------------------------------------------------------------------------------------
-- Validation
---------------------------------------------------------------------------------------------

---Splits a list of choices as Excel writes it, `"a,b,c"`.
---@param text string
---@return string[]
local function split_list (text)
  local out = {} ---@type string[]
  for item in string.gmatch (text .. ',', '([^,]*),') do
    local trimmed = string.match (item, '^%s*(.-)%s*$')
    if trimmed ~= '' then
      out[#out + 1] = trimmed
    end
  end
  return out
end

---@param kit Sheet.XlsxKit
---@param ctx Sheet.XlsxReadCtx
local function read_validation (kit, ctx)
  local list = {} ---@type Sheet.Validation[]
  for _, node in
    ipairs (
      kit.children (kit.child (ctx.root, 'dataValidations'), 'dataValidation')
    )
  do
    local a = node.attrs
    local f1 = kit.child (node, 'formula1')
    local f2 = kit.child (node, 'formula2')
    local kind = a.type or 'none'
    local v = {} ---@type table<string, any>
    local good = true
    if kind == 'list' and f1 then
      v.type = 'list'
      local inner = string.match (f1.text, '^"(.*)"$')
      if inner then
        v.values = split_list ((string.gsub (inner, '""', '"')))
      else
        v.formula = '=' .. kit.from_excel (f1.text)
      end
    elseif kind == 'custom' and f1 then
      v.type, v.formula = 'formula', '=' .. kit.from_excel (f1.text)
    elseif
      (
        kind == 'whole'
        or kind == 'decimal'
        or kind == 'date'
        or kind == 'textLength'
      ) and f1
    then
      v.type = kind == 'date' and 'date'
        or kind == 'textLength' and 'length'
        or 'number'
      if kind == 'whole' then
        v.integer = true
      end
      v.op = OPS_READ[a.operator or 'between']
      ---@param node2 Sheet.XmlNode?
      ---@return string?
      local function value_of (node2)
        if not node2 then
          return nil
        end
        local n = tonumber (node2.text)
        if not n then
          -- The app tests typed values, so a limit read from cells is left out.
          good = false
          return nil
        end
        if kind == 'date' then
          return iso_date (n)
        end
        return kit.read_number (n)
      end
      v.value = value_of (f1)
      if v.op == 'between' or v.op == 'not_between' then
        v.value2 = value_of (f2)
        good = good and v.value2 ~= nil
      end
      good = good and v.op ~= nil
    else
      good = false
    end
    if a.errorStyle == 'warning' or a.errorStyle == 'information' then
      v.strict = false
    end
    if a.error and a.error ~= '' then
      v.message = a.error
    end
    if good then
      for part in string.gmatch (a.sqref or '', '%S+') do
        local r = rect_of (part)
        if r then
          local one = copy (v)
          one.range = rect_text (r)
          list[#list + 1] = one --[[@as Sheet.Validation]]
        end
      end
    elseif kind ~= 'none' then
      ctx.found.validation = true
    end
  end
  if #list > 0 then
    ctx.data.validation = list
  end
end

---@param kit Sheet.XlsxKit
---@param ctx Sheet.XlsxWriteCtx
---@return string
local function write_validation (kit, ctx)
  local rules = ctx.data.validation
  if type (rules) ~= 'table' then
    return ''
  end
  local parts = {} ---@type string[]
  local skipped = false
  for _, v in ipairs (rules) do
    local r = type (v) == 'table' and rect_of (v.range)
    local kind = r and VALIDATION_TYPES[v.type or '']
    local f1, f2 = nil, nil ---@type string?, string?
    local op = nil ---@type string?
    if kind == 'list' then
      if type (v.values) == 'table' and #v.values > 0 then
        local items = {} ---@type string[]
        for i, item in ipairs (v.values) do
          items[i] = tostring (item)
          if string.find (items[i], ',', 1, true) then
            kind = nil
          end
        end
        f1 = '"' .. string.gsub (table.concat (items, ','), '"', '""') .. '"'
        -- Excel holds at most 255 characters of choices.
        if #f1 > 257 then
          kind = nil
        end
      elseif formula.is_formula (v.formula) then
        f1 = kit.to_excel (string.sub (v.formula --[[@as string]], 2))
      else
        kind = nil
      end
    elseif kind == 'custom' then
      if formula.is_formula (v.formula) then
        f1 = kit.to_excel (string.sub (v.formula --[[@as string]], 2))
      else
        kind = nil
      end
    elseif kind then
      if v.integer and kind == 'decimal' then
        kind = 'whole'
      end
      op = OPS[v.op or '']
      if not op or not v.value then
        kind = nil
      else
        f1 = value_formula (kit, v.value)
        if op == 'between' or op == 'notBetween' then
          f2 = value_formula (kit, v.value2 or '')
        end
      end
    end
    if r and kind and f1 then
      local head = {
        '<dataValidation type="' .. kind .. '"',
      }
      if op and op ~= 'between' then
        head[#head + 1] = ' operator="' .. op .. '"'
      end
      if v.strict == false then
        head[#head + 1] = ' errorStyle="warning"'
      end
      head[#head + 1] = ' allowBlank="1" showErrorMessage="1"'
      if type (v.message) == 'string' and v.message ~= '' then
        head[#head + 1] = ' error="' .. kit.attr (v.message) .. '"'
      end
      head[#head + 1] = ' sqref="' .. rect_text (r) .. '">'
      parts[#parts + 1] = table.concat (head)
        .. '<formula1>'
        .. kit.formula_text (f1)
        .. '</formula1>'
        .. (f2 and ('<formula2>' .. kit.formula_text (f2) .. '</formula2>') or '')
        .. '</dataValidation>'
    else
      skipped = true
    end
  end
  if skipped then
    ctx.warn (
      'validation',
      'Validation rules Excel cannot hold were left out of the Excel file.'
    )
  end
  if #parts == 0 then
    return ''
  end
  return '<dataValidations count="'
    .. #parts
    .. '">'
    .. table.concat (parts)
    .. '</dataValidations>'
end

---------------------------------------------------------------------------------------------
-- The filter
---------------------------------------------------------------------------------------------

---One custom filter as the app's test, or nil.
---@param op string
---@param val string
---@return Sheet.FilterColumn?
local function custom_read (op, val)
  if op == 'equal' and val == '' then
    return { op = 'blank' }
  elseif op == 'notEqual' and val == ' ' then
    return { op = 'not_blank' }
  end
  local inner = string.match (val, '^%*(.*)%*$')
  if inner and inner ~= '' then
    if op == 'equal' then
      return { op = 'contains', value = inner }
    elseif op == 'notEqual' then
      return { op = 'not_contains', value = inner }
    end
    return nil
  end
  if op == 'equal' and string.sub (val, -1) == '*' then
    return { op = 'starts', value = string.sub (val, 1, -2) }
  elseif op == 'equal' and string.sub (val, 1, 1) == '*' then
    return { op = 'ends', value = string.sub (val, 2) }
  elseif op == 'equal' and not tonumber (val) then
    return { op = 'equals', value = val }
  end
  local mine = OPS_READ[op]
  if mine and mine ~= 'between' and mine ~= 'not_between' then
    return { op = mine, value = val }
  end
  return nil
end

---@param kit Sheet.XlsxKit
---@param ctx Sheet.XlsxReadCtx
local function read_filter (kit, ctx)
  local node = kit.child (ctx.root, 'autoFilter')
  local r = node and rect_of (node.attrs.ref)
  if not node or not r then
    return
  end
  ---@type Sheet.Filter
  local filter = { range = rect_text (r) }
  local columns = {} ---@type table<string, Sheet.FilterColumn>
  for _, col in ipairs (kit.children (node, 'filterColumn')) do
    local id = kit.int (col.attrs.colId)
    local test = nil ---@type Sheet.FilterColumn?
    local filters = kit.child (col, 'filters')
    local custom = kit.child (col, 'customFilters')
    if filters then
      local values = {} ---@type string[]
      for _, f in ipairs (kit.children (filters, 'filter')) do
        values[#values + 1] = f.attrs.val or ''
      end
      if filters.attrs.blank and kit.flag (filters.attrs.blank) then
        values[#values + 1] = ''
      end
      test = { values = values }
    elseif custom then
      local list = kit.children (custom, 'customFilter')
      local both = custom.attrs['and'] and kit.flag (custom.attrs['and'])
      if #list == 1 then
        test = custom_read (
          list[1].attrs.operator or 'equal',
          list[1].attrs.val or ''
        )
      elseif #list == 2 then
        local a, b = list[1].attrs, list[2].attrs
        if
          both
          and a.operator == 'greaterThanOrEqual'
          and b.operator == 'lessThanOrEqual'
        then
          test = { op = 'between', value = a.val or '', value2 = b.val or '' }
        elseif
          not both
          and a.operator == 'lessThan'
          and b.operator == 'greaterThan'
        then
          test =
            { op = 'not_between', value = a.val or '', value2 = b.val or '' }
        end
      end
    end
    if id and test then
      columns[formula.col_name (r.c1 + id)] = test
    elseif id then
      ctx.found.filter = true
    end
  end
  if next (columns) then
    filter.columns = columns
  end
  ctx.data.filter = filter
end

---One column's test as Excel's `filterColumn`, or nil when Excel has no such test.
---@param kit Sheet.XlsxKit
---@param id integer
---@param test Sheet.FilterColumn
---@return string?
local function filter_column (kit, id, test)
  local head = '<filterColumn colId="' .. id .. '">'
  ---@param list { [1]: string, [2]: string }[]
  ---@param both? boolean
  ---@return string
  local function custom (list, both)
    local parts = { head, '<customFilters', both and ' and="1">' or '>' }
    for _, f in ipairs (list) do
      parts[#parts + 1] = '<customFilter'
        .. (f[1] ~= 'equal' and (' operator="' .. f[1] .. '"') or '')
        .. ' val="'
        .. kit.attr (f[2])
        .. '"/>'
    end
    parts[#parts + 1] = '</customFilters></filterColumn>'
    return table.concat (parts)
  end
  if type (test.values) == 'table' and #test.values > 0 then
    local parts = { head }
    local blank = false
    local items = {} ---@type string[]
    for _, v in ipairs (test.values) do
      if v == '' then
        blank = true
      else
        items[#items + 1] = '<filter val="' .. kit.attr (tostring (v)) .. '"/>'
      end
    end
    parts[#parts + 1] = blank and '<filters blank="1">' or '<filters>'
    parts[#parts + 1] = table.concat (items)
    parts[#parts + 1] = '</filters></filterColumn>'
    return table.concat (parts)
  end
  local op = test.op
  local a, b = test.value or '', test.value2 or ''
  if op == 'blank' then
    return custom ({ { 'equal', '' } })
  elseif op == 'not_blank' then
    return custom ({ { 'notEqual', ' ' } })
  elseif op == 'contains' then
    return custom ({ { 'equal', '*' .. a .. '*' } })
  elseif op == 'not_contains' then
    return custom ({ { 'notEqual', '*' .. a .. '*' } })
  elseif op == 'starts' then
    return custom ({ { 'equal', a .. '*' } })
  elseif op == 'ends' then
    return custom ({ { 'equal', '*' .. a } })
  elseif op == 'equals' then
    return custom ({ { 'equal', a } })
  elseif op == 'between' then
    return custom (
      { { 'greaterThanOrEqual', a }, { 'lessThanOrEqual', b } },
      true
    )
  elseif op == 'not_between' then
    return custom ({ { 'lessThan', a }, { 'greaterThan', b } })
  elseif op and OPS[op] then
    return custom ({ { OPS[op], a } })
  end
  return nil
end

---@param kit Sheet.XlsxKit
---@param ctx Sheet.XlsxWriteCtx
---@param out Sheet.XlsxSheetParts
local function write_filter (kit, ctx, out)
  local filter = ctx.data.filter
  local r = type (filter) == 'table' and rect_of (filter.range)
  if not filter or not r then
    return
  end
  local parts = { '<autoFilter ref="' .. rect_text (r) .. '">' }
  local keys = {} ---@type integer[]
  for letters in
    pairs (type (filter.columns) == 'table' and filter.columns or {})
  do
    local c = formula.col_number (tostring (letters))
    if c and c >= r.c1 and c <= r.c2 then
      keys[#keys + 1] = c
    end
  end
  table.sort (keys)
  for _, c in ipairs (keys) do
    local test = (filter.columns or {})[formula.col_name (c)]
    local xml = type (test) == 'table' and filter_column (kit, c - r.c1, test)
    if xml then
      parts[#parts + 1] = xml
    else
      ctx.warn (
        'filter',
        'Filter tests Excel cannot hold were left out of the Excel file.'
      )
    end
  end
  parts[#parts + 1] = '</autoFilter>'
  out.filter = table.concat (parts)
  out.defined = '<definedName name="_xlnm._FilterDatabase" localSheetId="'
    .. (ctx.index - 1)
    .. '" hidden="1">'
    .. kit.formula_text (
      formula.quote_sheet (ctx.name)
        .. '!'
        .. absolute (r.r1, r.c1)
        .. ':'
        .. absolute (r.r2, r.c2)
    )
    .. '</definedName>'
  for _, row in ipairs (ctx.filtered or {}) do
    out.hidden[row] = true
  end
end

---------------------------------------------------------------------------------------------
-- Charts
---------------------------------------------------------------------------------------------

---The pixel sizes of a sheet's columns or rows, from its data, hidden ones taking none.
---@param data Sheet.SheetData
---@param axis 'col'|'row'
---@return fun(i: integer): number
local function sizes_of (data, axis)
  local hidden = {} ---@type table<integer, boolean>
  local own = {} ---@type table<integer, number>
  if axis == 'col' then
    for _, letters in
      ipairs (type (data.hidden_cols) == 'table' and data.hidden_cols or {})
    do
      local c = formula.col_number (tostring (letters))
      if c then
        hidden[c] = true
      end
    end
    for letters, px in
      pairs (type (data.widths) == 'table' and data.widths or {})
    do
      local c = formula.col_number (tostring (letters))
      if c then
        own[c] = tonumber (px) or APP_WIDTH
      end
    end
  else
    for _, row in
      ipairs (type (data.hidden_rows) == 'table' and data.hidden_rows or {})
    do
      local r = math.tointeger (tonumber (row))
      if r then
        hidden[r] = true
      end
    end
    for key, px in pairs (type (data.heights) == 'table' and data.heights or {}) do
      local r = math.tointeger (tonumber (key))
      if r then
        own[r] = tonumber (px) or APP_HEIGHT
      end
    end
  end
  local default = axis == 'col' and APP_WIDTH or APP_HEIGHT
  return function (i)
    if hidden[i] then
      return 0
    end
    return own[i] or default
  end
end

---The cell a pixel position falls in along columns or rows, counting from 0 as drawings do,
---and how far into it, in pixels.
---@param size fun(i: integer): number
---@param px number
---@return integer index
---@return number offset
local function cell_of (size, px)
  local i, left = 1, 0
  while i < 1048576 do
    local w = size (i)
    if w > 0 and px < left + w then
      return i - 1, px - left
    end
    left = left + w
    i = i + 1
  end
  return i - 1, 0
end

---The pixel position of a drawing's cell and offset.
---@param size fun(i: integer): number
---@param index integer From 0.
---@param offset number In pixels.
---@return number
local function pos_of (size, index, offset)
  local px = 0
  for i = 1, index do
    px = px + size (i)
  end
  return px + offset
end

---A reference as a chart writes it, `'Sheet 1'!$B$2:$B$5`.
---@param name string
---@param r1 integer
---@param c1 integer
---@param r2 integer
---@param c2 integer
---@return string
local function chart_ref (name, r1, c1, r2, c2)
  local text = formula.quote_sheet (name) .. '!' .. absolute (r1, c1)
  if r1 ~= r2 or c1 ~= c2 then
    text = text .. ':' .. absolute (r2, c2)
  end
  return text
end

---Rich text for a chart's title or an axis's.
---@param kit Sheet.XlsxKit
---@param text string
---@return string
local function title_xml (kit, text)
  return '<c:title><c:tx><c:rich><a:bodyPr/><a:p><a:r><a:t>'
    .. kit.text (text)
    .. '</a:t></a:r></a:p></c:rich></c:tx><c:overlay val="0"/></c:title>'
end

---The values of a block, as the chart reads them, and their text.
---@param ctx Sheet.XlsxWriteCtx
---@param r Sheet.Rect
---@return Sheet.Value[][]
local function block_values (ctx, r)
  local out = {} ---@type Sheet.Value[][]
  local cells = type (ctx.data.cells) == 'table' and ctx.data.cells or {}
  for row = r.r1, r.r2 do
    local line = {} ---@type Sheet.Value[]
    for col = r.c1, r.c2 do
      local v = nil ---@type Sheet.Value
      if ctx.values then
        v = ctx.values (ctx.index, row, col)
      else
        local text = cells[formula.address (row, col)]
        if type (text) == 'string' and not formula.is_formula (text) then
          v = (format.parse_input (text))
        end
      end
      line[col - r.c1 + 1] = v
    end
    out[row - r.r1 + 1] = line
  end
  return out
end

---A series' cached values or text.
---@param kit Sheet.XlsxKit
---@param values Sheet.Value[][]
---@param cells { [1]: integer, [2]: integer }[] Places in the block.
---@param numbers boolean
---@return string
local function cache_xml (kit, values, cells, numbers)
  local tag = numbers and 'c:numCache' or 'c:strCache'
  local parts = { '<' .. tag .. '>' }
  if numbers then
    parts[#parts + 1] = '<c:formatCode>General</c:formatCode>'
  end
  parts[#parts + 1] = '<c:ptCount val="' .. #cells .. '"/>'
  for k, at in ipairs (cells) do
    local v = (values[at[1]] or {})[at[2]]
    local text = nil ---@type string?
    if numbers then
      if
        type (v) == 'number'
        and v == v
        and v ~= math.huge
        and v ~= -math.huge
      then
        text = kit.number_text (v)
      end
    elseif v ~= nil and type (v) ~= 'table' then
      text = type (v) == 'number' and kit.number_text (v) or tostring (v)
    end
    if text then
      parts[#parts + 1] = '<c:pt idx="'
        .. (k - 1)
        .. '"><c:v>'
        .. kit.text (text)
        .. '</c:v></c:pt>'
    end
  end
  parts[#parts + 1] = '</' .. tag .. '>'
  return table.concat (parts)
end

---One chart as a chart part, or nil when its range cannot be read.
---@param kit Sheet.XlsxKit
---@param ctx Sheet.XlsxWriteCtx
---@param spec Sheet.ChartSpec
---@return string?
local function chart_xml (kit, ctx, spec)
  local r = rect_of (spec.range)
  if not r then
    return nil
  end
  local values = block_values (ctx, r)
  local layout = chart_mod.layout_of (values, {
    series_in = spec.series_in,
    headers = spec.headers,
  })
  if not layout or #layout.series == 0 then
    return nil
  end
  local kind = spec.type or 'column'
  local by_rows = layout.by_rows
  local first_i = layout.headers and 2 or 1
  local ni = by_rows and layout.cols or layout.rows
  ---A place in the block, from a place along the categories and one along the series.
  ---@param i integer
  ---@param j integer
  ---@return integer row
  ---@return integer col
  local function at (i, j)
    if by_rows then
      return j, i
    end
    return i, j
  end
  ---@param i1 integer
  ---@param i2 integer
  ---@param j integer
  ---@return string ref
  ---@return { [1]: integer, [2]: integer }[] cells
  local function line (i1, i2, j)
    local r1, c1 = at (i1, j)
    local r2, c2 = at (i2, j)
    local cells = {} ---@type { [1]: integer, [2]: integer }[]
    for i = i1, i2 do
      local row, col = at (i, j)
      cells[#cells + 1] = { row, col }
    end
    return chart_ref (
      ctx.name,
      r.r1 + r1 - 1,
      r.c1 + c1 - 1,
      r.r1 + r2 - 1,
      r.c1 + c2 - 1
    ),
      cells
  end
  local colors = type (spec.colors) == 'table' and spec.colors or {}
  local pie = kind == 'pie' or kind == 'doughnut'
  local series = {} ---@type string[]
  for n, j in ipairs (layout.series) do
    local parts = {
      '<c:ser><c:idx val="'
        .. (n - 1)
        .. '"/><c:order val="'
        .. (n - 1)
        .. '"/>',
    }
    if layout.headers then
      local ref, cells = line (1, 1, j)
      parts[#parts + 1] = '<c:tx><c:strRef><c:f>'
        .. kit.formula_text (ref)
        .. '</c:f>'
        .. cache_xml (kit, values, cells, false)
        .. '</c:strRef></c:tx>'
    end
    local color = not pie and kit.argb (colors[n])
    if color then
      local fill = '<a:solidFill><a:srgbClr val="'
        .. string.sub (color, 3)
        .. '"/></a:solidFill>'
      if kind == 'line' or kind == 'scatter' then
        parts[#parts + 1] = '<c:spPr><a:ln w="28575">'
          .. fill
          .. '</a:ln></c:spPr>'
      else
        parts[#parts + 1] = '<c:spPr>' .. fill .. '</c:spPr>'
      end
    end
    if kind == 'line' or kind == 'scatter' then
      parts[#parts + 1] = '<c:marker><c:symbol val="'
        .. (kind == 'scatter' and 'circle' or 'none')
        .. '"/></c:marker>'
    end
    if pie then
      for k, c in ipairs (colors) do
        local hex = kit.argb (c)
        if hex and k <= ni - first_i + 1 then
          parts[#parts + 1] = '<c:dPt><c:idx val="'
            .. (k - 1)
            .. '"/><c:bubble3D val="0"/><c:spPr><a:solidFill><a:srgbClr val="'
            .. string.sub (hex, 3)
            .. '"/></a:solidFill></c:spPr></c:dPt>'
        end
      end
    end
    local val_ref, val_cells = line (first_i, ni, j)
    local cat_tag, val_tag = 'c:cat', 'c:val'
    if kind == 'scatter' then
      cat_tag, val_tag = 'c:xVal', 'c:yVal'
    end
    if layout.labels then
      local cat_ref, cat_cells = line (first_i, ni, 1)
      parts[#parts + 1] = '<'
        .. cat_tag
        .. '><c:strRef><c:f>'
        .. kit.formula_text (cat_ref)
        .. '</c:f>'
        .. cache_xml (kit, values, cat_cells, false)
        .. '</c:strRef></'
        .. cat_tag
        .. '>'
    end
    parts[#parts + 1] = '<'
      .. val_tag
      .. '><c:numRef><c:f>'
      .. kit.formula_text (val_ref)
      .. '</c:f>'
      .. cache_xml (kit, values, val_cells, true)
      .. '</c:numRef></'
      .. val_tag
      .. '>'
    if kind == 'line' or kind == 'scatter' then
      parts[#parts + 1] = '<c:smooth val="0"/>'
    end
    parts[#parts + 1] = '</c:ser>'
    series[#series + 1] = table.concat (parts)
  end

  local grouping = spec.stacked and 'stacked' or 'standard'
  local plot = {} ---@type string[]
  if kind == 'column' or kind == 'bar' then
    plot[#plot + 1] = '<c:barChart><c:barDir val="'
      .. (kind == 'bar' and 'bar' or 'col')
      .. '"/><c:grouping val="'
      .. (spec.stacked and 'stacked' or 'clustered')
      .. '"/><c:varyColors val="0"/>'
      .. table.concat (series)
      .. '<c:gapWidth val="150"/>'
      .. (spec.stacked and '<c:overlap val="100"/>' or '')
      .. '<c:axId val="1"/><c:axId val="2"/></c:barChart>'
  elseif kind == 'line' then
    plot[#plot + 1] = '<c:lineChart><c:grouping val="'
      .. grouping
      .. '"/><c:varyColors val="0"/>'
      .. table.concat (series)
      .. '<c:marker val="1"/><c:axId val="1"/><c:axId val="2"/></c:lineChart>'
  elseif kind == 'area' then
    plot[#plot + 1] = '<c:areaChart><c:grouping val="'
      .. grouping
      .. '"/><c:varyColors val="0"/>'
      .. table.concat (series)
      .. '<c:axId val="1"/><c:axId val="2"/></c:areaChart>'
  elseif kind == 'pie' then
    plot[#plot + 1] = '<c:pieChart><c:varyColors val="1"/>'
      .. table.concat (series)
      .. '<c:firstSliceAng val="0"/></c:pieChart>'
  elseif kind == 'doughnut' then
    plot[#plot + 1] = '<c:doughnutChart><c:varyColors val="1"/>'
      .. table.concat (series)
      .. '<c:firstSliceAng val="0"/><c:holeSize val="50"/></c:doughnutChart>'
  elseif kind == 'scatter' then
    plot[#plot + 1] = '<c:scatterChart><c:scatterStyle val="lineMarker"/><c:varyColors val="0"/>'
      .. table.concat (series)
      .. '<c:axId val="1"/><c:axId val="2"/></c:scatterChart>'
  else
    return nil
  end
  if not pie then
    local x_title = type (spec.x_title) == 'string'
        and spec.x_title ~= ''
        and title_xml (kit, spec.x_title)
      or ''
    local y_title = type (spec.y_title) == 'string'
        and spec.y_title ~= ''
        and title_xml (kit, spec.y_title)
      or ''
    local across, down = 'b', 'l'
    if kind == 'bar' then
      across, down = 'l', 'b'
    end
    local cat_axis = kind == 'scatter' and 'c:valAx' or 'c:catAx'
    plot[#plot + 1] = '<'
      .. cat_axis
      .. '><c:axId val="1"/><c:scaling><c:orientation val="minMax"/></c:scaling>'
      .. '<c:delete val="0"/><c:axPos val="'
      .. across
      .. '"/>'
      .. x_title
      .. '<c:crossAx val="2"/></'
      .. cat_axis
      .. '>'
    plot[#plot + 1] = '<c:valAx><c:axId val="2"/><c:scaling><c:orientation val="minMax"/></c:scaling>'
      .. '<c:delete val="0"/><c:axPos val="'
      .. down
      .. '"/><c:majorGridlines/>'
      .. y_title
      .. '<c:numFmt formatCode="General" sourceLinked="1"/><c:crossAx val="1"/></c:valAx>'
  end
  local title = ''
  if type (spec.title) == 'string' and spec.title ~= '' then
    title = title_xml (kit, spec.title) .. '<c:autoTitleDeleted val="0"/>'
  else
    title = '<c:autoTitleDeleted val="1"/>'
  end
  local legend = ''
  local where = spec.legend or 'bottom'
  if where ~= 'none' and (#series >= 2 or pie) then
    legend = '<c:legend><c:legendPos val="'
      .. (where == 'top' and 't' or where == 'bottom' and 'b' or 'r')
      .. '"/><c:overlay val="0"/></c:legend>'
  end
  return XML_HEAD
    .. '<c:chartSpace xmlns:c="'
    .. NS_C
    .. '" xmlns:a="'
    .. NS_A
    .. '" xmlns:r="'
    .. NS_REL
    .. '"><c:roundedCorners val="0"/><c:chart>'
    .. title
    .. '<c:plotArea><c:layout/>'
    .. table.concat (plot)
    .. '</c:plotArea>'
    .. legend
    .. '<c:plotVisOnly val="1"/></c:chart></c:chartSpace>'
end

---@param kit Sheet.XlsxKit
---@param ctx Sheet.XlsxWriteCtx
---@param out Sheet.XlsxSheetParts
local function write_charts (kit, ctx, out)
  local charts = ctx.data.charts
  if type (charts) ~= 'table' or #charts == 0 then
    return
  end
  local width = sizes_of (ctx.data, 'col')
  local height = sizes_of (ctx.data, 'row')
  local anchors = {} ---@type string[]
  local rels = {} ---@type string[]
  local skipped = false
  for _, spec in ipairs (charts) do
    local xml = type (spec) == 'table' and chart_xml (kit, ctx, spec)
    if xml then
      local n = ctx.charts + out.charts + 1
      out.charts = out.charts + 1
      out.files['xl/charts/chart' .. n .. '.xml'] = xml
      out.types[#out.types + 1] = '<Override PartName="/xl/charts/chart'
        .. n
        .. '.xml" ContentType="'
        .. DOC_TYPE
        .. 'drawingml.chart+xml"/>'
      local id = 'rId' .. (#rels + 1)
      rels[#rels + 1] = '<Relationship Id="'
        .. id
        .. '" Type="'
        .. NS_REL
        .. '/chart" Target="../charts/chart'
        .. n
        .. '.xml"/>'
      local x, y = tonumber (spec.x) or 0, tonumber (spec.y) or 0
      local w, h = tonumber (spec.w) or 480, tonumber (spec.h) or 300
      local c1, cx1 = cell_of (width, x)
      local r1, ry1 = cell_of (height, y)
      local c2, cx2 = cell_of (width, x + w)
      local r2, ry2 = cell_of (height, y + h)
      anchors[#anchors + 1] = '<xdr:twoCellAnchor editAs="oneCell"><xdr:from><xdr:col>'
        .. c1
        .. '</xdr:col><xdr:colOff>'
        .. math.floor (cx1 * EMU + 0.5)
        .. '</xdr:colOff><xdr:row>'
        .. r1
        .. '</xdr:row><xdr:rowOff>'
        .. math.floor (ry1 * EMU + 0.5)
        .. '</xdr:rowOff></xdr:from><xdr:to><xdr:col>'
        .. c2
        .. '</xdr:col><xdr:colOff>'
        .. math.floor (cx2 * EMU + 0.5)
        .. '</xdr:colOff><xdr:row>'
        .. r2
        .. '</xdr:row><xdr:rowOff>'
        .. math.floor (ry2 * EMU + 0.5)
        .. '</xdr:rowOff></xdr:to><xdr:graphicFrame macro=""><xdr:nvGraphicFramePr>'
        .. '<xdr:cNvPr id="'
        .. (#anchors + 2)
        .. '" name="'
        .. kit.attr (
          type (spec.title) == 'string' and spec.title ~= '' and spec.title
            or ('Chart ' .. n)
        )
        .. '"/><xdr:cNvGraphicFramePr/></xdr:nvGraphicFramePr><xdr:xfrm><a:off x="0" y="0"/>'
        .. '<a:ext cx="0" cy="0"/></xdr:xfrm><a:graphic><a:graphicData uri="'
        .. NS_C
        .. '"><c:chart xmlns:c="'
        .. NS_C
        .. '" xmlns:r="'
        .. NS_REL
        .. '" r:id="'
        .. id
        .. '"/></a:graphicData></a:graphic></xdr:graphicFrame><xdr:clientData/></xdr:twoCellAnchor>'
    else
      skipped = true
    end
  end
  if skipped then
    ctx.warn ('charts', 'Charts with no data were left out of the Excel file.')
  end
  if #anchors == 0 then
    return
  end
  local i = ctx.index
  out.files['xl/drawings/drawing' .. i .. '.xml'] = XML_HEAD
    .. '<xdr:wsDr xmlns:xdr="'
    .. NS_XDR
    .. '" xmlns:a="'
    .. NS_A
    .. '">'
    .. table.concat (anchors)
    .. '</xdr:wsDr>'
  out.files['xl/drawings/_rels/drawing' .. i .. '.xml.rels'] = XML_HEAD
    .. '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    .. table.concat (rels)
    .. '</Relationships>'
  out.types[#out.types + 1] = '<Override PartName="/xl/drawings/drawing'
    .. i
    .. '.xml" ContentType="'
    .. DOC_TYPE
    .. 'drawing+xml"/>'
  local id = 'rId' .. (#out.rels + 1)
  out.rels[#out.rels + 1] = '<Relationship Id="'
    .. id
    .. '" Type="'
    .. NS_REL
    .. '/drawing" Target="../drawings/drawing'
    .. i
    .. '.xml"/>'
  -- The drawing comes before the notes' drawing, as the schema orders them.
  out.drawings = '<drawing r:id="' .. id .. '"/>' .. out.drawings
end

---The text of a chart's or an axis's title, or nil.
---@param kit Sheet.XlsxKit
---@param node Sheet.XmlNode?
---@return string?
local function title_read (kit, node)
  local title = kit.child (node, 'title')
  if not title then
    return nil
  end
  local parts = {} ---@type string[]
  local stack = { title } ---@type Sheet.XmlNode[]
  -- The runs of the title's text, in order, found without recursion.
  local order = {} ---@type Sheet.XmlNode[]
  while #stack > 0 do
    local n = table.remove (stack)
    order[#order + 1] = n
    for k = #n.children, 1, -1 do
      stack[#stack + 1] = n.children[k]
    end
  end
  for _, n in ipairs (order) do
    if kit.bare (n.name) == 't' then
      parts[#parts + 1] = n.text
    end
  end
  local text = table.concat (parts)
  if text == '' then
    return nil
  end
  return text
end

---A chart reference read into its sheet and block.
---@param kit Sheet.XlsxKit
---@param node Sheet.XmlNode?
---@return string? sheet
---@return Sheet.Rect?
local function ref_read (kit, node)
  local f =
    kit.child (kit.child (node, 'strRef') or kit.child (node, 'numRef'), 'f')
  if not f then
    return nil, nil
  end
  local text = string.gsub (f.text, '^%((.*)%)$', '%1')
  local sheet, where = string.match (text, "^'(.+)'!(.+)$")
  if sheet then
    sheet = string.gsub (sheet, "''", "'")
  else
    sheet, where = string.match (text, '^([^!]+)!(.+)$')
  end
  return sheet, rect_of (where)
end

---One chart part as the app's chart, or nil when the app cannot show it.
---@param kit Sheet.XlsxKit
---@param ctx Sheet.XlsxReadCtx
---@param root Sheet.XmlNode
---@return Sheet.ChartSpec?
local function chart_read (kit, ctx, root)
  local chart = kit.child (root, 'chart')
  local plot = kit.child (chart, 'plotArea')
  if not plot then
    return nil
  end
  local node = nil ---@type Sheet.XmlNode?
  local kind = nil ---@type Sheet.ChartKind?
  for _, c in ipairs (plot.children) do
    local name = kit.bare (c.name)
    if CHART_READ[name] then
      if node then
        -- Two kinds of chart in one: the app shows one kind.
        return nil
      end
      node, kind = c, CHART_READ[name]
    end
  end
  if not node or not kind then
    return nil
  end
  ---@type table<string, any>
  local spec = { type = kind }
  local bar_dir = kit.child (node, 'barDir')
  if bar_dir and bar_dir.attrs.val == 'bar' then
    spec.type = 'bar'
  end
  local grouping = kit.child (node, 'grouping')
  if
    grouping
    and (
      grouping.attrs.val == 'stacked'
      or grouping.attrs.val == 'percentStacked'
    )
  then
    spec.stacked = true
  end
  local name = ctx.data.name
  local box = nil ---@type Sheet.Rect?
  local by_rows = nil ---@type boolean?
  local headers = false
  local colors = {} ---@type string[]
  local any_color = false
  ---@param r Sheet.Rect
  local function take (r)
    if not box then
      box = { r1 = r.r1, c1 = r.c1, r2 = r.r2, c2 = r.c2 }
    else
      box.r1, box.c1 = math.min (box.r1, r.r1), math.min (box.c1, r.c1)
      box.r2, box.c2 = math.max (box.r2, r.r2), math.max (box.c2, r.c2)
    end
  end
  local list = kit.children (node, 'ser')
  if #list == 0 then
    return nil
  end
  for n, ser in ipairs (list) do
    local val_sheet, val =
      ref_read (kit, kit.child (ser, 'val') or kit.child (ser, 'yVal'))
    if not val or (val_sheet and val_sheet ~= name) then
      return nil
    end
    take (val)
    local rows = val.c1 == val.c2 and val.r1 ~= val.r2
    local cols = val.r1 == val.r2 and val.c1 ~= val.c2
    if rows then
      by_rows = by_rows == nil and false or by_rows
    elseif cols then
      by_rows = by_rows == nil and true or by_rows
    end
    local tx_sheet, tx = ref_read (kit, kit.child (ser, 'tx'))
    if tx and (not tx_sheet or tx_sheet == name) then
      take (tx)
      headers = true
    end
    local cat_sheet, cat =
      ref_read (kit, kit.child (ser, 'cat') or kit.child (ser, 'xVal'))
    if cat and (not cat_sheet or cat_sheet == name) then
      take (cat)
    end
    local fill = kit.child (kit.child (ser, 'spPr'), 'solidFill')
      or kit.child (kit.child (kit.child (ser, 'spPr'), 'ln'), 'solidFill')
    local rgb = kit.child (fill, 'srgbClr')
    if rgb and rgb.attrs.val then
      colors[n] = '#' .. string.lower (rgb.attrs.val)
      any_color = true
    else
      colors[n] = ''
    end
  end
  local r = box --[[@as Sheet.Rect]]
  spec.range = rect_text (r)
  -- The app works out which way the series run, and the headings, from the cells. It keeps
  -- them in the chart only where the file says otherwise.
  local values = {} ---@type Sheet.Value[][]
  local cells = type (ctx.data.cells) == 'table' and ctx.data.cells or {}
  for row = r.r1, r.r2 do
    local line = {} ---@type Sheet.Value[]
    for col = r.c1, r.c2 do
      local text = cells[formula.address (row, col)]
      if type (text) == 'string' then
        if formula.is_formula (text) then
          line[col - r.c1 + 1] = 0
        else
          line[col - r.c1 + 1] = (format.parse_input (text))
        end
      end
    end
    values[row - r.r1 + 1] = line
  end
  local seen = chart_mod.layout_of (values)
  if by_rows == nil then
    by_rows = seen and seen.by_rows or false
  end
  if not seen or seen.by_rows ~= by_rows then
    spec.series_in = by_rows and 'rows' or 'cols'
  end
  local seen_headers =
    chart_mod.layout_of (values, { series_in = by_rows and 'rows' or 'cols' })
  if not seen_headers or seen_headers.headers ~= headers then
    spec.headers = headers
  end
  if any_color and kind ~= 'pie' and kind ~= 'doughnut' then
    spec.colors = colors
  end
  spec.title = title_read (kit, chart)
  local axes = {} ---@type Sheet.XmlNode[]
  for _, c in ipairs (plot.children) do
    local axis = kit.bare (c.name)
    if axis == 'catAx' or axis == 'valAx' or axis == 'dateAx' then
      axes[#axes + 1] = c
    end
  end
  if #axes >= 2 then
    local x_title = title_read (kit, axes[1])
    local y_title = title_read (kit, axes[2])
    spec.x_title, spec.y_title = x_title, y_title
  end
  -- The app shows a legend at the bottom when there is more than one series, or a pie.
  local legend = kit.child (chart, 'legend')
  local pos = kit.child (legend, 'legendPos')
  local wanted = #list >= 2 or kind == 'pie' or kind == 'doughnut'
  if legend then
    local side = LEGEND_READ[pos and pos.attrs.val or 'r'] or 'right'
    spec.legend = side ~= 'bottom' and side or nil
  elseif wanted then
    spec.legend = 'none'
  end
  return spec --[[@as Sheet.ChartSpec]]
end

---@param kit Sheet.XlsxKit
---@param ctx Sheet.XlsxReadCtx
---@param rels table<string, { type: string, target: string, external: boolean }>
local function read_charts (kit, ctx, rels)
  local path = rel_target (rels, 'drawing')
  local root = path and kit.part_xml (ctx.src, path)
  if not path or not root then
    return
  end
  local drawing_rels = all_rels (kit, ctx.src, path)
  local width = sizes_of (ctx.data, 'col')
  local height = sizes_of (ctx.data, 'row')
  local charts = {} ---@type Sheet.ChartSpec[]
  for _, anchor in ipairs (root.children) do
    local how = kit.bare (anchor.name)
    local frame = kit.child (anchor, 'graphicFrame')
    local data = kit.child (kit.child (frame, 'graphic'), 'graphicData')
    local ref = data and kit.child (data, 'chart')
    local id = ref and kit.prefixed (ref, 'id')
    local rel = id and drawing_rels[id]
    if rel and rel.type == 'chart' then
      local chart_root = kit.part_xml (ctx.src, rel.target)
      local spec = chart_root and chart_read (kit, ctx, chart_root)
      ---@param node Sheet.XmlNode?
      ---@param tag string
      ---@return number
      local function number_in (node, tag)
        local found = kit.child (node, tag)
        return found and tonumber (found.text) or 0
      end
      ---@param node Sheet.XmlNode?
      ---@return number x
      ---@return number y
      local function corner (node)
        local col = math.floor (number_in (node, 'col'))
        local row = math.floor (number_in (node, 'row'))
        return pos_of (width, col, number_in (node, 'colOff') / EMU),
          pos_of (height, row, number_in (node, 'rowOff') / EMU)
      end
      if spec then
        local x, y, w, h = 0, 0, 480, 300
        if how == 'twoCellAnchor' then
          x, y = corner (kit.child (anchor, 'from'))
          local x2, y2 = corner (kit.child (anchor, 'to'))
          w, h = x2 - x, y2 - y
        elseif how == 'oneCellAnchor' then
          x, y = corner (kit.child (anchor, 'from'))
          local ext = kit.child (anchor, 'ext')
          w = (tonumber (ext and ext.attrs.cx) or 480 * EMU) / EMU
          h = (tonumber (ext and ext.attrs.cy) or 300 * EMU) / EMU
        elseif how == 'absoluteAnchor' then
          local pos = kit.child (anchor, 'pos')
          local ext = kit.child (anchor, 'ext')
          x = (tonumber (pos and pos.attrs.x) or 0) / EMU
          y = (tonumber (pos and pos.attrs.y) or 0) / EMU
          w = (tonumber (ext and ext.attrs.cx) or 480 * EMU) / EMU
          h = (tonumber (ext and ext.attrs.cy) or 300 * EMU) / EMU
        end
        spec.id = 'c' .. (#charts + 1)
        spec.x = math.floor (x + 0.5)
        spec.y = math.floor (y + 0.5)
        spec.w = math.max (40, math.floor (w + 0.5))
        spec.h = math.max (40, math.floor (h + 0.5))
        charts[#charts + 1] = spec
      else
        ctx.found.charts = true
      end
    elseif rel and rel.type == 'image' then
      ctx.found.pictures = true
    elseif
      how == 'twoCellAnchor'
      or how == 'oneCellAnchor'
      or how == 'absoluteAnchor'
    then
      if kit.child (anchor, 'sp') then
        ctx.found.shapes = true
      elseif kit.child (anchor, 'pic') then
        ctx.found.pictures = true
      elseif frame then
        ctx.found.charts = true
      end
    end
  end
  if #charts > 0 then
    ctx.data.charts = charts
  end
end

---------------------------------------------------------------------------------------------
-- The module's two calls
---------------------------------------------------------------------------------------------

---Reads the notes, links, conditional formats, validation, filter and charts of a worksheet
---into its data. What the app cannot show is marked in `ctx.found`.
---@param kit Sheet.XlsxKit
---@param ctx Sheet.XlsxReadCtx
function M.read (kit, ctx)
  local rels = all_rels (kit, ctx.src, ctx.path)
  read_notes (kit, ctx, rels)
  read_links (kit, ctx, rels)
  read_rules (kit, ctx)
  read_validation (kit, ctx)
  read_filter (kit, ctx)
  read_charts (kit, ctx, rels)
end

---Writes the notes, links, conditional formats, validation, filter and charts of a sheet.
---@param kit Sheet.XlsxKit
---@param ctx Sheet.XlsxWriteCtx
---@return Sheet.XlsxSheetParts
function M.write (kit, ctx)
  ---@type Sheet.XlsxSheetParts
  local out = {
    filter = '',
    after_merges = '',
    drawings = '',
    rels = {},
    files = {},
    types = {},
    defaults = {},
    hidden = {},
    charts = 0,
  }
  write_filter (kit, ctx, out)
  out.after_merges = write_rules (kit, ctx)
    .. write_validation (kit, ctx)
    .. write_links (kit, ctx, out)
  write_charts (kit, ctx, out)
  write_notes (kit, ctx, out)
  return out
end

return M
