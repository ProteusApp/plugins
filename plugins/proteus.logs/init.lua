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
--
-- This file puts the screen together and wires its events. The rest lives in modules that
-- share one context, Logs.Ctx: logs_list draws the list of lines, logs_detail shows the line
-- picked in it, and logs_sources opens, runs and shows the sources the lines come from.

local CSS = require ('logs_css') --[[@as string]]
local detail_m = require ('logs_detail') --[[@as Logs.DetailModule]]
local lf = require ('log_filter') --[[@as Logs.FilterModule]]
local list_m = require ('logs_list') --[[@as Logs.ListModule]]
local sources_m = require ('logs_sources') --[[@as Logs.SourcesViewModule]]

local PAGE_STEP = 2500 -- how far the window moves
local FILTER_MS = 150

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

---What the log viewer's modules share. init.lua fills in the state, the screen parts and its
---own helpers, and each module adds the functions it offers the others.
---@class Logs.Ctx
---@field app Proteus.App
---@field ui Proteus.UI
---@field commands Proteus.Commands
---@field picker? Proteus.Picker
---@field desktop boolean False in the browser, which cannot follow files or run commands.
---@field sources Logs.Source[]
---@field shown? Logs.Source The source the list shows, or nil.
---@field merged boolean True while the list shows every source, merged by time. Then `shown` is nil.
---@field view_all Logs.Line[] Every line of the view that passes the filter and the chips.
---@field win_from integer Where the window of drawn lines starts in view_all.
---@field view_first integer Where the lines still held start in view_all. Lines a source let go are dropped from the front without moving the rest, and the list is packed now and then.
---@field by_id table<integer, Logs.Line> The drawn lines by id.
---@field view_newest? number The time of the view's newest line, for a filter such as after:-15m.
---@field query Logs.Query
---@field hidden table<string, boolean> The levels the chips hide.
---@field follow boolean True while the list stays at the bottom as lines arrive.
---@field selected? Logs.Line The line the detail panel shows.
---@field pending Logs.Line[] Lines that arrived and are not drawn yet.
---@field chunks Logs.Chunk[]
---@field drawn integer Rows in the chunks.
---@field matched integer Lines that pass the filter and the chips.
---@field levels table<Logs.Level, integer> Lines of each level that pass the filter.
---@field recent Logs.SourceSpec[]
---@field filter_box Proteus.El
---@field problem_el Proteus.El
---@field list Proteus.El
---@field rows_el Proteus.El
---@field earlier_bar Proteus.El
---@field earlier_text Proteus.El
---@field later_bar Proteus.El
---@field later_text Proteus.El
---@field detail Proteus.El
---@field detail_title Proteus.El
---@field detail_text Proteus.El
---@field json_box Proteus.El
---@field selection_css Proteus.El The rule that marks the picked row.
---@field level_names table<string, string> Each level's name, such as Warn.
---@field src_list Proteus.El The list in the Sources view.
---@field say fun(text: string)
---@field say_error fun(text: string)
---@field render_toggles fun()
---@field scroll_bottom fun()
---@field render_chip_counts fun()
---@field render_empty fun()
---@field update_status fun()
---@field update_counts fun()
---@field set_follow fun(on: boolean)
---@field redraw_list fun() From logs_list.
---@field show_window fun(from: integer)
---@field page fun(step: integer)
---@field reveal fun(id: integer)
---@field locate fun(id: integer): integer?, integer?
---@field view_sources fun(): Logs.Source[]
---@field id_of fun(line: Logs.Line): integer
---@field tag_of fun(line: Logs.Line): { name: string, n: integer }?
---@field forget_line fun(line: Logs.Line)
---@field schedule fun()
---@field close_detail fun() From logs_detail.
---@field open_detail fun(line: Logs.Line)
---@field select_line fun(id: integer)
---@field move_selection fun(step: integer)
---@field find_source fun(id: number?): Logs.Source? From logs_sources.
---@field render_sources fun()
---@field show_source fun(src: Logs.Source?)
---@field show_merged fun()
---@field new_source fun(spec: Logs.SourceSpec): Logs.Source
---@field start fun(src: Logs.Source)
---@field stop fun(src: Logs.Source)
---@field restart fun(src: Logs.Source)
---@field close_source fun(src: Logs.Source)
---@field open_file fun(whole: boolean)
---@field run_command fun()
---@field paste_log fun()
---@field open_recent fun()

---@type Proteus.Plugin
return {
  name = 'Logs',
  description = 'Follow a log file or a program, filter the lines, and spot errors.',
  version = '1.2.1',
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

    local wrap = app.store.get ('wrap', false) == true
    local filter_cancel = nil ---@type fun()?
    local empty_key = nil ---@type string?
    local my_tab = nil ---@type Proteus.Tab?

    -- What the modules share. Each adds its own functions to it.
    local shared = {
      app = app,
      ui = ui,
      commands = commands,
      sources = {},
      merged = false,
      view_all = {},
      win_from = 1,
      view_first = 1,
      by_id = {},
      query = lf.parse_query (''),
      hidden = {},
      follow = true,
      pending = {},
      chunks = {},
      drawn = 0,
      matched = 0,
      levels = lf.zero_levels (),
      recent = lf.clean_specs (app.store.get ('recent', {})),
    }
    local ctx = shared --[[@as Logs.Ctx]]
    for _, level in ipairs (lf.clean_levels (app.store.get ('hidden', {}))) do
      ctx.hidden[level] = true
    end

    ---@type fun()
    local redraw_list

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
      follow_btn:class ('on', ctx.follow)
      wrap_btn:class ('on', wrap)
    end

    local function scroll_bottom ()
      list:set ('scrollTop', 1e9)
    end

    ---@param on boolean
    local function set_follow (on)
      ctx.follow = on
      render_toggles ()
      if on then
        scroll_bottom ()
      end
    end

    local function render_chip_counts ()
      for _, level in ipairs (lf.LEVELS) do
        local n = ctx.levels[level] or 0
        if chip_values[level] ~= n then
          chip_values[level] = n
          chip_counts[level]:text (lf.group (n))
        end
      end
    end

    local function render_chip_states ()
      for _, level in ipairs (lf.LEVELS) do
        local off = ctx.hidden[level] == true
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
      if ctx.merged then
        local n = 0
        for _, src in ipairs (ctx.sources) do
          n = n + src.lines:count ()
        end
        return n
      end
      return ctx.shown and ctx.shown.lines:count () or 0
    end

    local function update_status ()
      if not st_state or not st_lines then
        return
      end
      if ctx.merged then
        st_state.set ('All sources, by time')
      elseif not ctx.shown then
        st_state.set ('')
        st_lines.set ('')
        return
      elseif ctx.shown.state == 'pasted' then
        st_state.set (ctx.shown.name)
      else
        st_state.set (
          ctx.shown.name
            .. ': '
            .. lf.state_label (ctx.shown.state, ctx.shown.code)
        )
      end
      local total = view_total ()
      if lf.is_empty (ctx.query) and next (ctx.hidden) == nil then
        st_lines.set (lf.group (total) .. (total == 1 and ' line' or ' lines'))
      else
        st_lines.set (
          lf.group (ctx.matched) .. ' of ' .. lf.group (total) .. ' lines'
        )
      end
    end

    local function update_counts ()
      for _, src in ipairs (ctx.sources) do
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
      ctx.query = lf.parse_query ('')
      ctx.hidden = {}
      app.store.set ('hidden', {})
      render_chip_states ()
      redraw_list ()
    end

    ---Shows a message in place of the list when there is nothing to list. It is rebuilt only
    ---when what it says changes.
    local function render_empty ()
      local key = nil ---@type string?
      local src = ctx.shown
      if ctx.merged then
        key = view_total () == 0 and 'blank:merged'
          or (ctx.matched == 0 and 'nomatch' or nil)
      elseif not src then
        key = 'none'
      elseif src.lines:count () == 0 then
        key = table.concat ({ 'blank', src.id, src.state, src.code or '' }, ':')
      elseif ctx.matched == 0 then
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
          text = sources_m.DESKTOP_ONLY .. ' Pasting a log works here too.'
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

    ctx.filter_box, ctx.problem_el = filter_box, problem_el
    ctx.list, ctx.rows_el = list, rows_el
    ctx.earlier_bar, ctx.earlier_text = earlier_bar, earlier_text
    ctx.later_bar, ctx.later_text = later_bar, later_text
    ctx.render_toggles, ctx.scroll_bottom = render_toggles, scroll_bottom
    ctx.render_chip_counts, ctx.render_empty = render_chip_counts, render_empty
    ctx.update_status, ctx.update_counts = update_status, update_counts
    list_m.attach (ctx)
    redraw_list = ctx.redraw_list
    local show_window, page, reveal = ctx.show_window, ctx.page, ctx.reveal
    local view_sources, id_of = ctx.view_sources, ctx.id_of

    -- The detail panel ------------------------------------------------------------------------

    ctx.detail, ctx.detail_title = detail, detail_title
    ctx.detail_text, ctx.json_box = detail_text, json_box
    ctx.selection_css, ctx.level_names = selection_css, LEVEL_NAMES
    ctx.set_follow = set_follow
    detail_m.attach (ctx)
    local close_detail, select_line = ctx.close_detail, ctx.select_line
    local move_selection = ctx.move_selection

    -- Sources ---------------------------------------------------------------------------------

    ctx.picker, ctx.desktop, ctx.src_list = picker, desktop, src_list
    ctx.say, ctx.say_error = say, say_error
    ctx.close_detail = close_detail
    sources_m.attach (ctx)
    local show_source, find_source = ctx.show_source, ctx.find_source
    local show_merged = ctx.show_merged
    local new_source, start = ctx.new_source, ctx.start
    local stop, restart, close_source = ctx.stop, ctx.restart, ctx.close_source
    local open_file, run_command = ctx.open_file, ctx.run_command
    local paste_log, open_recent = ctx.paste_log, ctx.open_recent

    -- Actions ---------------------------------------------------------------------------------

    local function clear_lines ()
      if not ctx.shown and not ctx.merged then
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
      if not ctx.shown and not ctx.merged then
        return
      end
      local texts = {} ---@type string[]
      for k = ctx.view_first, #ctx.view_all do
        texts[#texts + 1] = ctx.view_all[k].plain
      end
      app.system.clipboard (table.concat (texts, '\n'))
      say (
        'Copied '
          .. lf.group (#texts)
          .. (#texts == 1 and ' line.' or ' lines.')
      )
    end

    local function copy_selected ()
      if ctx.selected then
        app.system.clipboard (ctx.selected.plain)
        say ('Copied the line.')
      end
    end

    ---@param level string
    local function toggle_level (level)
      if ctx.hidden[level] then
        ctx.hidden[level] = nil
      else
        ctx.hidden[level] = true
      end
      local saved = {} ---@type string[]
      for _, name in ipairs (lf.LEVELS) do
        if ctx.hidden[name] then
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
      if ctx.follow then
        scroll_bottom ()
      elseif ctx.selected then
        reveal (ctx.selected.n)
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
        ctx.query = lf.parse_query (text)
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
          ctx.query = lf.parse_query ('')
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
      set_follow (not ctx.follow)
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
      if ev.key == 'Escape' and ctx.selected then
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
      if at_bottom ~= ctx.follow then
        ctx.follow = at_bottom
        render_toggles ()
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
          picked = ctx.by_id[math.floor (n)]
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
          disabled = ctx.matched == 0,
          run = copy_matching,
        }
        items[#items + 1] = {
          label = 'Clear',
          icon = 'eraser',
          key = 'Ctrl+K',
          disabled = ctx.shown == nil and not ctx.merged,
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
              disabled = #ctx.sources < 2,
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
      return here () and (ctx.shown ~= nil or ctx.merged)
    end

    ---@return boolean
    local function is_running ()
      local src = ctx.shown
      return here () and src ~= nil and src.state == 'running'
    end

    ---@return boolean
    local function can_restart ()
      local src = ctx.shown
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
        return here () and #ctx.sources >= 2
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
        return has_source () and ctx.win_from > ctx.view_first
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
        return has_source () and ctx.win_from + ctx.drawn - 1 < #ctx.view_all
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
        show_window (#ctx.view_all - list_m.MAX_SHOWN + 1)
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
        return here () and #ctx.recent > 0
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
        if ctx.shown then
          stop (ctx.shown)
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
        if ctx.shown and ctx.shown.spec.kind ~= 'paste' then
          restart (ctx.shown)
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
        if ctx.shown then
          close_source (ctx.shown)
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
        set_follow (not ctx.follow)
      end,
    })
    commands.register ({
      id = 'logs.copy_line',
      category = 'Logs',
      title = 'Copy Selected Line',
      icon = 'copy',
      when = function ()
        return here () and ctx.selected ~= nil
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
    local first = ctx.sources[1]
    for _, src in ipairs (ctx.sources) do
      if lf.spec_key (src.spec) == last_shown then
        first = src
      end
    end
    if last_shown == 'merged' and #ctx.sources >= 2 then
      show_merged ()
    else
      show_source (first)
    end
  end,
}
