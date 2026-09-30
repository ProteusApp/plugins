-- daw_resolve: turns a song into what the audio engine plays. Each device on a track becomes
-- its patch, with every parameter filled in from the device's defaults. Devices that no
-- running plugin provides are left out, and their ids come back so the app can say so.

local device_mod = require ('daw_device') --[[@as Daw.DeviceModule]]

local M = {}

---@param ref Daw.DeviceRef
---@param spec Daw.DeviceSpec
---@return Daw.EngineDevice
function M.device (ref, spec)
  local params = device_mod.values (spec, ref)
  if spec.wam then
    -- A module takes a choice by its index, from 0.
    for _, p in ipairs (spec.params) do
      if p.kind == 'choice' then
        local at = 0
        for i, o in ipairs (p.options or {}) do
          if o == params[p.key] then
            at = i - 1
          end
        end
        params[p.key] = at
      end
    end
    return {
      id = ref.id,
      kind = spec.id,
      bypass = ref.bypass == true,
      params = params,
      patch = { role = spec.role },
      wam = { url = '_/' .. tostring (spec.owner) .. '/' .. spec.wam.path },
    }
  end
  local patch = spec.patch
  return {
    id = ref.id,
    bypass = ref.bypass == true,
    params = params,
    patch = {
      role = spec.role,
      poly = patch.poly,
      voice = patch.voice,
      pads = patch.pads,
      nodes = patch.nodes,
      connect = patch.connect,
    },
  }
end

---@param song Daw.Song
---@param lookup fun(id: string): Daw.DeviceSpec?
---@return Daw.EngineSong, string[]
function M.song (song, lookup)
  local missing = {} ---@type string[]
  local noted = {} ---@type table<string, boolean>

  ---@param ref Daw.DeviceRef?
  ---@param role Daw.Role
  ---@return Daw.EngineDevice?
  local function one (ref, role)
    if not ref then
      return nil
    end
    local spec = lookup (ref.device)
    if not spec or spec.role ~= role then
      if not noted[ref.device] then
        noted[ref.device] = true
        missing[#missing + 1] = ref.device
      end
      return nil
    end
    return M.device (ref, spec)
  end

  ---@param refs Daw.DeviceRef[]
  ---@return Daw.EngineDevice[]
  local function effects (refs)
    local out = {} ---@type Daw.EngineDevice[]
    for _, ref in ipairs (refs) do
      local d = one (ref, 'effect')
      if d then
        out[#out + 1] = d
      end
    end
    return out
  end

  local tracks = {} ---@type Daw.EngineTrack[]
  for _, t in ipairs (song.tracks) do
    tracks[#tracks + 1] = {
      id = t.id,
      kind = t.kind,
      volume = t.volume,
      pan = t.pan,
      mute = t.mute,
      solo = t.solo,
      instrument = t.kind == 'instrument' and one (t.instrument, 'instrument')
        or nil,
      effects = effects (t.effects),
      clips = t.clips,
    }
  end
  local sig = song.signature or {}
  ---@type Daw.EngineSong
  local out = {
    tempo = song.tempo,
    beats_per_bar = math.max (1, math.floor (tonumber (sig[1]) or 4)),
    loop = {
      on = song.loop.on,
      start = song.loop.start,
      ['end'] = song.loop.finish,
    },
    master = {
      volume = song.master.volume,
      effects = effects (song.master.effects),
    },
    tracks = tracks,
  }
  return out, missing
end

return M
