-- Functions the generated shaders call, written once in each language. A shader carries only
-- the ones its nodes use, plus the ones those need. Every name starts with `sb_`, so they
-- stay clear of names in Expression nodes.

---@type table<string, Shader.Helper>
local HELPERS = {
  hash = {
    glsl = [[
float sb_hash(vec2 p) {
  vec3 p3 = fract(p.xyx * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}]],
    wgsl = [[
fn sb_hash(p: vec2f) -> f32 {
  var p3 = fract(p.xyx * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}]],
  },
  hash2 = {
    glsl = [[
vec2 sb_hash2(vec2 p) {
  vec3 p3 = fract(p.xyx * vec3(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
}]],
    wgsl = [[
fn sb_hash2(p: vec2f) -> vec2f {
  var p3 = fract(p.xyx * vec3f(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
}]],
  },
  value_noise = {
    needs = { 'hash' },
    glsl = [[
float sb_value_noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 s = f * f * (3.0 - 2.0 * f);
  float a = sb_hash(i);
  float b = sb_hash(i + vec2(1.0, 0.0));
  float c = sb_hash(i + vec2(0.0, 1.0));
  float d = sb_hash(i + vec2(1.0, 1.0));
  return mix(mix(a, b, s.x), mix(c, d, s.x), s.y);
}]],
    wgsl = [[
fn sb_value_noise(p: vec2f) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let s = f * f * (3.0 - 2.0 * f);
  let a = sb_hash(i);
  let b = sb_hash(i + vec2f(1.0, 0.0));
  let c = sb_hash(i + vec2f(0.0, 1.0));
  let d = sb_hash(i + vec2f(1.0, 1.0));
  return mix(mix(a, b, s.x), mix(c, d, s.x), s.y);
}]],
  },
  gradient_noise = {
    needs = { 'hash2' },
    glsl = [[
float sb_gradient_noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 s = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
  float a = dot(sb_hash2(i) * 2.0 - 1.0, f);
  float b = dot(sb_hash2(i + vec2(1.0, 0.0)) * 2.0 - 1.0, f - vec2(1.0, 0.0));
  float c = dot(sb_hash2(i + vec2(0.0, 1.0)) * 2.0 - 1.0, f - vec2(0.0, 1.0));
  float d = dot(sb_hash2(i + vec2(1.0, 1.0)) * 2.0 - 1.0, f - vec2(1.0, 1.0));
  return 0.5 + 0.7071 * mix(mix(a, b, s.x), mix(c, d, s.x), s.y);
}]],
    wgsl = [[
fn sb_gradient_noise(p: vec2f) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let s = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
  let a = dot(sb_hash2(i) * 2.0 - 1.0, f);
  let b = dot(sb_hash2(i + vec2f(1.0, 0.0)) * 2.0 - 1.0, f - vec2f(1.0, 0.0));
  let c = dot(sb_hash2(i + vec2f(0.0, 1.0)) * 2.0 - 1.0, f - vec2f(0.0, 1.0));
  let d = dot(sb_hash2(i + vec2f(1.0, 1.0)) * 2.0 - 1.0, f - vec2f(1.0, 1.0));
  return 0.5 + 0.7071 * mix(mix(a, b, s.x), mix(c, d, s.x), s.y);
}]],
  },
  fbm = {
    needs = { 'value_noise' },
    glsl = [[
float sb_fbm(vec2 p, int octaves, float lacunarity, float gain) {
  float sum = 0.0;
  float amp = 0.5;
  float norm = 0.0;
  vec2 q = p;
  for (int i = 0; i < 12; i++) {
    if (i >= octaves) break;
    sum += amp * sb_value_noise(q);
    norm += amp;
    q = q * lacunarity + vec2(17.3, 9.1);
    amp *= gain;
  }
  return sum / max(norm, 0.0001);
}]],
    wgsl = [[
fn sb_fbm(p: vec2f, octaves: i32, lacunarity: f32, gain: f32) -> f32 {
  var sum = 0.0;
  var amp = 0.5;
  var norm = 0.0;
  var q = p;
  for (var i = 0; i < 12; i++) {
    if (i >= octaves) {
      break;
    }
    sum += amp * sb_value_noise(q);
    norm += amp;
    q = q * lacunarity + vec2f(17.3, 9.1);
    amp *= gain;
  }
  return sum / max(norm, 0.0001);
}]],
  },
  voronoi = {
    needs = { 'hash', 'hash2' },
    glsl = [[
vec2 sb_voronoi(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  float best = 8.0;
  float id = 0.0;
  for (int y = -1; y <= 1; y++) {
    for (int x = -1; x <= 1; x++) {
      vec2 g = vec2(float(x), float(y));
      vec2 r = g + sb_hash2(i + g) - f;
      float d = dot(r, r);
      if (d < best) {
        best = d;
        id = sb_hash(i + g);
      }
    }
  }
  return vec2(sqrt(best), id);
}]],
    wgsl = [[
fn sb_voronoi(p: vec2f) -> vec2f {
  let i = floor(p);
  let f = fract(p);
  var best = 8.0;
  var id = 0.0;
  for (var y = -1; y <= 1; y++) {
    for (var x = -1; x <= 1; x++) {
      let g = vec2f(f32(x), f32(y));
      let r = g + sb_hash2(i + g) - f;
      let d = dot(r, r);
      if (d < best) {
        best = d;
        id = sb_hash(i + g);
      }
    }
  }
  return vec2f(sqrt(best), id);
}]],
  },
  hsv2rgb = {
    glsl = [[
vec3 sb_hsv2rgb(vec3 c) {
  vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
  return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}]],
    wgsl = [[
fn sb_hsv2rgb(c: vec3f) -> vec3f {
  let p = abs(fract(c.xxx + vec3f(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
  return c.z * mix(vec3f(1.0), clamp(p - 1.0, vec3f(0.0), vec3f(1.0)), c.y);
}]],
  },
  rgb2hsv = {
    glsl = [[
vec3 sb_rgb2hsv(vec3 c) {
  vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
  vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
  vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
  float d = q.x - min(q.w, q.y);
  float e = 1.0e-10;
  return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}]],
    wgsl = [[
fn sb_rgb2hsv(c: vec3f) -> vec3f {
  let k = vec4f(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
  let p = mix(vec4f(c.bg, k.wz), vec4f(c.gb, k.xy), step(c.b, c.g));
  let q = mix(vec4f(p.xyw, c.r), vec4f(c.r, p.yzx), step(p.x, c.r));
  let d = q.x - min(q.w, q.y);
  let e = 1.0e-10;
  return vec3f(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}]],
  },
  rotate = {
    glsl = [[
vec2 sb_rotate(vec2 p, float a) {
  float c = cos(a);
  float s = sin(a);
  return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}]],
    wgsl = [[
fn sb_rotate(p: vec2f, a: f32) -> vec2f {
  let c = cos(a);
  let s = sin(a);
  return vec2f(p.x * c - p.y * s, p.x * s + p.y * c);
}]],
  },
}

local M = {}

M.all = HELPERS

---The helpers `names` need, each after the ones it calls, in a fixed order.
---@param names string[]
---@return string[]
function M.closure (names)
  local out = {} ---@type string[]
  local seen = {} ---@type table<string, boolean>
  ---@param name string
  local function visit (name)
    if seen[name] or not HELPERS[name] then
      return
    end
    seen[name] = true
    for _, dep in ipairs (HELPERS[name].needs or {}) do
      visit (dep)
    end
    out[#out + 1] = name
  end
  local sorted = {} ---@type string[]
  for _, name in ipairs (names) do
    sorted[#sorted + 1] = name
  end
  table.sort (sorted)
  for _, name in ipairs (sorted) do
    visit (name)
  end
  return out
end

---The source of the helpers `names` need, in one language.
---@param names string[]
---@param lang Shader.Lang
---@return string[]
function M.sources (names, lang)
  local out = {} ---@type string[]
  for _, name in ipairs (M.closure (names)) do
    local h = HELPERS[name]
    out[#out + 1] = lang == 'wgsl' and h.wgsl or h.glsl
  end
  return out
end

return M
