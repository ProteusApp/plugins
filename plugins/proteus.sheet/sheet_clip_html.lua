-- sheet_clip_html: the cells of a copy as an HTML table, and an HTML table pasted from another
-- program, such as Excel, Google Sheets, LibreOffice or a web page, as a clip. The HTML carries
-- what plain text loses: bold and italic text, colours, fills, alignment, borders, merged
-- cells and links. sheet_grid_act puts the HTML on the clipboard beside the tab-separated
-- text, and reads it back on paste.

---@class Sheet.ClipHtmlModule
local M = {}

-- Notes and links in a clip go by `i * KEY + j`, as in the sheet.
local KEY = (require ('sheet_model') --[[@as Sheet.ModelModule]]).KEY

-------------------------------------------------------------------------------------------
-- Writing
-------------------------------------------------------------------------------------------

---@param s string
---@return string
local function escape (s)
  return (
    string.gsub (s, '[&<>"]', {
      ['&'] = '&amp;',
      ['<'] = '&lt;',
      ['>'] = '&gt;',
      ['"'] = '&quot;',
    })
  )
end
M.escape = escape

local BORDER_CSS = {
  thin = '1px solid',
  medium = '2px solid',
  thick = '3px solid',
  dashed = '1px dashed',
  dotted = '1px dotted',
  double = '3px double',
} ---@type table<string, string>

---The inline CSS for a cell's style.
---@param style Sheet.Style
---@return string
function M.style_css (style)
  local out = {} ---@type string[]
  if style.bold then
    out[#out + 1] = 'font-weight:bold'
  end
  if style.italic then
    out[#out + 1] = 'font-style:italic'
  end
  if style.underline or style.strike then
    out[#out + 1] = 'text-decoration:'
      .. (style.underline and 'underline' or '')
      .. (style.underline and style.strike and ' ' or '')
      .. (style.strike and 'line-through' or '')
  end
  if style.size and style.size ~= 13 then
    out[#out + 1] = 'font-size:' .. style.size .. 'px'
  end
  if style.color and style.color ~= 'none' then
    out[#out + 1] = 'color:' .. style.color
  end
  if style.fill and style.fill ~= 'none' then
    out[#out + 1] = 'background-color:' .. style.fill
  end
  if style.align and style.align ~= 'general' then
    out[#out + 1] = 'text-align:' .. style.align
  end
  if style.valign and style.valign ~= 'bottom' then
    out[#out + 1] = 'vertical-align:' .. style.valign
  end
  if style.wrap then
    out[#out + 1] = 'white-space:normal'
  end
  local color = style.border_color or '#000000'
  for _, side in ipairs ({ 'top', 'right', 'bottom', 'left' }) do
    local b = (style --[[@as table<string, string?>]])['border_' .. side]
    if b and BORDER_CSS[b] then
      out[#out + 1] = 'border-' .. side .. ':' .. BORDER_CSS[b] .. ' ' .. color
    end
  end
  return table.concat (out, ';')
end

---A link a page may hold: a web or mail address.
---@param link string?
---@return boolean
local function web_link (link)
  return link ~= nil
    and (
      string.match (string.lower (link), '^https?://') ~= nil
      or string.match (string.lower (link), '^mailto:') ~= nil
    )
end

---The block of cells as an HTML table, with each cell's shown value, style, merges and web
---links. Hidden rows and columns are left out, as other spreadsheets copy them.
---@param sheet Sheet.Sheet
---@param rect Sheet.Rect
---@return string
function M.from_sheet (sheet, rect)
  local rows = {} ---@type string[]
  for row = rect.r1, rect.r2 do
    if not sheet:row_hidden (row) then
      local cells = {} ---@type string[]
      for col = rect.c1, rect.c2 do
        local m = sheet:merge_at (row, col)
        local covered = m ~= nil and (m.r1 ~= row or m.c1 ~= col)
        if not sheet:col_hidden (col) and not covered then
          local attrs = '' ---@type string
          if m then
            local r2, c2 = math.min (m.r2, rect.r2), math.min (m.c2, rect.c2)
            if r2 > row then
              attrs = attrs .. ' rowspan="' .. (r2 - row + 1) .. '"'
            end
            if c2 > col then
              attrs = attrs .. ' colspan="' .. (c2 - col + 1) .. '"'
            end
          end
          local css = M.style_css (sheet:style_at (row, col))
          if css ~= '' then
            attrs = attrs .. ' style="' .. escape (css) .. '"'
          end
          local text = escape (sheet:display (row, col) or '')
          text = string.gsub (text, '\r?\n', '<br>')
          local link = sheet:link (row, col)
          if web_link (link) then
            text = '<a href="'
              .. escape (link --[[@as string]])
              .. '">'
              .. text
              .. '</a>'
          end
          cells[#cells + 1] = '<td' .. attrs .. '>' .. text .. '</td>'
        end
      end
      rows[#rows + 1] = '<tr>' .. table.concat (cells) .. '</tr>'
    end
  end
  return '<meta charset="utf-8"><table style="border-collapse:collapse">'
    .. table.concat (rows)
    .. '</table>'
end

-------------------------------------------------------------------------------------------
-- Reading
-------------------------------------------------------------------------------------------

local NAMED = {
  black = '#000000',
  white = '#ffffff',
  red = '#ff0000',
  green = '#008000',
  blue = '#0000ff',
  yellow = '#ffff00',
  gray = '#808080',
  grey = '#808080',
  silver = '#c0c0c0',
  maroon = '#800000',
  navy = '#000080',
  purple = '#800080',
  teal = '#008080',
  olive = '#808000',
  orange = '#ffa500',
  windowtext = '#000000',
} ---@type table<string, string>

---A CSS colour as `#rrggbb`, or nil.
---@param v string
---@return string?
function M.color (v)
  local s = string.lower (string.match (v, '^%s*(.-)%s*$') or '')
  local hex = string.match (s, '^#(%x%x%x%x%x%x)$')
  if hex then
    return '#' .. hex
  end
  local a, b, c = string.match (s, '^#(%x)(%x)(%x)$')
  if a then
    return '#' .. a .. a .. b .. b .. c .. c
  end
  local r, g, bl = string.match (s, '^rgba?%(%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)')
  if r then
    return string.format (
      '#%02x%02x%02x',
      math.min (255, tonumber (r) --[[@as integer]]),
      math.min (255, tonumber (g) --[[@as integer]]),
      math.min (255, tonumber (bl) --[[@as integer]])
    )
  end
  return NAMED[s]
end

---A border as the sheet names it, from a CSS border such as `.5pt solid windowtext`. Nil for
---no border, and the colour beside it.
---@param v string
---@return string?
---@return string?
local function border_of (v)
  local s = string.lower (v)
  if string.find (s, 'none', 1, true) or string.find (s, 'hidden', 1, true) then
    return nil
  end
  local color ---@type string?
  for word in string.gmatch (s, '%S+') do
    color = color or M.color (word)
  end
  if string.find (s, 'double', 1, true) then
    return 'double', color
  elseif string.find (s, 'dashed', 1, true) then
    return 'dashed', color
  elseif string.find (s, 'dotted', 1, true) then
    return 'dotted', color
  end
  local n, unit = string.match (s, '([%d%.]+)(p[xt])')
  local px = tonumber (n) or 1
  if unit == 'pt' then
    px = px * 4 / 3
  end
  if not string.find (s, 'solid', 1, true) and not n then
    return nil
  end
  if px >= 3 then
    return 'thick', color
  elseif px > 1.5 then
    return 'medium', color
  end
  return 'thin', color
end

---Reads CSS declarations into a style patch, adding to `into`.
---@param decls string
---@param into table<string, any>
local function read_css (decls, into)
  for name, value in string.gmatch (decls .. ';', '([%w%-]+)%s*:%s*([^;]*);') do
    name = string.lower (name)
    local v = string.lower (string.match (value, '^%s*(.-)%s*$') or '')
    v = string.gsub (v, '%s*!important$', '')
    if name == 'font-weight' then
      into.bold = v == 'bold' or v == 'bolder' or (tonumber (v) or 400) >= 600
    elseif name == 'font-style' then
      into.italic = v == 'italic' or v == 'oblique'
    elseif name == 'text-decoration' or name == 'text-decoration-line' then
      into.underline = string.find (v, 'underline', 1, true) ~= nil
      into.strike = string.find (v, 'line-through', 1, true) ~= nil
    elseif name == 'font-size' then
      local n, unit = string.match (v, '^([%d%.]+)%s*(%a*)')
      local size = tonumber (n)
      if size then
        if unit == 'pt' then
          size = size * 4 / 3
        end
        size = math.floor (size + 0.5)
        -- 10 or 11 points is every program's plain size, which the sheet draws at 13 pixels.
        if size >= 13 and size <= 15 then
          into.size = nil
        else
          into.size = size
        end
      end
    elseif name == 'color' then
      into.color = M.color (v)
    elseif name == 'background-color' or name == 'background' then
      local c = M.color (v)
      if c and c ~= '#ffffff' then
        into.fill = c
      end
    elseif name == 'text-align' then
      if v == 'left' or v == 'center' or v == 'right' then
        into.align = v
      end
    elseif name == 'vertical-align' then
      if v == 'top' or v == 'bottom' then
        into.valign = v
      elseif v == 'middle' then
        into.valign = 'middle'
      end
    elseif name == 'border' then
      local b, c = border_of (v)
      into.border_top, into.border_right = b, b
      into.border_bottom, into.border_left = b, b
      into.border_color = c or into.border_color
    elseif
      name == 'border-top'
      or name == 'border-right'
      or name == 'border-bottom'
      or name == 'border-left'
    then
      local b, c = border_of (v)
      into['border_' .. string.sub (name, 8)] = b
      into.border_color = c or into.border_color
    end
  end
end

local ENTITIES = {
  amp = '&',
  lt = '<',
  gt = '>',
  quot = '"',
  apos = "'",
  nbsp = ' ',
} ---@type table<string, string>

---@param code integer
---@return string
local function utf8_of (code)
  if code < 0x80 then
    return string.char (code)
  elseif code < 0x800 then
    return string.char (0xC0 + math.floor (code / 64), 0x80 + code % 64)
  elseif code < 0x10000 then
    return string.char (
      0xE0 + math.floor (code / 4096),
      0x80 + math.floor (code / 64) % 64,
      0x80 + code % 64
    )
  end
  return string.char (
    0xF0 + math.floor (code / 262144),
    0x80 + math.floor (code / 4096) % 64,
    0x80 + math.floor (code / 64) % 64,
    0x80 + code % 64
  )
end

---Turns entities such as `&amp;` and `&#233;` back into text.
---@param s string
---@return string
function M.unescape (s)
  return (
    string.gsub (s, '&(#?[%w]+);', function (e)
      local hex = string.match (e, '^#[xX](%x+)$')
      local dec = string.match (e, '^#(%d+)$')
      local code = hex and tonumber (hex, 16) or dec and tonumber (dec)
      if code then
        if code == 160 then
          return ' '
        end
        return code < 0x110000 and utf8_of (math.floor (code)) or ''
      end
      return ENTITIES[string.lower (e)]
    end)
  )
end

---The value of one attribute in a tag's text, or nil.
---@param tag string
---@param name string
---@return string?
local function attr (tag, name)
  local lower = string.lower (tag)
  for _, q in ipairs ({ '"', "'" }) do
    local at = string.find (lower, '[%s]' .. name .. '%s*=%s*' .. q)
    if at then
      local open = string.find (tag, q, at, true) --[[@as integer]]
      local close = string.find (tag, q, open + 1, true)
      if close then
        return M.unescape (string.sub (tag, open + 1, close - 1))
      end
    end
  end
  local bare = string.match (tag, '[%s]' .. name .. '%s*=%s*([^%s>"\']+)')
    or string.match (lower, '[%s]' .. name .. '%s*=%s*([^%s>"\']+)')
  return bare and M.unescape (bare) or nil
end

---The text of a cell's HTML: tags out, line breaks for `<br>` and blocks inside the cell, and
---the spaces of HTML folded into one.
---@param html string
---@return string
local function cell_text (html)
  local s = string.gsub (html, '<!%-%-.-%-%->', '')
  s = string.gsub (s, '[\r\n\t]+', ' ')
  s = string.gsub (s, '<[Bb][Rr]%s*/?>', '\n')
  s = string.gsub (s, '</[Pp]>%s*<[Pp][^>]*>', '\n')
  s = string.gsub (s, '</[Dd][Ii][Vv]>%s*<[Dd][Ii][Vv][^>]*>', '\n')
  s = string.gsub (s, '<[^>]*>', '')
  s = string.gsub (s, ' +', ' ')
  s = M.unescape (s)
  s = string.gsub (s, ' *\n *', '\n')
  return (string.match (s, '^%s*(.-)%s*$'))
end

---The rules of `<style>` blocks that name a class, such as Excel's `.xl65 { ... }`.
---@param html string
---@return table<string, string>
local function class_rules (html)
  local out = {} ---@type table<string, string>
  for body in
    string.gmatch (
      html,
      '<[Ss][Tt][Yy][Ll][Ee][^>]*>(.-)</[Ss][Tt][Yy][Ll][Ee]>'
    )
  do
    body = string.gsub (body, '/%*.-%*/', '')
    body = string.gsub (body, '<!%-%-', '')
    body = string.gsub (body, '%-%->', '')
    for selectors, decls in string.gmatch (body, '([^{}]+){([^{}]*)}') do
      for sel in string.gmatch (selectors, '[^,]+') do
        local class = string.match (sel, '^%s*%a*%.([%w_%-]+)%s*$')
        if class then
          out[class] = (out[class] or '') .. ';' .. decls
        end
      end
    end
  end
  return out
end

---The first `<table>` in some HTML as a clip that pastes as typed text with its styles. Nil
---when the HTML holds no table with cells.
---@param html string
---@return Sheet.Clip?
function M.parse (html)
  local start = string.find (string.lower (html), '<table', 1, true)
  if not start then
    return nil
  end
  local classes = class_rules (html)
  local body = string.sub (html, start)
  local stop = string.find (string.lower (body), '</table>', 1, true)
  if stop then
    body = string.sub (body, 1, stop - 1)
  end
  local texts, patches = {}, {} ---@type string[][], Sheet.StylePatch[][]
  local merges, links = {}, {} ---@type Sheet.Rect[], table<integer, string>
  local taken = {} ---@type table<integer, boolean> Cells a span from above already holds.
  local lower = string.lower (body)
  local row = 0
  local pos = 1
  while true do
    local tr = string.find (lower, '<tr[%s>]', pos)
    if not tr then
      break
    end
    local tr_end = string.find (lower, '<tr[%s>]', tr + 3) or (#lower + 1)
    local row_html = string.sub (body, tr, tr_end - 1)
    local row_lower = string.sub (lower, tr, tr_end - 1)
    row = row + 1
    texts[row], patches[row] = texts[row] or {}, patches[row] or {}
    local col = 0
    local p = 1
    while true do
      local a, b = string.find (row_lower, '<t[dh][%s>]', p)
      if not a then
        break
      end
      local tag_end = string.find (row_html, '>', a, true) or #row_html
      local tag = string.sub (row_html, a, tag_end)
      local next_cell = string.find (row_lower, '<t[dh][%s>]', b)
        or (#row_lower + 1)
      local close = string.find (row_lower, '</t[dh]>', tag_end) or next_cell
      local inner =
        string.sub (row_html, tag_end + 1, math.min (close, next_cell) - 1)
      p = math.max (tag_end + 1, math.min (close, next_cell))
      col = col + 1
      while taken[row * KEY + col] do
        texts[row][col] = ''
        col = col + 1
      end
      local patch = {} ---@type table<string, any>
      if string.sub (string.lower (tag), 1, 3) == '<th' then
        patch.bold = true
      end
      local class = attr (tag, 'class')
      if class then
        for name in string.gmatch (class, '%S+') do
          if classes[name] then
            read_css (classes[name], patch)
          end
        end
      end
      local inline = attr (tag, 'style')
      if inline then
        read_css (inline, patch)
      end
      local align = attr (tag, 'align')
      if align and not patch.align then
        align = string.lower (align)
        if align == 'left' or align == 'center' or align == 'right' then
          patch.align = align
        end
      end
      local bg = attr (tag, 'bgcolor')
      if bg and not patch.fill then
        patch.fill = M.color (bg)
      end
      local inner_lower = string.lower (inner)
      if
        string.find (inner_lower, '<b[%s>]')
        or string.find (inner_lower, '<strong[%s>]')
      then
        patch.bold = true
      end
      if
        string.find (inner_lower, '<i[%s>]')
        or string.find (inner_lower, '<em[%s>]')
      then
        patch.italic = true
      end
      local a_tag = string.match (inner, '<[Aa]%s[^>]*>')
      local href = a_tag and attr (a_tag, 'href')
      if href and web_link (href) then
        links[row * KEY + col] = href
      end
      texts[row][col] = cell_text (inner)
      if next (patch) then
        patches[row][col] = patch --[[@as Sheet.StylePatch]]
      end
      local rs =
        math.max (1, math.floor (tonumber (attr (tag, 'rowspan') or '') or 1))
      local cs =
        math.max (1, math.floor (tonumber (attr (tag, 'colspan') or '') or 1))
      rs, cs = math.min (rs, 1000), math.min (cs, 1000)
      if rs > 1 or cs > 1 then
        merges[#merges + 1] =
          { r1 = row, c1 = col, r2 = row + rs - 1, c2 = col + cs - 1 }
        for i = row, row + rs - 1 do
          for j = col, col + cs - 1 do
            if i ~= row or j ~= col then
              taken[i * KEY + j] = true
            end
          end
        end
      end
      while cs > 1 do
        col = col + 1
        texts[row][col] = ''
        cs = cs - 1
      end
    end
    -- Cells a span from above holds at the end of the row.
    while taken[row * KEY + col + 1] do
      col = col + 1
      texts[row][col] = ''
    end
    pos = tr_end
  end
  local any = false
  for _, line in ipairs (texts) do
    if #line > 0 then
      any = true
    end
  end
  if not any then
    return nil
  end
  -- A row that only a span reaches, past the last <tr>.
  local last = row
  for key in pairs (taken) do
    last = math.max (last, math.floor (key / KEY))
  end
  for r = 1, last do
    texts[r] = texts[r] or {}
    patches[r] = patches[r] or {}
  end
  return {
    texts = texts,
    patches = patches,
    merges = merges,
    links = next (links) and links or nil,
    typed = true,
  }
end

return M
