-- log_filter: the logic behind proteus.logs, kept apart from the screen so the tests reach it.
-- It draws a line as HTML, with its colours and the filter's matches, and finds JSON inside a
-- line. It draws nothing on its own and calls no host function. The rest lives in modules of
-- its own, and this one hands out all of it, so the plugin and the tests need only this one:
-- log_text holds small text helpers, log_ansi the colour codes, log_level a line's level,
-- log_query the filter, log_ring the lines and the ring that holds them, log_sources where
-- lines come from, log_format the formats that take fields out of lines, and log_export the
-- text of the lines it exports. Regular expressions are in log_regex.lua, and times in
-- log_time.lua.

local ansi = require ('log_ansi') --[[@as Logs.AnsiModule]]
local lfmt = require ('log_format') --[[@as Logs.FormatModule]]
local ll = require ('log_level') --[[@as Logs.LevelModule]]
local lq = require ('log_query') --[[@as Logs.QueryModule]]
local lr = require ('log_ring') --[[@as Logs.RingModule]]
local ls = require ('log_sources') --[[@as Logs.SourcesModule]]
local lx = require ('log_export') --[[@as Logs.ExportModule]]
local tx = require ('log_text') --[[@as Logs.TextModule]]

local escape, clip = tx.escape, tx.clip
local parse_ansi, strip_ansi = ansi.parse_ansi, ansi.strip_ansi
local highlight = lq.highlight

---@class Logs.FilterModule
---@field LEVELS Logs.Level[] Every level, worst first.
---@field parse_query fun(text: string, fields?: table<string, string>): Logs.Query
---@field is_empty fun(query: Logs.Query): boolean True when the query hides nothing.
---@field detect_level fun(line: string): Logs.Level
---@field matches fun(line: string, query: Logs.Query, level?: Logs.Level): boolean
---@field highlight fun(line: string, query: Logs.Query): Logs.Range[]
---@field strip_ansi fun(text: string): string
---@field parse_ansi fun(text: string): Logs.Segment[]
---@field escape fun(text: string): string
---@field render_line fun(line: string, query: Logs.Query): string
---@field row_html fun(line: Logs.Line, query: Logs.Query, tag?: { name: string, n: integer }, cols?: Logs.Columns): string
---@field head_html fun(cols: Logs.Columns, sort?: Logs.Sort): string
---@field clip fun(text: string, max: integer): string
---@field find_json fun(line: string): string?
---@field pretty_json fun(text: string): string?
---@field make_line fun(n: integer, text: string, err?: boolean, prev_time?: number): Logs.Line
---@field matches_line fun(line: Logs.Line, query: Logs.Query, newest?: number): boolean
---@field ring fun(capacity: integer): Logs.Ring
---@field find_line fun(ring: Logs.Ring, n: integer): Logs.Line?
---@field index_of fun(sorted: integer[], n: integer): integer?
---@field zero_levels fun(): table<Logs.Level, integer>
---@field classify fun(line: Logs.Line, query: Logs.Query, hidden: table<string, boolean>, newest?: number): boolean, boolean
---@field scan fun(ring: Logs.Ring, query: Logs.Query, hidden: table<string, boolean>, limit: integer, newest?: number): Logs.Scan
---@field merge fun(lists: Logs.Line[][]): Logs.Line[]
---@field newest fun(ring: Logs.Ring): number?
---@field has_time fun(query: Logs.Query): boolean
---@field split_lines fun(text: string): string[]
---@field trim fun(text: string): string
---@field sentence fun(text: string): string
---@field group fun(n: number): string
---@field is_gzip fun(path: string): boolean
---@field rotation_base fun(name: string): string
---@field rotated_files fun(base: string, names: string[]): string[]
---@field follow_command fun(path: string, os_name: string, whole?: boolean, older?: string[]): string, string[]
---@field reads_whole fun(spec: Logs.SourceSpec): boolean
---@field shell_command fun(line: string, os_name: string): string, string[]
---@field source_name fun(spec: Logs.SourceSpec): string
---@field source_title fun(spec: Logs.SourceSpec): string
---@field state_label fun(state: Logs.State, code?: integer, file?: boolean): string
---@field spec_key fun(spec: Logs.SourceSpec): string
---@field remember fun(list: Logs.SourceSpec[], spec: Logs.SourceSpec, max: integer): Logs.SourceSpec[]
---@field clean_specs fun(value: any): Logs.SourceSpec[]
---@field clean_levels fun(value: any): Logs.Level[]
---@field is_csv fun(path: string): boolean
---@field as_text fun(lines: Logs.Line[]): string
---@field as_csv fun(lines: Logs.Line[], source_of?: (fun(line: Logs.Line): string?), fields?: string[]): string
---@field time_text fun(ms: number): string
---@field FORMAT_KINDS table<Logs.FormatKind, string>
---@field json_fields fun(plain: string): table<string, string>?, string[]?
---@field logfmt_fields fun(plain: string): table<string, string>?, string[]?
---@field compile_format fun(format: Logs.Format): Logs.Parser?, string?
---@field apply_format fun(line: Logs.Line, parser?: Logs.Parser)
---@field discover_fields fun(lines: Logs.Line[], kind: Logs.FormatKind, max: integer): string[]
---@field split_names fun(text: string): string[]
---@field clean_formats fun(value: any): Logs.Format[]
---@field sort_lines fun(lines: Logs.Line[], field: string, desc: boolean): Logs.Line[]
---@field column_widths fun(lines: Logs.Line[], fields: string[]): integer[]

-- Lines longer than this show cut short in the list. The detail panel shows them whole.
local MAX_ROW = 4000
local MAX_CELL = 200 -- the most of a field a column shows

---The columns the list shows: the fields of the formats of its sources.
---@class Logs.Columns
---@field names string[]
---@field widths integer[] In characters.

---How the list is sorted.
---@class Logs.Sort
---@field field string
---@field desc boolean

local MAX_JSON_DEPTH = 64

---The HTML for the text of one line: escaped, coloured from its ANSI codes, and with each
---filter match in `<mark>`. A match that crosses a colour change is marked in each part.
---@param line string
---@param query Logs.Query
---@return string
local function render_line (line, query)
  local ranges = highlight (line, query)
  ---@type string[]
  local out = {}
  -- Where the current run starts in the plain text.
  local pos = 1 ---@type integer
  local r = 1
  for _, seg in ipairs (parse_ansi (line)) do
    ---@type string[]
    local classes = {}
    if seg.fg then
      classes[#classes + 1] = 'logs-c' .. seg.fg
    end
    if seg.bold then
      classes[#classes + 1] = 'logs-b'
    end
    if #classes > 0 then
      out[#out + 1] = '<span class="' .. table.concat (classes, ' ') .. '">'
    end
    local last = pos + #seg.text - 1 ---@type integer
    local at = pos ---@type integer
    while at <= last do
      while ranges[r] and ranges[r].to < at do
        r = r + 1
      end
      local range = ranges[r]
      if range and range.from <= at then
        local stop = math.min (range.to, last)
        out[#out + 1] = '<mark>'
          .. escape (seg.text:sub (at - pos + 1, stop - pos + 1))
          .. '</mark>'
        at = stop + 1
      else
        local stop = range and math.min (range.from - 1, last) or last
        out[#out + 1] = escape (seg.text:sub (at - pos + 1, stop - pos + 1))
        at = stop + 1
      end
    end
    if #classes > 0 then
      out[#out + 1] = '</span>'
    end
    pos = last + 1
  end
  return table.concat (out)
end

---The cells of a row's columns.
---@param line Logs.Line
---@param cols? Logs.Columns
---@return string
local function cells_html (line, cols)
  if not cols or #cols.names == 0 then
    return ''
  end
  local out = {} ---@type string[]
  local fields = line.fields or {}
  for i, name in ipairs (cols.names) do
    local value = fields[name] or ''
    if #value > MAX_CELL then
      value = clip (value, MAX_CELL)
    end
    out[#out + 1] = '<span class="logs-f" style="width:'
      .. cols.widths[i]
      .. 'ch">'
      .. escape ((value:gsub ('[\r\n\t]', ' ')))
      .. '</span>'
  end
  return table.concat (out)
end

---The HTML of the row of column names above the list. Each name carries `col:<name>` in
---`data-item`, and the column the list is sorted by shows an arrow.
---@param cols Logs.Columns
---@param sort? Logs.Sort
---@return string
local function head_html (cols, sort)
  local out = { '<span class="logs-n"></span>' } ---@type string[]
  for i, name in ipairs (cols.names) do
    local arrow = ''
    if sort and sort.field == name then
      arrow = sort.desc and ' ▼' or ' ▲'
    end
    out[#out + 1] = '<span class="logs-hcol'
      .. (arrow ~= '' and ' on' or '')
      .. '" data-item="col:'
      .. escape (name)
      .. '" title="Sort by '
      .. escape (name)
      .. '" style="width:'
      .. cols.widths[i]
      .. 'ch">'
      .. escape (name)
      .. arrow
      .. '</span>'
  end
  out[#out + 1] = '<span class="logs-t">Line</span>'
  return table.concat (out)
end

---The HTML for one row of the list. The row carries the line's id in `data-item`, or its
---number when it has no id. In the merged view, `tag` names the source the line came from,
---and `n` picks its colour. `cols` adds a cell for each field the formats show.
---@param line Logs.Line
---@param query Logs.Query
---@param tag? { name: string, n: integer }
---@param cols? Logs.Columns
---@return string
local function row_html (line, query, tag, cols)
  local text = line.text
  local more = ''
  if #text > MAX_ROW then
    text = clip (text, MAX_ROW)
    more = '<span class="logs-more">…</span>'
  end
  return table.concat ({
    '<div class="logs-row logs-lv-',
    line.level,
    line.err and ' logs-stderr' or '',
    '" data-item="',
    line.id or line.n,
    '"><span class="logs-n">',
    line.n,
    '</span>',
    cells_html (line, cols),
    tag
        and ('<span class="logs-tag logs-tag-' .. (tag.n % 6) .. '">' .. escape (
          tag.name
        ) .. '</span>')
      or '',
    '<span class="logs-t">',
    render_line (text, query),
    more,
    '</span></div>',
  })
end

---------------------------------------------------------------------------------------------
-- JSON
---------------------------------------------------------------------------------------------

---@param s string
---@param i integer
---@return integer
local function skip_space (s, i)
  return s:find ('[^ \t\r\n]', i) or #s + 1
end

---Reads a JSON string that starts at `i`. Returns the position after it.
---@param s string
---@param i integer
---@return integer?
local function read_string (s, i)
  local at = i + 1
  while true do
    local c = s:find ('["\\%c]', at)
    if not c then
      return nil
    end
    local ch = s:sub (c, c)
    if ch == '"' then
      return c + 1
    end
    if ch ~= '\\' then
      return nil
    end
    local nx = s:sub (c + 1, c + 1)
    if nx == 'u' then
      if not s:match ('^%x%x%x%x', c + 2) then
        return nil
      end
      at = c + 6
    elseif nx ~= '' and ('"\\/bfnrt'):find (nx, 1, true) then
      at = c + 2
    else
      return nil
    end
  end
end

---Reads a JSON number that starts at `i`. Returns the position after it.
---@param s string
---@param i integer
---@return integer?
local function read_number (s, i)
  local at = s:match ('^%-?0()', i) or s:match ('^%-?[1-9]%d*()', i)
  if not at then
    return nil
  end
  at = s:match ('^%.%d+()', at) or at
  at = s:match ('^[eE][%+%-]?%d+()', at) or at
  return at
end

---Reads one JSON value that starts at `i`, and adds its tokens to `out` when given.
---Returns the position after it, or nil when the text there is not JSON.
---@param s string
---@param i integer
---@param out string[]?
---@param depth integer
---@return integer?
local function read_value (s, i, out, depth)
  if depth > MAX_JSON_DEPTH then
    return nil
  end
  local c = s:sub (i, i)
  if c == '{' or c == '[' then
    local close = c == '{' and '}' or ']'
    if out then
      out[#out + 1] = c
    end
    local at = skip_space (s, i + 1)
    if s:sub (at, at) == close then
      if out then
        out[#out + 1] = close
      end
      return at + 1
    end
    while true do
      if c == '{' then
        if s:sub (at, at) ~= '"' then
          return nil
        end
        local key_end = read_string (s, at)
        if not key_end then
          return nil
        end
        if out then
          out[#out + 1] = s:sub (at, key_end - 1)
        end
        at = skip_space (s, key_end)
        if s:sub (at, at) ~= ':' then
          return nil
        end
        if out then
          out[#out + 1] = ':'
        end
        at = skip_space (s, at + 1)
      end
      local value_end = read_value (s, at, out, depth + 1)
      if not value_end then
        return nil
      end
      at = skip_space (s, value_end)
      local sep = s:sub (at, at)
      if sep == close then
        if out then
          out[#out + 1] = close
        end
        return at + 1
      end
      if sep ~= ',' then
        return nil
      end
      if out then
        out[#out + 1] = ','
      end
      at = skip_space (s, at + 1)
    end
  end
  local after = nil ---@type integer?
  local word = s:match ('^%a+', i)
  if c == '"' then
    after = read_string (s, i)
  elseif word == 'true' or word == 'false' or word == 'null' then
    after = i + #word
  else
    after = read_number (s, i)
  end
  if after and out then
    out[#out + 1] = s:sub (i, after - 1)
  end
  return after
end

---The JSON object or array a line ends with, such as the part after a time, or nil.
---@param line string
---@return string?
local function find_json (line)
  local plain = strip_ansi (line)
  local start = plain:find ('[{%[]')
  local tries = 0
  while start and tries < 50 do
    tries = tries + 1
    local after = read_value (plain, start, nil, 0)
    if after and after - start > 2 and not plain:find ('%S', after) then
      return plain:sub (start, after - 1)
    end
    start = plain:find ('[{%[]', start + 1)
  end
  return nil
end

---JSON laid out with two spaces per level. Keys keep their order. Returns nil for text that
---is not JSON.
---@param text string
---@return string?
local function pretty_json (text)
  ---@type string[]
  local tokens = {}
  local after = read_value (text, skip_space (text, 1), tokens, 0)
  if not after or text:find ('%S', after) then
    return nil
  end
  ---@type string[]
  local out = {}
  local depth = 0
  local i = 1
  while i <= #tokens do
    local t = tokens[i]
    if t == '{' or t == '[' then
      local close = t == '{' and '}' or ']'
      if tokens[i + 1] == close then
        out[#out + 1] = t .. close
        i = i + 1
      else
        depth = depth + 1
        out[#out + 1] = t .. '\n' .. string.rep ('  ', depth)
      end
    elseif t == '}' or t == ']' then
      depth = depth - 1
      out[#out + 1] = '\n' .. string.rep ('  ', depth) .. t
    elseif t == ',' then
      out[#out + 1] = ',\n' .. string.rep ('  ', depth)
    elseif t == ':' then
      out[#out + 1] = ': '
    else
      out[#out + 1] = t
    end
    i = i + 1
  end
  return table.concat (out)
end

---@type Logs.FilterModule
local M = {
  LEVELS = ll.LEVELS,
  parse_query = lq.parse_query,
  is_empty = lq.is_empty,
  detect_level = ll.detect_level,
  matches = lq.matches,
  highlight = lq.highlight,
  strip_ansi = ansi.strip_ansi,
  parse_ansi = ansi.parse_ansi,
  escape = tx.escape,
  render_line = render_line,
  row_html = row_html,
  head_html = head_html,
  clip = tx.clip,
  find_json = find_json,
  pretty_json = pretty_json,
  make_line = lr.make_line,
  matches_line = lq.matches_line,
  ring = lr.ring,
  find_line = lr.find_line,
  index_of = lr.index_of,
  zero_levels = ll.zero_levels,
  classify = lr.classify,
  scan = lr.scan,
  merge = lr.merge,
  newest = lr.newest,
  has_time = lq.has_time,
  split_lines = tx.split_lines,
  trim = tx.trim,
  sentence = tx.sentence,
  group = tx.group,
  is_gzip = ls.is_gzip,
  rotation_base = ls.rotation_base,
  rotated_files = ls.rotated_files,
  follow_command = ls.follow_command,
  reads_whole = ls.reads_whole,
  shell_command = ls.shell_command,
  source_name = ls.source_name,
  source_title = ls.source_title,
  state_label = ls.state_label,
  spec_key = ls.spec_key,
  remember = ls.remember,
  clean_specs = ls.clean_specs,
  clean_levels = ls.clean_levels,
  is_csv = lx.is_csv,
  as_text = lx.as_text,
  as_csv = lx.as_csv,
  time_text = lx.time_text,
  FORMAT_KINDS = lfmt.KINDS,
  json_fields = lfmt.json_fields,
  logfmt_fields = lfmt.logfmt_fields,
  compile_format = lfmt.compile,
  apply_format = lfmt.apply,
  discover_fields = lfmt.discover,
  split_names = lfmt.split_names,
  clean_formats = lfmt.clean_formats,
  sort_lines = lfmt.sort_lines,
  column_widths = lfmt.widths,
}

return M
