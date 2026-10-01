-- shader.docs: the shaders open in the builder. It reads and saves their files, keeps the
-- undo history of each graph, knows which one is in front, and compiles each on demand.
-- Other plugins draw the documents: an opener for each kind makes the tab's content.
--
-- A graph is a *.shader.json file. A code shader is a .frag, .glsl or .wgsl file, and a .vert
-- file beside a .frag file of the same name is its vertex shader. New files go in shaders/,
-- which it claims in `folders`, and it copies the examples there.
--
-- Its handbook/ folder holds Learning shaders, a course in the Handbook that goes from a first
-- shader to the weather system in examples/weather.frag.

local FOLDER = 'shaders'
local EXTENSIONS = { '.shader.json', '.frag', '.vert', '.glsl', '.wgsl' }
-- The examples that came with 1.0, which a workspace from then has copied already.
local FIRST_EXAMPLES = {
  'cells.shader.json',
  'clouds.shader.json',
  'plasma.shader.json',
  'raymarch.frag',
  'shadertoy.frag',
  'shapes.shader.json',
  'tunnel.wgsl',
  'waves.frag',
}

---@type Proteus.Plugin
return {
  name = 'Shader documents',
  description = 'Opens, saves and compiles the shaders in the builder, and keeps the undo history of each graph.',
  version = '1.1.0',
  requires = {
    proteus = '>=0.2.0',
    features = { 'permissions', 'folders', 'plugin-files' },
  },
  permissions = {},
  folders = { 'shaders' },
  depends = { 'lib.ui', 'shader.core', 'ui.tabs', 'core.commands' },
  optional = { 'ui.palette', 'ui.notify', 'core.settings', 'core.keys' },
  activate = function (app)
    local core = app.use ('shader') --[[@as Shader.Core]]
    local tabs = app.use ('tabs')
    local commands = app.use ('commands')
    local picker = app.try_use ('picker')
    local notify = app.try_use ('notify')
    local settings = app.try_use ('settings')

    if settings then
      settings.define ('shader.language', {
        title = 'Preview language for graphs',
        type = 'select',
        options = { 'glsl', 'wgsl' },
        default = 'glsl',
        description = 'The language the Preview runs a graph in, until the graph picks one. WGSL needs WebGPU.',
      })
    end

    local open = {} ---@type table<string, Shader.OpenDoc>
    local order = {} ---@type string[]
    local active_path = nil ---@type string?
    local openers = {} ---@type table<Shader.DocKind, fun(doc: Shader.OpenDoc): Proteus.El>
    local cache = {} ---@type table<string, { version: integer, result: Shader.CompileResult }>

    ---@param text string
    local function say (text)
      if notify then
        notify.info (text)
      else
        app.log (text)
      end
    end

    ---@param text string
    local function warn (text)
      if notify then
        notify.error (text)
      else
        app.warn (text)
      end
    end

    ---@param path string
    ---@return string
    local function base_name (path)
      return (path:match ('([^/]+)$') or path)
    end

    ---@param path string
    ---@return Shader.DocKind?
    local function kind_of (path)
      if path:lower ():sub (-#core.file.EXTENSION) == core.file.EXTENSION then
        return 'graph'
      end
      if core.source.kind_of (path) then
        return 'code'
      end
      return nil
    end

    local function remember ()
      app.store.set ('open', order)
      app.store.set ('active', active_path)
    end

    ---@param doc Shader.OpenDoc
    local function refresh_tab (doc)
      if doc.tab then
        doc.tab.set_title (doc.title)
        doc.tab.set_dirty (doc.dirty)
      end
    end

    ---@param doc Shader.OpenDoc
    local function mark (doc)
      local dirty ---@type boolean
      if doc.kind == 'graph' then
        dirty = core.file.save (doc.history.doc) ~= doc.saved
      else
        dirty = doc.text ~= doc.saved
      end
      if dirty ~= doc.dirty then
        doc.dirty = dirty
        refresh_tab (doc)
        app.emit ('shader:dirty', doc.path, dirty)
      end
    end

    ---@param doc Shader.OpenDoc
    local function changed (doc)
      doc.version = doc.version + 1
      mark (doc)
      app.emit ('shader:changed', doc.path)
    end

    ---@type Shader.Docs
    local api

    ---@param path string?
    local function set_active (path)
      if active_path == path then
        return
      end
      active_path = path
      remember ()
      app.emit ('shader:active', path)
    end

    ---Makes a record for a file's text.
    ---@param path string
    ---@param text string
    ---@return Shader.OpenDoc?, string?
    local function make (path, text)
      local kind = kind_of (path)
      if not kind then
        return nil, base_name (path) .. ' is not a shader.'
      end
      ---@type Shader.OpenDoc
      local doc = {
        path = path,
        kind = kind,
        language = 'glsl',
        stage = 'fragment',
        title = base_name (path),
        text = '',
        saved = text,
        dirty = false,
        version = 1,
        selection = {},
        values = {},
      }
      if kind == 'graph' then
        local graph_doc, err = core.file.load (text)
        if not graph_doc then
          return nil, base_name (path) .. ': ' .. tostring (err)
        end
        doc.history = core.history.new (graph_doc)
        doc.saved = core.file.save (graph_doc)
        doc.language = graph_doc.preview
          or (settings and settings.get ('shader.language') == 'wgsl' and 'wgsl')
          or 'glsl'
        doc.title = base_name (path):sub (1, -#core.file.EXTENSION - 1)
      else
        local lang, stage = core.source.kind_of (path)
        doc.language = lang or 'glsl'
        doc.stage = stage or 'fragment'
        doc.text = text
        local stored = app.store.get ('values:' .. path)
        if type (stored) == 'table' then
          doc.values = stored
        end
      end
      return doc
    end

    ---Drops a document whose tab is closing.
    ---@param path string
    local function forget (path)
      local d = open[path]
      if d and d.dirty then
        app.emit ('shader:dirty', path, false)
      end
      open[path] = nil
      for i, p in ipairs (order) do
        if p == path then
          table.remove (order, i)
          break
        end
      end
      cache[path] = nil
      app.emit ('shader:closed', path)
      if active_path == path then
        set_active (nil)
      end
      remember ()
    end

    ---@param path string
    ---@return Shader.OpenDoc?
    local function open_path (path)
      local existing = open[path]
      if existing then
        if existing.tab then
          existing.tab.focus ()
        end
        set_active (path)
        return existing
      end
      local text = app.fs.read (path)
      if not text then
        warn ('There is no file at ' .. path .. '.')
        return nil
      end
      local doc, err = make (path, text)
      if not doc then
        warn (err or 'That file cannot open here.')
        return nil
      end
      local opener = openers[doc.kind]
      if not opener then
        warn ('Nothing here can show a ' .. doc.kind .. ' yet.')
        return nil
      end
      open[path] = doc
      order[#order + 1] = path
      local content = opener (doc)
      doc.tab = tabs.open ({
        id = 'shader:' .. path,
        title = doc.title,
        tooltip = path,
        icon = doc.kind == 'graph' and 'workflow' or 'file-code',
        content = content,
        on_focus = function ()
          set_active (path)
        end,
        on_close = function ()
          if doc.dirty and picker then
            picker.confirm ({
              message = doc.title
                .. ' has changes that are not saved. Close it anyway?',
              yes = 'Close Without Saving',
              no = 'Keep Open',
              on_yes = function ()
                forget (path)
                if doc.tab then
                  doc.tab.close (true)
                end
              end,
            })
            return false
          end
          forget (path)
          return true
        end,
      })
      app.emit ('shader:opened', path)
      set_active (path)
      remember ()
      return doc
    end

    ---A path in shaders/ that no file has yet.
    ---@param stem string
    ---@param ext string
    ---@return string
    local function free_path (stem, ext)
      local clean = stem:gsub ('[^%w%-_ ]', ''):gsub ('%s+', '-'):lower ()
      if clean == '' then
        clean = 'shader'
      end
      local path = FOLDER .. '/' .. clean .. ext
      local n = 2
      while app.fs.exists (path) do
        path = FOLDER .. '/' .. clean .. '-' .. n .. ext
        n = n + 1
      end
      return path
    end

    ---The vertex shader beside a .frag file, from its tab when it is open.
    ---@param doc Shader.OpenDoc
    ---@return string?
    local function vertex_of (doc)
      if doc.kind ~= 'code' or doc.language ~= 'glsl' then
        return nil
      end
      local vert = doc.path:gsub ('%.[%w]+$', '.vert')
      if vert == doc.path then
        return nil
      end
      local other = open[vert]
      if other then
        return other.text
      end
      return app.fs.read (vert)
    end

    api = {
      folder = FOLDER,
      extensions = EXTENSIONS,
      kind_of = kind_of,

      register_opener = function (kind, fn)
        openers[kind] = fn
      end,

      open = open_path,

      get = function (path)
        return open[path]
      end,

      active = function ()
        return active_path and open[active_path] or nil
      end,

      list = function ()
        local out = {} ---@type Shader.OpenDoc[]
        for _, p in ipairs (order) do
          out[#out + 1] = open[p]
        end
        return out
      end,

      files = function ()
        local out = {} ---@type string[]
        local seen = {} ---@type table<string, boolean>
        for _, path in ipairs (app.fs.files ()) do
          if
            path:sub (1, #FOLDER + 1) == FOLDER .. '/'
            and path:sub (1, #FOLDER + 7) ~= FOLDER .. '/build/'
            and kind_of (path)
          then
            if not seen[path] then
              seen[path] = true
              out[#out + 1] = path
            end
          end
        end
        table.sort (out)
        return out
      end,

      change = function (path, doc, key)
        local d = open[path]
        if not d or d.kind ~= 'graph' then
          return
        end
        core.history.push (d.history, doc, key, app.util.now ())
        if doc.preview then
          d.language = doc.preview
        end
        changed (d)
      end,

      set_text = function (path, text)
        local d = open[path]
        if not d or d.kind ~= 'code' or d.text == text then
          return
        end
        d.text = text
        changed (d)
        -- A .vert file changes the program of the .frag file beside it.
        if d.stage == 'vertex' then
          local frag = path:gsub ('%.vert$', '.frag') ---@type string
          local other = open[frag]
          if other then
            changed (other)
          end
        end
      end,

      undo = function (path)
        local d = open[path]
        if d and d.kind == 'graph' and core.history.undo (d.history) then
          changed (d)
          return true
        end
        return false
      end,

      redo = function (path)
        local d = open[path]
        if d and d.kind == 'graph' and core.history.redo (d.history) then
          changed (d)
          return true
        end
        return false
      end,

      save = function (path)
        local d = open[path]
        if not d then
          return false
        end
        local text = d.kind == 'graph' and core.file.save (d.history.doc)
          or d.text
        local ok, err = pcall (app.fs.write, path, text)
        if not ok then
          warn ('Could not save ' .. d.title .. ': ' .. tostring (err))
          return false
        end
        d.saved = text
        mark (d)
        app.emit ('shader:saved', path)
        return true
      end,

      select = function (path, ids)
        local d = open[path]
        if not d then
          return
        end
        d.selection = ids
        app.emit ('shader:selected', path, ids)
      end,

      compiled = function (path)
        local d = open[path]
        if not d or d.kind ~= 'graph' then
          return nil
        end
        local hit = cache[path]
        if hit and hit.version == d.version then
          return hit.result
        end
        local result = core.compile.compile (d.history.doc)
        cache[path] = { version = d.version, result = result }
        return result
      end,

      program = function (path, lang)
        local d = open[path]
        if not d then
          return nil, {}
        end
        if d.kind == 'graph' then
          local result = api.compiled (path) --[[@as Shader.CompileResult]]
          local which = lang or d.language
          return which == 'wgsl' and result.wgsl or result.glsl, result.errors
        end
        if d.stage == 'vertex' then
          -- A vertex shader runs with the fragment shader beside it.
          local frag = d.path:gsub ('%.vert$', '.frag')
          local frag_doc = open[frag]
          local frag_text = frag_doc and frag_doc.text or app.fs.read (frag)
          if not frag_text then
            return nil,
              {
                {
                  message = 'A vertex shader runs with the fragment shader of the same name, '
                    .. base_name (frag)
                    .. ', which does not exist yet.',
                },
              }
          end
          return core.source.glsl_program (frag_text, d.text)
        end
        local program, errors =
          core.source.program (d.language, d.text, vertex_of (d))
        for _, u in ipairs (program.uniforms) do
          local v = d.values[u.key]
          if v then
            u.value = v
          end
        end
        return program, errors
      end,

      set_language = function (path, lang)
        local d = open[path]
        if not d or d.kind ~= 'graph' or d.language == lang then
          return
        end
        local doc = core.graph.copy (d.history.doc) --[[@as Shader.Doc]]
        doc.preview = lang
        api.change (path, doc, 'language')
      end,

      set_uniform = function (path, key, value)
        local d = open[path]
        if not d then
          return
        end
        if d.kind == 'graph' then
          local node = core.graph.parameter (d.history.doc, key)
          if not node then
            return
          end
          local full = {} ---@type number[]
          local old = node.settings.value or {}
          for i = 1, 4 do
            full[i] = value[i] or old[i] or 0
          end
          local doc =
            core.graph.set_setting (d.history.doc, node.id, 'value', full)
          if doc then
            core.history.push (
              d.history,
              doc,
              'uniform:' .. key,
              app.util.now ()
            )
            -- A uniform's value is not in the code, so the program stays as it is.
            d.version = d.version + 1
            cache[path] = nil
            mark (d)
            app.emit ('shader:uniform', path, key, value)
          end
        else
          d.values[key] = value
          app.store.set ('values:' .. path, d.values)
          app.emit ('shader:uniform', path, key, value)
        end
      end,

      new_graph = function (name)
        local path = free_path (name or 'graph', core.file.EXTENSION)
        local doc = core.graph.new (name or 'Untitled')
        app.fs.write (path, core.file.save (doc))
        return open_path (path)
      end,

      new_code = function (lang, name, template)
        local t = core.source.TEMPLATES
        local text = template
          or (lang == 'wgsl' and t.wgsl)
          or (lang == 'vertex' and t.vertex)
          or t.glsl
        local ext = lang == 'wgsl' and '.wgsl'
          or (lang == 'vertex' and '.vert')
          or '.frag'
        local path = name and name:find ('/', 1, true) and name
          or free_path (name or 'shader', ext)
        app.fs.write (path, text)
        return open_path (path)
      end,
    }

    app.provide ('shader.docs', api)

    -- Files changed by another window or program load again, unless they have edits.
    app.on ('fs:changed', function (path, remote)
      local d = open[path]
      if not d or not remote or d.dirty then
        return
      end
      local text = app.fs.read (path)
      if not text or text == d.saved then
        return
      end
      local fresh = make (path, text)
      if not fresh then
        return
      end
      d.saved = fresh.saved
      if d.kind == 'graph' and fresh.history then
        core.history.push (d.history, fresh.history.doc)
      else
        d.text = fresh.text
      end
      changed (d)
      app.emit ('shader:reloaded', path)
    end)

    -- Commands ---------------------------------------------------------------------------------

    ---@return boolean
    local function graph_in_front ()
      local d = api.active ()
      return d ~= nil
        and d.kind == 'graph'
        and not app.dom.focus_info ().editable
    end

    ---@param lang 'glsl'|'wgsl'|'vertex'|'shadertoy'
    ---@param title string
    local function ask_new (lang, title)
      local function make_it (name)
        if lang == 'shadertoy' then
          api.new_code ('glsl', name, core.source.TEMPLATES.shadertoy)
        else
          api.new_code (lang --[[@as Shader.Lang|'vertex']], name)
        end
      end
      if picker then
        picker.input ({
          prompt = title,
          value = 'my-shader',
          on_submit = function (text)
            make_it (text)
          end,
        })
      else
        make_it ('shader')
      end
    end

    commands.register ({
      id = 'shader.new_graph',
      category = 'Shader',
      title = 'New Node Graph',
      -- The library's New buttons run it too.
      shared = true,
      menu = 'File',
      group = '1-new',
      order = 1,
      icon = 'workflow',
      key = 'ctrl+n',
      toolbar = 1,
      run = function ()
        if picker then
          picker.input ({
            prompt = 'Name the new graph',
            value = 'My Shader',
            on_submit = function (text)
              api.new_graph (text)
            end,
          })
        else
          api.new_graph ('My Shader')
        end
      end,
    })
    commands.register ({
      id = 'shader.new_glsl',
      category = 'Shader',
      title = 'New GLSL Shader',
      -- The library's New buttons run it too.
      shared = true,
      menu = 'File',
      group = '1-new',
      order = 2,
      icon = 'file-code',
      run = function ()
        ask_new ('glsl', 'Name the new GLSL fragment shader')
      end,
    })
    commands.register ({
      id = 'shader.new_wgsl',
      category = 'Shader',
      title = 'New WGSL Shader',
      -- The library's New buttons run it too.
      shared = true,
      menu = 'File',
      group = '1-new',
      order = 3,
      icon = 'file-code-2',
      run = function ()
        ask_new ('wgsl', 'Name the new WGSL shader')
      end,
    })
    commands.register ({
      id = 'shader.new_shadertoy',
      category = 'Shader',
      title = 'New Shadertoy-Style Shader',
      menu = 'File',
      group = '1-new',
      order = 4,
      icon = 'sparkles',
      run = function ()
        ask_new ('shadertoy', 'Name the new mainImage shader')
      end,
    })
    commands.register ({
      id = 'shader.new_vertex',
      category = 'Shader',
      title = 'Add a Vertex Shader to This Shader',
      menu = 'File',
      group = '1-new',
      order = 5,
      icon = 'triangle',
      when = function ()
        local d = api.active ()
        return d ~= nil
          and d.kind == 'code'
          and d.language == 'glsl'
          and d.stage == 'fragment'
      end,
      run = function ()
        local d = api.active ()
        if not d then
          return
        end
        local vert = d.path:gsub ('%.[%w]+$', '.vert')
        if app.fs.exists (vert) then
          open_path (vert)
        else
          api.new_code ('vertex', vert)
          say (
            'The preview now runs '
              .. base_name (vert)
              .. ' as the vertex shader.'
          )
        end
      end,
    })
    commands.register ({
      id = 'shader.open',
      category = 'Shader',
      title = 'Open Shader...',
      menu = 'File',
      group = '2-open',
      icon = 'folder-open',
      key = 'ctrl+o',
      run = function ()
        local items = {} ---@type Proteus.PickItem[]
        for _, path in ipairs (api.files ()) do
          items[#items + 1] = {
            label = base_name (path),
            detail = path,
            icon = kind_of (path) == 'graph' and 'workflow' or 'file-code',
            value = path,
          }
        end
        if picker then
          picker.pick ({
            items = items,
            placeholder = 'Open a shader',
            empty = 'No shaders in shaders/ yet.',
            on_pick = function (item)
              open_path (item.value)
            end,
          })
        end
      end,
    })
    commands.register ({
      id = 'shader.save',
      category = 'Shader',
      title = 'Save',
      menu = 'File',
      group = '3-save',
      icon = 'save',
      key = 'ctrl+s',
      when = function ()
        return api.active () ~= nil
      end,
      run = function ()
        local d = api.active ()
        if d and api.save (d.path) then
          say ('Saved ' .. d.path .. '.')
        end
      end,
    })
    commands.register ({
      id = 'shader.save_as',
      category = 'Shader',
      title = 'Save As...',
      menu = 'File',
      group = '3-save',
      icon = 'save-all',
      key = 'ctrl+shift+s',
      when = function ()
        return api.active () ~= nil and picker ~= nil
      end,
      run = function ()
        local d = api.active ()
        if not d or not picker then
          return
        end
        picker.input ({
          prompt = 'Save a copy as',
          value = d.path,
          validate = function (text)
            if kind_of (text) ~= d.kind then
              return 'Keep the same kind of ending, such as '
                .. (d.kind == 'graph' and '.shader.json' or d.path:match (
                  '%.[%w]+$'
                ))
                .. '.'
            end
            if app.fs.exists (text) then
              return 'A file has that name already.'
            end
            return nil
          end,
          on_submit = function (text)
            local body = d.kind == 'graph' and core.file.save (d.history.doc)
              or d.text
            local ok, err = pcall (app.fs.write, text, body)
            if not ok then
              warn ('Could not save ' .. text .. ': ' .. tostring (err))
              return
            end
            open_path (text)
          end,
        })
      end,
    })
    commands.register ({
      id = 'shader.undo',
      category = 'Shader',
      title = 'Undo',
      menu = 'Edit',
      group = '1-undo',
      icon = 'undo-2',
      key = 'ctrl+z',
      when = graph_in_front,
      run = function ()
        local d = api.active ()
        if d then
          api.undo (d.path)
        end
      end,
    })
    commands.register ({
      id = 'shader.redo',
      category = 'Shader',
      title = 'Redo',
      menu = 'Edit',
      group = '1-undo',
      icon = 'redo-2',
      key = { 'ctrl+y', 'ctrl+shift+z' },
      when = graph_in_front,
      run = function ()
        local d = api.active ()
        if d then
          api.redo (d.path)
        end
      end,
    })

    -- Each example is copied into shaders/ once, where it can be changed and saved. An example
    -- added in a later version reaches a workspace that started before it, and one the user
    -- deleted stays deleted.
    local copied = {} ---@type table<string, boolean>
    local stored = app.store.get ('examples', false)
    if stored == true then
      -- Before 1.1.0 the store held true once the first examples were copied.
      for _, name in ipairs (FIRST_EXAMPLES) do
        copied[name] = true
      end
    elseif type (stored) == 'table' then
      for _, name in
        ipairs (stored --[[@as string[] ]])
      do
        copied[name] = true
      end
    end
    local names = {} ---@type string[]
    for _, entry in ipairs (app.plugin.list ('examples')) do
      if not entry.dir then
        local target = FOLDER .. '/' .. entry.name
        if not copied[entry.name] and not app.fs.exists (target) then
          local text = app.plugin.read ('examples/' .. entry.name)
          if text then
            app.fs.write (target, text)
          end
        end
        names[#names + 1] = entry.name
      end
    end
    app.store.set ('examples', names)

    -- The shaders open at the last close open again, once every opener is in place. On the
    -- first start the Plasma example opens.
    app.timer.after (0, function ()
      local list = app.store.get ('open', nil)
      if type (list) ~= 'table' then
        list = { FOLDER .. '/plasma.shader.json' }
      end
      local last = app.store.get ('active', nil)
      for _, path in
        ipairs (list --[[@as string[] ]])
      do
        if type (path) == 'string' and app.fs.exists (path) then
          open_path (path)
        end
      end
      if type (last) == 'string' and open[last] then
        open_path (last)
      end
    end)
  end,
}
