-- markup: the parts of the plugin that only read and write text. Nothing here calls the
-- app, so the tests reach all of it.
--
--   skeleton   the HTML5 page that `!` and `html:5` complete to
--   closing    the closing tag for the element that is still open
--   page       the HTML the preview shows, with or without its scripts

-- Elements that never have a closing tag.
local VOID = {
  area = true,
  base = true,
  br = true,
  col = true,
  embed = true,
  hr = true,
  img = true,
  input = true,
  link = true,
  meta = true,
  source = true,
  track = true,
  wbr = true,
}

-- Elements whose content is text up to their closing tag, so a `<` inside starts no tag.
local RAW = { script = true, style = true, textarea = true, title = true }

-- The page the skeleton completion writes, one line at a time.
local SKELETON = {
  '<!doctype html>',
  '<html lang="en">',
  '  <head>',
  '    <meta charset="utf-8" />',
  '    <meta name="viewport" content="width=device-width, initial-scale=1" />',
  '    <title>Document</title>',
  '  </head>',
  '  <body>',
  '  </body>',
  '</html>',
}

-- Goes first in every preview. It keeps the page where it was scrolled when the preview
-- shows a new version: the page reports where it is, and the plugin sends that back to the
-- next version.
-- lang=html
local KEEP_SCROLL = [[<script>
(() => {
  let y = 0;
  let loaded = false;
  proteus.on((m) => {
    if (m && m.type === 'scroll' && typeof m.y === 'number') {
      y = m.y;
      if (loaded) scrollTo(0, y);
    }
  });
  addEventListener('load', () => {
    loaded = true;
    scrollTo(0, y);
  });
  let wait = 0;
  addEventListener('scroll', () => {
    clearTimeout(wait);
    wait = setTimeout(() => proteus.post({ type: 'scroll', y: scrollY }), 150);
  });
})();
</script>]]

-- With scripts off, this follows the scroll keeper. The page's script elements are gone
-- already. This also stops what is left, such as `onclick` attributes.
local NO_SCRIPTS =
  [[<meta http-equiv="Content-Security-Policy" content="script-src 'none'">]]

---@class LangHtml.Markup
local M = {}

---How many UTF-16 units a UTF-8 string takes. The editor counts columns this way.
---@param s string
---@return integer
function M.units (s)
  local n = 0
  for i = 1, #s do
    local b = s:byte (i)
    if b < 0x80 or (b >= 0xC0 and b < 0xF0) then
      n = n + 1
    elseif b >= 0xF0 then
      n = n + 2
    end
  end
  return n
end

---How many bytes of a line come before a column the editor gives in UTF-16 units.
---@param line string
---@param units integer
---@return integer
function M.byte_col (line, units)
  local i, n = 1, 0
  while i <= #line and n < units do
    local b = line:byte (i)
    local size = b >= 0xF0 and 4 or b >= 0xE0 and 3 or b >= 0xC0 and 2 or 1
    n = n + (size == 4 and 2 or 1)
    i = i + size
  end
  return i - 1
end

---The text before a position, and the part of its line before it.
---@param text string
---@param pos Proteus.CodePosition
---@return string before
---@return string line_before
function M.before (text, pos)
  local start = 1
  for _ = 1, pos.line do
    local nl = text:find ('\n', start, true)
    if not nl then
      break
    end
    start = nl + 1
  end
  local stop = text:find ('\n', start, true)
  local line = text:sub (start, stop and stop - 1 or #text)
  local line_before = line:sub (1, M.byte_col (line, pos.character))
  return text:sub (1, start - 1) .. line_before, line_before
end

---The HTML5 page, with each line after the first indented like the first.
---@param indent string
---@return string
function M.skeleton_text (indent)
  return table.concat (SKELETON, '\n' .. indent)
end

---The skeleton completion, when the line so far holds only `!` or the start of `html:5`.
---@param line_before string The line up to the cursor.
---@return Proteus.CompletionItem? item
---@return integer? from The column the item replaces from, in UTF-16 units.
function M.skeleton (line_before)
  local indent, word = line_before:match ('^(%s*)(%S+)$')
  if not word then
    return nil, nil
  end
  local label = nil ---@type string?
  if word == '!' then
    label = '!'
  elseif #word >= 4 and ('html:5'):sub (1, #word) == word then
    label = 'html:5'
  end
  if not label then
    return nil, nil
  end
  local text = M.skeleton_text (indent)
  return {
    label = label,
    kind = 'snippet',
    detail = 'HTML5 page',
    documentation = '```html\n' .. M.skeleton_text ('') .. '\n```',
    insert = text,
  },
    M.units (indent)
end

---Where a tag that starts before `from` ends: its `>`, past any `>` inside quotes.
---@param text string
---@param from integer
---@return integer?
local function tag_end (text, from)
  local i = from
  while true do
    local at = text:find ('[\'">]', i)
    if not at then
      return nil
    end
    local c = text:sub (at, at)
    if c == '>' then
      return at
    end
    local close = text:find (c, at + 1, true)
    if not close then
      return nil
    end
    i = close + 1
  end
end

---Takes an element off the list of open ones, with every element opened inside it.
---@param open string[]
---@param name string In lower case.
local function close_element (open, name)
  for k = #open, 1, -1 do
    if open[k]:lower () == name then
      for j = #open, k, -1 do
        open[j] = nil
      end
      return
    end
  end
end

---The element still open at the end of the text, as its tag spells it, or nil. Comments,
---void elements such as `<br>`, and tags that close themselves open nothing.
---@param text string
---@return string?
function M.open_element (text)
  local lower = text:lower ()
  local open = {} ---@type string[]
  local i = 1
  while true do
    local lt = text:find ('<', i, true)
    if not lt then
      break
    end
    local after = text:sub (lt + 1, lt + 1)
    if text:sub (lt, lt + 3) == '<!--' then
      local close = text:find ('-->', lt + 4, true)
      if not close then
        return nil
      end
      i = close + 3
    elseif after == '!' or after == '?' or after == '/' then
      local close = text:find ('>', lt, true)
      if not close then
        break
      end
      local name = after == '/' and lower:match ('^</([%w:%-]+)', lt) or nil
      if name then
        close_element (open, name)
      end
      i = close + 1
    else
      local name = text:match ('^<(%a[%w:%-]*)', lt)
      local close = name and tag_end (text, lt + 1 + #name)
      if not name then
        i = lt + 1
      elseif not close then
        break
      else
        local key = name:lower ()
        local closes_itself = text:sub (close - 1, close - 1) == '/'
        i = close + 1
        if RAW[key] and not closes_itself then
          local finish = lower:find ('</' .. key, i, true)
          if not finish then
            return name
          end
          i = (text:find ('>', finish, true) or #text) + 1
        elseif not VOID[key] and not closes_itself then
          open[#open + 1] = name
        end
      end
    end
  end
  return open[#open]
end

---The closing tag completion, when the line so far ends in `</` and maybe part of a name.
---@param before string The whole text up to the cursor.
---@param line_before string The line up to the cursor.
---@return Proteus.CompletionItem? item
---@return integer? from The column the item replaces from, in UTF-16 units.
function M.closing (before, line_before)
  local lt, typed = line_before:match ('()</([%w:%-]*)$')
  if not lt then
    return nil, nil
  end
  local typed_bytes = #line_before - lt + 1
  local name = M.open_element (before:sub (1, #before - typed_bytes))
  if not name or name:lower ():sub (1, #typed) ~= typed:lower () then
    return nil, nil
  end
  local tag = '</' .. name .. '>'
  return { label = tag, kind = 'keyword', detail = 'closing tag', insert = tag },
    M.units (line_before:sub (1, lt - 1))
end

---Snippet text as plain text: `${1:name}` becomes `name`, `${1|a,b|}` becomes `a`, and
---`$1`, `${1}` and `$0` go.
---@param text string
---@return string
function M.plain_snippet (text)
  local out = text:gsub ('\\%$', '\1')
  out = out:gsub ('%${%d+:([^}]*)}', '%1')
  out = out:gsub ('%${%d+|([^,|]*)[^}]*}', '%1')
  out = out:gsub ('%${%d+}', '')
  out = out:gsub ('%$%d+', '')
  out = out:gsub ('\1', '$')
  return out
end

---The HTML without its script elements.
---@param html string
---@return string
function M.strip_scripts (html)
  local lower = html:lower ()
  local parts = {} ---@type string[]
  local i = 1
  while true do
    local open = lower:find ('<script[%s>/]', i)
    if not open then
      break
    end
    parts[#parts + 1] = html:sub (i, open - 1)
    local _, finish = lower:find ('</script%s*>', open)
    if not finish then
      i = #html + 1
      break
    end
    i = finish + 1
  end
  parts[#parts + 1] = html:sub (i)
  return table.concat (parts)
end

---The page the preview shows: the file's HTML, after its doctype the scroll keeper, and
---without scripts unless they may run.
---@param html string
---@param scripts boolean
---@return string
function M.page (html, scripts)
  local body = scripts and html or M.strip_scripts (html)
  local head = KEEP_SCROLL .. (scripts and '' or NO_SCRIPTS)
  local _, doctype = body:lower ():find ('^%s*<!doctype[^>]*>')
  if doctype then
    return body:sub (1, doctype) .. head .. body:sub (doctype + 1)
  end
  return head .. body
end

---True for a path the preview and the extra completion are for: `.html` and `.htm`.
---@param path string
---@return boolean
function M.is_page (path)
  return path:lower ():match ('%.html?$') ~= nil
end

return M
