-- shader.docs: the shaders open in the builder. It reads and saves their files, keeps the
-- undo history of each graph, knows which one is in front, and compiles each on demand.
-- Other plugins draw the documents: an opener for each kind makes the tab's content.
--
-- A graph is a *.shader.json file. A code shader is a .frag, .glsl, .wgsl or .gdshader file, and a .vert
-- file beside a .frag file of the same name is its vertex shader. `x.buffer-a.frag` is Buffer A
-- of the shader `x.frag`: a pass drawn before it each frame, which its channels can read. New
-- files go in shaders/, which it claims in `folders`, and it copies the examples there.
--
-- Its handbook/ folder holds Learning shaders, a course in the Handbook that goes from a first
-- shader to the weather system in examples/weather.frag.

local FOLDER = 'shaders'
local EXTENSIONS =
  { '.shader.json', '.frag', '.vert', '.glsl', '.wgsl', '.gdshader' }
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
  version = '1.5.0',
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
    local cache = {} ---@type table<string, { doc: Shader.OpenDoc, version: integer, result: Shader.CompileResult }>
    -- Shaders read from their files without a tab, such as the buffers of the one in front,
    -- kept until the file's text changes.
    local peeked = {} ---@type table<string, { text: string, doc: Shader.OpenDoc }>
    -- Every shader in shaders/, kept until a file there changes.
    local file_list = nil ---@type string[]?
    -- The documents a question about their file is open for.
    local asking = {} ---@type table<Shader.OpenDoc, boolean>

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

    ---The ending a rename keeps, such as `.shader.json` or `.frag`.
    ---@param path string
    ---@return string
    local function ending (path)
      local lower = path:lower ()
      if lower:sub (-#core.file.EXTENSION) == core.file.EXTENSION then
        return core.file.EXTENSION
      end
      return lower:match ('%.[%w]+$') or ''
    end

    ---The tab's title: the file name, without the ending for a graph.
    ---@param path string
    ---@param kind Shader.DocKind
    ---@return string
    local function title_of (path, kind)
      if kind == 'graph' then
        return base_name (path):sub (1, -#core.file.EXTENSION - 1)
      end
      return base_name (path)
    end

    ---True for shaders/ and every path inside it.
    ---@param path string
    ---@return boolean
    local function in_folder (path)
      return path == FOLDER or path:sub (1, #FOLDER + 1) == FOLDER .. '/'
    end

    -- Shaders from a folder on disk, such as the Code Editor's, by full path. A plugin with the
    -- `files` permission reads them and hands their text over, and saves go back through it.
    local disk = {} ---@type table<string, string>
    local disk_writer = nil ---@type Shader.DiskWriter?
    -- Set when another plugin reopens files itself, so the shaders open at the last close stay
    -- closed.
    local skip_reopen = false

    ---True for a full path on disk, rather than a path in the workspace.
    ---@param path string
    ---@return boolean
    local function on_disk (path)
      return path:sub (1, 1) == '/' or path:match ('^%a:[/\\]') ~= nil
    end

    ---A file's text, from the workspace or from what was handed over from disk.
    ---@param path string
    ---@return string?
    local function read (path)
      if on_disk (path) then
        return disk[path]
      end
      return app.fs.read (path)
    end

    ---@param path string
    ---@return boolean
    local function exists (path)
      if on_disk (path) then
        return disk[path] ~= nil
      end
      return app.fs.exists (path)
    end

    ---Writes a file. One on disk is written through the plugin that handed it over, and an
    ---error it gives later arrives through `on_error`.
    ---@param path string
    ---@param text string
    ---@param on_error? fun(err: string)
    local function write (path, text, on_error)
      if not on_disk (path) then
        app.fs.write (path, text)
        return
      end
      if not disk_writer then
        error ('nothing can write files on disk here', 0)
      end
      disk[path] = text
      disk_writer (path, text, function (err)
        if err and on_error then
          on_error (err)
        end
      end)
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

    ---Works out whether a document has unsaved changes. A graph compares its document with the
    ---one last saved. Undo brings that back as the same table.
    ---@param doc Shader.OpenDoc
    local function mark (doc)
      local dirty ---@type boolean
      if doc.missing then
        dirty = true
      elseif doc.kind == 'graph' then
        dirty = doc.history.doc ~= doc.saved_doc
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
        title = title_of (path, kind),
        text = '',
        saved = text,
        dirty = false,
        missing = false,
        version = 1,
        selection = {},
        values = {},
        channels = {},
      }
      if kind == 'graph' then
        local graph_doc, err = core.file.load (text)
        if not graph_doc then
          return nil, base_name (path) .. ': ' .. tostring (err)
        end
        doc.history = core.history.new (graph_doc)
        doc.saved_doc = graph_doc
        doc.language = graph_doc.preview
          or (settings and settings.get ('shader.language') == 'wgsl' and 'wgsl')
          or 'glsl'
      else
        local lang, stage = core.source.kind_of (path)
        doc.language = lang or 'glsl'
        doc.stage = stage or 'fragment'
        doc.text = text
        local stored = app.store.get ('values:' .. path)
        if type (stored) == 'table' then
          doc.values = stored
        end
        local picked = app.store.get ('channels:' .. path)
        if type (picked) == 'table' then
          for i = 0, core.passes.COUNT - 1 do
            local src = core.passes.clean_source (picked[tostring (i)])
            if src then
              doc.channels[tostring (i)] = src
            end
          end
        end
      end
      return doc
    end

    ---Drops a document whose tab is closing.
    ---@param path string
    local function forget (path)
      local d = open[path]
      if not d then
        return
      end
      if d.dirty then
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

    ---Opens a shader in a tab, or brings its tab to the front. `carry` is a document that was
    ---open under another path, and it keeps its undo and unsaved changes in the new tab.
    ---@param path string
    ---@param carry? Shader.OpenDoc
    ---@return Shader.OpenDoc?
    local function open_path (path, carry)
      local existing = open[path]
      if existing then
        if existing.tab then
          existing.tab.focus ()
        end
        set_active (path)
        return existing
      end
      local doc ---@type Shader.OpenDoc
      if carry then
        doc = carry
        doc.path = path
        doc.title = title_of (path, doc.kind)
        doc.tab = nil
        doc.version = doc.version + 1
        if doc.kind == 'code' and next (doc.values) then
          app.store.set ('values:' .. path, doc.values)
        end
        if doc.kind == 'code' and next (doc.channels) then
          app.store.set ('channels:' .. path, doc.channels)
        end
      else
        local text = read (path)
        if not text then
          warn ('There is no file at ' .. path .. '.')
          return nil
        end
        local made, err = make (path, text)
        if not made then
          warn (err or 'That file cannot open here.')
          return nil
        end
        doc = made
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
          if open[path] ~= doc then
            return true
          end
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
      if doc.dirty then
        refresh_tab (doc)
        app.emit ('shader:dirty', path, true)
      end
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
      while exists (path) do
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
      return read (vert)
    end

    ---The text a save writes.
    ---@param d Shader.OpenDoc
    ---@return string
    local function body_of (d)
      if d.kind == 'graph' then
        return core.file.save (d.history.doc)
      end
      return d.text
    end

    ---Closes a document's tab without asking.
    ---@param d Shader.OpenDoc
    local function close_doc (d)
      forget (d.path)
      if d.tab then
        d.tab.close (true)
      end
    end

    ---Puts the file's text in place of what is open. For a graph it is one undo step, so undo
    ---brings back what was here.
    ---@param d Shader.OpenDoc
    ---@param text string
    local function reload (d, text)
      d.saved = text
      d.missing = false
      local fresh, err = make (d.path, text)
      if not fresh then
        -- What is here stays, unsaved, and the next save writes over the file.
        d.saved_doc = nil
        mark (d)
        warn (err or (d.title .. ' cannot open now.'))
        return
      end
      if d.kind == 'graph' and fresh.history then
        core.history.push (d.history, fresh.history.doc)
        d.saved_doc = d.history.doc
        d.language = fresh.language
      else
        d.text = fresh.text
      end
      changed (d)
      app.emit ('shader:reloaded', d.path)
    end

    ---Follows an open file after something changed it. A shader without unsaved changes loads
    ---the file again, and one with changes asks first. A deleted file is never written back on
    ---its own: the shader stays open, unsaved, until a save writes it again.
    ---@param path string
    local function check_disk (path)
      local d = open[path]
      if not d or asking[d] then
        return
      end
      local text = read (path)
      if text == nil then
        if not d.missing then
          d.missing = true
          mark (d)
          say (d.title .. ' was deleted. Save writes it again.')
        end
        return
      end
      if d.missing then
        d.missing = false
        mark (d)
      end
      if text == d.saved then
        return
      end
      if text == body_of (d) then
        -- The file holds what is here already.
        d.saved = text
        if d.history then
          d.saved_doc = d.history.doc
        end
        mark (d)
        return
      end
      if not d.dirty then
        reload (d, text)
        return
      end
      if not picker then
        -- Nothing can ask, so what is here stays, and the next save writes over the file.
        d.saved = text
        mark (d)
        warn (
          d.title
            .. ' changed outside the builder. The shader here stays as it is.'
        )
        return
      end
      picker.pick ({
        prompt = d.title
          .. ' changed outside the builder, and the shader here has changes that are not saved.',
        items = {
          {
            label = 'Load the file',
            detail = d.kind == 'graph' and 'Undo brings back the graph here'
              or 'The changes here are lost',
            icon = 'file-down',
            value = 'load',
          },
          {
            label = 'Keep the shader here',
            detail = 'The next save writes over the file',
            icon = 'pencil',
            value = 'keep',
          },
        },
        on_pick = function (item)
          asking[d] = nil
          local now = open[d.path] == d and read (d.path)
          if not now then
            return
          end
          if item.value == 'load' then
            reload (d, now)
          else
            d.saved = now
            mark (d)
          end
        end,
        on_cancel = function ()
          asking[d] = nil
        end,
      })
      -- After `pick`, which cancels any question open before it.
      asking[d] = true
    end

    local checking = {} ---@type table<string, boolean>

    ---Checks a file a moment later, because a rename sends the old path's change before the
    ---rename itself.
    ---@param path string
    local function check_soon (path)
      if checking[path] then
        return
      end
      checking[path] = true
      app.timer.after (0, function ()
        checking[path] = nil
        check_disk (path)
      end)
    end

    ---Moves the shaders open at `from`, or inside it, to `to`. Each opens in a new tab and keeps
    ---its undo and unsaved changes.
    ---@param from string
    ---@param to string
    local function follow (from, to)
      local front = active_path
      local paths = {} ---@type string[]
      for i, p in ipairs (order) do
        paths[i] = p
      end
      for _, p in ipairs (paths) do
        local target = nil ---@type string?
        if p == from then
          target = to
        elseif p:sub (1, #from + 1) == from .. '/' then
          target = to .. p:sub (#from + 1)
        end
        local d = open[p]
        if target and d and not open[target] then
          close_doc (d)
          open_path (target, d)
          if front == p then
            front = target
          end
        end
      end
      if front and front ~= active_path and open[front] then
        open_path (front)
      end
    end

    ---Why `to` cannot be the new name of the shader at `path`, or nil when it can.
    ---@param path string
    ---@param to string
    ---@return string?
    local function rename_problem (path, to)
      if ending (to) ~= ending (path) then
        return 'Keep the ending ' .. ending (path) .. '.'
      end
      if to ~= path and exists (to) then
        return 'A file has that name already.'
      end
      return nil
    end

    ---An open shader, or one read from its file without a tab.
    ---@param path string
    ---@return Shader.OpenDoc?
    local function peek (path)
      local d = open[path]
      if d then
        return d
      end
      local text = read (path)
      if not text then
        peeked[path] = nil
        return nil
      end
      local hit = peeked[path]
      if hit and hit.text == text then
        return hit.doc
      end
      local made = make (path, text)
      peeked[path] = made and { text = text, doc = made } or nil
      return made
    end

    ---A graph compiled, kept until it changes.
    ---@param d Shader.OpenDoc
    ---@return Shader.CompileResult
    local function compiled_of (d)
      local hit = cache[d.path]
      if hit and hit.doc == d and hit.version == d.version then
        return hit.result
      end
      local result = core.compile.compile (d.history.doc)
      cache[d.path] = { doc = d, version = d.version, result = result }
      return result
    end

    ---What the user picked for each channel, by `'0'` to `'3'`.
    ---@param d Shader.OpenDoc
    ---@return table<string, Shader.ChannelSource>
    local function picked_channels (d)
      if d.kind == 'graph' then
        return d.history.doc.channels or {}
      end
      return d.channels or {}
    end

    ---The program of a shader, and its problems, before the channels are checked.
    ---@param d Shader.OpenDoc
    ---@param lang? Shader.Lang
    ---@return Shader.Program?, Shader.CompileError[]
    local function program_of (d, lang)
      if d.kind == 'graph' then
        local result = compiled_of (d)
        local which = lang or d.language
        return which == 'wgsl' and result.wgsl or result.glsl, result.errors
      end
      if d.stage == 'vertex' then
        -- A vertex shader runs with the fragment shader beside it.
        local frag = d.path:gsub ('%.vert$', '.frag')
        local frag_doc = open[frag]
        local frag_text = frag_doc and frag_doc.text or read (frag)
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
    end

    ---What each channel shows: the user's pick, or what the notes give.
    ---@param d Shader.OpenDoc
    ---@param program Shader.Program?
    ---@return table<integer, Shader.ChannelSource>
    local function effective (d, program)
      local picked = picked_channels (d)
      local out = {} ---@type table<integer, Shader.ChannelSource>
      for i = 0, core.passes.COUNT - 1 do
        out[i] = picked[tostring (i)] or { kind = 'none' }
      end
      for _, c in ipairs (program and program.channels or {}) do
        if not picked[tostring (c.index)] and c.source then
          out[c.index] = c.source
        end
      end
      return out
    end

    ---The shader's passes: the files of its image and of each buffer that exists.
    ---@param path string
    ---@return Shader.PassSet
    local function passes_of (path)
      local base, show = core.passes.pass_of (path)
      ---@param pass Shader.PassId
      ---@return string?
      local function find (pass)
        for _, p in ipairs (core.passes.pass_paths (base, pass)) do
          if open[p] or exists (p) then
            return p
          end
        end
        return nil
      end
      ---@type Shader.PassSet
      local set =
        { base = base, show = show, image = find ('image'), buffers = {} }
      for _, b in ipairs (core.passes.BUFFERS) do
        set.buffers[b] = find (b)
      end
      return set
    end

    ---Problems with what the channels a program reads show: nothing, or a buffer with no file.
    ---@param d Shader.OpenDoc
    ---@param program Shader.Program
    ---@return Shader.CompileError[]
    local function channel_problems (d, program)
      local out = {} ---@type Shader.CompileError[]
      if not program.channels or #program.channels == 0 then
        return out
      end
      local sources = effective (d, program)
      local set = nil ---@type Shader.PassSet?
      for _, c in ipairs (program.channels) do
        local src = sources[c.index]
        local name = 'iChannel' .. c.index
        local message ---@type string?
        if src.kind == 'none' then
          message = name
            .. ' shows nothing, so it reads black. Pick what it shows under Channels in the Preview panel.'
        elseif src.kind == 'buffer' then
          set = set or passes_of (d.path)
          if not set.buffers[src.buffer] then
            message = name
              .. ' reads '
              .. core.passes.label (src)
              .. ', which this shader does not have yet. Add it with File > Add a Buffer to This Shader.'
          end
        elseif src.kind == 'image' and not src.grant then
          message = name .. ' has no image yet. Pick one in the Preview panel.'
        end
        if message then
          out[#out + 1] = {
            message = message,
            line = c.line,
            node = c.nodes and c.nodes[1] or nil,
            severity = 'warning',
          }
        end
      end
      return out
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
        if file_list then
          return file_list
        end
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
        file_list = out
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
        local text = body_of (d)
        local before = d.saved
        local ok, err = pcall (write, path, text, function (late)
          -- A file on disk failed to write after all, so the shader has unsaved changes again.
          if open[path] == d and d.saved == text then
            d.saved = before
            mark (d)
          end
          warn ('Could not save ' .. d.title .. ': ' .. late)
        end)
        if not ok then
          warn ('Could not save ' .. d.title .. ': ' .. tostring (err))
          return false
        end
        d.saved = text
        d.missing = false
        if d.history then
          d.saved_doc = d.history.doc
        end
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
        local d = peek (path)
        if not d or d.kind ~= 'graph' then
          return nil
        end
        return compiled_of (d)
      end,

      program = function (path, lang)
        local d = peek (path)
        if not d then
          return nil, {}
        end
        local program, errors = program_of (d, lang)
        if not program then
          return nil, errors
        end
        local extra = channel_problems (d, program)
        if #extra == 0 then
          return program, errors
        end
        -- A graph's problems are kept with its compiled code, so they are copied.
        local all = {} ---@type Shader.CompileError[]
        for _, e in ipairs (errors) do
          all[#all + 1] = e
        end
        for _, e in ipairs (extra) do
          all[#all + 1] = e
        end
        return program, all
      end,

      passes = passes_of,

      channels = function (path)
        local d = peek (path)
        if not d then
          local none = {} ---@type table<integer, Shader.ChannelSource>
          for i = 0, core.passes.COUNT - 1 do
            none[i] = { kind = 'none' }
          end
          return none
        end
        return effective (d, (program_of (d)))
      end,

      set_channel = function (path, index, src)
        local d = open[path]
        if not d or index < 0 or index >= core.passes.COUNT then
          return
        end
        local clean = core.passes.clean_source (src)
        if d.kind == 'graph' then
          api.change (
            path,
            core.graph.set_channel (d.history.doc, index, clean),
            'channel'
          )
          return
        end
        d.channels[tostring (index)] = clean
        app.store.set (
          'channels:' .. path,
          next (d.channels) and d.channels or nil
        )
        -- The code is the same, but what it reads is not.
        d.version = d.version + 1
        app.emit ('shader:changed', path)
      end,

      new_buffer = function (path)
        local set = passes_of (path)
        local free = nil ---@type Shader.PassId?
        for _, b in ipairs (core.passes.BUFFERS) do
          if not set.buffers[b] then
            free = b
            break
          end
        end
        if not free then
          return nil, 'This shader has all four buffers.'
        end
        local target = core.passes.buffer_path (path, free)
        local text ---@type string
        if kind_of (target) == 'graph' then
          text = core.file.save (core.examples.buffer (free))
        else
          local t = core.source.TEMPLATES
          local template = core.source.kind_of (target) == 'wgsl'
              and t.buffer_wgsl
            or t.buffer
          text = template:gsub ('{{BUFFER}}', 'buffer-' .. free) --[[@as string]]
        end
        local ok, err = pcall (write, target, text)
        if not ok then
          return nil, tostring (err)
        end
        file_list = nil
        return open_path (target)
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

      remove = function (path)
        local d = open[path]
        if on_disk (path) then
          warn ('Delete ' .. base_name (path) .. ' in the file tree.')
          return false
        end
        local ok, err = pcall (app.fs.remove, path)
        if not ok then
          warn ('Could not delete ' .. path .. ': ' .. tostring (err))
          return false
        end
        file_list = nil
        if d and open[path] == d then
          local text = read (path)
          if text then
            -- The example underneath shows again in place of the changed copy.
            reload (d, text)
          else
            close_doc (d)
          end
        end
        return true
      end,

      rename = function (path, to)
        if to == path then
          return true
        end
        if on_disk (path) or on_disk (to) then
          return false, 'Rename it in the file tree.'
        end
        local problem = rename_problem (path, to)
        if problem then
          return false, problem
        end
        local ok, err = pcall (app.fs.rename, path, to)
        if not ok then
          return false, tostring (err)
        end
        file_list = nil
        -- The rename event has moved the open shader already, unless the host sent none.
        follow (path, to)
        return true
      end,

      skip_reopen = function ()
        skip_reopen = true
      end,

      attach_disk = function (writer)
        disk_writer = writer
        return function ()
          if disk_writer == writer then
            disk_writer = nil
          end
        end
      end,

      open_disk = function (path, texts)
        for p, text in pairs (texts) do
          if on_disk (p) and not (open[p] and open[p].dirty) then
            disk[p] = text
          end
        end
        file_list = nil
        return open_path (path)
      end,

      disk_changed = function (path, text)
        if not on_disk (path) then
          return
        end
        if text == nil and not open[path] then
          disk[path] = nil
          return
        end
        disk[path] = text
        if open[path] then
          check_soon (path)
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
          or (lang == 'gdshader' and t.gdshader)
          or (lang == 'vertex' and t.vertex)
          or t.glsl
        local ext = lang == 'wgsl' and '.wgsl'
          or (lang == 'gdshader' and '.gdshader')
          or (lang == 'vertex' and '.vert')
          or '.frag'
        local path = name and name:find ('/', 1, true) and name
          or free_path (name or 'shader', ext)
        app.fs.write (path, text)
        return open_path (path)
      end,
    }

    app.provide ('shader.docs', api)

    -- A shader whose file changed loads it again, unless it has edits, and then it asks. Its
    -- own saves change nothing, since the file then holds what was saved.
    app.on ('fs:changed', function (changed_path)
      local p = tostring (changed_path)
      if in_folder (p) then
        file_list = nil
      end
      for _, each in ipairs (order) do
        if each == p or each:sub (1, #p + 1) == p .. '/' then
          check_soon (each)
        end
      end
    end)
    app.on ('fs:renamed', function (from, to)
      file_list = nil
      follow (tostring (from), tostring (to))
    end)

    -- Commands ---------------------------------------------------------------------------------

    ---@return boolean
    local function graph_in_front ()
      local d = api.active ()
      return d ~= nil
        and d.kind == 'graph'
        and not app.dom.focus_info ().editable
    end

    ---@param lang 'glsl'|'wgsl'|'gdshader'|'vertex'|'shadertoy'
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
      id = 'shader.new_godot',
      category = 'Shader',
      title = 'New Godot Shader',
      shared = true,
      menu = 'File',
      group = '1-new',
      order = 4,
      icon = 'gamepad-2',
      run = function ()
        ask_new ('gdshader', 'Name the new Godot shader')
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
        if exists (vert) then
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
      id = 'shader.new_buffer',
      category = 'Shader',
      title = 'Add a Buffer to This Shader',
      menu = 'File',
      group = '1-new',
      order = 6,
      icon = 'layers',
      when = function ()
        return api.active () ~= nil
      end,
      run = function ()
        local d = api.active ()
        if not d then
          return
        end
        local made, why = api.new_buffer (d.path)
        if not made then
          warn ('Could not add a buffer: ' .. tostring (why))
          return
        end
        local _, pass = core.passes.pass_of (made.path)
        say (
          'Added '
            .. core.passes.pass_label (pass)
            .. ', which draws before the image each frame. Set a channel of the image to '
            .. core.passes.pass_label (pass)
            .. ' in the Preview panel to read it.'
        )
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
            if exists (text) then
              return 'A file has that name already.'
            end
            return nil
          end,
          on_submit = function (text)
            local body = body_of (d)
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
      id = 'shader.rename',
      category = 'Shader',
      title = 'Rename...',
      menu = 'File',
      group = '3-save',
      icon = 'pencil',
      when = function ()
        return api.active () ~= nil and picker ~= nil
      end,
      run = function ()
        local d = api.active ()
        if not d or not picker then
          return
        end
        local path = d.path
        picker.input ({
          prompt = 'Rename ' .. base_name (path) .. ' to',
          value = path,
          validate = function (text)
            return rename_problem (path, text)
          end,
          on_submit = function (text)
            local ok, err = api.rename (path, text)
            if not ok then
              warn ('Could not rename ' .. path .. ': ' .. tostring (err))
            end
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
      if skip_reopen then
        return
      end
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
