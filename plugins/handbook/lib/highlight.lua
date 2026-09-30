-- lib.highlight: colors code for the Handbook's examples, as HTML. Lua gets keywords, strings,
-- numbers, comments, calls, fields and the standard library. JSON, CSS and anything else
-- gets strings, numbers and comments. Every piece of text is escaped, so the result is safe
-- to put in a page whatever the code holds.

local M = {}

local KEYWORDS = {} ---@type table<string, true>
for word in
  ([[and break do else elseif end for function goto if in local not or repeat return then
  until while]]):gmatch ('%S+')
do
  KEYWORDS[
    word --[[@as string]]
  ] = true
end

local CONSTANTS = { ['true'] = true, ['false'] = true, ['nil'] = true }

local BUILTINS = {} ---@type table<string, true>
for word in
  ([[assert error ipairs next pairs pcall print rawequal rawget rawlen rawset require select
  setmetatable getmetatable tonumber tostring type xpcall load string table math os utf8
  coroutine self]]):gmatch ('%S+')
do
  BUILTINS[
    word --[[@as string]]
  ] = true
end

---@param text string
---@return string
function M.escape (text)
  return (
    text:gsub ('[&<>"\']', {
      ['&'] = '&amp;',
      ['<'] = '&lt;',
      ['>'] = '&gt;',
      ['"'] = '&quot;',
      ["'"] = '&#39;',
    })
  )
end

---@param class string
---@param text string
---@return string
local function span (class, text)
  return '<span class="hb-' .. class .. '">' .. M.escape (text) .. '</span>'
end

---The end of a long bracket that opens at `i`, such as `[[` or `[==[`, or nil.
---@param code string
---@param i integer
---@return integer? stop
local function long_bracket (code, i)
  local equals = code:match ('^%[(=*)%[', i)
  if not equals then
    return nil
  end
  local _, stop = code:find (']' .. equals .. ']', i + #equals + 2, true)
  return stop or #code
end

---The end of a quoted string that opens at `i`. It stops at the end of a line when the
---string never closes, as Lua does.
---@param code string
---@param i integer
---@return integer
local function quoted (code, i)
  local quote = code:sub (i, i)
  local j = i + 1
  while j <= #code do
    local c = code:sub (j, j)
    if c == '\\' then
      j = j + 2
    elseif c == quote then
      return j
    elseif c == '\n' then
      return j - 1
    else
      j = j + 1
    end
  end
  return #code
end

---@param code string
---@param i integer
---@return integer? stop
local function number_at (code, i)
  local hex = code:match ('^0[xX][%x.]+[pP]?[+-]?%d*', i)
  if hex then
    return i + #hex - 1
  end
  local dec = code:match ('^%d*%.?%d+[eE][+-]?%d+', i)
    or code:match ('^%d+%.?%d*', i)
    or code:match ('^%.%d+', i)
  return dec and (i + #dec - 1) or nil
end

---Lua as HTML.
---@param code string
---@return string
function M.lua (code)
  local out = {} ---@type string[]
  local i, n = 1, #code
  local last = '' -- The last character that was not a space, to spot `.name` and `:name`.
  local after_function = false
  while i <= n do
    local c = code:sub (i, i)
    if code:sub (i, i + 1) == '--' then
      local stop = long_bracket (code, i + 2)
      if not stop then
        stop = (code:find ('\n', i, true) or (n + 1)) - 1
      end
      out[#out + 1] = span ('c', code:sub (i, stop))
      i = stop + 1
    elseif c == '"' or c == "'" then
      local stop = quoted (code, i)
      out[#out + 1] = span ('s', code:sub (i, stop))
      i, last = stop + 1, c
    elseif c == '[' and long_bracket (code, i) then
      local stop = long_bracket (code, i) --[[@as integer]]
      out[#out + 1] = span ('s', code:sub (i, stop))
      i, last = stop + 1, ']'
    elseif c:match ('[%a_]') then
      local word = code:match ('^[%a_][%w_]*', i)
      local next_char = code:match ('^%s*(.)', i + #word) or ''
      local class ---@type string?
      if last == '.' or last == ':' then
        class = (
          next_char == '('
          or next_char == '{'
          or next_char == "'"
          or next_char == '"'
        )
            and 'f'
          or 'p'
      elseif KEYWORDS[word] then
        class = 'k'
      elseif CONSTANTS[word] then
        class = 'o'
      elseif after_function or next_char == '(' then
        class = 'f'
      elseif BUILTINS[word] then
        class = 'b'
      end
      out[#out + 1] = class and span (class, word) or M.escape (word)
      after_function = word == 'function'
      i, last = i + #word, 'a'
    elseif
      c:match ('%d') or (c == '.' and code:sub (i + 1, i + 1):match ('%d'))
    then
      local stop = number_at (code, i) or i
      out[#out + 1] = span ('n', code:sub (i, stop))
      i, last = stop + 1, '0'
    else
      out[#out + 1] = M.escape (c)
      if not c:match ('%s') then
        last = c
        if c ~= '.' and c ~= ':' then
          after_function = false
        end
      end
      i = i + 1
    end
  end
  return table.concat (out)
end

---Code in a language the Handbook does not know, with only strings, numbers and comments.
---@param code string
---@param comment? string The line comment, such as `//` or `#`.
---@return string
local function simple (code, comment)
  local out = {} ---@type string[]
  local i, n = 1, #code
  while i <= n do
    local c = code:sub (i, i)
    if code:sub (i, i + 1) == '/*' then
      local _, stop = code:find ('*/', i + 2, true)
      stop = stop or n
      out[#out + 1] = span ('c', code:sub (i, stop))
      i = stop + 1
    elseif comment and code:sub (i, i + #comment - 1) == comment then
      local stop = (code:find ('\n', i, true) or (n + 1)) - 1
      out[#out + 1] = span ('c', code:sub (i, stop))
      i = stop + 1
    elseif c == '"' or c == "'" then
      local stop = quoted (code, i)
      out[#out + 1] = span ('s', code:sub (i, stop))
      i = stop + 1
    elseif c:match ('%d') and not code:sub (i - 1, i - 1):match ('[%w_%-]') then
      local stop = number_at (code, i) or i
      out[#out + 1] = span ('n', code:sub (i, stop))
      i = stop + 1
    else
      local stop = (code:find ('[/"\'%d#-]', i + 1) or (n + 1)) - 1
      out[#out + 1] = M.escape (code:sub (i, stop))
      i = stop + 1
    end
  end
  return table.concat (out)
end

-- JSON and CSS have no line comment, and every language here has `/* */` or none.
local COMMENTS = {
  js = '//',
  javascript = '//',
  ts = '//',
  typescript = '//',
  rust = '//',
  glsl = '//',
  wgsl = '//',
  toml = '#',
  yaml = '#',
  sh = '#',
  bash = '#',
  python = '#',
}

---Code as HTML, colored for its language when the Handbook knows it.
---@param code string
---@param lang? string
---@return string
function M.html (code, lang)
  lang = (lang or ''):lower ()
  if lang == 'lua' or lang == 'luau' then
    return M.lua (code)
  end
  if lang == '' or lang == 'text' or lang == 'txt' or lang == 'markdown' then
    return M.escape (code)
  end
  return simple (code, COMMENTS[lang])
end

return M
