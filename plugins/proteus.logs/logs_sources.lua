-- logs_sources: where the log viewer's lines come from. It opens log files, gzip files and
-- rotated logs, runs commands and reads pasted logs, starts, stops and restarts them, keeps their lines, draws the Sources view
-- and shows one source, or every source merged by time. The log viewer's init.lua attaches it
-- to the context its modules share.

local lf = require ('log_filter') --[[@as Logs.FilterModule]]

local MAX_LINES = 50000 -- kept per source
local MAX_WHOLE = 250000 -- kept for a whole file, a gzip file or a rotated log
local MAX_RECENT = 12
local DESKTOP_ONLY =
  'Following files and running commands needs the desktop app.'

---@type table<string, string>
local KIND_ICONS = {
  file = 'file-text',
  command = 'square-terminal',
  paste = 'clipboard-paste',
}

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

---@class Logs.SourcesViewModule
local M = {}

-- What the viewer says where it cannot follow files or run commands.
M.DESKTOP_ONLY = DESKTOP_ONLY

---Adds the sources to `ctx`.
---@param ctx Logs.Ctx
function M.attach (ctx)
  local app, ui, picker = ctx.app, ctx.ui, ctx.picker
  local desktop = ctx.desktop
  local src_list = ctx.src_list
  local say, say_error = ctx.say, ctx.say_error
  local render_toggles, render_empty = ctx.render_toggles, ctx.render_empty
  local update_status = ctx.update_status
  local redraw_list, forget_line, schedule =
    ctx.redraw_list, ctx.forget_line, ctx.schedule
  local close_detail = ctx.close_detail

  local next_line_id = 1
  local next_id = 1

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

  ---@param id number?
  ---@return Logs.Source?
  local function find_source (id)
    for _, src in ipairs (ctx.sources) do
      if src.id == id then
        return src
      end
    end
    return nil
  end

  local function save_open ()
    local open = {} ---@type Logs.SourceSpec[]
    for _, src in ipairs (ctx.sources) do
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

  local function render_sources ()
    local rows = {} ---@type Proteus.El[]
    if #ctx.sources >= 2 then
      rows[1] = ui.div ({
        class = 'logs-src merged' .. (ctx.merged and ' active' or ''),
        title = 'Every source in one list, in order of time',
        attrs = { ['data-item'] = 'merged' },
        ui.span ({ class = 'logs-src-icon', html = icon_svg ('git-merge') }),
        ui.span ({ class = 'logs-src-name', 'All sources, by time' }),
      })
    end
    for _, src in ipairs (ctx.sources) do
      local label =
        lf.state_label (src.state, src.code, src.spec.kind == 'file')
      local count = ui.span ({
        class = 'logs-src-count',
        lf.group (src.lines:count ()),
      })
      src.count_el = count
      src.counted = src.lines:count ()
      rows[#rows + 1] = ui.div ({
        class = 'logs-src'
          .. ((src == ctx.shown and not ctx.merged) and ' active' or ''),
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
    if src == ctx.shown or ctx.merged then
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
    if src == ctx.shown or ctx.merged then
      ctx.pending[#ctx.pending + 1] = line
      if dropped then
        local counted =
          lf.classify (dropped, ctx.query, ctx.hidden, ctx.view_newest)
        if counted then
          ctx.levels[dropped.level] = ctx.levels[dropped.level] - 1
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
      lines = lf.ring (lf.reads_whole (spec) and MAX_WHOLE or MAX_LINES),
      next_n = 1,
      state = 'stopped',
      run = 0,
      counted = 0,
    }
    next_id = next_id + 1
    ctx.sources[#ctx.sources + 1] = src
    return src
  end

  ---Runs a source's program, unless the source was stopped or started again meanwhile.
  ---@param src Logs.Source
  ---@param run integer
  ---@param program string
  ---@param args string[]
  local function spawn (src, run, program, args)
    if src.run ~= run then
      return
    end
    ---@type Proteus.SpawnOptions
    local opts = {
      cwd = src.spec.cwd,
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
    src.state = 'running'
    if spec.kind ~= 'file' then
      local program, args = lf.shell_command (spec.command or '', app.os)
      spawn (src, run, program, args)
      return
    end
    local path = spec.path or ''
    if not spec.rotated then
      local program, args = lf.follow_command (path, app.os, spec.whole)
      spawn (src, run, program, args)
      return
    end
    -- A rotated log reads the files beside it that it was rotated into, oldest first.
    local folder, sep, base = path:match ('^(.*)([/\\])([^/\\]+)$')
    source_changed (src)
    if not folder then
      local program, args = lf.follow_command (path, app.os, true)
      spawn (src, run, program, args)
      return
    end
    app.fs.list_dir (folder == '' and sep or folder, function (names)
      local older = {} ---@type string[]
      for _, name in ipairs (lf.rotated_files (base, names or {})) do
        older[#older + 1] = folder .. sep .. name
      end
      local program, args = lf.follow_command (path, app.os, true, older)
      spawn (src, run, program, args)
    end)
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
    if src == ctx.shown or ctx.merged then
      close_detail ()
      redraw_list ()
    end
    start (src)
  end

  local function show_source (src)
    if ctx.shown ~= src or ctx.merged then
      close_detail ()
      ctx.shown = src
      ctx.merged = false
      ctx.follow = true
      render_toggles ()
      app.store.set ('shown', src and lf.spec_key (src.spec) or nil)
    end
    redraw_list ()
    render_sources ()
  end

  ---Shows every source in one list, in order of time.
  local function show_merged ()
    if #ctx.sources < 2 then
      say ('The merged view needs two sources or more.')
      return
    end
    if not ctx.merged then
      close_detail ()
      ctx.shown = nil
      ctx.merged = true
      ctx.follow = true
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
    for i, other in ipairs (ctx.sources) do
      if other == src then
        index = i
        table.remove (ctx.sources, i)
        break
      end
    end
    save_open ()
    if ctx.merged and #ctx.sources < 2 then
      show_source (ctx.sources[1])
    elseif ctx.merged then
      redraw_list ()
      render_sources ()
    elseif ctx.shown == src then
      show_source (ctx.sources[index] or ctx.sources[index - 1])
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
    ctx.recent = lf.remember (ctx.recent, spec, MAX_RECENT)
    app.store.set ('recent', ctx.recent)
    local key = lf.spec_key (spec)
    for _, src in ipairs (ctx.sources) do
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

  ---Asks for one file of a rotated log, such as `app.log` or `app.log.1`, and reads every file
  ---of it as one source, oldest first, then follows the file written to now.
  local function open_rotated ()
    if not desktop then
      say (DESKTOP_ONLY)
      return
    end
    app.fs.pick_open ({ title = 'Open Rotated Log' }, function (paths, err)
      if err then
        say_error ('Could not show the file picker. ' .. err)
        return
      end
      local path = paths and paths[1]
      if not path then
        return
      end
      local folder, name = path:match ('^(.*[/\\])([^/\\]+)$')
      local base = (folder or '') .. lf.rotation_base (name or path)
      open_spec ({ kind = 'file', path = base, rotated = true })
    end)
  end

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
    for _, spec in ipairs (ctx.recent) do
      items[#items + 1] = {
        label = lf.source_name (spec)
          .. (
            spec.rotated and ' (with rotated files)'
            or (spec.whole and ' (whole file)' or '')
          ),
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

  ctx.find_source = find_source
  ctx.render_sources = render_sources
  ctx.show_source = show_source
  ctx.show_merged = show_merged
  ctx.new_source = new_source
  ctx.start = start
  ctx.stop = stop
  ctx.restart = restart
  ctx.close_source = close_source
  ctx.open_file = open_file
  ctx.open_rotated = open_rotated
  ctx.run_command = run_command
  ctx.paste_log = paste_log
  ctx.open_recent = open_recent
end

return M
