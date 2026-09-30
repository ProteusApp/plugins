// Builds Web Audio graphs from patches. A patch is plain data written in Lua by a device
// plugin: a list of nodes and the wires between them. The same patch builds once per note
// for an instrument's voice, and once per track for an effect.
//
// Each node type below turns into one or two Web Audio nodes. A field that names an
// AudioParam takes an expression (see expr.js), and the engine works it out again whenever
// a parameter it reads changes. A wire is a string: `'osc > amp'` carries sound, and
// `'env > amp.gain'` moves a parameter, added to the value the parameter already has.

'use strict';

/** An envelope: a 0-to-1 curve shaped by attack, decay, sustain and release. */
class Envelope {
  t0 = 0;
  a = 0.01;
  d = 0.1;
  s = 1;
  r = 0.1;
  oneshot;

  constructor(source, spec) {
    this.source = source;
    this.spec = spec;
    this.oneshot = spec.oneshot === true;
  }

  trigger(t, scope) {
    const num = (key, fallback) => Math.max(0, field(this.spec[key], fallback).fn(scope));
    this.t0 = t;
    this.a = Math.max(0.001, num('a', 0.005));
    this.d = Math.max(0.001, num('d', 0.1));
    this.s = this.oneshot ? 0 : Math.min(1, num('s', 1));
    this.r = Math.max(0.005, num('r', 0.05));
    const o = this.source.offset;
    o.cancelScheduledValues(t);
    o.setValueAtTime(0, t);
    o.linearRampToValueAtTime(1, t + this.a);
    o.setTargetAtTime(this.s, t + this.a, this.d / 5);
    return t + this.a + this.d;
  }

  /** The curve's value at a time after the trigger, worked out rather than read back. */
  valueAt(t) {
    const since = t - this.t0;
    if (since <= 0) return 0;
    if (since < this.a) return since / this.a;
    return this.s + (1 - this.s) * Math.exp(-(since - this.a) / (this.d / 5));
  }

  /** Starts the release. Returns when the curve has faded out. */
  release(t) {
    const o = this.source.offset;
    o.cancelScheduledValues(t);
    o.setValueAtTime(this.valueAt(t), t);
    o.setTargetAtTime(0, t, this.r / 5);
    return t + this.r;
  }
}

/** A built graph: its nodes, the parameters it keeps up to date, and what it plays. */
class Built {
  nodes = new Map();
  params = new Map();
  bindings = [];
  refreshers = [];
  sources = [];
  envelopes = [];
  input;
  output;

  constructor(ctx, scope) {
    this.ctx = ctx;
    this.scope = scope;
    this.input = ctx.createGain();
    this.output = ctx.createGain();
    this.nodes.set('in', this.input);
    this.nodes.set('out', this.output);
  }

  /** Works out every live field again after a parameter changed. */
  refresh(params, bpm = this.scope.bpm) {
    this.scope = { ...this.scope, params, bpm };
    const now = this.ctx.currentTime;
    for (const b of this.bindings) {
      if (!b.live) continue;
      const v = b.fn(this.scope);
      if (Number.isFinite(v)) b.param.setTargetAtTime(v, now, 0.012);
    }
    for (const r of this.refreshers) r.apply(this.scope, false);
  }

  start(t) {
    for (const s of this.sources) s.start(t);
  }

  stop(t) {
    for (const s of this.sources) {
      try {
        s.stop(t);
      } catch {
        // A source that never started cannot stop, and needs nothing.
      }
    }
  }

  disconnect() {
    for (const n of this.nodes.values()) n.disconnect();
  }
}

let noiseBuffer = null;

function noise(ctx) {
  if (noiseBuffer && noiseBuffer.sampleRate === ctx.sampleRate) return noiseBuffer;
  const buf = ctx.createBuffer(1, ctx.sampleRate * 2, ctx.sampleRate);
  const data = buf.getChannelData(0);
  for (let i = 0; i < data.length; i++) data[i] = Math.random() * 2 - 1;
  noiseBuffer = buf;
  return buf;
}

const pulseWaves = new Map();

/** A pulse wave with a given duty cycle, the classic sound of old game consoles. */
function pulse(ctx, duty) {
  const d = Math.min(0.95, Math.max(0.05, duty));
  const key = `${ctx.sampleRate}:${d.toFixed(3)}`;
  const hit = pulseWaves.get(key);
  if (hit && ctx instanceof AudioContext) return hit;
  const n = 64;
  const real = new Float32Array(n);
  const imag = new Float32Array(n);
  for (let k = 1; k < n; k++) {
    real[k] = (2 / (k * Math.PI)) * Math.sin(Math.PI * k * d);
  }
  const wave = ctx.createPeriodicWave(real, imag);
  if (ctx instanceof AudioContext) pulseWaves.set(key, wave);
  return wave;
}

function setWave(ctx, osc, shape, duty) {
  if (shape === 'pulse') osc.setPeriodicWave(pulse(ctx, duty));
  else if (shape === 'sine' || shape === 'square' || shape === 'sawtooth' || shape === 'triangle')
    osc.type = shape;
  else osc.type = 'sine';
}

/** A reverb's impulse: noise that dies away, a little different on each side. */
function impulse(ctx, seconds, decay) {
  const len = Math.max(1, Math.floor(ctx.sampleRate * Math.min(10, Math.max(0.1, seconds))));
  const buf = ctx.createBuffer(2, len, ctx.sampleRate);
  for (let ch = 0; ch < 2; ch++) {
    const data = buf.getChannelData(ch);
    for (let i = 0; i < len; i++)
      data[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / len, Math.max(0.1, decay));
  }
  return buf;
}

/** A waveshaper curve: soft and hard clipping, folding, and a staircase that crushes bits. */
function curve(shape, amount) {
  const n = 2048;
  const out = new Float32Array(n);
  const k = Math.max(0, amount);
  for (let i = 0; i < n; i++) {
    const x = (i / (n - 1)) * 2 - 1;
    let y;
    if (shape === 'hard') y = Math.max(-1, Math.min(1, x * (1 + k * 20)));
    else if (shape === 'fold') y = Math.sin(x * (1 + k * 8) * (Math.PI / 2));
    else if (shape === 'crush') {
      const steps = Math.max(2, Math.round(Math.pow(2, 8 - k * 7)));
      y = Math.round(x * steps) / steps;
    } else y = Math.tanh(x * (1 + k * 20)) / Math.tanh(1 + k * 20);
    out[i] = y;
  }
  return out;
}

/** Each node type, and the fields of it that wires can reach. */
const MAKERS = {
  osc: {
    make(b, spec, bind) {
      const osc = b.ctx.createOscillator();
      bind(osc.frequency, 'freq', b.scope.freq);
      bind(osc.detune, 'detune', 0);
      let last = '';
      b.refreshers.push({
        apply(scope) {
          const shape = textField(spec.wave, scope.params, 'sine');
          const duty = field(spec.duty, 0.5).fn(scope);
          const key = `${shape}:${duty}`;
          if (key !== last) setWave(b.ctx, osc, shape, duty);
          last = key;
        },
      });
      b.sources.push(osc);
      return osc;
    },
    params: { freq: (n) => n.frequency, detune: (n) => n.detune },
  },
  noise: {
    make(b) {
      const src = b.ctx.createBufferSource();
      src.buffer = noise(b.ctx);
      src.loop = true;
      src.loopEnd = src.buffer.duration;
      b.sources.push(src);
      return src;
    },
    params: { rate: (n) => n.playbackRate },
  },
  // An audio file the user picked, named by the file parameter's grant id. It is silent
  // until the file arrives, and the next note plays it.
  sample: {
    make(b, spec, bind) {
      const src = b.ctx.createBufferSource();
      bind(src.playbackRate, 'rate', 1);
      bind(src.detune, 'detune', 0);
      const id = textField(spec.file, b.scope.params, '');
      const buf = id ? FILES.buffer(id) : undefined;
      if (id && !buf) FILES.want(id);
      if (buf) {
        src.buffer = buf;
        src.loop = flagField(spec.loop, b.scope.params);
      }
      b.sources.push(src);
      return src;
    },
    params: { rate: (n) => n.playbackRate, detune: (n) => n.detune },
  },
  gain: {
    make(b, _spec, bind) {
      const g = b.ctx.createGain();
      bind(g.gain, 'gain', 1);
      return g;
    },
    params: { gain: (n) => n.gain },
  },
  filter: {
    make(b, spec, bind) {
      const f = b.ctx.createBiquadFilter();
      bind(f.frequency, 'freq', 1000);
      bind(f.Q, 'q', 0.7);
      bind(f.gain, 'gain', 0);
      bind(f.detune, 'detune', 0);
      b.refreshers.push({
        apply(scope) {
          const mode = textField(spec.mode, scope.params, 'lowpass');
          if (f.type !== mode) {
            try {
              f.type = mode;
            } catch {
              f.type = 'lowpass';
            }
          }
        },
      });
      return f;
    },
    params: { freq: (n) => n.frequency, q: (n) => n.Q, gain: (n) => n.gain, detune: (n) => n.detune },
  },
  delay: {
    make(b, _spec, bind) {
      const d = b.ctx.createDelay(4);
      bind(d.delayTime, 'time', 0.25);
      return d;
    },
    params: { time: (n) => n.delayTime },
  },
  pan: {
    make(b, _spec, bind) {
      const p = b.ctx.createStereoPanner();
      bind(p.pan, 'pan', 0);
      return p;
    },
    params: { pan: (n) => n.pan },
  },
  compressor: {
    make(b, _spec, bind) {
      const c = b.ctx.createDynamicsCompressor();
      bind(c.threshold, 'threshold', -24);
      bind(c.knee, 'knee', 12);
      bind(c.ratio, 'ratio', 4);
      bind(c.attack, 'attack', 0.01);
      bind(c.release, 'release', 0.2);
      return c;
    },
    params: { threshold: (n) => n.threshold, ratio: (n) => n.ratio },
  },
  reverb: {
    make(b, spec) {
      const conv = b.ctx.createConvolver();
      let last = '';
      b.refreshers.push({
        apply(scope) {
          const seconds = field(spec.seconds, 2).fn(scope);
          const decay = field(spec.decay, 3).fn(scope);
          const key = `${seconds.toFixed(2)}:${decay.toFixed(2)}`;
          if (key !== last) conv.buffer = impulse(b.ctx, seconds, decay);
          last = key;
        },
      });
      return conv;
    },
    params: {},
  },
  shaper: {
    make(b, spec) {
      const ws = b.ctx.createWaveShaper();
      ws.oversample = '4x';
      let last = '';
      b.refreshers.push({
        apply(scope) {
          const shape = textField(spec.curve, scope.params, 'soft');
          const amount = field(spec.amount, 0.3).fn(scope);
          const key = `${shape}:${amount.toFixed(3)}`;
          if (key !== last) ws.curve = curve(shape, amount);
          last = key;
        },
      });
      return ws;
    },
    params: {},
  },
  lfo: {
    make(b, spec, bind) {
      const osc = b.ctx.createOscillator();
      const depth = b.ctx.createGain();
      osc.connect(depth);
      bind(osc.frequency, 'rate', 4);
      bind(depth.gain, 'depth', 0);
      b.refreshers.push({
        apply(scope) {
          setWave(b.ctx, osc, textField(spec.wave, scope.params, 'sine'), 0.5);
        },
      });
      b.sources.push(osc);
      depth.lfoRate = osc.frequency;
      return depth;
    },
    params: { rate: (n) => n.lfoRate, depth: (n) => n.gain },
  },
  env: {
    make(b, spec, bind) {
      const src = b.ctx.createConstantSource();
      src.offset.value = 0;
      const amount = b.ctx.createGain();
      src.connect(amount);
      bind(amount.gain, 'amount', 1);
      b.envelopes.push(new Envelope(src, spec));
      b.sources.push(src);
      return amount;
    },
    params: { amount: (n) => n.gain },
  },
  const: {
    make(b, _spec, bind) {
      const src = b.ctx.createConstantSource();
      bind(src.offset, 'value', 0);
      b.sources.push(src);
      return src;
    },
    params: { value: (n) => n.offset },
  },
};

const NODE_TYPES = Object.keys(MAKERS);

/** The list inside a Lua table that crossed as JSON: `{}` when it was empty. */
function list(value) {
  if (Array.isArray(value)) return value;
  if (value && typeof value === 'object') return Object.values(value);
  return [];
}

/** Builds a graph. Mistakes in the patch are reported through `warn` and skipped. */
function build(ctx, graph, scope, warn) {
  const b = new Built(ctx, scope);
  for (const spec of list(graph.nodes)) {
    const kind = MAKERS[spec.type];
    if (!kind || !spec.id || spec.id === 'in' || spec.id === 'out') {
      warn(`skipped node ${spec.id ?? '?'}: unknown type ${spec.type}`);
      continue;
    }
    try {
      const node = kind.make(b, spec, (param, key, fallback) => {
        const f = field(spec[key], fallback);
        const v = f.fn(scope);
        if (Number.isFinite(v)) param.setValueAtTime(v, 0);
        b.bindings.push({ param, fn: f.fn, live: f.live });
      });
      b.nodes.set(spec.id, node);
      for (const [name, get] of Object.entries(kind.params)) {
        const p = get(node);
        if (p) b.params.set(`${spec.id}.${name}`, p);
      }
    } catch (err) {
      warn(`node ${spec.id}: ${String(err instanceof Error ? err.message : err)}`);
    }
  }
  for (const r of b.refreshers) r.apply(scope, true);
  for (const wire of list(graph.connect)) {
    const m = /^\s*([\w.]+)\s*>\s*([\w.]+)\s*$/.exec(String(wire));
    if (!m) {
      warn(`skipped wire "${wire}"`);
      continue;
    }
    const from = b.nodes.get(m[1]);
    const toNode = b.nodes.get(m[2]);
    const toParam = b.params.get(m[2]);
    if (!from || (!toNode && !toParam)) {
      warn(`skipped wire "${wire}": no such node or field`);
      continue;
    }
    if (toParam) from.connect(toParam);
    else from.connect(toNode);
  }
  return b;
}

/** A note number as hertz. */
function noteFreq(key) {
  return 440 * Math.pow(2, (key - 69) / 12);
}

function noteScope(params, key, vel, bpm) {
  return { params, key, vel, bpm, freq: noteFreq(key) };
}
