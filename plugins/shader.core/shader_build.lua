-- Builds a shader into files that stand on their own: the complete GLSL vertex and fragment
-- shaders, the WGSL module, a page that runs the shader in any browser, a JSON list of the
-- uniforms, and a README that says how to feed them.

local file = require ('shader_file') --[[@as Shader.FileModule]]

-- lang=html
local GLSL_PAGE = [[
<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>{{TITLE}}</title>
    <style>
      html, body { margin: 0; height: 100%; background: #000; }
      canvas { display: block; width: 100%; height: 100%; touch-action: none; }
      pre { position: fixed; inset: 0; margin: 0; padding: 16px; color: #f88; background: #000; white-space: pre-wrap; }
    </style>
  </head>
  <body>
    <canvas id="view"></canvas>
    <script>
      // {{TITLE}}: GLSL ES 3.00 on WebGL 2, built with the Proteus shader builder.
      const VERTEX = {{VERTEX}};
      const FRAGMENT = {{FRAGMENT}};
      const UNIFORMS = {{UNIFORMS}};

      const canvas = document.getElementById('view');
      const gl = canvas.getContext('webgl2');
      const fail = (text) => { document.body.innerHTML = ''; const pre = document.createElement('pre'); pre.textContent = text; document.body.appendChild(pre); throw new Error(text); };
      if (!gl) fail('This browser has no WebGL 2.');
      const compile = (type, source) => {
        const shader = gl.createShader(type);
        gl.shaderSource(shader, source);
        gl.compileShader(shader);
        if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) fail(gl.getShaderInfoLog(shader));
        return shader;
      };
      const program = gl.createProgram();
      gl.attachShader(program, compile(gl.VERTEX_SHADER, VERTEX));
      gl.attachShader(program, compile(gl.FRAGMENT_SHADER, FRAGMENT));
      gl.linkProgram(program);
      if (!gl.getProgramParameter(program, gl.LINK_STATUS)) fail(gl.getProgramInfoLog(program));
      const active = {};
      for (let i = 0; i < gl.getProgramParameter(program, gl.ACTIVE_UNIFORMS); i++) {
        const info = gl.getActiveUniform(program, i);
        active[info.name] = { loc: gl.getUniformLocation(program, info.name), type: info.type };
      }
      const set = (name, v) => {
        const u = active[name];
        if (!u) return;
        const n = (i) => v[i] ?? 0;
        if (u.type === gl.FLOAT) gl.uniform1f(u.loc, n(0));
        else if (u.type === gl.FLOAT_VEC2) gl.uniform2f(u.loc, n(0), n(1));
        else if (u.type === gl.FLOAT_VEC3) gl.uniform3f(u.loc, n(0), n(1), n(2));
        else if (u.type === gl.FLOAT_VEC4) gl.uniform4f(u.loc, n(0), n(1), n(2), n(3));
        else if (u.type === gl.INT || u.type === gl.BOOL) gl.uniform1i(u.loc, Math.round(n(0)));
        else if (u.type === gl.UNSIGNED_INT) gl.uniform1ui(u.loc, Math.max(0, Math.round(n(0))));
      };
      const mouse = { x: 0, y: 0, down: false, cx: 0, cy: 0 };
      const at = (e) => {
        const r = canvas.getBoundingClientRect();
        return [((e.clientX - r.left) / r.width) * canvas.width, ((r.bottom - e.clientY) / r.height) * canvas.height];
      };
      canvas.addEventListener('pointerdown', (e) => { [mouse.x, mouse.y] = at(e); mouse.cx = mouse.x; mouse.cy = mouse.y; mouse.down = true; });
      canvas.addEventListener('pointermove', (e) => { if (mouse.down) [mouse.x, mouse.y] = at(e); });
      addEventListener('pointerup', () => { mouse.down = false; });
      const vao = gl.createVertexArray();
      const start = performance.now();
      let last = start;
      let frame = 0;
      const draw = (now) => {
        const ratio = devicePixelRatio || 1;
        const w = Math.max(1, Math.floor(canvas.clientWidth * ratio));
        const h = Math.max(1, Math.floor(canvas.clientHeight * ratio));
        if (canvas.width !== w || canvas.height !== h) { canvas.width = w; canvas.height = h; }
        const time = (now - start) / 1000;
        gl.viewport(0, 0, w, h);
        gl.useProgram(program);
        set('u_resolution', [w, h]);
        set('u_time', [time]);
        set('u_frame', [frame]);
        set('u_mouse', [mouse.x, mouse.y, mouse.down ? 1 : 0, 0]);
        set('iResolution', [w, h, 1]);
        set('iTime', [time]);
        set('iTimeDelta', [(now - last) / 1000]);
        set('iFrame', [frame]);
        set('iMouse', [mouse.x, mouse.y, mouse.down ? mouse.cx : -mouse.cx, mouse.down ? mouse.cy : -mouse.cy]);
        for (const u of UNIFORMS) set(u.glsl, u.value);
        gl.bindVertexArray(vao);
        gl.drawArrays(gl.TRIANGLES, 0, 3);
        last = now;
        frame += 1;
        requestAnimationFrame(draw);
      };
      requestAnimationFrame(draw);
    </script>
  </body>
</html>
]]

-- lang=html
local WGSL_PAGE = [[
<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>{{TITLE}}</title>
    <style>
      html, body { margin: 0; height: 100%; background: #000; }
      canvas { display: block; width: 100%; height: 100%; touch-action: none; }
      pre { position: fixed; inset: 0; margin: 0; padding: 16px; color: #f88; background: #000; white-space: pre-wrap; }
    </style>
  </head>
  <body>
    <canvas id="view"></canvas>
    <script type="module">
      // {{TITLE}}: WGSL on WebGPU, built with the Proteus shader builder.
      const MODULE = {{MODULE}};
      const VERTEX_ENTRY = {{VERTEX_ENTRY}};
      const FRAGMENT_ENTRY = {{FRAGMENT_ENTRY}};
      // Where each field of the uniform struct sits in its buffer, in bytes.
      const LAYOUT = {{LAYOUT}};
      const UNIFORMS = {{UNIFORMS}};

      const canvas = document.getElementById('view');
      const fail = (text) => { document.body.innerHTML = ''; const pre = document.createElement('pre'); pre.textContent = text; document.body.appendChild(pre); throw new Error(text); };
      if (!navigator.gpu) fail('This browser has no WebGPU.');
      const adapter = await navigator.gpu.requestAdapter();
      if (!adapter) fail('No graphics adapter offers WebGPU here.');
      const device = await adapter.requestDevice();
      const context = canvas.getContext('webgpu');
      const format = navigator.gpu.getPreferredCanvasFormat();
      context.configure({ device, format, alphaMode: 'premultiplied' });
      const module = device.createShaderModule({ code: MODULE });
      const info = await module.getCompilationInfo();
      const errors = info.messages.filter((m) => m.type === 'error');
      if (errors.length) fail(errors.map((m) => `line ${m.lineNum}: ${m.message}`).join('\n'));
      const pipeline = await device.createRenderPipelineAsync({
        layout: 'auto',
        vertex: { module, entryPoint: VERTEX_ENTRY },
        fragment: { module, entryPoint: FRAGMENT_ENTRY, targets: [{ format }] },
        primitive: { topology: 'triangle-list' },
      });
      const size = Math.max(16, Math.ceil(LAYOUT.size / 16) * 16);
      const data = new ArrayBuffer(size);
      const f32 = new Float32Array(data);
      const i32 = new Int32Array(data);
      const u32 = new Uint32Array(data);
      let buffer = null;
      let bindGroup = null;
      if (LAYOUT.fields.length) {
        buffer = device.createBuffer({ size, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST });
        try {
          bindGroup = device.createBindGroup({ layout: pipeline.getBindGroupLayout(0), entries: [{ binding: 0, resource: { buffer } }] });
        } catch { bindGroup = null; }
      }
      const values = Object.fromEntries(UNIFORMS.map((u) => [u.key, u.value]));
      const mouse = { x: 0, y: 0, down: false };
      const at = (e) => {
        const r = canvas.getBoundingClientRect();
        return [((e.clientX - r.left) / r.width) * canvas.width, ((r.bottom - e.clientY) / r.height) * canvas.height];
      };
      canvas.addEventListener('pointerdown', (e) => { [mouse.x, mouse.y] = at(e); mouse.down = true; });
      canvas.addEventListener('pointermove', (e) => { if (mouse.down) [mouse.x, mouse.y] = at(e); });
      addEventListener('pointerup', () => { mouse.down = false; });
      const start = performance.now();
      let frame = 0;
      const draw = (now) => {
        const ratio = devicePixelRatio || 1;
        const w = Math.max(1, Math.floor(canvas.clientWidth * ratio));
        const h = Math.max(1, Math.floor(canvas.clientHeight * ratio));
        if (canvas.width !== w || canvas.height !== h) { canvas.width = w; canvas.height = h; }
        const builtins = { resolution: [w, h], time: [(now - start) / 1000], frame: [frame], mouse: [mouse.x, mouse.y, mouse.down ? 1 : 0, 0] };
        if (buffer && bindGroup) {
          for (const f of LAYOUT.fields) {
            const v = (f.builtin ? builtins[f.builtin] : values[f.name]) || [];
            const n = { vec2: 2, vec3: 3, vec4: 4 }[f.type] || 1;
            for (let i = 0; i < n; i++) {
              const at = f.offset / 4 + i;
              if (f.type === 'int') i32[at] = Math.round(v[i] ?? 0);
              else if (f.type === 'uint') u32[at] = Math.max(0, Math.round(v[i] ?? 0));
              else f32[at] = v[i] ?? 0;
            }
          }
          device.queue.writeBuffer(buffer, 0, data);
        }
        const encoder = device.createCommandEncoder();
        const pass = encoder.beginRenderPass({
          colorAttachments: [{ view: context.getCurrentTexture().createView(), clearValue: { r: 0, g: 0, b: 0, a: 1 }, loadOp: 'clear', storeOp: 'store' }],
        });
        pass.setPipeline(pipeline);
        if (bindGroup) pass.setBindGroup(0, bindGroup);
        pass.draw(3);
        pass.end();
        device.queue.submit([encoder.finish()]);
        frame += 1;
        requestAnimationFrame(draw);
      };
      requestAnimationFrame(draw);
    </script>
  </body>
</html>
]]

local M = {}

---A value as JavaScript, safe inside a script element.
---@param value any
---@return string
local function js (value)
  return (file.encode (value):gsub ('</', '<\\/'))
end

---@param template string
---@param values table<string, string>
---@return string
local function fill (template, values)
  return (
    template:gsub ('{{([%w_]+)}}', function (key)
      return values[key] or ''
    end)
  )
end

---A file name from a shader's name.
---@param name string
---@return string
function M.stem (name)
  local s = tostring (name or ''):lower ():gsub ('[^%w%-_]+', '-')
  s = s:gsub ('^%-+', ''):gsub ('%-+$', '')
  return s ~= '' and s or 'shader'
end

---@param list Shader.Uniform[]
---@return table[]
local function uniform_rows (list)
  local out = file.array ({}) ---@type table[]
  for _, u in ipairs (list) do
    out[#out + 1] = {
      key = u.key,
      glsl = u.glsl,
      offset = u.offset,
      type = u.type,
      value = u.value,
      min = u.min,
      max = u.max,
      color = u.color or nil,
    }
  end
  return out
end

---The files a build writes, by name.
---@param input Shader.BuildInput
---@return table<string, string>
function M.files (input)
  local stem = M.stem (input.name)
  local title = tostring (input.name or stem):gsub ('[<>&]', '')
  local out = {} ---@type table<string, string>
  ---@type string[]
  local readme = {
    '# ' .. title,
    '',
    'Built with the Proteus shader builder. Every file here stands on its own.',
    '',
    '| File | What it holds |',
    '|------|---------------|',
  }
  local glsl = input.glsl ---@type Shader.Program?
  local wgsl = input.wgsl ---@type Shader.Program?
  if glsl then
    out[stem .. '.frag'] = glsl.source
    out[stem .. '.vert'] = glsl.vertex or ''
    out['index.html'] = fill (GLSL_PAGE, {
      TITLE = title,
      VERTEX = js (glsl.vertex or ''),
      FRAGMENT = js (glsl.source),
      UNIFORMS = js (uniform_rows (glsl.uniforms)),
    })
    readme[#readme + 1] = '| `'
      .. stem
      .. '.frag` | The GLSL ES 3.00 fragment shader, for WebGL 2 and OpenGL ES 3 |'
    readme[#readme + 1] = '| `'
      .. stem
      .. '.vert` | Its vertex shader: one triangle over the whole picture, from `gl_VertexID`. Draw 3 vertices with no attributes |'
  end
  if wgsl then
    out[stem .. '.wgsl'] = wgsl.source
    local page = fill (WGSL_PAGE, {
      TITLE = title,
      MODULE = js (wgsl.source),
      VERTEX_ENTRY = js (wgsl.vertex_entry or 'vs_main'),
      FRAGMENT_ENTRY = js (wgsl.fragment_entry or 'fs_main'),
      LAYOUT = js ({
        size = wgsl.layout and wgsl.layout.size or 16,
        fields = file.array (wgsl.layout and wgsl.layout.fields or {}),
      }),
      UNIFORMS = js (uniform_rows (wgsl.uniforms)),
    })
    out[glsl and 'webgpu.html' or 'index.html'] = page
    readme[#readme + 1] = '| `'
      .. stem
      .. '.wgsl` | The WGSL module for WebGPU, with the vertex entry point `'
      .. (wgsl.vertex_entry or 'vs_main')
      .. '` and the fragment entry point `'
      .. (wgsl.fragment_entry or 'fs_main')
      .. '`. Draw 3 vertices |'
  end
  if glsl then
    readme[#readme + 1] =
      '| `index.html` | Runs the GLSL shader in a browser with WebGL 2 |'
    if wgsl then
      readme[#readme + 1] =
        '| `webgpu.html` | Runs the WGSL shader in a browser with WebGPU |'
    end
  elseif wgsl then
    readme[#readme + 1] =
      '| `index.html` | Runs the WGSL shader in a browser with WebGPU |'
  end
  readme[#readme + 1] = '| `uniforms.json` | Each uniform: '
    .. (glsl and 'its GLSL name, ' or '')
    .. (wgsl and 'its byte offset in the WGSL buffer, ' or '')
    .. 'its type and its value |'
  readme[#readme + 1] = ''
  readme[#readme + 1] = '## Uniforms'
  readme[#readme + 1] = ''
  if glsl and glsl.shadertoy then
    readme[#readme + 1] =
      'Set these every frame: `iResolution` (pixels, and 1), `iTime` (seconds), `iTimeDelta`, `iFrame` and `iMouse`, as Shadertoy does.'
  elseif glsl then
    readme[#readme + 1] =
      'Set these every frame: `u_resolution` (pixels), `u_time` (seconds), `u_frame`, and `u_mouse` (x and y in pixels from the bottom left, z is 1 while the button is down).'
  end
  if wgsl then
    readme[#readme + 1] = (
      glsl and 'WGSL reads the same values from' or 'Set these every frame in'
    )
      .. ' the `resolution`, `time`, `frame` and `mouse` fields of its `Uniforms` struct, bound at group 0, binding 0. `uniforms.json` gives the offset of each field in the buffer.'
  end
  local list = (glsl or wgsl)
      and (glsl or wgsl --[[@as Shader.Program]]).uniforms
    or {}
  if #list > 0 then
    readme[#readme + 1] = ''
    readme[#readme + 1] = '| Name | Type | Value | Range |'
    readme[#readme + 1] = '|------|------|-------|-------|'
    for _, u in ipairs (list) do
      local values = {} ---@type string[]
      for i, v in ipairs (u.value) do
        values[i] = string.format ('%g', v)
      end
      readme[#readme + 1] = '| `'
        .. (u.glsl or u.key)
        .. '` | '
        .. u.type
        .. (u.color and ' (colour)' or '')
        .. ' | '
        .. table.concat (values, ', ')
        .. ' | '
        .. (u.color and '0 to 1' or string.format ('%g to %g', u.min, u.max))
        .. ' |'
    end
  end
  readme[#readme + 1] = ''
  out['README.md'] = table.concat (readme, '\n')
  out['uniforms.json'] = file.encode ({
    name = title,
    glsl = glsl and uniform_rows (glsl.uniforms) or nil,
    wgsl = wgsl and {
      buffer_size = wgsl.layout and wgsl.layout.size or 0,
      fields = file.array (wgsl.layout and wgsl.layout.fields or {}),
      uniforms = uniform_rows (wgsl.uniforms),
    } or nil,
  }) .. '\n'
  return out
end

return M
