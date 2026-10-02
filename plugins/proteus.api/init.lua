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
--
-- This file keeps the open requests, puts the screen together and registers the commands.
-- The rest lives in modules that share one context, ApiApp.Ctx: api_editor draws and edits
-- the request, api_response sends it and shows the answer, api_list saves and lists the
-- requests, api_history keeps the ones sent, and api_envs the environments.

local CSS = require ('api_css') --[[@as string]]
local core = require ('api_core') --[[@as ApiApp.Core]]
local editor_m = require ('api_editor') --[[@as ApiApp.EditorModule]]
local envs_m = require ('api_envs') --[[@as ApiApp.EnvsModule]]
local history_m = require ('api_history') --[[@as ApiApp.HistoryModule]]
local list_m = require ('api_list') --[[@as ApiApp.ListModule]]
local response_m = require ('api_response') --[[@as ApiApp.ResponseModule]]

local DIR = 'data/proteus.api'
local ENV_PATH = DIR .. '/environments.json'

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

---What the list needs from a saved file, kept until the file changes.
---@class ApiApp.FileInfo
---@field method string
---@field url string

---What the API client's modules share. init.lua fills in the state and its own helpers, and
---each module adds the functions it offers the others.
---@class ApiApp.Ctx
---@field app Proteus.App
---@field ui Proteus.UI
---@field http Proteus.Http
---@field views Proteus.Views
---@field status? Proteus.Status
---@field picker? Proteus.Picker
---@field notify? Proteus.Notify
---@field toolbar? Proteus.Toolbar
---@field menus? Proteus.Menus
---@field DIR string The folder the requests live in.
---@field ENV_PATH string The file the environments live in.
---@field browser boolean True in the browser, where requests go through its fetch.
---@field envs Http.Envs
---@field env_problem? string What is wrong with the environments file, if anything.
---@field history Http.HistoryEntry[] The requests sent, newest first.
---@field docs table<string, ApiApp.Doc> The open requests, by key.
---@field fresh string[] Keys of new requests, oldest first.
---@field current? ApiApp.Doc The request the editor shows.
---@field file_cache table<string, ApiApp.FileInfo> What the list read from each saved file.
---@field list_timer? fun() Cancels the redraw of the list that is waiting.
---@field tab? Proteus.Tab The tab the client sits in, in the editor profile.
---@field editor Proteus.El The request and the response, shown while a request is open.
---@field none Proteus.El What shows while no request is open.
---@field split Proteus.El The line between the request and the response.
---@field bottom Proteus.El The response.
---@field head Proteus.El The request's name.
---@field line Proteus.El The method, the address and the Send button.
---@field req_tabs Proteus.El
---@field pane_box Proteus.El
---@field send_btn Proteus.El
---@field url_in Proteus.El The address field.
---@field au table<string, Proteus.El> The controls of the sign-ins.
---@field none_new Proteus.El The buttons shown while no request is open.
---@field none_import Proteus.El
---@field none_collection Proteus.El
---@field st_count? Proteus.StatusItem The count of saved requests in the status bar.
---@field tokens table<string, ApiApp.Token> Tokens got for OAuth 2 sign-ins, by `http.oauth_key`.
---@field env_code? Proteus.El The editor of the environments file, once it is made.
---@field env_timer? fun() Cancels the check of the environments text that is waiting.
---@field say fun(text: string)
---@field complain fun(text: string)
---@field icon fun(name: string, size?: integer): string
---@field stem fun(path: string): string
---@field folder_of fun(path: string): string
---@field path_for fun(folder: string, name: string): string
---@field read_request fun(path: string): Http.Request?, string?
---@field doc_at fun(path: string): ApiApp.Doc?
---@field forget fun(doc: ApiApp.Doc)
---@field schedule_list fun()
---@field touch fun()
---@field render_status fun()
---@field schedule_drafts fun()
---@field effective_auth fun(doc: ApiApp.Doc): Http.Auth, string?
---@field token_key fun(auth: Http.Auth): string
---@field change_files fun(what: string, fn: fun()): boolean
---@field load_envs fun()
---@field add_new fun(req: Http.Request, folder: string): ApiApp.Doc
---@field render_env fun() From api_envs.
---@field edit_envs fun()
---@field choose_env fun()
---@field render_head fun() From api_editor.
---@field show fun(doc: ApiApp.Doc?)
---@field render_tabs fun()
---@field render_token fun()
---@field render_auth fun()
---@field render_send fun()
---@field count_html fun(n: integer): string
---@field fill_editor fun()
---@field format_body fun()
---@field sum Proteus.El From api_response: the status line of the answer.
---@field warn Proteus.El
---@field res_box Proteus.El
---@field render_response fun()
---@field send fun()
---@field render_list fun() From api_list.
---@field badge fun(method: string): string
---@field walk fun(dir: string, depth: integer, out: Http.ListItem[])
---@field save fun(doc?: ApiApp.Doc)
---@field new_request fun(folder: string)
---@field open_folder_auth fun(folder: string)
---@field copy_curl fun(doc: ApiApp.Doc)
---@field import_curl fun()
---@field import_collection fun()
---@field new_folder fun(parent: string)
---@field rename fun(path: string)
---@field duplicate fun(path: string)
---@field delete fun(path: string)
---@field search Proteus.El The search field of the Requests view.
---@field requests_side Proteus.El The Requests view.
---@field render_history fun() From api_history.
---@field clear_history fun()
---@field history_side Proteus.El The History view.

---@type Proteus.Plugin
return {
  name = 'API Client',
  description = 'Send HTTP requests, save them, and read the answers.',
  version = '1.2.1',
  requires = {
    proteus = '>=0.3.1',
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
    local new_count = 0
    local writing = 0
    local top_px = app.store.get ('split', nil) ---@type number?
    local file_cache = {} ---@type table<string, ApiApp.FileInfo>
    local drafts_timer = nil ---@type fun()?

    local render_list ---@type fun()
    local render_head ---@type fun()
    local render_tabs ---@type fun()
    local render_env ---@type fun()

    -- What the modules share. Each adds its own functions to it.
    local shared = {
      app = app,
      ui = ui,
      http = http,
      views = views,
      status = status,
      picker = picker,
      toolbar = toolbar,
      menus = menus,
      notify = notify,
      DIR = DIR,
      ENV_PATH = ENV_PATH,
      say = say,
      complain = complain,
      browser = browser,
      envs = assert (http.parse_envs (nil)),
      history = {},
      docs = docs,
      fresh = fresh,
      file_cache = file_cache,
    }
    local ctx = shared --[[@as ApiApp.Ctx]]

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
    ctx.icon, ctx.stem, ctx.folder_of, ctx.path_for =
      icon, stem, folder_of, path_for

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
        ctx.envs = parsed
        ctx.env_problem = nil
      else
        ctx.envs = assert (http.parse_envs (nil))
        ctx.env_problem = err
      end
      render_env ()
    end
    ctx.change_files, ctx.load_envs = change_files, load_envs

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
          if doc == ctx.current then
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
        ctx.current and not ctx.current.folder_auth and ctx.current.path or nil
      )
      app.store.set ('last_new', last_new)
    end

    local function schedule_drafts ()
      if not drafts_timer then
        drafts_timer = app.timer.after (400, save_drafts)
      end
    end

    local function schedule_list ()
      if not ctx.list_timer then
        ctx.list_timer = app.timer.after (40, function ()
          ctx.list_timer = nil
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
      local doc = ctx.current
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
      local doc = ctx.current
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

    -- The request editor ------------------------------------------------------------------

    ctx.touch, ctx.schedule_list = touch, schedule_list
    ctx.schedule_drafts, ctx.render_status = schedule_drafts, render_status
    ctx.effective_auth = effective_auth
    editor_m.attach (ctx)
    render_head, render_tabs = ctx.render_head, ctx.render_tabs
    local fill_editor, show = ctx.fill_editor, ctx.show
    local head, line, req_tabs, pane_box =
      ctx.head, ctx.line, ctx.req_tabs, ctx.pane_box
    local format_body = ctx.format_body

    -- The response ------------------------------------------------------------------------

    response_m.attach (ctx)
    local sum, warn, res_box = ctx.sum, ctx.warn, ctx.res_box
    local send = ctx.send

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
    ctx.editor, ctx.none, ctx.split, ctx.bottom = editor, none, split, bottom

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

    -- Saving, managing and listing requests ------------------------------------------------

    ctx.none_new, ctx.none_import = none_new, none_import
    ctx.none_collection, ctx.st_count = none_collection, st_count
    ctx.read_request, ctx.doc_at, ctx.forget = read_request, doc_at, forget
    ctx.add_new = add_new
    list_m.attach (ctx)
    render_list = ctx.render_list
    local walk, save, new_request = ctx.walk, ctx.save, ctx.new_request
    local open_folder_auth, copy_curl = ctx.open_folder_auth, ctx.copy_curl
    local import_curl, import_collection =
      ctx.import_curl, ctx.import_collection
    local new_folder, rename = ctx.new_folder, ctx.rename
    local duplicate, delete = ctx.duplicate, ctx.delete

    -- History -----------------------------------------------------------------------------

    history_m.attach (ctx)
    local render_history, clear_history = ctx.render_history, ctx.clear_history

    -- Environments ------------------------------------------------------------------------

    envs_m.attach (ctx)
    render_env = ctx.render_env
    local edit_envs, choose_env = ctx.edit_envs, ctx.choose_env

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
          ctx.env_code
          and not ctx.env_timer
          and ctx.env_code:widget ('get_text') ~= text
        then
          ctx.env_code:widget ('set_text', text)
        end
        return
      end
      local doc = docs[path]
      if doc and not doc.dirty and doc.folder_auth then
        local auth = http.parse_folder (app.fs.read (path))
        doc.req.auth = auth
        doc.saved = http.encode_folder (auth)
        if doc == ctx.current then
          fill_editor ()
        end
      elseif doc and not doc.dirty then
        if not app.fs.exists (path) then
          docs[path] = nil
          if doc == ctx.current then
            show (nil)
          end
        else
          local req = read_request (path)
          if req then
            doc.req = req
            doc.saved = http.encode_request (req)
            if doc == ctx.current then
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
      content = ctx.requests_side,
    })
    views.add ('left', {
      id = 'api.history',
      title = 'History',
      icon = 'history',
      order = 2,
      content = ctx.history_side,
      on_show = function ()
        render_history ()
      end,
    })

    -- In the editor profile the app sits in a tab, and its keys work only while it shows.
    ---@return boolean
    local function on_screen ()
      return ctx.tab == nil or ctx.tab.is_active ()
    end
    ---@return boolean
    local function has_doc ()
      return ctx.current ~= nil and on_screen ()
    end
    ---@return boolean
    local function has_saved ()
      return ctx.current ~= nil and ctx.current.path ~= nil and on_screen ()
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
          if ctx.current then
            copy_curl (ctx.current)
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
          if ctx.current then
            open_folder_auth (ctx.current.folder)
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
            and ctx.current ~= nil
            and ctx.current.req.body_mode == 'json'
        end,
        run = format_body,
      },
      {
        id = 'api.search',
        title = 'Search Requests',
        icon = 'search',
        run = function ()
          views.show ('api.requests')
          ctx.search:focus ()
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
          return #ctx.history > 0
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
          if ctx.current and ctx.current.path then
            rename (ctx.current.path)
          end
        end,
      },
      {
        id = 'api.duplicate',
        title = 'Duplicate Request',
        icon = 'copy-plus',
        when = has_saved,
        run = function ()
          if ctx.current and ctx.current.path then
            duplicate (ctx.current.path)
          end
        end,
      },
      {
        id = 'api.delete',
        title = 'Delete Request',
        icon = 'trash-2',
        when = has_saved,
        run = function ()
          if ctx.current and ctx.current.path then
            delete (ctx.current.path)
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
      ctx.tab = tabs.open ({
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
