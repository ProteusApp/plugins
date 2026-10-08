-- shader.code: shaders as code. A .frag, .glsl, .vert or .wgsl file opens in a code editor
-- whose problems come from the real compiler, line by line. The Code panel shows what a graph
-- turns into, in GLSL and in WGSL, and a click on a line picks the node that wrote it.

local FLUSH_MS = 180

-- GLSL ES 3.00, the language of WebGL 2 shaders, for the code editor.
---@type Proteus.LanguageSpec
local GLSL = {
  name = 'glsl',
  extensions = { 'glsl', 'frag', 'vert' },
  directive = '#',
  keywords = 'attribute const uniform varying layout centroid flat smooth break continue do for while switch case '
    .. 'default if else in out inout true false invariant discard return struct precision highp mediump lowp',
  types = 'float int uint bool void vec2 vec3 vec4 ivec2 ivec3 ivec4 uvec2 uvec3 uvec4 bvec2 bvec3 bvec4 mat2 mat3 mat4 '
    .. 'mat2x2 mat2x3 mat2x4 mat3x2 mat3x3 mat3x4 mat4x2 mat4x3 mat4x4 sampler2D sampler3D samplerCube '
    .. 'sampler2DShadow samplerCubeShadow sampler2DArray isampler2D usampler2D',
  block_keywords = 'for while do if else struct switch',
  builtins = 'radians degrees sin cos tan asin acos atan sinh cosh tanh pow exp log exp2 log2 sqrt inversesqrt abs '
    .. 'sign floor trunc round roundEven ceil fract mod modf min max clamp mix step smoothstep isnan isinf '
    .. 'length distance dot cross normalize faceforward reflect refract matrixCompMult outerProduct transpose '
    .. 'determinant inverse lessThan lessThanEqual greaterThan greaterThanEqual equal notEqual any all not '
    .. 'texture textureProj textureLod textureOffset texelFetch textureGrad textureSize dFdx dFdy fwidth',
  atoms = 'gl_FragCoord gl_FrontFacing gl_PointCoord gl_FragDepth gl_Position gl_PointSize gl_VertexID gl_InstanceID',
}

-- WGSL, the language of WebGPU shaders. `@vertex` and other attributes read as meta.
---@type Proteus.LanguageSpec
local WGSL = {
  name = 'wgsl',
  extensions = { 'wgsl' },
  attribute = '@',
  keywords = 'alias break case const const_assert continue continuing default diagnostic discard else enable fn for if '
    .. 'let loop override requires return struct switch var while true false',
  types = 'bool f16 f32 i32 u32 vec2 vec3 vec4 vec2f vec3f vec4f vec2i vec3i vec4i vec2u vec3u vec4u vec2h vec3h vec4h '
    .. 'mat2x2 mat2x3 mat2x4 mat3x2 mat3x3 mat3x4 mat4x2 mat4x3 mat4x4 mat2x2f mat3x3f mat4x4f array atomic ptr '
    .. 'sampler sampler_comparison texture_2d texture_3d texture_cube texture_storage_2d texture_depth_2d '
    .. 'uniform storage function private workgroup read write read_write',
  block_keywords = 'for while loop if else struct switch fn',
  builtins = 'abs acos asin atan atan2 ceil clamp cos cosh cross degrees determinant distance dot exp exp2 floor fma '
    .. 'fract inverseSqrt length log log2 max min mix modf normalize pow radians reflect refract round saturate '
    .. 'select sign sin sinh smoothstep sqrt step tan tanh transpose trunc dpdx dpdy fwidth textureSample '
    .. 'textureSampleLevel textureLoad textureDimensions arrayLength bitcast',
}

local GLSL_WORDS = {
  'u_resolution',
  'u_time',
  'u_frame',
  'u_mouse',
  'fragColor',
  'gl_FragCoord',
  'v_uv',
  'iResolution',
  'iTime',
  'iTimeDelta',
  'iFrame',
  'iMouse',
  'mainImage',
  'smoothstep',
  'normalize',
  'reflect',
  'inversesqrt',
  'texture',
  'precision',
  'highp',
  'uniform',
}

local WGSL_WORDS = {
  'Uniforms',
  'resolution',
  'mouse',
  'vec2f',
  'vec3f',
  'vec4f',
  'smoothstep',
  'normalize',
  'inverseSqrt',
  'atan2',
  '@fragment',
  '@vertex',
  '@builtin(position)',
  '@location(0)',
  '@group(0) @binding(0)',
  'var<uniform>',
}

-- The app's help for Godot shaders, in versions of Proteus that ship it.
local has_godot, godot_lib = pcall (require, 'gdshader')

---Completion and hover help for a Godot shader, from the app's `gdshader` library, or nil
---when this version of Proteus has none.
---@param text fun(): string The shader's text now.
---@return Proteus.CodeProvider?
local function godot_provider (text)
  if not has_godot or type (godot_lib) ~= 'table' then
    return nil
  end
  local lib = godot_lib --[[@as table]]
  ---@type Proteus.CodeProvider
  return {
    complete = lib.complete and function (pos, respond)
      respond (lib.complete (text (), pos.line, pos.character))
    end or nil,
    hover = lib.hover and function (pos, respond)
      respond (lib.hover (text (), pos.line, pos.character))
    end or nil,
    signature = lib.signature and function (pos, respond)
      respond (lib.signature (text (), pos.line, pos.character))
    end or nil,
  }
end

-- lang=css
local CSS = [[
.sc-root { display: flex; flex-direction: column; height: 100%; min-height: 0; }
.sc-bar {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 4px 8px;
  border-bottom: 0.5px solid var(--border);
  background: var(--bg-alt);
  font-size: 12px;
  min-height: 30px;
  box-sizing: border-box;
}
.sc-bar .sc-note { color: var(--fg-muted); }
.sc-bar .sc-grow { flex: 1; }
.sc-editor { flex: 1; min-height: 0; }
.sc-tabs { display: flex; border: 0.5px solid var(--border); border-radius: 6px; overflow: hidden; }
.sc-tabs button {
  border: none;
  background: transparent;
  color: var(--fg-muted);
  font: inherit;
  font-size: 12px;
  padding: 3px 10px;
  cursor: pointer;
}
.sc-tabs button.on { background: var(--accent); color: var(--accent-fg, #fff); }
]]

---@type Proteus.Plugin
return {
  name = 'Shader code',
  description = 'Edits GLSL, WGSL and Godot shaders with problems from the real compiler, and shows the code a graph turns into.',
  version = '1.1.0',
  requires = { proteus = '>=0.2.0', features = { 'permissions', 'languages' } },
  permissions = {},
  depends = { 'lib.ui', 'shader.core', 'shader.docs', 'core.commands' },
  optional = { 'ui.views', 'shader.canvas', 'ui.notify', 'ui.palette' },
  activate = function (app)
    local ui = app.use ('ui')
    ui.language (GLSL)
    ui.language (WGSL)
    local docs = app.use ('shader.docs') --[[@as Shader.Docs]]
    local core = app.use ('shader') --[[@as Shader.Core]]
    local commands = app.use ('commands')
    local views = app.try_use ('views')
    local canvas = app.try_use ('shader.canvas') --[[@as Shader.CanvasService?]]
    local notify = app.try_use ('notify')
    ui.css (CSS)

    local editors = {} ---@type table<string, Proteus.El>
    local problems = {} ---@type table<string, Shader.CompileError[]>

    ---@param text string
    local function say (text)
      if notify then
        notify.info (text)
      end
    end

    ---Shows problems in an editor, lines counted from 1 in the user's text.
    ---@param path string
    local function show_problems (path)
      local editor = editors[path]
      if not editor then
        return
      end
      local list = {} ---@type Proteus.Diagnostic[]
      for _, p in ipairs (problems[path] or {}) do
        if p.line then
          list[#list + 1] = {
            line = math.max (0, p.line - 1),
            character = math.max (0, (p.column or 1) - 1),
            end_line = math.max (0, p.line - 1),
            end_character = 999,
            severity = p.severity == 'warning' and 'warning' or 'error',
            message = p.message,
            source = p.stage == 'vertex' and 'vertex shader' or 'compiler',
          }
        end
      end
      editor:widget ('set_diagnostics', list)
    end

    ---@param doc Shader.OpenDoc
    ---@return Proteus.El
    local function make_editor (doc)
      local path = doc.path
      local pending = false
      local editor ---@type Proteus.El
      local function flush ()
        pending = false
        if editor and editor:alive () then
          docs.set_text (path, editor:widget ('get_text'))
        end
      end
      editor = ui.widget ('code', {
        text = doc.text,
        language = doc.language,
        completions = doc.language == 'wgsl' and WGSL_WORDS
          or doc.language ~= 'gdshader' and GLSL_WORDS
          or nil,
        provider = doc.language == 'gdshader'
            and godot_provider (function ()
              return editor and editor:alive () and editor:widget ('get_text')
                or doc.text
            end)
          or nil,
        on_change = function ()
          if not pending then
            pending = true
            app.timer.after (FLUSH_MS, flush)
          end
        end,
      })
      editor:class ('sc-editor')
      editors[path] = editor

      local note = ui.span ({ class = 'sc-note' })
      local function describe ()
        local program = docs.program (path)
        local parts = {} ---@type string[]
        parts[#parts + 1] = doc.language == 'wgsl' and 'WGSL · WebGPU'
          or doc.language == 'gdshader' and 'Godot 4 shader · runs here as GLSL'
          or 'GLSL ES 3.00 · WebGL 2'
        if doc.stage == 'vertex' then
          parts[#parts + 1] = 'vertex shader'
        elseif program and program.shadertoy then
          parts[#parts + 1] = 'Shadertoy style'
        elseif program and program.offset > 0 then
          parts[#parts + 1] =
            'the version, uniforms and output it leaves out are added'
        end
        if program and #program.uniforms > 0 then
          parts[#parts + 1] = #program.uniforms
            .. (#program.uniforms == 1 and ' control' or ' controls')
        end
        note:text (table.concat (parts, ' · '))
      end
      describe ()
      app.on ('shader:changed', function (changed_path)
        if changed_path == path then
          describe ()
        end
      end)

      local bar = ui.div ({
        class = 'sc-bar',
        ui.icon (
          doc.language == 'wgsl' and 'file-code-2'
            or doc.language == 'gdshader' and 'gamepad-2'
            or 'file-code',
          14
        ),
        note,
        ui.span ({ class = 'sc-grow' }),
        ui.button ({
          'Build',
          icon = 'package',
          variant = 'ghost',
          title = 'Write the complete shader files to shaders/build',
          onclick = function ()
            commands.run ('shader.build')
          end,
        }),
      })
      return ui.div ({ class = 'sc-root', bar, editor })
    end

    docs.register_opener ('code', make_editor)

    app.on ('shader:problems', function (path, list)
      problems[path] = list
      show_problems (path)
    end)
    app.on ('shader:reloaded', function (path)
      local d = docs.get (path)
      local editor = editors[path]
      if d and editor and d.kind == 'code' then
        editor:widget ('replace_text', d.text)
      end
    end)
    app.on ('shader:closed', function (path)
      editors[path] = nil
      problems[path] = nil
    end)

    -- The Code panel: what a graph turns into ----------------------------------------------

    local which = app.store.get ('code_view', 'glsl') ---@type string
    local shown_path = nil ---@type string?
    local shown_lines = {} ---@type table<integer, string>
    local quiet = false
    local out_note = ui.span ({ class = 'sc-note' })
    local tab_buttons = {} ---@type table<string, Proteus.El>
    local output = ui.widget ('code', {
      text = '',
      language = 'glsl',
      readonly = true,
      on_cursor = function (line)
        if quiet or not shown_path then
          return
        end
        local node = shown_lines[line]
        local d = docs.get (shown_path)
        if node and canvas and d then
          local current = d.selection
          if #current ~= 1 or current[1] ~= node then
            canvas.select (shown_path, { node })
          end
        end
      end,
    })
    output:class ('sc-editor')

    ---The text the Code panel shows for a graph, and which node wrote each line.
    ---@param path string
    ---@return string text, Shader.Lang lang, table<integer, string> lines
    local function generated (path)
      local result = docs.compiled (path) --[[@as Shader.CompileResult]]
      if which == 'vertex' then
        return result.glsl.vertex or '', 'glsl', {}
      elseif which == 'godot' then
        if not result.ir or #result.errors > 0 then
          return '// Fix the problems in the graph to see its Godot shader.\n',
            'gdshader',
            {}
        end
        return core.export.godot (result.ir), 'gdshader', {}
      elseif which == 'wgsl' then
        return result.wgsl.source, 'wgsl', result.wgsl.lines or {}
      end
      return result.glsl.source, 'glsl', result.glsl.lines or {}
    end

    local function highlight ()
      local d = shown_path and docs.get (shown_path)
      local lines = {} ---@type integer[]
      if d then
        local picked = {} ---@type table<string, boolean>
        for _, id in ipairs (d.selection) do
          picked[id] = true
        end
        for line, node in pairs (shown_lines) do
          if picked[node] then
            lines[#lines + 1] = line
          end
        end
        table.sort (lines)
      end
      output:widget ('set_highlight', lines)
      if lines[1] then
        output:widget ('reveal', lines[1])
      end
    end

    local function refresh ()
      local d = docs.active ()
      for key, button in pairs (tab_buttons) do
        button:class ('on', key == which)
      end
      if not d or d.kind ~= 'graph' then
        shown_path = nil
        shown_lines = {}
        out_note:text (
          d
              and 'A code shader is its own code. The Code panel shows what a graph turns into.'
            or 'Open a graph to see the code it turns into.'
        )
        quiet = true
        output:widget ('set_text', '')
        quiet = false
        return
      end
      local text, lang, lines = generated (d.path)
      shown_path = d.path
      shown_lines = lines
      local result = docs.compiled (d.path) --[[@as Shader.CompileResult]]
      local count = #result.errors
      out_note:text (
        count == 0 and 'Click a line to pick the node that wrote it.'
          or (
            count
            .. (count == 1 and ' problem' or ' problems')
            .. ' in the graph'
          )
      )
      quiet = true
      output:widget ('set_language', lang)
      if output:widget ('get_text') ~= text then
        output:widget ('replace_text', text)
      end
      quiet = false
      highlight ()
    end

    local refresh_pending = false
    local function soon ()
      if not refresh_pending then
        refresh_pending = true
        app.timer.after (120, function ()
          refresh_pending = false
          refresh ()
        end)
      end
    end

    ---@param key string
    ---@param label string
    ---@return Proteus.El
    local function tab (key, label)
      local b = ui.button ({
        label,
        onclick = function ()
          which = key
          app.store.set ('code_view', key)
          refresh ()
        end,
      })
      tab_buttons[key] = b
      return b
    end

    local panel = ui.div ({
      class = 'sc-root',
      ui.div ({
        class = 'sc-bar',
        ui.div ({
          class = 'sc-tabs',
          tab ('glsl', 'GLSL fragment'),
          tab ('vertex', 'GLSL vertex'),
          tab ('wgsl', 'WGSL'),
          tab ('godot', 'Godot'),
        }),
        out_note,
        ui.span ({ class = 'sc-grow' }),
        ui.button ({
          'Copy',
          icon = 'copy',
          variant = 'ghost',
          onclick = function ()
            app.system.clipboard (output:widget ('get_text'))
            say ('Copied the code.')
          end,
        }),
        ui.button ({
          'Open as Code',
          icon = 'file-code',
          variant = 'ghost',
          title = 'Start a code shader from this code, to take it further by hand',
          onclick = function ()
            commands.run ('shader.to_code')
          end,
        }),
      }),
      output,
    })

    if views then
      views.add ('bottom', {
        id = 'shader.code',
        title = 'Code',
        icon = 'code',
        order = 1,
        content = panel,
        on_show = refresh,
      })
    end

    app.on ('shader:active', soon)
    app.on ('shader:changed', function (path)
      if path == shown_path or not shown_path then
        soon ()
      end
    end)
    app.on ('shader:selected', function (path)
      if path == shown_path then
        highlight ()
      end
    end)

    commands.register ({
      id = 'shader.show_code',
      category = 'Shader',
      title = 'Show the Generated Code',
      -- The canvas's Show Its Code menu entry runs it too.
      shared = true,
      menu = 'View',
      icon = 'code',
      key = 'ctrl+shift+c',
      run = function ()
        if views then
          views.show ('shader.code')
        end
        refresh ()
      end,
    })
    commands.register ({
      id = 'shader.to_code',
      category = 'Shader',
      title = 'Open This Graph as a Code Shader',
      menu = 'Graph',
      icon = 'file-code',
      when = function ()
        local d = docs.active ()
        return d ~= nil and d.kind == 'graph'
      end,
      run = function ()
        local d = docs.active ()
        if not d or d.kind ~= 'graph' then
          return
        end
        local result = docs.compiled (d.path) --[[@as Shader.CompileResult]]
        local stem = d.title
        if which == 'wgsl' then
          docs.new_code ('wgsl', stem, result.wgsl.source)
        elseif which == 'godot' and result.ir and #result.errors == 0 then
          docs.new_code ('gdshader', stem, core.export.godot (result.ir))
        else
          docs.new_code ('glsl', stem, result.glsl.source)
        end
      end,
    })
  end,
}
