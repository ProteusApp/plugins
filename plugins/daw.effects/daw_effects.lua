-- daw_effects: the builtin effects, as data. Each patch sits between the implicit nodes `in`
-- and `out` and is built once for the track it is on.

---@param default number
---@return Daw.ParamSpec
local function mix (default)
  return { key = 'mix', label = 'Mix', default = default, unit = '%' }
end

---@type Daw.DeviceSpec
local EQ = {
  id = 'daw.eq',
  name = 'EQ Three',
  role = 'effect',
  category = 'EQ and filters',
  icon = 'sliders-horizontal',
  description = 'Low shelf, a sweepable middle and a high shelf.',
  params = {
    {
      key = 'low',
      label = 'Low',
      min = -18,
      max = 12,
      default = 0,
      unit = 'dB',
      group = 'Low',
    },
    {
      key = 'low_freq',
      label = 'Low freq',
      min = 40,
      max = 600,
      default = 200,
      curve = 'log',
      unit = 'Hz',
      group = 'Low',
    },
    {
      key = 'mid',
      label = 'Mid',
      min = -18,
      max = 12,
      default = 0,
      unit = 'dB',
      group = 'Mid',
    },
    {
      key = 'mid_freq',
      label = 'Mid freq',
      min = 200,
      max = 8000,
      default = 1000,
      curve = 'log',
      unit = 'Hz',
      group = 'Mid',
    },
    {
      key = 'mid_q',
      label = 'Mid width',
      min = 0.2,
      max = 8,
      default = 0.9,
      curve = 'log',
      group = 'Mid',
    },
    {
      key = 'high',
      label = 'High',
      min = -18,
      max = 12,
      default = 0,
      unit = 'dB',
      group = 'High',
    },
    {
      key = 'high_freq',
      label = 'High freq',
      min = 1500,
      max = 16000,
      default = 5000,
      curve = 'log',
      unit = 'Hz',
      group = 'High',
    },
  },
  presets = {
    { name = 'Warm', params = { low = 3, high = -4, mid = -1 } },
    { name = 'Bright', params = { high = 5, high_freq = 7000, low = -2 } },
    {
      name = 'Telephone',
      params = {
        low = -18,
        low_freq = 500,
        high = -18,
        high_freq = 3000,
        mid = 6,
        mid_freq = 1500,
      },
    },
  },
  patch = {
    nodes = {
      {
        id = 'lo',
        type = 'filter',
        mode = 'lowshelf',
        freq = '$low_freq',
        gain = '$low',
      },
      {
        id = 'md',
        type = 'filter',
        mode = 'peaking',
        freq = '$mid_freq',
        q = '$mid_q',
        gain = '$mid',
      },
      {
        id = 'hi',
        type = 'filter',
        mode = 'highshelf',
        freq = '$high_freq',
        gain = '$high',
      },
    },
    connect = { 'in > lo', 'lo > md', 'md > hi', 'hi > out' },
  },
}

---@type Daw.DeviceSpec
local FILTER = {
  id = 'daw.filter',
  name = 'Filter',
  role = 'effect',
  category = 'EQ and filters',
  icon = 'funnel',
  description = 'A resonant filter that an LFO can sweep.',
  params = {
    {
      key = 'mode',
      label = 'Type',
      kind = 'choice',
      options = { 'lowpass', 'highpass', 'bandpass', 'notch' },
      default = 'lowpass',
    },
    {
      key = 'cutoff',
      label = 'Cutoff',
      min = 30,
      max = 18000,
      default = 2000,
      curve = 'log',
      unit = 'Hz',
    },
    {
      key = 'res',
      label = 'Resonance',
      min = 0.1,
      max = 20,
      default = 2,
      curve = 'log',
    },
    {
      key = 'rate',
      label = 'LFO rate',
      min = 0.05,
      max = 16,
      default = 0.5,
      curve = 'log',
      unit = 'Hz',
      group = 'LFO',
    },
    {
      key = 'depth',
      label = 'LFO depth',
      min = 0,
      max = 4800,
      default = 0,
      unit = 'ct',
      group = 'LFO',
    },
  },
  presets = {
    {
      name = 'Slow Sweep',
      params = { cutoff = 900, res = 6, rate = 0.25, depth = 2400 },
    },
    { name = 'Thin', params = { mode = 'highpass', cutoff = 700, res = 0.7 } },
  },
  patch = {
    nodes = {
      {
        id = 'f',
        type = 'filter',
        mode = '$mode',
        freq = '$cutoff',
        q = '$res',
      },
      { id = 'lfo', type = 'lfo', rate = '$rate', depth = '$depth' },
    },
    connect = { 'in > f', 'f > out', 'lfo > f.detune' },
  },
}

---@type Daw.DeviceSpec
local DELAY = {
  id = 'daw.delay',
  name = 'Delay',
  role = 'effect',
  category = 'Delay and reverb',
  icon = 'repeat',
  description = 'Echoes in time with the song, darker with each repeat.',
  params = {
    {
      key = 'time',
      label = 'Time',
      min = 0.25,
      max = 4,
      step = 0.25,
      default = 0.75,
      unit = 'b',
    },
    {
      key = 'feedback',
      label = 'Feedback',
      min = 0,
      max = 0.95,
      default = 0.4,
      unit = '%',
    },
    {
      key = 'tone',
      label = 'Tone',
      min = 500,
      max = 16000,
      default = 4500,
      curve = 'log',
      unit = 'Hz',
    },
    mix (0.3),
  },
  presets = {
    {
      name = 'Dotted Eighth',
      params = { time = 0.75, feedback = 0.35, mix = 0.25 },
    },
    {
      name = 'Slapback',
      params = { time = 0.25, feedback = 0.1, mix = 0.3, tone = 6000 },
    },
    {
      name = 'Dub',
      params = { time = 1.5, feedback = 0.7, tone = 1400, mix = 0.4 },
    },
  },
  patch = {
    nodes = {
      { id = 'dly', type = 'delay', time = '$time * 60 / bpm' },
      { id = 'tone', type = 'filter', mode = 'lowpass', freq = '$tone' },
      { id = 'fb', type = 'gain', gain = '$feedback' },
      { id = 'wet', type = 'gain', gain = '$mix' },
    },
    connect = {
      'in > out',
      'in > dly',
      'dly > tone',
      'tone > fb',
      'fb > dly',
      'tone > wet',
      'wet > out',
    },
  },
}

---@type Daw.DeviceSpec
local REVERB = {
  id = 'daw.reverb',
  name = 'Reverb',
  role = 'effect',
  category = 'Delay and reverb',
  icon = 'waves',
  description = 'A room made from decaying noise, from a small booth to a cave.',
  params = {
    {
      key = 'size',
      label = 'Size',
      min = 0.3,
      max = 8,
      default = 2.2,
      curve = 'log',
      unit = 's',
    },
    { key = 'decay', label = 'Decay shape', min = 1, max = 8, default = 3 },
    {
      key = 'predelay',
      label = 'Pre-delay',
      min = 0,
      max = 0.2,
      default = 0.015,
      unit = 's',
    },
    {
      key = 'tone',
      label = 'Tone',
      min = 800,
      max = 18000,
      default = 7000,
      curve = 'log',
      unit = 'Hz',
    },
    mix (0.25),
  },
  presets = {
    { name = 'Room', params = { size = 0.8, decay = 4, mix = 0.18 } },
    {
      name = 'Hall',
      params = { size = 3.2, decay = 2.5, predelay = 0.03, mix = 0.3 },
    },
    {
      name = 'Cave',
      params = { size = 7, decay = 1.6, tone = 3000, mix = 0.45 },
    },
  },
  patch = {
    nodes = {
      { id = 'pre', type = 'delay', time = '$predelay' },
      { id = 'rv', type = 'reverb', seconds = '$size', decay = '$decay' },
      { id = 'tone', type = 'filter', mode = 'lowpass', freq = '$tone' },
      { id = 'wet', type = 'gain', gain = '$mix' },
      { id = 'dry', type = 'gain', gain = '1 - $mix * 0.5' },
    },
    connect = {
      'in > dry',
      'dry > out',
      'in > pre',
      'pre > rv',
      'rv > tone',
      'tone > wet',
      'wet > out',
    },
  },
}

---@type Daw.DeviceSpec
local COMP = {
  id = 'daw.comp',
  name = 'Compressor',
  role = 'effect',
  category = 'Dynamics',
  icon = 'chevrons-down-up',
  description = 'Evens out loud and quiet parts, then brings the level back up.',
  params = {
    {
      key = 'threshold',
      label = 'Threshold',
      min = -60,
      max = 0,
      default = -18,
      unit = 'dB',
    },
    {
      key = 'ratio',
      label = 'Ratio',
      min = 1,
      max = 20,
      default = 4,
      curve = 'log',
      unit = ':1',
    },
    {
      key = 'attack',
      label = 'Attack',
      min = 0.001,
      max = 0.3,
      default = 0.01,
      curve = 'log',
      unit = 's',
    },
    {
      key = 'release',
      label = 'Release',
      min = 0.02,
      max = 1,
      default = 0.2,
      curve = 'log',
      unit = 's',
    },
    {
      key = 'knee',
      label = 'Knee',
      min = 0,
      max = 40,
      default = 8,
      unit = 'dB',
    },
    {
      key = 'makeup',
      label = 'Makeup',
      min = -12,
      max = 24,
      default = 3,
      unit = 'dB',
    },
  },
  presets = {
    {
      name = 'Glue',
      params = {
        threshold = -14,
        ratio = 2,
        attack = 0.03,
        release = 0.15,
        makeup = 1,
      },
    },
    {
      name = 'Squash',
      params = {
        threshold = -32,
        ratio = 12,
        attack = 0.002,
        release = 0.08,
        makeup = 10,
      },
    },
    {
      name = 'Limiter',
      params = {
        threshold = -3,
        ratio = 20,
        attack = 0.001,
        release = 0.05,
        knee = 0,
        makeup = 2,
      },
    },
  },
  patch = {
    nodes = {
      {
        id = 'c',
        type = 'compressor',
        threshold = '$threshold',
        ratio = '$ratio',
        attack = '$attack',
        release = '$release',
        knee = '$knee',
      },
      { id = 'mk', type = 'gain', gain = 'db($makeup)' },
    },
    connect = { 'in > c', 'c > mk', 'mk > out' },
  },
}

---@type Daw.DeviceSpec
local DRIVE = {
  id = 'daw.drive',
  name = 'Drive',
  role = 'effect',
  category = 'Distortion',
  icon = 'flame',
  description = 'Warm saturation, hard clipping, wave folding or crushed bits.',
  params = {
    {
      key = 'shape',
      label = 'Shape',
      kind = 'choice',
      options = { 'soft', 'hard', 'fold', 'crush' },
      default = 'soft',
    },
    { key = 'amount', label = 'Amount', default = 0.3, unit = '%' },
    {
      key = 'tone',
      label = 'Tone',
      min = 500,
      max = 18000,
      default = 9000,
      curve = 'log',
      unit = 'Hz',
    },
    mix (1),
    {
      key = 'output',
      label = 'Output',
      min = -24,
      max = 6,
      default = -3,
      unit = 'dB',
    },
  },
  presets = {
    {
      name = 'Tape',
      params = { shape = 'soft', amount = 0.15, tone = 7000, mix = 0.7 },
    },
    {
      name = 'Fuzz',
      params = { shape = 'hard', amount = 0.7, tone = 5000, output = -8 },
    },
    {
      name = 'Bitcrush',
      params = { shape = 'crush', amount = 0.6, tone = 12000 },
    },
  },
  patch = {
    nodes = {
      { id = 'ws', type = 'shaper', curve = '$shape', amount = '$amount' },
      { id = 'tone', type = 'filter', mode = 'lowpass', freq = '$tone' },
      { id = 'wet', type = 'gain', gain = '$mix' },
      { id = 'dry', type = 'gain', gain = '1 - $mix' },
      { id = 'outg', type = 'gain', gain = 'db($output)' },
    },
    connect = {
      'in > ws',
      'ws > tone',
      'tone > wet',
      'wet > outg',
      'in > dry',
      'dry > outg',
      'outg > out',
    },
  },
}

---@type Daw.DeviceSpec
local CHORUS = {
  id = 'daw.chorus',
  name = 'Chorus',
  role = 'effect',
  category = 'Modulation',
  icon = 'git-merge',
  description = 'Two drifting copies, one on each side, for a wide and shimmering sound.',
  params = {
    {
      key = 'rate',
      label = 'Rate',
      min = 0.05,
      max = 8,
      default = 0.6,
      curve = 'log',
      unit = 'Hz',
    },
    {
      key = 'depth',
      label = 'Depth',
      min = 0,
      max = 0.008,
      default = 0.003,
      unit = 's',
    },
    {
      key = 'delay',
      label = 'Delay',
      min = 0.005,
      max = 0.04,
      default = 0.018,
      unit = 's',
    },
    mix (0.45),
  },
  presets = {
    { name = 'Wide', params = { rate = 0.4, depth = 0.004, mix = 0.5 } },
    {
      name = 'Vibrato',
      params = { rate = 5, depth = 0.002, delay = 0.006, mix = 1 },
    },
  },
  patch = {
    nodes = {
      { id = 'd1', type = 'delay', time = '$delay' },
      { id = 'd2', type = 'delay', time = '$delay * 1.3' },
      { id = 'l1', type = 'lfo', rate = '$rate', depth = '$depth' },
      { id = 'l2', type = 'lfo', rate = '$rate * 1.13', depth = '$depth' },
      { id = 'p1', type = 'pan', pan = -0.7 },
      { id = 'p2', type = 'pan', pan = 0.7 },
      { id = 'wet', type = 'gain', gain = '$mix' },
      { id = 'dry', type = 'gain', gain = '1 - $mix * 0.5' },
    },
    connect = {
      'in > dry',
      'dry > out',
      'in > d1',
      'in > d2',
      'l1 > d1.time',
      'l2 > d2.time',
      'd1 > p1',
      'd2 > p2',
      'p1 > wet',
      'p2 > wet',
      'wet > out',
    },
  },
}

---@type Daw.DeviceSpec
local UTILITY = {
  id = 'daw.utility',
  name = 'Utility',
  role = 'effect',
  category = 'Utility',
  icon = 'gauge',
  description = 'Gain and pan, anywhere in a chain.',
  params = {
    {
      key = 'gain',
      label = 'Gain',
      min = -36,
      max = 24,
      default = 0,
      unit = 'dB',
    },
    { key = 'pan', label = 'Pan', min = -1, max = 1, default = 0 },
  },
  patch = {
    nodes = {
      { id = 'g', type = 'gain', gain = 'db($gain)' },
      { id = 'p', type = 'pan', pan = '$pan' },
    },
    connect = { 'in > g', 'g > p', 'p > out' },
  },
}

return { EQ, FILTER, DELAY, REVERB, COMP, DRIVE, CHORUS, UTILITY }
