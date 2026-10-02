-- log_histogram: how many lines were written over time, by level, for the bars above the list.
-- The time from the first line to the last is cut into bars of a round length, such as 10
-- seconds or 5 minutes, few enough to fit. A bar, or a run of bars, gives a span of time,
-- which goes into the filter as `after:` and `before:`.

local ll = require ('log_level') --[[@as Logs.LevelModule]]
local lx = require ('log_export') --[[@as Logs.ExportModule]]
local tx = require ('log_text') --[[@as Logs.TextModule]]

local SECOND = 1000
local MINUTE = 60 * SECOND
local HOUR = 60 * MINUTE
local DAY = 24 * HOUR

-- The lengths a bar may have, shortest first.
local STEPS = {
  1,
  2,
  5,
  10,
  20,
  50,
  100,
  200,
  500,
  SECOND,
  2 * SECOND,
  5 * SECOND,
  10 * SECOND,
  15 * SECOND,
  30 * SECOND,
  MINUTE,
  2 * MINUTE,
  5 * MINUTE,
  10 * MINUTE,
  15 * MINUTE,
  30 * MINUTE,
  HOUR,
  2 * HOUR,
  3 * HOUR,
  6 * HOUR,
  12 * HOUR,
  DAY,
  2 * DAY,
  7 * DAY,
  14 * DAY,
  30 * DAY,
  91 * DAY,
  365 * DAY,
}

-- The words of the filter that keep a span of time.
local TIME_WORDS = { 'after', 'since', 'before', 'until' }

---One bar: the lines written in its span of time.
---@class Logs.Bin
---@field total integer
---@field levels table<Logs.Level, integer>

---@class Logs.Histogram
---@field from number Where the first bar starts, in milliseconds since 1970.
---@field step number How long each bar is, in milliseconds.
---@field bins Logs.Bin[]
---@field max integer The most lines in one bar.
---@field lines integer The lines counted, which are those with a time.

---@class Logs.HistogramModule
---@field build fun(lines: Logs.Line[], first: integer, max_bins: integer): Logs.Histogram?
---@field span fun(h: Logs.Histogram, a: integer, b: integer): number, number
---@field step_text fun(step: number): string
---@field time_label fun(ms: number, step: number): string
---@field bin_title fun(h: Logs.Histogram, i: integer): string
---@field bars_html fun(h: Logs.Histogram): string
---@field with_range fun(text: string, from: number, to: number): string
---@field without_range fun(text: string): string

---Counts the lines from `first` on, by time, in at most `max_bins` bars. Nil when no line has
---a time.
---@param lines Logs.Line[]
---@param first integer
---@param max_bins integer
---@return Logs.Histogram?
local function build (lines, first, max_bins)
  local lo, hi = nil, nil ---@type number?, number?
  for k = first, #lines do
    local t = lines[k].time
    if t then
      if not lo or t < lo then
        lo = t
      end
      if not hi or t > hi then
        hi = t
      end
    end
  end
  if not lo or not hi then
    return nil
  end
  local step = nil ---@type number?
  for _, s in ipairs (STEPS) do
    local from = math.floor (lo / s) * s
    if math.floor ((hi - from) / s) + 1 <= max_bins then
      step = s
      break
    end
  end
  if not step then
    step = math.ceil ((hi - lo + 1) / max_bins)
  end
  local from = math.floor (lo / step) * step
  local count = math.floor ((hi - from) / step) + 1
  local bins = {} ---@type Logs.Bin[]
  for i = 1, count do
    bins[i] = { total = 0, levels = ll.zero_levels () }
  end
  local max, counted = 0, 0
  for k = first, #lines do
    local line = lines[k]
    local t = line.time
    if t then
      local bin = bins[math.floor ((t - from) / step) + 1]
      bin.total = bin.total + 1
      bin.levels[line.level] = bin.levels[line.level] + 1
      if bin.total > max then
        max = bin.total
      end
      counted = counted + 1
    end
  end
  return { from = from, step = step, bins = bins, max = max, lines = counted }
end

---The span of time of the bars from `a` to `b`, in either order: where it starts, and the
---last millisecond in it.
---@param h Logs.Histogram
---@param a integer
---@param b integer
---@return number from
---@return number to
local function span (h, a, b)
  local lo, hi = math.min (a, b), math.max (a, b)
  return h.from + (lo - 1) * h.step, h.from + hi * h.step - 1
end

---How long a bar is, in words, such as `5 minutes`.
---@param step number
---@return string
local function step_text (step)
  ---@type { [1]: number, [2]: string }[]
  local units = {
    { DAY, 'day' },
    { HOUR, 'hour' },
    { MINUTE, 'minute' },
    { SECOND, 'second' },
    { 1, 'millisecond' },
  }
  for _, unit in ipairs (units) do
    if step >= unit[1] and step % unit[1] == 0 then
      local n = math.floor (step / unit[1])
      return tx.group (n) .. ' ' .. unit[2] .. (n == 1 and '' or 's')
    end
  end
  return tx.group (step) .. ' milliseconds'
end

---A time on the axis, as exact as the bars are. A line with a time of day and no date has
---1 January 1970, so only its time of day shows.
---@param ms number
---@param step number
---@return string
local function time_label (ms, step)
  local whole = math.floor (ms / 1000)
  local clock = step < MINUTE and '%H:%M:%S' or '%H:%M'
  local text ---@type string
  if ms < DAY then
    text = tostring (os.date ('!' .. clock, whole))
  elseif step >= DAY then
    text = tostring (os.date ('!%Y-%m-%d', whole))
  else
    text = tostring (os.date ('!%Y-%m-%d ' .. clock, whole))
  end
  if step < SECOND then
    text = text .. string.format ('.%03d', math.floor (ms % 1000))
  end
  return text
end

---What a bar's tooltip says: its span, and how many lines of each level it holds.
---@param h Logs.Histogram
---@param i integer
---@return string
local function bin_title (h, i)
  local bin = h.bins[i]
  local from, to = span (h, i, i)
  local parts = {
    time_label (from, h.step)
      .. ' to '
      .. time_label (to + 1, h.step)
      .. ': '
      .. tx.group (bin.total)
      .. (bin.total == 1 and ' line' or ' lines'),
  } ---@type string[]
  ---@type { [1]: Logs.Level, [2]: string, [3]: string }[]
  local names = {
    { 'error', 'error', 'errors' },
    { 'warn', 'warning', 'warnings' },
  }
  for _, n in ipairs (names) do
    local count = bin.levels[n[1]]
    if count > 0 then
      parts[#parts + 1] = tx.group (count)
        .. ' '
        .. (count == 1 and n[2] or n[3])
    end
  end
  return table.concat (parts, ', ')
end

---The HTML of the bars. Each bar carries its number in `data-item` and stacks its levels,
---errors at the bottom, each as tall as its share of the fullest bar.
---@param h Logs.Histogram
---@return string
local function bars_html (h)
  local out = {} ---@type string[]
  for i, bin in ipairs (h.bins) do
    out[#out + 1] = '<div class="logs-hbin" data-item="'
      .. i
      .. '" title="'
      .. tx.escape (bin_title (h, i))
      .. '">'
    if bin.total > 0 then
      for _, level in ipairs (ll.LEVELS) do
        local n = bin.levels[level]
        if n > 0 then
          out[#out + 1] = '<i class="logs-hb-'
            .. level
            .. '" style="height:'
            .. string.format ('%.2f', n / h.max * 100)
            .. '%"></i>'
        end
      end
    end
    out[#out + 1] = '</div>'
  end
  return table.concat (out)
end

---The filter text with its span of time taken out.
---@param text string
---@return string
local function without_range (text)
  local out = ' ' .. text
  for _, word in ipairs (TIME_WORDS) do
    local any_case = word:gsub ('%a', function (c)
      return '[' .. c:lower () .. c:upper () .. ']'
    end)
    out = out:gsub ('%s+%-?' .. any_case .. ':%S*', '')
  end
  return (out:gsub ('^%s+', ''):gsub ('%s+$', ''))
end

---The filter text with its span of time set to `from` to `to`, the last millisecond in it.
---@param text string
---@param from number
---@param to number
---@return string
local function with_range (text, from, to)
  local rest = without_range (text)
  local range = 'after:'
    .. lx.time_text (from)
    .. ' before:'
    .. lx.time_text (to)
  return rest == '' and range or (rest .. ' ' .. range)
end

---@type Logs.HistogramModule
return {
  build = build,
  span = span,
  step_text = step_text,
  time_label = time_label,
  bin_title = bin_title,
  bars_html = bars_html,
  with_range = with_range,
  without_range = without_range,
}
