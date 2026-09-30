-- lib.reference: turns a type file for lua-language-server, such as the app's
-- types/services.lua, into a handbook page. Each `---@class` and `---@alias` becomes a
-- heading with its fields or values, and each function below a class becomes a heading
-- with its signature, parameters and return values. Anchors follow the names, so
-- `types/services.md#proteus.commands.register` reaches `Commands.register`.

local page = require ('lib.page')

local M = {}

---@class Handbook.RefField
---@field name string
---@field type string
---@field text string

---@class Handbook.RefItem
---@field kind 'class'|'alias'|'function'|'group'
---@field name string For a function, `Class.name`.
---@field call? string For a function, how it is called, such as `Commands.register (spec)`.
---@field text string[] Description lines, as Markdown.
---@field fields Handbook.RefField[] A class's fields, an alias's values, or a function's parameters.
---@field returns Handbook.RefField[]
---@field overloads string[]
---@field type? string An alias's type, when it is one line.

---Reads a type from `s` at `i`: up to a space outside brackets, except that `|`, `,` and a
---`:` after `fun(...)` carry it on.
---@param s string
---@param i integer
---@return string type
---@return integer next
function M.read_type (s, i)
  local depth, j, n = 0, i, #s
  while j <= n do
    local c = s:sub (j, j)
    if c == '(' or c == '<' or c == '{' or c == '[' then
      depth = depth + 1
    elseif c == ')' or c == '>' or c == '}' or c == ']' then
      depth = math.max (depth - 1, 0)
    elseif c:match ('%s') and depth == 0 then
      local before = s:sub (i, j - 1):match ('(%S)%s*$') or ''
      local after = s:match ('^%s*(%S)', j) or ''
      if
        not (before == '|' or before == ',' or before == ':' or after == '|')
      then
        break
      end
    elseif c == '#' and depth == 0 then
      break
    end
    j = j + 1
  end
  return (s:sub (i, j - 1):gsub ('%s+$', '')), j
end

---Splits `name type text` from a `@field` or `@param` tag.
---@param rest string
---@return Handbook.RefField
local function field_of (rest)
  local name, after = rest:match ('^%s*(%S+)()')
  if not name then
    return { name = '', type = '', text = '' }
  end
  local t, next_i = M.read_type (rest, after + #(rest:match ('^%s*', after)))
  local text = rest:sub (next_i):gsub ('^%s*#?%s*', '')
  return { name = name, type = t, text = text }
end

---Splits `type [name] text` from a `@return` tag. A lower case word after the type names
---the value.
---@param rest string
---@return Handbook.RefField
local function return_of (rest)
  local start = #(rest:match ('^%s*')) + 1
  local t, next_i = M.read_type (rest, start)
  local tail = rest:sub (next_i):gsub ('^%s*#?%s*', '')
  local name, text = tail:match ('^([%l_][%w_]*)%s*(.*)$')
  if name and not text:match ('^%l') then
    return { name = name, type = t, text = text }
  end
  return { name = '', type = t, text = tail }
end

---Reads a type file into items, in the order the file has them.
---@param text string
---@return Handbook.RefItem[] items
---@return string intro The comment at the top of the file.
function M.read (text)
  local items = {} ---@type Handbook.RefItem[]
  local locals = {} ---@type table<string, string>
  local intro = {} ---@type string[]
  local lines = {} ---@type string[]
  for line in (text:gsub ('\r\n', '\n') .. '\n'):gmatch ('([^\n]*)\n') do
    lines[#lines + 1] = line
  end

  local desc = {} ---@type string[]
  local current ---@type Handbook.RefItem?
  local fn ---@type Handbook.RefItem?
  local started = false

  ---@return Handbook.RefItem
  local function pending_fn ()
    if not fn then
      fn = {
        kind = 'function',
        name = '',
        text = desc,
        fields = {},
        returns = {},
        overloads = {},
      }
      desc = {}
    end
    return fn
  end

  local function reset ()
    desc, current, fn = {}, nil, nil
  end

  local i = 1
  while i <= #lines do
    local line = lines[i]
    local banner = line:match ('^%-%-%-%-%-%-%-%-%-%-+$')
    local doc = not banner and line:match ('^%-%-%-(.*)$')
    if banner then
      local title = (lines[i + 1] or ''):match ('^%-%-%s+(.-)%s*$')
      if title and (lines[i + 2] or ''):match ('^%-%-%-%-%-%-%-%-%-%-+$') then
        items[#items + 1] = {
          kind = 'group',
          name = title,
          text = {},
          fields = {},
          returns = {},
          overloads = {},
        }
        i = i + 2
      end
      reset ()
      started = true
    elseif doc then
      local tag, rest = doc:match ('^@(%w+)%s*(.*)$') ---@type string?, string
      started = started or tag ~= 'meta'
      if tag == 'meta' then
        reset ()
      elseif doc:match ('^|') then
        if current and current.kind == 'alias' then
          local value, note = doc:match ('^|%s*(.-)%s*#%s*(.*)$') ---@type string?, string?
          value = value or doc:match ('^|%s*(.-)%s*$')
          current.fields[#current.fields + 1] =
            { name = '', type = value, text = note or '' }
        end
      elseif tag == 'class' then
        local name = rest:match ('^([%w_.]+)') ---@type string?
        current = {
          kind = 'class',
          name = name or rest,
          text = desc,
          fields = {},
          returns = {},
          overloads = {},
        }
        items[#items + 1] = current
        desc, fn = {}, nil
      elseif tag == 'alias' then
        local name, t = rest:match ('^([%w_.]+)%s*(.*)$') ---@type string?, string
        current = {
          kind = 'alias',
          name = name or rest,
          text = desc,
          fields = {},
          returns = {},
          overloads = {},
          type = t ~= '' and t or nil,
        }
        items[#items + 1] = current
        desc, fn = {}, nil
      elseif tag == 'field' and current and current.kind == 'class' then
        current.fields[#current.fields + 1] = field_of (rest)
      elseif tag == 'param' then
        local f = pending_fn ()
        f.fields[#f.fields + 1] = field_of (rest)
      elseif tag == 'return' then
        local f = pending_fn ()
        f.returns[#f.returns + 1] = return_of (rest)
      elseif tag == 'overload' then
        local f = pending_fn ()
        f.overloads[#f.overloads + 1] = rest
      elseif tag then
        -- @type, @generic and the rest say nothing a reader needs.
      else
        if fn then
          fn.text[#fn.text + 1] = doc
        else
          desc[#desc + 1] = doc
        end
        current = nil
      end
    else
      local var = line:match ('^local%s+([%w_]+)%s*=%s*{%s*}')
      local last = items[#items]
      if var and last and last.kind == 'class' then
        locals[var] = last.name
      end
      local owner, sep, name, args =
        line:match ('^function%s+([%w_]+)([.:])([%w_]+)%s*(%b())')
      if owner then
        local f = pending_fn ()
        f.name = (locals[owner] or owner) .. '.' .. name
        f.call = (sep == ':' and owner:lower () or owner)
          .. sep
          .. name
          .. ' '
          .. args
        items[#items + 1] = f
      elseif not started then
        local comment = line:match ('^%-%-%s?(.*)$')
        if comment then
          intro[#intro + 1] = comment
        end
      end
      if line:match ('%S') or owner then
        reset ()
      end
      if line:match ('%S') and not line:match ('^%-%-') then
        started = true
      end
    end
    i = i + 1
  end
  return items, table.concat (intro, '\n')
end

---Writes a type as Markdown, linking the names `link` knows.
---@param t string
---@param link fun(name: string): string?
---@return string
local function type_md (t, link)
  if t == '' then
    return ''
  end
  local out = {} ---@type string[]
  local plain = {} ---@type string[]
  local function flush ()
    local s = table.concat (plain)
    plain = {}
    if s ~= '' then
      local ticks = s:find ('`') and '``' or '`'
      local pad = ticks == '``' and ' ' or ''
      out[#out + 1] = ticks .. pad .. s .. pad .. ticks
    end
  end
  local i = 1
  while i <= #t do
    local s, e = t:find ('[%a_][%w_]*[%w_.]*', i)
    if not s then
      plain[#plain + 1] = t:sub (i)
      break
    end
    plain[#plain + 1] = t:sub (i, s - 1)
    local name = t:sub (s, e)
    local target = name:find ('%.') and link (name) or nil
    if target then
      flush ()
      out[#out + 1] = '[`' .. name .. '`](' .. target .. ')'
    else
      plain[#plain + 1] = name
    end
    i = e + 1
  end
  flush ()
  return table.concat (out)
end

---@param f Handbook.RefField
---@param link fun(name: string): string?
---@return string
local function field_md (f, link)
  local parts = {} ---@type string[]
  if f.name ~= '' then
    parts[#parts + 1] = '**`' .. f.name .. '`**'
  end
  if f.type ~= '' then
    parts[#parts + 1] = type_md (f.type, link)
  end
  local line = '- ' .. table.concat (parts, ' ')
  if f.text ~= '' then
    line = line .. ' — ' .. f.text
  end
  return line
end

---@class Handbook.RefOptions
---@field title string The page's title.
---@field source string Where the types come from, such as `types/services.lua`.
---@field link? fun(name: string): string? A link for a class or alias name, if the Handbook knows one.

---Builds a page's Markdown from a type file.
---@param text string
---@param opts Handbook.RefOptions
---@return string markdown
---@return string[] names Every class and alias the file defines.
function M.build (text, opts)
  local items, intro = M.read (text)
  local link = opts.link or function ()
    return nil
  end
  local out = { '# ' .. opts.title, '' } ---@type string[]
  if intro ~= '' then
    out[#out + 1] = intro
    out[#out + 1] = ''
  end
  out[#out + 1] = 'Built from `'
    .. opts.source
    .. '` as the app runs, so it always matches the app.'
  out[#out + 1] = ''
  local names = {} ---@type string[]
  for _, item in ipairs (items) do
    if item.kind == 'group' then
      out[#out + 1] = '## ' .. item.name
    elseif item.kind == 'class' or item.kind == 'alias' then
      names[#names + 1] = item.name
      out[#out + 1] = '### ' .. item.name
    else
      out[#out + 1] = '#### ' .. item.name
      out[#out + 1] = ''
      out[#out + 1] = '`' .. (item.call or item.name) .. '`'
    end
    out[#out + 1] = ''
    if #item.text > 0 then
      out[#out + 1] = table.concat (item.text, '\n')
      out[#out + 1] = ''
    end
    if item.kind == 'alias' and item.type then
      out[#out + 1] = type_md (item.type, link)
      out[#out + 1] = ''
    end
    if #item.fields > 0 then
      if item.kind == 'function' then
        out[#out + 1] = '**Parameters**'
        out[#out + 1] = ''
      end
      for _, f in ipairs (item.fields) do
        out[#out + 1] = field_md (f, link)
      end
      out[#out + 1] = ''
    end
    if #item.returns > 0 then
      out[#out + 1] = '**Returns**'
      out[#out + 1] = ''
      for _, f in ipairs (item.returns) do
        out[#out + 1] = field_md (f, link)
      end
      out[#out + 1] = ''
    end
    if #item.overloads > 0 then
      out[#out + 1] = '**Also called as**'
      out[#out + 1] = ''
      for _, o in ipairs (item.overloads) do
        out[#out + 1] = '- ' .. type_md (o, link)
      end
      out[#out + 1] = ''
    end
  end
  return table.concat (out, '\n'), names
end

---The names of the classes and aliases a type file defines, without building the page.
---@param text string
---@return string[]
function M.names (text)
  local names = {} ---@type string[]
  for line in text:gmatch ('[^\n]+') do
    local name = line:match ('^%-%-%-@class%s+([%w_.]+)')
      or line:match ('^%-%-%-@alias%s+([%w_.]+)')
    if name then
      names[#names + 1] = name
    end
  end
  return names
end

M.slug = page.slug

return M
