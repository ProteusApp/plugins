// Web Audio Modules: instruments and effects that plugins bring as modules, instead of patches.
// A device names its module under the page's mounts, such as
// `_/wam.basics/wam/polysynth/index.js`. The engine makes one instance for each device, plays
// it notes as MIDI events on the audio clock, and sets its parameters by id. An instance loads
// in the background, so the device stays silent, or passes its sound straight through, until
// it is ready.
//
// Messages to the plugin:
//   { type: 'wam_params', device, info }    a module's parameters, once, for its device id
//
// A module may keep more than its parameters, such as a sample or a preset of its own. The
// page asks it with getState and gives it back with setState, as text the song keeps (see
// wam-state.js). An instance starts from the state the page holds for its device, then takes
// the song's values.

'use strict';

/** The saved state of each device, by device id: what the plugin restored, or a module said. */
const DEVICE_STATES = new Map();

/** Resolves to `fallback` when `promise` takes longer than `ms`, as a module that went may. */
function within(promise, ms, fallback) {
  return Promise.race([promise, new Promise((resolve) => setTimeout(() => resolve(fallback), ms))]);
}

/**
 * Gives a ready instance the state the page holds for its device, then the song's values, so
 * they stay the ones it plays. A state it cannot take leaves it as it is, with a warning.
 */
async function restoreWam(node, device, warn) {
  const text = DEVICE_STATES.get(device.id);
  if (text) {
    try {
      await node.setState(decodeWamState(text));
    } catch (err) {
      warn(`${device.kind}: its saved state did not load: ${err?.message ?? err}`);
    }
  }
  node.setParameterValues(wamValues(device.params));
}

/** What a ready instance would save now, as text, or undefined. */
async function saveWam(node) {
  return encodeWamState(await within(node.getState(), 2000, undefined));
}

/** Each audio context's host group, set up once. */
const WAM_GROUPS = new WeakMap();
/** The instances still loading in each context, so a render can wait for them. */
const WAM_PENDING = new WeakMap();
/** Device ids whose parameters went to the plugin already. */
const WAM_REPORTED = new Set();
/** Each context's instances that are ready. */
const WAM_NODES = new WeakMap();

/** The SDK, once its module script has run. */
function loadWamSdk() {
  if (window.WAM_SDK) return Promise.resolve(window.WAM_SDK);
  return new Promise((resolve) => addEventListener('wam-sdk', () => resolve(window.WAM_SDK), { once: true }));
}

function wamGroup(ctx) {
  if (!WAM_GROUPS.has(ctx)) WAM_GROUPS.set(ctx, loadWamSdk().then((sdk) => sdk.initializeWamHost(ctx)));
  return WAM_GROUPS.get(ctx).then(([groupId]) => groupId);
}

/** Loads a device's module and makes an instance of it in `ctx`. */
function createWam(ctx, device) {
  const made = (async () => {
    const groupId = await wamGroup(ctx);
    const mod = await (await loadWamSdk()).load('./' + device.wam.url);
    return mod.default.createInstance(groupId, ctx, {});
  })();
  if (!WAM_NODES.has(ctx)) WAM_NODES.set(ctx, new Set());
  wamPending(ctx, made);
  made.then((instance) => WAM_NODES.get(ctx).add(instance.audioNode)).catch(() => {});
  return made;
}

/** Counts `promise` as loading in `ctx` until it settles, so a render waits for it. */
function wamPending(ctx, promise) {
  if (!WAM_PENDING.has(ctx)) WAM_PENDING.set(ctx, new Set());
  const pending = WAM_PENDING.get(ctx);
  pending.add(promise);
  promise.finally(() => pending.delete(promise)).catch(() => {});
}

/** Waits until every instance `ctx` started loading is ready, or failed. */
async function wamSettled(ctx) {
  const pending = WAM_PENDING.get(ctx);
  while (pending && pending.size > 0) await Promise.allSettled([...pending]);
}

/**
 * Waits until every instance in `ctx` has taken the events and values sent to it so far. An
 * offline render runs faster than messages reach the audio thread, so it waits for each
 * instance to answer one question, which it does after everything sent before it.
 */
async function wamFlush(ctx) {
  await Promise.allSettled([...(WAM_NODES.get(ctx) ?? [])].map((node) => node.getParameterValues(false)));
}

/** A device's values as a module takes them: numbers by parameter id. */
function wamValues(params) {
  const out = {};
  for (const [id, v] of Object.entries(params || {})) {
    if (typeof v === 'number' || typeof v === 'boolean') out[id] = { id, value: Number(v), normalized: false };
  }
  return out;
}

/** Tells the plugin a module's parameters, once for each device id. */
function reportWam(ctx, device, node) {
  if (!(ctx instanceof AudioContext) || !device.kind || WAM_REPORTED.has(device.kind)) return;
  WAM_REPORTED.add(device.kind);
  void node.getParameterInfo().then((info) => {
    const plain = {};
    for (const [id, p] of Object.entries(info || {})) {
      plain[id] = {
        type: p.type,
        label: p.label,
        defaultValue: p.defaultValue,
        minValue: p.minValue,
        maxValue: p.maxValue,
        exponent: p.exponent,
        choices: p.choices ? [...p.choices] : undefined,
        units: p.units,
      };
    }
    proteus.post({ type: 'wam_params', device: device.kind, info: plain });
  });
}

const midi = (node, time, bytes) => node.scheduleEvents({ type: 'wam-midi', time, data: { bytes } });

/** An instrument that is a module: notes go to it as MIDI events. */
class WamInstrument {
  node = null;

  constructor(ctx, device, out, warn) {
    this.ctx = ctx;
    this.device = device;
    this.warn = warn;
    this.ready = createWam(ctx, device)
      .then(async (instance) => {
        await restoreWam(instance.audioNode, device, warn);
        this.node = instance.audioNode;
        this.node.connect(out);
        reportWam(ctx, device, this.node);
      })
      .catch((err) => warn(`${device.kind}: ${err?.message ?? err}`));
    // Ready once its state is in, which a render waits for.
    wamPending(ctx, this.ready);
  }

  /** Takes the state the page now holds for this device. */
  restore() {
    return this.ready.then(() => this.node && restoreWam(this.node, this.device, this.warn));
  }

  noteOn(t, key, vel) {
    if (!this.node) return undefined;
    midi(this.node, t, [0x90, key & 127, Math.max(1, Math.min(127, Math.round(vel * 127)))]);
    return { key: key & 127 };
  }

  noteOff(voice, t) {
    if (voice && this.node) midi(this.node, t, [0x80, voice.key, 0]);
  }

  stopAll(t) {
    if (this.node) midi(this.node, t, [0xb0, 123, 0]);
  }

  update(params) {
    this.device.params = params;
    this.node?.setParameterValues(wamValues(params));
  }

  destroy() {
    try {
      this.node?.disconnect();
      this.node?.destroy?.();
    } catch {
      // It went already.
    }
  }
}

/** An effect that is a module. Its sound passes straight through until the module is ready. */
class WamEffect {
  node = null;

  constructor(ctx, device, warn, bpm) {
    this.input = ctx.createGain();
    this.output = ctx.createGain();
    this.input.connect(this.output);
    this.scope = { bpm };
    this.device = device;
    this.warn = warn;
    this.ready = createWam(ctx, device)
      .then(async (instance) => {
        await restoreWam(instance.audioNode, device, warn);
        this.node = instance.audioNode;
        this.input.disconnect();
        this.input.connect(this.node);
        this.node.connect(this.output);
        reportWam(ctx, device, this.node);
      })
      .catch((err) => warn(`${device.kind}: ${err?.message ?? err}`));
    // Ready once its state is in, which a render waits for.
    wamPending(ctx, this.ready);
  }

  /** Takes the state the page now holds for this device. */
  restore() {
    return this.ready.then(() => this.node && restoreWam(this.node, this.device, this.warn));
  }

  start() {}

  refresh(params, bpm) {
    this.scope.bpm = bpm;
    this.device.params = params;
    this.node?.setParameterValues(wamValues(params));
  }

  stop() {
    try {
      this.node?.disconnect();
      this.node?.destroy?.();
    } catch {
      // It went already.
    }
  }

  disconnect() {
    this.output.disconnect();
  }
}
