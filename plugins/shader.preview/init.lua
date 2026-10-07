-- shader.preview: runs the shader in front, live. GLSL runs on WebGL 2 and WGSL on WebGPU,
-- in a web view: page/preview.js draws, and this plugin sends it the passes as messages.
-- The panel shows the picture, its problems by line or by node, what each channel shows, and
-- a control for every uniform: a Parameter node in a graph, or a uniform with notes in a code
-- shader. Moving a control changes the picture at once, without compiling again.
--
-- A shader's buffers run before it each frame, and its channels read them, noise, a checker,
-- or an image the user picks. An image comes through app.grants, so the plugin never sees a
-- path and needs no permission: the web view gets the file's bytes.
--
-- The View menu puts the shader on a mesh, a sphere, a cube, a plane or a torus, which a drag
-- turns. A graph, or a GLSL shader that reads only v_uv for its place, colours the mesh's
-- surface as its fragment shader. Any other shader draws a square picture the mesh shows.

-- lang=css
local CSS = [[
.sp-root { display: flex; flex-direction: column; height: 100%; min-height: 0; font-size: 12px; }
.sp-bar {
  display: flex;
  align-items: center;
  gap: 4px;
  padding: 4px 6px;
  border-bottom: 0.5px solid var(--border);
  background: var(--bg-alt);
  flex-wrap: wrap;
}
.sp-bar .sp-grow { flex: 1; }
.sp-seg { display: flex; border: 0.5px solid var(--border); border-radius: 6px; overflow: hidden; }
.sp-seg button {
  border: none;
  background: transparent;
  color: var(--fg-muted);
  font: inherit;
  padding: 2px 9px;
  cursor: pointer;
}
.sp-seg button.on { background: var(--accent); color: var(--accent-fg, #fff); }
.sp-seg button:disabled { cursor: default; opacity: 0.5; }
.sp-view {
  font: inherit;
  font-size: 11.5px;
  color: var(--fg);
  background: var(--bg);
  border: 0.5px solid var(--border);
  border-radius: 5px;
  padding: 1px 4px;
}
.sp-surface { position: relative; flex: none; height: 46%; min-height: 160px; border-bottom: 0.5px solid var(--border); }
.sp-root.large .sp-surface { flex: 1; height: auto; }
.sp-stats { display: flex; gap: 10px; padding: 3px 8px; color: var(--fg-muted); font-family: var(--font-mono); font-size: 11px; border-bottom: 0.5px solid var(--border); }
.sp-scroll { flex: 1; min-height: 0; overflow: auto; }
.sp-root.large .sp-scroll { flex: none; max-height: 30%; }
.sp-section { padding: 6px 8px; }
.sp-section h4 { margin: 2px 0 6px; font-size: 11px; text-transform: uppercase; letter-spacing: 0.04em; color: var(--fg-muted); }
.sp-problem { display: flex; gap: 6px; padding: 4px 6px; border-radius: 5px; cursor: pointer; line-height: 1.35; }
.sp-problem:hover { background: var(--bg-hover, var(--bg-alt)); }
.sp-problem .where { flex: none; color: var(--fg-muted); font-family: var(--font-mono); }
.sp-problem.error .what { color: var(--danger); }
.sp-problem.warning .what { color: var(--warning, #d97706); }
.sp-ok { color: var(--success, #16a34a); padding: 2px 6px; }
.sp-uniform { display: grid; grid-template-columns: 92px 1fr; gap: 4px 8px; align-items: center; margin-bottom: 6px; }
.sp-uniform .name { font-family: var(--font-mono); font-size: 11px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.sp-uniform .parts { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
.sp-part { display: flex; gap: 6px; align-items: center; }
.sp-part input[type=range] { flex: 1; min-width: 0; accent-color: var(--accent); }
.sp-part .num { width: 48px; text-align: right; font-family: var(--font-mono); font-size: 11px; color: var(--fg-muted); }
.sp-part input[type=color] { width: 44px; height: 22px; padding: 0; border: 0.5px solid var(--border); border-radius: 4px; background: none; }
.sp-empty { color: var(--fg-muted); padding: 2px 6px; }
.sp-channel { display: grid; grid-template-columns: 92px 1fr; gap: 4px 8px; align-items: center; margin-bottom: 6px; }
.sp-channel .name { font-family: var(--font-mono); font-size: 11px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.sp-channel .parts { display: flex; flex-wrap: wrap; gap: 4px; align-items: center; min-width: 0; }
.sp-channel select {
  font: inherit;
  font-size: 11.5px;
  color: var(--fg);
  background: var(--bg);
  border: 0.5px solid var(--border);
  border-radius: 5px;
  padding: 1px 4px;
  max-width: 100%;
}
.sp-channel .file { color: var(--fg-muted); font-size: 11px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; max-width: 120px; }
]]

local SCALES = { 0.5, 1, 2 }

-- What the picture shows on: the whole panel, or a mesh.
local SHAPES = {
  { 'flat', 'Flat' },
  { 'sphere', 'Sphere' },
  { 'cube', 'Cube' },
  { 'plane', 'Plane' },
  { 'torus', 'Torus' },
}

-- What a channel can show, as the choices of its menu.
local SOURCES = {
  { 'none', 'Nothing' },
  { 'noise', 'Noise' },
  { 'checker', 'Checker' },
  { 'image', 'Image…' },
  { 'buffer-a', 'Buffer A' },
  { 'buffer-b', 'Buffer B' },
  { 'buffer-c', 'Buffer C' },
  { 'buffer-d', 'Buffer D' },
}

local IMAGE_TYPES = { 'png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp', 'avif' }

local DIMS =
  { float = 1, int = 1, uint = 1, bool = 1, vec2 = 2, vec3 = 3, vec4 = 4 }

---@type Proteus.Plugin
return {
  name = 'Shader preview',
  description = 'Runs the shader in front live, flat or on a mesh, on WebGL 2 or WebGPU, with its buffers, its channels, its problems and a control for every uniform.',
  version = '1.2.1',
  requires = {
    proteus = '>=0.2.0',
    features = { 'permissions', 'webview', 'grants' },
  },
  permissions = {},
  depends = {
    'lib.ui',
    'shader.core',
    'shader.docs',
    'ui.views',
    'core.commands',
  },
  optional = { 'ui.tabs', 'shader.canvas', 'ui.statusbar', 'ui.notify' },
  activate = function (app)
    local notify = app.try_use ('notify')
    local ui = app.use ('ui')
    local core = app.use ('shader') --[[@as Shader.Core]]
    local docs = app.use ('shader.docs') --[[@as Shader.Docs]]
    local views = app.use ('views')
    local commands = app.use ('commands')
    local tabs = app.try_use ('tabs')
    local canvas = app.try_use ('shader.canvas') --[[@as Shader.CanvasService?]]
    local status = app.try_use ('status')
    ui.css (CSS)
    local to_hex, from_hex = core.format.to_hex, core.format.from_hex

    ---A number for a control, with up to three digits after the point.
    ---@param v number
    ---@return string
    local function fmt (v)
      return core.format.fmt (v, 3)
    end

    local status_item = status
      and status.add ({
        id = 'shader.preview',
        text = '',
        icon = 'monitor-play',
        align = 'right',
        tooltip = 'The shader preview',
        command = 'shader.toggle_play',
      })

    local previews = {} ---@type ShaderPreview.Instance[]
    -- Why an image a channel shows did not arrive, by grant.
    local file_errors = {} ---@type table<string, string>

    ---@param text string
    local function warn (text)
      if notify then
        notify.error (text)
      else
        app.warn (text)
      end
    end

    ---Asks the user for an image for a channel, and shows it there.
    ---@param path string
    ---@param index integer
    ---@param src Shader.ChannelSource
    local function pick_image (path, index, src)
      if not app.grants then
        warn ('Picking an image needs a newer version of Proteus.')
        return
      end
      app.grants.open ({
        title = 'Pick an Image for iChannel' .. index,
        filters = { { name = 'Images', extensions = IMAGE_TYPES } },
      }, function (picked, err)
        local g = picked and picked[1]
        if not g then
          if err then
            warn ('Could not pick an image: ' .. tostring (err))
          end
          return
        end
        -- Picking a file again sends its bytes again, even one refused earlier.
        file_errors[g.id] = nil
        for _, p in ipairs (previews) do
          p.resend (g.id)
        end
        docs.set_channel (path, index, {
          kind = 'image',
          grant = g.id,
          name = g.name,
          filter = src.filter,
          wrap = src.wrap,
        })
      end)
    end

    ---Builds one preview: the picture and its panels. The dock and the large tab each have one.
    ---@param large boolean
    ---@return ShaderPreview.Instance
    local function make_preview (large)
      local shown_path = nil ---@type string?
      local shown_pass = 'image' ---@type Shader.PassId
      local last_key = nil ---@type string?
      -- The passes that run, by id: each one's file and program.
      local runs = {} ---@type table<string, { path: string, program: Shader.Program }>
      local lua_errors = {} ---@type Shader.CompileError[]
      local gpu_errors = {} ---@type Shader.GpuError[]
      -- The images whose bytes went to this preview's page, by grant.
      local sent = {} ---@type table<string, boolean>
      local playing = true
      local uniform_shape = ''
      local channel_shape = ''
      local scale = tonumber (app.store.get ('scale', 1)) or 1
      local shape = tostring (app.store.get ('view', 'flat'))
      local lang_buttons = {} ---@type table<string, Proteus.El>
      local scale_buttons = {} ---@type table<number, Proteus.El>
      local problems_el = ui.div ({ class = 'sp-section' })
      local uniforms_el = ui.div ({ class = 'sp-section' })
      local channels_el = ui.div ({ class = 'sp-section' })
      local fps_el = ui.span ({ text = '' })
      local time_el = ui.span ({ text = '' })
      local lang_el = ui.span ({ text = '' })
      local inst ---@type ShaderPreview.Instance

      ---Problems from the compiler, as lines of the user's text or nodes of the graph.
      ---@return Shader.CompileError[]
      local function mapped ()
        local out = {} ---@type Shader.CompileError[]
        for _, e in ipairs (lua_errors) do
          out[#out + 1] = e
        end
        for _, e in ipairs (gpu_errors) do
          local pass = e.pass or shown_pass
          local run = runs[pass]
          local p = run and run.program
          local line = e.line
          local node ---@type string?
          if line and p then
            if p.lines then
              node = p.lines[line]
            end
            if e.stage == 'vertex' then
              line = line - (p.vertex_offset or 0)
            else
              line = line - p.offset
            end
            -- Lines outside the user's text, such as the added main, point nowhere.
            local past = e.stage ~= 'vertex'
              and p.user_lines ~= nil
              and line > p.user_lines
            if line < 1 or past then
              line = nil
            end
          end
          out[#out + 1] = {
            message = e.message,
            line = not (p and p.lines) and line or nil,
            column = e.column,
            node = node,
            severity = e.severity,
            stage = e.stage == 'vertex' and 'vertex' or 'fragment',
            pass = pass ~= shown_pass and pass or nil,
            path = run and run.path or nil,
          }
        end
        return out
      end

      local function draw_problems ()
        local list = mapped ()
        if shown_path and not large then
          -- Each pass's lines go to its own file's editor.
          local by_path = { [shown_path] = {} } ---@type table<string, Shader.CompileError[]>
          for _, run in pairs (runs) do
            by_path[run.path] = by_path[run.path] or {}
          end
          for _, e in ipairs (list) do
            local where = e.path or shown_path
            if e.line and by_path[where] then
              table.insert (by_path[where], e)
            end
          end
          for path, code_list in pairs (by_path) do
            app.emit ('shader:problems', path, code_list)
          end
        end
        local children = { ui.h4 ({ 'Problems' }) } ---@type Proteus.Child[]
        if not shown_path then
          children[#children + 1] = ui.div ({
            class = 'sp-empty',
            'Open a shader to see it run.',
          })
        elseif #list == 0 then
          children[#children + 1] =
            ui.div ({ class = 'sp-ok', 'None. The shader compiles.' })
        end
        for _, e in ipairs (list) do
          local where = e.node and ('node ' .. e.node)
            or (e.line and ('line ' .. e.line))
            or (e.stage or '')
          if e.pass then
            where = core.passes.pass_label (e.pass) .. ' ' .. where
          end
          children[#children + 1] = ui.div ({
            class = {
              'sp-problem',
              e.severity == 'warning' and 'warning' or 'error',
            },
            ui.span ({ class = 'where', where }),
            ui.span ({ class = 'what', e.message }),
            onclick = function ()
              if e.path and e.path ~= shown_path then
                docs.open (e.path)
              elseif e.node and canvas and shown_path then
                canvas.select (shown_path, { e.node })
              end
            end,
          })
        end
        problems_el:set_children (children)
      end

      ---@param message any
      local function on_message (message)
        if type (message) ~= 'table' then
          return
        end
        if message.type == 'status' then
          local list = {} ---@type Shader.GpuError[]
          local errors = type (message.errors) == 'table' and message.errors
            or {} --[[@as table[] ]]
          for _, e in ipairs (errors) do
            if type (e) == 'table' and type (e.message) == 'string' then
              list[#list + 1] = e --[[@as Shader.GpuError]]
            end
          end
          table.sort (list, function (a, b)
            return (tonumber (a.line) or 0) < (tonumber (b.line) or 0)
          end)
          gpu_errors = list
          draw_problems ()
        elseif message.type == 'file' and type (message.grant) == 'string' then
          file_errors[message.grant] =
            tostring (message.error or 'It did not load.')
          app.timer.after (0, function ()
            for _, p in ipairs (previews) do
              p.refresh ()
            end
          end)
        elseif message.type == 'stats' then
          local fps = tonumber (message.fps) or 0
          fps_el:text (string.format ('%d fps', math.floor (fps + 0.5)))
          time_el:text (string.format ('%.1f s', tonumber (message.time) or 0))
          if status_item and not large then
            status_item.set (string.format ('%d fps', math.floor (fps + 0.5)))
          end
        end
      end

      local surface = ui.webview ({
        page = 'page/preview.html',
        on_message = on_message,
        on_status = function (st)
          if not st.responsive then
            gpu_errors = {
              {
                message = st.error or 'The preview stopped answering.',
                stage = 'setup',
                severity = 'error',
              },
            }
            draw_problems ()
          end
        end,
      })

      ---@param message table
      local function post (message)
        surface:widget ('post', message)
      end
      post ({ type = 'scale', scale = scale })
      post ({ type = 'view', shape = shape })

      ---What the page needs of a program, and nothing else. Each channel carries what it shows.
      ---@param p Shader.Program
      ---@param sources table<integer, Shader.ChannelSource>
      ---@return table
      local function page_program (p, sources)
        local uniforms = {} ---@type table[]
        for i, u in ipairs (p.uniforms) do
          uniforms[i] =
            { key = u.key, glsl = u.glsl, type = u.type, value = u.value }
        end
        local channels = {} ---@type table[]
        for i, c in ipairs (p.channels or {}) do
          channels[i] =
            { index = c.index, names = c.names, source = sources[c.index] }
        end
        return {
          language = p.language,
          source = p.source,
          vertex = p.vertex,
          vertex_entry = p.vertex_entry,
          fragment_entry = p.fragment_entry,
          uniforms = uniforms,
          layout = p.layout,
          bindings = p.bindings,
          channels = channels,
          surface = p.surface,
        }
      end

      ---A source as text, for telling whether anything the page runs changed.
      ---@param src Shader.ChannelSource?
      ---@return string
      local function source_key (src)
        if not src then
          return ''
        end
        return table.concat ({
          src.kind,
          src.buffer or '',
          src.grant or '',
          src.filter or '',
          src.wrap or '',
        }, ':')
      end

      ---@param u Shader.Uniform
      ---@param values number[]
      local function send (u, values)
        -- The controls now show values their key does not hold, so the next refresh, such
        -- as after an undo, draws them again.
        uniform_shape = ''
        post ({ type = 'uniform', key = u.key, value = values })
        if shown_path then
          docs.set_uniform (shown_path, u.key, values)
        end
      end

      ---One control for a uniform.
      ---@param u Shader.Uniform
      ---@return Proteus.El
      local function control (u)
        local values = {} ---@type number[]
        for i = 1, DIMS[u.type] or 1 do
          values[i] = tonumber (u.value[i]) or 0
        end
        local parts = {} ---@type Proteus.Child[]
        if u.color then
          parts[#parts + 1] = ui.div ({
            class = 'sp-part',
            ui.input ({
              type = 'color',
              value = to_hex (values),
              oninput = function (ev)
                local rgb = from_hex (ev.value or '')
                if rgb then
                  for i = 1, 3 do
                    values[i] = rgb[i]
                  end
                  send (u, values)
                end
              end,
            }),
          })
        elseif u.type == 'bool' then
          parts[#parts + 1] = ui.div ({
            class = 'sp-part',
            ui.input ({
              type = 'checkbox',
              checked = values[1] ~= 0,
              onchange = function (ev)
                values[1] = ev.checked and 1 or 0
                send (u, values)
              end,
            }),
          })
        else
          local lo, hi = u.min, u.max
          if hi <= lo then
            hi = lo + 1
          end
          local step = u.step or ((hi - lo) / 1000)
          for i = 1, #values do
            local num = ui.span ({ class = 'num', fmt (values[i]) })
            parts[#parts + 1] = ui.div ({
              class = 'sp-part',
              ui.input ({
                type = 'range',
                attrs = { min = lo, max = hi, step = step },
                value = values[i],
                oninput = function (ev)
                  local v = tonumber (ev.value)
                  if v then
                    values[i] = v
                    num:text (fmt (v))
                    send (u, values)
                  end
                end,
              }),
              num,
            })
          end
        end
        return ui.div ({
          class = 'sp-uniform',
          ui.span ({ class = 'name', title = u.key, u.key }),
          ui.div ({ class = 'parts', parts }),
        })
      end

      ---@param list Shader.Uniform[]
      local function draw_uniforms (list)
        local marks = {} ---@type string[]
        -- The values count too, so an undo moves the controls back. A control's own moves
        -- change no document, so they never draw the controls again mid-drag.
        for _, u in ipairs (list) do
          local values = {} ---@type string[]
          for i, v in ipairs (u.value) do
            values[i] = tostring (v)
          end
          marks[#marks + 1] = table.concat (values, ' ')
          marks[#marks + 1] = u.key
            .. ':'
            .. u.type
            .. ':'
            .. tostring (u.color)
            .. ':'
            .. u.min
            .. ':'
            .. u.max
        end
        local key = (shown_path or '') .. '|' .. table.concat (marks, ',')
        if key == uniform_shape then
          return
        end
        uniform_shape = key
        local children = { ui.h4 ({ 'Uniforms' }) } ---@type Proteus.Child[]
        if #list == 0 then
          children[#children + 1] = ui.div ({
            class = 'sp-empty',
            'None yet. Add a Parameter node, or a uniform with a note such as // @range 0 1.',
          })
        end
        for _, u in ipairs (list) do
          children[#children + 1] = control (u)
        end
        uniforms_el:set_children (children)
      end

      ---One channel's controls: what it shows, and how it filters and wraps.
      ---@param path string
      ---@param c Shader.Channel
      ---@param src Shader.ChannelSource
      ---@return Proteus.El
      local function channel_row (path, c, src)
        local current = src.kind == 'buffer'
            and ('buffer-' .. tostring (src.buffer))
          or src.kind
        ---@param words string
        local function set (words)
          local next_src = core.passes.parse_source (words) or { kind = 'none' }
          next_src.filter, next_src.wrap = src.filter, src.wrap
          docs.set_channel (path, c.index, next_src)
        end
        ---@type Proteus.ElementSpec
        local menu = {
          title = 'What iChannel' .. c.index .. ' shows',
          onchange = function (ev)
            local v = tostring (ev.value or '')
            if v == 'image' then
              pick_image (path, c.index, src)
              -- The menu shows the source again until an image is picked.
              channel_shape = ''
              app.timer.after (0, function ()
                inst.refresh ()
              end)
            else
              set (v)
            end
          end,
        }
        for _, o in ipairs (SOURCES) do
          menu[#menu + 1] =
            ui.h ('option', { value = o[1], selected = o[1] == current, o[2] })
        end
        local parts = { ui.h ('select', menu) } ---@type Proteus.Child[]
        if src.kind == 'image' then
          parts[#parts + 1] =
            ui.span ({ class = 'file', title = src.name, src.name or '' })
          parts[#parts + 1] = ui.button ({
            'Pick…',
            variant = 'ghost',
            title = 'Pick another image',
            onclick = function ()
              pick_image (path, c.index, src)
            end,
          })
        end
        if src.kind ~= 'none' then
          local filter = src.filter or 'linear'
          local wrap = src.wrap
            or (src.kind == 'buffer' and 'clamp' or 'repeat')
          parts[#parts + 1] = ui.h ('select', {
            title = 'How it reads between pixels',
            ui.h (
              'option',
              { value = 'linear', selected = filter == 'linear', 'Smooth' }
            ),
            ui.h (
              'option',
              { value = 'nearest', selected = filter == 'nearest', 'Pixels' }
            ),
            onchange = function (ev)
              local copy = core.graph.copy (src) --[[@as Shader.ChannelSource]]
              copy.filter = tostring (ev.value) == 'nearest' and 'nearest'
                or 'linear'
              docs.set_channel (path, c.index, copy)
            end,
          })
          parts[#parts + 1] = ui.h ('select', {
            title = 'What it reads past its edges',
            ui.h (
              'option',
              { value = 'repeat', selected = wrap == 'repeat', 'Repeat' }
            ),
            ui.h (
              'option',
              { value = 'clamp', selected = wrap == 'clamp', 'Clamp' }
            ),
            onchange = function (ev)
              local copy = core.graph.copy (src) --[[@as Shader.ChannelSource]]
              copy.wrap = tostring (ev.value) == 'clamp' and 'clamp' or 'repeat'
              docs.set_channel (path, c.index, copy)
            end,
          })
        end
        return ui.div ({
          class = 'sp-channel',
          ui.span ({
            class = 'name',
            title = table.concat (c.names, ', '),
            table.concat (c.names, ', '),
          }),
          ui.div ({ class = 'parts', parts }),
        })
      end

      ---The Channels section: one row for each channel the shader in front reads.
      ---@param path string?
      ---@param p Shader.Program?
      ---@param sources table<integer, Shader.ChannelSource>
      local function draw_channels (path, p, sources)
        local list = p and p.channels or {}
        local marks = { path or '' } ---@type string[]
        for _, c in ipairs (list) do
          marks[#marks + 1] = table.concat (c.names, ',')
            .. '='
            .. source_key (sources[c.index])
            .. ':'
            .. tostring (sources[c.index] and sources[c.index].name)
        end
        local key = table.concat (marks, '|')
        if key == channel_shape then
          return
        end
        channel_shape = key
        if #list == 0 or not path then
          channels_el:set_children ({})
          channels_el:show (false)
          return
        end
        local children = { ui.h4 ({ 'Channels' }) } ---@type Proteus.Child[]
        for _, c in ipairs (list) do
          children[#children + 1] =
            channel_row (path, c, sources[c.index] or { kind = 'none' })
        end
        channels_el:show (true)
        channels_el:set_children (children)
      end

      local function draw_bar ()
        local d = shown_path and docs.get (shown_path)
        for key, b in pairs (lang_buttons) do
          b:class ('on', d ~= nil and d.language == key)
          b:set ('disabled', not d or d.kind ~= 'graph')
        end
        for s, b in pairs (scale_buttons) do
          b:class ('on', s == scale)
        end
        lang_el:text (
          d and (d.language == 'wgsl' and 'WGSL · WebGPU' or 'GLSL · WebGL 2')
            or ''
        )
      end

      ---Runs the shader in front, compiling only when its code changed.
      local function refresh ()
        local d = docs.active ()
        shown_path = d and d.path or nil
        draw_bar ()
        if not d then
          runs, lua_errors, gpu_errors = {}, {}, {}
          last_key = nil
          draw_problems ()
          draw_uniforms ({})
          draw_channels (nil, nil, {})
          return
        end
        local p, errors = docs.program (d.path)
        local set = docs.passes (d.path)
        shown_pass = set.show
        lua_errors = {}
        for _, e in ipairs (errors or {}) do
          lua_errors[#lua_errors + 1] = e
        end
        if not p then
          runs, gpu_errors = {}, {}
          draw_problems ()
          draw_uniforms ({})
          draw_channels (nil, nil, {})
          return
        end
        -- Each buffer runs before the image, in the image's language. When a buffer is in
        -- front, the page shows its picture, and the image does not run.
        runs = {}
        local order = {} ---@type { id: Shader.PassId, path: string, program: Shader.Program }[]
        for _, b in ipairs (core.passes.BUFFERS) do
          local path = set.buffers[b]
          if path then
            local bp, berrors ---@type Shader.Program?, Shader.CompileError[]
            if b == set.show then
              bp, berrors = p, {}
            else
              bp, berrors = docs.program (path, p.language)
            end
            for _, e in ipairs (berrors or {}) do
              local copy = core.graph.copy (e) --[[@as Shader.CompileError]]
              copy.pass, copy.path = b, path
              lua_errors[#lua_errors + 1] = copy
            end
            if bp and bp.language ~= p.language then
              lua_errors[#lua_errors + 1] = {
                message = core.passes.pass_label (b)
                  .. ' is '
                  .. bp.language:upper ()
                  .. ', and this shader runs '
                  .. p.language:upper ()
                  .. '. Every pass runs in one language.',
                severity = 'error',
                pass = b,
                path = path,
              }
            elseif bp then
              order[#order + 1] = { id = b, path = path, program = bp }
            end
          end
        end
        if set.show == 'image' then
          order[#order + 1] = { id = 'image', path = d.path, program = p }
        end
        local passes = {} ---@type table[]
        local key_parts = { d.path, p.language, set.show } ---@type string[]
        local shown_sources = {} ---@type table<integer, Shader.ChannelSource>
        for i, run in ipairs (order) do
          runs[run.id] = { path = run.path, program = run.program }
          local sources = docs.channels (run.path)
          if run.id == set.show then
            shown_sources = sources
          end
          passes[i] =
            { id = run.id, program = page_program (run.program, sources) }
          local rp = run.program
          key_parts[#key_parts + 1] = table.concat ({
            run.id,
            rp.source,
            rp.vertex or '',
            rp.vertex_entry or '',
            rp.fragment_entry or '',
          }, '\1')
          for _, c in ipairs (rp.channels or {}) do
            local src = sources[c.index]
            key_parts[#key_parts + 1] = source_key (src)
            -- An image goes to the page once, and stays there for every pass.
            if src and src.kind == 'image' and src.grant then
              if file_errors[src.grant] then
                lua_errors[#lua_errors + 1] = {
                  message = 'iChannel'
                    .. c.index
                    .. ' shows '
                    .. (src.name or 'an image')
                    .. ', which did not arrive: '
                    .. file_errors[src.grant]
                    .. ' Pick it again to use it.',
                  severity = 'warning',
                  pass = run.id ~= set.show and run.id or nil,
                  path = run.path,
                }
              elseif not sent[src.grant] then
                sent[src.grant] = true
                local ok, err = pcall (
                  surface.widget,
                  surface,
                  'send_file',
                  src.grant,
                  src.grant
                )
                if not ok then
                  file_errors[src.grant] = tostring (err)
                end
              end
            end
          end
        end
        local key = table.concat (key_parts, '\0')
        if key ~= last_key then
          last_key = key
          post ({
            type = 'run',
            language = p.language,
            show = set.show,
            passes = passes,
          })
        else
          for _, u in ipairs (p.uniforms) do
            post ({ type = 'uniform', key = u.key, value = u.value })
          end
          -- After a run, the page's status draws the problems.
          draw_problems ()
        end
        draw_uniforms (p.uniforms)
        draw_channels (d.path, p, shown_sources)
      end

      ---@param key 'glsl'|'wgsl'
      ---@param label string
      ---@return Proteus.El
      local function lang_button (key, label)
        local b = ui.button ({
          label,
          title = 'Run the graph as ' .. label,
          onclick = function ()
            local d = docs.active ()
            if d and d.kind == 'graph' then
              docs.set_language (d.path, key)
            end
          end,
        })
        lang_buttons[key] = b
        return b
      end

      ---@param s number
      ---@return Proteus.El
      local function scale_button (s)
        local b = ui.button ({
          s == 0.5 and '½×' or (fmt (s) .. '×'),
          title = 'Draw ' .. fmt (s) .. ' pixels for each screen pixel',
          onclick = function ()
            scale = s
            app.store.set ('scale', s)
            for _, other in ipairs (previews) do
              other.set_scale (s)
            end
          end,
        })
        scale_buttons[s] = b
        return b
      end

      local play = ui.button ({
        icon = 'pause',
        variant = 'ghost',
        title = 'Pause or play (Ctrl+Space)',
        onclick = function ()
          commands.run ('shader.toggle_play')
        end,
      })

      ---@type Proteus.ElementSpec
      local view_menu = {
        class = 'sp-view',
        title = 'Show the shader flat, or on a mesh. Drag a mesh to turn it, and double-click to reset.',
        onchange = function (ev)
          local next_shape = tostring (ev.value or 'flat')
          app.store.set ('view', next_shape)
          for _, other in ipairs (previews) do
            other.set_view (next_shape)
          end
        end,
      }
      for _, o in ipairs (SHAPES) do
        view_menu[#view_menu + 1] =
          ui.h ('option', { value = o[1], selected = o[1] == shape, o[2] })
      end
      local view_select = ui.h ('select', view_menu)

      local scale_seg = ui.div ({ class = 'sp-seg' })
      for _, s in ipairs (SCALES) do
        scale_seg:append (scale_button (s))
      end

      local bar = ui.div ({
        class = 'sp-bar',
        play,
        ui.button ({
          icon = 'rotate-ccw',
          variant = 'ghost',
          title = 'Start the time again from 0',
          onclick = function ()
            post ({ type = 'restart' })
          end,
        }),
        ui.div ({
          class = 'sp-seg',
          lang_button ('glsl', 'GLSL'),
          lang_button ('wgsl', 'WGSL'),
        }),
        ui.span ({ class = 'sp-grow' }),
        view_select,
        scale_seg,
        not large and ui.button ({
          icon = 'maximize-2',
          variant = 'ghost',
          title = 'Open a large preview',
          onclick = function ()
            commands.run ('shader.large_preview')
          end,
        }) or nil,
      })

      local root = ui.div ({
        class = large and { 'sp-root', 'large' } or 'sp-root',
        bar,
        ui.div ({ class = 'sp-surface', surface }),
        ui.div ({ class = 'sp-stats', lang_el, fps_el, time_el }),
        ui.div ({ class = 'sp-scroll', problems_el, channels_el, uniforms_el }),
      })

      inst = {
        root = root,
        refresh = refresh,
        set_playing = function (on)
          playing = on
          post ({ type = on and 'play' or 'pause' })
          play:set_children ({ ui.icon (on and 'pause' or 'play', 16) })
        end,
        playing = function ()
          return playing
        end,
        set_scale = function (s)
          scale = s
          post ({ type = 'scale', scale = s })
          draw_bar ()
        end,
        set_view = function (next_shape)
          shape = next_shape
          view_select:set ('value', next_shape)
          post ({ type = 'view', shape = next_shape })
        end,
        uniform = function (path, key, value)
          if path == shown_path then
            post ({ type = 'uniform', key = key, value = value })
          end
        end,
        resend = function (grant)
          sent[grant] = nil
        end,
      }
      return inst
    end

    local dock = make_preview (false)
    previews[#previews + 1] = dock
    views.add ('right', {
      id = 'shader.preview',
      title = 'Preview',
      icon = 'monitor-play',
      order = 1,
      content = dock.root,
      on_show = dock.refresh,
    })

    local soon_pending = false
    local function soon ()
      if soon_pending then
        return
      end
      soon_pending = true
      app.timer.after (60, function ()
        soon_pending = false
        for _, p in ipairs (previews) do
          p.refresh ()
        end
      end)
    end

    app.on ('shader:active', soon)
    app.on ('shader:changed', soon)
    app.on ('shader:closed', soon)
    app.on ('shader:uniform', function (path, key, value)
      for _, p in ipairs (previews) do
        p.uniform (path, key, value)
      end
    end)
    -- A buffer without a tab runs from its file, so a change to any shader file counts.
    app.on ('fs:changed', function (path)
      local p = tostring (path)
      if p:sub (1, #docs.folder + 1) == docs.folder .. '/' then
        soon ()
      end
    end)
    app.on ('settings:changed', function (key)
      if key == 'shader.language' then
        soon ()
      end
    end)

    commands.register ({
      id = 'shader.toggle_play',
      category = 'Shader',
      title = 'Pause or Play the Preview',
      menu = 'View',
      icon = 'play',
      key = 'ctrl+space',
      run = function ()
        local on = not dock.playing ()
        for _, p in ipairs (previews) do
          p.set_playing (on)
        end
      end,
    })
    commands.register ({
      id = 'shader.show_preview',
      category = 'Shader',
      title = 'Show the Preview',
      menu = 'View',
      icon = 'monitor-play',
      run = function ()
        views.show ('shader.preview')
      end,
    })
    commands.register ({
      id = 'shader.large_preview',
      category = 'Shader',
      title = 'Open a Large Preview',
      menu = 'View',
      icon = 'maximize-2',
      when = function ()
        return tabs ~= nil
      end,
      run = function ()
        if not tabs then
          return
        end
        local existing = tabs.get ('shader:large-preview')
        if existing then
          existing.focus ()
          return
        end
        local big = make_preview (true)
        previews[#previews + 1] = big
        tabs.open ({
          id = 'shader:large-preview',
          title = 'Preview',
          icon = 'monitor-play',
          content = big.root,
          on_close = function ()
            for i, p in ipairs (previews) do
              if p == big then
                table.remove (previews, i)
                break
              end
            end
            return true
          end,
        })
        app.timer.after (30, big.refresh)
      end,
    })

    soon ()
  end,
}
