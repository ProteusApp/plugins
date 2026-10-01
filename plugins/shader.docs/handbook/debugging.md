---
title: 3. When a shader goes wrong
section: Learning shaders
order: 303
keywords: debug debugging error compile error message black screen nan infinity show value colour visualise performance fps slow fast cost loops scale
---

# 3. When a shader goes wrong

A shader cannot print a value, so finding a problem works differently. Compile errors come with a line number, but everything else is found by turning values into colours and looking at them. This chapter covers both, and how to tell why a shader runs slowly.

## Reading an error

The Shader Builder underlines the line with the error and shows the compiler's message. The Preview lists the same messages under the picture, and keeps showing the last version that worked. The messages come from the graphics driver, so their wording is terse, but a few cover most mistakes:

| The message says | What it usually means |
|------------------|-----------------------|
| `cannot convert from 'const int' to 'highp float'` | A whole number such as `1` where a decimal such as `1.0` belongs. |
| `wrong operand types` | Arithmetic between two types that do not mix, such as a `float` times an `int`, or a `vec2` plus a `vec3`. |
| `undeclared identifier` | A name that is misspelled, or used above the line that declares it. |
| `no matching overloaded function found` | A function called with the wrong types or the wrong number of inputs. |
| `not enough data provided for construction` | A vector made from too few numbers, such as `vec3(1.0, 0.5)`. |
| `dimension mismatch` | A vector stored in a variable of another size. |
| `syntax error` | Often a missing `;` at the end of the line before the one named. |

Fix the first error first. One mistake often causes several messages, and the rest can disappear with it.

## Showing a value as colour

The way to look inside a shader is to send a value to the screen. A number from 0 to 1 shows as grey, from black to white:

```glsl
void main() {
  vec2 p = (gl_FragCoord.xy - 0.5 * u_resolution) / u_resolution.y;
  float d = length(p);
  fragColor = vec4(vec3(d), 1.0);
}
```

The middle is black, where the distance is 0, and it brightens outward. The corners are nearly white, because the distance there is close to 1, and the screen cuts every colour off at 1. A value below 0 shows as black too, so a grey picture cannot tell -5 from 0, or 1 from 50.

This function shows any value. Positive values are orange and negative ones blue. Faint bands mark every 0.1, and the line where the value is 0 shows white:

```glsl
vec3 showValue(float v) {
  vec3 color = v > 0.0 ? vec3(0.9, 0.6, 0.3) : vec3(0.4, 0.7, 0.9);
  color *= 0.8 + 0.2 * cos(v * 62.83);
  color = mix(color, vec3(1.0), 1.0 - smoothstep(0.0, 0.01, abs(v)));
  return color;
}

void main() {
  vec2 p = (gl_FragCoord.xy - 0.5 * u_resolution) / u_resolution.y;
  float d = length(p) - 0.3;
  fragColor = vec4(showValue(d), 1.0);
}
```

`length(p) - 0.3` is negative inside a circle of radius 0.3 and positive outside it, so the white line is the circle's edge. [Shapes from distance](shapes.md) builds whole pictures from values like this. Copy `showValue` into any shader that misbehaves, and look at its values one at a time.

## Looking at one step at a time

Most shaders build a picture in steps. To see one step on its own, write it to `fragColor` and `return` straight after. Nothing below the `return` runs.

```glsl
void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  float sky = smoothstep(0.3, 1.0, uv.y);

  // Look at the sky value alone. Delete these two lines to see the whole picture.
  fragColor = vec4(vec3(sky), 1.0);
  return;

  vec3 color = mix(vec3(1.0, 0.7, 0.4), vec3(0.2, 0.4, 0.9), sky);
  fragColor = vec4(color, 1.0);
}
```

Move the two lines down the shader, step by step, until the picture stops looking right. The step above them is the one at fault.

## Values that are not numbers

Some maths has no answer: the square root of a negative number, 0 divided by 0, or `normalize` of a vector with no length. The result is a value called NaN, short for "not a number". Anything it touches becomes NaN too, and the pixel usually shows black.

A division by 0 gives infinity instead, which is as hard to see. `isnan` and `isinf` find them. This shader paints them magenta, so they stand out:

```glsl
void main() {
  vec2 p = (gl_FragCoord.xy - 0.5 * u_resolution) / u_resolution.y;
  // sqrt of a negative number has no answer, so the left half goes wrong.
  float v = sqrt(p.x) * 0.5;
  vec3 color = vec3(v);
  if (isnan(v) || isinf(v)) {
    color = vec3(1.0, 0.0, 1.0);
  }
  fragColor = vec4(color, 1.0);
}
```

The fixes are small:

- Clamp before a square root with `sqrt(max(x, 0.0))`.
- Divide by `max(x, 0.0001)` rather than `x`.
- Use `pow` only on numbers above 0.

## Other common surprises

- **The picture is upside down.** `gl_FragCoord.y` counts up from the bottom, not down from the top as image files do.
- **The picture is stretched.** The code uses `uv`, whose steps differ in `x` and `y`. Divide by `u_resolution.y` as in [A first shader](first-shader.md#a-circle).
- **Colours look washed out or too dark.** The maths was done in amounts of light, and the screen needs a gamma step. [Colour](colour.md#gamma) explains it.
- **Edges flicker and shimmer when they move.** The edge is a hard step across one pixel. [Shapes from distance](shapes.md#soft-edges) shows how to soften it.
- **Noise shows lines or blocks after a while.** Large numbers such as a big `u_time` lose precision. Wrap the time with `mod(u_time, 1000.0)`, or keep the inputs to noise small.

## Keeping it fast

The Preview shows frames per second above the picture. At 60 the shader keeps up with the screen. Below 30 it starts to feel slow.

The cost of a shader is the work done for one pixel, times the number of pixels. A large preview has millions of pixels, so a little work per pixel adds up. These cost the most:

| What | Why it costs |
|------|--------------|
| Loops | Each step repeats all the work inside it. Ray marching and clouds loop hundreds of times. |
| Loops inside loops | The counts multiply. A light step inside a cloud step is the usual case. |
| Noise | Each layer of fractal noise is a full noise lookup. Five layers cost five times one. |
| Heavy functions | `pow`, `exp`, `sin` and division cost more than `+` and `*`, but far less than a loop. |

To make a shader faster:

- Use the `0.5` scale button while working. It draws a quarter of the pixels.
- Lower loop counts and noise layers until the picture changes, then put one back.
- `break` out of a loop as soon as its answer is known.
- Skip work a pixel does not need. A pixel of sky has no ground to light.

[The Book of Shaders](https://thebookofshaders.com/) runs every example in the browser beside its code. It is a good place to see these ideas at work in someone else's shader.

## Try this

- Paste `showValue` into the sunset from [A first shader](first-shader.md#a-sunset) and use it to look at `p.y`, then `length(p - sun)`.
- Break a working shader on purpose: drop a `;`, write `1` for `1.0`, call `mix` with two inputs. Read each message.
- Note the frames per second of the slider shader in [The GLSL language](glsl-language.md#uniforms-and-sliders). Then put its wave calculation inside a loop of 200 steps, and watch the frames per second fall.

Next: [Shaping values](shaping.md).
