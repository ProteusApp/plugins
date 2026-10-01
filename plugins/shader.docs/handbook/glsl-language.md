---
title: 2. The GLSL language
section: Learning shaders
order: 302
keywords: glsl language syntax types float int bool vec2 vec3 vec4 mat2 swizzle functions loops if uniform slider range default color step const built-in functions
---

# 2. The GLSL language

GLSL, the OpenGL Shading Language, is the language of the shaders on these pages. It looks like C, with numbers, `if`, `for` and functions, plus types for vectors and a large set of maths functions built in.

This chapter covers the parts the course uses. The full language is in the [GLSL ES 3.00 specification](https://registry.khronos.org/OpenGL/specs/es/3.0/GLSL_ES_Specification_3.00.pdf), which is long but fine for looking up a single question.

## Types

Every value has a type, and GLSL never changes one type into another by itself.

| Type | What it holds | Example |
|------|---------------|---------|
| `float` | A decimal number. | `0.5`, `1.0`, `-3.25` |
| `int` | A whole number. | `0`, `7`, `-2` |
| `bool` | `true` or `false`. | `d < 0.3` |
| `vec2` | Two floats, such as a position. | `vec2(0.5, 0.25)` |
| `vec3` | Three floats, such as a colour or a point in 3D. | `vec3(1.0, 0.8, 0.2)` |
| `vec4` | Four floats, such as a colour with alpha. | `vec4(color, 1.0)` |
| `mat2` | A 2 by 2 grid of floats, used to turn 2D points. | `mat2(c, s, -s, c)` |
| `mat3` | A 3 by 3 grid of floats, used to turn 3D points. | `mat3(right, up, forward)` |

To change a type, write the type as if it were a function: `float(i)` turns the `int` `i` into a `float`. Mixing types without this is the most common error in GLSL:

| Code | What happens |
|------|--------------|
| `float x = 1;` | An error. `1` is an `int`. Write `1.0`. |
| `float x = 2.0 * i;` | An error when `i` is an `int`. Write `2.0 * float(i)`. |
| `vec3 c = vec4(1.0);` | An error. A `vec4` does not fit in a `vec3`. Write `vec4(1.0).rgb`. |

## Making vectors

Build a vector from any mix of numbers and smaller vectors, as long as the count adds up:

- `vec3(0.5)` sets all three parts to 0.5, which makes a mid grey.
- `vec3(p, 0.0)` takes the two parts of the `vec2` `p` and adds a third.
- `vec4(color, 1.0)` adds alpha to a colour.

## Swizzles

The parts of a vector are named `x`, `y`, `z` and `w`. For a colour, they can also be called `r`, `g`, `b` and `a`, which read better and mean the same. Picking parts by name is called a swizzle:

- `p.x` is the first part.
- `color.rgb` is the first three parts of a `vec4`, as a `vec3`.
- `p.yx` swaps the parts of a `vec2`.
- `c.xxx` repeats one part three times.
- `p.xy = vec2(0.0);` writes two parts at once.

Swizzles cost nothing, so shaders use them everywhere.

## Maths on vectors

Arithmetic on vectors works part by part. `vec2(1.0, 2.0) + vec2(3.0, 4.0)` is `vec2(4.0, 6.0)`, and `vec3(1.0, 0.5, 0.0) * 0.5` halves every part. A colour multiplied by a colour is how light tints a surface, as in [Light, shadow and fog](lighting.md).

Most built-in functions work part by part too. `floor(vec2(1.5, 2.7))` is `vec2(1.0, 2.0)`. These are the ones the course uses most. [Shaping values](shaping.md) draws the ones that shape numbers:

| Function | What it gives |
|----------|---------------|
| `abs(x)` | `x` without its sign. |
| `floor(x)`, `ceil(x)` | `x` rounded down or up. |
| `fract(x)` | The part of `x` after the point, from 0 up to 1. |
| `mod(x, y)` | What is left after dividing `x` by `y`. |
| `min(a, b)`, `max(a, b)` | The smaller or larger of two values. |
| `clamp(x, lo, hi)` | `x`, kept between `lo` and `hi`. |
| `mix(a, b, t)` | A blend from `a` to `b` as `t` goes from 0 to 1. |
| `step(edge, x)` | 0 below `edge`, 1 above it. |
| `smoothstep(e0, e1, x)` | A smooth climb from 0 to 1 as `x` goes from `e0` to `e1`. |
| `sin(x)`, `cos(x)` | Waves between -1 and 1. `x` is in radians, so one full wave is 6.2831853. |
| `atan(y, x)` | The angle of a direction, from -3.14159 to 3.14159. |
| `pow(x, y)`, `exp(x)`, `sqrt(x)` | Powers, `e` to a power, and square roots. |
| `length(v)` | How long a vector is. |
| `distance(a, b)` | The distance between two points. |
| `dot(a, b)` | How much two directions agree: 1 for the same direction, 0 at right angles, -1 for opposite. Those readings hold when both have a length of 1. |
| `cross(a, b)` | A direction at right angles to both of two 3D directions. |
| `normalize(v)` | `v` scaled to a length of 1, keeping its direction. |
| `reflect(d, n)` | The direction `d` takes after it bounces off a surface facing `n`. |

## Functions

A function starts with the type of value it gives back, then lists its inputs with their types. It must be written above the code that calls it.

```glsl
float circle(vec2 p, vec2 center, float radius) {
  return length(p - center) < radius ? 1.0 : 0.0;
}

void main() {
  vec2 p = (gl_FragCoord.xy - 0.5 * u_resolution) / u_resolution.y;
  vec3 color = vec3(0.05, 0.05, 0.1);
  color += circle(p, vec2(-0.3, 0.0), 0.2) * vec3(1.0, 0.3, 0.2);
  color += circle(p, vec2(0.3, 0.0), 0.2) * vec3(0.2, 0.5, 1.0);
  fragColor = vec4(color, 1.0);
}
```

`a ? b : c` picks `b` when `a` is true and `c` otherwise. Here it turns "inside or not" into a number that can multiply a colour, so each circle adds its colour only inside itself.

An input marked `out` is a second way to hand a value back, and `inout` is both read and written. GLSL has no recursion, so a function cannot call itself.

## `if` and loops

`if` and `else` work as in C. So does `for`, which this shader uses to draw six circles turning around the middle:

```glsl
float circle(vec2 p, vec2 center, float radius) {
  return length(p - center) < radius ? 1.0 : 0.0;
}

void main() {
  vec2 p = (gl_FragCoord.xy - 0.5 * u_resolution) / u_resolution.y;
  vec3 color = vec3(0.05, 0.05, 0.1);
  for (int i = 0; i < 6; i++) {
    float angle = float(i) / 6.0 * 6.2831853 + u_time;
    vec2 center = 0.3 * vec2(cos(angle), sin(angle));
    color += circle(p, center, 0.06) * vec3(1.0, 0.6, 0.2);
  }
  fragColor = vec4(color, 1.0);
}
```

`cos(angle)` and `sin(angle)` give a point on a circle of radius 1, for any angle. Scaling it by 0.3 and stepping the angle round puts the six circles in a ring. This pair of functions comes back in every chapter that turns or orbits anything.

A loop runs once for every pixel, so a loop of 100 steps does 100 times the work across the whole picture. `break` leaves a loop early, which [3D with ray marching](raymarching.md) relies on to stay fast.

## Constants and arrays

`const float PI = 3.14159265;` names a value that never changes. An array holds a fixed number of values of one type:

```glsl
const vec3 COLORS[3] = vec3[3](
  vec3(1.0, 0.3, 0.2),
  vec3(0.3, 0.9, 0.4),
  vec3(0.2, 0.5, 1.0)
);

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  int band = int(uv.x * 3.0);
  fragColor = vec4(COLORS[min(band, 2)], 1.0);
}
```

## Uniforms and sliders

A uniform is a value handed to the shader from outside, the same for every pixel. `u_time` and `u_resolution` are uniforms the Preview sets. A uniform the shader declares itself gets a control in the Preview panel, and a note in its comment shapes the control:

```glsl
uniform float u_speed; // @range 0 4 @default 1
uniform float u_rings; // @range 1 20 @step 1 @default 8
uniform vec3 u_tint; // @color @default 0.3 0.6 1.0

void main() {
  vec2 p = (gl_FragCoord.xy - 0.5 * u_resolution) / u_resolution.y;
  float wave = 0.5 + 0.5 * sin(length(p) * u_rings * 6.2831853 - u_time * u_speed * 3.0);
  fragColor = vec4(u_tint * wave, 1.0);
}
```

| Note | What it does |
|------|--------------|
| `@range 0 4` | The slider runs from 0 to 4. Without it, the range is 0 to 1. |
| `@min 0`, `@max 4` | Set one end of the range. |
| `@step 1` | The slider moves in steps of this size. |
| `@default 1` | The starting value. A `vec3` takes three numbers, such as `@default 0.3 0.6 1.0`. |
| `@color` | Shows a colour picker for a `vec3` or `vec4`. |

A control can be a `float`, `int`, `bool`, `vec2`, `vec3` or `vec4`. Moving it changes the picture at once, without compiling again, and the Shader Builder remembers the value for that file. The course gives every number worth tuning a slider like this, because it is the fastest way to learn what a number does.

## What GLSL does not have

GLSL has no strings, no printing and no way to stop and look at a value. A shader shows what it knows through colour, and [When a shader goes wrong](debugging.md) shows how.

A shader also has no memory between frames and no way to read another pixel's result. Everything must come from the pixel's position, the time and the uniforms.

## Try this

- In the slider shader, replace `length(p)` with `p.x`, then with `abs(p.x) + abs(p.y)`. Each one is a different measure of distance, and each draws a different shape.
- Change the loop to draw twelve circles, each one a different colour. Make the colour from `float(i)`.
- Add a `uniform float u_radius; // @range 0.01 0.2` and use it for the circles' size.

Next: [When a shader goes wrong](debugging.md).
