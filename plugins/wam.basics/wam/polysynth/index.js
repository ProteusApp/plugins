// PolySynth: a Web Audio Module instrument. Each note plays two detuned oscillators through a
// resonant low-pass filter, with an attack and release envelope. It plays up to 16 notes at
// once, holds notes while the sustain pedal is down, and runs in an AudioWorklet, so any WAM
// host can load it.

import { WebAudioModule, WamNode, addFunctionModule } from '../sdk/index.js';

/**
 * The processor, which runs in the audio thread. The SDK turns this function into a worklet
 * module as text, so it reaches nothing outside itself.
 * @param {string} moduleId
 */
const getPolySynthProcessor = (moduleId) => {
  const scope = globalThis;
  const ModuleScope = scope.webAudioModules.getModuleScope(moduleId);
  const { WamProcessor, WamParameterInfo } = ModuleScope;
  const WAVES = ['saw', 'square', 'triangle', 'sine'];
  const MAX_VOICES = 16;

  /** A band-limiting correction for a step in a waveform, which keeps saws from aliasing. */
  const polyBlep = (t, dt) => {
    if (t < dt) {
      const x = t / dt;
      return x + x - x * x - 1;
    }
    if (t > 1 - dt) {
      const x = (t - 1) / dt;
      return x * x + x + x + 1;
    }
    return 0;
  };

  /** One sample of a waveform at phase `t`, from 0 to 1, moving `dt` a sample. */
  const oscillate = (wave, t, dt) => {
    switch (wave) {
      case 'square': {
        let v = t < 0.5 ? 1 : -1;
        v += polyBlep(t, dt);
        v -= polyBlep((t + 0.5) % 1, dt);
        return v;
      }
      case 'triangle':
        return 4 * Math.abs(t - 0.5) - 1;
      case 'sine':
        return Math.sin(2 * Math.PI * t);
      default:
        return 2 * t - 1 - polyBlep(t, dt);
    }
  };

  class PolySynthProcessor extends WamProcessor {
    constructor(options) {
      super(options);
      this.voices = [];
      this.pedal = false;
    }

    _generateWamParameterInfo() {
      return {
        wave: new WamParameterInfo('wave', { type: 'choice', label: 'Wave', choices: WAVES, defaultValue: 0 }),
        detune: new WamParameterInfo('detune', { label: 'Detune', defaultValue: 8, minValue: 0, maxValue: 50, units: 'ct' }),
        cutoff: new WamParameterInfo('cutoff', {
          label: 'Cutoff',
          defaultValue: 2400,
          minValue: 60,
          maxValue: 12000,
          exponent: 3,
          units: 'Hz',
        }),
        resonance: new WamParameterInfo('resonance', { label: 'Resonance', defaultValue: 0.3, minValue: 0, maxValue: 0.95 }),
        attack: new WamParameterInfo('attack', { label: 'Attack', defaultValue: 0.01, minValue: 0.001, maxValue: 2, exponent: 2, units: 's' }),
        release: new WamParameterInfo('release', { label: 'Release', defaultValue: 0.4, minValue: 0.01, maxValue: 4, exponent: 2, units: 's' }),
        level: new WamParameterInfo('level', { label: 'Level', defaultValue: 0.6, minValue: 0, maxValue: 1 }),
      };
    }

    _onMidi(midiData) {
      const [status, a, b] = midiData.bytes;
      const kind = status & 0xf0;
      if (kind === 0x90 && b > 0) this.noteOn(a, b / 127);
      else if (kind === 0x80 || (kind === 0x90 && b === 0)) this.noteOff(a);
      else if (kind === 0xb0 && a === 64) {
        this.pedal = b >= 64;
        if (!this.pedal) for (const v of this.voices) if (v.held) v.releasing = true;
      } else if (kind === 0xb0 && (a === 120 || a === 123)) {
        for (const v of this.voices) v.releasing = true;
      }
    }

    noteOn(note, velocity) {
      for (const v of this.voices) if (v.note === note) v.releasing = true;
      if (this.voices.length >= MAX_VOICES) this.voices.shift();
      this.voices.push({ note, velocity, phase1: 0, phase2: Math.random(), env: 0, releasing: false, held: false, low: 0, band: 0 });
    }

    noteOff(note) {
      for (const v of this.voices) {
        if (v.note !== note || v.releasing) continue;
        if (this.pedal) v.held = true;
        else v.releasing = true;
      }
    }

    _process(startSample, endSample, inputs, outputs) {
      const out = outputs[0];
      if (!out || !out[0]) return;
      const left = out[0];
      const right = out[1] || out[0];
      const p = this._parameterInterpolators;
      const wave = WAVES[Math.round(p.wave.values[startSample])] || 'saw';
      const detune = Math.pow(2, p.detune.values[startSample] / 1200);
      const attack = 1 / Math.max(1, p.attack.values[startSample] * sampleRate);
      const release = 1 / Math.max(1, p.release.values[startSample] * sampleRate);
      const level = p.level.values[startSample];
      const cutoff = Math.min(p.cutoff.values[startSample], sampleRate * 0.2);
      const f = 2 * Math.sin((Math.PI * cutoff) / sampleRate);
      const damp = 2 * (1 - p.resonance.values[startSample]);
      for (let i = startSample; i < endSample; i++) {
        left[i] = 0;
        right[i] = 0;
      }
      for (const v of this.voices) {
        const freq = 440 * Math.pow(2, (v.note - 69) / 12);
        const dt1 = freq / detune / sampleRate;
        const dt2 = (freq * detune) / sampleRate;
        for (let i = startSample; i < endSample; i++) {
          if (v.releasing) v.env = Math.max(0, v.env - release);
          else v.env = Math.min(1, v.env + attack);
          const a = oscillate(wave, v.phase1, dt1);
          const b = oscillate(wave, v.phase2, dt2);
          v.phase1 = (v.phase1 + dt1) % 1;
          v.phase2 = (v.phase2 + dt2) % 1;
          // A state variable filter, low-pass.
          const x = (a + b) * 0.5;
          v.low += f * v.band;
          const high = x - v.low - damp * v.band;
          v.band += f * high;
          const s = v.low * v.env * v.velocity * level * 0.35;
          left[i] += s * (0.6 + 0.4 * (a - b) * 0.1);
          right[i] += s * (0.6 - 0.4 * (a - b) * 0.1);
        }
      }
      this.voices = this.voices.filter((v) => !(v.releasing && v.env <= 0));
    }
  }

  if (scope.AudioWorkletProcessor && !ModuleScope.PolySynthProcessor) {
    ModuleScope.PolySynthProcessor = PolySynthProcessor;
    scope.registerProcessor(moduleId, PolySynthProcessor);
  }
};

export default class PolySynth extends WebAudioModule {
  constructor(groupId, audioContext) {
    super(groupId, audioContext);
    Object.assign(this._descriptor, {
      identifier: 'dev.proteus.wam.polysynth',
      name: 'PolySynth',
      vendor: 'Proteus',
      description: 'Two detuned oscillators through a resonant low-pass filter.',
      version: '1.0.0',
      isInstrument: true,
      hasAudioInput: false,
      hasMidiInput: true,
    });
    this._guiModuleUrl = new URL('./gui.js', import.meta.url).href;
  }

  async createAudioNode(initialState) {
    await WamNode.addModules(this.audioContext, this.moduleId);
    await addFunctionModule(this.audioContext.audioWorklet, getPolySynthProcessor, this.moduleId);
    const node = new WamNode(this, { numberOfInputs: 0, numberOfOutputs: 1, outputChannelCount: [2] });
    await node._initialize();
    if (initialState) await node.setState(initialState);
    return node;
  }
}
