-- proteus.code.search: finds text in every file of the project folder, in the left dock.
--
-- Typing searches after a short pause, and Enter searches at once. The three buttons beside
-- the box match case, match whole words, and read the text as a regular expression. Files to
-- include and exclude take glob patterns, such as `src/**` or `*.test.ts`, separated by
-- commas. What .gitignore leaves out, and the folders in the `project.exclude` setting, are
-- never searched. A click on a match opens the file at that line.
--
-- The `code:search_folder` event, with a full path, opens the panel with the search limited to
-- one folder. The explorer sends it from Find in Folder.

local disk = require ('disk_paths') --[[@as DiskPaths]]

-- A search stops after this many matches, which is more than anyone reads.
local LIMIT = 2000
-- Typing waits this long before it searches.
local PAUSE = 300

-- lang=css
local CSS = [[
.search { display: flex; flex-direction: column; height: 100%; min-height: 0; }
.search-form { flex: none; display: flex; flex-direction: column; gap: 6px; padding: 8px 10px; }
.search-row { display: flex; align-items: center; gap: 4px; }
.search-row .ui-input { flex: 1; min-width: 0; }
.search-toggle { flex: none; display: inline-grid; place-items: center; width: 24px; height: 24px; padding: 0;
  border: 1px solid transparent; border-radius: var(--radius); background: none; color: var(--fg-muted);
  font: 600 11px var(--font-mono); cursor: pointer; }
.search-toggle:hover { background: var(--bg-hover); color: var(--fg); }
.search-toggle.on { border-color: var(--accent); color: var(--accent);
  background: color-mix(in srgb, var(--accent) 12%, transparent); }
.search-more { align-self: flex-start; padding: 0 2px; border: none; background: none; color: var(--fg-faint);
  font-size: 11px; cursor: pointer; }
.search-more:hover { color: var(--fg); }
.search-status { flex: none; padding: 0 12px 6px; font-size: 12px; color: var(--fg-faint); }
.search-status.error { color: var(--danger); }
.search-results { flex: 1; min-height: 0; overflow: auto; padding-bottom: 12px; font-size: 13px; }
.search-file { display: flex; align-items: center; gap: 4px; height: 24px; padding: 0 8px; cursor: pointer;
  white-space: nowrap; user-select: none; }
.search-file:hover, .search-match:hover { background: var(--bg-hover); }
.search-file .ui-icon, .search-file svg { flex: none; color: var(--fg-muted); }
.search-file-name { flex: none; font-weight: 600; }
.search-file-dir { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; font-size: 12px; color: var(--fg-faint); }
.search-count { flex: none; min-width: 18px; padding: 0 5px; border-radius: 9px; font-size: 11px; line-height: 16px;
  text-align: center; background: var(--bg-active); color: var(--fg-muted); }
.search-match { display: flex; height: 22px; align-items: center; padding: 0 8px 0 34px; cursor: pointer;
  white-space: pre; overflow: hidden; font-family: var(--font-mono); font-size: 12px; color: var(--fg-muted); }
.search-match .text { overflow: hidden; text-overflow: ellipsis; }
.search-match mark { background: color-mix(in srgb, var(--warning) 35%, transparent); color: var(--fg);
  border-radius: 2px; }
.search-match .line { flex: none; margin-left: auto; padding-left: 8px; font-size: 11px; color: var(--fg-faint); }
]]

---All the matches in one file.
---@class CodeSearch.File
---@field path string From the project folder.
---@field matches Proteus.SearchMatch[]

---Splits a list of glob patterns typed with commas. A plain folder name, such as `src`, means
---everything inside it.
---@param text string
---@return string[]
local function globs (text)
  local out = {} ---@type string[]
  for part in text:gmatch ('[^,]+') do
    local glob = part:match ('^%s*(.-)%s*$') --[[@as string]]
    glob = glob:gsub ('\\', '/'):gsub ('^%./', '')
    if glob ~= '' then
      if not glob:find ('[%*%?%[]') then
        glob = glob:gsub ('/$', '') .. '/**'
      end
      out[#out + 1] = glob
    end
  end
  return out
end

---Groups matches by file, keeping the order they came in.
---@param matches Proteus.SearchMatch[]
---@return CodeSearch.File[]
local function by_file (matches)
  local out = {} ---@type CodeSearch.File[]
  local last = nil ---@type CodeSearch.File?
  for _, m in ipairs (matches) do
    if not last or last.path ~= m.path then
      last = { path = m.path, matches = {} }
      out[#out + 1] = last
    end
    last.matches[#last.matches + 1] = m
  end
  return out
end

---@type Proteus.Plugin
return {
  name = 'Search',
  description = 'Finds text in every file of the folder open in the Code Editor.',
  version = '1.0.0',
  -- `files` to search the folder on disk, and for the `project` and `editor` services.
  permissions = { 'files' },
  requires = { proteus = '>=0.3.0', features = { 'permissions' } },
  depends = { 'proteus.lib.ui', 'proteus.ui.views', 'proteus.code.project' },
  optional = {
    'proteus.core.commands',
    'proteus.core.keys',
    'proteus.editor.core',
    'proteus.ui.menus',
  },
  activate = function (app)
    local ui = app.use ('ui')
    local views = app.use ('views')
    local project = app.use ('project')
    local commands = app.try_use ('commands')
    ui.css (CSS)

    ---Opens a file in the editor.
    ---@param full string
    ---@param opts? Proteus.OpenOptions
    local function open_file (full, opts)
      local editor = app.try_use ('editor')
      if editor then
        editor.open_file (full, opts)
      end
    end

    local root = project.root ()
    -- With no folder open there is nothing to search, so the panel stays away.
    if not root then
      return
    end
    local esc = app.util.escape
    local options = app.store.get ('options', {}) --[[@as table<string, boolean>]]
    if type (options) ~= 'table' then
      options = {}
    end
    local files = {} ---@type CodeSearch.File[]
    local closed = {} ---@type table<string, boolean> Files folded shut in the results.
    local seq = 0
    local cancel_pause = nil ---@type fun()?

    local query = ui.input ({
      placeholder = 'Search',
      spellcheck = false,
      attrs = { ['aria-label'] = 'Search' },
    })
    local include = ui.input ({
      placeholder = 'Files to include, such as src/**, *.ts',
      spellcheck = false,
    })
    local exclude = ui.input ({
      placeholder = 'Files to exclude, such as *.min.js',
      spellcheck = false,
    })
    local status = ui.div ({ class = 'search-status' })
    local results = ui.div ({ class = 'search-results' })

    ---@type fun()
    local run

    ---@param key string
    ---@param label string
    ---@param title string
    ---@return Proteus.El
    local function toggle (key, label, title)
      local button = ui.button ({
        class = 'search-toggle',
        title = title,
        label,
      })
      button:class ('on', options[key] == true)
      button:on ('click', function ()
        options[key] = not options[key]
        app.store.set ('options', options)
        button:class ('on', options[key] == true)
        run ()
        return nil
      end)
      return button
    end

    local more_rows = ui.div ({
      class = 'search-form',
      style = { padding = '0' },
      ui.div ({ class = 'search-row', include }),
      ui.div ({ class = 'search-row', exclude }),
    })
    local show_more = options.more == true
    more_rows:show (show_more)
    local more = ui.button ({
      class = 'search-more',
      show_more and 'Hide file filters' or 'File filters…',
    })
    more:on ('click', function ()
      show_more = not show_more
      options.more = show_more
      app.store.set ('options', options)
      more_rows:show (show_more)
      more:text (show_more and 'Hide file filters' or 'File filters…')
      return nil
    end)

    ---@param text string
    ---@param is_error? boolean
    local function set_status (text, is_error)
      status:text (text)
      status:class ('error', is_error == true)
    end

    local function draw ()
      if #files == 0 then
        results:html ('')
        return
      end
      local file_icon = app.util.icon ('file', 14) or ''
      local open_icon = app.util.icon ('chevron-down', 14) or ''
      local shut_icon = app.util.icon ('chevron-right', 14) or ''
      local html = {} ---@type string[]
      for fi, f in ipairs (files) do
        local name = f.path:match ('[^/]+$') or f.path
        local dir = f.path:match ('^(.*)/[^/]+$') or ''
        local shut = closed[f.path] == true
        html[#html + 1] = '<div class="search-file" data-item="f:'
          .. fi
          .. '" title="'
          .. esc (f.path)
          .. '">'
          .. (shut and shut_icon or open_icon)
          .. file_icon
          .. '<span class="search-file-name">'
          .. esc (name)
          .. '</span><span class="search-file-dir">'
          .. esc (dir)
          .. '</span><span class="search-count">'
          .. #f.matches
          .. '</span></div>'
        if not shut then
          for mi, m in ipairs (f.matches) do
            html[#html + 1] = '<div class="search-match" data-item="m:'
              .. fi
              .. ':'
              .. mi
              .. '"><span class="text">'
              .. esc (m.before)
              .. '<mark>'
              .. esc (m.hit)
              .. '</mark>'
              .. esc (m.after)
              .. '</span><span class="line">'
              .. m.line
              .. '</span></div>'
          end
        end
      end
      results:html (table.concat (html))
    end

    run = function ()
      if cancel_pause then
        cancel_pause ()
        cancel_pause = nil
      end
      seq = seq + 1
      local mine = seq
      local text = query:value () or ''
      app.store.set ('query', text)
      if not root then
        return
      end
      if text == '' then
        files = {}
        set_status ('')
        draw ()
        return
      end
      set_status ('Searching…')
      ---@type Proteus.SearchOptions
      local opts = {
        case = options.case == true,
        word = options.word == true,
        regex = options.regex == true,
        include = globs (include:value () or ''),
        exclude = globs (exclude:value () or ''),
        skip = project.excluded (),
        limit = LIMIT,
      }
      app.fs.search_dir (root, text, opts, function (result, err)
        if mine ~= seq then
          return
        end
        if not result then
          files = {}
          draw ()
          set_status (err or 'The search failed.', true)
          return
        end
        files = by_file (result.matches)
        closed = {}
        draw ()
        local count = #result.matches
        if count == 0 then
          set_status ('No results.')
        else
          set_status (
            (result.truncated and 'The first ' or '')
              .. count
              .. (count == 1 and ' result' or ' results')
              .. ' in '
              .. #files
              .. (#files == 1 and ' file' or ' files')
              .. (
                result.truncated and '. Narrow the search to see the rest.'
                or '.'
              )
          )
        end
      end)
    end

    local function run_soon ()
      if cancel_pause then
        cancel_pause ()
      end
      cancel_pause = app.timer.after (PAUSE, function ()
        cancel_pause = nil
        run ()
      end)
    end

    for _, box in ipairs ({ query, include, exclude }) do
      box:on ('input', function ()
        run_soon ()
        return nil
      end)
      box:on ('keydown', function (ev)
        if ev.key == 'Enter' then
          run ()
          return 'stop'
        end
        return nil
      end)
    end

    results:on ('click', function (ev)
      local item = ev.item
      if not item or not root then
        return nil
      end
      local fi = tonumber (item:match ('^f:(%d+)$'))
      if fi then
        local f = files[math.floor (fi)]
        if f then
          closed[f.path] = not closed[f.path] or nil
          draw ()
        end
        return true
      end
      local a, b = item:match ('^m:(%d+):(%d+)$')
      local f = a and files[math.floor (tonumber (a) or 0)]
      local m = f and f.matches[math.floor (tonumber (b) or 0)]
      if f and m then
        open_file (disk.join (root, f.path), { line = m.line, col = m.col })
        return true
      end
      return nil
    end)

    local menus = app.try_use ('menus')
    if menus then
      menus.attach (results, function (ev)
        local fi = ev.item and tonumber (ev.item:match ('^[fm]:(%d+)'))
        local f = fi and files[math.floor (fi)]
        if not f or not root then
          return nil
        end
        local full = disk.join (root, f.path)
        ---@type Proteus.MenuItem[]
        return {
          {
            label = 'Open File',
            icon = 'file',
            run = function ()
              open_file (full)
            end,
          },
          {
            label = 'Copy Path',
            icon = 'copy',
            run = function ()
              app.system.clipboard (disk.native (full, app.os))
            end,
          },
          {
            label = 'Copy Relative Path',
            icon = 'copy',
            run = function ()
              app.system.clipboard (f.path)
            end,
          },
          { separator = true },
          {
            label = 'Collapse All',
            icon = 'list-collapse',
            run = function ()
              for _, each in ipairs (files) do
                closed[each.path] = true
              end
              draw ()
            end,
          },
          {
            label = 'Expand All',
            icon = 'list-tree',
            run = function ()
              closed = {}
              draw ()
            end,
          },
        }
      end)
    end

    local content = ui.div ({
      class = 'search',
      ui.div ({
        class = 'search-form',
        ui.div ({
          class = 'search-row',
          query,
          toggle ('case', 'Aa', 'Match Case'),
          toggle ('word', 'ab', 'Match Whole Word'),
          toggle ('regex', '.*', 'Use Regular Expression'),
        }),
        more,
        more_rows,
      }),
      status,
      results,
    })

    views.add ('left', {
      id = 'search',
      title = 'Search',
      icon = 'search',
      order = 12,
      content = content,
    })

    ---Shows the panel and puts the keys in the search box. Text selected in the editor, on
    ---one line, becomes the search.
    ---@param folder? string A full path to search in, instead of the whole folder.
    local function show (folder)
      views.show ('search')
      local editor = app.try_use ('editor')
      local doc = editor and editor.current ()
      local picked = doc and doc.selection () or ''
      if picked ~= '' and not picked:find ('\n') then
        query:value (picked)
      end
      if folder and root then
        local rel = disk.relative (root, folder, app.os)
        if rel then
          include:value (rel == '' and '' or (rel .. '/**'))
          show_more = true
          more_rows:show (true)
          more:text ('Hide file filters')
        end
      end
      query:focus ()
      query:select ()
      if (query:value () or '') ~= '' then
        run ()
      end
    end

    app.on ('code:search_folder', function (folder)
      show (type (folder) == 'string' and folder or nil)
    end)

    if commands then
      commands.register ({
        id = 'search.find_in_files',
        category = 'Search',
        title = 'Find in Files',
        key = 'ctrl+shift+f',
        icon = 'search',
        menu = 'Edit',
        group = 'find',
        order = 35,
        -- It only shows the panel, so any plugin may offer it.
        shared = true,
        run = function ()
          show ()
        end,
      })
    end

    local last = app.store.get ('query', '')
    if type (last) == 'string' and last ~= '' then
      query:value (last)
    end
  end,
}
