-- shader.build: turns the shader in front into files that stand on their own. A graph builds
-- into GLSL and WGSL both, and for other engines: HLSL, Godot, three.js and Unity. A code
-- shader builds in its own language, with everything a short shader leaves out filled in.
-- Each build also writes a page that runs the shader in any browser, the list of its
-- uniforms, and a README.
--
-- A build goes into shaders/build in the workspace, the one folder it writes. It asks for no
-- permission, so it reaches no other file on disk.

local BUILD_FOLDER = 'shaders/build'

---@type Proteus.Plugin
return {
  name = 'Shader build',
  description = 'Builds the shader in front into complete GLSL and WGSL files, a page that runs it, a list of its uniforms, and a graph for other engines.',
  version = '1.3.0',
  requires = { proteus = '>=0.2.0', features = { 'permissions', 'folders' } },
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

    ---The name of a shader's file, without its folder and ending.
    ---@param path string
    ---@return string
    local function stem_of (path)
      local name = path:match ('([^/]+)$') or path
      if name:lower ():sub (-#core.file.EXTENSION) == core.file.EXTENSION then
        return name:sub (1, -#core.file.EXTENSION - 1)
      end
      return (name:gsub ('%.[%w]+$', ''))
    end

    ---A pass's code in each language it has, or why it cannot build.
    ---@param path string
    ---@param label string
    ---@return { glsl?: Shader.Program, wgsl?: Shader.Program, ir?: Shader.Ir }?, string?
    local function code_of (path, label)
      if docs.kind_of (path) == 'graph' then
        local result = docs.compiled (path)
        if not result then
          return nil, 'There is no file at ' .. path .. '.'
        end
        if not result.ok then
          return nil,
            label
              .. ' has problems: '
              .. result.errors[1].message
              .. ' Fix them to build it.'
        end
        return { glsl = result.glsl, wgsl = result.wgsl, ir = result.ir }
      end
      local program, errors = docs.program (path)
      if not program then
        return nil,
          errors and errors[1] and errors[1].message or 'Nothing to build.'
      end
      for _, e in ipairs (errors or {}) do
        if e.severity ~= 'warning' then
          return nil, label .. ': ' .. e.message
        end
      end
      return { [program.language] = program }
    end

    ---What the shader in front builds into, or why it cannot build. A buffer in front builds
    ---the whole shader it belongs to.
    ---@return Shader.BuildInput?, string?
    local function input_of_front ()
      local d = docs.active ()
      if not d then
        return nil, 'Open a shader to build it.'
      end
      local set = docs.passes (d.path)
      local image = set.image
      if not image then
        return nil,
          'This shader has buffers but no image, such as '
            .. set.base
            .. '.frag. Add one to build it.'
      end
      local code, err = code_of (image, 'The shader')
      if not code then
        return nil, err
      end
      local open_doc = docs.get (image)
      local name = stem_of (image)
      if open_doc and open_doc.history and open_doc.history.doc.name ~= '' then
        name = open_doc.history.doc.name
      end
      ---@type Shader.BuildInput
      local input = {
        name = name,
        glsl = code.glsl,
        wgsl = code.wgsl,
        channels = docs.channels (image),
        buffers = {},
        ir = code.ir,
      }
      local any = { glsl = code.glsl ~= nil, wgsl = code.wgsl ~= nil }
      for _, b in ipairs (core.passes.BUFFERS) do
        local path = set.buffers[b]
        if path then
          local label = core.passes.pass_label (b)
          local pass, why = code_of (path, label)
          if not pass then
            return nil, why
          end
          any.glsl = any.glsl and pass.glsl ~= nil
          any.wgsl = any.wgsl and pass.wgsl ~= nil
          input.buffers[#input.buffers + 1] = {
            id = b,
            glsl = pass.glsl,
            wgsl = pass.wgsl,
            channels = docs.channels (path),
          }
        end
      end
      if not any.glsl and not any.wgsl then
        return nil, 'Every pass needs its code in one language to build.'
      end
      return input
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

    ---Copies the graph in front, written for another engine.
    ---@param target Shader.ExportTarget
    local function copy_for (target)
      local d = docs.active ()
      local result = d and docs.compiled (d.path)
      if not result then
        warn ('Only a node graph exports to other engines.')
        return
      end
      if not result.ok then
        warn (
          'The graph has problems: '
            .. result.errors[1].message
            .. ' Fix them to export it.'
        )
        return
      end
      local text = core.export.export (target.id, result.ir)
      if text then
        app.system.clipboard (text)
        say ('Copied the shader for ' .. target.title .. '.')
      end
    end

    commands.register ({
      id = 'shader.copy_engine',
      category = 'Shader',
      title = 'Copy the Shader for Another Engine...',
      menu = 'Build',
      icon = 'copy',
      when = function ()
        local d = docs.active ()
        return d ~= nil and d.kind == 'graph'
      end,
      run = function ()
        local picker = app.try_use ('picker')
        if not picker then
          copy_for (core.export.TARGETS[1])
          return
        end
        local items = {} ---@type Proteus.PickItem[]
        for _, t in ipairs (core.export.TARGETS) do
          items[#items + 1] =
            { label = t.title, detail = t.about, value = t.id }
        end
        picker.pick ({
          placeholder = 'Copy the shader for which engine?',
          items = items,
          on_pick = function (item)
            local target = core.export.target (tostring (item.value))
            if target then
              copy_for (target)
            end
          end,
        })
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
