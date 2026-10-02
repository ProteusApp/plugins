-- proteus.api: an API client that sends HTTP requests, saves them, and shows the answers.
--
-- Requests go out through app.net.fetch, which runs in Rust in the desktop app, so any address
-- works. Each saved request is a JSON file in data/proteus.api/, so the editor profile can open
-- it too, and data/proteus.api/environments.json holds the values for {{variables}}. The logic
-- that needs no screen comes from the `http` service in proteus.lib.http.
--
-- New requests and unsaved changes stay in memory and in app.store, so a reload keeps them.
-- A folder's .folder.json holds the sign-in its requests inherit. Files go by the ids
-- app.grants.open gives, so the client needs no `files` permission. The parts that need no
-- screen are in api_core.lua, where the tests reach them.

local CSS = require ('api_css') --[[@as string]]
local core = require ('api_core') --[[@as ApiApp.Core]]

local DIR = 'data/proteus.api'
local ENV_PATH = DIR .. '/environments.json'
local HISTORY_MAX = 50
-- A longer answer shows as it came, since formatting it would hold up the window.
local PRETTY_MAX = 3 * 1024 * 1024
-- How much of a binary answer shows as hex.
local HEX_MAX = 4096

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

---A request open in the editor. A saved one is keyed by its path, a new one by `new:<n>`.
---@class ApiApp.Doc
---@field key string
---@field path? string
---@field folder string Where Save puts a new request, under data/proteus.api.
---@field req Http.Request
---@field saved string The file text as last read or written. Empty for a new request.
---@field dirty boolean
---@field result? ApiApp.Result
---@field pending? integer The number of the send that is out, if any.
---@field call? Proteus.HttpCall The request that is out, which Cancel stops.
---@field warning? string What to say about the send that is out, such as a missing variable.
---@field folder_auth? boolean True for a folder's sign-in, which has only the Auth tab.

---A key and value table drawn as one HTML string.
---@class ApiApp.Grid
---@field el Proteus.El
---@field render fun()

---How a key and value grid lets its rows send files.
---@class ApiApp.FileRows
---@field on fun(): boolean True while the rows may send files.
---@field pick fun(row: Http.Row, done: fun()) Asks for a file for the row.

---What the list needs from a saved file, kept until the file changes.
---@class ApiApp.FileInfo
---@field method string
---@field url string

---@type Proteus.Plugin
return {
  name = 'API Client',
  description = 'Send HTTP requests, save them, and read the answers.',
  version = '1.2.1',
  requires = {
    proteus = '>=0.3.0',
    features = { 'permissions', 'grants', 'grants-read', 'http-bodies' },
  },
  -- It sends the requests the user writes, to any address. Files to send and collections to
  -- import come from the system's dialog, by grant, so it needs no `files`.
  permissions = { 'net' },
  depends = {
    'proteus.lib.ui',
    'proteus.lib.http',
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
    local http = app.use ('http')
    local views = app.use ('views')
    local commands = app.use ('commands')
    local status = app.try_use ('status')
    local notify = app.try_use ('notify')
    local picker = app.try_use ('picker')
    local menus = app.try_use ('menus')
    local toolbar = app.try_use ('toolbar')
    local tabs = app.try_use ('tabs')
    local esc = app.util.escape
    local browser = app.platform == 'browser'
    ui.css (CSS)

    ---@param name string
    ---@param size? integer
    ---@return string
    local function icon (name, size)
      return app.util.icon (name, size or 14) or ''
    end

    ---@param text string
    local function say (text)
      if notify then
        notify.info (text, { timeout = 2500 })
      end
    end

    ---@param text string
    local function complain (text)
      if notify then
        notify.error (text)
      else
        app.warn (text)
      end
    end

    -- State -------------------------------------------------------------------------------

    local docs = {} ---@type table<string, ApiApp.Doc>
    local fresh = {} ---@type string[] Keys of new requests, oldest first.
    local current = nil ---@type ApiApp.Doc?
    local new_count = 0
    local send_count = 0
    local writing = 0
    local query = ''
    local saved_count = 0
    local folded = app.store.get ('folded', {}) ---@type table<string, boolean>
    local pane = app.store.get ('pane', 'params') ---@type string
    local res_view = app.store.get ('res_view', 'body') ---@type string
    local raw = app.store.get ('raw', false) == true
    local top_px = app.store.get ('split', nil) ---@type number?
    local envs = assert (http.parse_envs (nil))
    local env_problem = nil ---@type string?
    local history = {} ---@type Http.HistoryEntry[]
    local file_cache = {} ---@type table<string, ApiApp.FileInfo>
    local list_timer = nil ---@type fun()?
    local drafts_timer = nil ---@type fun()?
    local tab = nil ---@type Proteus.Tab?

    local render_list ---@type fun()
    local render_history ---@type fun()
    local render_head ---@type fun()
    local render_tabs ---@type fun()
    local render_env ---@type fun()
    local fill_editor ---@type fun()
    local show ---@type fun(doc: ApiApp.Doc?)

    -- Files -------------------------------------------------------------------------------

    local stem = core.stem

    ---@param path string A file or folder under data/proteus.api.
    ---@return string
    local function folder_of (path)
      return core.folder_of (DIR, path)
    end

    ---@param folder string
    ---@param name string
    ---@return string
    local function path_for (folder, name)
      return core.path_for (DIR, folder, name)
    end

    ---@param path string
    ---@return Http.Request?
    ---@return string?
    local function read_request (path)
      local text = app.fs.read (path)
      if not text then
        return nil, 'The file is gone.'
      end
      local data, err = http.json_decode (text)
      if err then
        return nil, err
      end
      local req = http.normalize (data)
      req.name = stem (path)
      return req, nil
    end

    -- Changes this plugin makes to its own files raise change events, which the handler below
    -- skips while this count is above zero.
    ---@param what string
    ---@param fn fun()
    ---@return boolean
    local function change_files (what, fn)
      writing = writing + 1
      local ok, err = pcall (fn)
      writing = writing - 1
      if not ok then
        complain (what .. '. ' .. tostring (err))
      end
      return ok
    end

    local function load_envs ()
      local parsed, err = http.parse_envs (app.fs.read (ENV_PATH))
      if parsed then
        envs = parsed
        env_problem = nil
      else
        envs = assert (http.parse_envs (nil))
        env_problem = err
      end
      render_env ()
    end

    -- Open requests -----------------------------------------------------------------------

    ---@param path string
    ---@return ApiApp.Doc?
    local function doc_at (path)
      local doc = docs[path]
      if doc then
        return doc
      end
      local req, err = read_request (path)
      if not req then
        complain ('Could not read "' .. stem (path) .. '". ' .. tostring (err))
        return nil
      end
      doc = {
        key = path,
        path = path,
        folder = folder_of (path),
        req = req,
        saved = http.encode_request (req),
        dirty = false,
      }
      docs[path] = doc
      return doc
    end

    ---@param req Http.Request
    ---@param folder string
    ---@return ApiApp.Doc
    local function add_new (req, folder)
      new_count = new_count + 1
      local doc = {
        key = 'new:' .. new_count,
        folder = folder,
        req = req,
        saved = '',
        dirty = true,
      } ---@type ApiApp.Doc
      docs[doc.key] = doc
      fresh[#fresh + 1] = doc.key
      return doc
    end

    ---@param doc ApiApp.Doc
    local function forget (doc)
      docs[doc.key] = nil
      for i, key in ipairs (fresh) do
        if key == doc.key then
          table.remove (fresh, i)
          break
        end
      end
    end

    local function save_drafts ()
      drafts_timer = nil
      local list = {} ---@type table[]
      local last_new = 0
      for _, key in ipairs (fresh) do
        local doc = docs[key]
        if doc then
          list[#list + 1] = { folder = doc.folder, req = doc.req }
          if doc == current then
            last_new = #list
          end
        end
      end
      -- A folder's sign-in that was not saved is not kept.
      for _, doc in pairs (docs) do
        if doc.path and doc.dirty and not doc.folder_auth then
          list[#list + 1] = { path = doc.path, req = doc.req }
        end
      end
      app.store.set ('drafts', list)
      app.store.set (
        'last',
        current and not current.folder_auth and current.path or nil
      )
      app.store.set ('last_new', last_new)
    end

    local function schedule_drafts ()
      if not drafts_timer then
        drafts_timer = app.timer.after (400, save_drafts)
      end
    end

    local function schedule_list ()
      if not list_timer then
        list_timer = app.timer.after (40, function ()
          list_timer = nil
          render_list ()
        end)
      end
    end

    ---The text a doc's file holds: a request, or a folder's sign-in.
    ---@param doc ApiApp.Doc
    ---@return string
    local function doc_text (doc)
      if doc.folder_auth then
        return http.encode_folder (doc.req.auth)
      end
      return http.encode_request (doc.req)
    end

    ---Marks the open request changed, and works out whether it differs from its file.
    local function touch ()
      local doc = current
      if not doc then
        return
      end
      local was = doc.dirty
      doc.dirty = doc.path == nil or doc_text (doc) ~= doc.saved
      render_head ()
      render_tabs ()
      if was ~= doc.dirty then
        schedule_list ()
      end
      schedule_drafts ()
    end

    -- The request editor ------------------------------------------------------------------

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
      return current and current.req.params or {}
    end, function ()
      local doc = current
      if doc then
        doc.req.url = http.url_with_params (doc.req.url, doc.req.params)
        url_in:value (doc.req.url)
        touch ()
      end
    end)
    local headers_grid = kv_grid (function ()
      return current and current.req.headers or {}
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
        return current and current.req.form or {}
      end,
      touch,
      {
        on = function ()
          return current ~= nil and current.req.body_mode == 'multipart'
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
        local doc = current
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
        local doc = current
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

    -- The response ------------------------------------------------------------------------

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

    -- The whole main area -----------------------------------------------------------------

    local top = ui.div ({ class = 'api-top', head, line, req_tabs, pane_box })
    local split = ui.div ({ class = 'api-split', title = 'Drag to resize' })
    local bottom = ui.div ({ class = 'api-bottom', sum, warn, res_box })
    local editor = ui.div ({ class = 'api-editor', top, split, bottom })
    if type (top_px) == 'number' then
      editor:style ('--api-top', math.floor (top_px) .. 'px')
    end

    local none_new = ui.button ({
      'New Request',
      icon = 'file-plus',
      variant = 'primary',
    })
    local none_import = ui.button ({ 'Import curl', icon = 'terminal' })
    local none_collection =
      ui.button ({ 'Import Collection…', icon = 'import' })
    local none = ui.div ({
      class = 'api-none',
      ui.div ({
        class = 'api-none-card',
        ui.icon ('send', 28),
        ui.div ({ class = 'api-none-title', 'No request open' }),
        ui.div ({ 'Make a new request, or pick a saved one on the left.' }),
        ui.div ({ class = 'ui-row', none_new, none_import, none_collection }),
      }),
    })

    local root = ui.div ({
      class = 'api',
      editor,
      none,
    })

    -- Status bar --------------------------------------------------------------------------

    local st_count = status
      and status.add ({
        id = 'api.count',
        text = '',
        icon = 'folder',
        align = 'left',
        order = 10,
      })
    local st_result = status
      and status.add ({
        id = 'api.result',
        text = '',
        align = 'right',
        order = 10,
      })

    local function render_status ()
      if not st_result then
        return
      end
      local doc = current
      local r = doc and doc.result
      if doc and doc.pending then
        st_result.set ('Sending…')
      elseif r and r.status then
        st_result.set (
          http.status_line (r.status)
            .. ' · '
            .. http.format_ms (r.ms)
            .. ' · '
            .. http.human_size (r.size)
        )
      elseif r and r.error then
        st_result.set ('No answer')
      else
        st_result.set ('')
      end
    end

    -- Folder sign-ins ---------------------------------------------------------------------

    ---The sign-ins of a folder and the folders around it, from the folder itself outward.
    ---@param folder string A path under data/proteus.api, or '' for the top.
    ---@return Http.Auth[]
    ---@return string[] names Each folder's name as the list shows it, '' for the top.
    local function folder_auths (folder)
      local out = {} ---@type Http.Auth[]
      local names = {} ---@type string[]
      for _, path in ipairs (core.folder_files (DIR, folder)) do
        out[#out + 1] = http.parse_folder (app.fs.read (path))
        names[#names + 1] = core.folder_of_file (DIR, path)
      end
      return out, names
    end

    ---The folder a folder's sign-in hands down to, for a folder doc: the folder around it.
    ---@param doc ApiApp.Doc
    ---@return string
    local function chain_start (doc)
      if doc.folder_auth then
        return doc.folder:match ('^(.*)/[^/]*$') or ''
      end
      return doc.folder
    end

    ---The sign-in a request uses, and the folder it comes from when it is inherited.
    ---@param doc ApiApp.Doc
    ---@return Http.Auth
    ---@return string? from
    local function effective_auth (doc)
      if doc.req.auth.mode ~= 'inherit' then
        return doc.req.auth, nil
      end
      local auths, names = folder_auths (chain_start (doc))
      if doc.folder_auth and doc.folder == '' then
        auths, names = {}, {}
      end
      local auth, at = http.resolve_auth (doc.req.auth, auths)
      return auth, at and names[at] or nil
    end

    -- Drawing the editor ------------------------------------------------------------------

    render_head = function ()
      local doc = current
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
      if tab then
        tab.set_dirty (doc.dirty)
      end
    end

    local function paint_method ()
      local meth = current and current.req.method or 'GET'
      method_sel:set ('className', 'api-method api-m-' .. meth:lower ())
    end

    ---@param n integer
    ---@return string
    local function count_html (n)
      return n > 0 and ('<span class="api-count">' .. n .. '</span>') or ''
    end

    render_tabs = function ()
      local doc = current
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
      local shown = current and current.folder_auth and 'auth' or pane
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
      local doc = current
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
      return http.oauth_key (auth, http.env_vars (envs))
    end

    local function render_token ()
      local doc = current
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
      local doc = current
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
      local doc = current
      if not doc then
        return
      end
      op.timeout_note:text (
        doc.req.timeout > 0 and '' or 'Empty waits 30 seconds.'
      )
      op.redirects_in:set ('checked', doc.req.redirects)
    end

    local function render_send ()
      local waiting = current ~= nil and current.pending ~= nil
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
      local doc = current
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

    fill_editor = function ()
      local doc = current
      editor:show (doc ~= nil)
      none:show (doc == nil)
      render_status ()
      if not doc then
        if tab then
          tab.set_dirty (false)
        end
        return
      end
      local req = doc.req
      -- A folder's sign-in has nothing to send, so only the Auth tab shows.
      line:show (not doc.folder_auth)
      split:show (not doc.folder_auth)
      bottom:show (not doc.folder_auth)
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
      render_response ()
    end

    show = function (doc)
      current = doc
      fill_editor ()
      render_list ()
      schedule_drafts ()
    end

    -- Editing -----------------------------------------------------------------------------

    method_sel:on ('change', function (ev)
      local doc = current
      if doc and ev.value then
        doc.req.method = ev.value
        paint_method ()
        touch ()
        schedule_list ()
      end
      return nil
    end)

    url_in:on ('input', function (ev)
      local doc = current
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
        and not (current and current.folder_auth)
      then
        pane = ev.item
        app.store.set ('pane', pane)
        show_pane ()
        render_tabs ()
      end
      return nil
    end)

    body_modes:on ('click', function (ev)
      local doc = current
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
      local doc = current
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
        local doc = current
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
      local doc = current
      if doc and (ev.item == 'header' or ev.item == 'query') then
        doc.req.auth.place = ev.item --[[@as 'header'|'query']]
        render_auth ()
        touch ()
      end
      return nil
    end)
    au.grant_seg:on ('click', function (ev)
      local doc = current
      if doc and (ev.item == 'client_credentials' or ev.item == 'password') then
        doc.req.auth.grant = ev.item --[[@as 'client_credentials'|'password']]
        render_auth ()
        touch ()
      end
      return nil
    end)

    bx.file_pick:on ('click', function ()
      local doc = current
      if not doc then
        return nil
      end
      pick_file ('File to send', function (grant)
        doc.req.file = { id = grant.id, name = grant.name }
        if doc == current then
          render_body ()
        end
        touch ()
      end)
      return nil
    end)

    op.timeout_in:on ('input', function (ev)
      local doc = current
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
      local doc = current
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
      local doc = current
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

    -- The line between the request and the response drags the same way as the shell's docks.
    split:on ('mousedown', function (ev)
      local start = ev.y or 0
      local from = top:rect ().h
      local total = editor:rect ().h
      local off_move = nil ---@type fun()?
      local off_up = nil ---@type fun()?
      editor:class ('api-dragging', true)
      off_move = app.dom.on_global ('mousemove', function (mv)
        local px =
          math.max (110, math.min (from + (mv.y or start) - start, total - 90))
        top_px = px
        editor:style ('--api-top', math.floor (px) .. 'px')
        return nil
      end)
      off_up = app.dom.on_global ('mouseup', function ()
        if off_move then
          off_move ()
        end
        if off_up then
          off_up ()
        end
        editor:class ('api-dragging', false)
        if top_px then
          app.store.set ('split', top_px)
        end
        return nil
      end)
      return true
    end)

    -- Sending -----------------------------------------------------------------------------

    ---Asks the token address of an OAuth 2 sign-in for a token, and keeps it. `done` gets
    ---the token, or nil and why not. Returns the request, so Cancel can stop it.
    ---@param auth Http.Auth
    ---@param done fun(token: string?, err: string?)
    ---@return Proteus.HttpCall?
    local function get_token (auth, done)
      local request, err = http.oauth_request (auth, http.env_vars (envs))
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
      local doc = current
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
      local env = http.env_vars (envs)
      local auth = effective_auth (doc)
      ---@type Http.BuildContext
      local ctx = { auth = auth }
      local kept = auth.mode == 'oauth2' and tokens[token_key (auth)] or nil
      if kept and core.token_fresh (kept, app.util.now ()) then
        ctx.token = kept.token
      end
      local built = http.build (doc.req, env, ctx)
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
      local warning = http.missing_text (built.missing, envs.active)
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
        history = http.add_history (history, {
          method = built.method,
          url = built.url,
          status = result.status or 0,
          time = app.util.now (),
          request = snapshot,
        }, HISTORY_MAX)
        app.store.set ('history', history)
        render_history ()
        if doc == current then
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

      if auth.mode == 'oauth2' and not ctx.token then
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
      local doc = current
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
      local doc = current
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

    -- Saving and managing requests --------------------------------------------------------

    ---@param doc ApiApp.Doc
    ---@param path string
    ---@return boolean
    local function write_doc (doc, path)
      doc.req.name = stem (path)
      local text = http.encode_request (doc.req)
      if
        not change_files ('Could not save "' .. doc.req.name .. '"', function ()
          app.fs.write (path, text)
        end)
      then
        return false
      end
      if doc.key ~= path then
        forget (doc)
        doc.key = path
        doc.path = path
        doc.folder = folder_of (path)
        docs[path] = doc
      end
      file_cache[path] = nil
      doc.saved = text
      doc.dirty = false
      if doc == current then
        render_head ()
      end
      schedule_list ()
      schedule_drafts ()
      return true
    end

    ---@param doc? ApiApp.Doc
    local function save (doc)
      doc = doc or current
      if not doc then
        return
      end
      if doc.folder_auth and doc.path then
        local folder_doc = doc
        local path = doc.path --[[@as string]]
        local text = http.encode_folder (folder_doc.req.auth)
        if
          change_files ('Could not save the folder sign-in', function ()
            app.fs.write (path, text)
          end)
        then
          folder_doc.saved = text
          folder_doc.dirty = false
          if folder_doc == current then
            render_head ()
          end
          say ('Saved the folder sign-in.')
        end
        return
      end
      local target = doc
      if target.path then
        if write_doc (target, target.path) then
          say ('Saved "' .. target.req.name .. '".')
        end
        return
      end
      local at_top = target.folder == ''
      ---@param text string
      ---@return string?
      local function problem (text)
        local name, err = http.check_name (text, at_top)
        if not name then
          return err
        end
        if app.fs.exists (path_for (target.folder, name)) then
          return 'A request with that name is already there.'
        end
        return nil
      end
      ---@param text string
      local function finish (text)
        local name = http.check_name (text, at_top)
        if name and write_doc (target, path_for (target.folder, name)) then
          say ('Saved "' .. name .. '".')
          render_list ()
        end
      end
      local suggestion = target.req.name ~= '' and target.req.name
        or http.suggest_name (target.req)
      if not picker then
        finish (http.unique_name (suggestion, function (name)
          return app.fs.exists (path_for (target.folder, name))
        end))
        return
      end
      picker.input ({
        prompt = 'Name this request',
        value = suggestion,
        validate = problem,
        on_submit = finish,
      })
    end

    ---@param path string
    local function open_path (path)
      local doc = doc_at (path)
      if doc then
        show (doc)
      end
    end

    ---Opens a folder's sign-in, which its requests set to From folder use.
    ---@param folder string A path under data/proteus.api, or '' for the top.
    local function open_folder_auth (folder)
      local path = core.folder_files (DIR, folder)[1]
      local doc = docs[path]
      if not doc then
        local auth = http.parse_folder (app.fs.read (path))
        local req = http.normalize ({})
        req.auth = auth
        doc = {
          key = path,
          path = path,
          folder = folder,
          req = req,
          saved = http.encode_folder (auth),
          dirty = false,
          folder_auth = true,
        }
        docs[path] = doc
      end
      show (doc)
    end

    au.inherit_edit:on ('click', function ()
      local doc = current
      if doc then
        open_folder_auth (doc.folder)
      end
      return nil
    end)

    ---@param folder string
    local function new_request (folder)
      show (add_new (http.normalize ({}), folder))
      url_in:focus ()
    end

    ---@param doc ApiApp.Doc
    local function copy_curl (doc)
      if doc.folder_auth then
        return
      end
      local auth = effective_auth (doc)
      local kept = auth.mode == 'oauth2' and tokens[token_key (auth)] or nil
      app.system.clipboard (
        http.to_curl (http.build (doc.req, http.env_vars (envs), {
          auth = auth,
          token = kept and kept.token or nil,
        }))
      )
      say ('Copied the request as a curl command.')
    end

    local function import_curl ()
      if not picker then
        return
      end
      picker.input ({
        prompt = 'Paste a curl command',
        placeholder = "curl 'https://example.com' -H 'Accept: application/json'",
        validate = function (text)
          local _, err = http.from_curl (text)
          return err
        end,
        on_submit = function (text)
          local req, _, notes = http.from_curl (text)
          if req then
            show (add_new (req, ''))
            say ('Opened the curl command as a new request.')
            -- What the request leaves out, such as a file the command sends.
            for _, note in ipairs (notes or {}) do
              if notify then
                notify.warn (note)
              else
                app.warn (note)
              end
            end
          end
        end,
      })
    end

    ---Writes what an import read into a folder of its own, with its folder sign-ins, and adds
    ---an environment for its variables.
    ---@param imported Http.Import
    ---@param source string The file's name.
    local function write_import (imported, source)
      local into = http.unique_name (imported.name, function (n)
        return app.fs.exists (DIR .. '/' .. n) or n:lower () == 'environments'
      end)
      local base = DIR .. '/' .. into
      local count = 0
      local wrote = change_files ('Could not import ' .. source, function ()
        for _, f in ipairs (imported.folders) do
          local dir = base .. (f.folder ~= '' and ('/' .. f.folder) or '')
          app.fs.write (
            dir .. '/' .. core.FOLDER_FILE,
            http.encode_folder (f.auth)
          )
        end
        for _, item in ipairs (imported.requests) do
          local dir = base .. (item.folder ~= '' and ('/' .. item.folder) or '')
          local name = http.unique_name (item.request.name, function (n)
            return app.fs.exists (dir .. '/' .. n .. '.json')
          end)
          item.request.name = name
          app.fs.write (
            dir .. '/' .. name .. '.json',
            http.encode_request (item.request)
          )
          count = count + 1
        end
      end)
      if not wrote then
        render_list ()
        return
      end
      local notes = {} ---@type string[]
      local seen = {} ---@type table<string, boolean>
      for _, note in ipairs (imported.notes) do
        if not seen[note] then
          seen[note] = true
          notes[#notes + 1] = note
        end
      end
      if next (imported.variables) then
        local text, name = http.add_environment (
          app.fs.read (ENV_PATH),
          into,
          imported.variables
        )
        if
          text
          and change_files ('Could not save the environments', function ()
            app.fs.write (ENV_PATH, text)
          end)
        then
          load_envs ()
          notes[#notes + 1] = 'Its variables are in the new environment "'
            .. tostring (name)
            .. '". Choose it to use them.'
        elseif not text then
          notes[#notes + 1] = 'Its variables were not added, since the environments file has a problem. '
            .. tostring (name)
        end
      end
      folded[base] = nil
      app.store.set ('folded', folded)
      render_list ()
      say (
        'Imported '
          .. (count == 1 and '1 request' or (count .. ' requests'))
          .. ' into "'
          .. into
          .. '".'
      )
      for _, note in ipairs (notes) do
        if notify then
          notify.warn (note)
        else
          app.warn (note)
        end
      end
    end

    ---Imports a Postman collection, an OpenAPI or Swagger description, an Insomnia export or
    ---a HAR file the user picks.
    local function import_collection ()
      local ok, err = pcall (app.grants.open, {
        title = 'Import a Collection',
        filters = {
          {
            name = 'Collections, API descriptions and HAR files',
            extensions = { 'json', 'yaml', 'yml', 'har' },
          },
        },
      }, function (picked, why)
        if why then
          complain ('Could not show the file picker. ' .. why)
          return
        end
        local grant = picked and picked[1]
        if not grant then
          return
        end
        app.grants.read (grant.id, function (text, read_err)
          -- The file is read once, so the client lets it go.
          app.grants.forget (grant.id)
          if not text then
            complain (
              'Could not read ' .. grant.name .. '. ' .. tostring (read_err)
            )
            return
          end
          local imported, problem = http.import (text)
          if not imported then
            complain (
              'Could not import ' .. grant.name .. '. ' .. tostring (problem)
            )
            return
          end
          write_import (imported, grant.name)
        end)
      end)
      if not ok then
        complain ('Could not show the file picker. ' .. tostring (err))
      end
    end

    ---@param path string
    local function rename (path)
      if not picker then
        return
      end
      local folder = folder_of (path)
      picker.input ({
        prompt = 'Rename "' .. stem (path) .. '"',
        value = stem (path),
        validate = function (text)
          local name, err = http.check_name (text, folder == '')
          if not name then
            return err
          end
          local to = path_for (folder, name)
          if to ~= path and app.fs.exists (to) then
            return 'A request with that name is already there.'
          end
          return nil
        end,
        on_submit = function (text)
          local name = http.check_name (text, folder == '')
          local to = name and path_for (folder, name)
          if not name or not to or to == path then
            return
          end
          if
            not change_files ('Could not rename the request', function ()
              app.fs.rename (path, to)
            end)
          then
            return
          end
          file_cache[path] = nil
          -- The name inside the file changes too.
          local on_disk = read_request (to)
          local text_now = on_disk and http.encode_request (on_disk)
          if text_now then
            change_files ('Could not rename the request', function ()
              app.fs.write (to, text_now)
            end)
          end
          local doc = docs[path]
          if doc then
            docs[path] = nil
            doc.key = to
            doc.path = to
            doc.req.name = name
            doc.saved = text_now or ''
            doc.dirty = http.encode_request (doc.req) ~= doc.saved
            docs[to] = doc
            if doc == current then
              render_head ()
            end
          end
          schedule_drafts ()
          render_list ()
        end,
      })
    end

    ---@param path string
    local function duplicate (path)
      local req, err = read_request (path)
      if not req then
        complain ('Could not read "' .. stem (path) .. '". ' .. tostring (err))
        return
      end
      local folder = folder_of (path)
      local name = http.unique_name (stem (path), function (n)
        return app.fs.exists (path_for (folder, n))
      end)
      local to = path_for (folder, name)
      req.name = name
      if
        change_files ('Could not copy the request', function ()
          app.fs.write (to, http.encode_request (req))
        end)
      then
        open_path (to)
      end
    end

    ---@param path string
    local function delete (path)
      local function go ()
        if
          not change_files ('Could not delete the request', function ()
            app.fs.remove (path)
          end)
        then
          return
        end
        file_cache[path] = nil
        local doc = docs[path]
        docs[path] = nil
        if doc and doc == current then
          show (nil)
        else
          render_list ()
        end
        schedule_drafts ()
      end
      if picker then
        picker.confirm ({
          message = 'Delete "' .. stem (path) .. '"?',
          yes = 'Delete',
          on_yes = go,
        })
      else
        go ()
      end
    end

    ---@param doc ApiApp.Doc
    local function discard (doc)
      local function go ()
        forget (doc)
        if doc == current then
          show (nil)
        else
          render_list ()
        end
        schedule_drafts ()
      end
      if picker then
        picker.confirm ({
          message = 'Discard this request? It was never saved.',
          yes = 'Discard',
          on_yes = go,
        })
      else
        go ()
      end
    end

    ---@param parent string A folder under data/proteus.api, or '' for the top.
    local function new_folder (parent)
      if not picker then
        return
      end
      ---@param name string
      ---@return string
      local function folder_path (name)
        return DIR .. '/' .. (parent ~= '' and (parent .. '/') or '') .. name
      end
      picker.input ({
        prompt = parent == '' and 'New folder' or ('New folder in ' .. parent),
        placeholder = 'Folder name',
        validate = function (text)
          local name, err = http.check_name (text, false)
          if not name then
            return err
          end
          if app.fs.exists (folder_path (name)) then
            return 'Something with that name is already there.'
          end
          return nil
        end,
        on_submit = function (text)
          local name = http.check_name (text, false)
          if not name then
            return
          end
          local path = folder_path (name)
          if
            change_files ('Could not make the folder', function ()
              app.fs.mkdir (path)
            end)
          then
            folded[path] = nil
            if parent ~= '' then
              folded[DIR .. '/' .. parent] = nil
            end
            app.store.set ('folded', folded)
            render_list ()
          end
        end,
      })
    end

    none_new:on ('click', function ()
      new_request ('')
      return nil
    end)
    none_import:on ('click', function ()
      import_curl ()
      return nil
    end)
    none_collection:on ('click', function ()
      import_collection ()
      return nil
    end)

    -- The request list --------------------------------------------------------------------

    local search = ui.input ({
      class = 'api-search',
      placeholder = 'Search requests',
      spellcheck = false,
    })
    local list = ui.div ({ class = 'api-list' })
    local list_empty_text = ui.div ({ 'No saved requests' })
    local list_empty_btn = ui.button ({
      'New Request',
      icon = 'file-plus',
      variant = 'primary',
      onclick = function ()
        new_request ('')
        return nil
      end,
    })
    local list_empty =
      ui.div ({ class = 'api-empty', list_empty_text, list_empty_btn })
    local list_box = ui.div ({ class = 'api-list-box', list, list_empty })
    local requests_side = ui.div ({
      class = 'api-side',
      ui.div ({
        class = 'api-side-bar',
        search,
        ui.button ({
          variant = 'ghost',
          class = 'api-side-btn',
          title = 'New Request (Ctrl+N)',
          ui.icon ('file-plus', 15),
          onclick = function ()
            new_request ('')
            return nil
          end,
        }),
        ui.button ({
          variant = 'ghost',
          class = 'api-side-btn',
          title = 'New Folder',
          ui.icon ('folder-plus', 15),
          onclick = function ()
            new_folder ('')
            return nil
          end,
        }),
      }),
      list_box,
    })

    search:on ('input', function (ev)
      query = ev.value or ''
      render_list ()
      return nil
    end)

    ---@param dir string
    ---@param depth integer
    ---@param out Http.ListItem[]
    local function walk (dir, depth, out)
      for _, e in ipairs (app.fs.list (dir)) do
        if e.dir then
          out[#out + 1] = {
            path = e.path,
            name = e.name,
            dir = true,
            depth = depth,
            method = '',
            url = '',
          }
          walk (e.path, depth + 1, out)
        elseif
          e.name:find ('%.json$')
          and not core.hidden (e.name)
          and not (depth == 0 and e.name == 'environments.json')
        then
          -- A file is read once, and again only after it changes, so a search that redraws
          -- the list on each key reads nothing.
          local info = file_cache[e.path]
          if not info then
            local req =
              http.normalize ((http.json_decode (app.fs.read (e.path) or '')))
            info = { method = req.method, url = req.url }
            file_cache[e.path] = info
          end
          out[#out + 1] = {
            path = e.path,
            name = stem (e.path),
            dir = false,
            depth = depth,
            method = info.method,
            url = info.url,
          }
        end
      end
    end

    ---@param method string
    ---@return string
    local function badge (method)
      return '<span class="api-badge api-m-'
        .. method:lower ()
        .. '">'
        .. http.method_short (method)
        .. '</span>'
    end

    ---@param item string
    ---@param method string
    ---@param name string
    ---@param url string
    ---@param depth integer
    ---@param active boolean
    ---@param dirty boolean
    ---@param untitled boolean
    ---@return string
    local function row_html (
      item,
      method,
      name,
      url,
      depth,
      active,
      dirty,
      untitled
    )
      return '<div class="api-row'
        .. (active and ' on' or '')
        .. '" data-item="'
        .. esc (item)
        .. '" title="'
        .. esc (method .. ' ' .. url)
        .. '" style="padding-left:'
        .. (8 + depth * 16)
        .. 'px">'
        .. badge (method)
        .. '<span class="api-rname'
        .. (untitled and ' untitled' or '')
        .. '">'
        .. esc (name)
        .. '</span>'
        .. (dirty and '<span class="api-dot" title="Unsaved changes"></span>' or '')
        .. '</div>'
    end

    render_list = function ()
      if list_timer then
        list_timer ()
        list_timer = nil
      end
      local items = {} ---@type Http.ListItem[]
      walk (DIR, 0, items)
      saved_count = 0
      for _, it in ipairs (items) do
        if not it.dir then
          saved_count = saved_count + 1
        end
      end
      local shown = http.visible_items (items, folded, query)
      local parts = {} ---@type string[]

      local drafts = {} ---@type ApiApp.Doc[]
      for _, key in ipairs (fresh) do
        local doc = docs[key]
        if
          doc
          and http.matches ({
            name = doc.req.name,
            method = doc.req.method,
            url = doc.req.url,
          }, query)
        then
          drafts[#drafts + 1] = doc
        end
      end
      if #drafts > 0 then
        parts[#parts + 1] = '<div class="api-group">Not saved</div>'
        for _, doc in ipairs (drafts) do
          parts[#parts + 1] = row_html (
            'd:' .. doc.key,
            doc.req.method,
            doc.req.name ~= '' and doc.req.name or 'Untitled',
            doc.req.url,
            0,
            doc == current,
            true,
            doc.req.name == ''
          )
        end
        if #shown > 0 then
          parts[#parts + 1] = '<div class="api-group">Saved</div>'
        end
      end

      for _, it in ipairs (shown) do
        if it.dir then
          local open = query ~= '' or not folded[it.path]
          parts[#parts + 1] = '<div class="api-folder" data-item="'
            .. esc ('f:' .. it.path)
            .. '" style="padding-left:'
            .. (4 + it.depth * 16)
            .. 'px">'
            .. icon (open and 'chevron-down' or 'chevron-right')
            .. icon (open and 'folder-open' or 'folder')
            .. '<span class="api-rname">'
            .. esc (it.name)
            .. '</span></div>'
        else
          local doc = docs[it.path]
          local changed = doc and doc.dirty and doc or nil
          parts[#parts + 1] = row_html (
            'r:' .. it.path,
            changed and changed.req.method or it.method,
            it.name,
            changed and changed.req.url or it.url,
            it.depth,
            current ~= nil and current.key == it.path,
            changed ~= nil,
            false
          )
        end
      end

      list:html (table.concat (parts))
      list_empty:show (#parts == 0)
      list_empty_text:text (
        query ~= '' and 'Nothing matches' or 'No saved requests'
      )
      list_empty_btn:show (query == '')
      if st_count then
        st_count.set (
          saved_count == 1 and '1 request' or (saved_count .. ' requests')
        )
      end
    end

    list:on ('click', function (ev)
      local kind, rest = (ev.item or ''):match ('^(%a):(.*)$')
      if kind == 'f' and rest then
        folded[rest] = (not folded[rest]) or nil
        app.store.set ('folded', folded)
        render_list ()
      elseif kind == 'r' and rest then
        open_path (rest)
      elseif kind == 'd' and rest and docs[rest] then
        show (docs[rest])
      end
      return nil
    end)

    -- History -----------------------------------------------------------------------------

    do
      local stored = app.store.get ('history', {}) ---@type table<string, any>[]
      for _, e in ipairs (type (stored) == 'table' and stored or {}) do
        if type (e) == 'table' and type (e.url) == 'string' then
          history[#history + 1] = {
            method = http.normalize ({ method = e.method }).method,
            url = e.url,
            status = math.floor (tonumber (e.status) or 0),
            time = tonumber (e.time) or 0,
            request = http.normalize (e.request),
          }
        end
      end
    end

    local function clear_history ()
      local function go ()
        history = {}
        app.store.set ('history', history)
        render_history ()
      end
      if #history == 0 then
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
      hist_empty:show (#history == 0)
      local now = app.util.now ()
      local parts = {} ---@type string[]
      for i, h in ipairs (history) do
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
      local entry = history[math.floor (tonumber (ev.item or '') or 0)]
      if entry then
        open_history (entry)
      end
      return nil
    end)
    app.timer.every (60000, function ()
      render_history ()
    end)

    -- Environments ------------------------------------------------------------------------

    local env_label = ui.span ({ class = 'toolbar-text' })
    local env_btn = ui.h ('button', {
      class = 'toolbar-button api-env',
      title = 'Choose an environment',
      ui.icon ('variable', 16),
      env_label,
    })
    local st_env = nil ---@type Proteus.StatusItem?
    if toolbar then
      toolbar.add (env_btn, { order = 10 })
    elseif status then
      st_env = status.add ({
        id = 'api.env',
        text = '',
        icon = 'variable',
        align = 'left',
        order = 20,
        command = 'api.environment',
      })
    end

    render_env = function ()
      local label = envs.active ~= '' and envs.active or 'No environment'
      env_label:text (label)
      env_btn:class ('on', envs.active ~= '')
      env_btn:set (
        'title',
        env_problem and ('The environments file has a problem. ' .. env_problem)
          or 'Choose an environment'
      )
      if st_env then
        st_env.set (label)
      end
    end

    local env_code = nil ---@type Proteus.El?
    local env_view = nil ---@type Proteus.View?
    local env_timer = nil ---@type fun()?
    local env_msg = ui.div ({ class = 'api-env-msg' })
    local env_host = ui.div ({ class = 'api-code' })

    ---Saves the environments text when it is valid, and shows the problem when it is not.
    ---@return boolean saved
    local function check_env_text ()
      env_timer = nil
      local code = env_code
      if not code then
        return true
      end
      local text = code:widget ('get_text')
      local parsed, err = http.parse_envs (text)
      if not parsed then
        env_msg:text (err or 'This is not valid.')
        env_msg:class ('bad', true)
        return false
      end
      env_msg:class ('bad', false)
      if text ~= (app.fs.read (ENV_PATH) or '') then
        if
          not change_files ('Could not save the environments', function ()
            app.fs.write (ENV_PATH, text)
          end)
        then
          return false
        end
      end
      env_msg:text ('Saved. Write a name as {{name}} anywhere in a request.')
      envs = parsed
      env_problem = nil
      render_env ()
      return true
    end

    local function close_envs ()
      if env_timer then
        env_timer ()
      end
      if not check_env_text () then
        complain (
          'The environments are not saved. Fix the problem under the text first.'
        )
        return
      end
      if env_view then
        env_view.remove ()
        env_view = nil
      end
      views.show ('api.requests')
    end

    local env_side = ui.div ({
      class = 'api-side api-envs',
      ui.div ({
        class = 'api-side-bar',
        ui.span ({ class = 'api-side-title', DIR .. '/environments.json' }),
        ui.span ({ class = 'api-grow' }),
        ui.button ({
          'Done',
          icon = 'check',
          variant = 'ghost',
          class = 'api-small',
          onclick = function ()
            close_envs ()
            return nil
          end,
        }),
      }),
      env_host,
      env_msg,
    })

    local function edit_envs ()
      local text = app.fs.read (ENV_PATH) or http.ENV_TEMPLATE
      if not env_code then
        env_code = ui.widget ('code', {
          language = 'json',
          text = text,
          on_change = function ()
            if env_timer then
              env_timer ()
            end
            env_timer = app.timer.after (400, check_env_text)
          end,
        })
        env_host:append (env_code)
      elseif not env_view then
        -- The view was closed, so the text starts again from the file.
        env_code:widget ('set_text', text)
      end
      if not env_view then
        env_msg:class ('bad', env_problem ~= nil)
        env_msg:text (env_problem or 'Changes save once the text is valid.')
        env_view = views.add ('left', {
          id = 'api.envs',
          title = 'Environments',
          icon = 'variable',
          order = 3,
          content = env_side,
        })
      end
      views.show ('api.envs')
    end

    ---@param name string
    local function set_env (name)
      if name == envs.active then
        return
      end
      local text = app.fs.read (ENV_PATH)
      if not text or http.trim (text) == '' then
        return
      end
      local next_text, err = http.set_active (text, name)
      if not next_text then
        complain ('The environments file has a problem. ' .. tostring (err))
        edit_envs ()
        return
      end
      if
        change_files ('Could not save the environments', function ()
          app.fs.write (ENV_PATH, next_text)
        end)
      then
        load_envs ()
        if env_code and not env_timer then
          env_code:widget ('set_text', next_text)
        end
        say (
          name == '' and 'No environment is active.'
            or ('The "' .. name .. '" environment is active.')
        )
      end
    end

    local function choose_env ()
      if not picker then
        return
      end
      local items = {} ---@type Proteus.PickItem[]
      for _, name in ipairs (envs.names) do
        local count = 0
        for _ in pairs (envs.environments[name]) do
          count = count + 1
        end
        items[#items + 1] = {
          label = name,
          detail = count == 1 and '1 variable' or (count .. ' variables'),
          icon = name == envs.active and 'check' or 'variable',
          value = name,
        }
      end
      items[#items + 1] = {
        label = 'No environment',
        icon = envs.active == '' and 'check' or 'circle-slash',
        value = '',
      }
      items[#items + 1] =
        { label = 'Edit environments…', icon = 'pencil', value = false }
      picker.pick ({
        placeholder = env_problem
            and 'The environments file has a problem. Pick Edit to fix it.'
          or 'Choose an environment',
        items = items,
        on_pick = function (item)
          if item.value == false then
            edit_envs ()
          else
            set_env (tostring (item.value))
          end
        end,
      })
    end

    env_btn:on ('click', function ()
      choose_env ()
      return nil
    end)

    -- Files changed elsewhere, such as in the editor profile ------------------------------

    ---Forgets what the list knew of a file, or of every file in a folder.
    ---@param path string
    local function forget_cached (path)
      file_cache[path] = nil
      local prefix = path .. '/'
      for k in pairs (file_cache) do
        if k:sub (1, #prefix) == prefix then
          file_cache[k] = nil
        end
      end
    end

    ---@param from any
    ---@param to any
    app.on ('fs:renamed', function (from, to)
      if type (from) == 'string' and type (to) == 'string' then
        forget_cached (from)
        forget_cached (to)
        schedule_list ()
      end
    end)

    ---@param path any
    app.on ('fs:changed', function (path)
      if type (path) == 'string' then
        forget_cached (path)
      end
      if type (path) ~= 'string' or writing > 0 then
        return
      end
      if path ~= DIR and path:sub (1, #DIR + 1) ~= DIR .. '/' then
        return
      end
      if path == ENV_PATH then
        load_envs ()
        local text = app.fs.read (ENV_PATH) or http.ENV_TEMPLATE
        if
          env_code
          and not env_timer
          and env_code:widget ('get_text') ~= text
        then
          env_code:widget ('set_text', text)
        end
        return
      end
      local doc = docs[path]
      if doc and not doc.dirty and doc.folder_auth then
        local auth = http.parse_folder (app.fs.read (path))
        doc.req.auth = auth
        doc.saved = http.encode_folder (auth)
        if doc == current then
          fill_editor ()
        end
      elseif doc and not doc.dirty then
        if not app.fs.exists (path) then
          docs[path] = nil
          if doc == current then
            show (nil)
          end
        else
          local req = read_request (path)
          if req then
            doc.req = req
            doc.saved = http.encode_request (req)
            if doc == current then
              fill_editor ()
            end
          end
        end
      end
      schedule_list ()
    end)

    -- Views, menus and commands -----------------------------------------------------------

    views.add ('left', {
      id = 'api.requests',
      title = 'Requests',
      icon = 'folder',
      order = 1,
      content = requests_side,
    })
    views.add ('left', {
      id = 'api.history',
      title = 'History',
      icon = 'history',
      order = 2,
      content = history_side,
      on_show = function ()
        render_history ()
      end,
    })

    if menus then
      menus.attach (list_box, function (ev)
        local kind, rest = (ev.item or ''):match ('^(%a):(.*)$')
        if kind == 'r' and rest then
          local path = rest
          return {
            {
              label = 'Open',
              icon = 'file-text',
              run = function ()
                open_path (path)
              end,
            },
            {
              label = 'Rename',
              icon = 'pencil',
              run = function ()
                rename (path)
              end,
            },
            {
              label = 'Duplicate',
              icon = 'copy-plus',
              run = function ()
                duplicate (path)
              end,
            },
            {
              label = 'Copy as curl',
              icon = 'clipboard-copy',
              run = function ()
                local doc = doc_at (path)
                if doc then
                  copy_curl (doc)
                end
              end,
            },
            { separator = true },
            {
              label = 'Delete',
              icon = 'trash-2',
              danger = true,
              run = function ()
                delete (path)
              end,
            },
          }
        end
        local doc = kind == 'd' and rest and docs[rest] or nil
        if doc then
          local draft = doc
          return {
            {
              label = 'Open',
              icon = 'file-text',
              run = function ()
                show (draft)
              end,
            },
            {
              label = 'Save',
              icon = 'save',
              run = function ()
                save (draft)
              end,
            },
            {
              label = 'Copy as curl',
              icon = 'clipboard-copy',
              run = function ()
                copy_curl (draft)
              end,
            },
            { separator = true },
            {
              label = 'Discard',
              icon = 'trash-2',
              danger = true,
              run = function ()
                discard (draft)
              end,
            },
          }
        end
        local folder = (kind == 'f' and rest) and rest:sub (#DIR + 2) or ''
        return {
          {
            label = 'New Request',
            icon = 'file-plus',
            run = function ()
              new_request (folder)
            end,
          },
          {
            label = 'New Folder',
            icon = 'folder-plus',
            run = function ()
              new_folder (folder)
            end,
          },
          {
            label = folder ~= '' and 'Folder Sign-in…'
              or 'Sign-in for Every Request…',
            icon = 'key-round',
            run = function ()
              open_folder_auth (folder)
            end,
          },
          { separator = true },
          {
            label = 'Import Collection…',
            icon = 'import',
            run = import_collection,
          },
        }
      end)

      menus.attach (hist_box, function (ev)
        local entry = history[math.floor (tonumber (ev.item or '') or 0)]
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

    -- In the editor profile the app sits in a tab, and its keys work only while it shows.
    ---@return boolean
    local function on_screen ()
      return tab == nil or tab.is_active ()
    end
    ---@return boolean
    local function has_doc ()
      return current ~= nil and on_screen ()
    end
    ---@return boolean
    local function has_saved ()
      return current ~= nil and current.path ~= nil and on_screen ()
    end

    local CATEGORY = 'API Client'
    ---@type Proteus.CommandSpec[]
    local specs = {
      {
        id = 'api.new',
        title = 'New Request',
        key = 'ctrl+n',
        icon = 'file-plus',
        toolbar = 1,
        when = on_screen,
        run = function ()
          new_request ('')
        end,
      },
      {
        id = 'api.save',
        title = 'Save Request',
        key = 'ctrl+s',
        icon = 'save',
        toolbar = 2,
        when = has_doc,
        run = function ()
          save ()
        end,
      },
      {
        id = 'api.send',
        title = 'Send Request',
        key = 'ctrl+enter',
        icon = 'send',
        when = has_doc,
        run = send,
      },
      {
        id = 'api.copy_curl',
        title = 'Copy as curl',
        icon = 'clipboard-copy',
        toolbar = 3,
        when = has_doc,
        run = function ()
          if current then
            copy_curl (current)
          end
        end,
      },
      {
        id = 'api.import_curl',
        title = 'Import curl',
        icon = 'import',
        toolbar = 4,
        when = on_screen,
        run = import_curl,
      },
      {
        id = 'api.import',
        title = 'Import Collection…',
        icon = 'import',
        toolbar = 5,
        when = on_screen,
        run = import_collection,
      },
      {
        id = 'api.folder_auth',
        title = 'Folder Sign-in',
        icon = 'key-round',
        when = has_doc,
        run = function ()
          if current then
            open_folder_auth (current.folder)
          end
        end,
      },
      {
        id = 'api.environment',
        title = 'Choose Environment',
        icon = 'variable',
        run = choose_env,
      },
      {
        id = 'api.edit_environments',
        title = 'Edit Environments',
        icon = 'pencil',
        run = edit_envs,
      },
      {
        id = 'api.format',
        title = 'Format JSON Body',
        icon = 'wand-sparkles',
        when = function ()
          return has_doc ()
            and current ~= nil
            and current.req.body_mode == 'json'
        end,
        run = format_body,
      },
      {
        id = 'api.search',
        title = 'Search Requests',
        icon = 'search',
        run = function ()
          views.show ('api.requests')
          search:focus ()
        end,
      },
      {
        id = 'api.history',
        title = 'Show History',
        icon = 'history',
        run = function ()
          views.show ('api.history')
        end,
      },
      {
        id = 'api.clear_history',
        title = 'Clear History',
        icon = 'eraser',
        when = function ()
          return #history > 0
        end,
        run = clear_history,
      },
      {
        id = 'api.new_folder',
        title = 'New Folder',
        icon = 'folder-plus',
        run = function ()
          new_folder ('')
        end,
      },
      {
        id = 'api.rename',
        title = 'Rename Request',
        icon = 'pencil',
        when = has_saved,
        run = function ()
          if current and current.path then
            rename (current.path)
          end
        end,
      },
      {
        id = 'api.duplicate',
        title = 'Duplicate Request',
        icon = 'copy-plus',
        when = has_saved,
        run = function ()
          if current and current.path then
            duplicate (current.path)
          end
        end,
      },
      {
        id = 'api.delete',
        title = 'Delete Request',
        icon = 'trash-2',
        when = has_saved,
        run = function ()
          if current and current.path then
            delete (current.path)
          end
        end,
      },
      {
        id = 'api.theme',
        title = 'Change Theme',
        icon = 'palette',
        toolbar = 90,
        toolbar_align = 'right',
        run = function ()
          commands.run ('theme.choose')
        end,
      },
      {
        id = 'api.switch_app',
        title = 'Switch App',
        icon = 'layers',
        toolbar = 91,
        toolbar_align = 'right',
        run = function ()
          commands.run ('profile.switch')
        end,
      },
    }
    for _, spec in ipairs (specs) do
      spec.category = CATEGORY
      commands.register (spec)
    end

    -- Start -------------------------------------------------------------------------------

    load_envs ()

    -- The two examples go in once, on the first start with nothing in the folder.
    if not app.store.get ('seeded', false) then
      app.store.set ('seeded', true)
      local empty = true
      for _, e in ipairs (app.fs.list (DIR)) do
        if e.name ~= 'environments.json' then
          empty = false
        end
      end
      if empty then
        for _, example in ipairs (http.examples ()) do
          change_files ('Could not write the examples', function ()
            app.fs.write (
              path_for ('', example.name),
              http.encode_request (example)
            )
          end)
        end
      end
    end

    -- Requests left unsaved at the last reload come back.
    local restored = {} ---@type ApiApp.Doc[]
    local stored = app.store.get ('drafts', {}) ---@type table<string, any>[]
    if type (stored) == 'table' then
      for _, d in ipairs (stored) do
        if type (d) == 'table' and type (d.req) == 'table' then
          local req = http.normalize (d.req)
          local path = d.path
          if
            type (path) == 'string' and path:sub (1, #DIR + 1) == DIR .. '/'
          then
            local on_disk = read_request (path)
            local saved = on_disk and http.encode_request (on_disk) or ''
            req.name = stem (path)
            docs[path] = {
              key = path,
              path = path,
              folder = folder_of (path),
              req = req,
              saved = saved,
              dirty = http.encode_request (req) ~= saved,
            }
          else
            restored[#restored + 1] =
              add_new (req, type (d.folder) == 'string' and d.folder or '')
          end
        end
      end
    end

    local first = nil ---@type ApiApp.Doc?
    local last_new = tonumber (app.store.get ('last_new', 0)) or 0
    local last = app.store.get ('last', nil)
    if restored[math.floor (last_new)] then
      first = restored[math.floor (last_new)]
    elseif type (last) == 'string' and app.fs.exists (last) then
      first = doc_at (last)
    else
      local items = {} ---@type Http.ListItem[]
      walk (DIR, 0, items)
      for _, it in ipairs (items) do
        if not it.dir then
          first = doc_at (it.path)
          break
        end
      end
    end

    if tabs then
      tab = tabs.open ({
        id = 'proteus.api',
        title = 'API Client',
        icon = 'send',
        content = root,
        closable = false,
      })
    else
      app.use ('shell').mount ('main', root)
    end

    show (first)
    render_history ()
    render_env ()
    app.dispose (function ()
      if drafts_timer then
        drafts_timer ()
      end
      save_drafts ()
    end)
  end,
}
