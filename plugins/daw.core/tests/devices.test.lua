local demo = require ('daw_demo') --[[@as Daw.DemoModule]]
local device = require ('daw_device') --[[@as Daw.DeviceModule]]
-- The builtin devices live in their own plugins, so the test reads them from there.
---@param path string
---@return Daw.DeviceSpec[]
local function specs_of (path)
  local chunk = assert (load (read (path), '@' .. path))
  return chunk () --[[@as Daw.DeviceSpec[] ]]
end
local effects = specs_of ('plugins/daw.effects/daw_effects.lua')
local instruments = specs_of ('plugins/daw.instruments/daw_instruments.lua')
local resolve = require ('daw_resolve') --[[@as Daw.ResolveModule]]

---@type table<string, Daw.DeviceSpec>
local checked = {}
---Every builtin device, instruments first.
local all = {} ---@type Daw.DeviceSpec[]

---@param specs Daw.DeviceSpec[]
local function check_all (specs)
  for _, spec in ipairs (specs) do
    local out, err = device.check (spec)
    if out then
      checked[out.id] = out
    else
      error (tostring (err))
    end
    all[#all + 1] = spec
  end
end
check_all (instruments)
check_all (effects)

---@param id string
---@return Daw.DeviceSpec?
local function lookup (id)
  return checked[id]
end

test ('every builtin device passes the check', function ()
  for _, spec in ipairs (instruments) do
    ok (checked[spec.id], spec.id)
    eq (checked[spec.id].role, 'instrument')
  end
  for _, spec in ipairs (effects) do
    ok (checked[spec.id], spec.id)
    eq (checked[spec.id].role, 'effect')
  end
end)

test ('presets only name parameters their device has', function ()
  for _, spec in ipairs (all) do
    for _, preset in ipairs (spec.presets or {}) do
      for key in pairs (preset.params) do
        ok (
          device.param (spec, key),
          spec.id .. ' preset ' .. preset.name .. ' names ' .. key
        )
      end
    end
  end
end)

---A small effect that passes the check.
---@return { id: string, role: string, params: table<string, any>[], patch: { nodes: table<string, any>[], connect: string[] } }
local function good ()
  return {
    id = 'my.fx',
    role = 'effect',
    params = { { key = 'g', min = 0, max = 2, default = 1 } },
    patch = {
      nodes = { { id = 'a', type = 'gain', gain = '$g' } },
      connect = { 'in > a', 'a > out' },
    },
  }
end

---@param spec table<string, any>
---@param want string
local function refused (spec, want)
  local out, err = device.check (spec)
  ok (not out, 'should refuse: ' .. want)
  ok (
    tostring (err):find (want, 1, true),
    'the reason should mention "' .. want .. '", got: ' .. tostring (err)
  )
end

test ('check refuses broken specs with a reason', function ()
  ok (device.check (good ()))
  local s = good ()
  s.role = 'toaster'
  refused (s, 'role')
  s = good ()
  s.patch.nodes[1].type = 'laser'
  refused (s, 'unknown type')
  s = good ()
  s.patch.connect = { 'a > nowhere' }
  refused (s, 'not there')
  s = good ()
  s.patch.connect = { 'a to out' }
  refused (s, 'should read')
  s = good ()
  s.params[1].max = -1
  refused (s, 'max above min')
  s = good ()
  s.params[2] = { key = 'g' }
  refused (s, 'twice')
  s = good ()
  s.patch.nodes[2] = { id = 'a', type = 'gain' }
  refused (s, 'taken')
end)

test ('parameters clamp, step and move along their knobs', function ()
  local p = {
    key = 'f',
    label = 'F',
    min = 20,
    max = 20000,
    curve = 'log',
    default = 1000,
  } --[[@as Daw.ParamSpec]]
  eq (device.clamp (p, 5), 20)
  eq (device.clamp (p, 'x'), 1000)
  ok (math.abs (device.to_unit (p, 632.455532) - 0.5) < 1e-6)
  ok (math.abs (device.from_unit (p, 0.5) - 632.455532) < 1e-4)
  local st =
    { key = 's', label = 'S', min = -12, max = 12, step = 1, default = 0 } --[[@as Daw.ParamSpec]]
  eq (device.clamp (st, 3.4), 3)
  local choice = {
    key = 'c',
    label = 'C',
    kind = 'choice',
    options = { 'a', 'b' },
    default = 'a',
  } --[[@as Daw.ParamSpec]]
  eq (device.clamp (choice, 'b'), 'b')
  eq (device.clamp (choice, 'z'), 'a')
end)

---How a value reads in each unit: the unit, the value, and the text.
---@type { [1]: string, [2]: number, [3]: string }[]
local UNIT_CASES = {
  { 'Hz', 2400, '2.40 kHz' },
  { 'Hz', 440, '440 Hz' },
  { 'Hz', 55.5, '55.5 Hz' },
  { 'dB', -6, '-6.0 dB' },
  { 'dB', -60, '-inf dB' },
  { 's', 0.12, '120 ms' },
  { 's', 1.5, '1.50 s' },
  { '%', 0.35, '35%' },
  { 'st', 7, '+7 st' },
  { 'ct', -3, '-3 ct' },
  { 'b', 0.75, '3/16' },
  { 'b', 0.5, '1/8' },
  { 'b', 4, '1/1' },
  { ':1', 4, '4.0:1' },
  { '', 3, '3' },
}

---@param fields table<string, any>
---@return Daw.ParamSpec
local function param_of (fields)
  local p = { key = 'k', label = 'K', default = 0 } ---@type table<string, any>
  for k, v in pairs (fields) do
    p[k] = v
  end
  return p --[[@as Daw.ParamSpec]]
end

---@type fun(param: Daw.ParamSpec, value: Daw.Value): string
local format = device.format

test ('parameter values read in their units', function ()
  for _, case in ipairs (UNIT_CASES) do
    eq (format (param_of ({ unit = case[1] }), case[2]), case[3], case[1])
  end
  eq (
    format (param_of ({ kind = 'file', default = '' }), '/kits/kick.wav'),
    'kick.wav'
  )
  eq (format (param_of ({ kind = 'toggle', default = false }), true), 'On')
end)

test ('ref starts a device from a preset', function ()
  local synth = checked['daw.synth']
  local r = device.ref (synth, 'Pluck')
  eq (r.device, 'daw.synth')
  eq (r.preset, 'Pluck')
  eq (r.params, {})
  eq (device.value (synth, r, 'cutoff'), 400, 'the preset sits over the default')
  eq (device.value (synth, r, 'wave1'), 'sawtooth')
  r.params.cutoff = 900
  eq (
    device.value (synth, r, 'cutoff'),
    900,
    'a value changed on the track wins'
  )
  eq (device.values (synth, r).fsustain, 0, 'the rest of the preset stays')
  eq (device.ref (synth, 'No such preset').preset, nil)
end)

test ('the demo song only uses builtin devices and presets', function ()
  local s = demo.song ()
  local engine, missing = resolve.song (s, lookup)
  eq (missing, {})
  eq (#engine.tracks, 4)
  for _, t in ipairs (s.tracks) do
    local refs = { t.instrument }
    for _, e in ipairs (t.effects) do
      refs[#refs + 1] = e
    end
    for _, r in ipairs (refs) do
      local spec = checked[r.device]
      ok (spec, r.device)
      if r.preset then
        local found = false
        for _, p in ipairs (spec.presets or {}) do
          found = found or p.name == r.preset
        end
        ok (found, r.device .. ' has the preset ' .. r.preset)
      end
    end
  end
end)

test ('resolve fills in defaults and reports missing devices', function ()
  local s = demo.empty ()
  s.tracks[1].effects[1] =
    { id = 'dx', device = 'someone.else', params = {}, bypass = false }
  local engine, missing = resolve.song (s, lookup)
  eq (missing, { 'someone.else' })
  eq (#engine.tracks[1].effects, 0)
  local inst = engine.tracks[2].instrument
  ok (inst)
  eq (inst and inst.params.cutoff, 2400)
  eq (inst and inst.patch.role, 'instrument')
  eq (engine.loop['end'], 16)
end)

test ('resolve plays a preset the song names', function ()
  local engine = resolve.song (demo.song (), lookup)
  local bass = engine.tracks[2].instrument
  eq (bass and bass.params.cutoff, 600, 'Sub Bass sets the cutoff')
  eq (bass and bass.params.wave1, 'triangle')
end)

test ('the device in the plugin guide passes the check', function ()
  local spec, err = device.check ({
    id = 'my.wobble',
    name = 'Wobble Bass',
    role = 'instrument',
    category = 'Synths',
    params = {
      {
        key = 'cutoff',
        label = 'Cutoff',
        min = 40,
        max = 8000,
        default = 600,
        curve = 'log',
        unit = 'Hz',
      },
      {
        key = 'rate',
        label = 'Wobble',
        min = 0.5,
        max = 12,
        default = 4,
        unit = 'Hz',
      },
    },
    patch = {
      poly = 1,
      voice = {
        nodes = {
          { id = 'osc', type = 'osc', wave = 'sawtooth', freq = 'freq' },
          {
            id = 'flt',
            type = 'filter',
            mode = 'lowpass',
            freq = '$cutoff',
            q = 8,
          },
          { id = 'lfo', type = 'lfo', rate = '$rate', depth = '$cutoff * 0.8' },
          { id = 'amp', type = 'gain', gain = 0 },
          {
            id = 'env',
            type = 'env',
            a = 0.005,
            d = 0.2,
            s = 0.8,
            r = 0.1,
            amount = 'vel',
          },
        },
        connect = {
          'osc > flt',
          'flt > amp',
          'amp > out',
          'lfo > flt.freq',
          'env > amp.gain',
        },
      },
    },
  })
  ok (spec, tostring (err))
end)

test ('a Web Audio Module device names a module instead of a patch', function ()
  local spec, err = device.check ({
    id = 'wam.synth',
    name = 'Synth',
    role = 'instrument',
    wam = { path = 'wam/synth/index.js' },
  })
  eq (err, nil)
  eq (spec and spec.wam, { path = 'wam/synth/index.js' })
  eq (spec and #spec.params, 0, 'its parameters come later')
  for _, bad in ipairs ({
    '../up.js',
    '/abs.js',
    'wam/synth',
    'a//b.js',
    'wam/x.lua',
  }) do
    local none, why =
      device.check ({ id = 'w', role = 'effect', wam = { path = bad } })
    eq (none, nil, bad)
    ok (why and why:find ('wam.path'), bad)
  end
end)

test ("a module's parameter info becomes parameter specs", function ()
  local params = device.from_wam ({
    wave = {
      type = 'choice',
      label = 'Wave',
      choices = { 'saw', 'square' },
      defaultValue = 1,
    },
    cutoff = {
      type = 'float',
      label = 'Cutoff',
      minValue = 60,
      maxValue = 12000,
      defaultValue = 2400,
      exponent = 3,
      units = 'Hz',
    },
    voices = {
      type = 'int',
      minValue = 1,
      maxValue = 16,
      defaultValue = 8,
      units = 'voices',
    },
    on = { type = 'boolean', label = 'On', defaultValue = 1 },
    broken = { type = 'float', minValue = 1, maxValue = 1 },
    ['bad key'] = { type = 'float' },
  })
  local by = {} ---@type table<string, Daw.ParamSpec>
  for _, p in ipairs (params) do
    by[p.key] = p
  end
  eq (#params, 4, 'the broken and badly named ones are left out')
  eq (by.wave.kind, 'choice')
  eq (by.wave.options, { 'saw', 'square' })
  eq (by.wave.default, 'square')
  eq (by.cutoff.curve, 'log')
  eq (by.cutoff.unit, 'Hz')
  eq (by.cutoff.default, 2400)
  eq (by.voices.step, 1)
  eq (by.voices.unit, nil, 'a unit the DAW does not read is dropped')
  eq (by.on.kind, 'toggle')
  eq (by.on.default, true)
end)

test ('a module device resolves to its address and choice indices', function ()
  local spec = assert (device.check ({
    id = 'wam.synth',
    role = 'instrument',
    wam = { path = 'wam/synth/index.js' },
  }))
  spec.owner = 'wam.basics'
  spec.params = device.from_wam ({
    wave = {
      type = 'choice',
      choices = { 'saw', 'square', 'sine' },
      defaultValue = 0,
    },
    level = { type = 'float', minValue = 0, maxValue = 1, defaultValue = 0.5 },
  })
  local out = resolve.device ({
    id = 'd1',
    device = 'wam.synth',
    params = { wave = 'sine' },
    bypass = false,
  }, spec)
  eq (out.wam, { url = '_/wam.basics/wam/synth/index.js' })
  eq (out.kind, 'wam.synth')
  eq (out.params, { wave = 2, level = 0.5 })
end)
