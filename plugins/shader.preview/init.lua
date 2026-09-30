-- shader.preview: runs the shader in front, live. GLSL runs on WebGL 2 and WGSL on WebGPU,
-- in a web view: page/preview.js draws, and this plugin sends it the program as messages.
-- The panel shows the picture, its problems by line or by node, and a control for every
-- uniform: a Parameter node in a graph, or a uniform with notes in a code shader. Moving a
-- control changes the picture at once, without compiling again.

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
]]

local SCALES = { 0.5, 1, 2 }

---@param v number
---@return string
local function fmt (v)
  if v == math.floor (v) and math.abs (v) < 1e9 then
    return string.format ('%d', v)
  end
  return (string.format ('%.3f', v):gsub ('0+$', ''):gsub ('%.$', ''))
end

---@param rgb number[]
---@return string
local function to_hex (rgb)
  local parts = {} ---@type string[]
  for i = 1, 3 do
    local v = math.max (0, math.min (1, tonumber (rgb[i]) or 0))
    parts[i] = string.format ('%02x', math.floor (v * 255 + 0.5))
  end
  return '#' .. table.concat (parts)
end

---@param hex string
---@return number[]?
local function from_hex (hex)
  local r, g, b = tostring (hex):match ('^#(%x%x)(%x%x)(%x%x)$')
  if not r then
    return nil
  end
  local function part (h)
    return math.floor (tonumber (h, 16) / 255 * 1000 + 0.5) / 1000
  end
  return { part (r), part (g), part (b) }
end

local DIMS =
  { float = 1, int = 1, uint = 1, bool = 1, vec2 = 2, vec3 = 3, vec4 = 4 }

---@type Proteus.Plugin
return {
  name = 'Shader preview',
  description = 'Runs the shader in front live, on WebGL 2 or WebGPU, with its problems and a control for every uniform.',
  version = '1.0.0',
  requires = { proteus = '>=0.2.0', features = { 'permissions', 'webview' } },
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
    local ui = app.use ('ui')
    local docs = app.use ('shader.docs') --[[@as Shader.Docs]]
    local views = app.use ('views')
    local commands = app.use ('commands')
    local tabs = app.try_use ('tabs')
    local canvas = app.try_use ('shader.canvas') --[[@as Shader.CanvasService?]]
    local status = app.try_use ('status')
    ui.css (CSS)

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

    ---Builds one preview: the picture and its panels. The dock and the large tab each have one.
    ---@param large boolean
    ---@return ShaderPreview.Instance
    local function make_preview (large)
      local shown_path = nil ---@type string?
      local last_key = nil ---@type string?
      local program = nil ---@type Shader.Program?
      local lua_errors = {} ---@type Shader.CompileError[]
      local gpu_errors = {} ---@type Shader.GpuError[]
      local playing = true
      local uniform_shape = ''
      local scale = tonumber (app.store.get ('scale', 1)) or 1
      local lang_buttons = {} ---@type table<string, Proteus.El>
      local scale_buttons = {} ---@type table<number, Proteus.El>
      local problems_el = ui.div ({ class = 'sp-section' })
      local uniforms_el = ui.div ({ class = 'sp-section' })
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
        local p = program
        for _, e in ipairs (gpu_errors) do
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
          }
        end
        return out
      end

      local function draw_problems ()
        local list = mapped ()
        if shown_path then
          local code_list = {} ---@type Shader.CompileError[]
          for _, e in ipairs (list) do
            if e.line then
              code_list[#code_list + 1] = e
            end
          end
          if not large then
            app.emit ('shader:problems', shown_path, code_list)
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
          children[#children + 1] = ui.div ({
            class = {
              'sp-problem',
              e.severity == 'warning' and 'warning' or 'error',
            },
            ui.span ({ class = 'where', where }),
            ui.span ({ class = 'what', e.message }),
            onclick = function ()
              if e.node and canvas and shown_path then
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

      ---What the page needs of a program, and nothing else.
      ---@param p Shader.Program
      ---@return table
      local function page_program (p)
        local uniforms = {} ---@type table[]
        for i, u in ipairs (p.uniforms) do
          uniforms[i] =
            { key = u.key, glsl = u.glsl, type = u.type, value = u.value }
        end
        return {
          language = p.language,
          source = p.source,
          vertex = p.vertex,
          vertex_entry = p.vertex_entry,
          fragment_entry = p.fragment_entry,
          uniforms = uniforms,
          layout = p.layout,
        }
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
        local shape = {} ---@type string[]
        -- The values count too, so an undo moves the controls back. A control's own moves
        -- change no document, so they never draw the controls again mid-drag.
        for _, u in ipairs (list) do
          local values = {} ---@type string[]
          for i, v in ipairs (u.value) do
            values[i] = tostring (v)
          end
          shape[#shape + 1] = table.concat (values, ' ')
          shape[#shape + 1] = u.key
            .. ':'
            .. u.type
            .. ':'
            .. tostring (u.color)
            .. ':'
            .. u.min
            .. ':'
            .. u.max
        end
        local key = (shown_path or '') .. '|' .. table.concat (shape, ',')
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
          program, lua_errors, gpu_errors = nil, {}, {}
          last_key = nil
          draw_problems ()
          draw_uniforms ({})
          return
        end
        local p, errors = docs.program (d.path)
        lua_errors = errors or {}
        program = p
        if not p then
          gpu_errors = {}
          draw_problems ()
          draw_uniforms ({})
          return
        end
        local key = table.concat ({
          d.path,
          p.language,
          p.source,
          p.vertex or '',
          p.vertex_entry or '',
          p.fragment_entry or '',
        }, '\0')
        if key ~= last_key then
          last_key = key
          post ({ type = 'run', program = page_program (p) })
        else
          for _, u in ipairs (p.uniforms) do
            post ({ type = 'uniform', key = u.key, value = u.value })
          end
          draw_problems ()
        end
        draw_uniforms (p.uniforms)
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
        ui.div ({ class = 'sp-scroll', problems_el, uniforms_el }),
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
        uniform = function (path, key, value)
          if path == shown_path then
            post ({ type = 'uniform', key = key, value = value })
          end
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
