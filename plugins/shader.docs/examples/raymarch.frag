#version 300 es
precision highp float;

// A ray-marched scene: a sphere melting into a rounded box above a checked floor, with soft
// shadows. Drag over the preview to turn the camera.

uniform vec2 u_resolution;
uniform float u_time;
uniform vec4 u_mouse;
uniform float u_blend; // @range 0 1 @default 0.35
uniform vec3 u_color; // @color @default 1.0 0.45 0.2
uniform float u_shadow; // @range 1 32 @default 12

out vec4 fragColor;

float smin(float a, float b, float k) {
  float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
  return mix(b, a, h) - k * h * (1.0 - h);
}

float sdBox(vec3 p, vec3 b, float r) {
  vec3 q = abs(p) - b;
  return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0) - r;
}

// The distance to the nearest surface, and which surface it is: 1 for the shapes, 2 for
// the floor.
vec2 scene(vec3 p) {
  float bob = 0.35 * sin(u_time * 1.3);
  float sphere = length(p - vec3(0.0, 0.9 + bob, 0.0)) - 0.55;
  float box = sdBox(p - vec3(0.0, 0.35, 0.0), vec3(0.45, 0.25, 0.45), 0.08);
  float shapes = smin(sphere, box, max(u_blend, 0.001));
  float floor_d = p.y;
  return shapes < floor_d ? vec2(shapes, 1.0) : vec2(floor_d, 2.0);
}

vec3 normalAt(vec3 p) {
  vec2 e = vec2(0.001, 0.0);
  return normalize(vec3(
    scene(p + e.xyy).x - scene(p - e.xyy).x,
    scene(p + e.yxy).x - scene(p - e.yxy).x,
    scene(p + e.yyx).x - scene(p - e.yyx).x));
}

float softShadow(vec3 ro, vec3 rd) {
  float res = 1.0;
  float t = 0.02;
  for (int i = 0; i < 48; i++) {
    float h = scene(ro + rd * t).x;
    res = min(res, u_shadow * h / t);
    t += clamp(h, 0.02, 0.2);
    if (res < 0.001 || t > 8.0) break;
  }
  return clamp(res, 0.0, 1.0);
}

void main() {
  vec2 p = (gl_FragCoord.xy - 0.5 * u_resolution) / u_resolution.y;
  float turn = u_mouse.z > 0.0 ? (u_mouse.x / u_resolution.x - 0.5) * 6.2831 : u_time * 0.2;
  vec3 ro = vec3(3.2 * sin(turn), 1.6, 3.2 * cos(turn));
  vec3 target = vec3(0.0, 0.5, 0.0);
  vec3 f = normalize(target - ro);
  vec3 r = normalize(cross(vec3(0.0, 1.0, 0.0), f));
  vec3 u = cross(f, r);
  vec3 rd = normalize(p.x * r + p.y * u + 1.6 * f);

  vec3 sky = mix(vec3(0.75, 0.85, 1.0), vec3(0.3, 0.45, 0.8), clamp(rd.y * 2.0, 0.0, 1.0));
  vec3 color = sky;
  float t = 0.0;
  for (int i = 0; i < 128; i++) {
    vec2 h = scene(ro + rd * t);
    if (h.x < 0.001) {
      vec3 pos = ro + rd * t;
      vec3 n = normalAt(pos);
      vec3 light = normalize(vec3(0.6, 0.9, 0.4));
      float diffuse = max(dot(n, light), 0.0) * softShadow(pos + n * 0.002, light);
      vec3 albedo = u_color;
      if (h.y > 1.5) {
        float check = mod(floor(pos.x * 2.0) + floor(pos.z * 2.0), 2.0);
        albedo = mix(vec3(0.85), vec3(0.55), check);
      }
      float spec = pow(max(dot(reflect(-light, n), -rd), 0.0), 32.0);
      color = albedo * (0.15 + 0.85 * diffuse) + 0.4 * spec * diffuse;
      color = mix(color, sky, 1.0 - exp(-0.02 * t * t));
      break;
    }
    t += h.x;
    if (t > 30.0) break;
  }
  color = pow(color, vec3(1.0 / 2.2));
  fragColor = vec4(color, 1.0);
}
