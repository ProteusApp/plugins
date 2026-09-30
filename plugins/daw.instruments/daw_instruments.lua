-- daw_instruments: the builtin instruments, as data. Each is a patch of Web Audio nodes that
-- the engine builds once per note, with parameters the patch reads as `$name`. None of it
-- runs Lua while it plays, so a note costs the page nothing.

---@param key string
---@param label string
---@param default number
---@param max? number
---@param group string
---@return Daw.ParamSpec
local function time (key, label, default, max, group)
  return {
    key = key,
    label = label,
    min = 0.001,
    max = max or 4,
    default = default,
    curve = 'log',
    unit = 's',
    group = group,
  }
end

local WAVES = { 'sine', 'triangle', 'sawtooth', 'square', 'pulse' }

---@type Daw.DeviceSpec
local SYNTH = {
  id = 'daw.synth',
  name = 'Synth',
  role = 'instrument',
  category = 'Synths',
  icon = 'audio-waveform',
  description = 'Two oscillators and a sub, a filter with its own envelope, and an LFO.',
  params = {
    {
      key = 'wave1',
      label = 'Wave 1',
      kind = 'choice',
      options = WAVES,
      default = 'sawtooth',
      group = 'Oscillators',
    },
    {
      key = 'wave2',
      label = 'Wave 2',
      kind = 'choice',
      options = WAVES,
      default = 'square',
      group = 'Oscillators',
    },
    {
      key = 'mix',
      label = 'Mix',
      default = 0.35,
      unit = '%',
      group = 'Oscillators',
    },
    {
      key = 'tune2',
      label = 'Tune 2',
      min = -24,
      max = 24,
      step = 1,
      default = 0,
      unit = 'st',
      group = 'Oscillators',
    },
    {
      key = 'detune2',
      label = 'Detune 2',
      min = -50,
      max = 50,
      step = 1,
      default = 7,
      unit = 'ct',
      group = 'Oscillators',
    },
    {
      key = 'sub',
      label = 'Sub',
      default = 0,
      unit = '%',
      group = 'Oscillators',
    },
    {
      key = 'duty',
      label = 'Pulse width',
      min = 0.05,
      max = 0.95,
      default = 0.25,
      unit = '%',
      group = 'Oscillators',
    },
    {
      key = 'mode',
      label = 'Filter',
      kind = 'choice',
      options = { 'lowpass', 'highpass', 'bandpass' },
      default = 'lowpass',
      group = 'Filter',
    },
    {
      key = 'cutoff',
      label = 'Cutoff',
      min = 30,
      max = 18000,
      default = 2400,
      curve = 'log',
      unit = 'Hz',
      group = 'Filter',
    },
    {
      key = 'res',
      label = 'Resonance',
      min = 0.1,
      max = 20,
      default = 1,
      curve = 'log',
      group = 'Filter',
    },
    {
      key = 'fenv',
      label = 'Env amount',
      min = 0,
      max = 8000,
      default = 1500,
      unit = 'Hz',
      group = 'Filter',
    },
    time ('fdecay', 'Env decay', 0.4, 4, 'Filter'),
    {
      key = 'fsustain',
      label = 'Env sustain',
      default = 0.2,
      unit = '%',
      group = 'Filter',
    },
    time ('attack', 'Attack', 0.005, 4, 'Amp'),
    time ('decay', 'Decay', 0.3, 4, 'Amp'),
    {
      key = 'sustain',
      label = 'Sustain',
      default = 0.7,
      unit = '%',
      group = 'Amp',
    },
    time ('release', 'Release', 0.25, 6, 'Amp'),
    {
      key = 'level',
      label = 'Level',
      min = -24,
      max = 6,
      default = -6,
      unit = 'dB',
      group = 'Amp',
    },
    {
      key = 'lrate',
      label = 'LFO rate',
      min = 0.05,
      max = 20,
      default = 5,
      curve = 'log',
      unit = 'Hz',
      group = 'LFO',
    },
    {
      key = 'lpitch',
      label = 'Vibrato',
      min = 0,
      max = 100,
      default = 0,
      unit = 'ct',
      group = 'LFO',
    },
    {
      key = 'lfilter',
      label = 'Wobble',
      min = 0,
      max = 4000,
      default = 0,
      unit = 'Hz',
      group = 'LFO',
    },
  },
  presets = {
    {
      name = 'Saw Lead',
      params = {
        wave1 = 'sawtooth',
        wave2 = 'sawtooth',
        mix = 0.5,
        detune2 = 12,
        cutoff = 3200,
        res = 2,
        fenv = 2500,
        fdecay = 0.3,
        sustain = 0.8,
        release = 0.2,
        lpitch = 12,
      },
    },
    {
      name = 'Pluck',
      params = {
        wave1 = 'sawtooth',
        wave2 = 'square',
        mix = 0.3,
        cutoff = 400,
        res = 3,
        fenv = 5000,
        fdecay = 0.18,
        fsustain = 0,
        decay = 0.35,
        sustain = 0,
        release = 0.3,
      },
    },
    {
      name = 'Warm Pad',
      params = {
        wave1 = 'sawtooth',
        wave2 = 'triangle',
        mix = 0.5,
        detune2 = 14,
        cutoff = 1200,
        res = 0.8,
        fenv = 600,
        fdecay = 1.5,
        fsustain = 0.5,
        attack = 0.6,
        decay = 1,
        sustain = 0.8,
        release = 1.8,
        lrate = 0.3,
        lfilter = 250,
      },
    },
    {
      name = 'Sub Bass',
      params = {
        wave1 = 'triangle',
        wave2 = 'sine',
        mix = 0.2,
        sub = 0.8,
        cutoff = 600,
        res = 0.9,
        fenv = 300,
        fdecay = 0.2,
        attack = 0.003,
        decay = 0.4,
        sustain = 0.8,
        release = 0.12,
        level = -3,
      },
    },
    {
      name = 'Acid Bass',
      params = {
        wave1 = 'sawtooth',
        wave2 = 'square',
        mix = 0.1,
        cutoff = 280,
        res = 14,
        fenv = 3200,
        fdecay = 0.22,
        fsustain = 0,
        decay = 0.25,
        sustain = 0.5,
        release = 0.08,
      },
    },
    {
      name = 'Soft Keys',
      params = {
        wave1 = 'triangle',
        wave2 = 'sine',
        mix = 0.4,
        tune2 = 12,
        cutoff = 2800,
        fenv = 800,
        fdecay = 0.6,
        attack = 0.004,
        decay = 1.2,
        sustain = 0.3,
        release = 0.5,
      },
    },
    {
      name = 'Square Chip',
      params = {
        wave1 = 'pulse',
        wave2 = 'square',
        mix = 0,
        duty = 0.25,
        cutoff = 12000,
        fenv = 0,
        res = 0.5,
        attack = 0.001,
        decay = 0.1,
        sustain = 0.8,
        release = 0.05,
        lpitch = 20,
        lrate = 6,
      },
    },
  },
  patch = {
    poly = 12,
    voice = {
      nodes = {
        {
          id = 'o1',
          type = 'osc',
          wave = '$wave1',
          duty = '$duty',
          freq = 'freq',
        },
        {
          id = 'o2',
          type = 'osc',
          wave = '$wave2',
          duty = '$duty',
          freq = 'freq * semis($tune2)',
          detune = '$detune2',
        },
        { id = 'subosc', type = 'osc', wave = 'sine', freq = 'freq / 2' },
        { id = 'g1', type = 'gain', gain = '1 - $mix' },
        { id = 'g2', type = 'gain', gain = '$mix' },
        { id = 'gsub', type = 'gain', gain = '$sub' },
        {
          id = 'flt',
          type = 'filter',
          mode = '$mode',
          freq = '$cutoff',
          q = '$res',
        },
        {
          id = 'fenv',
          type = 'env',
          a = 0.004,
          d = '$fdecay',
          s = '$fsustain',
          r = '$release',
          amount = '$fenv',
        },
        { id = 'amp', type = 'gain', gain = 0 },
        {
          id = 'aenv',
          type = 'env',
          a = '$attack',
          d = '$decay',
          s = '$sustain',
          r = '$release',
          amount = 'vel * db($level)',
        },
        { id = 'vib', type = 'lfo', rate = '$lrate', depth = '$lpitch' },
        { id = 'wob', type = 'lfo', rate = '$lrate', depth = '$lfilter' },
      },
      connect = {
        'o1 > g1',
        'o2 > g2',
        'subosc > gsub',
        'g1 > flt',
        'g2 > flt',
        'gsub > flt',
        'flt > amp',
        'amp > out',
        'aenv > amp.gain',
        'fenv > flt.freq',
        'vib > o1.detune',
        'vib > o2.detune',
        'wob > flt.freq',
      },
    },
  },
}

---@type Daw.DeviceSpec
local FM = {
  id = 'daw.fm',
  name = 'FM Keys',
  role = 'instrument',
  category = 'Synths',
  icon = 'piano',
  description = 'Two-operator FM: bright keys, bells and metallic basses.',
  params = {
    {
      key = 'ratio',
      label = 'Ratio',
      min = 0.5,
      max = 12,
      step = 0.5,
      default = 1,
      unit = 'x',
      group = 'Modulator',
    },
    {
      key = 'index',
      label = 'Depth',
      min = 0,
      max = 12,
      default = 2.5,
      group = 'Modulator',
    },
    time ('mdecay', 'Decay', 0.8, 6, 'Modulator'),
    {
      key = 'msustain',
      label = 'Sustain',
      default = 0.1,
      unit = '%',
      group = 'Modulator',
    },
    {
      key = 'fine',
      label = 'Fine',
      min = -50,
      max = 50,
      step = 1,
      default = 3,
      unit = 'ct',
      group = 'Modulator',
    },
    time ('attack', 'Attack', 0.002, 4, 'Amp'),
    time ('decay', 'Decay', 1.4, 8, 'Amp'),
    {
      key = 'sustain',
      label = 'Sustain',
      default = 0.25,
      unit = '%',
      group = 'Amp',
    },
    time ('release', 'Release', 0.4, 6, 'Amp'),
    {
      key = 'level',
      label = 'Level',
      min = -24,
      max = 6,
      default = -8,
      unit = 'dB',
      group = 'Amp',
    },
  },
  presets = {
    {
      name = 'Electric Piano',
      params = {
        ratio = 1,
        index = 2.2,
        mdecay = 0.9,
        msustain = 0.05,
        decay = 1.6,
        sustain = 0.2,
        release = 0.5,
      },
    },
    {
      name = 'Bell',
      params = {
        ratio = 3.5,
        index = 5,
        mdecay = 2.5,
        msustain = 0,
        decay = 3,
        sustain = 0,
        release = 2.5,
      },
    },
    {
      name = 'Metal Bass',
      params = {
        ratio = 0.5,
        index = 4,
        mdecay = 0.25,
        msustain = 0.1,
        decay = 0.4,
        sustain = 0.6,
        release = 0.1,
        level = -4,
      },
    },
    {
      name = 'Glass',
      params = {
        ratio = 7,
        index = 1.5,
        mdecay = 1.2,
        msustain = 0.2,
        attack = 0.01,
        decay = 2,
        sustain = 0.4,
        release = 1.2,
      },
    },
  },
  patch = {
    poly = 12,
    voice = {
      nodes = {
        { id = 'car', type = 'osc', wave = 'sine', freq = 'freq' },
        {
          id = 'mod',
          type = 'osc',
          wave = 'sine',
          freq = 'freq * $ratio',
          detune = '$fine',
        },
        { id = 'depth', type = 'gain', gain = 0 },
        {
          id = 'menv',
          type = 'env',
          a = 0.002,
          d = '$mdecay',
          s = '$msustain',
          r = '$release',
          amount = 'freq * $index * (0.4 + vel * 0.6)',
        },
        { id = 'amp', type = 'gain', gain = 0 },
        {
          id = 'aenv',
          type = 'env',
          a = '$attack',
          d = '$decay',
          s = '$sustain',
          r = '$release',
          amount = 'vel * db($level)',
        },
      },
      connect = {
        'mod > depth',
        'menv > depth.gain',
        'depth > car.freq',
        'car > amp',
        'aenv > amp.gain',
        'amp > out',
      },
    },
  },
}

---A drum voice: `body` sounds through an amp that dies away over `decay`.
---@param body Daw.PatchNode[]
---@param wires string[]
---@param decay string|number
---@return Daw.Graph
local function hit (body, wires, decay)
  local nodes = {} ---@type Daw.PatchNode[]
  for _, n in ipairs (body) do
    nodes[#nodes + 1] = n
  end
  nodes[#nodes + 1] = { id = 'amp', type = 'gain', gain = 0 }
  nodes[#nodes + 1] = {
    id = 'aenv',
    type = 'env',
    oneshot = true,
    a = 0.001,
    d = decay,
    amount = 'vel * db($level)',
  }
  local connect = {} ---@type string[]
  for _, w in ipairs (wires) do
    connect[#connect + 1] = w
  end
  connect[#connect + 1] = 'aenv > amp.gain'
  connect[#connect + 1] = 'amp > out'
  return { nodes = nodes, connect = connect }
end

---@param pitch integer
---@param name string
---@param ratio number
---@return Daw.Pad
local function tom (pitch, name, ratio)
  return {
    pitch = pitch,
    name = name,
    voice = hit ({
      { id = 'o', type = 'osc', wave = 'sine', freq = '$tom_tune * ' .. ratio },
      {
        id = 'penv',
        type = 'env',
        oneshot = true,
        a = 0.001,
        d = 0.12,
        amount = '$tom_tune * ' .. ratio,
      },
    }, { 'o > amp', 'penv > o.freq' }, '$tom_decay'),
  }
end

---@type Daw.DeviceSpec
local DRUMS = {
  id = 'daw.drums',
  name = 'Drum Kit',
  role = 'instrument',
  category = 'Drums',
  icon = 'drum',
  description = 'A synthesised kit on the General MIDI notes: kick C1, snare D1, clap D#1, hats F#1 and A#1.',
  params = {
    {
      key = 'kick_tune',
      label = 'Kick tune',
      min = 30,
      max = 100,
      default = 50,
      unit = 'Hz',
      group = 'Kick',
    },
    {
      key = 'kick_punch',
      label = 'Kick punch',
      min = 0,
      max = 400,
      default = 180,
      unit = 'Hz',
      group = 'Kick',
    },
    time ('kick_decay', 'Kick decay', 0.45, 2, 'Kick'),
    {
      key = 'snare_tone',
      label = 'Snare tone',
      min = 120,
      max = 400,
      default = 190,
      unit = 'Hz',
      group = 'Snare',
    },
    {
      key = 'snare_snap',
      label = 'Snare snap',
      default = 0.7,
      unit = '%',
      group = 'Snare',
    },
    time ('snare_decay', 'Snare decay', 0.2, 1, 'Snare'),
    time ('clap_decay', 'Clap decay', 0.25, 1, 'Snare'),
    {
      key = 'hat_tone',
      label = 'Hat tone',
      min = 3000,
      max = 14000,
      default = 8000,
      curve = 'log',
      unit = 'Hz',
      group = 'Hats',
    },
    time ('hat_decay', 'Closed decay', 0.06, 0.5, 'Hats'),
    time ('ohat_decay', 'Open decay', 0.45, 2, 'Hats'),
    {
      key = 'tom_tune',
      label = 'Tom tune',
      min = 60,
      max = 300,
      default = 110,
      curve = 'log',
      unit = 'Hz',
      group = 'Toms',
    },
    time ('tom_decay', 'Tom decay', 0.4, 2, 'Toms'),
    {
      key = 'level',
      label = 'Level',
      min = -24,
      max = 6,
      default = -10,
      unit = 'dB',
      group = 'Kit',
    },
  },
  presets = {
    {
      name = 'Tight',
      params = {
        kick_decay = 0.3,
        kick_punch = 240,
        snare_decay = 0.14,
        hat_decay = 0.04,
        ohat_decay = 0.3,
      },
    },
    {
      name = 'Boom',
      params = {
        kick_tune = 42,
        kick_decay = 1.2,
        kick_punch = 120,
        snare_tone = 160,
        snare_decay = 0.3,
      },
    },
    {
      name = 'Lo-Fi',
      params = {
        hat_tone = 4500,
        snare_snap = 0.4,
        kick_punch = 90,
        level = -13,
      },
    },
  },
  patch = {
    poly = 24,
    pads = {
      {
        pitch = 36,
        name = 'Kick',
        voice = hit ({
          { id = 'o', type = 'osc', wave = 'sine', freq = '$kick_tune' },
          {
            id = 'penv',
            type = 'env',
            oneshot = true,
            a = 0.001,
            d = 0.07,
            amount = '$kick_punch',
          },
        }, { 'o > amp', 'penv > o.freq' }, '$kick_decay'),
      },
      {
        pitch = 38,
        name = 'Snare',
        voice = hit ({
          { id = 'o', type = 'osc', wave = 'triangle', freq = '$snare_tone' },
          {
            id = 'penv',
            type = 'env',
            oneshot = true,
            a = 0.001,
            d = 0.05,
            amount = '$snare_tone * 0.5',
          },
          { id = 'tone', type = 'gain', gain = '1 - $snare_snap * 0.6' },
          { id = 'n', type = 'noise' },
          { id = 'hp', type = 'filter', mode = 'highpass', freq = 1400 },
          { id = 'snap', type = 'gain', gain = '$snare_snap' },
        }, {
          'o > tone',
          'tone > amp',
          'penv > o.freq',
          'n > hp',
          'hp > snap',
          'snap > amp',
        }, '$snare_decay'),
      },
      {
        pitch = 39,
        name = 'Clap',
        voice = hit ({
          { id = 'n', type = 'noise' },
          {
            id = 'bp',
            type = 'filter',
            mode = 'bandpass',
            freq = 1100,
            q = 1.8,
          },
          {
            id = 'flutter',
            type = 'lfo',
            wave = 'square',
            rate = 70,
            depth = 0.5,
          },
          { id = 'g', type = 'gain', gain = 0.5 },
        }, { 'n > bp', 'bp > g', 'flutter > g.gain', 'g > amp' }, '$clap_decay'),
      },
      {
        pitch = 42,
        name = 'Closed Hat',
        choke = 'hat',
        voice = hit ({
          { id = 'n', type = 'noise' },
          { id = 'hp', type = 'filter', mode = 'highpass', freq = '$hat_tone' },
          { id = 'g', type = 'gain', gain = 0.6 },
        }, { 'n > hp', 'hp > g', 'g > amp' }, '$hat_decay'),
      },
      {
        pitch = 46,
        name = 'Open Hat',
        choke = 'hat',
        voice = hit ({
          { id = 'n', type = 'noise' },
          {
            id = 'hp',
            type = 'filter',
            mode = 'highpass',
            freq = '$hat_tone * 0.9',
          },
          { id = 'g', type = 'gain', gain = 0.5 },
        }, { 'n > hp', 'hp > g', 'g > amp' }, '$ohat_decay'),
      },
      tom (45, 'Low Tom', 1),
      tom (48, 'High Tom', 1.5),
      {
        pitch = 49,
        name = 'Crash',
        voice = hit ({
          { id = 'n', type = 'noise' },
          {
            id = 'hp',
            type = 'filter',
            mode = 'highpass',
            freq = '$hat_tone * 0.6',
          },
          { id = 'g', type = 'gain', gain = 0.45 },
        }, { 'n > hp', 'hp > g', 'g > amp' }, 1.4),
      },
      {
        pitch = 56,
        name = 'Cowbell',
        voice = hit ({
          { id = 'o1', type = 'osc', wave = 'square', freq = 540 },
          { id = 'o2', type = 'osc', wave = 'square', freq = 800 },
          { id = 'bp', type = 'filter', mode = 'bandpass', freq = 800, q = 2 },
          { id = 'g', type = 'gain', gain = 0.35 },
        }, { 'o1 > bp', 'o2 > bp', 'bp > g', 'g > amp' }, 0.3),
      },
    },
  },
}

---@type Daw.DeviceSpec
local SAMPLER = {
  id = 'daw.sampler',
  name = 'Sampler',
  role = 'instrument',
  category = 'Samplers',
  icon = 'file-audio',
  description = 'Plays an audio file you pick across the keyboard, pitched from its root note.',
  params = {
    {
      key = 'file',
      label = 'Sample',
      kind = 'file',
      default = '',
      group = 'Sample',
    },
    {
      key = 'root',
      label = 'Root note',
      min = 0,
      max = 127,
      step = 1,
      default = 60,
      group = 'Sample',
    },
    {
      key = 'tune',
      label = 'Tune',
      min = -24,
      max = 24,
      step = 1,
      default = 0,
      unit = 'st',
      group = 'Sample',
    },
    {
      key = 'loop',
      label = 'Loop',
      kind = 'toggle',
      default = false,
      group = 'Sample',
    },
    {
      key = 'cutoff',
      label = 'Cutoff',
      min = 30,
      max = 20000,
      default = 20000,
      curve = 'log',
      unit = 'Hz',
      group = 'Filter',
    },
    time ('attack', 'Attack', 0.002, 4, 'Amp'),
    time ('release', 'Release', 0.3, 6, 'Amp'),
    {
      key = 'level',
      label = 'Level',
      min = -24,
      max = 6,
      default = 0,
      unit = 'dB',
      group = 'Amp',
    },
  },
  patch = {
    poly = 16,
    voice = {
      nodes = {
        {
          id = 'smp',
          type = 'sample',
          file = '$file',
          loop = '$loop',
          rate = 'semis(key - $root + $tune)',
        },
        { id = 'flt', type = 'filter', mode = 'lowpass', freq = '$cutoff' },
        { id = 'amp', type = 'gain', gain = 0 },
        {
          id = 'aenv',
          type = 'env',
          a = '$attack',
          d = 0.05,
          s = 1,
          r = '$release',
          amount = 'vel * db($level)',
        },
      },
      connect = { 'smp > flt', 'flt > amp', 'aenv > amp.gain', 'amp > out' },
    },
  },
}

return { SYNTH, FM, DRUMS, SAMPLER }
