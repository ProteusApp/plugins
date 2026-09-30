-- shader.library: the left side of the shader builder. Shaders lists the files in shaders/,
-- the examples among them, with buttons to make new ones. Nodes lists every node by group,
-- with a search box, and a click adds one to the graph in front.

-- lang=css
local CSS = [[
.sl-root { display: flex; flex-direction: column; height: 100%; min-height: 0; font-size: 12.5px; }
.sl-actions { display: flex; flex-wrap: wrap; gap: 4px; padding: 6px 8px; border-bottom: 0.5px solid var(--border); }
.sl-list { flex: 1; min-height: 0; overflow: auto; padding: 4px 0; }
.sl-group { padding: 8px 12px 3px; font-size: 11px; text-transform: uppercase; letter-spacing: 0.04em; color: var(--fg-muted); display: flex; align-items: center; gap: 6px; }
.sl-group .dot { width: 8px; height: 8px; border-radius: 50%; }
.sl-item {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 4px 12px;
  cursor: pointer;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.sl-item:hover { background: var(--bg-hover, var(--bg-alt)); }
.sl-item.on { background: var(--bg-active, var(--bg-alt)); color: var(--accent); }
.sl-item .sl-name { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; }
.sl-item .sl-tag { color: var(--fg-muted); font-size: 11px; }
.sl-search { margin: 6px 8px; }
.sl-hint { padding: 8px 12px; color: var(--fg-muted); line-height: 1.5; }
]]

---@type Proteus.Plugin
return {
  name = 'Shader library',
  description = 'Lists the shaders in shaders/ and every node, and adds nodes to the graph in front.',
  version = '1.0.0',
  requires = { proteus = '>=0.2.0', features = { 'permissions' } },
  permissions = {},
  depends = {
    'lib.ui',
    'shader.core',
    'shader.docs',
    'ui.views',
    'core.commands',
  },
  optional = { 'shader.canvas', 'ui.menus', 'ui.palette', 'ui.notify' },
  activate = function (app)
    local ui = app.use ('ui')
    local core = app.use ('shader') --[[@as Shader.Core]]
    local docs = app.use ('shader.docs') --[[@as Shader.Docs]]
    local views = app.use ('views')
    local commands = app.use ('commands')
    local canvas = app.try_use ('shader.canvas') --[[@as Shader.CanvasService?]]
    local menus = app.try_use ('menus')
    local picker = app.try_use ('picker')
    local notify = app.try_use ('notify')
    ui.css (CSS)
    local esc = app.util.escape

    -- Shaders ------------------------------------------------------------------------------

    local files = {} ---@type string[]
    local list = ui.div ({ class = 'sl-list' })

    ---@param path string
    ---@return string
    local function tag_of (path)
      local lower = path:lower ()
      if lower:sub (-#core.file.EXTENSION) == core.file.EXTENSION then
        return 'graph'
      end
      local lang, stage = core.source.kind_of (path)
      if stage == 'vertex' then
        return 'vertex'
      end
      return lang == 'wgsl' and 'WGSL' or 'GLSL'
    end

    local function draw_files ()
      files = docs.files ()
      local active = docs.active ()
      local parts = {} ---@type string[]
      local groups = {
        { 'Graphs', 'graph' },
        { 'Code', 'code' },
      }
      for _, g in ipairs (groups) do
        local any = false
        for i, path in ipairs (files) do
          if docs.kind_of (path) == g[2] then
            if not any then
              parts[#parts + 1] = '<div class="sl-group">' .. g[1] .. '</div>'
              any = true
            end
            local name = path:sub (#docs.folder + 2)
            if g[2] == 'graph' then
              name = string.sub (name, 1, -#core.file.EXTENSION - 1) --[[@as string]]
            end
            local stat = app.fs.stat (path)
            local example = stat.builtin and not stat.user and not stat.project
            parts[#parts + 1] = '<div class="sl-item'
              .. (active and active.path == path and ' on' or '')
              .. '" data-item="'
              .. i
              .. '" title="'
              .. esc (path)
              .. '">'
              .. (app.util.icon (
                g[2] == 'graph' and 'workflow' or 'file-code',
                14
              ) or '')
              .. '<span class="sl-name">'
              .. esc (name)
              .. '</span><span class="sl-tag">'
              .. esc (
                example and ('example · ' .. tag_of (path)) or tag_of (path)
              )
              .. '</span></div>'
          end
        end
      end
      if #files == 0 then
        parts[#parts + 1] =
          '<div class="sl-hint">No shaders yet. Start one with the buttons above.</div>'
      end
      list:html (table.concat (parts))
    end

    list:on ('click', function (ev)
      local path = ev.item and files[tonumber (ev.item) or 0]
      if path then
        docs.open (path)
      end
      return nil
    end)

    if menus then
      menus.attach (list, function (ev)
        local path = ev.item and files[tonumber (ev.item) or 0]
        if not path then
          return nil
        end
        local stat = app.fs.stat (path)
        return {
          {
            label = 'Open',
            icon = 'file',
            run = function ()
              docs.open (path)
            end,
          },
          {
            label = 'Copy Path',
            icon = 'clipboard',
            run = function ()
              app.system.clipboard (path)
            end,
          },
          { separator = true },
          {
            label = stat.builtin and 'Revert to the Example' or 'Delete',
            icon = stat.builtin and 'undo-2' or 'trash-2',
            danger = true,
            disabled = stat.builtin and not stat.user,
            run = function ()
              local function go ()
                app.fs.remove (path)
                draw_files ()
              end
              if picker then
                picker.confirm ({
                  message = stat.builtin
                      and ('Throw away your changes to ' .. path .. '?')
                    or ('Delete ' .. path .. '?'),
                  yes = stat.builtin and 'Revert' or 'Delete',
                  on_yes = go,
                })
              else
                go ()
              end
            end,
          },
        }
      end)
    end

    local shaders_root = ui.div ({
      class = 'sl-root',
      ui.div ({
        class = 'sl-actions',
        ui.button ({
          'Graph',
          icon = 'plus',
          variant = 'ghost',
          title = 'A new node graph',
          onclick = function ()
            commands.run ('shader.new_graph')
          end,
        }),
        ui.button ({
          'GLSL',
          icon = 'plus',
          variant = 'ghost',
          title = 'A new GLSL fragment shader',
          onclick = function ()
            commands.run ('shader.new_glsl')
          end,
        }),
        ui.button ({
          'WGSL',
          icon = 'plus',
          variant = 'ghost',
          title = 'A new WGSL shader',
          onclick = function ()
            commands.run ('shader.new_wgsl')
          end,
        }),
      }),
      list,
    })

    views.add ('left', {
      id = 'shader.files',
      title = 'Shaders',
      icon = 'folder',
      order = 1,
      content = shaders_root,
      on_show = draw_files,
    })

    local redraw_pending = false
    local function redraw ()
      if not redraw_pending then
        redraw_pending = true
        app.timer.after (100, function ()
          redraw_pending = false
          draw_files ()
        end)
      end
    end
    app.on ('shader:active', redraw)
    app.on ('shader:opened', redraw)
    app.on ('shader:saved', redraw)
    app.on ('fs:changed', function (path)
      if tostring (path):sub (1, #docs.folder + 1) == docs.folder .. '/' then
        redraw ()
      end
    end)
    draw_files ()

    -- Nodes --------------------------------------------------------------------------------

    local query = ''
    local shown = {} ---@type Shader.NodeDef[]
    local node_list = ui.div ({ class = 'sl-list' })

    local function draw_nodes ()
      shown = {}
      local parts = {} ---@type string[]
      local q = query:lower ()
      for _, cat in ipairs (core.nodes.categories) do
        local any = false
        for _, def in ipairs (core.nodes.list) do
          if def.category == cat.id then
            local hay = (def.title .. ' ' .. def.type .. ' ' .. def.description):lower ()
            if q == '' or hay:find (q, 1, true) then
              if not any then
                parts[#parts + 1] = '<div class="sl-group"><span class="dot" style="background:'
                  .. cat.color
                  .. '"></span>'
                  .. esc (cat.title)
                  .. '</div>'
                any = true
              end
              shown[#shown + 1] = def
              parts[#parts + 1] = '<div class="sl-item" data-item="'
                .. #shown
                .. '" title="'
                .. esc (def.description)
                .. '"><span class="sl-name">'
                .. esc (def.title)
                .. '</span></div>'
            end
          end
        end
      end
      if #shown == 0 then
        parts[#parts + 1] = '<div class="sl-hint">No node matches.</div>'
      end
      node_list:html (table.concat (parts))
    end

    node_list:on ('click', function (ev)
      local def = ev.item and shown[tonumber (ev.item) or 0]
      if not def then
        return nil
      end
      local d = docs.active ()
      if not d or d.kind ~= 'graph' then
        if notify then
          notify.info ('Open a graph first. Nodes go into a graph.')
        end
        return nil
      end
      if canvas then
        canvas.add (def.type)
      end
      return nil
    end)

    local search = ui.input ({
      class = 'sl-search',
      placeholder = 'Search nodes',
      oninput = function (ev)
        query = ev.value or ''
        draw_nodes ()
      end,
    })
    local nodes_root = ui.div ({
      class = 'sl-root',
      search,
      node_list,
      ui.div ({
        class = 'sl-hint',
        'Click a node to add it. On the canvas, double-click or press Ctrl+K to search, and drop a wire on empty space for the nodes that take it.',
      }),
    })
    views.add ('left', {
      id = 'shader.nodes',
      title = 'Nodes',
      icon = 'blocks',
      order = 2,
      content = nodes_root,
    })
    draw_nodes ()
  end,
}
