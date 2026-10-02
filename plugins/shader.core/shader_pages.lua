-- The pages a build writes: one runs GLSL on WebGL 2, the other WGSL on WebGPU. Each draws
-- the shader's buffers in order into pictures of their own, then its image, every frame, as
-- the Preview panel does. A channel reads noise or a checker the page makes, an image beside
-- the page by its file name, or a buffer. shader_build.lua fills in the {{NAMES}}.

local M = {}

-- The noise and checker textures, the same as the preview's, so a build looks the same.
local TEXTURES = [[
      const TEXTURE_SIZE = 256;
      const builtinPixels = (kind) => {
        const data = new Uint8Array(TEXTURE_SIZE * TEXTURE_SIZE * 4);
        if (kind === 'noise') {
          let seed = 0x9e3779b9;
          for (let i = 0; i < data.length; i++) {
            seed = (seed + 0x6d2b79f5) | 0;
            let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
            t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
            data[i] = ((t ^ (t >>> 14)) >>> 0) & 255;
          }
          return data;
        }
        const square = TEXTURE_SIZE / 8;
        for (let y = 0; y < TEXTURE_SIZE; y++) {
          for (let x = 0; x < TEXTURE_SIZE; x++) {
            const v = (Math.floor(x / square) + Math.floor(y / square)) % 2 === 0 ? 230 : 90;
            data.set([v, v, v, 255], (y * TEXTURE_SIZE + x) * 4);
          }
        }
        return data;
      };
      const filterOf = (source) => (source?.filter === 'nearest' ? 'nearest' : 'linear');
      const wrapOf = (source) => (source?.wrap ? source.wrap : source?.kind === 'buffer' ? 'clamp' : 'repeat');
      const mouse = { x: 0, y: 0, down: false, cx: 0, cy: 0 };
      const at = (e) => {
        const r = canvas.getBoundingClientRect();
        return [((e.clientX - r.left) / r.width) * canvas.width, ((r.bottom - e.clientY) / r.height) * canvas.height];
      };
      canvas.addEventListener('pointerdown', (e) => { [mouse.x, mouse.y] = at(e); mouse.cx = mouse.x; mouse.cy = mouse.y; mouse.down = true; });
      canvas.addEventListener('pointermove', (e) => { if (mouse.down) [mouse.x, mouse.y] = at(e); });
      addEventListener('pointerup', () => { mouse.down = false; });
      const date = () => {
        const d = new Date();
        return [d.getFullYear(), d.getMonth(), d.getDate(), d.getHours() * 3600 + d.getMinutes() * 60 + d.getSeconds() + d.getMilliseconds() / 1000];
      };
      const fitCanvas = () => {
        const ratio = devicePixelRatio || 1;
        const w = Math.max(1, Math.floor(canvas.clientWidth * ratio));
        const h = Math.max(1, Math.floor(canvas.clientHeight * ratio));
        if (canvas.width !== w || canvas.height !== h) { canvas.width = w; canvas.height = h; }
        return [w, h];
      };]]

-- lang=html
M.GLSL = [[
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
      // {{TITLE}}: GLSL ES 3.00 on WebGL 2, built with the Proteus shader builder. Each frame
      // the buffers draw in order into pictures of their own, then the image draws here.
      const PASSES = {{PASSES}};

      const canvas = document.getElementById('view');
      const gl = canvas.getContext('webgl2');
      const fail = (text) => { document.body.innerHTML = ''; const pre = document.createElement('pre'); pre.textContent = text; document.body.appendChild(pre); throw new Error(text); };
      if (!gl) fail('This browser has no WebGL 2.');
{{TEXTURES}}
      const compile = (type, source) => {
        const shader = gl.createShader(type);
        gl.shaderSource(shader, source);
        gl.compileShader(shader);
        if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) fail(gl.getShaderInfoLog(shader));
        return shader;
      };
      for (const pass of PASSES) {
        const program = gl.createProgram();
        gl.attachShader(program, compile(gl.VERTEX_SHADER, pass.vertex));
        gl.attachShader(program, compile(gl.FRAGMENT_SHADER, pass.fragment));
        gl.linkProgram(program);
        if (!gl.getProgramParameter(program, gl.LINK_STATUS)) fail(gl.getProgramInfoLog(program));
        pass.program = program;
        pass.active = {};
        for (let i = 0; i < gl.getProgramParameter(program, gl.ACTIVE_UNIFORMS); i++) {
          const info = gl.getActiveUniform(program, i);
          pass.active[info.name.replace(/\[0\]$/, '')] = { loc: gl.getUniformLocation(program, info.name), type: info.type, size: info.size };
        }
      }
      const set = (u, v) => {
        const n = (i) => v[i] ?? 0;
        if (u.size > 1) {
          const data = new Float32Array(v.length ? v : [0]);
          if (u.type === gl.FLOAT_VEC3) gl.uniform3fv(u.loc, data);
          return;
        }
        if (u.type === gl.FLOAT) gl.uniform1f(u.loc, n(0));
        else if (u.type === gl.FLOAT_VEC2) gl.uniform2f(u.loc, n(0), n(1));
        else if (u.type === gl.FLOAT_VEC3) gl.uniform3f(u.loc, n(0), n(1), n(2));
        else if (u.type === gl.FLOAT_VEC4) gl.uniform4f(u.loc, n(0), n(1), n(2), n(3));
        else if (u.type === gl.INT || u.type === gl.BOOL) gl.uniform1i(u.loc, Math.round(n(0)));
        else if (u.type === gl.UNSIGNED_INT) gl.uniform1ui(u.loc, Math.max(0, Math.round(n(0))));
      };

      // Buffers keep numbers outside 0 to 1 where the graphics card can draw into floats.
      const floats = !!gl.getExtension('EXT_color_buffer_float');
      const linear32 = floats && !!gl.getExtension('OES_texture_float_linear');
      const FORMAT = linear32 ? [gl.RGBA32F, gl.FLOAT] : floats ? [gl.RGBA16F, gl.HALF_FLOAT] : [gl.RGBA8, gl.UNSIGNED_BYTE];
      const upload = (w, h, data) => {
        const tex = gl.createTexture();
        gl.bindTexture(gl.TEXTURE_2D, tex);
        // The first row is the top of the picture.
        gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true);
        if (data instanceof Uint8Array) gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, w, h, 0, gl.RGBA, gl.UNSIGNED_BYTE, data);
        else gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, gl.RGBA, gl.UNSIGNED_BYTE, data);
        gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
        return { tex, w, h };
      };
      const fixed = {};
      const images = {};
      // An image a channel shows sits beside this page, by its file name. Browsers load it
      // only when the page is served, such as by `npx serve`, not opened as a file.
      const imageTexture = (name) => {
        if (!(name in images)) {
          images[name] = null;
          const img = new Image();
          img.onload = () => { images[name] = upload(img.naturalWidth, img.naturalHeight, img); };
          img.onerror = () => console.warn(`${name} did not load. Put it beside this page and serve the folder.`);
          img.src = name;
        }
        return images[name];
      };
      const buffers = {};
      const bufferOf = (id, w, h) => {
        let b = buffers[id];
        if (b && b.w === w && b.h === h) return b;
        const side = () => {
          const tex = gl.createTexture();
          gl.bindTexture(gl.TEXTURE_2D, tex);
          gl.texImage2D(gl.TEXTURE_2D, 0, FORMAT[0], w, h, 0, gl.RGBA, FORMAT[1], null);
          const fb = gl.createFramebuffer();
          gl.bindFramebuffer(gl.FRAMEBUFFER, fb);
          gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, tex, 0);
          return { tex, fb };
        };
        b = buffers[id] = { w, h, front: side(), back: side() };
        return b;
      };
      const textureFor = (source) => {
        const kind = source?.kind;
        if (kind === 'noise' || kind === 'checker') return (fixed[kind] ??= upload(TEXTURE_SIZE, TEXTURE_SIZE, builtinPixels(kind)));
        if (kind === 'buffer') { const b = buffers[source.buffer]; return b && { tex: b.front.tex, w: b.w, h: b.h }; }
        if (kind === 'image' && source.name) return imageTexture(source.name);
        return null;
      };
      const samplers = {};
      const samplerFor = (source) => {
        const key = filterOf(source) + wrapOf(source);
        if (samplers[key]) return samplers[key];
        const s = gl.createSampler();
        const filter = filterOf(source) === 'nearest' ? gl.NEAREST : gl.LINEAR;
        const wrap = wrapOf(source) === 'clamp' ? gl.CLAMP_TO_EDGE : gl.REPEAT;
        gl.samplerParameteri(s, gl.TEXTURE_MIN_FILTER, filter);
        gl.samplerParameteri(s, gl.TEXTURE_MAG_FILTER, filter);
        gl.samplerParameteri(s, gl.TEXTURE_WRAP_S, wrap);
        gl.samplerParameteri(s, gl.TEXTURE_WRAP_T, wrap);
        return (samplers[key] = s);
      };
      const black = upload(1, 1, new Uint8Array([0, 0, 0, 255]));

      const vao = gl.createVertexArray();
      const start = performance.now();
      let last = start;
      let frame = 0;
      const draw = (now) => {
        const [w, h] = fitCanvas();
        const time = (now - start) / 1000;
        for (const pass of PASSES) {
          const target = pass.id === 'image' ? null : bufferOf(pass.id, w, h);
          gl.bindFramebuffer(gl.FRAMEBUFFER, target ? target.back.fb : null);
          gl.viewport(0, 0, w, h);
          gl.useProgram(pass.program);
          const sizes = new Array(12).fill(0);
          for (const c of pass.channels) {
            const t = textureFor(c.source) ?? black;
            gl.activeTexture(gl.TEXTURE0 + c.index);
            gl.bindTexture(gl.TEXTURE_2D, t.tex);
            gl.bindSampler(c.index, samplerFor(c.source));
            if (t !== black) sizes.splice(c.index * 3, 3, t.w, t.h, 1);
            for (const name of c.names) if (pass.active[name]) gl.uniform1i(pass.active[name].loc, c.index);
          }
          const values = {
            u_resolution: [w, h], u_time: [time], u_frame: [frame], u_mouse: [mouse.x, mouse.y, mouse.down ? 1 : 0, 0], u_date: date(),
            iResolution: [w, h, 1], iTime: [time], iTimeDelta: [(now - last) / 1000], iFrame: [frame], iDate: date(), iChannelResolution: sizes,
            iMouse: [mouse.x, mouse.y, mouse.down ? mouse.cx : -mouse.cx, mouse.down ? mouse.cy : -mouse.cy],
          };
          for (const u of pass.uniforms) values[u.glsl] = u.value;
          for (const [name, u] of Object.entries(pass.active)) if (values[name]) set(u, values[name]);
          gl.bindVertexArray(vao);
          gl.drawArrays(gl.TRIANGLES, 0, 3);
          if (target) [target.front, target.back] = [target.back, target.front];
        }
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
M.WGSL = [[
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
      // {{TITLE}}: WGSL on WebGPU, built with the Proteus shader builder. Each frame the
      // buffers draw in order into pictures of their own, then the image draws here. A
      // pass's layout says where each field of its uniform struct sits in its buffer.
      const PASSES = {{PASSES}};

      const canvas = document.getElementById('view');
      const fail = (text) => { document.body.innerHTML = ''; const pre = document.createElement('pre'); pre.textContent = text; document.body.appendChild(pre); throw new Error(text); };
      if (!navigator.gpu) fail('This browser has no WebGPU.');
      const adapter = await navigator.gpu.requestAdapter();
      if (!adapter) fail('No graphics adapter offers WebGPU here.');
      const float32 = adapter.features.has('float32-filterable');
      const device = await adapter.requestDevice(float32 ? { requiredFeatures: ['float32-filterable'] } : undefined);
      const context = canvas.getContext('webgpu');
      const format = navigator.gpu.getPreferredCanvasFormat();
      const bufferFormat = float32 ? 'rgba32float' : 'rgba16float';
      context.configure({ device, format, alphaMode: 'premultiplied' });
{{TEXTURES}}
      for (const pass of PASSES) {
        const module = device.createShaderModule({ code: pass.module });
        const info = await module.getCompilationInfo();
        const errors = info.messages.filter((m) => m.type === 'error');
        if (errors.length) fail(errors.map((m) => `${pass.id} line ${m.lineNum}: ${m.message}`).join('\n'));
        pass.pipeline = await device.createRenderPipelineAsync({
          layout: 'auto',
          vertex: { module, entryPoint: pass.vertex_entry },
          fragment: { module, entryPoint: pass.fragment_entry, targets: [{ format: pass.id === 'image' ? format : bufferFormat }] },
          primitive: { topology: 'triangle-list' },
        });
        const size = Math.max(16, Math.ceil(pass.layout.size / 16) * 16);
        pass.data = new ArrayBuffer(size);
        pass.buffer = pass.layout.fields.length ? device.createBuffer({ size, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST }) : null;
        pass.values = Object.fromEntries(pass.uniforms.map((u) => [u.key, u.value]));
      }

      const upload = (w, h, data) => {
        const texture = device.createTexture({ size: [w, h], format: 'rgba8unorm', usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST | GPUTextureUsage.RENDER_ATTACHMENT });
        if (data instanceof Uint8Array) device.queue.writeTexture({ texture }, data, { bytesPerRow: w * 4 }, [w, h]);
        else device.queue.copyExternalImageToTexture({ source: data }, { texture }, [w, h]);
        return { view: texture.createView(), w, h };
      };
      const fixed = {};
      const images = {};
      // An image a channel shows sits beside this page, by its file name. Browsers load it
      // only when the page is served, such as by `npx serve`, not opened as a file.
      const imageTexture = (name) => {
        if (!(name in images)) {
          images[name] = null;
          fetch(name)
            .then((r) => r.blob())
            .then((blob) => createImageBitmap(blob))
            .then((bitmap) => { images[name] = upload(bitmap.width, bitmap.height, bitmap); })
            .catch(() => console.warn(`${name} did not load. Put it beside this page and serve the folder.`));
        }
        return images[name];
      };
      const buffers = {};
      const bufferOf = (id, w, h) => {
        let b = buffers[id];
        if (b && b.w === w && b.h === h) return b;
        const side = () => device.createTexture({ size: [w, h], format: bufferFormat, usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.RENDER_ATTACHMENT }).createView();
        b = buffers[id] = { w, h, front: side(), back: side() };
        return b;
      };
      const textureFor = (source) => {
        const kind = source?.kind;
        if (kind === 'noise' || kind === 'checker') return (fixed[kind] ??= upload(TEXTURE_SIZE, TEXTURE_SIZE, builtinPixels(kind)));
        if (kind === 'buffer') { const b = buffers[source.buffer]; return b && { view: b.front }; }
        if (kind === 'image' && source.name) return imageTexture(source.name);
        return null;
      };
      const samplers = {};
      const samplerFor = (source) => {
        const key = filterOf(source) + wrapOf(source);
        const wrap = wrapOf(source) === 'clamp' ? 'clamp-to-edge' : 'repeat';
        return (samplers[key] ??= device.createSampler({ magFilter: filterOf(source), minFilter: filterOf(source), addressModeU: wrap, addressModeV: wrap }));
      };
      const black = upload(1, 1, new Uint8Array([0, 0, 0, 255]));

      const start = performance.now();
      let frame = 0;
      const draw = (now) => {
        const [w, h] = fitCanvas();
        const builtins = { resolution: [w, h], time: [(now - start) / 1000], frame: [frame], mouse: [mouse.x, mouse.y, mouse.down ? 1 : 0, 0], date: date() };
        const encoder = device.createCommandEncoder();
        for (const pass of PASSES) {
          const f32 = new Float32Array(pass.data);
          const i32 = new Int32Array(pass.data);
          const u32 = new Uint32Array(pass.data);
          for (const f of pass.layout.fields) {
            const v = (f.builtin ? builtins[f.builtin] : pass.values[f.name]) || [];
            const n = { vec2: 2, vec3: 3, vec4: 4 }[f.type] || 1;
            for (let i = 0; i < n; i++) {
              const at = f.offset / 4 + i;
              if (f.type === 'int') i32[at] = Math.round(v[i] ?? 0);
              else if (f.type === 'uint') u32[at] = Math.max(0, Math.round(v[i] ?? 0));
              else f32[at] = v[i] ?? 0;
            }
          }
          if (pass.buffer) device.queue.writeBuffer(pass.buffer, 0, pass.data);
          const channels = Object.fromEntries(pass.channels.map((c) => [c.index, c]));
          const groups = {};
          for (const b of pass.bindings) {
            if (!b.used) continue;
            let resource;
            if (b.kind === 'uniforms') resource = pass.buffer && { buffer: pass.buffer };
            else if (b.kind === 'texture') resource = (textureFor(channels[b.channel]?.source) ?? black).view;
            else resource = samplerFor(channels[b.channel]?.source);
            if (resource) (groups[b.group] ??= []).push({ binding: b.binding, resource });
          }
          const target = pass.id === 'image' ? null : bufferOf(pass.id, w, h);
          const rp = encoder.beginRenderPass({
            colorAttachments: [{ view: target ? target.back : context.getCurrentTexture().createView(), clearValue: { r: 0, g: 0, b: 0, a: 1 }, loadOp: 'clear', storeOp: 'store' }],
          });
          rp.setPipeline(pass.pipeline);
          for (const [g, entries] of Object.entries(groups)) {
            rp.setBindGroup(Number(g), device.createBindGroup({ layout: pass.pipeline.getBindGroupLayout(Number(g)), entries }));
          }
          rp.draw(3);
          rp.end();
          if (target) [target.front, target.back] = [target.back, target.front];
        }
        device.queue.submit([encoder.finish()]);
        frame += 1;
        requestAnimationFrame(draw);
      };
      requestAnimationFrame(draw);
    </script>
  </body>
</html>
]]

---A page with its parts filled in.
---@param template string
---@param values table<string, string>
---@return string
function M.fill (template, values)
  local all = { TEXTURES = TEXTURES } ---@type table<string, string>
  for k, v in pairs (values) do
    all[k] = v
  end
  return (
    template:gsub ('{{([%w_]+)}}', function (key)
      return all[key] or ''
    end)
  )
end

return M
