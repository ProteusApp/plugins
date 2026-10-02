-- api_history: the API client's history of sent requests. It keeps the last 50 in the store,
-- lists them in the History view, opens one again as a new request, and clears them. The
-- client's init.lua attaches it to the context its modules share.

---@class ApiApp.HistoryModule
local M = {}

---Adds the history to `ctx`.
---@param ctx ApiApp.Ctx
function M.attach (ctx)
  local app, ui, http = ctx.app, ctx.ui, ctx.http
  local picker, menus = ctx.picker, ctx.menus
  local esc, say, badge = app.util.escape, ctx.say, ctx.badge
  local show, add_new = ctx.show, ctx.add_new

  local render_history ---@type fun()

  do
    local stored = app.store.get ('history', {}) ---@type table<string, any>[]
    local scrubbed = false
    for _, e in ipairs (type (stored) == 'table' and stored or {}) do
      if type (e) == 'table' and type (e.url) == 'string' then
        local request = http.normalize (e.request)
        -- An older history kept the address with the environment's values filled in. The
        -- request it came from has the {{variables}} instead.
        local url = e.url
        if type (e.request) == 'table' then
          url = http.build (request).url
          scrubbed = scrubbed or url ~= e.url
        end
        ctx.history[#ctx.history + 1] = {
          method = http.normalize ({ method = e.method }).method,
          url = url,
          status = math.floor (tonumber (e.status) or 0),
          time = tonumber (e.time) or 0,
          request = request,
        }
      end
    end
    if scrubbed then
      app.store.set ('history', ctx.history)
    end
  end

  local function clear_history ()
    local function go ()
      ctx.history = {}
      app.store.set ('history', ctx.history)
      render_history ()
    end
    if #ctx.history == 0 then
      return
    end
    if picker then
      picker.confirm ({
        message = 'Clear the history of sent requests?',
        yes = 'Clear',
        on_yes = go,
      })
    else
      go ()
    end
  end

  local hist_list = ui.div ({ class = 'api-list' })
  local hist_empty = ui.div ({
    class = 'api-empty',
    ui.div ({ 'No requests sent yet' }),
    ui.div ({ 'Each request that goes out shows up here.' }),
  })
  local hist_box = ui.div ({ class = 'api-list-box', hist_list, hist_empty })
  local history_side = ui.div ({
    class = 'api-side',
    ui.div ({
      class = 'api-side-bar',
      ui.span ({ class = 'api-side-title', 'The last 50 sent' }),
      ui.span ({ class = 'api-grow' }),
      ui.button ({
        'Clear',
        icon = 'eraser',
        variant = 'ghost',
        class = 'api-small',
        onclick = function ()
          clear_history ()
          return nil
        end,
      }),
    }),
    hist_box,
  })

  render_history = function ()
    hist_empty:show (#ctx.history == 0)
    local now = app.util.now ()
    local parts = {} ---@type string[]
    for i, h in ipairs (ctx.history) do
      local answered = h.status > 0
      parts[#parts + 1] = '<div class="api-hrow" data-item="'
        .. i
        .. '" title="'
        .. esc (h.method .. ' ' .. h.url)
        .. '"><div class="api-hline">'
        .. badge (h.method)
        .. '<span class="api-hurl">'
        .. esc (h.url)
        .. '</span></div><div class="api-hmeta"><span class="api-s-'
        .. (answered and http.status_class (h.status) or 'none')
        .. '">'
        .. (answered and esc (http.status_line (h.status)) or 'No answer')
        .. '</span><span>'
        .. http.ago (h.time, now)
        .. '</span></div></div>'
    end
    hist_list:html (table.concat (parts))
  end

  ---@param entry Http.HistoryEntry
  local function open_history (entry)
    local req = http.copy (entry.request)
    -- It opens as a new request, so it takes no name from the one it came from.
    req.name = ''
    show (add_new (req, ''))
  end

  hist_list:on ('click', function (ev)
    local entry = ctx.history[math.floor (tonumber (ev.item or '') or 0)]
    if entry then
      open_history (entry)
    end
    return nil
  end)
  app.timer.every (60000, function ()
    render_history ()
  end)

  if menus then
    menus.attach (hist_box, function (ev)
      local entry = ctx.history[math.floor (tonumber (ev.item or '') or 0)]
      if entry then
        return {
          {
            label = 'Open',
            icon = 'file-text',
            run = function ()
              open_history (entry)
            end,
          },
          {
            label = 'Copy Address',
            icon = 'copy',
            run = function ()
              app.system.clipboard (entry.url)
              say ('Copied the address.')
            end,
          },
          { separator = true },
          {
            label = 'Clear History',
            icon = 'eraser',
            danger = true,
            run = clear_history,
          },
        }
      end
      return nil
    end)
  end

  ctx.render_history = render_history
  ctx.clear_history = clear_history
  ctx.history_side = history_side
end

return M
