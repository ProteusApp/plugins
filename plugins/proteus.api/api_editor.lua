-- api_editor: the API client's request editor. It draws the method, the address and the tabs
-- of a request, the key and value grids, the body, sign-in and option panes, and fills them
-- from the open request, and it writes each edit back into the request. The client's init.lua
-- attaches it to the context its modules share, and puts the editor and the response together.

local core = require ('api_core') --[[@as ApiApp.Core]]

local BODY_OPTIONS = {
  { 'none', 'None' },
  { 'json', 'JSON' },
  { 'text', 'Text' },
  { 'form', 'Form' },
  { 'multipart', 'Multipart' },
  { 'graphql', 'GraphQL' },
  { 'file', 'File' },
}
local AUTH_OPTIONS = {
  { 'none', 'None' },
  { 'inherit', 'From folder' },
  { 'bearer', 'Bearer token' },
  { 'basic', 'Basic' },
  { 'apikey', 'API key' },
  { 'digest', 'Digest' },
  { 'oauth2', 'OAuth 2' },
}
-- A folder's own sign-in: `inherit` there hands down what the folders around it hold.
local FOLDER_AUTH_OPTIONS = {
  { 'inherit', 'From the folder above' },
  { 'none', 'None' },
  { 'bearer', 'Bearer token' },
  { 'basic', 'Basic' },
  { 'apikey', 'API key' },
  { 'digest', 'Digest' },
  { 'oauth2', 'OAuth 2' },
}

---A key and value table drawn as one HTML string.
---@class ApiApp.Grid
---@field el Proteus.El
---@field render fun()

---How a key and value grid lets its rows send files.
---@class ApiApp.FileRows
---@field on fun(): boolean True while the rows may send files.
---@field pick fun(row: Http.Row, done: fun()) Asks for a file for the row.

---@class ApiApp.EditorModule
local M = {}

---Adds the request editor to `ctx`.
---@param ctx ApiApp.Ctx
function M.attach (ctx)
  local app, ui, http = ctx.app, ctx.ui, ctx.http
  local esc, icon, complain = app.util.escape, ctx.icon, ctx.complain
  local touch, schedule_list = ctx.touch, ctx.schedule_list
  local schedule_drafts, render_status = ctx.schedule_drafts, ctx.render_status
  local effective_auth = ctx.effective_auth

  local pane = app.store.get ('pane', 'params') ---@type string

  local title = ui.span ({ class = 'api-title' })
  local head_dot = ui.span ({ class = 'api-dot', title = 'Unsaved changes' })
  local where = ui.span ({ class = 'api-where' })
  local head = ui.div ({ class = 'api-head', title, head_dot, where })

  local method_html = {} ---@type string[]
  for _, meth in ipairs (http.METHODS) do
    method_html[#method_html + 1] = '<option value="'
      .. meth
      .. '" class="api-m-'
      .. meth:lower ()
      .. '">'
      .. meth
      .. '</option>'
  end
  local method_sel = ui.h ('select', {
    class = 'api-method',
    title = 'Method',
    html = table.concat (method_html),
  })
  local url_in = ui.input ({
    class = 'api-url',
    placeholder = 'https://example.com/path, or {{base_url}}/path',
    spellcheck = false,
  })
  local send_btn = ui.button ({ class = 'api-send', variant = 'primary' })
  local line = ui.div ({ class = 'api-line', method_sel, url_in, send_btn })
  local req_tabs = ui.div ({ class = 'api-tabs' })

  ---@param get fun(): Http.Row[]
  ---@param changed fun()
  ---@param files? ApiApp.FileRows Rows that send files, in Multipart mode.
  ---@return ApiApp.Grid
  local function kv_grid (get, changed, files)
    local el = ui.div ({ class = 'api-kv' })

    -- Each row is an element of its own, so a new blank row can be added after the one
    -- being typed in without drawing the rows again, which would move the cursor.
    ---@param i integer
    ---@param r Http.Row
    ---@param with_files boolean
    ---@return Proteus.El
    local function row_el (i, r, with_files)
      local n = tostring (i)
      local value ---@type string
      if r.file_name then
        local need = (r.file or '') == ''
        value = '<button class="api-kv-file'
          .. (need and ' need' or '')
          .. '" title="'
          .. (need and 'Pick the file to send' or 'Pick another file')
          .. '" data-item="'
          .. n
          .. ':pick">'
          .. icon ('paperclip', 13)
          .. esc (r.file_name)
          .. (need and ' (pick it)' or '')
          .. '</button>'
      else
        value = '<input class="api-kv-in" placeholder="Value" spellcheck="false" autocomplete="off" data-item="'
          .. n
          .. ':value" value="'
          .. esc (r.value)
          .. '">'
      end
      local kind = ''
      if with_files then
        kind = '<button class="api-kv-kind'
          .. (r.file_name and ' on' or '')
          .. '" title="'
          .. (r.file_name and 'Send text instead' or 'Send a file')
          .. '" data-item="'
          .. n
          .. ':kind">'
          .. icon (r.file_name and 'type' or 'paperclip')
          .. '</button>'
      end
      local html = '<input type="checkbox" title="Send this row" data-item="'
        .. n
        .. ':on"'
        .. (r.on and ' checked' or '')
        .. '><input class="api-kv-in" placeholder="Key" spellcheck="false" autocomplete="off" data-item="'
        .. n
        .. ':key" value="'
        .. esc (r.key)
        .. '">'
        .. value
        .. kind
        .. '<button class="api-kv-del" title="Remove this row" data-item="'
        .. n
        .. ':del">'
        .. icon ('x')
        .. '</button>'
      return ui.div ({
        class = 'api-kv-row' .. (r.on and '' or ' off'),
        html = html,
      })
    end

    ---@return boolean
    local function with_files ()
      return files ~= nil and files.on ()
    end

    local function render ()
      local rows = get ()
      local wf = with_files ()
      el:class ('files', wf)
      local kids = {
        ui.div ({
          class = 'api-kv-head',
          html = '<span></span><span>Key</span><span>Value</span><span></span>'
            .. (wf and '<span></span>' or ''),
        }),
      } ---@type Proteus.El[]
      for i, r in ipairs (rows) do
        kids[#kids + 1] = row_el (i, r, wf)
      end
      kids[#kids + 1] =
        row_el (#rows + 1, { key = '', value = '', on = true }, false)
      el:set_children (kids)
    end

    el:on ('input', function (ev)
      local i, field = core.grid_item (ev.item)
      if not i or (field ~= 'key' and field ~= 'value') then
        return nil
      end
      local rows = get ()
      local r = rows[i]
      if not r then
        if i ~= #rows + 1 then
          return nil
        end
        r = { key = '', value = '', on = true }
        rows[i] = r
        -- The blank row now holds text, so a new blank row goes after it. Adding it
        -- without a redraw keeps the cursor where it is.
        el:append (row_el (i + 1, { key = '', value = '', on = true }, false))
      end
      if field == 'key' then
        r.key = ev.value or ''
      else
        r.value = ev.value or ''
      end
      changed ()
      return nil
    end)

    el:on ('change', function (ev)
      local i, field = core.grid_item (ev.item)
      local r = i and get ()[i]
      if field ~= 'on' or not r then
        return nil
      end
      r.on = ev.checked == true
      render ()
      changed ()
      return nil
    end)

    el:on ('click', function (ev)
      local i, field = core.grid_item (ev.item)
      local rows = get ()
      local r = i and rows[i]
      if not i or not r then
        return nil
      end
      if field == 'del' then
        table.remove (rows, i)
        render ()
        changed ()
      elseif files and field == 'kind' and r.file_name then
        r.file, r.file_name = nil, nil
        render ()
        changed ()
      elseif files and (field == 'kind' or field == 'pick') then
        local row = r
        local pick = files.pick
        pick (row, function ()
          render ()
          changed ()
        end)
      end
      return nil
    end)

    return { el = el, render = render }
  end

  local params_grid = kv_grid (function ()
    return ctx.current and ctx.current.req.params or {}
  end, function ()
    local doc = ctx.current
    if doc then
      doc.req.url = http.url_with_params (doc.req.url, doc.req.params)
      url_in:value (doc.req.url)
      touch ()
    end
  end)
  local headers_grid = kv_grid (function ()
    return ctx.current and ctx.current.req.headers or {}
  end, touch)

  ---Asks the user for a file in the system's dialog. `done` gets the one picked.
  ---@param heading string
  ---@param done fun(grant: Proteus.FileGrant)
  local function pick_file (heading, done)
    local ok, err = pcall (
      app.grants.open,
      { title = heading },
      function (picked, why)
        if why then
          complain ('Could not show the file picker. ' .. why)
        elseif picked and picked[1] then
          done (picked[1])
        end
      end
    )
    if not ok then
      complain ('Could not show the file picker. ' .. tostring (err))
    end
  end

  local form_grid = kv_grid (
    function ()
      return ctx.current and ctx.current.req.form or {}
    end,
    touch,
    {
      on = function ()
        return ctx.current ~= nil and ctx.current.req.body_mode == 'multipart'
      end,
      pick = function (row, done)
        local key = row.key ~= '' and row.key or 'the form'
        pick_file ('File for ' .. key, function (grant)
          row.file = grant.id
          row.file_name = grant.name
          done ()
        end)
      end,
    }
  )

  local body_modes = ui.div ({ class = 'api-modes' })
  local format_btn = ui.button ({
    'Format',
    icon = 'wand-sparkles',
    variant = 'ghost',
    class = 'api-small',
    title = 'Lay the JSON out with indents',
  })
  local body_code ---@type Proteus.El
  body_code = ui.widget ('code', {
    language = 'json',
    text = '',
    on_change = function ()
      local doc = ctx.current
      if doc then
        doc.req.body = body_code:widget ('get_text')
        touch ()
      end
    end,
  })
  local body_host = ui.div ({ class = 'api-code', body_code })
  local body_none =
    ui.div ({ class = 'api-note', 'This request sends no body.' })

  -- GraphQL: the query goes in the body editor, and its variables here.
  -- The controls of the newer body modes, sign-ins and options, in tables of their own,
  -- since a Lua function holds at most 200 locals.
  local bx = {} ---@type table<string, Proteus.El>
  local au = {} ---@type table<string, Proteus.El>
  local op = {} ---@type table<string, Proteus.El>

  bx.vars_code = ui.widget ('code', {
    language = 'json',
    text = '',
    on_change = function ()
      local doc = ctx.current
      if doc then
        doc.req.variables = bx.vars_code:widget ('get_text')
        touch ()
      end
    end,
  })
  bx.vars_box = ui.div ({
    class = 'api-part',
    ui.span ({ class = 'api-label', 'Variables, as one JSON object' }),
    ui.div ({ class = 'api-code vars', bx.vars_code }),
  })

  -- File: the whole body is one file the user picks.
  bx.file_label = ui.span ({ class = 'api-file-name' })
  bx.file_pick = ui.button ({
    'Pick File…',
    icon = 'paperclip',
    class = 'api-small',
  })
  bx.file_box = ui.div ({
    class = 'api-part',
    ui.div ({ class = 'api-filebox', bx.file_pick, bx.file_label }),
    ui.div ({
      class = 'api-note',
      'The file goes out as it is. Its Content-Type comes from its name unless a header sets one.',
    }),
  })

  local auth_modes = ui.div ({ class = 'api-modes' })
  local token_in = ui.input ({
    class = 'api-mono',
    placeholder = 'The token, or {{token}}',
    spellcheck = false,
  })
  local user_in = ui.input ({
    class = 'api-mono',
    placeholder = 'User name',
    spellcheck = false,
  })
  local pass_in = ui.input ({
    class = 'api-mono',
    placeholder = 'Password',
    type = 'password',
    spellcheck = false,
  })
  local pass_eye = ui.button ({
    variant = 'ghost',
    class = 'api-small',
    title = 'Show or hide the password',
    icon = 'eye',
  })
  local bearer_box = ui.div ({
    class = 'api-fields',
    ui.label ({ class = 'api-field', ui.span ({ 'Token' }), token_in }),
    ui.div ({
      class = 'api-note',
      'It goes out as the header "Authorization: Bearer" and the token.',
    }),
  })
  au.basic_note = ui.div ({ class = 'api-note' })
  local basic_box = ui.div ({
    class = 'api-fields',
    ui.label ({ class = 'api-field', ui.span ({ 'User name' }), user_in }),
    ui.div ({
      class = 'api-field',
      ui.span ({ 'Password' }),
      ui.div ({ class = 'api-pass', pass_in, pass_eye }),
    }),
    au.basic_note,
  })

  ---@param placeholder string
  ---@param secret? boolean
  ---@return Proteus.El
  local function field_input (placeholder, secret)
    return ui.input ({
      class = 'api-mono',
      placeholder = placeholder,
      type = secret and 'password' or nil,
      spellcheck = false,
    })
  end
  au.key_in = field_input ('Such as X-Api-Key')
  au.key_value_in = field_input ('The key, or {{api_key}}', true)
  au.place_seg = ui.div ({ class = 'api-seg' })
  au.apikey_box = ui.div ({
    class = 'api-fields',
    ui.label ({ class = 'api-field', ui.span ({ 'Name' }), au.key_in }),
    ui.label ({ class = 'api-field', ui.span ({ 'Key' }), au.key_value_in }),
    ui.div ({
      class = 'api-field',
      ui.span ({ 'Send it as' }),
      ui.div ({ class = 'api-inline', au.place_seg }),
    }),
  })

  au.grant_seg = ui.div ({ class = 'api-seg' })
  au.token_url_in = field_input ('https://auth.example.com/oauth/token')
  au.client_id_in = field_input ('Client id, or {{client_id}}')
  au.client_secret_in =
    field_input ('Client secret, or {{client_secret}}', true)
  au.scope_in = field_input ('Such as read write. Can stay empty.')
  au.oauth_user_in = field_input ('User name')
  au.oauth_pass_in = field_input ('Password', true)
  au.oauth_user_box = ui.div ({
    class = 'api-fields',
    ui.label ({
      class = 'api-field',
      ui.span ({ 'User name' }),
      au.oauth_user_in,
    }),
    ui.label ({
      class = 'api-field',
      ui.span ({ 'Password' }),
      au.oauth_pass_in,
    }),
  })
  au.token_state = ui.span ({ class = 'api-note' })
  au.token_btn = ui.button ({
    'Get New Token',
    icon = 'key-round',
    class = 'api-small',
  })
  au.oauth_box = ui.div ({
    class = 'api-fields',
    ui.div ({
      class = 'api-field',
      ui.span ({ 'Grant' }),
      ui.div ({ class = 'api-inline', au.grant_seg }),
    }),
    ui.label ({
      class = 'api-field',
      ui.span ({ 'Token address' }),
      au.token_url_in,
    }),
    ui.label ({
      class = 'api-field',
      ui.span ({ 'Client id' }),
      au.client_id_in,
    }),
    ui.label ({
      class = 'api-field',
      ui.span ({ 'Client secret' }),
      au.client_secret_in,
    }),
    ui.label ({ class = 'api-field', ui.span ({ 'Scope' }), au.scope_in }),
    au.oauth_user_box,
    ui.div ({ class = 'api-inline', au.token_btn, au.token_state }),
    ui.div ({
      class = 'api-note',
      'Send asks for a token the first time and keeps it until it runs out. The token stays in memory and never goes in the file.',
    }),
  })

  au.inherit_note = ui.div ({ class = 'api-note' })
  au.inherit_edit = ui.button ({
    'Edit Folder Sign-in',
    icon = 'folder-key',
    class = 'api-small',
  })
  au.inherit_box = ui.div ({
    class = 'api-fields',
    au.inherit_note,
    ui.div ({ class = 'api-inline', au.inherit_edit }),
  })
  local auth_none = ui.div ({
    class = 'api-note',
    'This request sends no Authorization header.',
  })

  -- Options: the time limit and redirects.
  op.timeout_in = ui.input ({
    class = 'api-mono api-num',
    placeholder = '30',
    spellcheck = false,
  })
  op.timeout_note = ui.span ({ class = 'api-note' })
  op.redirects_in = ui.h ('input', { attrs = { type = 'checkbox' } })
  op.options_box = ui.div ({
    class = 'api-fields',
    ui.div ({
      class = 'api-field',
      ui.span ({ 'Wait for the answer, in seconds' }),
      ui.div ({ class = 'api-inline', op.timeout_in, op.timeout_note }),
    }),
    ui.label ({
      class = 'api-check',
      op.redirects_in,
      ui.span ({ 'Follow redirects' }),
    }),
    ui.div ({
      class = 'api-note',
      'When redirects are not followed, the redirect itself is the answer, so its Location header shows.',
    }),
  })

  local panes = {
    params = ui.div ({
      class = 'api-part',
      params_grid.el,
      ui.div ({
        class = 'api-note',
        'These rows and the query in the address stay in step.',
      }),
    }),
    headers = ui.div ({ class = 'api-part', headers_grid.el }),
    body = ui.div ({
      class = 'api-part fill',
      ui.div ({
        class = 'api-modes-row',
        body_modes,
        ui.span ({ class = 'api-grow' }),
        format_btn,
      }),
      body_host,
      bx.vars_box,
      bx.file_box,
      form_grid.el,
      body_none,
    }),
    auth = ui.div ({
      class = 'api-part',
      auth_modes,
      au.inherit_box,
      bearer_box,
      basic_box,
      au.apikey_box,
      au.oauth_box,
      auth_none,
    }),
    options = ui.div ({ class = 'api-part', op.options_box }),
  } ---@type table<string, Proteus.El>
  local pane_box = ui.div ({
    class = 'api-pane',
    panes.params,
    panes.headers,
    panes.body,
    panes.auth,
    panes.options,
  })

  -- Drawing the editor ------------------------------------------------------------------

  local function render_head ()
    local doc = ctx.current
    if not doc then
      return
    end
    if doc.folder_auth then
      title:text (
        'Sign-in for ' .. (doc.folder ~= '' and doc.folder or 'every request')
      )
      title:class ('untitled', false)
      where:text ('requests set to From folder use it')
    else
      title:text (doc.req.name ~= '' and doc.req.name or 'Untitled')
      title:class ('untitled', doc.req.name == '')
      where:text (doc.folder ~= '' and ('in ' .. doc.folder) or '')
    end
    head_dot:show (doc.dirty)
    if ctx.tab then
      ctx.tab.set_dirty (doc.dirty)
    end
  end

  local function paint_method ()
    local meth = ctx.current and ctx.current.req.method or 'GET'
    method_sel:set ('className', 'api-method api-m-' .. meth:lower ())
  end

  ---@param n integer
  ---@return string
  local function count_html (n)
    return n > 0 and ('<span class="api-count">' .. n .. '</span>') or ''
  end

  local function render_tabs ()
    local doc = ctx.current
    if not doc then
      return
    end
    local req = doc.req
    local mark = '<span class="api-mark"></span>'
    local body_extra = ''
    if req.body_mode == 'form' or req.body_mode == 'multipart' then
      body_extra = count_html (http.count_rows (req.form))
    elseif req.body_mode ~= 'none' then
      body_extra = mark
    end
    ---@type { [1]: string, [2]: string, [3]: string }[]
    local list = {
      { 'params', 'Params', count_html (http.count_rows (req.params)) },
      { 'headers', 'Headers', count_html (http.count_rows (req.headers)) },
      { 'body', 'Body', body_extra },
      { 'auth', 'Auth', req.auth.mode ~= 'none' and mark or '' },
      {
        'options',
        'Options',
        (req.timeout > 0 or not req.redirects) and mark or '',
      },
    }
    if doc.folder_auth then
      list = { { 'auth', 'Auth', '' } }
    end
    local parts = {} ---@type string[]
    for _, t in ipairs (list) do
      parts[#parts + 1] = '<button class="api-tab'
        .. ((pane == t[1] or doc.folder_auth) and ' on' or '')
        .. '" data-item="'
        .. t[1]
        .. '">'
        .. t[2]
        .. t[3]
        .. '</button>'
    end
    req_tabs:html (table.concat (parts))
  end

  local function show_pane ()
    local shown = ctx.current and ctx.current.folder_auth and 'auth' or pane
    for id, el in pairs (panes) do
      el:show (id == shown)
    end
  end

  ---@param box Proteus.El
  ---@param options { [1]: string, [2]: string }[]
  ---@param active string
  local function render_modes (box, options, active)
    local parts = {} ---@type string[]
    for _, o in ipairs (options) do
      parts[#parts + 1] = '<button class="api-mode'
        .. (o[1] == active and ' on' or '')
        .. '" data-item="'
        .. o[1]
        .. '">'
        .. esc (o[2])
        .. '</button>'
    end
    box:html (table.concat (parts))
  end

  ---@param box Proteus.El
  ---@param options { [1]: string, [2]: string }[]
  ---@param active string
  local function render_seg (box, options, active)
    local parts = {} ---@type string[]
    for _, o in ipairs (options) do
      parts[#parts + 1] = '<button class="'
        .. (o[1] == active and 'on' or '')
        .. '" data-item="'
        .. o[1]
        .. '">'
        .. esc (o[2])
        .. '</button>'
    end
    box:html (table.concat (parts))
  end

  local function render_body ()
    local doc = ctx.current
    if not doc then
      return
    end
    local mode = doc.req.body_mode
    render_modes (body_modes, BODY_OPTIONS, mode)
    format_btn:show (mode == 'json')
    body_host:show (mode == 'json' or mode == 'text' or mode == 'graphql')
    bx.vars_box:show (mode == 'graphql')
    bx.file_box:show (mode == 'file')
    form_grid.el:show (mode == 'form' or mode == 'multipart')
    body_none:show (mode == 'none')
    local f = doc.req.file
    local need = f.id == ''
    bx.file_label:text (
      need
          and (f.name ~= '' and (f.name .. ': pick it to send') or 'No file picked')
        or f.name
    )
    bx.file_label:class ('need', need)
    bx.file_pick:html (
      icon ('paperclip')
        .. '<span>'
        .. (need and 'Pick File…' or 'Pick Another…')
        .. '</span>'
    )
  end

  ---Tokens got for OAuth 2 sign-ins, by `http.oauth_key`. They stay in memory only.
  local tokens = {} ---@type table<string, ApiApp.Token>

  ---@param auth Http.Auth
  ---@return string
  local function token_key (auth)
    return http.oauth_key (auth, http.env_vars (ctx.envs))
  end

  local function render_token ()
    local doc = ctx.current
    if not doc or doc.req.auth.mode ~= 'oauth2' then
      return
    end
    local kept = tokens[token_key (doc.req.auth)]
    local now = app.util.now ()
    if kept and core.token_fresh (kept, now) then
      au.token_state:text (
        kept.ends
            and ('A token is kept until ' .. os.date (
              '%H:%M',
              math.floor (kept.ends / 1000)
            ) .. '.')
          or 'A token is kept.'
      )
    else
      au.token_state:text ('No token yet.')
    end
  end

  local function render_auth ()
    local doc = ctx.current
    if not doc then
      return
    end
    local auth = doc.req.auth
    local mode = auth.mode
    render_modes (
      auth_modes,
      doc.folder_auth and FOLDER_AUTH_OPTIONS or AUTH_OPTIONS,
      mode
    )
    au.inherit_box:show (mode == 'inherit')
    bearer_box:show (mode == 'bearer')
    basic_box:show (mode == 'basic' or mode == 'digest')
    au.basic_note:text (
      mode == 'digest'
          and 'The first answer asks for Digest, and the request goes again with the answer to its challenge.'
        or ''
    )
    au.basic_note:show (mode == 'digest')
    au.apikey_box:show (mode == 'apikey')
    au.oauth_box:show (mode == 'oauth2')
    auth_none:show (mode == 'none')
    render_seg (au.place_seg, {
      { 'header', 'Header' },
      { 'query', 'Query parameter' },
    }, auth.place)
    render_seg (au.grant_seg, {
      { 'client_credentials', 'Client credentials' },
      { 'password', 'Password' },
    }, auth.grant)
    au.oauth_user_box:show (auth.grant == 'password')
    render_token ()
    if mode == 'inherit' then
      local got, from = effective_auth (doc)
      local label = got.mode ---@type string
      for _, o in ipairs (AUTH_OPTIONS) do
        if o[1] == got.mode then
          label = o[2]
        end
      end
      if got.mode == 'none' then
        au.inherit_note:text (
          'No folder around this one has a sign-in, so it sends none.'
        )
      else
        au.inherit_note:text (
          'It uses '
            .. label
            .. ' from '
            .. (from == '' and 'the top folder' or ('the folder ' .. tostring (
              from
            )))
            .. '.'
        )
      end
    end
  end

  local function render_options ()
    local doc = ctx.current
    if not doc then
      return
    end
    op.timeout_note:text (
      doc.req.timeout > 0 and '' or 'Empty waits 30 seconds.'
    )
    op.redirects_in:set ('checked', doc.req.redirects)
  end

  local function render_send ()
    local waiting = ctx.current ~= nil and ctx.current.pending ~= nil
    send_btn:html (
      icon (waiting and 'x' or 'send')
        .. '<span>'
        .. (waiting and 'Cancel' or 'Send')
        .. '</span>'
    )
    send_btn:class ('primary', not waiting)
    send_btn:set (
      'title',
      waiting and 'Stop the request' or 'Send the request (Ctrl+Enter)'
    )
  end

  local function fill_editor ()
    local doc = ctx.current
    ctx.editor:show (doc ~= nil)
    ctx.none:show (doc == nil)
    render_status ()
    if not doc then
      if ctx.tab then
        ctx.tab.set_dirty (false)
      end
      return
    end
    local req = doc.req
    -- A folder's sign-in has nothing to send, so only the Auth tab shows.
    line:show (not doc.folder_auth)
    ctx.split:show (not doc.folder_auth)
    ctx.bottom:show (not doc.folder_auth)
    method_sel:value (req.method)
    paint_method ()
    url_in:value (req.url)
    body_code:widget ('set_text', req.body)
    body_code:widget (
      'set_language',
      req.body_mode == 'json' and 'json' or 'text'
    )
    bx.vars_code:widget ('set_text', req.variables)
    local a = req.auth
    token_in:value (a.token)
    user_in:value (a.user)
    pass_in:value (a.password)
    au.key_in:value (a.key)
    au.key_value_in:value (a.value)
    au.token_url_in:value (a.token_url)
    au.client_id_in:value (a.client_id)
    au.client_secret_in:value (a.client_secret)
    au.scope_in:value (a.scope)
    au.oauth_user_in:value (a.user)
    au.oauth_pass_in:value (a.password)
    op.timeout_in:value (core.timeout_text (req.timeout))
    params_grid.render ()
    headers_grid.render ()
    form_grid.render ()
    render_body ()
    render_auth ()
    render_options ()
    show_pane ()
    render_tabs ()
    render_head ()
    render_send ()
    ctx.render_response ()
  end

  ---@param doc ApiApp.Doc?
  local function show (doc)
    ctx.current = doc
    fill_editor ()
    ctx.render_list ()
    schedule_drafts ()
  end

  -- Editing -----------------------------------------------------------------------------

  method_sel:on ('change', function (ev)
    local doc = ctx.current
    if doc and ev.value then
      doc.req.method = ev.value
      paint_method ()
      touch ()
      schedule_list ()
    end
    return nil
  end)

  url_in:on ('input', function (ev)
    local doc = ctx.current
    if doc then
      doc.req.url = ev.value or ''
      doc.req.params = http.sync_params (doc.req.params, doc.req.url)
      params_grid.render ()
      touch ()
    end
    return nil
  end)

  req_tabs:on ('click', function (ev)
    if
      ev.item
      and panes[ev.item]
      and not (ctx.current and ctx.current.folder_auth)
    then
      pane = ev.item
      app.store.set ('pane', pane)
      show_pane ()
      render_tabs ()
    end
    return nil
  end)

  body_modes:on ('click', function (ev)
    local doc = ctx.current
    local mode = ev.item
    if doc and mode and mode ~= doc.req.body_mode then
      doc.req.body_mode = mode --[[@as Http.BodyMode]]
      body_code:widget ('set_language', mode == 'json' and 'json' or 'text')
      render_body ()
      touch ()
    end
    return nil
  end)

  auth_modes:on ('click', function (ev)
    local doc = ctx.current
    local mode = ev.item
    if doc and mode and mode ~= doc.req.auth.mode then
      doc.req.auth.mode = mode --[[@as Http.AuthMode]]
      render_auth ()
      touch ()
    end
    return nil
  end)

  ---@param el Proteus.El
  ---@param set fun(auth: Http.Auth, text: string)
  local function auth_field (el, set)
    el:on ('input', function (ev)
      local doc = ctx.current
      if doc then
        set (doc.req.auth, ev.value or '')
        touch ()
      end
      return nil
    end)
  end
  auth_field (token_in, function (auth, text)
    auth.token = text
  end)
  auth_field (user_in, function (auth, text)
    auth.user = text
  end)
  auth_field (pass_in, function (auth, text)
    auth.password = text
  end)
  auth_field (au.key_in, function (auth, text)
    auth.key = text
  end)
  auth_field (au.key_value_in, function (auth, text)
    auth.value = text
  end)
  auth_field (au.token_url_in, function (auth, text)
    auth.token_url = text
  end)
  auth_field (au.client_id_in, function (auth, text)
    auth.client_id = text
  end)
  auth_field (au.client_secret_in, function (auth, text)
    auth.client_secret = text
  end)
  auth_field (au.scope_in, function (auth, text)
    auth.scope = text
  end)
  auth_field (au.oauth_user_in, function (auth, text)
    auth.user = text
  end)
  auth_field (au.oauth_pass_in, function (auth, text)
    auth.password = text
  end)

  au.place_seg:on ('click', function (ev)
    local doc = ctx.current
    if doc and (ev.item == 'header' or ev.item == 'query') then
      doc.req.auth.place = ev.item --[[@as 'header'|'query']]
      render_auth ()
      touch ()
    end
    return nil
  end)
  au.grant_seg:on ('click', function (ev)
    local doc = ctx.current
    if doc and (ev.item == 'client_credentials' or ev.item == 'password') then
      doc.req.auth.grant = ev.item --[[@as 'client_credentials'|'password']]
      render_auth ()
      touch ()
    end
    return nil
  end)

  bx.file_pick:on ('click', function ()
    local doc = ctx.current
    if not doc then
      return nil
    end
    pick_file ('File to send', function (grant)
      doc.req.file = { id = grant.id, name = grant.name }
      if doc == ctx.current then
        render_body ()
      end
      touch ()
    end)
    return nil
  end)

  op.timeout_in:on ('input', function (ev)
    local doc = ctx.current
    if not doc then
      return nil
    end
    local seconds = core.parse_timeout (ev.value or '')
    if seconds then
      doc.req.timeout = seconds
      render_options ()
      render_tabs ()
      touch ()
    else
      op.timeout_note:text ('Type a number of seconds, up to 3600.')
    end
    return nil
  end)
  op.redirects_in:on ('change', function (ev)
    local doc = ctx.current
    if doc then
      doc.req.redirects = ev.checked == true
      render_tabs ()
      touch ()
    end
    return nil
  end)

  local pass_shown = false
  pass_eye:on ('click', function ()
    pass_shown = not pass_shown
    pass_in:set ('type', pass_shown and 'text' or 'password')
    pass_eye:html (icon (pass_shown and 'eye-off' or 'eye', 16))
    return nil
  end)

  local function format_body ()
    local doc = ctx.current
    if not doc then
      return
    end
    local pretty, err = http.pretty_json (body_code:widget ('get_text'))
    if not pretty then
      complain ('The body is not valid JSON. ' .. tostring (err))
      return
    end
    -- The text changes in one edit, so Ctrl+Z brings the old layout back. The change
    -- handler stores the new text.
    body_code:widget ('replace_text', pretty)
  end
  format_btn:on ('click', function ()
    format_body ()
    return nil
  end)

  ctx.au = au
  ctx.url_in = url_in
  ctx.send_btn = send_btn
  ctx.head = head
  ctx.line = line
  ctx.req_tabs = req_tabs
  ctx.pane_box = pane_box
  ctx.tokens = tokens
  ctx.token_key = token_key
  ctx.count_html = count_html
  ctx.render_head = render_head
  ctx.render_tabs = render_tabs
  ctx.render_token = render_token
  ctx.render_auth = render_auth
  ctx.render_send = render_send
  ctx.fill_editor = fill_editor
  ctx.show = show
  ctx.format_body = format_body
end

return M
