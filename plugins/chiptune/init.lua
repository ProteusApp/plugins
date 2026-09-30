-- Chiptune: instruments and an effect for the DAW profile, in the style of old game
-- consoles. It shows how a plugin adds devices: each one is a patch of Web Audio nodes,
-- described as data and registered with the `daw.devices` service. Nothing here runs while
-- notes play, so the devices cost the page nothing.

---A pulse or noise voice: `body` sounds through an amp shaped by an envelope.
---@param body Daw.PatchNode[]
---@param wires string[]
---@param env Daw.PatchNode
---@return Daw.Graph
local function voice (body, wires, env)
  local nodes = {} ---@type Daw.PatchNode[]
  for _, n in ipairs (body) do
    nodes[#nodes + 1] = n
  end
  nodes[#nodes + 1] = { id = 'amp', type = 'gain', gain = 0 }
  nodes[#nodes + 1] = env
  local connect = {} ---@type string[]
  for _, w in ipairs (wires) do
    connect[#connect + 1] = w
  end
  connect[#connect + 1] = 'aenv > amp.gain'
  connect[#connect + 1] = 'amp > out'
  return { nodes = nodes, connect = connect }
end

---A drum hit that dies away over `decay` seconds.
---@param decay number|string
---@return Daw.PatchNode
local function hit (decay)
  return {
    id = 'aenv',
    type = 'env',
    oneshot = true,
    a = 0.001,
    d = decay,
    amount = 'vel * db($level)',
  }
end

---@type Daw.DeviceSpec
local PULSE = {
  id = 'chip.pulse',
  name = 'Pulse',
  role = 'instrument',
  category = 'Chiptune',
  icon = 'gamepad-2',
  description = 'A pulse wave with the narrow widths of an 8-bit console, a pitch sweep and vibrato.',
  params = {
    {
      key = 'duty',
      label = 'Width',
      min = 0.125,
      max = 0.5,
      step = 0.125,
      default = 0.25,
      unit = '%',
    },
    {
      key = 'sweep',
      label = 'Sweep from',
      min = -24,
      max = 24,
      step = 1,
      default = 0,
      unit = 'st',
    },
    {
      key = 'sweep_time',
      label = 'Sweep time',
      min = 0.01,
      max = 1,
      default = 0.08,
      curve = 'log',
      unit = 's',
    },
    {
      key = 'vibrato',
      label = 'Vibrato',
      min = 0,
      max = 100,
      default = 0,
      unit = 'ct',
    },
    {
      key = 'rate',
      label = 'Vibrato rate',
      min = 1,
      max = 12,
      default = 6,
      unit = 'Hz',
    },
    {
      key = 'decay',
      label = 'Decay',
      min = 0.02,
      max = 3,
      default = 0.4,
      curve = 'log',
      unit = 's',
    },
    { key = 'sustain', label = 'Sustain', default = 0.6, unit = '%' },
    {
      key = 'release',
      label = 'Release',
      min = 0.01,
      max = 1,
      default = 0.05,
      curve = 'log',
      unit = 's',
    },
    {
      key = 'level',
      label = 'Level',
      min = -24,
      max = 6,
      default = -12,
      unit = 'dB',
    },
  },
  presets = {
    { name = 'Lead', params = { duty = 0.25, vibrato = 18, sustain = 0.8 } },
    { name = 'Thin', params = { duty = 0.125, sustain = 0.5 } },
    {
      name = 'Laser',
      params = {
        duty = 0.5,
        sweep = 24,
        sweep_time = 0.15,
        sustain = 0,
        decay = 0.2,
      },
    },
    {
      name = 'Coin',
      params = {
        duty = 0.5,
        sweep = -5,
        sweep_time = 0.02,
        decay = 0.35,
        sustain = 0,
      },
    },
  },
  patch = {
    poly = 3,
    voice = voice ({
      {
        id = 'osc',
        type = 'osc',
        wave = 'pulse',
        duty = '$duty',
        freq = 'freq',
      },
      {
        id = 'sweep',
        type = 'env',
        oneshot = true,
        a = 0.001,
        d = '$sweep_time',
        amount = '$sweep * 100',
      },
      {
        id = 'vib',
        type = 'lfo',
        wave = 'triangle',
        rate = '$rate',
        depth = '$vibrato',
      },
    }, {
      'osc > amp',
      'sweep > osc.detune',
      'vib > osc.detune',
    }, {
      id = 'aenv',
      type = 'env',
      a = 0.002,
      d = '$decay',
      s = '$sustain',
      r = '$release',
      amount = 'vel * db($level)',
    }),
  },
}

---@type Daw.DeviceSpec
local TRIANGLE = {
  id = 'chip.triangle',
  name = 'Triangle Bass',
  role = 'instrument',
  category = 'Chiptune',
  icon = 'triangle',
  description = 'The stepped triangle of an 8-bit console: a round bass with no volume curve of its own.',
  params = {
    { key = 'steps', label = 'Steps', default = 0.55, unit = '%' },
    {
      key = 'octave',
      label = 'Octave',
      min = -2,
      max = 1,
      step = 1,
      default = 0,
    },
    {
      key = 'level',
      label = 'Level',
      min = -24,
      max = 6,
      default = -6,
      unit = 'dB',
    },
  },
  presets = {
    { name = 'Smooth', params = { steps = 0 } },
    { name = 'Low', params = { octave = -1 } },
  },
  patch = {
    poly = 1,
    voice = voice ({
      {
        id = 'osc',
        type = 'osc',
        wave = 'triangle',
        freq = 'freq * pow(2, $octave)',
      },
      { id = 'crush', type = 'shaper', curve = 'crush', amount = '$steps' },
    }, { 'osc > crush', 'crush > amp' }, {
      id = 'aenv',
      type = 'env',
      a = 0.002,
      d = 0.01,
      s = 1,
      r = 0.02,
      amount = 'db($level)',
    }),
  },
}

---@type Daw.DeviceSpec
local NOISE = {
  id = 'chip.noise',
  name = 'Noise Kit',
  role = 'instrument',
  category = 'Chiptune',
  icon = 'gamepad-2',
  description = 'Crunchy console drums on the usual notes: kick C1, snare D1, hats F#1 and A#1.',
  params = {
    { key = 'crunch', label = 'Crunch', default = 0.6, unit = '%' },
    {
      key = 'kick_decay',
      label = 'Kick decay',
      min = 0.05,
      max = 0.8,
      default = 0.2,
      curve = 'log',
      unit = 's',
    },
    {
      key = 'snare_decay',
      label = 'Snare decay',
      min = 0.05,
      max = 0.8,
      default = 0.18,
      curve = 'log',
      unit = 's',
    },
    {
      key = 'hat_decay',
      label = 'Hat decay',
      min = 0.01,
      max = 0.4,
      default = 0.04,
      curve = 'log',
      unit = 's',
    },
    {
      key = 'level',
      label = 'Level',
      min = -24,
      max = 6,
      default = -10,
      unit = 'dB',
    },
  },
  patch = {
    poly = 8,
    pads = {
      {
        pitch = 36,
        name = 'Kick',
        voice = voice (
          {
            { id = 'osc', type = 'osc', wave = 'pulse', duty = 0.5, freq = 45 },
            {
              id = 'drop',
              type = 'env',
              oneshot = true,
              a = 0.001,
              d = 0.05,
              amount = 260,
            },
            {
              id = 'crush',
              type = 'shaper',
              curve = 'crush',
              amount = '$crunch',
            },
          },
          { 'osc > crush', 'crush > amp', 'drop > osc.freq' },
          hit ('$kick_decay')
        ),
      },
      {
        pitch = 38,
        name = 'Snare',
        voice = voice ({
          { id = 'n', type = 'noise' },
          {
            id = 'bp',
            type = 'filter',
            mode = 'bandpass',
            freq = 2200,
            q = 0.8,
          },
          {
            id = 'crush',
            type = 'shaper',
            curve = 'crush',
            amount = '$crunch',
          },
        }, { 'n > bp', 'bp > crush', 'crush > amp' }, hit (
          '$snare_decay'
        )),
      },
      {
        pitch = 42,
        name = 'Closed Hat',
        choke = 'hat',
        voice = voice ({
          { id = 'n', type = 'noise' },
          { id = 'hp', type = 'filter', mode = 'highpass', freq = 7000 },
        }, { 'n > hp', 'hp > amp' }, hit ('$hat_decay')),
      },
      {
        pitch = 46,
        name = 'Open Hat',
        choke = 'hat',
        voice = voice ({
          { id = 'n', type = 'noise' },
          { id = 'hp', type = 'filter', mode = 'highpass', freq = 6000 },
        }, { 'n > hp', 'hp > amp' }, hit ('$hat_decay * 6')),
      },
    },
  },
}

---@type Daw.DeviceSpec
local CRUSHER = {
  id = 'chip.crusher',
  name = 'Bit Crusher',
  role = 'effect',
  category = 'Chiptune',
  icon = 'binary',
  description = 'Fewer bits and a darker top, for sound that fits in an old cartridge.',
  params = {
    { key = 'bits', label = 'Crush', default = 0.5, unit = '%' },
    {
      key = 'tone',
      label = 'Tone',
      min = 800,
      max = 18000,
      default = 6000,
      curve = 'log',
      unit = 'Hz',
    },
    { key = 'mix', label = 'Mix', default = 1, unit = '%' },
  },
  presets = {
    { name = 'Handheld', params = { bits = 0.7, tone = 3500 } },
    { name = 'Light', params = { bits = 0.3, mix = 0.5 } },
  },
  patch = {
    nodes = {
      { id = 'crush', type = 'shaper', curve = 'crush', amount = '$bits' },
      { id = 'tone', type = 'filter', mode = 'lowpass', freq = '$tone' },
      { id = 'wet', type = 'gain', gain = '$mix' },
      { id = 'dry', type = 'gain', gain = '1 - $mix' },
    },
    connect = {
      'in > crush',
      'crush > tone',
      'tone > wet',
      'wet > out',
      'in > dry',
      'dry > out',
    },
  },
}

---@type Proteus.Plugin
return {
  name = 'Chiptune',
  description = 'Pulse, triangle and noise instruments and a bit crusher for the DAW, in the style of old game consoles.',
  version = '1.0.0',
  requires = { proteus = '>=0.2.0', features = { 'permissions' } },
  permissions = {},
  depends = { 'daw.devices' },
  activate = function (app)
    local devices = app.use ('daw.devices') --[[@as Daw.Devices]]
    for _, spec in ipairs ({ PULSE, TRIANGLE, NOISE, CRUSHER }) do
      devices.register (spec)
    end
  end,
}
