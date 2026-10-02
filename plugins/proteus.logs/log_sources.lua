-- log_sources: where the log viewer's lines come from. It builds the command that follows a
-- file, reads a gzip file or a rotated log, or runs a command line, names and describes a
-- source, keeps the list of recent ones, and reads back the sources and levels saved in the
-- store.

local ll = require ('log_level') --[[@as Logs.LevelModule]]
local tx = require ('log_text') --[[@as Logs.TextModule]]

local trim, clip = tx.trim, tx.clip
local LEVELS = ll.LEVELS

---@alias Logs.State
---| 'running' # The program runs.
---| 'stopped' # Stopped from the app.
---| 'exited' # The program ended by itself.
---| 'failed' # The program could not start.
---| 'pasted' # Text from the clipboard, which does not grow.

---Where lines come from: a file to follow, a command to run, or pasted text.
---@class Logs.SourceSpec
---@field kind 'file'|'command'|'paste'
---@field path? string The full path of a file.
---@field command? string The command line of a command.
---@field cwd? string The folder a command runs in.
---@field name? string The name of pasted text.
---@field whole? boolean For a file, read from its first line rather than its last thousand.
---@field rotated? boolean For a file, read the older files it was rotated into first, oldest first, then follow it from its first line.
---@field format? string The name of the format whose fields show as columns.

---@class Logs.SourcesModule
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

---True for a path that names a gzip file, such as `app.log.2.gz`.
---@param path string
---@return boolean
local function is_gzip (path)
  return path:lower ():find ('%.gz$') ~= nil
end

---The name of the file a rotated log is written to now: `app.log` for `app.log.1`,
---`app.log.2.gz` or `app.log-20240301.gz`. A name that is no rotated file stays as it is.
---@param name string
---@return string
local function rotation_base (name)
  local base = name:gsub ('%.[gG][zZ]$', '')
  local numbered = base:match ('^(.+)%.%d+$')
  if numbered then
    return numbered
  end
  local dated = base:match ('^(.+)%-%d%d%d%d%d%d%d%d%d*$')
  return dated or base
end

---The older files a log was rotated into, among the names of the files beside it, oldest
---first: dated ones such as `app.log-20240301.gz` by date, then numbered ones such as
---`app.log.2.gz` and `app.log.1`, the highest number first.
---@param base string The name of the file written to now, such as `app.log`.
---@param names string[] The names in its folder. Folders end with `/`.
---@return string[]
local function rotated_files (base, names)
  ---@type { name: string, key: number, dated: boolean }[]
  local found = {}
  local plain_base = base:gsub ('%p', '%%%0')
  for _, name in ipairs (names) do
    local bare = name:gsub ('%.[gG][zZ]$', '')
    local n = bare:match ('^' .. plain_base .. '%.(%d+)$')
    local date = bare:match ('^' .. plain_base .. '%-(%d%d%d%d%d%d%d%d%d*)$')
    if name:sub (-1) ~= '/' and (n or date) then
      found[#found + 1] = {
        name = name,
        key = tonumber (n or date) or 0,
        dated = date ~= nil,
      }
    end
  end
  table.sort (found, function (a, b)
    if a.dated ~= b.dated then
      return a.dated
    end
    if a.key ~= b.key then
      -- A dated file is older the earlier its date, a numbered one the higher its number.
      return (a.key < b.key) == a.dated
    end
    return a.name < b.name
  end)
  local out = {} ---@type string[]
  for _, f in ipairs (found) do
    out[#out + 1] = f.name
  end
  return out
end

---A path in single quotes for PowerShell, which ends a quoted string at any of its four
---single quotes, so each is doubled.
---@param path string
---@return string
local function ps_quote (path)
  return "'"
    .. path:gsub ("'", "''"):gsub ('\226\128[\152-\155]', '%0%0')
    .. "'"
end

-- What PowerShell runs first: write UTF-8, and a function that prints a gzip file's lines.
local PS_START = '[Console]::OutputEncoding = [Text.Encoding]::UTF8; '
local PS_GZIP = 'function Read-Gzip ($p) { '
  .. '$z = New-Object IO.Compression.GZipStream ([IO.File]::OpenRead ($p), '
  .. '[IO.Compression.CompressionMode]::Decompress); '
  .. '$r = New-Object IO.StreamReader ($z, [Text.Encoding]::UTF8); '
  .. 'while ($null -ne ($l = $r.ReadLine ())) { $l }; $r.Close () }; '

-- What sh runs to print each file it is given, unpacking the gzip ones.
local SH_READ =
  'for f in "$@"; do case "$f" in *.gz|*.GZ) gzip -dc "$f" ;; *) cat "$f" ;; esac; done'

---True when a source reads a file from its first line: a whole file, a gzip file or a
---rotated log.
---@param spec Logs.SourceSpec
---@return boolean
local function reads_whole (spec)
  return spec.whole == true
    or spec.rotated == true
    or (spec.kind == 'file' and is_gzip (spec.path or ''))
end

---The program and arguments that follow a file: the last thousand lines, or with `whole`
---every line from the first, then each new one. `older` names the files the log was rotated
---into, oldest first, which are read before it. A gzip file is read once, since it does not
---grow.
---@param path string
---@param os_name string
---@param whole? boolean
---@param older? string[]
---@return string program
---@return string[] args
local function follow_command (path, os_name, whole, older)
  local before = older or {}
  local gzip = is_gzip (path)
  if os_name == 'windows' then
    -- PowerShell also writes in the console code page unless told to use UTF-8.
    local parts = { PS_START } ---@type string[]
    local all = {} ---@type string[]
    for _, p in ipairs (before) do
      all[#all + 1] = p
    end
    if gzip then
      all[#all + 1] = path
    end
    local unpacks = false
    for _, p in ipairs (all) do
      unpacks = unpacks or is_gzip (p)
    end
    if unpacks then
      parts[#parts + 1] = PS_GZIP
    end
    for _, p in ipairs (all) do
      if is_gzip (p) then
        parts[#parts + 1] = 'Read-Gzip ' .. ps_quote (p) .. '; '
      else
        parts[#parts + 1] = 'Get-Content -LiteralPath '
          .. ps_quote (p)
          .. ' -Encoding UTF8; '
      end
    end
    if not gzip then
      parts[#parts + 1] = 'Get-Content -LiteralPath '
        .. ps_quote (path)
        .. ((whole or #before > 0) and '' or ' -Tail 1000')
        .. ' -Wait -Encoding UTF8'
    end
    local script = table.concat (parts):gsub ('; $', '')
    return 'powershell', { '-NoProfile', '-Command', script }
  end
  if gzip and #before == 0 then
    return 'gzip', { '-dc', path }
  end
  if #before > 0 or gzip then
    local args = { '-c', '', 'sh' } ---@type string[]
    for _, p in ipairs (before) do
      args[#args + 1] = p
    end
    if gzip then
      args[#args + 1] = path
      args[2] = SH_READ
    else
      -- The file followed comes first, and the rest are read before it.
      table.insert (args, 4, path)
      args[2] = 'b="$1"; shift; ' .. SH_READ .. '; exec tail -n +1 -F "$b"'
    end
    return 'sh', args
  end
  return 'tail', { '-n', whole and '+1' or '1000', '-F', path }
end

---The program and arguments that run a command line through the shell.
---@param line string
---@param os_name string
---@return string program
---@return string[] args
local function shell_command (line, os_name)
  if os_name == 'windows' then
    return 'cmd', { '/c', line }
  end
  return 'sh', { '-c', line }
end

---@param spec Logs.SourceSpec
---@return string
local function source_name (spec)
  if spec.kind == 'file' then
    local path = spec.path or ''
    return path:match ('[^/\\]+$') or path
  end
  if spec.kind == 'command' then
    local line = trim (spec.command or '')
    if #line > 60 then
      return clip (line, 57) .. '…'
    end
    return line
  end
  return spec.name or 'Pasted text'
end

---A longer description of a source, for a tooltip.
---@param spec Logs.SourceSpec
---@return string
local function source_title (spec)
  if spec.kind == 'file' then
    local path = spec.path or ''
    if spec.rotated then
      return path .. '\nwith the files it was rotated into'
    end
    return path .. ((spec.whole or is_gzip (path)) and '\nthe whole file' or '')
  end
  if spec.kind == 'command' then
    local cwd = spec.cwd
    return (spec.command or '') .. (cwd and ('\nin ' .. cwd) or '')
  end
  return spec.name or 'Pasted text'
end

---What a state is called. `file` says the source reads a file, which has read to its end
---when its program ended well.
---@param state Logs.State
---@param code? integer
---@param file? boolean
---@return string
local function state_label (state, code, file)
  if file and state == 'exited' and code == 0 then
    return 'Read to the end'
  elseif state == 'running' then
    return 'Running'
  elseif state == 'stopped' then
    return 'Stopped'
  elseif state == 'exited' then
    return code and ('Exited with code ' .. code) or 'Exited'
  elseif state == 'failed' then
    return 'Failed to start'
  end
  return 'Pasted'
end

---Two specs with the same key are the same source.
---@param spec Logs.SourceSpec
---@return string
local function spec_key (spec)
  return table.concat ({
    spec.kind,
    spec.path or spec.command or spec.name or '',
    spec.cwd or '',
    spec.whole and 'whole' or '',
  }, '\n') .. (spec.rotated and '\nrotated' or '')
end

---A copy of a spec with only the fields that are saved.
---@param spec Logs.SourceSpec
---@return Logs.SourceSpec
local function copy_spec (spec)
  return {
    kind = spec.kind,
    path = spec.path,
    command = spec.command,
    cwd = spec.cwd,
    whole = spec.whole,
    rotated = spec.rotated,
    format = spec.format,
  }
end

---A new list of recent sources with `spec` first and no repeats.
---@param list Logs.SourceSpec[]
---@param spec Logs.SourceSpec
---@param max integer
---@return Logs.SourceSpec[]
local function remember (list, spec, max)
  local key = spec_key (spec)
  ---@type Logs.SourceSpec[]
  local out = { copy_spec (spec) }
  for _, other in ipairs (list) do
    if #out >= max then
      break
    end
    if spec_key (other) ~= key then
      out[#out + 1] = other
    end
  end
  return out
end

---Saved specs, with anything malformed left out.
---@param value any
---@return Logs.SourceSpec[]
local function clean_specs (value)
  ---@type Logs.SourceSpec[]
  local out = {}
  if type (value) ~= 'table' then
    return out
  end
  for _, v in
    ipairs (value --[[@as table<string, any>[] ]])
  do
    if type (v) == 'table' then
      local path, command, cwd = v.path, v.command, v.cwd
      local format = type (v.format) == 'string' and v.format ~= '' and v.format
        or nil
      if v.kind == 'file' and type (path) == 'string' and path ~= '' then
        out[#out + 1] = {
          kind = 'file',
          path = path,
          whole = v.whole == true or nil,
          rotated = v.rotated == true or nil,
          format = format,
        }
      elseif
        v.kind == 'command'
        and type (command) == 'string'
        and command:match ('%S')
      then
        out[#out + 1] = {
          kind = 'command',
          command = command,
          cwd = type (cwd) == 'string' and cwd ~= '' and cwd or nil,
          format = format,
        }
      end
    end
  end
  return out
end

---Saved level names, with anything unknown left out.
---@param value any
---@return Logs.Level[]
local function clean_levels (value)
  ---@type Logs.Level[]
  local out = {}
  if type (value) ~= 'table' then
    return out
  end
  for _, v in
    ipairs (value --[[@as any[] ]])
  do
    for _, level in ipairs (LEVELS) do
      if v == level then
        out[#out + 1] = level
      end
    end
  end
  return out
end

---@type Logs.SourcesModule
local M = {
  is_gzip = is_gzip,
  rotation_base = rotation_base,
  rotated_files = rotated_files,
  follow_command = follow_command,
  reads_whole = reads_whole,
  shell_command = shell_command,
  source_name = source_name,
  source_title = source_title,
  state_label = state_label,
  spec_key = spec_key,
  remember = remember,
  clean_specs = clean_specs,
  clean_levels = clean_levels,
}

return M
