-- shader.build: turns the shader in front into files that stand on their own. A graph builds
-- into GLSL and WGSL both. A code shader builds in its own language, with everything a short
-- shader leaves out filled in. Each build also writes a page that runs the shader in any
-- browser, the list of its uniforms, and a README.

local BUILD_FOLDER = 'shaders/build'

---@type Proteus.Plugin
return {
  name = 'Shader build',
  description = 'Builds the shader in front into complete GLSL and WGSL files, a page that runs it, and a list of its uniforms.',
  version = '1.0.2',
  requires = { proteus = '>=0.2.0', features = { 'permissions', 'folders' } },
  -- Export to Folder writes the build anywhere on disk the user picks.
  permissions = { 'files' },
  folders = { 'shaders' },
  depends = { 'shader.core', 'shader.docs', 'core.commands' },
  optional = { 'ui.notify', 'ui.palette' },
  activate = function (app)
    local core = app.use ('shader') --[[@as Shader.Core]]
    local docs = app.use ('shader.docs') --[[@as Shader.Docs]]
    local commands = app.use ('commands')
    local notify = app.try_use ('notify')

    ---@param text string
    ---@param action? { label: string, run: fun() }
    local function say (text, action)
      if notify then
        notify.success (text, { action = action })
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

    ---What the shader in front builds into, or why it cannot build.
    ---@return Shader.BuildInput?, string?
    local function input_of_front ()
      local d = docs.active ()
      if not d then
        return nil, 'Open a shader to build it.'
      end
      if d.kind == 'graph' then
        local result = docs.compiled (d.path) --[[@as Shader.CompileResult]]
        if not result.ok then
          return nil,
            'The graph has problems: '
              .. result.errors[1].message
              .. ' Fix them to build it.'
        end
        return {
          name = d.history.doc.name ~= '' and d.history.doc.name or d.title,
          glsl = result.glsl,
          wgsl = result.wgsl,
        }
      end
      local program, errors = docs.program (d.path)
      if not program then
        return nil,
          errors and errors[1] and errors[1].message or 'Nothing to build.'
      end
      for _, e in ipairs (errors or {}) do
        if e.severity ~= 'warning' then
          return nil, e.message
        end
      end
      local stem = d.title:gsub ('%.[%w]+$', '')
      if program.language == 'wgsl' then
        return { name = stem, wgsl = program }
      end
      return { name = stem, glsl = program }
    end

    ---@return table<string, string>?, string?
    local function files_of_front ()
      local input, err = input_of_front ()
      if not input then
        return nil, err
      end
      return core.build.files (input), core.build.stem (input.name)
    end

    ---@param files table<string, string>
    ---@return string[]
    local function sorted_names (files)
      local names = {} ---@type string[]
      for name in pairs (files) do
        names[#names + 1] = name
      end
      table.sort (names)
      return names
    end

    commands.register ({
      id = 'shader.build',
      category = 'Shader',
      title = 'Build Shader',
      -- The code view's Build button runs it too.
      shared = true,
      menu = 'Build',
      icon = 'package',
      key = 'ctrl+shift+b',
      toolbar = 20,
      toolbar_text = 'Build',
      when = function ()
        return docs.active () ~= nil
      end,
      run = function ()
        local files, stem = files_of_front ()
        if not files then
          warn (stem or 'Nothing to build.')
          return
        end
        local folder = BUILD_FOLDER .. '/' .. stem
        for _, name in ipairs (sorted_names (files)) do
          local ok, err =
            pcall (app.fs.write, folder .. '/' .. name, files[name])
          if not ok then
            warn ('Could not write ' .. name .. ': ' .. tostring (err))
            return
          end
        end
        local main = files[stem .. '.frag'] and (stem .. '.frag')
          or (stem .. '.wgsl')
        say ('Built ' .. folder .. '.', {
          label = 'Open ' .. main,
          run = function ()
            docs.open (folder .. '/' .. main)
          end,
        })
      end,
    })

    commands.register ({
      id = 'shader.export',
      category = 'Shader',
      title = 'Export to Folder...',
      menu = 'Build',
      icon = 'folder-output',
      when = function ()
        return docs.active () ~= nil and app.platform == 'tauri'
      end,
      run = function ()
        local files, stem = files_of_front ()
        if not files then
          warn (stem or 'Nothing to build.')
          return
        end
        app.fs.pick_open ({
          title = 'Export the shader into a folder',
          directory = true,
        }, function (paths)
          local dir = paths and paths[1]
          if not dir then
            return
          end
          local target = dir:gsub ('\\', '/'):gsub ('/$', '') .. '/' .. stem
          app.fs.make_dir (target, function (_, err)
            if err then
              warn ('Could not make ' .. target .. ': ' .. tostring (err))
              return
            end
            local names = sorted_names (files)
            local left = #names
            local failed = nil ---@type string?
            for _, name in ipairs (names) do
              app.fs.write_file (
                target .. '/' .. name,
                files[name],
                function (_, write_err)
                  if write_err then
                    failed = failed or write_err
                  end
                  left = left - 1
                  if left == 0 then
                    if failed then
                      warn ('Some files did not write: ' .. failed)
                    else
                      say (
                        'Exported ' .. #names .. ' files to ' .. target .. '.',
                        {
                          label = 'Show Folder',
                          run = function ()
                            app.system.open_path (target)
                          end,
                        }
                      )
                    end
                  end
                end
              )
            end
          end)
        end)
      end,
    })

    ---@param lang Shader.Lang
    local function copy (lang)
      local d = docs.active ()
      if not d then
        return
      end
      local program = docs.program (d.path, lang)
      if not program or program.language ~= lang then
        warn (
          'A '
            .. d.language:upper ()
            .. ' shader has no '
            .. lang:upper ()
            .. ' code to copy.'
        )
        return
      end
      app.system.clipboard (program.source)
      say ('Copied the ' .. lang:upper () .. ' code.')
    end

    commands.register ({
      id = 'shader.copy_glsl',
      category = 'Shader',
      title = 'Copy the GLSL Fragment Shader',
      menu = 'Build',
      icon = 'copy',
      when = function ()
        local d = docs.active ()
        return d ~= nil and (d.kind == 'graph' or d.language == 'glsl')
      end,
      run = function ()
        copy ('glsl')
      end,
    })
    commands.register ({
      id = 'shader.copy_wgsl',
      category = 'Shader',
      title = 'Copy the WGSL Module',
      menu = 'Build',
      icon = 'copy',
      when = function ()
        local d = docs.active ()
        return d ~= nil and (d.kind == 'graph' or d.language == 'wgsl')
      end,
      run = function ()
        copy ('wgsl')
      end,
    })
  end,
}
