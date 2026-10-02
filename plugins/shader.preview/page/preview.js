// The Shader Builder's live preview. It runs in a sandboxed web view: GLSL on WebGL 2 and WGSL
// on WebGPU, each on a canvas of its own, since a canvas keeps the first kind of context it
// gives out. The plugin sends it a program and uniform values as messages. The page sets time,
// resolution, frame and mouse itself, reports compile problems by line, and keeps drawing the
// last program that worked while a new one has errors.
//
// Messages from the plugin:
//   { type: 'run', program }        program: language, source, vertex, entries, uniforms, layout
//   { type: 'uniform', key, value } a new value for one uniform
//   { type: 'play' } { type: 'pause' } { type: 'restart' } { type: 'scale', scale }
// Messages to the plugin:
//   { type: 'status', ok, language, errors }   after each compile
//   { type: 'stats', fps, time, frame }        about twice a second while it draws and shows

(() => {
  'use strict';

  // GPUBufferUsage flags, spelled out so the page works where the global is missing.
  const BUFFER_COPY_DST = 0x08;
  const BUFFER_UNIFORM = 0x40;

  // GLSL uniforms the page sets itself.
  const GLSL_BUILTINS = new Set([
    'u_resolution',
    'u_time',
    'u_frame',
    'u_mouse',
    'iResolution',
    'iTime',
    'iTimeDelta',
    'iFrame',
    'iMouse',
  ]);

  const list = (value) => (Array.isArray(value) ? value : value ? Object.values(value) : []);
  const numbers = (value) => list(value).map(Number);

  const glCanvas = document.getElementById('gl');
  const gpuCanvas = document.getElementById('gpu');

  let language = 'glsl';
  let scale = 1;
  let playing = true;
  let time = 0;
  let frame = 0;
  let last = performance.now();
  let delta = 0;
  let raf = 0;
  let generation = 0;
  let glState = null;
  let lastGlsl = null;
  let gpuState = null;
  let gpuStarting = null;
  let gpuFailure = '';
  const values = new Map();
  let specs = [];
  const mouse = { x: 0, y: 0, down: false, clickX: 0, clickY: 0 };
  let fpsFrames = 0;
  let fpsSince = performance.now();

  const canvas = () => (language === 'glsl' ? glCanvas : gpuCanvas);

  function report(status) {
    proteus.post({ type: 'status', ok: status.ok, language: status.language, errors: status.errors });
  }

  function size() {
    const c = canvas();
    const ratio = (window.devicePixelRatio || 1) * scale;
    const w = Math.max(1, Math.floor(document.body.clientWidth * ratio));
    const h = Math.max(1, Math.floor(document.body.clientHeight * ratio));
    if (c.width !== w || c.height !== h) {
      c.width = w;
      c.height = h;
    }
    return [w, h];
  }

  /** Splits a WebGL info log into problems, such as `ERROR: 0:12: 'x' : undeclared identifier`. */
  function parseGlslLog(log, stage) {
    const out = [];
    for (const raw of log.split('\n')) {
      // Some drivers end the log with a NUL character.
      const line = raw.replace(/\0/g, '').trim();
      if (!line) continue;
      const m = /^(ERROR|WARNING):\s*\d+:(\d+):\s*(.*)$/.exec(line);
      if (m) {
        out.push({
          line: Number(m[2]) || undefined,
          message: m[3].replace(/^'([^']*)' : /, '$1: ').trim(),
          stage,
          severity: m[1] === 'WARNING' ? 'warning' : 'error',
        });
      } else if (!/^\d+ compilation errors?/i.test(line)) {
        out.push({ message: line, stage, severity: 'error' });
      }
    }
    return out;
  }

  // WebGL 2 ---------------------------------------------------------------------------------

  function glInit() {
    if (glState) return glState;
    const gl = glCanvas.getContext('webgl2', { alpha: true, premultipliedAlpha: false, antialias: false });
    if (!gl) return null;
    glState = { gl, vao: gl.createVertexArray(), program: null, uniforms: new Map() };
    return glState;
  }

  function glCompile(program) {
    lastGlsl = program;
    const s = glInit();
    if (!s) {
      report({
        ok: false,
        language: 'glsl',
        errors: [{ message: 'WebGL 2 is not available here, so GLSL cannot run.', stage: 'setup', severity: 'error' }],
      });
      return;
    }
    const { gl } = s;
    if (gl.isContextLost()) {
      report({
        ok: false,
        language: 'glsl',
        errors: [
          {
            message: 'The graphics context was lost. The preview comes back when it is restored.',
            stage: 'setup',
            severity: 'error',
          },
        ],
      });
      return;
    }
    const errors = [];
    const make = (type, source, stage) => {
      const sh = gl.createShader(type);
      gl.shaderSource(sh, source);
      gl.compileShader(sh);
      if (!gl.getShaderParameter(sh, gl.COMPILE_STATUS)) {
        errors.push(...parseGlslLog(gl.getShaderInfoLog(sh) || 'The shader did not compile.', stage));
        gl.deleteShader(sh);
        return null;
      }
      return sh;
    };
    const vs = make(gl.VERTEX_SHADER, program.vertex || '', 'vertex');
    const fs = make(gl.FRAGMENT_SHADER, program.source || '', 'fragment');
    let linked = null;
    if (vs && fs) {
      const p = gl.createProgram();
      gl.attachShader(p, vs);
      gl.attachShader(p, fs);
      gl.linkProgram(p);
      if (gl.getProgramParameter(p, gl.LINK_STATUS)) {
        linked = p;
      } else {
        errors.push({ message: gl.getProgramInfoLog(p) || 'The shaders did not link.', stage: 'link', severity: 'error' });
        gl.deleteProgram(p);
      }
    }
    if (vs) gl.deleteShader(vs);
    if (fs) gl.deleteShader(fs);
    if (linked) {
      if (s.program) gl.deleteProgram(s.program);
      s.program = linked;
      s.uniforms.clear();
      const count = gl.getProgramParameter(linked, gl.ACTIVE_UNIFORMS);
      for (let i = 0; i < count; i++) {
        const info = gl.getActiveUniform(linked, i);
        if (!info) continue;
        const loc = gl.getUniformLocation(linked, info.name);
        if (loc) s.uniforms.set(info.name.replace(/\[0\]$/, ''), { loc, type: info.type });
      }
    }
    report({ ok: !!linked, language: 'glsl', errors });
  }

  function glSet(gl, u, v) {
    const n = (i) => v[i] ?? 0;
    const r = (i) => Math.round(n(i));
    switch (u.type) {
      case gl.FLOAT:
        return gl.uniform1f(u.loc, n(0));
      case gl.FLOAT_VEC2:
        return gl.uniform2f(u.loc, n(0), n(1));
      case gl.FLOAT_VEC3:
        return gl.uniform3f(u.loc, n(0), n(1), n(2));
      case gl.FLOAT_VEC4:
        return gl.uniform4f(u.loc, n(0), n(1), n(2), n(3));
      case gl.INT:
      case gl.BOOL:
        return gl.uniform1i(u.loc, r(0));
      case gl.UNSIGNED_INT:
        return gl.uniform1ui(u.loc, Math.max(0, r(0)));
      case gl.INT_VEC2:
      case gl.BOOL_VEC2:
        return gl.uniform2i(u.loc, r(0), r(1));
      case gl.INT_VEC3:
      case gl.BOOL_VEC3:
        return gl.uniform3i(u.loc, r(0), r(1), r(2));
      case gl.INT_VEC4:
      case gl.BOOL_VEC4:
        return gl.uniform4i(u.loc, r(0), r(1), r(2), r(3));
    }
  }

  function builtin(name, w, h) {
    switch (name) {
      case 'u_resolution':
      case 'resolution':
        return [w, h];
      case 'iResolution':
        return [w, h, 1];
      case 'u_time':
      case 'time':
      case 'iTime':
        return [time];
      case 'iTimeDelta':
        return [delta];
      case 'u_frame':
      case 'frame':
      case 'iFrame':
        return [frame];
      case 'u_mouse':
      case 'mouse':
        return [mouse.x, mouse.y, mouse.down ? 1 : 0, 0];
      case 'iMouse':
        return [
          mouse.x,
          mouse.y,
          mouse.down ? mouse.clickX : -mouse.clickX,
          mouse.down ? mouse.clickY : -mouse.clickY,
        ];
    }
    return undefined;
  }

  function valueOf(name, glsl) {
    for (const spec of specs) {
      const own = glsl ? (spec.glsl ?? spec.key) : spec.key;
      if (own === name) return values.get(spec.key) ?? numbers(spec.value);
    }
    return undefined;
  }

  function glDraw() {
    const s = glState;
    if (!s || !s.program) return;
    const { gl } = s;
    const [w, h] = size();
    gl.viewport(0, 0, w, h);
    gl.clearColor(0, 0, 0, 0);
    gl.clear(gl.COLOR_BUFFER_BIT);
    gl.useProgram(s.program);
    for (const [name, u] of s.uniforms) {
      const b = GLSL_BUILTINS.has(name) ? builtin(name, w, h) : undefined;
      const v = b ?? valueOf(name, true);
      if (v) glSet(gl, u, v);
    }
    gl.bindVertexArray(s.vao);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
  }

  // The browser may take the WebGL context away, such as after a graphics driver reset. When it
  // gives it back, everything is made again and the last program compiled.
  glCanvas.addEventListener('webglcontextlost', (ev) => {
    ev.preventDefault();
    glState = null;
  });
  glCanvas.addEventListener('webglcontextrestored', () => {
    if (lastGlsl && language === 'glsl') {
      glCompile(lastGlsl);
      requestDraw();
    }
  });

  // WebGPU ----------------------------------------------------------------------------------

  async function gpuInit() {
    if (gpuState) return gpuState;
    if (!gpuStarting) {
      gpuStarting = (async () => {
        const gpu = navigator.gpu;
        if (!gpu) {
          gpuFailure = 'WebGPU is not available here, so WGSL cannot run. GLSL still works.';
          return null;
        }
        const adapter = await gpu.requestAdapter().catch(() => null);
        if (!adapter) {
          gpuFailure = 'No graphics adapter offers WebGPU here, so WGSL cannot run. GLSL still works.';
          return null;
        }
        const device = await adapter.requestDevice();
        const context = gpuCanvas.getContext('webgpu');
        if (!context) {
          gpuFailure = 'The canvas has no WebGPU context.';
          return null;
        }
        const format = gpu.getPreferredCanvasFormat();
        context.configure({ device, format, alphaMode: 'premultiplied' });
        device.lost.then((info) => {
          gpuState = null;
          gpuStarting = null;
          if (info.reason !== 'destroyed' && language === 'wgsl') {
            report({
              ok: false,
              language: 'wgsl',
              errors: [{ message: `The WebGPU device was lost: ${info.message}`, stage: 'setup', severity: 'error' }],
            });
          }
        });
        gpuState = {
          device,
          context,
          format,
          pipeline: null,
          buffer: null,
          bindGroup: null,
          data: new ArrayBuffer(16),
          fields: [],
        };
        return gpuState;
      })().catch((err) => {
        gpuFailure = `WebGPU did not start: ${String(err)}`;
        return null;
      });
    }
    return gpuStarting;
  }

  async function gpuCompile(program, ticket) {
    const s = await gpuInit();
    if (ticket !== generation) return;
    if (!s) {
      report({ ok: false, language: 'wgsl', errors: [{ message: gpuFailure, stage: 'setup', severity: 'error' }] });
      return;
    }
    const { device } = s;
    const errors = [];
    device.pushErrorScope('validation');
    const module = device.createShaderModule({ code: program.source || '' });
    const info = await module.getCompilationInfo();
    for (const m of info.messages) {
      errors.push({
        line: m.lineNum || undefined,
        column: m.linePos || undefined,
        message: m.message,
        stage: 'fragment',
        severity: m.type === 'error' ? 'error' : 'warning',
      });
    }
    await device.popErrorScope();
    if (ticket !== generation) return;
    if (errors.some((e) => e.severity === 'error')) {
      report({ ok: false, language: 'wgsl', errors });
      return;
    }
    device.pushErrorScope('validation');
    let pipeline = null;
    try {
      pipeline = await device.createRenderPipelineAsync({
        layout: 'auto',
        vertex: { module, entryPoint: program.vertex_entry || 'vs_main' },
        fragment: { module, entryPoint: program.fragment_entry || 'fs_main', targets: [{ format: s.format }] },
        primitive: { topology: 'triangle-list' },
      });
    } catch (err) {
      errors.push({ message: String(err?.message ?? err), stage: 'pipeline', severity: 'error' });
    }
    const scoped = await device.popErrorScope();
    if (scoped) errors.push({ message: scoped.message, stage: 'pipeline', severity: 'error' });
    if (ticket !== generation) return;
    if (!pipeline || errors.some((e) => e.severity === 'error')) {
      report({ ok: false, language: 'wgsl', errors });
      return;
    }
    const fields = list(program.layout?.fields);
    const bytes = Math.max(16, Math.ceil((program.layout?.size ?? 16) / 16) * 16);
    s.buffer?.destroy();
    s.buffer = null;
    s.bindGroup = null;
    if (fields.length > 0) {
      s.buffer = device.createBuffer({ size: bytes, usage: BUFFER_UNIFORM | BUFFER_COPY_DST });
      device.pushErrorScope('validation');
      try {
        s.bindGroup = device.createBindGroup({
          layout: pipeline.getBindGroupLayout(0),
          entries: [{ binding: 0, resource: { buffer: s.buffer } }],
        });
      } catch {
        s.bindGroup = null; // The shader reads no uniforms.
      }
      if (await device.popErrorScope()) s.bindGroup = null;
    }
    s.pipeline = pipeline;
    s.data = new ArrayBuffer(bytes);
    s.fields = fields;
    report({ ok: true, language: 'wgsl', errors });
    requestDraw();
  }

  function gpuDraw() {
    const s = gpuState;
    if (!s || !s.pipeline) return;
    const [w, h] = size();
    if (s.buffer && s.bindGroup) {
      const f32 = new Float32Array(s.data);
      const i32 = new Int32Array(s.data);
      const u32 = new Uint32Array(s.data);
      for (const f of s.fields) {
        const v = (f.builtin ? builtin(f.builtin, w, h) : undefined) ?? valueOf(f.name, false) ?? [];
        const at = f.offset / 4;
        const n = f.type === 'vec2' ? 2 : f.type === 'vec3' ? 3 : f.type === 'vec4' ? 4 : 1;
        for (let i = 0; i < n; i++) {
          const x = v[i] ?? 0;
          if (f.type === 'int') i32[at + i] = Math.round(x);
          else if (f.type === 'uint') u32[at + i] = Math.max(0, Math.round(x));
          else f32[at + i] = x;
        }
      }
      s.device.queue.writeBuffer(s.buffer, 0, s.data);
    }
    const encoder = s.device.createCommandEncoder();
    const pass = encoder.beginRenderPass({
      colorAttachments: [
        {
          view: s.context.getCurrentTexture().createView(),
          clearValue: { r: 0, g: 0, b: 0, a: 0 },
          loadOp: 'clear',
          storeOp: 'store',
        },
      ],
    });
    pass.setPipeline(s.pipeline);
    if (s.bindGroup) pass.setBindGroup(0, s.bindGroup);
    pass.draw(3);
    pass.end();
    s.device.queue.submit([encoder.finish()]);
  }

  // The loop --------------------------------------------------------------------------------

  // A hidden panel has no size. The loop stops then, and starts again when the panel shows.
  let stopped = false;
  const hidden = () => document.hidden || document.body.clientWidth === 0 || document.body.clientHeight === 0;

  function draw() {
    if (language === 'glsl') glDraw();
    else gpuDraw();
  }

  function tick(now) {
    raf = 0;
    if (hidden()) {
      stopped = true;
      return;
    }
    delta = Math.min(0.25, (now - last) / 1000);
    last = now;
    if (playing) {
      time += delta;
      frame += 1;
    }
    draw();
    fpsFrames += 1;
    if (now - fpsSince > 500) {
      proteus.post({ type: 'stats', fps: (fpsFrames * 1000) / (now - fpsSince), time, frame });
      fpsFrames = 0;
      fpsSince = now;
    }
    if (playing) raf = requestAnimationFrame(tick);
  }

  function requestDraw() {
    if (!raf) {
      last = performance.now();
      if (stopped) {
        // The frame rate counts from now, not from before the panel hid.
        stopped = false;
        fpsFrames = 0;
        fpsSince = last;
      }
      raf = requestAnimationFrame(tick);
    }
  }

  function run(program) {
    generation += 1;
    specs = list(program.uniforms);
    language = program.language === 'wgsl' ? 'wgsl' : 'glsl';
    glCanvas.style.display = language === 'glsl' ? 'block' : 'none';
    gpuCanvas.style.display = language === 'wgsl' ? 'block' : 'none';
    if (language === 'glsl') {
      glCompile(program);
      requestDraw();
    } else {
      void gpuCompile(program, generation);
    }
  }

  // Mouse, in pixels of the picture from its bottom left, as the shader sees them.
  const at = (ev) => {
    const c = canvas();
    const w = Math.max(1, document.body.clientWidth);
    const h = Math.max(1, document.body.clientHeight);
    return [(ev.clientX / w) * c.width, ((h - ev.clientY) / h) * c.height];
  };
  document.addEventListener('pointerdown', (ev) => {
    if (ev.button !== 0) return;
    const [x, y] = at(ev);
    Object.assign(mouse, { x, y, down: true, clickX: x, clickY: y });
    document.body.setPointerCapture?.(ev.pointerId);
    requestDraw();
  });
  document.addEventListener('pointermove', (ev) => {
    if (!mouse.down) return;
    [mouse.x, mouse.y] = at(ev);
    requestDraw();
  });
  const up = () => {
    mouse.down = false;
    requestDraw();
  };
  document.addEventListener('pointerup', up);
  document.addEventListener('pointercancel', up);
  new ResizeObserver(() => requestDraw()).observe(document.body);
  document.addEventListener('visibilitychange', () => requestDraw());

  proteus.on((msg) => {
    if (!msg || typeof msg !== 'object') return;
    switch (msg.type) {
      case 'run':
        if (msg.program && typeof msg.program === 'object') run(msg.program);
        break;
      case 'uniform':
        values.set(String(msg.key), numbers(msg.value));
        requestDraw();
        break;
      case 'play':
        playing = true;
        requestDraw();
        break;
      case 'pause':
        playing = false;
        break;
      case 'restart':
        time = 0;
        frame = 0;
        requestDraw();
        break;
      case 'scale':
        scale = Math.min(2, Math.max(0.1, Number(msg.scale) || 1));
        requestDraw();
        break;
    }
  });
})();
