-- api_response: sends the open request and shows the answer. It gets an OAuth 2 token when the
-- sign-in needs one, answers a Digest challenge, cancels a request that is out, adds each send
-- to the history, and draws the status, the headers and the body, formatted when it is JSON.
-- The client's init.lua attaches it to the context its modules share.

local core = require ('api_core') --[[@as ApiApp.Core]]

local HISTORY_MAX = 50
-- A longer answer shows as it came, since formatting it would hold up the window.
local PRETTY_MAX = 3 * 1024 * 1024
-- How much of a binary answer shows as hex.
local HEX_MAX = 4096

---@class ApiApp.ResponseModule
local M = {}

---Adds the response and sending to `ctx`.
---@param ctx ApiApp.Ctx
function M.attach (ctx)
  local app, ui, http = ctx.app, ctx.ui, ctx.http
  local esc, icon, browser = app.util.escape, ctx.icon, ctx.browser
  local say, complain = ctx.say, ctx.complain
  local render_status, effective_auth = ctx.render_status, ctx.effective_auth
  local tokens, token_key = ctx.tokens, ctx.token_key
  local url_in, send_btn, au = ctx.url_in, ctx.send_btn, ctx.au
  local count_html, render_send = ctx.count_html, ctx.render_send
  local render_auth, render_token = ctx.render_auth, ctx.render_token

  local send_count = 0
  local res_view = app.store.get ('res_view', 'body') ---@type string
  local raw = app.store.get ('raw', false) == true

  local sum = ui.div ({ class = 'api-sum' })
  local warn = ui.div ({ class = 'api-warn' })
  local res_hint = ui.div ({ class = 'api-hint' })
  local res_error = ui.div ({ class = 'api-error' })
  local res_code =
    ui.widget ('code', { language = 'json', readonly = true, text = '' })
  local res_code_host = ui.div ({ class = 'api-code', res_code })
  local res_headers = ui.div ({ class = 'api-hdrs' })
  local res_box = ui.div ({
    class = 'api-res',
    res_hint,
    res_error,
    res_code_host,
    res_headers,
  })
  local shown_for = nil ---@type ApiApp.Result?
  local shown_text = nil ---@type string?

  ---@param list Proteus.HttpHeader[]
  ---@return string
  local function headers_html (list)
    if #list == 0 then
      return '<div class="api-hint">No headers came back.</div>'
    end
    local parts = { '<table class="api-htable">' }
    for _, h in ipairs (list) do
      parts[#parts + 1] = '<tr><td>'
        .. esc (h.name)
        .. '</td><td>'
        .. esc (h.value)
        .. '</td></tr>'
    end
    parts[#parts + 1] = '</table>'
    return table.concat (parts)
  end

  ---@param id string
  ---@param label string
  ---@param on boolean
  ---@return string
  local function seg_button (id, label, on)
    return '<button class="'
      .. (on and 'on' or '')
      .. '" data-item="'
      .. id
      .. '">'
      .. label
      .. '</button>'
  end

  local function render_response ()
    local doc = ctx.current
    if not doc then
      return
    end
    local waiting = doc.pending ~= nil
    local r = not waiting and doc.result or nil
    local answer = r and r.status and r or nil
    local kind = answer
        and not answer.binary
        and http.body_kind (answer.headers, answer.body)
      or 'text'

    local parts = {} ---@type string[]
    if waiting then
      parts[#parts + 1] =
        '<span class="api-meta">Waiting for the answer…</span>'
    elseif answer then
      local code = answer.status or 0
      parts[#parts + 1] = '<span class="api-status api-s-'
        .. http.status_class (code)
        .. '">'
        .. esc (http.status_line (code))
        .. '</span><span class="api-meta">'
        .. http.format_ms (answer.ms)
        .. '</span><span class="api-meta">'
        .. http.human_size (answer.size)
        .. (answer.binary and ', bytes' or '')
        .. '</span>'
      if answer.url then
        parts[#parts + 1] = '<span class="api-to" title="'
          .. esc (answer.url)
          .. '">'
          .. (answer.redirects == 1 and '1 redirect to ' or (answer.redirects .. ' redirects to '))
          .. esc (answer.url)
          .. '</span>'
      end
    else
      parts[#parts + 1] = '<span class="api-sum-label">Response</span>'
    end
    parts[#parts + 1] = '<span class="api-grow"></span>'
    if answer then
      parts[#parts + 1] = '<span class="api-seg">'
        .. seg_button ('body', 'Body', res_view == 'body')
        .. seg_button (
          'headers',
          'Headers ' .. count_html (#answer.list),
          res_view == 'headers'
        )
        .. '</span>'
      if res_view == 'body' and kind == 'json' then
        parts[#parts + 1] = '<span class="api-seg">'
          .. seg_button ('pretty', 'Pretty', not raw)
          .. seg_button ('raw', 'Raw', raw)
          .. '</span>'
      end
      parts[#parts + 1] = '<button class="api-icon-btn" data-item="copy" title="'
        .. (answer.binary and 'Copy the body as base64' or 'Copy the body')
        .. '">'
        .. icon ('copy')
        .. '</button>'
    end
    sum:html (table.concat (parts))

    local warning = waiting and doc.warning or (r and r.warning)
    warn:text (warning or '')
    warn:show (warning ~= nil)
    res_hint:show (false)
    res_error:show (false)
    res_code_host:show (false)
    res_headers:show (false)

    ---@param text string
    local function hint (text)
      res_hint:text (text)
      res_hint:show (true)
    end

    if doc.folder_auth then
      hint ('Requests in this folder set to From folder sign in this way.')
    elseif waiting then
      hint ('Waiting for the answer. Cancel stops the request.')
    elseif not r then
      hint ('Press Ctrl+Enter to send.')
    elseif r.error then
      res_error:text (r.error)
      res_error:show (true)
    elseif not answer then
      hint (r.note or 'Press Ctrl+Enter to send.')
    elseif res_view == 'headers' then
      res_headers:html (headers_html (answer.list))
      res_headers:show (true)
    elseif answer.body == '' then
      hint ('The answer has no body.')
    else
      local text, language = answer.body, 'text'
      if answer.binary then
        -- Bytes that are not text show as hex, the first few kilobytes of them.
        answer.shown = answer.shown
          or (
            'The answer is '
            .. http.human_size (answer.size)
            .. ' of bytes that are not text. The first of them:\n\n'
            .. http.hex_dump (http.base64_decode (answer.body), HEX_MAX)
          )
        text = answer.shown
      elseif kind == 'json' then
        language = 'json'
        if not raw and #answer.body <= PRETTY_MAX then
          answer.pretty = answer.pretty
            or http.pretty_json (answer.body)
            or answer.body
          text = answer.pretty
        end
      elseif kind == 'html' or kind == 'xml' then
        language = 'html'
      end
      -- Sending a long body to the code editor again would reset its scroll for nothing.
      if shown_for ~= answer or shown_text ~= text then
        res_code:widget ('set_language', language)
        res_code:widget ('set_text', text)
        shown_for = answer
        shown_text = text
      end
      res_code_host:show (true)
    end
  end

  -- Sending -----------------------------------------------------------------------------

  ---Asks the token address of an OAuth 2 sign-in for a token, and keeps it. `done` gets
  ---the token, or nil and why not. Returns the request, so Cancel can stop it.
  ---@param auth Http.Auth
  ---@param done fun(token: string?, err: string?)
  ---@return Proteus.HttpCall?
  local function get_token (auth, done)
    local request, err = http.oauth_request (auth, http.env_vars (ctx.envs))
    if not request then
      done (nil, err)
      return nil
    end
    local key = token_key (auth)
    local ok, call = pcall (app.net.fetch, request, function (reply, why)
      if not reply then
        done (nil, http.error_text (why, browser))
        return
      end
      local token, seconds, problem = http.oauth_token (reply)
      if not token then
        done (nil, problem)
        return
      end
      tokens[key] = core.keep_token (token, seconds, app.util.now ())
      done (token, nil)
    end)
    if not ok then
      done (nil, tostring (call))
      return nil
    end
    return call --[[@as Proteus.HttpCall]]
  end

  local function send ()
    local doc = ctx.current
    if not doc or doc.folder_auth then
      return
    end
    if doc.pending then
      -- Cancel stops the request itself, not only the wait for it.
      local call = doc.call
      doc.pending = nil
      doc.call = nil
      if call then
        call.cancel ()
      end
      doc.result =
        core.empty_result ({ note = 'Cancelled. The request stopped.' })
      render_send ()
      render_response ()
      render_status ()
      return
    end
    local env = http.env_vars (ctx.envs)
    local auth = effective_auth (doc)
    ---@type Http.BuildContext
    local build_ctx = { auth = auth }
    local kept = auth.mode == 'oauth2' and tokens[token_key (auth)] or nil
    if kept and core.token_fresh (kept, app.util.now ()) then
      build_ctx.token = kept.token
    end
    local built = http.build (doc.req, env, build_ctx)
    if built.url == '' then
      doc.result = core.empty_result ({ note = 'Type an address first.' })
      render_response ()
      url_in:focus ()
      return
    end
    local problem = core.send_problem (built)
    if problem then
      doc.result = core.empty_result ({ error = problem })
      render_response ()
      render_status ()
      return
    end
    send_count = send_count + 1
    local number = send_count
    local started = app.util.now ()
    local warning = http.missing_text (built.missing, ctx.envs.active)
    local snapshot = http.copy (doc.req)
    doc.pending = number
    doc.warning = warning
    render_send ()
    render_response ()
    render_status ()

    ---@param result ApiApp.Result
    local function finish (result)
      if doc.pending ~= number then
        return
      end
      doc.pending = nil
      doc.call = nil
      doc.result = result
      ctx.history = http.add_history (ctx.history, {
        method = built.method,
        -- The address as typed, with {{variables}} left in, so no token from an environment
        -- is kept in the history.
        url = http.build (snapshot).url,
        status = result.status or 0,
        time = app.util.now (),
        request = snapshot,
      }, HISTORY_MAX)
      app.store.set ('history', ctx.history)
      ctx.render_history ()
      if doc == ctx.current then
        render_send ()
        render_response ()
        render_auth ()
      end
      render_status ()
    end

    ---@param err string
    local function fail (err)
      finish (core.empty_result ({
        error = err,
        warning = warning,
        ms = app.util.now () - started,
      }))
    end

    ---Sends a built request. A Digest challenge in a 401 is answered once.
    ---@param b Http.Built
    ---@param answered boolean
    local function go (b, answered)
      local ok, call = pcall (
        app.net.fetch,
        http.fetch_request (b),
        function (reply, err)
          if doc.pending ~= number then
            return
          end
          if not reply then
            fail (http.error_text (err, browser))
            return
          end
          if b.digest and not answered and reply.status == 401 then
            local header, why = http.digest_header (
              b,
              tostring (
                reply.headers and reply.headers['www-authenticate'] or ''
              ),
              core.random_hex (16, math.random),
              1
            )
            if header then
              b.headers.Authorization = header
              go (b, true)
              return
            end
            warning = (warning and (warning .. '\n') or '') .. tostring (why)
          end
          if auth.mode == 'oauth2' and reply.status == 401 then
            -- The token may have ended early, so the next send asks for a new one.
            tokens[token_key (auth)] = nil
          end
          finish (
            core.result_of (reply, b.url, app.util.now () - started, warning)
          )
        end
      )
      if not ok then
        fail (http.error_text (tostring (call), browser))
        return
      end
      doc.call = call --[[@as Proteus.HttpCall]]
    end

    if auth.mode == 'oauth2' and not build_ctx.token then
      doc.call = get_token (auth, function (token, err)
        if doc.pending ~= number then
          return
        end
        if not token then
          fail ('No token came, so the request did not go. ' .. tostring (err))
          return
        end
        go (http.build (doc.req, env, { auth = auth, token = token }), false)
      end)
    else
      go (built, false)
    end
  end

  au.token_btn:on ('click', function ()
    local doc = ctx.current
    if not doc then
      return nil
    end
    local auth = effective_auth (doc)
    if auth.mode ~= 'oauth2' then
      return nil
    end
    au.token_state:text ('Asking for a token…')
    get_token (auth, function (token, err)
      if token then
        say ('Got a new token.')
      else
        complain ('No token came. ' .. tostring (err))
      end
      render_token ()
    end)
    return nil
  end)

  send_btn:on ('click', function ()
    send ()
    return nil
  end)
  url_in:on ('keydown', function (ev)
    if ev.key == 'Enter' and not ev.ctrl and not ev.composing then
      send ()
      return true
    end
    return nil
  end)

  sum:on ('click', function (ev)
    local item = ev.item
    local doc = ctx.current
    if not item or not doc then
      return nil
    end
    if item == 'body' or item == 'headers' then
      res_view = item
      app.store.set ('res_view', item)
    elseif item == 'pretty' or item == 'raw' then
      raw = item == 'raw'
      app.store.set ('raw', raw)
    elseif item == 'copy' then
      local r = doc.result
      if r then
        app.system.clipboard (
          (shown_for == r and not r.binary) and shown_text or r.body
        )
        say (r.binary and 'Copied the body as base64.' or 'Copied the body.')
      end
      return nil
    end
    render_response ()
    return nil
  end)

  ctx.sum = sum
  ctx.warn = warn
  ctx.res_box = res_box
  ctx.render_response = render_response
  ctx.send = send
end

return M
