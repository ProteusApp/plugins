-- logs_hist: the bars above the log viewer's list, which show how many lines that match were
-- written over time, by level. A click on a bar keeps the lines of its span of time, and a
-- drag across bars keeps the lines of all their spans: the span goes into the filter as
-- `after:` and `before:`, so the bars then show that span in finer bars. All Time takes the
-- span out again. The log viewer's init.lua attaches it to the context its modules share.

local lf = require ('log_filter') --[[@as Logs.FilterModule]]
local lh = require ('log_histogram') --[[@as Logs.HistogramModule]]

local MAX_BINS = 90
local LATER_MS = 500 -- how often the bars take in new lines

---@class Logs.HistModule
local M = {}

---Adds the bars to `ctx`.
---@param ctx Logs.Ctx
function M.attach (ctx)
  local app, ui = ctx.app, ctx.ui

  local bars = ui.div ({ class = 'logs-hist-bars' })
  local sel = ui.div ({ class = 'logs-hist-sel' })
  sel:show (false)
  local plot = ui.div ({ class = 'logs-hist-plot', bars, sel })
  local from_text = ui.span ({ class = 'logs-hist-from' })
  local step_el = ui.span ({ class = 'logs-hist-step' })
  local to_text = ui.span ({ class = 'logs-hist-to' })
  local all_btn = ui.button ({
    variant = 'ghost',
    class = 'ui-small',
    title = 'Take the span of time out of the filter',
    ui.icon ('zoom-out', 14),
    'All Time',
    onclick = function ()
      ctx.set_filter (lh.without_range (ctx.filter_text))
      return nil
    end,
  })
  all_btn:show (false)
  local el = ui.div ({
    class = 'logs-hist',
    plot,
    ui.div ({
      class = 'logs-hist-axis',
      from_text,
      ui.div ({ class = 'ui-grow' }),
      step_el,
      all_btn,
      ui.div ({ class = 'ui-grow' }),
      to_text,
    }),
  })
  el:show (false)

  local shown = app.store.get ('histogram', true) ~= false
  local hist = nil ---@type Logs.Histogram?
  local drag_from = nil ---@type integer?
  local drag_to = nil ---@type integer?
  local later_cancel = nil ---@type fun()?

  ---Shades the bars from `a` to `b` while the mouse drags across them.
  ---@param a integer
  ---@param b integer
  local function show_drag (a, b)
    local h = hist
    if not h then
      return
    end
    local n = #h.bins
    local lo, hi = math.min (a, b), math.max (a, b)
    sel:style ('left', string.format ('%.3f%%', (lo - 1) / n * 100))
    sel:style ('width', string.format ('%.3f%%', (hi - lo + 1) / n * 100))
    sel:show (true)
  end

  ---Draws the bars from the lines the list holds.
  local function render_hist ()
    if later_cancel then
      later_cancel ()
      later_cancel = nil
    end
    local any = ctx.shown ~= nil or ctx.merged
    hist = (shown and any) and lh.build (ctx.view_all, ctx.view_first, MAX_BINS)
      or nil
    local h = hist
    if not h then
      el:show (false)
      return
    end
    el:show (true)
    bars:html (lh.bars_html (h))
    local last = h.from + #h.bins * h.step
    from_text:text (lh.time_label (h.from, h.step))
    to_text:text (lh.time_label (last, h.step))
    step_el:text ('Each bar is ' .. lh.step_text (h.step))
    all_btn:show (lf.has_time (ctx.query))
    if drag_from and drag_to then
      show_drag (drag_from, drag_to)
    end
  end

  ---Draws the bars again in a moment, so lines that arrive by the thousand draw them once.
  local function schedule_hist ()
    if shown and not later_cancel then
      later_cancel = app.timer.after (LATER_MS, function ()
        later_cancel = nil
        render_hist ()
      end)
    end
  end

  ---Keeps the lines of the bars from `a` to `b`.
  ---@param a integer
  ---@param b integer
  local function keep_span (a, b)
    local h = hist
    if not h or not h.bins[a] or not h.bins[b] then
      return
    end
    local from, to = lh.span (h, a, b)
    ctx.set_filter (lh.with_range (ctx.filter_text, from, to))
  end

  local function end_drag ()
    local a, b = drag_from, drag_to
    drag_from, drag_to = nil, nil
    sel:show (false)
    if a and b then
      keep_span (a, b)
    end
  end

  bars:on ('mousedown', function (ev)
    local i = tonumber (ev.item or '')
    if i and (ev.button or 0) == 0 then
      drag_from = math.floor (i)
      drag_to = drag_from
      show_drag (drag_from, drag_to)
      return true
    end
    return nil
  end)
  bars:on ('mouseover', function (ev)
    local i = tonumber (ev.item or '')
    if drag_from and i then
      drag_to = math.floor (i)
      show_drag (drag_from, drag_to)
    end
    return nil
  end)
  bars:on ('mouseup', function ()
    end_drag ()
    return nil
  end)
  -- A drag that leaves the bars keeps the span it reached.
  bars:on ('mouseleave', function ()
    if drag_from then
      end_drag ()
    end
    return nil
  end)

  local function toggle_hist ()
    shown = not shown
    app.store.set ('histogram', shown)
    render_hist ()
  end

  ctx.hist_el = el
  ctx.render_hist = render_hist
  ctx.schedule_hist = schedule_hist
  ctx.toggle_hist = toggle_hist
  ctx.hist_shown = function ()
    return shown
  end
end

return M
