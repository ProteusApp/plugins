#version 300 es
precision highp float;

// Layered sine waves over a gradient sky. Every uniform with a note in its comment gets a
// control in the Preview panel.

uniform vec2 u_resolution;
uniform float u_time;
uniform vec4 u_mouse;
uniform float u_speed; // @range 0 3 @default 1
uniform float u_layers; // @range 1 8 @step 1 @default 5
uniform vec3 u_deep; // @color @default 0.02 0.1 0.25
uniform vec3 u_foam; // @color @default 0.55 0.85 1.0

in vec2 v_uv;
out vec4 fragColor;

float wave(vec2 p, float k, float t) {
  return 0.08 * sin(p.x * (3.0 + k * 2.0) + t * (1.0 + 0.3 * k)) / (1.0 + k * 0.4);
}

void main() {
  vec2 p = v_uv;
  float t = u_time * u_speed;
  vec3 color = mix(vec3(1.0, 0.75, 0.55), vec3(0.35, 0.55, 0.9), p.y);
  for (int i = 0; i < 8; i++) {
    float k = float(i);
    if (k >= u_layers) break;
    float level = 0.55 - k * 0.07 + wave(p, k, t);
    float edge = smoothstep(level + 0.004, level - 0.004, p.y);
    vec3 layer = mix(u_foam, u_deep, k / max(u_layers - 1.0, 1.0));
    color = mix(color, layer, edge);
  }
  // A glow where the mouse was pressed.
  vec2 m = u_mouse.xy / u_resolution;
  color += 0.25 * exp(-40.0 * distance(p, m)) * u_mouse.z;
  fragColor = vec4(color, 1.0);
}
