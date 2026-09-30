// Echo: a Web Audio Module effect. A stereo delay whose repeats bounce between the left and
// right sides, darker each time through a low-pass filter in the feedback path.

import { WebAudioModule, WamNode, addFunctionModule } from '../sdk/index.js';

/**
 * The processor, which runs in the audio thread. The SDK turns this function into a worklet
 * module as text, so it reaches nothing outside itself.
 * @param {string} moduleId
 */
const getEchoProcessor = (moduleId) => {
  const scope = globalThis;
  const ModuleScope = scope.webAudioModules.getModuleScope(moduleId);
  const { WamProcessor, WamParameterInfo } = ModuleScope;
  const MAX_SECONDS = 2;

  class EchoProcessor extends WamProcessor {
    constructor(options) {
      super(options);
      const size = Math.ceil(MAX_SECONDS * sampleRate) + 1;
      this.bufL = new Float32Array(size);
      this.bufR = new Float32Array(size);
      this.at = 0;
      this.toneL = 0;
      this.toneR = 0;
    }

    _generateWamParameterInfo() {
      return {
        time: new WamParameterInfo('time', { label: 'Time', defaultValue: 0.33, minValue: 0.02, maxValue: MAX_SECONDS, exponent: 1, units: 's' }),
        feedback: new WamParameterInfo('feedback', { label: 'Feedback', defaultValue: 0.4, minValue: 0, maxValue: 0.95 }),
        tone: new WamParameterInfo('tone', { label: 'Tone', defaultValue: 4000, minValue: 300, maxValue: 16000, exponent: 3, units: 'Hz' }),
        mix: new WamParameterInfo('mix', { label: 'Mix', defaultValue: 0.3, minValue: 0, maxValue: 1 }),
      };
    }

    _process(startSample, endSample, inputs, outputs) {
      const input = inputs[0] || [];
      const out = outputs[0];
      if (!out || !out[0]) return;
      const inL = input[0];
      const inR = input[1] || input[0];
      const outL = out[0];
      const outR = out[1] || out[0];
      const p = this._parameterInterpolators;
      const size = this.bufL.length;
      const k = 1 - Math.exp((-2 * Math.PI * p.tone.values[startSample]) / sampleRate);
      for (let i = startSample; i < endSample; i++) {
        const delay = Math.max(1, Math.min(size - 1, Math.round(p.time.values[i] * sampleRate)));
        const read = (this.at - delay + size) % size;
        const dl = this.bufL[read];
        const dr = this.bufR[read];
        const xl = inL ? inL[i] : 0;
        const xr = inR ? inR[i] : 0;
        const fb = p.feedback.values[i];
        this.toneL += k * (dl - this.toneL);
        this.toneR += k * (dr - this.toneR);
        // Each side feeds the other, so the repeats bounce.
        this.bufL[this.at] = xl + this.toneR * fb;
        this.bufR[this.at] = xr + this.toneL * fb;
        this.at = (this.at + 1) % size;
        const mix = p.mix.values[i];
        outL[i] = xl * (1 - mix) + dl * mix;
        outR[i] = xr * (1 - mix) + dr * mix;
      }
    }
  }

  if (scope.AudioWorkletProcessor && !ModuleScope.EchoProcessor) {
    ModuleScope.EchoProcessor = EchoProcessor;
    scope.registerProcessor(moduleId, EchoProcessor);
  }
};

export default class Echo extends WebAudioModule {
  constructor(groupId, audioContext) {
    super(groupId, audioContext);
    Object.assign(this._descriptor, {
      identifier: 'dev.proteus.wam.echo',
      name: 'Echo',
      vendor: 'Proteus',
      description: 'A stereo delay whose repeats bounce between the sides.',
      version: '1.0.0',
      isInstrument: false,
      hasAudioInput: true,
      hasMidiInput: false,
    });
  }

  async createAudioNode(initialState) {
    await WamNode.addModules(this.audioContext, this.moduleId);
    await addFunctionModule(this.audioContext.audioWorklet, getEchoProcessor, this.moduleId);
    const node = new WamNode(this, {
      numberOfInputs: 1,
      numberOfOutputs: 1,
      outputChannelCount: [2],
      channelCount: 2,
      channelCountMode: 'explicit',
    });
    await node._initialize();
    if (initialState) await node.setState(initialState);
    return node;
  }
}
