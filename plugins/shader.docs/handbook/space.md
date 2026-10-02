---
title: 5. Moving space
section: Learning shaders
order: 305
keywords: coordinates space translate move scale zoom rotate turn rotation matrix repeat tile grid cell fract floor mirror symmetry polar angle radius atan warp distort wave
---

# 5. Moving space

A shader cannot pick up a shape and move it. It can only change the coordinates each pixel measures from. To move a circle right, every pixel moves its own position left before asking "am I inside?".

This chapter covers moving, scaling, turning and repeating, which all work that way.

## Move, turn and zoom

This shader draws one square, and three sliders change the coordinates it is drawn in:

```glsl
uniform vec2 u_offset; // @range -0.5 0.5 @default 0 0
uniform float u_angle; // @range 0 6.2831853 @default 0
uniform float u_zoom; // @range 0.25 4 @default 1

// Turns a point around 0 by an angle, in radians.
vec2 rotate(vec2 p, float a) {
  float c = cos(a);
  float s = sin(a);
  return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// 1 inside a square of the given half width around 0, and 0 outside it.
float square(vec2 p, float size) {
  vec2 d = abs(p);
  return max(d.x, d.y) < size ? 1.0 : 0.0;
}

void main() {
  vec2 p = (gl_FragCoord.xy - 0.5 * u_resolution) / u_resolution.y;
  vec2 q = p - u_offset;
  q = rotate(q, -u_angle);
  q = q / u_zoom;
  vec3 color = mix(vec3(0.1, 0.12, 0.18), vec3(0.95, 0.6, 0.25), square(q, 0.15));
  fragColor = vec4(color, 1.0);
}
```

Each line works backward from what it seems to do:

- `p - u_offset` moves the square by `u_offset`. A pixel at the square's new centre now measures 0, which is where the square sits.
- `rotate(q, -u_angle)` turns the square by `u_angle`. Turning the coordinates one way turns the picture the other way, so the angle is negated.
- `q / u_zoom` makes the square bigger. Dividing shrinks the coordinates, so the square's fixed size covers more of the picture.

The order matters too. Here the move comes first, so the square turns around its own centre. Swap the first two lines, and it swings around the middle of the picture instead.

`rotate` uses the same `cos` and `sin` as the ring of circles in [The GLSL language](glsl-language.md#if-and-loops). GLSL can also turn a point with a `mat2`, a small grid of numbers, and many shaders online write it as `mat2(c, s, -s, c) * p`. The result is the same.

## Repeating

`fract` repeats a number every 1. Applied to coordinates, it repeats the whole picture, so one shape becomes a grid of them. `floor` says which copy a pixel is in.

```glsl
vec2 rotate(vec2 p, float a) {
  float c = cos(a);
  float s = sin(a);
  return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float square(vec2 p, float size) {
  vec2 d = abs(p);
  return max(d.x, d.y) < size ? 1.0 : 0.0;
}

void main() {
  vec2 p = (gl_FragCoord.xy - 0.5 * u_resolution) / u_resolution.y;
  vec2 grid = p * 5.0;
  // Which cell the pixel is in, as whole numbers, and where it is inside that cell.
  vec2 cell = floor(grid);
  vec2 q = fract(grid) - 0.5;
  // Each cell turns at its own offset, so a wave runs across the grid.
  q = rotate(q, u_time + (cell.x + cell.y) * 0.5);
  vec3 tint = 0.5 + 0.5 * cos(vec3(0.0, 2.0, 4.0) + cell.x * 0.7 + cell.y);
  vec3 color = mix(vec3(0.08, 0.1, 0.15), tint, square(q, 0.25));
  fragColor = vec4(color, 1.0);
}
```

Multiplying by 5 makes five cells for each unit of `p`, so about five rows fit in the picture. `fract(grid) - 0.5` runs from -0.5 to 0.5 inside every cell, so each one has its own centre at 0. The shape is drawn once, in those coordinates, and appears in every cell.

`cell` is the same for every pixel in a cell and different from cell to cell. That makes it the way to vary the copies, and here it changes their turn and colour. [Randomness and noise](noise.md#a-random-number-for-each-cell) turns it into a random number, which is how rain and snow scatter drops in [A weather system](weather.md#rain).

## Mirrors

`abs` folds space in half. After `p.x = abs(p.x);` the left half of the picture is a copy of the right, so anything drawn once on the right appears twice.

Folding both `x` and `y` makes four copies. Faces, butterflies and snowflakes all start this way.

## Angles and rings

Any point can be described by its distance from the middle and the angle it lies at, instead of by `x` and `y`. These are called polar coordinates. `length(p)` gives the distance, and `atan(p.y, p.x)` the angle.

```glsl
void main() {
  vec2 p = (gl_FragCoord.xy - 0.5 * u_resolution) / u_resolution.y;
  float r = length(p);
  float a = atan(p.y, p.x);
  // cos repeats once per turn of the angle, so cos(a * 12.0) makes twelve rays.
  float rays = 0.5 + 0.5 * cos(a * 12.0 + u_time * 0.5);
  rays *= exp(-r * 3.0);
  float disc = smoothstep(0.155, 0.145, r);
  vec3 color = vec3(0.1, 0.2, 0.45) + vec3(1.0, 0.8, 0.4) * rays * 0.6;
  color = mix(color, vec3(1.0, 0.95, 0.8), disc);
  fragColor = vec4(color, 1.0);
}
```

Anything that repeats around a centre is easier this way: rays, petals, clock faces and spirals. A spiral is `cos(a * 3.0 + r * 20.0)`, because the angle moves on as the distance grows.

## Bending space

Space can be bent as well as moved. Adding a wave to `x` that depends on `y` makes each row slide by a different amount, so straight lines sway:

```glsl
uniform float u_bend; // @range 0 0.1 @default 0.04

void main() {
  vec2 p = (gl_FragCoord.xy - 0.5 * u_resolution) / u_resolution.y;
  p.x += u_bend * sin(p.y * 10.0 + u_time * 2.0);
  // A zigzag of fract, made sharp by smoothstep, draws soft stripes.
  float zig = abs(fract(p.x * 6.0) * 2.0 - 1.0);
  float stripes = smoothstep(0.45, 0.55, zig);
  vec3 color = mix(vec3(0.15, 0.3, 0.2), vec3(0.6, 0.85, 0.4), stripes);
  fragColor = vec4(color, 1.0);
}
```

This is how grass sways, flags wave and hot air shimmers. A plain slant, `p.x += p.y * 0.3`, tilts the picture as wind tilts falling rain. When the bend comes from noise rather than a wave, it is called domain warping, and [Randomness and noise](noise.md#warping) uses it for smoke and marble.

## Try this

- In the first shader, swap the move and the turn, and watch the square orbit.
- Make the grid of squares into a checkerboard. Use `mod(cell.x + cell.y, 2.0)` to pick one of two colours.
- Draw a flower: a circle whose radius is `0.2 + 0.05 * cos(a * 5.0)`.
- Fold the grid with `abs` before tiling, and see how the pattern changes.

Next: [Shapes from distance](shapes.md).
