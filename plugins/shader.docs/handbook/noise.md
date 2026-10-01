---
title: 8. Randomness and noise
section: Learning shaders
order: 308
keywords: random hash noise value noise gradient noise perlin fbm fractal brownian motion octaves lacunarity gain domain warping voronoi worley cells stars 3d noise clouds texture procedural
---

# 8. Randomness and noise

Clouds, smoke, terrain, water and rain all have a rough, random look that changes slowly from place to place. Shaders make it from noise, which is randomness smoothed out. This chapter builds noise from scratch, then layers it into the fractal noise behind every cloud in the course.

## Random numbers

GLSL has no random number function. A shader makes its own with a hash: a function that scrambles its input so thoroughly that the output looks random. The same input always gives the same output, so every pixel gets the same "random" value for a place, and it stays put from frame to frame.

This hash is from Dave Hoskins's [Hash without Sine](https://www.shadertoy.com/view/4djSRW), which gives the same results on every graphics card:

```glsl
// A random number from 0 to 1 for any 2D point.
float hash(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

void main() {
  // Ten new pictures of static every second.
  float frame = floor(u_time * 10.0);
  float v = hash(gl_FragCoord.xy + frame * 17.0);
  fragColor = vec4(vec3(v), 1.0);
}
```

Many shaders online use `fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453)` instead. It is shorter, but `sin` of a large number gives different answers on different graphics cards, and it shows patterns once the inputs grow. The hash above avoids both.

## A random number for each cell

Hashing every pixel gives static. Hashing the cell from [Moving space](space.md#repeating) gives one random number per cell, the same for every pixel in it. That is how to scatter things: put one in each cell, at a random place in the cell, with a random size.

```glsl
float hash(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// Two random numbers from 0 to 1 for any 2D point.
vec2 hash2(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
}

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  vec2 p = (gl_FragCoord.xy - 0.5 * u_resolution) / u_resolution.y;
  vec3 color = mix(vec3(0.0, 0.01, 0.04), vec3(0.02, 0.05, 0.15), uv.y);

  vec2 grid = p * 14.0;
  vec2 cell = floor(grid);
  // A random place for the star, kept away from the cell's sides.
  vec2 star = 0.15 + 0.7 * hash2(cell);
  float d = length(fract(grid) - star);
  // pow makes most stars faint and a few bright.
  float brightness = pow(hash(cell + 7.0), 6.0);
  // Each star twinkles at its own speed.
  float twinkle = 0.7 + 0.3 * sin(u_time * (1.0 + 4.0 * hash(cell + 3.0)) + 6.28 * hash(cell));
  color += vec3(1.0, 0.95, 0.85) * brightness * twinkle * exp(-d * 40.0) * 2.0;

  fragColor = vec4(color, 1.0);
}
```

Adding a number such as `7.0` to `cell` before hashing gives a second, unrelated random number for the same cell. The weather sky uses these stars at night.

## Value noise

Random numbers jump from cell to cell. Noise is smooth. Value noise gives each corner of the grid a random number, then blends between the four corners around a pixel:

```glsl
float hash(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// Smooth noise from 0 to 1, changing about once per unit.
float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  // smoothstep's curve, so the blend has no corners.
  vec2 u = f * f * (3.0 - 2.0 * f);
  float a = hash(i);
  float b = hash(i + vec2(1.0, 0.0));
  float c = hash(i + vec2(0.0, 1.0));
  float d = hash(i + vec2(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void main() {
  vec2 p = gl_FragCoord.xy / u_resolution.y * 8.0;
  float v = noise(p + vec2(u_time, 0.0));
  fragColor = vec4(vec3(v), 1.0);
}
```

`i` is the cell and `f` is the place inside it. The two inner `mix` calls blend along the bottom and top edges of the cell, and the outer one blends between those. Scaling `p` sets the size of the blobs: multiply by 8 and there are 8 per unit.

Gradient noise, also called Perlin noise after its inventor, gives each corner a random direction rather than a random value, and it looks less blocky. The **Gradient Noise** node in the node editor is one, and [the Book of Shaders chapter on noise](https://thebookofshaders.com/11/) explains both kinds. Value noise is enough for everything in this course.

## Fractal noise

One layer of noise looks like soft blobs. Real clouds have big shapes, smaller shapes on those, and smaller ones again.

Fractal noise adds layers of noise together, each one finer and fainter than the last. Each layer is called an octave. The result is often written fbm, for fractal Brownian motion.

```glsl
uniform float u_octaves; // @range 1 8 @step 1 @default 5
uniform float u_gain; // @range 0.2 0.8 @default 0.5

float hash(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  float a = hash(i);
  float b = hash(i + vec2(1.0, 0.0));
  float c = hash(i + vec2(0.0, 1.0));
  float d = hash(i + vec2(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
  float sum = 0.0;
  float amplitude = 0.5;
  float total = 0.0;
  for (int i = 0; i < 8; i++) {
    if (float(i) >= u_octaves) break;
    sum += amplitude * noise(p);
    total += amplitude;
    // Each octave is twice as fine, turned a little so the grids do not line up.
    p = mat2(1.6, 1.2, -1.2, 1.6) * p;
    amplitude *= u_gain;
  }
  return sum / total;
}

void main() {
  vec2 p = gl_FragCoord.xy / u_resolution.y * 3.0;
  float v = fbm(p + vec2(u_time * 0.2, 0.0));
  fragColor = vec4(vec3(v), 1.0);
}
```

Slide `u_octaves` from 1 up. Each octave adds finer detail at half the size of the last. By octave 8 the new detail is only a pixel or two across, even on a large preview.

`u_gain` sets how strong each octave is against the last. Low gain gives smooth, rolling shapes, and high gain gives rough, rocky ones.

The matrix `mat2(1.6, 1.2, -1.2, 1.6)` doubles the scale and turns it by about 37 degrees in one step. Dividing by `total` keeps the result between 0 and 1 for any number of octaves. Inigo Quilez's article on [fbm](https://iquilezles.org/articles/fbm/) goes into why these numbers work.

## Warping

[Moving space](space.md#bending-space) bent coordinates with a wave. Bending them with noise instead makes swirls, like smoke, marble or ink in water. Feeding fractal noise into its own input is called domain warping:

```glsl
float hash(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  float a = hash(i);
  float b = hash(i + vec2(1.0, 0.0));
  float c = hash(i + vec2(0.0, 1.0));
  float d = hash(i + vec2(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
  float sum = 0.0;
  float amplitude = 0.5;
  for (int i = 0; i < 5; i++) {
    sum += amplitude * noise(p);
    p = mat2(1.6, 1.2, -1.2, 1.6) * p;
    amplitude *= 0.5;
  }
  return sum / 0.96875;
}

void main() {
  vec2 p = gl_FragCoord.xy / u_resolution.y * 3.0;
  // Two fbm values make a direction to push p by. Then that is done again.
  vec2 q = vec2(fbm(p), fbm(p + vec2(5.2, 1.3)));
  vec2 r = vec2(fbm(p + 4.0 * q + vec2(1.7, 9.2) + 0.15 * u_time),
                fbm(p + 4.0 * q + vec2(8.3, 2.8) + 0.12 * u_time));
  float v = fbm(p + 4.0 * r);
  vec3 color = mix(vec3(0.1, 0.2, 0.3), vec3(0.9, 0.8, 0.6), v);
  color = mix(color, vec3(0.6, 0.2, 0.1), length(q) * 0.5);
  fragColor = vec4(color, 1.0);
}
```

This is Inigo Quilez's [domain warping](https://iquilezles.org/articles/warp/), and the article shows where it leads. The weather's storm clouds use a light touch of it, so they boil rather than drift.

## Cells

Voronoi noise, also called cell noise or Worley noise, scatters one point per cell and measures the distance to the nearest point. Each pixel checks its own cell and the eight around it, since the nearest point can be in a neighbour.

```glsl
vec2 hash2(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
}

float voronoi(vec2 p) {
  vec2 cell = floor(p);
  vec2 local = fract(p);
  float nearest = 8.0;
  for (int y = -1; y <= 1; y++) {
    for (int x = -1; x <= 1; x++) {
      vec2 offset = vec2(float(x), float(y));
      vec2 h = hash2(cell + offset);
      // Each point wanders around its cell.
      vec2 point = offset + 0.5 + 0.4 * sin(u_time + 6.2831 * h);
      nearest = min(nearest, length(point - local));
    }
  }
  return nearest;
}

void main() {
  vec2 p = gl_FragCoord.xy / u_resolution.y * 6.0;
  float d = voronoi(p);
  fragColor = vec4(vec3(d), 1.0);
}
```

The picture looks like cells under a microscope, or light rippling on the floor of a pool. Cell noise makes cracked mud, scales, stone walls and the round puddles on the weather's wet ground. The `cells` graph in `shaders/` builds it from the **Voronoi** node.

## Noise in 3D

The same blend works in 3D, over the eight corners of a cube. Clouds in [Clouds and other volumes](volumes.md) need it, since they fill space rather than a flat picture. It has a second use in 2D: using time as the third coordinate makes a 2D pattern change shape over time, rather than slide.

```glsl
// A random number from 0 to 1 for any 3D point.
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

void main() {
  vec2 p = gl_FragCoord.xy / u_resolution.y * 6.0;
  // The pattern stays in place and changes shape, because time moves through the third axis.
  float v = noise3(vec3(p, u_time * 0.5));
  fragColor = vec4(vec3(v), 1.0);
}
```

`e.xyy` is `vec2(1.0, 0.0).xyy`, which is `vec3(1.0, 0.0, 0.0)`. Swizzling one small vector is a short way to write the eight corners of the cube.

## Clouds in 2D

This shader turns fractal noise into a sky of clouds. Three sliders set how much of the sky they cover, how fast the wind blows them, and how dark they are. The light comes from noise too: a point is in shadow when the cloud is thicker a little way toward the sun.

```glsl
uniform float u_cover; // @range 0 1 @default 0.5
uniform float u_wind; // @range 0 1 @default 0.15
uniform float u_dark; // @range 0 1 @default 0.2

float hash(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  float a = hash(i);
  float b = hash(i + vec2(1.0, 0.0));
  float c = hash(i + vec2(0.0, 1.0));
  float d = hash(i + vec2(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
  float sum = 0.0;
  float amplitude = 0.5;
  for (int i = 0; i < 6; i++) {
    sum += amplitude * noise(p);
    p = mat2(1.6, 1.2, -1.2, 1.6) * p;
    amplitude *= 0.5;
  }
  return sum / 0.984375;
}

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  // Stretching y makes the clouds wider than they are tall.
  vec2 p = gl_FragCoord.xy / u_resolution.y * vec2(2.0, 3.5) + vec2(u_time * u_wind, 0.0);

  vec3 sky = mix(vec3(0.6, 0.75, 0.95), vec3(0.2, 0.4, 0.8), uv.y);
  float n = fbm(p);
  // More cover lowers the bar the noise has to clear.
  float edge = mix(0.75, 0.3, u_cover);
  float c = smoothstep(edge, edge + 0.3, n);
  // Compare with the noise a little toward the sun, up and to the right.
  // Where the cloud thins toward the sun, light gets in, so the point is lit.
  float toward = fbm(p + vec2(0.05, 0.08));
  float shade = clamp(0.65 + (n - toward) * 5.0, 0.0, 1.0);
  vec3 lit = mix(vec3(0.95, 0.97, 1.0), vec3(0.35, 0.38, 0.45), u_dark);
  vec3 cloudColor = lit * mix(0.55, 1.05, shade);

  vec3 color = mix(sky, cloudColor, c);
  fragColor = vec4(color, 1.0);
}
```

Raise `u_cover` and `u_dark` together, and a fine day turns overcast and grey. That pairing, one dial moving many values at once, is the main idea of [A weather system](weather.md#the-weather-dial).

These clouds are flat, though. Sunlight cannot shine through them or glow at their edges. The next three chapters build up to clouds with real depth.

## Try this

- Make the static from the first example move like old film: only part of each frame changes.
- Give each star a random colour, from blue-white to orange.
- Warp the 2D clouds a little: add `0.3 * vec2(fbm(p + 3.0), fbm(p + 7.0))` to `p` before the cloud lookup.
- Use the 3D noise for the 2D clouds, with `u_time * 0.05` as the third coordinate, so they change shape as they drift.

Next: [3D with ray marching](raymarching.md).
