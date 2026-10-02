-- sheet_xml: the XML the Sheet app's Excel files are made of. `parse_xml` reads a document into
-- a tree of elements, the helpers find children and attributes whatever namespace prefix a
-- file gives them, and the writing helpers make text safe for an element or an attribute. The
-- module is pure, and keeps to what Excel files need: no DTDs and no namespaces resolved.

---An element of an XML document.
---@class Sheet.XmlNode
---@field name string The tag as written, prefix included, such as `x:c`.
---@field attrs table<string, string>
---@field children Sheet.XmlNode[]
---@field text string The text directly inside the element, with entities decoded.

---@class Sheet.XmlModule
local M = {}

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
  -- XML has no NUL character, and a cell never holds one.
  if code == 0 then
    return ''
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

---------------------------------------------------------------------------------------------
-- Writing XML
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
  s = string.gsub (s, '[&<>]', TEXT_ESCAPES)
  -- After the escapes, so the reference itself is not escaped again.
  return (string.gsub (s, '\r', '&#13;'))
end

M.bare = bare
M.child = child
M.children = children
M.prefixed = prefixed
M.flag = flag
M.int = int
M.utf8_only = utf8_only
M.attr = attr
M.cell_string = cell_string
M.formula_text = formula_text

return M
