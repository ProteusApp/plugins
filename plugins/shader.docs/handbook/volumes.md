---
title: 11. Clouds and other volumes
section: Learning shaders
order: 311
keywords: volume volumetric rendering clouds fog smoke density transmittance beer lambert absorption scattering light march phase function henyey greenstein silver lining cloud layer coverage jitter banding performance
---

# 11. Clouds and other volumes

A cloud has no surface for a ray to hit. It is a region of tiny water drops, thick in the middle and thin at the edges, and light passes partway into it before it is used up.

Drawing one means marching through it in steps, adding up the light each step sends toward the eye. This chapter builds that up from a ball of smoke to a whole sky of clouds, which [A weather system](weather.md) then puts to work.

## Density and what gets through

A volume has a density at each point: 0 for clear air, higher for thicker cloud. Light that crosses a thin slice of it loses a share of itself. Over a distance, the share that gets through falls off as `exp(-density * distance)`.

This is the Beer–Lambert law, the same curve as fog in [Light, shadow and fog](lighting.md#fog). The share that gets through is called transmittance.

So a ray marches through the volume in small, equal steps. At each step it reads the density and multiplies its transmittance by what that step lets through:

```glsl
uniform float u_density; // @range 0 4 @default 1.5

// 1 inside a ball of radius 1, and 0 outside it.
float density(vec3 p) {
  return length(p) < 1.0 ? 1.0 : 0.0;
}

void main() {
  vec2 p = (gl_FragCoord.xy - 0.5 * u_resolution) / u_resolution.y;
  vec3 ro = vec3(0.0, 0.0, -3.0);
  vec3 rd = normalize(vec3(p, 1.5));
  vec3 sky = mix(vec3(0.9, 0.85, 0.8), vec3(0.4, 0.6, 0.9), p.y + 0.5);

  // March from 1.5 to 4.5 units, which covers the whole ball.
  const int STEPS = 48;
  float dt = 3.0 / float(STEPS);
  float transmit = 1.0;
  for (int i = 0; i < STEPS; i++) {
    vec3 pos = ro + rd * (1.5 + (float(i) + 0.5) * dt);
    transmit *= exp(-density(pos) * u_density * dt);
  }

  fragColor = vec4(sky * transmit, 1.0);
}
```

The ball darkens the sky behind it, most in the middle, where the path through it is longest. At the edge the path is short, so most light gets through. This is a ball of soot, which blocks light but sends none of its own.

Unlike a march to a surface, this march takes even steps, because a volume has no distance to jump by. Every ray that crosses it takes all 48 steps.

## Light inside the volume

Real cloud is white because its drops scatter sunlight in every direction, and some of it toward the eye. Each step of the march adds that light.

How much sunlight reaches a point depends on how much cloud lies between it and the sun. So each step marches a second, shorter ray toward the sun and adds up the density along it.

Per step, three things happen:

1. Measure the cloud between this point and the sun. The sunlight reaching the point is `exp(-depth)`.
2. Work out the share of light this step's slice blocks: `1.0 - exp(-density * dt)`. The same share of the light at the point turns toward the eye.
3. Add that light, weakened by everything in front of the slice, and pass on what the slice lets through.

```glsl
uniform float u_density; // @range 0.5 8 @default 4
uniform float u_sunAngle; // @range 0 6.2831853 @default 3.6
uniform float u_forward; // @range 0 0.9 @default 0.6

float hash3(vec3 p) {
  p = fract(p * 0.1031);
  p += dot(p, p.zyx + 31.32);
  return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
  vec3 i = floor(p);
  vec3 f = fract(p);
  vec3 u = f * f * (3.0 - 2.0 * f);
  vec2 e = vec2(1.0, 0.0);
  float a = mix(hash3(i), hash3(i + e.xyy), u.x);
  float b = mix(hash3(i + e.yxy), hash3(i + e.xxy), u.x);
  float c = mix(hash3(i + e.yyx), hash3(i + e.xyx), u.x);
  float d = mix(hash3(i + e.yxx), hash3(i + e.xxx), u.x);
  return mix(mix(a, b, u.y), mix(c, d, u.y), u.z);
}

float fbm3(vec3 p) {
  float sum = 0.0;
  float amplitude = 0.5;
  for (int i = 0; i < 4; i++) {
    sum += amplitude * noise3(p);
    p = p * 2.03 + vec3(0.0, 0.0, 1.7);
    amplitude *= 0.5;
  }
  return sum / 0.9375;
}

// A ball of cloud, its edge frayed by noise.
float density(vec3 p) {
  float n = fbm3(p * 1.8 + vec3(0.0, 0.0, u_time * 0.1));
  float ball = 1.0 - length(p) / 1.3;
  return clamp(ball + (n - 0.5) * 1.2, 0.0, 1.0) * u_density;
}

// How much light scatters toward the eye, by the angle between the eye and the sun.
float phase(float c, float g) {
  float g2 = g * g;
  return (1.0 - g2) / pow(1.0 + g2 - 2.0 * g * c, 1.5);
}

void main() {
  vec2 p = (gl_FragCoord.xy - 0.5 * u_resolution) / u_resolution.y;
  vec3 ro = vec3(0.0, 0.0, -5.0);
  vec3 rd = normalize(vec3(p, 1.5));
  vec3 sunDir = normalize(vec3(cos(u_sunAngle), 0.5, sin(u_sunAngle)));
  vec3 sunColor = vec3(1.0, 0.9, 0.75) * 3.0;
  vec3 skyColor = vec3(0.25, 0.4, 0.75);

  vec3 background = mix(vec3(0.5, 0.6, 0.75), skyColor, p.y + 0.5);
  background += sunColor * smoothstep(0.9990, 0.9995, dot(rd, sunDir));

  const int STEPS = 48;
  float dt = 4.0 / float(STEPS);
  // Most light goes on forward, and a little comes back. Real clouds do both.
  float c = dot(rd, sunDir);
  float ph = mix(phase(c, u_forward), phase(c, -0.2), 0.4);
  vec3 light = vec3(0.0);
  float transmit = 1.0;
  for (int i = 0; i < STEPS; i++) {
    vec3 pos = ro + rd * (3.0 + (float(i) + 0.5) * dt);
    float d = density(pos);
    if (d > 0.001) {
      // 1. The cloud between this point and the sun.
      float depth = 0.0;
      for (int j = 0; j < 6; j++) {
        depth += density(pos + sunDir * (float(j) + 0.5) * 0.25) * 0.25;
      }
      vec3 lit = sunColor * exp(-depth) * ph + skyColor * 0.4;
      // 2. The share of light this slice blocks, and sends toward the eye.
      float block = 1.0 - exp(-d * dt);
      // 3. Add its light, dimmed by the cloud in front, then pass on what gets through.
      light += transmit * lit * block;
      transmit *= 1.0 - block;
    }
  }

  vec3 color = background * transmit + light;
  color = 1.0 - exp(-color * 1.2);
  color = pow(color, vec3(1.0 / 2.2));
  fragColor = vec4(color, 1.0);
}
```

The puff is bright on the sun's side and grey on the far side, because sunlight must cross more cloud to get there. Thin edges stay pale, since light passes through them easily. Turn `u_sunAngle` to about 1.6, which puts the sun behind the cloud, and its edges light up.

## Silver linings

That glowing edge is the silver lining. Water drops send most of the light they scatter onward, close to the direction it was already going. So a cloud seen against the sun glows at its thin edges, and one seen with the sun behind the eye looks flatter.

The `phase` function sets how much light turns toward the eye at each angle. This one is the Henyey–Greenstein function, which [Physically Based Rendering](https://www.pbr-book.org/4ed/Volume_Scattering/Phase_Functions) explains. Its `g`, set by `u_forward`, says how much light keeps going forward: 0 sends it every way equally, and 0.9 sends nearly all of it onward.

Real clouds also send a little light back the way it came, because light bounces around inside them many times. So the shader mixes in a second, weaker phase with `g` at -0.2. Without it, a cloud lit from behind the eye looks grey and thin.

## A layer of clouds

The sky's clouds sit in a layer, between a base height and a top height. A ray from the ground enters the layer at the base and leaves at the top, so the march only covers that stretch. The density comes from 3D fractal noise, thinned out by a coverage value, as the 2D clouds in [Randomness and noise](noise.md#clouds-in-2d) were.

Three more things make the layer look right:

- **A height profile.** Real clouds have flat bases and rounded tops. Multiplying the density by a curve over the layer's height gives that: it climbs fast from the base and fades toward the top.
- **Fading with distance.** Near the horizon a ray crosses miles of cloud. Fading far clouds into the sky hides that, as haze does.
- **A random start.** Even steps leave visible bands where each step lands. Starting each pixel's march a random part of a step later turns the bands into fine grain, which the eye ignores.

```glsl
uniform float u_cover; // @range 0 1 @default 0.45
uniform float u_sun; // @range 0.05 1.5 @default 0.5
uniform float u_jitter; // @range 0 1 @step 1 @default 1

const float BASE = 12.0;
const float TOP = 22.0;

float hash(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

float hash3(vec3 p) {
  p = fract(p * 0.1031);
  p += dot(p, p.zyx + 31.32);
  return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
  vec3 i = floor(p);
  vec3 f = fract(p);
  vec3 u = f * f * (3.0 - 2.0 * f);
  vec2 e = vec2(1.0, 0.0);
  float a = mix(hash3(i), hash3(i + e.xyy), u.x);
  float b = mix(hash3(i + e.yxy), hash3(i + e.xxy), u.x);
  float c = mix(hash3(i + e.yyx), hash3(i + e.xyx), u.x);
  float d = mix(hash3(i + e.yxx), hash3(i + e.xxx), u.x);
  return mix(mix(a, b, u.y), mix(c, d, u.y), u.z);
}

float fbm3(vec3 p, int octaves) {
  float sum = 0.0;
  float amplitude = 0.5;
  float total = 0.0;
  for (int i = 0; i < 5; i++) {
    if (i >= octaves) break;
    sum += amplitude * noise3(p);
    total += amplitude;
    p = p * 2.03 + vec3(0.0, 0.0, 1.7);
    amplitude *= 0.5;
  }
  return sum / total;
}

float cloudDensity(vec3 p, int octaves) {
  float h = (p.y - BASE) / (TOP - BASE);
  if (h < 0.0 || h > 1.0) return 0.0;
  float profile = smoothstep(0.0, 0.1, h) * smoothstep(1.0, 0.35, h);
  float n = fbm3(p * 0.07 + vec3(u_time * 0.03, 0.0, 0.0), octaves);
  float bar = mix(0.62, 0.2, u_cover);
  return clamp((n - bar) * profile * 3.0, 0.0, 1.0);
}

float phase(float c, float g) {
  float g2 = g * g;
  return (1.0 - g2) / pow(1.0 + g2 - 2.0 * g * c, 1.5);
}

void main() {
  vec2 p = (gl_FragCoord.xy - 0.5 * u_resolution) / u_resolution.y;
  vec3 ro = vec3(0.0, 1.5, 0.0);
  vec3 rd = normalize(vec3(p.x, p.y + 0.25, 1.3));
  vec3 sunDir = normalize(vec3(-0.5 * cos(u_sun), sin(u_sun), 0.8));
  // A low sun is redder, as in the lighting chapter.
  vec3 sunColor = mix(vec3(1.0, 0.45, 0.2), vec3(1.0, 0.92, 0.8), smoothstep(0.0, 0.5, sunDir.y)) * 2.2;
  vec3 zenith = vec3(0.02, 0.09, 0.45);

  vec3 sky = mix(vec3(0.3, 0.48, 0.8), zenith, pow(max(rd.y, 0.0), 0.5));
  sky += sunColor * smoothstep(0.9994, 0.9997, dot(rd, sunDir)) * 3.0;
  vec3 color = sky;

  if (rd.y > 0.01) {
    float t0 = (BASE - ro.y) / rd.y;
    float t1 = min((TOP - ro.y) / rd.y, t0 + 40.0);
    const int STEPS = 40;
    float dt = (t1 - t0) / float(STEPS);
    float t = t0 + dt * hash(gl_FragCoord.xy) * u_jitter;
    float c = dot(rd, sunDir);
    float ph = mix(phase(c, 0.6), phase(c, -0.2), 0.4);
    vec3 light = vec3(0.0);
    float transmit = 1.0;
    for (int i = 0; i < STEPS; i++) {
      vec3 pos = ro + rd * t;
      float d = cloudDensity(pos, 4);
      if (d > 0.002) {
        float depth = 0.0;
        for (int j = 0; j < 3; j++) {
          float dist = 0.8 + 2.5 * float(j * j);
          depth += cloudDensity(pos + sunDir * dist, 2) * (1.0 + 2.0 * float(j));
        }
        float h = (pos.y - BASE) / (TOP - BASE);
        vec3 lit = sunColor * exp(-depth * 0.6) * ph + zenith * mix(0.2, 0.8, h);
        float block = 1.0 - exp(-d * dt * 0.6);
        light += transmit * lit * block;
        transmit *= 1.0 - block;
        if (transmit < 0.01) break;
      }
      t += dt;
    }
    // Far clouds fade into the haze near the horizon.
    float far = exp(-t0 * 0.007);
    color = sky * mix(1.0, transmit, far) + light * far;
  } else if (rd.y < 0.0) {
    color = vec3(0.03, 0.05, 0.02);
  }

  color = 1.0 - exp(-color * 1.3);
  color = pow(color, vec3(1.0 / 2.2));
  fragColor = vec4(color, 1.0);
}
```

Slide `u_cover` from 0 to 1 to go from a clear sky to a full one. Lower `u_sun` toward the horizon and the cloud bases darken while their sunward edges glow. Set `u_jitter` to 0 to see the bands that the random start hides.

In `cloudDensity`, `bar` is the coverage: the noise must rise above it to make cloud. `profile` shapes the layer from base to top. `* 0.07` sets the size of the clouds, and the time term blows them along.

## Keeping volumes fast

Volumes are the slowest thing in this course. Each pixel of cloud takes 40 steps, each step reads four octaves of 3D noise, and each step also marches three steps toward the sun. That is hundreds of noise lookups for one pixel.

These keep the cost down:

- **Fewer octaves toward the sun.** The light march only needs the cloud's rough shape, so it reads two octaves, not four.
- **Stop when it is opaque.** Once `transmit` is below 0.01, nothing further back can show. `break` saves the rest of the steps.
- **Skip empty space.** `if (d > 0.002)` skips the light march where there is no cloud.
- **Only march where clouds can be.** Rays that point at the ground never enter the layer.

The Preview's `0.5` scale button helps most of all, since it marches a quarter of the rays.

These go further into clouds:

- Sebastian Lague's video [Coding Adventure: Clouds](https://www.youtube.com/watch?v=4QOcCGI6xOU) builds a cloud renderer from the start.
- Andrew Schneider's talk on [the clouds of Horizon Zero Dawn](https://www.guerrilla-games.com/read/the-real-time-volumetric-cloudscapes-of-horizon-zero-dawn) shows how a game does it at full quality.
- Inigo Quilez's [Clouds](https://www.shadertoy.com/view/XslGRr) is a complete cloud shader to read.
- Scratchapixel's [introduction to volume rendering](https://www.scratchapixel.com/lessons/3d-basic-rendering/volume-rendering-for-developers/intro-volume-rendering.html) covers the maths in full.

## Try this

- In the cloud puff, raise the light march from 6 steps to 12, and see whether the picture changes. Then try 2.
- Swap the ball in the puff for two balls joined with `min`, and watch light pass between them.
- In the cloud layer, make the clouds thicker in the distance than overhead, as weather fronts are. Raise `u_cover` with `t0`.
- Give the cloud layer's ambient light the colour of the sky at sunset when `u_sun` is low.

Next: [A weather system](weather.md).
