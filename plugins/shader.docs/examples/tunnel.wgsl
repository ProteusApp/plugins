// A tunnel of rings in WGSL, for WebGPU. The preview fills the first four fields of the
// Uniforms struct every frame. Every other field gets a control in the Preview panel, shaped
// by the notes in its comment.

struct Uniforms {
  resolution: vec2f,
  time: f32,
  frame: f32,
  mouse: vec4f,
  speed: f32, // @range 0 4 @default 1.2
  twist: f32, // @range -3 3 @default 0.8
  glow: vec3f, // @color @default 0.2 0.8 1.0
}

@group(0) @binding(0) var<uniform> u: Uniforms;

struct VertexOut {
  @builtin(position) position: vec4f,
  @location(0) uv: vec2f,
}

// One triangle that covers the picture.
@vertex
fn vs_main(@builtin(vertex_index) index: u32) -> VertexOut {
  let p = vec2f(f32((index << 1u) & 2u), f32(index & 2u));
  var result: VertexOut;
  result.position = vec4f(p * 2.0 - 1.0, 0.0, 1.0);
  result.uv = p;
  return result;
}

fn palette(t: f32) -> vec3f {
  return 0.5 + 0.5 * cos(6.28318 * (t + vec3f(0.0, 0.1, 0.2)));
}

@fragment
fn fs_main(input: VertexOut) -> @location(0) vec4f {
  let frag = vec2f(input.position.x, u.resolution.y - input.position.y);
  let p = (frag - 0.5 * u.resolution) / u.resolution.y;
  let radius = length(p);
  let depth = 0.3 / max(radius, 0.001) + u.time * u.speed;
  let angle = atan2(p.y, p.x) / 6.28318 + depth * u.twist * 0.1;
  let rings = abs(fract(depth) - 0.5);
  let spokes = abs(fract(angle * 12.0) - 0.5);
  let lines = smoothstep(0.06, 0.0, min(rings, spokes * 0.5));
  let fade = smoothstep(0.0, 0.6, radius);
  let color = (palette(depth * 0.1) * 0.35 + u.glow * lines) * fade;
  return vec4f(color, 1.0);
}
