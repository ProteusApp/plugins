-- logs_list: the log viewer's list of lines. It draws the window of lines that match, a chunk
-- of rows at a time, with a column for each field the sources' formats show, sorts it by a
-- column, moves the window, adds the lines that arrive, and finds a line's row. The log
-- viewer's init.lua attaches it to the context its modules share.
--
-- Lines can arrive by the thousand, so the list is drawn from HTML strings instead of one
-- element per row. Rows go into chunks of a few hundred, and each chunk is one element. New
-- rows join the last chunk, and whole chunks drop off the top once the list passes its cap.

local lf = require ('log_filter') --[[@as Logs.FilterModule]]

local MAX_SHOWN = 5000 -- drawn at once
local CHUNK_ROWS = 250
local FLUSH_MS = 100
local RESORT_MS = 1000 -- how often a sorted list takes in the lines that arrived

---Rows drawn as one element.
---@class Logs.Chunk
---@field el Proteus.El
---@field ns integer[] The ids of the lines in its rows, in order.

---@class Logs.ListModule
local M = {}

-- How many lines the list draws at once.
M.MAX_SHOWN = MAX_SHOWN

---Adds the list of lines to `ctx`.
---@param ctx Logs.Ctx
function M.attach (ctx)
  local app, ui = ctx.app, ctx.ui
  local filter_box, problem_el = ctx.filter_box, ctx.problem_el
  local list, rows_el, head_el = ctx.list, ctx.rows_el, ctx.head_el
  local earlier_bar, earlier_text = ctx.earlier_bar, ctx.earlier_text
  local later_bar, later_text = ctx.later_bar, ctx.later_text
  local render_toggles, scroll_bottom = ctx.render_toggles, ctx.scroll_bottom
  local render_chip_counts, render_empty =
    ctx.render_chip_counts, ctx.render_empty
  local update_status, update_counts = ctx.update_status, ctx.update_counts

  -- The chunk each drawn line sits in, by id.
  local where = {} ---@type table<integer, Logs.Chunk>
  local flush_cancel = nil ---@type fun()?
  local resort_cancel = nil ---@type fun()?

  local function clear_list ()
    rows_el:clear ()
    ctx.chunks = {}
    ctx.drawn = 0
    ctx.by_id = {}
    where = {}
  end

  ---Shows how many matching lines lie before and after the window.
  local function render_bars ()
    local before = math.max (0, ctx.win_from - ctx.view_first)
    local after = math.max (0, #ctx.view_all - (ctx.win_from + ctx.drawn - 1))
    earlier_bar:show (before > 0)
    later_bar:show (after > 0)
    earlier_text:text (
      lf.group (before) .. (before == 1 and ' earlier line' or ' earlier lines')
    )
    later_text:text (
      lf.group (after) .. (after == 1 and ' later line' or ' later lines')
    )
  end

  ---The tag a row carries in the merged view.
  ---@param line Logs.Line
  ---@return { name: string, n: integer }?
  local function tag_of (line)
    if not ctx.merged then
      return nil
    end
    for i, src in ipairs (ctx.sources) do
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
      local chunk = ctx.chunks[#ctx.chunks]
      if not chunk or #chunk.ns >= CHUNK_ROWS then
        chunk = { el = ui.div ({ class = 'logs-chunk' }), ns = {} }
        rows_el:append (chunk.el)
        ctx.chunks[#ctx.chunks + 1] = chunk
      end
      local last = math.min (#lines, i + CHUNK_ROWS - #chunk.ns - 1) ---@type integer
      local parts = {} ---@type string[]
      for k = i, last do
        local line = lines[k]
        local id = line.id or line.n
        parts[#parts + 1] =
          lf.row_html (line, ctx.query, tag_of (line), ctx.cols)
        chunk.ns[#chunk.ns + 1] = id
        ctx.by_id[id] = line
        where[id] = chunk
      end
      -- Each batch of rows is an element of its own, which shows only its rows.
      chunk.el:append (
        ui.div ({ class = 'logs-batch', html = table.concat (parts) })
      )
      ctx.drawn = ctx.drawn + (last - i + 1)
      i = last + 1
    end
    -- While the list is scrolled up, keep what is on screen still as rows go from the top.
    local lost = 0
    while #ctx.chunks > 1 and ctx.drawn - #ctx.chunks[1].ns >= MAX_SHOWN do
      local first = table.remove (ctx.chunks, 1)
      ctx.drawn = ctx.drawn - #first.ns
      ctx.win_from = ctx.win_from + #first.ns
      for _, id in ipairs (first.ns) do
        ctx.by_id[id] = nil
        where[id] = nil
      end
      if not ctx.follow then
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

  ---Draws the row of column names, or hides it when the formats show no fields.
  local function render_head ()
    local cols = ctx.cols
    if not cols then
      head_el:show (false)
      return
    end
    head_el:html (lf.head_html (cols, ctx.sort))
    head_el:show (true)
  end

  ---Draws the window of matching lines that starts at `from`.
  ---@param from integer
  local function show_window (from)
    clear_list ()
    ctx.win_from =
      math.max (ctx.view_first, math.min (from, #ctx.view_all - MAX_SHOWN + 1))
    local lines = {} ---@type Logs.Line[]
    for k = ctx.win_from, math.min (#ctx.view_all, ctx.win_from + MAX_SHOWN - 1) do
      lines[#lines + 1] = ctx.view_all[k]
    end
    -- Each column is as wide as the widest value it shows in the window.
    ctx.cols = #ctx.col_names > 0
        and {
          names = ctx.col_names,
          widths = lf.column_widths (lines, ctx.col_names),
        }
      or nil
    render_head ()
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
    for ci, c in ipairs (ctx.chunks) do
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
    local chunk = ctx.chunks[ci]
    local chunk_top = tonumber (chunk.el:get ('offsetTop')) or 0
    local chunk_height = tonumber (chunk.el:get ('offsetHeight')) or 0
    local row_height = chunk_height / #chunk.ns
    local top = chunk_top + (ri - 1) * row_height
    local bottom = top + row_height
    local scroll = tonumber (list:get ('scrollTop')) or 0
    local view = tonumber (list:get ('clientHeight')) or 0
    -- The row of column names stays at the top, over the rows.
    local head = ctx.cols and (tonumber (head_el:get ('offsetHeight')) or 0)
      or 0
    if top - head < scroll then
      list:set ('scrollTop', top - head)
    elseif bottom > scroll + view then
      list:set ('scrollTop', bottom - view)
    end
  end

  ---The sources the view shows.
  ---@return Logs.Source[]
  local function view_sources ()
    if ctx.merged then
      return ctx.sources
    end
    return ctx.shown and { ctx.shown } or {}
  end

  ---@param line Logs.Line
  ---@return integer
  local function id_of (line)
    return line.id or line.n
  end

  ---Finds the fields the formats of the view's sources show. The filter reads `field:value`
  ---only for those, so the query is read again when they change.
  local function refresh_columns ()
    local names, seen = {}, {} ---@type string[], table<string, boolean>
    for _, src in ipairs (view_sources ()) do
      local parser = src.parser
      for _, name in ipairs (parser and parser.fields or {}) do
        if not seen[name] then
          seen[name] = true
          names[#names + 1] = name
        end
      end
    end
    local key = table.concat (names, '\n')
    if key == ctx.cols_key then
      return
    end
    ctx.cols_key = key
    ctx.col_names = names
    local known = {} ---@type table<string, string>
    for _, name in ipairs (names) do
      known[name:lower ()] = name
    end
    ctx.known_fields = known
    ctx.query = lf.parse_query (ctx.filter_text, known)
    if ctx.sort and not seen[ctx.sort.field] then
      ctx.sort = nil
    end
  end

  local function redraw_list ()
    if resort_cancel then
      resort_cancel ()
      resort_cancel = nil
    end
    refresh_columns ()
    ctx.pending = {}
    ctx.matched = 0
    ctx.levels = lf.zero_levels ()
    problem_el:text (ctx.query.problem or '')
    problem_el:show (ctx.query.problem ~= nil)
    filter_box:class ('bad', ctx.query.problem ~= nil)
    ctx.view_newest = nil
    for _, src in ipairs (view_sources ()) do
      local t = lf.newest (src.lines)
      if t and (not ctx.view_newest or t > ctx.view_newest) then
        ctx.view_newest = t
      end
    end
    local lists = {} ---@type Logs.Line[][]
    for _, src in ipairs (view_sources ()) do
      local result =
        lf.scan (src.lines, ctx.query, ctx.hidden, 0, ctx.view_newest)
      lists[#lists + 1] = result.all
      for level, n in pairs (result.levels) do
        ctx.levels[level] = ctx.levels[level] + n
      end
    end
    ctx.view_all = #lists == 1 and lists[1] or lf.merge (lists)
    if ctx.sort then
      ctx.view_all = lf.sort_lines (ctx.view_all, ctx.sort.field, ctx.sort.desc)
    end
    ctx.view_first = 1
    ctx.matched = #ctx.view_all
    -- Following shows the newest lines. Otherwise the window keeps the selected line.
    local from = #ctx.view_all - MAX_SHOWN + 1
    if not ctx.follow and ctx.selected then
      local want = id_of (ctx.selected)
      for k, line in ipairs (ctx.view_all) do
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
    ctx.render_hist ()
    if ctx.follow then
      scroll_bottom ()
    elseif ctx.selected then
      reveal (id_of (ctx.selected))
    end
  end

  ---Sorts the list by a column: up, then down, then back to the order the lines came in.
  ---@param field string
  local function sort_by (field)
    local sort = ctx.sort
    if not sort or sort.field ~= field then
      ctx.sort = { field = field, desc = false }
    elseif not sort.desc then
      ctx.sort = { field = field, desc = true }
    else
      ctx.sort = nil
    end
    redraw_list ()
  end

  head_el:on ('click', function (ev)
    local field = (ev.item or ''):match ('^col:(.+)$')
    if field then
      for _, name in ipairs (ctx.col_names) do
        if name == field then
          sort_by (name)
        end
      end
    end
    return nil
  end)

  ---Moves the window by `step` lines, earlier when it is below 0.
  ---@param step integer
  local function page (step)
    if ctx.follow then
      ctx.follow = false
      render_toggles ()
    end
    local top_id = ctx.chunks[1] and ctx.chunks[1].ns[1]
    show_window (ctx.win_from + step)
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
    if ctx.merged then
      return
    end
    if ctx.view_all[ctx.view_first] == line then
      ctx.view_first = ctx.view_first + 1
      ctx.matched = ctx.matched - 1
    end
    -- Pack the list now and then, so the lines let go do not pile up.
    if ctx.view_first > 20000 then
      local shift = ctx.view_first - 1
      local packed = {} ---@type Logs.Line[]
      for k = ctx.view_first, #ctx.view_all do
        packed[#packed + 1] = ctx.view_all[k]
      end
      ctx.view_all = packed
      ctx.view_first = 1
      ctx.win_from = ctx.win_from - shift
    end
  end

  local function flush ()
    flush_cancel = nil
    local batch = ctx.pending
    if ctx.sort and #batch > 0 then
      -- A sorted list sorts again to take in new lines, at most once a second.
      if not resort_cancel then
        resort_cancel = app.timer.after (RESORT_MS, function ()
          resort_cancel = nil
          redraw_list ()
        end)
      end
      update_counts ()
      update_status ()
      return
    end
    ctx.pending = {}
    if (ctx.shown or ctx.merged) and #batch > 0 then
      -- New lines show when the window has reached the end. Otherwise only the count of
      -- later lines grows.
      local at_end = ctx.win_from + ctx.drawn - 1 >= #ctx.view_all
      local fresh = {} ---@type Logs.Line[]
      for _, line in ipairs (batch) do
        local counted, visible =
          lf.classify (line, ctx.query, ctx.hidden, ctx.view_newest)
        if counted then
          ctx.levels[line.level] = ctx.levels[line.level] + 1
        end
        if visible then
          ctx.view_all[#ctx.view_all + 1] = line
          ctx.matched = ctx.matched + 1
          fresh[#fresh + 1] = line
        end
      end
      if at_end and #fresh > MAX_SHOWN then
        -- More new rows than the list holds, so the list starts again with the newest.
        show_window (#ctx.view_all - MAX_SHOWN + 1)
      elseif at_end and #fresh > 0 then
        draw_rows (fresh)
      else
        render_bars ()
      end
      render_chip_counts ()
      render_empty ()
      if #fresh > 0 then
        ctx.schedule_hist ()
      end
      if ctx.follow and #fresh > 0 then
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

  ctx.redraw_list = redraw_list
  ctx.sort_by = sort_by
  ctx.show_window = show_window
  ctx.page = page
  ctx.reveal = reveal
  ctx.locate = locate
  ctx.view_sources = view_sources
  ctx.id_of = id_of
  ctx.tag_of = tag_of
  ctx.forget_line = forget_line
  ctx.schedule = schedule
end

return M
