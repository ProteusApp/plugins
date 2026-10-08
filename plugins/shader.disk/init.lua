-- shader.disk: shaders in the Code Editor's folder open in the Shader Builder.
--
-- With the shader plugins switched on beside the Code Editor, opening a graph (.shader.json)
-- or a code shader (.frag, .vert, .glsl, .wgsl or .gdshader) from the file tree opens it in
-- the builder: a graph on its node canvas, and code beside the live Preview. **Open as Text**
-- in the file tree's right-click menu opens one in the plain editor instead.
--
-- shader.docs keeps workspace files only, so this plugin reads a shader on disk, with the
-- shaders beside it that it may run with, such as its .vert file and its buffers, and hands
-- them over. Saves come back here, and only those files may be written.

local disk_paths = require ('disk_paths') --[[@as DiskPaths]]

-- The most shaders read from one folder for the shader being opened.
local MAX_NEIGHBOURS = 24

---@type Proteus.Plugin
return {
  name = 'Shaders on disk',
  description = 'Opens the shaders in the Code Editor folder in the Shader Builder, with a live preview.',
  version = '1.0.0',
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
    'proteus.code.project',
    'proteus.code.explorer',
    'ui.notify',
  },
  activate = function (app)
    local docs = app.use ('shader.docs') --[[@as Shader.Docs]]
    local editor = app.use ('editor')
    local notify = app.try_use ('notify')

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
