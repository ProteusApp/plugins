-- api_list: the API client's saved requests. It lists them in the Requests view with their
-- folders and the requests not saved yet, saves, renames, copies and deletes them, makes
-- folders, opens a folder's sign-in, and imports curl commands and collections. The client's
-- init.lua attaches it to the context its modules share.

local core = require ('api_core') --[[@as ApiApp.Core]]

---@class ApiApp.ListModule
local M = {}

---Adds the request list to `ctx`.
---@param ctx ApiApp.Ctx
function M.attach (ctx)
  local app, ui, http = ctx.app, ctx.ui, ctx.http
  local picker, menus, notify = ctx.picker, ctx.menus, ctx.notify
  local DIR, ENV_PATH = ctx.DIR, ctx.ENV_PATH
  local docs, fresh, file_cache = ctx.docs, ctx.fresh, ctx.file_cache
  local esc, icon = app.util.escape, ctx.icon
  local say, complain = ctx.say, ctx.complain
  local change_files, read_request = ctx.change_files, ctx.read_request
  local stem, folder_of, path_for = ctx.stem, ctx.folder_of, ctx.path_for
  local doc_at, add_new, forget = ctx.doc_at, ctx.add_new, ctx.forget
  local show, render_head = ctx.show, ctx.render_head
  local schedule_list, schedule_drafts = ctx.schedule_list, ctx.schedule_drafts
  local load_envs, effective_auth = ctx.load_envs, ctx.effective_auth
  local tokens, token_key = ctx.tokens, ctx.token_key
  local url_in, au = ctx.url_in, ctx.au
  local none_new, none_import = ctx.none_new, ctx.none_import
  local none_collection, st_count = ctx.none_collection, ctx.st_count

  local query = ''
  local saved_count = 0
  local folded = app.store.get ('folded', {}) ---@type table<string, boolean>

  local render_list ---@type fun()

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
    if doc == ctx.current then
      render_head ()
    end
    schedule_list ()
    schedule_drafts ()
    return true
  end

  ---@param doc? ApiApp.Doc
  local function save (doc)
    doc = doc or ctx.current
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
        if folder_doc == ctx.current then
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
    local doc = ctx.current
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
      http.to_curl (http.build (doc.req, http.env_vars (ctx.envs), {
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
      local text, name =
        http.add_environment (app.fs.read (ENV_PATH), into, imported.variables)
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
          if doc == ctx.current then
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
      if doc and doc == ctx.current then
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
      if doc == ctx.current then
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
    if ctx.list_timer then
      ctx.list_timer ()
      ctx.list_timer = nil
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
          doc == ctx.current,
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
          ctx.current ~= nil and ctx.current.key == it.path,
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
  end

  ctx.render_list = render_list
  ctx.badge = badge
  ctx.walk = walk
  ctx.save = save
  ctx.new_request = new_request
  ctx.open_folder_auth = open_folder_auth
  ctx.copy_curl = copy_curl
  ctx.import_curl = import_curl
  ctx.import_collection = import_collection
  ctx.new_folder = new_folder
  ctx.rename = rename
  ctx.duplicate = duplicate
  ctx.delete = delete
  ctx.search = search
  ctx.requests_side = requests_side
end

return M
