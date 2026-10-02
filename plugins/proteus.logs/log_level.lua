-- log_level: finds the level of a log line. It reads a JSON or logfmt level field, a glog
-- letter, a bracketed letter, or a level word near the start of the line that reads as a
-- level rather than as part of a sentence. It also names the levels `level:` takes.

local ansi = require ('log_ansi') --[[@as Logs.AnsiModule]]
local tx = require ('log_text') --[[@as Logs.TextModule]]

local trim = tx.trim
local strip_ansi = ansi.strip_ansi

---@alias Logs.Level 'error'|'warn'|'info'|'debug'|'other'

---@class Logs.LevelModule
---@field LEVELS Logs.Level[] Every level, worst first.
---@field detect_level fun(line: string): Logs.Level
---@field level_named fun(name: string): Logs.Level? The level a `level:` value names.
---@field zero_levels fun(): table<Logs.Level, integer>

---@type Logs.Level[]
local LEVELS = { 'error', 'warn', 'info', 'debug', 'other' }

-- Words that name a level. A single letter counts only in brackets or as a JSON value.
---@type table<string, Logs.Level>
local WORDS = {
  error = 'error',
  err = 'error',
  fatal = 'error',
  critical = 'error',
  crit = 'error',
  panic = 'error',
  severe = 'error',
  emerg = 'error',
  emergency = 'error',
  ftl = 'error',
  warn = 'warn',
  warning = 'warn',
  wrn = 'warn',
  info = 'info',
  inf = 'info',
  information = 'info',
  notice = 'info',
  debug = 'debug',
  dbg = 'debug',
  trace = 'debug',
  trc = 'debug',
  verbose = 'debug',
  vrb = 'debug',
}

---@type table<string, Logs.Level>
local LETTERS = {
  E = 'error',
  F = 'error',
  W = 'warn',
  I = 'info',
  D = 'debug',
  T = 'debug',
  V = 'debug',
}

-- JSON and logfmt field names that hold a level.
---@type table<string, boolean>
local LEVEL_KEYS = {
  level = true,
  severity = true,
  lvl = true,
  loglevel = true,
  log_level = true,
  levelname = true,
  ['log.level'] = true,
  ['@l'] = true,
  ['@level'] = true,
}

-- Names that `level:` takes, tried in order, so `level:w` means warnings.
---@type { [1]: string, [2]: Logs.Level }[]
local LEVEL_NAMES = {
  { 'error', 'error' },
  { 'warning', 'warn' },
  { 'information', 'info' },
  { 'debug', 'debug' },
  { 'trace', 'debug' },
  { 'other', 'other' },
  { 'fatal', 'error' },
  { 'critical', 'error' },
}

---@return table<Logs.Level, integer>
local function zero_levels ()
  return { error = 0, warn = 0, info = 0, debug = 0, other = 0 }
end

---The level a JSON or logfmt value names, such as `"warning"` or `"E"`.
---@param value string
---@return Logs.Level?
local function value_level (value)
  local word = trim (value):lower ()
  local level = WORDS[word]
  if level then
    return level
  end
  if #word == 1 then
    return LETTERS[word:upper ()]
  end
  return nil
end

---Reads a quoted logfmt value. Returns the value and where the text after it starts.
---@param text string
---@param quote integer Where the opening quote is.
---@return string
---@return integer
local function read_quoted (text, quote)
  local out = {} ---@type string[]
  local i = quote + 1
  while i <= #text do
    local c = text:sub (i, i)
    if c == '\\' then
      out[#out + 1] = text:sub (i + 1, i + 1)
      i = i + 2
    elseif c == '"' then
      return table.concat (out), i + 1
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat (out), i
end

---The level a logfmt pair names, such as `level=warn`. The line is read pair by pair, so text
---inside a quoted value, as in `msg="level=error in config"`, is never read as a pair.
---@param plain string
---@return Logs.Level?
local function logfmt_level (plain)
  local i, n = 1, #plain
  while i <= n do
    local c = plain:sub (i, i)
    if c:find ('%s') or c == '=' then
      i = i + 1
    elseif c == '"' then
      local _, after = read_quoted (plain, i)
      i = after
    else
      local stop = plain:find ('[%s="]', i) or n + 1
      local key = plain:sub (i, stop - 1)
      i = stop
      if plain:sub (stop, stop) == '=' then
        local value ---@type string
        if plain:sub (stop + 1, stop + 1) == '"' then
          value, i = read_quoted (plain, stop + 1)
        else
          local finish = plain:find ('%s', stop + 1) or n + 1
          value = plain:sub (stop + 1, finish - 1)
          i = finish
        end
        if LEVEL_KEYS[key:lower ()] then
          local word = value:match ("^'?(%a+)")
          local level = word and value_level (word)
          if level then
            return level
          end
        end
      end
    end
  end
  return nil
end

---A level field anywhere in the line, as JSON or as logfmt.
---@param plain string
---@return Logs.Level?
local function field_level (plain)
  if plain:find ('"%s*:') then
    local at = 1
    while true do
      local _, stop, key, value =
        plain:find ('"([%w_%.@]+)"%s*:%s*"([^"]*)"', at)
      if not stop then
        break
      end
      if LEVEL_KEYS[tostring (key):lower ()] then
        local level = value_level (tostring (value))
        if level then
          return level
        end
      end
      at = stop + 1
    end
    -- pino and bunyan write the level as a number.
    at = 1
    while true do
      local _, stop, key, number = plain:find ('"([%w_%.@]+)"%s*:%s*(%d+)', at)
      if not stop then
        break
      end
      if LEVEL_KEYS[tostring (key):lower ()] then
        local n = tonumber (number) or 0
        if n >= 50 then
          return 'error'
        elseif n >= 40 then
          return 'warn'
        elseif n >= 30 then
          return 'info'
        elseif n >= 10 then
          return 'debug'
        end
      end
      at = stop + 1
    end
  end
  if plain:find ('=', 1, true) then
    return logfmt_level (plain)
  end
  return nil
end

---The first level word near the start of a line that reads as a level rather than as part
---of a sentence. Returns the level and where it starts.
---@param head string
---@return Logs.Level?
---@return integer?
local function word_level (head)
  local first_word = nil ---@type integer?
  local at = 1
  while true do
    local s, stop = head:find ('%a+', at)
    if not s or not stop then
      break
    end
    at = stop + 1
    local word = head:sub (s, stop)
    local e = stop + 1
    if not first_word and #word >= 2 then
      first_word = s
    end
    local level = WORDS[word:lower ()]
    if level then
      local before = head:sub (s - 1, s - 1)
      local after = head:sub (e, e)
      local whole = not before:match ('[%w_]') and not after:match ('[%w_]')
      -- In a sentence a level word is in lower case and stands between spaces. As a level it
      -- is in capitals, starts the line, or sits in brackets or before a colon.
      if
        whole
        and (
          word == word:upper ()
          or s == first_word
          or before:match ('[%[<(|]')
          or after:match ('[:%]>)|]')
        )
      then
        return level, s
      end
    end
  end
  return nil, nil
end

-- glog and klog, as Kubernetes and gRPC write them, start a line with the level's letter and
-- the date: `E1001 12:00:00.000000 1 file.go:12] message`.
local GLOG = '^%s*([IWEF])%d%d%d%d %d%d:%d%d:%d%d'

---@param line string
---@return Logs.Level
local function detect_level (line)
  local plain = strip_ansi (line)
  local glog = plain:match (GLOG)
  if glog then
    return LETTERS[glog]
  end
  local field = field_level (plain)
  if field then
    return field
  end
  local head = plain:sub (1, 80)
  local level, at = word_level (head)
  local bracket = head:find ('%[[EWIDTFV]%]')
  if bracket and (not at or bracket < at) then
    return LETTERS[head:sub (bracket + 1, bracket + 1)]
  end
  return level or 'other'
end

---The level a `level:` value names, or nil for a name it does not know.
---@param name string
---@return Logs.Level?
local function level_named (name)
  local exact = WORDS[name]
  if exact then
    return exact
  end
  for _, pair in ipairs (LEVEL_NAMES) do
    if pair[1]:sub (1, #name) == name then
      return pair[2]
    end
  end
  return nil
end

---@type Logs.LevelModule
local M = {
  LEVELS = LEVELS,
  detect_level = detect_level,
  level_named = level_named,
  zero_levels = zero_levels,
}

return M
