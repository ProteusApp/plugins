---
title: 4. Shaping values
section: Learning shaders
order: 304
keywords: shaping functions step smoothstep mix clamp fract mod abs sin pow exp remap plot graph curve easing pulse glow falloff
---

# 4. Shaping values

Most of the work in a shader is turning one number into another. A distance becomes a soft edge, a time becomes a pulse, and a height becomes a colour. A handful of functions do nearly all of it, and this chapter draws each one so its shape can be seen.

## A function plotter

This shader draws the graph of a function `f`. Across the picture, `x` runs from 0 to 1. The green line is `f(x)`, and the background shows the same value as grey.

```glsl
float f(float x) {
  return x;
}

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  float y = f(uv.x);
  vec3 color = vec3(y);
  // The line is bright where the pixel's height is close to f(x).
  float line = smoothstep(0.01, 0.0, abs(uv.y - y));
  color = mix(color, vec3(0.2, 1.0, 0.4), line);
  fragColor = vec4(color, 1.0);
}
```

Keep it open in its own tab. Each section below gives a line to put in place of `return x;`, and the graph shows what the function does. The idea comes from the [shaping functions chapter](https://thebookofshaders.com/05/) of The Book of Shaders, which has more of them.

## `step`: a hard switch

`return step(0.5, x);` is 0 while `x` is below 0.5, and 1 from there on. It is the shader's way of saying "is `x` past this point?", without an `if`. `step(a, x) * (1.0 - step(b, x))` is 1 only between `a` and `b`.

A hard step makes a hard edge, one pixel wide. On a moving picture that edge shimmers, so most shaders use `smoothstep` instead.

## `smoothstep`: a soft switch

`return smoothstep(0.3, 0.7, x);` is 0 below 0.3 and 1 above 0.7. Between the two it climbs in a smooth S shape, gently at both ends. This one function draws soft edges, fades and blends across most of the course.

Swapping the two edges turns it around. `smoothstep(0.7, 0.3, x)` falls from 1 to 0, which is the same as `1.0 - smoothstep(0.3, 0.7, x)`. The plotter's own line uses this: `smoothstep(0.01, 0.0, d)` is 1 when `d` is 0 and fades to 0 by the time `d` reaches 0.01.

Two of them make a bump. `return smoothstep(0.2, 0.4, x) - smoothstep(0.6, 0.8, x);` rises, holds and falls.

## `mix`, `clamp` and changing a range

`mix(a, b, t)` blends from `a` to `b`. It works on numbers, but most often on colours. `return mix(0.2, 0.8, x);` draws a straight line from 0.2 up to 0.8.

Going the other way, from a range back to 0 to 1, takes a subtraction and a division. It comes up often enough to get a function of its own:

```glsl
// Where x sits between a and b: 0 at a, 1 at b, and beyond them past either end.
float remap(float x, float a, float b) {
  return (x - a) / (b - a);
}
```

`clamp(x, 0.0, 1.0)` keeps the result inside 0 to 1. `clamp(remap(x, 0.25, 0.75), 0.0, 1.0)` is a straight-line version of `smoothstep`.

## `fract` and `mod`: repeating

`return fract(x * 4.0);` climbs from 0 to 1 four times, dropping back each time, like the teeth of a saw. `fract` keeps the part of a number after the point, so it repeats once for every whole number. [Moving space](space.md#repeating) uses this to repeat a pattern across the picture.

`mod(x, y)` repeats every `y` rather than every 1. `fract(x)` is the same as `mod(x, 1.0)`.

`return abs(fract(x * 4.0) * 2.0 - 1.0);` folds each tooth in half, which makes a zigzag that rises and falls with no jump.

## `sin` and `cos`: waves

`return 0.5 + 0.5 * sin(x * 6.2831853 * 3.0);` makes three smooth waves. `sin` swings between -1 and 1, so halving it and adding 0.5 moves it to 0 to 1. A full wave takes 6.2831853, which is two times pi, so multiplying `x` by that makes one wave across the picture.

Add `u_time` inside to make the wave travel: `return 0.5 + 0.5 * sin(x * 20.0 - u_time * 3.0);`. Subtracting the time moves it to the right, and adding moves it to the left.

## `pow`, `sqrt` and `exp`: curves

- `return pow(x, 3.0);` starts flat and rises late. It suits a fade that should hold off, then arrive.
- `return sqrt(x);` rises early and levels off.
- `return exp(-x * 6.0);` starts at 1 and falls away fast, then slowly, never quite reaching 0.

The `exp` curve is how light and fog fade with distance. The glow around anything bright fades the same way. [Light, shadow and fog](lighting.md#fog) and [Clouds and other volumes](volumes.md) both run on it.

## Making a pulse

Functions combine. `fract` makes time repeat, and a falling curve makes each repeat a beat:

`return exp(-fract(x * 3.0 - u_time) * 5.0);`

That line makes three sharp flashes that fade, sliding across the plot. In time alone, `exp(-fract(u_time) * 5.0)` flashes once a second. Lightning in [A weather system](weather.md#lightning) starts from this.

## A glowing sun

This shader shapes three values for one picture. `smoothstep` gives the sun a soft edge, `exp` gives it a glow, and `mix` lays both over a sky that `pow` bends toward the horizon.

```glsl
uniform float u_glow; // @range 1 40 @default 12
uniform float u_size; // @range 0.02 0.3 @default 0.08

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  vec2 p = (gl_FragCoord.xy - 0.5 * u_resolution) / u_resolution.y;

  // The sky: pow keeps the warm colour low, near the horizon.
  vec3 color = mix(vec3(1.0, 0.55, 0.3), vec3(0.15, 0.3, 0.7), pow(uv.y, 0.6));

  vec2 sun = vec2(0.25, 0.05 + 0.05 * sin(u_time * 0.5));
  float d = length(p - sun);

  // The glow falls away with distance. The disc gets a soft edge a few pixels wide.
  float glow = exp(-d * u_glow);
  float disc = smoothstep(u_size + 0.004, u_size - 0.004, d);

  color += vec3(1.0, 0.7, 0.4) * glow * 0.6;
  color = mix(color, vec3(1.0, 0.95, 0.8), disc);

  fragColor = vec4(color, 1.0);
}
```

Drag the sliders. A high `u_glow` makes a tight glow, as in clear air. A low one spreads it wide, as in haze, which is a first hint of how weather changes a sky.

## Try this

- Plot `smoothstep(0.0, 1.0, x)` and `x * x * (3.0 - 2.0 * x)`. They are the same curve, which is how `smoothstep` works inside.
- Plot a heartbeat: two pulses close together, then a pause. Add two `exp` curves with different offsets.
- In the sun shader, make the glow pulse slowly with `u_time`.
- Read Inigo Quilez's [useful little functions](https://iquilezles.org/articles/functions/) and plot three of them.

Next: [Moving space](space.md).
