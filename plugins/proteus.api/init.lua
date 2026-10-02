-- proteus.api: an API client that sends HTTP requests, saves them, and shows the answers.
--
-- Requests go out through app.net.fetch, which runs in Rust in the desktop app, so any address
-- works. Each saved request is a JSON file in data/proteus.api/, so the editor profile can open
-- it too, and data/proteus.api/environments.json holds the values for {{variables}}. The logic
-- that needs no screen comes from the `http` service in proteus.lib.http.
--
-- New requests and unsaved changes stay in memory and in app.store, so a reload keeps them.

local DIR = 'data/proteus.api'
local ENV_PATH = DIR .. '/environments.json'
local HISTORY_MAX = 50
-- A longer answer shows as it came, since formatting it would hold up the window.
local PRETTY_MAX = 3 * 1024 * 1024

local BODY_OPTIONS = {
  { 'none', 'None' },
  { 'json', 'JSON' },
  { 'text', 'Text' },
  { 'form', 'Form' },
  { 'multipart', 'Multipart' },
}
local AUTH_OPTIONS =
  { { 'none', 'None' }, { 'bearer', 'Bearer token' }, { 'basic', 'Basic' } }

-- lang=css
local CSS = [[
.api { flex: 1; min-height: 0; height: 100%; display: flex; flex-direction: column;
  background: var(--bg); color: var(--fg); font-family: var(--font-ui); font-size: var(--font-size); }
.api-editor { flex: 1; min-height: 0; display: flex; flex-direction: column; }
.api-editor.api-dragging, .api-editor.api-dragging * { user-select: none; cursor: row-resize !important; }
.api-top { flex: none; height: var(--api-top, 46%); min-height: 110px; max-height: calc(100% - 90px);
  display: flex; flex-direction: column; min-width: 0; }
.api-head { flex: none; display: flex; align-items: center; gap: 8px; padding: 12px 16px 0; min-width: 0; }
.api-title { font-weight: 600; font-size: 14px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.api-title.untitled { font-style: italic; font-weight: 500; color: var(--fg-muted); }
.api-where { color: var(--fg-faint); font-size: 12px; white-space: nowrap; }
.api-dot { flex: none; width: 7px; height: 7px; border-radius: 50%; background: var(--accent); }
.api-line { flex: none; display: flex; align-items: center; gap: 6px; padding: 10px 16px; }
.api-method { flex: none; width: 100px; height: 32px; padding: 0 8px; border: 1px solid var(--border);
  border-radius: var(--radius); background: var(--bg-elev); font-family: var(--font-mono); font-size: 12px;
  font-weight: 700; outline: none; cursor: pointer; }
.api-method:focus { border-color: var(--accent); }
.api-method option { background: var(--bg-elev); font-weight: 700; }
.api-url { flex: 1; height: 32px; font-family: var(--font-mono); }
.api-send { flex: none; height: 32px; min-width: 96px; justify-content: center; }
.api-send:not(.primary) { color: var(--danger); }
.api-m-get { color: var(--success); }
.api-m-post { color: var(--warning); }
.api-m-put { color: var(--syn-function); }
.api-m-patch { color: var(--syn-keyword); }
.api-m-delete { color: var(--danger); }
.api-m-head { color: var(--syn-builtin); }
.api-m-options { color: var(--syn-constant); }
.api-tabs { flex: none; display: flex; gap: 4px; padding: 0 12px; border-bottom: 1px solid var(--border); }
.api-tab { display: inline-flex; align-items: center; gap: 6px; padding: 6px 8px 7px; margin-bottom: -1px;
  border: none; border-bottom: 2px solid transparent; background: none; color: var(--fg-muted); cursor: pointer; }
.api-tab:hover { color: var(--fg); }
.api-tab.on { color: var(--fg); border-bottom-color: var(--accent); }
.api-count { font-size: 11px; font-weight: 600; color: var(--accent); }
.api-mark { width: 5px; height: 5px; border-radius: 50%; background: var(--accent); }
.api-pane { flex: 1; min-height: 0; overflow: auto; display: flex; flex-direction: column; padding: 10px 16px 12px; }
.api-part { display: flex; flex-direction: column; gap: 8px; }
.api-part.fill { flex: 1; min-height: 0; }
.api-kv { display: flex; flex-direction: column; gap: 4px; }
.api-kv-head, .api-kv-row { display: grid; grid-template-columns: 22px minmax(0, 1fr) minmax(0, 1.5fr) 28px;
  gap: 6px; align-items: center; }
.api-kv-head { font-size: 11px; color: var(--fg-faint); }
.api-kv-row input[type=checkbox] { margin: 0 auto; accent-color: var(--accent); cursor: pointer; }
.api-kv-in { height: 28px; min-width: 0; padding: 0 8px; border: 1px solid var(--border); border-radius: var(--radius);
  background: var(--bg); color: var(--fg); font-family: var(--font-mono); font-size: 12px; outline: none; }
.api-kv-in:focus { border-color: var(--accent); }
.api-kv-row.off .api-kv-in { color: var(--fg-faint); }
.api-kv-del { display: inline-grid; place-items: center; width: 28px; height: 28px; border: none;
  border-radius: var(--radius); background: none; color: var(--fg-faint); cursor: pointer; }
.api-kv-del:hover { background: var(--bg-hover); color: var(--danger); }
.api-kv-row:last-child input[type=checkbox], .api-kv-row:last-child .api-kv-del { visibility: hidden; }
.api-note { color: var(--fg-faint); font-size: 12px; }
.api-modes-row { flex: none; display: flex; align-items: center; gap: 8px; }
.api-modes { display: flex; flex-wrap: wrap; gap: 4px; }
.api-mode { padding: 3px 12px; border: 1px solid var(--border); border-radius: 99px; background: none;
  color: var(--fg-muted); font-size: 12px; cursor: pointer; }
.api-mode:hover { color: var(--fg); background: var(--bg-hover); }
.api-mode.on { background: var(--accent); border-color: var(--accent); color: var(--accent-fg); }
.api-small { padding: 3px 8px; font-size: 12px; }
.api-code { flex: 1; min-height: 90px; border: 1px solid var(--border); border-radius: var(--radius); overflow: hidden; }
.api-code .cm-editor { height: 100%; }
.api-fields { display: flex; flex-direction: column; gap: 10px; max-width: 520px; }
.api-field { display: flex; flex-direction: column; gap: 4px; }
.api-field > span { font-size: 12px; color: var(--fg-muted); }
.api-mono { font-family: var(--font-mono); }
.api-pass { display: flex; gap: 4px; }
.api-pass .ui-input { flex: 1; }
.api-split { flex: none; position: relative; z-index: 2; height: 7px; margin: -3px 0; cursor: row-resize; }
.api-split::after { content: ""; position: absolute; left: 0; right: 0; top: 3px; height: 1px; background: var(--border); }
.api-split:hover::after, .api-dragging .api-split::after { top: 2px; height: 3px; background: var(--accent); }
.api-bottom { flex: 1; min-height: 70px; display: flex; flex-direction: column; background: var(--bg-alt); }
.api-sum { flex: none; display: flex; flex-wrap: wrap; align-items: center; gap: 12px; min-height: 40px;
  padding: 4px 16px; border-bottom: 1px solid var(--border); }
.api-sum-label { font-size: 11px; font-weight: 600; letter-spacing: .04em; text-transform: uppercase; color: var(--fg-muted); }
.api-status { font-family: var(--font-mono); font-weight: 700; }
.api-s-info { color: var(--fg-muted); }
.api-s-success { color: var(--success); }
.api-s-redirect { color: var(--accent); }
.api-s-client { color: var(--warning); }
.api-s-server, .api-s-none { color: var(--danger); }
.api-meta { color: var(--fg-muted); font-size: 12px; }
.api-grow { flex: 1; }
.api-seg { display: inline-flex; border: 1px solid var(--border); border-radius: var(--radius); overflow: hidden; }
.api-seg button { display: inline-flex; align-items: center; gap: 5px; padding: 3px 10px; border: none;
  background: none; color: var(--fg-muted); font-size: 12px; cursor: pointer; }
.api-seg button + button { border-left: 1px solid var(--border); }
.api-seg button:hover { color: var(--fg); background: var(--bg-hover); }
.api-seg button.on { color: var(--fg); background: var(--bg-active); }
.api-icon-btn { display: inline-grid; place-items: center; width: 28px; height: 26px; border: none;
  border-radius: var(--radius); background: none; color: var(--fg-muted); cursor: pointer; }
.api-icon-btn:hover { color: var(--fg); background: var(--bg-hover); }
.api-warn { flex: none; padding: 8px 16px 0; color: var(--warning); font-size: 12px; }
.api-res { flex: 1; min-height: 0; display: flex; flex-direction: column; padding: 10px 16px 14px; }
.api-hint { margin: auto; color: var(--fg-faint); text-align: center; }
.api-error { color: var(--danger); font-family: var(--font-mono); font-size: 12px; white-space: pre-wrap; overflow: auto; }
.api-hdrs { flex: 1; min-height: 0; overflow: auto; }
.api-htable { width: 100%; border-collapse: collapse; font-family: var(--font-mono); font-size: 12px; }
.api-htable td { padding: 5px 8px; border-bottom: 1px solid var(--border); vertical-align: top; word-break: break-all; }
.api-htable td:first-child { width: 32%; color: var(--fg-muted); word-break: normal; }
.api-none { flex: 1; display: flex; align-items: center; justify-content: center; padding: 24px; }
.api-none-card { display: flex; flex-direction: column; align-items: center; gap: 10px; text-align: center; color: var(--fg-muted); }
.api-none-card > .ui-icon { color: var(--fg-faint); }
.api-none-title { font-size: 15px; font-weight: 600; color: var(--fg); }
.api-side { display: flex; flex-direction: column; height: 100%; min-height: 0; }
.api-side-bar { flex: none; display: flex; align-items: center; gap: 4px; padding: 8px 8px 6px; }
.api-side-title { font-size: 12px; color: var(--fg-muted); }
.api-side-btn { padding: 4px 6px; }
.api-search { flex: 1; min-width: 0; }
.api-list-box { flex: 1; min-height: 0; display: flex; flex-direction: column; }
.api-list { flex: 1; min-height: 0; overflow: auto; padding: 0 6px 12px; }
.api-group { padding: 8px 8px 4px; font-size: 11px; font-weight: 600; letter-spacing: .04em; text-transform: uppercase;
  color: var(--fg-faint); }
.api-row, .api-folder { display: flex; align-items: center; gap: 6px; height: 28px; padding-right: 8px;
  border-radius: var(--radius); cursor: pointer; white-space: nowrap; }
.api-row:hover, .api-folder:hover { background: var(--bg-hover); }
.api-row.on { background: var(--bg-active); }
.api-folder { color: var(--fg-muted); }
.api-folder:hover { color: var(--fg); }
.api-badge { flex: none; width: 40px; font-family: var(--font-mono); font-size: 10px; font-weight: 700; text-align: right; }
.api-rname { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; }
.api-rname.untitled { font-style: italic; color: var(--fg-muted); }
.api-empty { margin: 24px 12px; display: flex; flex-direction: column; align-items: center; gap: 10px;
  color: var(--fg-faint); text-align: center; }
.api-hrow { padding: 6px 8px; border-radius: var(--radius); cursor: pointer; }
.api-hrow:hover { background: var(--bg-hover); }
.api-hline { display: flex; align-items: center; gap: 6px; min-width: 0; }
.api-hline .api-badge { width: auto; text-align: left; }
.api-hurl { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
  font-family: var(--font-mono); font-size: 12px; }
.api-hmeta { display: flex; gap: 10px; margin-top: 2px; font-size: 11px; color: var(--fg-faint); }
.api-envs .api-code { margin: 0 8px; }
.api-env-msg { flex: none; padding: 8px 10px 10px; font-size: 12px; color: var(--fg-muted); white-space: pre-wrap; }
.api-env-msg.bad { color: var(--danger); }
.api-env.on { color: var(--accent); }
]]

---What came back from one send.
---@class ApiApp.Result
---@field status? integer Nil when no answer came.
---@field headers table<string, string>
---@field body string
---@field ms number
---@field error? string
---@field warning? string
---@field note? string A line to show instead of an answer, such as after Cancel.
---@field pretty? string The body formatted, made the first time it shows.

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
---@field warning? string What to say about the send that is out, such as a missing variable.

---A key and value table drawn as one HTML string.
---@class ApiApp.Grid
---@field el Proteus.El
---@field render fun()

---What the list needs from a saved file, kept until the file changes.
---@class ApiApp.FileInfo
---@field text string
---@field method string
---@field url string

---@type Proteus.Plugin
return {
  name = 'API Client',
  description = 'Send HTTP requests, save them, and read the answers.',
  version = '1.1.0',
  requires = { proteus = '>=0.3.1', features = { 'permissions' } },
  -- It sends the requests the user writes, to any address.
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

    ---@param path string
    ---@return string
    local function stem (path)
      return path:match ('([^/]+)%.json$') or path
    end

    ---@param path string A file or folder under data/proteus.api.
    ---@return string
    local function folder_of (path)
      return path:sub (#DIR + 2):match ('^(.*)/[^/]*$') or ''
    end

    ---@param folder string
    ---@param name string
    ---@return string
    local function path_for (folder, name)
      return DIR
        .. '/'
        .. (folder ~= '' and (folder .. '/') or '')
        .. name
        .. '.json'
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
      for _, doc in pairs (docs) do
        if doc.path and doc.dirty then
          list[#list + 1] = { path = doc.path, req = doc.req }
        end
      end
      app.store.set ('drafts', list)
      app.store.set ('last', current and current.path or nil)
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

    ---Marks the open request changed, and works out whether it differs from its file.
    local function touch ()
      local doc = current
      if not doc then
        return
      end
      local was = doc.dirty
      doc.dirty = doc.path == nil or http.encode_request (doc.req) ~= doc.saved
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

    ---@param item string?
    ---@return integer?
    ---@return string?
    local function grid_item (item)
      local n, field = (item or ''):match ('^(%d+):(%a+)$')
      if not n then
        return nil, nil
      end
      return math.floor (tonumber (n) or 0), field
    end

    ---@param get fun(): Http.Row[]
    ---@param changed fun()
    ---@return ApiApp.Grid
    local function kv_grid (get, changed)
      local el = ui.div ({ class = 'api-kv' })

      ---@param i integer
      ---@param r Http.Row
      ---@return string
      local function row_html (i, r)
        local n = tostring (i)
        return '<div class="api-kv-row'
          .. (r.on and '' or ' off')
          .. '"><input type="checkbox" title="Send this row" data-item="'
          .. n
          .. ':on"'
          .. (r.on and ' checked' or '')
          .. '><input class="api-kv-in" placeholder="Key" spellcheck="false" autocomplete="off" data-item="'
          .. n
          .. ':key" value="'
          .. esc (r.key)
          .. '"><input class="api-kv-in" placeholder="Value" spellcheck="false" autocomplete="off" data-item="'
          .. n
          .. ':value" value="'
          .. esc (r.value)
          .. '"><button class="api-kv-del" title="Remove this row" data-item="'
          .. n
          .. ':del">'
          .. icon ('x')
          .. '</button></div>'
      end

      local function render ()
        local rows = get ()
        local parts = {
          '<div class="api-kv-head"><span></span><span>Key</span><span>Value</span><span></span></div>',
        }
        for i, r in ipairs (rows) do
          parts[#parts + 1] = row_html (i, r)
        end
        parts[#parts + 1] =
          row_html (#rows + 1, { key = '', value = '', on = true })
        el:html (table.concat (parts))
      end

      el:on ('input', function (ev)
        local i, field = grid_item (ev.item)
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
          el:call (
            'insertAdjacentHTML',
            'beforeend',
            row_html (i + 1, { key = '', value = '', on = true })
          )
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
        local i, field = grid_item (ev.item)
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
        local i, field = grid_item (ev.item)
        local rows = get ()
        if field ~= 'del' or not i or not rows[i] then
          return nil
        end
        table.remove (rows, i)
        render ()
        changed ()
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
    local form_grid = kv_grid (function ()
      return current and current.req.form or {}
    end, touch)

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
    local basic_box = ui.div ({
      class = 'api-fields',
      ui.label ({ class = 'api-field', ui.span ({ 'User name' }), user_in }),
      ui.div ({
        class = 'api-field',
        ui.span ({ 'Password' }),
        ui.div ({ class = 'api-pass', pass_in, pass_eye }),
      }),
    })
    local auth_none = ui.div ({
      class = 'api-note',
      'This request sends no Authorization header.',
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
        form_grid.el,
        body_none,
      }),
      auth = ui.div ({
        class = 'api-part',
        auth_modes,
        bearer_box,
        basic_box,
        auth_none,
      }),
    } ---@type table<string, Proteus.El>
    local pane_box = ui.div ({
      class = 'api-pane',
      panes.params,
      panes.headers,
      panes.body,
      panes.auth,
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
    local none_import = ui.button ({ 'Import curl', icon = 'import' })
    local none = ui.div ({
      class = 'api-none',
      ui.div ({
        class = 'api-none-card',
        ui.icon ('send', 28),
        ui.div ({ class = 'api-none-title', 'No request open' }),
        ui.div ({ 'Make a new request, or pick a saved one on the left.' }),
        ui.div ({ class = 'ui-row', none_new, none_import }),
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
            .. http.human_size (#r.body)
        )
      elseif r and r.error then
        st_result.set ('No answer')
      else
        st_result.set ('')
      end
    end

    -- Drawing the editor ------------------------------------------------------------------

    render_head = function ()
      local doc = current
      if not doc then
        return
      end
      title:text (doc.req.name ~= '' and doc.req.name or 'Untitled')
      title:class ('untitled', doc.req.name == '')
      head_dot:show (doc.dirty)
      where:text (doc.folder ~= '' and ('in ' .. doc.folder) or '')
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
      }
      local parts = {} ---@type string[]
      for _, t in ipairs (list) do
        parts[#parts + 1] = '<button class="api-tab'
          .. (pane == t[1] and ' on' or '')
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
      for id, el in pairs (panes) do
        el:show (id == pane)
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

    local function render_body ()
      local doc = current
      if not doc then
        return
      end
      local mode = doc.req.body_mode
      render_modes (body_modes, BODY_OPTIONS, mode)
      format_btn:show (mode == 'json')
      body_host:show (mode == 'json' or mode == 'text')
      form_grid.el:show (mode == 'form' or mode == 'multipart')
      body_none:show (mode == 'none')
    end

    local function render_auth ()
      local doc = current
      if not doc then
        return
      end
      local mode = doc.req.auth.mode
      render_modes (auth_modes, AUTH_OPTIONS, mode)
      bearer_box:show (mode == 'bearer')
      basic_box:show (mode == 'basic')
      auth_none:show (mode == 'none')
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
        waiting and 'Stop waiting and ignore the answer'
          or 'Send the request (Ctrl+Enter)'
      )
    end

    ---@param headers table<string, string>
    ---@return string
    local function headers_html (headers)
      local names = {} ---@type string[]
      for k in pairs (headers) do
        names[#names + 1] = tostring (k)
      end
      table.sort (names)
      if #names == 0 then
        return '<div class="api-hint">No headers came back.</div>'
      end
      local parts = { '<table class="api-htable">' }
      for _, k in ipairs (names) do
        parts[#parts + 1] = '<tr><td>'
          .. esc (k)
          .. '</td><td>'
          .. esc (tostring (headers[k]))
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
      local kind = answer and http.body_kind (answer.headers, answer.body)
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
          .. http.human_size (#answer.body)
          .. '</span>'
      else
        parts[#parts + 1] = '<span class="api-sum-label">Response</span>'
      end
      parts[#parts + 1] = '<span class="api-grow"></span>'
      if answer then
        local count = 0
        for _ in pairs (answer.headers) do
          count = count + 1
        end
        parts[#parts + 1] = '<span class="api-seg">'
          .. seg_button ('body', 'Body', res_view == 'body')
          .. seg_button (
            'headers',
            'Headers ' .. count_html (count),
            res_view == 'headers'
          )
          .. '</span>'
        if res_view == 'body' and kind == 'json' then
          parts[#parts + 1] = '<span class="api-seg">'
            .. seg_button ('pretty', 'Pretty', not raw)
            .. seg_button ('raw', 'Raw', raw)
            .. '</span>'
        end
        parts[#parts + 1] = '<button class="api-icon-btn" data-item="copy" title="Copy the body">'
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

      if waiting then
        hint ('Waiting for the answer. Cancel stops waiting.')
      elseif not r then
        hint ('Press Ctrl+Enter to send.')
      elseif r.error then
        res_error:text (r.error)
        res_error:show (true)
      elseif not answer then
        hint (r.note or 'Press Ctrl+Enter to send.')
      elseif res_view == 'headers' then
        res_headers:html (headers_html (answer.headers))
        res_headers:show (true)
      elseif answer.body == '' then
        hint ('The answer has no body.')
      else
        local text, language = answer.body, 'text'
        if kind == 'json' then
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
      method_sel:value (req.method)
      paint_method ()
      url_in:value (req.url)
      body_code:widget ('set_text', req.body)
      body_code:widget (
        'set_language',
        req.body_mode == 'json' and 'json' or 'text'
      )
      token_in:value (req.auth.token)
      user_in:value (req.auth.user)
      pass_in:value (req.auth.password)
      params_grid.render ()
      headers_grid.render ()
      form_grid.render ()
      render_body ()
      render_auth ()
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
      if ev.item and panes[ev.item] then
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

    local function send ()
      local doc = current
      if not doc then
        return
      end
      if doc.pending then
        doc.pending = nil
        doc.result = {
          headers = {},
          body = '',
          ms = 0,
          note = 'Cancelled. An answer that comes now is ignored.',
        }
        render_send ()
        render_response ()
        render_status ()
        return
      end
      local built = http.build (doc.req, http.env_vars (envs))
      if built.url == '' then
        doc.result = {
          headers = {},
          body = '',
          ms = 0,
          note = 'Type an address first.',
        }
        render_response ()
        url_in:focus ()
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

      ---@param reply Proteus.HttpReply?
      ---@param err string?
      local function done (reply, err)
        if doc.pending ~= number then
          return
        end
        doc.pending = nil
        local ms = app.util.now () - started
        local result ---@type ApiApp.Result
        if reply then
          result = {
            status = math.floor (tonumber (reply.status) or 0),
            headers = type (reply.headers) == 'table' and reply.headers or {},
            body = type (reply.body) == 'string' and reply.body or '',
            ms = ms,
            warning = warning,
          }
        else
          result = {
            headers = {},
            body = '',
            ms = ms,
            error = http.error_text (err, browser),
            warning = warning,
          }
        end
        doc.result = result
        -- The address as typed, with {{variables}} left in, so no token from an environment
        -- is kept in the history.
        history = http.add_history (history, {
          method = built.method,
          url = http.build (snapshot).url,
          status = result.status or 0,
          time = app.util.now (),
          request = snapshot,
        }, HISTORY_MAX)
        app.store.set ('history', history)
        render_history ()
        if doc == current then
          render_send ()
          render_response ()
        end
        render_status ()
      end

      local ok, err = pcall (app.net.fetch, {
        method = built.method,
        url = built.url,
        headers = built.headers,
        body = built.body,
      }, done)
      if not ok then
        done (nil, tostring (err))
      end
    end

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
          app.system.clipboard (shown_for == r and shown_text or r.body)
          say ('Copied the body.')
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

    ---@param folder string
    local function new_request (folder)
      show (add_new (http.normalize ({}), folder))
      url_in:focus ()
    end

    ---@param req Http.Request
    local function copy_curl (req)
      app.system.clipboard (
        http.to_curl (http.build (req, http.env_vars (envs)))
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
          and not (depth == 0 and e.name == 'environments.json')
        then
          local text = app.fs.read (e.path) or ''
          local info = file_cache[e.path]
          if not info or info.text ~= text then
            local req = http.normalize ((http.json_decode (text)))
            info = { text = text, method = req.method, url = req.url }
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
          history[#history + 1] = {
            method = http.normalize ({ method = e.method }).method,
            url = url,
            status = math.floor (tonumber (e.status) or 0),
            time = tonumber (e.time) or 0,
            request = request,
          }
        end
      end
      if scrubbed then
        app.store.set ('history', history)
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

    ---@param path any
    app.on ('fs:changed', function (path)
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
      if doc and not doc.dirty then
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
                  copy_curl (doc.req)
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
                copy_curl (draft.req)
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
            copy_curl (current.req)
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
