// The sound of a song: tracks with an instrument, a chain of effects, a fader and a pan,
// all feeding a master chain. The plugin sends the song already resolved:
//
//   { tempo, beats_per_bar, loop: { on, start, end },
//     master: { volume, effects: [device] },
//     tracks: [{ id, volume, pan, mute, solo, instrument: device, effects: [device],
//                clips: [{ start, length, notes: [{ pitch, start, length, velocity }] }] }] }
//
// An audio track's clips hold { start, length, file, offset, gain } instead of notes: file is
// a grant id (see files.js), offset is in seconds and gain in decibels.
//
// A device is { id, patch, params, bypass }, where patch is what patch.js builds, or a Web
// Audio Module, { id, kind, wam: { url }, params, bypass } (see wam-host.js). Times are
// in beats, volumes in decibels. Lists may arrive as empty objects, so list() reads both.

'use strict';

const dbToGain = (db) => (db <= -60 ? 0 : Math.pow(10, db / 20));

/** One instrument on one track. Each note builds its own voice from the patch. */
class Instrument {
  voices = [];

  constructor(ctx, device, out, warn, bpm) {
    this.ctx = ctx;
    this.device = device;
    this.out = out;
    this.warn = warn;
    this.bpm = bpm;
  }

  noteOn(t, key, vel) {
    const patch = this.device.patch;
    let graph = patch.voice;
    let choke;
    const pads = list(patch.pads);
    if (pads.length > 0) {
      const pad = pads.find((p) => p.pitch === key);
      if (!pad) return undefined;
      graph = pad.voice;
      choke = pad.choke || undefined;
    }
    if (!graph) return undefined;
    const scope = noteScope(this.device.params, key, vel, this.bpm());
    const built = build(this.ctx, graph, scope, this.warn);
    built.output.connect(this.out);
    const voice = { built, key, start: t, released: false, choke, done: false };
    if (choke) {
      for (const v of this.voices) if (v.choke === choke && !v.done) this.kill(v, t);
    }
    built.start(t);
    const ends = built.envelopes.map((e) => e.trigger(t, scope));
    if (built.envelopes.length > 0 && built.envelopes.every((e) => e.oneshot)) {
      voice.released = true;
      built.stop(Math.max(...ends) + 0.05);
    }
    const first = built.sources[0];
    if (!first) {
      built.disconnect();
      return undefined;
    }
    first.onended = () => {
      voice.done = true;
      built.disconnect();
      const i = this.voices.indexOf(voice);
      if (i >= 0) this.voices.splice(i, 1);
    };
    this.voices.push(voice);
    const poly = Math.max(1, Math.floor(patch.poly ?? 16));
    const live = this.voices.filter((v) => !v.done && !v.released);
    if (live.length > poly) this.kill(live[0], t);
    return voice;
  }

  noteOff(voice, t) {
    if (!voice || voice.released) return;
    voice.released = true;
    const ends = voice.built.envelopes.map((e) => e.release(t));
    voice.built.stop((ends.length ? Math.max(...ends) : t + 0.01) + 0.05);
  }

  /** Cuts a voice off quickly, without a click. */
  kill(voice, t) {
    voice.released = true;
    const g = voice.built.output.gain;
    g.cancelScheduledValues(t);
    g.setTargetAtTime(0, t, 0.004);
    voice.built.stop(t + 0.03);
  }

  stopAll(t) {
    for (const v of this.voices) if (!v.done) this.kill(v, t);
  }

  update(params) {
    this.device.params = params;
    for (const v of this.voices) if (!v.done) v.built.refresh(params, this.bpm());
  }
}

/** An effect this engine cannot play, such as a native plugin. Its sound passes straight through. */
class Through {
  constructor(ctx) {
    this.input = ctx.createGain();
    this.output = this.input;
    this.scope = {};
  }

  start() {}
  refresh() {}
  stop() {}

  disconnect() {
    this.input.disconnect();
  }
}

/** A chain of effects between an input and an output, rewired as devices come and go. */
class Chain {
  effects = new Map();
  /** The order the effects are wired in now. Null until the first wiring. */
  wired = null;

  constructor(ctx, input, output, warn, bpm) {
    this.ctx = ctx;
    this.input = input;
    this.output = output;
    this.warn = warn;
    this.bpm = bpm;
  }

  update(devices) {
    const keep = new Set();
    const order = [];
    for (const d of devices) {
      const key = JSON.stringify(d.patch) + (d.wam ? d.wam.url : '') + (d.native ? d.native.plugin : '');
      let fx = this.effects.get(d.id);
      if (fx && fx.key !== key) {
        fx.built.stop(0);
        fx.built.disconnect();
        this.effects.delete(d.id);
        fx = undefined;
        this.wired = null;
      }
      if (!fx) {
        if (d.native) this.warn(`${d.kind}: a native plugin, which plays only on the native engine`);
        const built = d.native
          ? new Through(this.ctx)
          : d.wam
          ? new WamEffect(this.ctx, d, this.warn, this.bpm())
          : build(this.ctx, d.patch, noteScope(d.params, 69, 1, this.bpm()), this.warn);
        built.start(this.ctx.currentTime);
        fx = { key, device: d, built };
        this.effects.set(d.id, fx);
        this.wired = null;
      } else if (
        JSON.stringify(fx.device.params) !== JSON.stringify(d.params) ||
        fx.built.scope.bpm !== this.bpm()
      ) {
        fx.built.refresh(d.params, this.bpm());
      }
      fx.device = d;
      keep.add(d.id);
      if (!d.bypass) order.push(fx);
    }
    for (const [id, fx] of this.effects) {
      if (keep.has(id)) continue;
      fx.built.stop(0);
      fx.built.disconnect();
      this.effects.delete(id);
      this.wired = null;
    }
    const wiring = order.map((fx) => fx.device.id).join('|');
    if (wiring === this.wired) return;
    this.wired = wiring;
    this.input.disconnect();
    for (const fx of this.effects.values()) fx.built.output.disconnect();
    let from = this.input;
    for (const fx of order) {
      from.connect(fx.built.input);
      from = fx.built.output;
    }
    from.connect(this.output);
  }

  setParam(id, key, value) {
    const fx = this.effects.get(id);
    if (!fx) return false;
    fx.device.params = { ...fx.device.params, [key]: value };
    fx.built.refresh(fx.device.params, this.bpm());
    return true;
  }

  stop() {
    for (const fx of this.effects.values()) {
      fx.built.stop(0);
      fx.built.disconnect();
    }
    this.effects.clear();
  }
}

class TrackNode {
  input;
  fader;
  panner;
  meter;
  chain;
  instrument = null;
  instKey = '';
  spec;
  events = [];
  audio = [];

  constructor(ctx, master, warn, bpm) {
    this.ctx = ctx;
    this.warn = warn;
    this.bpm = bpm;
    this.input = ctx.createGain();
    this.fader = ctx.createGain();
    this.panner = ctx.createStereoPanner();
    this.meter = ctx.createAnalyser();
    this.meter.fftSize = 512;
    this.chain = new Chain(ctx, this.input, this.fader, warn, bpm);
    this.fader.connect(this.panner);
    this.panner.connect(this.meter);
    this.panner.connect(master);
  }

  update(spec) {
    this.spec = spec;
    const inst = spec.instrument ?? null;
    const key = inst ? inst.id + JSON.stringify(inst.patch) + (inst.wam ? inst.wam.url : '') + (inst.native ? inst.native.plugin : '') : '';
    if (key !== this.instKey) {
      this.instrument?.stopAll(this.ctx.currentTime);
      this.instrument?.destroy?.();
      if (inst?.native) this.warn(`${inst.kind}: a native plugin, which plays only on the native engine`);
      this.instrument = !inst || inst.native
        ? null
        : inst.wam
          ? new WamInstrument(this.ctx, inst, this.input, this.warn)
          : new Instrument(this.ctx, inst, this.input, this.warn, this.bpm);
      this.instKey = key;
    } else if (this.instrument && inst) {
      if (JSON.stringify(this.instrument.device.params) !== JSON.stringify(inst.params)) {
        this.instrument.update(inst.params);
      }
      this.instrument.device = inst;
    }
    this.chain.update(list(spec.effects));
    this.panner.pan.setTargetAtTime(Math.max(-1, Math.min(1, spec.pan || 0)), this.ctx.currentTime, 0.01);
    const events = [];
    const audio = [];
    for (const clip of list(spec.clips)) {
      if (clip.file) {
        audio.push(clip);
        FILES.want(clip.file);
        continue;
      }
      for (const n of list(clip.notes)) {
        if (n.start < 0 || n.start >= clip.length || n.length <= 0) continue;
        const end = Math.min(n.start + n.length, clip.length);
        events.push({
          beat: clip.start + n.start,
          dur: end - n.start,
          pitch: n.pitch,
          vel: n.velocity ?? 0.8,
        });
      }
    }
    events.sort((a, b) => a.beat - b.beat || a.pitch - b.pitch);
    this.events = events;
    audio.sort((a, b) => a.start - b.start);
    this.audio = audio;
  }

  setGain(audible) {
    const g = audible && !this.spec.mute ? dbToGain(this.spec.volume || 0) : 0;
    this.fader.gain.setTargetAtTime(g, this.ctx.currentTime, 0.01);
  }

  stop() {
    this.instrument?.stopAll(this.ctx.currentTime);
    this.instrument?.destroy?.();
    this.chain.stop();
    this.input.disconnect();
    this.fader.disconnect();
    this.panner.disconnect();
  }
}

/** The index of the first event at or after a beat. */
function firstAt(events, beat) {
  let lo = 0;
  let hi = events.length;
  while (lo < hi) {
    const mid = (lo + hi) >> 1;
    if (events[mid].beat < beat) lo = mid + 1;
    else hi = mid;
  }
  return lo;
}

class Mixer {
  tracks = new Map();
  masterIn;
  masterOut;
  masterChain;
  metronome;
  song = {
    tempo: 120,
    beats_per_bar: 4,
    loop: { on: false, start: 0, end: 16 },
    master: { volume: 0, effects: [] },
    tracks: [],
  };
  /** Audio clips playing now, so Stop can silence them. */
  sounding = new Set();

  constructor(ctx, warn) {
    this.ctx = ctx;
    this.warn = warn;
    this.masterIn = ctx.createGain();
    this.masterOut = ctx.createGain();
    this.masterChain = new Chain(ctx, this.masterIn, this.masterOut, warn, () => this.song.tempo || 120);
    this.masterOut.connect(ctx.destination);
    this.metronome = ctx.createGain();
    this.metronome.gain.value = 0.5;
    this.metronome.connect(ctx.destination);
  }

  get spb() {
    return 60 / Math.max(20, Math.min(400, this.song.tempo || 120));
  }

  load(song) {
    this.song = song;
    const seen = new Set();
    for (const spec of list(song.tracks)) {
      let t = this.tracks.get(spec.id);
      if (!t) {
        t = new TrackNode(this.ctx, this.masterIn, this.warn, () => this.song.tempo || 120);
        this.tracks.set(spec.id, t);
      }
      t.update(spec);
      seen.add(spec.id);
    }
    for (const [id, t] of this.tracks) {
      if (seen.has(id)) continue;
      t.stop();
      this.tracks.delete(id);
    }
    this.masterChain.update(list(song.master?.effects));
    this.masterOut.gain.setTargetAtTime(dbToGain(song.master?.volume ?? 0), this.ctx.currentTime, 0.01);
    this.applyGains();
  }

  applyGains() {
    let solo = false;
    for (const t of this.tracks.values()) if (t.spec.solo) solo = true;
    for (const t of this.tracks.values()) t.setGain(!solo || t.spec.solo);
  }

  setMix(trackId, key, value) {
    if (trackId === 'master') {
      if (key === 'volume') {
        this.song.master.volume = Number(value) || 0;
        this.masterOut.gain.setTargetAtTime(dbToGain(this.song.master.volume), this.ctx.currentTime, 0.01);
      }
      return;
    }
    const t = this.tracks.get(trackId);
    if (!t) return;
    if (key === 'volume') t.spec.volume = Number(value) || 0;
    else if (key === 'pan') {
      t.spec.pan = Number(value) || 0;
      t.panner.pan.setTargetAtTime(t.spec.pan, this.ctx.currentTime, 0.01);
    } else if (key === 'mute') t.spec.mute = value === true;
    else if (key === 'solo') t.spec.solo = value === true;
    this.applyGains();
  }

  setParam(deviceId, key, value) {
    if (this.masterChain.setParam(deviceId, key, value)) return;
    for (const t of this.tracks.values()) {
      if (t.instrument && t.instrument.device.id === deviceId) {
        t.instrument.update({ ...t.instrument.device.params, [key]: value });
        return;
      }
      if (t.chain.setParam(deviceId, key, value)) return;
    }
  }

  /**
   * Plays every note and audio clip that starts in [from, to), where `from` falls at time
   * `t0`. Notes and clips are cut at `cut`, the loop's end while it loops.
   */
  schedule(from, to, t0, cut, metronome) {
    const spb = this.spb;
    const at = (beat) => t0 + (beat - from) * spb;
    for (const track of this.tracks.values()) {
      const inst = track.instrument;
      if (inst) {
        const ev = track.events;
        for (let i = firstAt(ev, from); i < ev.length && ev[i].beat < to; i++) {
          const e = ev[i];
          const voice = inst.noteOn(at(e.beat), e.pitch, e.vel);
          inst.noteOff(voice, at(Math.min(e.beat + e.dur, cut)));
        }
      }
      for (const clip of track.audio) {
        if (clip.start >= from && clip.start < to) {
          this.playAudio(track, clip, at(clip.start), 0, Math.min(clip.start + clip.length, cut) - clip.start);
        }
      }
    }
    if (metronome) {
      for (let b = Math.ceil(from - 1e-9); b < to; b++)
        this.click(at(b), b % (this.song.beats_per_bar || 4) === 0);
    }
  }

  /** Starts the audio clips already under way at a beat, from the right place in each. */
  chase(beat, t, cut) {
    for (const track of this.tracks.values()) {
      for (const clip of track.audio) {
        if (clip.start < beat && beat < clip.start + clip.length) {
          this.playAudio(track, clip, t, beat - clip.start, Math.min(clip.start + clip.length, cut) - beat);
        }
      }
    }
  }

  playAudio(track, clip, t, into, beats) {
    const buf = FILES.buffer(clip.file);
    if (!buf || beats <= 0) return;
    const offset = (clip.offset ?? 0) + into * this.spb;
    if (offset >= buf.duration) return;
    const src = this.ctx.createBufferSource();
    src.buffer = buf;
    const g = this.ctx.createGain();
    g.gain.value = dbToGain(clip.gain ?? 0);
    src.connect(g);
    g.connect(track.input);
    src.start(t, offset, beats * this.spb);
    this.sounding.add(src);
    src.onended = () => {
      this.sounding.delete(src);
      g.disconnect();
    };
  }

  click(t, accent) {
    const osc = this.ctx.createOscillator();
    const g = this.ctx.createGain();
    osc.frequency.value = accent ? 1760 : 1320;
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(accent ? 0.6 : 0.35, t + 0.002);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 0.06);
    osc.connect(g);
    g.connect(this.metronome);
    osc.start(t);
    osc.stop(t + 0.07);
    osc.onended = () => g.disconnect();
  }

  /** Silences every note and clip, at once. */
  silence() {
    const now = this.ctx.currentTime;
    for (const t of this.tracks.values()) t.instrument?.stopAll(now);
    for (const src of this.sounding) {
      try {
        src.stop(now);
      } catch {
        // It stopped already.
      }
    }
    this.sounding.clear();
  }

  /** Every device that plays as a Web Audio Module, with what plays it. */
  modules() {
    const out = [];
    const add = (device, player) => {
      if (device?.wam && player) out.push({ device, player });
    };
    for (const fx of this.masterChain.effects.values()) add(fx.device, fx.built);
    for (const t of this.tracks.values()) {
      add(t.instrument?.device, t.instrument);
      for (const fx of t.chain.effects.values()) add(fx.device, fx.built);
    }
    return out;
  }

  /** Where the song's last clip ends, in beats. */
  end() {
    let end = 0;
    for (const t of this.tracks.values()) {
      for (const c of list(t.spec.clips)) end = Math.max(end, c.start + c.length);
    }
    return end;
  }
}
