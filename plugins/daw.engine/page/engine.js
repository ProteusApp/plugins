// The live engine: a Mixer on the page's AudioContext, plus the transport that plays it.
//
// Lua cannot keep time to the millisecond, so the transport lives here. Every 25 ms it
// looks 150 ms ahead and hands the Web Audio clock each note that starts in that stretch.
// The plugin sends the whole song whenever it changes, and the next stretch plays the new song.

'use strict';

const TICK_MS = 25;
const AHEAD = 0.15;

class Engine {
  ctx;
  mixer;
  timer;
  playing = false;
  recording = false;
  metronome = false;
  cursorBeat = 0;
  cursorTime = 0;
  anchors = [];
  stopBeat = 0;
  liveTrack = '';
  held = new Map();
  recHeld = new Map();
  recorded = [];
  levelsNow = new Map();
  masterLevels = [0, 0];
  buf = new Float32Array(512);
  splitL;
  splitR;

  constructor(emit) {
    this.emit = emit;
    this.ctx = new AudioContext({ latencyHint: 'interactive' });
    this.mixer = new Mixer(this.ctx, (msg) => emit('warning', { message: msg }));
    const split = this.ctx.createChannelSplitter(2);
    this.splitL = this.ctx.createAnalyser();
    this.splitR = this.ctx.createAnalyser();
    this.splitL.fftSize = 512;
    this.splitR.fftSize = 512;
    this.mixer.masterOut.connect(split);
    split.connect(this.splitL, 0);
    split.connect(this.splitR, 1);
    this.ctx.onstatechange = () => emit('context', { state: this.ctx.state });
  }

  load(song) {
    const oldSpb = this.mixer.spb;
    this.mixer.load(song);
    if (this.playing && this.mixer.spb !== oldSpb) {
      this.anchors.push({ time: this.cursorTime, beat: this.cursorBeat, spb: this.mixer.spb });
    }
  }

  // Transport -------------------------------------------------------------------------------

  loopRange() {
    const loop = this.mixer.song.loop;
    if (!loop || !loop.on || !(loop.end > loop.start)) return null;
    return [loop.start, loop.end];
  }

  play(from) {
    void this.ctx.resume();
    if (this.playing) this.stop(true);
    const start = typeof from === 'number' && from >= 0 ? from : this.stopBeat;
    this.playing = true;
    this.cursorBeat = start;
    this.cursorTime = this.ctx.currentTime + 0.05;
    this.anchors = [{ time: this.cursorTime, beat: start, spb: this.mixer.spb }];
    const loop = this.loopRange();
    this.mixer.chase(start, this.cursorTime, loop && start < loop[1] ? loop[1] : Infinity);
    this.tick();
    this.timer = window.setInterval(() => this.tick(), TICK_MS);
    this.emit('transport', { playing: true, beat: start });
  }

  stop(keepPlace = false) {
    if (this.playing) {
      this.stopBeat = keepPlace ? this.position() : this.stopBeat;
      if (this.recording) this.finishHeld(this.position());
    }
    this.playing = false;
    if (this.timer !== undefined) window.clearInterval(this.timer);
    this.timer = undefined;
    this.mixer.silence();
    this.emit('transport', { playing: false, beat: this.stopBeat });
  }

  seek(beat) {
    const b = Math.max(0, beat || 0);
    this.stopBeat = b;
    if (this.playing) this.play(b);
    else this.emit('transport', { playing: false, beat: b });
  }

  position() {
    if (!this.playing) return this.stopBeat;
    const now = this.ctx.currentTime;
    let a = this.anchors[0];
    for (const x of this.anchors) if (x.time <= now) a = x;
    return Math.max(0, a.beat + (now - a.time) / a.spb);
  }

  tick() {
    if (!this.playing) return;
    const horizon = this.ctx.currentTime + AHEAD;
    let guard = 0;
    while (this.cursorTime < horizon && guard++ < 64) {
      const spb = this.mixer.spb;
      const loop = this.loopRange();
      const segEnd = loop && this.cursorBeat < loop[1] ? loop[1] : Infinity;
      const to = Math.min(this.cursorBeat + (horizon - this.cursorTime) / spb, segEnd);
      this.mixer.schedule(this.cursorBeat, to, this.cursorTime, segEnd, this.metronome);
      this.cursorTime += (to - this.cursorBeat) * spb;
      this.cursorBeat = to;
      if (loop && to >= segEnd) {
        this.cursorBeat = loop[0];
        this.anchors.push({ time: this.cursorTime, beat: loop[0], spb });
        this.mixer.chase(loop[0], this.cursorTime, loop[1]);
      }
    }
    const now = this.ctx.currentTime;
    while (this.anchors.length > 1 && this.anchors[1].time <= now) this.anchors.shift();
  }

  // Live notes and recording -------------------------------------------------------------------

  setLiveTrack(id) {
    this.liveTrack = id || '';
  }

  noteOn(trackId, pitch, vel) {
    void this.ctx.resume();
    const id = trackId || this.liveTrack;
    const track = this.mixer.tracks.get(id);
    if (!track?.instrument) return;
    const key = `${id}:${pitch}`;
    this.noteOff(id, pitch);
    const voice = track.instrument.noteOn(this.ctx.currentTime, pitch, vel);
    this.held.set(key, { voice, track: id });
    if (this.recording && this.playing && id === this.liveTrack) {
      this.recHeld.set(pitch, { pitch, vel, start: this.position() });
    }
  }

  noteOff(trackId, pitch) {
    const id = trackId || this.liveTrack;
    const key = `${id}:${pitch}`;
    const h = this.held.get(key);
    if (!h) return;
    this.held.delete(key);
    const track = this.mixer.tracks.get(id);
    track?.instrument?.noteOff(h.voice, this.ctx.currentTime);
    const rec = this.recHeld.get(pitch);
    if (rec && id === this.liveTrack) {
      this.recHeld.delete(pitch);
      this.keep(rec, this.position());
    }
  }

  allNotesOff() {
    for (const [key, h] of [...this.held]) {
      const pitch = Number(key.slice(key.lastIndexOf(':') + 1));
      this.noteOff(h.track, pitch);
    }
  }

  keep(h, end) {
    let length = end - h.start;
    const loop = this.loopRange();
    if (length < 0 && loop) length = loop[1] - h.start;
    if (length <= 0) length = 0.125;
    this.recorded.push({ pitch: h.pitch, start: h.start, length, velocity: h.vel });
  }

  finishHeld(at) {
    for (const h of this.recHeld.values()) this.keep(h, at);
    this.recHeld.clear();
  }

  setRecording(on) {
    if (!on && this.recording) this.finishHeld(this.position());
    this.recording = on;
  }

  takeRecording() {
    const out = this.recorded;
    this.recorded = [];
    return out;
  }

  setMetronome(on) {
    this.metronome = on;
  }

  // Meters -----------------------------------------------------------------------------------

  peak(a) {
    if (this.buf.length !== a.fftSize) this.buf = new Float32Array(a.fftSize);
    a.getFloatTimeDomainData(this.buf);
    let p = 0;
    for (let i = 0; i < this.buf.length; i++) p = Math.max(p, Math.abs(this.buf[i]));
    return p;
  }

  levels() {
    const tracks = {};
    for (const [id, t] of this.mixer.tracks) {
      const v = Math.max(this.peak(t.meter), (this.levelsNow.get(id) ?? 0) * 0.8);
      this.levelsNow.set(id, v);
      tracks[id] = Math.round(v * 1000) / 1000;
    }
    this.masterLevels = [
      Math.max(this.peak(this.splitL), this.masterLevels[0] * 0.8),
      Math.max(this.peak(this.splitR), this.masterLevels[1] * 0.8),
    ];
    return { tracks, master: this.masterLevels.map((v) => Math.round(v * 1000) / 1000) };
  }

  masterPeak() {
    return [this.peak(this.splitL), this.peak(this.splitR)];
  }

  // Rendering --------------------------------------------------------------------------------

  /**
   * Plays the song from `from` to `to` into an AudioBuffer, faster than real time. With `to`
   * at or before `from`, it plays to the end of the last clip. A tail lets reverbs ring out.
   */
  async render(from, to, tail = 2) {
    const end = to > from ? to : this.mixer.end();
    if (!(end > from)) throw new Error('the song is empty');
    const rate = 44100;
    const seconds = (end - from) * this.mixer.spb + tail;
    const off = new OfflineAudioContext({ numberOfChannels: 2, length: Math.ceil(seconds * rate), sampleRate: rate });
    const mixer = new Mixer(off, (msg) => this.emit('warning', { message: msg }));
    mixer.load(JSON.parse(JSON.stringify(this.mixer.song)));
    // Modules load in the background, and the render waits for them.
    await wamSettled(off);
    mixer.chase(from, 0, end);
    mixer.schedule(from, end, 0, end, false);
    await wamFlush(off);
    return off.startRendering();
  }

  dispose() {
    this.stop();
    void this.ctx.close();
  }
}
