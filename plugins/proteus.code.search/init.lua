-- proteus.code.search: finds and replaces text in every file of the project folder, in the left
-- dock.
--
-- Typing searches after a short pause, and Enter searches at once. A new search stops the one
-- still running, and so does Escape. The three buttons beside the box match case, match whole
-- words, and read the text as a regular expression. Up and Down in the box go through earlier
-- searches. Files to include and exclude take glob patterns, such as `src/**` or `*.test.ts`,
-- separated by commas, and the book button keeps the search to the files open in the editor.
-- What .gitignore leaves out, and what the `project.exclude` setting matches, are never
-- searched. The results follow changes on disk.
--
-- The arrow before the box opens the replace box. Each match then shows what it becomes, and
-- the buttons on a match, on a file and beside the box replace one match, every match in one
-- file, or every match listed. A file open in the editor changes there, as one edit its own
-- undo takes back, and stays unsaved. Undo in the status line takes back the last replace.
--
-- With the results focused, the arrow keys move through them, Left and Right fold a file,
-- Enter opens a match and Space opens it keeping the focus here. F4 and Shift+F4 open the next
-- and the previous match from anywhere.
--
-- The `code:search_folder` event, with a full path, opens the panel with the search limited to
-- one folder. The explorer sends it from Find in Folder.

local core = require ('search_core') --[[@as CodeSearch.Core]]
local disk = require ('disk_paths') --[[@as DiskPaths]]
local file_glob = require ('file_glob') --[[@as FileGlob]]

-- A search stops after this many matches, which is more than anyone reads.
local LIMIT = 2000
-- Typing waits this long before it searches.
local PAUSE = 300
-- Changes on disk search again once they rest this long.
local REFRESH = 500
-- How many earlier searches Up and Down go through.
local HISTORY = 30
-- The heights of a file's row and a match's row in the results, for scrolling to one.
local FILE_ROW = 24
local MATCH_ROW = 22

-- lang=css
local CSS = [[
.search { display: flex; flex-direction: column; height: 100%; min-height: 0; }
.search-form { flex: none; display: flex; flex-direction: column; gap: 6px; padding: 8px 10px; }
.search-head { display: flex; align-items: flex-start; gap: 2px; }
.search-fields { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 6px; }
.search-row { display: flex; align-items: center; gap: 4px; }
.search-row .ui-input { flex: 1; min-width: 0; }
.search-toggle { flex: none; display: inline-grid; place-items: center; width: 24px; height: 24px; padding: 0;
  border: 1px solid transparent; border-radius: var(--radius); background: none; color: var(--fg-muted);
  font: 600 11px var(--font-mono); cursor: pointer; }
.search-toggle:hover { background: var(--bg-hover); color: var(--fg); }
.search-toggle.on { border-color: var(--accent); color: var(--accent);
  background: color-mix(in srgb, var(--accent) 12%, transparent); }
.search-toggle:disabled { opacity: .4; cursor: default; }
.search-fold { flex: none; display: inline-grid; place-items: center; width: 16px; height: 26px; padding: 0;
  border: none; border-radius: var(--radius); background: none; color: var(--fg-muted); cursor: pointer; }
.search-fold:hover { background: var(--bg-hover); color: var(--fg); }
.search-more { align-self: flex-start; padding: 0 2px; border: none; background: none; color: var(--fg-faint);
  font-size: 11px; cursor: pointer; }
.search-more:hover { color: var(--fg); }
.search-status { flex: none; display: flex; flex-wrap: wrap; gap: 0 8px; padding: 0 12px 6px; font-size: 12px;
  color: var(--fg-faint); }
.search-status.error { color: var(--danger); }
.search-link { padding: 0; border: none; background: none; color: var(--accent); font-size: 12px; cursor: pointer; }
.search-link:hover { text-decoration: underline; }
.search-results { flex: 1; min-height: 0; overflow: auto; padding-bottom: 12px; font-size: 13px; outline: none; }
.search-file { display: flex; align-items: center; gap: 4px; height: 24px; padding: 0 8px; cursor: pointer;
  white-space: nowrap; user-select: none; }
.search-file:hover, .search-match:hover { background: var(--bg-hover); }
.search-results .cursor { background: var(--bg-active); }
.search-results:focus .cursor { box-shadow: inset 0 0 0 1px var(--accent); }
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
.search-match del { background: color-mix(in srgb, var(--danger) 25%, transparent); color: var(--fg);
  border-radius: 2px; }
.search-match ins { text-decoration: none; background: color-mix(in srgb, var(--success) 25%, transparent);
  color: var(--fg); border-radius: 2px; }
.search-match .line { flex: none; margin-left: auto; padding-left: 8px; font-size: 11px; color: var(--fg-faint); }
.search-act { flex: none; display: none; place-items: center; width: 20px; height: 20px; margin-left: 2px;
  border-radius: var(--radius); color: var(--fg-muted); }
.search-act:hover { background: var(--bg-hover); color: var(--fg); }
.search-file:hover .search-act, .search-match:hover .search-act, .search-results .cursor .search-act {
  display: inline-grid; }
]]

---What a replace changed in one file, so Undo can put it back.
---@class CodeSearch.Change
---@field path string From the project folder.
---@field doc? string The open document's path, when the change went to the editor.
---@field before string
---@field after string

---A line under the boxes, with a button for what can be done next.
---@class CodeSearch.Note
---@field text string
---@field action? { label: string, run: fun() }

---@type Proteus.Plugin
return {
  name = 'Search',
  description = 'Finds and replaces text in every file of the folder open in the Code Editor.',
  version = '1.1.0',
  -- `files` to search and change the folder on disk, and for the `project` and `editor`
  -- services.
  permissions = { 'files' },
  requires = { proteus = '>=0.3.1', features = { 'permissions' } },
  depends = { 'proteus.lib.ui', 'proteus.ui.views', 'proteus.code.project' },
  optional = {
    'proteus.core.commands',
    'proteus.core.keys',
    'proteus.editor.core',
    'proteus.ui.menus',
    'proteus.ui.notify',
    'proteus.ui.palette',
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
    local folder = root
    local fold_case = disk.folds_case (app.os)
    local esc = app.util.escape
    local options = app.store.get ('options', {}) --[[@as table<string, boolean>]]
    if type (options) ~= 'table' then
      options = {}
    end
    local history = {} ---@type string[]
    local saved = app.store.get ('history', {})
    for _, h in
      ipairs (type (saved) == 'table' and saved or {} --[[@as any[] ]])
    do
      if type (h) == 'string' and h ~= '' then
        history[#history + 1] = h
      end
    end

    local files = {} ---@type CodeSearch.File[]
    local closed = {} ---@type table<string, boolean> Files folded shut in the results.
    local groups = {} ---@type Proteus.El[] One element per file in the results.
    local cursor = nil ---@type string? The row the keys act on, by its key.
    local seq = 0
    local cancel_pause = nil ---@type fun()?
    local cancel_refresh = nil ---@type fun()?
    local running = nil ---@type Proteus.SearchHandle?
    -- The search the results come from, which a replace repeats.
    local shown_query = ''
    local shown_opts = nil ---@type Proteus.SearchOptions?
    local truncated = false
    local replacing = false
    local undo = nil ---@type CodeSearch.Change[]?
    local note = nil ---@type CodeSearch.Note?
    local hist_at = 0 ---@type integer
    local hist_draft = ''

    local query = ui.input ({
      placeholder = 'Search',
      spellcheck = false,
      attrs = { ['aria-label'] = 'Search' },
    })
    local replace_box = ui.input ({
      placeholder = 'Replace',
      spellcheck = false,
      attrs = { ['aria-label'] = 'Replace' },
    })
    local include = ui.input ({
      placeholder = 'Files to include, such as src/**, *.ts',
      spellcheck = false,
    })
    local exclude = ui.input ({
      placeholder = 'Files to exclude, such as *.min.js',
      spellcheck = false,
    })
    local status_text = ui.span ({})
    local status_action = ui.button ({ class = 'search-link' })
    status_action:show (false)
    local status =
      ui.div ({ class = 'search-status', status_text, status_action })
    local status_run = nil ---@type fun()?
    local results = ui.div ({
      class = 'search-results',
      attrs = { tabindex = 0, ['aria-label'] = 'Search results' },
    })

    ---@return Proteus.Notify?
    local function notify ()
      return app.try_use ('notify')
    end

    ---@param text string
    ---@param is_error? boolean
    ---@param action? { label: string, run: fun() }
    local function set_status (text, is_error, action)
      status_text:text (text)
      status:class ('error', is_error == true)
      status_action:text (action and action.label or '')
      status_action:show (action ~= nil)
      status_run = action and action.run or nil
    end
    status_action:on ('click', function ()
      if status_run then
        status_run ()
      end
      return nil
    end)

    ---@param err any
    local function report (err)
      local text = tostring (err):match ('^[^\n]*') or ''
      local n = notify ()
      if n then
        n.error (text)
      else
        set_status (text, true)
      end
    end

    ---@type fun(keep?: boolean)
    local run

    -- Drawing ---------------------------------------------------------------------------

    ---@param fi integer
    ---@return string
    local function group_html (fi)
      local f = files[fi]
      local name = f.path:match ('[^/]+$') or f.path
      local dir = f.path:match ('^(.*)/[^/]+$') or ''
      local shut = closed[f.path] == true
      local replace_on = shown_opts ~= nil and shown_opts.replace ~= nil
      local key = 'f:' .. fi
      local html = {
        '<div class="search-file',
        cursor == key and ' cursor' or '',
        '" data-item="',
        key,
        '" title="',
        esc (f.path),
        '">',
        app.util.icon (shut and 'chevron-right' or 'chevron-down', 14) or '',
        app.util.icon ('file', 14) or '',
        '<span class="search-file-name">',
        esc (name),
        '</span><span class="search-file-dir">',
        esc (dir),
        '</span><span class="search-count">',
        tostring (#f.matches),
        '</span>',
      } ---@type string[]
      if replace_on then
        html[#html + 1] = '<span class="search-act" data-item="R:'
          .. fi
          .. '" title="Replace All in File">'
          .. (app.util.icon ('replace-all', 14) or '')
          .. '</span>'
      end
      html[#html + 1] = '</div>'
      if not shut then
        local replace_icon = replace_on
            and (app.util.icon ('replace', 14) or '')
          or ''
        for mi, m in ipairs (f.matches) do
          local mkey = 'm:' .. fi .. ':' .. mi
          -- With a replace, a button on the row replaces this match alone.
          local act = ''
          if m.with then
            act = '<span class="search-act" data-item="r:'
              .. fi
              .. ':'
              .. mi
              .. '" title="Replace">'
              .. replace_icon
              .. '</span>'
          end
          local hit = m.with
              and ('<del>' .. esc (m.hit) .. '</del><ins>' .. esc (m.with) .. '</ins>')
            or ('<mark>' .. esc (m.hit) .. '</mark>')
          html[#html + 1] = '<div class="search-match'
            .. (cursor == mkey and ' cursor' or '')
            .. '" data-item="'
            .. mkey
            .. '"><span class="text">'
            .. esc (m.before)
            .. hit
            .. esc (m.after)
            .. '</span><span class="line">'
            .. m.line
            .. '</span>'
            .. act
            .. '</div>'
        end
      end
      return table.concat (html)
    end

    ---Draws one file's rows again, and leaves the others alone.
    ---@param fi integer?
    local function draw_group (fi)
      local g = fi and groups[fi]
      if g and fi and files[fi] then
        g:html (group_html (fi))
      end
    end

    local function draw ()
      local list = {} ---@type Proteus.El[]
      for fi in ipairs (files) do
        local g = ui.div ({})
        g:html (group_html (fi))
        list[fi] = g
      end
      groups = list
      results:set_children (list)
    end

    ---The file and the match a row's key names.
    ---@param key string?
    ---@return integer? fi
    ---@return integer? mi
    local function parse (key)
      if not key then
        return nil, nil
      end
      local a, b = key:match ('^%a:(%d+):(%d+)$')
      if a then
        return math.floor (tonumber (a) or 0), math.floor (tonumber (b) or 0)
      end
      local c = key:match ('^%a:(%d+)$')
      return c and math.floor (tonumber (c) or 0) or nil, nil
    end

    ---Scrolls the results so the cursor row shows.
    local function reveal_cursor ()
      local fi, mi = parse (cursor)
      if not fi then
        return
      end
      local top = 0
      for i = 1, fi - 1 do
        local shut = closed[files[i].path]
        top = top + FILE_ROW + (shut and 0 or #files[i].matches * MATCH_ROW)
      end
      local height = mi and MATCH_ROW or FILE_ROW
      local above = mi and (mi - 1) or 0
      top = top + (mi and FILE_ROW or 0) + above * MATCH_ROW
      local scroll = tonumber (results:get ('scrollTop')) or 0
      local view = tonumber (results:get ('clientHeight')) or 0
      if top < scroll then
        results:set ('scrollTop', top)
      elseif top + height > scroll + view then
        results:set ('scrollTop', top + height - view)
      end
    end

    ---Moves the cursor to another row.
    ---@param key string?
    local function set_cursor (key)
      if key == cursor then
        return
      end
      local old = parse (cursor)
      cursor = key
      local new = parse (key)
      draw_group (old)
      if new ~= old then
        draw_group (new)
      end
      reveal_cursor ()
    end

    ---@param fi integer
    local function toggle_file (fi)
      local f = files[fi]
      if not f then
        return
      end
      closed[f.path] = not closed[f.path] or nil
      if closed[f.path] and parse (cursor) == fi then
        cursor = 'f:' .. fi
      end
      draw_group (fi)
    end

    -- History -----------------------------------------------------------------------------

    local function remember_query ()
      local text = query:value () or ''
      if text ~= '' then
        history = core.remember (history, text, HISTORY)
        app.store.set ('history', history)
      end
    end

    ---@param step 1|-1 1 goes to an older search.
    ---@return boolean moved
    local function browse_history (step)
      local at = hist_at + step ---@type integer
      if at < 0 or at > #history then
        return false
      end
      if hist_at == 0 then
        hist_draft = query:value () or ''
      end
      hist_at = at
      query:value (at == 0 and hist_draft or history[at])
      return true
    end

    -- Opening matches -------------------------------------------------------------------

    ---@param fi integer
    ---@param mi integer
    ---@param keep_focus? boolean
    local function open_match (fi, mi, keep_focus)
      local f = files[fi]
      local m = f and f.matches[mi]
      if not (f and m) then
        return
      end
      remember_query ()
      open_file (
        disk.join (folder, f.path),
        { line = m.line, col = m.col, keep_focus = keep_focus }
      )
    end

    ---Opens the next or the previous match, and shows it in the results.
    ---@param step 1|-1
    local function go_match (step)
      local fi, mi = parse (cursor)
      if cursor and not cursor:find ('^m:') then
        mi = nil
      end
      local nf, nm = core.next_match (files, fi, mi, step)
      if not (nf and nm) then
        return
      end
      if closed[files[nf].path] then
        closed[files[nf].path] = nil
        draw_group (nf)
      end
      set_cursor ('m:' .. nf .. ':' .. nm)
      open_match (nf, nm)
    end

    -- Replacing ---------------------------------------------------------------------------

    ---The open document of a path from the folder, if one is open and can change.
    ---@param rel string
    ---@return Proteus.DocInfo?
    local function open_doc (rel)
      local editor = app.try_use ('editor')
      for _, info in ipairs (editor and editor.docs () or {}) do
        if
          not info.readonly
          and info.external
          and project.relative (info.path) == rel
        then
          return info
        end
      end
      return nil
    end

    ---Changes one file's text. An open document changes in the editor, as one edit its undo
    ---takes back. Any other file changes on disk.
    ---@param rel string
    ---@param transform fun(text: string, cb: fun(after: string?, problem: string?, count: integer?))
    ---@param done fun(change: CodeSearch.Change?, problem: string?, count: integer)
    local function change_file (rel, transform, done)
      local editor = app.try_use ('editor')
      local doc = open_doc (rel)
      if doc and editor then
        local before = doc.text ()
        transform (before, function (after, problem, count)
          if not after or after == before then
            done (nil, problem, 0)
          elseif doc.text () ~= before then
            done (nil, rel .. ' changed while it was being replaced.', 0)
          elseif editor.set_text (doc.path, after) then
            done (
              { path = rel, doc = doc.path, before = before, after = after },
              nil,
              count or 0
            )
          else
            done (nil, rel .. ' cannot change.', 0)
          end
        end)
        return
      end
      local full = disk.join (folder, rel)
      app.fs.read_file (full, function (before, err)
        if type (before) ~= 'string' then
          done (nil, err or ('Could not read ' .. rel .. '.'), 0)
          return
        end
        transform (before, function (after, problem, count)
          if not after or after == before then
            done (nil, problem, 0)
            return
          end
          app.fs.write_file (full, after, function (_, write_err)
            if write_err then
              done (nil, write_err, 0)
            else
              done (
                { path = rel, before = before, after = after },
                nil,
                count or 0
              )
            end
          end)
        end)
      end)
    end

    ---@type fun()
    local undo_replace

    ---Ends a replace: keeps what changed for Undo, says what happened, and searches again.
    ---@param changes CodeSearch.Change[]
    ---@param count integer
    ---@param problems string[]
    local function replaced (changes, count, problems)
      replacing = false
      if #changes > 0 then
        undo = changes
        note = {
          text = 'Replaced '
            .. count
            .. (count == 1 and ' match' or ' matches')
            .. ' in '
            .. #changes
            .. (#changes == 1 and ' file.' or ' files.'),
          action = { label = 'Undo', run = undo_replace },
        }
      end
      if #problems > 0 then
        report (problems[1])
      end
      run (true)
    end

    ---Replaces every match in the listed files, as the shown search finds them now.
    ---@param list CodeSearch.File[]
    local function replace_files (list)
      local opts = shown_opts
      if replacing or not opts or opts.replace == nil or #list == 0 then
        return
      end
      ---@type Proteus.SearchOptions
      local with = {
        case = opts.case,
        word = opts.word,
        regex = opts.regex,
        replace = replace_box:value () or '',
      }
      local text = shown_query
      remember_query ()
      replacing = true
      set_status ('Replacing…')
      local changes, problems = {}, {} ---@type CodeSearch.Change[], string[]
      local count, left = 0, #list
      for _, f in ipairs (list) do
        change_file (f.path, function (before, cb)
          app.fs.replace_text (before, text, with, function (result, err)
            if result then
              cb (result.text, nil, result.count)
            else
              cb (nil, err, 0)
            end
          end)
        end, function (change, problem, n)
          if change then
            changes[#changes + 1] = change
            count = count + n
          elseif problem then
            problems[#problems + 1] = problem
          end
          left = left - 1
          if left == 0 then
            replaced (changes, count, problems)
          end
        end)
      end
    end

    ---Replaces one match, where the search found it.
    ---@param fi integer
    ---@param mi integer
    local function replace_match (fi, mi)
      local f = files[fi]
      local m = f and f.matches[mi]
      if replacing or not (f and m) then
        return
      end
      remember_query ()
      replacing = true
      change_file (f.path, function (text, cb)
        local after, problem = core.replace_one (text, m)
        cb (after, problem, after and 1 or 0)
      end, function (change, problem)
        if not change and problem then
          replacing = false
          report (problem)
          return
        end
        replaced (change and { change } or {}, change and 1 or 0, {})
      end)
    end

    local function replace_all ()
      local p = app.try_use ('picker')
      if replacing or #files == 0 or not shown_opts or not p then
        return
      end
      local count = 0
      for _, f in ipairs (files) do
        count = count + #f.matches
      end
      local with = replace_box:value () or ''
      p.confirm ({
        message = 'Replace '
          .. (truncated and 'the matches in ' or (count .. (count == 1 and ' match in ' or ' matches in ')))
          .. #files
          .. (#files == 1 and ' file' or ' files')
          .. (with == '' and ' with nothing' or (' with "' .. with .. '"'))
          .. '?'
          .. (
            truncated
              and ' The search was cut short, so files past the first ' .. LIMIT .. ' results stay as they are.'
            or ''
          ),
        yes = 'Replace All',
        on_yes = function ()
          replace_files (files)
        end,
      })
    end

    undo_replace = function ()
      local list = undo
      if not list or replacing then
        return
      end
      undo, note = nil, nil
      replacing = true
      set_status ('Undoing the replace…')
      local editor = app.try_use ('editor')
      local left, missed = #list, 0
      local function one_done ()
        left = left - 1
        if left > 0 then
          return
        end
        replacing = false
        if missed > 0 then
          report (
            missed
              .. (missed == 1 and ' file' or ' files')
              .. ' changed again since the replace, so '
              .. (missed == 1 and 'it stays' or 'they stay')
              .. ' as it is now.'
          )
        end
        run (true)
      end
      for _, c in ipairs (list) do
        local change = c
        local doc = change.doc
        if doc then
          local info = open_doc (change.path)
          if editor and info and info.text () == change.after then
            editor.set_text (doc, change.before)
          else
            missed = missed + 1
          end
          one_done ()
        else
          local full = disk.join (folder, change.path)
          app.fs.read_file (full, function (now)
            if now ~= change.after then
              missed = missed + 1
              one_done ()
              return
            end
            app.fs.write_file (full, change.before, function (_, err)
              if err then
                missed = missed + 1
              end
              one_done ()
            end)
          end)
        end
      end
    end

    -- Searching ---------------------------------------------------------------------------

    local function stop ()
      if running then
        running.cancel ()
        running = nil
        set_status ('The search was stopped.')
      end
    end

    ---The include patterns: the typed ones, or with Search Only in Open Editors, the open
    ---files that fit them. Nil when no open file is left to search.
    ---@return string[]?
    local function include_globs ()
      local typed = core.globs (include:value () or '')
      if not options.open_only then
        return typed
      end
      local editor = app.try_use ('editor')
      local out = {} ---@type string[]
      for _, info in ipairs (editor and editor.docs () or {}) do
        local rel = info.external and project.relative (info.path) or nil
        if rel and rel ~= '' then
          local fits = #typed == 0
          for _, g in ipairs (typed) do
            fits = fits or file_glob.matches (g, '/' .. rel, fold_case)
          end
          if fits then
            out[#out + 1] = core.exact_glob (rel)
          end
        end
      end
      return #out > 0 and out or nil
    end

    ---Searches with what the boxes hold. `keep` searches again for the same text, such as
    ---after files changed, and keeps the folded files and the cursor.
    ---@param keep? boolean
    run = function (keep)
      if cancel_pause then
        cancel_pause ()
        cancel_pause = nil
      end
      if cancel_refresh then
        cancel_refresh ()
        cancel_refresh = nil
      end
      if running then
        running.cancel ()
        running = nil
      end
      seq = seq + 1
      local mine = seq
      local text = query:value () or ''
      app.store.set ('query', text)
      if not keep then
        note = nil
      end
      if text == '' then
        files, shown_opts, cursor = {}, nil, nil
        set_status ('')
        draw ()
        return
      end
      local includes = include_globs ()
      if not includes then
        files, shown_opts, cursor = {}, nil, nil
        draw ()
        set_status ('No files are open in the editor.')
        return
      end
      local excludes = core.globs (exclude:value () or '')
      for _, p in ipairs (project.excluded ()) do
        excludes[#excludes + 1] = p
      end
      ---@type Proteus.SearchOptions
      local opts = {
        case = options.case == true,
        word = options.word == true,
        regex = options.regex == true,
        include = includes,
        exclude = excludes,
        limit = LIMIT,
        replace = options.replace_open and (replace_box:value () or '') or nil,
      }
      set_status ('Searching…', false, { label = 'Stop', run = stop })
      running = app.fs.search_dir (folder, text, opts, function (result, err)
        if mine ~= seq then
          return
        end
        running = nil
        if not result then
          files, shown_opts, cursor = {}, nil, nil
          draw ()
          set_status (err or 'The search failed.', true)
          return
        end
        local old_cursor = nil ---@type Proteus.SearchMatch|string|nil
        if keep then
          local fi, mi = parse (cursor)
          local f = fi and files[fi]
          old_cursor = f and (mi and f.matches[mi] or f.path) or nil
        else
          closed = {}
        end
        files = core.by_file (result.matches)
        shown_query, shown_opts = text, opts
        truncated = result.truncated == true
        -- The cursor stays on the same match, or file, when it is still there.
        cursor = nil
        for fi, f in ipairs (files) do
          if old_cursor == f.path then
            cursor = 'f:' .. fi
          elseif type (old_cursor) == 'table' and old_cursor.path == f.path then
            for mi, m in ipairs (f.matches) do
              if m.line == old_cursor.line and m.col == old_cursor.col then
                cursor = 'm:' .. fi .. ':' .. mi
              end
            end
          end
        end
        draw ()
        local summary = core.summary (#result.matches, #files, truncated)
        if note then
          set_status (note.text .. ' ' .. summary, false, note.action)
        else
          set_status (summary)
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

    -- Changes on disk show in the results. A replace searches again once it is done.
    app.on ('code:disk_changed', function (changes, ev)
      if (query:value () or '') == '' then
        return
      end
      local any = type (ev) == 'table' and ev.overflow == true
      for _, change in
        ipairs (changes or {} --[[@as Proteus.DirChange[] ]])
      do
        any = any or not change.ignored
      end
      if not any or replacing then
        return
      end
      if cancel_refresh then
        cancel_refresh ()
      end
      cancel_refresh = app.timer.after (REFRESH, function ()
        cancel_refresh = nil
        if not replacing and not cancel_pause then
          run (true)
        end
      end)
    end)

    -- The form ----------------------------------------------------------------------------

    ---@param key string
    ---@param label string|Proteus.El
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

    local replace_all_button = ui.button ({
      class = 'search-toggle',
      title = 'Replace All (Ctrl+Alt+Enter)',
      ui.icon ('replace-all', 14),
    })
    replace_all_button:on ('click', function ()
      replace_all ()
      return nil
    end)
    local replace_row = ui.div ({
      class = 'search-row',
      replace_box,
      replace_all_button,
    })

    local fold_button = ui.button ({
      class = 'search-fold',
      title = 'Toggle Replace',
    })

    -- An older Proteus has no `replace_text`, so it searches without the replace box.
    local can_replace = app.fs.replace_text ~= nil
    fold_button:show (can_replace)

    ---@param on boolean
    local function show_replace (on)
      on = on and can_replace
      options.replace_open = on == true
      app.store.set ('options', options)
      replace_row:show (on)
      fold_button:set_children ({
        ui.icon (on and 'chevron-down' or 'chevron-right', 14),
      })
    end
    show_replace (options.replace_open == true)
    fold_button:on ('click', function ()
      show_replace (not options.replace_open)
      run (true)
      return nil
    end)

    local more_rows = ui.div ({
      class = 'search-form',
      style = { padding = '0' },
      ui.div ({
        class = 'search-row',
        include,
        toggle (
          'open_only',
          ui.icon ('book-open', 14),
          'Search Only in Open Editors'
        ),
      }),
      ui.div ({ class = 'search-row', exclude }),
    })
    local show_more = options.more == true
    more_rows:show (show_more)
    local more = ui.button ({
      class = 'search-more',
      show_more and 'Hide file filters' or 'File filters…',
    })

    ---@param on boolean
    local function set_more (on)
      show_more = on
      options.more = on
      app.store.set ('options', options)
      more_rows:show (on)
      more:text (on and 'Hide file filters' or 'File filters…')
    end
    more:on ('click', function ()
      set_more (not show_more)
      return nil
    end)

    for _, box in ipairs ({ query, replace_box, include, exclude }) do
      local this = box
      this:on ('input', function ()
        if this == query then
          hist_at = 0
        end
        run_soon ()
        return nil
      end)
      this:on ('keydown', function (ev)
        if ev.composing then
          return nil
        end
        local ctrl = ev.ctrl or ev.meta
        if ev.key == 'Enter' and ctrl and ev.alt then
          replace_all ()
          return 'stop'
        elseif ev.key == 'Enter' then
          remember_query ()
          run ()
          return 'stop'
        elseif ev.key == 'Escape' and running then
          stop ()
          return 'stop'
        elseif ev.key == 'ArrowDown' and ctrl then
          results:focus ()
          return 'stop'
        elseif
          this == query
          and not ctrl
          and not ev.alt
          and (ev.key == 'ArrowUp' or ev.key == 'ArrowDown')
        then
          if browse_history (ev.key == 'ArrowUp' and 1 or -1) then
            run_soon ()
            return 'stop'
          end
        end
        return nil
      end)
    end

    -- The results -------------------------------------------------------------------------

    results:on ('click', function (ev)
      local item = ev.item
      if not item then
        return nil
      end
      local fi, mi = parse (item)
      local kind = item:sub (1, 1)
      if not fi then
        return nil
      elseif kind == 'r' and mi then
        replace_match (fi, mi)
      elseif kind == 'R' then
        local f = files[fi]
        if f then
          replace_files ({ f })
        end
      elseif kind == 'f' then
        set_cursor (item)
        toggle_file (fi)
      elseif kind == 'm' and mi then
        set_cursor (item)
        open_match (fi, mi)
      end
      return true
    end)

    results:on ('focus', function ()
      if not cursor and #files > 0 then
        set_cursor ('f:1')
      end
      return nil
    end)

    results:on ('keydown', function (ev)
      if ev.ctrl or ev.meta or ev.alt or ev.composing then
        return nil
      end
      local key = ev.key or ''
      local rows = core.rows (files, closed)
      local at = 0
      for i, r in ipairs (rows) do
        if r.key == cursor then
          at = i
        end
      end
      ---@param i integer
      local function go (i)
        local r = rows[math.max (1, math.min (#rows, i))]
        if r then
          set_cursor (r.key)
        end
      end
      local here = rows[at]
      if key == 'ArrowDown' then
        go (at + 1)
      elseif key == 'ArrowUp' then
        go (at == 0 and #rows or at - 1)
      elseif key == 'PageDown' then
        go (at + 10)
      elseif key == 'PageUp' then
        go (at - 10)
      elseif key == 'Home' then
        go (1)
      elseif key == 'End' then
        go (#rows)
      elseif key == 'ArrowRight' and here then
        if not here.mi and closed[files[here.fi].path] then
          toggle_file (here.fi)
        elseif not here.mi then
          go (at + 1)
        end
      elseif key == 'ArrowLeft' and here then
        if here.mi then
          set_cursor ('f:' .. here.fi)
        elseif not closed[files[here.fi].path] then
          toggle_file (here.fi)
        end
      elseif (key == 'Enter' or key == ' ') and here then
        if here.mi then
          open_match (here.fi, here.mi, key == ' ')
        else
          toggle_file (here.fi)
        end
      elseif key == 'Escape' then
        query:focus ()
      else
        return nil
      end
      return 'stop'
    end)

    local menus = app.try_use ('menus')
    if menus then
      menus.attach (results, function (ev)
        local fi = parse (ev.item)
        local f = fi and files[fi]
        if not f then
          return nil
        end
        local full = disk.join (folder, f.path)
        local replace_on = shown_opts ~= nil and shown_opts.replace ~= nil
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
            label = 'Replace All in File',
            icon = 'replace-all',
            disabled = not replace_on,
            run = function ()
              replace_files ({ f })
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
              if cursor then
                cursor = 'f:' .. (parse (cursor) or 1)
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
          class = 'search-head',
          fold_button,
          ui.div ({
            class = 'search-fields',
            ui.div ({
              class = 'search-row',
              query,
              toggle ('case', 'Aa', 'Match Case'),
              toggle ('word', 'ab', 'Match Whole Word'),
              toggle ('regex', '.*', 'Use Regular Expression'),
            }),
            replace_row,
          }),
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
    ---@param dir? string A full path to search in, instead of the whole folder.
    ---@param with_replace? boolean Opens the replace box too.
    local function show (dir, with_replace)
      views.show ('search')
      if with_replace and not options.replace_open then
        show_replace (true)
      end
      local editor = app.try_use ('editor')
      local doc = editor and editor.current ()
      local picked = doc and doc.selection () or ''
      if picked ~= '' and not picked:find ('\n') then
        query:value (picked)
      end
      if dir then
        local rel = disk.relative (folder, dir, app.os)
        if rel then
          include:value (rel == '' and '' or (rel .. '/**'))
          set_more (true)
        end
      end
      local box = query
      if with_replace and (query:value () or '') ~= '' then
        box = replace_box
      end
      box:focus ()
      box:select ()
      if (query:value () or '') ~= '' then
        run ()
      end
    end

    app.on ('code:search_folder', function (dir)
      show (type (dir) == 'string' and dir or nil)
    end)

    ---@return boolean
    local function has_matches ()
      return #files > 0
    end

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
      commands.register ({
        id = 'search.replace_in_files',
        category = 'Search',
        title = 'Replace in Files',
        key = 'ctrl+shift+h',
        icon = 'replace',
        menu = 'Edit',
        group = 'find',
        order = 36,
        run = function ()
          show (nil, true)
        end,
      })
      commands.register ({
        id = 'search.next_match',
        category = 'Search',
        title = 'Go to Next Search Result',
        key = 'f4',
        icon = 'arrow-down',
        when = has_matches,
        run = function ()
          go_match (1)
        end,
      })
      commands.register ({
        id = 'search.previous_match',
        category = 'Search',
        title = 'Go to Previous Search Result',
        key = 'shift+f4',
        icon = 'arrow-up',
        when = has_matches,
        run = function ()
          go_match (-1)
        end,
      })
      commands.register ({
        id = 'search.stop',
        category = 'Search',
        title = 'Stop Searching',
        icon = 'circle-stop',
        when = function ()
          return running ~= nil
        end,
        run = stop,
      })
      commands.register ({
        id = 'search.refresh',
        category = 'Search',
        title = 'Refresh Search Results',
        icon = 'refresh-cw',
        when = function ()
          return (query:value () or '') ~= ''
        end,
        run = function ()
          run (true)
        end,
      })
      commands.register ({
        id = 'search.undo_replace',
        category = 'Search',
        title = 'Undo the Last Replace in Files',
        icon = 'undo-2',
        when = function ()
          return undo ~= nil
        end,
        run = function ()
          undo_replace ()
        end,
      })
    end

    local last = app.store.get ('query', '')
    if type (last) == 'string' and last ~= '' then
      query:value (last)
    end
  end,
}
