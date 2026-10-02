-- perf.profiler: which plugin works the hardest, and why the window lags.
--
-- The kernel times every plugin callback and keeps the slow tasks (app.kernel.perf). Once a
-- second this plugin reads what changed and hands it to perf_model.lua, which works out each
-- plugin's share, the stalls and their causes, and the findings. The panel is drawn from HTML
-- strings, one per section, so redrawing it each second stays cheap. It redraws only while it
-- shows, and watches the page's frames only then, since watching keeps the page drawing.

local model = require ('perf_model') --[[@as Profiler.ModelModule]]

local SAMPLE_MS = 1000
-- Counting the elements walks the whole page, so it runs this often at most.
local DOM_MS = 5000
local MAX_ROWS = 60
local MAX_STALLS = 50
local MAX_KINDS = 12
local TAB_ID = 'perf.profiler'

---@class Profiler.Span
---@field id string
---@field label string
---@field seconds? number

---@type Profiler.Span[]
local SPANS = {
  { id = '10', label = '10 s', seconds = 10 },
  { id = '60', label = '1 min', seconds = 60 },
  { id = 'all', label = 'Since start', seconds = nil },
}

---@type table<string, string>
local LEVEL_LABELS = { high = 'High', medium = 'Medium', info = 'Note' }

---@type table<string, string>
local LEVEL_ICONS =
  { high = 'octagon-alert', medium = 'triangle-alert', info = 'info' }

-- lang=css
local CSS = [[
.prof {
  flex: 1;
  height: 100%;
  min-height: 0;
  display: flex;
  flex-direction: column;
  background: var(--bg);
  color: var(--fg);
  font-family: var(--font-ui);
  --s1: #3987e5;
  --s2: #d95926;
  --s3: #199e70;
  --s4: #c98500;
  --s5: #d55181;
  --s0: var(--fg-faint);
}
.prof-bar {
  flex: none;
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 6px;
  padding: 6px 10px;
  border-bottom: 1px solid var(--border);
  background: var(--bg-alt);
}
.prof-spans {
  display: inline-flex;
  border: 1px solid var(--border);
  border-radius: var(--radius);
  overflow: hidden;
}
.prof-span {
  padding: 3px 10px;
  border: none;
  background: none;
  color: var(--fg-muted);
  cursor: pointer;
  font: inherit;
}
.prof-span + .prof-span {
  border-left: 1px solid var(--border);
}
.prof-span.on {
  background: var(--bg-active);
  color: var(--fg);
}
.prof-gap {
  flex: 1;
}
.prof-body {
  flex: 1;
  min-height: 0;
  overflow: auto;
  padding: 12px 14px 24px;
}
.prof-section {
  margin-top: 18px;
}
.prof-section h3 {
  margin: 0 0 8px;
  font-size: 12px;
  font-weight: 600;
  letter-spacing: 0.04em;
  text-transform: uppercase;
  color: var(--fg-muted);
}
.prof-hint {
  margin: -4px 0 8px;
  color: var(--fg-faint);
  font-size: 12px;
}
.prof-cards {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
  gap: 8px;
}
.prof-card {
  padding: 8px 10px;
  border: 1px solid var(--border);
  border-radius: var(--radius);
  background: var(--bg-alt);
  min-width: 0;
}
.prof-card-label {
  font-size: 11px;
  color: var(--fg-muted);
}
.prof-card-value {
  margin-top: 2px;
  font-size: 18px;
  font-weight: 600;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.prof-card-note {
  margin-top: 2px;
  font-size: 11px;
  color: var(--fg-faint);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.prof-chart {
  position: relative;
  display: flex;
  align-items: flex-end;
  gap: 2px;
  height: 90px;
  padding-top: 12px;
  border-bottom: 1px solid var(--border);
}
.prof-col {
  position: relative;
  flex: 1;
  height: 100%;
  display: flex;
  flex-direction: column-reverse;
  gap: 2px;
}
.prof-col:hover {
  background: var(--bg-hover);
}
.prof-seg {
  flex: none;
  min-height: 1px;
  background: var(--s0);
}
.prof-seg:last-child {
  border-radius: 4px 4px 0 0;
}
.prof-mark {
  position: absolute;
  top: -12px;
  left: 50%;
  transform: translateX(-50%);
  color: var(--danger);
  font-size: 10px;
  line-height: 1;
}
.prof-axis {
  display: flex;
  justify-content: space-between;
  margin-top: 3px;
  font-size: 11px;
  color: var(--fg-faint);
}
.prof-legend {
  display: flex;
  flex-wrap: wrap;
  gap: 4px 14px;
  margin-top: 6px;
  font-size: 12px;
  color: var(--fg-muted);
}
.prof-key {
  display: inline-flex;
  align-items: center;
  gap: 5px;
}
.prof-key i {
  width: 10px;
  height: 10px;
  border-radius: 2px;
  background: var(--s0);
}
.prof-key b {
  color: var(--danger);
  font-weight: normal;
}
.s1 {
  background: var(--s1) !important;
}
.s2 {
  background: var(--s2) !important;
}
.s3 {
  background: var(--s3) !important;
}
.s4 {
  background: var(--s4) !important;
}
.s5 {
  background: var(--s5) !important;
}
.prof-findings {
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.prof-finding {
  display: flex;
  align-items: flex-start;
  gap: 8px;
  padding: 7px 10px;
  border: 1px solid var(--border);
  border-left: 3px solid var(--fg-faint);
  border-radius: var(--radius);
  background: var(--bg-alt);
  cursor: default;
}
.prof-finding[data-item] {
  cursor: pointer;
}
.prof-finding.high {
  border-left-color: var(--danger);
}
.prof-finding.medium {
  border-left-color: var(--warning);
}
.prof-finding svg {
  flex: none;
  margin-top: 2px;
}
.prof-finding.high svg {
  color: var(--danger);
}
.prof-finding.medium svg {
  color: var(--warning);
}
.prof-level {
  flex: none;
  min-width: 52px;
  font-size: 11px;
  font-weight: 600;
  color: var(--fg-muted);
  margin-top: 2px;
}
.prof-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 12px;
}
.prof-table th {
  position: sticky;
  top: -12px;
  padding: 5px 8px;
  text-align: right;
  font-weight: 600;
  color: var(--fg-muted);
  background: var(--bg);
  border-bottom: 1px solid var(--border);
  white-space: nowrap;
  cursor: pointer;
}
.prof-table th:first-child,
.prof-table td:first-child {
  text-align: left;
}
.prof-table th.on {
  color: var(--fg);
}
.prof-table td {
  padding: 4px 8px;
  text-align: right;
  border-bottom: 1px solid var(--border);
  font-variant-numeric: tabular-nums;
  white-space: nowrap;
}
.prof-row {
  cursor: pointer;
}
.prof-row:hover td {
  background: var(--bg-hover);
}
.prof-row.open td {
  background: var(--bg-active);
}
.prof-row.idle td {
  color: var(--fg-faint);
}
.prof-id {
  font-family: var(--font-mono);
  font-size: 12px;
}
.prof-dot {
  display: inline-block;
  width: 8px;
  height: 8px;
  margin-right: 6px;
  border-radius: 2px;
  background: transparent;
}
.prof-share {
  display: inline-flex;
  align-items: center;
  justify-content: flex-end;
  gap: 6px;
}
.prof-meter {
  width: 60px;
  height: 6px;
  border-radius: 3px;
  background: var(--bg-active);
  overflow: hidden;
}
.prof-meter span {
  display: block;
  height: 100%;
  background: var(--accent);
}
.prof-detail td {
  padding: 8px 8px 12px 24px;
  text-align: left;
  background: var(--bg-alt);
  white-space: normal;
}
.prof-detail .prof-table {
  margin: 6px 0;
}
.prof-detail .prof-table th {
  position: static;
  background: transparent;
  cursor: default;
}
.prof-actions {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
  margin-top: 6px;
  color: var(--fg-muted);
}
.prof-btn {
  padding: 3px 10px;
  border: 1px solid var(--border);
  border-radius: var(--radius);
  background: var(--bg);
  color: var(--fg);
  cursor: pointer;
  font: inherit;
}
.prof-btn:hover {
  background: var(--bg-hover);
}
.prof-stalls {
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.prof-stall {
  display: grid;
  grid-template-columns: 70px 70px 1fr;
  gap: 4px 10px;
  align-items: center;
  font-size: 12px;
}
.prof-stall-time {
  color: var(--fg-muted);
  font-variant-numeric: tabular-nums;
}
.prof-stall-ms {
  font-weight: 600;
  text-align: right;
  font-variant-numeric: tabular-nums;
}
.prof-split {
  grid-column: 3;
  display: flex;
  gap: 2px;
  height: 6px;
}
.prof-split span {
  min-width: 2px;
  border-radius: 2px;
  background: var(--s0);
}
.prof-split .browser {
  background: repeating-linear-gradient(
    45deg,
    var(--fg-faint) 0 2px,
    transparent 2px 5px
  );
}
.prof-empty {
  padding: 10px 0;
  color: var(--fg-faint);
}
]]

---@param list string[]
---@return table<string, true>
local function set_of (list)
  local out = {} ---@type table<string, true>
  for _, v in ipairs (list) do
    out[v] = true
  end
  return out
end

---Hours between local time and UTC, for the times of day the panel shows.
---@return number
local function utc_offset ()
  local now = os.time ()
  local here = os.date ('*t', now) --[[@as osdate]]
  local utc = os.date ('!*t', now) --[[@as osdate]]
  -- os.time reads both tables as local time, so the UTC one borrows the local daylight
  -- saving flag. Otherwise the offset is an hour out in summer.
  utc.isdst = here.isdst
  return (
    os.time (here --[[@as osdateparam]]) - os.time (utc --[[@as osdateparam]])
  ) / 3600
end

---@type Proteus.Plugin
return {
  name = 'Profiler',
  description = 'Shows which plugin works the hardest, and why the window lags.',
  version = '1.0.0',
  requires = { proteus = '>=0.3.0', features = { 'permissions', 'perf' } },
  -- app.kernel.perf tells what every plugin does and how long it takes, and Restart reloads a
  -- plugin to time its start.
  permissions = { 'kernel' },
  depends = { 'proteus.lib.ui', 'proteus.core.commands' },
  optional = {
    'proteus.ui.tabs',
    'proteus.ui.views',
    'proteus.ui.statusbar',
    'proteus.ui.notify',
    'proteus.ui.palette',
    'proteus.core.keys',
    'proteus.ui.menus',
  },
  activate = function (app)
    local ui = app.use ('ui')
    local commands = app.use ('commands')
    local tabs = app.try_use ('tabs')
    local views = app.try_use ('views')
    local status = app.try_use ('status')
    local notify = app.try_use ('notify')
    local perf = app.kernel.perf
    ui.css (CSS)

    local state = model.new ()
    local offset = utc_offset ()
    local paused = false
    local span_id = app.store.get ('span', '10') --[[@as string]]
    local sort = app.store.get ('sort', 'self') --[[@as string]]
    local open_id = nil ---@type string?
    local restarted = {} ---@type table<string, string> What the last restart of each plugin found.
    local dom = nil ---@type Proteus.PerfDom?
    local dom_at = 0
    local tab = nil ---@type Proteus.Tab?
    local view_open = false

    local h = model.escape

    ---@return Profiler.Span
    local function span ()
      for _, s in ipairs (SPANS) do
        if s.id == span_id then
          return s
        end
      end
      return SPANS[1]
    end

    ---@return boolean
    local function showing ()
      if tab then
        return tab.is_active ()
      end
      return view_open
    end

    -- The panel ----------------------------------------------------------------------------

    local root = nil ---@type Proteus.El?
    local body = nil ---@type Proteus.El?
    local span_buttons = {} ---@type table<string, Proteus.El>
    local pause_button = nil ---@type Proteus.El?

    local render ---@type fun()
    local window_of ---@type fun(seconds?: number): Profiler.Window?
    local stalls_of ---@type fun(from: number): Profiler.Stall[]

    -- The panel's sections, each its own element, and the HTML each shows. A section is drawn
    -- again only when its HTML changed, since parsing HTML and laying it out costs more than
    -- building it.
    local PARTS = {
      'cards',
      'timeline',
      'findings',
      'plugins',
      'stalls',
      'events',
      'startup',
    }
    local parts = {} ---@type table<string, Proteus.El>
    local shown_html = {} ---@type table<string, string>

    ---@param name string
    ---@param html string
    local function put (name, html)
      local el = parts[name]
      if el and shown_html[name] ~= html then
        shown_html[name] = html
        el:html (html)
      end
    end

    -- What the kernel says about each plugin, kept until a plugin starts or stops, since the
    -- table is drawn every second.
    local infos = {} ---@type table<string, Proteus.PluginInfo|false>
    for _, event in ipairs ({
      'kernel:plugin_started',
      'kernel:plugin_stopped',
      'kernel:plugin_reloaded',
    }) do
      app.on (event, function ()
        infos = {}
      end)
    end

    ---@param id string
    ---@return Proteus.PluginInfo?
    local function info_of (id)
      local info = infos[id]
      if info == nil then
        info = app.kernel.plugin (id) or false
        infos[id] = info
      end
      return info or nil
    end

    ---@param id string
    ---@return string
    local function name_of (id)
      if id == 'kernel' then
        return 'The kernel'
      end
      local info = info_of (id)
      return info and info.name or id
    end

    ---@param id string
    ---@return string
    local function dot (id)
      local slot = state.slots[id]
      return '<span class="prof-dot'
        .. (slot and (' s' .. slot) or '')
        .. '"></span>'
    end

    ---@param label string
    ---@param value string
    ---@param note? string
    ---@return string
    local function card (label, value, note)
      return '<div class="prof-card"><div class="prof-card-label">'
        .. h (label)
        .. '</div><div class="prof-card-value" title="'
        .. h (value)
        .. '">'
        .. h (value)
        .. '</div>'
        .. (note and ('<div class="prof-card-note" title="' .. h (note) .. '">' .. h (
          note
        ) .. '</div>') or '')
        .. '</div>'
    end

    ---@param win Profiler.Window
    ---@param stalls Profiler.Stall[]
    ---@param fps? number
    ---@param worst number
    ---@return string
    local function cards_html (win, stalls, fps, worst)
      local out = {} ---@type string[]
      local busy = win.wall > 0 and win.busy / win.wall or 0
      out[#out + 1] = card (
        'Plugin code',
        model.percent (busy) .. ' busy',
        model.ms (win.busy) .. ' of ' .. model.ms (win.wall)
      )
      local top = nil ---@type Profiler.Row?
      local mine = nil ---@type Profiler.Row?
      for _, row in ipairs (win.rows) do
        if row.id == app.id then
          mine = row
        elseif not top then
          top = row
        end
      end
      if top and top.self > 0 then
        local kind = top.kinds[1]
        out[#out + 1] = card (
          'Busiest plugin',
          top.id,
          model.percent (top.share)
            .. ' of the time'
            .. (kind and (', mostly ' .. model.describe (kind.what)) or '')
        )
      else
        out[#out + 1] = card ('Busiest plugin', 'None', 'No plugin code ran')
      end
      if fps then
        out[#out + 1] = card (
          'Frames',
          string.format ('%.0f fps', fps),
          'Longest gap ' .. model.ms (worst)
        )
      else
        out[#out + 1] = card ('Frames', '-', 'Counted while this panel shows')
      end
      local longest = 0
      for _, s in ipairs (stalls) do
        longest = math.max (longest, s.ms)
      end
      out[#out + 1] = card (
        'Stalls',
        model.count (#stalls),
        #stalls > 0 and ('Longest ' .. model.ms (longest)) or 'None over 50 ms'
      )
      out[#out + 1] = card (
        'Lua memory',
        model.count (win.lua_kb / 1024) .. ' MB',
        win.js_kb
            and ('Page scripts ' .. model.count (win.js_kb / 1024) .. ' MB')
          or nil
      )
      if dom then
        out[#out + 1] = card (
          'Elements',
          model.count (dom.total),
          model.count (dom.unowned or 0) .. ' belong to the app itself'
        )
      end
      out[#out + 1] = card (
        'This profiler',
        mine and model.percent (mine.share) or '0%',
        'Its own share, in the table too'
      )
      return '<div class="prof-cards">' .. table.concat (out) .. '</div>'
    end

    ---@return string
    local function timeline_html ()
      local bars = model.timeline (state, stalls_of (0))
      local scale = 100
      for _, b in ipairs (bars) do
        scale = math.max (scale, b.ms)
      end
      local cols = {} ---@type string[]
      for _ = #bars + 1, model.KEEP_SAMPLES - 1 do
        cols[#cols + 1] = '<div class="prof-col"></div>'
      end
      for _, b in ipairs (bars) do
        local tip = {
          model.clock (b.at, offset)
            .. ': '
            .. model.ms (b.ms)
            .. ' of plugin code',
        } ---@type string[]
        local segs = {} ---@type string[]
        for _, part in ipairs (b.parts) do
          tip[#tip + 1] = (part.id == '' and 'Other plugins' or part.id)
            .. ' '
            .. model.ms (part.ms)
          segs[#segs + 1] = string.format (
            '<div class="prof-seg%s" style="height:%.2f%%"></div>',
            part.slot > 0 and (' s' .. part.slot) or '',
            part.ms / scale * 100
          )
        end
        if b.stall then
          tip[#tip + 1] = 'The window stalled in this second'
        end
        cols[#cols + 1] = '<div class="prof-col" title="'
          .. h (table.concat (tip, '\n'))
          .. '">'
          .. (b.stall and '<span class="prof-mark">&#9650;</span>' or '')
          .. table.concat (segs)
          .. '</div>'
      end
      local keys = {} ---@type string[]
      local legend = model.legend (state)
      for slot = 1, model.SLOTS do
        if legend[slot] then
          keys[#keys + 1] = '<span class="prof-key"><i class="s'
            .. slot
            .. '"></i>'
            .. h (legend[slot])
            .. '</span>'
        end
      end
      keys[#keys + 1] = '<span class="prof-key"><i></i>Other plugins</span>'
      keys[#keys + 1] = '<span class="prof-key"><b>&#9650;</b>Stall</span>'
      return '<div class="prof-chart">'
        .. table.concat (cols)
        .. '</div><div class="prof-axis"><span>1 min ago</span><span>Top: '
        .. h (model.ms (scale))
        .. ' a second</span><span>Now</span></div><div class="prof-legend">'
        .. table.concat (keys)
        .. '</div>'
    end

    ---@param findings Profiler.Finding[]
    ---@return string
    local function findings_html (findings)
      local out = {} ---@type string[]
      for _, f in ipairs (findings) do
        out[#out + 1] = '<div class="prof-finding '
          .. f.level
          .. '"'
          .. (f.plugin and (' data-item="plugin:' .. h (f.plugin) .. '" title="Show ' .. h (
            f.plugin
          ) .. ' in the table"') or '')
          .. '>'
          .. (app.util.icon (LEVEL_ICONS[f.level], 14) or '')
          .. '<span class="prof-level">'
          .. LEVEL_LABELS[f.level]
          .. '</span><span>'
          .. h (f.text)
          .. '</span></div>'
      end
      return '<div class="prof-findings">' .. table.concat (out) .. '</div>'
    end

    ---@type { key: string, label: string, title: string }[]
    local COLUMNS = {
      { key = 'id', label = 'Plugin', title = 'Sort by name' },
      {
        key = 'self',
        label = 'Share',
        title = 'Time in its own code, as a share of the window',
      },
      {
        key = 'total',
        label = 'With nested',
        title = 'Its time with the handlers of other plugins it set off',
      },
      {
        key = 'calls',
        label = 'Calls',
        title = 'How many of its callbacks ran',
      },
      { key = 'avg', label = 'Each', title = 'Its own time per call' },
      {
        key = 'longest',
        label = 'Longest',
        title = 'Its longest share of one task over 4 ms',
      },
      {
        key = 'errors',
        label = 'Errors',
        title = 'Callbacks that raised an error',
      },
      {
        key = 'nodes',
        label = 'Elements',
        title = 'Elements it has on the page',
      },
      {
        key = 'start',
        label = 'Start',
        title = 'Loading its code and running activate, the last time',
      },
    }

    ---@param row Profiler.Row
    ---@return number|string
    local function sort_value (row)
      if sort == 'id' then
        return row.id
      elseif sort == 'total' then
        return row.total
      elseif sort == 'calls' then
        return row.calls
      elseif sort == 'avg' then
        return row.calls > 0 and row.self / row.calls or 0
      elseif sort == 'longest' then
        return row.longest or 0
      elseif sort == 'errors' then
        return row.errors
      elseif sort == 'nodes' then
        local d = dom and dom.plugins[row.id] or nil
        return d and d.nodes or 0
      elseif sort == 'start' then
        return (row.load or 0) + (row.start or 0)
      end
      return row.self
    end

    ---@param row Profiler.Row
    ---@return string
    local function detail_html (row)
      local kinds = {} ---@type string[]
      for i, k in ipairs (row.kinds) do
        if i > MAX_KINDS then
          break
        end
        kinds[#kinds + 1] = '<tr><td>'
          .. h (model.describe (k.what))
          .. '</td><td>'
          .. h (model.ms (k.self))
          .. '</td><td>'
          .. h (model.count (k.calls))
          .. '</td><td>'
          .. h (model.ms (k.self / k.calls))
          .. '</td></tr>'
      end
      local info = info_of (row.id)
      local can_restart = info ~= nil
        and info.status == 'active'
        and not info.locked
        and row.id ~= app.id
      local actions = {} ---@type string[]
      if can_restart then
        actions[#actions + 1] = '<button class="prof-btn" data-item="restart:'
          .. h (row.id)
          .. '" title="Stops it and the plugins that use it, loads its code again, and starts them">Restart and time its start</button>'
      end
      if restarted[row.id] then
        actions[#actions + 1] = '<span>' .. h (restarted[row.id]) .. '</span>'
      end
      return '<tr class="prof-detail"><td colspan="'
        .. #COLUMNS
        .. '"><div>'
        .. h (name_of (row.id))
        .. (info and info.description ~= '' and (': ' .. h (info.description)) or '')
        .. '</div>'
        .. (#kinds > 0 and ('<table class="prof-table"><tr><th>Where the time went</th><th>Self</th><th>Calls</th><th>Each</th></tr>' .. table.concat (
          kinds
        ) .. '</table>') or '<div class="prof-empty">No callbacks ran in this window.</div>')
        .. (#actions > 0 and ('<div class="prof-actions">' .. table.concat (
          actions
        ) .. '</div>') or '')
        .. '</td></tr>'
    end

    ---@param win Profiler.Window
    ---@return string
    local function plugins_html (win)
      local rows = {} ---@type Profiler.Row[]
      for _, row in ipairs (win.rows) do
        rows[#rows + 1] = row
      end
      table.sort (rows, function (a, b)
        local x, y = sort_value (a), sort_value (b)
        if x ~= y then
          if sort == 'id' then
            return x < y
          end
          return x > y
        end
        return a.id < b.id
      end)
      local running = set_of (app.kernel.active ())
      local top_share = 0
      for _, row in ipairs (rows) do
        top_share = math.max (top_share, row.share)
      end
      local head = {} ---@type string[]
      for _, c in ipairs (COLUMNS) do
        head[#head + 1] = '<th data-item="sort:'
          .. c.key
          .. '" title="'
          .. h (c.title)
          .. '"'
          .. (c.key == sort and ' class="on"' or '')
          .. '>'
          .. h (c.label)
          .. '</th>'
      end
      local body_rows = {} ---@type string[]
      for i, row in ipairs (rows) do
        if i > MAX_ROWS then
          break
        end
        local d = dom and dom.plugins[row.id] or nil
        local idle = row.id ~= 'kernel' and not running[row.id]
        local classes = 'prof-row'
          .. (row.id == open_id and ' open' or '')
          .. (idle and ' idle' or '')
        local start = (row.load or 0) + (row.start or 0)
        body_rows[#body_rows + 1] = '<tr class="'
          .. classes
          .. '" data-item="plugin:'
          .. h (row.id)
          .. '" title="'
          .. h (name_of (row.id) .. (idle and ' (not running)' or ''))
          .. '"><td>'
          .. dot (row.id)
          .. '<span class="prof-id">'
          .. h (row.id)
          .. '</span></td><td><span class="prof-share">'
          .. h (model.ms (row.self))
          .. ' <span class="prof-meter"><span style="width:'
          .. string.format (
            '%.1f',
            top_share > 0 and row.share / top_share * 100 or 0
          )
          .. '%"></span></span>'
          .. h (model.percent (row.share))
          .. '</span></td><td>'
          .. h (model.ms (row.total))
          .. '</td><td>'
          .. h (model.count (row.calls))
          .. '</td><td>'
          .. h (row.calls > 0 and model.ms (row.self / row.calls) or '-')
          .. '</td><td>'
          .. h (row.longest and model.ms (row.longest) or '-')
          .. '</td><td>'
          .. h (row.errors > 0 and model.count (row.errors) or '')
          .. '</td><td>'
          .. h (d and model.count (d.nodes) or '')
          .. '</td><td>'
          .. h (start > 0 and model.ms (start) or '')
          .. '</td></tr>'
        if row.id == open_id then
          body_rows[#body_rows + 1] = detail_html (row)
        end
      end
      if #body_rows == 0 then
        return '<div class="prof-empty">No plugin code ran in this window.</div>'
      end
      return '<table class="prof-table"><tr>'
        .. table.concat (head)
        .. '</tr>'
        .. table.concat (body_rows)
        .. '</table>'
    end

    ---@param stalls Profiler.Stall[]
    ---@return string
    local function stalls_html (stalls)
      if #stalls == 0 then
        return '<div class="prof-empty">The window has not frozen for 50 ms or more in this stretch.</div>'
      end
      local out = {} ---@type string[]
      for i = #stalls, math.max (1, #stalls - MAX_STALLS + 1), -1 do
        local s = stalls[i]
        local split = {} ---@type string[]
        local tip = {} ---@type string[]
        for _, part in ipairs (s.parts) do
          if part.ms >= 1 then
            local slot = state.slots[part.owner]
            split[#split + 1] = string.format (
              '<span class="%s" style="flex:%.1f"></span>',
              slot and ('s' .. slot) or '',
              part.ms
            )
            tip[#tip + 1] = part.owner
              .. ', '
              .. model.describe (part.what)
              .. ': '
              .. model.ms (part.ms)
          end
        end
        if s.browser >= 1 then
          split[#split + 1] = string.format (
            '<span class="browser" style="flex:%.1f"></span>',
            s.browser
          )
          tip[#tip + 1] = 'The browser: ' .. model.ms (s.browser)
        end
        out[#out + 1] = '<div class="prof-stall" title="'
          .. h (table.concat (tip, '\n'))
          .. '"><span class="prof-stall-time">'
          .. h (model.clock (s.at, offset))
          .. '</span><span class="prof-stall-ms">'
          .. h (model.ms (s.ms))
          .. '</span><span>'
          .. h (s.cause)
          .. '</span><div class="prof-split">'
          .. table.concat (split)
          .. '</div></div>'
      end
      return '<div class="prof-stalls">' .. table.concat (out) .. '</div>'
    end

    ---@param win Profiler.Window
    ---@return string
    local function events_html (win)
      if #win.events == 0 then
        return '<div class="prof-empty">No events were sent in this stretch.</div>'
      end
      local rows = {} ---@type string[]
      for i, ev in ipairs (win.events) do
        if i > 30 then
          break
        end
        rows[#rows + 1] = '<tr><td class="prof-id">'
          .. h (ev.name)
          .. '</td><td>'
          .. h (model.count (ev.sent))
          .. '</td><td>'
          .. h (string.format ('%.1f', ev.rate))
          .. '</td><td>'
          .. h (model.ms (ev.ms))
          .. '</td></tr>'
      end
      return '<table class="prof-table"><tr><th>Event</th><th>Sent</th><th>A second</th><th>Listeners took</th></tr>'
        .. table.concat (rows)
        .. '</table>'
    end

    ---@return string
    local function startup_html ()
      local last = state.samples[#state.samples]
      if not last then
        return ''
      end
      local running = set_of (app.kernel.active ())
      local list = {} ---@type { id: string, load?: number, start?: number }[]
      for id, p in pairs (last.stats.plugins) do
        if running[id] and (p.load or p.start) then
          list[#list + 1] = { id = id, load = p.load, start = p.start }
        end
      end
      table.sort (list, function (a, b)
        return (a.load or 0) + (a.start or 0) > (b.load or 0) + (b.start or 0)
      end)
      local rows = {} ---@type string[]
      for i, row in ipairs (list) do
        if i > 25 then
          break
        end
        rows[#rows + 1] = '<tr class="prof-row" data-item="plugin:'
          .. h (row.id)
          .. '"><td class="prof-id">'
          .. h (row.id)
          .. '</td><td>'
          .. h (model.ms (row.load or 0))
          .. '</td><td>'
          .. h (model.ms (row.start or 0))
          .. '</td><td>'
          .. h (model.ms ((row.load or 0) + (row.start or 0)))
          .. '</td></tr>'
      end
      return '<table class="prof-table"><tr><th>Plugin</th><th>Loading its code</th><th>activate</th><th>Together</th></tr>'
        .. table.concat (rows)
        .. '</table>'
    end

    ---@param title string
    ---@param hint? string
    ---@param inner string
    ---@return string
    local function section (title, hint, inner)
      return '<section class="prof-section"><h3>'
        .. h (title)
        .. '</h3>'
        .. (hint and ('<p class="prof-hint">' .. h (hint) .. '</p>') or '')
        .. inner
        .. '</section>'
    end

    -- The status bar and the panel ask for the same windows, so each is worked out once a tick.
    local memo = {} ---@type table<string, Profiler.Window|false>
    local memo_stalls = {} ---@type table<number, Profiler.Stall[]>

    ---@param seconds? number
    ---@return Profiler.Window?
    function window_of (seconds)
      local key = tostring (seconds)
      local win = memo[key]
      if win == nil then
        win = model.window (state, seconds) or false
        memo[key] = win
      end
      return win or nil
    end

    ---The stalls since `from`, in milliseconds since 1970, or every stall kept for 0.
    ---@param from number
    ---@return Profiler.Stall[]
    function stalls_of (from)
      local stalls = memo_stalls[from]
      if not stalls then
        stalls = model.stalls (state, from)
        memo_stalls[from] = stalls
      end
      return stalls
    end

    local function forget ()
      memo, memo_stalls = {}, {}
    end

    ---What the panel and the report need for the chosen stretch of time.
    ---@return Profiler.Window? win
    ---@return Profiler.Stall[] stalls
    ---@return Profiler.Finding[] findings
    ---@return number? fps
    ---@return number worst
    local function current ()
      local s = span ()
      local win = window_of (s.seconds)
      if not win then
        return nil, {}, {}, nil, 0
      end
      local stalls = stalls_of (win.from)
      local fps, worst = model.fps (state, s.seconds)
      return win,
        stalls,
        model.findings (win, stalls, dom, fps, app.id, offset),
        fps,
        worst
    end

    render = function ()
      if not body then
        return
      end
      for id, b in pairs (span_buttons) do
        b:class ('on', id == span_id)
      end
      if pause_button then
        pause_button:text (paused and 'Resume' or 'Pause')
      end
      local win, stalls, findings, fps, worst = current ()
      if not win then
        put (
          'cards',
          '<div class="prof-empty">Reading the first numbers...</div>'
        )
        return
      end
      put ('cards', cards_html (win, stalls, fps, worst))
      put (
        'timeline',
        section (
          'Timeline',
          'Plugin code in each second of the last minute, by plugin. A taller bar is a busier second.',
          timeline_html ()
        )
      )
      put (
        'findings',
        section ('What stands out', nil, findings_html (findings))
      )
      put (
        'plugins',
        section (
          'Plugins',
          "Share is time in the plugin's own code. Click a row to see where its time went.",
          plugins_html (win)
        )
      )
      put (
        'stalls',
        section (
          'Stalls',
          "Times the window froze for 50 ms or more, newest first. The bar splits each one into plugin code and the browser's own work, striped.",
          stalls_html (stalls)
        )
      )
      put ('events', section ('Events', nil, events_html (win)))
      put (
        'startup',
        section (
          'Start-up',
          'How long each running plugin took to load and start, the last time it did.',
          startup_html ()
        )
      )
    end

    ---@param text string
    local function tell (text)
      if notify then
        notify.info (text)
      else
        app.log (text)
      end
    end

    ---Reloads a plugin and reads how long its start took.
    ---@param id string
    local function restart (id)
      local ok, err = app.kernel.reload (id)
      if not ok then
        restarted[id] = 'It did not start again: ' .. tostring (err)
      else
        local p = perf.stats ().plugins[id]
        restarted[id] = 'Started again: '
          .. model.ms (p and p.load or 0)
          .. ' loading its code, '
          .. model.ms (p and p.start or 0)
          .. ' in activate.'
      end
      render ()
    end

    ---@param ev Proteus.DomEvent
    local function on_click (ev)
      local item = ev.item
      if not item then
        return
      end
      local kind, value = item:match ('^(%a+):(.*)$')
      if kind == 'plugin' then
        open_id = open_id ~= value and value or nil
        render ()
      elseif kind == 'sort' then
        sort = value
        app.store.set ('sort', sort)
        render ()
      elseif kind == 'restart' then
        restart (value)
      end
    end

    ---@return string
    local function report ()
      local win, stalls, findings = current ()
      if not win then
        return 'No numbers yet.\n'
      end
      return model.report (win, stalls, findings, dom, offset)
    end

    local function reset ()
      perf.reset ()
      state = model.new ()
      forget ()
      restarted = {}
      render ()
    end

    local function toggle_pause ()
      paused = not paused
      render ()
    end

    local function copy_report ()
      app.system.clipboard (report ())
      tell ('The profile is on the clipboard, as Markdown.')
    end

    local function save_report ()
      local stamp = os.date ('%Y-%m-%d-%H%M%S') --[[@as string]]
      local path = 'data/' .. app.id .. '/profile-' .. stamp .. '.md'
      app.fs.write (path, report ())
      tell ('Saved the profile to ' .. path .. '.')
    end

    ---@return Proteus.El
    local function build ()
      span_buttons = {}
      local spans = ui.div ({ class = 'prof-spans' })
      for _, s in ipairs (SPANS) do
        local b = ui.h ('button', {
          class = 'prof-span',
          s.label,
          title = s.seconds and ('The last ' .. s.label)
            or 'Since the app started, or since Reset',
          onclick = function ()
            span_id = s.id
            app.store.set ('span', span_id)
            render ()
          end,
        })
        span_buttons[s.id] = b
        spans:append (b)
      end
      pause_button = ui.button ({
        variant = 'ghost',
        text = 'Pause',
        title = 'Stops reading new numbers, so the panel holds still',
        onclick = toggle_pause,
      })
      body = ui.div ({ class = 'prof-body' })
      parts, shown_html = {}, {}
      for _, name in ipairs (PARTS) do
        parts[name] = ui.div ()
        body:append (parts[name])
      end
      body:on ('click', on_click)
      root = ui.div ({
        class = 'prof',
        ui.div ({
          class = 'prof-bar',
          spans,
          ui.div ({ class = 'prof-gap' }),
          pause_button,
          ui.button ({
            variant = 'ghost',
            icon = 'rotate-ccw',
            'Reset',
            title = 'Starts counting from now',
            onclick = reset,
          }),
          ui.button ({
            variant = 'ghost',
            icon = 'copy',
            'Copy Report',
            onclick = copy_report,
          }),
          ui.button ({
            variant = 'ghost',
            icon = 'save',
            'Save Report',
            onclick = save_report,
          }),
        }),
        body,
      })
      return root --[[@as Proteus.El]]
    end

    local function open ()
      if tabs then
        local existing = tab and tabs.get (TAB_ID) or nil
        if existing then
          existing.focus ()
        else
          tab = tabs.open ({
            id = TAB_ID,
            title = 'Profiler',
            icon = 'gauge',
            content = build (),
            on_focus = function ()
              render ()
            end,
            on_close = function ()
              tab, body, root, parts = nil, nil, nil, {}
              return true
            end,
          })
        end
        render ()
      elseif views then
        views.show ('profiler.panel')
      end
    end

    if not tabs and views then
      views.add ('bottom', {
        id = 'profiler.panel',
        title = 'Profiler',
        icon = 'gauge',
        content = build (),
        on_show = function ()
          view_open = true
          render ()
        end,
      })
    end

    -- Reading the numbers ------------------------------------------------------------------

    local item = status
      and status.add ({
        id = 'profiler.status',
        icon = 'gauge',
        text = '',
        tooltip = 'Profiler',
        align = 'right',
        order = 90,
        command = 'profiler.open',
      })
    local last_stall_shown = 0

    local function update_status ()
      if not item then
        return
      end
      local win = window_of (10)
      if not win then
        return
      end
      local busy = win.wall > 0 and win.busy / win.wall or 0
      local top = nil ---@type Profiler.Row?
      for _, row in ipairs (win.rows) do
        if row.id ~= app.id then
          top = row
          break
        end
      end
      local stalls = stalls_of (win.from)
      local newest = stalls[#stalls]
      local tip = 'Plugin code: '
        .. model.percent (busy)
        .. ' of the last 10 s.'
      if top and top.self > 0 then
        tip = tip
          .. ' Busiest: '
          .. top.id
          .. ', '
          .. model.percent (top.share)
          .. '.'
      end
      if #stalls > 0 then
        tip = tip .. ' ' .. model.count (#stalls) .. ' stalls.'
      end
      item.set_tooltip (tip .. ' Click to open the Profiler.')
      if newest and newest.at > last_stall_shown then
        item.set ('Stall ' .. model.ms (newest.ms))
        item.accent (true)
        if newest.at + 5000 < win.to then
          last_stall_shown = newest.at
        end
      else
        item.set (model.percent (busy))
        item.accent (false)
      end
    end

    local function sample ()
      if paused then
        return
      end
      local shown = showing ()
      model.add (
        state,
        perf.stats (),
        perf.tasks (state.task_seq),
        perf.frames (state.frame_seq, shown)
      )
      forget ()
      update_status ()
      if shown then
        local now = app.util.now ()
        if now - dom_at >= DOM_MS then
          dom, dom_at = perf.dom (), now
        end
        render ()
      end
    end

    app.timer.every (SAMPLE_MS, sample)
    sample ()

    commands.register ({
      id = 'profiler.open',
      category = 'Profiler',
      title = 'Open Profiler',
      icon = 'gauge',
      key = 'ctrl+alt+shift+p',
      run = open,
    })
    commands.register ({
      id = 'profiler.reset',
      category = 'Profiler',
      title = 'Reset',
      icon = 'rotate-ccw',
      run = reset,
    })
    commands.register ({
      id = 'profiler.pause',
      category = 'Profiler',
      title = 'Pause or Resume',
      icon = 'pause',
      run = toggle_pause,
    })
    commands.register ({
      id = 'profiler.copy',
      category = 'Profiler',
      title = 'Copy Report',
      icon = 'copy',
      run = copy_report,
    })
    commands.register ({
      id = 'profiler.save',
      category = 'Profiler',
      title = 'Save Report',
      icon = 'save',
      run = save_report,
    })
  end,
}
