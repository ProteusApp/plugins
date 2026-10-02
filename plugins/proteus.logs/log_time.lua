-- log_time: the time a log line was written, and the times the filter's after: and before:
-- name. Times are milliseconds since 1970. A time written with a zone, such as `Z` or
-- `+02:00`, counts in UTC. A time with no zone counts as written, as if it were UTC, so lines
-- and filters without zones compare as they read. A line with a time of day and no date, such
-- as `12:00:01 INFO`, gets 1 January 1970, so only a time of day in the filter compares with it.

local DAY = 24 * 60 * 60 * 1000

---@type table<string, integer>
local MONTHS = {
  jan = 1,
  feb = 2,
  mar = 3,
  apr = 4,
  may = 5,
  jun = 6,
  jul = 7,
  aug = 8,
  sep = 9,
  oct = 10,
  nov = 11,
  dec = 12,
}

---Days from 1970-01-01 to a date, after Howard Hinnant's days_from_civil.
---@param y integer
---@param m integer
---@param d integer
---@return integer
local function days (y, m, d)
  if m <= 2 then
    y = y - 1
  end
  local era = math.floor (y / 400)
  local yoe = y - era * 400
  local mp = (m + 9) % 12
  local doy = math.floor ((153 * mp + 2) / 5) + d - 1
  local doe = yoe * 365 + math.floor (yoe / 4) - math.floor (yoe / 100) + doy
  return era * 146097 + doe - 719468
end

---@param y integer
---@param mo integer
---@param d integer
---@param h integer
---@param mi integer
---@param s integer
---@param frac string? Digits after the seconds' point, such as `123` or `123456`.
---@param zone string? `Z`, `+02:00`, `-0700` or nil.
---@return number?
local function stamp (y, mo, d, h, mi, s, frac, zone)
  if mo < 1 or mo > 12 or d < 1 or d > 31 or h > 23 or mi > 59 or s > 60 then
    return nil
  end
  local ms = ((days (y, mo, d) * 24 + h) * 60 + mi) * 60000 + s * 1000
  if frac and frac ~= '' then
    ms = ms + math.floor (tonumber ('0.' .. frac) * 1000 + 0.5)
  end
  if zone and zone ~= '' and zone ~= 'Z' and zone ~= 'z' then
    local sign, zh, zm = zone:match ('^([+-])(%d%d):?(%d%d)$')
    if sign then
      local offset = (tonumber (zh) * 60 + tonumber (zm)) * 60000
      ms = sign == '+' and ms - offset or ms + offset
    end
  end
  return ms
end

---The time in one piece of text that holds a date and time: ISO 8601 and the forms near it,
---such as `2024-03-01 12:00:01,123` or `2024/03/01T12:00:01Z`. Nil when it holds none.
---@param text string
---@return number?
local function parse_stamp (text)
  local y, mo, d, h, mi, rest =
    text:match ('(%d%d%d%d)[-/](%d%d)[-/](%d%d)[Tt _]+(%d%d):(%d%d)(.*)')
  if not y then
    return nil
  end
  local s = rest:match ('^:(%d%d)')
  if s then
    rest = rest:sub (4)
  end
  local frac = rest:match ('^[.,](%d+)')
  if frac then
    rest = rest:sub (#frac + 2)
  end
  rest = rest:gsub ('^ ', '')
  local zone = rest:match ('^([Zz])') or rest:match ('^([+-]%d%d:?%d%d)')
  return stamp (
    math.floor (tonumber (y) or 0),
    math.floor (tonumber (mo) or 0),
    math.floor (tonumber (d) or 0),
    math.floor (tonumber (h) or 0),
    math.floor (tonumber (mi) or 0),
    math.floor (tonumber (s) or 0),
    frac,
    zone
  )
end

---A number of seconds, milliseconds, microseconds or nanoseconds since 1970, told apart by
---its size.
---@param n number
---@return number
local function epoch (n)
  if n > 1e17 then
    return n / 1e6
  elseif n > 1e14 then
    return n / 1e3
  elseif n > 1e11 then
    return n
  end
  return n * 1000
end

-- JSON and logfmt fields that hold a line's time, in the order they are looked for.
local FIELDS =
  { '@timestamp', 'timestamp', 'time', 'ts', 'datetime', 'date', 't' }

---The time a log line was written, or nil when it says none. `year` fills in the year of a
---syslog line or a glog line, which write none.
---@param plain string The line without colour codes.
---@param year integer
---@return number?
local function line_time (plain, year)
  local head = plain:sub (1, 160)
  -- Most lines start with an ISO 8601 time, so that is looked for first. A JSON line may
  -- hold other dates, so its time field comes first.
  local json = plain:find ('^%s*{') ~= nil
  if not json then
    local iso = parse_stamp (head)
    if iso then
      return iso
    end
  end
  -- A JSON or logfmt field, which may hold a number or come further along the line.
  if plain:find ('[=:]') then
    for _, name in ipairs (FIELDS) do
      if plain:find (name, 1, true) then
        local key = name:gsub ('%p', '%%%0')
        local quoted = plain:match ('"' .. key .. '"%s*:%s*"([^"]+)"')
          or plain:match ('%f[%w@]' .. key .. '="([^"]+)"')
          or plain:match ('%f[%w@]' .. key .. '=(%S+)')
        if quoted then
          local t = parse_stamp (quoted)
          if t then
            return t
          end
          local n = tonumber (quoted)
          if n then
            return epoch (n)
          end
        end
        local number = plain:match ('"' .. key .. '"%s*:%s*(%d+%.?%d*)')
        if number then
          return epoch (tonumber (number) or 0)
        end
      end
    end
  end
  if json then
    local iso = parse_stamp (head)
    if iso then
      return iso
    end
  end
  -- Common Log Format, as web servers write it: [10/Oct/2000:13:55:36 -0700].
  local cd, cmon, cy, ch, cmi, cs, cz = head:match (
    '%[(%d%d)/(%a%a%a)/(%d%d%d%d):(%d%d):(%d%d):(%d%d) ([+-]%d%d%d%d)%]'
  )
  if cd and MONTHS[cmon:lower ()] then
    return stamp (
      math.floor (tonumber (cy) or 0),
      MONTHS[cmon:lower ()],
      math.floor (tonumber (cd) or 0),
      math.floor (tonumber (ch) or 0),
      math.floor (tonumber (cmi) or 0),
      math.floor (tonumber (cs) or 0),
      nil,
      cz
    )
  end
  -- syslog: Oct 10 13:55:36, maybe after a <priority>.
  local smon, sd, sh, smi, ss =
    head:match ('^%s*<?%d*>?%s*(%a%a%a) +(%d%d?) (%d%d):(%d%d):(%d%d)')
  if smon and MONTHS[smon:lower ()] then
    return stamp (
      year,
      MONTHS[smon:lower ()],
      math.floor (tonumber (sd) or 0),
      math.floor (tonumber (sh) or 0),
      math.floor (tonumber (smi) or 0),
      math.floor (tonumber (ss) or 0),
      nil,
      nil
    )
  end
  -- glog and klog: I1001 12:00:00.000000.
  local gmo, gd, gh, gmi, gs, gfrac =
    head:match ('^%s*[IWEF](%d%d)(%d%d) (%d%d):(%d%d):(%d%d)%.?(%d*)')
  if gmo then
    return stamp (
      year,
      math.floor (tonumber (gmo) or 0),
      math.floor (tonumber (gd) or 0),
      math.floor (tonumber (gh) or 0),
      math.floor (tonumber (gmi) or 0),
      math.floor (tonumber (gs) or 0),
      gfrac,
      nil
    )
  end
  -- A time of day at the start, with no date.
  local th, tmi, ts, tfrac =
    head:match ('^%s*%[?(%d%d):(%d%d):(%d%d)[.,]?(%d*)')
  if th then
    return stamp (
      1970,
      1,
      1,
      math.floor (tonumber (th) or 0),
      math.floor (tonumber (tmi) or 0),
      math.floor (tonumber (ts) or 0),
      tfrac,
      nil
    )
  end
  return nil
end

---A time the filter names after `after:` or `before:`.
---@class Logs.When
---@field kind 'at'|'day'|'ago' `at` is a moment, `day` a time of day, `ago` a time before the newest line.
---@field ms number The moment, the milliseconds into the day, or how many milliseconds back.

---@type table<string, integer>
local UNITS = { s = 1000, m = 60000, h = 3600000, d = DAY }

---Reads a time from the filter: `2024-03-01`, `2024-03-01T12:00`, `12:00` or `12:00:30`,
---or `-15m`, `-2h`, `-1d` or `-30s`. Nil when it is none of these.
---@param text string
---@return Logs.When?
local function parse_when (text)
  local n, unit = text:match ('^%-(%d+%.?%d*)([smhd])$')
  if n then
    return { kind = 'ago', ms = (tonumber (n) or 0) * UNITS[unit] }
  end
  local h, mi, s = text:match ('^(%d%d?):(%d%d):?(%d?%d?)$')
  if h then
    local hh, mm = tonumber (h) or 0, tonumber (mi) or 0
    local ss = tonumber (s) or 0
    if hh > 23 or mm > 59 or ss > 59 then
      return nil
    end
    return { kind = 'day', ms = ((hh * 60 + mm) * 60 + ss) * 1000 }
  end
  local y, mo, d = text:match ('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
  if y then
    local t = stamp (
      math.floor (tonumber (y) or 0),
      math.floor (tonumber (mo) or 0),
      math.floor (tonumber (d) or 0),
      0,
      0,
      0,
      nil,
      nil
    )
    return t and { kind = 'at', ms = t } or nil
  end
  local t = parse_stamp (text)
  if t then
    return { kind = 'at', ms = t }
  end
  return nil
end

---True when a line's time is after or at `when`, or before or at it.
---@param time number
---@param when Logs.When
---@param newest number? The newest line's time, for a time `ago`.
---@param before boolean
---@return boolean
local function passes (time, when, newest, before)
  local t, limit = time, when.ms
  if when.kind == 'day' then
    t = time % DAY
  elseif when.kind == 'ago' then
    if not newest then
      return true
    end
    limit = newest - when.ms
  end
  if before then
    return t <= limit
  end
  return t >= limit
end

---@class Logs.TimeModule
---@field DAY integer
---@field parse_stamp fun(text: string): number?
---@field line_time fun(plain: string, year: integer): number?
---@field parse_when fun(text: string): Logs.When?
---@field passes fun(time: number, when: Logs.When, newest: number?, before: boolean): boolean

---@type Logs.TimeModule
return {
  DAY = DAY,
  parse_stamp = parse_stamp,
  line_time = line_time,
  parse_when = parse_when,
  passes = passes,
}
