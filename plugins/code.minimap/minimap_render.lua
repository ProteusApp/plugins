-- minimap_render: turns a file's text into the HTML of its minimap.
--
-- Each line becomes one line of a `pre`, with comments, strings, keywords, constants and
-- numbers wrapped in spans the stylesheet colors. It is a small scanner, not a parser, so a
-- language only needs its comment and string markers and a few keywords. A comment or string
-- that runs past the end of a line carries over to the next, so each line is drawn from the
-- state the line before left. A painter keeps each line it has drawn, so typing redraws only
-- the lines that changed.

---How one language looks to the scanner.
---@class Minimap.Spec
---@field line? string[] What starts a comment that runs to the end of the line.
---@field block? string[][] Pairs that open and close a comment, which may span lines.
---@field quotes? string[] Characters that open and close a string on one line.
---@field long? string[][] Pairs that open and close a string, which may span lines.
---@field raw? boolean True when a backslash in a `long` string escapes nothing, as in Lua.
---@field keywords? table<string, true>
---@field constants? table<string, true>
---@field fold? boolean Matches keywords in any case, as SQL does.
---@field heading? boolean A line that starts with `#` is a heading, as in Markdown.

---What a painter hands back.
---@class Minimap.Picture
---@field html string The lines, ready for a `pre`.
---@field lines integer How many lines the file has.
---@field drawn integer How many of them `html` holds.

---@class Minimap.Painter
---@field paint fun(text: string, language: string): Minimap.Picture

---@class Minimap.RenderModule
---@field MAX_LINES integer
---@field MAX_COLS integer
---@field spec_for fun(language: string): Minimap.Spec
---@field line fun(spec: Minimap.Spec, text: string, state: string): string, string
---@field painter fun(): Minimap.Painter
---@field line_at fun(y: number, line_height: number, lines: integer): integer

local M = {}

-- A longer file is drawn up to this line, so a huge log does not stall the editor.
M.MAX_LINES = 10000
-- Characters past this column are too small to see, so they are not drawn.
M.MAX_COLS = 160
-- A painter forgets its lines once it holds this many, so memory stays flat.
local MAX_KEPT = 40000

---@param words string
---@return table<string, true>
local function set (words)
  local out = {}
  for w in words:gmatch ('%S+') do
    out[w] = true
  end
  return out
end

local C_KEYWORDS = set ([[
  abstract as async await break case catch chan class const continue def default defer
  delete do else enum export extends extern final finally fn for from func function go goto
  if impl implements import in instanceof interface internal let loop match mod module
  mut namespace new of override package private protected pub public range return sealed
  select static struct super switch template this throw throws trait try type typedef
  typename typeof union unsafe use using val var virtual void volatile when where while
  with yield]])
local C_CONSTANTS = set ('true false null nil undefined None NaN Infinity')

local LUA = {
  line = { '--' },
  block = { { '--[[', ']]' }, { '--[=[', ']=]' }, { '--[==[', ']==]' } },
  quotes = { '"', "'" },
  long = { { '[[', ']]' }, { '[=[', ']=]' }, { '[==[', ']==]' } },
  raw = true,
  keywords = set ([[
    and break do else elseif end for function goto if in local not or repeat return then
    until while]]),
  constants = set ('true false nil self'),
}

local C_LIKE = {
  line = { '//' },
  block = { { '/*', '*/' } },
  quotes = { '"', "'" },
  keywords = C_KEYWORDS,
  constants = C_CONSTANTS,
}

local JS = {
  line = { '//' },
  block = { { '/*', '*/' } },
  quotes = { '"', "'" },
  long = { { '`', '`' } },
  keywords = C_KEYWORDS,
  constants = C_CONSTANTS,
}

local PYTHON = {
  line = { '#' },
  quotes = { '"', "'" },
  long = { { '"""', '"""' }, { "'''", "'''" } },
  keywords = set ([[
    and as assert async await break class continue def del elif else except finally for
    from global if import in is lambda match nonlocal not or pass raise return try while
    with yield]]),
  constants = set ('True False None self'),
}

local SHELL = {
  line = { '#' },
  quotes = { '"', "'" },
  keywords = set ([[
    case do done elif else esac export fi for function if in local return select then
    until while begin process end param foreach]]),
  constants = set ('true false $true $false $null'),
}

local RUBY = {
  line = { '#' },
  quotes = { '"', "'" },
  keywords = set ([[
    begin break case class def do else elsif end ensure for if in module next redo rescue
    retry return then unless until when while yield]]),
  constants = set ('true false nil self'),
}

local HASH_DATA = {
  line = { '#' },
  quotes = { '"', "'" },
  constants = set ('true false null yes no on off'),
}

local INI = {
  line = { ';', '#' },
  quotes = { '"' },
  constants = set ('true false yes no on off'),
}

local SQL = {
  line = { '--' },
  block = { { '/*', '*/' } },
  quotes = { "'", '"' },
  fold = true,
  keywords = set ([[
    add alter and as asc begin between by case commit create cross delete desc distinct drop
    else end exists from full group having if in index inner insert into is join key left
    like limit not null on or order outer primary references returning right rollback
    select set table then union unique update values view when where with]]),
  constants = set ('true false null'),
}

local HASKELL = {
  line = { '--' },
  block = { { '{-', '-}' } },
  quotes = { '"' },
  keywords = set ([[
    case class data deriving do else if import in infix infixl infixr instance let module
    newtype of then type where]]),
  constants = set ('True False Nothing Just'),
}

local ML = {
  block = { { '(*', '*)' } },
  line = { '//' },
  quotes = { '"' },
  keywords = set ([[
    and as begin do done else end exception for fun function if in let match module mutable
    of open rec struct then to type val when while with]]),
  constants = set ('true false'),
}

local LISP = {
  line = { ';' },
  quotes = { '"' },
  keywords = set (
    'def defn defun defmacro define lambda let if cond when unless loop do fn ns'
  ),
  constants = set ('nil t true false'),
}

local ERLANG = {
  line = { '%' },
  quotes = { '"' },
  keywords = set ('after begin case catch end fun if of receive try when'),
  constants = set ('true false undefined'),
}

local CSS = {
  block = { { '/*', '*/' } },
  quotes = { '"', "'" },
}

local MARKUP = {
  block = { { '<!--', '-->' } },
  quotes = { '"', "'" },
}

local MARKDOWN = {
  block = { { '<!--', '-->' } },
  heading = true,
}

local PLAIN = {}

-- The editor's language names, from proteus.editor.core.
local SPECS = {
  lua = LUA,
  javascript = JS,
  typescript = JS,
  jsx = JS,
  tsx = JS,
  json = C_LIKE,
  c = C_LIKE,
  cpp = C_LIKE,
  csharp = C_LIKE,
  java = C_LIKE,
  kotlin = C_LIKE,
  scala = C_LIKE,
  dart = C_LIKE,
  go = JS,
  rust = C_LIKE,
  swift = C_LIKE,
  groovy = C_LIKE,
  protobuf = C_LIKE,
  python = PYTHON,
  shell = SHELL,
  powershell = SHELL,
  dockerfile = HASH_DATA,
  ruby = RUBY,
  perl = RUBY,
  r = HASH_DATA,
  julia = PYTHON,
  cmake = HASH_DATA,
  yaml = HASH_DATA,
  toml = HASH_DATA,
  ini = INI,
  sql = SQL,
  haskell = HASKELL,
  elm = HASKELL,
  ocaml = ML,
  fsharp = ML,
  clojure = LISP,
  scheme = LISP,
  commonlisp = LISP,
  erlang = ERLANG,
  css = CSS,
  sass = CSS,
  html = MARKUP,
  xml = MARKUP,
  markdown = MARKDOWN,
}

---The scanner's view of a language. An unknown language, or `text`, is drawn plain.
---@param language string
---@return Minimap.Spec
function M.spec_for (language)
  return SPECS[language] or PLAIN
end

local ESCAPES = { ['&'] = '&amp;', ['<'] = '&lt;', ['>'] = '&gt;' }

---Collects a line's HTML, joining text of the same kind into one span, and stops at the
---last column worth drawing.
---@return fun(kind: string, text: string), fun(): string
local function writer ()
  local out, n = {}, 0
  local kind, buf = '', {}
  local cols = 0
  local function flush ()
    if #buf == 0 then
      return
    end
    local text = table.concat (buf):gsub ('[&<>]', ESCAPES)
    n = n + 1
    out[n] = kind == '' and text
      or ('<span class="' .. kind .. '">' .. text .. '</span>')
    buf = {}
  end
  local function put (k, text)
    if cols >= M.MAX_COLS or text == '' then
      return
    end
    if cols + #text > M.MAX_COLS then
      text = text:sub (1, M.MAX_COLS - cols)
    end
    cols = cols + #text
    if k ~= kind then
      flush ()
      kind = k
    end
    buf[#buf + 1] = text
  end
  local function finish ()
    flush ()
    return table.concat (out)
  end
  return put, finish
end

---Where `close` next appears in `text` from `from`, skipping characters a backslash escapes
---unless `raw`. Returns the position just past it, or nil when the line ends first.
---@param text string
---@param from integer
---@param close string
---@param raw boolean
---@return integer?
local function find_close (text, from, close, raw)
  local i = from
  while i <= #text do
    if not raw and text:sub (i, i) == '\\' then
      i = i + 2
    elseif text:sub (i, i + #close - 1) == close then
      return i + #close
    else
      i = i + 1
    end
  end
  return nil
end

---The first of `pairs` whose opener sits at `i`, longest first.
---@param text string
---@param i integer
---@param list string[][]
---@return integer?
local function opener_at (text, i, list)
  local best, best_len = nil, 0
  for n, pair in ipairs (list) do
    local open = pair[1]
    if #open > best_len and text:sub (i, i + #open - 1) == open then
      best, best_len = n, #open
    end
  end
  return best
end

---@param text string
---@param i integer
---@param list? string[]
---@return boolean
local function starts_with_any (text, i, list)
  if not list then
    return false
  end
  for _, mark in ipairs (list) do
    if text:sub (i, i + #mark - 1) == mark then
      return true
    end
  end
  return false
end

---Draws one line. `state` is what the line before left open: `''` for nothing, `'c<n>'` for
---the nth block comment, or `'s<n>'` for the nth long string. Returns the line's HTML and the
---state it leaves for the next line.
---@param spec Minimap.Spec
---@param text string
---@param state string
---@return string html
---@return string state
function M.line (spec, text, state)
  local put, finish = writer ()
  local blocks, longs = spec.block or {}, spec.long or {}
  local i = 1

  -- A comment or string the line before left open runs on until it closes.
  local open_kind, open_n = state:match ('^([cs])(%d+)$')
  if open_kind then
    local n = tonumber (open_n) --[[@as integer]]
    local pair = open_kind == 'c' and blocks[n] or longs[n]
    local raw = open_kind == 'c' or spec.raw == true
    local stop = find_close (text, 1, pair[2], raw)
    if not stop then
      put (open_kind, text)
      return finish (), state
    end
    put (open_kind, text:sub (1, stop - 1))
    i = stop
  end

  if spec.heading and i == 1 and text:match ('^#+%s') then
    put ('k', text)
    return finish (), ''
  end

  local plain_from = i
  local function plain_to (j)
    if j > plain_from then
      put ('', text:sub (plain_from, j - 1))
    end
  end

  while i <= #text do
    local c = text:sub (i, i)
    local block = opener_at (text, i, blocks)
    local long = nil ---@type integer?
    if not block then
      long = opener_at (text, i, longs)
    end
    if block then
      plain_to (i)
      local pair = blocks[block]
      local stop = find_close (text, i + #pair[1], pair[2], true)
      if not stop then
        put ('c', text:sub (i))
        return finish (), 'c' .. block
      end
      put ('c', text:sub (i, stop - 1))
      i = stop
      plain_from = i
    elseif starts_with_any (text, i, spec.line) then
      plain_to (i)
      put ('c', text:sub (i))
      return finish (), ''
    elseif long then
      plain_to (i)
      local pair = longs[long]
      local stop = find_close (text, i + #pair[1], pair[2], spec.raw == true)
      if not stop then
        put ('s', text:sub (i))
        return finish (), 's' .. long
      end
      put ('s', text:sub (i, stop - 1))
      i = stop
      plain_from = i
    elseif spec.quotes and starts_with_any (text, i, spec.quotes) then
      plain_to (i)
      -- A string left open at the end of the line stops there, as most languages say.
      local stop = find_close (text, i + 1, c, false) or (#text + 1)
      put ('s', text:sub (i, stop - 1))
      i = stop
      plain_from = i
    elseif c:match ('[%a_$]') then
      local word = text:match ('^[%w_$]+', i)
      local key = spec.fold and word:lower () or word
      local kind = (spec.keywords and spec.keywords[key]) and 'k'
        or (spec.constants and spec.constants[key]) and 't'
        or nil
      if kind then
        plain_to (i)
        put (kind, word)
        plain_from = i + #word
      end
      i = i + #word
    elseif c:match ('%d') and not text:sub (i - 1, i - 1):match ('[%w_]') then
      local number = text:match ('^%d[%w%.]*', i)
      plain_to (i)
      put ('n', number)
      i = i + #number
      plain_from = i
    else
      i = i + 1
    end
  end
  plain_to (i)
  return finish (), ''
end

---A painter draws whole files, and keeps each line it drew so the next paint redraws only
---the lines that changed.
---@return Minimap.Painter
function M.painter ()
  local kept = {} ---@type table<string, { [1]: string, [2]: string }>
  local count = 0
  local kept_for = nil ---@type Minimap.Spec?

  ---@param text string
  ---@param language string
  ---@return Minimap.Picture
  local function paint (text, language)
    local spec = M.spec_for (language)
    if spec ~= kept_for or count > MAX_KEPT then
      kept, count, kept_for = {}, 0, spec
    end
    local out, n = {}, 0
    local state = ''
    local lines = 0
    for line in (text .. '\n'):gmatch ('([^\n]*)\n') do
      lines = lines + 1
      if lines <= M.MAX_LINES then
        line = line:gsub ('\r$', '')
        local key = state .. '\n' .. line
        local hit = kept[key]
        if not hit then
          local html, next_state = M.line (spec, line, state)
          hit = { html, next_state }
          kept[key] = hit
          count = count + 1
        end
        n = n + 1
        out[n] = hit[1]
        state = hit[2]
      end
    end
    return { html = table.concat (out, '\n'), lines = lines, drawn = n }
  end

  return { paint = paint }
end

---The line, from 1, under a point `y` pixels from the top of the picture.
---@param y number
---@param line_height number
---@param lines integer
---@return integer
function M.line_at (y, line_height, lines)
  local n = math.floor (y / line_height) + 1
  return math.max (1, math.min (n, math.max (1, lines)))
end

return M
