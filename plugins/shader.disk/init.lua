-- shader.disk: shaders in the Code Editor's folder open in the Shader Builder.
--
-- With the shader plugins switched on beside the Code Editor, opening a graph (.shader.json)
-- or a code shader (.frag, .vert, .glsl, .wgsl or .gdshader) from the file tree opens it in
-- the builder: a graph on its node canvas, and code beside the live Preview. **Open as Text**
-- in the file tree's right-click menu opens one in the plain editor instead, and the Preview
-- follows that tab too, as it is typed in.
--
-- A folder's right-click menu makes a new shader graph or Godot shader there.
--
-- shader.docs keeps workspace files only, so this plugin reads a shader on disk, with the
-- shaders beside it that it may run with, such as its .vert file and its buffers, and hands
-- them over. Saves come back here, and only those files may be written.

local disk_paths = require ('disk_paths') --[[@as DiskPaths]]

-- The most shaders read from one folder for the shader being opened.
local MAX_NEIGHBOURS = 24
-- How long after an edit the Preview takes the Code Editor's text, in milliseconds.
local FOLLOW_MS = 150

---@type Proteus.Plugin
return {
  name = 'Shaders on disk',
  description = 'Opens the shaders in the Code Editor folder in the Shader Builder, with a live preview.',
  version = '1.1.0',
  requires = { proteus = '>=0.3.1', features = { 'permissions' } },
  -- `files` for the `editor` service, and to read and save the shaders on disk.
  permissions = { 'files' },
  -- The canvas, the code view and the Preview come along, so switching this one plugin on in
  -- the Code Editor brings the whole builder.
  depends = {
    'lib.ui',
    'shader.core',
    'shader.docs',
    'shader.canvas',
    'shader.code',
    'shader.preview',
    'proteus.editor.core',
  },
  optional = {
    'proteus.tools.diagnostics',
    'proteus.code.project',
    'proteus.code.explorer',
    'ui.notify',
    'ui.palette',
  },
  activate = function (app)
    local docs = app.use ('shader.docs') --[[@as Shader.Docs]]
    local editor = app.use ('editor')
    local notify = app.try_use ('notify')
    local picker = app.try_use ('picker')
    local core = app.use ('shader') --[[@as Shader.Core]]

    -- Files handed to the builder, which its saves may write.
    local handed = {} ---@type table<string, boolean>

    ---@param text string
    local function warn (text)
      if notify then
        notify.error (text)
      else
        app.warn (text)
      end
    end

    -- The Code Editor reopens its own files, so the builder's last shaders stay closed.
    docs.skip_reopen ()

    app.dispose (docs.attach_disk (function (path, text, done)
      if not handed[path] then
        done ('the Shader Builder did not open ' .. path)
        return
      end
      app.fs.write_file (path, text, function (ok, err)
        done ((not ok) and tostring (err or 'it could not be written') or nil)
      end)
    end))

    ---Reads the shader at `path` and the shaders in its folder, then opens it.
    ---@param path string
    local function open_disk (path)
      local folder = disk_paths.parent (path)
      app.fs.list_dir (folder, function (names)
        local wanted = { path } ---@type string[]
        for _, name in ipairs (names or {}) do
          local p = disk_paths.join (folder, name)
          if
            #wanted < MAX_NEIGHBOURS
            and p ~= path
            and name:sub (-1) ~= '/'
            and docs.kind_of (p)
          then
            wanted[#wanted + 1] = p
          end
        end
        local texts = {} ---@type table<string, string>
        local left = #wanted
        for _, p in ipairs (wanted) do
          app.fs.read_file (p, function (text)
            if text then
              texts[p] = text
              handed[p] = true
            end
            left = left - 1
            if left == 0 then
              if not texts[path] then
                warn ('Could not read ' .. path .. '.')
                return
              end
              docs.open_disk (path, texts)
            end
          end)
        end
      end)
    end

    app.dispose (editor.add_opener (function (path, opts)
      if (opts and opts.as_text) or not docs.kind_of (path) then
        return false
      end
      if disk_paths.is_absolute (path) then
        open_disk (disk_paths.normalize (path))
      else
        docs.open (path)
      end
      return true
    end))

    -- A shader changed or deleted outside the builder reads again, or says it is gone.
    app.on ('code:disk_changed', function (changes)
      for _, change in ipairs (changes or {}) do
        local p = change.path
        if handed[p] then
          if change.kind == 'remove' then
            docs.disk_changed (p, nil)
          else
            app.fs.read_file (p, function (text)
              docs.disk_changed (p, text)
            end)
          end
        end
      end
    end)

    -- The Code Editor's tab in front runs in the Preview while it holds a shader, and each edit
    -- shows a moment later. A builder tab, or the last shader followed, stays in the Preview
    -- while another kind of file is in front.
    local followed = nil ---@type string?
    local pending = false

    local function follow_front ()
      pending = false
      local doc = editor.current ()
      if not doc or not docs.kind_of (doc.path) then
        return
      end
      local path = doc.external and disk_paths.normalize (doc.path) or doc.path
      if followed and followed ~= path then
        docs.unfollow (followed)
      end
      followed = path
      docs.follow (path, doc.text ())
    end

    local function follow_soon ()
      if not pending then
        pending = true
        app.timer.after (FOLLOW_MS, follow_front)
      end
    end

    app.on ('tabs:changed', follow_soon)
    app.on ('editor:opened', follow_soon)
    app.on ('editor:changed', function (doc)
      if docs.kind_of (doc.path) then
        follow_soon ()
      end
    end)
    app.on ('editor:closed', function (path)
      local p = disk_paths.is_absolute (path) and disk_paths.normalize (path)
        or path
      if p == followed then
        docs.unfollow (p)
        followed = nil
      end
    end)
    follow_soon ()

    -- What the compiler finds in a followed shader goes to the Problems panel, on its lines.
    local diagnostics = app.try_use ('diagnostics')
    if diagnostics then
      local shown = {} ---@type table<string, boolean>
      app.on ('shader:problems', function (path, list)
        if path ~= followed and not shown[path] then
          return
        end
        local out = {} ---@type Proteus.Diagnostic[]
        for _, p in ipairs (list or {}) do
          if p.line then
            out[#out + 1] = {
              line = math.max (0, p.line - 1),
              character = math.max (0, (p.column or 1) - 1),
              end_line = math.max (0, p.line - 1),
              end_character = 999,
              severity = p.severity == 'warning' and 'warning' or 'error',
              message = p.message,
              source = 'shader',
            }
          end
        end
        shown[path] = #out > 0 or nil
        diagnostics.set ('shader', path, out)
      end)
      app.on ('shader:closed', function (path)
        if shown[path] then
          shown[path] = nil
          diagnostics.set ('shader', path, {})
        end
      end)
    end

    local explorer = app.try_use ('code.explorer')
    if explorer and explorer.add_menu_item then
      explorer.add_menu_item ({
        label = 'Open as Text',
        icon = 'file-text',
        when = function (path)
          return docs.kind_of (path) ~= nil
        end,
        run = function (path)
          editor.open_external (path, { as_text = true })
        end,
      })
      ---Adds a menu item to folders that writes a new shader there and opens it.
      ---@param label string
      ---@param icon string
      ---@param ending string
      ---@param body fun(): string
      local function new_item (label, icon, ending, body)
        explorer.add_menu_item ({
          label = label,
          icon = icon,
          folders = true,
          run = function (folder)
            local function make (name)
              local clean =
                name:gsub ('[^%w%-_ ]', ''):gsub ('%s+', '-'):lower ()
              if clean == '' then
                clean = 'shader'
              end
              local path =
                disk_paths.join (disk_paths.normalize (folder), clean .. ending)
              app.fs.stat_path (path, function (stat)
                if stat and stat.exists then
                  warn (disk_paths.name (path) .. ' is there already.')
                  return
                end
                app.fs.write_file (path, body (), function (ok, err)
                  if not ok then
                    warn ('Could not write ' .. path .. ': ' .. tostring (err))
                    return
                  end
                  open_disk (path)
                end)
              end)
            end
            if picker then
              picker.input ({
                prompt = 'Name the new shader',
                value = 'my-shader',
                on_submit = make,
              })
            else
              make ('shader')
            end
          end,
        })
      end
      new_item (
        'New Shader Graph…',
        'workflow',
        core.file.EXTENSION,
        function ()
          return core.file.save (core.graph.new ('My Shader'))
        end
      )
      new_item ('New Godot Shader…', 'gamepad-2', '.gdshader', function ()
        return core.source.TEMPLATES.gdshader
      end)
      explorer.add_menu_item ({
        label = 'Open in the Shader Builder',
        icon = 'workflow',
        when = function (path)
          return docs.kind_of (path) ~= nil
        end,
        run = function (path)
          open_disk (disk_paths.normalize (path))
        end,
      })
    end
  end,
}
