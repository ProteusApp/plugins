// The Shader Builder's live preview. It runs in a sandboxed web view: GLSL on WebGL 2 and WGSL
// on WebGPU, each on a canvas of its own, since a canvas keeps the first kind of context it
// gives out. The plugin sends it the passes of a shader and uniform values as messages. The
// page sets time, resolution, frame, mouse and date itself, reports compile problems by pass
// and line, and keeps drawing the last passes that worked while new ones have errors.
//
// A shader has an image pass and up to four buffers, a to d, as Shadertoy has. Each frame the
// buffers draw in order into pictures of their own, then the image draws on the canvas. A
// channel reads a buffer's newest picture: one drawn earlier this frame, or the last frame's
// for itself and the buffers after it. When the shader in front is a buffer, the page shows
// that buffer's picture instead of the image.
//
// Messages from the plugin:
//   { type: 'run', language, show, passes }   passes: { id, program } in the order they draw,
//                                             program: language, source, vertex, entries,
//                                             uniforms, layout, bindings and channels, each
//                                             channel with its index, names and source
//   { type: 'uniform', key, value }           a new value for one uniform of the pass shown
//   { type: 'play' } { type: 'pause' } { type: 'restart' } { type: 'scale', scale }
// Files: the plugin sends each image a channel shows with `send_file`, tagged with its grant.
// Messages to the plugin:
//   { type: 'status', ok, language, errors }   after each compile, each error with its pass
//   { type: 'stats', fps, time, frame }        about twice a second while it draws and shows
//   { type: 'file', grant, name, error }       an image that did not arrive or did not decode

(() => {
  'use strict';

  // GPUBufferUsage and GPUTextureUsage flags, spelled out so the page works where the globals
  // are missing.
  const BUFFER_COPY_DST = 0x08;
  const BUFFER_UNIFORM = 0x40;
  const TEXTURE_COPY_DST = 0x02;
  const TEXTURE_BINDING = 0x04;
  const TEXTURE_RENDER = 0x10;

  // Uniforms the page sets itself, in GLSL and in a WGSL struct.
  const BUILTINS = new Set([
    'u_resolution',
    'u_time',
    'u_frame',
    'u_mouse',
    'u_date',
    'iResolution',
    'iTime',
    'iTimeDelta',
    'iFrame',
    'iMouse',
    'iDate',
    'iChannelResolution',
  ]);

  // The size of the noise and checker textures.
  const TEXTURE_SIZE = 256;

  const list = (value) => (Array.isArray(value) ? value : value ? Object.values(value) : []);
  const numbers = (value) => list(value).map(Number);

  const glCanvas = document.getElementById('gl');
  const gpuCanvas = document.getElementById('gpu');

  let language = 'glsl';
  let show = 'image';
  let scale = 1;
  let playing = true;
  let time = 0;
  let frame = 0;
  let last = performance.now();
  let delta = 0;
  let raf = 0;
  let generation = 0;
  let glState = null;
  let lastRun = null;
  let gpuState = null;
  let gpuStarting = null;
  let gpuFailure = '';
  // Values the controls set, for the pass shown.
  const values = new Map();
  // Images by grant: the file's bytes, and a texture for each kind of context once made.
  const images = new Map();
  const mouse = { x: 0, y: 0, down: false, clickX: 0, clickY: 0 };
  let fpsFrames = 0;
  let fpsSince = performance.now();
  // Buffers draw only while time runs, and once after a run or a resize, so a paused shader
  // keeps its picture.
  let freshBuffers = true;

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
  function parseGlslLog(log, stage, pass) {
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
          pass,
          severity: m[1] === 'WARNING' ? 'warning' : 'error',
        });
      } else if (!/^\d+ compilation errors?/i.test(line)) {
        out.push({ message: line, stage, pass, severity: 'error' });
      }
    }
    return out;
  }

  // Built-in textures -----------------------------------------------------------------------

  /** RGBA noise, four numbers that do not depend on each other per pixel, the same every time. */
  function noisePixels() {
    const data = new Uint8Array(TEXTURE_SIZE * TEXTURE_SIZE * 4);
    let seed = 0x9e3779b9;
    for (let i = 0; i < data.length; i++) {
      seed = (seed + 0x6d2b79f5) | 0;
      let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      data[i] = ((t ^ (t >>> 14)) >>> 0) & 255;
    }
    return data;
  }

  /** Grey and white squares, 8 to a side. */
  function checkerPixels() {
    const data = new Uint8Array(TEXTURE_SIZE * TEXTURE_SIZE * 4);
    const square = TEXTURE_SIZE / 8;
    for (let y = 0; y < TEXTURE_SIZE; y++) {
      for (let x = 0; x < TEXTURE_SIZE; x++) {
        const on = (Math.floor(x / square) + Math.floor(y / square)) % 2 === 0;
        const v = on ? 230 : 90;
        const at = (y * TEXTURE_SIZE + x) * 4;
        data[at] = v;
        data[at + 1] = v;
        data[at + 2] = v;
        data[at + 3] = 255;
      }
    }
    return data;
  }

  let noiseData = null;
  let checkerData = null;
  const builtinPixels = (kind) => {
    if (kind === 'noise') return (noiseData ??= noisePixels());
    return (checkerData ??= checkerPixels());
  };

  const filterOf = (source) => (source?.filter === 'nearest' ? 'nearest' : 'linear');
  const wrapOf = (source) => (source?.wrap ? source.wrap : source?.kind === 'buffer' ? 'clamp' : 'repeat');

  /** The pixels a builtin uniform holds. */
  function builtin(name, w, h, sizes) {
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
      case 'u_date':
      case 'date':
      case 'iDate': {
        const d = new Date();
        const seconds = d.getHours() * 3600 + d.getMinutes() * 60 + d.getSeconds() + d.getMilliseconds() / 1000;
        return [d.getFullYear(), d.getMonth(), d.getDate(), seconds];
      }
      case 'iChannelResolution':
        return sizes ?? new Array(12).fill(0);
    }
    return undefined;
  }

  /** A uniform's value in a pass: the control's when the pass is shown, else the program's. */
  function valueOf(pass, name, glsl) {
    for (const spec of list(pass.program.uniforms)) {
      const own = glsl ? (spec.glsl ?? spec.key) : spec.key;
      if (own === name) return (pass.id === show && values.get(spec.key)) || numbers(spec.value);
    }
    return undefined;
  }

  /** What each pass reads, by channel index, from its program. */
  const channelsOf = (pass) => list(pass.program.channels);

  // WebGL 2 ---------------------------------------------------------------------------------

  const GL_VERTEX = `#version 300 es
out vec2 v_uv;
void main() {
  vec2 p = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2));
  v_uv = p;
  gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}`;
  const GL_COPY = `#version 300 es
precision highp float;
uniform highp sampler2D picture;
in vec2 v_uv;
out vec4 color;
void main() { color = texture(picture, v_uv); }`;

  function glInit() {
    if (glState) return glState;
    const gl = glCanvas.getContext('webgl2', { alpha: true, premultipliedAlpha: false, antialias: false });
    if (!gl) return null;
    // Buffers keep numbers outside 0 to 1 where the graphics card can draw into floats.
    const floats = !!gl.getExtension('EXT_color_buffer_float');
    const linear32 = floats && !!gl.getExtension('OES_texture_float_linear');
    const format = linear32
      ? { internal: gl.RGBA32F, type: gl.FLOAT }
      : floats
        ? { internal: gl.RGBA16F, type: gl.HALF_FLOAT }
        : { internal: gl.RGBA8, type: gl.UNSIGNED_BYTE };
    glState = {
      gl,
      vao: gl.createVertexArray(),
      format,
      set: null,
      buffers: new Map(),
      textures: new Map(),
      samplers: new Map(),
      copy: null,
    };
    return glState;
  }

  function glMakeProgram(gl, vertex, fragment, pass, errors) {
    const make = (type, source, stage) => {
      const sh = gl.createShader(type);
      gl.shaderSource(sh, source);
      gl.compileShader(sh);
      if (!gl.getShaderParameter(sh, gl.COMPILE_STATUS)) {
        errors.push(...parseGlslLog(gl.getShaderInfoLog(sh) || 'The shader did not compile.', stage, pass));
        gl.deleteShader(sh);
        return null;
      }
      return sh;
    };
    const vs = make(gl.VERTEX_SHADER, vertex, 'vertex');
    const fs = make(gl.FRAGMENT_SHADER, fragment, 'fragment');
    let linked = null;
    if (vs && fs) {
      const p = gl.createProgram();
      gl.attachShader(p, vs);
      gl.attachShader(p, fs);
      gl.linkProgram(p);
      if (gl.getProgramParameter(p, gl.LINK_STATUS)) {
        linked = p;
      } else {
        errors.push({ message: gl.getProgramInfoLog(p) || 'The shaders did not link.', stage: 'link', pass, severity: 'error' });
        gl.deleteProgram(p);
      }
    }
    if (vs) gl.deleteShader(vs);
    if (fs) gl.deleteShader(fs);
    if (!linked) return null;
    const uniforms = new Map();
    const count = gl.getProgramParameter(linked, gl.ACTIVE_UNIFORMS);
    for (let i = 0; i < count; i++) {
      const info = gl.getActiveUniform(linked, i);
      if (!info) continue;
      const loc = gl.getUniformLocation(linked, info.name);
      if (loc) uniforms.set(info.name.replace(/\[0\]$/, ''), { loc, type: info.type, size: info.size });
    }
    return { program: linked, uniforms };
  }

  function glCompile(run) {
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
    const made = [];
    for (const pass of run.passes) {
      const p = glMakeProgram(gl, pass.program.vertex || GL_VERTEX, pass.program.source || '', pass.id, errors);
      if (p) made.push({ ...pass, gl: p });
    }
    const ok = made.length === run.passes.length;
    if (ok) {
      if (s.set) for (const old of s.set.passes) gl.deleteProgram(old.gl.program);
      s.set = { passes: made, show: run.show };
      freshBuffers = true;
    } else {
      for (const p of made) gl.deleteProgram(p.gl.program);
    }
    report({ ok, language: 'glsl', errors });
  }

  function glSet(gl, u, v) {
    const n = (i) => v[i] ?? 0;
    const r = (i) => Math.round(n(i));
    if (u.size > 1) {
      const per = { [gl.FLOAT]: 1, [gl.FLOAT_VEC2]: 2, [gl.FLOAT_VEC3]: 3, [gl.FLOAT_VEC4]: 4 }[u.type];
      if (!per) return;
      const data = new Float32Array(per * u.size);
      for (let i = 0; i < data.length; i++) data[i] = n(i);
      if (per === 1) gl.uniform1fv(u.loc, data);
      else if (per === 2) gl.uniform2fv(u.loc, data);
      else if (per === 3) gl.uniform3fv(u.loc, data);
      else gl.uniform4fv(u.loc, data);
      return;
    }
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

  /** A texture of 8-bit pixels, made once for each kind. */
  function glFixedTexture(s, key, w, h, pixels) {
    let t = s.textures.get(key);
    if (t) return t;
    const { gl } = s;
    const tex = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, tex);
    // The first row of the pixels is the top of the picture, as in an image and in WebGPU.
    gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, w, h, 0, gl.RGBA, gl.UNSIGNED_BYTE, pixels);
    gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
    t = { tex, w, h };
    s.textures.set(key, t);
    return t;
  }

  function glSampler(s, source) {
    const key = `${filterOf(source)}-${wrapOf(source)}`;
    let sampler = s.samplers.get(key);
    if (sampler) return sampler;
    const { gl } = s;
    sampler = gl.createSampler();
    const filter = filterOf(source) === 'nearest' ? gl.NEAREST : gl.LINEAR;
    const wrap = wrapOf(source) === 'clamp' ? gl.CLAMP_TO_EDGE : gl.REPEAT;
    gl.samplerParameteri(sampler, gl.TEXTURE_MIN_FILTER, filter);
    gl.samplerParameteri(sampler, gl.TEXTURE_MAG_FILTER, filter);
    gl.samplerParameteri(sampler, gl.TEXTURE_WRAP_S, wrap);
    gl.samplerParameteri(sampler, gl.TEXTURE_WRAP_T, wrap);
    s.samplers.set(key, sampler);
    return sampler;
  }

  /** A buffer's two pictures at the canvas's size: the newest, and the one it draws into. */
  function glBuffer(s, id, w, h) {
    const { gl } = s;
    let b = s.buffers.get(id);
    if (b && b.w === w && b.h === h) return b;
    if (b) for (const side of [b.front, b.back]) glDropTarget(gl, side);
    const make = () => {
      const tex = gl.createTexture();
      gl.bindTexture(gl.TEXTURE_2D, tex);
      gl.texImage2D(gl.TEXTURE_2D, 0, s.format.internal, w, h, 0, gl.RGBA, s.format.type, null);
      const fb = gl.createFramebuffer();
      gl.bindFramebuffer(gl.FRAMEBUFFER, fb);
      gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, tex, 0);
      return { tex, fb };
    };
    b = { w, h, front: make(), back: make() };
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    s.buffers.set(id, b);
    freshBuffers = true;
    return b;
  }

  function glDropTarget(gl, side) {
    gl.deleteTexture(side.tex);
    gl.deleteFramebuffer(side.fb);
  }

  function glClearBuffers(s) {
    for (const b of s.buffers.values()) for (const side of [b.front, b.back]) glDropTarget(s.gl, side);
    s.buffers.clear();
  }

  /** The texture a channel's source reads now, or null when it has none yet. */
  function glTextureFor(s, source, w, h) {
    const kind = source?.kind;
    if (kind === 'noise' || kind === 'checker') {
      return glFixedTexture(s, kind, TEXTURE_SIZE, TEXTURE_SIZE, builtinPixels(kind));
    }
    if (kind === 'buffer') {
      const b = s.buffers.get(source.buffer);
      return b ? { tex: b.front.tex, w: b.w, h: b.h } : null;
    }
    if (kind === 'image') {
      const entry = images.get(source.grant);
      if (!entry) return null;
      if (!entry.gl && !entry.glMaking) {
        entry.glMaking = true;
        // A bitmap ignores the flip WebGL offers, so it turns over as it decodes.
        createImageBitmap(entry.blob, { imageOrientation: 'flipY' })
          .then((bitmap) => {
            if (!glState || glState !== s) return;
            const { gl } = s;
            const tex = gl.createTexture();
            gl.bindTexture(gl.TEXTURE_2D, tex);
            gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, gl.RGBA, gl.UNSIGNED_BYTE, bitmap);
            entry.gl = { tex, w: bitmap.width, h: bitmap.height };
            bitmap.close();
            requestDraw();
          })
          .catch(() => imageFailed(entry));
      }
      return entry.gl ?? null;
    }
    return null;
  }

  function glBindChannels(s, pass, prog, w, h) {
    const { gl } = s;
    const sizes = new Array(12).fill(0);
    for (const c of channelsOf(pass)) {
      const index = Number(c.index);
      if (!(index >= 0 && index < 4)) continue;
      const t = glTextureFor(s, c.source, w, h) ?? glFixedTexture(s, 'black', 1, 1, new Uint8Array([0, 0, 0, 255]));
      gl.activeTexture(gl.TEXTURE0 + index);
      gl.bindTexture(gl.TEXTURE_2D, t.tex);
      gl.bindSampler(index, glSampler(s, c.source));
      if (c.source?.kind && c.source.kind !== 'none') sizes.splice(index * 3, 3, t.w, t.h, 1);
      for (const name of list(c.names)) {
        const u = prog.uniforms.get(name);
        if (u) gl.uniform1i(u.loc, index);
      }
    }
    return sizes;
  }

  function glRunPass(s, pass, w, h, target) {
    const { gl } = s;
    const prog = pass.gl;
    gl.bindFramebuffer(gl.FRAMEBUFFER, target ? target.fb : null);
    gl.viewport(0, 0, w, h);
    gl.clearColor(0, 0, 0, 0);
    gl.clear(gl.COLOR_BUFFER_BIT);
    gl.useProgram(prog.program);
    const sizes = glBindChannels(s, pass, prog, w, h);
    for (const [name, u] of prog.uniforms) {
      if (u.type === gl.SAMPLER_2D) continue;
      const b = BUILTINS.has(name) ? builtin(name, w, h, sizes) : undefined;
      const v = b ?? valueOf(pass, name, true);
      if (v) glSet(gl, u, v);
    }
    gl.bindVertexArray(s.vao);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
  }

  function glShowBuffer(s, b, w, h) {
    const { gl } = s;
    if (!s.copy) s.copy = glMakeProgram(gl, GL_VERTEX, GL_COPY, 'show', []);
    if (!s.copy) return;
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    gl.viewport(0, 0, w, h);
    gl.clearColor(0, 0, 0, 0);
    gl.clear(gl.COLOR_BUFFER_BIT);
    gl.useProgram(s.copy.program);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, b.front.tex);
    gl.bindSampler(0, glSampler(s, { kind: 'buffer', filter: 'nearest' }));
    const u = s.copy.uniforms.get('picture');
    if (u) gl.uniform1i(u.loc, 0);
    gl.bindVertexArray(s.vao);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
  }

  function glDraw(advance) {
    const s = glState;
    if (!s || !s.set) return;
    const [w, h] = size();
    const runBuffers = advance || freshBuffers;
    for (const pass of s.set.passes) {
      if (pass.id === 'image') {
        glRunPass(s, pass, w, h, null);
      } else {
        const b = glBuffer(s, pass.id, w, h);
        if (!runBuffers) continue;
        glRunPass(s, pass, w, h, b.back);
        [b.front, b.back] = [b.back, b.front];
      }
    }
    if (runBuffers) freshBuffers = false;
    if (s.set.show !== 'image') {
      const b = s.buffers.get(s.set.show);
      if (b) glShowBuffer(s, b, w, h);
    }
  }

  // The browser may take the WebGL context away, such as after a graphics driver reset. When it
  // gives it back, everything is made again and the last passes compiled.
  glCanvas.addEventListener('webglcontextlost', (ev) => {
    ev.preventDefault();
    glState = null;
    for (const entry of images.values()) {
      entry.gl = null;
      entry.glMaking = false;
    }
  });
  glCanvas.addEventListener('webglcontextrestored', () => {
    if (lastRun && language === 'glsl') {
      glCompile(lastRun);
      requestDraw();
    }
  });

  // WebGPU ----------------------------------------------------------------------------------

  const GPU_COPY = `
@group(0) @binding(0) var picture: texture_2d<f32>;
@group(0) @binding(1) var picture_sampler: sampler;
struct CopyOut {
  @builtin(position) position: vec4f,
  @location(0) uv: vec2f,
}
@vertex
fn vs_copy(@builtin(vertex_index) index: u32) -> CopyOut {
  let p = vec2f(f32((index << 1u) & 2u), f32(index & 2u));
  var out: CopyOut;
  out.position = vec4f(p * 2.0 - 1.0, 0.0, 1.0);
  out.uv = vec2f(p.x, 1.0 - p.y);
  return out;
}
@fragment
fn fs_copy(input: CopyOut) -> @location(0) vec4f {
  return textureSample(picture, picture_sampler, input.uv);
}`;

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
        // Buffers keep 32-bit floats where they can be filtered, and 16-bit ones otherwise.
        const float32 = adapter.features.has('float32-filterable');
        const device = await adapter.requestDevice(float32 ? { requiredFeatures: ['float32-filterable'] } : undefined);
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
          for (const entry of images.values()) {
            entry.gpu = null;
            entry.gpuMaking = false;
          }
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
          bufferFormat: float32 ? 'rgba32float' : 'rgba16float',
          set: null,
          buffers: new Map(),
          textures: new Map(),
          samplers: new Map(),
          copy: null,
        };
        return gpuState;
      })().catch((err) => {
        gpuFailure = `WebGPU did not start: ${String(err)}`;
        return null;
      });
    }
    return gpuStarting;
  }

  function gpuFixedTexture(s, key, w, h, pixels) {
    let t = s.textures.get(key);
    if (t) return t;
    const texture = s.device.createTexture({ size: [w, h], format: 'rgba8unorm', usage: TEXTURE_BINDING | TEXTURE_COPY_DST });
    s.device.queue.writeTexture({ texture }, pixels, { bytesPerRow: w * 4 }, [w, h]);
    t = { view: texture.createView(), texture, w, h };
    s.textures.set(key, t);
    return t;
  }

  function gpuSampler(s, source) {
    const key = `${filterOf(source)}-${wrapOf(source)}`;
    let sampler = s.samplers.get(key);
    if (sampler) return sampler;
    const filter = filterOf(source);
    const wrap = wrapOf(source) === 'clamp' ? 'clamp-to-edge' : 'repeat';
    sampler = s.device.createSampler({
      magFilter: filter,
      minFilter: filter,
      addressModeU: wrap,
      addressModeV: wrap,
    });
    s.samplers.set(key, sampler);
    return sampler;
  }

  function gpuBuffer(s, id, w, h) {
    let b = s.buffers.get(id);
    if (b && b.w === w && b.h === h) return b;
    if (b) {
      b.front.texture.destroy();
      b.back.texture.destroy();
    }
    const make = () => {
      const texture = s.device.createTexture({
        size: [w, h],
        format: s.bufferFormat,
        usage: TEXTURE_BINDING | TEXTURE_RENDER,
      });
      return { texture, view: texture.createView() };
    };
    b = { w, h, front: make(), back: make() };
    s.buffers.set(id, b);
    freshBuffers = true;
    return b;
  }

  function gpuClearBuffers(s) {
    for (const b of s.buffers.values()) {
      b.front.texture.destroy();
      b.back.texture.destroy();
    }
    s.buffers.clear();
  }

  function gpuTextureFor(s, source) {
    const kind = source?.kind;
    if (kind === 'noise' || kind === 'checker') {
      return gpuFixedTexture(s, kind, TEXTURE_SIZE, TEXTURE_SIZE, builtinPixels(kind));
    }
    if (kind === 'buffer') {
      const b = s.buffers.get(source.buffer);
      return b ? { view: b.front.view, w: b.w, h: b.h } : null;
    }
    if (kind === 'image') {
      const entry = images.get(source.grant);
      if (!entry) return null;
      if (!entry.gpu && !entry.gpuMaking) {
        entry.gpuMaking = true;
        createImageBitmap(entry.blob)
          .then((bitmap) => {
            if (!gpuState || gpuState !== s) return;
            const texture = s.device.createTexture({
              size: [bitmap.width, bitmap.height],
              format: 'rgba8unorm',
              usage: TEXTURE_BINDING | TEXTURE_COPY_DST | TEXTURE_RENDER,
            });
            s.device.queue.copyExternalImageToTexture({ source: bitmap }, { texture }, [bitmap.width, bitmap.height]);
            entry.gpu = { texture, view: texture.createView(), w: bitmap.width, h: bitmap.height };
            bitmap.close();
            requestDraw();
          })
          .catch(() => imageFailed(entry));
      }
      return entry.gpu ?? null;
    }
    return null;
  }

  /** The bind groups of a pass for this frame: its uniforms, and what its channels read now. */
  function gpuBindGroups(s, pass, uniformBuffer) {
    const groups = new Map();
    const byChannel = new Map(channelsOf(pass).map((c) => [Number(c.index), c]));
    for (const b of list(pass.program.bindings)) {
      if (!b.used) continue;
      let resource = null;
      if (b.kind === 'uniforms') {
        if (!uniformBuffer) continue;
        resource = { buffer: uniformBuffer };
      } else if (b.kind === 'texture') {
        const c = byChannel.get(Number(b.channel));
        const t = gpuTextureFor(s, c?.source) ?? gpuFixedTexture(s, 'black', 1, 1, new Uint8Array([0, 0, 0, 255]));
        resource = t.view;
      } else {
        resource = gpuSampler(s, byChannel.get(Number(b.channel))?.source);
      }
      const g = Number(b.group);
      if (!groups.has(g)) groups.set(g, []);
      groups.get(g).push({ binding: Number(b.binding), resource });
    }
    const out = [];
    for (const [g, entries] of groups) {
      out.push({ group: g, bindGroup: s.device.createBindGroup({ layout: pass.gpu.pipeline.getBindGroupLayout(g), entries }) });
    }
    return out;
  }

  async function gpuMakePass(s, pass, ticket, errors) {
    const { device } = s;
    const program = pass.program;
    device.pushErrorScope('validation');
    const module = device.createShaderModule({ code: program.source || '' });
    const info = await module.getCompilationInfo();
    const mine = [];
    for (const m of info.messages) {
      mine.push({
        line: m.lineNum || undefined,
        column: m.linePos || undefined,
        message: m.message,
        stage: 'fragment',
        pass: pass.id,
        severity: m.type === 'error' ? 'error' : 'warning',
      });
    }
    await device.popErrorScope();
    errors.push(...mine);
    if (ticket !== generation || mine.some((e) => e.severity === 'error')) return null;
    device.pushErrorScope('validation');
    let pipeline = null;
    try {
      pipeline = await device.createRenderPipelineAsync({
        layout: 'auto',
        vertex: { module, entryPoint: program.vertex_entry || 'vs_main' },
        fragment: {
          module,
          entryPoint: program.fragment_entry || 'fs_main',
          targets: [{ format: pass.id === 'image' ? s.format : s.bufferFormat }],
        },
        primitive: { topology: 'triangle-list' },
      });
    } catch (err) {
      errors.push({ message: String(err?.message ?? err), stage: 'pipeline', pass: pass.id, severity: 'error' });
    }
    const scoped = await device.popErrorScope();
    if (scoped) errors.push({ message: scoped.message, stage: 'pipeline', pass: pass.id, severity: 'error' });
    if (!pipeline || ticket !== generation) return null;
    const fields = list(program.layout?.fields);
    const bytes = Math.max(16, Math.ceil((program.layout?.size ?? 16) / 16) * 16);
    const uniformBuffer = fields.length > 0 ? device.createBuffer({ size: bytes, usage: BUFFER_UNIFORM | BUFFER_COPY_DST }) : null;
    const made = { ...pass, gpu: { pipeline, uniformBuffer, data: new ArrayBuffer(bytes), fields } };
    // Binding once now finds a resource the module reads that the page does not give it.
    device.pushErrorScope('validation');
    try {
      gpuBindGroups(s, made, uniformBuffer);
    } catch (err) {
      errors.push({ message: String(err?.message ?? err), stage: 'pipeline', pass: pass.id, severity: 'error' });
    }
    const bad = await device.popErrorScope();
    if (bad) {
      errors.push({ message: bad.message, stage: 'pipeline', pass: pass.id, severity: 'error' });
      uniformBuffer?.destroy();
      return null;
    }
    return made;
  }

  async function gpuCompile(run, ticket) {
    const s = await gpuInit();
    if (ticket !== generation) return;
    if (!s) {
      report({ ok: false, language: 'wgsl', errors: [{ message: gpuFailure, stage: 'setup', severity: 'error' }] });
      return;
    }
    const errors = [];
    const made = await Promise.all(run.passes.map((pass) => gpuMakePass(s, pass, ticket, errors)));
    if (ticket !== generation) {
      for (const p of made) p?.gpu.uniformBuffer?.destroy();
      return;
    }
    const ok = made.every((p) => p) && !errors.some((e) => e.severity === 'error');
    if (ok) {
      if (s.set) for (const old of s.set.passes) old.gpu.uniformBuffer?.destroy();
      s.set = { passes: made, show: run.show };
      freshBuffers = true;
    } else {
      for (const p of made) p?.gpu.uniformBuffer?.destroy();
    }
    report({ ok, language: 'wgsl', errors });
    if (ok) requestDraw();
  }

  function gpuFillUniforms(s, pass, w, h) {
    const g = pass.gpu;
    if (!g.uniformBuffer) return;
    const f32 = new Float32Array(g.data);
    const i32 = new Int32Array(g.data);
    const u32 = new Uint32Array(g.data);
    for (const f of g.fields) {
      const v = (f.builtin ? builtin(f.builtin, w, h) : undefined) ?? valueOf(pass, f.name, false) ?? [];
      const at = f.offset / 4;
      const n = f.type === 'vec2' ? 2 : f.type === 'vec3' ? 3 : f.type === 'vec4' ? 4 : 1;
      for (let i = 0; i < n; i++) {
        const x = v[i] ?? 0;
        if (f.type === 'int') i32[at + i] = Math.round(x);
        else if (f.type === 'uint') u32[at + i] = Math.max(0, Math.round(x));
        else f32[at + i] = x;
      }
    }
    s.device.queue.writeBuffer(g.uniformBuffer, 0, g.data);
  }

  function gpuRunPass(s, encoder, pass, w, h, view) {
    gpuFillUniforms(s, pass, w, h);
    const groups = gpuBindGroups(s, pass, pass.gpu.uniformBuffer);
    const rp = encoder.beginRenderPass({
      colorAttachments: [{ view, clearValue: { r: 0, g: 0, b: 0, a: 0 }, loadOp: 'clear', storeOp: 'store' }],
    });
    rp.setPipeline(pass.gpu.pipeline);
    for (const { group, bindGroup } of groups) rp.setBindGroup(group, bindGroup);
    rp.draw(3);
    rp.end();
  }

  function gpuShowBuffer(s, encoder, b, view) {
    if (!s.copy) {
      const module = s.device.createShaderModule({ code: GPU_COPY });
      s.copy = s.device.createRenderPipeline({
        layout: 'auto',
        vertex: { module, entryPoint: 'vs_copy' },
        fragment: { module, entryPoint: 'fs_copy', targets: [{ format: s.format }] },
        primitive: { topology: 'triangle-list' },
      });
    }
    const bindGroup = s.device.createBindGroup({
      layout: s.copy.getBindGroupLayout(0),
      entries: [
        { binding: 0, resource: b.front.view },
        { binding: 1, resource: gpuSampler(s, { kind: 'buffer', filter: 'nearest' }) },
      ],
    });
    const rp = encoder.beginRenderPass({
      colorAttachments: [{ view, clearValue: { r: 0, g: 0, b: 0, a: 0 }, loadOp: 'clear', storeOp: 'store' }],
    });
    rp.setPipeline(s.copy);
    rp.setBindGroup(0, bindGroup);
    rp.draw(3);
    rp.end();
  }

  function gpuDraw(advance) {
    const s = gpuState;
    if (!s || !s.set) return;
    const [w, h] = size();
    const runBuffers = advance || freshBuffers;
    const encoder = s.device.createCommandEncoder();
    const screen = s.context.getCurrentTexture().createView();
    for (const pass of s.set.passes) {
      if (pass.id === 'image') {
        gpuRunPass(s, encoder, pass, w, h, screen);
      } else {
        const b = gpuBuffer(s, pass.id, w, h);
        if (!runBuffers) continue;
        gpuRunPass(s, encoder, pass, w, h, b.back.view);
        [b.front, b.back] = [b.back, b.front];
      }
    }
    if (runBuffers) freshBuffers = false;
    if (s.set.show !== 'image') {
      const b = s.buffers.get(s.set.show);
      if (b) gpuShowBuffer(s, encoder, b, screen);
    }
    s.device.queue.submit([encoder.finish()]);
  }

  // Images ----------------------------------------------------------------------------------

  function imageFailed(entry) {
    images.delete(entry.grant);
    proteus.post({ type: 'file', grant: entry.grant, name: entry.name, error: 'The picture did not load. It may be damaged, or in a form the browser cannot read.' });
  }

  proteus.onFile((file) => {
    const grant = String(file.tag ?? file.id);
    const old = images.get(grant);
    if (old?.gl && glState) glState.gl.deleteTexture(old.gl.tex);
    old?.gpu?.texture.destroy();
    if (!file.bytes) {
      images.delete(grant);
      proteus.post({ type: 'file', grant, name: file.name, error: file.error || 'The file could not be read.' });
      return;
    }
    images.set(grant, { grant, name: file.name, blob: new Blob([file.bytes]), gl: null, gpu: null });
    requestDraw();
  });

  // The loop --------------------------------------------------------------------------------

  // A hidden panel has no size. The loop stops then, and starts again when the panel shows.
  let stopped = false;
  const hidden = () => document.hidden || document.body.clientWidth === 0 || document.body.clientHeight === 0;

  function draw(advance) {
    if (language === 'glsl') glDraw(advance);
    else gpuDraw(advance);
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
    draw(playing);
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

  function run(message) {
    generation += 1;
    const passes = list(message.passes)
      .filter((p) => p && typeof p === 'object' && p.program && typeof p.program === 'object')
      .map((p) => ({ id: String(p.id), program: p.program }));
    const next = {
      language: message.language === 'wgsl' ? 'wgsl' : 'glsl',
      show: String(message.show || 'image'),
      passes,
    };
    lastRun = next;
    language = next.language;
    show = next.show;
    glCanvas.style.display = language === 'glsl' ? 'block' : 'none';
    gpuCanvas.style.display = language === 'wgsl' ? 'block' : 'none';
    if (language === 'glsl') {
      glCompile(next);
      requestDraw();
    } else {
      void gpuCompile(next, generation);
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
        run(msg);
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
        // The buffers start again from nothing, as the shader did.
        if (glState) glClearBuffers(glState);
        if (gpuState) gpuClearBuffers(gpuState);
        requestDraw();
        break;
      case 'scale':
        scale = Math.min(2, Math.max(0.1, Number(msg.scale) || 1));
        requestDraw();
        break;
    }
  });
})();
