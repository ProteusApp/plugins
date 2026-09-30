-- handbook: the full documentation of Proteus, in a panel in the right dock.
--
-- Pages come from three places. The app's own chapters are Markdown files in
-- docs/handbook/. Any plugin adds pages as Markdown files in a `handbook` folder inside its
-- own folder, or from code through the `handbook` service. The Reference section is built
-- from the type files in types/, and from any plugin's own `types` folder, as the app runs,
-- so it always matches the app. lib/ holds the parts that touch nothing on screen: reading
-- pages, coloring code, building the reference and searching.

local library = require ('lib.library')
local page = require ('lib.page')
local reference = require ('lib.reference')
local render = require ('lib.render')

-- lang=css
local CSS = [[
.hb { display: flex; flex-direction: column; height: 100%; min-height: 0; }
.hb-bar { display: flex; align-items: center; gap: 2px; padding: 6px 8px; border-bottom: 1px solid var(--border);
  flex: none; }
.hb-bar .ui-input { flex: 1; min-width: 0; height: 26px; margin: 0 4px; }
.hb-icon { display: inline-grid; place-items: center; flex: none; width: 26px; height: 26px; padding: 0;
  border: none; border-radius: var(--radius); background: none; color: var(--fg-muted); cursor: pointer; }
.hb-icon:hover:not(:disabled) { background: var(--bg-hover); color: var(--fg); }
.hb-icon:disabled { opacity: .35; cursor: default; }
.hb-scroll { flex: 1; min-height: 0; overflow: auto; padding: 14px 16px 48px; }
.hb-wide .hb-scroll { padding: 28px 32px 80px; }
.hb-wide .hb-view { max-width: 820px; margin: 0 auto; }
.hb-crumbs { display: flex; align-items: center; flex-wrap: wrap; gap: 6px; margin-bottom: 4px; color: var(--fg-faint);
  font-size: 11px; letter-spacing: .06em; text-transform: uppercase; }
.hb-badge { padding: 0 6px; border: 1px solid var(--border); border-radius: 999px; color: var(--fg-muted);
  font-family: var(--font-mono); font-size: 10.5px; letter-spacing: 0; text-transform: none; }
.hb-badge.off { border-color: color-mix(in srgb, var(--warning) 45%, transparent); color: var(--warning); }
.hb-toc { margin: 6px 0 14px; border: 1px solid var(--border); border-radius: 8px; background: var(--bg-alt); }
.hb-toc-head { display: flex; align-items: center; gap: 6px; padding: 6px 10px; color: var(--fg-muted); font-size: 12px;
  cursor: pointer; user-select: none; }
.hb-toc-head .ui-icon { transition: transform .12s; }
.hb-toc.open .hb-toc-head .ui-icon { transform: rotate(90deg); }
.hb-toc-list { display: none; padding: 0 6px 6px; }
.hb-toc.open .hb-toc-list { display: block; }
.hb-toc-row { overflow: hidden; padding: 3px 6px; border-radius: 4px; color: var(--fg-muted); font-size: 12px;
  text-overflow: ellipsis; white-space: nowrap; cursor: pointer; }
.hb-toc-row.l3 { padding-left: 18px; }
.hb-toc-row:hover { background: var(--bg-hover); color: var(--fg); }
.hb-body { line-height: 1.6; }
.hb-body p, .hb-body li { overflow-wrap: anywhere; }
.hb-body h1 { margin: 2px 0 10px; font-size: 21px; letter-spacing: -.01em; }
.hb-body h2 { margin: 26px 0 8px; padding-top: 12px; border-top: 1px solid var(--border); font-size: 16px; }
.hb-body h3 { margin: 20px 0 6px; font-size: 14px; }
.hb-body h4 { margin: 18px 0 6px; font-family: var(--font-mono); font-size: 12.5px; }
.hb-body p { margin: 8px 0; }
.hb-body ul, .hb-body ol { padding-left: 20px; }
.hb-body table { display: block; overflow-x: auto; margin: 10px 0; border-collapse: collapse; font-size: 12.5px; }
.hb-body th, .hb-body td { min-width: 4.5em; padding: 4px 8px; border: 1px solid var(--border); text-align: left;
  vertical-align: top; }
.hb-body td:first-child, .hb-body th:first-child { white-space: nowrap; }
.hb-body td:last-child { min-width: 14em; }
.hb-body th { background: var(--bg-alt); }
.hb-body blockquote { margin: 10px 0; padding: 6px 12px; border-left: 3px solid var(--accent); border-radius: 0 6px 6px 0;
  background: color-mix(in srgb, var(--accent) 8%, transparent); }
.hb-body blockquote p { margin: 4px 0; }
.hb-body a { color: var(--accent); text-decoration: none; cursor: pointer; }
.hb-body a:hover { text-decoration: underline; }
.hb-body a[data-item]:not([data-page])::after { content: ' \2197'; font-size: 10px; }
.hb-body :not(pre) > code { padding: 1px 4px; border-radius: 4px; background: var(--bg-alt);
  font-family: var(--font-mono); font-size: .92em; }
.hb-code { margin: 10px 0; overflow: hidden; border: 1px solid var(--border); border-radius: 8px;
  background: var(--editor-bg, var(--bg-alt)); }
.hb-code-head { display: flex; align-items: center; justify-content: space-between; min-height: 22px;
  padding: 2px 4px 2px 10px; border-bottom: 1px solid var(--border); color: var(--fg-faint);
  font-family: var(--font-mono); font-size: 11px; }
.hb-copy { padding: 2px 8px; border: none; border-radius: 4px; background: none; color: var(--fg-muted);
  font: inherit; cursor: pointer; }
.hb-copy:hover { background: var(--bg-hover); color: var(--fg); }
.hb-code pre { margin: 0; padding: 10px 12px; overflow: auto; border-radius: 0; background: none;
  font-family: var(--font-mono); font-size: 12px; line-height: 1.55; }
.hb-code code { padding: 0; background: none; }
.hb-k { color: var(--syn-keyword); }
.hb-s { color: var(--syn-string); }
.hb-n { color: var(--syn-number); }
.hb-o { color: var(--syn-constant); }
.hb-c { color: var(--syn-comment); font-style: italic; }
.hb-f { color: var(--syn-function); }
.hb-p { color: var(--syn-property); }
.hb-b { color: var(--syn-builtin); }
.hb-home h1 { margin: 2px 0 2px; font-size: 21px; }
.hb-lead { margin: 0 0 6px; color: var(--fg-muted); line-height: 1.5; }
.hb-sec-title { margin: 18px 0 4px; padding: 0 8px; color: var(--fg-faint); font-size: 11px; letter-spacing: .07em;
  text-transform: uppercase; }
.hb-row { display: flex; align-items: center; gap: 8px; padding: 5px 8px; border-radius: 6px; cursor: pointer; }
.hb-row:hover, .hb-hit:hover { background: var(--bg-hover); }
.hb-row .t { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.hb-row .s { flex: none; color: var(--fg-faint); font-family: var(--font-mono); font-size: 10.5px; }
.hb-hit { padding: 7px 8px; border-radius: 6px; cursor: pointer; }
.hb-hit .l { font-weight: 600; }
.hb-hit .c { margin-left: 6px; color: var(--fg-faint); font-size: 11.5px; }
.hb-hit .x { margin-top: 2px; color: var(--fg-muted); font-size: 12px; line-height: 1.45; }
.hb-hit.first { background: var(--bg-hover); }
.hb-foot { display: flex; gap: 8px; margin-top: 28px; padding-top: 12px; border-top: 1px solid var(--border); }
.hb-nav { flex: 1; min-width: 0; padding: 8px 10px; border: 1px solid var(--border); border-radius: 8px;
  font-size: 12px; cursor: pointer; }
.hb-nav:hover { border-color: var(--accent); }
.hb-nav.next { text-align: right; }
.hb-nav small { display: block; color: var(--fg-faint); }
.hb-nav span { display: block; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.hb-from { margin-top: 18px; color: var(--fg-faint); font-family: var(--font-mono); font-size: 11px;
  word-break: break-all; }
.hb-empty { padding: 20px 4px; color: var(--fg-muted); line-height: 1.6; }
]]

-- The type files the app ships, with the names their reference pages go by.
local TYPE_TITLES = {
  proteus = 'The app table and plugins',
  services = 'Services',
  ui = 'Elements and the ui library',
  http = 'HTTP',
  nodal = 'Nodal',
}

---Where a reader is: a page and a heading on it, or the contents when `id` is nil.
---@class Handbook.Place
---@field id? string
---@field anchor? string

---@class Handbook.Reader
---@field root Proteus.El
---@field go fun(id?: string, anchor?: string): boolean Shows a page, or the contents when `id` is nil.
---@field redraw fun() Draws the view again after the pages changed.
---@field current fun(): string? The id of the page in view.
---@field search fun() Puts the cursor in the search box.

---@type Proteus.Plugin
return {
  name = 'Handbook',
  description = 'The full documentation of Proteus in a side panel, with examples, and every plugin can add pages to it.',
  version = '1.0.0',
  requires = { proteus = '>=0.2.0', features = { 'permissions' } },
  permissions = { 'net' },
  depends = { 'lib.ui', 'ui.views' },
  optional = { 'core.commands', 'ui.palette', 'ui.tabs', 'ui.notify' },
  activate = function (app)
    local ui = app.use ('ui')
    local views = app.use ('views')
    local commands = app.try_use ('commands')
    local picker = app.try_use ('picker')
    local tabs = app.try_use ('tabs')
    local notify = app.try_use ('notify')
    ui.css (CSS)

    local pages = library.new ()
    local file_ids = {} ---@type table<string, true> Pages that came from files.
    local type_texts = {} ---@type table<string, string> The text each type page was built from.
    local type_active = {} ---@type table<string, boolean> Whether each type page's plugin runs.
    local type_links = {} ---@type table<string, string> A class or alias name, and its page and anchor.
    local readers = {} ---@type table<Handbook.Reader, Handbook.Reader>

    ---@param name string
    ---@return string?
    local function link_type (name)
      return type_links[name]
    end

    ---@param text string
    local function say (text)
      if notify then
        notify.info (text)
      end
    end

    ---Reads every page that comes from a file: the app's chapters, each plugin's handbook
    ---folder, and the type files.
    local function scan ()
      local by_dir = {} ---@type table<string, Proteus.PluginInfo>
      for _, info in ipairs (app.kernel.plugins ()) do
        local dir = info.path:match ('^(.*)/init%.lua$')
        if dir then
          by_dir[dir] = info
        end
      end
      local seen = {} ---@type table<string, true>
      local types = {} ---@type { id: string, path: string, title: string, order: number, info?: Proteus.PluginInfo }[]

      for _, path in ipairs (app.fs.files ()) do
        local dir, name = path:match ('^(.+)/handbook/([%w_.%-]+)%.md$') ---@type string?, string
        local info = dir and by_dir[dir]
        if dir == 'docs' or info then
          local id = (info and info.id or 'proteus') .. '/' .. name
          local text = app.fs.read (path)
          if text and not seen[id] then
            seen[id] = true
            pages.set (id, {
              source = info and info.id or 'proteus',
              name = name --[[@as string]],
              markdown = text,
              origin = 'file',
              plugin_name = info and info.name or 'Proteus',
              active = not info or info.status == 'active',
              path = path,
            })
          end
        end
        local stem = path:match ('^types/([%w_.%-]+)%.lua$')
        if stem then
          types[#types + 1] = {
            id = 'types/' .. stem,
            path = path,
            title = TYPE_TITLES[stem] or ('Types: ' .. stem),
            order = 900,
          }
        end
        local pdir, pstem = path:match ('^(.+)/types/([%w_.%-]+)%.lua$')
        local owner = pdir and by_dir[pdir]
        if owner then
          types[#types + 1] = {
            id = owner.id .. '/types/' .. pstem,
            path = path,
            title = owner.name .. ' types: ' .. pstem,
            order = 950,
            info = owner,
          }
        end
      end

      -- Every class and alias links to its heading, from any reference page.
      local texts = {} ---@type table<string, string>
      type_links = {}
      for _, t in ipairs (types) do
        local text = app.fs.read (t.path) or ''
        texts[t.id] = text
        for _, name in ipairs (reference.names (text)) do
          type_links[name] = type_links[name]
            or (t.id .. '.md#' .. page.slug (name))
        end
      end
      for _, t in ipairs (types) do
        seen[t.id] = true
        local text = texts[t.id]
        local active = not t.info or t.info.status == 'active'
        if type_texts[t.id] ~= text or type_active[t.id] ~= active then
          type_texts[t.id], type_active[t.id] = text, active
          local title, path, order = t.title, t.path, t.order
          pages.set (t.id, {
            source = t.info and t.info.id or 'types',
            name = t.info and ('types/' .. t.id:match ('([^/]+)$'))
              or t.id:sub (7),
            markdown = function ()
              local md = reference.build (text, {
                title = title,
                source = path,
                link = link_type,
              })
              return '---\nsection: Reference\norder: '
                .. order
                .. '\nkeywords: types api reference\n---\n'
                .. md
            end,
            origin = 'types',
            plugin_name = t.info and t.info.name or 'Proteus',
            active = active,
            path = path,
          })
        end
      end

      for id in pairs (file_ids) do
        if not seen[id] then
          pages.remove (id)
          type_texts[id], type_active[id] = nil, nil
        end
      end
      file_ids = seen
      for _, r in pairs (readers) do
        r.redraw ()
      end
    end

    local scan_pending = false
    local function soon ()
      if scan_pending then
        return
      end
      scan_pending = true
      app.timer.after (250, function ()
        scan_pending = false
        scan ()
      end)
    end

    ---@param path any
    ---@return boolean
    local function is_page_file (path)
      return type (path) == 'string'
        and (
          path:match ('/handbook/[^/]+%.md$') ~= nil
          or path:match ('^types/[^/]+%.lua$') ~= nil
          or path:match ('/types/[^/]+%.lua$') ~= nil
        )
    end

    app.on ('fs:changed', function (path)
      if is_page_file (path) then
        soon ()
      end
    end)
    app.on ('fs:renamed', function (from, to)
      if is_page_file (from) or is_page_file (to) then
        soon ()
      end
    end)
    for _, event in ipairs ({
      'kernel:plugin_started',
      'kernel:plugin_stopped',
      'kernel:plugin_reloaded',
    }) do
      app.on (event, soon)
    end

    ---A reader: the search bar, the contents, pages and search results. The panel has one,
    ---and so does each page opened in a tab.
    ---@param opts { wide?: boolean, on_title?: fun(title: string) }
    ---@return Handbook.Reader
    local function new_reader (opts)
      local back, forward = {}, {} ---@type Handbook.Place[], Handbook.Place[]
      local here = {} ---@type Handbook.Place
      local shown ---@type Handbook.Page?
      local shown_version = -1
      local codes = {} ---@type string[]
      local anchors = {} ---@type table<string, Proteus.El>
      local hits = {} ---@type Handbook.Hit[]
      local query = ''
      local search_pending = false

      local scroll = ui.div ({ class = 'hb-scroll' })
      local back_button, forward_button, input ---@type Proteus.El, Proteus.El, Proteus.El

      ---@param icon string
      ---@param title string
      ---@param fn fun()
      ---@return Proteus.El
      local function icon_button (icon, title, fn)
        return ui.h ('button', {
          class = 'hb-icon',
          title = title,
          ui.icon (icon, 15),
          onclick = function ()
            fn ()
            return 'stop'
          end,
        })
      end

      local function update_buttons ()
        back_button:set ('disabled', #back == 0)
        forward_button:set ('disabled', #forward == 0)
      end

      ---Scrolls so a heading sits at the top of the view.
      ---@param el Proteus.El
      local function jump (el)
        local now = tonumber (scroll:get ('scrollTop')) or 0
        local top = el:rect ().top - scroll:rect ().top + now - 8
        scroll:set ('scrollTop', math.max (0, top))
      end

      ---@param text string
      ---@return string
      local function esc (text)
        return app.util.escape (text)
      end

      local function draw_home ()
        shown = nil
        local sections = pages.sections ()
        local count, plugins = 0, {} ---@type integer, table<string, true>
        local html = {} ---@type string[]
        for _, section in ipairs (sections) do
          html[#html + 1] = '<div class="hb-sec-title">'
            .. esc (section.name)
            .. '</div>'
          for _, p in ipairs (section.pages) do
            count = count + 1
            plugins[p.source] = true
            html[#html + 1] = '<div class="hb-row" data-item="page:'
              .. esc (p.id)
              .. '" title="'
              .. esc (p.id)
              .. '"><span class="t">'
              .. esc (p.title)
              .. '</span>'
              .. (p.active and '' or '<span class="hb-badge off">Off</span>')
              .. '</div>'
          end
        end
        local sources = 0
        for _ in pairs (plugins) do
          sources = sources + 1
        end
        scroll:set_children ({
          ui.div ({
            class = 'hb-view hb-home',
            ui.h ('h1', 'Handbook'),
            ui.h ('p', {
              class = 'hb-lead',
              html = count
                .. ' pages from '
                .. sources
                .. ' plugins and the app. Search above, or pick a page. Any plugin can add pages to it: '
                .. '<a class="ui-link" data-item="page:handbook/writing-pages">Writing handbook pages</a> shows how.',
            }),
            ui.div ({ html = table.concat (html) }),
          }),
        })
        scroll:set ('scrollTop', 0)
        if opts.on_title then
          opts.on_title ('Handbook')
        end
      end

      ---@param id string
      local function draw_missing (id)
        shown = nil
        scroll:set_children ({
          ui.div ({
            class = 'hb-view hb-empty',
            ui.h ('p', "There is no page called '" .. id .. "'."),
            ui.h ('p', {
              html = 'Its plugin may have been removed, or the link may be wrong. <a class="ui-link" data-item="page:">Show the contents</a>.',
            }),
          }),
        })
      end

      ---@param p Handbook.Page
      ---@return Proteus.El?
      local function toc_of (p)
        local rows = {} ---@type string[]
        for _, h in ipairs (p.doc.headings) do
          if h.level == 2 or h.level == 3 then
            rows[#rows + 1] = '<div class="hb-toc-row l'
              .. h.level
              .. '" data-item="page:'
              .. esc (p.id .. '#' .. h.anchor)
              .. '">'
              .. esc (page.plain (h.text))
              .. '</div>'
          end
        end
        if #rows < 2 then
          return nil
        end
        local toc ---@type Proteus.El
        toc = ui.div ({
          class = 'hb-toc',
          ui.div ({
            class = 'hb-toc-head',
            ui.icon ('chevron-right', 13),
            'On this page (' .. #rows .. ')',
            onclick = function ()
              toc:class ('open', not toc:has_class ('open'))
              return 'stop'
            end,
          }),
          ui.div ({ class = 'hb-toc-list', html = table.concat (rows) }),
        })
        return toc
      end

      ---@param p Handbook.Page
      ---@param anchor? string
      ---@param keep_scroll? number
      local function draw_page (p, anchor, keep_scroll)
        shown, shown_version = p, pages.version ()
        local parts
        parts, codes =
          render.parts (p.doc, p.source, p.name, app.util.safe_markdown)
        anchors = {}
        local body = ui.div ({ class = 'hb-body' })
        if not p.doc.blocks[1] or p.doc.blocks[1].level ~= 1 then
          body:append (ui.h ('h1', p.title))
        end
        for _, part in ipairs (parts) do
          local heading = part.heading
          if heading then
            local el = ui.div ({
              html = render.heading (
                heading,
                p.source,
                p.name,
                app.util.safe_markdown
              ),
            })
            anchors[heading.anchor or ''] = el
            body:append (el)
          end
          if part.html ~= '' then
            body:append (ui.div ({ html = part.html }))
          end
        end

        local before, after = pages.neighbors (p.id)
        ---@param other Handbook.Page?
        ---@param class string
        ---@param label string
        ---@return Proteus.El
        local function nav (other, class, label)
          if not other then
            return ui.div ({ class = 'hb-grow', style = { flex = '1' } })
          end
          return ui.div ({
            class = 'hb-nav ' .. class,
            attrs = { ['data-item'] = 'page:' .. other.id },
            ui.h ('small', label),
            ui.span ({ other.title }),
          })
        end

        local crumbs = ui.div ({
          class = 'hb-crumbs',
          ui.span ({ p.section }),
          ui.span ({ class = 'hb-badge', p.source }),
          not p.active and ui.span ({
            class = 'hb-badge off',
            title = 'The plugin this page belongs to is not running.',
            'Off',
          }) or nil,
        })

        scroll:set_children ({
          ui.div ({
            class = 'hb-view hb-page',
            crumbs,
            toc_of (p),
            body,
            ui.div ({
              class = 'hb-foot',
              nav (before, 'prev', 'Previous'),
              nav (after, 'next', 'Next'),
            }),
            p.path and ui.div ({ class = 'hb-from', 'From ' .. p.path }) or nil,
          }),
        })
        local target = anchor and anchors[anchor]
        if target then
          jump (target)
          -- Once fonts and code have settled, the heading may have moved.
          app.timer.after (60, function ()
            if shown == p and anchors[anchor] == target then
              jump (target)
            end
          end)
        else
          scroll:set ('scrollTop', keep_scroll or 0)
        end
        if opts.on_title then
          opts.on_title (p.title)
        end
      end

      local function draw_here ()
        if here.id then
          local p = pages.get (here.id)
          if p then
            draw_page (p, here.anchor)
          else
            draw_missing (here.id)
          end
        else
          draw_home ()
        end
      end

      local function draw_results ()
        shown = nil
        if #hits == 0 then
          scroll:set_children ({
            ui.div ({
              class = 'hb-view hb-empty',
              "Nothing matches '" .. query .. "'.",
            }),
          })
          return
        end
        local html = {} ---@type string[]
        for i, hit in ipairs (hits) do
          html[#html + 1] = '<div class="hb-hit'
            .. (i == 1 and ' first' or '')
            .. '" data-item="page:'
            .. esc (hit.id .. (hit.anchor and ('#' .. hit.anchor) or ''))
            .. '"><span class="l">'
            .. esc (hit.label)
            .. '</span><span class="c">'
            .. esc (hit.context)
            .. '</span>'
            .. (hit.snippet and ('<div class="x">' .. esc (hit.snippet) .. '</div>') or '')
            .. '</div>'
        end
        scroll:set_children ({
          ui.div ({ class = 'hb-view', html = table.concat (html) }),
        })
        scroll:set ('scrollTop', 0)
      end

      ---Moves to a place and remembers where it was.
      ---@param id? string
      ---@param anchor? string
      ---@return boolean found
      local function go (id, anchor)
        if query ~= '' then
          query = ''
          input:value ('')
        end
        if id == '' then
          id = nil
        end
        local same = here.id == id and shown ~= nil
        if here.id ~= id or here.anchor ~= anchor then
          back[#back + 1] = here
          forward = {}
        end
        here = { id = id, anchor = anchor }
        update_buttons ()
        if id and not opts.wide then
          app.store.set ('last', id)
        end
        if same and anchor and anchors[anchor] then
          jump (anchors[anchor])
          return true
        end
        draw_here ()
        return id == nil or pages.has (id)
      end

      local function go_back ()
        if #back == 0 then
          return
        end
        forward[#forward + 1] = here
        here = table.remove (back)
        update_buttons ()
        draw_here ()
      end

      local function go_forward ()
        if #forward == 0 then
          return
        end
        back[#back + 1] = here
        here = table.remove (forward)
        update_buttons ()
        draw_here ()
      end

      local function run_search ()
        search_pending = false
        query = input:value ():gsub ('^%s+', ''):gsub ('%s+$', '')
        if query == '' then
          draw_here ()
          return
        end
        hits = pages.find (query, 60)
        draw_results ()
      end

      back_button = icon_button ('arrow-left', 'Back', go_back)
      forward_button = icon_button ('arrow-right', 'Forward', go_forward)
      input = ui.input ({
        placeholder = 'Search the Handbook',
        spellcheck = false,
        oninput = function ()
          if not search_pending then
            search_pending = true
            app.timer.after (120, run_search)
          end
        end,
        onkeydown = function (ev)
          if ev.key == 'Enter' then
            run_search ()
            local first = hits[1]
            if query ~= '' and first then
              go (first.id, first.anchor)
            end
            return 'stop'
          elseif ev.key == 'Escape' and query ~= '' then
            input:value ('')
            run_search ()
            return 'stop'
          end
          return nil
        end,
      })

      local bar = ui.div ({
        class = 'hb-bar',
        back_button,
        forward_button,
        input,
        icon_button ('list', 'Contents', function ()
          go (nil)
        end),
      })
      if tabs and not opts.wide then
        bar:append (
          icon_button ('square-arrow-out-up-right', 'Open in a tab', function ()
            if here.id then
              local tab ---@type Proteus.Tab?
              local reader = new_reader ({
                wide = true,
                on_title = function (title)
                  if tab then
                    tab.set_title (title)
                  end
                end,
              })
              tab = tabs.open ({
                id = 'handbook:' .. here.id,
                title = shown and shown.title or 'Handbook',
                icon = 'book-open',
                content = reader.root,
                on_close = function ()
                  readers[reader] = nil
                  return true
                end,
              })
              reader.go (here.id, here.anchor)
            end
          end)
        )
      end

      local root = ui.div ({
        class = opts.wide and 'hb hb-wide' or 'hb',
        bar,
        scroll,
      })

      scroll:on ('click', function (ev)
        local target = render.target (ev.item)
        if not target then
          return nil
        end
        if target.kind == 'copy' then
          local code = codes[target.n]
          if code then
            app.system.clipboard (code)
            say ('Copied the example.')
          end
        elseif target.kind == 'url' then
          app.system.open_url (target.url)
        else
          go (target.id ~= '' and target.id or nil, target.anchor)
        end
        return 'stop'
      end)
      update_buttons ()

      ---@type Handbook.Reader
      local reader = {
        root = root,
        go = go,
        redraw = function ()
          if query ~= '' then
            hits = pages.find (query, 60)
            draw_results ()
          elseif not here.id then
            draw_home ()
          elseif shown and shown_version ~= pages.version () then
            local now = pages.get (here.id)
            if now ~= shown then
              local top = scroll:get ('scrollTop') --[[@as number?]]
              if now then
                draw_page (now, nil, top)
              else
                draw_missing (here.id)
              end
            end
          end
        end,
        current = function ()
          return here.id
        end,
        search = function ()
          input:focus ()
          input:select ()
        end,
      }
      readers[reader] = reader
      return reader
    end

    scan ()
    local panel = new_reader ({})
    local last = app.store.get ('last')
    if type (last) == 'string' and pages.has (last) then
      panel.go (last)
    else
      panel.go (nil)
    end

    views.add ('right', {
      id = 'handbook',
      title = 'Handbook',
      icon = 'book-open',
      content = panel.root,
    })

    ---@param ref? string
    ---@return boolean
    local function open (ref)
      views.show ('handbook')
      if not ref or ref == '' then
        panel.go (nil)
        return true
      end
      local id, anchor = page.split_id (ref)
      if not pages.has (id) then
        return false
      end
      return panel.go (id, anchor)
    end

    ---@param id string
    ---@return Handbook.PageInfo
    local function info_of (id)
      local p = pages.get (id) --[[@as Handbook.Page]]
      return {
        id = p.id,
        title = p.title,
        section = p.section,
        origin = p.origin,
        active = p.active,
      }
    end

    app.provide_scoped ('handbook', function (consumer)
      local owner = consumer.id
      ---@type Handbook.Service
      return {
        add = function (spec)
          if type (spec) ~= 'table' then
            error ('handbook.add takes a table', 2)
          end
          local name, text = spec.id, spec.markdown ---@type string?, string?
          if type (name) ~= 'string' or not name:match ('^[%w_.%-]+$') then
            error (
              'handbook.add needs an `id` of letters, digits, dots, dashes and underscores',
              2
            )
          end
          if type (text) ~= 'string' then
            error ('handbook.add needs `markdown` as a string', 2)
          end
          local id = owner .. '/' .. name
          if file_ids[id] then
            error (
              "handbook.add: the page '" .. id .. "' comes from a file already",
              2
            )
          end
          ---@param markdown string
          ---@return string
          local function with_front (markdown)
            local front = {} ---@type string[]
            local values = {
              { 'title', spec.title },
              { 'section', spec.section },
              { 'order', spec.order },
              { 'keywords', spec.keywords },
            }
            for _, pair in ipairs (values) do
              if pair[2] ~= nil then
                front[#front + 1] = pair[1]
                  .. ': '
                  .. tostring (pair[2]):gsub ('[\r\n]+', ' ')
              end
            end
            local _, body = page.split_front (markdown)
            if #front == 0 then
              return body
            end
            return '---\n' .. table.concat (front, '\n') .. '\n---\n' .. body
          end
          local live = true
          local function put (markdown)
            pages.set (id, {
              source = owner,
              name = name,
              markdown = with_front (markdown),
              origin = 'code',
              plugin_name = owner,
              active = true,
            })
            for _, r in pairs (readers) do
              r.redraw ()
            end
          end
          local function drop ()
            if live then
              live = false
              pages.remove (id)
              for _, r in pairs (readers) do
                r.redraw ()
              end
            end
          end
          put (text)
          consumer.dispose (drop)
          return {
            id = id,
            set = function (markdown)
              if live and type (markdown) == 'string' then
                put (markdown)
              end
            end,
            remove = drop,
          }
        end,
        open = open,
        pages = function ()
          local out = {} ---@type Handbook.PageInfo[]
          for _, p in ipairs (pages.list ()) do
            out[#out + 1] = info_of (p.id)
          end
          return out
        end,
        find = function (query, limit)
          local out = {} ---@type Handbook.SearchHit[]
          for _, hit in
            ipairs (pages.find (tostring (query or ''), limit or 20))
          do
            out[#out + 1] = {
              id = hit.id,
              anchor = hit.anchor,
              label = hit.label,
              context = hit.context,
              snippet = hit.snippet,
            }
          end
          return out
        end,
      }
    end)

    if commands then
      commands.register ({
        id = 'handbook.show',
        category = 'Handbook',
        title = 'Show or Hide the Handbook',
        menu = 'Help',
        menu_title = 'Handbook',
        icon = 'book-open',
        key = 'ctrl+shift+h',
        run = function ()
          views.toggle ('handbook')
        end,
      })
      commands.register ({
        id = 'handbook.contents',
        category = 'Handbook',
        title = 'Contents',
        icon = 'list',
        run = function ()
          open (nil)
        end,
      })
      commands.register ({
        id = 'handbook.search',
        category = 'Handbook',
        title = 'Search the Handbook',
        icon = 'search',
        run = function ()
          views.show ('handbook')
          panel.search ()
        end,
      })
      if picker then
        local pick = picker
        commands.register ({
          id = 'handbook.find',
          category = 'Handbook',
          title = 'Go to a Page or Heading',
          menu = 'Help',
          menu_title = 'Handbook: Go to a Page…',
          icon = 'book-open-text',
          key = 'shift+f1',
          run = function ()
            local items = {} ---@type Proteus.PickItem[]
            for _, p in ipairs (pages.list ()) do
              items[#items + 1] = {
                label = p.title,
                detail = p.section,
                icon = p.origin == 'types' and 'braces' or 'file-text',
                value = p.id,
              }
              local deepest = p.origin == 'types' and 3 or 2
              for _, h in ipairs (p.doc.headings) do
                if h.level >= 2 and h.level <= deepest then
                  items[#items + 1] = {
                    label = page.plain (h.text),
                    detail = p.title,
                    icon = 'hash',
                    value = p.id .. '#' .. h.anchor,
                  }
                end
              end
            end
            pick.pick ({
              items = items,
              placeholder = 'Go to a Handbook page or heading',
              on_pick = function (item)
                open (tostring (item.value))
              end,
            })
          end,
        })
      end
    end
  end,
}
