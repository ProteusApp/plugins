-- log_export: the text the log viewer writes when it exports the lines that match. A log
-- file gets each line as it reads, without colour codes. A CSV file gets a row for each line,
-- with its number, time and level, the source it came from in the merged view, the fields its
-- format shows as columns, and its text.

---@class Logs.ExportModule
---@field is_csv fun(path: string): boolean
---@field as_text fun(lines: Logs.Line[]): string
---@field as_csv fun(lines: Logs.Line[], source_of?: (fun(line: Logs.Line): string?), fields?: string[]): string
---@field time_text fun(ms: number): string

---True for a path that names a CSV file.
---@param path string
---@return boolean
local function is_csv (path)
  return path:lower ():find ('%.csv$') ~= nil
end

---A time as ISO 8601, with milliseconds when it has any. It has no zone, since a line's
---time counts as it is written.
---@param ms number
---@return string
local function time_text (ms)
  local whole = math.floor (ms / 1000)
  local rest = math.floor (ms - whole * 1000 + 0.5)
  local text = tostring (os.date ('!%Y-%m-%dT%H:%M:%S', whole))
  if rest > 0 then
    text = text .. string.format ('.%03d', rest)
  end
  return text
end

---The lines as they read, one to a line of text.
---@param lines Logs.Line[]
---@return string
local function as_text (lines)
  local out = {} ---@type string[]
  for i, line in ipairs (lines) do
    out[i] = line.plain
  end
  if #out == 0 then
    return ''
  end
  return table.concat (out, '\n') .. '\n'
end

---One CSV field, quoted when it holds a comma, a quote or a line break.
---@param value string
---@return string
local function csv_field (value)
  if value:find ('[,"\r\n]') then
    return '"' .. value:gsub ('"', '""') .. '"'
  end
  return value
end

---@param values string[]
---@return string
local function csv_row (values)
  local out = {} ---@type string[]
  for i, v in ipairs (values) do
    out[i] = csv_field (v)
  end
  return table.concat (out, ',')
end

---The lines as CSV, a header first. `source_of` names the source of a line, for the merged
---view, and adds a column for it. `fields` adds a column for each field.
---@param lines Logs.Line[]
---@param source_of? fun(line: Logs.Line): string?
---@param fields? string[]
---@return string
local function as_csv (lines, source_of, fields)
  local header = { 'line', 'time', 'level' } ---@type string[]
  if source_of then
    header[#header + 1] = 'source'
  end
  for _, name in ipairs (fields or {}) do
    header[#header + 1] = name
  end
  header[#header + 1] = 'text'
  local rows = { csv_row (header) } ---@type string[]
  for _, line in ipairs (lines) do
    local values = {
      tostring (line.n),
      line.time and time_text (line.time) or '',
      line.level,
    } ---@type string[]
    if source_of then
      values[#values + 1] = source_of (line) or ''
    end
    for _, name in ipairs (fields or {}) do
      values[#values + 1] = line.fields and line.fields[name] or ''
    end
    values[#values + 1] = line.plain
    rows[#rows + 1] = csv_row (values)
  end
  return table.concat (rows, '\r\n') .. '\r\n'
end

---@type Logs.ExportModule
return {
  is_csv = is_csv,
  as_text = as_text,
  as_csv = as_csv,
  time_text = time_text,
}
