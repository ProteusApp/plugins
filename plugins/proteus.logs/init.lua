-- proteus.logs: a log viewer. It follows log files and running programs, and shows their lines
-- as they arrive, with a filter, level colours and a detail view. The logic that needs no
-- screen lives in log_filter.lua, where the tests reach it.
--
-- Lines can arrive by the thousand, so the list is drawn from HTML strings instead of one
-- element per row. Rows go into chunks of a few hundred, and each chunk is one element. New
-- rows join the last chunk, and whole chunks drop off the top once the list passes its cap.
--
-- The list shows a window of up to 5,000 of the lines that match. Bars above and below it move
-- the window, so every line that matches can be reached. The merged view shows the lines of
-- every source in one list, in order of time.

local lf = require ('log_filter') --[[@as Logs.FilterModule]]

local MAX_LINES = 50000 -- kept per source
local MAX_WHOLE = 250000 -- kept for a whole file
local MAX_SHOWN = 5000 -- drawn at once
local PAGE_STEP = 2500 -- how far the window moves
local CHUNK_ROWS = 250
local FLUSH_MS = 100
local FILTER_MS = 150
local MAX_RECENT = 12
local DESKTOP_ONLY =
  'Following files and running commands needs the desktop app.'

---@type table<string, string>
local LEVEL_NAMES = {
  error = 'Error',
  warn = 'Warn',
  info = 'Info',
  debug = 'Debug',
  other = 'Other',
}

---@type table<string, string>
local LEVEL_PLURALS = {
  error = 'Errors',
  warn = 'Warnings',
  info = 'Info Lines',
  debug = 'Debug Lines',
  other = 'Lines With No Level',
}

---@type table<string, string>
local KIND_ICONS = {
  file = 'file-text',
  command = 'square-terminal',
  paste = 'clipboard-paste',
}

-- lang=css
local CSS = [[
.logs {
  flex: 1;
  height: 100%;
  min-height: 0;
  display: flex;
  flex-direction: column;
  background: var(--bg);
  color: var(--fg);
}
.logs-bar {
  flex: none;
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 6px;
  padding: 6px 8px;
  border-bottom: 1px solid var(--border);
  background: var(--bg-alt);
}
.logs-filter {
  flex: 1 1 220px;
  min-width: 160px;
  max-width: 460px;
  font-family: var(--font-mono);
}
.logs-chips {
  display: flex;
  flex-wrap: wrap;
  gap: 4px;
}
.logs-chip {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  padding: 2px 9px;
  border: 1px solid var(--border);
  border-radius: 99px;
  background: var(--bg-elev);
  color: var(--fg);
  font: inherit;
  font-size: 12px;
  cursor: pointer;
}
.logs-chip::before {
  content: "";
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: var(--fg-faint);
}
.logs-chip:hover {
  background: var(--bg-hover);
}
.logs-chip.off {
  opacity: 0.45;
  text-decoration: line-through;
}
.logs-chip-error::before {
  background: var(--danger);
}
.logs-chip-warn::before {
  background: var(--warning);
}
.logs-chip-info::before {
  background: var(--accent);
}
.logs-chip-debug::before {
  background: var(--fg-muted);
}
.logs-chip-n {
  color: var(--fg-muted);
  font-variant-numeric: tabular-nums;
}
.logs-bar .ui-button {
  padding: 3px 9px;
  font-size: 12px;
}
.logs-bar .logs-toggle.on {
  color: var(--accent);
  border-color: var(--accent);
}
.logs-body {
  flex: 1;
  min-height: 0;
  display: flex;
  flex-direction: column;
}
.logs-list {
  flex: 1;
  min-height: 0;
  overflow: auto;
  position: relative;
  outline: none;
  padding: 4px 0;
  font: 12px/18px var(--font-mono);
}
.logs-row {
  display: flex;
  width: max-content;
  min-width: 100%;
  white-space: pre;
  border-left: 2px solid transparent;
}
.logs-row:hover {
  background: var(--bg-hover);
}
.logs-wrap .logs-row {
  width: auto;
  white-space: pre-wrap;
  overflow-wrap: anywhere;
}
.logs-n {
  flex: none;
  min-width: 5.5em;
  padding: 0 12px 0 6px;
  text-align: right;
  color: var(--fg-faint);
  user-select: none;
}
.logs-t {
  flex: 1;
  min-width: 0;
  padding-right: 12px;
}
.logs-lv-error {
  color: var(--danger);
}
.logs-lv-warn {
  color: var(--warning);
}
.logs-lv-debug {
  color: var(--fg-muted);
}
.logs-stderr {
  border-left-color: var(--danger);
}
.logs-list mark {
  background: var(--accent);
  color: var(--accent-fg);
  border-radius: 2px;
}
.logs-more {
  color: var(--fg-faint);
}
.logs-b {
  font-weight: 700;
}
.logs-c0,
.logs-c8 {
  color: var(--fg-faint);
}
.logs-c1,
.logs-c9 {
  color: var(--danger);
}
.logs-c2 {
  color: var(--success);
}
.logs-c3 {
  color: var(--warning);
}
.logs-c4,
.logs-c12 {
  color: var(--syn-function);
}
.logs-c5,
.logs-c13 {
  color: var(--syn-keyword);
}
.logs-c6 {
  color: var(--syn-operator);
}
.logs-c7 {
  color: var(--fg-muted);
}
.logs-c10 {
  color: var(--syn-string);
}
.logs-c11 {
  color: var(--syn-property);
}
.logs-c14 {
  color: var(--syn-builtin);
}
.logs-c15 {
  color: var(--fg);
}
.logs-empty {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 8px;
  padding: 24px;
  text-align: center;
  color: var(--fg-muted);
}
.logs-empty-title {
  font-size: 16px;
  font-weight: 600;
  color: var(--fg);
}
.logs-empty-text {
  max-width: 420px;
}
.logs-empty-actions {
  display: flex;
  flex-wrap: wrap;
  justify-content: center;
  gap: 8px;
  margin-top: 8px;
}
.logs-detail {
  flex: none;
  height: 38%;
  min-height: 140px;
  display: flex;
  flex-direction: column;
  border-top: 1px solid var(--border);
  background: var(--bg-alt);
}
.logs-detail-head {
  flex: none;
  display: flex;
  align-items: center;
  gap: 4px;
  padding: 3px 6px 3px 12px;
  border-bottom: 1px solid var(--border);
  font-size: 12px;
}
.logs-detail-head .ui-button {
  padding: 3px 8px;
  font-size: 12px;
}
.logs-detail-title {
  color: var(--fg-muted);
}
.logs-detail-body {
  flex: 1;
  min-height: 0;
  display: flex;
  flex-direction: column;
}
.logs-detail-text {
  flex: 1;
  min-height: 0;
  margin: 0;
  padding: 8px 12px;
  overflow: auto;
  font: 12px/1.5 var(--font-mono);
  white-space: pre-wrap;
  overflow-wrap: anywhere;
  user-select: text;
}
.logs-has-json .logs-detail-text {
  flex: none;
  max-height: 5.5em;
  border-bottom: 1px solid var(--border);
}
.logs-json {
  flex: 1;
  min-height: 0;
}
.logs-side {
  display: flex;
  flex-direction: column;
  height: 100%;
  min-height: 0;
}
.logs-side-actions {
  flex: none;
  display: flex;
  gap: 4px;
  padding: 8px;
}
.logs-side-actions .ui-button {
  flex: 1;
  justify-content: center;
  padding: 4px 6px;
  font-size: 12px;
}
.logs-sources {
  flex: 1;
  min-height: 0;
  overflow: auto;
  padding: 0 6px 8px;
}
.logs-src {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 6px 6px 6px 8px;
  border-radius: var(--radius);
  cursor: pointer;
}
.logs-src:hover {
  background: var(--bg-hover);
}
.logs-src.active {
  background: var(--bg-active);
}
.logs-src-icon {
  display: inline-flex;
  color: var(--fg-muted);
}
.logs-src-name {
  flex: 1;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.logs-src-count {
  font-size: 11px;
  color: var(--fg-faint);
  font-variant-numeric: tabular-nums;
}
.logs-dot {
  flex: none;
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: var(--fg-faint);
}
.logs-dot-running {
  background: var(--success);
}
.logs-dot-done {
  background: var(--fg-muted);
}
.logs-dot-exit {
  background: var(--warning);
}
.logs-dot-failed {
  background: var(--danger);
}
.logs-dot-pasted {
  background: var(--accent);
}
.logs-batch {
  display: contents;
}
.logs-tag {
  flex: none;
  max-width: 12em;
  margin-right: 8px;
  padding: 0 6px;
  border-radius: 4px;
  overflow: hidden;
  text-overflow: ellipsis;
  background: var(--bg-active);
  color: var(--fg-muted);
}
.logs-tag-1 {
  color: var(--accent);
}
.logs-tag-2 {
  color: var(--success);
}
.logs-tag-3 {
  color: var(--warning);
}
.logs-tag-4 {
  color: var(--syn-keyword);
}
.logs-tag-5 {
  color: var(--syn-function);
}
.logs-page {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 4px 12px;
  color: var(--fg-muted);
  font-family: var(--font-ui);
}
.logs-filter.bad {
  border-color: var(--danger);
}
.logs-problem {
  flex: 1 1 100%;
  color: var(--danger);
  font-size: 12px;
}
.logs-src.merged .logs-src-name {
  font-style: italic;
}
.logs-src-close {
  display: inline-flex;
  padding: 2px;
  border: none;
  border-radius: 4px;
  background: none;
  color: var(--fg-faint);
  cursor: pointer;
  opacity: 0;
}
.logs-src:hover .logs-src-close,
.logs-src.active .logs-src-close {
  opacity: 1;
}
.logs-src-close:hover {
  color: var(--fg);
  background: var(--bg-hover);
}
.logs-src-none {
  padding: 16px 8px;
  text-align: center;
  color: var(--fg-faint);
}
]]

---A source open in the app.
---@class Logs.Source
---@field id integer
---@field spec Logs.SourceSpec
---@field name string
---@field lines Logs.Ring
---@field next_n integer The number the next line gets.
---@field state Logs.State
---@field code? integer The exit code, once the program has ended.
---@field detail? string Why the program could not start.
---@field proc? Proteus.ProcessHandle
---@field run integer Goes up with each start and stop, so output from an old run is ignored.
---@field count_el? Proteus.El The line count in the Sources view.
---@field counted integer The line count shown there now.
---@field last_time? number The time of the newest line that has one, for a line that says none.

---Rows drawn as one element.
---@class Logs.Chunk
---@field el Proteus.El
---@field ns integer[] The ids of the lines in its rows, in order.

---@type Proteus.Plugin
return {
  name = 'Logs',
  description = 'Follow a log file or a program, filter the lines, and spot errors.',
  version = '1.2.0',
  requires = { proteus = '>=0.3.0', features = { 'permissions' } },
  -- It runs the programs the user names, and follows a log file anywhere on disk with one. Paste
  -- Log reads the clipboard.
  permissions = { 'clipboard', 'files', 'process' },
  depends = {
    'proteus.lib.ui',
    'proteus.ui.shell',
    'proteus.ui.views',
    'proteus.core.commands',
  },
  optional = {
    'proteus.ui.toolbar',
    'proteus.ui.statusbar',
    'proteus.ui.palette',
    'proteus.ui.notify',
    'proteus.core.keys',
    'proteus.ui.menus',
    'proteus.ui.tabs',
  },
  activate = function (app)
    local ui = app.use ('ui')
    local shell = app.use ('shell')
    local views = app.use ('views')
    local commands = app.use ('commands')
    local status = app.try_use ('status')
    local notify = app.try_use ('notify')
    local picker = app.try_use ('picker')
    local menus = app.try_use ('menus')
    local tabs = app.try_use ('tabs')
    ui.css (CSS)
    local desktop = app.platform ~= 'browser'

    local sources = {} ---@type Logs.Source[]
    local shown = nil ---@type Logs.Source?
    -- True while the list shows every source, merged by time. Then `shown` is nil.
    local merged = false
    local next_line_id = 1
    -- Every line of the view that passes the filter and the chips, and the window of them drawn.
    local view_all = {} ---@type Logs.Line[]
    local win_from = 1
    -- The drawn lines by id, and the chunk each sits in.
    local by_id = {} ---@type table<integer, Logs.Line>
    local where = {} ---@type table<integer, Logs.Chunk>
    -- The time of the view's newest line, for a filter such as after:-15m.
    local view_newest = nil ---@type number?
    local next_id = 1
    local query = lf.parse_query ('')
    local hidden = {} ---@type table<string, boolean>
    for _, level in ipairs (lf.clean_levels (app.store.get ('hidden', {}))) do
      hidden[level] = true
    end
    local wrap = app.store.get ('wrap', false) == true
    local follow = true
    local selected = nil ---@type Logs.Line?
    local pending = {} ---@type Logs.Line[]
    local flush_cancel = nil ---@type fun()?
    local filter_cancel = nil ---@type fun()?
    local chunks = {} ---@type Logs.Chunk[]
    local drawn = 0 -- rows in the chunks
    local matched = 0 -- lines that pass the filter and the chips
    local levels = lf.zero_levels () -- lines of each level that pass the filter
    local empty_key = nil ---@type string?
    local recent = lf.clean_specs (app.store.get ('recent', {}))
    local my_tab = nil ---@type Proteus.Tab?

    ---@type fun(src: Logs.Source?)
    local show_source
    ---@type fun()
    local redraw_list
    ---@type fun()
    local render_sources
    ---@type fun()
    local flush

    local icon_cache = {} ---@type table<string, string>
    ---@param name string
    ---@return string
    local function icon_svg (name)
      local svg = icon_cache[name]
      if not svg then
        svg = app.util.icon (name, 14) or ''
        icon_cache[name] = svg
      end
      return svg
    end

    ---@param text string
    local function say (text)
      if notify then
        notify.info (text)
      else
        app.log (text)
      end
    end

    ---@param text string
    local function say_error (text)
      if notify then
        notify.error (text)
      else
        app.warn (text)
      end
    end

    ---True while the Logs screen is the one in front.
    ---@return boolean
    local function here ()
      return my_tab == nil or my_tab.is_active ()
    end

    -- Screen parts ---------------------------------------------------------------------------

    local FILTER_TIP =
      'Every word must appear. -word hides lines with it. /a|b/ is a regular expression. level:warn keeps one level. after:12:00 and before:2024-03-01T13:00 keep a span of time, and after:-15m the last 15 minutes.'
    local filter_box = ui.input ({
      class = 'logs-filter',
      placeholder = 'Filter: words, -word, "a phrase", /regex/, level:error, after:12:00',
      title = FILTER_TIP,
      spellcheck = false,
    })
    local problem_el = ui.span ({ class = 'logs-problem' })
    problem_el:show (false)
    local chips = ui.div ({ class = 'logs-chips' })
    local chip_buttons = {} ---@type table<string, Proteus.El>
    local chip_counts = {} ---@type table<string, Proteus.El>
    local chip_values = {} ---@type table<string, integer>
    for _, level in ipairs (lf.LEVELS) do
      local count = ui.span ({ class = 'logs-chip-n', '0' })
      local button = ui.h ('button', {
        class = 'logs-chip logs-chip-' .. level,
        attrs = { ['data-item'] = level },
        LEVEL_NAMES[level],
        count,
      })
      chip_buttons[level] = button
      chip_counts[level] = count
      chips:append (button)
    end
    local follow_btn = ui.button ({
      variant = 'ghost',
      class = 'logs-toggle',
      title = 'Stay at the bottom as lines arrive',
      ui.icon ('arrow-down-to-line', 14),
      'Follow',
    })
    local wrap_btn = ui.button ({
      variant = 'ghost',
      class = 'logs-toggle',
      title = 'Wrap long lines (Alt+Z)',
      ui.icon ('text-wrap', 14),
      'Wrap',
    })
    local clear_btn = ui.button ({
      variant = 'ghost',
      title = 'Clear the lines (Ctrl+K)',
      ui.icon ('eraser', 14),
      'Clear',
    })
    -- The window of matching lines sits between two bars that move it.
    local earlier_text = ui.span ({})
    local earlier_bar = ui.div ({
      class = 'logs-page',
      earlier_text,
      ui.button ({
        variant = 'ghost',
        class = 'ui-small',
        ui.icon ('chevrons-up', 14),
        'Show Earlier',
        onclick = function ()
          commands.run ('logs.earlier')
          return nil
        end,
      }),
    })
    local later_text = ui.span ({})
    local later_bar = ui.div ({
      class = 'logs-page',
      later_text,
      ui.button ({
        variant = 'ghost',
        class = 'ui-small',
        ui.icon ('chevrons-down', 14),
        'Show Later',
        onclick = function ()
          commands.run ('logs.later')
          return nil
        end,
      }),
      ui.button ({
        variant = 'ghost',
        class = 'ui-small',
        ui.icon ('arrow-down-to-line', 14),
        'Newest',
        onclick = function ()
          commands.run ('logs.follow_newest')
          return nil
        end,
      }),
    })
    earlier_bar:show (false)
    later_bar:show (false)
    local rows_el = ui.div ({ class = 'logs-rows' })
    local list = ui.div ({
      class = 'logs-list',
      attrs = { tabindex = '0' },
      earlier_bar,
      rows_el,
      later_bar,
    })
    list:class ('logs-wrap', wrap)
    local empty = ui.div ({ class = 'logs-empty' })
    local detail_title = ui.span ({ class = 'logs-detail-title' })
    local detail_text = ui.pre ({ class = 'logs-detail-text' })
    local json_box = ui.div ({ class = 'logs-json' })
    local json_view = nil ---@type Proteus.El?
    local copy_btn = ui.button ({
      variant = 'ghost',
      title = 'Copy the line',
      ui.icon ('copy', 14),
      'Copy',
    })
    local close_btn = ui.button ({
      variant = 'ghost',
      title = 'Close (Escape)',
      ui.icon ('x', 14),
    })
    local detail = ui.div ({
      class = 'logs-detail',
      ui.div ({
        class = 'logs-detail-head',
        detail_title,
        ui.div ({ class = 'ui-grow' }),
        copy_btn,
        close_btn,
      }),
      ui.div ({ class = 'logs-detail-body', detail_text, json_box }),
    })
    detail:show (false)
    local root = ui.div ({
      class = 'logs',
      ui.div ({
        class = 'logs-bar',
        filter_box,
        chips,
        ui.div ({ class = 'ui-grow' }),
        follow_btn,
        wrap_btn,
        clear_btn,
        problem_el,
      }),
      ui.div ({ class = 'logs-body', list, empty }),
      detail,
    })
    -- The selected row has no element of its own, so one CSS rule picks it by line number.
    local selection_css = ui.css ('')

    local src_list = ui.div ({ class = 'logs-sources' })

    ---@param icon string
    ---@param label string
    ---@param command string
    ---@param tip string
    ---@return Proteus.El
    local function side_button (icon, label, command, tip)
      return ui.button ({
        title = tip,
        ui.icon (icon, 14),
        label,
        onclick = function ()
          commands.run (command)
          return nil
        end,
      })
    end

    local side = ui.div ({
      class = 'logs-side',
      ui.div ({
        class = 'logs-side-actions',
        side_button (
          'file-text',
          'File',
          'logs.open_file',
          'Open Log File (Ctrl+O)'
        ),
        side_button (
          'square-terminal',
          'Command',
          'logs.run',
          'Run Command (Ctrl+Shift+R)'
        ),
        side_button ('clipboard-paste', 'Paste', 'logs.paste', 'Paste Log'),
      }),
      src_list,
    })

    local st_state = status
      and status.add ({
        id = 'logs.state',
        text = '',
        align = 'left',
        order = 10,
      })
    local st_lines = status
      and status.add ({
        id = 'logs.lines',
        text = '',
        align = 'right',
        order = 10,
      })

    -- Small screen updates --------------------------------------------------------------------

    local function render_toggles ()
      follow_btn:class ('on', follow)
      wrap_btn:class ('on', wrap)
    end

    local function scroll_bottom ()
      list:set ('scrollTop', 1e9)
    end

    ---@param on boolean
    local function set_follow (on)
      follow = on
      render_toggles ()
      if on then
        scroll_bottom ()
      end
    end

    local function render_chip_counts ()
      for _, level in ipairs (lf.LEVELS) do
        local n = levels[level] or 0
        if chip_values[level] ~= n then
          chip_values[level] = n
          chip_counts[level]:text (lf.group (n))
        end
      end
    end

    local function render_chip_states ()
      for _, level in ipairs (lf.LEVELS) do
        local off = hidden[level] == true
        chip_buttons[level]:class ('off', off)
        chip_buttons[level]:attr (
          'title',
          (off and 'Show ' or 'Hide ') .. LEVEL_PLURALS[level]:lower ()
        )
      end
    end

    ---How many lines the view holds, before the filter.
    ---@return integer
    local function view_total ()
      if merged then
        local n = 0
        for _, src in ipairs (sources) do
          n = n + src.lines:count ()
        end
        return n
      end
      return shown and shown.lines:count () or 0
    end

    local function update_status ()
      if not st_state or not st_lines then
        return
      end
      if merged then
        st_state.set ('All sources, by time')
      elseif not shown then
        st_state.set ('')
        st_lines.set ('')
        return
      elseif shown.state == 'pasted' then
        st_state.set (shown.name)
      else
        st_state.set (
          shown.name .. ': ' .. lf.state_label (shown.state, shown.code)
        )
      end
      local total = view_total ()
      if lf.is_empty (query) and next (hidden) == nil then
        st_lines.set (lf.group (total) .. (total == 1 and ' line' or ' lines'))
      else
        st_lines.set (
          lf.group (matched) .. ' of ' .. lf.group (total) .. ' lines'
        )
      end
    end

    local function update_counts ()
      for _, src in ipairs (sources) do
        local n = src.lines:count ()
        if src.count_el and src.counted ~= n then
          src.counted = n
          src.count_el:text (lf.group (n))
        end
      end
    end

    ---@param label string
    ---@param icon string
    ---@param run fun()
    ---@param variant? 'primary'|'ghost'|'danger'
    ---@return Proteus.El
    local function empty_button (label, icon, run, variant)
      return ui.button ({
        variant = variant,
        ui.icon (icon, 14),
        label,
        onclick = function ()
          run ()
          return nil
        end,
      })
    end

    local function reset_filter ()
      filter_box:value ('')
      query = lf.parse_query ('')
      hidden = {}
      app.store.set ('hidden', {})
      render_chip_states ()
      redraw_list ()
    end

    ---Shows a message in place of the list when there is nothing to list. It is rebuilt only
    ---when what it says changes.
    local function render_empty ()
      local key = nil ---@type string?
      local src = shown
      if merged then
        key = view_total () == 0 and 'blank:merged'
          or (matched == 0 and 'nomatch' or nil)
      elseif not src then
        key = 'none'
      elseif src.lines:count () == 0 then
        key = table.concat ({ 'blank', src.id, src.state, src.code or '' }, ':')
      elseif matched == 0 then
        key = 'nomatch'
      end
      if key == empty_key then
        return
      end
      empty_key = key
      list:show (key == nil)
      empty:show (key ~= nil)
      if not key then
        return
      end
      local title, text = '', ''
      local actions = {} ---@type Proteus.El[]
      if key == 'blank:merged' then
        title = 'No lines yet'
        text = 'The lines of every source show here, in order of time.'
      elseif not src and key ~= 'nomatch' then
        title = 'No logs open'
        if desktop then
          text =
            'Follow a log file, run a command and watch what it prints, or paste a log.'
          actions = {
            empty_button ('Open Log File', 'file-text', function ()
              commands.run ('logs.open_file')
            end, 'primary'),
            empty_button ('Run Command', 'square-terminal', function ()
              commands.run ('logs.run')
            end),
            empty_button ('Paste Log', 'clipboard-paste', function ()
              commands.run ('logs.paste')
            end),
          }
        else
          text = DESKTOP_ONLY .. ' Pasting a log works here too.'
          actions = {
            empty_button ('Paste Log', 'clipboard-paste', function ()
              commands.run ('logs.paste')
            end, 'primary'),
          }
        end
      elseif key == 'nomatch' then
        title = 'No lines match'
        text = 'Change the filter, or show the levels that are hidden.'
        actions =
          { empty_button ('Show All Lines', 'eye', reset_filter, 'primary') }
      elseif src and src.state == 'running' then
        title = 'Waiting for lines'
        text = src.spec.kind == 'file'
            and 'New lines show here as the file grows.'
          or 'Lines show here as the program prints them.'
      elseif src then
        title = 'No lines'
        text = lf.state_label (src.state, src.code)
          .. (src.detail and ('. ' .. src.detail) or '.')
      end
      empty:set_children ({
        ui.div ({ class = 'logs-empty-title', title }),
        ui.div ({ class = 'logs-empty-text', text }),
        ui.div ({ class = 'logs-empty-actions', actions }),
      })
    end

    -- The line list -----------------------------------------------------------------------------

    -- Where the lines still held start in view_all. Lines a source let go are dropped from the
    -- front without moving the rest, and the list is packed now and then.
    local view_first = 1

    local function clear_list ()
      rows_el:clear ()
      chunks = {}
      drawn = 0
      by_id = {}
      where = {}
    end

    ---Shows how many matching lines lie before and after the window.
    local function render_bars ()
      local before = math.max (0, win_from - view_first)
      local after = math.max (0, #view_all - (win_from + drawn - 1))
      earlier_bar:show (before > 0)
      later_bar:show (after > 0)
      earlier_text:text (
        lf.group (before)
          .. (before == 1 and ' earlier line' or ' earlier lines')
      )
      later_text:text (
        lf.group (after) .. (after == 1 and ' later line' or ' later lines')
      )
    end

    ---The tag a row carries in the merged view.
    ---@param line Logs.Line
    ---@return { name: string, n: integer }?
    local function tag_of (line)
      if not merged then
        return nil
      end
      for i, src in ipairs (sources) do
        if src.id == line.src then
          return { name = src.name, n = i }
        end
      end
      return nil
    end

    ---Draws lines at the end of the list, then drops chunks off the top past the cap.
    ---@param lines Logs.Line[]
    local function draw_rows (lines)
      local i = 1 ---@type integer
      while i <= #lines do
        local chunk = chunks[#chunks]
        if not chunk or #chunk.ns >= CHUNK_ROWS then
          chunk = { el = ui.div ({ class = 'logs-chunk' }), ns = {} }
          rows_el:append (chunk.el)
          chunks[#chunks + 1] = chunk
        end
        local last = math.min (#lines, i + CHUNK_ROWS - #chunk.ns - 1) ---@type integer
        local parts = {} ---@type string[]
        for k = i, last do
          local line = lines[k]
          local id = line.id or line.n
          parts[#parts + 1] = lf.row_html (line, query, tag_of (line))
          chunk.ns[#chunk.ns + 1] = id
          by_id[id] = line
          where[id] = chunk
        end
        -- Each batch of rows is an element of its own, which shows only its rows.
        chunk.el:append (
          ui.div ({ class = 'logs-batch', html = table.concat (parts) })
        )
        drawn = drawn + (last - i + 1)
        i = last + 1
      end
      -- While the list is scrolled up, keep what is on screen still as rows go from the top.
      local lost = 0
      while #chunks > 1 and drawn - #chunks[1].ns >= MAX_SHOWN do
        local first = table.remove (chunks, 1)
        drawn = drawn - #first.ns
        win_from = win_from + #first.ns
        for _, id in ipairs (first.ns) do
          by_id[id] = nil
          where[id] = nil
        end
        if not follow then
          lost = lost + (tonumber (first.el:get ('offsetHeight')) or 0)
        end
        first.el:remove ()
      end
      if lost > 0 then
        local top = tonumber (list:get ('scrollTop')) or 0
        list:set ('scrollTop', math.max (0, top - lost))
      end
      render_bars ()
    end

    ---Draws the window of matching lines that starts at `from`.
    ---@param from integer
    local function show_window (from)
      clear_list ()
      win_from =
        math.max (view_first, math.min (from, #view_all - MAX_SHOWN + 1))
      local lines = {} ---@type Logs.Line[]
      for k = win_from, math.min (#view_all, win_from + MAX_SHOWN - 1) do
        lines[#lines + 1] = view_all[k]
      end
      draw_rows (lines)
    end

    ---Where a line's row is: the chunk, and the row inside it.
    ---@param id integer
    ---@return integer? chunk
    ---@return integer? row
    local function locate (id)
      local chunk = where[id]
      if not chunk then
        return nil, nil
      end
      for ci, c in ipairs (chunks) do
        if c == chunk then
          for ri, other in ipairs (c.ns) do
            if other == id then
              return ci, ri
            end
          end
        end
      end
      return nil, nil
    end

    ---Scrolls the list so a line's row shows. Rows have no elements of their own, so the
    ---row's place is worked out from its chunk. With wrapped lines of different heights,
    ---this is close rather than exact.
    ---@param id integer
    local function reveal (id)
      local ci, ri = locate (id)
      if not ci or not ri then
        return
      end
      local chunk = chunks[ci]
      local chunk_top = tonumber (chunk.el:get ('offsetTop')) or 0
      local chunk_height = tonumber (chunk.el:get ('offsetHeight')) or 0
      local row_height = chunk_height / #chunk.ns
      local top = chunk_top + (ri - 1) * row_height
      local bottom = top + row_height
      local scroll = tonumber (list:get ('scrollTop')) or 0
      local view = tonumber (list:get ('clientHeight')) or 0
      if top < scroll then
        list:set ('scrollTop', top)
      elseif bottom > scroll + view then
        list:set ('scrollTop', bottom - view)
      end
    end

    ---The sources the view shows.
    ---@return Logs.Source[]
    local function view_sources ()
      if merged then
        return sources
      end
      return shown and { shown } or {}
    end

    ---@param line Logs.Line
    ---@return integer
    local function id_of (line)
      return line.id or line.n
    end

    redraw_list = function ()
      pending = {}
      matched = 0
      levels = lf.zero_levels ()
      problem_el:text (query.problem or '')
      problem_el:show (query.problem ~= nil)
      filter_box:class ('bad', query.problem ~= nil)
      view_newest = nil
      for _, src in ipairs (view_sources ()) do
        local t = lf.newest (src.lines)
        if t and (not view_newest or t > view_newest) then
          view_newest = t
        end
      end
      local lists = {} ---@type Logs.Line[][]
      for _, src in ipairs (view_sources ()) do
        local result = lf.scan (src.lines, query, hidden, 0, view_newest)
        lists[#lists + 1] = result.all
        for level, n in pairs (result.levels) do
          levels[level] = levels[level] + n
        end
      end
      view_all = #lists == 1 and lists[1] or lf.merge (lists)
      view_first = 1
      matched = #view_all
      -- Following shows the newest lines. Otherwise the window keeps the selected line.
      local from = #view_all - MAX_SHOWN + 1
      if not follow and selected then
        local want = id_of (selected)
        for k, line in ipairs (view_all) do
          if id_of (line) == want then
            from = k - math.floor (MAX_SHOWN / 2)
            break
          end
        end
      end
      show_window (from)
      render_chip_counts ()
      render_empty ()
      update_status ()
      if follow then
        scroll_bottom ()
      elseif selected then
        reveal (id_of (selected))
      end
    end

    ---Moves the window by `step` lines, earlier when it is below 0.
    ---@param step integer
    local function page (step)
      if follow then
        follow = false
        render_toggles ()
      end
      local top_id = chunks[1] and chunks[1].ns[1]
      show_window (win_from + step)
      if step < 0 and top_id then
        -- The line that was at the top stays in sight, below the new ones.
        reveal (top_id)
      elseif step > 0 then
        list:set ('scrollTop', 0)
      end
    end

    ---A line the source let go. The single view drops it from the front of its lines.
    ---@param line Logs.Line
    local function forget_line (line)
      if merged then
        return
      end
      if view_all[view_first] == line then
        view_first = view_first + 1
        matched = matched - 1
      end
      -- Pack the list now and then, so the lines let go do not pile up.
      if view_first > 20000 then
        local shift = view_first - 1
        local packed = {} ---@type Logs.Line[]
        for k = view_first, #view_all do
          packed[#packed + 1] = view_all[k]
        end
        view_all = packed
        view_first = 1
        win_from = win_from - shift
      end
    end

    flush = function ()
      flush_cancel = nil
      local batch = pending
      pending = {}
      if (shown or merged) and #batch > 0 then
        -- New lines show when the window has reached the end. Otherwise only the count of
        -- later lines grows.
        local at_end = win_from + drawn - 1 >= #view_all
        local fresh = {} ---@type Logs.Line[]
        for _, line in ipairs (batch) do
          local counted, visible =
            lf.classify (line, query, hidden, view_newest)
          if counted then
            levels[line.level] = levels[line.level] + 1
          end
          if visible then
            view_all[#view_all + 1] = line
            matched = matched + 1
            fresh[#fresh + 1] = line
          end
        end
        if at_end and #fresh > MAX_SHOWN then
          -- More new rows than the list holds, so the list starts again with the newest.
          show_window (#view_all - MAX_SHOWN + 1)
        elseif at_end and #fresh > 0 then
          draw_rows (fresh)
        else
          render_bars ()
        end
        render_chip_counts ()
        render_empty ()
        if follow and #fresh > 0 then
          scroll_bottom ()
        end
      end
      update_counts ()
      update_status ()
    end

    local function schedule ()
      if not flush_cancel then
        flush_cancel = app.timer.after (FLUSH_MS, flush)
      end
    end

    -- The detail panel ------------------------------------------------------------------------

    local function close_detail ()
      selected = nil
      selection_css:set ('')
      detail:show (false)
    end

    ---@param line Logs.Line
    local function open_detail (line)
      selected = line
      selection_css:set (
        '.logs-list .logs-row[data-item="'
          .. id_of (line)
          .. '"] { background: var(--selection); }'
      )
      local from = nil ---@type string?
      if merged then
        local tag = tag_of (line)
        from = tag and tag.name or nil
      end
      detail_title:text (
        (from and (from .. '  ·  ') or '')
          .. 'Line '
          .. line.n
          .. '  ·  '
          .. LEVEL_NAMES[line.level]
          .. (line.err and '  ·  stderr' or '')
          .. (
            line.time
              and ('  ·  ' .. os.date (
                '!%Y-%m-%d %H:%M:%S',
                math.floor (line.time / 1000)
              ) .. (line.stamped and '' or ' (from the line above)'))
            or ''
          )
      )
      detail_text:text (line.plain)
      local pretty = nil ---@type string?
      local json = lf.find_json (line.plain)
      if json then
        pretty = lf.pretty_json (json)
      end
      detail:class ('logs-has-json', pretty ~= nil)
      json_box:show (pretty ~= nil)
      detail:show (true)
      -- The editor measures itself when it is made, so it is made once the panel shows.
      if pretty then
        if json_view then
          json_view:widget ('set_text', pretty)
        else
          json_view = ui.widget ('code', {
            text = pretty,
            language = 'json',
            readonly = true,
            wrap = true,
          })
          json_box:append (json_view)
        end
      end
    end

    ---@param id integer
    local function select_line (id)
      local line = by_id[id]
      if not line then
        return
      end
      if follow then
        set_follow (false)
      end
      open_detail (line)
      reveal (id)
    end

    ---@param step integer 1 moves down and -1 moves up.
    local function move_selection (step)
      if #chunks == 0 then
        return
      end
      local target = nil ---@type integer?
      local ci, ri = nil, nil ---@type integer?, integer?
      if selected then
        ci, ri = locate (id_of (selected))
      end
      if ci and ri then
        local ns = chunks[ci].ns
        local next_chunk, prev_chunk = chunks[ci + 1], chunks[ci - 1]
        if ns[ri + step] then
          target = ns[ri + step]
        elseif step > 0 and next_chunk then
          target = next_chunk.ns[1]
        elseif step < 0 and prev_chunk then
          target = prev_chunk.ns[#prev_chunk.ns]
        end
      elseif step > 0 then
        target = chunks[1].ns[1]
      else
        local last = chunks[#chunks].ns
        target = last[#last]
      end
      if target then
        select_line (target)
      end
    end

    -- Sources ---------------------------------------------------------------------------------

    ---@param id number?
    ---@return Logs.Source?
    local function find_source (id)
      for _, src in ipairs (sources) do
        if src.id == id then
          return src
        end
      end
      return nil
    end

    local function save_open ()
      local open = {} ---@type Logs.SourceSpec[]
      for _, src in ipairs (sources) do
        if src.spec.kind ~= 'paste' then
          open[#open + 1] = src.spec
        end
      end
      app.store.set ('open', open)
    end

    ---@param src Logs.Source
    ---@return string
    local function dot_kind (src)
      if src.state == 'exited' then
        return src.code == 0 and 'done' or 'exit'
      end
      return src.state
    end

    render_sources = function ()
      local rows = {} ---@type Proteus.El[]
      if #sources >= 2 then
        rows[1] = ui.div ({
          class = 'logs-src merged' .. (merged and ' active' or ''),
          title = 'Every source in one list, in order of time',
          attrs = { ['data-item'] = 'merged' },
          ui.span ({ class = 'logs-src-icon', html = icon_svg ('git-merge') }),
          ui.span ({ class = 'logs-src-name', 'All sources, by time' }),
        })
      end
      for _, src in ipairs (sources) do
        local label = lf.state_label (src.state, src.code)
        local count = ui.span ({
          class = 'logs-src-count',
          lf.group (src.lines:count ()),
        })
        src.count_el = count
        src.counted = src.lines:count ()
        rows[#rows + 1] = ui.div ({
          class = 'logs-src'
            .. ((src == shown and not merged) and ' active' or ''),
          title = lf.source_title (src.spec)
            .. '\n'
            .. label
            .. (src.detail and (': ' .. src.detail) or ''),
          attrs = { ['data-item'] = tostring (src.id) },
          ui.span ({
            class = 'logs-src-icon',
            html = icon_svg (KIND_ICONS[src.spec.kind] or 'file-text'),
          }),
          ui.span ({ class = 'logs-src-name', src.name }),
          ui.span ({
            class = 'logs-dot logs-dot-' .. dot_kind (src),
            title = label,
          }),
          count,
          ui.h ('button', {
            class = 'logs-src-close',
            title = 'Stop and close',
            attrs = { ['data-item'] = 'close:' .. src.id },
            html = icon_svg ('x'),
          }),
        })
      end
      if #rows == 0 then
        rows[1] = ui.div ({ class = 'logs-src-none', 'Nothing open yet' })
      end
      src_list:set_children (rows)
    end

    ---@param src Logs.Source
    local function source_changed (src)
      render_sources ()
      if src == shown or merged then
        render_empty ()
        update_status ()
      end
    end

    ---@param src Logs.Source
    ---@param text string
    ---@param err boolean
    local function add_line (src, text, err)
      local line = lf.make_line (src.next_n, text, err, src.last_time)
      line.src = src.id
      line.id = next_line_id
      next_line_id = next_line_id + 1
      src.last_time = line.time
      src.next_n = src.next_n + 1
      local dropped = src.lines:push (line)
      if src == shown or merged then
        pending[#pending + 1] = line
        if dropped then
          local counted = lf.classify (dropped, query, hidden, view_newest)
          if counted then
            levels[dropped.level] = levels[dropped.level] - 1
          end
          forget_line (dropped)
        end
      end
      schedule ()
    end

    ---@param spec Logs.SourceSpec
    ---@return Logs.Source
    local function new_source (spec)
      ---@type Logs.Source
      local src = {
        id = next_id,
        spec = spec,
        name = lf.source_name (spec),
        lines = lf.ring (spec.whole and MAX_WHOLE or MAX_LINES),
        next_n = 1,
        state = 'stopped',
        run = 0,
        counted = 0,
      }
      next_id = next_id + 1
      sources[#sources + 1] = src
      return src
    end

    ---@param src Logs.Source
    local function start (src)
      src.run = src.run + 1
      local run = src.run
      src.code, src.detail = nil, nil
      if not desktop then
        src.state = 'failed'
        src.detail = DESKTOP_ONLY
        source_changed (src)
        return
      end
      local spec = src.spec
      local program, args ---@type string, string[]
      if spec.kind == 'file' then
        program, args = lf.follow_command (spec.path or '', app.os, spec.whole)
      else
        program, args = lf.shell_command (spec.command or '', app.os)
      end
      src.state = 'running'
      ---@type Proteus.SpawnOptions
      local opts = {
        cwd = spec.cwd,
        framing = 'lines',
        on_message = function (text)
          if src.run == run then
            add_line (src, tostring (text), false)
          end
        end,
        on_stderr = function (text)
          if src.run == run then
            add_line (src, tostring (text), true)
          end
        end,
        on_exit = function (code)
          if src.run == run then
            src.proc = nil
            src.state = 'exited'
            src.code = code
            source_changed (src)
          end
        end,
        on_error = function (err)
          if src.run == run then
            local why = lf.sentence (tostring (err))
            src.proc = nil
            src.state = 'failed'
            src.detail = why
            source_changed (src)
            say_error ('"' .. src.name .. '" did not start. ' .. why)
          end
        end,
      }
      local ok, result = pcall (app.process.spawn, program, args, opts)
      if ok then
        src.proc = result --[[@as Proteus.ProcessHandle]]
      else
        local why = lf.sentence (tostring (result))
        src.state = 'failed'
        src.detail = why
        say_error ('"' .. src.name .. '" did not start. ' .. why)
      end
      source_changed (src)
    end

    ---Stops a source's program. Output still on its way is ignored.
    ---@param src Logs.Source
    local function halt (src)
      src.run = src.run + 1
      local proc = src.proc
      src.proc = nil
      if proc then
        pcall (proc.kill)
      end
      if src.state == 'running' then
        src.state = 'stopped'
      end
    end

    ---@param src Logs.Source
    local function stop (src)
      halt (src)
      source_changed (src)
    end

    ---Starts a source again from an empty list. A file sends its last thousand lines again
    ---when it restarts, so keeping the old lines would show them twice.
    ---@param src Logs.Source
    local function restart (src)
      halt (src)
      src.lines:clear ()
      src.last_time = nil
      if src == shown or merged then
        close_detail ()
        redraw_list ()
      end
      start (src)
    end

    show_source = function (src)
      if shown ~= src or merged then
        close_detail ()
        shown = src
        merged = false
        follow = true
        render_toggles ()
        app.store.set ('shown', src and lf.spec_key (src.spec) or nil)
      end
      redraw_list ()
      render_sources ()
    end

    ---Shows every source in one list, in order of time.
    local function show_merged ()
      if #sources < 2 then
        say ('The merged view needs two sources or more.')
        return
      end
      if not merged then
        close_detail ()
        shown = nil
        merged = true
        follow = true
        render_toggles ()
        app.store.set ('shown', 'merged')
      end
      redraw_list ()
      render_sources ()
    end

    ---@param src Logs.Source
    local function remove_source (src)
      halt (src)
      local index = 1
      for i, other in ipairs (sources) do
        if other == src then
          index = i
          table.remove (sources, i)
          break
        end
      end
      save_open ()
      if merged and #sources < 2 then
        show_source (sources[1])
      elseif merged then
        redraw_list ()
        render_sources ()
      elseif shown == src then
        show_source (sources[index] or sources[index - 1])
      else
        render_sources ()
      end
    end

    ---@param src Logs.Source
    local function close_source (src)
      if src.state == 'running' and src.spec.kind == 'command' and picker then
        picker.confirm ({
          message = 'Stop "' .. src.name .. '" and close it?',
          yes = 'Stop and Close',
          on_yes = function ()
            remove_source (src)
          end,
        })
        return
      end
      remove_source (src)
    end

    ---Opens a file or a command, or brings it to the front when it is open already.
    ---@param spec Logs.SourceSpec
    local function open_spec (spec)
      if not desktop then
        say (DESKTOP_ONLY)
        return
      end
      recent = lf.remember (recent, spec, MAX_RECENT)
      app.store.set ('recent', recent)
      local key = lf.spec_key (spec)
      for _, src in ipairs (sources) do
        if lf.spec_key (src.spec) == key then
          show_source (src)
          if src.state ~= 'running' then
            restart (src)
          end
          return
        end
      end
      local src = new_source (spec)
      save_open ()
      show_source (src)
      start (src)
    end

    -- Actions ---------------------------------------------------------------------------------

    ---Asks for log files and follows them. A whole file is read from its first line, and
    ---keeps up to 250,000 lines.
    ---@param whole boolean
    local function open_file (whole)
      if not desktop then
        say (DESKTOP_ONLY)
        return
      end
      app.fs.pick_open ({
        title = whole and 'Open Whole Log File' or 'Open Log File',
        multiple = true,
      }, function (paths, err)
        if err then
          say_error ('Could not show the file picker. ' .. err)
          return
        end
        for _, path in ipairs (paths or {}) do
          open_spec ({ kind = 'file', path = path, whole = whole or nil })
        end
      end)
    end

    local function run_command ()
      if not desktop then
        say (DESKTOP_ONLY)
        return
      end
      local p = picker
      if not p then
        say_error ('Running a command needs the palette plugin.')
        return
      end
      p.input ({
        prompt = 'Command to run',
        placeholder = app.os == 'windows' and 'Such as: ping -t localhost'
          or 'Such as: tail -f /var/log/syslog',
        value = tostring (app.store.get ('last_command', '')),
        validate = function (text)
          if not text:match ('%S') then
            return 'Type a command to run.'
          end
          return nil
        end,
        on_submit = function (text)
          local command = lf.trim (text)
          app.store.set ('last_command', command)
          p.input ({
            prompt = 'Folder to run it in',
            placeholder = 'A full path. Leave it empty for the default folder.',
            value = tostring (app.store.get ('last_cwd', '')),
            on_submit = function (folder)
              local cwd = lf.trim (folder)
              app.store.set ('last_cwd', cwd)
              open_spec ({
                kind = 'command',
                command = command,
                cwd = cwd ~= '' and cwd or nil,
              })
            end,
          })
        end,
      })
    end

    local function paste_log ()
      app.system.clipboard_read (function (text, err)
        if err then
          say_error ('Could not read the clipboard. ' .. err)
          return
        end
        local body = text or ''
        if not body:match ('%S') then
          say ('The clipboard holds no text.')
          return
        end
        local src = new_source ({
          kind = 'paste',
          name = 'Pasted at ' .. tostring (os.date ('%H:%M')),
        })
        src.state = 'pasted'
        for _, raw in ipairs (lf.split_lines (body)) do
          local line = lf.make_line (src.next_n, raw, false, src.last_time)
          line.src = src.id
          line.id = next_line_id
          next_line_id = next_line_id + 1
          src.last_time = line.time
          src.lines:push (line)
          src.next_n = src.next_n + 1
        end
        show_source (src)
      end)
    end

    local function open_recent ()
      local p = picker
      if not p then
        return
      end
      local items = {} ---@type Proteus.PickItem[]
      for _, spec in ipairs (recent) do
        items[#items + 1] = {
          label = lf.source_name (spec)
            .. (spec.whole and ' (whole file)' or ''),
          detail = spec.kind == 'file' and spec.path or spec.cwd,
          icon = KIND_ICONS[spec.kind],
          value = spec,
        }
      end
      p.pick ({
        items = items,
        placeholder = 'Open a recent file or command',
        empty = 'Nothing opened yet',
        on_pick = function (item)
          open_spec (item.value)
        end,
      })
    end

    local function clear_lines ()
      if not shown and not merged then
        return
      end
      -- The merged view clears every source.
      for _, src in ipairs (view_sources ()) do
        src.lines:clear ()
      end
      close_detail ()
      redraw_list ()
      update_counts ()
    end

    local function copy_matching ()
      if not shown and not merged then
        return
      end
      local texts = {} ---@type string[]
      for k = view_first, #view_all do
        texts[#texts + 1] = view_all[k].plain
      end
      app.system.clipboard (table.concat (texts, '\n'))
      say (
        'Copied '
          .. lf.group (#texts)
          .. (#texts == 1 and ' line.' or ' lines.')
      )
    end

    local function copy_selected ()
      if selected then
        app.system.clipboard (selected.plain)
        say ('Copied the line.')
      end
    end

    ---@param level string
    local function toggle_level (level)
      if hidden[level] then
        hidden[level] = nil
      else
        hidden[level] = true
      end
      local saved = {} ---@type string[]
      for _, name in ipairs (lf.LEVELS) do
        if hidden[name] then
          saved[#saved + 1] = name
        end
      end
      app.store.set ('hidden', saved)
      render_chip_states ()
      redraw_list ()
    end

    local function toggle_wrap ()
      wrap = not wrap
      app.store.set ('wrap', wrap)
      list:class ('logs-wrap', wrap)
      render_toggles ()
      if follow then
        scroll_bottom ()
      elseif selected then
        reveal (selected.n)
      end
    end

    local function focus_filter ()
      if my_tab then
        my_tab.focus ()
      end
      filter_box:focus ()
      filter_box:select ()
    end

    -- Events ----------------------------------------------------------------------------------

    filter_box:on ('input', function (ev)
      local text = ev.value or ''
      if filter_cancel then
        filter_cancel ()
      end
      filter_cancel = app.timer.after (FILTER_MS, function ()
        filter_cancel = nil
        query = lf.parse_query (text)
        redraw_list ()
      end)
      return nil
    end)

    filter_box:on ('keydown', function (ev)
      if ev.key == 'Escape' then
        if filter_box:value () ~= '' then
          if filter_cancel then
            filter_cancel ()
            filter_cancel = nil
          end
          filter_box:value ('')
          query = lf.parse_query ('')
          redraw_list ()
        else
          list:focus ()
        end
        return true
      end
      if ev.key == 'Enter' or ev.key == 'ArrowDown' then
        list:focus ()
        return true
      end
      return nil
    end)

    chips:on ('click', function (ev)
      local level = ev.item
      if level and LEVEL_NAMES[level] then
        toggle_level (level)
      end
      return nil
    end)

    follow_btn:on ('click', function ()
      set_follow (not follow)
      return nil
    end)
    wrap_btn:on ('click', function ()
      toggle_wrap ()
      return nil
    end)
    clear_btn:on ('click', function ()
      clear_lines ()
      return nil
    end)
    copy_btn:on ('click', function ()
      copy_selected ()
      return nil
    end)
    close_btn:on ('click', function ()
      close_detail ()
      list:focus ()
      return nil
    end)

    list:on ('click', function (ev)
      local n = tonumber (ev.item or '')
      if n then
        select_line (math.floor (n))
      end
      return nil
    end)

    list:on ('keydown', function (ev)
      if ev.key == 'ArrowDown' then
        move_selection (1)
        return true
      end
      if ev.key == 'ArrowUp' then
        move_selection (-1)
        return true
      end
      if ev.key == 'Escape' and selected then
        close_detail ()
        return true
      end
      return nil
    end)

    -- Scrolling up stops following, and scrolling back to the bottom starts it again.
    list:on ('scroll', function ()
      local top = tonumber (list:get ('scrollTop')) or 0
      local height = tonumber (list:get ('scrollHeight')) or 0
      local view = tonumber (list:get ('clientHeight')) or 0
      local at_bottom = top + view >= height - 8
      if at_bottom ~= follow then
        follow = at_bottom
        render_toggles ()
      end
      return nil
    end)

    src_list:on ('click', function (ev)
      local item = ev.item
      if not item then
        return nil
      end
      if item == 'merged' then
        show_merged ()
        return nil
      end
      local close_id = item:match ('^close:(%d+)$')
      local src = find_source (tonumber (close_id or item))
      if src and close_id then
        close_source (src)
      elseif src then
        show_source (src)
      end
      return nil
    end)

    -- Right-click menus -------------------------------------------------------------------------

    if menus then
      menus.attach (list, function (ev)
        local items = {} ---@type Proteus.MenuItem[]
        local picked = nil ---@type Logs.Line?
        local n = tonumber (ev.item or '')
        if n then
          picked = by_id[math.floor (n)]
        end
        local selection = ev.selection or ''
        if selection ~= '' then
          items[#items + 1] = {
            label = 'Copy',
            icon = 'copy',
            key = 'Ctrl+C',
            run = function ()
              app.system.clipboard (selection)
            end,
          }
        end
        if picked then
          local line = picked
          items[#items + 1] = {
            label = 'Copy Line',
            icon = 'copy',
            run = function ()
              app.system.clipboard (line.plain)
            end,
          }
          items[#items + 1] = {
            label = 'Show Details',
            icon = 'panel-bottom',
            run = function ()
              select_line (id_of (line))
            end,
          }
          items[#items + 1] = {
            label = 'Hide ' .. LEVEL_PLURALS[line.level],
            icon = 'eye-off',
            run = function ()
              toggle_level (line.level)
            end,
          }
          items[#items + 1] = { separator = true }
        end
        items[#items + 1] = {
          label = 'Copy Matching Lines',
          icon = 'clipboard-list',
          disabled = matched == 0,
          run = copy_matching,
        }
        items[#items + 1] = {
          label = 'Clear',
          icon = 'eraser',
          key = 'Ctrl+K',
          disabled = shown == nil and not merged,
          run = clear_lines,
        }
        return items
      end)

      menus.attach (src_list, function (ev)
        local id = tonumber ((ev.item or ''):match ('(%d+)$') or '')
        local src = find_source (id)
        if not src then
          return {
            {
              label = 'Open Log File',
              icon = 'file-text',
              run = function ()
                open_file (false)
              end,
            },
            {
              label = 'Open Whole Log File',
              icon = 'file-search',
              run = function ()
                open_file (true)
              end,
            },
            {
              label = 'All Sources, by Time',
              icon = 'git-merge',
              disabled = #sources < 2,
              run = show_merged,
            },
            {
              label = 'Run Command',
              icon = 'square-terminal',
              run = run_command,
            },
            {
              label = 'Paste Log',
              icon = 'clipboard-paste',
              run = paste_log,
            },
          }
        end
        local s = src
        local items = {} ---@type Proteus.MenuItem[]
        items[#items + 1] = {
          label = 'Show',
          icon = 'eye',
          run = function ()
            show_source (s)
          end,
        }
        if s.state == 'running' then
          items[#items + 1] = {
            label = 'Stop',
            icon = 'square',
            run = function ()
              stop (s)
            end,
          }
        end
        if s.spec.kind ~= 'paste' then
          items[#items + 1] = {
            label = 'Restart',
            icon = 'rotate-cw',
            run = function ()
              restart (s)
            end,
          }
        end
        local path, command = s.spec.path, s.spec.command
        if path then
          items[#items + 1] = {
            label = 'Copy Path',
            icon = 'copy',
            run = function ()
              app.system.clipboard (path)
            end,
          }
        end
        if command then
          items[#items + 1] = {
            label = 'Copy Command',
            icon = 'copy',
            run = function ()
              app.system.clipboard (command)
            end,
          }
        end
        items[#items + 1] = { separator = true }
        items[#items + 1] = {
          label = 'Close',
          icon = 'x',
          danger = true,
          run = function ()
            close_source (s)
          end,
        }
        return items
      end)
    end

    -- Commands --------------------------------------------------------------------------------

    ---@return boolean
    local function has_source ()
      return here () and (shown ~= nil or merged)
    end

    ---@return boolean
    local function is_running ()
      local src = shown
      return here () and src ~= nil and src.state == 'running'
    end

    ---@return boolean
    local function can_restart ()
      local src = shown
      return here () and src ~= nil and src.spec.kind ~= 'paste'
    end

    commands.register ({
      id = 'logs.open_file',
      category = 'Logs',
      title = 'Open Log File',
      key = 'ctrl+o',
      icon = 'file-text',
      toolbar = 1,
      when = here,
      run = function ()
        open_file (false)
      end,
    })
    commands.register ({
      id = 'logs.open_whole',
      category = 'Logs',
      title = 'Open Whole Log File',
      key = 'ctrl+shift+o',
      icon = 'file-search',
      when = here,
      run = function ()
        open_file (true)
      end,
    })
    commands.register ({
      id = 'logs.merged',
      category = 'Logs',
      title = 'Show All Sources by Time',
      icon = 'git-merge',
      when = function ()
        return here () and #sources >= 2
      end,
      run = show_merged,
    })
    commands.register ({
      id = 'logs.earlier',
      category = 'Logs',
      title = 'Show Earlier Lines',
      key = 'ctrl+pageup',
      icon = 'chevrons-up',
      when = function ()
        return has_source () and win_from > view_first
      end,
      run = function ()
        page (-PAGE_STEP)
      end,
    })
    commands.register ({
      id = 'logs.later',
      category = 'Logs',
      title = 'Show Later Lines',
      key = 'ctrl+pagedown',
      icon = 'chevrons-down',
      when = function ()
        return has_source () and win_from + drawn - 1 < #view_all
      end,
      run = function ()
        page (PAGE_STEP)
      end,
    })
    commands.register ({
      id = 'logs.follow_newest',
      category = 'Logs',
      title = 'Go to the Newest Line',
      key = 'ctrl+end',
      icon = 'arrow-down-to-line',
      when = has_source,
      run = function ()
        show_window (#view_all - MAX_SHOWN + 1)
        set_follow (true)
      end,
    })
    commands.register ({
      id = 'logs.run',
      category = 'Logs',
      title = 'Run Command',
      key = 'ctrl+shift+r',
      icon = 'square-terminal',
      toolbar = 2,
      when = here,
      run = run_command,
    })
    commands.register ({
      id = 'logs.paste',
      category = 'Logs',
      title = 'Paste Log',
      icon = 'clipboard-paste',
      toolbar = 3,
      when = here,
      run = paste_log,
    })
    commands.register ({
      id = 'logs.recent',
      category = 'Logs',
      title = 'Open Recent',
      icon = 'history',
      toolbar = 4,
      when = function ()
        return here () and #recent > 0
      end,
      run = open_recent,
    })
    commands.register ({
      id = 'logs.stop',
      category = 'Logs',
      title = 'Stop',
      icon = 'square',
      toolbar = 5,
      when = is_running,
      run = function ()
        if shown then
          stop (shown)
        end
      end,
    })
    commands.register ({
      id = 'logs.restart',
      category = 'Logs',
      title = 'Restart',
      icon = 'rotate-cw',
      toolbar = 6,
      when = can_restart,
      run = function ()
        if shown and shown.spec.kind ~= 'paste' then
          restart (shown)
        end
      end,
    })
    commands.register ({
      id = 'logs.close',
      category = 'Logs',
      title = 'Close Source',
      icon = 'x',
      when = has_source,
      run = function ()
        if shown then
          close_source (shown)
        end
      end,
    })
    commands.register ({
      id = 'logs.filter',
      category = 'Logs',
      title = 'Filter Lines',
      key = 'ctrl+f',
      icon = 'search',
      when = here,
      run = focus_filter,
    })
    commands.register ({
      id = 'logs.clear',
      category = 'Logs',
      title = 'Clear Lines',
      key = 'ctrl+k',
      icon = 'eraser',
      when = has_source,
      run = clear_lines,
    })
    commands.register ({
      id = 'logs.wrap',
      category = 'Logs',
      title = 'Toggle Wrap',
      key = 'alt+z',
      icon = 'text-wrap',
      when = here,
      run = toggle_wrap,
    })
    commands.register ({
      id = 'logs.follow',
      category = 'Logs',
      title = 'Toggle Follow',
      icon = 'arrow-down-to-line',
      when = here,
      run = function ()
        set_follow (not follow)
      end,
    })
    commands.register ({
      id = 'logs.copy_line',
      category = 'Logs',
      title = 'Copy Selected Line',
      icon = 'copy',
      when = function ()
        return here () and selected ~= nil
      end,
      run = copy_selected,
    })
    commands.register ({
      id = 'logs.copy_matching',
      category = 'Logs',
      title = 'Copy Matching Lines',
      icon = 'clipboard-list',
      when = has_source,
      run = copy_matching,
    })
    commands.register ({
      id = 'logs.show_all',
      category = 'Logs',
      title = 'Show All Lines',
      icon = 'eye',
      when = here,
      run = reset_filter,
    })
    commands.register ({
      id = 'logs.theme',
      category = 'Logs',
      title = 'Change Theme',
      icon = 'palette',
      toolbar = 90,
      toolbar_align = 'right',
      run = function ()
        commands.run ('theme.choose')
      end,
    })
    commands.register ({
      id = 'logs.switch_app',
      category = 'Logs',
      title = 'Switch App',
      icon = 'layers',
      toolbar = 91,
      toolbar_align = 'right',
      run = function ()
        commands.run ('profile.switch')
      end,
    })

    -- Start -----------------------------------------------------------------------------------

    if tabs then
      my_tab = tabs.open ({
        id = 'proteus.logs',
        title = 'Logs',
        icon = 'scroll-text',
        content = root,
        closable = false,
      })
    else
      shell.mount ('main', root)
    end
    views.add ('left', {
      id = 'logs.sources',
      title = 'Sources',
      icon = 'scroll-text',
      order = 1,
      content = side,
    })

    render_toggles ()
    render_chip_states ()

    -- Sources that were open at the last close open again.
    local last_shown = app.store.get ('shown')
    if desktop then
      for _, spec in ipairs (lf.clean_specs (app.store.get ('open', {}))) do
        start (new_source (spec))
      end
    end
    local first = sources[1]
    for _, src in ipairs (sources) do
      if lf.spec_key (src.spec) == last_shown then
        first = src
      end
    end
    if last_shown == 'merged' and #sources >= 2 then
      show_merged ()
    else
      show_source (first)
    end
  end,
}
